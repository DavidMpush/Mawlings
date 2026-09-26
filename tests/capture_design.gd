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
	var hud_node: Node = scene.get_node("HUD/Controls")
	for connection in hud_node.pause_requested.get_connections():
		hud_node.pause_requested.disconnect(connection.callable)
	world._update_hud("JAGE · WACHSE · ÜBERLEBE")
	# UI components animate in; give them time before each frame.
	await create_timer(1.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview_design_active.png")
	world.model.population = 250
	swarm.set_population(250)
	for frame in 120:
		swarm._process(0.05)
	world._update_hud("SCHWARM VOLL · BIOMASSE BLEIBT LIEGEN")
	# UI components animate in; give them time before each frame.
	await create_timer(1.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview_design_250.png")
	# Busiest HUD state: boss bar, threats, corpse, biomass, hit flash, pointer, pressed input.
	var hud: Variant = scene.get_node("HUD/Controls")
	hud.elapsed = 347.0
	hud.pressure = 24.0
	hud.hunters = 3
	hud.skitters = 2
	hud.boss_health = 620.0
	hud.boss_max_health = 1000.0
	hud.boss_vulnerable = false
	hud.boss_pointer = Vector2(hud.size.x - 56, 520)
	hud.nearest_corpse = "Kadaver: 12m · links oben"
	hud.biomass_bank = 1.4
	hud.hit_feedback = 1.0
	hud.last_loss = 7
	hud.rally_pressed = true
	hud.movement_vector = Vector2(0.7, -0.7)
	hud.hint = ""
	hud.alpha_cores = 1
	world.evolution.ranks = {"saeurespucker": 2, "sporenwolke": 1, "jaws": 1}
	hud.queue_redraw()
	# UI components animate in; give them time before each frame.
	await create_timer(1.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview_design_busy.png")
	hud.rally_pressed = false
	hud.movement_vector = Vector2.ZERO
	world.evolution.offers = [world.evolution.ATTACKS[2], world.evolution.TRAITS[4], world.evolution.ATTACKS[0]]
	world.evolution.rerolls = 1
	world.evolution.skips = 1
	world.evolution.banishes = 1
	world._update_hud("")
	# UI components animate in; give them time before each frame.
	await create_timer(1.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview_design_cards.png")
	world.evolution.offers.clear()
	world.model.apply_loss(250)
	swarm.set_population(0)
	world._update_hud("")
	# UI components animate in; give them time before each frame.
	await create_timer(1.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview_design_result.png")
	print("Saved four design review frames")
	quit()
