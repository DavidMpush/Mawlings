extends SceneTree


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var swarm: Variant = scene.get_node("Swarm")
	var world: Variant = scene.get_node("HuntWorld")
	var target: Variant = world.prey[0]
	target.health = 0.01
	swarm.position = target.position
	await process_frame
	swarm.position += Vector3(3.0, 0.0, 0.0)
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var result := image.save_png("res://preview_hunt.png")
	if result != OK:
		push_error("Preview capture failed: " + str(result))
		quit(1)
		return
	print("Saved preview_hunt.png")
	quit(0)
