extends SceneTree

# Review frames for stage 10 (run WITHOUT --headless, e.g. tools/capture.ps1
# -Only migration): the Moosschlund in a real run - ground warning, arrival,
# a pattern with the apex bar, the victory, the open Migrationsschlund, the
# hold, the swirl and the arrival in the Glutsumpf. HuntWorld is stepped by hand
# (fixed 1/60 s per frame); Main runs normally (camera, zoom, Königsmoment).

const APEX = preload("res://scripts/apex_boss.gd")
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
	world.model.elapsed = 222.0
	world.model.population = 90
	swarm.set_population(90, false)
	world.hunters_unlocked = true
	for key in ["hunter_clock", "skitter_clock", "leaper_clock", "elite_clock", "nest_clock", "boss_clock"]:
		world.set(key, 9999.0)
	world.spawn_clock = -9999.0
	for target in world.prey:
		target.queue_free()
	world.prey.clear()
	await _run(1.0)
	# 1 - ground warning ahead of the swarm
	world.begin_apex_warning()
	await _run(1.7)
	await _save("preview_migration_1_warning.png")
	# 2 - the Moosschlund rises
	await _run(TUNING.APEX_WARNING_SECONDS - 1.7 + 1.3)
	await _save("preview_migration_2_arrival.png")
	await _run(1.2)
	# 3 - a locked pattern with the apex bar
	var apex: Variant = world.apex
	apex.cooldown = 9999.0
	apex.state = APEX.State.CHASE
	apex.begin_attack(APEX.Pattern.ROOTS, swarm.position, 1.0)
	await _run(0.8)
	await _save("preview_migration_3_pattern.png")
	apex._clear_telegraphs()
	apex.state = APEX.State.CHASE
	await _run(0.4)
	# 4 - victory: Königsmoment and banner
	apex.phase = 2
	apex.health = 0.5
	apex.take_damage(1.0)
	await _run(0.1)
	await _run_real(0.6)
	await _save("preview_migration_4_victory.png")
	# 5 - the maw opens behind the corpse
	await _run(TUNING.APEX_PORTAL_DELAY + 1.6)
	var maw: Variant = world.portal
	if maw == null:
		push_error("no migration maw")
		quit(1)
		return
	var toward: Vector3 = (maw.position - swarm.position)
	toward.y = 0.0
	swarm.position = maw.position - toward.normalized() * 6.5
	await _run(1.0)
	await _save("preview_migration_5_portal.png")
	# 6 - holding inside
	swarm.position = maw.position
	world.unit_points_valid = false
	await _run(0.6)
	await _save("preview_migration_6_hold.png")
	# 7 - the swirl (just before the biome switch)
	while not world.migrating():
		await _run(DT)
	await _run(TUNING.MIGRATION_SWITCH_AT * 0.8)
	await _save("preview_migration_7_swirl.png")
	# 8 - arrival in the Glutsumpf
	await _run(TUNING.MIGRATION_TRANSITION_SECONDS)
	await _run(0.7)
	await _save("preview_migration_8_glutsumpf.png")
	await _run(2.5)
	await _save("preview_migration_9_glutsumpf_play.png")
	print("Saved migration review frames")
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
	root.get_texture().get_image().save_png("res://" + file_name)
