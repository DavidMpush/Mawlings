extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var swarm: Variant = scene.get_node("Swarm")
	var world: Variant = scene.get_node("HuntWorld")
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)
	var model: Node = swarm.units[0].get_node("Game model")
	var pieces := model.find_children("*", "MeshInstance3D", true, false)
	if pieces.size() != 1:
		push_error("Gameplay Mawling must share one mesh and draw call")
		quit(1)
		return
	var mesh: Mesh = pieces[0].mesh
	var triangles: int = mesh.surface_get_array_index_len(0) / 3
	if triangles > 5000 or triangles < 1000:
		push_error("Gameplay mesh exceeds detail budget or is missing")
		quit(1)
		return
	world.model.population = 250
	swarm.set_population(250)
	if swarm.units.size() != swarm.VISUAL_LIMIT or swarm.population != 250:
		push_error("Logical population and visible model budget diverged")
		quit(1)
		return
	print("PASS model budget: %d triangles, one mesh each, %d visible at 250 population" % [triangles, swarm.units.size()])
	quit(0)
