extends SceneTree

# Review frames for seeded maps: per seed the start and a far position from the
# real game camera, plus one wide overview (camera offset x4, larger chunk ring).
# Run WITHOUT --headless: preview_seed_<seed>_start/far/overview.png

const SEEDS := [4242, 777, 90210]
const FAR := Vector3(70.0, 0.0, -60.0)


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var world: Variant = scene.get_node("HuntWorld")
	var swarm: Variant = scene.get_node("Swarm")
	var arena: Variant = scene.get_node("Arena")
	var camera: Camera3D = scene.get_node("Camera3D")
	var controls: Variant = scene.get_node("HUD/Controls")
	# Losing window focus must not pause the review.
	for connection in controls.pause_requested.get_connections():
		controls.pause_requested.disconnect(connection.callable)
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)
	for prey in world.prey:
		prey.visible = false
	for seed_value in SEEDS:
		arena.set_seed(seed_value)
		for pair in [["start", Vector3.ZERO], ["far", FAR]]:
			var spot: Vector3 = arena.safe_spawn(pair[1], 1.5)
			swarm.position = spot
			arena.view_radius = arena.VISIBLE_RADIUS
			arena.sync(spot)
			scene._snap_camera()
			await _settle()
			root.get_texture().get_image().save_png("res://preview_seed_%d_%s.png" % [seed_value, pair[0]])
		# Wide overview around the start: more chunks, camera pulled far back.
		swarm.position = Vector3.ZERO
		arena.view_radius = 4
		arena.sync(Vector3.ZERO)
		camera.position = scene.CAMERA_OFFSET * 4.0
		camera.look_at(Vector3.ZERO, Vector3.UP)
		await _settle()
		root.get_texture().get_image().save_png("res://preview_seed_%d_overview.png" % seed_value)
		arena.view_radius = arena.VISIBLE_RADIUS
		print("Seed %d captured" % seed_value)
	quit()


func _settle() -> void:
	for index in 3:
		await process_frame
	await RenderingServer.frame_post_draw
