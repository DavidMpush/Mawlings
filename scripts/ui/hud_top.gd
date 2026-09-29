extends Control

# Stage 04 · HUD_TOP. Replaces legacy "top" and "badges" of touch_controls.gd:
# top bar (swarm, run time + danger, DNA/level, pause), context chips, boss bar,
# Alpha-Kern chip and attack-form medallions (Etappe 16: no corpse/biomass hints,
# the loot crystals fly in by themselves).
# Reads every value from the parent (touch_controls.gd); input stays there.
# Shared icon/frame kits are used as soon as they exist; until then (or for ids
# they do not provide) the local fallbacks below draw the same shapes.

#
# Stage 07 (performance): the picture is split into UiLayer children, one per
# section, each repainted only when the values it shows change; static sections
# are baked into one texture each. Pulses that only fade or grow (Alpha-Kern
# gem, danger skull) animate the layer's modulate/scale instead of repainting.
# The section painters draw on `_cv`; `_paint` names the part being painted
# (layout runs with `_paint == ""` and draws nothing).

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const UiLayer := preload("res://scripts/ui/ui_layer.gd")
const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")
const ICONS_PATH := "res://scripts/ui/ui_icons.gd"
const FRAMES_PATH := "res://scripts/ui/ui_frames.gd"
const MAX_POPULATION := 250
const TOP := 18.0
const BAR_H := 100.0
const ROW_H := 40.0
const GAP := 10.0
const LABEL := 22       # stage 06: smallest HUD text (900 grid)
# Threat chips repeat the in-world creature colours (no palette token exists).
const HUNTER_COLOR := UiStyle.VIOLET
const SKITTER_COLOR := Color("e46ad0")
const LEAPER_COLOR := Color("5fc9c0")

var _icons: Script
var _frames: Script
var _lib_timer := 0.0

var _last_pop := -1
var _pop_delta := 0
var _pop_pulse := 0.0
var _last_level := -1
var _level_pulse := 0.0
var _time := 0.0

var _cv: CanvasItem = self
var _paint := ""
var _layers: Dictionary = {}
# Layout of the last frame (computed without drawing).
var _row_y := 0.0
var _pressure_rect := Rect2()
var _right_y := 0.0
var _boss_y := -1.0
var _skull_c := Vector2.ZERO
var _gem_c := Vector2.INF
var _bar_rects: Array = [Rect2(), Rect2(), Rect2(), Rect2()]   # swarm, time, dna, pause
var _chips_bottom := 0.0
# Etappe 09: loss strength of the current counter pulse (share of the swarm lost)
# and the leader marker (crown + hit point pips) above units[0].
var _loss_strength := 0.0
var _swarm_node: Node3D
var _leader := {}
var _leader_screen := Vector2.INF
var _crown_from_screen := Vector2.INF
# Stage 15 (skin brawl): reduced HUD, see the "brawl" section below.
var _brawl := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_libs(0.0)
	_build_layers()


# Skin brawl (stage 15) uses its own reduced set of layers; calm/organic keep
# the stage 04-09 layout. Rebuilt when the skin changes during a run.
func _build_layers() -> void:
	for layer: Control in _layers.values():
		remove_child(layer)
		layer.queue_free()
	_layers.clear()
	_brawl = UiStyle.is_brawl()
	var specs: Array = BRAWL_LAYERS if _brawl else [
		["backdrop", false, Rect2(0, 0, 0, 200)],
		["leader", false, Rect2()],
		["swarm", true, Rect2()],
		["time", true, Rect2()],
		["time_glow", false, Rect2()],
		["time_skull", true, Rect2()],
		["dna", true, Rect2()],
		["pause", true, Rect2()],
		["chips", true, Rect2()],
		["alpha_glow", false, Rect2()],
		["alpha_top", true, Rect2()],
		["boss", true, Rect2()],
		["medals", true, Rect2()],
	]
	# Order = drawing order.
	for spec in specs:
		var part: String = spec[0]
		var layer: Control = UiLayer.make(self, part.capitalize().replace(" ", ""), _painter(part), spec[1], spec[2])
		_layers[part] = layer


func _painter(part: String) -> Callable:
	return func(canvas: CanvasItem) -> void:
		_cv = canvas
		_paint = part
		_paint_part(part)
		_paint = ""
		_cv = self


func _paint_part(part: String) -> void:
	if _brawl:
		_paint_brawl(part)
		return
	match part:
		"backdrop":
			_draw_backdrop()
		"leader":
			_draw_leader()
		"swarm", "time", "time_glow", "time_skull", "dna", "pause":
			_draw_top_bar()
		"chips", "alpha_glow", "alpha_top":
			var pressure_rect := _draw_pressure_chip(_row_y)
			_draw_threat_chips(_row_y, _threat_limit(pressure_rect), _threat_start(pressure_rect))
			_draw_alpha_chip(_row_y, pressure_rect.end.x + GAP)
		"boss":
			if _boss_y >= 0.0:
				_draw_boss_bar_legacy(_boss_y)
		"medals":
			if not bool(_hud_value("extinct", false)):
				_draw_medallions(_right_y + 16.0)


func _process(delta: float) -> void:
	_advance(delta)
	if get_parent() == null:
		return
	if UiStyle.is_brawl() != _brawl:
		_build_layers()
	if _brawl:
		_brawl_context(delta)
		_brawl_layout()
		_brawl_refresh()
		return
	_layout()
	_refresh_layers()


# Same rows as the original single pass; nothing is drawn here.
func _layout() -> void:
	_paint = ""
	_row_y = _draw_top_bar() + 12.0
	_pressure_rect = _draw_pressure_chip(_row_y)
	var left_y := _draw_threat_chips(_row_y, _threat_limit(_pressure_rect), _threat_start(_pressure_rect))
	_right_y = _draw_alpha_chip(_row_y, _pressure_rect.end.x + GAP)
	var y := maxf(left_y, _pressure_rect.end.y + 12.0)
	_chips_bottom = maxf(y, _right_y)
	_boss_y = -1.0
	if float(_hud_value("boss_health", 0.0)) > 0.0:
		_boss_y = y
		_draw_boss_bar_legacy(y)


func _refresh_layers() -> void:
	var fraction := _danger_fraction()
	var danger_q := int(round(fraction * 255.0))
	var hot := smoothstep(0.55, 0.9, fraction)
	var evo := _evolution()
	var pop := int(_hud_value("population", 0))
	# Cache areas: each baked section only needs its own box (glow, shadow and
	# claws reach ~20 px out), not a full-screen texture.
	_region("swarm", _bar_rects[0].grow(26))
	_region("time", _bar_rects[1].grow(26))
	_region("time_skull", Rect2(_skull_c - Vector2(32, 32), Vector2(64, 64)))
	_region("dna", _bar_rects[2].grow(26))
	_region("pause", _bar_rects[3].grow(26))
	_region("chips", Rect2(0, _row_y - 16, size.x, _chips_bottom - _row_y + 32))
	_region("alpha_top", Rect2(size.x * 0.5, _row_y - 16, size.x * 0.5, _chips_bottom - _row_y + 32))
	_region("boss", Rect2(0, _boss_y - 36, size.x, 84 + 72))
	_region("medals", Rect2(size.x - 110, _right_y, 110, maxf(1.0, size.y - _right_y)))
	_layers.backdrop.refresh(size)
	_refresh_leader()
	_layers.swarm.refresh([pop, _pop_delta, _pop_pulse, int(_time * 60.0) if _pop_pulse > 0.0 and _pop_delta < 0 else 0, size])
	_layers.time.refresh([int(float(_hud_value("elapsed", 0.0))), danger_q, size])
	# Danger skull glow: radius and alpha breathe through scale/modulate only.
	var glow: Control = _layers.time_glow
	glow.visible = hot > 0.0
	if glow.visible:
		glow.refresh([_skull_c, size])
		var pulse := hot * (0.5 + 0.5 * sin(_time * 6.0))
		glow.pivot_offset = _skull_c
		glow.scale = Vector2.ONE * (22.0 + 6.0 * pulse) / 22.0
		glow.modulate = Color(1, 1, 1, 0.22 + 0.25 * pulse)
	_layers.time_skull.refresh([danger_q, _skull_c])
	var dna_key: Array = [_level(), _level_pulse, size]
	if evo != null:
		dna_key.append_array([int(evo.get("dna")), int(evo.threshold()), bool(evo.complete())])
	_layers.dna.refresh(dna_key)
	_layers.pause.refresh(_pause_rect())
	_layers.chips.refresh([_pressure_text(), danger_q, _hud_value("hunters", 0), _hud_value("skitters", 0), _hud_value("leapers", 0), _hud_value("alpha_cores", 0), size])
	var cores := int(_hud_value("alpha_cores", 0))
	var gem: Control = _layers.alpha_glow
	gem.visible = cores > 0
	if gem.visible:
		gem.refresh([_gem_c])
		gem.modulate = Color(1, 1, 1, 0.2 + 0.15 * sin(_time * 4.0))
	_layers.alpha_top.visible = cores > 0
	if cores > 0:
		_layers.alpha_top.refresh([cores, _gem_c])
	var boss: Control = _layers.boss
	boss.visible = _boss_y >= 0.0
	if boss.visible:
		var health := clampf(float(_hud_value("boss_health", 0.0)) / maxf(1.0, _hud_value("boss_max_health", 1.0)), 0.0, 1.0)
		var vulnerable: bool = _hud_value("boss_vulnerable", false)
		# Vulnerable: the gold glow and tag blink, repainted at 30 Hz.
		boss.refresh([int(round(health * 2000.0)), vulnerable, int(_time * 30.0) if vulnerable else 0, _boss_y, size])
	var medals: Control = _layers.medals
	medals.visible = not bool(_hud_value("extinct", false))
	if medals.visible:
		medals.refresh([_medal_key(evo), _right_y, size])


func _region(part: String, rect: Rect2) -> void:
	var layer: Control = _layers[part]
	var snapped := Rect2(rect.position.floor(), rect.size.ceil())
	if layer.region != snapped:
		layer.region = snapped
		layer.invalidate()


# Owned attack forms with their ranks (what the medallions show).
func _medal_key(evo: Object) -> Array:
	if evo == null or not evo.has_method("attack_ranks"):
		return []
	var ranks: Dictionary = evo.attack_ranks()
	var key: Array = []
	for group in ["ATTACKS", "EVOLVED"]:
		var entries: Variant = evo.get(group)
		if entries is Array:
			for entry in entries:
				if ranks.has(entry[0]):
					key.append([entry[0], ranks[entry[0]], evo.kind_of(entry[0])])
	return key


func _advance(delta: float) -> void:
	_time += delta
	_refresh_libs(delta)
	var hud := get_parent()
	if hud == null:
		return
	var pop := int(hud.get("population"))
	if _last_pop < 0:
		_last_pop = pop
	elif pop != _last_pop:
		var change := pop - _last_pop
		# Consecutive changes in the same direction add up while the pulse lasts.
		if _pop_pulse > 0.05 and signi(change) == signi(_pop_delta):
			_pop_delta += change
		else:
			_pop_delta = change
			_loss_strength = 0.0
		if change < 0:
			# Share of the swarm lost: 1 of 3 flashes hard, 1 of 200 barely.
			var share := float(-change) / float(maxi(1, _last_pop))
			share = maxf(share, float(_hud_value("last_loss_fraction", 0.0)))
			_loss_strength = clampf(maxf(_loss_strength, 0.25 + sqrt(share) * 1.2), 0.0, 1.0)
		_pop_pulse = 1.0
		_last_pop = pop
	_pop_pulse = maxf(0.0, _pop_pulse - delta * 1.1)
	var level := _level()
	if _last_level < 0:
		_last_level = level
	elif level != _last_level:
		_level_pulse = 1.0
		_last_level = level
	_level_pulse = maxf(0.0, _level_pulse - delta * 1.2)


func _refresh_libs(delta: float) -> void:
	_lib_timer -= delta
	if _lib_timer > 0.0 or (_icons != null and _frames != null):
		return
	_lib_timer = 1.0
	if _icons == null:
		_icons = _try_load(ICONS_PATH)
	if _frames == null:
		_frames = _try_load(FRAMES_PATH)


func _try_load(path: String) -> Script:
	if not ResourceLoader.exists(path):
		return null
	var script: Script = load(path)
	return script if script != null and script.can_instantiate() else null


# ---------------------------------------------------------------- data

func _hud_value(key: String, fallback: Variant) -> Variant:
	var hud := get_parent()
	if hud == null:
		return fallback
	var value: Variant = hud.get(key)
	# Stage 09 values may arrive as meta when the HUD has no such property.
	if value == null and hud.has_meta(key):
		value = hud.get_meta(key)
	return fallback if value == null else value


func _evolution() -> Object:
	return _hud_value("evolution", null)


func _level() -> int:
	var evo := _evolution()
	return 0 if evo == null else int(evo.get("level"))


func _pause_rect() -> Rect2:
	var hud := get_parent()
	if hud != null and hud.has_method("_pause_rect"):
		return hud._pause_rect()
	return Rect2(Vector2(size.x - 98, TOP), Vector2(82, BAR_H))


func _danger_fraction() -> float:
	var pressure: float = _hud_value("pressure", 1.0)
	return clampf(log(maxf(1.0, pressure)) / log(256.0), 0.0, 1.0)


func _pressure_text() -> String:
	var pressure: float = _hud_value("pressure", 1.0)
	return ("DRUCK ×%.1f" % pressure) if pressure < 10.0 else ("DRUCK ×%d" % int(pressure))


func _danger_color() -> Color:
	return UiStyle.color("amber").lerp(UiStyle.color("danger"), _danger_fraction())


# ---------------------------------------------------------------- drawing

func _draw_backdrop() -> void:
	# Soft dark falloff behind the top bar so it reads over bright ground.
	var h := 190.0
	var top := Color(UiStyle.color("outline"), 0.62)
	var bottom := Color(UiStyle.color("outline"), 0.0)
	_cv.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, h), Vector2(0, h)]), PackedColorArray([top, top, bottom, bottom]))


# Returns the bottom edge of the bar.
func _draw_top_bar() -> float:
	var pause := _pause_rect()
	var swarm_rect := Rect2(16, TOP, 272, BAR_H)
	var dna_w := 178.0
	var dna_rect := Rect2(pause.position.x - 12 - dna_w, TOP, dna_w, BAR_H)
	var time_rect := Rect2(swarm_rect.end.x + 12, TOP, dna_rect.position.x - 12 - (swarm_rect.end.x + 12), BAR_H)
	_skull_c = Vector2(time_rect.end.x - 32, time_rect.position.y + 70 + 9 - 2)
	_bar_rects = [swarm_rect, time_rect, dna_rect, pause]
	match _paint:
		"swarm":
			_draw_swarm(swarm_rect)
		"time", "time_glow", "time_skull":
			_draw_time(time_rect)
		"dna":
			_draw_dna(dna_rect)
		"pause":
			_draw_pause(pause)
	return TOP + BAR_H


func _draw_swarm(rect: Rect2) -> void:
	var pop := int(_hud_value("population", 0))
	var gain := _pop_delta >= 0
	var pulse_color := UiStyle.color("toxic") if gain else UiStyle.color("danger")
	var accent := UiStyle.color("ember").lerp(pulse_color, _pop_pulse * 0.8)
	var hurt := 0.0 if gain else _loss_strength * _pop_pulse
	if hurt > 0.0:
		_panel_glow(rect, UiStyle.color("danger"), 0.55 * hurt)
	_panel(rect, accent, 16.0, false)
	var head_c := rect.position + Vector2(52, 52)
	if _pop_pulse > 0.0 and not UiStyle.is_calm():
		_cv.draw_circle(head_c, 40 + 8 * _pop_pulse + 10 * hurt, Color(pulse_color, 0.25 * _pop_pulse + 0.2 * hurt))
	var head_ids := ["v2_population"] if UiStyle.is_calm() else [_strain_head(), "mawling_head_color", "mawling_head"]
	var head_r := 34.0 if UiStyle.is_calm() else 40.0
	if not _icon(head_ids, Rect2(head_c - Vector2(head_r, head_r), Vector2(head_r, head_r) * 2.0), Color.WHITE):
		_fb_head(head_c, 36, UiStyle.color("ember"))
	var x := rect.position.x + 102
	_label("SCHWARM", Vector2(x, rect.position.y + 28), UiStyle.color("text_dim") if UiStyle.is_calm() else UiStyle.color("ember_glow"))
	# Big number grows and tints on change, then settles back.
	var num_size := roundf(54 + 8 * _ease(_pop_pulse))
	var num_color := Color.WHITE.lerp(pulse_color.lightened(0.25), _pop_pulse)
	# Growth: the number hops once; loss: it shakes, harder for a bigger share.
	var at := Vector2(x - 2, rect.position.y + 84)
	if gain and _pop_pulse > 0.0:
		at.y -= 12.0 * sin(PI * clampf((1.0 - _pop_pulse) * 3.0, 0.0, 1.0))
	elif hurt > 0.0:
		at.x += sin(_time * 70.0) * 7.0 * hurt
	var w := UiStyle.text_px(_cv, "%d" % pop, at, num_size, num_color, false, 9)
	UiStyle.text(_cv, "/ %d" % MAX_POPULATION, Vector2(x + w + 6, rect.position.y + 82), LABEL, UiStyle.color("text_dim"), false, 5, UiStyle.body_font())
	# Floating delta ("+7" / "−12") rises out of the number.
	if _pop_pulse > 0.0 and _pop_delta != 0:
		var rise := (1.0 - _pop_pulse) * 12.0
		if gain:
			rise += 10.0 * sin(PI * clampf((1.0 - _pop_pulse) * 4.0, 0.0, 1.0))
		var sign_text := "+" if gain else "−"
		UiStyle.text(_cv, "%s%d" % [sign_text, absi(_pop_delta)], Vector2(rect.end.x - 30, rect.position.y + 44 - rise), UiStyle.SIZE_BODY, Color(pulse_color.lightened(0.2), minf(1.0, _pop_pulse * 1.6)), true, 6)
	# Population fill along the lower rim.
	var fill := clampf(float(pop) / MAX_POPULATION, 0.0, 1.0)
	_bar(Rect2(x, rect.end.y - 10, rect.end.x - x - 16, 6), fill, UiStyle.color("ember"))


func _draw_time(rect: Rect2) -> void:
	var fraction := _danger_fraction()
	var color := _danger_color()
	var hot := smoothstep(0.55, 0.9, fraction)
	var bar := Rect2(rect.position.x + 18, rect.position.y + 70, rect.size.x - 78, 18)
	var skull_c := Vector2(rect.end.x - 32, bar.get_center().y - 2)
	if _paint == "time":
		_panel(rect, UiStyle.color("panel_edge").lerp(color, 0.35 + 0.65 * fraction), 18.0, false)
		var elapsed: float = _hud_value("elapsed", 0.0)
		var cx := rect.get_center().x
		UiStyle.text(_cv, "%02d:%02d" % [int(elapsed) / 60, int(elapsed) % 60], Vector2(cx, rect.position.y + 58), 50, UiStyle.color("text"), true, 8)
		# Danger bar in segments, skull at the end. Calm: one kit track with the
		# threat fill (progress_track + progress_fill_threat look).
		if UiStyle.is_calm():
			_bar(bar.grow_individual(0, -2, 0, -2), maxf(0.05, fraction), color)
		else:
			_segments(bar, maxf(0.05, fraction), color, 10)
	elif _paint == "time_glow":
		# Drawn at rest size and full alpha; the layer's scale/modulate breathe it
		# (radius 22 + 6 * pulse, alpha 0.22 + 0.25 * pulse).
		if hot > 0.0:
			_cv.draw_circle(skull_c, 18 if UiStyle.is_calm() else 22, UiStyle.color("danger"))
	elif _paint == "time_skull":
		if UiStyle.is_calm() and _icon(["v2_threat"], Rect2(skull_c - Vector2(21, 21), Vector2(42, 42)), Color.WHITE):
			return
		if not _icon(["pressure", "skull"], Rect2(skull_c - Vector2(24, 24), Vector2(48, 48)), Color.WHITE.lerp(UiStyle.color("amber"), 0.5 * (1.0 - fraction))):
			_fb_skull(skull_c, 17, color)


func _draw_dna(rect: Rect2) -> void:
	var evo := _evolution()
	var level := _level()
	var dna := 0 if evo == null else int(evo.get("dna"))
	var needed := 20 if evo == null else int(evo.threshold())
	var maxed := evo != null and bool(evo.complete())
	_panel(rect, UiStyle.color("cyan").lerp(Color.WHITE, _level_pulse * 0.5), 16.0, false)
	var helix_c := rect.position + Vector2(30, 50)
	if _level_pulse > 0.0 and not UiStyle.is_calm():
		_cv.draw_circle(helix_c, 30 + 10 * _level_pulse, Color(UiStyle.color("cyan"), 0.3 * _level_pulse))
	if not _icon(["dna"], Rect2(helix_c - Vector2(34, 34), Vector2(68, 68)), Color.WHITE):
		_fb_helix(helix_c, 62, UiStyle.color("cyan"))
	var x := rect.position.x + 60
	var lv_size := roundf(38 + 8 * _ease(_level_pulse))
	UiStyle.text_px(_cv, "LV %d" % level, Vector2(x, rect.position.y + 48), lv_size, Color.WHITE.lerp(UiStyle.color("cyan").lightened(0.4), _level_pulse), false, 8)
	_bar(Rect2(x, rect.position.y + 58, rect.end.x - x - 14, 12), 1.0 if maxed else clampf(float(dna) / maxf(1.0, needed), 0.0, 1.0), UiStyle.color("cyan"))
	var dna_text := "MAX" if maxed else "%d/%d DNA" % [dna, needed]
	if _text_width(dna_text, LABEL) > rect.end.x - x - 8.0:
		dna_text = "%d/%d" % [dna, needed]
	UiStyle.text(_cv, dna_text, Vector2(x, rect.position.y + 92), LABEL, UiStyle.color("cyan").lightened(0.45), false, 5, UiStyle.body_font())


func _draw_pause(rect: Rect2) -> void:
	if _lib_has(_frames, "button"):
		_frames.call("button", _cv, rect, "secondary", false)
	else:
		_panel(rect, UiStyle.color("bone"), 18.0, false)
	var c := rect.get_center()
	if not _icon(["pause"], Rect2(c - Vector2(30, 30), Vector2(60, 60)), Color.WHITE):
		for dx in [-15.0, 5.0]:
			var bar := Rect2(c + Vector2(dx, -19), Vector2(10, 38))
			_cv.draw_rect(Rect2(bar.position + Vector2(0, 3), bar.size), UiStyle.color("shadow"))
			_cv.draw_rect(bar, UiStyle.color("bone"))
			_cv.draw_rect(Rect2(bar.position, Vector2(4, bar.size.y)), Color(1, 1, 1, 0.35))


# Minimap stage: with the round minimap in the top-left corner the left column
# (chips, boss bar, corpse/biomass hints) starts right of it.
func _left_x() -> float:
	var hud := get_parent()
	if hud != null and bool(hud.get("minimap_enabled")) and hud.has_method("_minimap_rect"):
		return (hud._minimap_rect() as Rect2).end.x + 20.0
	return 16.0


func _inset() -> bool:
	return _left_x() > 16.5


# First threat chip x (after the pressure chip when the minimap takes the corner).
func _threat_start(pressure_rect: Rect2) -> float:
	return pressure_rect.end.x + GAP if _inset() else 16.0


func _threat_limit(pressure_rect: Rect2) -> float:
	if not _inset():
		return pressure_rect.position.x - GAP
	var limit := size.x - 120.0
	var cores := int(_hud_value("alpha_cores", 0))
	if cores > 0:
		limit = minf(limit, size.x - 16.0 - (_text_width("ALPHA-KERN ×%d" % cores, LABEL) + 58.0) - GAP)
	return limit


# Pressure multiplier below the run time; returns its rect.
func _draw_pressure_chip(y: float) -> Rect2:
	var text := _pressure_text()
	var color := _danger_color()
	var w := _text_width(text, LABEL) + 40
	var rect := Rect2(_left_x() if _inset() else size.x * 0.5 - w * 0.5, y, w, ROW_H - 4)
	if _paint != "chips":
		return rect
	var hot := smoothstep(0.55, 0.9, _danger_fraction())
	if hot > 0.0:
		_pill(rect.grow(4), Color(UiStyle.color("danger"), 0.0), Color(UiStyle.color("danger"), hot * (0.2 + 0.15 * sin(_time * 6.0))))
	_pill(rect, color, UiStyle.color("panel_soft").lerp(Color(UiStyle.color("danger"), 0.8), hot * 0.35))
	UiStyle.text(_cv, text, Vector2(rect.get_center().x, rect.position.y + 26), LABEL, color.lerp(Color.WHITE, 0.5 + 0.4 * hot), true, 5, UiStyle.body_font())
	return rect


# Threat chips from the left; wraps below when the row runs out. Returns next y.
func _draw_threat_chips(y: float, right_limit: float, start_x: float = 16.0) -> float:
	var entries := []
	var hunters := int(_hud_value("hunters", 0))
	var skitters := int(_hud_value("skitters", 0))
	var leapers := int(_hud_value("leapers", 0))
	if hunters > 0:
		entries.append(["JÄGER %d" % hunters, HUNTER_COLOR])
	if skitters > 0:
		entries.append(["SKITTER %d" % skitters, SKITTER_COLOR])
	if leapers > 0:
		entries.append(["LEAPER %d" % leapers, LEAPER_COLOR])
	if entries.is_empty():
		return y
	var x := start_x
	var wrap_x := _left_x()
	for entry in entries:
		var w := _text_width(entry[0], LABEL) + 52
		if x > wrap_x + 0.5 and x + w > right_limit:
			x = wrap_x
			y += ROW_H + 4
		var rect := Rect2(x, y, w, ROW_H - 4)
		var accent: Color = entry[1]
		if _paint == "chips":
			_pill(rect, accent)
			_diamond(rect.position + Vector2(21, rect.size.y * 0.5), 9, accent)
			UiStyle.text(_cv, entry[0], rect.position + Vector2(38, 26), LABEL, accent.lerp(Color.WHITE, 0.7), false, 5, UiStyle.body_font())
		x += w + 8
	return y + ROW_H + 4


# Alpha-Kern chip right-aligned; returns the y below the right column's chips.
func _draw_alpha_chip(y: float, left_limit: float) -> float:
	var cores := int(_hud_value("alpha_cores", 0))
	if cores <= 0:
		_gem_c = Vector2.INF
		return y
	var text := "ALPHA-KERN ×%d" % cores
	var w := _text_width(text, LABEL) + 58
	if size.x - 16 - w < left_limit:
		y += ROW_H + 4
	var rect := Rect2(size.x - 16 - w, y, w, ROW_H - 4)
	var gem_c := rect.position + Vector2(24, rect.size.y * 0.5)
	_gem_c = gem_c
	match _paint:
		"chips":
			_pill(rect, UiStyle.color("violet"), Color(UiStyle.color("panel").darkened(0.2), 0.92).lerp(UiStyle.color("violet"), 0.12))
		"alpha_glow":
			# Full alpha here; the layer's modulate pulses it (0.2 + 0.15 * sin).
			_cv.draw_circle(gem_c, 16, UiStyle.color("violet"))
		"alpha_top":
			if not _icon(["alpha_core"], Rect2(gem_c - Vector2(18, 18), Vector2(36, 36)), Color.WHITE):
				_fb_gem(gem_c, 12)
			UiStyle.text(_cv, text, rect.position + Vector2(44, 26), LABEL, UiStyle.color("gold").lightened(0.3), false, 5, UiStyle.body_font())
	return y + ROW_H + 4


# Boss bar of the calm/organic skins: crown medallion, name, segmented health,
# VERWUNDBAR tag. Returns bottom. (Brawl: _draw_boss_bar.)
func _draw_boss_bar_legacy(y: float) -> float:
	var health: float = _hud_value("boss_health", 0.0)
	var max_health: float = maxf(1.0, _hud_value("boss_max_health", 1.0))
	var vulnerable: bool = _hud_value("boss_vulnerable", false)
	var blink := 0.5 + 0.5 * sin(_time * 7.0)
	var accent := UiStyle.color("gold") if vulnerable else UiStyle.color("ember")
	var w := minf(620.0, size.x - 2 * 110.0)
	var rect := Rect2(size.x * 0.5 - w * 0.5, y, w, 84)
	if _inset():
		var avail := size.x - 110.0 - _left_x()
		w = minf(620.0, avail)
		rect = Rect2(_left_x() + (avail - w) * 0.5, y, w, 84)
	if _paint != "boss":
		return rect.end.y
	if vulnerable:
		_panel_glow(rect, UiStyle.color("gold"), 0.25 + 0.25 * blink)
	_panel(rect, accent, 16.0, true, UiStyle.color("panel").lerp(Color(UiStyle.color("danger"), 0.9), 0.12))
	var crown_c := rect.position + Vector2(48, 42)
	if UiStyle.is_calm():
		_plate(crown_c, 31, accent)
	else:
		_cv.draw_circle(crown_c + Vector2(0, 4), 31, UiStyle.color("shadow"))
		_cv.draw_circle(crown_c, 31, UiStyle.color("panel").darkened(0.3))
		_cv.draw_arc(crown_c, 30, 0, TAU, 40, accent, 3.0, true)
	# V2 portrait bust of the Bog King on the plate (crown icon as fallback).
	if not _icon(["portrait_bog_king"], Rect2(crown_c - Vector2(37, 40), Vector2(74, 74)), Color.WHITE) 			and not _icon(["crown"], Rect2(crown_c - Vector2(27, 27), Vector2(54, 54)), Color.WHITE):
		_fb_crown(crown_c, 20, UiStyle.color("gold"))
	var x := rect.position.x + 92
	UiStyle.text(_cv, "BOG KING", Vector2(x, rect.position.y + 36), 30, UiStyle.color("text"), false, 7)
	if vulnerable:
		var tag := "VERWUNDBAR"
		var tw := _text_width(tag, LABEL) + 28
		var tag_rect := Rect2(rect.end.x - 18 - tw, rect.position.y + 10, tw, 32)
		_pill(tag_rect, UiStyle.color("gold"), UiStyle.color("gold").darkened(0.55).lerp(UiStyle.color("gold").darkened(0.3), blink))
		UiStyle.text(_cv, tag, Vector2(tag_rect.get_center().x, tag_rect.position.y + 24), LABEL, Color.WHITE, true, 5, UiStyle.body_font())
	var bar := Rect2(x, rect.position.y + 50, rect.end.x - x - 20, 20)
	_segments(bar, clampf(health / max_health, 0.0, 1.0), UiStyle.color("gold") if vulnerable else UiStyle.color("danger"), 14)
	return rect.end.y


# Owned attack forms as medallions down the right edge.
func _draw_medallions(y: float) -> void:
	var evo := _evolution()
	if evo == null or not evo.has_method("attack_ranks"):
		return
	var hud := get_parent()
	var ranks: Dictionary = evo.attack_ranks()
	var ids := []
	for group in ["ATTACKS", "EVOLVED"]:
		var entries: Variant = evo.get(group)
		if entries is Array:
			for entry in entries:
				if ranks.has(entry[0]):
					ids.append(entry[0])
	var r := 38.0
	var c := Vector2(size.x - 16 - r, y + r)
	for id in ids:
		var evolved: bool = evo.kind_of(id) == "evolved"
		var accent: Color = hud._mutation_color(id) if hud != null and hud.has_method("_mutation_color") else UiStyle.color("ember")
		var ring := UiStyle.color("violet") if evolved else accent
		if UiStyle.is_calm():
			_plate(c, r, UiStyle.tone(ring))
		else:
			_cv.draw_circle(c + Vector2(0, 5), r + 2, UiStyle.color("shadow"))
			_cv.draw_circle(c, r + 6, Color(ring, 0.18))
			_cv.draw_circle(c, r, UiStyle.color("panel").darkened(0.25))
			_cv.draw_circle(c + Vector2(0, -r * 0.35), r * 0.7, Color(1, 1, 1, 0.05))
			_cv.draw_arc(c, r - 1.5, 0, TAU, 44, ring, 4.0, true)
			_cv.draw_arc(c, r - 6, PI * 1.1, PI * 1.6, 12, Color(1, 1, 1, 0.3), 2.0, true)
		if not _icon([id], Rect2(c - Vector2(r, r) * 0.82, Vector2(r, r) * 1.64), Color.WHITE):
			UiStyle.text(_cv, String(id).left(1).to_upper(), c + Vector2(0, 13), 36, accent, true, 6)
		if evolved:
			var gem_c := c + Vector2(-r * 0.78, -r * 0.72)
			if not _icon(["alpha_core"], Rect2(gem_c - Vector2(15, 15), Vector2(30, 30)), Color.WHITE):
				_fb_gem(gem_c, 10)
		else:
			var rank := int(ranks[id])
			for i in 3:
				_diamond(c + Vector2(-16 + i * 16, r + 10), 6.5, UiStyle.tone(accent) if i < rank else Color(UiStyle.color("panel_edge"), 0.9), not UiStyle.is_calm())
		c.y += r * 2 + 30


# ---------------------------------------------------------------- brawl (stage 15)
# Reduced run HUD of the skin brawl: three fixed elements plus pause - swarm
# pill (left), run time with the pressure bar (centre), DNA pill with level
# badge and level bar (right). Everything else is contextual: ONE short line
# under the pressure bar (pressure doubles, hunters arrive) that
# fades out again, the Alpha-Kern pill while cores are stored, the boss bar
# while a boss lives and the attack-form medallions down the right edge.
# Corpse, biomass, pressure and threat chips no longer exist here. Drawn only
# with ui_kit_brawl.gd and UiStyle tokens; the UiLayer caches stay (one layer
# per element, repainted only when its values change).

const BRAWL_LAYERS := [
	["xp", false, Rect2()],
	["leader", false, Rect2()],
	# Etappe 22b: swarm pill and boss bar split into a baked still picture
	# (pill, portrait, panel, name) and the parts that change during a fight
	# (count, LP strip, health bar; the pulse rings behind them).
	["swarm_back", false, Rect2()],
	["swarm", true, Rect2()],
	["swarm_live", true, Rect2()],
	["time_glow", false, Rect2()],
	["time", true, Rect2()],
	["dna", true, Rect2()],
	["alpha", true, Rect2()],
	["pause", true, Rect2()],
	["boss_back", false, Rect2()],
	["boss", true, Rect2()],
	["boss_live", true, Rect2()],
	["context", true, Rect2()],
	["medals", true, Rect2()],
	["boosts", false, Rect2()],
]
const B_TOP := 28.0
const B_PILL_H := 80.0
const B_PLATE := 76.0
const B_TIME_W := 224.0
const B_BAR_H := 26.0
const B_ALPHA_H := 48.0
const BOSS_H := 92.0
const CONTEXT_SECONDS := 2.6
const CONTEXT_H := 50.0
const CONTEXT_QUEUE := 3
const CONTEXT_STALE := 4.0
const MEDAL_SIZE := 64.0
# Etappe 17 Welle 2: relic strip under the weapons, power-up row under the swarm pill.
const RELIC_SIZE := 42.0
const RELIC_GAP := 10.0
const RELIC_COLS := 2
const RELIC_MAX := 8
const BOOST_SIZE := 50.0
const BOOST_GAP := 12.0

var _b_swarm := Rect2()
var _b_time := Rect2()
var _b_bar := Rect2()
var _b_dna := Rect2()
var _b_alpha := Rect2()
var _b_pause_c := Vector2.ZERO
var _b_pause_r := 40.0
var _b_context := Rect2()
var _b_medal_y := 0.0
# Context line: queue of [text, tone, icon id, queued at]; the current entry fades in and
# out through the layer's modulate (no repaint while it shows).
var _ctx_queue: Array = []
var _ctx_current: Array = []
var _ctx_t := -1.0
var _ctx_tier := -1
var _ctx_hunters := -1
var _ctx_surge := false


func _paint_brawl(part: String) -> void:
	match part:
		"leader":
			_draw_leader()
		"swarm", "swarm_back", "swarm_live":
			_b_draw_swarm()
		"time_glow":
			# Full alpha; the layer's modulate breathes it.
			Kit.rrect(_cv, _b_bar.grow(7), _b_bar.size.y * 0.5 + 7, UiStyle.BRAWL_DANGER_FACE)
		"time":
			_b_draw_time()
		"dna":
			_b_draw_amber()
		"xp":
			_b_draw_xp()
		"alpha":
			_b_draw_alpha()
		"pause":
			Kit.round_button(_cv, _b_pause_c, _b_pause_r, "neutral")
			var c := Kit.round_label_center(_b_pause_c, _b_pause_r)
			_icon(["pause"], Rect2(c - Vector2(17, 17), Vector2(34, 34)), Color.WHITE)
		"boss", "boss_back", "boss_live":
			if _boss_y >= 0.0:
				_draw_boss_bar(_boss_y)
		"context":
			_b_draw_context()
		"medals":
			_b_draw_medals()
		"boosts":
			_b_draw_boosts()


func _brawl_layout() -> void:
	var cx := size.x * 0.5
	var pause := _pause_rect()
	_b_pause_c = pause.get_center()
	_b_pause_r = minf(40.0, minf(pause.size.x, pause.size.y) * 0.5)
	_b_time = Rect2(cx - B_TIME_W * 0.5, B_TOP - 4.0, B_TIME_W, B_PILL_H + 8.0)
	_b_bar = Rect2(cx - 96.0, _b_time.end.y + 8.0, 192.0, B_BAR_H)
	_b_swarm = Rect2(16, B_TOP, minf(256.0, _b_time.position.x - 16.0 - 24.0), B_PILL_H)
	var dna_x := _b_time.end.x + 20.0
	_b_dna = Rect2(dna_x, B_TOP, _b_pause_c.x - _b_pause_r - 12.0 - dna_x, B_PILL_H)
	var right_bottom := _b_dna.end.y + 8.0
	_b_alpha = Rect2()
	if int(_hud_value("alpha_cores", 0)) > 0:
		_b_alpha = Rect2(_b_dna.position.x + 8.0, _b_dna.end.y + 14.0, _b_dna.size.x - 8.0, B_ALPHA_H)
		right_bottom = _b_alpha.end.y + 10.0
	var y := _b_bar.end.y + 16.0
	_boss_y = -1.0
	var below := right_bottom
	# Package H: one stack for every living boss (Bog King, apex), then the
	# flood pill (drawn by hud_flood.gd into the slot reserved here).
	_boss_list = _boss_entries()
	if not _boss_list.is_empty():
		# The boss bar spans the width, so it starts below the right column.
		_boss_y = maxf(y, right_bottom)
		y = _draw_boss_bar(_boss_y) + 14.0
		below = y
	y = _flood_layout(y)
	if _flood_slot.size.y > 0.0:
		below = maxf(below, y)
	_stack_bottom = below
	_b_context = Rect2()
	if not _ctx_current.is_empty():
		var w := _b_text_width(String(_ctx_current[0]), UiStyle.T_LABEL) + CONTEXT_H + 40.0
		_b_context = Rect2(cx - w * 0.5, y, w, CONTEXT_H)
	_b_medal_y = below + 16.0


func _brawl_refresh() -> void:
	var fraction := _danger_fraction()
	var danger_q := int(round(fraction * 255.0))
	var hot := smoothstep(0.55, 0.9, fraction)
	var evo := _evolution()
	var pop := int(_hud_value("population", 0))
	var extinct := bool(_hud_value("extinct", false))
	_region("swarm", _b_swarm.grow(24))
	_region("swarm_live", _b_swarm.grow(24))
	_region("time", _b_time.merge(_b_bar).grow(16))
	_region("dna", _b_dna.grow(32))
	var pad := Vector2.ONE * (_b_pause_r + 14.0)
	_region("pause", Rect2(_b_pause_c - pad, pad * 2.0))
	_region("alpha", _b_alpha.grow(24))
	_region("boss", Rect2(0, _boss_y - 24, size.x, _boss_stack_h + 48))
	_region("boss_live", Rect2(0, _boss_y - 24, size.x, _boss_stack_h + 48))
	_region("context", _b_context.grow(20))
	_region("medals", Rect2(size.x - MEDAL_SIZE - 56, _b_medal_y - 12, MEDAL_SIZE + 56, maxf(1.0, size.y - _b_medal_y)))
	_refresh_leader()
	var shaking := _pop_pulse > 0.0 and _pop_delta < 0
	var hurt := _swarm_hurt()
	var swarm_back: Control = _layers.swarm_back
	swarm_back.visible = hurt > 0.0
	if swarm_back.visible:
		swarm_back.refresh([hurt, _b_swarm])
	_layers.swarm.refresh([_b_swarm, _strain_head()])
	_layers.swarm_live.refresh([pop, _pop_delta, _pop_pulse, int(_time * 60.0) if shaking else 0, _b_swarm, _strain_head(), _leader_hp(), _leader_max_hp(), _leader_hp() * 4 < _leader_max_hp()])
	_layers.time.refresh([int(float(_hud_value("elapsed", 0.0))), danger_q, _b_time, int(_hud_value("world", 1))])
	var glow: Control = _layers.time_glow
	glow.visible = hot > 0.0
	if glow.visible:
		glow.refresh([_b_bar])
		glow.modulate = Color(1, 1, 1, hot * (0.25 + 0.3 * (0.5 + 0.5 * sin(_time * 6.0))))
	var dna_key: Array = [_level(), _level_pulse, _b_dna]
	if evo != null:
		dna_key.append_array([int(evo.get("dna")), int(evo.threshold()), bool(evo.complete())])
	dna_key.append(int(_hud_value("amber", 0)))
	_layers.dna.refresh(dna_key)
	_layers.pause.refresh([_b_pause_c, _b_pause_r])
	# XP bar (Welle 2): thin violet strip over the full width, no numbers.
	var xp: Control = _layers.xp
	xp.visible = not extinct
	if xp.visible:
		xp.refresh([_xp_fill(), _level_pulse, size, _xp_top()])
	var cores := int(_hud_value("alpha_cores", 0))
	var alpha: Control = _layers.alpha
	alpha.visible = cores > 0
	if alpha.visible:
		alpha.refresh([cores, _b_alpha])
	var boss_on := _boss_y >= 0.0
	for part in ["boss_back", "boss", "boss_live"]:
		(_layers[part] as Control).visible = boss_on
	if boss_on:
		var keys := _boss_keys()
		_layers.boss_back.refresh(keys[0])
		_layers.boss.refresh(keys[1])
		_layers.boss_live.refresh(keys[2])
	var context: Control = _layers.context
	context.visible = not _ctx_current.is_empty() and not extinct
	if context.visible:
		context.refresh([_ctx_current, _b_context])
		var appear := clampf(_ctx_t / 0.2, 0.0, 1.0)
		var fade := clampf((CONTEXT_SECONDS - _ctx_t) / 0.45, 0.0, 1.0)
		context.modulate = Color(1, 1, 1, minf(appear, fade))
		context.position = Vector2(0, -12.0 * (1.0 - _ease(appear)))
	var medals: Control = _layers.medals
	medals.visible = not extinct
	if medals.visible:
		medals.refresh([_medal_key(evo), _relic_key(evo), _b_medal_y, size])
	var boosts: Control = _layers.boosts
	var active := _boost_list()
	boosts.visible = not extinct and not active.is_empty()
	if boosts.visible:
		var boost_key: Array = [_b_boost_origin(), _b_boost_limit()]
		for entry: Dictionary in active:
			boost_key.append([String(entry.id), int(float(entry.fraction) * 90.0), float(entry.left) <= 1.5 and int(_time * 6.0) % 2 == 0])
		boosts.refresh(boost_key)


# Collects context events and advances the one visible line.
func _brawl_context(delta: float) -> void:
	var pressure: float = _hud_value("pressure", 1.0)
	var tier := int(floor(log(maxf(1.0, pressure)) / log(2.0)))
	if _ctx_tier >= 0 and tier > _ctx_tier:
		_ctx_push(["DRUCK %s" % _b_pressure(pressure), "danger", "skull"])
	_ctx_tier = tier
	var hunters := int(_hud_value("hunters", 0))
	if _ctx_hunters == 0 and hunters > 0:
		_ctx_push(["JÄGER ×%d" % hunters, "danger", "skull"])
	_ctx_hunters = hunters
	# Etappe 27: an announced Hordenwelle jumps the queue (it is the next threat).
	var surge := bool(_hud_value("surge_warning", false))
	if surge and not _ctx_surge:
		_ctx_queue.push_front(["HORDE NAHT!", "danger", "skull", _time])
		_ctx_t = -1.0
	_ctx_surge = surge
	# Entries that waited too long are stale (the situation moved on).
	while not _ctx_queue.is_empty() and _time - float(_ctx_queue[0][3]) > CONTEXT_STALE:
		_ctx_queue.pop_front()
	if _ctx_t < 0.0 and not _ctx_queue.is_empty():
		_ctx_current = _ctx_queue.pop_front().slice(0, 3)
		_ctx_t = 0.0
	if _ctx_t >= 0.0:
		_ctx_t += delta
		if _ctx_t > CONTEXT_SECONDS:
			_ctx_t = -1.0
			_ctx_current = []


func _ctx_push(entry: Array) -> void:
	entry.append(_time)
	_ctx_queue.append(entry)
	while _ctx_queue.size() > CONTEXT_QUEUE:
		_ctx_queue.pop_front()


## Text of the context line currently shown ("" = none); tests read it.
func context_text() -> String:
	return "" if _ctx_current.is_empty() else String(_ctx_current[0])


func _b_pressure(pressure: float) -> String:
	if pressure < 10.0:
		return ("×%.1f" % pressure).replace(".", ",")
	return "×%s" % Kit.format_int(int(pressure))


func _b_text_width(value: String, font_size: int) -> float:
	return UiStyle.display_font().get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


func _b_left_x() -> float:
	var hud := get_parent()
	if hud != null and bool(hud.get("minimap_enabled")) and hud.has_method("_minimap_rect"):
		return (hud._minimap_rect() as Rect2).end.x + 8.0
	return 16.0


# Tone of a mutation (attack form) from its accent colour.
func _b_tone(accent: Variant) -> Variant:
	if accent is Color and _lib_has(_frames, "brawl_tone"):
		return _frames.call("brawl_tone", accent)
	return accent


func _b_draw_swarm() -> void:
	var rect := _b_swarm
	var cy := rect.get_center().y
	var pop := int(_hud_value("population", 0))
	var gain := _pop_delta >= 0
	var hurt := _swarm_hurt()
	var danger: Dictionary = UiStyle.brawl_tone("danger")
	var action: Dictionary = UiStyle.brawl_tone("action")
	# Etappe 22b: three layers - back (hurt ring), still (pill, dark plate, head)
	# and live (red plate while hurt, count, change pulse, LP strip).
	if _paint == "swarm_back":
		if hurt > 0.0:
			Kit.ring(_cv, rect.grow(6), rect.size.y * 0.5 + 6.0, 7.0, Color(danger["face"], 0.9 * hurt))
		return
	var plate_c := Vector2(rect.position.x + B_PLATE * 0.5 + 2.0, cy)
	var head_rect := Rect2(Kit.plate_center(plate_c, B_PLATE) - Vector2(26, 26), Vector2(52, 52))
	if _paint == "swarm":
		Kit.pill(_cv, rect)
		# The painted strain portrait head on a dark plate (turns red while hurt).
		Kit.icon_plate(_cv, plate_c, B_PLATE, "dark")
		_icon([_strain_head(), "mawling_head_color"], head_rect, Color.WHITE)
		return
	if hurt > 0.0:
		var plate_tone: Color = (UiStyle.brawl_tone("ember")["face"] as Color).lerp(danger["face"], hurt)
		# Over the baked dark plate, which already casts the drop shadow.
		var batch := Kit.TriBatch.new()
		Kit.icon_plate_into(batch, plate_c, B_PLATE, plate_tone, false)
		batch.flush(_cv)
		_icon([_strain_head(), "mawling_head_color"], head_rect, Color.WHITE)
	var x := plate_c.x + B_PLATE * 0.5 + 10.0
	var pulse_color: Color = action["light"] if gain else danger["light"]
	var at := Vector2(x, cy)
	if gain and _pop_pulse > 0.0:
		at.y -= 10.0 * sin(PI * clampf((1.0 - _pop_pulse) * 3.0, 0.0, 1.0))
	elif hurt > 0.0:
		at.x += sin(_time * 70.0) * 6.0 * hurt
	var room := rect.end.x - 18.0 - x
	# Etappe 17b: no limit any more - the count stands alone, short from 10.000 ("12,3k").
	at.y -= 7.0
	var w := Kit.number(_cv, at, short_count(pop), UiStyle.T_HEAD, Color.WHITE.lerp(pulse_color, _pop_pulse * 0.7), Kit.LEFT | Kit.MIDDLE, room * 0.62)
	var tail := Vector2(x + w + 6.0, cy - 3.0)
	if _pop_pulse > 0.0 and _pop_delta != 0:
		# Change pulse ("+7" / "−12") next to the count, then settles back.
		var text := "%s%s" % ["+" if gain else "−", short_count(absi(_pop_delta))]
		var rise := (1.0 - _pop_pulse) * 8.0
		Kit.number(_cv, tail - Vector2(0, 4.0 + rise), text, UiStyle.T_BODY, Color(pulse_color, minf(1.0, _pop_pulse * 1.8)), Kit.LEFT | Kit.MIDDLE, rect.end.x - 16.0 - tail.x)
	# Etappe 17c: the leader's LP as a small strip along the pill.
	var hp_rect := Rect2(x, rect.end.y - 24.0, rect.end.x - 22.0 - x, 12.0)
	_hp_strip(hp_rect, _leader_hp(), _leader_max_hp())


# How strongly the swarm pill shows a loss (0 = calm).
func _swarm_hurt() -> float:
	return 0.0 if _pop_delta >= 0 else _loss_strength * _pop_pulse


func _b_draw_time() -> void:
	Kit.pill(_cv, _b_time, "dark")
	var elapsed := int(float(_hud_value("elapsed", 0.0)))
	var text := "%02d:%02d" % [elapsed / 60, elapsed % 60]
	Kit.number(_cv, _b_time.get_center() - Vector2(0, 2), text, UiStyle.T_TITLE, Color.WHITE, Kit.CENTER | Kit.MIDDLE, _b_time.size.x - 44.0)
	Kit.bar(_cv, _b_bar, maxf(0.04, _danger_fraction()), "danger", 5)
	# Etappe 26: from the second world on, a small "WELT n" chip on the pill's top
	# edge (the clock keeps the total run time; flood and apex count world time).
	var world := int(_hud_value("world", 1))
	if world >= 2:
		var label := "WELT %d" % world
		var w := UiStyle.display_font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.T_LABEL).x + 24.0
		# Etappe 27: never over the XP bar above it (the chip slides down a little).
		var chip_top := maxf(_b_time.position.y - 16.0, _xp_top() + XP_H + 5.0)
		var chip := Rect2(_b_time.get_center().x - w * 0.5, chip_top, w, 32.0 if chip_top <= _b_time.position.y - 16.0 else 26.0)
		Kit.chip(_cv, chip, "special")
		Kit.text_outlined(_cv, chip.get_center(), label, UiStyle.T_LABEL, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE, w - 10.0)


func _b_draw_dna() -> void:
	var rect := _b_dna
	var evo := _evolution()
	var level := _level()
	var dna := 0 if evo == null else int(evo.get("dna"))
	var needed := 20 if evo == null else int(evo.threshold())
	var maxed := evo != null and bool(evo.complete())
	var info: Dictionary = UiStyle.brawl_tone("info")
	if _level_pulse > 0.0:
		Kit.ring(_cv, rect.grow(6), rect.size.y * 0.5 + 6.0, 7.0, Color(info["light"], 0.9 * _level_pulse))
	Kit.pill(_cv, rect)
	var plate_c := Vector2(rect.position.x + B_PLATE * 0.5 + 2.0, rect.get_center().y)
	Kit.icon_plate(_cv, plate_c, B_PLATE, "info")
	_icon(["dna"], Rect2(Kit.plate_center(plate_c, B_PLATE) - Vector2(24, 24), Vector2(48, 48)), Color.WHITE)
	var x0 := plate_c.x + B_PLATE * 0.5 + 10.0
	var x1 := rect.end.x - 24.0
	Kit.number(_cv, Vector2(x0, rect.position.y + 31.0), dna, UiStyle.T_HEAD, (info["light"] as Color).lerp(Color.WHITE, 0.55), Kit.LEFT | Kit.MIDDLE, x1 - x0)
	var fill := 1.0 if maxed else clampf(float(dna) / maxf(1.0, needed), 0.0, 1.0)
	Kit.bar(_cv, Rect2(x0, rect.position.y + 50.0, x1 - x0, 18.0), fill, "info")
	# Level as a badge on the plate (from level 1); it swells on level-up.
	if level <= 0 and not maxed:
		return
	var badge_size := UiStyle.T_HEAD if _level_pulse > 0.4 else UiStyle.T_BODY
	Kit.badge(_cv, plate_c + Vector2(-B_PLATE * 0.36, B_PLATE * 0.34), "MAX" if maxed else str(level), "special", badge_size)


func _b_draw_alpha() -> void:
	var rect := _b_alpha
	var cores := int(_hud_value("alpha_cores", 0))
	Kit.pill(_cv, rect, "dark", UiStyle.STROKE_S)
	var plate_size := rect.size.y + 8.0
	var plate_c := Vector2(rect.position.x + plate_size * 0.5 - 4.0, rect.get_center().y)
	Kit.icon_plate(_cv, plate_c, plate_size, "special")
	_icon(["alpha_core"], Rect2(Kit.plate_center(plate_c, plate_size) - Vector2(17, 17), Vector2(34, 34)), Color.WHITE)
	var x := plate_c.x + plate_size * 0.5 + 8.0
	var text := "ALPHA-KERN" if cores == 1 else "ALPHA-KERN ×%d" % cores
	Kit.text_outlined(_cv, Vector2(x, rect.get_center().y), text, UiStyle.T_LABEL, (UiStyle.brawl_tone("special")["light"] as Color).lerp(Color.WHITE, 0.5), -1, -1, null, Kit.LEFT | Kit.MIDDLE, rect.end.x - 18.0 - x)


func _b_draw_context() -> void:
	if _ctx_current.is_empty():
		return
	var rect := _b_context
	# See-through (handtest): the line must not hide the arena behind it.
	Kit.veil_pill(_cv, rect, "dark", 0.6)
	var plate_size := rect.size.y + 6.0
	var plate_c := Vector2(rect.position.x + plate_size * 0.5 - 4.0, rect.get_center().y)
	Kit.icon_plate(_cv, plate_c, plate_size, _ctx_current[1])
	_icon([String(_ctx_current[2])], Rect2(Kit.plate_center(plate_c, plate_size) - Vector2(16, 16), Vector2(32, 32)), Color.WHITE)
	Kit.text_outlined(_cv, Vector2(plate_c.x + plate_size * 0.5 + 10.0, rect.get_center().y), String(_ctx_current[0]), UiStyle.T_LABEL, Color.WHITE, -1, -1, null, Kit.LEFT | Kit.MIDDLE)


# Owned weapons as plates down the right edge, rank 1-5 as five pips (gold at
# rank 5); an evolved weapon glows violet and carries an EVO chip. Under them
# the relic strip (Etappe 17 Welle 2): small square plates in RELIC_COLS
# columns with a stack badge, at most RELIC_MAX (the last one shows "+N").
func _b_draw_medals() -> void:
	var hud := get_parent()
	var c := Vector2(size.x - 16.0 - MEDAL_SIZE * 0.5, _b_medal_y + MEDAL_SIZE * 0.5)
	for entry: Array in _medal_key(_evolution()):
		var id := String(entry[0])
		var evolved := String(entry[2]) == "evolved"
		var tone: Variant = "special"
		if not evolved:
			tone = _b_tone(hud._mutation_color(id)) if hud != null and hud.has_method("_mutation_color") else "ember"
		if evolved:
			Kit.glow(_cv, c, MEDAL_SIZE * 0.95, "special", 0.75)
		Kit.icon_plate(_cv, c, MEDAL_SIZE, tone)
		if not _icon([_item_icon(id), id], Rect2(Kit.plate_center(c, MEDAL_SIZE) - Vector2(24, 24), Vector2(48, 48)), Color.WHITE):
			Kit.text_outlined(_cv, Kit.plate_center(c, MEDAL_SIZE), id.left(1).to_upper(), UiStyle.T_BODY, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
		if evolved:
			var chip := Rect2(c + Vector2(-26.0, MEDAL_SIZE * 0.5 - 8.0), Vector2(52.0, 24.0))
			Kit.chip(_cv, chip, "special")
			Kit.text_outlined(_cv, chip.get_center(), "EVO", UiStyle.T_LABEL - 4, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
		else:
			var light: Color = UiStyle.brawl_tone(tone)["light"]
			var rank := int(entry[1])
			var fill: Color = UiStyle.brawl_tone("loot")["light"] if rank >= 5 else light
			for i in 5:
				var p := c + Vector2(-24.0 + 12.0 * i, MEDAL_SIZE * 0.5 + 5.0)
				Kit.disc(_cv, p, 6.5, UiStyle.BRAWL_INK)
				Kit.disc(_cv, p, 4.0, fill if i < rank else UiStyle.BRAWL_WELL)
		c.y += MEDAL_SIZE + 28.0
	var relics := _relic_key(_evolution())
	if relics.is_empty():
		return
	var shown := mini(relics.size(), RELIC_MAX)
	var right := size.x - 16.0
	var top_y := c.y - MEDAL_SIZE * 0.5 - 4.0
	for index in shown:
		var col := index % RELIC_COLS
		var row := index / RELIC_COLS
		var rc := Vector2(right - RELIC_SIZE * 0.5 - float(RELIC_COLS - 1 - col) * (RELIC_SIZE + RELIC_GAP), top_y + RELIC_SIZE * 0.5 + float(row) * (RELIC_SIZE + RELIC_GAP))
		var entry: Array = relics[index]
		Kit.icon_plate(_cv, rc, RELIC_SIZE, String(entry[2]), "square")
		if index == RELIC_MAX - 1 and relics.size() > RELIC_MAX:
			Kit.text_outlined(_cv, Kit.plate_center(rc, RELIC_SIZE), "+%d" % (relics.size() - RELIC_MAX + 1), UiStyle.T_LABEL, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
			continue
		var id := String(entry[0])
		if not _icon([_item_icon(id), id], Rect2(Kit.plate_center(rc, RELIC_SIZE) - Vector2(15, 15), Vector2(30, 30)), Color.WHITE):
			Kit.text_outlined(_cv, Kit.plate_center(rc, RELIC_SIZE), id.left(1).to_upper(), UiStyle.T_LABEL, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
		if int(entry[1]) > 1:
			Kit.badge(_cv, rc + Vector2(RELIC_SIZE * 0.4, RELIC_SIZE * 0.36), str(int(entry[1])), "dark", 16)


# Head icon of the played strain (cut from its painted portrait, ui_icons.strain_head).
func _strain_head() -> String:
	var strain := String(_hud_value("strain_id", ""))
	if strain != "" and _lib_has(_icons, "strain_head"):
		return String(_icons.call("strain_head", strain))
	return "mawling_head_color"


# Existing icon for an item id (evolution.icon_id maps new ids to old icons).
func _item_icon(id: String) -> String:
	var evo := _evolution()
	if evo != null and evo.has_method("icon_id"):
		return String(evo.icon_id(id))
	return id


# Owned relics [id, stacks, rarity tone] in catalogue order.
func _relic_key(evo: Object) -> Array:
	if evo == null or not evo.has_method("stacks"):
		return []
	var table: Variant = evo.get("RELICS")
	if not table is Array:
		return []
	# Stage 28: the rarity id itself is the kit tone (UiStyle.RARITY_TONES).
	var key: Array = []
	for row in table:
		var stacks := int(evo.stacks(String(row[0])))
		if stacks > 0:
			var rarity := String(row[3]) if row.size() > 3 else "common"
			key.append([String(row[0]), stacks, rarity if UiStyle.RARITY_TONES.has(rarity) else "common", UiStyle.colorblind])
	return key


# Active power-ups from HuntWorld (HUD meta "arsenal_world").
func _boost_list() -> Array:
	var state: Variant = _hud_value("arsenal_world", {})
	if state is Dictionary:
		return (state as Dictionary).get("active", [])
	return []


func _b_boost_origin() -> Vector2:
	var left := _b_left_x()
	return Vector2(left + BOOST_SIZE * 0.5 + (6.0 if left > 16.0 else 4.0), _b_swarm.end.y + 16.0 + BOOST_SIZE * 0.5)


func _b_boost_limit() -> float:
	return maxf(_b_boost_origin().x + BOOST_SIZE, _b_time.position.x - 8.0)


# Power-up row under the swarm pill: plate + icon in the booster tone, a ring
# timer around it (white arc = time left), blinking in the last 1.5 s.
func _b_draw_boosts() -> void:
	var origin := _b_boost_origin()
	var limit := _b_boost_limit()
	var c := origin
	for entry: Dictionary in _boost_list():
		if c.x + BOOST_SIZE * 0.5 > limit and c.x > origin.x:
			c = Vector2(origin.x, c.y + BOOST_SIZE + BOOST_GAP + 6.0)
		var tone := String(entry.get("tone", "neutral"))
		var fraction := clampf(float(entry.get("fraction", 0.0)), 0.0, 1.0)
		var blink := float(entry.get("left", 0.0)) <= 1.5 and int(_time * 6.0) % 2 == 0
		var ring_r := BOOST_SIZE * 0.5 + 6.0
		Kit.disc(_cv, c + Vector2(0, 3), ring_r + 3.0, UiStyle.BRAWL_INK_SOFT)
		Kit.disc(_cv, c, ring_r + 3.0, UiStyle.BRAWL_INK)
		Kit.circle_ring(_cv, c, ring_r, 5.0, UiStyle.BRAWL_WELL)
		if fraction > 0.0:
			var arc_color: Color = UiStyle.brawl_tone("danger")["light"] if blink else UiStyle.brawl_tone(tone)["light"].lerp(Color.WHITE, 0.45)
			_cv.draw_arc(c, ring_r - 0.5, -PI * 0.5, -PI * 0.5 + TAU * fraction, maxi(8, int(48.0 * fraction)), arc_color, 5.0, true)
		Kit.icon_plate(_cv, c, BOOST_SIZE, tone)
		if not _icon([String(entry.get("icon", "")), String(entry.get("id", ""))], Rect2(Kit.plate_center(c, BOOST_SIZE) - Vector2(17, 17), Vector2(34, 34)), Color(1, 1, 1, 0.55 if blink else 1.0)):
			Kit.text_outlined(_cv, Kit.plate_center(c, BOOST_SIZE), String(entry.get("id", "?")).left(1).to_upper(), UiStyle.T_LABEL, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
		c.x += BOOST_SIZE + BOOST_GAP + 12.0


# Etappe 17 Welle 2 - Bernstein pill (right): gold plate + Bernstein count with
# German thousands dots; the level sits as a small violet badge on the plate.
# The DNA number is gone - experience shows as the thin violet XP bar on top.
func _b_draw_amber() -> void:
	var rect := _b_dna
	var evo := _evolution()
	var level := _level()
	var maxed := evo != null and bool(evo.complete())
	var amber := int(_hud_value("amber", 0))
	var loot: Dictionary = UiStyle.brawl_tone("loot")
	if _level_pulse > 0.0:
		Kit.ring(_cv, rect.grow(6), rect.size.y * 0.5 + 6.0, 7.0, Color(UiStyle.brawl_tone("special")["light"], 0.9 * _level_pulse))
	Kit.pill(_cv, rect)
	var plate_c := Vector2(rect.position.x + B_PLATE * 0.5 + 2.0, rect.get_center().y)
	Kit.icon_plate(_cv, plate_c, B_PLATE, "loot")
	if not _icon(["amber", "currency_amber", "crown_tooth"], Rect2(Kit.plate_center(plate_c, B_PLATE) - Vector2(24, 24), Vector2(48, 48)), Color.WHITE):
		Kit.disc(_cv, Kit.plate_center(plate_c, B_PLATE), 16.0, loot["light"])
	var x0 := plate_c.x + B_PLATE * 0.5 + 10.0
	var x1 := rect.end.x - 20.0
	Kit.number(_cv, Vector2(x0, rect.get_center().y), amber, UiStyle.T_HEAD, (loot["light"] as Color).lerp(Color.WHITE, 0.35), Kit.LEFT | Kit.MIDDLE, x1 - x0)
	if level <= 0 and not maxed:
		return
	var badge_size := UiStyle.T_BODY if _level_pulse > 0.4 else UiStyle.T_LABEL
	Kit.badge(_cv, plate_c + Vector2(-B_PLATE * 0.36, B_PLATE * 0.34), "MAX" if maxed else str(level), "special", badge_size)


## XP fill 0..1 (DNA towards the next level; 1 when every stat is maxed).
func _xp_fill() -> float:
	var evo := _evolution()
	if evo == null:
		return 0.0
	# Etappe 31: with every stat maxed the levels go on (overdrive choices), so
	# the bar keeps filling; MAX only once no overdrive bonus is left either.
	if bool(evo.complete()) and evo.has_method("overdrive_candidates") and (evo.overdrive_candidates() as Array).is_empty():
		return 1.0
	return clampf(float(evo.get("dna")) / maxf(1.0, float(evo.threshold())), 0.0, 1.0)


## Top edge of the XP bar: below the display's safe area (notch), measured in
## viewport units. Etappe 27 (S25): the viewport is letterboxed (stretch aspect
## "keep"), so the safe inset is taken relative to the viewport's top edge on
## the screen; the old screen-to-viewport ratio pushed the bar down behind the
## pill row on the phone.
func _xp_top() -> float:
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.y <= 0 or not is_inside_tree():
		return 0.0
	var root := get_tree().root
	if root == null or root.size.y <= 0 or DisplayServer.window_get_size().y < DisplayServer.screen_get_size().y - 2:
		return 0.0
	var screen_from_canvas := root.get_final_transform()
	var scale_y := screen_from_canvas.get_scale().y
	if scale_y <= 0.0:
		return 0.0
	var inset := (float(safe.position.y) - screen_from_canvas.origin.y) / scale_y
	# Never down into the pill row (B_TOP): the bar must stay above every panel.
	return clampf(inset, 0.0, B_TOP - XP_H - 4.0)


const XP_H := 16.0


# Violet strip across the full width (Kit tone special), no numbers; it flashes
# on a level-up. Etappe 27: 10 -> 16 px with a light track and an ink frame so
# it reads on the phone and never sits behind a panel (drawn above B_TOP).
func _b_draw_xp() -> void:
	var top := _xp_top()
	var track := Rect2(0.0, top, size.x, XP_H)
	var special: Dictionary = UiStyle.brawl_tone("special")
	_cv.draw_rect(Rect2(0.0, top, size.x, XP_H + 3.0), Color(UiStyle.BRAWL_INK, 0.92))
	_cv.draw_rect(track.grow_individual(0.0, -2.0, 0.0, -2.0), Color(UiStyle.BRAWL_WELL, 0.95))
	var fill := _xp_fill()
	if fill > 0.0:
		var bar := Rect2(track.position + Vector2(0.0, 2.0), Vector2(track.size.x * fill, XP_H - 4.0))
		_cv.draw_rect(bar, special["face"])
		_cv.draw_rect(Rect2(bar.position, Vector2(bar.size.x, 4.0)), Color(special["light"], 0.95))
		_cv.draw_rect(Rect2(bar.end.x - 4.0, bar.position.y, 4.0, bar.size.y), Color(Color.WHITE, 0.9))
	if _level_pulse > 0.0:
		_cv.draw_rect(track.grow(2.0), Color(special["light"], 0.6 * _level_pulse))


# ---------------------------------------------------------------- boss stack (package H)
# One look for every boss (S10): dark panel, square danger portrait plate that
# sticks out a little, the name from the data (T_HEAD), exact numbers and a
# health bar with one segment per phase plus phase markers. While a boss is
# exhausted (vulnerable) a gold ring blinks and the chip JETZT ANGREIFEN takes
# the place of the numbers; a rising apex shows ERWACHT and a filling bar. A
# new bar slides in from the right and pulses briefly. Two bosses at once
# stack as two compact bars. Bog King values come from the HUD, the apex
# (Moosschlund / Aschenkröte) from the HUD meta "objectives"; hud_objectives.gd
# draws no apex bar of its own in the skin brawl. Below the stack a row is
# reserved for the flood pill of hud_flood.gd (flood_slot()).

const BOSS_FULL_H := 92.0
const BOSS_COMPACT_H := 66.0
const BOSS_GAP := 14.0
const BOSS_INTRO := 0.6        # slide-in from the right (s)
const BOSS_PULSE := 1.8        # danger glow after the entrance (s)
const FLOOD_H := 60.0
const FLOOD_H_COMPACT := 48.0

var _boss_list: Array = []
var _boss_seen: Dictionary = {}      # boss id -> _time when its bar appeared
var _boss_stack_h := 0.0
var _flood_slot := Rect2()
var _stack_bottom := 0.0


## Bottom of the contextual stack under the header (boss bars, flood pill);
## hud_objectives keeps its edge pointers below it.
func top_stack_bottom() -> float:
	return _stack_bottom if _brawl else 0.0


## Row reserved for the flood pill (hud_flood.gd centres itself in it). Empty
## without an announced or running flood and outside the skin brawl.
func flood_slot() -> Rect2:
	return _flood_slot if _brawl else Rect2()


## Names of the boss bars shown, top to bottom (tests read it).
func boss_names() -> PackedStringArray:
	var names := PackedStringArray()
	for entry: Dictionary in _boss_list:
		names.append(String(entry.name))
	return names


# Living bosses in order of appearance: {id, name, icon, health, max,
# vulnerable, warning (-1 or the rising share 0..1), phases, phase}.
func _boss_entries() -> Array:
	var list: Array = []
	var king := float(_hud_value("boss_health", 0.0))
	if king > 0.0:
		list.append({"id": "bog_king", "name": "BOG KING", "icon": ["portrait_bog_king", "bog_king", "crown"],
			"health": king, "max": maxf(1.0, float(_hud_value("boss_max_health", 1.0))),
			"vulnerable": bool(_hud_value("boss_vulnerable", false)), "warning": -1.0, "phases": 1, "phase": 1})
	var hud := get_parent()
	var state: Variant = hud.get_meta("objectives", {}) if hud != null else {}
	var obj: Dictionary = state if state is Dictionary else {}
	var apex_state := int(obj.get("apex_state", 0))
	if apex_state == 1 or apex_state == 2:
		var kind := String(obj.get("apex_kind", "apex"))
		list.append({"id": kind, "name": String(obj.get("apex_name", "MOOSSCHLUND")), "icon": ["portrait_" + kind, "diff_apex", "crown"],
			"health": float(obj.get("apex_health", 0.0)), "max": maxf(1.0, float(obj.get("apex_max_health", 1.0))),
			"vulnerable": apex_state == 2 and bool(obj.get("apex_vulnerable", false)),
			# apex_warning runs 1 -> 0 while the apex rises; the bar fills up.
			"warning": clampf(1.0 - float(obj.get("apex_warning", 0.0)), 0.0, 1.0) if apex_state == 1 else -1.0,
			"phases": 2, "phase": int(obj.get("apex_phase", 1))})
	var alive := {}
	for entry: Dictionary in list:
		alive[entry.id] = true
		if not _boss_seen.has(entry.id):
			_boss_seen[entry.id] = _time
	for id in _boss_seen.keys():
		if not alive.has(id):
			_boss_seen.erase(id)
	# The boss that came first keeps the top slot.
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(_boss_seen[a.id]) < float(_boss_seen[b.id]))
	return list


# Etappe 22b: keys of the three boss layers [back, still, live]. The still
# picture (panel, portrait, name, tag chip) only repaints during the entrance
# slide or when its text layout changes; health and warning only touch the
# live layer (numbers, bar, phase marks), the pulse rings sit behind in back.
func _boss_keys() -> Array:
	var base: Array = [_boss_y, size, _b_left_x()]
	var back: Array = base.duplicate()
	var still: Array = base.duplicate()
	var live: Array = base.duplicate()
	var ringing := false
	var sliding := false
	var compact := _boss_list.size() > 1
	var left := _b_left_x()
	for entry: Dictionary in _boss_list:
		var t := _time - float(_boss_seen.get(entry.id, -100.0))
		var vulnerable := bool(entry.vulnerable)
		var warning := float(entry.warning)
		if vulnerable or warning >= 0.0 or t < BOSS_PULSE:
			ringing = true
		if t < BOSS_INTRO:
			sliding = true
		back.append([entry.id, vulnerable, warning >= 0.0])
		var layout := _boss_text_layout(entry, size.x - 16.0 - left, compact)
		still.append([entry.id, entry.name, int(entry.max), vulnerable, warning >= 0.0, entry.phase, int(entry.phases), layout])
		live.append([entry.id, int(ceil(float(entry.health))), int(entry.max), vulnerable, snappedf(warning, 0.005), entry.phase, int(entry.phases)])
	back.append(int(_time * 30.0) if ringing else -1)
	still.append(int(_time * 30.0) if sliding else -1)
	live.append(int(_time * 30.0) if sliding else -1)
	return [back, still, live]


# Width-dependent parts of a boss entry's text row that the still picture
# depends on: the name's squeeze and where the phase chip goes. The numbers'
# width (live) decides how much room the name has. width = panel width.
func _boss_text_layout(entry: Dictionary, width: float, compact: bool) -> Array:
	var h := BOSS_COMPACT_H if compact else BOSS_FULL_H
	var plate := h + (6.0 if compact else 10.0)
	var room := width - (plate - 6.0) - 12.0 - 18.0
	var slot_w := _boss_slot_width(entry, room)
	var name_room := room - slot_w - 14.0
	var name_size := UiStyle.T_BODY if compact else UiStyle.T_HEAD
	var natural := _b_text_width(String(entry.name), name_size)
	var name_w := minf(natural, name_room)
	var chip_fits := false
	if int(entry.phases) > 1 and int(entry.phase) > 1 and float(entry.warning) < 0.0:
		var pw := _b_text_width("PHASE %d" % int(entry.phase), UiStyle.T_LABEL) + 24.0
		chip_fits = not compact and name_w + 14.0 + pw <= name_room
	return [snappedf(name_room, 0.25) if natural > name_room else -1.0, chip_fits]


# Right slot width of a boss entry: tag chip or exact numbers; room = x1 - x0.
func _boss_slot_width(entry: Dictionary, room: float) -> float:
	var tag := ""
	if bool(entry.vulnerable):
		tag = "JETZT ANGREIFEN"
	elif float(entry.warning) >= 0.0:
		tag = "ERWACHT"
	if tag != "":
		return minf(_b_text_width(tag, UiStyle.T_LABEL) + 40.0, room * 0.62)
	var numbers := "%s / %s" % [Kit.format_int(int(ceil(float(entry.health)))), Kit.format_int(int(entry.max))]
	return minf(UiStyle.number_font().get_string_size(numbers, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.T_LABEL).x, room * 0.5)


# Lays out (paint "") or draws (paint "boss") the boss stack from y; returns the bottom.
func _draw_boss_bar(y: float) -> float:
	var left := _b_left_x()
	var compact := _boss_list.size() > 1
	var h := BOSS_COMPACT_H if compact else BOSS_FULL_H
	var bottom := y
	for i in _boss_list.size():
		var rect := Rect2(left, y + i * (h + BOSS_GAP), size.x - 16.0 - left, h)
		bottom = rect.end.y
		if _paint.begins_with("boss"):
			_draw_boss_entry(_boss_list[i], rect, compact)
	_boss_stack_h = bottom - y
	return bottom


func _draw_boss_entry(entry: Dictionary, rect: Rect2, compact: bool) -> void:
	var t := _time - float(_boss_seen.get(entry.id, -100.0))
	# Entrance: slides in from the right edge with a small overshoot.
	var k := clampf(t / BOSS_INTRO, 0.0, 1.0)
	var back := 1.0 + 2.4 * pow(k - 1.0, 3.0) + 1.4 * pow(k - 1.0, 2.0)
	rect.position.x += (1.0 - back) * (size.x - rect.position.x + 24.0)
	var danger: Dictionary = UiStyle.brawl_tone("danger")
	var loot: Dictionary = UiStyle.brawl_tone("loot")
	var vulnerable := bool(entry.vulnerable)
	var warning := float(entry.warning)
	var radius := UiStyle.R_M if compact else UiStyle.R_L
	var beat := 0.5 + 0.5 * sin(_time * 7.0)
	# Etappe 22b: "boss_back" = pulse ring, "boss" = still picture, "boss_live" = numbers and bar.
	var still := _paint == "boss"
	var live := _paint == "boss_live"
	if _paint != "boss_back":
		pass
	elif vulnerable:
		Kit.ring(_cv, rect.grow(6), radius + 6.0, 7.0, Color(loot["face"], 0.35 + 0.6 * beat))
	elif t < BOSS_PULSE and k >= 1.0:
		var fade := 1.0 - (t - BOSS_INTRO) / (BOSS_PULSE - BOSS_INTRO)
		var swell := 0.5 + 0.5 * sin(t * 12.0)
		Kit.ring(_cv, rect.grow(5.0 + 4.0 * swell), radius + 5.0 + 4.0 * swell, 6.0, Color(danger["face"], fade * (0.3 + 0.55 * swell)))
	elif warning >= 0.0:
		Kit.ring(_cv, rect.grow(5), radius + 5.0, 5.0, Color(danger["face"], 0.2 + 0.45 * beat))
	if not still and not live:
		return
	# Portrait plate: a little taller than the panel, so it reads as a medallion.
	var plate := rect.size.y + (6.0 if compact else 10.0)
	var plate_c := Vector2(rect.position.x + plate * 0.5 - 6.0, rect.get_center().y)
	if still:
		Kit.panel(_cv, rect, "dark", radius)
		Kit.icon_plate(_cv, plate_c, plate, "danger", "square")
		var face := Kit.plate_center(plate_c, plate)
		var icon := roundf(plate * 0.76)
		if not _icon(entry.icon, Rect2(face - Vector2(icon, icon) * 0.5, Vector2(icon, icon)), Color.WHITE):
			Kit.text_outlined(_cv, face, String(entry.name).left(1), UiStyle.T_HEAD, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
	var x0 := plate_c.x + plate * 0.5 + 12.0
	var x1 := rect.end.x - 18.0
	var name_size := UiStyle.T_BODY if compact else UiStyle.T_HEAD
	var name_y := rect.position.y + (30.0 if compact else 40.0)
	var chip_h := 30.0 if compact else 34.0
	var chip_y := rect.position.y + (6.0 if compact else 10.0)
	# Right slot: JETZT ANGREIFEN, ERWACHT or the exact numbers.
	var slot_w := 0.0
	var tag := ""
	var tag_tone := "loot"
	if vulnerable:
		tag = "JETZT ANGREIFEN"
	elif warning >= 0.0:
		tag = "ERWACHT"
		tag_tone = "danger"
	if tag != "":
		slot_w = minf(_b_text_width(tag, UiStyle.T_LABEL) + 40.0, (x1 - x0) * 0.62)
		var tag_rect := Rect2(x1 - slot_w, chip_y, slot_w, chip_h)
		if still:
			Kit.chip(_cv, tag_rect, tag_tone)
			Kit.text_outlined(_cv, tag_rect.get_center(), tag, UiStyle.T_LABEL, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE, slot_w - 16.0)
	else:
		var numbers := "%s / %s" % [Kit.format_int(int(ceil(float(entry.health)))), Kit.format_int(int(entry.max))]
		slot_w = UiStyle.number_font().get_string_size(numbers, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.T_LABEL).x
		slot_w = minf(slot_w, (x1 - x0) * 0.5)
		if live:
			Kit.number(_cv, Vector2(x1, name_y - 2.0), numbers, UiStyle.T_LABEL, (danger["light"] as Color).lerp(Color.WHITE, 0.6), Kit.RIGHT, slot_w)
	if live:
		_draw_boss_bar_fill(entry, x0, x1, rect, compact, vulnerable, warning)
		return
	var name_room := x1 - x0 - slot_w - 14.0
	var name_w := Kit.text_outlined(_cv, Vector2(x0, name_y), String(entry.name), name_size, Color.WHITE, -1, -1, null, Kit.LEFT, name_room)
	# Phase 2: a chip after the name when it fits, else a badge on the plate.
	var phase := int(entry.phase)
	if int(entry.phases) > 1 and phase > 1 and warning < 0.0:
		var label := "PHASE %d" % phase
		var pw := _b_text_width(label, UiStyle.T_LABEL) + 24.0
		if not compact and name_w + 14.0 + pw <= name_room:
			var phase_rect := Rect2(x0 + name_w + 14.0, chip_y + 2.0, pw, chip_h - 4.0)
			Kit.chip(_cv, phase_rect, "ember")
			Kit.text_outlined(_cv, phase_rect.get_center(), label, UiStyle.T_LABEL, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE, pw - 12.0)
		else:
			Kit.badge(_cv, plate_c + Vector2(plate * 0.4, plate * 0.36), str(phase), "ember", UiStyle.T_LABEL)


# Live part of a boss entry: the health (or warning) bar with its phase marks.
func _draw_boss_bar_fill(entry: Dictionary, x0: float, x1: float, rect: Rect2, compact: bool, vulnerable: bool, warning: float) -> void:
	var bar := Rect2(x0, rect.position.y + 38.0, x1 - x0, 20.0) if compact else Rect2(x0, rect.position.y + 50.0, x1 - x0, 28.0)
	var fraction := warning if warning >= 0.0 else clampf(float(entry.health) / float(entry.max), 0.0, 1.0)
	var phases := int(entry.phases)
	Kit.bar(_cv, bar, fraction, "loot" if vulnerable else "danger", phases if phases > 1 else 0)
	if warning < 0.0 and phases > 1:
		# Etappe 22b: shadows and faces of all marks in one triangle list
		# (the marks never overlap), then the outlines.
		var batch := Kit.TriBatch.new()
		var outlines: Array = []
		for i in range(1, phases):
			outlines.append(_boss_phase_mark(batch, bar, float(i) / float(phases), fraction, compact))
		batch.flush(_cv)
		for outline: PackedVector2Array in outlines:
			_cv.draw_polyline(outline, UiStyle.BRAWL_INK, UiStyle.STROKE_S, true)


# Phase marker: a diamond on the bar's top edge at the phase threshold, lit
# while it is still ahead, dark once the boss has passed it. Adds shadow and
# face to `batch` and returns the outline.
func _boss_phase_mark(batch: Kit.TriBatch, bar: Rect2, at: float, fraction: float, compact: bool) -> PackedVector2Array:
	var r := 10.0 if compact else 12.0
	var c := Vector2(roundf(bar.position.x + 3.0 + (bar.size.x - 6.0) * at), bar.position.y - 1.0)
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	var fill: Color = UiStyle.brawl_tone("danger")["light"] if fraction > at else UiStyle.BRAWL_WELL
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(0, 3))
	batch.polygon(shadow, PackedColorArray([UiStyle.BRAWL_INK_SOFT, UiStyle.BRAWL_INK_SOFT, UiStyle.BRAWL_INK_SOFT, UiStyle.BRAWL_INK_SOFT]))
	batch.polygon(pts, PackedColorArray([fill, fill, fill, fill]))
	var outline := pts.duplicate()
	outline.append(pts[0])
	return outline


# Reserves the flood pill row below the boss stack; returns the next free y.
func _flood_layout(y: float) -> float:
	_flood_slot = Rect2()
	var hud := get_parent()
	var state: Variant = hud.get_meta("flood", {}) if hud != null else {}
	var flood: Dictionary = state if state is Dictionary else {}
	var mode := int(flood.get("state", 0))
	if (mode != 1 and mode != 2) or bool(_hud_value("extinct", false)):
		return y
	var h := FLOOD_H if _boss_list.is_empty() else FLOOD_H_COMPACT
	if _boss_list.is_empty() and _b_alpha.size.y > 0.0:
		# The Alpha-Kern pill hangs under the DNA pill; the flood pill waits below it.
		y = maxf(y, _b_alpha.end.y + 12.0)
	_flood_slot = Rect2(0, y, size.x, h)
	return y + h + 14.0


# ---------------------------------------------------------------- leader marker

const LEADER_PIP_R := 13.0
const LEADER_PIP_GAP := 34.0
const PIP_BREAK_SECONDS := 0.55


func _find_swarm() -> Node3D:
	if _swarm_node == null or not is_instance_valid(_swarm_node):
		_swarm_node = get_tree().get_first_node_in_group("swarm") as Node3D if is_inside_tree() else null
	return _swarm_node


# Projects the leader anchor every frame and only moves the layer; it repaints
# when hit points, the crown jump or a breaking pip change.
func _refresh_leader() -> void:
	var layer: Control = _layers.leader
	var swarm := _find_swarm()
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	_leader = swarm.call("leader_display") if swarm != null and swarm.has_method("leader_display") else {}
	var shown := camera != null and bool(_leader.get("visible", false)) and not bool(_hud_value("extinct", false)) and not bool(_hud_value("paused", false))
	if shown:
		var anchor: Vector3 = _leader.anchor
		shown = not camera.is_position_behind(anchor)
		if shown:
			_leader_screen = camera.unproject_position(anchor)
			var from: Vector3 = _leader.from
			_crown_from_screen = camera.unproject_position(from) if not camera.is_position_behind(from) else _leader_screen
	layer.visible = shown
	if not shown:
		return
	layer.position = (_leader_screen - Vector2(0, 14)).round()
	var hp := _leader_hp()
	var max_hp := _leader_max_hp()
	var jump := float(_leader.get("jump", 1.0))
	var hit := float(_leader.get("hit_age", 99.0))
	var broke := float(_leader.get("pip_break_age", 99.0))
	var moving := jump < 1.0 or hit < 0.5 or broke < PIP_BREAK_SECONDS
	var heal: Variant = _hud_value("leader_heal", {})
	var healing: bool = heal is Dictionary and float(heal.get("age", 99.0)) < 0.9
	layer.refresh([hp, max_hp, int(_time * 60.0) if moving or healing or (max_hp > 0 and hp * 4 < max_hp) else 0, jump < 1.0])
	# Invulnerable: the whole marker blinks through modulate (no repaint).
	var blink := bool(_hud_value("leader_invulnerable", _leader.get("invulnerable", false)))
	layer.modulate = Color(1, 1, 1, 0.35 if blink and fmod(_time * 7.0, 1.0) < 0.5 else 1.0)


func _leader_hp() -> int:
	return int(_hud_value("leader_hp", _leader.get("hp", 0)))


func _leader_max_hp() -> int:
	return int(_hud_value("leader_max_hp", _leader.get("max_hp", 0)))


# Etappe 17c: crown above a health bar in the enemy-bar style (green -> yellow ->
# red with the share of LP), a white chunk fades where the last hit took LP, a
# small green "+N" rises when the leader heals (Lebensraub, Regeneration).
func _draw_leader() -> void:
	if _leader.is_empty():
		return
	var hp := _leader_hp()
	var max_hp := maxi(1, _leader_max_hp())
	var hit := float(_leader.get("hit_age", 99.0))
	var shake := Vector2.ZERO
	if hit < 0.4:
		var k := 1.0 - hit / 0.4
		shake = Vector2(sin(_time * 80.0) * 6.0 * k, cos(_time * 67.0) * 3.0 * k)
	var bar := Rect2(Vector2(-LEADER_BAR_W * 0.5, -LEADER_BAR_H * 0.5) + shake, Vector2(LEADER_BAR_W, LEADER_BAR_H))
	var before := int(_leader.get("pip_broken", -1))
	var broke := float(_leader.get("pip_break_age", 99.0))
	_hp_bar(bar, hp, max_hp, before if broke < PIP_BREAK_SECONDS else -1, broke / PIP_BREAK_SECONDS)
	var heal: Variant = _hud_value("leader_heal", {})
	if heal is Dictionary and int(heal.get("amount", 0)) > 0 and float(heal.get("age", 99.0)) < 0.9:
		var t := float(heal.age) / 0.9
		var at := Vector2(LEADER_BAR_W * 0.5 + 10.0, -6.0 - 22.0 * t) + shake
		Kit.text_outlined(_cv, at, "+%d" % int(heal.amount), UiStyle.T_LABEL, Color(UiStyle.brawl_tone("action")["light"], 1.0 - t * t), -1, -1, null, Kit.LEFT | Kit.MIDDLE)
	# Crown: jumps in an arc from the fallen leader to its successor.
	var crown := Vector2(0, bar.position.y - 20.0)
	var jump := float(_leader.get("jump", 1.0))
	var scale := 1.0
	var disc := _disc_texture()
	if jump < 1.0:
		var from := _crown_from_screen - _leader_screen + crown
		crown = from.lerp(crown, _ease(jump)) + Vector2(0, -70.0 * sin(PI * jump))
		scale = 1.0 + 0.5 * sin(PI * jump)
		var glow := Vector2(34, 34) * scale
		_cv.draw_texture_rect(disc, Rect2(crown - glow, glow * 2.0), false, Color(UiStyle.color("gold"), 0.3 * (1.0 - jump)))
	var r := 24.0 * scale
	if not _icon(["crown"], Rect2(crown - Vector2(r, r), Vector2(r, r) * 2.0), Color.WHITE):
		_crown(crown, 18.0 * scale)


const LEADER_BAR_W := 92.0
const LEADER_BAR_H := 14.0


## Health colour: green (full) -> yellow (half) -> red (critical).
static func hp_color(share: float) -> Color:
	var green := Color("5fe03a")
	var yellow := Color("ffd23a")
	var red := Color("ff3b4a")
	if share >= 0.5:
		return yellow.lerp(green, (share - 0.5) / 0.5)
	return red.lerp(yellow, clampf((share - 0.2) / 0.3, 0.0, 1.0))


# Enemy-bar style: ink frame, dark track, coloured fill with a top gloss and
# (optionally) the white chunk of the last hit fading out.
func _hp_bar(rect: Rect2, hp: int, max_hp: int, before: int = -1, chunk_t: float = 1.0) -> void:
	var share := clampf(float(hp) / float(maxi(1, max_hp)), 0.0, 1.0)
	Kit.rrect(_cv, rect.grow(3.0), rect.size.y * 0.5 + 3.0, UiStyle.BRAWL_INK)
	Kit.rrect(_cv, rect, rect.size.y * 0.5, UiStyle.BRAWL_WELL)
	if before > hp and chunk_t < 1.0:
		var from := clampf(float(before) / float(maxi(1, max_hp)), 0.0, 1.0)
		var chunk := Rect2(rect.position.x + rect.size.x * share, rect.position.y, rect.size.x * (from - share), rect.size.y)
		_cv.draw_rect(chunk, Color(1, 1, 1, 0.85 * (1.0 - chunk_t)))
	if share > 0.0:
		var fill := Rect2(rect.position, Vector2(maxf(rect.size.y, rect.size.x * share), rect.size.y))
		var color := hp_color(share)
		Kit.rrect(_cv, fill, rect.size.y * 0.5, color)
		Kit.rrect(_cv, Rect2(fill.position + Vector2(3, 2), Vector2(fill.size.x - 6.0, rect.size.y * 0.3)), rect.size.y * 0.15, Color(1, 1, 1, 0.35))
	# Low LP: the frame pulses red.
	if share < 0.25 and share > 0.0:
		Kit.ring(_cv, rect.grow(3.0), rect.size.y * 0.5 + 3.0, 2.0, Color(UiStyle.brawl_tone("danger")["light"], 0.5 + 0.5 * sin(_time * 10.0)))


# Thin LP strip on the swarm pill (same colours as the leader bar).
func _hp_strip(rect: Rect2, hp: int, max_hp: int) -> void:
	if max_hp <= 0 or rect.size.x <= 8.0:
		return
	_hp_bar(rect, hp, max_hp)


## Population text: German thousands dots, short from 10.000 ("12,3k", "1,2M").
static func short_count(value: int) -> String:
	if value >= 1000000:
		return ("%.1fM" % (float(value) / 1000000.0)).replace(".", ",")
	if value >= 10000:
		return ("%.1fk" % (float(value) / 1000.0)).replace(".", ",").replace(",0k", "k")
	return Kit.format_int(value)


# Soft-edged white disc shared by the leader pips and their backing.
static var _disc: GradientTexture2D


func _disc_texture() -> Texture2D:
	if _disc == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.8, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		_disc = GradientTexture2D.new()
		_disc.gradient = gradient
		_disc.fill = GradientTexture2D.FILL_RADIAL
		_disc.fill_from = Vector2(0.5, 0.5)
		_disc.fill_to = Vector2(1.0, 0.5)
		_disc.width = 64
		_disc.height = 64
	return _disc


# One hit point: dark rim, warm ember core and a gloss dot; empty = dark socket.
func _pip(disc: Texture2D, c: Vector2, full: bool, flash: bool) -> void:
	var r := LEADER_PIP_R
	_cv.draw_texture_rect(disc, Rect2(c - Vector2(r + 3, r + 3), Vector2(r + 3, r + 3) * 2.0), false, UiStyle.color("outline"))
	if full:
		var fill := UiStyle.color("ember_glow").lerp(Color.WHITE, 0.6) if flash else UiStyle.color("ember").lerp(UiStyle.color("ember_glow"), 0.55)
		_cv.draw_texture_rect(disc, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false, fill)
		var dot := r * 0.32
		_cv.draw_texture_rect(disc, Rect2(c + Vector2(-r * 0.3, -r * 0.32) - Vector2(dot, dot), Vector2(dot, dot) * 2.0), false, Color(1, 1, 1, 0.6))
	else:
		_cv.draw_texture_rect(disc, Rect2(c - Vector2(r - 3, r - 3), Vector2(r - 3, r - 3) * 2.0), false, Color(UiStyle.color("danger").darkened(0.55), 0.9))


# The pip that just broke: two halves fly apart, tumble and fade.
func _broken_pip(c: Vector2, t: float) -> void:
	var r := LEADER_PIP_R
	var a := 1.0 - t
	var drift := 22.0 * _ease(t)
	var drop := 26.0 * t * t
	for side: float in [-1.0, 1.0]:
		var o := c + Vector2(side * drift, drop)
		var turn := side * t * 1.6
		var half := PackedVector2Array([Vector2(0, -r * 1.15), Vector2(side * r, -r * 0.2), Vector2(side * r * 0.7, r * 0.8), Vector2(0, r * 1.1), Vector2(side * r * 0.15, 0)])
		var pts := PackedVector2Array()
		for p in half:
			pts.append(o + p.rotated(turn))
		_cv.draw_colored_polygon(pts, Color(UiStyle.color("danger").lerp(UiStyle.color("ember_glow"), 0.3), a))
	if t < 0.35:
		_cv.draw_circle(c, r * (1.0 + 2.0 * t), Color(1, 1, 1, 0.5 * (1.0 - t / 0.35)))


func _crown(c: Vector2, r: float) -> void:
	var k := r / 20.0
	var pts := PackedVector2Array([c + Vector2(-20, 12) * k, c + Vector2(-23, -12) * k, c + Vector2(-10, 0) * k, c + Vector2(0, -18) * k, c + Vector2(10, 0) * k, c + Vector2(23, -12) * k, c + Vector2(20, 12) * k])
	var outline := pts.duplicate()
	outline.append(pts[0])
	_cv.draw_polyline(outline, UiStyle.color("outline"), 6.0 * maxf(1.0, k), true)
	_gradient(pts, UiStyle.color("gold").lightened(0.35), UiStyle.color("amber").darkened(0.2), c.y - r, c.y + r * 0.6)
	for tip: Vector2 in [Vector2(-23, -12), Vector2(0, -18), Vector2(23, -12)]:
		_cv.draw_circle(c + tip * k, 3.2 * k, UiStyle.color("bone"))


# ---------------------------------------------------------------- building blocks

# Chamfered panel with drop shadow, gradient body, gloss, glowing accent rim,
# notches and optional bone claws.
func _panel(rect: Rect2, accent: Color, cut: float = 16.0, claws: bool = true, fill: Color = UiStyle.PANEL) -> void:
	var pts := _bevel(rect, cut)
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(0, 7))
	_cv.draw_colored_polygon(shadow, UiStyle.color("shadow"))
	if _lib_has(_frames, "panel"):
		_frames.call("panel", _cv, rect, accent, claws)
		if fill != UiStyle.PANEL:
			_cv.draw_colored_polygon(_bevel(rect.grow(-6), cut - 4), Color(fill, 0.35))
		if UiStyle.is_calm():
			return
		# Gloss over the upper half for a lit, wet surface.
		var sheen := _bevel(Rect2(rect.position + Vector2(8, 6), Vector2(rect.size.x - 16, rect.size.y * 0.4)), cut - 6)
		_gradient(sheen, Color(1, 1, 1, 0.09), Color(1, 1, 1, 0.0), rect.position.y + 6, rect.position.y + rect.size.y * 0.46)
		return
	_panel_glow(rect, accent, 0.2)
	var top := Color(fill.lightened(0.1), 0.94)
	var bottom := Color(fill.darkened(0.35), 0.96)
	_gradient(pts, top, bottom, rect.position.y, rect.end.y)
	# Faint cell texture keeps big panels from looking flat.
	var cell_seed := int(rect.position.x * 7 + rect.position.y * 13)
	for i in int(rect.size.x * rect.size.y / 1800.0):
		var h := (cell_seed + i * 7919) % 10007
		var p := rect.position + Vector2(cut * 0.5 + float(h % 997) / 997.0 * (rect.size.x - cut), 8 + float(h % 787) / 787.0 * (rect.size.y - 16))
		_cv.draw_arc(p, 3.0 + float(h % 5), 0, TAU, 10, Color(accent, 0.07), 1.2, true)
	var gloss := _bevel(Rect2(rect.position + Vector2(3, 3), Vector2(rect.size.x - 6, rect.size.y * 0.45)), cut - 2)
	_gradient(gloss, Color(1, 1, 1, 0.11), Color(1, 1, 1, 0.0), rect.position.y, rect.position.y + rect.size.y * 0.45)
	var ring := pts.duplicate()
	ring.append(pts[0])
	_cv.draw_polyline(ring, accent.darkened(0.25), 3.0, true)
	_cv.draw_polyline(PackedVector2Array([pts[0], pts[1]]), accent.lightened(0.35), 2.0, true)
	# Two notches in the lower rim.
	for t in [0.28, 0.72]:
		var n := Vector2(lerpf(rect.position.x + cut, rect.end.x - cut, t), rect.end.y)
		_cv.draw_colored_polygon(PackedVector2Array([n + Vector2(-7, 1), n + Vector2(7, 1), n + Vector2(0, -6)]), accent.darkened(0.25))
	if claws:
		_claw(rect.position + Vector2(cut * 0.3, rect.size.y * 0.72), Vector2(-1, 0.55), 15)
		_claw(Vector2(rect.end.x - cut * 0.3, rect.position.y + rect.size.y * 0.28), Vector2(1, -0.55), 15)


func _panel_glow(rect: Rect2, accent: Color, alpha: float) -> void:
	var ring := _bevel(rect.grow(2), 17.0)
	ring.append(ring[0])
	if UiStyle.is_calm():
		# Glow only as a small temporary layer: one thin halo stroke.
		_cv.draw_polyline(ring, Color(UiStyle.tone(accent), alpha), 5.0, true)
		return
	_cv.draw_polyline(ring, Color(accent, alpha), 8.0, true)
	_cv.draw_polyline(ring, Color(accent, alpha * 0.5), 14.0, true)


func _pill(rect: Rect2, accent: Color, fill: Color = UiStyle.PANEL_SOFT) -> void:
	var pts := _capsule(rect)
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(0, 4))
	_cv.draw_colored_polygon(shadow, UiStyle.color("shadow"))
	if _lib_has(_frames, "pill") and accent.a > 0.0:
		_frames.call("pill", _cv, rect, accent)
		if fill != UiStyle.PANEL_SOFT:
			_cv.draw_colored_polygon(_capsule(rect.grow(-3)), Color(fill, 0.45))
		return
	if fill.a > 0.0:
		_gradient(pts, Color(fill.lightened(0.12), maxf(fill.a, 0.9)), Color(fill.darkened(0.3), maxf(fill.a, 0.9)), rect.position.y, rect.end.y)
	if accent.a > 0.0:
		var ring := pts.duplicate()
		ring.append(pts[0])
		_cv.draw_polyline(ring, Color(accent, 0.85), 2.0, true)
		var r := rect.size.y * 0.5
		_cv.draw_line(rect.position + Vector2(r, 3), Vector2(rect.end.x - r, rect.position.y + 3), Color(1, 1, 1, 0.14), 2.0)


func _bar(rect: Rect2, fraction: float, color: Color) -> void:
	if _lib_has(_frames, "bar"):
		_frames.call("bar", _cv, rect, fraction, color)
		return
	var track := _capsule(rect)
	_cv.draw_colored_polygon(track, Color(UiStyle.color("outline"), 0.9))
	if fraction <= 0.0:
		return
	var fill_rect := Rect2(rect.position, Vector2(maxf(rect.size.y, rect.size.x * fraction), rect.size.y))
	var pts := _capsule(fill_rect)
	_gradient(pts, color.lightened(0.3), color.darkened(0.2), rect.position.y, rect.end.y)
	_cv.draw_line(fill_rect.position + Vector2(rect.size.y * 0.5, 2), Vector2(fill_rect.end.x - rect.size.y * 0.5, rect.position.y + 2), Color(1, 1, 1, 0.4), 1.5)


# Slanted segment bar; partially filled last segment.
func _segments(rect: Rect2, fraction: float, color: Color, count: int) -> void:
	if _lib_has(_frames, "bar"):
		_cv.draw_colored_polygon(_capsule(Rect2(rect.position + Vector2(0, 3), rect.size)), UiStyle.color("shadow"))
		_frames.call("bar", _cv, rect, fraction, color, count)
		return
	var track := _capsule(rect.grow(3))
	_cv.draw_colored_polygon(PackedVector2Array(Array(track).map(func(p): return p + Vector2(0, 3))), UiStyle.color("shadow"))
	_cv.draw_colored_polygon(track, Color(UiStyle.color("outline"), 0.95))
	var gap := 3.0
	var slant := rect.size.y * 0.3
	var w := (rect.size.x - gap * (count - 1)) / count
	for i in count:
		var x := rect.position.x + i * (w + gap)
		var fill := clampf(fraction * count - i, 0.0, 1.0)
		_cv.draw_colored_polygon(_slanted(Rect2(x, rect.position.y, w, rect.size.y), slant), Color(color, 0.14))
		if fill > 0.0:
			var seg := _slanted(Rect2(x, rect.position.y, w * fill, rect.size.y), slant * fill)
			_gradient(seg, color.lightened(0.35), color.darkened(0.25), rect.position.y, rect.end.y)
			_cv.draw_line(Vector2(x + slant, rect.position.y + 2), Vector2(x + w * fill, rect.position.y + 2), Color(1, 1, 1, 0.35), 1.5)


func _slanted(rect: Rect2, slant: float) -> PackedVector2Array:
	return PackedVector2Array([rect.position + Vector2(slant, 0), Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x - slant, rect.end.y), Vector2(rect.position.x, rect.end.y)])


func _bevel(rect: Rect2, cut: float) -> PackedVector2Array:
	var p := rect.position
	var e := rect.end
	cut = minf(cut, minf(rect.size.x, rect.size.y) * 0.5)
	return PackedVector2Array([p + Vector2(cut, 0), Vector2(e.x - cut, p.y), Vector2(e.x, p.y + cut), Vector2(e.x, e.y - cut), Vector2(e.x - cut, e.y), Vector2(p.x + cut, e.y), Vector2(p.x, e.y - cut), Vector2(p.x, p.y + cut)])


func _capsule(rect: Rect2) -> PackedVector2Array:
	if UiStyle.is_calm():
		return _bevel(rect, minf(12.0, rect.size.y * 0.3))
	var r := rect.size.y * 0.5
	var pts := PackedVector2Array()
	for i in 9:
		var a := -PI * 0.5 + PI * i / 8.0
		pts.append(Vector2(rect.end.x - r, rect.position.y + r) + Vector2(cos(a), sin(a)) * r)
	for i in 9:
		var a := PI * 0.5 + PI * i / 8.0
		pts.append(Vector2(rect.position.x + r, rect.position.y + r) + Vector2(cos(a), sin(a)) * r)
	return pts


func _gradient(pts: PackedVector2Array, top: Color, bottom: Color, y0: float, y1: float) -> void:
	var colors := PackedColorArray()
	for p in pts:
		colors.append(top.lerp(bottom, clampf((p.y - y0) / maxf(1.0, y1 - y0), 0.0, 1.0)))
	_cv.draw_polygon(pts, colors)


func _claw(base: Vector2, direction: Vector2, length: float) -> void:
	if UiStyle.is_calm():
		return
	var d := direction.normalized()
	var side := Vector2(-d.y, d.x)
	var tip := base + d * length + side * length * 0.35
	var pts := PackedVector2Array([base + side * 5, base + d * length * 0.55 + side * 4, tip, base + d * length * 0.5 - side * 2, base - side * 5])
	var outline := PackedVector2Array()
	for p in pts:
		outline.append(p + (p - base).normalized() * 1.5)
	_cv.draw_colored_polygon(outline, UiStyle.color("outline"))
	_cv.draw_colored_polygon(pts, UiStyle.color("bone"))


# Calm socket: octagonal petrol plate with one accent stroke (V2 kit).
func _plate(c: Vector2, r: float, accent: Color) -> void:
	var pts := _bevel(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), r * 0.42)
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(0, 4))
	_cv.draw_colored_polygon(shadow, UiStyle.color("shadow"))
	_cv.draw_colored_polygon(pts, Color(UiStyle.CALM_BG, 0.96))
	pts.append(pts[0])
	_cv.draw_polyline(pts, accent, 3.0, true)


func _diamond(c: Vector2, r: float, color: Color, outline: bool = true) -> void:
	if outline:
		_cv.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r - 2), c + Vector2(r * 0.9 + 2, 0), c + Vector2(0, r + 2), c + Vector2(-r * 0.9 - 2, 0)]), UiStyle.color("outline"))
	_cv.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.9, 0), c + Vector2(0, r), c + Vector2(-r * 0.9, 0)]), color)
	_cv.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.9, 0), c + Vector2(0, 0)]), Color(1, 1, 1, 0.3))


func _icon(ids: Array, rect: Rect2, tint: Color) -> bool:
	if not _lib_has(_icons, "has") or not _lib_has(_icons, "draw"):
		return false
	for id in ids:
		if _icons.call("has", id):
			_icons.call("draw", _cv, id, rect, tint)
			return true
	return false


func _text_width(value: String, font_size: int) -> float:
	return UiStyle.body_font().get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


func _label(value: String, at: Vector2, color: Color) -> void:
	UiStyle.text(_cv, value, at, LABEL, color, false, 5, UiStyle.body_font())


func _ease(t: float) -> float:
	# Quick swell, slow settle.
	return sin(clampf(t, 0.0, 1.0) * PI * 0.5) * t


# ---------------------------------------------------------------- fallback icons

func _fb_head(center: Vector2, r: float, color: Color) -> void:
	var s := Vector2(r, r)
	var outline := PackedVector2Array()
	for v in [Vector2(-0.95, 0.15), Vector2(-0.85, -0.4), Vector2(-0.5, -0.72), Vector2(-0.05, -0.82), Vector2(0.45, -0.66), Vector2(0.9, -0.42), Vector2(1.05, -0.2), Vector2(1.0, -0.08), Vector2(0.12, 0.06), Vector2(0.86, 0.3), Vector2(0.9, 0.42), Vector2(0.6, 0.6), Vector2(0.05, 0.64), Vector2(-0.5, 0.62), Vector2(-0.86, 0.45)]:
		outline.append(center + v * s)
	var shadow := PackedVector2Array()
	for p in outline:
		shadow.append(p + Vector2(0, 4))
	_cv.draw_colored_polygon(shadow, UiStyle.color("shadow"))
	for spike in [[Vector2(-0.93, -0.05), Vector2(-0.8, -0.48), Vector2(-1.28, -0.5)], [Vector2(-0.72, -0.56), Vector2(-0.34, -0.78), Vector2(-0.78, -1.02)], [Vector2(-0.22, -0.8), Vector2(0.14, -0.78), Vector2(-0.2, -1.1)]]:
		_cv.draw_colored_polygon(PackedVector2Array([center + spike[0] * s, center + spike[1] * s, center + spike[2] * s]), color.darkened(0.25))
	_gradient(outline, color.lightened(0.2), color.darkened(0.25), center.y - r, center.y + r * 0.7)
	for t in [0.18, 0.46, 0.74]:
		var a: Vector2 = Vector2(0.95, -0.07).lerp(Vector2(0.2, 0.05), t)
		_cv.draw_colored_polygon(PackedVector2Array([center + (a + Vector2(-0.08, 0)) * s, center + (a + Vector2(0.08, 0)) * s, center + (a + Vector2(0, 0.2)) * s]), UiStyle.color("bone"))
	for t in [0.3, 0.65]:
		var b: Vector2 = Vector2(0.2, 0.1).lerp(Vector2(0.84, 0.31), t)
		_cv.draw_colored_polygon(PackedVector2Array([center + (b + Vector2(-0.07, 0.02)) * s, center + (b + Vector2(0.07, 0.02)) * s, center + (b + Vector2(0, -0.17)) * s]), UiStyle.color("bone"))
	_cv.draw_circle(center + Vector2(0.36, -0.36) * s, r * 0.13, UiStyle.color("outline"))
	_cv.draw_circle(center + Vector2(0.39, -0.39) * s, r * 0.05, UiStyle.color("gold"))


func _fb_helix(center: Vector2, height: float, color: Color) -> void:
	var a := PackedVector2Array()
	var b := PackedVector2Array()
	var steps := 18
	for i in steps + 1:
		var t := float(i) / steps
		var y := center.y - height * 0.5 + height * t
		var phase := t * TAU * 1.25
		a.append(Vector2(center.x + sin(phase) * 11, y))
		b.append(Vector2(center.x + sin(phase + PI) * 11, y))
		if i % 3 == 1:
			_cv.draw_line(a[i], b[i], Color(color, 0.55), 2)
	_cv.draw_polyline(a, UiStyle.color("outline"), 7, true)
	_cv.draw_polyline(b, UiStyle.color("outline"), 7, true)
	_cv.draw_polyline(a, color, 4, true)
	_cv.draw_polyline(b, color.darkened(0.25), 4, true)


func _fb_skull(center: Vector2, r: float, color: Color) -> void:
	_cv.draw_circle(center + Vector2(0, -0.18 * r), 0.82 * r + 2, UiStyle.color("outline"))
	_cv.draw_circle(center + Vector2(0, -0.18 * r), 0.82 * r, color)
	_cv.draw_rect(Rect2(center + Vector2(-0.46, 0.25) * r, Vector2(0.92, 0.55) * r), color)
	for side in [-1.0, 1.0]:
		_cv.draw_circle(center + Vector2(side * 0.32, -0.16) * r, 0.23 * r, UiStyle.color("outline"))
	_cv.draw_colored_polygon(PackedVector2Array([center + Vector2(0, 0.12) * r, center + Vector2(0.1, 0.32) * r, center + Vector2(-0.1, 0.32) * r]), UiStyle.color("outline"))
	for i in 3:
		var x := (-0.2 + i * 0.2) * r
		_cv.draw_line(center + Vector2(x, 0.5 * r), center + Vector2(x, 0.8 * r), UiStyle.color("outline"), maxf(1.5, r * 0.08))


func _fb_crown(c: Vector2, r: float, color: Color) -> void:
	var k := r / 20.0
	var pts := PackedVector2Array([c + Vector2(-20, 12) * k, c + Vector2(-22, -12) * k, c + Vector2(-10, 0) * k, c + Vector2(0, -17) * k, c + Vector2(10, 0) * k, c + Vector2(22, -12) * k, c + Vector2(20, 12) * k])
	_gradient(pts, color.lightened(0.3), color.darkened(0.3), c.y - r, c.y + r * 0.6)


func _fb_gem(c: Vector2, r: float) -> void:
	_cv.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.8, 0), c + Vector2(0, r), c + Vector2(-r * 0.8, 0)]), UiStyle.color("violet"))
	_cv.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.55), c + Vector2(r * 0.42, 0), c + Vector2(0, r * 0.55), c + Vector2(-r * 0.42, 0)]), UiStyle.color("amber"))
	_cv.draw_circle(c + Vector2(-r * 0.12, -r * 0.2), r * 0.12, Color(1, 1, 1, 0.7))


var _lib_methods: Dictionary = {}

func _lib_has(script: Script, method: String) -> bool:
	if script == null:
		return false
	if not _lib_methods.has(script):
		var names := {}
		for entry in script.get_script_method_list():
			names[entry.name] = true
		_lib_methods[script] = names
	return _lib_methods[script].has(method)
