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
	print("PASS: scene, 25 Mawlings, keyboard movement, Rally")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
