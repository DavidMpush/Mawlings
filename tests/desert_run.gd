extends SceneTree

# Stage 19 phase 2: the Dürrschlund inside a real run (HuntWorld).
#   - migration order Verdant Maw -> Dürrschlund -> Glutsumpf (desert map, look,
#     SandPortal maw), menu/meta: trophy "Sandwurm bezwungen", biome unlock
#   - the Sandwurm rises APEX_ARRIVAL_DELAY after the arrival (warning, boss
#     music, APEX_SANDWORM_HEALTH), breakthrough and tail sweep hit per animal
#   - sand grubs from the worm (take_grubs) and as a rare ambush: bite through
#     the Moorbrut path, die to melee, pay out as crystals
#   - death: apex_sandworm corpse, boss cocoon, Migrationsschlund to the Glutsumpf
#   - quicksand slows the swarm (walkable, never lethal), sandstorm waves
#     (hint, edge veil, enemies faster, never the swarm)

const TUNING = preload("res://scripts/tuning.gd")
const BIOMES = preload("res://scripts/biomes.gd")
const WORM = preload("res://scripts/apex_sandworm.gd")
const PROFILE = preload("res://scripts/meta/profile.gd")
const DATA = preload("res://scripts/meta/meta_data.gd")
const DT := 1.0 / 60.0
const SEED := 4242

var failures: Array[String] = []
var scene: Node
var world: Variant
var swarm: Variant
var arena: Variant


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	arena = scene.get_node("Arena")
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)
	arena.set_seed(SEED)
	_check_order()
	_check_worm_arrival()
	_check_breach_per_animal()
	_check_grubs()
	_check_ambush()
	_check_death()
	_check_quicksand()
	_check_sandstorm()
	_check_meta()
	arena.set_seed(0)
	scene.queue_free()
	await process_frame
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS desert_run: Verdant -> Dürrschlund -> Glutsumpf (desert map + SandPortal maw), Sandwurm %.0f s after arrival (%.0f HP), breakthrough + sweep per animal, grubs (worm + ambush) bite and pay, corpse + boss cocoon + maw, quicksand x%.2f, sandstorm x%.2f, trophy + unlock" % [TUNING.APEX_ARRIVAL_DELAY, TUNING.APEX_SANDWORM_HEALTH, TUNING.QUICKSAND_SLOW, TUNING.SANDSTORM_ENEMY_HASTE])
	quit(0)


func _fresh(population: int, elapsed: float) -> void:
	world.config = {}
	world.reset_run()
	world.model.population = population
	swarm.set_population(population, false)
	world.model.elapsed = elapsed
	world.hunters_unlocked = true
	for clock in ["hunter_clock", "skitter_clock", "leaper_clock", "elite_clock", "nest_clock", "boss_clock", "flood_wave_clock"]:
		world.set(clock, 999.0)
	world.flood_start = 100000.0
	for target in world.prey:
		target.queue_free()
	world.prey.clear()
	world.spawn_clock = -999.0
	_spread()


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


func _migrate() -> void:
	var maw: Variant = world.portal
	if maw == null:
		failures.append("No maw to migrate through")
		return
	_steps(1.3)
	swarm.position = maw.position
	world.unit_points_valid = false
	_steps(TUNING.MIGRATION_HOLD_SECONDS + TUNING.MIGRATION_TRANSITION_SECONDS + 0.3)
	arena.finish_rebuild()


# Verdant -> Dürrschlund -> Glutsumpf -> Verdant.
func _check_order() -> void:
	_check(BIOMES.ORDER == ["verdant_maw", "duerrschlund", "glutsumpf"], "Biome order Verdant -> Dürrschlund -> Glutsumpf")
	_check(world.apex_kind_for("duerrschlund") == "apex_sandworm" and world.apex_kind_for("glutsumpf") == "apex_toad" and world.apex_kind_for("verdant_maw") == "apex", "Apex per biome")
	_fresh(50, 300.0)
	world.apex_state = 3
	var maw: Variant = world.open_portal(swarm.position + Vector3(0, 0, -10))
	_check(maw != null and maw.target_biome == "duerrschlund" and String(maw.lip.name) == "Lip", "Verdant maw (pit) leads into the Dürrschlund")
	_migrate()
	_check(world.biome_id == "duerrschlund" and arena.biome_id == "duerrschlund" and world.migrations == 1, "Arrived in the Dürrschlund")
	_check(arena._desert_look() and arena.layout != null and bool(arena.layout.desert), "Desert map and look")
	_check(arena.quicksand_patches().size() >= 5, "Quicksand on the desert map (%d)" % arena.quicksand_patches().size())
	var desert_ground := false
	for key in arena.chunks:
		var ground: Node = arena.chunks[key].get_node_or_null("Open ground")
		if ground != null and ground.material_override == arena.desert_ground_tint_material:
			desert_ground = true
	_check(desert_ground, "Desert shader ground")
	world.apex_state = 3
	var desert_maw: Variant = world.open_portal(swarm.position + Vector3(0, 0, -10))
	_check(desert_maw != null and desert_maw.target_biome == "glutsumpf" and String(desert_maw.lip.name) == "Sand lip", "Desert maw = SandPortal, leads to the Glutsumpf")
	_migrate()
	_check(world.biome_id == "glutsumpf" and not arena._desert_look(), "On to the Glutsumpf")
	_check(world.desert.grubs.count() == 0 and is_equal_approx(arena.enemy_haste, 1.0), "Desert effects stay in the desert")
	world.apex_state = 3
	var glut_maw: Variant = world.open_portal(swarm.position + Vector3(0, 0, -10))
	_check(glut_maw != null and glut_maw.target_biome == "verdant_maw", "Glutsumpf leads back to the Verdant Maw")


func _arrive_in_desert(population: int) -> void:
	_fresh(population, 300.0)
	world.apex_state = 3
	world.open_portal(swarm.position + Vector3(0, 0, -10))
	_migrate()
	world.desert.storm.force(9999.0)
	world.desert.ambush_clock = 9999.0
	_spread()


func _check_worm_arrival() -> void:
	_arrive_in_desert(60)
	_check(world.biome_id == "duerrschlund" and world.apex_state == 0, "Desert: apex waits after the arrival")
	var arrival: float = world.apex_due - TUNING.APEX_ARRIVAL_DELAY
	_check(absf(arrival - world.model.elapsed) < 1.0, "Sandwurm due %.0f s after the arrival" % TUNING.APEX_ARRIVAL_DELAY)
	world.model.elapsed = world.apex_due + 0.05
	_steps(0.1)
	_check(world.apex_state == 1 and world.apex_kind == "apex_sandworm", "Ground warning for the Sandwurm (state %d, kind %s)" % [world.apex_state, world.apex_kind])
	_check(String(world.hud.hint).contains("SANDWURM"), "Warning hint names the Sandwurm ('%s')" % world.hud.hint)
	_steps(TUNING.APEX_WARNING_SECONDS + 0.1)
	var worm: Variant = world.apex
	_check(worm != null and worm is WORM and world.apex_state == 2, "The Sandwurm rises in the Dürrschlund")
	if worm == null:
		return
	_check(_apex_hp_ok(worm.max_health, TUNING.APEX_SANDWORM_HEALTH * world.world_scale()), "APEX_SANDWORM_HEALTH x world bonus (%.0f)" % worm.max_health)
	var objectives: Dictionary = world.hud.get_meta("objectives")
	_check(String(objectives.apex_name) == "SANDWURM", "HUD names the Sandwurm")
	var music: Variant = scene.get_node_or_null("Music")
	if music != null:
		_check(music.last_stinger() == "boss", "Boss stinger for the Sandwurm")
	# Population gate: a small swarm waits (at the latest APEX_LATEST_EXTRA).
	_arrive_in_desert(12)
	world.model.elapsed = world.apex_due + 1.0
	_steps(0.2)
	_check(world.apex_state == 0, "Small swarm (%d < %d): the worm waits" % [world.model.population, TUNING.APEX_SANDWORM_MIN_POPULATION])


# A quiet worm (buried, long cooldown) far from the swarm.
func _quiet_worm() -> Variant:
	var worm: Variant = world.spawn_apex(swarm.position + Vector3(0, 0, -14), "apex_sandworm")
	worm.state = WORM.State.CHASE
	worm.remaining = 0.0
	worm.cooldown = 999.0
	world.unit_points_valid = false
	return worm


# Steps until the worm's strike resolves: [lost, expected, followers inside, points].
func _strike_tick() -> Array:
	var worm: Variant = world.apex
	for frame in 240:
		var points: PackedVector3Array = swarm.unit_world_points()
		var before: int = world.model.population
		world.unit_points_valid = false
		world.model.leader_invulnerable = 99.0
		world.step(DT)
		var power: int = worm.resolved_power
		if power > 0:
			var inside := 0
			for index in range(1, points.size()):
				if worm.contains(points[index]):
					inside += 1
			var expected := ceili(float(power) * float(inside) / float(points.size()) - 0.0001)
			# Etappe 26: the world bonus (difficulty_scale) scales every area loss.
			var scale: float = world.difficulty_scale(world.enemy_damage)
			if expected > 0 and scale != 1.0:
				expected = maxi(1, ceili(float(expected) * scale))
			worm.cooldown = 999.0
			return [before - world.model.population, mini(expected, before - 1), inside, points.size()]
	return [-1, -1, 0, 0]


func _check_breach_per_animal() -> void:
	_arrive_in_desert(60)
	var worm: Variant = _quiet_worm()
	# Breakthrough right under the swarm: every follower inside.
	worm.begin_attack(WORM.Pattern.BREACH, swarm.position, 1.0)
	var full := _strike_tick()
	_check(full[0] > 0 and full[0] == full[1] and full[2] == full[3] - 1, "Breakthrough under the swarm: all inside, loss %d = %d (%d of %d)" % [full[0], full[1], full[2], full[3]])
	_steps(6.0)
	worm.state = WORM.State.CHASE
	worm.cooldown = 999.0
	_spread()
	# Breakthrough at the rim: only the animals in the ring fall.
	world.model.population = 60
	swarm.set_population(60, false)
	_spread()
	worm.begin_attack(WORM.Pattern.BREACH, swarm.position + Vector3(6.2, 0, 0), 1.0)
	var part := _strike_tick()
	_check(part[2] > 0 and part[2] < part[3] - 1 and part[0] == part[1] and part[0] < full[0], "Rim breakthrough per animal (%d inside of %d, loss %d = %d)" % [part[2], part[3], part[0], part[1]])
	_steps(6.0)
	worm.state = WORM.State.CHASE
	worm.cooldown = 999.0
	# Dodged: nothing falls.
	world.model.population = 60
	swarm.set_population(60, false)
	_spread()
	worm.begin_attack(WORM.Pattern.BREACH, swarm.position + Vector3(14, 0, 0), 1.0)
	var dodged := _strike_tick()
	_check(dodged[0] == 0 and dodged[2] == 0, "Breakthrough beside the swarm costs nothing (%d)" % dodged[0])
	_steps(6.0)
	worm.state = WORM.State.CHASE
	worm.cooldown = 999.0
	# Tail sweep: a cone through the swarm, loss per animal inside.
	world.model.population = 60
	swarm.set_population(60, false)
	_spread()
	worm.begin_attack(WORM.Pattern.SWEEP, swarm.position, 1.0)
	var sweep := _strike_tick()
	_check(sweep[2] > 0 and sweep[0] == sweep[1], "Tail sweep per animal (%d inside, loss %d = %d)" % [sweep[2], sweep[0], sweep[1]])


func _check_grubs() -> void:
	_arrive_in_desert(60)
	var worm: Variant = _quiet_worm()
	# Phase two releases grubs; HuntWorld takes them (take_grubs) into the desert brood.
	worm.health = worm.max_health * 0.45
	worm.take_damage(1.0)
	var spawned_before: int = world.desert.grubs_spawned
	_steps(0.5)
	_check(world.desert.grubs_spawned > spawned_before and world.desert.grubs.count() > 0, "Worm grubs appear (%d)" % world.desert.grubs.count())
	_check(worm.take_grubs().is_empty(), "Grub queue drained by HuntWorld")
	_check(world.attack_forms == null or world.attack_forms.horde == world.desert.brood, "Attack forms see horde + grubs")
	# Grubs run in and bite through the brood path; the swarm bites back.
	world.apex.position = swarm.position + Vector3(0, 0, -40)
	world.apex.cooldown = 999.0
	# The flow field (arena.sync in a real frame) guides grubs around walls.
	arena.finish_flow(swarm.position)
	var population_before: int = world.model.population
	var kills_before: int = int(world.model.kills_by_type.get("sandgrub", 0))
	for frame in 600:
		if world.choosing():
			world.choose_mutation(0)
		world.model.leader_invulnerable = 99.0
		world.apex.cooldown = 999.0
		world.step(DT)
		if world.desert.grubs.count() == 0:
			break
	_check(int(world.desert.grubs.total_bites) > 0, "Grubs bite (%d bites)" % int(world.desert.grubs.total_bites))
	_check(world.model.population < population_before or world.desert.grubs.total_bites == 0, "Grub bites cost animals")
	_check(int(world.model.kills_by_type.get("sandgrub", 0)) > kills_before and world.desert.grub_kills > 0, "Grubs die to melee (%d)" % world.desert.grub_kills)
	_steps(0.5)
	_check(world.flood_bundles.is_empty(), "Grub kills paid out as crystals (bundles flushed)")


func _check_ambush() -> void:
	_arrive_in_desert(40)
	world.desert.ambush_clock = 0.0
	_steps(0.1)
	var count: int = world.desert.grubs.count()
	_check(world.desert.ambushes == 1 and count >= TUNING.SANDGRUB_AMBUSH_MIN and count <= TUNING.SANDGRUB_AMBUSH_MAX, "Rare ambush: a small grub group (%d)" % count)
	_check(world.desert.ambush_clock > 10.0, "Next ambush far off (%.0f s)" % world.desert.ambush_clock)
	# Small swarms are spared.
	_arrive_in_desert(TUNING.SANDGRUB_MIN_POPULATION - 3)
	world.desert.ambush_clock = 0.0
	_steps(0.2)
	_check(world.desert.grubs.count() == 0, "No ambush on a tiny swarm")


func _check_death() -> void:
	_arrive_in_desert(60)
	world.apex_spawned = 1
	var worm: Variant = _quiet_worm()
	var cocoons_before: int = world.chests.closed_count("boss") if world.chests != null else 0
	# Phase two already reached (no rage at the last hit), lying exhausted.
	worm.phase = 2
	worm.state = WORM.State.EXHAUSTED
	worm.remaining = 5.0
	worm.health = 0.5
	worm.position = swarm.position + Vector3(0, 0, -(worm.body_radius + 0.5))
	world.unit_points_valid = false
	world.evolution.ranks["bite"] = 3
	_steps(0.4)
	_check(world.apex == null and world.apex_state == 3 and world.worm_kills == 1, "Sandwurm kill resolves once (state %d, worm kills %d)" % [world.apex_state, world.worm_kills])
	var corpses := 0
	for id in world.corpse_kinds:
		if world.corpse_kinds[id] == "apex_sandworm":
			corpses += 1
	_check(corpses == 1, "One apex_sandworm corpse (%d)" % corpses)
	if world.chests != null:
		_check(world.chests.closed_count("boss") == cocoons_before + 1, "Boss cocoon dropped")
	_check(String(world.hud.get_meta("objectives").apex_name) == "SANDWURM", "Victory banner names the Sandwurm")
	_steps(TUNING.APEX_PORTAL_DELAY + 0.3)
	_check(world.portal != null and world.portal.target_biome == "glutsumpf" and String(world.portal.lip.name) == "Sand lip", "SandPortal maw to the Glutsumpf behind the worm")
	var stats: Dictionary = world.run_stats()
	_check(int(stats.worm_kills) == 1 and int(stats.apex_kills) == 1, "RunStats: worm_kills 1")


func _check_quicksand() -> void:
	_arrive_in_desert(30)
	var patches: Array = arena.quicksand_patches()
	if patches.is_empty():
		failures.append("No quicksand patch")
		return
	var patch: Vector4 = patches[0]
	var middle := Vector3(patch.x, 0.0, patch.z)
	swarm.position = middle
	swarm.movement_vector = Vector2(1, 0)
	var start: Vector3 = swarm.position
	swarm._process(0.05)
	var slow: float = swarm.position.distance_to(start)
	var firm_spot := Vector3(patch.x + patch.w + 6.0, 0.0, patch.z)
	firm_spot = arena.safe_spawn(firm_spot, 1.0)
	swarm.position = firm_spot
	start = swarm.position
	swarm._process(0.05)
	var fast: float = swarm.position.distance_to(start)
	swarm.movement_vector = Vector2.ZERO
	_check(slow > 0.0 and slow < fast * 0.6, "Quicksand slows the swarm (%.3f vs %.3f m)" % [slow, fast])
	# Walkable and never lethal: a long stay costs nothing.
	swarm.position = middle
	world.unit_points_valid = false
	var before: int = world.model.population
	_steps(3.0)
	_check(world.model.population >= before, "Quicksand never kills")
	_check(String(world.hud.hint).begins_with("TREIBSAND"), "Hint in the quicksand ('%s')" % world.hud.hint)


func _check_sandstorm() -> void:
	_arrive_in_desert(30)
	var storm: Variant = world.desert.storm
	storm.force(0.0)
	_steps(0.2)
	_check(storm.state == storm.State.WARNING and String(world.hud.hint).begins_with("SANDSTURM"), "Storm announced ('%s')" % world.hud.hint)
	_steps(TUNING.SANDSTORM_WARNING + 1.8)
	_check(storm.blowing() and storm.waves == 1 and storm.strength > 0.9, "Storm blows (strength %.2f)" % storm.strength)
	_check(is_equal_approx(arena.enemy_haste, TUNING.SANDSTORM_ENEMY_HASTE), "Enemies faster in the storm")
	var hunter_step: Vector3 = arena.resolve_motion(swarm.position, Vector3(0.1, 0, 0), 0.8)
	var swarm_step: Vector3 = arena.resolve_motion(swarm.position, Vector3(0.1, 0, 0), 0.75)
	var hunter_moved: float = hunter_step.distance_to(swarm.position)
	var swarm_moved: float = swarm_step.distance_to(swarm.position)
	_check(hunter_moved > swarm_moved * 1.1, "A hunter moves faster than the swarm (%.3f vs %.3f)" % [hunter_moved, swarm_moved])
	# The veil lies on the edges: the middle of the screen stays clear.
	var veil: ColorRect = storm._veil
	_check(veil != null and veil.visible and float(veil.material.get_shader_parameter("inner")) >= 0.6, "Edge veil visible, centre clear")
	_steps(TUNING.SANDSTORM_SECONDS + TUNING.SANDSTORM_FADE + 0.5)
	_check(storm.state == storm.State.CALM and is_equal_approx(arena.enemy_haste, 1.0) and not veil.visible, "Storm passes, calm again")
	_check(storm.clock >= TUNING.SANDSTORM_INTERVAL.x - 1.0, "Next storm %.0f-%.0f s later (%.0f)" % [TUNING.SANDSTORM_INTERVAL.x, TUNING.SANDSTORM_INTERVAL.y, storm.clock])


func _check_meta() -> void:
	var path := "user://desert_run_test_profile.json"
	var profile: Variant = PROFILE.load_or_create(path)
	_check(not profile.is_biome_unlocked("duerrschlund"), "Dürrschlund locked on a fresh profile")
	var outcome: Dictionary = profile.record_run({"apex_kills": 2, "worm_kills": 1, "toad_kills": 0, "biome_seconds": {"duerrschlund": 90.0}})
	_check(profile.quest_value("total_worms") == 1.0 and outcome.new_quests.has("apex_sandwurm"), "Trophy Sandwurm bezwungen")
	_check(profile.quest_value("total_moss") == 1.0 and profile.is_biome_unlocked("duerrschlund"), "Moosschlund victory unlocks the Dürrschlund")
	_check(not DATA.quest("apex_sandwurm").is_empty() and DATA.BIOME_ORDER.has("duerrschlund"), "Trophy and biome in meta_data")
	var config: Dictionary = profile.build_run_config(DATA.STRAIN_ORDER[0], "duerrschlund", 0)
	_check(String(config.biome_id) == "duerrschlund", "A run can start in the Dürrschlund once unlocked")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

# Etappe 30: apex HP = max(base formula, APEX_KING_RATIO x a Bog King now) (2 % slack:
# the pressure moved a little since the spawn).
func _apex_hp_ok(value: float, base: float) -> bool:
	var expected := maxf(base, TUNING.APEX_KING_RATIO * float(world.bog_king_health()))
	return absf(value - expected) <= expected * 0.02 or (value >= base - 0.5 and value <= expected * 1.02 and value >= expected * 0.9)
