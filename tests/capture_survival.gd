extends SceneTree


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var world: Variant = scene.get_node("HuntWorld")
	var swarm: Variant = scene.get_node("Swarm")
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)
	world.model.elapsed = 60.0
	world.drop_loot(Vector3(-3, 0, 1), 12.0)
	var hunter: Variant = world._spawn_hunter(Vector3(2.5, 0, 0))
	hunter.step(1.1, Vector3.ZERO, world.model.pressure())
	hunter.step(0.01, Vector3.ZERO, world.model.pressure())
	world.paused = false
	world._update_hud("RAUS AUS DEM ROTEN RING!")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/preview_survival.png")
	for tick in 1200:
		world.step(1.0 / 60.0)
		if world.model.extinct:
			break
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/preview_extinction.png")
	print("Saved survival warning and extinction previews")
	quit()
