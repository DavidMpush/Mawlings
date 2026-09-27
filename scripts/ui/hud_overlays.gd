extends Control

# Stage 04 OVERLAYS: result (extinction) and pause screens, evolution banner,
# loss feedback and the off-screen boss pointer. Replaces the legacy keys
# result, banner, feedback and pointer of touch_controls.gd. Reads every value
# from the parent HUD; input stays in touch_controls.gd, buttons are drawn on
# its _action_rect() / _hub_rect() so the hit areas match.

#
# Stage 07 (performance): repaints only while something moves (popups, loss
# number, king moment, boss pointer, banner, screen intros) or when the shown
# values change; idle it draws nothing and costs nothing. Zooming text is
# scaled from a fixed palette size (UiStyle.text_px) instead of rasterising a
# new font size per frame.

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const ICONS_PATH := "res://scripts/ui/ui_icons.gd"
const FRAMES_PATH := "res://scripts/ui/ui_frames.gd"

const KILL_TYPES := [
	["prey", "BEUTE"], ["hunter", "JÄGER"], ["skitter", "SKITTER"], ["leaper", "LEAPER"], ["boss", "BOG KING"],
]
const EVOLVE_TIME := 3.0      # hunt_world sets evolve_flash to this on evolution
const LOSS_WINDOW := 0.9      # hits closer than this are bundled into one number
const KING_TIME := 2.4        # real seconds of the "KÖNIG VERSCHLUNGEN" moment
const LABEL := 22             # stage 06: smallest text on these overlays (900 grid)
const SHORT_LABEL := {"MAX. SCHWARM": "PEAK"}
const LOSS_Y := -250.0        # loss number sits fixed above the swarm (screen centre + this)
const LOSS_ZONE := Vector2(360, 140)  # reserved while it shows; kill popups keep out

var _icons: Script
var _frames: Script
var _icon_ids: Dictionary = {}
var _frame_methods: Dictionary = {}

var _result_time := -1.0
var _pause_time := -1.0
var _loss_total := 0
var _loss_age := 99.0
var _last_feedback := 0.0
var _clock := 0.0
# Königsmoment: HuntWorld counts Bog King kills in the HUD meta "king_moments".
var _king_seen := 0
var _king_time := -1.0
var _last_key: Variant = null
# Etappe 09: milestone banner (HUD "milestone", else the swarm's own count) and
# the last-animal vignette.
const MILESTONE_TIME := 1.9   # real seconds
var _milestone_seen := 0
var _milestone := 0
var _milestone_time := -1.0
var _swarm_node: Node


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_link_kits()


# Shared icon/frame kits are written in parallel; use them once they exist.
func _link_kits() -> void:
	if _icons == null and ResourceLoader.exists(ICONS_PATH):
		_icons = load(ICONS_PATH)
	if _frames == null and ResourceLoader.exists(FRAMES_PATH):
		_frames = load(FRAMES_PATH)
		if _frames != null:
			for method in _frames.get_script_method_list():
				_frame_methods[method.name] = method.args.size()


func _process(delta: float) -> void:
	var hud := get_parent()
	if hud == null:
		return
	_clock += delta
	_result_time = _result_time + delta if hud.extinct else -1.0
	if _result_time < 0.0 and hud.extinct:
		_result_time = 0.0
	_pause_time = (_pause_time + delta if _pause_time >= 0.0 else 0.0) if hud.paused and not hud.extinct else -1.0
	# A fresh hit raises hit_feedback again; bundle quick successive losses.
	var feedback: float = hud.hit_feedback
	if feedback > _last_feedback + 0.05 and int(hud.last_loss) > 0:
		_loss_total = (_loss_total if _loss_age < LOSS_WINDOW else 0) + int(hud.last_loss)
		_loss_age = 0.0
	elif not hud.paused:
		_loss_age += delta
	_last_feedback = feedback
	# The moment runs in real time, unaffected by its own slow motion.
	var moments: int = int(hud.get_meta("king_moments", 0))
	if moments > _king_seen:
		_king_time = 0.0
	_king_seen = moments
	if _king_time >= 0.0:
		_king_time += delta / maxf(0.01, Engine.time_scale)
		if _king_time > KING_TIME or hud.extinct:
			_king_time = -1.0
	_step_milestone(hud, delta / maxf(0.01, Engine.time_scale))
	var key: Variant = _redraw_key(hud)
	if key == null or typeof(key) != typeof(_last_key) or key != _last_key:
		queue_redraw()
	_last_key = key


# null = animating (repaint every frame); otherwise a key of what is shown.
func _redraw_key(hud: Control) -> Variant:
	if hud.extinct:
		# After the count-up only the rays behind the skull turn (slowly).
		return null if _result_time < 3.2 else ["result", int(_clock * 30.0), size, hud.run_stats]
	if hud.paused:
		if _pause_time < 0.3:
			return null
		var evo: Variant = hud.evolution
		return ["pause", int(hud.elapsed), int(hud.population), size, str(evo.ranks) if evo != null else "", str(evo.evolutions) if evo != null else "", int(evo.level) if evo != null else 0]
	var popups: Array = hud.get_meta("kill_popups", [])
	for popup in popups:
		if float(popup.get("t", 1.0)) < 1.0:
			return null
	if _loss_visible() or float(hud.hit_feedback) > 0.0 or _king_time >= 0.0:
		return null
	if _milestone_time >= 0.0 or _last_one(hud):
		return null
	if hud.boss_pointer.is_finite() or float(hud.evolve_flash) > 0.0:
		return null
	return ["idle", size]


func _draw() -> void:
	var hud := get_parent()
	if hud == null:
		return
	if hud.extinct:
		_draw_result(hud)
		return
	if hud.paused:
		_draw_pause(hud)
		return
	if _last_one(hud):
		_draw_last_one(hud)
	_draw_popups(hud)
	_draw_loss(hud)
	if _milestone_time >= 0.0 and not _choosing(hud) and _king_time < 0.0:
		_draw_milestone()
	if _king_time >= 0.0 and not _choosing(hud):
		_draw_king(hud)
	if hud.boss_pointer.is_finite():
		_draw_boss_pointer(hud)
	if float(hud.evolve_flash) > 0.0 and not _choosing(hud):
		_draw_evolve_banner(hud)


# ---------------------------------------------------------------- result

func _draw_result(hud: Control) -> void:
	var t := _result_time
	var stats: Dictionary = hud.run_stats if hud.run_stats is Dictionary else {}
	var cx := size.x * 0.5
	var cy := size.y * 0.5
	# World dims to near black with a red rim: the run is over.
	draw_rect(Rect2(Vector2.ZERO, size), Color(UiStyle.DIM, clampf(t / 0.35, 0.0, 1.0) * 0.93))
	_vignette(Color(UiStyle.DANGER, 0.24 * clampf(t / 0.6, 0.0, 1.0)), 240.0)
	var action: Rect2 = hud._action_rect()
	var panel_top := cy - 572
	var panel := Rect2(cx - 390, panel_top, 780, action.end.y + 34 - panel_top)
	var appear := _ease_out(clampf(t / 0.35, 0.0, 1.0))
	_panel(Rect2(panel.position + Vector2(0, 40.0 * (1.0 - appear)), panel.size), UiStyle.DANGER, appear)
	# Skull medallion breaks the top edge; title punches in.
	var punch := 1.0 + 0.5 * (1.0 - _ease_out(clampf(t / 0.3, 0.0, 1.0)))
	var skull_c := Vector2(cx, panel.position.y)
	_rays(skull_c, 150.0 * punch, 14, _clock * 0.25, Color(UiStyle.DANGER, 0.16 * appear), Color(UiStyle.EMBER, 0.08 * appear))
	_medallion(skull_c, 74.0 * punch, UiStyle.DANGER, appear)
	_icon("skull", Rect2(skull_c - Vector2(46, 46) * punch, Vector2(92, 92) * punch), Color(UiStyle.BONE, appear))
	var title_alpha := clampf((t - 0.1) / 0.25, 0.0, 1.0)
	var title_size := roundf(UiStyle.SIZE_HERO * (1.0 + 0.35 * (1.0 - _ease_out(clampf((t - 0.1) / 0.3, 0.0, 1.0)))))
	_title("AUSGESTORBEN", Vector2(cx, panel.position.y + 150), title_size, Color(UiStyle.TEXT, title_alpha), UiStyle.DANGER)
	var lost := int(stats.get("lost", 0))
	var sub := "DER SCHWARM IST ERLOSCHEN" if lost <= 0 else "%d MAWLINGS GEFALLEN" % lost
	_label(sub, Vector2(cx, panel.position.y + 190), LABEL, Color(UiStyle.TEXT_DIM, title_alpha), true)
	# Survival time: the hero number, counted up from its own timer.
	var seconds := float(stats.get("seconds", hud.elapsed))
	var shown := seconds * _ease_out(clampf((t - 0.35) / 1.0, 0.0, 1.0))
	var time_alpha := clampf((t - 0.3) / 0.2, 0.0, 1.0)
	_label("ÜBERLEBT", Vector2(cx, panel.position.y + 232), LABEL, Color(UiStyle.GOLD, time_alpha), true)
	_icon("clock", Rect2(cx - 196, panel.position.y + 258, 56, 56), Color(UiStyle.GOLD, time_alpha))
	_title(_clock_text(shown), Vector2(cx + 24, panel.position.y + 318), 96, Color(UiStyle.TEXT, time_alpha), UiStyle.GOLD)
	# Four stat tiles, each counting up in turn.
	var tiles := [
		["mawling", "MAX. SCHWARM", float(stats.get("peak_population", hud.peak_population)), UiStyle.EMBER, false],
		["fang", "KILLS", float(stats.get("kills", hud.kills)), UiStyle.CYAN, false],
		["biomass", "BIOMASSE", float(stats.get("biomass", hud.consumed_biomass)), UiStyle.AMBER, true],
		["crown", "BOSSE", float(stats.get("bosses", 0)), UiStyle.GOLD, false],
	]
	# The card art has a thick rim; keep tiles inside it.
	var tile_w := (panel.size.x - 110 - 3 * 14) / 4.0
	for i in tiles.size():
		var start := 1.0 + i * 0.16
		var a := clampf((t - start) / 0.2, 0.0, 1.0)
		if a <= 0.0:
			continue
		var tile := Rect2(panel.position.x + 55 + i * (tile_w + 14), panel.position.y + 344 + 18.0 * (1.0 - a), tile_w, 142)
		var value: float = tiles[i][2] * _ease_out(clampf((t - start) / 0.7, 0.0, 1.0))
		_stat_tile(tile, tiles[i][0], tiles[i][1], ("%.1f" % value) if tiles[i][4] else "%d" % int(round(value)), tiles[i][3], a)
	# Kill breakdown by creature type.
	var by_type: Dictionary = stats.get("kills_by_type", {})
	var kills_alpha := clampf((t - 1.75) / 0.25, 0.0, 1.0)
	var row_y := panel.position.y + 530
	_divider(Vector2(cx, row_y - 18), 320, "BEUTE NACH ART", kills_alpha)
	var chips: Array = []
	for entry in KILL_TYPES:
		var count := int(by_type.get(entry[0], 0))
		if count > 0:
			chips.append([entry[0], count])
	if chips.is_empty():
		_label("Keine Beute erlegt", Vector2(cx, row_y + 46), LABEL, Color(UiStyle.TEXT_DIM, kills_alpha), true)
	else:
		var chip_w := minf(146.0, (panel.size.x - 60 - (chips.size() - 1) * 10) / chips.size())
		var x0 := cx - (chips.size() * chip_w + (chips.size() - 1) * 10) * 0.5
		for i in chips.size():
			var ca := clampf((t - 1.75 - i * 0.08) / 0.2, 0.0, 1.0)
			_kill_chip(Rect2(x0 + i * (chip_w + 10), row_y + 4, chip_w, 58), chips[i][0], chips[i][1], ca * kills_alpha)
	# Chosen mutations as an icon row with rank pips.
	var build := _build(hud, stats)
	var build_alpha := clampf((t - 2.05) / 0.25, 0.0, 1.0)
	var build_y := panel.position.y + 640
	_divider(Vector2(cx, build_y - 18), 320, "MUTATIONEN", build_alpha)
	_build_row(build, Vector2(cx, build_y + 44), t - 2.05, build_alpha)
	# Buttons exactly on the touch_controls rectangles; visible early since they are live.
	var button_alpha := clampf((t - 0.45) / 0.3, 0.0, 1.0)
	_button(action, "NEUER RUN", "primary", button_alpha, "restart")
	_button(hud._hub_rect(), "BRUTSTÄTTE", "secondary", button_alpha, "hub")
	_label("R / ENTER  ·  H BRUTSTÄTTE", Vector2(cx, panel.end.y + 44), LABEL, Color(UiStyle.TEXT_DIM, button_alpha * 0.8), true)


# ---------------------------------------------------------------- pause

func _draw_pause(hud: Control) -> void:
	var t := maxf(0.0, _pause_time)
	var a := _ease_out(clampf(t / 0.25, 0.0, 1.0))
	var cx := size.x * 0.5
	var cy := size.y * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), Color(UiStyle.DIM, 0.82 * a))
	var action: Rect2 = hud._action_rect()
	var panel := Rect2(cx - 350, cy - 410, 700, action.position.y - (cy - 410) - 34)
	_panel(Rect2(panel.position + Vector2(0, 24.0 * (1.0 - a)), panel.size), UiStyle.CYAN, a)
	var top := panel.position.y + 24.0 * (1.0 - a)
	_medallion(Vector2(cx, top), 56.0, UiStyle.CYAN, a)
	_icon("pause", Rect2(cx - 30, top - 30, 60, 60), Color(UiStyle.BONE, a))
	_title("PAUSE", Vector2(cx, top + 120), UiStyle.SIZE_HERO, Color(UiStyle.TEXT, a), UiStyle.CYAN)
	_label("DIE JAGD WARTET", Vector2(cx, top + 160), LABEL, Color(UiStyle.TEXT_DIM, a), true)
	# Run so far: time, swarm, level in three quiet columns.
	var level: int = 0 if hud.evolution == null else int(hud.evolution.level)
	var cols := [
		["clock", "LAUFZEIT", _clock_text(hud.elapsed), UiStyle.GOLD],
		["mawling", "SCHWARM", "%d" % int(hud.population), UiStyle.EMBER],
		["dna", "STUFE", "%d" % level, UiStyle.CYAN],
	]
	var col_w := (panel.size.x - 60 - 2 * 14) / 3.0
	for i in cols.size():
		var tile := Rect2(panel.position.x + 30 + i * (col_w + 14), top + 194, col_w, 136)
		_stat_tile(tile, cols[i][0], cols[i][1], cols[i][2], cols[i][3], a)
	var build_y := top + 392
	_divider(Vector2(cx, build_y), 300, "AKTUELLER BUILD", a)
	_build_row(_build(hud, {}), Vector2(cx, build_y + 74), 9.0, a)
	_button(action, "WEITERSPIELEN", "primary", a, "play")
	_button(hud._hub_rect(), "BRUTSTÄTTE", "secondary", a, "hub")
	_label("P / ESCAPE", Vector2(cx, action.end.y + 52), LABEL, Color(UiStyle.TEXT_DIM, 0.8 * a), true)


# ---------------------------------------------------------------- evolution banner

# Big, short moment above the swarm, then it shrinks to the upper third and fades.
func _draw_evolve_banner(hud: Control) -> void:
	var t := EVOLVE_TIME - float(hud.evolve_flash)
	var burst := _ease_out(clampf(t / 0.22, 0.0, 1.0))
	var settle := _ease_in_out(clampf((t - 1.5) / 0.45, 0.0, 1.0))
	var fade := clampf(float(hud.evolve_flash) / 0.45, 0.0, 1.0) * burst
	var scale := lerpf(1.45, 1.0, burst) * lerpf(1.0, 0.58, settle)
	var c := Vector2(size.x * 0.5, lerpf(size.y * 0.5 - 250, size.y * 0.5 - 360, settle))
	# Rays and a soft violet flood only during the big moment.
	var big := (1.0 - settle) * fade
	_rays(c, 360.0 * scale, 18, _clock * 0.6, Color(UiStyle.VIOLET, 0.30 * big), Color(UiStyle.GOLD, 0.22 * big))
	draw_circle(c, 210.0 * scale, Color(UiStyle.VIOLET, 0.10 * big))
	var ribbon := Rect2(c - Vector2(400, 72) * scale, Vector2(800, 144) * scale)
	_ribbon(ribbon, fade)
	var gem_c := c + Vector2(0, -104) * scale
	_medallion(gem_c, 60.0 * scale, UiStyle.GOLD, fade)
	_icon("alpha_core", Rect2(gem_c - Vector2(42, 42) * scale, Vector2(84, 84) * scale), Color(1, 1, 1, fade))
	_label("EVOLUTION", c + Vector2(0, -24) * scale, maxf(LABEL, floorf(LABEL * scale * 1.3)), Color(UiStyle.GOLD, fade), true)
	var name_text := String(hud.evolve_name).to_upper()
	_title(name_text if name_text != "" else "EVOLUTION", c + Vector2(0, 54) * scale, floorf(UiStyle.SIZE_HERO * scale), Color(1, 1, 1, fade), UiStyle.VIOLET)


func _ribbon(rect: Rect2, alpha: float) -> void:
	var p := rect.position
	var e := rect.end
	var my := rect.get_center().y
	var tail := rect.size.y * 0.45
	var shape := PackedVector2Array([
		Vector2(p.x + tail, p.y), Vector2(e.x - tail, p.y), Vector2(e.x, p.y + rect.size.y * 0.12),
		Vector2(e.x - tail * 0.7, my), Vector2(e.x, e.y - rect.size.y * 0.12), Vector2(e.x - tail, e.y),
		Vector2(p.x + tail, e.y), Vector2(p.x, e.y - rect.size.y * 0.12), Vector2(p.x + tail * 0.7, my),
		Vector2(p.x, p.y + rect.size.y * 0.12),
	])
	_glow(shape, UiStyle.VIOLET, alpha)
	_gradient(shape, rect, Color(Color("3a1f5c"), 0.96 * alpha), Color(Color("150b22"), 0.96 * alpha))
	_outline(shape, Color(UiStyle.GOLD, alpha), 4.0)
	var inner := _inset(shape, rect, 9.0)
	_outline(inner, Color(UiStyle.VIOLET, 0.55 * alpha), 2.0)


# ---------------------------------------------------------------- milestones

func _swarm() -> Node:
	if _swarm_node == null or not is_instance_valid(_swarm_node):
		_swarm_node = get_tree().get_first_node_in_group("swarm") if is_inside_tree() else null
	return _swarm_node


# KERN sets the HUD variable "milestone" (0 = none); without it the swarm's own
# milestone count stands in. A new non-zero value starts the banner.
func _step_milestone(hud: Control, real_delta: float) -> void:
	var value: Variant = hud.get("milestone")
	if value == null and hud.has_meta("milestone"):
		value = hud.get_meta("milestone")
	if value == null:
		var swarm := _swarm()
		value = swarm.get("last_milestone") if swarm != null else 0
	var mark := int(value) if value != null else 0
	if mark <= 0:
		_milestone_seen = 0
	elif mark != _milestone_seen:
		_milestone_seen = mark
		_milestone = mark
		_milestone_time = 0.0
	if _milestone_time >= 0.0:
		_milestone_time += real_delta
		if _milestone_time > MILESTONE_TIME or hud.extinct:
			_milestone_time = -1.0


func _milestone_text(mark: int) -> String:
	if mark >= 250:
		return "SCHWARM VOLL: 250"
	if mark >= 100:
		return "HORDE: %d!" % mark
	return "%d MAWLINGS!" % mark


# Warm ember ribbon in the upper third: pops in, holds, drifts up and fades.
func _draw_milestone() -> void:
	var t := _milestone_time
	var burst := _ease_out(clampf(t / 0.2, 0.0, 1.0))
	var fade := burst * (1.0 - clampf((t - (MILESTONE_TIME - 0.45)) / 0.45, 0.0, 1.0))
	if fade <= 0.0:
		return
	var big := _milestone >= 100
	var scale := lerpf(1.5, 1.0, burst) * (1.12 if big else 1.0)
	var c := Vector2(size.x * 0.5, size.y * 0.5 - 380 - 30.0 * clampf((t - 1.2) / 0.7, 0.0, 1.0))
	_rays(c, 260.0 * scale, 14, _clock * 0.7, Color(UiStyle.GOLD, 0.26 * fade), Color(UiStyle.EMBER_GLOW, 0.16 * fade))
	var text := _milestone_text(_milestone)
	var font_size := floorf((58.0 if text.length() < 14 else 48.0) * scale)
	var w := UiStyle.width_px(text, font_size, UiStyle.display_font()) + 120.0 * scale
	var rect := Rect2(c - Vector2(w * 0.5, 52 * scale), Vector2(w, 104 * scale))
	var shape := _chamfer(rect, 22.0 * scale, 0.0)
	_glow(shape, UiStyle.EMBER, fade)
	_gradient(shape, rect, Color(Color("5a2412"), 0.95 * fade), Color(Color("1c0b06"), 0.95 * fade))
	_outline(shape, Color(UiStyle.GOLD, fade), 4.0)
	_outline(_inset(shape, rect, 8.0), Color(UiStyle.EMBER_GLOW, 0.45 * fade), 2.0)
	var badge := c + Vector2(0, -74) * scale
	_medallion(badge, 38.0 * scale, UiStyle.GOLD, fade)
	_icon("mawling", Rect2(badge - Vector2(26, 26) * scale, Vector2(52, 52) * scale), Color(1, 1, 1, fade))
	_title(text, c + Vector2(0, 20) * scale, font_size, Color(1, 1, 1, fade), UiStyle.EMBER)


# ---------------------------------------------------------------- last animal

# Only one Mawling left after the swarm was bigger (swarm plays the heartbeat).
func _last_one(hud: Control) -> bool:
	if hud.extinct or hud.paused or int(hud.population) != 1:
		return false
	return int(hud.peak_population) > 1


# Red vignette beating with the heartbeat loop (lub-dub every 0.92 s).
func _draw_last_one(hud: Control) -> void:
	var phase := fmod(_clock, 0.92)
	var beat := exp(-phase * 14.0) + 0.7 * exp(-maxf(0.0, phase - 0.29) * 14.0) * (1.0 if phase >= 0.29 else 0.0)
	beat = clampf(beat, 0.0, 1.0)
	_vignette(Color(UiStyle.DANGER, 0.3 + 0.25 * beat), 170.0 + 50.0 * beat)
	_vignette(Color(Color("3a0606"), 0.3), 80.0)
	var a := 0.8 + 0.2 * beat
	UiStyle.text_px(self, "LETZTER MAWLING", Vector2(size.x * 0.5, size.y * 0.5 + 200), UiStyle.SIZE_HEAD * (1.0 + 0.06 * beat), Color(UiStyle.DANGER.lightened(0.35), a), true, 8)


# ---------------------------------------------------------------- loss feedback

func _draw_loss(hud: Control) -> void:
	var strength := clampf(float(hud.hit_feedback) / 1.2, 0.0, 1.0)
	if strength > 0.0:
		var pulse := 0.75 + 0.25 * sin(_clock * 14.0)
		_vignette(Color(UiStyle.DANGER, 0.3 * strength * pulse), 110.0 + 50.0 * strength)
	if not _loss_visible():
		return
	var a := 1.0 - clampf((_loss_age - 0.95) / 0.4, 0.0, 1.0)
	var pop := 1.0 + 0.45 * (1.0 - _ease_out(clampf(_loss_age / 0.18, 0.0, 1.0)))
	# Fixed anchor above the swarm (the camera keeps the swarm centred): it no
	# longer drifts, so kill popups can reliably steer around it.
	var c := _loss_center()
	var number := "−%d" % _loss_total
	var fs := floorf(64 * pop)
	var w := UiStyle.width_px(number, fs)
	var head := 44.0 * pop
	var total := head + 10 + w
	var x0 := c.x - total * 0.5
	var pill := Rect2(x0 - 22, c.y - 46 * pop, total + 44, 64 * pop)
	draw_colored_polygon(_chamfer(pill, 16.0 * pop, 0.0), Color(UiStyle.OUTLINE, 0.62 * a))
	_icon("mawling", Rect2(x0, c.y - head * 0.5 - 14 * pop, head, head), Color(UiStyle.DANGER, a))
	UiStyle.text_px(self, number, Vector2(x0 + head + 10, c.y + 8 * pop), fs, Color(Color("ffd9cc"), a), false, 9)
	_label("MAWLINGS", Vector2(c.x, c.y + 44 * pop), LABEL, Color(UiStyle.DANGER.lightened(0.35), a), true)


func _loss_visible() -> bool:
	return _loss_total > 0 and _loss_age <= 1.35


func _loss_center() -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.5 + LOSS_Y)


# Area the loss number owns while it shows (pill + MAWLINGS label).
func _loss_zone() -> Rect2:
	var c := _loss_center()
	return Rect2(c.x - LOSS_ZONE.x * 0.5, c.y - 64.0, LOSS_ZONE.x, LOSS_ZONE.y)


# ---------------------------------------------------------------- kill popups

# "+DNA" and "+biomass" rise from the kill spot (screen positions from HuntWorld).
# Simple collision avoidance: older popups keep their place, newer ones step
# aside. The loss zone pushes sideways (up if the side is off screen), other
# popups push upward; everything stays inside the screen.
func _draw_popups(hud: Control) -> void:
	var popups: Array = hud.get_meta("kill_popups", [])
	var font := UiStyle.display_font()
	var placed: Array = []
	var loss_zone := Rect2()
	if _loss_visible():
		loss_zone = _loss_zone()
		placed.append(loss_zone)
	for popup in popups:
		var t: float = popup.get("t", 1.0)
		if t >= 1.0:
			continue
		var a := 1.0 - clampf((t - 0.6) / 0.4, 0.0, 1.0)
		var pop := 1.0 + 0.35 * (1.0 - _ease_out(clampf(t / 0.2, 0.0, 1.0)))
		var c: Vector2 = popup.get("screen", Vector2.ZERO) - Vector2(0, 70.0 * _ease_out(t))
		var parts: Array = []
		if int(popup.get("dna", 0)) > 0:
			parts.append(["dna", "+%d" % int(popup.dna), UiStyle.CYAN])
		if int(popup.get("biomass", 0)) > 0:
			parts.append(["biomass", "+%d" % int(popup.biomass), UiStyle.AMBER])
		if parts.is_empty():
			continue
		var fs := floorf(34 * pop)
		var icon := 34.0 * pop
		var gap := 16.0 * pop
		var widths: Array = []
		var total := 0.0
		for part in parts:
			var w := icon + 4.0 + UiStyle.width_px(part[1], fs, font)
			widths.append(w)
			total += w
		total += gap * (parts.size() - 1)
		var pill := Rect2(c.x - total * 0.5 - 14.0, c.y - 26.0 * pop, total + 28.0, 44.0 * pop)
		var box := _avoid(pill.grow(5.0), placed, loss_zone)
		placed.append(box)
		var shift := box.get_center() - pill.grow(5.0).get_center()
		pill.position += shift
		c += shift
		draw_colored_polygon(_chamfer(pill, 12.0 * pop, 0.0), Color(UiStyle.OUTLINE, 0.55 * a))
		var x := c.x - total * 0.5
		for index in parts.size():
			var part: Array = parts[index]
			_icon(part[0], Rect2(Vector2(x, c.y - icon * 0.5 - 4.0 * pop), Vector2(icon, icon)), Color(part[2], a))
			UiStyle.text_px(self, part[1], Vector2(x + icon + 4.0, c.y + 10.0 * pop), fs, Color(part[2].lightened(0.35), a), false, 7)
			x += widths[index] + gap


func _avoid(box: Rect2, placed: Array, loss_zone: Rect2) -> Rect2:
	var margin := 8.0
	for step in 10:
		var hit := Rect2()
		for other: Rect2 in placed:
			if other.intersects(box):
				hit = other
				break
		if hit.size == Vector2.ZERO:
			break
		var moved := box
		if hit == loss_zone:
			var to_right := box.get_center().x >= hit.get_center().x
			moved.position.x = hit.end.x + 2.0 if to_right else hit.position.x - box.size.x - 2.0
			if moved.position.x < margin or moved.end.x > size.x - margin:
				moved.position.x = hit.position.x - box.size.x - 2.0 if to_right else hit.end.x + 2.0
			if moved.position.x < margin or moved.end.x > size.x - margin:
				moved = box
				moved.position.y = hit.position.y - box.size.y - 2.0
		else:
			moved.position.y = hit.position.y - box.size.y - 2.0
		box = moved
	box.position.x = clampf(box.position.x, margin, maxf(margin, size.x - margin - box.size.x))
	box.position.y = maxf(box.position.y, 150.0)
	return box


# ---------------------------------------------------------------- Königsmoment

# Gold flash, rays and a crowned ribbon; it holds centre stage, then fades.
func _draw_king(hud: Control) -> void:
	var t := _king_time
	var burst := _ease_out(clampf(t / 0.25, 0.0, 1.0))
	var fade := burst * (1.0 - clampf((t - (KING_TIME - 0.5)) / 0.5, 0.0, 1.0))
	var flash := 1.0 - clampf(t / 0.35, 0.0, 1.0)
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(UiStyle.GOLD, 0.35 * flash))
	_vignette(Color(UiStyle.GOLD, 0.28 * fade), 150.0)
	var scale := lerpf(1.6, 1.0, burst)
	var c := Vector2(size.x * 0.5, size.y * 0.5 - 420)
	_rays(c, 420.0 * scale, 22, _clock * 0.8, Color(UiStyle.GOLD, 0.34 * fade), Color(UiStyle.EMBER_GLOW, 0.22 * fade))
	draw_circle(c, 230.0 * scale, Color(UiStyle.GOLD, 0.10 * fade))
	var ribbon := Rect2(c - Vector2(430, 76) * scale, Vector2(860, 152) * scale)
	_ribbon(ribbon, fade)
	var crown_c := c + Vector2(0, -112) * scale
	_medallion(crown_c, 62.0 * scale, UiStyle.GOLD, fade)
	_icon("crown", Rect2(crown_c - Vector2(40, 40) * scale, Vector2(80, 80) * scale), Color(UiStyle.GOLD, fade))
	_label("BOG KING", c + Vector2(0, -26) * scale, maxf(LABEL, floorf(LABEL * scale * 1.3)), Color(UiStyle.GOLD, fade), true)
	_title("KÖNIG VERSCHLUNGEN", c + Vector2(0, 50) * scale, floorf(58 * scale), Color(1, 1, 1, fade), UiStyle.GOLD)


# ---------------------------------------------------------------- boss pointer

func _draw_boss_pointer(hud: Control) -> void:
	var at: Vector2 = hud.boss_pointer
	var vulnerable: bool = hud.boss_vulnerable
	var accent: Color = UiStyle.GOLD if vulnerable else UiStyle.EMBER
	var direction := (at - size * 0.5).normalized()
	var side := Vector2(-direction.y, direction.x)
	# Keep medallion plus arrow tip on screen.
	var reach := at + direction * 92.0
	var over := Vector2(maxf(0.0, maxf(12.0 - reach.x, reach.x - size.x + 12.0)), maxf(0.0, maxf(12.0 - reach.y, reach.y - size.y + 12.0)))
	at -= Vector2(signf(direction.x) * over.x, signf(direction.y) * over.y)
	var pulse := 0.5 + 0.5 * sin(_clock * (8.0 if vulnerable else 4.5))
	draw_circle(at, 58 + 6 * pulse, Color(accent, 0.12 + 0.12 * pulse))
	# Arrow first so the medallion rim sits on top of its base.
	var base := at + direction * 30.0
	var tip := at + direction * (82.0 + 6.0 * pulse)
	var arrow := PackedVector2Array([tip + direction * 5.0, base + side * 36.0, base + direction * 14.0, base - side * 36.0])
	draw_colored_polygon(arrow, UiStyle.OUTLINE)
	var inner_arrow := PackedVector2Array([tip - direction * 3.0, base + side * 27.0 + direction * 6.0, base + direction * 18.0, base - side * 27.0 + direction * 6.0])
	draw_colored_polygon(inner_arrow, accent)
	draw_colored_polygon(PackedVector2Array([tip - direction * 3.0, base + side * 27.0 + direction * 6.0, base + direction * 18.0]), accent.lightened(0.3))
	_medallion(at, 44.0, accent, 1.0)
	_icon("crown", Rect2(at - Vector2(30, 30), Vector2(60, 60)), accent.lightened(0.15))
	var label := "VERWUNDBAR!" if vulnerable else "BOG KING"
	# Label under the medallion (above it near the bottom edge).
	var label_c := at + Vector2(0, -74 if direction.y > 0.6 else 74)
	var font := UiStyle.display_font()
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL).x
	var pill := Rect2(label_c - Vector2(w * 0.5 + 16, 19), Vector2(w + 32, 38))
	pill.position.x = clampf(pill.position.x, 8.0, size.x - pill.size.x - 8.0)
	draw_colored_polygon(_chamfer(pill, 10.0, 0.0), Color(UiStyle.PANEL, 0.95))
	_outline(_chamfer(pill, 10.0, 0.0), Color(accent, 0.8), 2.0)
	UiStyle.text(self, label, Vector2(pill.get_center().x, pill.get_center().y + 8), LABEL, accent.lightened(0.3) if vulnerable else UiStyle.TEXT, true, 4)


# ---------------------------------------------------------------- building blocks

func _stat_tile(rect: Rect2, icon: String, label: String, value: String, accent: Color, alpha: float) -> void:
	if _kit("panel"):
		_frames.call("panel", self, _pop(rect, alpha), accent, false)
	else:
		var shape := _chamfer(rect, 14.0, 0.0)
		_gradient(shape, rect, Color(UiStyle.PANEL_SOFT.lightened(0.04), 0.95 * alpha), Color(UiStyle.OUTLINE, 0.95 * alpha))
		_outline(shape, Color(accent, 0.75 * alpha), 2.5)
	draw_line(rect.position + Vector2(18, 3), Vector2(rect.end.x - 18, rect.position.y + 3), Color(accent, 0.35 * alpha), 3.0)
	_icon(icon, Rect2(rect.get_center().x - 22, rect.position.y + 12, 44, 44), Color(accent, alpha))
	var fs := UiStyle.SIZE_TITLE
	var font := UiStyle.display_font()
	while fs > 30 and font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > rect.size.x - 16:
		fs -= 2
	UiStyle.text(self, value, Vector2(rect.get_center().x, rect.position.y + 58 + fs * 0.82), fs, Color(UiStyle.TEXT, alpha), true, 6)
	# Narrow tiles keep 22 px and switch to a short label instead of shrinking.
	var shown := label
	if font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL).x > rect.size.x - 12:
		shown = SHORT_LABEL.get(label, label)
	_label(shown, Vector2(rect.get_center().x, rect.end.y - 14), LABEL, Color(accent.lerp(UiStyle.TEXT, 0.35), alpha), true)


func _kill_chip(rect: Rect2, kind: String, count: int, alpha: float) -> void:
	if alpha <= 0.0:
		return
	var accent := _kill_color(kind)
	if _kit("pill"):
		_frames.call("pill", self, _pop(rect, alpha), accent)
	else:
		var shape := _chamfer(rect, 12.0, 0.0)
		draw_colored_polygon(shape, Color(UiStyle.OUTLINE, 0.9 * alpha))
		_outline(shape, Color(accent, 0.6 * alpha), 2.0)
	_icon(kind, Rect2(rect.position.x + 8, rect.get_center().y - 22, 44, 44), Color(accent, alpha))
	UiStyle.text(self, "×%d" % count, Vector2(rect.position.x + 58, rect.get_center().y + 13), UiStyle.SIZE_HEAD, Color(UiStyle.TEXT, alpha), false, 5)


# Owned mutations: evolved forms first, their base form hidden.
func _build(hud: Control, stats: Dictionary) -> Array:
	var ranks: Dictionary = stats.get("mutations", {})
	var evolved: Array = stats.get("evolutions", [])
	var evo: Variant = hud.evolution
	if ranks.is_empty() and evo != null:
		ranks = evo.ranks
		evolved = Array(evo.evolutions)
	var hidden: Array = []
	if evo != null:
		for rule in evo.EVOLUTION_RULES:
			if evolved.has(rule.id):
				hidden.append(rule.base)
	var result: Array = []
	for id in evolved:
		result.append([id, 0, true])
	for group in ["attack", "trait"]:
		for id in ranks:
			if int(ranks[id]) <= 0 or hidden.has(id) or evolved.has(id):
				continue
			var kind: String = evo.kind_of(id) if evo != null else "trait"
			if kind == group:
				result.append([id, int(ranks[id]), false])
	return result


func _build_row(build: Array, center: Vector2, t: float, alpha: float) -> void:
	if alpha <= 0.0:
		return
	if build.is_empty():
		_label("Keine Mutationen gewählt", center + Vector2(0, 8), UiStyle.SIZE_BODY, Color(UiStyle.TEXT_DIM, alpha), true)
		return
	var step := minf(104.0, 680.0 / build.size())
	var x0 := center.x - (build.size() - 1) * step * 0.5
	for i in build.size():
		var a := clampf((t - i * 0.08) / 0.2, 0.0, 1.0) * alpha
		if a <= 0.0:
			continue
		var id: String = build[i][0]
		var evolved: bool = build[i][2]
		var accent := _mutation_color(id)
		var c := Vector2(x0 + i * step, center.y - 10.0 * (1.0 - a))
		var r := minf(42.0, step * 0.42)
		if evolved:
			draw_circle(c, r + 12, Color(UiStyle.VIOLET, 0.25 * a))
		_medallion(c, r, UiStyle.GOLD if evolved else accent, a)
		_icon(id, Rect2(c - Vector2(r, r) * 0.72, Vector2(r, r) * 1.44), Color(accent, a) if not _has_icon(id) else Color(1, 1, 1, a))
		if evolved:
			_label("EVO", c + Vector2(0, r + 30), LABEL, Color(UiStyle.GOLD, a), true)
			continue
		for k in 3:
			var pc := c + Vector2((k - 1) * 18.0, r + 20)
			var diamond := PackedVector2Array([pc + Vector2(0, -9), pc + Vector2(7, 0), pc + Vector2(0, 9), pc + Vector2(-7, 0)])
			draw_colored_polygon(diamond, Color(UiStyle.OUTLINE, a))
			var inner := PackedVector2Array([pc + Vector2(0, -6), pc + Vector2(4.5, 0), pc + Vector2(0, 6), pc + Vector2(-4.5, 0)])
			draw_colored_polygon(inner, Color(accent, a) if k < int(build[i][1]) else Color(accent, 0.22 * a))


func _button(rect: Rect2, label: String, kind: String, alpha: float, icon: String) -> void:
	if alpha <= 0.0:
		return
	var primary := kind == "primary"
	var accent: Color = UiStyle.EMBER if primary else UiStyle.TOXIC
	if _kit("button"):
		_frames.call("button", self, _pop(rect, alpha), kind, false)
	else:
		if primary:
			var breathe := 0.5 + 0.5 * sin(_clock * 3.0)
			_glow(_chamfer(rect.grow(4), 20.0, 0.0), accent, (0.5 + 0.5 * breathe) * alpha)
		var shape := _chamfer(rect, 18.0, 0.0)
		var top: Color = Color("c4541f") if primary else Color("1f4a37")
		var bottom: Color = Color("6e260d") if primary else Color("0c2219")
		_gradient(shape, rect, Color(top, alpha), Color(bottom, alpha))
		draw_colored_polygon(_chamfer(Rect2(rect.position + Vector2(10, 6), Vector2(rect.size.x - 20, rect.size.y * 0.38)), 12.0, 0.0), Color(1, 1, 1, 0.10 * alpha))
		_outline(shape, Color(accent.lightened(0.2), alpha), 3.5)
		_outline(_chamfer(rect.grow(-7), 13.0, 0.0), Color(UiStyle.OUTLINE, 0.45 * alpha), 2.0)
		for s: float in [-1.0, 1.0]:
			var corner := Vector2(rect.get_center().x + s * rect.size.x * 0.5, rect.position.y)
			_claw(corner + Vector2(-s * 24, 4), Vector2(s * 0.5, -1), 20, 6, Color(UiStyle.BONE, alpha), s * 0.5)
	var font := UiStyle.display_font()
	var fs := UiStyle.SIZE_HEAD
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var icon_w := 40.0
	var x := rect.get_center().x - (w + icon_w + 10) * 0.5
	_icon(icon, Rect2(x, rect.get_center().y - icon_w * 0.5, icon_w, icon_w), Color(UiStyle.TEXT, alpha))
	UiStyle.text(self, label, Vector2(x + icon_w + 10, rect.get_center().y + fs * 0.36), fs, Color(UiStyle.TEXT, alpha), false, 6)


func _divider(center: Vector2, half: float, label: String, alpha: float) -> void:
	if alpha <= 0.0:
		return
	var font := UiStyle.display_font()
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL).x * 0.5
	if _kit("divider"):
		_frames.call("divider", self, center + Vector2(0, -7), half * 2.0, Color(UiStyle.BONE, alpha), w * 2.0 + 28.0, 0.6)
		_label(label, center, LABEL, Color(UiStyle.TEXT_DIM, alpha), true)
		return
	for s: float in [-1.0, 1.0]:
		var a := Vector2(center.x + s * (w + 16), center.y - 7)
		var b := Vector2(center.x + s * half, center.y - 7)
		draw_line(a, b, Color(UiStyle.PANEL_EDGE.lightened(0.25), alpha), 2.0, true)
		draw_colored_polygon(PackedVector2Array([b + Vector2(0, -5), b + Vector2(s * 6, 0), b + Vector2(0, 5), b - Vector2(s * 6, 0)]), Color(UiStyle.BONE, 0.7 * alpha))
	_label(label, center, LABEL, Color(UiStyle.TEXT_DIM, alpha), true)


# Organic card: glow, gradient body, pores, double rim, bone horns on top.
func _panel(rect: Rect2, accent: Color, alpha: float) -> void:
	if alpha <= 0.0:
		return
	if _kit("card"):
		# Kit frames have no alpha; they pop in by scale instead of fading.
		_frames.call("card", self, _pop(rect, alpha), accent, "selected")
		return
	var shape := _chamfer(rect, 42.0, 34.0)
	_glow(shape, accent, 0.8 * alpha)
	_gradient(shape, rect, Color(UiStyle.PANEL.lightened(0.05), 0.97 * alpha), Color(Color("060e0b"), 0.97 * alpha))
	# Cell texture: faint veins along the rim, pores in the upper corners.
	for i in 9:
		var y := rect.position.y + 70 + i * (rect.size.y - 140) / 8.0
		for s: float in [-1.0, 1.0]:
			var x := rect.get_center().x + s * (rect.size.x * 0.5 - 14)
			draw_line(Vector2(x, y), Vector2(x - s * (18 + 10 * sin(i * 1.7)), y + 22), Color(UiStyle.PANEL_EDGE, 0.55 * alpha), 2.0, true)
	for s: float in [-1.0, 1.0]:
		var corner := Vector2(rect.get_center().x + s * (rect.size.x * 0.5 - 70), rect.position.y + 50)
		for pore in [Vector2(0, 0), Vector2(-s * 22, 10), Vector2(-s * 6, 24)]:
			draw_circle(corner + pore, 7, Color(UiStyle.OUTLINE, 0.9 * alpha))
			draw_arc(corner + pore, 7, 0, TAU, 12, Color(accent, 0.35 * alpha), 1.5, true)
	_outline(shape, Color(accent, alpha), 4.0)
	_outline(_inset(shape, rect, 10.0), Color(accent, 0.22 * alpha), 2.0)
	for s: float in [-1.0, 1.0]:
		var top_corner := Vector2(rect.get_center().x + s * (rect.size.x * 0.5 - 30), rect.position.y + 6)
		_claw(top_corner, Vector2(s * 0.55, -1), 44, 11, Color(UiStyle.BONE, alpha), s * 0.55)
		var low := Vector2(rect.get_center().x + s * (rect.size.x * 0.5 - 4), rect.end.y - 60)
		_claw(low, Vector2(s, 0.35), 30, 8, Color(UiStyle.BONE, 0.85 * alpha), -s * 0.4)


func _medallion(c: Vector2, r: float, accent: Color, alpha: float) -> void:
	if alpha <= 0.0:
		return
	draw_circle(c, r + 8, Color(accent, 0.18 * alpha))
	draw_circle(c, r, Color(UiStyle.OUTLINE, 0.97 * alpha))
	draw_circle(c + Vector2(0, -r * 0.18), r * 0.78, Color(UiStyle.PANEL_SOFT, 0.9 * alpha))
	draw_arc(c, r, 0, TAU, 48, Color(accent, alpha), maxf(3.0, r * 0.08), true)
	draw_arc(c, r - maxf(6.0, r * 0.14), 0, TAU, 40, Color(accent, 0.3 * alpha), 1.5, true)


# Sizes may be fractional (zoom): drawn from a palette size, scaled.
func _title(value: String, at: Vector2, font_size: float, color: Color, glow: Color) -> void:
	var font := UiStyle.display_font()
	var step := UiStyle.size_step(font_size)
	var k := font_size / step
	var w := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, step).x * k
	var origin := at - Vector2(w * 0.5, 0)
	draw_set_transform(origin, 0.0, Vector2(k, k))
	draw_string_outline(font, Vector2(0, 5) / k, value, HORIZONTAL_ALIGNMENT_LEFT, -1, step, 16, Color(glow, 0.25 * color.a))
	draw_string_outline(font, Vector2.ZERO, value, HORIZONTAL_ALIGNMENT_LEFT, -1, step, 10, Color(UiStyle.OUTLINE, color.a))
	draw_string(font, Vector2.ZERO, value, HORIZONTAL_ALIGNMENT_LEFT, -1, step, color)
	draw_set_transform(Vector2.ZERO)


func _label(value: String, at: Vector2, font_size: float, color: Color, centered: bool) -> void:
	UiStyle.text_px(self, value, at, font_size, color, centered, 4)


func _rays(c: Vector2, r: float, count: int, spin: float, a: Color, b: Color) -> void:
	if a.a <= 0.0 and b.a <= 0.0:
		return
	for i in count:
		var angle := spin + TAU * i / count
		var width := TAU / count * 0.28
		var tip := r * (1.0 if i % 2 == 0 else 0.72)
		var color := a if i % 2 == 0 else b
		draw_polygon(PackedVector2Array([c, c + Vector2(cos(angle - width), sin(angle - width)) * tip, c + Vector2(cos(angle + width), sin(angle + width)) * tip]), PackedColorArray([color, Color(color, 0.0), Color(color, 0.0)]))


# Soft coloured rim around the whole screen (inner edge transparent).
func _vignette(color: Color, depth: float) -> void:
	if color.a <= 0.0:
		return
	var clear := Color(color, 0.0)
	var o := Vector2.ZERO
	var e := size
	var edges := [
		[o, Vector2(e.x, 0), Vector2(e.x - depth, depth), Vector2(depth, depth)],
		[Vector2(e.x, 0), e, Vector2(e.x - depth, e.y - depth), Vector2(e.x - depth, depth)],
		[e, Vector2(0, e.y), Vector2(depth, e.y - depth), Vector2(e.x - depth, e.y - depth)],
		[Vector2(0, e.y), o, Vector2(depth, depth), Vector2(depth, e.y - depth)],
	]
	for quad in edges:
		draw_polygon(PackedVector2Array(quad), PackedColorArray([color, color, clear, clear]))


# ---------------------------------------------------------------- geometry

# Bevelled rectangle with side notches (the concept's organic card outline).
func _chamfer(rect: Rect2, cut: float, notch: float) -> PackedVector2Array:
	var p := rect.position
	var e := rect.end
	var my := rect.get_center().y
	var pts := PackedVector2Array([Vector2(p.x + cut, p.y), Vector2(e.x - cut, p.y), Vector2(e.x, p.y + cut)])
	if notch > 0.0:
		pts.append_array([Vector2(e.x, my - notch), Vector2(e.x - notch * 0.45, my), Vector2(e.x, my + notch)])
	pts.append_array([Vector2(e.x, e.y - cut), Vector2(e.x - cut, e.y), Vector2(p.x + cut, e.y), Vector2(p.x, e.y - cut)])
	if notch > 0.0:
		pts.append_array([Vector2(p.x, my + notch), Vector2(p.x + notch * 0.45, my), Vector2(p.x, my - notch)])
	pts.append(Vector2(p.x, p.y + cut))
	return pts


func _inset(shape: PackedVector2Array, rect: Rect2, amount: float) -> PackedVector2Array:
	var c := rect.get_center()
	var sx := (rect.size.x * 0.5 - amount) / (rect.size.x * 0.5)
	var sy := (rect.size.y * 0.5 - amount) / (rect.size.y * 0.5)
	var result := PackedVector2Array()
	for point in shape:
		result.append(c + (point - c) * Vector2(sx, sy))
	return result


func _gradient(shape: PackedVector2Array, rect: Rect2, top: Color, bottom: Color) -> void:
	var colors := PackedColorArray()
	for point in shape:
		colors.append(top.lerp(bottom, clampf((point.y - rect.position.y) / maxf(1.0, rect.size.y), 0.0, 1.0)))
	draw_polygon(shape, colors)


func _outline(shape: PackedVector2Array, color: Color, width: float) -> void:
	var closed := shape.duplicate()
	closed.append(shape[0])
	draw_polyline(closed, color, width, true)


func _glow(shape: PackedVector2Array, color: Color, alpha: float) -> void:
	for layer in [[22.0, 0.06], [13.0, 0.12], [7.0, 0.2]]:
		_outline(shape, Color(color, layer[1] * alpha), layer[0])


func _claw(base: Vector2, direction: Vector2, length: float, width: float, color: Color, bend: float) -> void:
	var d := direction.normalized()
	var side := Vector2(-d.y, d.x)
	var points := PackedVector2Array()
	for i in 7:
		var t := i / 6.0
		points.append(base + d * length * t + side * (bend * length * t * t) + side * width * (1.0 - t))
	for i in range(5, -1, -1):
		var t := i / 6.0
		points.append(base + d * length * t + side * (bend * length * t * t) - side * width * (1.0 - t))
	draw_colored_polygon(points, color)


# ---------------------------------------------------------------- icons

const ICON_ALIASES := {
	"skull": ["skull", "schaedel"], "crown": ["crown", "krone"], "clock": ["clock", "uhr"],
	"mawling": ["mawling_head", "mawling"], "pause": ["pause"], "dna": ["dna", "helix"],
	"alpha_core": ["alpha_core", "alpha", "alpha_kern"], "biomass": ["biomass"],
	"fang": ["jaws"], "boss": ["boss", "crown", "krone"],
	"restart": ["restart"], "hub": ["hub"], "play": ["play"],
}


func _icon_id(id: String) -> String:
	if _icons == null:
		return ""
	if not _icon_ids.has(id):
		_icon_ids[id] = ""
		for candidate in ICON_ALIASES.get(id, [id]):
			if bool(_icons.call("has", candidate)):
				_icon_ids[id] = candidate
				break
	return _icon_ids[id]


func _kit(method: String) -> bool:
	return _frames != null and _frame_methods.has(method)


# Scale-in for kit frames (they carry no alpha).
func _pop(rect: Rect2, alpha: float) -> Rect2:
	var k := lerpf(0.86, 1.0, _ease_out(clampf(alpha, 0.0, 1.0)))
	return Rect2(rect.get_center() - rect.size * k * 0.5, rect.size * k)


func _has_icon(id: String) -> bool:
	return _icon_id(id) != ""


func _icon(id: String, rect: Rect2, tint: Color) -> void:
	if tint.a <= 0.0:
		return
	var kit_id := _icon_id(id)
	if kit_id != "":
		_icons.call("draw", self, kit_id, rect, tint)
		return
	var c := rect.get_center()
	var r := rect.size.x * 0.5
	match id:
		"skull":
			_skull(c, r, tint)
		"crown", "boss":
			_crown(c, r, tint)
		"clock":
			draw_arc(c, r * 0.78, 0, TAU, 32, tint, maxf(3.0, r * 0.14), true)
			draw_line(c, c + Vector2(0, -r * 0.5), tint, maxf(3.0, r * 0.12), true)
			draw_line(c, c + Vector2(r * 0.38, r * 0.1), tint, maxf(3.0, r * 0.12), true)
		"mawling":
			_head(c, r, tint)
		"pause":
			draw_rect(Rect2(c + Vector2(-0.55, -0.7) * r, Vector2(0.4, 1.4) * r), tint)
			draw_rect(Rect2(c + Vector2(0.15, -0.7) * r, Vector2(0.4, 1.4) * r), tint)
		"play":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-0.45, -0.7) * r, c + Vector2(0.7, 0) * r, c + Vector2(-0.45, 0.7) * r]), tint)
		"restart":
			draw_arc(c, r * 0.62, -PI * 0.35, PI * 1.45, 24, tint, maxf(3.0, r * 0.2), true)
			var tip := c + Vector2(cos(-PI * 0.35), sin(-PI * 0.35)) * r * 0.62
			draw_colored_polygon(PackedVector2Array([tip + Vector2(0.4, 0.05) * r, tip + Vector2(-0.3, -0.35) * r, tip + Vector2(-0.2, 0.35) * r]), tint)
		"hub":
			for o in [Vector2(-0.34, 0.2), Vector2(0.34, 0.2), Vector2(0, -0.28)]:
				_ellipse(c + o * r, 0.3 * r, 0.4 * r, tint)
		"dna":
			for k in 2:
				var pts := PackedVector2Array()
				for i in 13:
					var y := -0.85 + 1.7 * i / 12.0
					pts.append(c + Vector2(sin(y * 3.7 + k * PI) * 0.4, y) * r)
				draw_polyline(pts, tint, maxf(2.5, r * 0.12), true)
		"alpha_core":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -1) * r, c + Vector2(0.8, 0) * r, c + Vector2(0, 1) * r, c + Vector2(-0.8, 0) * r]), Color(UiStyle.VIOLET, tint.a))
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -0.55) * r, c + Vector2(0.42, 0) * r, c + Vector2(0, 0.55) * r, c + Vector2(-0.42, 0) * r]), Color(UiStyle.AMBER, tint.a))
		"biomass":
			_drop(c, r * 0.62, tint)
		"fang", "jaws":
			for s: float in [-1.0, 1.0]:
				_claw(c + Vector2(s * 0.3, -0.7) * r, Vector2(-s * 0.15, 1), r * 1.3, r * 0.26, tint, -s * 0.25)
		"prey":
			_ellipse(c + Vector2(0, 0.1) * r, 0.7 * r, 0.5 * r, tint)
			draw_circle(c + Vector2(0.55, -0.35) * r, 0.3 * r, tint)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-0.2, -0.35) * r, c + Vector2(0.05, -0.95) * r, c + Vector2(0.2, -0.3) * r]), tint)
		"hunter":
			for i in 3:
				_claw(c + Vector2(-0.55 + i * 0.4, -0.75) * r, Vector2(0.2, 1), r * 1.4, r * 0.2, tint, 0.35)
		"skitter":
			draw_circle(c, 0.4 * r, tint)
			for i in 6:
				var a := PI * 0.15 + i * PI * 0.14 + (PI if i >= 3 else 0.0)
				draw_line(c, c + Vector2(cos(a), sin(a)) * 0.95 * r, tint, maxf(2.0, r * 0.12), true)
		"leaper":
			draw_arc(c + Vector2(0, 0.55) * r, 0.8 * r, PI * 1.1, PI * 1.9, 14, Color(tint, tint.a * 0.6), maxf(2.0, r * 0.1), true)
			_ellipse(c + Vector2(0.1, -0.1) * r, 0.55 * r, 0.35 * r, tint)
			draw_circle(c + Vector2(0.6, -0.35) * r, 0.22 * r, tint)
		_:
			_mutation_glyph(id, c, r, tint)


func _mutation_glyph(id: String, c: Vector2, r: float, tint: Color) -> void:
	match id:
		"brood":
			for o in [Vector2(-0.34, 0.2), Vector2(0.34, 0.2), Vector2(0, -0.28)]:
				_ellipse(c + o * r, 0.3 * r, 0.4 * r, tint)
		"glutton":
			_drop(c, r * 0.6, tint)
		"pack", "meute", "rudelbiss":
			_head(c + Vector2(-0.3, -0.25) * r, r * 0.5, tint.darkened(0.3))
			_head(c + Vector2(0.1, 0.2) * r, r * 0.65, tint)
		"scatter":
			for a in [-2.35, -PI * 0.5, -0.79]:
				var d := Vector2(cos(a), sin(a))
				draw_line(c + Vector2(0, 0.6) * r, c + Vector2(0, 0.6) * r + d * 1.2 * r, tint, maxf(3.0, r * 0.14), true)
		"armor":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -0.9) * r, c + Vector2(0.7, -0.5) * r, c + Vector2(0.55, 0.45) * r, c + Vector2(0, 0.95) * r, c + Vector2(-0.55, 0.45) * r, c + Vector2(-0.7, -0.5) * r]), tint)
		"sporenwolke":
			for s in [[Vector2(0, 0), 0.4], [Vector2(-0.45, 0.2), 0.28], [Vector2(0.45, 0.2), 0.3], [Vector2(0, -0.45), 0.25]]:
				draw_circle(c + s[0] * r, s[1] * r, tint)
		"saeurespucker", "aetzflut":
			_drop(c + Vector2(0.15, 0), r * 0.5, tint)
			for i in 3:
				draw_circle(c + Vector2(-0.4 - i * 0.2, 0.3 + i * 0.12) * r, (0.14 - i * 0.03) * r, tint)
		"stachelruecken":
			for i in 5:
				var a := PI + 0.35 + i * 0.6
				var d := Vector2(cos(a), sin(a))
				var b := c + Vector2(0, 0.4) * r + d * 0.35 * r
				var sd := Vector2(-d.y, d.x)
				draw_colored_polygon(PackedVector2Array([b + sd * 0.14 * r, b - sd * 0.14 * r, b + d * 0.6 * r]), tint)
		_:
			draw_circle(c, 0.5 * r, tint)


func _skull(c: Vector2, r: float, color: Color) -> void:
	var ink := Color(UiStyle.OUTLINE, color.a)
	draw_circle(c + Vector2(0, -0.18) * r, 0.78 * r, color)
	draw_colored_polygon(_chamfer(Rect2(c + Vector2(-0.45, 0.2) * r, Vector2(0.9, 0.6) * r), 0.12 * r, 0.0), color)
	for s: float in [-1.0, 1.0]:
		_ellipse(c + Vector2(s * 0.3, -0.12) * r, 0.22 * r, 0.25 * r, ink)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, 0.14) * r, c + Vector2(0.1, 0.34) * r, c + Vector2(-0.1, 0.34) * r]), ink)
	for i in 3:
		var x := (-0.2 + i * 0.2) * r
		draw_line(c + Vector2(x, 0.52 * r), c + Vector2(x, 0.8 * r), ink, maxf(1.5, r * 0.07))


func _crown(c: Vector2, r: float, color: Color) -> void:
	var k := r / 20.0
	draw_colored_polygon(PackedVector2Array([c + Vector2(-18, 12) * k, c + Vector2(-20, -10) * k, c + Vector2(-9, 0) * k, c + Vector2(0, -15) * k, c + Vector2(9, 0) * k, c + Vector2(20, -10) * k, c + Vector2(18, 12) * k]), color)
	for p in [Vector2(-20, -12), Vector2(0, -17), Vector2(20, -12)]:
		draw_circle(c + p * k, 3.2 * k, color.lightened(0.3))


func _head(c: Vector2, r: float, color: Color) -> void:
	var s := Vector2(r, r)
	var outline := PackedVector2Array()
	for v in [Vector2(-0.95, 0.15), Vector2(-0.85, -0.4), Vector2(-0.5, -0.72), Vector2(-0.05, -0.82), Vector2(0.45, -0.66), Vector2(0.9, -0.42), Vector2(1.05, -0.2), Vector2(1.0, -0.08), Vector2(0.12, 0.06), Vector2(0.86, 0.3), Vector2(0.9, 0.42), Vector2(0.6, 0.6), Vector2(0.05, 0.64), Vector2(-0.5, 0.62), Vector2(-0.86, 0.45)]:
		outline.append(c + v * s)
	draw_colored_polygon(outline, color)
	draw_circle(c + Vector2(0.36, -0.36) * s, r * 0.13, Color(UiStyle.OUTLINE, color.a))


func _drop(c: Vector2, r: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 17:
		var angle := -PI * 0.2 + (PI * 1.4) * i / 16.0
		points.append(c + Vector2(cos(angle), sin(angle)) * r + Vector2(0, r * 0.25))
	points.append(c + Vector2(0, -r * 1.35))
	draw_colored_polygon(points, color)


func _ellipse(c: Vector2, rx: float, ry: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		points.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(points, color)


# ---------------------------------------------------------------- data helpers

func _mutation_color(id: String) -> Color:
	if id in ["aetzflut", "meute"]:
		return UiStyle.VIOLET
	if id in ["rudelbiss", "sporenwolke", "saeurespucker", "stachelruecken", "jaws", "pack"]:
		return UiStyle.EMBER
	if id in ["brood", "glutton"]:
		return UiStyle.CYAN
	if id == "scatter":
		return UiStyle.VIOLET
	return UiStyle.TOXIC


func _kill_color(kind: String) -> Color:
	match kind:
		"prey":
			return UiStyle.CYAN
		"hunter":
			return UiStyle.VIOLET
		"skitter":
			return Color("e46ad0")
		"leaper":
			return UiStyle.TOXIC
		"boss":
			return UiStyle.GOLD
	return UiStyle.TEXT


func _choosing(hud: Control) -> bool:
	return hud.evolution != null and not hud.evolution.offers.is_empty()


func _clock_text(seconds: float) -> String:
	var s := int(seconds)
	return "%02d:%02d" % [s / 60, s % 60]


func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


func _ease_in_out(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)
