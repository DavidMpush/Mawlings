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
	world.paused = false
	world.evolution.rng.seed = 19
	world._kill_prey(world.prey[0])
	world._kill_prey(world.prey[0])
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview_evolution.png")
	world.choose_mutation(0)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview_evolution_play.png")
	for mutation in world.evolution.TRAITS:
		world.evolution.ranks[mutation[0]] = 3
	world.evolution.level = 18
	world.toggle_pause()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview_evolution_summary.png")
	print("Saved evolution, gameplay and summary previews")
	quit()
