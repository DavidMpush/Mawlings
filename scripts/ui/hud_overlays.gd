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
		_push_king()
	_king_seen = moments
	if _king_time >= 0.0:
		_king_time += delta / maxf(0.01, Engine.time_scale)
		if _king_time > KING_TIME or hud.extinct:
			_king_time = -1.0
	_step_milestone(hud, delta / maxf(0.01, Engine.time_scale))
	_step_brawl(hud, delta)
	var key: Variant = _redraw_key(hud)
	if key == null or typeof(key) != typeof(_last_key) or key != _last_key:
		queue_redraw()
	_last_key = key


# null = animating (repaint every frame); otherwise a key of what is shown.
func _redraw_key(hud: Control) -> Variant:
	if UiStyle.is_brawl():
		return _brawl_redraw_key(hud)
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
	var brawl := UiStyle.is_brawl()
	if hud.extinct:
		if brawl:
			_draw_result_backdrop()
		else:
			_draw_result(hud)
		return
	if hud.paused:
		if brawl:
			Kit.dim(self, Rect2(Vector2.ZERO, size), 0.72 * _ease_out(clampf(_pause_time / 0.2, 0.0, 1.0)))
		else:
			_draw_pause(hud)
		return
	if brawl:
		# Polier-Runde: popups, loss number, last-animal text and the boss pointer
		# in kit form (outlined numbers, plates, chevron).
		if _last_one(hud):
			_draw_last_one_brawl(hud)
		_draw_popups_brawl(hud)
		_draw_loss_brawl(hud)
		# Banners, milestones, king and evolution moments are ribbons on the
		# banner layer (stage 15); only the full-screen flash stays here.
		_draw_banner_flash()
		if hud.boss_pointer.is_finite():
			_draw_boss_pointer_brawl(hud)
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
	draw_rect(Rect2(Vector2.ZERO, size), Color(UiStyle.color("dim"), clampf(t / 0.35, 0.0, 1.0) * 0.93))
	_vignette(Color(UiStyle.color("danger"), 0.24 * clampf(t / 0.6, 0.0, 1.0)), 240.0)
	var action: Rect2 = hud._action_rect()
	var panel_top := cy - 572
	var panel := Rect2(cx - 390, panel_top, 780, action.end.y + 34 - panel_top)
	var appear := _ease_out(clampf(t / 0.35, 0.0, 1.0))
	_panel(Rect2(panel.position + Vector2(0, 40.0 * (1.0 - appear)), panel.size), UiStyle.color("danger"), appear)
	# Skull medallion breaks the top edge; title punches in.
	var punch := 1.0 + 0.5 * (1.0 - _ease_out(clampf(t / 0.3, 0.0, 1.0)))
	var skull_c := Vector2(cx, panel.position.y)
	_rays(skull_c, 150.0 * punch, 14, _clock * 0.25, Color(UiStyle.color("danger"), 0.16 * appear), Color(UiStyle.color("ember"), 0.08 * appear))
	_medallion(skull_c, 74.0 * punch, UiStyle.color("danger"), appear)
	_icon("skull", Rect2(skull_c - Vector2(46, 46) * punch, Vector2(92, 92) * punch), Color(UiStyle.color("bone"), appear))
	var title_alpha := clampf((t - 0.1) / 0.25, 0.0, 1.0)
	var title_size := roundf(UiStyle.SIZE_HERO * (1.0 + 0.35 * (1.0 - _ease_out(clampf((t - 0.1) / 0.3, 0.0, 1.0)))))
	_title("AUSGESTORBEN", Vector2(cx, panel.position.y + 150), title_size, Color(UiStyle.color("text"), title_alpha), UiStyle.color("danger"))
	var lost := int(stats.get("lost", 0))
	var sub := "DER SCHWARM IST ERLOSCHEN" if lost <= 0 else "%d MAWLINGS GEFALLEN" % lost
	_label(sub, Vector2(cx, panel.position.y + 190), LABEL, Color(UiStyle.color("text_dim"), title_alpha), true)
	# Survival time: the hero number, counted up from its own timer.
	var seconds := float(stats.get("seconds", hud.elapsed))
	var shown := seconds * _ease_out(clampf((t - 0.35) / 1.0, 0.0, 1.0))
	var time_alpha := clampf((t - 0.3) / 0.2, 0.0, 1.0)
	_label("ÜBERLEBT", Vector2(cx, panel.position.y + 232), LABEL, Color(UiStyle.color("gold"), time_alpha), true)
	_icon("clock", Rect2(cx - 196, panel.position.y + 258, 56, 56), Color(UiStyle.color("gold"), time_alpha))
	_title(_clock_text(shown), Vector2(cx + 24, panel.position.y + 318), 96, Color(UiStyle.color("text"), time_alpha), UiStyle.color("gold"))
	# Four stat tiles, each counting up in turn.
	var tiles := [
		["mawling", "MAX. SCHWARM", float(stats.get("peak_population", hud.peak_population)), UiStyle.color("ember"), false],
		["fang", "KILLS", float(stats.get("kills", hud.kills)), UiStyle.color("cyan"), false],
		["biomass", "BIOMASSE", float(stats.get("biomass", hud.consumed_biomass)), UiStyle.color("amber"), true],
		["crown", "BOSSE", float(stats.get("bosses", 0)), UiStyle.color("gold"), false],
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
		_label("Keine Beute erlegt", Vector2(cx, row_y + 46), LABEL, Color(UiStyle.color("text_dim"), kills_alpha), true)
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
	_label("R / ENTER  ·  H BRUTSTÄTTE", Vector2(cx, panel.end.y + 44), LABEL, Color(UiStyle.color("text_dim"), button_alpha * 0.8), true)


# ---------------------------------------------------------------- pause

func _draw_pause(hud: Control) -> void:
	var t := maxf(0.0, _pause_time)
	var a := _ease_out(clampf(t / 0.25, 0.0, 1.0))
	var cx := size.x * 0.5
	var cy := size.y * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), Color(UiStyle.color("dim"), 0.82 * a))
	var action: Rect2 = hud._action_rect()
	var panel := Rect2(cx - 350, cy - 410, 700, action.position.y - (cy - 410) - 34)
	_panel(Rect2(panel.position + Vector2(0, 24.0 * (1.0 - a)), panel.size), UiStyle.color("cyan"), a)
	var top := panel.position.y + 24.0 * (1.0 - a)
	_medallion(Vector2(cx, top), 56.0, UiStyle.color("cyan"), a)
	_icon("pause", Rect2(cx - 30, top - 30, 60, 60), Color(UiStyle.color("bone"), a))
	_title("PAUSE", Vector2(cx, top + 120), UiStyle.SIZE_HERO, Color(UiStyle.color("text"), a), UiStyle.color("cyan"))
	_label("DIE JAGD WARTET", Vector2(cx, top + 160), LABEL, Color(UiStyle.color("text_dim"), a), true)
	# Run so far: time, swarm, level in three quiet columns.
	var level: int = 0 if hud.evolution == null else int(hud.evolution.level)
	var cols := [
		["clock", "LAUFZEIT", _clock_text(hud.elapsed), UiStyle.color("gold")],
		["mawling", "SCHWARM", "%d" % int(hud.population), UiStyle.color("ember")],
		["dna", "STUFE", "%d" % level, UiStyle.color("cyan")],
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
	_label("P / ESCAPE", Vector2(cx, action.end.y + 52), LABEL, Color(UiStyle.color("text_dim"), 0.8 * a), true)


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
	_rays(c, 360.0 * scale, 18, _clock * 0.6, Color(UiStyle.color("violet"), 0.30 * big), Color(UiStyle.color("gold"), 0.22 * big))
	if not UiStyle.is_calm():
		draw_circle(c, 210.0 * scale, Color(UiStyle.color("violet"), 0.10 * big))
	var ribbon := Rect2(c - Vector2(400, 72) * scale, Vector2(800, 144) * scale)
	_ribbon(ribbon, fade)
	var gem_c := c + Vector2(0, -104) * scale
	_medallion(gem_c, 60.0 * scale, UiStyle.color("gold"), fade)
	_icon("alpha_core", Rect2(gem_c - Vector2(42, 42) * scale, Vector2(84, 84) * scale), Color(1, 1, 1, fade))
	_label("EVOLUTION", c + Vector2(0, -24) * scale, maxf(LABEL, floorf(LABEL * scale * 1.3)), Color(UiStyle.color("gold"), fade), true)
	var name_text := String(hud.evolve_name).to_upper()
	_title(name_text if name_text != "" else "EVOLUTION", c + Vector2(0, 54) * scale, floorf(UiStyle.SIZE_HERO * scale), Color(1, 1, 1, fade), UiStyle.color("violet"))


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
	if UiStyle.is_calm():
		# V2: petrol ribbon, violet top wash and a single broad stroke.
		_gradient(shape, rect, Color(UiStyle.CALM_VIOLET.darkened(0.72), 0.97 * alpha), Color(UiStyle.CALM_BG, 0.97 * alpha))
		_outline(shape, Color(UiStyle.CALM_VIOLET, alpha), 4.0)
		return
	_glow(shape, UiStyle.color("violet"), alpha)
	_gradient(shape, rect, Color(UiStyle.tone(Color("3a1f5c")), 0.96 * alpha), Color(UiStyle.tone(Color("150b22")), 0.96 * alpha))
	_outline(shape, Color(UiStyle.color("gold"), alpha), 4.0)
	var inner := _inset(shape, rect, 9.0)
	_outline(inner, Color(UiStyle.color("violet"), 0.55 * alpha), 2.0)


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
		_push_milestone(mark)
	if _milestone_time >= 0.0:
		_milestone_time += real_delta
		if _milestone_time > MILESTONE_TIME or hud.extinct:
			_milestone_time = -1.0


static func _thousands(value: int) -> String:
	var text := str(value)
	var out := ""
	while text.length() > 3:
		out = "." + text.right(3) + out
		text = text.left(text.length() - 3)
	return text + out


func _milestone_text(mark: int) -> String:
	# Etappe 17b: no limit - big marks read as a swarm count.
	if mark >= 1000:
		return "SCHWARM: %s!" % _thousands(mark)
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
	_rays(c, 260.0 * scale, 14, _clock * 0.7, Color(UiStyle.color("gold"), 0.26 * fade), Color(UiStyle.color("ember_glow"), 0.16 * fade))
	var text := _milestone_text(_milestone)
	var font_size := floorf((58.0 if text.length() < 14 else 48.0) * scale)
	var w := UiStyle.width_px(text, font_size, UiStyle.display_font()) + 120.0 * scale
	var rect := Rect2(c - Vector2(w * 0.5, 52 * scale), Vector2(w, 104 * scale))
	var shape := _chamfer(rect, 22.0 * scale, 0.0)
	if UiStyle.is_calm():
		_gradient(shape, rect, Color(UiStyle.CALM_ORANGE.darkened(0.7), 0.96 * fade), Color(UiStyle.CALM_BG, 0.96 * fade))
		_outline(shape, Color(UiStyle.CALM_ORANGE, fade), 4.0)
	else:
		_glow(shape, UiStyle.color("ember"), fade)
		_gradient(shape, rect, Color(UiStyle.tone(Color("5a2412")), 0.95 * fade), Color(UiStyle.tone(Color("1c0b06")), 0.95 * fade))
		_outline(shape, Color(UiStyle.color("gold"), fade), 4.0)
		_outline(_inset(shape, rect, 8.0), Color(UiStyle.color("ember_glow"), 0.45 * fade), 2.0)
	var badge := c + Vector2(0, -74) * scale
	_medallion(badge, 38.0 * scale, UiStyle.color("gold"), fade)
	_icon("mawling", Rect2(badge - Vector2(26, 26) * scale, Vector2(52, 52) * scale), Color(1, 1, 1, fade))
	_title(text, c + Vector2(0, 20) * scale, font_size, Color(1, 1, 1, fade), UiStyle.color("ember"))


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
	_vignette(Color(UiStyle.color("danger"), 0.3 + 0.25 * beat), 170.0 + 50.0 * beat)
	_vignette(Color(UiStyle.tone(Color("3a0606")), 0.3), 80.0)
	var a := 0.8 + 0.2 * beat
	UiStyle.text_px(self, "LETZTER MAWLING", Vector2(size.x * 0.5, size.y * 0.5 + 200), UiStyle.SIZE_HEAD * (1.0 + 0.06 * beat), Color(UiStyle.color("danger").lightened(0.35), a), true, 8)


# ---------------------------------------------------------------- loss feedback

func _draw_loss(hud: Control) -> void:
	var strength := clampf(float(hud.hit_feedback) / 1.2, 0.0, 1.0)
	if strength > 0.0:
		var pulse := 0.75 + 0.25 * sin(_clock * 14.0)
		_vignette(Color(UiStyle.color("danger"), 0.3 * strength * pulse), 110.0 + 50.0 * strength)
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
	draw_colored_polygon(_chamfer(pill, 16.0 * pop, 0.0), Color(UiStyle.color("outline"), 0.62 * a))
	_icon("mawling", Rect2(x0, c.y - head * 0.5 - 14 * pop, head, head), Color(UiStyle.color("danger"), a))
	UiStyle.text_px(self, number, Vector2(x0 + head + 10, c.y + 8 * pop), fs, Color(UiStyle.tone(Color("ffd9cc")), a), false, 9)
	_label("MAWLINGS", Vector2(c.x, c.y + 44 * pop), LABEL, Color(UiStyle.color("danger").lightened(0.35), a), true)


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
			parts.append(["dna", "+%d" % int(popup.dna), UiStyle.color("cyan")])
		if int(popup.get("biomass", 0)) > 0:
			parts.append(["biomass", "+%d" % int(popup.biomass), UiStyle.brawl_tone("action")["light"]])
		if int(popup.get("amber", 0)) > 0:
			parts.append(["crown_tooth", "+%d" % int(popup.amber), UiStyle.color("amber")])
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
		draw_colored_polygon(_chamfer(pill, 12.0 * pop, 0.0), Color(UiStyle.color("outline"), 0.55 * a))
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
		draw_rect(Rect2(Vector2.ZERO, size), Color(UiStyle.color("gold"), 0.35 * flash))
	_vignette(Color(UiStyle.color("gold"), 0.28 * fade), 150.0)
	var scale := lerpf(1.6, 1.0, burst)
	var c := Vector2(size.x * 0.5, size.y * 0.5 - 420)
	_rays(c, 420.0 * scale, 22, _clock * 0.8, Color(UiStyle.color("gold"), 0.34 * fade), Color(UiStyle.color("ember_glow"), 0.22 * fade))
	if not UiStyle.is_calm():
		draw_circle(c, 230.0 * scale, Color(UiStyle.color("gold"), 0.10 * fade))
	var ribbon := Rect2(c - Vector2(430, 76) * scale, Vector2(860, 152) * scale)
	_ribbon(ribbon, fade)
	var crown_c := c + Vector2(0, -112) * scale
	_medallion(crown_c, 62.0 * scale, UiStyle.color("gold"), fade)
	_icon("crown", Rect2(crown_c - Vector2(40, 40) * scale, Vector2(80, 80) * scale), Color(UiStyle.color("gold"), fade))
	_label("BOG KING", c + Vector2(0, -26) * scale, maxf(LABEL, floorf(LABEL * scale * 1.3)), Color(UiStyle.color("gold"), fade), true)
	_title("KÖNIG VERSCHLUNGEN", c + Vector2(0, 50) * scale, floorf(58 * scale), Color(1, 1, 1, fade), UiStyle.color("gold"))


# ---------------------------------------------------------------- boss pointer

func _draw_boss_pointer(hud: Control) -> void:
	var at: Vector2 = hud.boss_pointer
	var vulnerable: bool = hud.boss_vulnerable
	var accent: Color = UiStyle.color("gold") if vulnerable else UiStyle.color("ember")
	var direction := _pointer_direction(at)
	var side := Vector2(-direction.y, direction.x)
	# Keep medallion plus arrow tip on screen.
	var reach := at + direction * 92.0
	var over := Vector2(maxf(0.0, maxf(12.0 - reach.x, reach.x - size.x + 12.0)), maxf(0.0, maxf(12.0 - reach.y, reach.y - size.y + 12.0)))
	at -= Vector2(signf(direction.x) * over.x, signf(direction.y) * over.y)
	var pulse := 0.5 + 0.5 * sin(_clock * (8.0 if vulnerable else 4.5))
	if not UiStyle.is_calm():
		draw_circle(at, 58 + 6 * pulse, Color(accent, 0.12 + 0.12 * pulse))
	# Arrow first so the medallion rim sits on top of its base.
	var base := at + direction * 30.0
	var tip := at + direction * (82.0 + 6.0 * pulse)
	var arrow := PackedVector2Array([tip + direction * 5.0, base + side * 36.0, base + direction * 14.0, base - side * 36.0])
	draw_colored_polygon(arrow, UiStyle.color("outline"))
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
	draw_colored_polygon(_chamfer(pill, 10.0, 0.0), Color(UiStyle.color("panel"), 0.95))
	_outline(_chamfer(pill, 10.0, 0.0), Color(accent, 0.8), 2.0)
	UiStyle.text(self, label, Vector2(pill.get_center().x, pill.get_center().y + 8), LABEL, accent.lightened(0.3) if vulnerable else UiStyle.color("text"), true, 4)


# Direction from the screen centre to an edge marker; never zero (a zero
# direction collapses the arrow polygon: "Invalid polygon data").
func _pointer_direction(at: Vector2) -> Vector2:
	var d := at - size * 0.5
	return d.normalized() if d.length_squared() > 1.0 else Vector2.UP


# ---------------------------------------------------------------- brawl: popups, loss, pointer

const POP_SIZE := 54        # glyph size of collect numbers (scaled down smoothly)
const POP_REST := 0.8       # resting scale of a collect number (~ 44 px)
const LOSS_SIZE := 64
const LOSS_REST := 0.84


# Outlined kit number scaled smoothly below its glyph size (one glyph cache):
# drawn at `size_px` and fitted into width * k.
func _k_number(at: Vector2, value: String, size_px: int, k: float, color: Color) -> void:
	var font := UiStyle.number_font()
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	Kit.text_outlined(self, at, value, size_px, color, -1, -1, font, Kit.LEFT | Kit.MIDDLE, maxf(1.0, width * minf(k, 1.0)))


func _k_width(value: String, size_px: int, k: float) -> float:
	return UiStyle.number_font().get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x * minf(k, 1.0)


# Kit shapes carry no alpha: popups pop out (shrink) instead of fading.
func _pop_out(t: float, start: float) -> float:
	var u := clampf((t - start) / (1.0 - start), 0.0, 1.0)
	return 1.0 - u * u


# S5 collect counter: one growing "+N" per burst above the swarm. A small icon
# plate (biomass gold, DNA blue) and an outlined number in the tone's light
# colour; every increment restarts a short hop (HuntWorld resets the age).
func _draw_popups_brawl(hud: Control) -> void:
	var popups: Array = hud.get_meta("kill_popups", [])
	var placed: Array = []
	var loss_zone := Rect2()
	if _loss_visible():
		loss_zone = _loss_zone()
		placed.append(loss_zone)
	for popup in popups:
		var t: float = popup.get("t", 1.0)
		if t >= 1.0:
			continue
		# Etappe 17 Welle 2: Bernstein gold (loot), Biomasse green (action), DNA blue (info).
		var parts: Array = []
		if int(popup.get("amber", 0)) > 0:
			parts.append(["loot", "crown_tooth", "+%d" % int(popup.amber)])
		if int(popup.get("biomass", 0)) > 0:
			parts.append(["action", "biomass", "+%d" % int(popup.biomass)])
		if int(popup.get("dna", 0)) > 0:
			parts.append(["info", "dna", "+%d" % int(popup.dna)])
		if parts.is_empty():
			continue
		var out := _pop_out(t, 0.72)
		if out <= 0.3:
			continue
		# Hop: the first 16 % of the life pops the number up and settles it back.
		var hop := sin(PI * clampf(t / 0.16, 0.0, 1.0))
		var k := POP_REST * (1.0 + 0.24 * hop) * out
		var c: Vector2 = popup.get("screen", Vector2.ZERO) - Vector2(0, 56.0 * _ease_out(clampf((t - 0.4) / 0.6, 0.0, 1.0)) + 10.0 * hop)
		var plate := 46.0 * k
		var gap := 18.0 * k
		var widths: Array = []
		var total := 0.0
		for part in parts:
			var w: float = plate + 6.0 * k + _k_width(part[2], POP_SIZE, k)
			widths.append(w)
			total += w
		total += gap * (parts.size() - 1)
		var box := Rect2(c.x - total * 0.5 - 8.0, c.y - plate * 0.6, total + 16.0, plate * 1.2)
		var moved := _avoid(box, placed, loss_zone)
		placed.append(moved)
		c += moved.get_center() - box.get_center()
		var x := c.x - total * 0.5
		for index in parts.size():
			var part: Array = parts[index]
			var pc := Vector2(x + plate * 0.5, c.y)
			Kit.icon_plate(self, pc, plate, part[0])
			_icon(part[1], Rect2(Kit.plate_center(pc, plate) - Vector2.ONE * plate * 0.36, Vector2.ONE * plate * 0.72), Color.WHITE)
			var tone: Dictionary = UiStyle.brawl_tone(part[0])
			_k_number(Vector2(x + plate + 6.0 * k, c.y), part[2], POP_SIZE, k, tone["light"].lerp(Color.WHITE, 0.25))
			x += float(widths[index]) + gap


# Lost Mawlings: "-N" in danger colours next to a small Mawling plate, a hop
# on every new hit, "MAWLINGS" below. Sits fixed above the swarm.
func _draw_loss_brawl(hud: Control) -> void:
	var strength := clampf(float(hud.hit_feedback) / 1.2, 0.0, 1.0)
	var danger: Dictionary = UiStyle.brawl_tone("danger")
	if strength > 0.0:
		var pulse := 0.75 + 0.25 * sin(_clock * 14.0)
		_vignette(Color(danger["face"], 0.26 * strength * pulse), 110.0 + 50.0 * strength)
	if not _loss_visible():
		return
	var out := _pop_out(_loss_age / 1.35, 0.75)
	if out <= 0.3:
		return
	var hop := sin(PI * clampf(_loss_age / 0.18, 0.0, 1.0))
	var k := LOSS_REST * (1.0 + 0.22 * hop) * out
	var c := _loss_center() + Vector2(0, -8.0 * hop)
	var number := "−%d" % _loss_total
	var plate := 58.0 * k
	var total := plate + 8.0 * k + _k_width(number, LOSS_SIZE, k)
	var x0 := c.x - total * 0.5
	var pc := Vector2(x0 + plate * 0.5, c.y)
	Kit.icon_plate(self, pc, plate, "danger")
	_icon("mawling", Rect2(Kit.plate_center(pc, plate) - Vector2.ONE * plate * 0.36, Vector2.ONE * plate * 0.72), Color.WHITE)
	_k_number(Vector2(x0 + plate + 8.0 * k, c.y), number, LOSS_SIZE, k, danger["light"].lerp(Color.WHITE, 0.35))
	if out > 0.6:
		Kit.text_outlined(self, Vector2(c.x, c.y + 46.0 * k), "MAWLINGS", UiStyle.T_LABEL, danger["light"].lerp(Color.WHITE, 0.5), -1, -1, null, Kit.CENTER | Kit.MIDDLE)


# Only one Mawling left: heartbeat vignette plus a danger ribbon with outlined text.
func _draw_last_one_brawl(_hud: Control) -> void:
	var phase := fmod(_clock, 0.92)
	var beat := exp(-phase * 14.0) + 0.7 * exp(-maxf(0.0, phase - 0.29) * 14.0) * (1.0 if phase >= 0.29 else 0.0)
	beat = clampf(beat, 0.0, 1.0)
	var danger: Dictionary = UiStyle.brawl_tone("danger")
	_vignette(Color(danger["face"], 0.26 + 0.22 * beat), 170.0 + 50.0 * beat)
	_vignette(Color(danger["dark"].darkened(0.6), 0.3), 80.0)
	var c := Vector2(size.x * 0.5, size.y * 0.5 + 210.0)
	var font := UiStyle.display_font()
	var label := "LETZTER MAWLING"
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.T_TITLE).x
	var k := 0.8 * (1.0 + 0.05 * beat)
	var band := Rect2(c.x - w * k * 0.5 - 70.0, c.y - 42.0 * k, w * k + 140.0, 84.0 * k)
	Kit.ribbon(self, band, "danger")
	Kit.text_outlined(self, c + Vector2(0, -3.0 * k), label, UiStyle.T_TITLE, Color.WHITE, -1, -1, font, Kit.CENTER | Kit.MIDDLE, w * k)


# Off-screen boss: kit plate with the crown, a chevron towards the boss, a soft
# halo that beats faster while it is vulnerable, and an outlined label.
func _draw_boss_pointer_brawl(hud: Control) -> void:
	var at: Vector2 = hud.boss_pointer
	var vulnerable: bool = hud.boss_vulnerable
	var tone := "loot" if vulnerable else "danger"
	var direction := _pointer_direction(at)
	var plate := 80.0
	var r := plate * 0.5
	# Keep plate plus chevron on screen.
	var reach := at + direction * (r + 44.0)
	var over := Vector2(maxf(0.0, maxf(12.0 - reach.x, reach.x - size.x + 12.0)), maxf(0.0, maxf(12.0 - reach.y, reach.y - size.y + 12.0)))
	at -= Vector2(signf(direction.x) * over.x, signf(direction.y) * over.y)
	var pulse := 0.5 + 0.5 * sin(_clock * (8.0 if vulnerable else 4.5))
	Kit.glow(self, at, r + 30.0 + 8.0 * pulse, tone, 0.35 + 0.3 * pulse)
	Kit.chevron(self, at + direction * (r + 22.0 + 4.0 * pulse), direction, 34.0, tone)
	Kit.icon_plate(self, at, plate, tone)
	_icon("crown", Rect2(Kit.plate_center(at, plate) - Vector2(28, 28), Vector2(56, 56)), Color.WHITE)
	var label := "VERWUNDBAR!" if vulnerable else "BOG KING"
	var label_y := at.y + (-r - 30.0 if direction.y > 0.6 else r + 30.0)
	var font := UiStyle.display_font()
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.T_BODY).x
	var lx := clampf(at.x, w * 0.5 + 14.0, size.x - w * 0.5 - 14.0)
	Kit.text_outlined(self, Vector2(lx, label_y), label, UiStyle.T_BODY, UiStyle.brawl_tone("loot")["light"] if vulnerable else Color.WHITE, -1, -1, font, Kit.CENTER | Kit.MIDDLE)


# ---------------------------------------------------------------- building blocks

func _stat_tile(rect: Rect2, icon: String, label: String, value: String, accent: Color, alpha: float) -> void:
	if _kit("panel"):
		_frames.call("panel", self, _pop(rect, alpha), accent, false)
	else:
		var shape := _chamfer(rect, 14.0, 0.0)
		_gradient(shape, rect, Color(UiStyle.color("panel_soft").lightened(0.04), 0.95 * alpha), Color(UiStyle.color("outline"), 0.95 * alpha))
		_outline(shape, Color(accent, 0.75 * alpha), 2.5)
	draw_line(rect.position + Vector2(18, 3), Vector2(rect.end.x - 18, rect.position.y + 3), Color(accent, 0.35 * alpha), 3.0)
	_icon(icon, Rect2(rect.get_center().x - 22, rect.position.y + 12, 44, 44), Color(accent, alpha))
	var fs := UiStyle.SIZE_TITLE
	var font := UiStyle.display_font()
	while fs > 30 and font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > rect.size.x - 16:
		fs -= 2
	UiStyle.text(self, value, Vector2(rect.get_center().x, rect.position.y + 58 + fs * 0.82), fs, Color(UiStyle.color("text"), alpha), true, 6)
	# Narrow tiles keep 22 px and switch to a short label instead of shrinking.
	var shown := label
	if font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL).x > rect.size.x - 12:
		shown = SHORT_LABEL.get(label, label)
	_label(shown, Vector2(rect.get_center().x, rect.end.y - 14), LABEL, Color(accent.lerp(UiStyle.color("text"), 0.35), alpha), true)


func _kill_chip(rect: Rect2, kind: String, count: int, alpha: float) -> void:
	if alpha <= 0.0:
		return
	var accent := _kill_color(kind)
	if _kit("pill"):
		_frames.call("pill", self, _pop(rect, alpha), accent)
	else:
		var shape := _chamfer(rect, 12.0, 0.0)
		draw_colored_polygon(shape, Color(UiStyle.color("outline"), 0.9 * alpha))
		_outline(shape, Color(accent, 0.6 * alpha), 2.0)
	if kind == "boss" and _has_icon("portrait_bog_king"):
		# V2 Bog King portrait (painted, untinted) instead of the crown glyph.
		_icon("portrait_bog_king", Rect2(rect.position.x + 4, rect.get_center().y - 27, 52, 52), Color(1, 1, 1, alpha))
	else:
		_icon(kind, Rect2(rect.position.x + 8, rect.get_center().y - 22, 44, 44), Color(accent, alpha))
	UiStyle.text(self, "×%d" % count, Vector2(rect.position.x + 58, rect.get_center().y + 13), UiStyle.SIZE_HEAD, Color(UiStyle.color("text"), alpha), false, 5)


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
		_label("Keine Mutationen gewählt", center + Vector2(0, 8), UiStyle.SIZE_BODY, Color(UiStyle.color("text_dim"), alpha), true)
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
		if evolved and not UiStyle.is_calm():
			draw_circle(c, r + 12, Color(UiStyle.color("violet"), 0.25 * a))
		_medallion(c, r, UiStyle.color("gold") if evolved else accent, a)
		_icon(id, Rect2(c - Vector2(r, r) * 0.72, Vector2(r, r) * 1.44), Color(accent, a) if not _has_icon(id) else Color(1, 1, 1, a))
		if evolved:
			_label("EVO", c + Vector2(0, r + 30), LABEL, Color(UiStyle.color("gold"), a), true)
			continue
		for k in 3:
			var pc := c + Vector2((k - 1) * 18.0, r + 20)
			var diamond := PackedVector2Array([pc + Vector2(0, -9), pc + Vector2(7, 0), pc + Vector2(0, 9), pc + Vector2(-7, 0)])
			draw_colored_polygon(diamond, Color(UiStyle.color("outline"), a))
			var inner := PackedVector2Array([pc + Vector2(0, -6), pc + Vector2(4.5, 0), pc + Vector2(0, 6), pc + Vector2(-4.5, 0)])
			draw_colored_polygon(inner, Color(accent, a) if k < int(build[i][1]) else Color(accent, 0.22 * a))


func _button(rect: Rect2, label: String, kind: String, alpha: float, icon: String) -> void:
	if alpha <= 0.0:
		return
	var primary := kind == "primary"
	var accent: Color = UiStyle.color("ember") if primary else UiStyle.color("toxic")
	if _kit("button"):
		_frames.call("button", self, _pop(rect, alpha), kind, false)
	else:
		if primary:
			var breathe := 0.5 + 0.5 * sin(_clock * 3.0)
			_glow(_chamfer(rect.grow(4), 20.0, 0.0), accent, (0.5 + 0.5 * breathe) * alpha)
		var shape := _chamfer(rect, 18.0, 0.0)
		var top: Color = UiStyle.tone(Color("c4541f")) if primary else UiStyle.tone(Color("1f4a37"))
		var bottom: Color = UiStyle.tone(Color("6e260d")) if primary else UiStyle.tone(Color("0c2219"))
		_gradient(shape, rect, Color(top, alpha), Color(bottom, alpha))
		draw_colored_polygon(_chamfer(Rect2(rect.position + Vector2(10, 6), Vector2(rect.size.x - 20, rect.size.y * 0.38)), 12.0, 0.0), Color(1, 1, 1, 0.10 * alpha))
		_outline(shape, Color(accent.lightened(0.2), alpha), 3.5)
		_outline(_chamfer(rect.grow(-7), 13.0, 0.0), Color(UiStyle.color("outline"), 0.45 * alpha), 2.0)
		for s: float in [-1.0, 1.0]:
			var corner := Vector2(rect.get_center().x + s * rect.size.x * 0.5, rect.position.y)
			_claw(corner + Vector2(-s * 24, 4), Vector2(s * 0.5, -1), 20, 6, Color(UiStyle.color("bone"), alpha), s * 0.5)
	var font := UiStyle.display_font()
	var fs := UiStyle.SIZE_HEAD
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var icon_w := 40.0
	var x := rect.get_center().x - (w + icon_w + 10) * 0.5
	_icon(icon, Rect2(x, rect.get_center().y - icon_w * 0.5, icon_w, icon_w), Color(UiStyle.color("text"), alpha))
	UiStyle.text(self, label, Vector2(x + icon_w + 10, rect.get_center().y + fs * 0.36), fs, Color(UiStyle.color("text"), alpha), false, 6)


func _divider(center: Vector2, half: float, label: String, alpha: float) -> void:
	if alpha <= 0.0:
		return
	var font := UiStyle.display_font()
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL).x * 0.5
	if _kit("divider"):
		_frames.call("divider", self, center + Vector2(0, -7), half * 2.0, Color(UiStyle.color("bone"), alpha), w * 2.0 + 28.0, 0.6)
		_label(label, center, LABEL, Color(UiStyle.color("text_dim"), alpha), true)
		return
	for s: float in [-1.0, 1.0]:
		var a := Vector2(center.x + s * (w + 16), center.y - 7)
		var b := Vector2(center.x + s * half, center.y - 7)
		draw_line(a, b, Color(UiStyle.color("panel_edge").lightened(0.25), alpha), 2.0, true)
		draw_colored_polygon(PackedVector2Array([b + Vector2(0, -5), b + Vector2(s * 6, 0), b + Vector2(0, 5), b - Vector2(s * 6, 0)]), Color(UiStyle.color("bone"), 0.7 * alpha))
	_label(label, center, LABEL, Color(UiStyle.color("text_dim"), alpha), true)


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
	_gradient(shape, rect, Color(UiStyle.color("panel").lightened(0.05), 0.97 * alpha), Color(UiStyle.tone(Color("060e0b")), 0.97 * alpha))
	# Cell texture: faint veins along the rim, pores in the upper corners.
	for i in 9:
		var y := rect.position.y + 70 + i * (rect.size.y - 140) / 8.0
		for s: float in [-1.0, 1.0]:
			var x := rect.get_center().x + s * (rect.size.x * 0.5 - 14)
			draw_line(Vector2(x, y), Vector2(x - s * (18 + 10 * sin(i * 1.7)), y + 22), Color(UiStyle.color("panel_edge"), 0.55 * alpha), 2.0, true)
	for s: float in [-1.0, 1.0]:
		var corner := Vector2(rect.get_center().x + s * (rect.size.x * 0.5 - 70), rect.position.y + 50)
		for pore in [Vector2(0, 0), Vector2(-s * 22, 10), Vector2(-s * 6, 24)]:
			draw_circle(corner + pore, 7, Color(UiStyle.color("outline"), 0.9 * alpha))
			draw_arc(corner + pore, 7, 0, TAU, 12, Color(accent, 0.35 * alpha), 1.5, true)
	_outline(shape, Color(accent, alpha), 4.0)
	_outline(_inset(shape, rect, 10.0), Color(accent, 0.22 * alpha), 2.0)
	for s: float in [-1.0, 1.0]:
		var top_corner := Vector2(rect.get_center().x + s * (rect.size.x * 0.5 - 30), rect.position.y + 6)
		_claw(top_corner, Vector2(s * 0.55, -1), 44, 11, Color(UiStyle.color("bone"), alpha), s * 0.55)
		var low := Vector2(rect.get_center().x + s * (rect.size.x * 0.5 - 4), rect.end.y - 60)
		_claw(low, Vector2(s, 0.35), 30, 8, Color(UiStyle.color("bone"), 0.85 * alpha), -s * 0.4)


func _medallion(c: Vector2, r: float, accent: Color, alpha: float) -> void:
	if alpha <= 0.0:
		return
	if UiStyle.is_calm():
		# V2: octagonal petrol plate with one broad accent stroke, no glow.
		var plate := _chamfer(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), r * 0.42, 0.0)
		draw_colored_polygon(plate, Color(UiStyle.CALM_BG, 0.97 * alpha))
		_outline(plate, Color(accent, alpha), maxf(3.0, r * 0.07))
		return
	draw_circle(c, r + 8, Color(accent, 0.18 * alpha))
	draw_circle(c, r, Color(UiStyle.color("outline"), 0.97 * alpha))
	draw_circle(c + Vector2(0, -r * 0.18), r * 0.78, Color(UiStyle.color("panel_soft"), 0.9 * alpha))
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
	if not UiStyle.is_calm():
		draw_string_outline(font, Vector2(0, 5) / k, value, HORIZONTAL_ALIGNMENT_LEFT, -1, step, 16, Color(glow, 0.25 * color.a))
	draw_string_outline(font, Vector2.ZERO, value, HORIZONTAL_ALIGNMENT_LEFT, -1, step, 10, Color(UiStyle.color("outline"), color.a))
	draw_string(font, Vector2.ZERO, value, HORIZONTAL_ALIGNMENT_LEFT, -1, step, UiStyle.tone(color))
	draw_set_transform(Vector2.ZERO)


func _label(value: String, at: Vector2, font_size: float, color: Color, centered: bool) -> void:
	UiStyle.text_px(self, value, at, font_size, color, centered, 4)


func _rays(c: Vector2, r: float, count: int, spin: float, a: Color, b: Color) -> void:
	if UiStyle.is_calm():
		# Glow only as a small, short layer: fewer, fainter, shorter rays.
		a = Color(UiStyle.tone(a), a.a * 0.35)
		b = Color(UiStyle.tone(b), 0.0)
		r *= 0.7
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
	if UiStyle.is_calm():
		_outline(shape, Color(color, 0.12 * alpha), 8.0)
		return
	for layer in [[22.0, 0.06], [13.0, 0.12], [7.0, 0.2]]:
		_outline(shape, Color(color, layer[1] * alpha), layer[0])


func _claw(base: Vector2, direction: Vector2, length: float, width: float, color: Color, bend: float) -> void:
	if UiStyle.is_calm():
		return
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
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -1) * r, c + Vector2(0.8, 0) * r, c + Vector2(0, 1) * r, c + Vector2(-0.8, 0) * r]), Color(UiStyle.color("violet"), tint.a))
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -0.55) * r, c + Vector2(0.42, 0) * r, c + Vector2(0, 0.55) * r, c + Vector2(-0.42, 0) * r]), Color(UiStyle.color("amber"), tint.a))
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
	var ink := Color(UiStyle.color("outline"), color.a)
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
	draw_circle(c + Vector2(0.36, -0.36) * s, r * 0.13, Color(UiStyle.color("outline"), color.a))


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
		return UiStyle.color("violet")
	if id in ["rudelbiss", "sporenwolke", "saeurespucker", "stachelruecken", "jaws", "pack"]:
		return UiStyle.color("ember")
	if id in ["brood", "glutton"]:
		return UiStyle.color("cyan")
	if id == "scatter":
		return UiStyle.color("violet")
	return UiStyle.color("toxic")


func _kill_color(kind: String) -> Color:
	match kind:
		"prey":
			return UiStyle.color("cyan")
		"hunter":
			return UiStyle.color("violet")
		"skitter":
			return UiStyle.tone(Color("e46ad0"))
		"leaper":
			return UiStyle.color("toxic")
		"boss":
			return UiStyle.color("gold")
	return UiStyle.color("text")


func _choosing(hud: Control) -> bool:
	return hud.evolution != null and not hud.evolution.offers.is_empty()


func _clock_text(seconds: float) -> String:
	var s := int(seconds)
	return "%02d:%02d" % [s / 60, s % 60]


func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


func _ease_in_out(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


# ================================================================ brawl skin (stage 15, package D)
#
# Result, pause and every in-run banner in the Supercell-style kit. The pieces
# live on UiLayer children (drawn after this node): each section has its own
# modulate/position/scale, so the kit blocks (which carry no alpha) can fade,
# slide and pop. Input stays in touch_controls.gd; the buttons are drawn on
# its _action_rect() / _hub_rect() / _share_rect() / _restart_rect().
#
# Result timeline (Höhepunkt – Ruhe – Auswertung, S10/S13):
#   0.0  danger vignette over the still visible world (the moment)
#   0.3  the world dims; 0.45 ribbon "AUSGESTORBEN" punches in
#   0.8  survival time counts up (gold panel + badge on a new record)
#   1.15 stat tiles, 1.55 build + essence, 1.85 tasks (bars fill from the
#        progress before this run to the progress after it)
#   0.9  buttons (live from the first frame, they are the touch areas)
#
# Banners: one ribbon at a time in the upper quarter (never the centre),
# queued. Tones: flood/boss = danger, migration = info, victory/milestone =
# loot, evolution = special, leader = ember. Flood start, apex victory and
# arrival are still drawn by hud_flood / hud_objectives; this file draws them
# once that component sets `banners_in_overlays = true` (or is missing).

const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")
const UiLayer := preload("res://scripts/ui/ui_layer.gd")
const PROFILE_PATH := "res://scripts/meta/profile.gd"
const META_PATH := "res://scripts/meta/meta_data.gd"
const SHARE_PATH := "res://scripts/ui/share_card.gd"
const BASE_H := 1600.0
const BANNER_Y := 400.0          # banner centre below the top HUD (upper quarter)
const BANNER_TIME := 1.9         # real seconds per banner (queued ones get less)
const BANNER_TITLE_W := 560.0
const HANDOVER := {"flood": "hud_flood", "victory": "hud_objectives", "arrival": "hud_objectives"}
# Same card tones as mutation_screen.gd (attack forms ember, evolutions special).
const BRANCH_OF := {
	"jaws": "attack", "pack": "attack",
	"brood": "growth", "glutton": "growth", "lockduft": "growth",
	"armor": "protect", "regeneration": "protect", "dornenhaut": "protect",
	"scatter": "special",
}
const BRANCH_TONE := {"attack": "ember", "growth": "info", "protect": "action", "special": "special"}
const ROMAN := ["I", "II", "III", "IV", "V"]
# Section -> start time of its entry on the result screen.
const R_SECTIONS := {"r_title": 0.45, "r_hero": 0.8, "r_stats": 1.15, "r_build": 1.55, "r_tasks": 1.85, "r_buttons": 0.9}
const R_COUNT := 0.7             # count-up duration of numbers
const R_BARS := 0.35             # task bars start this long after the task panel

## Captures/tests: profile used for record and task preview instead of the
## saved one (it is copied, never saved).
var result_profile: RefCounted = null
## Captures: draw the handed-over banner kinds too.
var force_banners := false

var _b: Dictionary = {}
var _res: Dictionary = {}
var _queue: Array = []
var _banner: Dictionary = {}
var _banner_t := 0.0
var _flash := {}
var _seen: Dictionary = {}
var _share_state := ""
var _share_t := 0.0
var _world_node: Node


# ---------------------------------------------------------------- layers and stepping

func _ensure_layers() -> void:
	if not _b.is_empty():
		return
	for id in ["r_title", "r_hero", "r_stats", "r_build", "r_tasks", "r_buttons", "pause", "banner"]:
		var layer := UiLayer.make(self, "B_" + id, Callable(self, "_paint_" + id))
		layer.visible = false
		_b[id] = layer


func _oy() -> float:
	return (size.y - BASE_H) * 0.5


func _step_brawl(hud: Control, delta: float) -> void:
	if not UiStyle.is_brawl():
		for layer in _b.values():
			layer.visible = false
		return
	_ensure_layers()
	var real := delta / maxf(0.01, Engine.time_scale)
	# Result
	if hud.extinct and _res.is_empty():
		_res = _result_data(hud)
	elif not hud.extinct:
		_res = {}
		_share_state = ""
	if _share_state in ["saved", "failed"]:
		_share_t += real
		if _share_t > 2.5:
			_share_state = ""
	for id in R_SECTIONS:
		_step_section(id, hud.extinct)
	# Pause
	var pause: Control = _b.pause
	var pa := _ease_out(clampf(_pause_time / 0.22, 0.0, 1.0)) if hud.paused and not hud.extinct else 0.0
	pause.visible = pa > 0.0
	if pause.visible:
		pause.modulate.a = pa
		pause.pivot_offset = Vector2(size.x * 0.5, _oy() + 760.0)
		pause.scale = Vector2.ONE * lerpf(0.9, 1.0, pa)
		var evo: Variant = hud.evolution
		pause.refresh([size, int(hud.elapsed), int(hud.population), str(evo.ranks) if evo != null else "", str(evo.evolutions) if evo != null else "", int(evo.level) if evo != null else 0])
	# Banners
	_detect_banners(hud)
	_step_banner(hud, real)


func _step_section(id: String, shown: bool) -> void:
	var layer: Control = _b[id]
	var t := _result_time
	var a := clampf((t - float(R_SECTIONS[id])) / 0.28, 0.0, 1.0) if shown else 0.0
	layer.visible = a > 0.0
	if not layer.visible:
		return
	var e := _ease_out(a)
	layer.modulate.a = e
	if id == "r_title":
		layer.pivot_offset = Vector2(size.x * 0.5, _oy() + 112.0)
		layer.scale = Vector2.ONE * lerpf(1.7, 1.0, _ease_back(a))
		layer.position = Vector2.ZERO
	else:
		layer.position = Vector2(0.0, 34.0 * (1.0 - e))
	var key: Array = [size]
	match id:
		"r_hero":
			key.append_array([int(_count(0.9, 1.0) * 200.0), bool(_res.get("record", false)) and t > 2.0, int(clampf((t - 2.0) / 0.25, 0.0, 1.0) * 20.0)])
		"r_stats":
			key.append(int(_count(1.2, R_COUNT + 0.3) * 100.0))
		"r_build":
			key.append(int(clampf((t - 1.55) / 0.6, 0.0, 1.0) * 20.0))
		"r_tasks":
			key.append(int(_count(float(R_SECTIONS.r_tasks) + R_BARS, 0.8) * 120.0))
		"r_buttons":
			key.append(_share_state)
	layer.refresh(key)


# 0..1 progress of a count-up that starts at `start` and runs `span` seconds.
func _count(start: float, span: float) -> float:
	return _ease_out(clampf((_result_time - start) / span, 0.0, 1.0))


func _brawl_redraw_key(hud: Control) -> Variant:
	if hud.extinct:
		return null if _result_time < 1.0 else ["result", size]
	if hud.paused:
		return null if _pause_time < 0.3 else ["pause", size]
	var popups: Array = hud.get_meta("kill_popups", [])
	for popup in popups:
		if float(popup.get("t", 1.0)) < 1.0:
			return null
	if _loss_visible() or float(hud.hit_feedback) > 0.0 or not _flash.is_empty() or _last_one(hud) or hud.boss_pointer.is_finite():
		return null
	return ["idle", size]


# ---------------------------------------------------------------- result data

func _result_data(hud: Control) -> Dictionary:
	var stats: Dictionary = hud.run_stats if hud.run_stats is Dictionary else {}
	var d := {
		"stats": stats,
		"seconds": float(stats.get("seconds", hud.elapsed)),
		"peak": int(stats.get("peak_population", hud.peak_population)),
		"kills": int(stats.get("kills", hud.kills)),
		"biomass": int(float(stats.get("biomass", hud.consumed_biomass))),
		"bosses": int(stats.get("bosses", 0)) + int(stats.get("apex_kills", 0)),
		"lost": int(stats.get("lost", 0)),
		"build": _build(hud, stats),
		"record": false, "record_peak": false, "tasks": [],
		"essence": 0, "crowns": 0, "context": "",
	}
	var meta: Variant = load(META_PATH) if ResourceLoader.exists(META_PATH) else null
	var profile_script: Variant = load(PROFILE_PATH) if ResourceLoader.exists(PROFILE_PATH) else null
	if meta != null:
		var strain: Dictionary = meta.STRAINS.get(String(stats.get("strain_id", "")), {})
		var diff := int(stats.get("difficulty", -1))
		var parts: Array = []
		if not strain.is_empty():
			parts.append(String(strain.get("name", "")))
		if diff >= 0 and diff < meta.DIFFICULTIES.size():
			parts.append(String(meta.DIFFICULTIES[diff].name))
		d.context = " · ".join(parts)
	if profile_script == null or meta == null:
		return d
	d.essence = int(profile_script.run_essence(stats))
	d.crowns = int(profile_script.run_crowns(stats))
	var source: RefCounted = result_profile if result_profile != null else profile_script.load_or_create()
	if source != null:
		_task_preview(d, source, profile_script, meta, stats)
	return d


# Record flags and the three next open tasks (S13), read-only: works on an
# in-memory copy of the profile that books this run the way record_run() will.
func _task_preview(d: Dictionary, source: RefCounted, profile_script: Variant, meta: Variant, stats: Dictionary) -> void:
	var copy: RefCounted = profile_script.new()
	copy._apply(source.to_dict())
	var records: Dictionary = copy.records
	var runs := int(records.get("runs", 0))
	d.record = runs > 0 and float(d.seconds) > float(records.get("best_seconds", 0.0)) + 0.01
	d.record_peak = runs > 0 and int(d.peak) > int(records.get("best_peak", 0))
	var before := {}
	for q in meta.QUESTS:
		if not copy.completed_quests.has(q.id):
			before[q.id] = copy.quest_value(q.stat)
	copy._update_records(stats)
	var list: Array = []
	for q in meta.QUESTS:
		if not before.has(q.id):
			continue
		var target := maxf(1.0, float(q.target))
		var now: float = copy.quest_value(q.stat)
		list.append({"q": q, "from": clampf(float(before[q.id]) / target, 0.0, 1.0), "to": clampf(now / target, 0.0, 1.0), "value": now, "done": now >= target})
	list.sort_custom(_task_order)
	d.tasks = list.slice(0, 3)
	for task in d.tasks:
		if task.done:
			d.essence += int(task.q.reward.get("essence", 0))
			d.crowns += int(task.q.reward.get("crowns", 0))


# Completed by this run first, then the closest open ones, then the smaller goal.
static func _task_order(a: Dictionary, b: Dictionary) -> bool:
	if a.done != b.done:
		return a.done
	if not is_equal_approx(a.to, b.to):
		return a.to > b.to
	return float(a.q.target) < float(b.q.target)


# ---------------------------------------------------------------- result painters

func _draw_result_backdrop() -> void:
	var t := _result_time
	var danger: Dictionary = UiStyle.brawl_tone("danger")
	# The moment: a hard danger rim over the still visible world, then calm.
	var hit := 1.0 - clampf((t - 0.25) / 0.6, 0.0, 1.0)
	_vignette(Color(danger.face, 0.55 * hit + 0.16), 260.0)
	Kit.dim(self, Rect2(Vector2.ZERO, size), 0.8 * _ease_out(clampf((t - 0.3) / 0.5, 0.0, 1.0)))


func _paint_r_title(c: CanvasItem) -> void:
	if _res.is_empty():
		return
	var cx := size.x * 0.5
	var rect := Rect2(cx - 300.0, _oy() + 60.0, 600.0, 104.0)
	Kit.ribbon(c, rect, "danger")
	Kit.text_outlined(c, Vector2(cx, rect.get_center().y - 2.0), "AUSGESTORBEN", UiStyle.T_HERO, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE, rect.size.x - 40.0)
	var lost := int(_res.lost)
	var sub := "DER SCHWARM IST ERLOSCHEN" if lost <= 0 else "%s MAWLINGS GEFALLEN" % Kit.format_int(lost)
	if String(_res.context) != "":
		sub += "  ·  " + String(_res.context).to_upper()
	Kit.text_outlined(c, Vector2(cx, _oy() + 214.0), sub, UiStyle.T_LABEL, UiStyle.BRAWL_TEXT_DIM, -1, -1, null, Kit.CENTER | Kit.MIDDLE, 780.0)


func _paint_r_hero(c: CanvasItem) -> void:
	if _res.is_empty():
		return
	var t := _result_time
	var cx := size.x * 0.5
	var rect := Rect2(cx - 300.0, _oy() + 244.0, 600.0, 150.0)
	var gold: bool = bool(_res.record) and t > 2.0
	Kit.panel(c, rect, "loot" if gold else "dark", UiStyle.R_L)
	var pc := Vector2(rect.position.x + 84.0, rect.get_center().y)
	Kit.icon_plate(c, pc, 104.0, "dark" if gold else "loot")
	_b_icon(c, "clock", Kit.plate_center(pc, 104.0), 64.0)
	var x := rect.position.x + 156.0
	Kit.text_outlined(c, Vector2(x, rect.position.y + 38.0), "ÜBERLEBT", UiStyle.T_LABEL, Color.WHITE if gold else UiStyle.BRAWL_TEXT_DIM, -1, -1, null, Kit.LEFT | Kit.MIDDLE)
	var shown := float(_res.seconds) * _count(0.9, 1.0)
	Kit.text_outlined(c, Vector2(x - 4.0, rect.position.y + 96.0), _clock_text(shown), 96, Color.WHITE, 18, 7, UiStyle.number_font(), Kit.LEFT | Kit.MIDDLE, rect.end.x - 24.0 - x)
	if gold:
		var pop := _ease_back(clampf((t - 2.0) / 0.25, 0.0, 1.0))
		if pop > 0.05:
			c.draw_set_transform(Vector2(rect.end.x - 92.0, rect.position.y - 2.0), -0.08, Vector2.ONE * pop)
			Kit.badge(c, Vector2.ZERO, "NEUER REKORD!", "danger", UiStyle.T_LABEL)
			c.draw_set_transform(Vector2.ZERO)


func _paint_r_stats(c: CanvasItem) -> void:
	if _res.is_empty():
		return
	var tiles := [
		["mawling_head_color", "PEAK", int(_res.peak), "ember", bool(_res.record_peak)],
		["jaws", "KILLS", int(_res.kills), "ember", false],
		["biomass", "BIOMASSE", int(_res.biomass), "loot", false],
		["bog_king", "BOSSE", int(_res.bosses), "danger", false],
	]
	var gap := UiStyle.SPACE_M
	var w := (780.0 - gap * 3.0) / 4.0
	var x0 := size.x * 0.5 - 390.0
	var y := _oy() + 418.0
	for i in tiles.size():
		var rect := Rect2(x0 + i * (w + gap), y, w, 140.0)
		Kit.panel(c, rect, "dark", UiStyle.R_L)
		var cx := rect.get_center().x
		var pc := Vector2(cx, rect.position.y + 40.0)
		Kit.icon_plate(c, pc, 60.0, tiles[i][3])
		_b_icon(c, tiles[i][0], Kit.plate_center(pc, 60.0), 46.0)
		var value := int(roundf(float(tiles[i][2]) * _count(1.2 + i * 0.1, R_COUNT)))
		Kit.number(c, Vector2(cx, rect.position.y + 92.0), value, UiStyle.T_TITLE, Color.WHITE, Kit.CENTER | Kit.MIDDLE, w - 24.0)
		Kit.text_outlined(c, Vector2(cx, rect.end.y - 18.0), tiles[i][1], UiStyle.T_LABEL, UiStyle.BRAWL_TEXT_DIM, -1, -1, null, Kit.CENTER | Kit.MIDDLE, w - 16.0)
		if tiles[i][4] and _result_time > 1.2 + R_COUNT:
			Kit.badge(c, Vector2(rect.end.x - 18.0, rect.position.y + 4.0), "REKORD", "danger", UiStyle.T_LABEL)


func _paint_r_build(c: CanvasItem) -> void:
	if _res.is_empty():
		return
	var cx := size.x * 0.5
	var rect := Rect2(cx - 390.0, _oy() + 578.0, 780.0, 140.0)
	Kit.panel(c, rect, "dark", UiStyle.R_L)
	Kit.text_outlined(c, Vector2(rect.position.x + 24.0, rect.position.y + 30.0), "BUILD", UiStyle.T_LABEL, UiStyle.BRAWL_TEXT_DIM, -1, -1, null, Kit.LEFT | Kit.MIDDLE)
	_paint_build(c, Rect2(rect.position.x + 20.0, rect.position.y + 40.0, rect.size.x - 40.0, 94.0), _res.build, 76.0, (_result_time - 1.55) / 0.6)
	# Essence (and crowns) this run earns, as reward pills under the build.
	var crowns := int(_res.crowns)
	var pills: Array = [["essence", "+%s ESSENZ" % Kit.format_int(int(_res.essence)), "special"]]
	if crowns > 0:
		pills.append(["crown_tooth", ("+%d KÖNIGSZAHN" % crowns) if crowns == 1 else ("+%d KÖNIGSZÄHNE" % crowns), "loot"])
	var font := UiStyle.display_font()
	var widths: Array = []
	var total := 0.0
	for p in pills:
		var w := 66.0 + font.get_string_size(p[1], HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.T_HEAD).x + 26.0
		widths.append(w)
		total += w
	total += UiStyle.SPACE_L * (pills.size() - 1)
	var x := cx - total * 0.5
	var y := _oy() + 740.0
	for i in pills.size():
		var r := Rect2(x, y, widths[i], 58.0)
		Kit.pill(c, r, "dark", UiStyle.STROKE_M)
		var pc := Vector2(r.position.x + 30.0, r.get_center().y)
		Kit.icon_plate(c, pc, 54.0, pills[i][2])
		_b_icon(c, pills[i][0], Kit.plate_center(pc, 54.0), 40.0)
		Kit.text_outlined(c, Vector2(r.position.x + 66.0, r.get_center().y), pills[i][1], UiStyle.T_HEAD, Color.WHITE, -1, -1, null, Kit.LEFT | Kit.MIDDLE)
		x += widths[i] + UiStyle.SPACE_L


func _paint_r_tasks(c: CanvasItem) -> void:
	if _res.is_empty():
		return
	var cx := size.x * 0.5
	var rect := Rect2(cx - 390.0, _oy() + 816.0, 780.0, 412.0)
	Kit.panel(c, rect, "dark", UiStyle.R_L)
	var hx := rect.position.x + 24.0
	_b_icon(c, "trophy", Vector2(hx + 20.0, rect.position.y + 40.0), 44.0)
	Kit.text_outlined(c, Vector2(hx + 52.0, rect.position.y + 40.0), "AUFGABEN", UiStyle.T_HEAD, Color.WHITE, -1, -1, null, Kit.LEFT | Kit.MIDDLE)
	var tasks: Array = _res.tasks
	if tasks.is_empty():
		Kit.paragraph(c, Vector2(rect.position.x + 24.0, rect.position.y + 200.0), "Alle Trophäen erreicht. Die Horde ist vollkommen.", rect.size.x - 48.0, UiStyle.T_BODY, UiStyle.BRAWL_TEXT_DIM, true, Kit.CENTER, 2)
		return
	var fill := _count(float(R_SECTIONS.r_tasks) + R_BARS, 0.8)
	for i in tasks.size():
		var row := Rect2(rect.position.x + 20.0, rect.position.y + 74.0 + i * 108.0, rect.size.x - 40.0, 96.0)
		_paint_task(c, row, tasks[i], fill)


func _paint_task(c: CanvasItem, row: Rect2, task: Dictionary, fill: float) -> void:
	var q: Dictionary = task.q
	var shown: float = lerpf(float(task.from), float(task.to), fill)
	var done: bool = bool(task.done) and fill >= 0.999
	Kit.well(c, row, UiStyle.R_M)
	var pc := Vector2(row.position.x + 50.0, row.get_center().y)
	Kit.icon_plate(c, pc, 72.0, "action" if done else "loot")
	_b_icon(c, "trophy", Kit.plate_center(pc, 72.0), 50.0)
	# Reward chip on the right.
	var reward := _task_reward(q)
	var chip := Rect2(row.end.x - 146.0, row.position.y + 14.0, 132.0, 68.0)
	Kit.chip(c, chip, "action" if done else "dark")
	_b_icon(c, reward[0], Vector2(chip.position.x + 34.0, chip.get_center().y), 46.0)
	var reward_text: String = reward[1]
	Kit.text_outlined(c, Vector2(chip.position.x + 62.0, chip.get_center().y), reward_text, UiStyle.T_HEAD, Color.WHITE, -1, -1, UiStyle.number_font() if reward_text.begins_with("+") else null, Kit.LEFT | Kit.MIDDLE, chip.end.x - 10.0 - (chip.position.x + 62.0))
	# Name, progress text and bar.
	var x := row.position.x + 100.0
	var right := chip.position.x - UiStyle.SPACE_L
	var progress := "GESCHAFFT!" if done else _task_progress_text(q, float(task.value) if fill >= 0.999 else shown * float(q.target))
	var pw := UiStyle.display_font().get_string_size(progress, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.T_LABEL).x
	Kit.text_outlined(c, Vector2(right, row.position.y + 28.0), progress, UiStyle.T_LABEL, UiStyle.brawl_tone("action")["light"] if done else UiStyle.BRAWL_TEXT_DIM, -1, -1, null, Kit.RIGHT | Kit.MIDDLE)
	Kit.text_outlined(c, Vector2(x, row.position.y + 28.0), String(q.name), UiStyle.T_BODY, Color.WHITE, 7, 3, UiStyle.body_bold_font(), Kit.LEFT | Kit.MIDDLE, right - pw - UiStyle.SPACE_M - x)
	Kit.bar(c, Rect2(x, row.position.y + 50.0, right - x, 32.0), shown, "action" if done else "loot")


func _task_reward(q: Dictionary) -> Array:
	var reward: Dictionary = q.get("reward", {})
	if int(reward.get("crowns", 0)) > 0:
		return ["crown_tooth", "+%d" % int(reward.crowns)]
	if int(reward.get("essence", 0)) > 0:
		return ["essence", "+%d" % int(reward.essence)]
	return ["lock", "NEU"]


func _task_progress_text(q: Dictionary, value: float) -> String:
	var stat := String(q.stat)
	var target := float(q.target)
	value = clampf(value, 0.0, target)
	if stat.contains("seconds") or stat.contains("time"):
		return "%s / %s" % [_short_time(value), _short_time(target)]
	return "%s / %s" % [Kit.format_int(int(value)), Kit.format_int(int(target))]


func _short_time(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]


func _paint_r_buttons(c: CanvasItem) -> void:
	var hud := get_parent()
	if hud == null or _res.is_empty():
		return
	var action: Rect2 = hud._action_rect()
	Kit.button(c, action, "action", false, UiStyle.R_XL)
	_button_label(c, action, false, "restart", "NOCHMAL", UiStyle.T_TITLE, 64.0)
	var hub: Rect2 = hud._hub_rect()
	Kit.button(c, hub, "neutral", false, UiStyle.R_L)
	_button_label(c, hub, false, "hub", "BRUTSTÄTTE", UiStyle.T_HEAD, 52.0)
	if hud.has_method("_share_rect"):
		var share: Rect2 = hud._share_rect()
		if share.size.x > 0.0:
			var busy := _share_state == "busy"
			Kit.button(c, share, "info", busy, UiStyle.R_L)
			var label: String = {"busy": "…", "saved": "GESPEICHERT", "failed": "FEHLER"}.get(_share_state, "TEILEN")
			Kit.text_outlined(c, Kit.button_label_center(share, busy), label, UiStyle.T_HEAD, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE, share.size.x - 28.0)


# Icon + label centred on a button face.
func _button_label(c: CanvasItem, rect: Rect2, pressed: bool, icon: String, label: String, font_size: int, icon_size: float) -> void:
	var lc := Kit.button_label_center(rect, pressed)
	var has_icon := _icons != null and bool(_icons.call("has", icon))
	var extra := icon_size + 12.0 if has_icon else 0.0
	var room := rect.size.x - 40.0 - extra
	var tw := minf(UiStyle.display_font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, room)
	var x := lc.x - (tw + extra) * 0.5
	if has_icon:
		_b_icon(c, icon, Vector2(x + icon_size * 0.5, lc.y), icon_size)
		x += extra
	Kit.text_outlined(c, Vector2(x, lc.y), label, font_size, Color.WHITE, -1, -1, null, Kit.LEFT | Kit.MIDDLE, room)


# Build as icon plates with rank badges (roman numerals; EVO for evolutions).
func _paint_build(c: CanvasItem, area: Rect2, build: Array, plate: float, reveal: float) -> void:
	if build.is_empty():
		Kit.text_outlined(c, area.get_center(), "Keine Mutationen gewählt", UiStyle.T_BODY, UiStyle.BRAWL_TEXT_DIM, 7, 3, UiStyle.body_bold_font(), Kit.CENTER | Kit.MIDDLE, area.size.x)
		return
	var n := build.size()
	var step := minf(plate + 22.0, area.size.x / n)
	var p := minf(plate, step - 12.0)
	var x0 := area.get_center().x - (n - 1) * step * 0.5
	var hud := get_parent()
	var evo: Variant = hud.evolution if hud != null else null
	for i in n:
		if reveal * n < i * 0.6:
			break
		var id: String = build[i][0]
		var evolved: bool = build[i][2]
		var center := Vector2(x0 + i * step, area.get_center().y + 4.0)
		Kit.icon_plate(c, center, p, _build_tone(evo, id, evolved))
		_b_icon(c, id, Kit.plate_center(center, p), p * 0.76)
		var rank := int(build[i][1])
		var tag: String = "EVO" if evolved else ROMAN[clampi(rank, 1, ROMAN.size()) - 1]
		Kit.badge(c, center + Vector2(p * 0.38, -p * 0.36), tag, "loot" if evolved else "neutral", UiStyle.T_LABEL)


func _build_tone(evo: Variant, id: String, evolved: bool) -> String:
	if evolved:
		return "special"
	var kind: String = evo.kind_of(id) if evo != null else ""
	if kind == "evolved":
		return "special"
	if kind == "attack":
		return "ember"
	return BRANCH_TONE[BRANCH_OF.get(id, "special")]


func _b_icon(c: CanvasItem, id: String, center: Vector2, side: float, tint: Color = Color.WHITE) -> bool:
	if _icons == null or not bool(_icons.call("has", id)):
		return false
	_icons.call("draw", c, id, Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side)), tint)
	return true


# ---------------------------------------------------------------- pause

func _paint_pause(c: CanvasItem) -> void:
	var hud := get_parent()
	if hud == null:
		return
	var cx := size.x * 0.5
	var oy := _oy()
	var panel := Rect2(cx - 390.0, oy + 300.0, 780.0, 900.0)
	Kit.panel(c, panel, "dark", UiStyle.R_XL, UiStyle.STROKE_L)
	var ribbon := Rect2(cx - 190.0, panel.position.y - 50.0, 380.0, 100.0)
	Kit.ribbon(c, ribbon, "info")
	Kit.text_outlined(c, Vector2(cx, ribbon.get_center().y - 2.0), "PAUSE", UiStyle.T_HERO, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE, ribbon.size.x - 40.0)
	# Run so far: time, swarm, level.
	var level: int = 0 if hud.evolution == null else int(hud.evolution.level)
	var tiles := [
		["clock", "ZEIT", _clock_text(hud.elapsed), "loot"],
		["mawling_head_color", "SCHWARM", Kit.format_int(int(hud.population)), "ember"],
		["dna", "STUFE", str(level), "info"],
	]
	var gap := UiStyle.SPACE_M
	var w := (700.0 - gap * 2.0) / 3.0
	for i in tiles.size():
		var rect := Rect2(cx - 350.0 + i * (w + gap), oy + 400.0, w, 124.0)
		Kit.well(c, rect, UiStyle.R_M)
		var pc := Vector2(rect.position.x + 44.0, rect.position.y + 50.0)
		Kit.icon_plate(c, pc, 60.0, tiles[i][3])
		_b_icon(c, tiles[i][0], Kit.plate_center(pc, 60.0), 44.0)
		Kit.number(c, Vector2(rect.position.x + 86.0, rect.position.y + 52.0), tiles[i][2], UiStyle.T_HEAD, Color.WHITE, Kit.LEFT | Kit.MIDDLE, rect.end.x - 12.0 - (rect.position.x + 86.0))
		Kit.text_outlined(c, Vector2(rect.get_center().x, rect.end.y - 22.0), tiles[i][1], UiStyle.T_LABEL, UiStyle.BRAWL_TEXT_DIM, -1, -1, null, Kit.CENTER | Kit.MIDDLE, w - 16.0)
	Kit.text_outlined(c, Vector2(cx, oy + 572.0), "AKTUELLER BUILD", UiStyle.T_LABEL, UiStyle.BRAWL_TEXT_DIM, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
	var build_well := Rect2(cx - 350.0, oy + 600.0, 700.0, 130.0)
	Kit.well(c, build_well, UiStyle.R_M)
	_paint_build(c, build_well.grow(-8.0), _build(hud, {}), 80.0, 9.0)
	var action: Rect2 = hud._action_rect()
	Kit.button(c, action, "action", false, UiStyle.R_XL)
	_button_label(c, action, false, "play", "WEITER", UiStyle.T_TITLE, 60.0)
	if hud.has_method("_restart_rect"):
		var restart: Rect2 = hud._restart_rect()
		if restart.size.x > 0.0:
			Kit.button(c, restart, "neutral", false, UiStyle.R_L)
			_button_label(c, restart, false, "restart", "NEUSTART", UiStyle.T_HEAD, 48.0)
	var hub: Rect2 = hud._hub_rect()
	Kit.button(c, hub, "neutral", false, UiStyle.R_L)
	_button_label(c, hub, false, "hub", "BRUTSTÄTTE", UiStyle.T_HEAD, 48.0)


# ---------------------------------------------------------------- banners

## Queues a ribbon banner. tone: kit tone name; icon: ui_icons id or "".
## kind decides the hand-over rule (HANDOVER); captures call this directly.
func push_banner(kind: String, title: String, tone: String, icon: String = "", kicker: String = "", sub: String = "", duration: float = BANNER_TIME, flash: bool = false) -> void:
	if not UiStyle.is_brawl():
		return
	if HANDOVER.has(kind) and not force_banners and not _handed_over(kind):
		return
	_queue.append({"kind": kind, "title": title, "tone": tone, "icon": icon, "kicker": kicker, "sub": sub, "dur": duration, "flash": flash})


func _handed_over(kind: String) -> bool:
	var hud := get_parent()
	if hud == null:
		return true
	var owner_node := hud.get_node_or_null(String(HANDOVER[kind]))
	return owner_node == null or owner_node.get("banners_in_overlays") == true


func _push_milestone(mark: int) -> void:
	if mark <= 0:
		return
	push_banner("milestone", _milestone_text(mark), "loot", "mawling_head_color", "HORDE!" if mark >= 100 else "MEILENSTEIN", "", 1.7)


func _push_king() -> void:
	push_banner("king", "KÖNIG VERSCHLUNGEN", "loot", "bog_king", "SIEG!", "Der Bog King ist Beute", 2.4, true)


func _world() -> Node:
	if _world_node != null and is_instance_valid(_world_node):
		return _world_node
	var node: Node = get_parent()
	while node != null:
		var found := node.get_node_or_null("HuntWorld")
		if found != null:
			_world_node = found
			return found
		node = node.get_parent()
	return null


func _hud_value(hud: Control, key: String, fallback: Variant) -> Variant:
	var value: Variant = hud.get(key)
	if value == null and hud.has_meta(key):
		value = hud.get_meta(key)
	return fallback if value == null else value


# Watches HUD values for the moments that get a banner. The first frame only
# remembers the values (no banner for a state the run starts in).
func _detect_banners(hud: Control) -> void:
	if hud.extinct:
		_queue.clear()
		_banner = {}
		return
	var fresh := _seen.is_empty()
	# Evolution: evolve_flash jumps up to EVOLVE_TIME.
	var flash := float(hud.evolve_flash)
	if not fresh and flash > float(_seen.get("evolve", 0.0)) + 0.5:
		var evo: Variant = hud.evolution
		var id := "alpha_core"
		if evo != null and not evo.evolutions.is_empty():
			id = String(evo.evolutions.back())
		var name_text := String(hud.evolve_name).to_upper()
		push_banner("evolution", name_text if name_text != "" else "EVOLUTION", "special", id, "EVOLUTION!", "", 2.2)
	_seen["evolve"] = flash
	# Bog King appears.
	var boss_on := float(hud.boss_max_health) > 0.0
	if not fresh and boss_on and not bool(_seen.get("boss", false)):
		push_banner("boss", "BOG KING NAHT", "danger", "bog_king", "BOSS", "Weich dem Stampfer aus, dann zubeißen")
	_seen["boss"] = boss_on
	# Leader swap (RunModel.leader_swaps; the HUD has no counter of its own).
	var world := _world()
	var model: Variant = world.get("model") if world != null else null
	if model != null:
		var swaps := int(model.leader_swaps)
		if not fresh and _seen.has("swaps") and swaps > int(_seen.swaps):
			var lp := int(_hud_value(hud, "leader_max_hp", 1))
			push_banner("leader", "NEUER ANFÜHRER", "ember", "mawling_head_color", "ANFÜHRER GEFALLEN", "Er führt mit %d LP" % lp)
		_seen["swaps"] = swaps
	# Flood start.
	var flood: Variant = hud.get_meta("flood", {})
	var flood_state := int(flood.get("state", 0)) if flood is Dictionary else 0
	if not fresh and flood_state == 2 and int(_seen.get("flood", 0)) != 2:
		push_banner("flood", "DIE FLUT BRICHT LOS", "danger", "skull", "GEFAHR", "In Bewegung bleiben, Brut zerbeißen")
	_seen["flood"] = flood_state
	# Apex: appears, is beaten, the swarm arrives in a new biome.
	var obj: Variant = hud.get_meta("objectives", {})
	if obj is Dictionary:
		var apex_state := int(obj.get("apex_state", 0))
		var apex_name := String(obj.get("apex_name", "APEX"))
		if not fresh and apex_state == 2 and int(_seen.get("apex", 0)) != 2:
			push_banner("apex", "%s ERSCHEINT" % apex_name, "danger", "skull", "APEX", "")
		_seen["apex"] = apex_state
		var wins := int(obj.get("apex_victories", 0))
		if not fresh and _seen.has("wins") and wins > int(_seen.wins):
			push_banner("victory", "%s BEZWUNGEN" % apex_name, "loot", "crown", "SIEG!", "Der Migrationsschlund öffnet sich", 2.6, true)
		_seen["wins"] = wins
		var arrivals := int(obj.get("arrivals", 0))
		if not fresh and _seen.has("arrivals") and arrivals > int(_seen.arrivals):
			var biome := String(obj.get("biome_id", ""))
			var title := String(obj.get("biome_title", "")).to_upper()
			push_banner("arrival", title if title != "" else "NEUES BIOM", "info", "biome_glutsumpf" if biome == "glutsumpf" else "biome_verdant", "MIGRATION", "", 2.2)
		_seen["arrivals"] = arrivals


func _step_banner(hud: Control, real_delta: float) -> void:
	var layer: Control = _b.banner
	var hold: bool = hud.paused or hud.extinct or _choosing(hud)
	var obj: Variant = hud.get_meta("objectives", {})
	var swirl: bool = obj is Dictionary and float(obj.get("migration", -1.0)) >= 0.0
	if _banner.is_empty() and not _queue.is_empty() and not hold:
		# An arrival waits until the migration swirl has opened again.
		if not (String(_queue[0].kind) == "arrival" and swirl):
			_banner = _queue.pop_front()
			_banner_t = 0.0
			if _banner.flash:
				_flash = {"t": 0.0, "tone": _banner.tone}
	if not _flash.is_empty():
		_flash.t = float(_flash.t) + real_delta
		if _flash.t > 0.4:
			_flash = {}
	if _banner.is_empty() or hold:
		layer.visible = false
		return
	_banner_t += real_delta
	# Queued banners shorten the current one so nothing piles up.
	var dur: float = float(_banner.dur) if _queue.is_empty() else minf(float(_banner.dur), 1.2)
	if _banner_t >= dur:
		_banner = {}
		layer.visible = false
		return
	var t := _banner_t
	var pop := _ease_back(clampf(t / 0.24, 0.0, 1.0))
	var out := clampf((t - (dur - 0.32)) / 0.32, 0.0, 1.0)
	layer.visible = true
	layer.modulate.a = clampf(t / 0.1, 0.0, 1.0) * (1.0 - out)
	layer.pivot_offset = Vector2(size.x * 0.5, _oy() + BANNER_Y)
	layer.scale = Vector2.ONE * lerpf(1.4, 1.0, pop)
	layer.position = Vector2(0.0, -46.0 * _ease_out(out))
	layer.refresh([size, _banner.title, _banner.kind, _banner.sub])


func _paint_banner(c: CanvasItem) -> void:
	if _banner.is_empty():
		return
	var b := _banner
	var cx := size.x * 0.5
	var cy := _oy() + BANNER_Y
	var title := String(b.title)
	var font := UiStyle.display_font()
	var tw := minf(font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.T_TITLE).x, BANNER_TITLE_W)
	var icon := String(b.icon)
	var has_icon := icon != "" and _icons != null and bool(_icons.call("has", icon))
	var plate := 76.0
	var w := tw + 64.0 + (plate + 8.0 if has_icon else 0.0)
	var rect := Rect2(cx - w * 0.5, cy - 46.0, w, 92.0)
	Kit.ribbon(c, rect, b.tone)
	var x := rect.position.x + 32.0
	if has_icon:
		var pc := Vector2(x + plate * 0.5 - 8.0, cy)
		Kit.icon_plate(c, pc, plate, "dark")
		_b_icon(c, icon, Kit.plate_center(pc, plate), plate * 0.8)
		x += plate + 8.0
	Kit.text_outlined(c, Vector2(x, cy - 2.0), title, UiStyle.T_TITLE, Color.WHITE, -1, -1, null, Kit.LEFT | Kit.MIDDLE, BANNER_TITLE_W)
	var kicker := String(b.kicker)
	if kicker != "":
		var kw := font.get_string_size(kicker, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.T_LABEL).x + 36.0
		var chip := Rect2(cx - kw * 0.5, rect.position.y - 36.0, kw, 42.0)
		Kit.chip(c, chip, "dark")
		Kit.text_outlined(c, chip.get_center(), kicker, UiStyle.T_LABEL, UiStyle.brawl_tone(b.tone)["light"], -1, -1, null, Kit.CENTER | Kit.MIDDLE)
	var sub := String(b.sub)
	if sub != "":
		Kit.text_outlined(c, Vector2(cx, rect.end.y + 48.0), sub, UiStyle.T_BODY, Color.WHITE, 7, 3, UiStyle.body_bold_font(), Kit.CENTER | Kit.MIDDLE, 760.0)


# Full-screen flash of victory moments (king, apex): short, under the ribbon.
func _draw_banner_flash() -> void:
	if _flash.is_empty():
		return
	var k := 1.0 - clampf(float(_flash.t) / 0.4, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(UiStyle.brawl_tone(_flash.tone)["light"], 0.32 * k))


# ---------------------------------------------------------------- share

## Renders the share card of the finished run (share_card.gd) into
## user://shares/. The result button shows "…" while it draws, then
## "GESPEICHERT". Real system sharing comes with the Android share plugin.
func share_result() -> String:
	if _share_state == "busy" or _res.is_empty() or not ResourceLoader.exists(SHARE_PATH):
		return ""
	_share_state = "busy"
	_share_t = 0.0
	var card: Node = load(SHARE_PATH).new()
	card.name = "ShareCard"
	add_child(card)
	var path: String = await card.render(_res.stats)
	card.queue_free()
	_share_state = "saved" if path != "" else "failed"
	_share_t = 0.0
	return path


func _ease_back(x: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)
