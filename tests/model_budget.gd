extends SceneTree

# Budget of the gameplay Mawling: one reduced mesh, drawn for every visible unit
# by a single MultiMeshInstance3D (one draw call for up to VISUAL_LIMIT animals).

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
	var sample: Node = load("res://assets/gameplay/characters/Mawling_game.glb").instantiate()
	var pieces := sample.find_children("*", "MeshInstance3D", true, false)
	sample.free()
	if pieces.size() != 1:
		push_error("Gameplay Mawling must share one mesh and draw call")
		quit(1)
		return
	var bodies: MultiMeshInstance3D = swarm.bodies
	var multimesh: MultiMesh = bodies.multimesh if bodies != null else null
	if multimesh == null or multimesh.mesh != swarm.mawling_mesh or multimesh.mesh == null:
		push_error("Visible Mawlings must be drawn by one MultiMesh of the gameplay mesh")
		quit(1)
		return
	if not multimesh.use_custom_data or multimesh.instance_count != swarm.VISUAL_LIMIT:
		push_error("Swarm MultiMesh needs custom data and VISUAL_LIMIT instances")
		quit(1)
		return
	if not swarm.units[0].find_children("*", "GeometryInstance3D", true, false).is_empty():
		push_error("Logical units must not carry their own meshes")
		quit(1)
		return
	var mesh: Mesh = multimesh.mesh
	var triangles := 0
	for surface in mesh.get_surface_count():
		triangles += mesh.surface_get_array_index_len(surface) / 3
	if mesh.get_surface_count() != 1 or triangles > 5000 or triangles < 1000:
		push_error("Gameplay mesh exceeds detail budget or is missing")
		quit(1)
		return
	world.model.population = 250
	swarm.set_population(250)
	if swarm.units.size() != swarm.VISUAL_LIMIT or swarm.population != 250 or multimesh.visible_instance_count != swarm.VISUAL_LIMIT:
		push_error("Logical population and visible model budget diverged")
		quit(1)
		return
	var swarm_geometry: Array = swarm.find_children("*", "GeometryInstance3D", true, false)
	if swarm_geometry.size() > 6:
		push_error("Swarm should draw with a handful of instances, found %d" % swarm_geometry.size())
		quit(1)
		return
	print("PASS model budget: %d triangles, one MultiMesh draw for %d visible at 250 population (%d triangles total)" % [triangles, multimesh.visible_instance_count, triangles * multimesh.visible_instance_count])
	quit(0)
