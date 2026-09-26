extends SceneTree
func _initialize() -> void:
	call_deferred("_capture")
func _capture() -> void:
	root.size = Vector2i(540, 960)
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
