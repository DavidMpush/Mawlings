extends SceneTree

# Review frames for stage 10 part 3 (run WITHOUT --headless): the Aschenkröte in
# a real run - arrival in the Glutsumpf through the maw, the ground warning
# APEX_ARRIVAL_DELAY s later, the toad rising, a spit with Glutpfützen, the swarm
# biting the rim, the victory (corpse + Königsmoment) and the maw back to the
# Verdant Maw. HuntWorld is stepped by hand (fixed 1/60 s per frame); Main runs
# normally (camera, zoom, Königsmoment).

const TOAD = preload("res://scripts/apex_toad.gd")
const TUNING = preload("res://scripts/tuning.gd")
const DT := 1.0 / 60.0

var scene: Node
var world: Variant
var swarm: Variant


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	var controls: Variant = scene.get_node("HUD/Controls")
	if controls.pause_requested.is_connected(world.toggle_pause):
		controls.pause_requested.disconnect(world.toggle_pause)
	world.set_process(false)
	world.model.elapsed = 260.0
	world.model.population = 80
	swarm.set_population(80, false)
	world.hunters_unlocked = true
	for key in ["hunter_clock", "skitter_clock", "leaper_clock", "elite_clock", "nest_clock", "boss_clock", "flood_wave_clock"]:
		world.set(key, 9999.0)
	world.flood_start = 100000.0
	world.spawn_clock = -9999.0
	for target in world.prey:
		target.queue_free()
	world.prey.clear()
	await _run(1.0)
	# The Moosschlund is beaten: walk through the maw into the Glutsumpf.
	world.apex_state = 3
	world.apex_spawned = 1
	world.apex_kills = 1
	var maw: Variant = world.open_portal(swarm.position + Vector3(0, 0, -7))
	await _run(1.4)
	swarm.position = maw.position
	world.unit_points_valid = false
	while not world.migrating():
		await _run(DT)
	await _run(TUNING.MIGRATION_TRANSITION_SECONDS + 1.0)
	# 1 - ground warning, APEX_ARRIVAL_DELAY after the arrival
	world.model.elapsed = world.apex_due
	await _run(1.6)
	await _save("preview_toad_run_1_warning.png")
	# 2 - the Aschenkröte rises
	await _run(TUNING.APEX_WARNING_SECONDS - 1.6 + 1.4)
	await _save("preview_toad_run_2_arrival.png")
	var toad: Variant = world.apex
	if not (toad is TOAD):
		push_error("no Aschenkröte")
		quit(1)
		return
	await _run(1.2)
	# 3 - Glutspucke: locked circles, then lingering Glutpfützen
	toad.cooldown = 9999.0
	toad.state = TOAD.State.CHASE
	toad.begin_attack(TOAD.Pattern.SPIT, swarm.position, 1.0)
	await _run(0.9)
	await _save("preview_toad_run_3_spit.png")
	swarm.position += Vector3(6, 0, 0)
	world.unit_points_valid = false
	while toad.state == TOAD.State.WINDUP or toad.state == TOAD.State.STRIKE:
		await _run(DT)
	await _run(0.5)
	await _save("preview_toad_run_4_puddles.png")
	# 5 - the swarm bites the exhausted toad at its rim
	toad.puddles.clear()
	toad.state = TOAD.State.EXHAUSTED
	toad.remaining = 9999.0
	var rim: Vector3 = swarm.position - toad.position
	rim.y = 0.0
	swarm.position = toad.position + rim.normalized() * (toad.body_radius + 1.2)
	world.unit_points_valid = false
	await _run(1.5)
	await _save("preview_toad_run_5_rim.png")
	# 6 - victory: corpse and Königsmoment
	toad.phase = 2
	toad.health = 0.5
	toad.take_damage(1.0)
	await _run(0.1)
	await _run_real(0.6)
	await _save("preview_toad_run_6_victory.png")
	await _run(TUNING.APEX_SINK_SECONDS)
	await _save("preview_toad_run_7_corpse.png")
	# 8 - the maw back to the Verdant Maw
	await _run(1.0)
	var back: Variant = world.portal
	if back == null:
		push_error("no maw back")
		quit(1)
		return
	var toward: Vector3 = back.position - swarm.position
	toward.y = 0.0
	swarm.position = back.position - toward.normalized() * 6.5
	await _run(1.0)
	await _save("preview_toad_run_8_portal.png")
	print("Saved toad run review frames (maw -> %s)" % back.target_biome)
	quit()


# Steps the world by fixed frames while Main renders them.
func _run(seconds: float) -> void:
	for index in maxi(1, int(round(seconds / DT))):
		if world.choosing():
			world.choose_mutation(0)
		world.step(DT)
		await process_frame


# Real time without world steps (the Königsmoment runs in real seconds).
func _run_real(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/" + file_name)
