extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.size = Vector2i(540, 960)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var swarm: Node3D = scene.get_node("Swarm")
	var world: Variant = scene.get_node("HuntWorld")
	var camera: Camera3D = scene.get_node("Camera3D")
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)
	swarm.position = Vector3(10, 0, 11)
	scene.get_node("Arena").sync(swarm.position)
	camera.position = swarm.position + Vector3(0, 23, 15)
	camera.look_at(swarm.position, Vector3.UP)
	world._spawn_prey(swarm.position + Vector3(-4, 0, -2))
	world._create_corpse(swarm.position + Vector3(2.5, 0, -3), 12)
	world._update_hud("Offene Arena · breite Wege")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview_arena.png")
	print("Saved arena preview")
	quit()
