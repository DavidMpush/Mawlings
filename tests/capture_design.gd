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
	world._update_hud("JAGE · WACHSE · ÜBERLEBE")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview_design_active.png")
	world.model.population = 250
	swarm.set_population(250)
	for frame in 120:
		swarm._process(0.05)
	world._update_hud("SCHWARM VOLL · BIOMASSE BLEIBT LIEGEN")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview_design_250.png")
	world.evolution.offers = [world.evolution.TRAITS[2], world.evolution.TRAITS[4], world.evolution.TRAITS[5]]
	world._update_hud("")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview_design_cards.png")
	world.evolution.offers.clear()
	world.model.apply_loss(250)
	swarm.set_population(0)
	world._update_hud("")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview_design_result.png")
	print("Saved four design review frames")
	quit()
