extends SceneTree
## Etappe 26: pause panel with the three volume sliders, and the "WELT 2" chip
## under the clock after a migration. Run WITHOUT --headless, with
## --audio-driver Dummy --screen 1. Writes previews/preview_pause_volume.png and
## previews/preview_world_chip.png (900 x 1600).

func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(900, 1600)
	DisplayServer.window_set_size(Vector2i(900, 1600))
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var controls: Control = scene.get_node("HUD/Controls")
	var world: Node = scene.get_node("HuntWorld")
	# Background capture windows lose focus; the auto-pause must not end up in the frames.
	if controls.pause_requested.is_connected(world.toggle_pause):
		controls.pause_requested.disconnect(world.toggle_pause)
	await _frames(20)
	if world.paused:
		world.toggle_pause()
	world.model.population = 60
	world.model.elapsed = 312.0
	world.model.world_start = 190.0
	world.arrivals = 1
	await _frames(12)
	await _shot("res://previews/preview_world_chip.png")
	controls.volumes = {"volume_master": 1.0, "volume_music": 0.45, "volume_sfx": 0.0}
	if not world.paused:
		world.toggle_pause()
	await _frames(40)
	await _shot("res://previews/preview_pause_volume.png")
	print("Saved pause volume previews")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("Saved ", path)
