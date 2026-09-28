extends SceneTree

# Stage 10 part 3: the Aschenkröte inside a real run (HuntWorld) and the biome
# circle. Spawn APEX_ARRIVAL_DELAY s after the arrival in the Glutsumpf
# (population gate, ground warning, boss music), Glutpfützen hit per animal
# through _resolve_area_hit, attack forms and melee measure to the body rim,
# the kill leaves one apex_toad corpse + Königsmoment + a maw back to the
# Verdant Maw, and every loop through the circle makes the apex stronger.

const APEX = preload("res://scripts/apex_boss.gd")
const TOAD = preload("res://scripts/apex_toad.gd")
const SANDWORM = preload("res://scripts/apex_sandworm.gd")
const TUNING = preload("res://scripts/tuning.gd")
const PROFILE = preload("res://scripts/meta/profile.gd")
const DATA = preload("res://scripts/meta/meta_data.gd")
const DT := 1.0 / 60.0
var failures: Array[String] = []
var scene: Node
var world: Variant
var swarm: Variant
var arena: Variant
var main: Variant


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	main = scene
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	arena = scene.get_node("Arena")
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)
	_check_spawn_after_arrival()
	_check_population_gate()
	_check_puddles()
	_check_rim()
	_check_kill_and_circle()
	scene.queue_free()
	await process_frame
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS toad_run: Aschenkröte %.0f s after the Glutsumpf arrival (population gate, warning, boss music), Glutpfützen per animal, rim distance for forms + melee, apex_toad corpse + Königsmoment + maw back to the Verdant Maw, loop 2 x%.1f HP" % [TUNING.APEX_ARRIVAL_DELAY, TUNING.APEX_LOOP_HEALTH])
	quit(0)


func _fresh(population: int, elapsed: float) -> void:
	world.config = {}
	world.reset_run()
	world.model.population = population
	swarm.set_population(population, false)
	world.model.elapsed = elapsed
	world.hunters_unlocked = true
	world.hunter_clock = 999.0
	world.skitter_clock = 999.0
	world.leaper_clock = 999.0
	world.elite_clock = 999.0
	world.nest_clock = 999.0
	world.boss_clock = 999.0
	world.flood_wave_clock = 999.0
	# The flood is not part of this test (it would thin the swarm over the loops).
	world.flood_start = 100000.0
	for target in world.prey:
		target.queue_free()
	world.prey.clear()
	world.spawn_clock = -999.0
	swarm.position = Vector3(0, 0, 30)
	arena.sync(swarm.position)
	_spread()


# The swarm's own animation is off: lay the animals out as a loose disc
# (sunflower spiral, leader in the middle) so areas can cover a part of it.
func _spread() -> void:
	for index in swarm.units.size():
		var angle := float(index) * 2.39996
		swarm.units[index].position = Vector3(cos(angle), 0.0, sin(angle)) * 0.42 * sqrt(float(index))
	world.unit_points_valid = false


func _steps(seconds: float) -> void:
	for index in int(ceil(seconds / DT)):
		if world.choosing():
			world.choose_mutation(0)
		world.step(DT)


func _move_swarm(to: Vector3) -> void:
	swarm.position = to
	world.unit_points_valid = false


# Walks the swarm through the open maw until the swirl is done.
func _migrate() -> void:
	var maw: Variant = world.portal
	if maw == null:
		failures.append("No maw to migrate through")
		return
	_steps(1.3)
	_move_swarm(maw.position)
	_steps(TUNING.MIGRATION_HOLD_SECONDS + TUNING.MIGRATION_TRANSITION_SECONDS + 0.3)
	arena.finish_rebuild()


# Moosschlund beaten -> maw -> Glutsumpf: the toad is due APEX_ARRIVAL_DELAY later.
func _arrive_in_glutsumpf(population: int) -> void:
	_fresh(population, 300.0)
	# Stage 19: the Glutsumpf lies behind the Dürrschlund (Verdant -> Dürrschlund -> Glutsumpf).
	world._set_world_biome("duerrschlund", false)
	world.apex_state = 3
	world.open_portal(Vector3(0, 0, 40))
	_migrate()


func _check_spawn_after_arrival() -> void:
	_arrive_in_glutsumpf(60)
	_check(world.biome_id == "glutsumpf" and world.migrations == 1, "Arrived in the Glutsumpf")
	var arrival: float = world.apex_due - TUNING.APEX_ARRIVAL_DELAY
	_check(world.apex_state == 0 and absf(arrival - world.model.elapsed) < 1.0, "Next apex due %.0f s after the arrival (due %.1f, now %.1f)" % [TUNING.APEX_ARRIVAL_DELAY, world.apex_due, world.model.elapsed])
	_steps(1.0)
	_check(world.apex_state == 0 and world.apex == null, "No toad right after the arrival")
	world.model.elapsed = world.apex_due - 0.2
	_steps(0.1)
	_check(world.apex_state == 0, "No toad before its time")
	_steps(0.2)
	_check(world.apex_state == 1 and world.apex == null and world.apex_kind == "apex_toad", "Ground warning first (state %d)" % world.apex_state)
	_check(String(world.hud.hint).contains("ASCHENKRÖTE"), "Warning hint names the Aschenkröte (got '%s')" % world.hud.hint)
	_steps(TUNING.APEX_WARNING_SECONDS + 0.1)
	var toad: Variant = world.apex
	_check(toad != null and toad is TOAD and world.apex_state == 2, "The Aschenkröte rises in the Glutsumpf")
	if toad == null:
		return
	_check(is_equal_approx(toad.max_health, TUNING.APEX_TOAD_HEALTH * world.world_scale()), "First toad: APEX_TOAD_HEALTH x world bonus (%.0f)" % toad.max_health)
	var objectives: Dictionary = world.hud.get_meta("objectives")
	_check(int(objectives.apex_state) == 2 and String(objectives.apex_name) == "ASCHENKRÖTE", "HUD gets the apex bar data and name")
	var music: Variant = scene.get_node_or_null("Music")
	if music != null:
		_check(music.last_stinger() == "boss" and music.stem_target("run_boss") == 1.0, "Boss stinger + boss music for the toad")
	var sfx: Variant = scene.get_node_or_null("Sfx")
	if sfx != null:
		_check(sfx.recently_played("boss_roar", 5000), "Roar at the toad spawn")
	_check(world.boss == null, "No Bog King while the toad lives")


func _check_population_gate() -> void:
	_arrive_in_glutsumpf(12)
	world.model.elapsed = world.apex_due + 1.0
	_steps(0.2)
	_check(world.apex_state == 0, "Small swarm (%d < %d): toad waits" % [world.model.population, TUNING.APEX_TOAD_MIN_POPULATION])
	world.model.elapsed = world.apex_due + TUNING.APEX_LATEST_EXTRA + 0.1
	_steps(0.1)
	_check(world.apex_state == 1, "Toad comes at the latest APEX_LATEST_EXTRA later")


# A toad far away that does not attack (only its puddles act).
func _quiet_toad(offset: Vector3) -> Variant:
	var toad: Variant = world.spawn_apex(swarm.position + offset, "apex_toad")
	toad.position = swarm.position + offset
	toad.state = TOAD.State.CHASE
	toad.remaining = 0.0
	toad.cooldown = 999.0
	toad.refresh_pose()
	world.unit_points_valid = false
	return toad


# Steps until a puddle tick; returns [lost, expected loss, followers inside, points].
func _puddle_tick() -> Array:
	var toad: Variant = world.apex
	for frame in 120:
		var points: PackedVector3Array = swarm.unit_world_points()
		var inside := 0
		for index in range(1, points.size()):
			if toad.puddles.contains(points[index]):
				inside += 1
		var before: int = world.model.population
		world.unit_points_valid = false
		world.step(DT)
		var power: int = toad.puddles.resolved_power
		if power > 0:
			var expected := ceili(float(power) * float(inside) / float(points.size()) - 0.0001)
			return [before - world.model.population, mini(expected, before - 1), inside, points.size()]
	return [-1, -1, 0, 0]


func _check_puddles() -> void:
	_fresh(60, 420.0)
	var toad: Variant = _quiet_toad(Vector3(0, 0, -22))
	world.model.leader_invulnerable = 99.0
	# A puddle under the whole swarm: every follower inside, a real loss.
	toad.puddles.add(swarm.position, 6.0, 5.0, TOAD.telegraph_material(TOAD.SHAPE_PUDDLE, false))
	var full := _puddle_tick()
	_check(full[0] > 0 and full[0] == full[1] and full[2] == full[3] - 1, "Puddle under the swarm: every follower inside, loss %d = %d" % [full[0], full[1]])
	_check(world.last_hit_share > 0.99, "Full hit share (%.2f)" % world.last_hit_share)
	toad.puddles.clear()
	# A small puddle at the rim: only the animals inside count.
	var points: PackedVector3Array = swarm.unit_world_points()
	var far := points[1]
	for point in points:
		if Vector2(point.x - swarm.position.x, point.z - swarm.position.z).length() > Vector2(far.x - swarm.position.x, far.z - swarm.position.z).length():
			far = point
	toad.puddles.add(far, 1.0, 5.0, TOAD.telegraph_material(TOAD.SHAPE_PUDDLE, false))
	var part := _puddle_tick()
	_check(part[2] > 0 and part[2] < part[3] - 1, "Rim puddle covers only a few animals (%d of %d, spread %.2f m)" % [part[2], part[3], Vector2(far.x - swarm.position.x, far.z - swarm.position.z).length()])
	_check(part[0] == part[1] and part[0] < full[0], "Rim puddle loss per animal (%d = %d < %d)" % [part[0], part[1], full[0]])
	_check(world.last_hit_share > 0.0 and world.last_hit_share < 0.5, "Partial hit share (%.2f)" % world.last_hit_share)
	toad.puddles.clear()
	# Dodged: no puddle under the swarm, nothing falls.
	toad.puddles.add(swarm.position + Vector3(12, 0, 0), 2.0, 5.0, TOAD.telegraph_material(TOAD.SHAPE_PUDDLE, false))
	var dodged := _puddle_tick()
	_check(dodged[0] == 0, "Puddle beside the swarm costs nothing (%d)" % dodged[0])
	toad.puddles.clear()


func _check_rim() -> void:
	_fresh(40, 420.0)
	var toad: Variant = _quiet_toad(Vector3(0, 0, -30))
	var forms: Variant = world.attack_forms
	var probe: Vector3 = toad.position + Vector3(0, 0, toad.body_radius + 1.0)
	_check(is_equal_approx(forms._target_distance(toad, probe), 1.0), "Forms measure to the toad's rim (%.2f)" % forms._target_distance(toad, probe))
	var moos: Variant = APEX.new()
	moos.position = Vector3(100, 0, 0)
	_check(is_equal_approx(moos.body_distance(Vector3(100, 0, TUNING.APEX_BODY_RADIUS + 2.0)), 2.0), "Moosschlund has body_distance (rim)")
	moos.free()
	_check(forms._nearest([toad], probe + Vector3(0, 0, 1.5), 3.0) == toad, "A form with 3 m reach finds the toad 2.5 m from its rim (centre %.1f m)" % (toad.body_radius + 2.5))
	# A real form: Sporenwolke R3 (4.2 m) around the swarm reaches the rim only.
	toad.position = swarm.position + Vector3(0, 0, -(toad.body_radius + 2.6))
	toad.refresh_pose()
	world.evolution.ranks["sporenwolke"] = 3
	world._sync_attack_forms()
	var before: float = toad.health
	_steps(1.0)
	var spores := float(forms.damage_dealt.get("sporenwolke", 0.0))
	_check(spores > 0.0 and toad.health < before, "Sporenwolke hits the toad by its rim (%.1f dmg, centre %.1f m > %.1f m)" % [spores, toad.body_radius + 2.6, forms.SPORE_RADIUS[2]])
	# Melee: animals within MELEE_REACH of the rim bite.
	toad.position = swarm.position + Vector3(0, 0, -(toad.body_radius + 1.0))
	_spread()
	var bite: float = world.melee_factor(toad.position, "apex_toad", toad.melee_range, toad)
	_check(bite > 0.0, "Melee reaches the toad at its rim (%.2f)" % bite)
	var far_bite: float = world.melee_factor(toad.position + Vector3(0, 0, -20), "apex_toad", toad.melee_range, null)
	_check(far_bite == 0.0, "No melee from afar")


func _check_kill_and_circle() -> void:
	_arrive_in_glutsumpf(70)
	# Moosschlund and Sandwurm of the first loop count as spawned (a real run).
	world.apex_spawned = 2
	world.apex_kills = 1
	world.model.elapsed = world.apex_due
	_steps(TUNING.APEX_WARNING_SECONDS + 0.3)
	var toad: Variant = world.apex
	_check(toad is TOAD and is_equal_approx(toad.max_health, TUNING.APEX_TOAD_HEALTH * world.world_scale()), "Toad after the Moosschlund: loop 0 health (x world bonus)")
	if not (toad is TOAD):
		return
	toad.state = TOAD.State.CHASE
	toad.cooldown = 999.0
	toad.phase = 2
	toad.health = 0.5
	var remains_before: int = world.remains.size()
	var pickups_before: int = world.alpha_pickups.size()
	world.evolution.ranks["bite"] = 3
	toad.position = swarm.position + Vector3(0, 0, -(toad.body_radius + 0.5))
	world.unit_points_valid = false
	_steps(0.3)
	_check(world.apex == null and world.apex_state == 3 and world.apex_kills == 2 and world.toad_kills == 1, "Toad kill resolves once (state %d, kills %d/%d)" % [world.apex_state, world.apex_kills, world.toad_kills])
	var toad_corpses := 0
	for id in world.corpse_kinds:
		if world.corpse_kinds[id] == "apex_toad":
			toad_corpses += 1
	_check(toad_corpses == 1 and world.remains.size() >= remains_before + 1, "Exactly one apex_toad corpse (%d)" % toad_corpses)
	_check(world.corpse_view != null and world.corpse_view.has_method("add"), "Corpse view present")
	# Etappe 17: kein Alpha-Kern mehr (Welle 2: Boss-Kokon).
	_check(world.alpha_pickups.size() == pickups_before, "Toad drops no Alpha-Kern any more")
	_check(int(world.model.kills_by_type.get("apex", 0)) == 1, "Counted as apex kill")
	_check(world.apex_victories == 1 and main.king_zoom_left > 0.0, "Königsmoment (victory banner + zoom)")
	var sfx: Variant = scene.get_node_or_null("Sfx")
	if sfx != null:
		_check(sfx.recently_played("fanfare", 5000), "Victory fanfare")
	var objectives: Dictionary = world.hud.get_meta("objectives")
	_check(String(objectives.apex_name) == "ASCHENKRÖTE", "Victory banner can name the toad")
	_steps(TUNING.APEX_PORTAL_DELAY + 0.2)
	_check(world.portal != null and String(world.portal.target_biome) == "verdant_maw", "Maw back to the Verdant Maw")
	var stats: Dictionary = world.run_stats()
	_check(int(stats.apex_kills) == 2 and int(stats.toad_kills) == 1, "RunStats: apex_kills counts both, toad_kills 1")
	var path := "user://toad_run_test_profile.json"
	var profile: Variant = PROFILE.load_or_create(path)
	var outcome: Dictionary = profile.record_run(stats)
	_check(profile.quest_value("total_toads") == 1.0 and outcome.new_quests.has("apex_aschenkroete"), "Trophy Aschenkröte bezwungen")
	_check(not DATA.quest("apex_aschenkroete").is_empty(), "Trophy in meta_data")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# Back in the Verdant Maw: the Moosschlund returns, one loop stronger.
	_migrate()
	_check(world.biome_id == "verdant_maw" and world.apex_state == 0 and world.migrations == 2, "Back in the Verdant Maw, apex waits again")
	world.model.elapsed = world.apex_due
	_steps(TUNING.APEX_WARNING_SECONDS + 0.3)
	var moos: Variant = world.apex
	_check(moos is APEX and world.apex_loop() == 1, "The Moosschlund returns (loop %d, biome %s, state %d, pop %d, due %.1f, now %.1f)" % [world.apex_loop(), world.biome_id, world.apex_state, world.model.population, world.apex_due, world.model.elapsed])
	if moos is APEX:
		_check(is_equal_approx(moos.max_health, TUNING.APEX_HEALTH * TUNING.APEX_LOOP_HEALTH * world.world_scale()), "Loop 2 Moosschlund: HP x%.1f (%.0f)" % [TUNING.APEX_LOOP_HEALTH, moos.max_health])
		_check(is_equal_approx(float(moos.get_meta("damage_scale")), TUNING.APEX_LOOP_DAMAGE * TUNING.APEX_DAMAGE_MULTIPLIER), "Loop 2 Moosschlund: losses x%.2f (x apex multiplier)" % TUNING.APEX_LOOP_DAMAGE)
		moos.state = APEX.State.CHASE
		moos.cooldown = 999.0
		moos.phase = 2
		moos.health = 0.5
		moos.position = swarm.position + Vector3(0, 0, -(moos.body_radius + 0.5))
		world.unit_points_valid = false
		_steps(0.3)
		_check(world.apex == null and world.apex_kills == 3, "Loop 2 Moosschlund falls")
		var moss_corpses := 0
		for id in world.corpse_kinds:
			if world.corpse_kinds[id] == "apex":
				moss_corpses += 1
		_check(moss_corpses >= 1 and world.corpse_kinds[world.remains_order[-1]] == "apex", "Moosschlund leaves its own corpse design")
		_steps(TUNING.APEX_PORTAL_DELAY + 0.2)
		_check(world.portal != null and String(world.portal.target_biome) == "duerrschlund", "... and the circle goes on to the Dürrschlund")
		_migrate()
		world.model.elapsed = world.apex_due
		_steps(TUNING.APEX_WARNING_SECONDS + 0.3)
		var second: Variant = world.apex
		_check(second is SANDWORM and is_equal_approx(second.max_health, TUNING.APEX_SANDWORM_HEALTH * TUNING.APEX_LOOP_HEALTH * world.world_scale()), "Loop 2 Sandwurm: HP x%.1f (biome %s, state %d, pop %d, hp %.0f)" % [TUNING.APEX_LOOP_HEALTH, world.biome_id, world.apex_state, world.model.population, second.max_health if second != null else -1.0])


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
