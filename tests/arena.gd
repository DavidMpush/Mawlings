extends SceneTree

var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var arena: Variant = scene.get_node("Arena")
	var world: Variant = scene.get_node("HuntWorld")
	var swarm: Variant = scene.get_node("Swarm")
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)
	var key := Vector2i(2, -3)
	var centers: Array[Vector3] = arena.obstacle_centers(key)
	check(arena.chunks.size() == 9, "Bounded initial visual chunks")
	var rock: Vector3 = arena.obstacle_centers(Vector2i.ZERO)[0]
	var start := rock + Vector3(4, 0, 0)
	var stopped: Vector3 = arena.resolve_motion(start, Vector3(-3, 0, 0), 0.75)
	check(stopped.distance_to(rock) >= arena.OBSTACLE_RADIUS + 0.75 - 0.001, "Stone blocks player")
	var slide: Vector3 = arena.resolve_motion(start + Vector3(0, 0, 1), Vector3(-3, 0, 2), 0.75)
	check(slide.z > start.z + 1, "Can slide past stone")
	var safe: Vector3 = arena.safe_spawn(rock, 0.9)
	check(safe.distance_to(rock) >= arena.OBSTACLE_RADIUS + 0.9 - 0.001, "Spawn pushed outside stone")
	world._create_corpse(Vector3(0, 0, 0), 12)
	var corpse_id: int = world.model.corpses[0].id
	for location in [Vector3(57, 0, -85), Vector3(-88, 0, 56), Vector3.ZERO]:
		swarm.position = location
		arena.sync(swarm.position)
		check(arena.chunks.size() == 9, "Visual chunk budget across endless map")
	check(arena.obstacle_centers(key) == centers, "Layout stable after travel")
	check(world.model.remaining_biomass(corpse_id) == 12, "Travel does not remove resources")
	var prey: Node3D = world.prey[0]
	prey.position = rock + Vector3(3.5, 0, 0)
	swarm.position = rock + Vector3(5, 0, 0)
	prey.call("step", 1.0, swarm.position)
	check(prey.position.distance_to(rock) >= arena.OBSTACLE_RADIUS + 0.55 - 0.001, "Prey obeys stone footprint")
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
	else:
		print("PASS arena: bounded chunks, deterministic travel, slide, safe spawn, persistent corpses, prey collision")
		quit(0)
