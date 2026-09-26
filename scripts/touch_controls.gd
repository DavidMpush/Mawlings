extends Control

signal restart_requested
signal pause_requested
signal mutation_chosen(slot: int)
signal hub_requested
signal reroll_requested
signal skip_requested
signal banish_requested(slot: int)

var evolution: RefCounted

var movement_vector := Vector2.ZERO
var rally_pressed := false
var movement_pointer := -1
var rally_pointer := -1
var population := 25
var biomass_bank := 0.0
var corpse_count := 0
var kills := 0
var hunters := 0
var skitters := 0
var leapers := 0
var boss_health := 0.0
var boss_max_health := 0.0
var hint := ""
var elapsed := 0.0
var pressure := 1.0
var extinct := false
var paused := false
var peak_population := 25
var consumed_biomass := 0.0
var nearest_corpse := ""
var hit_feedback := 0.0
var boss_pointer := Vector2.INF
var boss_vulnerable := false
var last_loss := 0
var alpha_cores := 0
var evolve_flash := 0.0
var evolve_name := ""
var run_stats: Dictionary = {}

# Palette shared by all HUD parts.
const INK := Color("0a1a17")
const PANEL := Color("0f231ee6")
const BONE := Color("f5e4b7")
const CLAW := Color("d9c79a")
const WARM := Color("ff8a3d")
const CYAN := Color("6ee4d4")
const DANGER := Color("ff5a44")
const ALPHA_AMBER := Color("ffb347")
const ALPHA_VIOLET := Color("a86bff")
const FORMS_PATH := "res://scripts/attack_forms.gd"

var _forms: Dictionary = {}
var _forms_loaded := false

var _bold: FontVariation


# Stage 04 components; order matters: overlays and the mutation dimmer sit on top.
const COMPONENTS := [
	["res://scripts/ui/hud_top.gd", ["top", "badges"]],
	["res://scripts/ui/hud_controls.gd", ["controls"]],
	["res://scripts/ui/mutation_screen.gd", ["mutations"]],
	["res://scripts/ui/hud_overlays.gd", ["result", "banner", "feedback", "pointer"]],
]


func _ready() -> void:
	set_process_input(true)
	_ensure_font()
	for entry in COMPONENTS:
		if not ResourceLoader.exists(entry[0]):
			continue
		var component: Control = load(entry[0]).new()
		component.name = String(entry[0]).get_file().get_basename()
		add_child(component)
		for key in entry[1]:
			legacy[key] = false
	queue_redraw()


func _ensure_font() -> void:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = ThemeDB.fallback_font
		_bold.variation_embolden = 0.85


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		clear_pointers()
		if not paused and not extinct and is_inside_tree():
			pause_requested.emit()


func clear_pointers() -> void:
	movement_vector = Vector2.ZERO
	rally_pressed = false
	movement_pointer = -1
	rally_pointer = -1
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ESCAPE, KEY_P]:
			pause_requested.emit()
		elif not extinct and not paused and event.keycode in [KEY_1, KEY_2, KEY_3]:
			mutation_chosen.emit(event.keycode - KEY_1)
		elif not extinct and not paused and _choosing() and event.keycode == KEY_R:
			reroll_requested.emit()
		elif not extinct and not paused and _choosing() and event.keycode == KEY_X:
			skip_requested.emit()
		elif extinct and event.keycode in [KEY_R, KEY_ENTER]:
			restart_requested.emit()
		elif extinct and event.keycode in [KEY_H, KEY_M]:
			hub_requested.emit()
	if event is InputEventScreenTouch:
		if event.pressed:
			_press(event.index, event.position)
		else:
			_release(event.index)
	elif event is InputEventScreenDrag and event.index == movement_pointer:
		_update_movement(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press(-2, event.position)
		else:
			_release(-2)
	elif event is InputEventMouseMotion and movement_pointer == -2:
		_update_movement(event.position)


func _press(pointer: int, location: Vector2) -> void:
	if extinct or paused:
		if _action_rect().has_point(location):
			if extinct:
				restart_requested.emit()
			else:
				pause_requested.emit()
		elif (extinct or paused) and _hub_rect().has_point(location):
			hub_requested.emit()
		return
	if _pause_rect().has_point(location):
		pause_requested.emit()
		return
	if _choosing():
		for slot in evolution.offers.size():
			if _count("banishes") > 0 and _banish_rect(slot).has_point(location):
				banish_requested.emit(slot)
				return
			if _mutation_rect(slot).has_point(location):
				mutation_chosen.emit(slot)
				return
		if _count("rerolls") > 0 and _reroll_rect().has_point(location):
			reroll_requested.emit()
		elif _count("skips") > 0 and _skip_rect().has_point(location):
			skip_requested.emit()
		return
	if movement_pointer == -1 and location.distance_to(_movement_center()) < 125.0:
		movement_pointer = pointer
		_update_movement(location)
	elif rally_pointer == -1 and location.distance_to(_rally_center()) < 125.0:
		rally_pointer = pointer
		rally_pressed = true
		queue_redraw()


func _release(pointer: int) -> void:
	if pointer == movement_pointer:
		movement_pointer = -1
		movement_vector = Vector2.ZERO
	if pointer == rally_pointer:
		rally_pointer = -1
		rally_pressed = false
	queue_redraw()


func _update_movement(location: Vector2) -> void:
	movement_vector = ((location - _movement_center()) / 66.0).limit_length(1.0)
	queue_redraw()


func _movement_center() -> Vector2:
	return Vector2(size.x - 125.0, size.y - 145.0)


func _rally_center() -> Vector2:
	return Vector2(125.0, size.y - 145.0)


func _pause_rect() -> Rect2:
	return Rect2(Vector2(size.x - 98, 18), Vector2(82, 100))

func _action_rect() -> Rect2:
	if extinct or paused:
		return Rect2(Vector2(size.x * 0.5 - 340, size.y * 0.5 + 235), Vector2(330, 88))
	return Rect2(Vector2(size.x * 0.5 - 220, size.y * 0.5 + 235), Vector2(440, 88))

func _hub_rect() -> Rect2:
	return Rect2(Vector2(size.x * 0.5 + 10, size.y * 0.5 + 235), Vector2(330, 88))

func _banish_rect(slot: int) -> Rect2:
	var card := _mutation_rect(slot)
	return Rect2(Vector2(card.end.x - 190, card.position.y + 14), Vector2(172, 44))

# Reroll and skip share one row below the cards; a lone button is centred.
func _reroll_rect() -> Rect2:
	var both := _count("skips") > 0
	return Rect2(Vector2(size.x * 0.5 - (322 if both else 160), size.y * 0.5 + 440), Vector2(300 if both else 320, 72))

func _skip_rect() -> Rect2:
	var both := _count("rerolls") > 0
	return Rect2(Vector2(size.x * 0.5 + (22 if both else -160), size.y * 0.5 + 440), Vector2(300 if both else 320, 72))

func _choosing() -> bool:
	return evolution != null and not evolution.offers.is_empty()

# Reroll/banish/skip counters; 0 when the evolution has none.
func _count(counter: String) -> int:
	if evolution == null:
		return 0
	var value: Variant = evolution.get(counter)
	return int(value) if value != null else 0

func _mutation_rect(slot: int) -> Rect2:
	# One or two offers stay vertically centred instead of hanging at the top.
	var count := 3 if evolution == null or evolution.offers.is_empty() else mini(3, evolution.offers.size())
	var top := size.y * 0.5 - 322 + float(3 - count) * 123.0
	return Rect2(Vector2(36, top + slot * 246), Vector2(size.x - 72, 226))

func _pulse(speed: float = 3.0) -> float:
	return 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * speed)

# ---------------------------------------------------------------- drawing

# UI pass (stage 04): each legacy block can be switched off once a component
# under scripts/ui/ draws it instead. Input handling stays in this script.
var legacy := {"top": true, "badges": true, "pointer": true, "feedback": true, "result": true, "mutations": true, "controls": true, "banner": true}


func _draw() -> void:
	_ensure_font()
	if legacy.top:
		_draw_top()
	if legacy.pointer and boss_pointer.is_finite() and not extinct and not paused:
		_draw_boss_pointer()
	if legacy.feedback and hit_feedback > 0.0 and not extinct:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.95, 0.24, 0.12, minf(0.11, hit_feedback * 0.11)))
		_text("−%d MAWLINGS" % last_loss, Vector2(size.x * 0.5, size.y * 0.5 - 170), 30, Color("ffe2c5"), true, 8)
	if extinct or paused:
		if legacy.result:
			_draw_result()
	elif _choosing():
		if legacy.mutations:
			_draw_mutations()
	else:
		if legacy.controls:
			_draw_controls()
		if legacy.banner and evolve_flash > 0.0:
			_draw_evolve_banner()

func _draw_top() -> void:
	# Swarm: Mawling head silhouette plus the survival number.
	var swarm_rect := Rect2(16, 18, 282, 100)
	_frame(swarm_rect, PANEL, WARM, 1)
	_mawling_head(Vector2(70, 70), 36, WARM)
	_text("SCHWARM", Vector2(124, 54), 18, Color("e9c9a0"))
	_text("%d" % population, Vector2(122, 104), 50, Color.WHITE, false, 6)
	# Time with pressure bar and danger skull.
	var cx := size.x * 0.5
	var time_rect := Rect2(cx - 134, 18, 268, 100)
	var danger_fraction := clampf(log(maxf(1.0, pressure)) / log(256.0), 0.0, 1.0)
	var danger_color := Color("f2b24a").lerp(DANGER, danger_fraction)
	_frame(time_rect, PANEL, Color("b6c58e").lerp(DANGER, danger_fraction), 0)
	_text("%02d:%02d" % [int(elapsed) / 60, int(elapsed) % 60], Vector2(cx - 12, 68), 46, BONE, true, 6)
	_segment_bar(Rect2(cx - 112, 84, 186, 14), maxf(0.04, danger_fraction), danger_color, 8)
	_skull(Vector2(cx + 100, 90), 17, danger_color)
	# DNA: helix, level and progress.
	var dna_rect := Rect2(size.x - 294, 18, 186, 100)
	_frame(dna_rect, PANEL, CYAN, 0)
	var level: int = 0 if evolution == null else evolution.level
	var dna: int = 0 if evolution == null else evolution.dna
	var needed: int = 20 if evolution == null else evolution.threshold()
	var maxed: bool = evolution != null and evolution.complete()
	_helix(Vector2(dna_rect.position.x + 30, 68), 64, CYAN)
	_text("LV %d" % level, Vector2(dna_rect.position.x + 58, 60), 32, Color.WHITE, false, 5)
	var bar := Rect2(dna_rect.position.x + 58, 72, 110, 12)
	_bar(bar, 1.0 if maxed else clampf(float(dna) / float(needed), 0, 1), CYAN)
	_text("MAX" if maxed else "%d / %d DNA" % [dna, needed], Vector2(dna_rect.position.x + 58, 106), 18, Color("bfeee6"))
	# Pause button.
	var pause := _pause_rect()
	_frame(pause, PANEL, BONE, 4)
	var pc := pause.get_center()
	draw_rect(Rect2(pc + Vector2(-15, -18), Vector2(10, 36)), BONE)
	draw_rect(Rect2(pc + Vector2(5, -18), Vector2(10, 36)), BONE)
	# Context line below the top bar.
	var pressure_text := "DRUCK ×%.1f" % pressure
	var pressure_w := ThemeDB.fallback_font.get_string_size(pressure_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x
	draw_colored_polygon(_rounded_points(Rect2(cx - pressure_w * 0.5 - 16, 130, pressure_w + 32, 32), 16, 4), Color("0f231ecc"))
	_text(pressure_text, Vector2(cx, 153), 21, danger_color.lerp(Color.WHITE, 0.45), true)
	var chip_x := 16.0
	if hunters > 0:
		chip_x = _chip(chip_x, "JÄGER %d" % hunters, Color("b07ae8"), Color("e6d6fa")) + 8
	if skitters > 0:
		chip_x = _chip(chip_x, "SKITTER %d" % skitters, Color("e46ad0"), Color("fad6f2")) + 8
	if leapers > 0:
		_chip(chip_x, "LEAPER %d" % leapers, Color("5fc9c0"), Color("d2f4ef"))
	if alpha_cores > 0:
		_alpha_chip()
	if legacy.badges:
		_draw_form_badges()
	var y := 176.0
	if boss_health > 0.0:
		var boss_rect := Rect2(cx - 300, y, 600, 72)
		var accent := Color("ffe07a") if boss_vulnerable else Color("e98e56")
		_frame(boss_rect, Color("1a1d18ee"), accent, 2 | 1)
		_crown(Vector2(boss_rect.position.x + 42, y + 38), 20, accent)
		_text("BOG KING" + ("  ·  VERWUNDBAR" if boss_vulnerable else ""), Vector2(boss_rect.position.x + 80, y + 30), 21, Color("ffe3ba"))
		_segment_bar(Rect2(boss_rect.position.x + 80, y + 42, 490, 14), clampf(boss_health / maxf(1.0, boss_max_health), 0.0, 1.0), Color("f09b63") if not boss_vulnerable else Color("ffe07a"), 12)
		y += 86
	if nearest_corpse != "":
		var corpse_rect := Rect2(24, y, minf(470, size.x - 48), 48)
		_frame(corpse_rect, Color("12201bd8"), Color("d9ad56"), 0)
		_biomass_drop(Vector2(50, y + 24), 13, Color("f6cc70"))
		_text(nearest_corpse, Vector2(72, y + 32), 21, BONE)
		y += 58
	if biomass_bank > 0.01:
		var text := "BIOMASSE %.1f / 2" % biomass_bank
		var w := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x
		draw_colored_polygon(_rounded_points(Rect2(24, y, w + 60, 36), 18, 4), Color("0f231ed8"))
		_biomass_drop(Vector2(44, y + 19), 10, Color("f6cc70"))
		_text(text, Vector2(62, y + 26), 21, Color("f6cc70"))

func _draw_boss_pointer() -> void:
	var direction := (boss_pointer - size * 0.5).normalized()
	var side := Vector2(-direction.y, direction.x)
	var tip := boss_pointer + direction * 34.0
	var accent := Color("ffe07a") if boss_vulnerable else Color("ff8a5c")
	draw_circle(boss_pointer, 48, Color(accent, 0.14 + 0.1 * _pulse(5.0)))
	draw_circle(boss_pointer, 40, Color("172921e6"))
	draw_arc(boss_pointer, 40, 0, TAU, 40, accent, 4.0, true)
	draw_colored_polygon(PackedVector2Array([tip + direction * 16.0, tip + side * 17.0, tip - side * 17.0]), accent)
	# Crown: the boss marker must not reuse the player's Mawling head.
	_crown(boss_pointer, 21, accent)
	var label := boss_pointer - direction * 66.0
	draw_colored_polygon(_rounded_points(Rect2(label - Vector2(58, 16), Vector2(116, 32)), 16, 4), Color("172921e0"))
	_text("BOG KING", label + Vector2(0, 7), 20, Color("ffe3ba"), true)


func _draw_controls() -> void:
	if hint != "":
		var hint_rect := Rect2(40, size.y - 348, size.x - 80, 60)
		_frame(hint_rect, Color("0f231ed0"), Color("8cae81"), 0)
		_text(hint, Vector2(size.x * 0.5, size.y - 309), 23, Color("f4e9cf"), true)
	_draw_rally(_rally_center())
	_draw_joystick(_movement_center())

func _draw_rally(c: Vector2) -> void:
	var glow := 0.55 + 0.45 * _pulse(2.4)
	if rally_pressed:
		glow = 1.3
	for i in 4:
		draw_circle(c, 110 + i * 7, Color(1.0, 0.45, 0.12, 0.07 * glow * (1.0 - i * 0.22)))
	for angle in [-2.45, -1.75, -1.05, -0.35]:
		var dir := Vector2(cos(angle), sin(angle))
		_claw(c + dir * 102, dir, 30, 9, CLAW, 0.35)
	draw_circle(c, 108, Color("1b120ce8"))
	draw_arc(c, 103, 0, TAU, 64, WARM.lightened(0.25 if rally_pressed else 0.0), 7, true)
	draw_arc(c, 94, 0, TAU, 64, Color("3a1a0e"), 3, true)
	var core := Color("c2521f") if rally_pressed else Color("6e2a14")
	draw_circle(c, 92, core)
	draw_circle(c + Vector2(0, -10), 70, core.lightened(0.08))
	draw_circle(c + Vector2(0, -20), 44, core.lightened(0.14))
	var head := Color("4a1a0c") if rally_pressed else Color("ff9a4a")
	_mawling_head(c + Vector2(-30, -34), 23, head.darkened(0.25))
	_mawling_head(c + Vector2(26, -38), 22, head.darkened(0.15))
	_mawling_head(c + Vector2(-2, -10), 31, head)
	_text("RALLY", c + Vector2(0, 52), 29, Color.WHITE, true, 6)
	_text("AKTIV" if rally_pressed else "HALTEN", c + Vector2(0, 76), 17, Color.WHITE if rally_pressed else Color("ffd6b0"), true, 4)

func _draw_joystick(c: Vector2) -> void:
	for angle in [-0.35, -1.05, -1.75, -2.45]:
		var dir := Vector2(-cos(angle), sin(angle))
		_claw(c + dir * 96, dir, 26, 8, Color(CLAW, 0.8), -0.35)
	draw_circle(c, 102, Color("0c1d1a88"))
	draw_arc(c, 99, 0, TAU, 64, Color(1, 1, 1, 0.42), 3, true)
	draw_arc(c, 70, 0, TAU, 48, Color(1, 1, 1, 0.12), 2, true)
	for i in 4:
		var dir := Vector2.RIGHT.rotated(i * PI * 0.5)
		var side := Vector2(-dir.y, dir.x)
		var alpha := 0.35 + 0.5 * clampf(movement_vector.dot(dir), 0.0, 1.0)
		var tip := c + dir * 90
		draw_colored_polygon(PackedVector2Array([tip, tip - dir * 14 + side * 12, tip - dir * 14 - side * 12]), Color(1, 1, 1, alpha))
	var knob := c + movement_vector * 52
	draw_circle(knob + Vector2(0, 5), 38, Color(0, 0, 0, 0.3))
	draw_circle(knob, 38, Color("9fb0aaee"))
	draw_circle(knob + Vector2(0, -3), 32, Color("d8e6e0f0"))
	draw_circle(knob + Vector2(-10, -13), 10, Color(1, 1, 1, 0.55))
	draw_arc(knob, 38, 0, TAU, 40, Color("22403a"), 2, true)

# ---------------------------------------------------------------- mutations

func _draw_mutations() -> void:
	draw_rect(Rect2(Vector2(0, 132), Vector2(size.x, size.y - 132)), Color("06120de0"))
	draw_rect(Rect2(Vector2(0, 124), Vector2(size.x, 8)), Color("06120d80"))
	var cy := size.y * 0.5
	var title := "MUTATION WÄHLEN"
	var title_y := cy - 388
	_text(title, Vector2(size.x * 0.5, title_y), 52, Color("f5e6ba"), true, 8)
	var half := _bold.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 52).x * 0.5
	for s in [-1.0, 1.0]:
		var inner := Vector2(size.x * 0.5 + s * (half + 18), title_y - 16)
		var outer := Vector2(size.x * 0.5 + s * (half + 70), title_y - 44)
		draw_line(inner, outer, Color("7fa86a"), 4, true)
		_claw(outer, Vector2(s * 0.3, -1), 22, 6, Color("9fc47f"), s * 0.4)
		_claw(inner + (outer - inner) * 0.5, Vector2(s * 0.6, 1), 14, 4, Color("7fa86a"), -s * 0.4)
	var sub := "STUFE %d   ·   %s" % [evolution.level + 1, _slot_text()]
	_text(sub, Vector2(size.x * 0.5, cy - 346), 22, Color("9ed5b3"), true)
	var sub_half := ThemeDB.fallback_font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x * 0.5
	for s in [-1.0, 1.0]:
		draw_line(Vector2(size.x * 0.5 + s * (sub_half + 16), cy - 353), Vector2(size.x * 0.5 + s * (sub_half + 130), cy - 353), Color("4f7a5c"), 2, true)
	for slot in evolution.offers.size():
		_draw_card(slot, evolution.offers[slot])
	var rerolls := _count("rerolls")
	var skips := _count("skips")
	if rerolls > 0:
		_small_button(_reroll_rect(), "NEU WÜRFELN  ×%d" % rerolls, Color("7fd0e0"))
	if skips > 0:
		_small_button(_skip_rect(), "ÜBERSPRINGEN  ×%d" % skips, Color("c5b58f"))
	var keys := "KARTE ANTIPPEN  ·  1 / 2 / 3"
	if rerolls > 0:
		keys += "  ·  R NEU"
	if skips > 0:
		keys += "  ·  X WEITER"
	_text(keys, Vector2(size.x * 0.5, cy + (548 if rerolls > 0 or skips > 0 else 440)), 21, Color("c5d4bb"), true)

func _draw_card(slot: int, mutation: Array) -> void:
	var id: String = mutation[0]
	var rank: int = evolution.rank(id)
	var accent := _mutation_color(id)
	var card := _mutation_rect(slot)
	var p := card.position
	_frame(card.grow(7), Color(accent, 0.12), Color(accent, 0.0), 0)
	_frame(card, Color("0e211cf5"), accent, 2 | 8, 4.0)
	var kind: String = evolution.kind_of(id) if evolution.has_method("kind_of") else "trait"
	if _count("banishes") > 0:
		var banish := _banish_rect(slot)
		_frame(banish, Color("2a1512e8"), Color("e0785a"), 0, 2.0)
		_text("× VERBANNEN", banish.get_center() + Vector2(0, 7), 18, Color("ffc9b4"), true)
	else:
		# Pores echo the bone-plate texture of the concept frames.
		for pore in [Vector2(-44, 30), Vector2(-26, 22), Vector2(-30, 42)]:
			draw_circle(Vector2(card.end.x, p.y) + pore, 6, Color(accent, 0.35))
	# Icon medallion with number badge.
	var mc := p + Vector2(116, card.size.y * 0.5)
	draw_circle(mc, 84, Color(accent, 0.10))
	draw_circle(mc, 76, INK)
	draw_arc(mc, 76, 0, TAU, 56, accent, 4, true)
	draw_circle(mc, 58, Color(accent, 0.08))
	_icon(id, mc, 50, accent)
	var badge := p + Vector2(44, 40)
	draw_circle(badge, 23, accent)
	draw_circle(badge, 19, INK)
	_text("%d" % (slot + 1), badge + Vector2(0, 9), 25, accent, true)
	# Text column.
	var x := p.x + 222
	var width := card.end.x - x - 28
	var kind_label := "ANGRIFFSFORM" if kind == "attack" else "ANLAGE"
	_text("%s · %s" % [kind_label, _mutation_category(id)], Vector2(x, p.y + 42), 17, Color(accent, 0.85))
	_text(mutation[1], Vector2(x, p.y + 84), 36, accent, false, 6)
	var description: String = _form_rank_text(id, rank) if kind == "attack" else String(mutation[2])
	if description == "":
		description = mutation[2]
	draw_multiline_string(ThemeDB.fallback_font, Vector2(x, p.y + 116), description, HORIZONTAL_ALIGNMENT_LEFT, width, 19, 2, Color("f2eacb"))
	draw_line(Vector2(x, p.y + 158), Vector2(card.end.x - 28, p.y + 158), Color(accent, 0.45), 2)
	# Rank pips: owned ranks filled, the offered rank glows.
	for i in 3:
		var pc := Vector2(x + 14 + i * 32, p.y + 186)
		var shape := PackedVector2Array([pc + Vector2(0, -13), pc + Vector2(10, 0), pc + Vector2(0, 13), pc + Vector2(-10, 0)])
		if i < rank:
			draw_colored_polygon(shape, accent)
		elif i == rank:
			draw_colored_polygon(shape, Color(accent, 0.45 + 0.45 * _pulse(4.0)))
			shape.append(shape[0])
			draw_polyline(shape, Color.WHITE, 2, true)
		else:
			shape.append(shape[0])
			draw_polyline(shape, Color(accent, 0.5), 2, true)
	_text("RANG %d" % (rank + 1), Vector2(x + 104, p.y + 194), 19, Color("b8d0bc"))
	if kind == "attack":
		var tag := "NEUE FORM" if rank == 0 else "VERSTÄRKEN"
		var tag_w := _bold.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		_text(tag, Vector2(card.end.x - 30 - tag_w, p.y + 197), 26, Color.WHITE, false, 5)
		return
	# Before → after, right aligned.
	var prefix := _mutation_sign(id)
	var before := "0 %" if rank == 0 else "%s%d %%" % [prefix, rank * _step_percent(id)]
	var after := "%s%d %%" % [prefix, (rank + 1) * _step_percent(id)]
	var font := _bold
	var after_w := font.get_string_size(after, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	var before_w := font.get_string_size(before, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	var right := card.end.x - 30
	_text(after, Vector2(right - after_w, p.y + 197), 30, Color.WHITE, false, 5)
	var arrow_x := right - after_w - 40
	draw_line(Vector2(arrow_x, p.y + 186), Vector2(arrow_x + 26, p.y + 186), accent, 4)
	draw_colored_polygon(PackedVector2Array([Vector2(arrow_x + 32, p.y + 186), Vector2(arrow_x + 22, p.y + 178), Vector2(arrow_x + 22, p.y + 194)]), accent)
	_text(before, Vector2(arrow_x - 10 - before_w, p.y + 194), 22, Color("9fb6a6"))

# ---------------------------------------------------------------- result / pause

func _draw_result() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("06120ef0"))
	var center := Vector2(size.x * 0.5, size.y * 0.5)
	var accent := Color("e4ad62") if not extinct else Color("f07a4f")
	var panel := Rect2(center.x - 360, center.y - 440, 720, 836)
	_frame(panel, Color("10231ef8"), accent, 1 | 2 | 4 | 8, 4.0)
	if extinct:
		_skull(center + Vector2(0, -366), 40, accent)
	else:
		draw_rect(Rect2(center + Vector2(-26, -396), Vector2(18, 60)), accent)
		draw_rect(Rect2(center + Vector2(8, -396), Vector2(18, 60)), accent)
	_text("AUSGESTORBEN" if extinct else "PAUSE", center + Vector2(0, -276), 54, Color("f5e6ba"), true, 8)
	_text("ÜBERLEBT", center + Vector2(0, -228), 20, Color("b6d0bc"), true)
	_text("%02d:%02d" % [int(elapsed) / 60, int(elapsed) % 60], center + Vector2(0, -180), 50, Color.WHITE, true, 6)
	var stats := [["MAX. SCHWARM", "%d" % peak_population, WARM], ["KILLS", "%d" % kills, CYAN], ["BIOMASSE", "%.1f" % consumed_biomass, Color("f6cc70")]]
	for i in stats.size():
		var tile := Rect2(center.x - 320 + i * 220, center.y - 150, 200, 100)
		_frame(tile, Color("0a1a16"), Color(stats[i][2], 0.7), 0)
		_text(stats[i][0], Vector2(tile.get_center().x, tile.position.y + 32), 17, Color("b6d0bc"), true)
		_text(stats[i][1], Vector2(tile.get_center().x, tile.position.y + 80), 38, stats[i][2], true)
	var level: int = 0 if evolution == null else evolution.level
	_text("MUTATIONEN  %d" % level, center + Vector2(0, -12), 24, Color("f4c48c"), true)
	var row := 0
	if evolution != null:
		for mutation in _all_mutations():
			var rank: int = evolution.rank(mutation[0])
			if rank <= 0:
				continue
			var color := _mutation_color(mutation[0])
			var cell := center + Vector2(-322 + (row % 2) * 330, 30 + int(row / 2.0) * 60)
			draw_circle(cell + Vector2(24, 0), 24, INK)
			draw_arc(cell + Vector2(24, 0), 24, 0, TAU, 32, color, 2, true)
			_icon(mutation[0], cell + Vector2(24, 0), 16, color)
			_text(mutation[1], cell + Vector2(58, 7), 21, color)
			if evolution.has_method("kind_of") and evolution.kind_of(mutation[0]) == "evolved":
				_text("EVO", cell + Vector2(246, 8), 21, ALPHA_AMBER, false, 3)
				row += 1
				continue
			for i in 3:
				var pc := cell + Vector2(252 + i * 22, 0)
				var shape := PackedVector2Array([pc + Vector2(0, -9), pc + Vector2(7, 0), pc + Vector2(0, 9), pc + Vector2(-7, 0)])
				if i < rank:
					draw_colored_polygon(shape, color)
				else:
					shape.append(shape[0])
					draw_polyline(shape, Color(color, 0.45), 2, true)
			row += 1
	if row == 0:
		_text("Keine Mutationen gewählt", center + Vector2(0, 36), 21, Color("8fa597"), true)
	var button := _action_rect()
	var button_color := WARM if extinct else Color("7fd0a0")
	_frame(button.grow(8), Color(button_color, 0.10 + 0.08 * _pulse(2.5)), Color(button_color, 0.0), 0)
	_frame(button, Color("8a3a18") if extinct else Color("235a45"), button_color, 0, 4.0)
	_text("NEUER RUN" if extinct else "WEITERSPIELEN", button.get_center() + Vector2(0, 12), 31 if extinct else 34, Color.WHITE, true, 6)
	if extinct:
		var hub := _hub_rect()
		_frame(hub, Color("1d4a3a"), Color("7fd0a0"), 0, 4.0)
		_text("BRUTSTÄTTE", hub.get_center() + Vector2(0, 12), 31, Color.WHITE, true, 6)
	_text("R / ENTER  ·  H BRUTSTÄTTE" if extinct else "P / ESCAPE", center + Vector2(0, 360), 19, Color("b6d0bc"), true)

# ---------------------------------------------------------------- helpers

func _text(value: String, point: Vector2, font_size: int, color: Color = Color.WHITE, centered: bool = false, outline: int = 0) -> void:
	var font: Font = _bold if font_size >= 24 else ThemeDB.fallback_font
	var origin := point
	if centered:
		origin.x -= font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5
	if outline > 0:
		draw_string_outline(font, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, Color(0.02, 0.07, 0.06, 0.85))
	draw_string(font, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _rounded_points(rect: Rect2, radius: float, steps: int = 6) -> PackedVector2Array:
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var centers := [Vector2(rect.end.x - r, rect.position.y + r), rect.end - Vector2(r, r), Vector2(rect.position.x + r, rect.end.y - r), rect.position + Vector2(r, r)]
	var points := PackedVector2Array()
	for i in 4:
		var start := -PI * 0.5 + i * PI * 0.5
		for s in steps + 1:
			var angle := start + PI * 0.5 * float(s) / float(steps)
			points.append(centers[i] + Vector2(cos(angle), sin(angle)) * r)
	return points

# Organic panel: soft rounded body, double rim and optional claws.
# claws bitmask: 1 top-left, 2 top-right, 4 bottom-right, 8 bottom-left.
func _frame(rect: Rect2, fill: Color, edge: Color, claws: int = 0, width: float = 3.0) -> void:
	var radius := minf(26.0, minf(rect.size.x, rect.size.y) * 0.32)
	var points := _rounded_points(rect, radius)
	draw_colored_polygon(points, fill)
	if edge.a <= 0.0:
		return
	var inner := _rounded_points(rect.grow(-6), radius - 5)
	inner.append(inner[0])
	draw_polyline(inner, Color(edge, 0.22), 2.0, true)
	points.append(points[0])
	draw_polyline(points, edge, width, true)
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	var outward := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for i in 4:
		if claws & (1 << i):
			var dir: Vector2 = outward[i].normalized()
			var base: Vector2 = corners[i] - dir * radius * 0.28
			_claw(base, dir, 22, 7, CLAW, 0.45 if i % 2 == 0 else -0.45)

func _claw(base: Vector2, direction: Vector2, length: float, width: float, color: Color, bend: float = 0.35) -> void:
	var d := direction.normalized()
	var side := Vector2(-d.y, d.x)
	var points := PackedVector2Array()
	var steps := 6
	for i in steps + 1:
		var t := float(i) / steps
		points.append(base + d * length * t + side * (bend * length * t * t) + side * width * (1.0 - t))
	for i in range(steps - 1, -1, -1):
		var t := float(i) / steps
		points.append(base + d * length * t + side * (bend * length * t * t) - side * width * (1.0 - t))
	draw_colored_polygon(points, color)

func _bar(rect: Rect2, fraction: float, color: Color) -> void:
	var back := _rounded_points(rect, rect.size.y * 0.5, 4)
	draw_colored_polygon(back, Color("2a4a44"))
	if fraction > 0.0:
		var fill := Rect2(rect.position, Vector2(maxf(rect.size.y, rect.size.x * fraction), rect.size.y))
		draw_colored_polygon(_rounded_points(fill, rect.size.y * 0.5, 4), color)

func _segment_bar(rect: Rect2, fraction: float, color: Color, segments: int) -> void:
	var gap := 3.0
	var seg := (rect.size.x - gap * (segments - 1)) / segments
	for i in segments:
		var cell := Rect2(rect.position + Vector2(i * (seg + gap), 0), Vector2(seg, rect.size.y))
		draw_rect(cell, Color("3a3c33"))
		var amount := clampf(fraction * segments - i, 0.0, 1.0)
		if amount > 0.0:
			draw_rect(Rect2(cell.position, Vector2(seg * amount, rect.size.y)), color)
			draw_rect(Rect2(cell.position, Vector2(seg * amount, 3)), color.lightened(0.35))

# Small dark pill with a coloured diamond; returns the right edge.
func _chip(x: float, text: String, accent: Color, color: Color) -> float:
	var w := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 50
	draw_colored_polygon(_rounded_points(Rect2(x, 130, w, 34), 17, 4), Color("0f231ed8"))
	_threat_dot(Vector2(x + 20, 147), accent)
	_text(text, Vector2(x + 36, 154), 20, color)
	return x + w

func _threat_dot(center: Vector2, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -9), center + Vector2(8, 0), center + Vector2(0, 9), center + Vector2(-8, 0)]), color)

func _mawling_head(center: Vector2, r: float, color: Color, facing: float = 1.0) -> void:
	var s := Vector2(r * facing, r)
	var outline := PackedVector2Array()
	for v in [Vector2(-0.95, 0.15), Vector2(-0.85, -0.4), Vector2(-0.5, -0.72), Vector2(-0.05, -0.82), Vector2(0.45, -0.66), Vector2(0.9, -0.42), Vector2(1.05, -0.2), Vector2(1.0, -0.08), Vector2(0.12, 0.06), Vector2(0.86, 0.3), Vector2(0.9, 0.42), Vector2(0.6, 0.6), Vector2(0.05, 0.64), Vector2(-0.5, 0.62), Vector2(-0.86, 0.45)]:
		outline.append(center + v * s)
	for spike in [[Vector2(-0.93, -0.05), Vector2(-0.8, -0.48), Vector2(-1.28, -0.5)], [Vector2(-0.72, -0.56), Vector2(-0.34, -0.78), Vector2(-0.78, -1.02)], [Vector2(-0.22, -0.8), Vector2(0.14, -0.78), Vector2(-0.2, -1.1)]]:
		draw_colored_polygon(PackedVector2Array([center + spike[0] * s, center + spike[1] * s, center + spike[2] * s]), color.darkened(0.2))
	draw_colored_polygon(outline, color)
	var tooth := Color("fff1d0")
	for t in [0.18, 0.46, 0.74]:
		var a: Vector2 = Vector2(0.95, -0.07).lerp(Vector2(0.2, 0.05), t)
		draw_colored_polygon(PackedVector2Array([center + (a + Vector2(-0.08, 0)) * s, center + (a + Vector2(0.08, 0)) * s, center + (a + Vector2(0, 0.2)) * s]), tooth)
	for t in [0.3, 0.65]:
		var b: Vector2 = Vector2(0.2, 0.1).lerp(Vector2(0.84, 0.31), t)
		draw_colored_polygon(PackedVector2Array([center + (b + Vector2(-0.07, 0.02)) * s, center + (b + Vector2(0.07, 0.02)) * s, center + (b + Vector2(0, -0.17)) * s]), tooth)
	draw_circle(center + Vector2(0.36, -0.36) * s, r * 0.13, INK)
	draw_circle(center + Vector2(0.39, -0.39) * s, r * 0.05, Color("ffe07a"))

func _helix(center: Vector2, height: float, color: Color) -> void:
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
			draw_line(a[i], b[i], Color(color, 0.5), 2)
	draw_polyline(a, color, 4, true)
	draw_polyline(b, color.darkened(0.2), 4, true)

func _skull(center: Vector2, r: float, color: Color) -> void:
	draw_circle(center + Vector2(0, -0.18 * r), 0.82 * r, color)
	draw_rect(Rect2(center + Vector2(-0.46, 0.25) * r, Vector2(0.92, 0.55) * r), color)
	for side in [-1.0, 1.0]:
		draw_circle(center + Vector2(side * 0.32, -0.16) * r, 0.23 * r, INK)
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, 0.12) * r, center + Vector2(0.1, 0.32) * r, center + Vector2(-0.1, 0.32) * r]), INK)
	for i in 3:
		var x := (-0.2 + i * 0.2) * r
		draw_line(center + Vector2(x, 0.5 * r), center + Vector2(x, 0.8 * r), INK, maxf(1.5, r * 0.08))

func _crown(c: Vector2, r: float, color: Color) -> void:
	var k := r / 20.0
	draw_colored_polygon(PackedVector2Array([c + Vector2(-20, 12) * k, c + Vector2(-22, -12) * k, c + Vector2(-10, 0) * k, c + Vector2(0, -17) * k, c + Vector2(10, 0) * k, c + Vector2(22, -12) * k, c + Vector2(20, 12) * k]), color)

func _biomass_drop(c: Vector2, r: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 17:
		var angle := -PI * 0.2 + (PI * 1.4) * i / 16.0
		points.append(c + Vector2(cos(angle), sin(angle)) * r + Vector2(0, r * 0.25))
	points.append(c + Vector2(0, -r * 1.35))
	draw_colored_polygon(points, color)

func _ring_sector(c: Vector2, r_in: float, r_out: float, a0: float, a1: float, color: Color) -> void:
	var points := PackedVector2Array()
	var steps := 14
	for i in steps + 1:
		var a := lerpf(a0, a1, float(i) / steps)
		points.append(c + Vector2(cos(a), sin(a)) * r_out)
	for i in range(steps, -1, -1):
		var a := lerpf(a0, a1, float(i) / steps)
		points.append(c + Vector2(cos(a), sin(a)) * r_in)
	draw_colored_polygon(points, color)

func _ellipse(c: Vector2, rx: float, ry: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		points.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(points, color)

func _mutation_color(id: String) -> Color:
	match id:
		"rudelbiss":
			return Color("ff9a4a")
		"sporenwolke":
			return Color("c4dc5a")
		"saeurespucker":
			return Color("7eec5c")
		"stachelruecken":
			return Color("f0d28c")
		"aetzflut":
			return Color("a6ff4f")
		"meute":
			return Color("ff6f5a")
	if id in ["jaws", "pack"]:
		return Color("f58a4d")
	if id in ["brood", "glutton"]:
		return Color("68d8c7")
	if id == "scatter":
		return Color("b798ec")
	return Color("b8d879")

func _mutation_category(id: String) -> String:
	match id:
		"rudelbiss":
			return "SPRUNG"
		"sporenwolke":
			return "AURA"
		"saeurespucker":
			return "FERNKAMPF"
		"stachelruecken":
			return "VERGELTUNG"
		"aetzflut", "meute":
			return "EVOLUTION"
	if id in ["jaws", "pack"]:
		return "ANGRIFF"
	if id in ["brood", "glutton"]:
		return "WACHSTUM"
	if id == "scatter":
		return "REFLEX"
	return "SCHUTZ"

func _mutation_sign(id: String) -> String:
	return "−" if id in ["scatter", "armor"] else "+"

func _step_percent(id: String) -> int:
	if id in ["jaws", "glutton"]:
		return 25
	if id in ["brood", "scatter", "armor"]:
		return 30 if id == "brood" else 10
	return 20

func _icon(id: String, c: Vector2, r: float, color: Color) -> void:
	var tooth := Color("fff1d0")
	if id == "jaws":
		_ring_sector(c + Vector2(0, -0.08 * r), 0.5 * r, 0.9 * r, PI + 0.35, TAU - 0.35, color)
		_ring_sector(c + Vector2(0, 0.08 * r), 0.5 * r, 0.85 * r, 0.45, PI - 0.45, color.darkened(0.12))
		for i in 4:
			var a := PI + 0.62 + i * 0.62
			var base := c + Vector2(0, -0.08 * r) + Vector2(cos(a), sin(a)) * 0.52 * r
			var tangent := Vector2(-sin(a), cos(a))
			draw_colored_polygon(PackedVector2Array([base + tangent * 0.12 * r, base - tangent * 0.12 * r, base.lerp(c, 0.55)]), tooth)
		for i in 3:
			var a := 0.95 + i * 0.6
			var base := c + Vector2(0, 0.08 * r) + Vector2(cos(a), sin(a)) * 0.52 * r
			var tangent := Vector2(-sin(a), cos(a))
			draw_colored_polygon(PackedVector2Array([base + tangent * 0.11 * r, base - tangent * 0.11 * r, base.lerp(c, 0.5)]), tooth)
	elif id == "brood":
		_ring_sector(c + Vector2(0, 0.2 * r), 0.62 * r, 0.9 * r, 0.25, PI - 0.25, color.darkened(0.45))
		for offset in [Vector2(-0.36, 0.18), Vector2(0.36, 0.18), Vector2(0, -0.26)]:
			var e: Vector2 = c + offset * r
			_ellipse(e, 0.3 * r, 0.4 * r, color)
			draw_circle(e + Vector2(-0.1, -0.14) * r, 0.07 * r, Color(1, 1, 1, 0.55))
			draw_circle(e + Vector2(0.1, 0.1) * r, 0.06 * r, color.darkened(0.45))
			draw_circle(e + Vector2(-0.05, 0.2) * r, 0.045 * r, color.darkened(0.45))
	elif id == "glutton":
		_biomass_drop(c + Vector2(0, 0.08 * r), 0.62 * r, color)
		draw_circle(c + Vector2(0.52, -0.02) * r, 0.3 * r, INK)
		draw_circle(c + Vector2(-0.18, 0.14) * r, 0.12 * r, Color(1, 1, 1, 0.45))
		for p in [Vector2(0.62, 0.52), Vector2(0.86, 0.3)]:
			draw_circle(c + p * r, 0.09 * r, color)
	elif id == "pack":
		_mawling_head(c + Vector2(-0.38, -0.3) * r, 0.36 * r, color.darkened(0.25))
		_mawling_head(c + Vector2(0.4, -0.22) * r, 0.34 * r, color.darkened(0.12))
		_mawling_head(c + Vector2(0.0, 0.3) * r, 0.46 * r, color)
	elif id in ["rudelbiss", "meute"]:
		# Leaping head(s) with a motion arc.
		draw_arc(c + Vector2(-0.15, 0.55) * r, 0.75 * r, PI * 1.05, PI * 1.6, 12, Color(color, 0.6), maxf(3.0, 0.1 * r), true)
		if id == "meute":
			_mawling_head(c + Vector2(-0.45, 0.25) * r, 0.36 * r, color.darkened(0.3))
			_mawling_head(c + Vector2(0.5, 0.35) * r, 0.34 * r, color.darkened(0.2))
		_mawling_head(c + Vector2(0.1, -0.2) * r, 0.52 * r, color)
		for i in 3:
			draw_line(c + Vector2(-0.95 + i * 0.12, -0.35 + i * 0.28) * r, c + Vector2(-0.6 + i * 0.12, -0.35 + i * 0.28) * r, Color(color, 0.7), maxf(2.0, 0.07 * r))
	elif id == "sporenwolke":
		for spore in [[Vector2(0, 0), 0.42], [Vector2(-0.48, 0.2), 0.3], [Vector2(0.5, 0.18), 0.32], [Vector2(-0.2, -0.45), 0.26], [Vector2(0.3, -0.42), 0.22]]:
			draw_circle(c + spore[0] * r, spore[1] * r, Color(color, 0.85))
			draw_circle(c + spore[0] * r + Vector2(-0.08, -0.08) * r, spore[1] * r * 0.35, Color(1, 1, 1, 0.35))
		draw_arc(c, 0.95 * r, 0, TAU, 32, Color(color, 0.5), maxf(2.0, 0.06 * r), true)
	elif id in ["saeurespucker", "aetzflut"]:
		if id == "aetzflut":
			_ellipse(c + Vector2(0, 0.62) * r, 0.85 * r, 0.26 * r, Color(color, 0.55))
		_biomass_drop(c + Vector2(0.25, -0.05) * r, 0.42 * r, color)
		draw_circle(c + Vector2(0.14, -0.1) * r, 0.1 * r, Color(1, 1, 1, 0.5))
		for i in 3:
			draw_circle(c + Vector2(-0.35 - i * 0.22, 0.2 + i * 0.16) * r, (0.13 - i * 0.03) * r, Color(color, 0.8 - i * 0.2))
	elif id == "stachelruecken":
		_ring_sector(c + Vector2(0, 0.35 * r), 0.2 * r, 0.55 * r, PI, TAU, color.darkened(0.35))
		for i in 5:
			var a := PI + 0.35 + i * 0.6
			var dir := Vector2(cos(a), sin(a))
			var base := c + Vector2(0, 0.35 * r) + dir * 0.5 * r
			var side := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([base + side * 0.13 * r, base - side * 0.13 * r, base + dir * 0.55 * r]), color)
	elif id == "scatter":
		var origin := c + Vector2(0, 0.7 * r)
		for angle in [-2.35, -PI * 0.5, -0.79]:
			var dir := Vector2(cos(angle), sin(angle))
			var tip := origin + dir * 1.25 * r
			draw_line(origin, tip - dir * 0.2 * r, color, maxf(3.0, 0.14 * r))
			var side := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([tip, tip - dir * 0.36 * r + side * 0.22 * r, tip - dir * 0.36 * r - side * 0.22 * r]), color)
		draw_circle(origin, 0.16 * r, color)
	else:
		var shield := PackedVector2Array([c + Vector2(0, -0.95) * r, c + Vector2(0.72, -0.55) * r, c + Vector2(0.6, 0.45) * r, c + Vector2(0, 0.98) * r, c + Vector2(-0.6, 0.45) * r, c + Vector2(-0.72, -0.55) * r])
		for side in [-1.0, 0.0, 1.0]:
			var base := c + Vector2(side * 0.4, -0.72 + absf(side) * 0.1) * r
			draw_colored_polygon(PackedVector2Array([base + Vector2(-0.14, 0.1) * r, base + Vector2(0.14, 0.1) * r, base + Vector2(0, -0.34) * r]), tooth)
		draw_colored_polygon(shield, color)
		for y in [-0.2, 0.2]:
			draw_line(c + Vector2(-0.55, y) * r, c + Vector2(0.55, y) * r, INK, maxf(2.0, 0.09 * r))
		draw_line(c + Vector2(0, -0.8) * r, c + Vector2(0, 0.85) * r, INK, maxf(2.0, 0.08 * r))

# ---------------------------------------------------------------- progression

func _slot_text() -> String:
	if evolution == null or not evolution.has_method("slots_used"):
		return "WELT PAUSIERT"
	return "Angriff %d/%d · Anlagen %d/%d" % [evolution.slots_used("attack"), evolution.slot_limit("attack"), evolution.slots_used("trait"), evolution.slot_limit("trait")]

func _all_mutations() -> Array:
	var result: Array = []
	for group in ["ATTACKS", "EVOLVED", "TRAITS"]:
		var entries: Variant = evolution.get(group) if evolution != null else null
		if entries is Array:
			result.append_array(entries)
	return result

# Per-rank description of an attack form from AttackForms.FORMS, "" if unknown.
func _form_rank_text(id: String, owned_rank: int) -> String:
	if not _forms_loaded:
		_forms_loaded = true
		if ResourceLoader.exists(FORMS_PATH):
			var script: Script = load(FORMS_PATH)
			if script != null:
				var forms: Variant = script.get_script_constant_map().get("FORMS")
				if forms is Dictionary:
					_forms = forms
	var entry: Variant = _forms.get(id)
	var texts: Array = []
	if entry is Dictionary:
		texts = entry.get("ranks", [])
	elif entry is Array and entry.size() > 1:
		texts = entry[1] if entry[1] is Array else entry.slice(1)
	if texts.is_empty():
		return ""
	return str(texts[clampi(owned_rank, 0, texts.size() - 1)])

func _small_button(rect: Rect2, label: String, accent: Color) -> void:
	_frame(rect, Color("10231ef0"), accent, 0, 3.0)
	_text(label, rect.get_center() + Vector2(0, 9), 24, Color.WHITE, true, 4)

# Amber core in a violet shell, as on the ground.
func _alpha_gem(c: Vector2, r: float) -> void:
	draw_circle(c, r * 1.35, Color(ALPHA_VIOLET, 0.25 + 0.15 * _pulse(4.0)))
	var shell := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.8, 0), c + Vector2(0, r), c + Vector2(-r * 0.8, 0)])
	draw_colored_polygon(shell, ALPHA_VIOLET)
	var core := PackedVector2Array([c + Vector2(0, -r * 0.55), c + Vector2(r * 0.42, 0), c + Vector2(0, r * 0.55), c + Vector2(-r * 0.42, 0)])
	draw_colored_polygon(core, ALPHA_AMBER)
	draw_circle(c + Vector2(-r * 0.12, -r * 0.2), r * 0.12, Color(1, 1, 1, 0.7))

func _alpha_chip() -> void:
	var text := "ALPHA-KERN ×%d" % alpha_cores
	var w := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 56
	var x := size.x - w - 16
	draw_colored_polygon(_rounded_points(Rect2(x, 130, w, 34), 17, 4), Color("1d1330e0"))
	_alpha_gem(Vector2(x + 22, 147), 11)
	_text(text, Vector2(x + 40, 154), 20, Color("ffd9a0"))

# Owned attack forms as medallions on the right edge: icon plus rank pips.
func _draw_form_badges() -> void:
	if evolution == null or not evolution.has_method("attack_ranks") or extinct:
		return
	var y := 214.0
	for mutation in _all_mutations():
		var id: String = mutation[0]
		var rank: int = evolution.rank(id)
		if rank <= 0 or evolution.kind_of(id) == "trait":
			continue
		var accent := _mutation_color(id)
		var c := Vector2(size.x - 50, y)
		draw_circle(c, 33, Color("0f231ed8"))
		draw_arc(c, 31, 0, TAU, 32, accent, 3, true)
		_icon(id, c, 22, accent)
		if evolution.kind_of(id) == "evolved":
			_alpha_gem(c + Vector2(-26, -24), 8)
		else:
			for i in 3:
				var pc := c + Vector2(-16 + i * 16, 42)
				var shape := PackedVector2Array([pc + Vector2(0, -6), pc + Vector2(5, 0), pc + Vector2(0, 6), pc + Vector2(-5, 0)])
				draw_colored_polygon(shape, accent if i < rank else Color(accent, 0.25))
		y += 96

func _draw_evolve_banner() -> void:
	var fade := clampf(evolve_flash / 0.6, 0.0, 1.0)
	var cy := size.y * 0.5 - 250
	var rect := Rect2(Vector2(size.x * 0.5 - 300, cy - 58), Vector2(600, 116))
	_frame(rect.grow(10), Color(ALPHA_VIOLET, 0.16 * fade), Color(ALPHA_VIOLET, 0.0), 0)
	_frame(rect, Color(0.07, 0.05, 0.12, 0.9 * fade), Color(ALPHA_AMBER, fade), 1 | 2, 4.0)
	_alpha_gem(Vector2(rect.position.x + 56, cy), 26)
	_text("EVOLUTION", Vector2(size.x * 0.5 + 30, cy - 12), 24, Color(ALPHA_AMBER, fade), true, 4)
	_text(evolve_name.to_upper(), Vector2(size.x * 0.5 + 30, cy + 36), 44, Color(1, 1, 1, fade), true, 7)
