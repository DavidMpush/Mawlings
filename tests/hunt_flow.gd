extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var swarm: Variant = scene.get_node("Swarm")
	var world: Variant = scene.get_node("HuntWorld")
	# Stage 09 lone start: the flow check uses a 25-strong swarm (one Mawling
	# needs far longer to bite a Nibbler down).
	world.model.population = 25
	swarm.set_population(25, false)
	var target: Variant = world.prey[0]
	for tick in 70:
		if not is_instance_valid(target) or not world.prey.has(target):
			break
		swarm.position = target.position
		await create_timer(0.05).timeout
	# Etappe 16: the kill bursts into loot crystals; leave at once so they stay.
	var kill_spot: Vector3 = swarm.position
	swarm.position = Vector3(20, 0, 20)
	if world.loot.count() < 2:
		_fail("Hunting must burst into crystals (%d)" % world.loot.count())
		return
	await create_timer(0.8).timeout
	var lying: int = world.loot.lying_count()
	var value: float = world.loot.total(0)
	await create_timer(0.5).timeout
	if lying == 0 or world.loot.lying_count() != lying or not is_equal_approx(world.loot.total(0), value):
		_fail("Crystals changed while the swarm was away (%d / %d)" % [lying, world.loot.lying_count()])
		return
	swarm.position = kill_spot
	for tick in 60:
		if world.loot.count() == 0:
			break
		await create_timer(0.05).timeout
	if world.loot.count() != 0 or world.model.population <= 25:
		_fail("Returning must pull in every crystal and grow the swarm")
		return
	print("PASS: hunt, crystals burst out and stay, return, magnet, growth")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
