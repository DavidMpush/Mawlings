extends SceneTree

# Review frames for stage 08 "Die Flut" (run WITHOUT --headless, e.g.
#   Godot_console.exe --screen 1 --audio-driver Dummy --path . --script res://tests/capture_flood.gd):
# announcement banner with countdown, early flood (first rings arriving),
# late flood (stage 5, full horde) and a Nibbler snap telegraph.

var scene: Node
var world: Variant
var swarm: Variant
var controls: Variant


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	controls = scene.get_node("HUD/Controls")
	# Background capture windows lose focus; the auto-pause must not end up in the frames.
	controls.pause_requested.disconnect(world.toggle_pause)
	# Let the HUD fade in first.
	await create_timer(1.2).timeout
	_quiet()
	world.model.population = 120
	swarm.set_population(120, false)
	# 1: announcement, 7 s before the flood, a hunter for context.
	world.model.elapsed = world.flood_start - 7.2
	world._spawn_hunter(swarm.position + Vector3(4.5, 0, -3.0)).state = 1
	await _wait(0.5, 120)
	await _save("preview_flood_warning.png")
	# 2: early flood: first rings closing in.
	world.model.elapsed = world.flood_start - 0.1
	await _wait(3.2, 120)
	await _save("preview_flood_early.png")
	# 3: late flood, stage 5, full horde around a big swarm.
	world.model.population = 200
	swarm.set_population(200, false)
	world.model.elapsed = world.flood_start + 165.0
	var horde: Variant = world.horde
	if horde != null:
		horde.spawn_ring(swarm.position, 160 - horde.count(), 9.0, world.flood_stats())
	await _wait(1.4, 200)
	await _save("preview_flood_late.png")
	# 4: Nibbler snap, no flood.
	world.flood_start = 1.0e9
	world.flood_state = 0
	if horde != null:
		horde.clear()
	for enemy in world.hunters:
		enemy.queue_free()
	world.hunters.clear()
	world.model.population = 30
	swarm.set_population(30, false)
	world.model.elapsed = 40.0
	await _wait(0.8, 30)
	# At the swarm's edge and just bitten: it snaps back; half the circle is visible.
	world._spawn_prey(swarm.position + Vector3(2.3, 0, -0.6))
	await process_frame
	var nibbler: Variant = world.prey[-1]
	nibbler.snap_cooldown = 0.0
	nibbler.health -= 1.0
	await _wait(0.3, 30)
	await _save("preview_flood_nibbler.png")
	print("Saved flood review frames")
	quit()


func _wait(seconds: float, population: int) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame
		_keep_alive(population)


func _keep_alive(population: int) -> void:
	world.evolution.offers.clear()
	if world.model.extinct or world.model.population < population / 2:
		world.model.extinct = false
		world.model.population = population
		swarm.set_population(population, false)


func _quiet() -> void:
	for target in world.prey:
		target.queue_free()
	world.prey.clear()
	world.spawn_clock = -1000000.0
	world.hunter_clock = 1000000.0
	world.skitter_clock = 1000000.0
	world.leaper_clock = 1000000.0
	world.boss_clock = 1000000.0
	world.elite_clock = 1000000.0
	world.nest_clock = 1000000.0


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/" + file_name)
