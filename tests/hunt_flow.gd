extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var swarm: Variant = scene.get_node("Swarm")
	var world: Variant = scene.get_node("HuntWorld")
	var target: Variant = world.prey[0]
	for tick in 70:
		if not is_instance_valid(target) or not world.prey.has(target):
			break
		swarm.position = target.position
		await create_timer(0.05).timeout
	if world.model.corpses.size() != 1:
		_fail("Hunting must leave one corpse")
		return
	var corpse_position: Vector3 = world.model.corpses[0].position
	swarm.position = Vector3(20, 0, 20)
	await create_timer(0.2).timeout
	var remainder: float = world.model.corpses[0].remaining
	await create_timer(0.3).timeout
	if not is_equal_approx(world.model.corpses[0].remaining, remainder):
		_fail("Biomass changed while the swarm was away")
		return
	swarm.position = corpse_position
	for tick in 100:
		if world.model.corpses.is_empty():
			break
		await create_timer(0.05).timeout
	if not world.model.corpses.is_empty() or world.model.population <= 25:
		_fail("Returning must finish harvest and grow the swarm")
		return
	print("PASS: hunt, persistent corpse, return, harvest, growth")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
