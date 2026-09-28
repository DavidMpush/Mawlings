extends SceneTree

# Every recorded sound id is reached from its HuntWorld moment (Sfx.recently_played),
# and the portal hum loop follows the Migrationsschlund: open -> on, pause -> off,
# resume -> on, migration / reset -> off. Run with --audio-driver Dummy.

const APEX_BOSS = preload("res://scripts/apex_boss.gd")
const MIRE_LEAPER = preload("res://scripts/mire_leaper.gd")
const TUNING = preload("res://scripts/tuning.gd")
const APEX_SANDWORM = preload("res://scripts/apex_sandworm.gd")
const SANDSTORM = preload("res://scripts/sandstorm.gd")
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
		await _check_e23()
	scene.queue_free()
	await process_frame
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS sfx_hooks: boss_roar, flood_warn, quake, regen, alpha_core, fanfare, migration_whoosh, leaper_windup, portal_open fire; portal_hum follows open/pause/migration/reset; Etappe 23: cocoons (open, 4 rarities, denied), power-ups (take, end), shrine (ticks, done), ability ready, desert (grubs, breach, sandstorm/dig loops stop on pause, desert ambience + music set); Glutsumpf (ambience, lava warn + burst)")
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


# Etappe 23: the new systems reach their own ids; desert loops follow the steps.
func _check_e23() -> void:
	_fresh()
	var chests: Variant = world.chests
	var dear: Dictionary = chests.spawn("map", swarm.position + Vector3(6.0, 0.0, 0.0))
	world.model.amber = 0
	for i in 120:
		chests.step(DT, dear.at)
	_expect("cocoon_denied", "cocoon too expensive")
	world.model.amber = 5000
	var cheap: Dictionary = chests.spawn("map", swarm.position + Vector3(-6.0, 0.0, 0.0))
	chests.open_now(cheap)
	_expect("cocoon_open", "cocoon opening")
	# Stage 28: uncommon reuses the common opening sound.
	for rarity: String in ["common", "uncommon", "rare", "epic", "legendary"]:
		var entry: Dictionary = chests.spawn("map", swarm.position + Vector3(0.0, 0.0, 8.0))
		chests.play_moment(entry, rarity)
		if rarity == "legendary" and not sfx.recently_played("fanfare", 2000):
			failures.append("legendary cocoon without its fanfare")
		_expect("cocoon_" + ("common" if rarity == "uncommon" else rarity), "cocoon moment " + rarity)

	_fresh()
	var powerups: Variant = world.powerups
	powerups.collect("rausch")
	_expect("powerup_take", "power-up pickup")
	powerups.step(30.0, swarm.position, PackedVector3Array())
	_expect("powerup_end", "power-up running out")

	_fresh()
	var shrines: Variant = world.shrines
	var shrine: Dictionary = shrines.spawn(swarm.position + Vector3(0.0, 0.0, 12.0))
	shrines.step(DT, shrine.at)
	_expect("shrine_tick", "shrine charging")
	shrines.charge_now(shrine)
	_expect("shrine_done", "shrine full")

	_fresh()
	var abilities: Variant = world.abilities
	if String(abilities.ability_id) == "":
		failures.append("no strain ability after reset (ability_ready not checked)")
	else:
		abilities.cooldown_left = 0.02
		abilities.step(0.05)
		_expect("ability_ready", "ability ready again")

	# Desert: start a run in the Dürrschlund.
	world.config = {"biome_id": "duerrschlund"}
	world.reset_run()
	world.model.population = 40
	swarm.set_population(40, false)
	world.hunter_clock = 999.0
	_clear()
	if String(world.biome_id) != "duerrschlund":
		failures.append("could not start in the Dürrschlund (biome %s)" % world.biome_id)
		return
	var desert: Variant = world.desert
	desert.ambush_clock = 9999.0
	desert.spawn_grubs(swarm.position + Vector3(5.0, 0.0, 0.0), 3)
	_expect("sandgrub_burst", "sand grubs breaking out")
	desert.grubs.clear()
	var storm: Variant = desert.storm
	storm.state = SANDSTORM.State.STORM
	storm.strength = 1.0
	storm.clock = 60.0
	var worm: Variant = world.spawn_apex(swarm.position + Vector3(0.0, 0.0, -16.0), "apex_sandworm")
	worm.state = APEX_SANDWORM.State.CHASE
	_clear()
	desert.step(DT, 0.0, "")
	if not sfx.is_looping("sandstorm"):
		failures.append("sandstorm loop does not run in the storm")
	if not sfx.is_looping("sandworm_dig"):
		failures.append("sandworm_dig loop does not run while the worm burrows")
	if sfx.ambience_id() != "ambience_desert":
		failures.append("desert ambience not selected (%s)" % sfx.ambience_id())
	var music: Variant = scene.get_node_or_null("Music")
	if music != null and music.biome() != "desert":
		failures.append("music not on the desert set (%s)" % music.biome())
	worm.current_pattern = APEX_SANDWORM.Pattern.BREACH
	worm.state = APEX_SANDWORM.State.STRIKE
	desert.step(DT, 0.0, "")
	_expect("sandworm_breach", "Sandwurm breakthrough")
	# No world step in a frame (pause, choice, migration): the loops go quiet.
	await process_frame
	await process_frame
	if sfx.is_looping("sandstorm") or sfx.is_looping("sandworm_dig"):
		failures.append("desert loops keep running while the world holds still")
	# Etappe 24: Glutsumpf - own ambience, eruptions warn and burst.
	world.config = {"biome_id": "glutsumpf"}
	world.reset_run()
	world.model.population = 40
	swarm.set_population(40, false)
	_clear()
	if String(world.biome_id) != "glutsumpf":
		failures.append("could not start in the Glutsumpf (biome %s)" % world.biome_id)
		return
	world.desert.step(DT, 0.0, "")
	if sfx.ambience_id() != "ambience_glutsumpf":
		failures.append("Glutsumpf ambience not selected (%s)" % sfx.ambience_id())
	var eruptions: Variant = world.eruptions
	# The start stays free of eruptions: search a spot with lava sources in reach.
	var spot := Vector3.INF
	for ring in range(1, 8):
		for k in 12:
			var probe := Vector3(cos(TAU * k / 12.0), 0.0, sin(TAU * k / 12.0)) * 20.0 * ring
			if not (eruptions.candidates(probe) as Array).is_empty():
				spot = probe
				break
		if spot.is_finite():
			break
	if spot.is_finite():
		swarm.position = spot
	eruptions.erupt_soon()
	eruptions.step(DT, swarm.position, 1.0)
	if eruptions.pending.is_empty():
		failures.append("no eruption scheduled in the Glutsumpf")
	else:
		_expect("lava_warn", "eruption announced")
		eruptions.step(eruptions.WARNING_SECONDS + 0.1, swarm.position, 1.0)
		_expect("lava_burst", "eruption burst")
	world.config = {}
	world.reset_run()
	world.desert.step(DT, 0.0, "")
	if sfx.ambience_id() != "ambience_jungle":
		failures.append("jungle ambience not back after leaving the desert (%s)" % sfx.ambience_id())
