extends Control

var movement_vector := Vector2.ZERO
var rally_pressed := false
var movement_pointer := -1
var rally_pointer := -1


func _ready() -> void:
	set_process_input(true)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _input(event: InputEvent) -> void:
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


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2(18.0, 20.0), Vector2(410.0, 116.0)), Color(0.05, 0.12, 0.10, 0.78))
	draw_string(font, Vector2(38.0, 63.0), "MAWLINGS", HORIZONTAL_ALIGNMENT_LEFT, -1, 31, Color("ffe6b4"))
	draw_string(font, Vector2(38.0, 104.0), "Godot · Bewegungs-Prototyp", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("d5e7d4"))
	draw_circle(_rally_center(), 86.0, Color(0.45, 0.14, 0.10, 0.82 if rally_pressed else 0.66))
	draw_circle(_movement_center(), 86.0, Color(0.05, 0.21, 0.22, 0.66))
	draw_circle(_movement_center() + movement_vector * 52.0, 31.0, Color("a7e2cf"))
	draw_string(font, _rally_center() + Vector2(-42.0, 8.0), "RALLY", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color.WHITE)
	draw_string(font, _movement_center() + Vector2(-43.0, 114.0), "MOVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color.WHITE)
