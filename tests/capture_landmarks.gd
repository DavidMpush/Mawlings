extends SceneTree

# Review frames from the real game camera: one per landmark type (nearest to the
# start), plus the Mire Reaper leaper in play and close up. Run WITHOUT --headless.

const NAMES := ["root_arch", "fallen_log", "pond", "meadow"]


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
	var controls: Variant = scene.get_node("HUD/Controls")
	# Losing window focus must not pause the review.
	for connection in controls.pause_requested.get_connections():
		controls.pause_requested.disconnect(connection.callable)
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)
	for prey in world.prey:
		prey.visible = false
	var found := {}
	for ring in 12:
		for x in range(-ring, ring + 1):
			for z in range(-ring, ring + 1):
				var mark: Dictionary = arena.landmark(Vector2i(x, z))
				if not mark.is_empty() and not found.has(mark.type):
					found[mark.type] = mark
	for type in found:
		var mark: Dictionary = found[type]
		# Swarm just south of the landmark so the camera shows both.
		var spot: Vector3 = arena.safe_spawn(mark.center + Vector3(0.0, 0.0, 5.5), 0.75)
		await _frame(scene, swarm, arena, spot)
		root.get_texture().get_image().save_png("res://previews/preview_landmark_%s.png" % NAMES[type])
		print("Landmark %s at %s (swarm %s)" % [NAMES[type], mark.center, spot])
	# Leaper beside the swarm in the game camera, crouched in its warning pose.
	var open: Vector3 = arena.safe_spawn(Vector3(3.0, 0.0, 30.0), 3.0)
	await _frame(scene, swarm, arena, open)
	world.model.elapsed = 60
	var leaper: Variant = world._spawn_leaper(open + Vector3(-4.0, 0.0, -3.5))
	await create_timer(0.9).timeout
	leaper.state = leaper.State.STALK
	leaper.step(0.2, open, 1.0)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/preview_leaper_game.png")
	# Close-up from the front-left to judge silhouette, facing and colours.
	var close := Camera3D.new()
	scene.add_child(close)
	close.fov = 40.0
	var forward := Vector3(sin(leaper.rotation.y), 0.0, cos(leaper.rotation.y))
	var side := Vector3(forward.z, 0.0, -forward.x)
	close.position = leaper.global_position + forward * 4.2 + side * 2.2 + Vector3(0.0, 2.6, 0.0)
	close.look_at(leaper.global_position + Vector3(0.0, 0.7, 0.0), Vector3.UP)
	close.current = true
	leaper.warning.visible = false
	leaper.arc.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/preview_leaper_model.png")
	# Pure side view: the head must point along the leaper's forward (+Z).
	close.position = leaper.global_position + side * 5.5 + Vector3(0.0, 1.2, 0.0)
	close.look_at(leaper.global_position + Vector3(0.0, 0.7, 0.0), Vector3.UP)
	var marker := MeshInstance3D.new()
	var tip := SphereMesh.new()
	tip.radius = 0.15
	tip.height = 0.3
	marker.mesh = tip
	scene.add_child(marker)
	marker.global_position = leaper.global_position + forward * 1.8 + Vector3(0.0, 0.3, 0.0)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/preview_leaper_side.png")
	marker.queue_free()
	print("Saved landmark and leaper review frames")
	quit()


func _frame(scene: Node, swarm: Node3D, arena: Node3D, spot: Vector3) -> void:
	swarm.position = spot
	arena.sync(spot)
	scene._snap_camera()
	for index in 3:
		await process_frame
	await RenderingServer.frame_post_draw
