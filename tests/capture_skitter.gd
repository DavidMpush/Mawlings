extends SceneTree
func _initialize() -> void:
	call_deferred("_capture")
func _capture() -> void:
	root.size = Vector2i(540, 960)
	await _side_view()
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var world: Variant = scene.get_node("HuntWorld")
	scene.set_process(false)
	world.set_process(false)
	scene.get_node("Swarm").set_process(false)
	world.model.elapsed = 60
	var skitter: Variant = world._spawn_skitter(Vector3(-4, 0, -1))
	skitter.state = skitter.State.CHASE
	skitter.step(0.01, Vector3.ZERO, world.model.pressure())
	world._update_hud("SPRINT! SEITLICH AUSWEICHEN")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview_skitter.png")
	print("Saved Skitter warning preview")
	quit()

# Model review: side view (red marker = local +Z, the facing direction) and top view.
func _side_view() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	stage.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("c9c2b4")
	stage.add_child(environment)
	var holder := Node3D.new()
	stage.add_child(holder)
	var skitter: Node3D = load("res://scripts/skitter.gd").new()
	holder.add_child(skitter)
	var marker := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.12
	ball.height = 0.24
	marker.mesh = ball
	var red := StandardMaterial3D.new()
	red.albedo_color = Color.RED
	marker.material_override = red
	marker.position = Vector3(0, 0.2, 1.3)
	stage.add_child(marker)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.look_at_from_position(Vector3(4.5, 1.8, 0), Vector3(0, 0.3, 0))
	camera.current = true
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview_skitter_side.png")
	camera.look_at_from_position(Vector3(0, 7, 4), Vector3(0, 0.2, 0))
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview_skitter_top.png")
	skitter.cleanup()
	stage.free()
