extends SceneTree

const TUNING = preload("res://scripts/tuning.gd")


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
	world.model.elapsed = 60
	var leaper: Variant = world._spawn_leaper(swarm.position + Vector3(-4.5, 0, -6.5))
	# Let the spawn ring fade before the review frames.
	await create_timer(0.8).timeout
	leaper.state = leaper.State.STALK
	leaper.lurk = 0.0
	leaper.step(0.01, swarm.position, world.model.pressure())
	# ~65 % through the warning: crouched, reticle closing, arc dots marching.
	while leaper.remaining > TUNING.LEAPER_WARNING_SECONDS * 0.35:
		leaper.step(1.0 / 60.0, swarm.position, world.model.pressure())
	world._update_hud("RAUS AUS DER SPRUNGZONE!")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/preview_leaper_warning.png")
	# Swarm sidesteps; capture the leaper at the top of its arc.
	var aside: Vector3 = swarm.position + Vector3(3.5, 0, 0)
	swarm.position = aside
	while leaper.state == leaper.State.WARNING:
		leaper.step(1.0 / 60.0, aside, world.model.pressure())
	while leaper.remaining > TUNING.LEAPER_FLIGHT_SECONDS * 0.5:
		leaper.step(1.0 / 60.0, aside, world.model.pressure())
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/preview_leaper_jump.png")
	# Landing: shock ring and exhausted pose.
	while leaper.state == leaper.State.LEAP:
		leaper.step(1.0 / 60.0, aside, world.model.pressure())
	for i in range(8):
		leaper.step(1.0 / 60.0, aside, world.model.pressure())
	world._update_hud("Leaper erschöpft · jetzt angreifen!")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/preview_leaper_landing.png")
	print("Saved Mire Leaper review frames")
	quit()
