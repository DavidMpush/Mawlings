extends SceneTree

# Stage 05 KAMPF review frames: partial ring hit, kill popups, Königsmoment.
# Needs a window (never --headless).


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	for i in 30:
		await process_frame
	var world: Variant = scene.get_node("HuntWorld")
	var swarm: Variant = scene.get_node("Swarm")
	world.hunter_clock = 1e9
	world.boss_clock = 1e9
	world.model.population = 60
	swarm.set_population(60, false)
	for i in 40:
		await process_frame

	# Partial hit: the ring covers only the left part of the swarm.
	var hunter: Variant = world._spawn_hunter(swarm.position + Vector3(-5.5, 0, 0.5))
	hunter.state = hunter.State.WARNING
	hunter.remaining = 0.35
	hunter.attack_center = swarm.position + Vector3(-2.6, 0, 0)
	hunter.attack_power = 30
	hunter.warning.global_position = hunter.attack_center
	hunter.warning.scale = Vector3.ONE
	hunter.warning.visible = true
	hunter.warning_material.albedo_color = Color("ff674b")
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/preview_combat_partial_warning.png")
	while hunter.state == hunter.State.WARNING:
		await process_frame
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/preview_combat_partial_hit.png")
	print("partial hit share=%.2f loss=%d population=%d" % [world.last_hit_share, world.last_loss, world.model.population])
	hunter.health = -1.0

	# Kill popups: two prey eaten beside the swarm.
	for i in 40:
		await process_frame
	world._spawn_prey(swarm.position + Vector3(2.5, 0, -1.5))
	world._spawn_prey(swarm.position + Vector3(-2.0, 0, 2.5))
	world._kill_prey(world.prey[-1])
	world._kill_prey(world.prey[-1])
	world.evolution.offers.clear()
	for i in 14:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/preview_combat_popups.png")

	# Königsmoment: the Bog King falls next to the swarm.
	for i in 60:
		await process_frame
	var king: Variant = world._spawn_boss(swarm.position + Vector3(0, 0, -5.0))
	king.state = king.State.RECOVERY
	king.emerge = 1.0
	king.remaining = 100.0
	for i in 10:
		await process_frame
	king.health = -1.0
	await process_frame
	# The kills above earn enough DNA for several offers; keep the moment unobstructed.
	for i in 12:
		world.evolution.offers.clear()
		world.evolution.dna = 0
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/preview_combat_king.png")
	print("king moment time_scale=%.2f" % Engine.time_scale)
	await create_timer(0.9, true, false, true).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/preview_combat_king_late.png")
	print("after moment time_scale=%.2f" % Engine.time_scale)
	print("Saved combat review frames")
	quit()
