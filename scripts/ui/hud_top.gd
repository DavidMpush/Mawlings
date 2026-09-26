extends Control

# Stage 04 · HUD_TOP. Replaces legacy "top" and "badges" of touch_controls.gd:
# top bar (swarm, run time + danger, DNA/level, pause), context chips, boss bar,
# corpse/biomass hints, Alpha-Kern chip and attack-form medallions.
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
var _corpse_y := 0.0
var _biomass_y := 0.0
var _skull_c := Vector2.ZERO
var _gem_c := Vector2.INF
var _bar_rects: Array = [Rect2(), Rect2(), Rect2(), Rect2()]   # swarm, time, dna, pause
var _chips_bottom := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_libs(0.0)
	# Order = drawing order of the original single pass.
	for spec in [
		["backdrop", false, Rect2(0, 0, 0, 200)],
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
		["hints", true, Rect2()],
		["medals", true, Rect2()],
	]:
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
	match part:
		"backdrop":
			_draw_backdrop()
		"swarm", "time", "time_glow", "time_skull", "dna", "pause":
			_draw_top_bar()
		"chips", "alpha_glow", "alpha_top":
			var pressure_rect := _draw_pressure_chip(_row_y)
			_draw_threat_chips(_row_y, pressure_rect.position.x - GAP)
			_draw_alpha_chip(_row_y, pressure_rect.end.x + GAP)
		"boss":
			if _boss_y >= 0.0:
				_draw_boss_bar(_boss_y)
		"hints":
			_draw_corpse_hint(_corpse_y)
			_draw_biomass(_biomass_y)
		"medals":
			if not bool(_hud_value("extinct", false)):
				_draw_medallions(_right_y + 16.0)


func _process(delta: float) -> void:
	_advance(delta)
	if get_parent() == null:
		return
	_layout()
	_refresh_layers()


# Same rows as the original single pass; nothing is drawn here.
func _layout() -> void:
	_paint = ""
	_row_y = _draw_top_bar() + 12.0
	_pressure_rect = _draw_pressure_chip(_row_y)
	var left_y := _draw_threat_chips(_row_y, _pressure_rect.position.x - GAP)
	_right_y = _draw_alpha_chip(_row_y, _pressure_rect.end.x + GAP)
	var y := maxf(left_y, _pressure_rect.end.y + 12.0)
	_chips_bottom = maxf(y, _right_y)
	_boss_y = -1.0
	if float(_hud_value("boss_health", 0.0)) > 0.0:
		_boss_y = y
		y = _draw_boss_bar(y) + 12.0
	_corpse_y = y
	_biomass_y = _draw_corpse_hint(y)


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
	_region("hints", Rect2(0, _corpse_y - 16, size.x, 130))
	_region("medals", Rect2(size.x - 110, _right_y, 110, maxf(1.0, size.y - _right_y)))
	_layers.backdrop.refresh(size)
	_layers.swarm.refresh([pop, _pop_delta, _pop_pulse, size])
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
	var bank: float = _hud_value("biomass_bank", 0.0)
	_layers.hints.refresh([_hud_value("nearest_corpse", ""), int(round(bank * 200.0)), _corpse_y, _biomass_y])
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
	return UiStyle.AMBER.lerp(UiStyle.DANGER, _danger_fraction())


# ---------------------------------------------------------------- drawing

func _draw_backdrop() -> void:
	# Soft dark falloff behind the top bar so it reads over bright ground.
	var h := 190.0
	var top := Color(UiStyle.OUTLINE, 0.62)
	var bottom := Color(UiStyle.OUTLINE, 0.0)
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
	var pulse_color := UiStyle.TOXIC if gain else UiStyle.DANGER
	var accent := UiStyle.EMBER.lerp(pulse_color, _pop_pulse * 0.8)
	_panel(rect, accent, 16.0, false)
	var head_c := rect.position + Vector2(52, 52)
	if _pop_pulse > 0.0:
		_cv.draw_circle(head_c, 40 + 8 * _pop_pulse, Color(pulse_color, 0.25 * _pop_pulse))
	if not _icon(["mawling_head_color", "mawling_head"], Rect2(head_c - Vector2(40, 40), Vector2(80, 80)), Color.WHITE):
		_fb_head(head_c, 36, UiStyle.EMBER)
	var x := rect.position.x + 102
	_label("SCHWARM", Vector2(x, rect.position.y + 28), UiStyle.EMBER_GLOW)
	# Big number grows and tints on change, then settles back.
	var num_size := roundf(54 + 8 * _ease(_pop_pulse))
	var num_color := Color.WHITE.lerp(pulse_color.lightened(0.25), _pop_pulse)
	var w := UiStyle.text_px(_cv, "%d" % pop, Vector2(x - 2, rect.position.y + 84), num_size, num_color, false, 9)
	UiStyle.text(_cv, "/ %d" % MAX_POPULATION, Vector2(x + w + 6, rect.position.y + 82), LABEL, UiStyle.TEXT_DIM, false, 5, UiStyle.body_font())
	# Floating delta ("+7" / "−12") rises out of the number.
	if _pop_pulse > 0.0 and _pop_delta != 0:
		var rise := (1.0 - _pop_pulse) * 12.0
		var sign_text := "+" if gain else "−"
		UiStyle.text(_cv, "%s%d" % [sign_text, absi(_pop_delta)], Vector2(rect.end.x - 30, rect.position.y + 44 - rise), UiStyle.SIZE_BODY, Color(pulse_color.lightened(0.2), minf(1.0, _pop_pulse * 1.6)), true, 6)
	# Population fill along the lower rim.
	var fill := clampf(float(pop) / MAX_POPULATION, 0.0, 1.0)
	_bar(Rect2(x, rect.end.y - 10, rect.end.x - x - 16, 6), fill, UiStyle.EMBER)


func _draw_time(rect: Rect2) -> void:
	var fraction := _danger_fraction()
	var color := _danger_color()
	var hot := smoothstep(0.55, 0.9, fraction)
	var bar := Rect2(rect.position.x + 18, rect.position.y + 70, rect.size.x - 78, 18)
	var skull_c := Vector2(rect.end.x - 32, bar.get_center().y - 2)
	if _paint == "time":
		_panel(rect, UiStyle.PANEL_EDGE.lerp(color, 0.35 + 0.65 * fraction), 18.0, false)
		var elapsed: float = _hud_value("elapsed", 0.0)
		var cx := rect.get_center().x
		UiStyle.text(_cv, "%02d:%02d" % [int(elapsed) / 60, int(elapsed) % 60], Vector2(cx, rect.position.y + 58), 50, UiStyle.TEXT, true, 8)
		# Danger bar in segments, skull at the end.
		_segments(bar, maxf(0.05, fraction), color, 10)
	elif _paint == "time_glow":
		# Drawn at rest size and full alpha; the layer's scale/modulate breathe it
		# (radius 22 + 6 * pulse, alpha 0.22 + 0.25 * pulse).
		if hot > 0.0:
			_cv.draw_circle(skull_c, 22, UiStyle.DANGER)
	elif _paint == "time_skull":
		if not _icon(["skull"], Rect2(skull_c - Vector2(24, 24), Vector2(48, 48)), Color.WHITE.lerp(UiStyle.AMBER, 0.5 * (1.0 - fraction))):
			_fb_skull(skull_c, 17, color)


func _draw_dna(rect: Rect2) -> void:
	var evo := _evolution()
	var level := _level()
	var dna := 0 if evo == null else int(evo.get("dna"))
	var needed := 20 if evo == null else int(evo.threshold())
	var maxed := evo != null and bool(evo.complete())
	_panel(rect, UiStyle.CYAN.lerp(Color.WHITE, _level_pulse * 0.5), 16.0, false)
	var helix_c := rect.position + Vector2(30, 50)
	if _level_pulse > 0.0:
		_cv.draw_circle(helix_c, 30 + 10 * _level_pulse, Color(UiStyle.CYAN, 0.3 * _level_pulse))
	if not _icon(["dna"], Rect2(helix_c - Vector2(34, 34), Vector2(68, 68)), Color.WHITE):
		_fb_helix(helix_c, 62, UiStyle.CYAN)
	var x := rect.position.x + 60
	var lv_size := roundf(38 + 8 * _ease(_level_pulse))
	UiStyle.text_px(_cv, "LV %d" % level, Vector2(x, rect.position.y + 48), lv_size, Color.WHITE.lerp(UiStyle.CYAN.lightened(0.4), _level_pulse), false, 8)
	_bar(Rect2(x, rect.position.y + 58, rect.end.x - x - 14, 12), 1.0 if maxed else clampf(float(dna) / maxf(1.0, needed), 0.0, 1.0), UiStyle.CYAN)
	var dna_text := "MAX" if maxed else "%d/%d DNA" % [dna, needed]
	if _text_width(dna_text, LABEL) > rect.end.x - x - 8.0:
		dna_text = "%d/%d" % [dna, needed]
	UiStyle.text(_cv, dna_text, Vector2(x, rect.position.y + 92), LABEL, UiStyle.CYAN.lightened(0.45), false, 5, UiStyle.body_font())


func _draw_pause(rect: Rect2) -> void:
	if _lib_has(_frames, "button"):
		_frames.call("button", _cv, rect, "secondary", false)
	else:
		_panel(rect, UiStyle.BONE, 18.0, false)
	var c := rect.get_center()
	if not _icon(["pause"], Rect2(c - Vector2(30, 30), Vector2(60, 60)), Color.WHITE):
		for dx in [-15.0, 5.0]:
			var bar := Rect2(c + Vector2(dx, -19), Vector2(10, 38))
			_cv.draw_rect(Rect2(bar.position + Vector2(0, 3), bar.size), UiStyle.SHADOW)
			_cv.draw_rect(bar, UiStyle.BONE)
			_cv.draw_rect(Rect2(bar.position, Vector2(4, bar.size.y)), Color(1, 1, 1, 0.35))


# Pressure multiplier below the run time; returns its rect.
func _draw_pressure_chip(y: float) -> Rect2:
	var text := _pressure_text()
	var color := _danger_color()
	var w := _text_width(text, LABEL) + 40
	var rect := Rect2(size.x * 0.5 - w * 0.5, y, w, ROW_H - 4)
	if _paint != "chips":
		return rect
	var hot := smoothstep(0.55, 0.9, _danger_fraction())
	if hot > 0.0:
		_pill(rect.grow(4), Color(UiStyle.DANGER, 0.0), Color(UiStyle.DANGER, hot * (0.2 + 0.15 * sin(_time * 6.0))))
	_pill(rect, color, UiStyle.PANEL_SOFT.lerp(Color(UiStyle.DANGER, 0.8), hot * 0.35))
	UiStyle.text(_cv, text, Vector2(rect.get_center().x, rect.position.y + 26), LABEL, color.lerp(Color.WHITE, 0.5 + 0.4 * hot), true, 5, UiStyle.body_font())
	return rect


# Threat chips from the left; wraps below when the row runs out. Returns next y.
func _draw_threat_chips(y: float, right_limit: float) -> float:
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
	var x := 16.0
	for entry in entries:
		var w := _text_width(entry[0], LABEL) + 52
		if x > 16.0 and x + w > right_limit:
			x = 16.0
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
			_pill(rect, UiStyle.VIOLET, Color(UiStyle.PANEL.darkened(0.2), 0.92).lerp(UiStyle.VIOLET, 0.12))
		"alpha_glow":
			# Full alpha here; the layer's modulate pulses it (0.2 + 0.15 * sin).
			_cv.draw_circle(gem_c, 16, UiStyle.VIOLET)
		"alpha_top":
			if not _icon(["alpha_core"], Rect2(gem_c - Vector2(18, 18), Vector2(36, 36)), Color.WHITE):
				_fb_gem(gem_c, 12)
			UiStyle.text(_cv, text, rect.position + Vector2(44, 26), LABEL, UiStyle.GOLD.lightened(0.3), false, 5, UiStyle.body_font())
	return y + ROW_H + 4


# Boss bar: crown medallion, name, segmented health, VERWUNDBAR tag. Returns bottom.
func _draw_boss_bar(y: float) -> float:
	var health: float = _hud_value("boss_health", 0.0)
	var max_health: float = maxf(1.0, _hud_value("boss_max_health", 1.0))
	var vulnerable: bool = _hud_value("boss_vulnerable", false)
	var blink := 0.5 + 0.5 * sin(_time * 7.0)
	var accent := UiStyle.GOLD if vulnerable else UiStyle.EMBER
	var w := minf(620.0, size.x - 2 * 110.0)
	var rect := Rect2(size.x * 0.5 - w * 0.5, y, w, 84)
	if _paint != "boss":
		return rect.end.y
	if vulnerable:
		_panel_glow(rect, UiStyle.GOLD, 0.25 + 0.25 * blink)
	_panel(rect, accent, 16.0, true, UiStyle.PANEL.lerp(Color(UiStyle.DANGER, 0.9), 0.12))
	var crown_c := rect.position + Vector2(48, 42)
	_cv.draw_circle(crown_c + Vector2(0, 4), 31, UiStyle.SHADOW)
	_cv.draw_circle(crown_c, 31, UiStyle.PANEL.darkened(0.3))
	_cv.draw_arc(crown_c, 30, 0, TAU, 40, accent, 3.0, true)
	if not _icon(["crown"], Rect2(crown_c - Vector2(27, 27), Vector2(54, 54)), Color.WHITE):
		_fb_crown(crown_c, 20, UiStyle.GOLD)
	var x := rect.position.x + 92
	UiStyle.text(_cv, "BOG KING", Vector2(x, rect.position.y + 36), 30, UiStyle.TEXT, false, 7)
	if vulnerable:
		var tag := "VERWUNDBAR"
		var tw := _text_width(tag, LABEL) + 28
		var tag_rect := Rect2(rect.end.x - 18 - tw, rect.position.y + 10, tw, 32)
		_pill(tag_rect, UiStyle.GOLD, UiStyle.GOLD.darkened(0.55).lerp(UiStyle.GOLD.darkened(0.3), blink))
		UiStyle.text(_cv, tag, Vector2(tag_rect.get_center().x, tag_rect.position.y + 24), LABEL, Color.WHITE, true, 5, UiStyle.body_font())
	var bar := Rect2(x, rect.position.y + 50, rect.end.x - x - 20, 20)
	_segments(bar, clampf(health / max_health, 0.0, 1.0), UiStyle.GOLD if vulnerable else UiStyle.DANGER, 14)
	return rect.end.y


func _draw_corpse_hint(y: float) -> float:
	var hint: String = _hud_value("nearest_corpse", "")
	if hint == "":
		return y
	var parts := hint.split("·")
	var text := parts[0].strip_edges()
	var direction := parts[1].strip_edges() if parts.size() > 1 else ""
	var w := _text_width(text, LABEL) + 104
	var rect := Rect2(16, y, w, 44)
	if _paint != "hints":
		return rect.end.y + 8
	_pill(rect, UiStyle.AMBER)
	var drop_c := rect.position + Vector2(24, 24)
	_fb_drop(drop_c + Vector2(0, 2), 11, UiStyle.AMBER)
	UiStyle.text(_cv, text, rect.position + Vector2(44, 30), LABEL, UiStyle.BONE, false, 5, UiStyle.body_font())
	_direction_mark(rect.position + Vector2(rect.size.x - 30, 22), direction, UiStyle.AMBER)
	return rect.end.y + 8


func _draw_biomass(y: float) -> void:
	var bank: float = _hud_value("biomass_bank", 0.0)
	if bank <= 0.01:
		return
	var text := "BIOMASSE %.1f / 2" % bank
	var w := _text_width(text, LABEL) + 60
	var rect := Rect2(16, y, w, 44)
	_pill(rect, UiStyle.AMBER)
	var drop_c := rect.position + Vector2(24, 22)
	_fb_drop(drop_c + Vector2(0, 2), 10, UiStyle.AMBER)
	UiStyle.text(_cv, text, rect.position + Vector2(44, 26), LABEL, UiStyle.AMBER.lightened(0.3), false, 5, UiStyle.body_font())
	_bar(Rect2(rect.position.x + 44, rect.end.y - 11, w - 64, 5), clampf(bank / 2.0, 0.0, 1.0), UiStyle.AMBER)


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
		var accent: Color = hud._mutation_color(id) if hud != null and hud.has_method("_mutation_color") else UiStyle.EMBER
		var ring := UiStyle.VIOLET if evolved else accent
		_cv.draw_circle(c + Vector2(0, 5), r + 2, UiStyle.SHADOW)
		_cv.draw_circle(c, r + 6, Color(ring, 0.18))
		_cv.draw_circle(c, r, UiStyle.PANEL.darkened(0.25))
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
				_diamond(c + Vector2(-16 + i * 16, r + 10), 6.5, accent if i < rank else Color(UiStyle.PANEL_EDGE, 0.9), true)
		c.y += r * 2 + 30


# ---------------------------------------------------------------- building blocks

# Chamfered panel with drop shadow, gradient body, gloss, glowing accent rim,
# notches and optional bone claws.
func _panel(rect: Rect2, accent: Color, cut: float = 16.0, claws: bool = true, fill: Color = UiStyle.PANEL) -> void:
	var pts := _bevel(rect, cut)
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(0, 7))
	_cv.draw_colored_polygon(shadow, UiStyle.SHADOW)
	if _lib_has(_frames, "panel"):
		_frames.call("panel", _cv, rect, accent, claws)
		if fill != UiStyle.PANEL:
			_cv.draw_colored_polygon(_bevel(rect.grow(-6), cut - 4), Color(fill, 0.35))
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
	_cv.draw_polyline(ring, Color(accent, alpha), 8.0, true)
	_cv.draw_polyline(ring, Color(accent, alpha * 0.5), 14.0, true)


func _pill(rect: Rect2, accent: Color, fill: Color = UiStyle.PANEL_SOFT) -> void:
	var pts := _capsule(rect)
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(0, 4))
	_cv.draw_colored_polygon(shadow, UiStyle.SHADOW)
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
	_cv.draw_colored_polygon(track, Color(UiStyle.OUTLINE, 0.9))
	if fraction <= 0.0:
		return
	var fill_rect := Rect2(rect.position, Vector2(maxf(rect.size.y, rect.size.x * fraction), rect.size.y))
	var pts := _capsule(fill_rect)
	_gradient(pts, color.lightened(0.3), color.darkened(0.2), rect.position.y, rect.end.y)
	_cv.draw_line(fill_rect.position + Vector2(rect.size.y * 0.5, 2), Vector2(fill_rect.end.x - rect.size.y * 0.5, rect.position.y + 2), Color(1, 1, 1, 0.4), 1.5)


# Slanted segment bar; partially filled last segment.
func _segments(rect: Rect2, fraction: float, color: Color, count: int) -> void:
	if _lib_has(_frames, "bar"):
		_cv.draw_colored_polygon(_capsule(Rect2(rect.position + Vector2(0, 3), rect.size)), UiStyle.SHADOW)
		_frames.call("bar", _cv, rect, fraction, color, count)
		return
	var track := _capsule(rect.grow(3))
	_cv.draw_colored_polygon(PackedVector2Array(Array(track).map(func(p): return p + Vector2(0, 3))), UiStyle.SHADOW)
	_cv.draw_colored_polygon(track, Color(UiStyle.OUTLINE, 0.95))
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
	var d := direction.normalized()
	var side := Vector2(-d.y, d.x)
	var tip := base + d * length + side * length * 0.35
	var pts := PackedVector2Array([base + side * 5, base + d * length * 0.55 + side * 4, tip, base + d * length * 0.5 - side * 2, base - side * 5])
	var outline := PackedVector2Array()
	for p in pts:
		outline.append(p + (p - base).normalized() * 1.5)
	_cv.draw_colored_polygon(outline, UiStyle.OUTLINE)
	_cv.draw_colored_polygon(pts, UiStyle.BONE)


func _diamond(c: Vector2, r: float, color: Color, outline: bool = true) -> void:
	if outline:
		_cv.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r - 2), c + Vector2(r * 0.9 + 2, 0), c + Vector2(0, r + 2), c + Vector2(-r * 0.9 - 2, 0)]), UiStyle.OUTLINE)
	_cv.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.9, 0), c + Vector2(0, r), c + Vector2(-r * 0.9, 0)]), color)
	_cv.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.9, 0), c + Vector2(0, 0)]), Color(1, 1, 1, 0.3))


func _direction_mark(c: Vector2, direction: String, color: Color) -> void:
	if direction == "" or direction == "hier":
		_cv.draw_arc(c, 9, 0, TAU, 20, color, 3.0, true)
		_cv.draw_circle(c, 3.5, color)
		return
	var dir := Vector2.RIGHT
	match direction:
		"oben":
			dir = Vector2.UP
		"unten":
			dir = Vector2.DOWN
		"links":
			dir = Vector2.LEFT
	var side := Vector2(-dir.y, dir.x)
	var tip := c + dir * 12
	var arrow := PackedVector2Array([tip, c - dir * 6 + side * 11, c - dir * 1 , c - dir * 6 - side * 11])
	var shadow := PackedVector2Array()
	for p in arrow:
		shadow.append(p + Vector2(0, 2))
	_cv.draw_colored_polygon(shadow, UiStyle.OUTLINE)
	_cv.draw_colored_polygon(arrow, color)


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
	_cv.draw_colored_polygon(shadow, UiStyle.SHADOW)
	for spike in [[Vector2(-0.93, -0.05), Vector2(-0.8, -0.48), Vector2(-1.28, -0.5)], [Vector2(-0.72, -0.56), Vector2(-0.34, -0.78), Vector2(-0.78, -1.02)], [Vector2(-0.22, -0.8), Vector2(0.14, -0.78), Vector2(-0.2, -1.1)]]:
		_cv.draw_colored_polygon(PackedVector2Array([center + spike[0] * s, center + spike[1] * s, center + spike[2] * s]), color.darkened(0.25))
	_gradient(outline, color.lightened(0.2), color.darkened(0.25), center.y - r, center.y + r * 0.7)
	for t in [0.18, 0.46, 0.74]:
		var a: Vector2 = Vector2(0.95, -0.07).lerp(Vector2(0.2, 0.05), t)
		_cv.draw_colored_polygon(PackedVector2Array([center + (a + Vector2(-0.08, 0)) * s, center + (a + Vector2(0.08, 0)) * s, center + (a + Vector2(0, 0.2)) * s]), UiStyle.BONE)
	for t in [0.3, 0.65]:
		var b: Vector2 = Vector2(0.2, 0.1).lerp(Vector2(0.84, 0.31), t)
		_cv.draw_colored_polygon(PackedVector2Array([center + (b + Vector2(-0.07, 0.02)) * s, center + (b + Vector2(0.07, 0.02)) * s, center + (b + Vector2(0, -0.17)) * s]), UiStyle.BONE)
	_cv.draw_circle(center + Vector2(0.36, -0.36) * s, r * 0.13, UiStyle.OUTLINE)
	_cv.draw_circle(center + Vector2(0.39, -0.39) * s, r * 0.05, UiStyle.GOLD)


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
	_cv.draw_polyline(a, UiStyle.OUTLINE, 7, true)
	_cv.draw_polyline(b, UiStyle.OUTLINE, 7, true)
	_cv.draw_polyline(a, color, 4, true)
	_cv.draw_polyline(b, color.darkened(0.25), 4, true)


func _fb_skull(center: Vector2, r: float, color: Color) -> void:
	_cv.draw_circle(center + Vector2(0, -0.18 * r), 0.82 * r + 2, UiStyle.OUTLINE)
	_cv.draw_circle(center + Vector2(0, -0.18 * r), 0.82 * r, color)
	_cv.draw_rect(Rect2(center + Vector2(-0.46, 0.25) * r, Vector2(0.92, 0.55) * r), color)
	for side in [-1.0, 1.0]:
		_cv.draw_circle(center + Vector2(side * 0.32, -0.16) * r, 0.23 * r, UiStyle.OUTLINE)
	_cv.draw_colored_polygon(PackedVector2Array([center + Vector2(0, 0.12) * r, center + Vector2(0.1, 0.32) * r, center + Vector2(-0.1, 0.32) * r]), UiStyle.OUTLINE)
	for i in 3:
		var x := (-0.2 + i * 0.2) * r
		_cv.draw_line(center + Vector2(x, 0.5 * r), center + Vector2(x, 0.8 * r), UiStyle.OUTLINE, maxf(1.5, r * 0.08))


func _fb_crown(c: Vector2, r: float, color: Color) -> void:
	var k := r / 20.0
	var pts := PackedVector2Array([c + Vector2(-20, 12) * k, c + Vector2(-22, -12) * k, c + Vector2(-10, 0) * k, c + Vector2(0, -17) * k, c + Vector2(10, 0) * k, c + Vector2(22, -12) * k, c + Vector2(20, 12) * k])
	_gradient(pts, color.lightened(0.3), color.darkened(0.3), c.y - r, c.y + r * 0.6)


func _fb_gem(c: Vector2, r: float) -> void:
	_cv.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.8, 0), c + Vector2(0, r), c + Vector2(-r * 0.8, 0)]), UiStyle.VIOLET)
	_cv.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.55), c + Vector2(r * 0.42, 0), c + Vector2(0, r * 0.55), c + Vector2(-r * 0.42, 0)]), UiStyle.AMBER)
	_cv.draw_circle(c + Vector2(-r * 0.12, -r * 0.2), r * 0.12, Color(1, 1, 1, 0.7))


func _fb_drop(c: Vector2, r: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 17:
		var angle := -PI * 0.2 + (PI * 1.4) * i / 16.0
		points.append(c + Vector2(cos(angle), sin(angle)) * r + Vector2(0, r * 0.25))
	points.append(c + Vector2(0, -r * 1.35))
	_gradient(points, color.lightened(0.3), color.darkened(0.2), c.y - r, c.y + r)
	_cv.draw_circle(c + Vector2(-r * 0.3, 0), r * 0.2, Color(1, 1, 1, 0.45))


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
