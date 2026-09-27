extends SceneTree

# Stage 10: the Moosschlund inside a real run (HuntWorld). Spawn time per
# difficulty (before the flood, population gate, ground warning first), hit
# paths (locked areas through _resolve_area_hit incl. the leader-LP rule, melee
# with body_radius x vulnerability(), attack forms), and the kill: one apex
# corpse, Königsmoment, victory banner counter and exactly one Migrationsschlund.

const APEX = preload("res://scripts/apex_boss.gd")
const TUNING = preload("res://scripts/tuning.gd")
const DATA = preload("res://scripts/meta/meta_data.gd")
const DT := 1.0 / 60.0
var failures: Array[String] = []
var scene: Node
var world: Variant
var swarm: Variant
var main: Variant


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _load()
	_check_spawn_times()
	_check_area_hit()
	_check_melee()
	_check_forms()
	_check_kill()
	scene.queue_free()
	await process_frame
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS apex_run: spawn before the flood per difficulty (population gate, ground warning), area hits with leader LP, melee x vulnerability, attack forms, one corpse + Königsmoment + one migration maw, no Bog King meanwhile")
	quit(0)


func _load() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	main = scene
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)


func _fresh(difficulty: int, population: int, elapsed: float) -> void:
	world.config = {"difficulty": difficulty}
	world.reset_run()
	world.model.population = population
	swarm.set_population(population, false)
	world.model.elapsed = elapsed
	# Keep side enemies out of the way (they would spawn late in a run).
	world.hunters_unlocked = true
	world.hunter_clock = 999.0
	world.skitter_clock = 999.0
	world.leaper_clock = 999.0
	world.elite_clock = 999.0
	world.nest_clock = 999.0
	for target in world.prey:
		target.queue_free()
	world.prey.clear()
	world.spawn_clock = -999.0


func _steps(seconds: float) -> void:
	var count := int(ceil(seconds / DT))
	for index in count:
		# Rewards may open a mutation offer; pick like a player would.
		if world.choosing():
			world.choose_mutation(0)
		world.step(DT)


func _check_spawn_times() -> void:
	var expected := [225.0, 180.0, 135.0]
	for difficulty in 3:
		var flood: float = float(DATA.DIFFICULTIES[difficulty].flood_start)
		_fresh(difficulty, 40, expected[difficulty] - 0.5)
		_check(is_equal_approx(world.apex_spawn_seconds(), expected[difficulty]), "Apex due at %.0f s on difficulty %d" % [expected[difficulty], difficulty])
		_check(world.apex_spawn_seconds() + TUNING.APEX_WARNING_SECONDS + TUNING.APEX_LATEST_EXTRA < flood, "Apex (latest) comes before the flood on difficulty %d" % difficulty)
		_steps(0.3)
		_check(world.apex_state == 0 and world.apex == null, "No apex before its time (difficulty %d)" % difficulty)
		_steps(0.3)
		_check(world.apex_state == 1 and world.apex == null, "Ground warning first (difficulty %d)" % difficulty)
		_check(String(world.hud.hint).contains("MOOSSCHLUND"), "Warning hint names the Moosschlund (got '%s')" % world.hud.hint)
		_steps(TUNING.APEX_WARNING_SECONDS + 0.1)
		_check(world.apex_state == 2 and world.apex != null, "Apex spawns after the warning (difficulty %d)" % difficulty)
		if world.apex != null:
			_check(is_equal_approx(world.apex.max_health, TUNING.APEX_HEALTH * TUNING.APEX_HEALTH_DIFFICULTY[difficulty]), "Apex health = APEX_HEALTH x APEX_HEALTH_DIFFICULTY (difficulty %d: %.0f)" % [difficulty, world.apex.max_health])
			_check(world.apex.position.distance_to(swarm.position) > TUNING.APEX_BODY_RADIUS + 3.0, "Apex rises away from the swarm")
			var objectives: Dictionary = world.hud.get_meta("objectives")
			_check(int(objectives.apex_state) == 2 and float(objectives.apex_max_health) > 0.0, "HUD gets the apex bar data")
		var music: Variant = scene.get_node_or_null("Music")
		if music != null:
			_check(music.last_stinger() == "boss", "Stinger 'boss' at the apex spawn")
			_check(music.stem_target("run_boss") == 1.0, "Boss music while the apex lives")
	# Population gate: a small swarm gets APEX_LATEST_EXTRA more seconds.
	_fresh(0, 5, 225.2)
	_steps(0.2)
	_check(world.apex_state == 0, "Small swarm: apex waits for the population gate")
	world.model.elapsed = 225.0 + TUNING.APEX_LATEST_EXTRA + 0.1
	_steps(0.1)
	_check(world.apex_state == 1, "Apex comes at the latest APEX_LATEST_EXTRA later")
	# A living Bog King delays it; no new Bog King while the apex lives.
	_fresh(0, 40, 226.0)
	var king: Variant = world._spawn_boss(swarm.position + Vector3(12, 0, 0))
	_steps(0.2)
	_check(world.apex_state == 0, "A living Bog King delays the apex")
	world.boss = null
	king.queue_free()
	_steps(0.1)
	_check(world.apex_state == 1, "Apex comes once the Bog King is gone")
	world.boss_clock = 0.0
	_steps(TUNING.APEX_WARNING_SECONDS + 0.5)
	_check(world.apex != null and world.boss == null, "No Bog King spawns while the apex rises or lives")


func _ready_apex(offset: Vector3) -> Variant:
	_fresh(0, 40, 230.0)
	var apex: Variant = world.spawn_apex(swarm.position + offset)
	apex.position = swarm.position + offset
	apex.state = APEX.State.CHASE
	apex.remaining = 0.0
	apex.cooldown = 999.0
	apex.refresh_pose()
	world.unit_points_valid = false
	return apex


func _check_area_hit() -> void:
	var apex: Variant = _ready_apex(Vector3(0, 0, -6.5))
	world.model.leader_invulnerable = 0.0
	var hp_before: int = world.model.leader_hp
	var population_before: int = world.model.population
	apex.begin_attack(APEX.Pattern.SPORES, swarm.position, 1.0)
	var points: PackedVector3Array = swarm.unit_world_points()
	var inside := 0
	for point in points:
		if apex.contains(point):
			inside += 1
	_check(inside == points.size(), "Spore ring covers the whole swarm (%d/%d)" % [inside, points.size()])
	var announced := 0.0
	var damaged_during_windup := false
	while apex.state == APEX.State.WINDUP and announced < 5.0:
		world.step(DT)
		announced += DT
		if apex.state == APEX.State.WINDUP and world.model.population < population_before:
			damaged_during_windup = true
	_check(not damaged_during_windup and announced >= TUNING.APEX_SPORE_WINDUP[0] - 0.05, "Nothing falls during the %.1f s wind-up" % TUNING.APEX_SPORE_WINDUP[0])
	var lost: int = population_before - world.model.population
	var expected := ceili(float(apex.attack_power) * float(points.size() - 1) / float(points.size()) - 0.0001)
	_check(lost == mini(expected, population_before - 1), "Followers inside fall like any area hit (lost %d, expected %d)" % [lost, expected])
	_check(world.model.leader_hp == hp_before - 1 and world.model.population > 0, "Leader inside loses 1 LP instead of dying (%d -> %d)" % [hp_before, world.model.leader_hp])
	_check(world.model.leader_invulnerable > 0.0, "Leader grace after the hit")
	# Outside the locked area: nothing happens.
	apex = _ready_apex(Vector3(0, 0, -6.5))
	world.model.leader_invulnerable = 0.0
	hp_before = world.model.leader_hp
	population_before = world.model.population
	apex.begin_attack(APEX.Pattern.ROOTS, swarm.position, 1.0)
	# Step the swarm out sideways of all three lanes before the strike.
	swarm.position += Vector3(12, 0, 0)
	world.unit_points_valid = false
	while apex.state == APEX.State.WINDUP:
		world.step(DT)
	_check(world.model.population == population_before and world.model.leader_hp == hp_before, "Dodged root lanes cost nothing")
	swarm.position = Vector3.ZERO


func _check_melee() -> void:
	var apex: Variant = _ready_apex(Vector3(0, 0, -4.0))
	var before: float = apex.health
	_steps(1.0)
	var chase_damage: float = before - apex.health
	_check(chase_damage > 0.0, "Melee bites the apex through its body radius (%.1f)" % chase_damage)
	apex.state = APEX.State.EXHAUSTED
	apex.remaining = 99.0
	before = apex.health
	_steps(1.0)
	var exhausted_damage: float = before - apex.health
	_check(absf(exhausted_damage / maxf(chase_damage, 0.001) - TUNING.APEX_EXHAUSTED_VULNERABILITY) < 0.12, "Exhausted apex takes x%.1f (%.1f vs %.1f)" % [TUNING.APEX_EXHAUSTED_VULNERABILITY, exhausted_damage, chase_damage])
	apex.state = APEX.State.PHASE_SHIFT
	apex.remaining = 99.0
	before = apex.health
	_steps(0.5)
	_check(apex.health == before and not world._living_targets().has(apex), "Roaring apex is immune and no form target")
	apex.state = APEX.State.CHASE
	_check(world._living_targets().has(apex), "Hittable apex is an attack-form target")


func _check_forms() -> void:
	if world.attack_forms == null:
		failures.append("attack_forms.gd missing - forms not checked")
		return
	var apex: Variant = _ready_apex(Vector3(0, 0, -8.0))
	apex.state = APEX.State.EXHAUSTED
	apex.remaining = 99.0
	world.evolution.ranks["saeurespucker"] = 3
	world._sync_attack_forms()
	var before: float = apex.health
	_steps(3.0)
	var dealt := 0.0
	for id in world.attack_forms.damage_dealt:
		dealt += float(world.attack_forms.damage_dealt[id])
	_check(apex.health < before and dealt > 0.0, "Attack forms hit the apex from range (%.1f)" % (before - apex.health))


func _check_kill() -> void:
	var apex: Variant = _ready_apex(Vector3(0, 0, -4.0))
	var bosses_before: int = world.model.bosses
	var pickups_before: int = world.alpha_pickups.size()
	var remains_before: int = world.remains.size()
	# Phase 2 already reached (at 50 % it roars and is immune first).
	apex.phase = 2
	apex.health = 0.5
	_steps(0.2)
	_check(world.apex == null and world.apex_state == 3 and world.apex_kills == 1, "Kill resolves once (state %d, kills %d)" % [world.apex_state, world.apex_kills])
	var apex_corpses := 0
	for id in world.corpse_kinds:
		if world.corpse_kinds[id] == "apex":
			apex_corpses += 1
	_check(apex_corpses == 1 and world.remains.size() >= remains_before + 1, "Exactly one apex corpse (%d)" % apex_corpses)
	_check(world.loot.lures.size() >= 1, "The apex drops a Lockruf")
	_check(int(world.model.kills_by_type.get("apex", 0)) == 1 and world.model.bosses == bosses_before, "Counted as apex kill, not as Bog King")
	_check(world.alpha_pickups.size() == pickups_before + TUNING.APEX_ALPHA_CORES, "Apex drops %d Alpha-Kerne" % TUNING.APEX_ALPHA_CORES)
	_check(world.apex_victories == 1 and main.king_zoom_left > 0.0, "Königsmoment (victory banner + zoom)")
	# The victory plays the "fanfare" sound (no second music stinger "king").
	var sfx: Variant = scene.get_node_or_null("Sfx")
	if sfx != null:
		_check(sfx.recently_played("fanfare", 5000), "Victory fanfare")
	var music: Variant = scene.get_node_or_null("Music")
	if music != null:
		_check(music.last_stinger() != "king", "No doubled king stinger")
	_check(world.portal == null and world.apex_dying != null, "Body sinks first, the maw opens after the delay")
	_steps(TUNING.APEX_PORTAL_DELAY + 0.1)
	_check(world.portal != null and _maws() == 1, "Exactly one migration maw")
	var corpse_position: Vector3 = world.remains_position(world.corpse_kinds.keys()[0]) if not world.corpse_kinds.is_empty() else Vector3.ZERO
	if world.portal != null:
		_check(world.portal.position.distance_to(corpse_position) >= TUNING.MIGRATION_RADIUS + 1.0, "Maw lies clear of the apex corpse (eating never migrates)")
	var again: Variant = world.open_portal(Vector3(30, 0, 30))
	_steps(TUNING.APEX_SINK_SECONDS + 0.5)
	_check(again == world.portal and _maws() == 1 and world.apex_dying == null, "No second maw; the body is gone after sinking")
	var objectives: Dictionary = world.hud.get_meta("objectives")
	_check(bool(objectives.portal_active) and String(objectives.portal_target) == "GLUTSUMPF", "HUD: MIGRATION pointer data")
	var stats: Dictionary = world.run_stats()
	_check(int(stats.apex_kills) == 1 and int(stats.biomes_visited) == 1, "RunStats apex_kills / biomes_visited")
	# The apex never returns in this run.
	world.model.elapsed = 400.0
	_steps(0.2)
	_check(world.apex == null and world.apex_state == 3, "One apex per run")


func _maws() -> int:
	var count := 0
	for child in world.get_children():
		if child.get_script() == preload("res://scripts/migration_maw.gd") and not child.is_queued_for_deletion():
			count += 1
	return count


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
