extends SceneTree
## Etappe 27: a Hordenwelle in world 2 - the warning (hint, context line, danger
## rings towards the incoming side) and the brood a few seconds later; the XP bar
## (16 px, above the pill row) is filled to ~60 %. Run WITHOUT --headless, with
## --audio-driver Dummy --screen 1. Writes previews/preview_surge_warning.png and
## previews/preview_surge_wave.png (900 x 1600).

func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(900, 1600)
	DisplayServer.window_set_size(Vector2i(900, 1600))
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var controls: Control = scene.get_node("HUD/Controls")
	var world: Node = scene.get_node("HuntWorld")
	var swarm: Node3D = scene.get_node("Swarm")
	# Background capture windows lose focus; the auto-pause must not end up in the frames.
	if controls.pause_requested.is_connected(world.toggle_pause):
		controls.pause_requested.disconnect(world.toggle_pause)
	await _frames(20)
	if world.paused:
		world.toggle_pause()
	world.model.population = 120
	swarm.set_population(120, false)
	world.model.elapsed = 330.0
	world.model.world_start = 290.0
	world.arrivals = 1
	world.apex_state = 4
	world.hunter_clock = 1000000.0
	world.skitter_clock = 1000000.0
	world.leaper_clock = 1000000.0
	world.boss_clock = 1000000.0
	world.elite_clock = 1000000.0
	world.nest_clock = 1000000.0
	world.model.leader_invulnerable = 1000000.0
	for target in world.prey:
		target.queue_free()
	world.prey.clear()
	world.spawn_clock = -1000000.0
	world.surge_next = 100000.0
	# Let the start banner fade before the warning.
	await _frames(260)
	world.evolution.offers.clear()
	world.evolution.dna = int(float(world.evolution.threshold()) * 0.6)
	world.surge_next = world.world_time() + 3.2
	await _frames(40)
	await _shot("res://previews/preview_surge_warning.png")
	world.evolution.offers.clear()
	await _frames(170)
	world.evolution.offers.clear()
	await _shot("res://previews/preview_surge_wave.png")
	print("Saved surge previews (%d brood)" % world.horde.count())
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("Saved ", path)
