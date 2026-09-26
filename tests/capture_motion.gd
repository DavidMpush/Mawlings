extends SceneTree

# Renders mid-motion review frames with real input and real time:
# run, attack, Rally, hit reaction, off-screen boss pointer, 250 population.

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
	await create_timer(0.3).timeout
	Input.action_press("move_right")
	Input.action_press("move_up")
	await create_timer(0.55).timeout
	await _save("preview_motion_run.png")
	Input.action_release("move_right")
	Input.action_release("move_up")
	await create_timer(0.35).timeout
	var target: Node3D = world.prey[0]
	target.set("health", 999.0)
	target.set_process(false)
	target.position = swarm.position + Vector3(0.9, 0.0, -0.4)
	await create_timer(0.55).timeout
	await _save("preview_motion_attack.png")
	target.set("health", 0.01)
	await create_timer(0.3).timeout
	controls.rally_pressed = true
	await create_timer(0.6).timeout
	await _save("preview_motion_rally.png")
	controls.rally_pressed = false
	await create_timer(0.5).timeout
	world._apply_hit(7, swarm.position + Vector3(1.6, 0.0, 0.4), 0.4)
	await create_timer(0.14).timeout
	await _save("preview_motion_hit.png")
	await create_timer(0.8).timeout
	world._spawn_boss(swarm.position + Vector3(16.0, 0.0, -9.0))
	await create_timer(0.4).timeout
	await _save("preview_motion_pointer.png")
	world.boss.queue_free()
	world.boss = null
	world.model.population = 250
	swarm.set_population(250)
	await create_timer(0.9).timeout
	await _save("preview_motion_250.png")
	print("Saved motion review frames")
	quit()


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + file_name)
