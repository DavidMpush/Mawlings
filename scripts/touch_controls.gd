extends Control

signal restart_requested
signal pause_requested
signal mutation_chosen(slot: int)

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
var last_loss := 0


func _ready() -> void:
	set_process_input(true)
	queue_redraw()


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
		elif extinct and event.keycode in [KEY_R, KEY_ENTER]:
			restart_requested.emit()
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
		return
	if _pause_rect().has_point(location):
		pause_requested.emit()
		return
	if evolution != null and not evolution.offers.is_empty():
		for slot in evolution.offers.size():
			if _mutation_rect(slot).has_point(location):
				mutation_chosen.emit(slot)
				return
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
	return Rect2(Vector2(size.x - 112, 146), Vector2(88, 64))

func _action_rect() -> Rect2:
	return Rect2(Vector2(size.x * 0.5 - 220, size.y * 0.5 + 235), Vector2(440, 88))

func _mutation_rect(slot: int) -> Rect2:
	return Rect2(Vector2(48, size.y * 0.5 - 300 + slot * 238), Vector2(size.x - 96, 214))

func _draw() -> void:
	var font := ThemeDB.fallback_font
	_draw_top(font)
	if hit_feedback > 0.0 and not extinct:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.95, 0.24, 0.12, minf(0.11, hit_feedback * 0.11)))
		_center_text(font, "−%d MAWLINGS" % last_loss, Vector2(size.x * 0.5, size.y * 0.5 - 170), 27, Color("ffe2c5"))
	if extinct or paused:
		_draw_result(font)
	elif evolution != null and not evolution.offers.is_empty():
		_draw_mutations(font)
	else:
		_draw_controls(font)

func _draw_top(font: Font) -> void:
	var panel := Color("102920e8")
	var bone := Color("f5e4b7")
	var warm := Color("f4783e")
	var cyan := Color("6ee4d4")
	_panel(Rect2(24, 24, 248, 111), panel, warm)
	_icon("jaws", Vector2(53, 78), 29, warm)
	draw_string(font, Vector2(96, 65), "SCHWARM", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, bone)
	draw_string(font, Vector2(96, 111), "%d" % population, HORIZONTAL_ALIGNMENT_LEFT, -1, 43, Color.WHITE)
	_panel(Rect2(size.x * 0.5 - 136, 24, 272, 111), panel, Color("b6c58e"))
	_center_text(font, "%02d:%02d" % [int(elapsed) / 60, int(elapsed) % 60], Vector2(size.x * 0.5, 83), 43, bone)
	var danger_fraction := clampf(log(maxf(1.0, pressure)) / log(256.0), 0.0, 1.0)
	var pressure_rect := Rect2(size.x * 0.5 - 101, 99, 202, 12)
	draw_rect(pressure_rect, Color("263b36"))
	draw_rect(Rect2(pressure_rect.position, Vector2(pressure_rect.size.x * maxf(0.05, danger_fraction), 12)), Color("ef7453"))
	_panel(Rect2(size.x - 272, 24, 248, 111), panel, cyan)
	var level: int = 0 if evolution == null else evolution.level
	var dna: int = 0 if evolution == null else evolution.dna
	var needed: int = 20 if evolution == null else evolution.threshold()
	draw_string(font, Vector2(size.x - 247, 65), "EVOLUTION  %d" % level, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, bone)
	draw_string(font, Vector2(size.x - 247, 97), "%d / %d DNA" % [dna, needed] if evolution == null or not evolution.complete() else "MAXIMUM", HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color.WHITE)
	draw_rect(Rect2(size.x - 247, 108, 198, 11), Color("254039"))
	if evolution != null and not evolution.complete():
		draw_rect(Rect2(size.x - 247, 108, 198.0 * clampf(float(dna) / float(needed), 0, 1), 11), cyan)
	var pause := _pause_rect()
	_panel(pause, panel, bone)
	draw_rect(Rect2(pause.position + Vector2(29, 17), Vector2(7, 29)), bone)
	draw_rect(Rect2(pause.position + Vector2(49, 17), Vector2(7, 29)), bone)
	_center_text(font, "DRUCK ×%.1f" % pressure, Vector2(size.x * 0.5, 179), 22, Color("f6c79f"))
	if hunters + skitters > 0:
		draw_string(font, Vector2(30, 188), "JÄGER %d   SKITTER %d" % [hunters, skitters], HORIZONTAL_ALIGNMENT_LEFT, -1, 21, bone)
	if boss_health > 0.0:
		var boss_rect := Rect2(size.x * 0.5 - 305, 206, 610, 75)
		_panel(boss_rect, Color("172921ed"), Color("e98e56"))
		_center_text(font, "BOG KING", Vector2(size.x * 0.5, 236), 24, Color("ffe3ba"))
		draw_rect(Rect2(size.x * 0.5 - 264, 251, 528, 12), Color("493833"))
		draw_rect(Rect2(size.x * 0.5 - 264, 251, 528 * clampf(boss_health / boss_max_health, 0.0, 1.0), 12), Color("f09b63"))
	if nearest_corpse != "":
		var corpse_y := 296.0 if boss_health > 0.0 else 216.0
		_panel(Rect2(24, corpse_y, minf(465, size.x - 48), 46), Color("102920d8"), Color("d9ad56"))
		draw_string(font, Vector2(43, corpse_y + 30), nearest_corpse, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, bone)
	if biomass_bank > 0.01:
		draw_string(font, Vector2(35, 374 if boss_health > 0.0 else 294), "BIOMASSE %.1f / 2" % biomass_bank, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color("f6cc70"))

func _draw_controls(font: Font) -> void:
	if hint != "":
		_panel(Rect2(24, size.y - 336, size.x - 48, 65), Color("102920cd"), Color("8cae81"))
		_center_text(font, hint, Vector2(size.x * 0.5, size.y - 294), 23, Color("f4e9cf"))
	var left := _rally_center()
	var right := _movement_center()
	draw_circle(left, 96, Color("112720bc"))
	draw_arc(left, 92, -PI, PI, 64, Color("fa9153"), 5)
	draw_circle(left, 68, Color("b14428" if rally_pressed else "5b2c21"))
	_icon("pack", left + Vector2(0, -7), 34, Color("ffe0b3"))
	_center_text(font, "RALLY", left + Vector2(0, 50), 22, Color.WHITE)
	draw_circle(right, 96, Color("102c2f98"))
	draw_arc(right, 92, -PI, PI, 64, Color("a0d9ca"), 4)
	draw_circle(right, 67, Color("183b3cc0"))
	draw_circle(right + movement_vector * 52, 30, Color("d8eee0"))
	_center_text(font, "BEWEGEN", right + Vector2(0, 131), 20, Color("f4e9cf"))

func _draw_mutations(font: Font) -> void:
	draw_rect(Rect2(Vector2(0, 215), Vector2(size.x, size.y - 215)), Color("06120ddc"))
	_center_text(font, "MUTATION WÄHLEN", Vector2(size.x * 0.5, size.y * 0.5 - 380), 43, Color("f5e6ba"))
	_center_text(font, "STUFE %d  ·  WELT PAUSIERT" % (evolution.level + 1), Vector2(size.x * 0.5, size.y * 0.5 - 340), 22, Color("9ed5b3"))
	for slot in evolution.offers.size():
		var mutation: Array = evolution.offers[slot]
		var id: String = mutation[0]
		var rank: int = evolution.rank(id)
		var accent := _mutation_color(id)
		var card := _mutation_rect(slot)
		_panel(card, Color("112c25f5"), accent)
		draw_rect(Rect2(card.position.x + 20, card.position.y + 21, 118, card.size.y - 42), Color("091c19"))
		_icon(id, card.position + Vector2(79, card.size.y * 0.5), 47, accent)
		var x := card.position.x + 160
		draw_string(font, Vector2(x, card.position.y + 58), "%d   %s" % [slot + 1, mutation[1]], HORIZONTAL_ALIGNMENT_LEFT, -1, 30, accent)
		draw_string(font, Vector2(x, card.position.y + 103), mutation[2], HORIZONTAL_ALIGNMENT_LEFT, int(card.size.x - 176), 22, Color("f2eacb"))
		draw_rect(Rect2(x, card.position.y + 128, card.size.x - 188, 2), accent.darkened(0.45))
		draw_string(font, Vector2(x, card.position.y + 162), "RANG %d / 3" % (rank + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("b8d0bc"))
		draw_string(font, Vector2(x, card.position.y + 189), "%d %%  →  %d %%" % [rank * _step_percent(id), (rank + 1) * _step_percent(id)], HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color.WHITE)
	_center_text(font, "KARTE ANTIPPEN  ODER  1 / 2 / 3", Vector2(size.x * 0.5, size.y * 0.5 + 476), 21, Color("c5d4bb"))

func _draw_result(font: Font) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("06120ef0"))
	var center := Vector2(size.x * 0.5, size.y * 0.5)
	_panel(Rect2(center.x - 355, center.y - 427, 710, 810), Color("142d24"), Color("e4ad62"))
	_center_text(font, "AUSGESTORBEN" if extinct else "PAUSE", center + Vector2(0, -318), 47, Color("f5e6ba"))
	_center_text(font, "ÜBERLEBT  %02d:%02d" % [int(elapsed) / 60, int(elapsed) % 60], center + Vector2(0, -239), 28, Color.WHITE)
	_center_text(font, "GRÖSSTER SCHWARM  %d" % peak_population, center + Vector2(0, -190), 23, Color("d5e8cc"))
	_center_text(font, "KILLS  %d    ·    BIOMASSE  %.1f" % [kills, consumed_biomass], center + Vector2(0, -149), 22, Color("d5e8cc"))
	_center_text(font, "MUTATIONEN  %d" % (0 if evolution == null else evolution.level), center + Vector2(0, -91), 24, Color("f4c48c"))
	if evolution != null:
		var row := 0
		for mutation in evolution.TRAITS:
			var rank: int = evolution.rank(mutation[0])
			if rank > 0:
				_center_text(font, "%s   %d / 3" % [mutation[1], rank], center + Vector2(0, -46 + row * 38), 22, _mutation_color(mutation[0]))
				row += 1
	var button := _action_rect()
	_panel(button, Color("295e4b"), Color("a7ddab"))
	_center_text(font, "NEUER RUN" if extinct else "WEITERSPIELEN", center + Vector2(0, 291), 29, Color.WHITE)
	_center_text(font, "R / ENTER" if extinct else "P / ESCAPE", center + Vector2(0, 355), 20, Color("b6d0bc"))

func _panel(rect: Rect2, fill: Color, edge: Color) -> void:
	var x := rect.position.x
	var y := rect.position.y
	var w := rect.size.x
	var h := rect.size.y
	var cut := minf(18, minf(w, h) * 0.18)
	var points := PackedVector2Array([Vector2(x + cut, y), Vector2(x + w - cut, y), Vector2(x + w, y + cut), Vector2(x + w, y + h - cut), Vector2(x + w - cut, y + h), Vector2(x + cut, y + h), Vector2(x, y + h - cut), Vector2(x, y + cut)])
	draw_colored_polygon(points, fill)
	points.append(points[0])
	draw_polyline(points, edge, 2.0, true)

func _mutation_color(id: String) -> Color:
	if id in ["jaws", "pack"]:
		return Color("f58a4d")
	if id in ["brood", "glutton"]:
		return Color("68d8c7")
	if id == "scatter":
		return Color("b798ec")
	return Color("b8d879")

func _step_percent(id: String) -> int:
	if id in ["jaws", "glutton"]:
		return 25
	if id in ["brood", "scatter", "armor"]:
		return 30 if id == "brood" else 10
	return 20

func _icon(id: String, center: Vector2, radius: float, color: Color) -> void:
	var dark := Color("102a25")
	if id == "jaws":
		draw_arc(center, radius * 0.80, 0.2, PI - 0.2, 18, color, 7)
		draw_arc(center, radius * 0.80, PI + 0.2, TAU - 0.2, 18, color, 7)
		for side in [-1.0, 1.0]:
			draw_colored_polygon(PackedVector2Array([center + Vector2(side * 15, -8), center + Vector2(side * 30, 5), center + Vector2(side * 7, 11)]), color)
	elif id == "brood":
		for offset in [Vector2(-19, 7), Vector2(19, 7), Vector2(0, -16)]:
			draw_circle(center + offset, radius * 0.30, color)
			draw_circle(center + offset + Vector2(-4, -4), radius * 0.08, dark)
	elif id == "glutton":
		draw_arc(center, radius * 0.72, -PI * 0.78, PI * 0.75, 24, color, 8)
		draw_circle(center + Vector2(0, 7), radius * 0.18, color)
		draw_colored_polygon(PackedVector2Array([center + Vector2(25, -29), center + Vector2(41, -19), center + Vector2(20, -13)]), color)
	elif id == "pack":
		for offset in [Vector2(-23, 14), Vector2(23, 14), Vector2(0, -17)]:
			draw_circle(center + offset, radius * 0.25, color)
		for side in [-1.0, 1.0]:
			draw_line(center + Vector2(0, -8), center + Vector2(side * 18, 8), color, 6)
	elif id == "scatter":
		for side in [-1.0, 1.0]:
			draw_line(center + Vector2(0, 8), center + Vector2(side * 32, -18), color, 8)
			draw_colored_polygon(PackedVector2Array([center + Vector2(side * 36, -28), center + Vector2(side * 35, -9), center + Vector2(side * 17, -19)]), color)
	else:
		var shield := PackedVector2Array([center + Vector2(0, -radius), center + Vector2(radius * 0.7, -radius * 0.5), center + Vector2(radius * 0.55, radius * 0.55), center + Vector2(0, radius), center + Vector2(-radius * 0.55, radius * 0.55), center + Vector2(-radius * 0.7, -radius * 0.5)])
		draw_colored_polygon(shield, color)
		draw_line(center + Vector2(0, -radius * 0.7), center + Vector2(0, radius * 0.65), dark, 5)

func _center_text(font: Font, value: String, point: Vector2, font_size: int, color: Color = Color.WHITE) -> void:
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, point - Vector2(width * 0.5, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
