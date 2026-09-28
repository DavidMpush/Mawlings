extends SceneTree

# Stage 10: the Migrationsschlund. Opening and hold rule (>= 60 % of the swarm
# for 1 s, leaving drains it), the swirl transition (world holds still, pause
# freezes it), the biome switch (arena, sun light, enemy tints, eruptions active,
# safe arrival), everything that must carry over (population, build, time,
# flood) and reset (also in the middle of the transition).

const TUNING = preload("res://scripts/tuning.gd")
const BIOMES = preload("res://scripts/biomes.gd")
const HUNTER = preload("res://scripts/hunter.gd")
const PROFILE = preload("res://scripts/meta/profile.gd")
const DT := 1.0 / 60.0
var failures: Array[String] = []
var scene: Node
var world: Variant
var swarm: Variant
var arena: Variant
var sun: DirectionalLight3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	arena = scene.get_node("Arena")
	sun = scene.get_node("Sun")
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)
	_check_hold_rule()
	_check_transition()
	_check_reset()
	_check_reset_mid_transition()
	_check_start_biome()
	scene.queue_free()
	await process_frame
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS migration: hold 60 %% / 1 s, swirl %.1f s (world still, pause-proof), biome + light + tints + eruptions, safe arrival, build/population/flood kept, reset (also mid-swirl), start biome from config" % TUNING.MIGRATION_TRANSITION_SECONDS)
	quit(0)


func _fresh(population: int) -> void:
	world.config = {}
	world.reset_run()
	world.model.population = population
	swarm.set_population(population, false)
	world.model.elapsed = 320.0
	world.hunters_unlocked = true
	world.hunter_clock = 999.0
	world.skitter_clock = 999.0
	world.leaper_clock = 999.0
	world.elite_clock = 999.0
	world.nest_clock = 999.0
	world.boss_clock = 999.0
	world.apex_state = 3
	world.flood_wave_clock = 999.0
	for target in world.prey:
		target.queue_free()
	world.prey.clear()
	world.spawn_clock = -999.0
	swarm.position = Vector3(0, 0, 30)
	arena.sync(swarm.position)
	world.unit_points_valid = false


func _steps(seconds: float) -> void:
	for index in int(ceil(seconds / DT)):
		if world.choosing():
			world.choose_mutation(0)
		world.step(DT)


func _move_swarm(to: Vector3) -> void:
	swarm.position = to
	world.unit_points_valid = false


func _check_hold_rule() -> void:
	_fresh(40)
	var maw: Variant = world.open_portal(Vector3(0, 0, 44))
	_check(maw != null and maw.target_biome == "duerrschlund", "Verdant leads to the Dürrschlund (stage 19 order)")
	_steps(1.5)
	_check(maw.opened >= 1.0 and maw.hold == 0.0 and world.migration_state == 0, "Opens and waits while nobody enters")
	# Only the edge of the swarm touches it: less than 60 % inside.
	_move_swarm(maw.position + Vector3(TUNING.MIGRATION_RADIUS + 1.2, 0, 0))
	_steps(0.5)
	var partial: float = maw.hit_fraction(swarm.unit_world_points())
	_check(partial < TUNING.MIGRATION_SHARE and maw.hold == 0.0, "Brushing the maw (%.0f %%) never migrates" % (partial * 100.0))
	_move_swarm(maw.position)
	_steps(0.5)
	_check(maw.hold > 0.4 and maw.hold < 0.6 and world.migration_state == 0, "Half a second inside = half the hold (%.2f)" % maw.hold)
	var objectives: Dictionary = world.hud.get_meta("objectives")
	_check(absf(float(objectives.portal_hold) - maw.hold) < 0.001 and String(world.hud.hint).begins_with("MIGRATION"), "HUD shows the hold")
	_move_swarm(maw.position + Vector3(12, 0, 0))
	_steps(0.25)
	_check(maw.hold < 0.1, "Leaving drains the hold twice as fast (%.2f)" % maw.hold)
	_steps(3.0)
	_check(world.portal == maw and world.migration_state == 0, "Ignoring the maw is allowed; it stays")


func _check_transition() -> void:
	_fresh(40)
	# Stage 19: the Glutsumpf now lies behind the Dürrschlund.
	world._set_world_biome("duerrschlund", false)
	arena.finish_rebuild()
	_move_swarm(Vector3(0, 0, 30))
	var desert_maw_ok := false
	world.evolution.ranks["bite"] = 2
	world.flood_state = 2
	world.flood_start = 300.0
	var ranks_before: Dictionary = world.evolution.ranks.duplicate()
	var population_before: int = world.model.population
	var peak_before: int = world.model.peak_population
	var level_before: float = world.flood_level()
	var prey_before: Node3D = null
	world._spawn_prey(Vector3(4, 0, 36))
	prey_before = world.prey[-1]
	var maw: Variant = world.open_portal(Vector3(0, 0, 40))
	desert_maw_ok = maw.target_biome == "glutsumpf" and maw.source_biome == "duerrschlund" and maw.lip != null and String(maw.lip.name) == "Sand lip"
	_check(desert_maw_ok, "The Dürrschlund maw is the SandPortal and leads to the Glutsumpf")
	_steps(1.3)
	_move_swarm(maw.position)
	var elapsed_before: float = world.model.elapsed
	_steps(TUNING.MIGRATION_HOLD_SECONDS + 0.05)
	_check(world.migrating(), "Holding 1 s inside starts the migration")
	var elapsed_frozen: float = world.model.elapsed
	var timer_before: float = world.migration_timer
	world.toggle_pause()
	_steps(1.0)
	_check(world.migration_timer == timer_before and arena.biome_id == "duerrschlund", "Pause freezes the swirl")
	world.toggle_pause()
	var objectives: Dictionary = world.hud.get_meta("objectives")
	_check(float(objectives.migration) >= 0.0 and String(objectives.migration_to) == "glutsumpf", "HUD gets the swirl progress")
	_steps(TUNING.MIGRATION_SWITCH_AT + 0.02)
	var arrival: Vector3 = Vector3(swarm.position.x, 0, swarm.position.z)
	_check(arena.biome_id == "glutsumpf" and world.biome_id == "glutsumpf", "Biome switches behind the swirl")
	_check(world.model.elapsed == elapsed_frozen, "The world holds still during the swirl")
	var light: Dictionary = BIOMES.get_data("glutsumpf").light
	_check(sun.light_color == light.color and is_equal_approx(sun.light_energy, light.energy), "Sun takes the Glutsumpf light")
	_check(world.eruptions != null and world.eruptions.active(), "Eruptions are active")
	var safe := false
	for zone in world.eruptions.safe_zones:
		if Vector2(zone.x - maw.position.x, zone.z - maw.position.z).length() < 0.5 and zone.w >= TUNING.MIGRATION_SAFE_RADIUS:
			safe = true
	_check(safe, "Arrival spot is a safe zone")
	_check(world.model.leader_invulnerable > 0.0, "Leader grace on arrival")
	var tint: Color = BIOMES.enemy_tint("glutsumpf", "prey")
	_check(is_instance_valid(prey_before) and prey_before.material.get_shader_parameter("body_tint") == tint, "Living Nibbler takes the biome tint")
	_steps(TUNING.MIGRATION_TRANSITION_SECONDS)
	_check(world.migration_state == 2 and world.portal == null and not world.migrating(), "Swirl opens, the maw is gone")
	_check(world.model.elapsed > elapsed_frozen and elapsed_frozen > elapsed_before, "Run time carries on after the swirl")
	_check(world.model.population == population_before and world.model.peak_population == peak_before, "Population kept (%d)" % world.model.population)
	_check(world.evolution.ranks == ranks_before, "Build kept")
	_check(world.flood_state == 2 and world.flood_level() >= level_before, "Flood keeps running")
	# New hunters wear the Glutsumpf tint (shared tinted material, no explosion).
	var hunter: Variant = world._spawn_hunter(arrival + Vector3(9, 0, 0))
	var tinted := 0
	var materials := {}
	var second: Variant = world._spawn_hunter(arrival + Vector3(-9, 0, 0))
	# Beetle hunters carry a creature-shader skin (body_tint uniform); the
	# primitive fallback swaps to shared tinted StandardMaterials.
	var skinned := 0
	for target in [hunter, second]:
		if target.skin != null and (target.skin.get_shader_parameter("body_tint") as Color).a > 0.0:
			skinned += 1
		for mesh in target.find_children("*", "MeshInstance3D", true, false):
			if mesh.has_meta("base_material") and mesh.material_override != mesh.get_meta("base_material"):
				tinted += 1
				materials[mesh.material_override.get_instance_id()] = true
	_check(skinned == 2 or (tinted >= 4 and materials.size() <= 3), "Hunters tinted (%d skins, %d parts, %d materials)" % [skinned, tinted, materials.size()])
	# Safe arrival: eruptions never pick a source inside the arrival zone.
	_move_swarm(arrival)
	world.eruptions.erupt_soon()
	var near := false
	for index in 600:
		world.model.leader_invulnerable = 1.0
		world.step(DT)
		for eruption in world.eruptions.pending:
			if Vector2(eruption.center.x - arrival.x, eruption.center.z - arrival.z).length() < TUNING.MIGRATION_SAFE_RADIUS:
				near = true
	_check(not near, "No eruption inside the arrival zone")
	var stats: Dictionary = world.run_stats()
	_check(int(stats.biomes_visited) == 3 and int(stats.migrations) == 1 and float(stats.biome_seconds.get("glutsumpf", 0.0)) > 5.0, "RunStats: biomes_visited 3, migrations 1, Glutsumpf seconds")
	# Trophies: the profile books migrations, apex kills and seconds per biome.
	var path := "user://migration_test_profile.json"
	var profile: Variant = PROFILE.load_or_create(path)
	stats["apex_kills"] = 1
	stats["biome_seconds"] = {"glutsumpf": 130.0, "verdant_maw": 200.0}
	var outcome: Dictionary = profile.record_run(stats)
	_check(profile.quest_value("total_migrations") == 1.0 and profile.quest_value("total_apex") == 1.0 and profile.quest_value("biome_time:glutsumpf") == 130.0, "Profile records apex, migration and Glutsumpf time")
	_check(outcome.new_quests.has("apex_moosschlund") and outcome.new_quests.has("migration_1") and outcome.new_quests.has("glutsumpf_2"), "Trophies Moosschlund / Migration / Glutherz complete")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check_reset() -> void:
	world.reset_run()
	var light: Dictionary = BIOMES.get_data("verdant_maw").light
	_check(arena.biome_id == "verdant_maw" and world.biome_id == "verdant_maw" and sun.light_color == light.color and is_equal_approx(sun.light_energy, light.energy), "Reset returns to Verdant Maw and its light")
	_check(world.portal == null and world.migration_state == 0 and world.apex_state == 0 and world.biomes_visited.size() == 1 and not world.eruptions.active(), "Reset clears maw, migration and eruptions")
	arena.finish_rebuild()


func _check_reset_mid_transition() -> void:
	_fresh(40)
	var maw: Variant = world.open_portal(Vector3(0, 0, 40))
	_steps(1.3)
	_move_swarm(maw.position)
	_steps(TUNING.MIGRATION_HOLD_SECONDS + 0.05 + TUNING.MIGRATION_SWITCH_AT + 0.05)
	_check(world.migrating() and arena.biome_id == "duerrschlund", "Mid-swirl state reached")
	world.reset_run()
	_steps(0.2)
	_check(not world.migrating() and arena.biome_id == "verdant_maw" and world.portal == null and world.model.elapsed < 1.0, "Reset in the middle of the swirl is clean")


func _check_start_biome() -> void:
	world.config = {"biome_id": "glutsumpf"}
	world.reset_run()
	_check(arena.biome_id == "glutsumpf" and world.biome_id == "glutsumpf", "A run configured for the Glutsumpf starts there")
	world.apex_state = 3
	var maw: Variant = world.open_portal(Vector3(0, 0, -20))
	_check(maw.target_biome == "verdant_maw", "Glutsumpf leads back to the Verdant Maw (endless order)")
	world.config = {}
	world.reset_run()
	_check(arena.biome_id == "verdant_maw", "Back to the default biome")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
