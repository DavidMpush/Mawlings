extends SceneTree

# Etappe 27 (S25 feedback): Hordenwellen outside the flood and the director's
# head start per reached world. Schedule (world 1 from SURGE_FIRST_SECONDS, later
# worlds from SURGE_FIRST_LATER, interval shrinking per world), 3 s warning (hint,
# HUD flag, context line), the brood comes from ONE side, count/HP scale with the
# population, bite/speed with world and wave, the shared active cap, no wave
# during flood announcement/flood/apex/migration or for a tiny first-world swarm,
# pause freezes it, a new world restarts the schedule and clears living brood,
# reset starts over. Director: hunter/side caps and head start grow per world.
const TUNING = preload("res://scripts/tuning.gd")
var failures: Array[String] = []
var world: Variant
var swarm: Variant
var hud: Variant


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	hud = scene.get_node("HUD/Controls")
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)

	_fresh(40)
	_check(world.surge_state == 0 and is_equal_approx(world.surge_next, TUNING.SURGE_FIRST_SECONDS), "World 1: first wave planned at %.0f s (got %.1f)" % [TUNING.SURGE_FIRST_SECONDS, world.surge_next])

	# ---- Nothing before the warning, then a 3 s warning with hint and HUD flag.
	world.model.elapsed = TUNING.SURGE_FIRST_SECONDS - TUNING.SURGE_WARNING_SECONDS - 0.2
	world.step(0.05)
	_check(world.surge_state == 0 and world.horde.count() == 0, "No warning before %.0f s" % (TUNING.SURGE_FIRST_SECONDS - TUNING.SURGE_WARNING_SECONDS))
	_steps(0.3)
	_check(world.surge_state == 1, "Warning %.0f s before the wave" % TUNING.SURGE_WARNING_SECONDS)
	_check(String(hud.hint).begins_with("HORDE NAHT"), "Hint announces the wave (%s)" % hud.hint)
	_check(bool(hud.get_meta("surge_warning", false)), "HUD flag surge_warning set")
	_check(world.horde.count() == 0, "No Moorbrut during the warning")
	var top: Node = hud.get_node_or_null("hud_top")
	if top != null and top.has_method("_brawl_context"):
		top._brawl_context(0.05)
		_check(top.context_text() == "HORDE NAHT!", "Context line HORDE NAHT! (got '%s')" % top.context_text())

	# ---- Pause freezes the warning.
	world.paused = true
	var before: float = world.model.elapsed
	_steps(5.0)
	_check(world.surge_state == 1 and world.horde.count() == 0 and is_equal_approx(world.model.elapsed, before), "Pause freezes the warning")
	world.paused = false

	# ---- The wave: count as surge_count(), from one side, off screen.
	var heading: Vector3 = world.surge_heading
	var expected: int = world.surge_count()
	_steps(TUNING.SURGE_WARNING_SECONDS + 0.1)
	var spawned: int = world.horde.count()
	_check(world.surge_state == 0 and world.surge_index == 1 and world.surge_total == 1, "Wave spawned, counters advance")
	_check(spawned > 0 and spawned >= expected - 4 and spawned <= expected, "Wave size %d (expected %d)" % [spawned, expected])
	var ahead := 0
	var far := 0
	for point in world.horde.positions():
		var away := Vector3(point.x - swarm.position.x, 0.0, point.z - swarm.position.z)
		if away.normalized().dot(heading) > 0.5:
			ahead += 1
		if away.length() > 12.0:
			far += 1
	_check(ahead >= int(spawned * 0.9), "Brood comes from one side (%d of %d within 60 deg of the heading)" % [ahead, spawned])
	_check(far == spawned, "Brood spawns off screen (%d of %d beyond 12 m)" % [far, spawned])
	_check(is_equal_approx(world.surge_next, world.world_time() + world.surge_interval()) or absf(world.surge_next - (world.world_time() + world.surge_interval())) < 0.2, "Next wave one interval later")
	# The brood walks in and bites without a flood (same horde step).
	var population_before: int = world.model.population
	world.model.leader_invulnerable = 1000.0
	_steps(6.0)
	_check(world.flood_state == 0, "Still no flood")
	_check(world.model.population < population_before or world.horde_kills > 0, "The wave fights without a flood (pop %d -> %d, horde kills %d)" % [population_before, world.model.population, world.horde_kills])

	# ---- Scaling: count and HP with the population, bite with the world.
	_fresh(40)
	var count_40: int = world.surge_count()
	var stats_40: Dictionary = world.surge_stats()
	world.model.population = 400
	var count_400: int = world.surge_count()
	var stats_400: Dictionary = world.surge_stats()
	_check(count_40 == TUNING.SURGE_COUNT and count_400 > count_40 and count_400 <= TUNING.SURGE_MAX, "Count grows with the population (%d -> %d, cap %d)" % [count_40, count_400, TUNING.SURGE_MAX])
	_check(float(stats_400.hp) > float(stats_40.hp) * 4.0 and is_equal_approx(float(stats_400.bite), float(stats_40.bite)), "HP grow with the population, bite does not (hp %.1f -> %.1f)" % [float(stats_40.hp), float(stats_400.hp)])
	world.arrivals = 2
	world.surge_index = 3
	var stats_w3: Dictionary = world.surge_stats()
	_check(float(stats_w3.bite) > float(stats_400.bite) * 2.0 and float(stats_w3.speed) >= float(stats_400.speed), "Bite and speed grow with world and wave (bite %.2f -> %.2f)" % [float(stats_400.bite), float(stats_w3.bite)])
	_check(world.surge_interval() < TUNING.SURGE_INTERVAL and world.surge_interval() >= TUNING.SURGE_INTERVAL_MIN, "Interval shrinks per world (%.0f s)" % world.surge_interval())
	# Shared cap with the flood: never above FLOOD_MAX_ACTIVE living brood.
	world.horde.spawn_ring(swarm.position + Vector3(0, 0, -22), TUNING.FLOOD_MAX_ACTIVE - 5, 6.0, world.flood_stats())
	_check(world.surge_count() <= TUNING.FLOOD_MAX_ACTIVE - world.horde.count(), "Wave respects the shared active cap (%d living, %d next)" % [world.horde.count(), world.surge_count()])

	# ---- Blocks: tiny first-world swarm, flood announcement/flood, apex, migration.
	_fresh(5)
	world.model.elapsed = TUNING.SURGE_FIRST_SECONDS + 1.0
	_steps(0.5)
	_check(world.surge_state == 0 and world.horde.count() == 0, "World 1: no wave for a swarm below %d" % TUNING.SURGE_MIN_POPULATION)
	_check(world.surge_next >= world.world_time() + TUNING.SURGE_WARNING_SECONDS, "A blocked wave is pushed back, not queued")
	_fresh(40)
	world.flood_start = TUNING.SURGE_FIRST_SECONDS + 5.0
	world.model.elapsed = TUNING.SURGE_FIRST_SECONDS - 1.0
	_steps(0.5)
	_check(world.surge_state == 0, "No wave shortly before the flood")
	_fresh(40)
	world.apex_state = 2
	world.model.elapsed = TUNING.SURGE_FIRST_SECONDS + 1.0
	_steps(0.5)
	_check(world.surge_state == 0 and world.horde.count() == 0, "No wave during an apex fight")
	world.apex_state = 4

	# ---- New world: schedule restarts early, living brood is cleared, director head start.
	_fresh(60)
	world.model.elapsed = TUNING.SURGE_FIRST_SECONDS + 10.0
	world.horde.spawn_ring(swarm.position + Vector3(0, 0, -22), 20, 6.0, world.surge_stats(), Vector3(0, 0, -1))
	world.surge_index = 2
	world.arrivals = 1
	world._start_new_world()
	_check(world.horde.count() == 0, "Living brood stays behind in the old world")
	_check(world.surge_index == 0 and is_equal_approx(world.surge_next, TUNING.SURGE_FIRST_LATER), "World 2: first wave at %.0f s world time" % TUNING.SURGE_FIRST_LATER)
	_check(world.model.elapsed - world.hunters_unlocked_at >= float(TUNING.WORLD_HUNTER_HEADSTART) * TUNING.HUNTER_BUDGET_SECONDS - 0.01, "World 2: hunter budget starts with a head start")
	world.hunter_clock = 0.0
	world.hunters_unlocked = true
	world.model.population = 200
	var hunters_before: int = world.hunters.size()
	world.step(0.05)
	_check(world.hunters.size() > hunters_before, "World 2: a hunter comes right away")
	# Count budget: head start 2 -> base 1 + 2 = 3 hunters allowed at world time 0.
	for index in 8:
		world.hunter_clock = 0.0
		world.step(0.05)
	_check(world.hunters.size() >= 1 + TUNING.WORLD_HUNTER_HEADSTART, "World 2: head start of %d hunters (got %d)" % [TUNING.WORLD_HUNTER_HEADSTART, world.hunters.size()])

	# ---- Reset starts over.
	world.surge_total = 5
	world.config = {}
	world.reset_run()
	_check(world.surge_total == 0 and world.surge_index == 0 and world.surge_state == 0 and is_equal_approx(world.surge_next, TUNING.SURGE_FIRST_SECONDS), "Reset restarts the wave schedule")

	scene.queue_free()
	await process_frame
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS surge: world 1 from %.0f s / later from %.0f s, %.0f s warning (hint, HUD, context), one side off screen, fights without flood, count+HP with P, bite with world, shared cap, blocks (small swarm, flood, apex), pause, new world (clear, head start), reset" % [TUNING.SURGE_FIRST_SECONDS, TUNING.SURGE_FIRST_LATER, TUNING.SURGE_WARNING_SECONDS])
	quit(0)


func _fresh(population: int) -> void:
	world.config = {}
	world.reset_run()
	world.model.population = population
	swarm.set_population(population, false)
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
	world.unit_points_valid = false


func _steps(seconds: float) -> void:
	for index in int(round(seconds / 0.05)):
		world.step(0.05)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
