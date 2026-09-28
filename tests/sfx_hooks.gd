extends SceneTree

# Every recorded sound id is reached from its HuntWorld moment (Sfx.recently_played),
# and the portal hum loop follows the Migrationsschlund: open -> on, pause -> off,
# resume -> on, migration / reset -> off. Run with --audio-driver Dummy.

const APEX_BOSS = preload("res://scripts/apex_boss.gd")
const MIRE_LEAPER = preload("res://scripts/mire_leaper.gd")
const TUNING = preload("res://scripts/tuning.gd")
const DT := 1.0 / 60.0
var failures: Array[String] = []
var scene: Node
var world: Variant
var swarm: Variant
var sfx: Variant


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	sfx = scene.get_node_or_null("Sfx")
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)
	if sfx == null:
		failures.append("Main has no Sfx node")
	else:
		_check_hooks()
	scene.queue_free()
	await process_frame
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS sfx_hooks: boss_roar, flood_warn, quake, regen, alpha_core, fanfare, migration_whoosh, leaper_windup, portal_open fire; portal_hum follows open/pause/migration/reset")
	quit(0)


func _fresh() -> void:
	world.config = {}
	world.reset_run()
	world.model.population = 40
	swarm.set_population(40, false)
	world.model.elapsed = 200.0
	world.hunter_clock = 999.0
	_clear()


# Forgets rate limits and bookkept voices (loops untouched) so every trigger
# below can start its id again.
func _clear() -> void:
	sfx._last_start_ms.clear()
	for i in sfx._player_end.size():
		sfx._player_end[i] = 0


func _expect(id: String, what: String) -> void:
	if not sfx.recently_played(id, 2000):
		failures.append("'%s' not played at %s" % [id, what])
	_clear()


func _check_hooks() -> void:
	_fresh()
	world._spawn_boss(swarm.position + Vector3(0.0, 0.0, -12.0))
	_expect("boss_roar", "Bog King spawn")

	_fresh()
	world.flood_state = 0
	world.model.elapsed = world.flood_start - TUNING.FLOOD_WARNING_SECONDS + 0.05
	world._step_flood(DT, 0.0)
	_expect("flood_warn", "flood announcement")

	_fresh()
	world.begin_apex_warning()
	_expect("quake", "apex ground warning")
	var apex: Variant = world.spawn_apex(swarm.position + Vector3(0.0, 0.0, -14.0))
	_expect("boss_roar", "apex spawn")
	world._audio_step(DT, world.model.population)
	_clear()
	apex.begin_attack(APEX_BOSS.Pattern.QUAKE, swarm.position, 1.0)
	world._audio_step(DT, world.model.population)
	_expect("quake", "apex QUAKE wind-up")

	_fresh()
	# Etappe 17c: Regeneration heals per second; the kill heal comes from the Königszahnkette.
	world.evolution.debug_grant("koenigszahnkette")
	world.model.leader_hp = maxi(1, world.model.leader_max_hp - 20)
	world._note_kills(15)
	_expect("regen", "regeneration heal")

	_fresh()
	world.collect_alpha_core()
	_expect("alpha_core", "Alpha-Kern pickup")

	_fresh()
	var music: Variant = scene.get_node_or_null("Music")
	var stinger_before: String = music.last_stinger() if music != null else ""
	world._king_moment(swarm.position)
	_expect("fanfare", "Königsmoment")
	if music != null and music.last_stinger() == "king" and stinger_before != "king":
		failures.append("Königsmoment still plays the music stinger 'king'")

	_fresh()
	var leaper: Variant = world._spawn_leaper(swarm.position + Vector3(0.0, 0.0, -10.0))
	world._audio_step(DT, world.model.population)
	_clear()
	leaper.state = MIRE_LEAPER.State.WARNING
	world._audio_step(DT, world.model.population)
	_expect("leaper_windup", "Mire Leaper wind-up")

	_fresh()
	world.open_portal(swarm.position + Vector3(0.0, 0.0, -8.0))
	_expect("portal_open", "portal opening")
	if not sfx.is_looping("portal_hum"):
		failures.append("portal_hum does not run while the portal is open")
	world.toggle_pause()
	if sfx.is_looping("portal_hum"):
		failures.append("portal_hum keeps running while paused")
	world.toggle_pause()
	if not sfx.is_looping("portal_hum"):
		failures.append("portal_hum does not resume after the pause")
	world._begin_migration()
	_expect("migration_whoosh", "migration start")
	if sfx.is_looping("portal_hum"):
		failures.append("portal_hum keeps running during the migration")

	_fresh()
	world.open_portal(swarm.position + Vector3(0.0, 0.0, -8.0))
	world.reset_run()
	if sfx.is_looping("portal_hum"):
		failures.append("portal_hum survives a reset")
