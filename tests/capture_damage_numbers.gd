extends SceneTree
## Etappe 37: damage numbers in a real fight (80 Mawlings against hunters, a
## skitter and a Bog King). Run WITHOUT --headless, with --audio-driver Dummy
## --screen 1. Writes previews/preview_damage_numbers.png (900 x 1600).

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
	if controls.pause_requested.is_connected(world.toggle_pause):
		controls.pause_requested.disconnect(world.toggle_pause)
	await _frames(20)
	if world.paused:
		world.toggle_pause()
	world.model.population = 80
	swarm.set_population(80, false)
	world.model.elapsed = 150.0
	world.model.leader_invulnerable = 1.0e9
	world.surge_next = 1.0e9
	world.flood_start = 1.0e9
	world.apex_state = 4
	for offset in [Vector3(2.5, 0, -2), Vector3(-2.5, 0, -1.5), Vector3(1, 0, 2.5), Vector3(-3, 0, 2)]:
		var hunter: Node3D = world._spawn_hunter(swarm.position + offset)
		hunter.set("state", 1)
	world._spawn_boss(swarm.position + Vector3(0, 0, -4.5))
	for index in 50:
		await process_frame
		if world.choosing():
			world.evolution.offers.clear()
			world.evolution.chest_offers.clear()
	await _shot("res://previews/preview_damage_numbers.png")
	print("Saved damage numbers preview")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
