extends SceneTree

# Etappe 17b/17c: Schwarm ohne Limit und Anführer-LP aus der echten Spielkamera.
# Ohne --headless ausführen, mit --screen 1 --audio-driver Dummy.
# Ergebnis: preview_swarm17_*.png (900 × 1600)
#   pop_120 / pop_500 / pop_5000   Schwarm bei 120, 500 und 5.000 Tieren
#   hud_12k                        HUD-Kurzform ab 10.000 („12,3k“)
#   leader_full / half / critical  Anführer-Balken grün, gelb, rot
#   lifesteal                      kleines grünes +N über dem Anführer
#   successor                      Nachfolger übernimmt (Krone springt)

const DT := 1.0 / 60.0

var scene: Node
var world: Node3D
var swarm: Node3D
var origin := Vector3.ZERO


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(900, 1600)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	var controls: Node = scene.get_node("HUD/Controls")
	if controls.pause_requested.is_connected(world.toggle_pause):
		controls.pause_requested.disconnect(world.toggle_pause)
	for i in 30:
		await process_frame
	if world.paused:
		world.toggle_pause()
	scene.set_process(false)
	world.set_process(false)
	_quiet()
	origin = swarm.position
	for entry in world.chests.cocoons:
		entry.node.position = Vector3(900, 0, 900)
		entry.at = Vector3(900, 0, 900)
	for pop in [120, 500, 5000]:
		_population(pop)
		await _run(1.6)
		await _save("pop_%d" % pop)
	_population(12345)
	await _run(0.8)
	await _save("hud_12k")
	_population(60)
	await _run(1.2)
	for pair in [["full", 1.0], ["half", 0.5], ["critical", 0.15]]:
		world.model.leader_hp = int(round(float(world.model.leader_max_hp) * float(pair[1])))
		await _run(0.3)
		await _save("leader_" + pair[0])
	world.model.leader_hp = int(world.model.leader_max_hp * 0.5)
	await _run(0.2)
	world.evolution.debug_grant("lifesteal", "legendary")
	world.melee_dealt = 700.0
	world._step_leader_heal(DT)
	await _run(0.25)
	await _save("lifesteal")
	# Successor: the leader falls, the crown jumps.
	world.model.leader_hp = 1
	world.model.leader_invulnerable = 0.0
	world._apply_hit(0, swarm.position, 0.2, null, true)
	await _run(0.22)
	await _save("successor")
	print("Saved stage 17b/c frames")
	quit()


func _population(count: int) -> void:
	world.model.population = count
	world.model.peak_population = maxi(world.model.peak_population, count)
	swarm.set_population(count, false)
	world.unit_points_valid = false


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
	world.flood_start = 1000000.0
	world.apex_state = 4
	world.totem_offered = true


func _run(seconds: float) -> void:
	for i in int(round(seconds / DT)):
		swarm.position = origin
		world.unit_points_valid = false
		world.step(DT)
		while not world.evolution.offers.is_empty():
			world.choose_mutation(0)
		await process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview_swarm17_%s.png" % name)
