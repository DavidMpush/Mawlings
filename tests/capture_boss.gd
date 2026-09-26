extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.size = Vector2i(540, 960)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var world: Variant = scene.get_node("HuntWorld")
	var swarm: Variant = scene.get_node("Swarm")
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)
	var boss: Variant = world._spawn_boss(Vector3(0, 0, -6.0))
	boss.state = boss.State.CHASE
	world._update_hud("DER BOG KING ERSCHEINT")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview_boss.png")
	boss.position = Vector3(0, 0, -4.4)
	boss.step(0.01, swarm.position, 1.0)
	world._update_hud("BOG KING STAMPFT · AUS DEM ROTEN KREIS!")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview_boss_warning.png")
	print("Saved boss review frames")
	quit()
