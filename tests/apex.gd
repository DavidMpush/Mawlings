extends SceneTree

# Stage 07 APEX building blocks: Moosschlund (scripts/apex_boss.gd) and the
# biome data (scripts/biomes.gd + Arena.set_biome). The run integration is
# checked in tests/apex_run.gd and tests/migration.gd (stage 10).

const APEX = preload("res://scripts/apex_boss.gd")
const BIOMES = preload("res://scripts/biomes.gd")
const TUNING = preload("res://scripts/tuning.gd")
const SWARM_SPEED := 7.0
# Share of the wind-up the player may lose to reaction time before moving.
const REACTION := 0.45
var failures: Array[String] = []
var defeated_at: Variant = null


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_boss_flow()
	_check_patterns()
	_check_dodgeable()
	_check_phase_two()
	_check_death_and_pause()
	_check_colorblind()
	await _check_biomes()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS apex: arrival, cycle, telegraph before damage, roots/spores/quake dodge, partial hits, exhaustion, phase 2, migration_ready, pause, colour-blind, biomes (verdant exact, glutsumpf, layout stable)")
	quit(0)


func _spawn() -> Variant:
	var main := Node3D.new()
	main.name = "Main"
	root.add_child(main)
	var world := Node3D.new()
	world.name = "World"
	main.add_child(world)
	var boss: Variant = APEX.new()
	world.add_child(boss)
	return boss


func _free(boss: Variant) -> void:
	boss.get_parent().get_parent().free()


func _ready_boss() -> Variant:
	var boss: Variant = _spawn()
	boss.state = APEX.State.CHASE
	boss.cooldown = 99.0
	boss.refresh_pose()
	return boss


# Steps through a full wind-up; returns [first non-zero result, time of it].
func _run_windup(boss: Variant, swarm: Vector3, pressure: float = 1.0) -> Array:
	var elapsed := 0.0
	var dt := 1.0 / 60.0
	while boss.state == APEX.State.WINDUP and elapsed < 10.0:
		var result: int = boss.step(dt, swarm, pressure)
		elapsed += dt
		if boss.resolved_power > 0:
			return [result, elapsed]
	return [0, elapsed]


func _check_boss_flow() -> void:
	var boss: Variant = _spawn()
	_check(boss.state == APEX.State.ARRIVING and boss.max_health >= 2.5 * TUNING.BOSS_HEALTH, "Apex arrives with far more (base) health than the Bog King")
	_check(boss.model.scale.x > 7.0 and boss.crown != null and boss.sacs.size() >= 3, "Larger model with root crown and spore sacs")
	var before: float = boss.health
	boss.take_damage(50.0)
	_check(boss.health == before, "Immune while emerging")
	boss.step(APEX.ARRIVE_SECONDS + 0.01, Vector3(20, 0, 0), 1.0)
	_check(boss.state == APEX.State.CHASE, "Arrival ends in chase")
	var start: Vector3 = boss.position
	boss.cooldown = 99.0
	boss.step(0.5, Vector3(30, 0, 0), 1.0)
	_check(boss.position.x > start.x, "Chases the swarm")
	# Automatic cycle: roots, spores, quake.
	var seen: Array[int] = []
	var swarm := Vector3(8, 0, 0)
	boss.position = Vector3.ZERO
	for attack in 3:
		boss.cooldown = 0.0
		boss.step(0.01, swarm, 1.0)
		seen.append(boss.current_pattern)
		_check(boss.state == APEX.State.WINDUP and boss.warning.visible and boss.telegraphs.size() > 0, "Attack %d shows a telegraph" % attack)
		_run_windup(boss, Vector3(0, 0, 40))
		for i in 400:
			if boss.state == APEX.State.CHASE:
				break
			boss.step(1.0 / 60.0, boss.position + Vector3(4, 0, 0), 1.0)
		boss.position = Vector3.ZERO
	_check(seen == [APEX.Pattern.ROOTS, APEX.Pattern.SPORES, APEX.Pattern.QUAKE], "Phase 1 cycle roots-spores-quake")
	_free(boss)


func _check_patterns() -> void:
	# Roots: telegraph first, the whole wind-up passes before any loss.
	var boss: Variant = _ready_boss()
	var swarm := Vector3(8, 0, 0)
	boss.begin_attack(APEX.Pattern.ROOTS, swarm, 2.0)
	_check(boss.telegraphs.size() == APEX.ROOT_LANES[0], "Three root lanes announced")
	_check(boss.step(0.01, swarm, 2.0) == 0 and boss.resolved_power == 0, "No loss during root wind-up")
	var hit := _run_windup(boss, swarm, 2.0)
	_check(hit[0] == int(ceil(APEX.ROOT_DAMAGE * 2.0)) and hit[1] >= APEX.ROOT_WINDUP[0] - 0.02, "Root lane hits after full wind-up (ROOT_DAMAGE x pressure)")
	_check(boss.step(0.1, swarm, 2.0) == 0, "Roots resolve only once")
	boss.state = APEX.State.CHASE
	boss.begin_attack(APEX.Pattern.ROOTS, swarm, 1.0)
	var aside := swarm + Vector3(0, 0, 2.6)
	hit = _run_windup(boss, aside)
	_check(hit[0] == 0 and boss.resolved_power == int(ceil(APEX.ROOT_DAMAGE)), "Side step out of the lane avoids the loss")
	# Partial hit: half the units in the centre lane.
	var points := PackedVector3Array([swarm, swarm + Vector3(0, 0, 0.5), swarm + Vector3(0, 0, 2.4), swarm + Vector3(0, 0, -2.4)])
	_check(is_equal_approx(boss.hit_fraction(points), 0.5), "hit_fraction counts units inside the lanes")
	_free(boss)
	# Spores: hugging the boss or leaving the ring is safe.
	boss = _ready_boss()
	boss.begin_attack(APEX.Pattern.SPORES, swarm, 1.0)
	_check(boss.telegraphs.size() == 1 and not boss.contains(Vector3(2.5, 0, 0)) and boss.contains(Vector3(6, 0, 0)) and not boss.contains(Vector3(10, 0, 0)), "Spore ring: inside and outside are safe")
	hit = _run_windup(boss, Vector3(2.5, 0, 0))
	_check(hit[0] == 0 and boss.resolved_power == APEX.SPORE_DAMAGE, "Hugging the boss dodges the spores")
	points = PackedVector3Array([Vector3(3, 0, 0), Vector3(5, 0, 0), Vector3(6, 0, 0), Vector3(9.5, 0, 0)])
	_check(is_equal_approx(boss.hit_fraction(points), 0.5), "Spore ring partial hit")
	_free(boss)
	# Quake: islands are safe, the rest of the disc is not; exhaustion follows.
	boss = _ready_boss()
	boss.begin_attack(APEX.Pattern.QUAKE, swarm, 1.0)
	_check(boss.islands.size() == APEX.QUAKE_ISLANDS[0], "Quake has three safe islands")
	var island: Vector4 = boss.islands[0]
	var on_island := Vector3(island.x, 0, island.z)
	_check(not boss.contains(on_island) and boss.contains(swarm) and not boss.contains(Vector3(APEX.QUAKE_RADIUS[0] + 1.0, 0, 0)), "Quake: islands and outside safe, swarm spot not")
	hit = _run_windup(boss, on_island)
	_check(hit[0] == 0 and boss.resolved_power == APEX.QUAKE_DAMAGE, "Standing on an island dodges the quake")
	for i in 40:
		boss.step(1.0 / 60.0, on_island, 1.0)
	_check(boss.state == APEX.State.EXHAUSTED, "Quake leaves the boss exhausted")
	var health: float = boss.health
	boss.take_damage(10.0)
	_check(is_equal_approx(health - boss.health, 10.0 * APEX.EXHAUSTED_VULNERABILITY), "Exhausted boss takes bonus damage")
	boss.step(APEX.EXHAUSTED_SECONDS[0] + 0.01, on_island, 1.0)
	_check(boss.state == APEX.State.CHASE, "Exhaustion window ends")
	_free(boss)


# Every pattern in both phases leaves a safe spot the swarm can reach in time,
# from near, mid and far positions and several directions.
func _check_dodgeable() -> void:
	for phase in [1, 2]:
		for pattern in [APEX.Pattern.ROOTS, APEX.Pattern.SPORES, APEX.Pattern.QUAKE]:
			for distance in [4.5, 7.0, 10.0, 13.0]:
				for angle in [0.0, 1.3, 2.9]:
					var boss: Variant = _ready_boss()
					boss.phase = phase
					var swarm: Vector3 = Vector3(cos(angle), 0, sin(angle)) * distance
					boss.begin_attack(pattern, swarm, 1.0)
					var reach: float = boss.remaining * (1.0 - REACTION) * SWARM_SPEED
					var best := INF
					for x in range(-40, 41):
						for z in range(-40, 41):
							var point: Vector3 = swarm + Vector3(x * 0.5, 0, z * 0.5)
							# Keep 1 m clear so a clump of units fits, not only the centre.
							if _safe_with_margin(boss, point, 1.0):
								best = minf(best, point.distance_to(swarm))
					_check(best <= reach, "Pattern %s phase %d from %.1f m is dodgeable (%.1f m needed, %.1f m reachable)" % [APEX.pattern_name(pattern), phase, distance, best, reach])
					_free(boss)


func _safe_with_margin(boss: Variant, point: Vector3, margin: float) -> bool:
	for offset in [Vector3.ZERO, Vector3(margin, 0, 0), Vector3(-margin, 0, 0), Vector3(0, 0, margin), Vector3(0, 0, -margin)]:
		if boss.contains(point + offset):
			return false
	return true


func _check_phase_two() -> void:
	var boss: Variant = _ready_boss()
	var swarm := Vector3(8, 0, 0)
	boss.begin_attack(APEX.Pattern.ROOTS, swarm, 1.0)
	boss.step(0.5, swarm, 1.0)
	var changed := [0]
	boss.phase_changed.connect(func(value: int) -> void: changed[0] = value)
	boss.health = boss.max_health * 0.49
	var result: int = boss.step(0.01, swarm, 1.0)
	_check(boss.phase == 2 and boss.state == APEX.State.PHASE_SHIFT and changed[0] == 2, "Phase 2 at 50 % health")
	_check(result == 0 and boss.resolved_power == 0 and boss.telegraphs.is_empty(), "Phase change cancels the pending attack without loss")
	var health: float = boss.health
	boss.take_damage(40.0)
	_check(boss.health == health, "Immune while roaring")
	boss.step(APEX.PHASE_SHIFT_SECONDS + 0.01, swarm, 1.0)
	_check(boss.state == APEX.State.CHASE, "Roar ends in chase")
	boss.begin_attack(APEX.Pattern.ROOTS, swarm, 1.0)
	_check(boss.telegraphs.size() == APEX.ROOT_LANES[1] and boss.remaining == APEX.ROOT_WINDUP[1], "Phase 2 roots: more lanes, shorter wind-up")
	boss.state = APEX.State.CHASE
	boss.begin_attack(APEX.Pattern.QUAKE, swarm, 1.0)
	_check(boss.islands.size() == APEX.QUAKE_ISLANDS[1] and boss.quake_radius == APEX.QUAKE_RADIUS[1], "Phase 2 quake: bigger, fewer islands")
	_free(boss)


func _check_death_and_pause() -> void:
	var boss: Variant = _ready_boss()
	var swarm := Vector3(8, 0, 0)
	# Pause: HuntWorld stops calling step(); a zero delta must not change anything either.
	boss.begin_attack(APEX.Pattern.QUAKE, swarm, 1.0)
	var snapshot := [boss.state, boss.remaining, boss.position, boss.health, boss.cooldown]
	var total := 0
	for i in 120:
		total += boss.step(0.0, swarm, 1.0)
	_check(not boss.is_processing() and not boss.is_physics_processing(), "Apex has no own clock (pause = no step)")
	_check(total == 0 and [boss.state, boss.remaining, boss.position, boss.health, boss.cooldown] == snapshot, "Zero-delta steps freeze the apex")
	boss.state = APEX.State.CHASE
	boss._clear_telegraphs()
	boss.phase = 2
	boss.defeated.connect(func(location: Vector3) -> void: defeated_at = location)
	boss.position = Vector3(3, 0, 4)
	boss.take_damage(boss.health + 1.0)
	_check(boss.state == APEX.State.DEAD and boss.migration_ready and defeated_at == Vector3(3, 0, 4) and boss.migration_point == Vector3(3, 0, 4), "Death opens migration (flag + signal)")
	_check(boss.step(1.0, boss.position, 1.0) == 0 and boss.telegraphs.is_empty(), "Dead apex never attacks")
	_check(boss.hud_message().contains("MIGRATION"), "Death banner announces the migration maw")
	_free(boss)


func _check_colorblind() -> void:
	for pattern in [APEX.Pattern.ROOTS, APEX.Pattern.SPORES, APEX.Pattern.QUAKE]:
		var normal: ShaderMaterial = APEX.telegraph_material(pattern, false)
		var blind: ShaderMaterial = APEX.telegraph_material(pattern, true)
		_check(normal.get_shader_parameter("pattern") == pattern and blind.get_shader_parameter("pattern") == pattern, "Pattern shape kept in colour-blind mode")
		_check(normal.shader.code.length() > 0 and blind.get_shader_parameter("edge_color") != null, "Telegraph material complete")


func _check_biomes() -> void:
	_check(BIOMES.ORDER.size() >= 2 and BIOMES.display_name("glutsumpf") == "Glutsumpf" and BIOMES.next_biome("verdant_maw") == "glutsumpf", "Biome data and migration order")
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var arena: Variant = scene.get_node("Arena")
	var world: Variant = scene.get_node("HuntWorld")
	var swarm: Variant = scene.get_node("Swarm")
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)
	_check(arena.biome_id == "verdant_maw", "Default biome is Verdant Maw")
	var classic := {"ground": Color("80a04c"), "path": Color("d4b377"), "edge": Color("aeaa62"), "water": Color("3fc0c4"), "shore": Color("dcd296"), "sand": Color("c8ab6e"), "plinth": Color("62883a")}
	_check(_arena_colors(arena) == classic and arena.moss_materials[1].albedo_color == Color("718f40") and not arena.water_material.emission_enabled, "Verdant Maw keeps the classic colours")
	var layout: Array = arena.obstacles(Vector2i(1, 2)).duplicate()
	var chunk: Node = arena.chunks[Vector2i(0, 0)]
	var count := chunk.get_child_count()
	arena.set_biome("glutsumpf")
	_check(arena.biome_id == "glutsumpf" and arena.ground_material.albedo_color == BIOMES.DATA.glutsumpf.ground and arena.water_material.emission_enabled, "Glutsumpf restyles ground and glowing pools")
	_check(arena.chunks.size() == 9 and arena.obstacles(Vector2i(1, 2)) == layout, "Biome switch keeps layout and chunk budget")
	arena.set_biome("unknown")
	_check(arena.biome_id == "verdant_maw" and _arena_colors(arena) == classic and not arena.water_material.emission_enabled, "Unknown biome falls back to Verdant Maw exactly")
	_check(arena.chunks[Vector2i(0, 0)].get_child_count() == count, "Verdant decoration count restored")
	scene.queue_free()
	await process_frame


func _arena_colors(arena: Variant) -> Dictionary:
	return {"ground": arena.ground_material.albedo_color, "path": arena.path_material.albedo_color, "edge": arena.path_edge_material.albedo_color, "water": arena.water_material.albedo_color, "shore": arena.shore_material.albedo_color, "sand": arena.sand_material.albedo_color, "plinth": arena.plinth_material.albedo_color}


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
