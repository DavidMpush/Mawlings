extends SceneTree

const TUNING = preload("res://scripts/tuning.gd")


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
	# Skip the emerge animation: fully risen chase pose.
	boss.state = boss.State.CHASE
	boss.emerge = 1.0
	var facing: Vector3 = swarm.position - boss.position
	boss.rotation.y = atan2(facing.x, facing.z) + PI * 0.5
	boss.refresh_pose()
	world._update_hud("DER BOG KING ERSCHEINT")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview_boss.png")
	boss.position = Vector3(0, 0, -4.4)
	boss.step(0.01, swarm.position, 1.0)
	for i in range(12):
		boss.step(1.0 / 60.0, swarm.position, 1.0)
	world._update_hud("BOG KING STAMPFT · AUS DEM ROTEN KREIS!")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview_boss_warning.png")
	# Advance to ~80 % of the warning to show the growing fill disc and rearing pose.
	while boss.state == boss.State.WARNING and boss.remaining > TUNING.BOSS_WARNING_SECONDS * 0.2:
		boss.step(1.0 / 60.0, swarm.position, 1.0)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview_boss_warning_late.png")
	# Swarm steps aside, the stomp lands; then settle into the exhausted recovery pose.
	var aside := Vector3(8, 0, 0)
	while boss.state == boss.State.WARNING:
		boss.step(1.0 / 60.0, aside, 1.0)
	for i in range(45):
		boss.step(1.0 / 60.0, aside, 1.0)
	world._update_hud("BOG KING ERSCHÖPFT · JETZT ANGREIFEN!")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview_boss_recovery.png")
	print("Saved boss review frames")
	quit()
