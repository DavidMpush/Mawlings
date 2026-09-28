extends SceneTree

# Etappe 27 (S25 feedback): floating movement joystick on the right. The origin
# is the touch-down point, steering is the displacement from it, release resets
# to the rest position; Rally (left) works at the same time (touch and the
# desktop mouse pointer -2), pause/minimap/top HUD/big map never start it, and
# the origin is clamped so the drawn joystick stays on screen.

var failures := 0
var pauses := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(2)
	var world: Variant = scene.get_node("HuntWorld")
	var controls: Variant = scene.get_node("HUD/Controls")
	# Count pause taps instead of pausing the world.
	if controls.pause_requested.is_connected(world.toggle_pause):
		controls.pause_requested.disconnect(world.toggle_pause)
	controls.pause_requested.connect(func() -> void: pauses += 1)
	var size: Vector2 = controls.size
	var rest: Vector2 = controls.movement_rest_center()
	var drawn: Variant = controls.get_node_or_null("hud_controls")

	# --- At rest ----------------------------------------------------------------
	check(not controls.movement_active(), "Joystick idle at start")
	check(controls._movement_center() == rest, "Idle centre is the rest position")
	await _frames(1)
	if drawn != null:
		check(drawn._layers.joy.modulate.a < 0.9, "Idle joystick is drawn dimmed")

	# --- Origin = touch-down point, direction relative to it --------------------
	var high := Vector2(size.x * 0.7, size.y * 0.6)
	_touch(controls, 1, high, true)
	check(controls.movement_active(), "Touch in the right zone starts the joystick")
	check(controls._movement_center() == high, "Origin is the touch-down point")
	check(controls.movement_vector.length() < 0.01, "No movement right at touch-down")
	_drag(controls, 1, high + Vector2(0.0, -66.0))
	check(controls.movement_vector.distance_to(Vector2(0.0, -1.0)) < 0.01, "Drag up = full speed up (relative to the origin)")
	_drag(controls, 1, high + Vector2(33.0, 0.0))
	check(controls.movement_vector.distance_to(Vector2(0.5, 0.0)) < 0.01, "Half drag right = half speed right")
	check(controls._movement_center() == high, "Origin stays while dragging")
	await _frames(1)
	if drawn != null:
		check(drawn._layers.joy.modulate.a > 0.99, "Active joystick drawn at full strength")
		check(drawn._layers.joy.region.has_point(high) and drawn._layers.joy_base.region.has_point(high), "Joystick layers follow the origin")

	# --- Simultaneous Rally --------------------------------------------------------
	_touch(controls, 2, controls._rally_center(), true)
	check(controls.rally_pressed and controls.movement_vector.x > 0.49, "Rally left and movement right at the same time")
	_touch(controls, 1, high + Vector2(33.0, 0.0), false)
	check(controls.movement_vector == Vector2.ZERO, "Release resets movement")
	check(not controls.movement_active() and controls._movement_center() == rest, "Release returns the origin to rest")
	check(controls.rally_pressed, "Releasing movement keeps Rally")
	_touch(controls, 2, controls._rally_center(), false)
	check(not controls.rally_pressed, "Rally releases independently")

	# Rally first, then movement (second thumb), then release in reverse.
	_touch(controls, 3, controls._rally_center() + Vector2(20.0, -30.0), true)
	_touch(controls, 4, Vector2(size.x * 0.62, size.y * 0.75), true)
	check(controls.rally_pressed and controls.movement_active() and controls.movement_pointer == 4, "Movement starts while Rally is held")
	_touch(controls, 3, Vector2.ZERO, false)
	_touch(controls, 4, Vector2.ZERO, false)

	# --- Desktop: mouse pointer -2 steers, a touch holds Rally ----------------------
	_mouse(controls, high, true)
	check(controls.movement_pointer == -2 and controls._movement_center() == high, "Mouse press starts the joystick at the cursor")
	var motion := InputEventMouseMotion.new()
	motion.position = high + Vector2(-66.0, 0.0)
	controls._input(motion)
	_touch(controls, 0, controls._rally_center(), true)
	check(controls.movement_vector.distance_to(Vector2(-1.0, 0.0)) < 0.01 and controls.rally_pressed, "Mouse movement and touch Rally together")
	_mouse(controls, high, false)
	check(controls.movement_vector == Vector2.ZERO and not controls.movement_active(), "Mouse release resets movement")
	_touch(controls, 0, Vector2.ZERO, false)

	# --- Old fixed spot still works --------------------------------------------------
	_touch(controls, 5, rest, true)
	check(controls.movement_active() and controls._movement_center() == rest, "Touch at the rest spot starts at rest")
	_touch(controls, 5, rest, false)

	# --- Clamped at the screen edge -------------------------------------------------
	_touch(controls, 6, size - Vector2(8.0, 8.0), true)
	var origin: Vector2 = controls._movement_center()
	var r: float = controls.MOVE_FRAME_R
	check(Rect2(Vector2.ONE * r, size - Vector2.ONE * r * 2.0).grow(0.01).has_point(origin), "Origin clamped so the frame stays on screen")
	check(origin.is_equal_approx(size - Vector2.ONE * r), "Corner touch clamps to the corner-most origin")
	check(controls.movement_vector.x > 0.0 and controls.movement_vector.y > 0.0, "Clamped origin still steers toward the thumb")
	_touch(controls, 6, Vector2.ZERO, false)

	# --- Touches that must not start the joystick ------------------------------------
	_touch(controls, 7, controls._pause_rect().get_center(), true)
	check(pauses == 1, "Pause button still pauses")
	check(not controls.movement_active(), "Pause button does not start the joystick")
	_touch(controls, 7, Vector2.ZERO, false)
	_touch(controls, 8, Vector2(size.x * 0.85, size.y * 0.2), true)
	check(not controls.movement_active(), "Top HUD (right) does not start the joystick")
	_touch(controls, 8, Vector2.ZERO, false)
	_touch(controls, 9, Vector2(size.x * 0.35, size.y * 0.6), true)
	check(not controls.movement_active() and not controls.rally_pressed, "Left half (off Rally) starts nothing")
	_touch(controls, 9, Vector2.ZERO, false)
	if controls.minimap_enabled:
		controls._map_toggled_at = -100000
		_touch(controls, 10, controls._minimap_rect().get_center(), true)
		check(controls.map_open and not controls.movement_active(), "Minimap tap opens the map, no joystick")
		_touch(controls, 10, Vector2.ZERO, false)
		var on_map := Vector2(size.x * 0.75, controls._bigmap_rect().get_center().y)
		_touch(controls, 11, on_map, true)
		check(not controls.movement_active(), "Open big map panel does not start the joystick")
		_touch(controls, 11, Vector2.ZERO, false)
		_touch(controls, 12, rest, true)
		check(controls.movement_active() and controls.map_open, "Steering below the big map still works")
		_touch(controls, 12, Vector2.ZERO, false)
		controls._map_toggled_at = -100000
		controls.set_map_open(false)

	# --- clear_pointers (focus out) ---------------------------------------------------
	_touch(controls, 13, high, true)
	_drag(controls, 13, high + Vector2(40.0, 40.0))
	controls.clear_pointers()
	check(controls.movement_vector == Vector2.ZERO and not controls.movement_active() and controls._movement_center() == rest, "clear_pointers resets the joystick")
	await _frames(1)
	if drawn != null:
		check(drawn._layers.joy.modulate.a < 0.9, "Joystick dimmed again after reset")

	if failures > 0:
		print("JOYSTICK FAILED: %d" % failures)
		quit(1)
		return
	print("PASS: floating joystick origin, relative steering, release/clear reset, simultaneous Rally (touch + mouse), pause/minimap/top HUD/big map excluded, edge clamp")
	quit(0)


func _touch(controls: Variant, index: int, at: Vector2, pressed: bool) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = index
	touch.position = at
	touch.pressed = pressed
	controls._input(touch)


func _drag(controls: Variant, index: int, at: Vector2) -> void:
	var drag := InputEventScreenDrag.new()
	drag.index = index
	drag.position = at
	controls._input(drag)


func _mouse(controls: Variant, at: Vector2, pressed: bool) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = at
	click.pressed = pressed
	controls._input(click)


func _frames(count: int) -> void:
	for index in count:
		await process_frame
