extends SceneTree
## Etappe 30: the sealed gate beside the world's boss arena, and the same gate
## unsealing after the endboss. Run WITHOUT --headless, with --audio-driver Dummy
## --screen 1. Writes previews/preview_gate_sealed.png and preview_gate_open.png.

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
	var arena: Node3D = scene.get_node("Arena")
	if controls.pause_requested.is_connected(world.toggle_pause):
		controls.pause_requested.disconnect(world.toggle_pause)
	await _frames(10)
	world.config = {"strain_id": "glutmaw", "seed": 4242}
	arena.set_seed(4242)
	world.reset_run()
	world.config = {}
	if world.paused:
		world.toggle_pause()
	for clock in ["hunter_clock", "skitter_clock", "leaper_clock", "elite_clock", "nest_clock", "boss_clock"]:
		world.set(clock, 1000000.0)
	world.flood_start = 1000000.0
	world.surge_next = 1000000.0
	world.model.leader_invulnerable = 1.0e9
	world.model.population = 60
	swarm.set_population(60, false)
	var gate: Node3D = world.gate
	if gate == null:
		print("No gate on this map")
		quit()
		return
	swarm.position = arena.safe_spawn(gate.position + Vector3(0, 0, 7), 1.0)
	arena.sync(swarm.position)
	await _frames(90)
	await _shot("res://previews/preview_gate_sealed.png")
	world.apex_state = 3
	world.open_portal(gate.position)
	await _frames(100)
	await _shot("res://previews/preview_gate_open.png")
	arena.set_seed(0)
	print("Saved gate previews")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("Saved ", path)
