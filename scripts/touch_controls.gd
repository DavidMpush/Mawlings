extends Control

signal restart_requested
signal pause_requested

var movement_vector := Vector2.ZERO
var rally_pressed := false
var movement_pointer := -1
var rally_pointer := -1
var population := 25
var biomass_bank := 0.0
var corpse_count := 0
var kills := 0
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
	return Rect2(Vector2(size.x - 140.0, 20.0), Vector2(120.0, 70.0))


func _action_rect() -> Rect2:
	return Rect2(Vector2(size.x * 0.5 - 170, size.y * 0.5 + 135), Vector2(340, 80))


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2(18.0, 20.0), Vector2(490.0, 184.0)), Color(0.05, 0.12, 0.10, 0.78))
	draw_string(font, Vector2(38.0, 63.0), "MAWLINGS", HORIZONTAL_ALIGNMENT_LEFT, -1, 31, Color("ffe6b4"))
	draw_string(font, Vector2(38.0, 103.0), "Schwarm  %d" % population, HORIZONTAL_ALIGNMENT_LEFT, -1, 27, Color.WHITE)
	draw_string(font, Vector2(38.0, 144.0), "Biomasse  %.1f / 2" % biomass_bank, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color("d5e7d4"))
	draw_string(font, Vector2(38.0, 178.0), "Kadaver  %d    Beute  %d" % [corpse_count, kills], HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color("d5e7d4"))
	draw_string(font, Vector2(38.0, 239.0), "%02d:%02d   ·   Druck ×%.1f" % [int(elapsed) / 60, int(elapsed) % 60, pressure], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("ffe6b4"))
	draw_string(font, Vector2(38.0, 277.0), nearest_corpse, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color("ffe6b4"))
	draw_rect(_pause_rect(), Color(0.05, 0.12, 0.10, 0.85))
	draw_string(font, _pause_rect().position + Vector2(22, 44), "PAUSE", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	if hit_feedback > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.9, 0.1, 0.04, minf(0.12, hit_feedback * 0.12)))
		draw_string(font, Vector2(size.x * 0.5 - 85, size.y * 0.5 - 150), "−%d Mawlings" % last_loss, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color("ffb299"))
	if hint != "":
		draw_rect(Rect2(Vector2(18.0, size.y - 328.0), Vector2(size.x - 36.0, 62.0)), Color(0.05, 0.12, 0.10, 0.68))
		draw_string(font, Vector2(38.0, size.y - 288.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color("e9ecce"))
	draw_circle(_rally_center(), 86.0, Color(0.45, 0.14, 0.10, 0.82 if rally_pressed else 0.66))
	draw_circle(_movement_center(), 86.0, Color(0.05, 0.21, 0.22, 0.66))
	draw_circle(_movement_center() + movement_vector * 52.0, 31.0, Color("a7e2cf"))
	draw_string(font, _rally_center() + Vector2(-42.0, 8.0), "RALLY", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color.WHITE)
	draw_string(font, _movement_center() + Vector2(-43.0, 114.0), "MOVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color.WHITE)
	if extinct or paused:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.015, 0.04, 0.035, 0.94))
		var center := Vector2(size.x * 0.5, size.y * 0.5)
		_center_text(font, "AUSGESTORBEN" if extinct else "PAUSE", center + Vector2(0, -170), 42)
		_center_text(font, "Überlebt  %02d:%02d" % [int(elapsed) / 60, int(elapsed) % 60], center + Vector2(0, -75), 28)
		_center_text(font, "Größter Schwarm: %d   ·   Kills: %d" % [peak_population, kills], center + Vector2(0, -22), 24)
		_center_text(font, "Geerntete Biomasse: %.1f" % consumed_biomass, center + Vector2(0, 24), 24)
		draw_rect(_action_rect(), Color("296454"))
		_center_text(font, "NEUER RUN" if extinct else "WEITERSPIELEN", center + Vector2(0, 187), 28)
		_center_text(font, "R / Enter" if extinct else "P / Escape", center + Vector2(0, 257), 20)


func _center_text(font: Font, text: String, position: Vector2, font_size: int) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, position - Vector2(width * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("e4f2dc"))
