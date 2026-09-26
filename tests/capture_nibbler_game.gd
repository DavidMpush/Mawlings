extends SceneTree

# Nibbler review from the real game camera: idle, fleeing and bitten frames,
# each saved full size plus a 3x close-up crop around the Nibbler.
# Focus-loss auto-pause is disconnected so background windows do not freeze the frame.

var scene: Node
var world: Variant
var swarm: Variant
var camera: Camera3D


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	camera = root.get_camera_3d()
	var controls: Node = scene.get_node("HUD/Controls")
	for connection in controls.pause_requested.get_connections():
		controls.pause_requested.disconnect(connection.callable)
	await create_timer(0.3).timeout
	var target: Node3D = world.prey[0]
	# Idle: swarm out of reach, Nibbler wanders and looks around.
	swarm.position = target.position + Vector3(0.0, 0.0, 6.0)
	await create_timer(1.2).timeout
	await _save("preview_nibbler_idle", target)
	# Flee: swarm right behind it.
	swarm.position = target.position + Vector3(-2.0, 0.0, 1.0)
	await create_timer(0.45).timeout
	await _save("preview_nibbler_flee", target)
	# Bite: swarm on top, health drops.
	target.set("health", 7.0)
	swarm.position = target.position + Vector3(-0.6, 0.0, 0.3)
	await create_timer(0.35).timeout
	await _save("preview_nibbler_bite", target)
	print("Saved nibbler game frames")
	quit(0)


func _save(file_name: String, target: Node3D) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://" + file_name + ".png")
	if not is_instance_valid(target):
		return
	var spot := camera.unproject_position(target.global_position + Vector3(0, 0.5, 0)) * Vector2(image.get_size()) / root.get_visible_rect().size
	print(file_name, " spot ", spot, " image ", image.get_size(), " cam ", camera.get_path())
	var box := Rect2i(Vector2i(spot) - Vector2i(60, 60), Vector2i(120, 120))
	box = box.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if box.size.x < 10 or box.size.y < 10:
		return
	var crop := image.get_region(box)
	crop.resize(box.size.x * 3, box.size.y * 3, Image.INTERPOLATE_NEAREST)
	crop.save_png("res://" + file_name + "_zoom.png")
