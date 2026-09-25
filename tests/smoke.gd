extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var swarm: Variant = scene.get_node("Swarm")
	if swarm.units.size() != 25:
		_fail("Expected 25 Mawlings")
		return
	var origin: Vector3 = swarm.position
	Input.action_press("move_right")
	await create_timer(0.15).timeout
	Input.action_release("move_right")
	if swarm.position.x <= origin.x + 0.1:
		_fail("Keyboard movement did not move the swarm")
		return
	var controls: Variant = scene.get_node("HUD/Controls")
	controls.rally_pressed = true
	await create_timer(0.5).timeout
	if not swarm.rally_pressed:
		_fail("Rally input did not reach the swarm")
		return
	controls.rally_pressed = false
	var move_center: Vector2 = Vector2(controls.size.x - 125.0, controls.size.y - 145.0)
	var rally_center: Vector2 = Vector2(125.0, controls.size.y - 145.0)
	var move_touch := InputEventScreenTouch.new()
	move_touch.index = 1
	move_touch.position = move_center
	move_touch.pressed = true
	controls._input(move_touch)
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = move_center + Vector2(66.0, 0.0)
	controls._input(drag)
	var rally_touch := InputEventScreenTouch.new()
	rally_touch.index = 2
	rally_touch.position = rally_center
	rally_touch.pressed = true
	controls._input(rally_touch)
	if controls.movement_vector.x < 0.9 or not controls.rally_pressed:
		_fail("Right movement and left Rally must work at the same time")
		return
	move_touch.pressed = false
	controls._input(move_touch)
	if controls.movement_vector != Vector2.ZERO or not controls.rally_pressed:
		_fail("Releasing movement must preserve the other touch")
		return
	rally_touch.pressed = false
	controls._input(rally_touch)
	if controls.rally_pressed:
		_fail("Rally must release independently")
		return
	print("PASS: scene, movement, Rally, simultaneous right/left touch")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
