extends SceneTree


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var result := image.save_png("res://preview.png")
	if result != OK:
		push_error("Preview capture failed: " + str(result))
		quit(1)
		return
	print("Saved preview.png: ", image.get_width(), "x", image.get_height())
	quit(0)
