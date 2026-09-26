extends SceneTree
func _initialize() -> void:
	call_deferred("_capture")
func _capture() -> void:
	root.size = Vector2i(540, 960)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var swarm: Node3D = scene.get_node("Swarm")
	scene.set_process(false)
	scene.get_node("HuntWorld").set_process(false)
	swarm.set_process(false)
	swarm.set_population(0)
	var imported: PackedScene = load("res://assets/Mawling_game.glb")
	for index in 16:
		var unit: Node3D = imported.instantiate()
		unit.position = Vector3((index % 4 - 1.5) * 0.9, 0, (index / 4 - 1.5) * 1.1)
		unit.scale = Vector3.ONE * 1.2
		swarm.add_child(unit)
		for mesh in unit.find_children("*", "MeshInstance3D", true, false):
			var material := StandardMaterial3D.new()
			material.vertex_color_use_as_albedo = true
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.roughness = 0.9
			mesh.material_override = material
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview_model_game.png")
	print("Saved model preview")
	quit()
