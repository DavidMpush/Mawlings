extends SceneTree

# Hunter Beetle review: side view (red marker = local +Z, the facing direction)
# and an in-game frame with two hunters closing in. Needs a window.


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	var stage := Node3D.new()
	root.add_child(stage)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	stage.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("c9c2b4")
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.6
	stage.add_child(environment)
	var hunter: Node3D = load("res://scripts/hunter.gd").new()
	stage.add_child(hunter)
	var marker := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.15
	ball.height = 0.3
	marker.mesh = ball
	var red := StandardMaterial3D.new()
	red.albedo_color = Color.RED
	marker.material_override = red
	marker.position = Vector3(0, 0.3, 1.6)
	stage.add_child(marker)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.look_at_from_position(Vector3(6, 2.5, 0), Vector3(0, 0.5, 0))
	camera.current = true
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview_hunter_beetle_side.png")
	camera.look_at_from_position(Vector3(0, 9, 5.5), Vector3(0, 0.3, 0))
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview_hunter_beetle_top.png")
	stage.free()

	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	for i in 30:
		await process_frame
	var world: Variant = scene.get_node("HuntWorld")
	var swarm: Variant = scene.get_node("Swarm")
	world.hunter_clock = 1e9
	world.boss_clock = 1e9
	world.model.population = 30
	swarm.set_population(30, false)
	for i in 30:
		await process_frame
	var first: Variant = world._spawn_hunter(swarm.position + Vector3(-5.0, 0, -3.0))
	var second: Variant = world._spawn_hunter(swarm.position + Vector3(4.5, 0, -4.5))
	second.make_elite(3.0)
	first.state = first.State.CHASE
	second.state = second.State.CHASE
	for i in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview_hunter_beetle_game.png")
	quit()
