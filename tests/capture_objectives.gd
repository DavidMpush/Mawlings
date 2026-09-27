extends SceneTree

# Review frames for stage 06 objectives (run WITHOUT --headless):
# Brutnest filling, hatched clutch, off-screen pointers, Fluch-Totem hold,
# cursed Bog King with an elite hunter and the curse status chip.

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
	_quiet()
	world.model.population = 60
	swarm.set_population(60, false)
	# 1: swarm walking into a half-filled nest.
	var nest: Variant = world.spawn_nest(swarm.position + Vector3(2.2, 0, -2.6))
	nest.progress = 0.45
	await create_timer(1.2).timeout
	await _save("preview_objectives_nest.png")
	# 2: hatched clutch with reward popup.
	nest.progress = 0.995
	await create_timer(0.3).timeout
	world.evolution.offers.clear()
	await create_timer(0.1).timeout
	await _save("preview_objectives_hatch.png")
	# 3: off-screen nest and totem pointers.
	world.nest_clock = 1000000.0
	world.spawn_nest(swarm.position + Vector3(22, 0, 6)).progress = 0.3
	world.spawn_totem(swarm.position + Vector3(-18, 0, -14))
	await create_timer(0.6).timeout
	await _save("preview_objectives_pointer.png")
	# 3b: the totem model close to the swarm, not yet held.
	world.totem.position = swarm.position + Vector3(0.0, 0, -5.0)
	await create_timer(0.4).timeout
	await _save("preview_objectives_totem_model.png")
	# 4: holding the totem.
	world.totem.position = swarm.position + Vector3(0.6, 0, -0.8)
	await create_timer(0.9).timeout
	await _save("preview_objectives_totem.png")
	await create_timer(1.2).timeout
	world.evolution.offers.clear()
	# 5: cursed boss arrives, elite hunter beside the swarm, curse chip in the HUD.
	world.nest.queue_free()
	world.nest = null
	world._spawn_boss(swarm.position + Vector3(4.5, 0, -6.5))
	var elite: Variant = world.spawn_elite(swarm.position + Vector3(-3.8, 0, -1.5))
	elite.state = elite.State.CHASE
	await create_timer(2.6).timeout
	await _save("preview_objectives_curse.png")
	print("Saved objective review frames")
	quit()


func _quiet() -> void:
	for target in world.prey:
		target.queue_free()
	world.prey.clear()
	world.spawn_clock = -1000000.0
	world.hunter_clock = 1000000.0
	world.skitter_clock = 1000000.0
	world.leaper_clock = 1000000.0
	world.boss_clock = 1000000.0
	world.elite_clock = 1000000.0
	world.nest_clock = 1000000.0


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + file_name)
