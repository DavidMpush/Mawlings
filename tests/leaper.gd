extends SceneTree

const LEAPER = preload("res://scripts/mire_leaper.gd")
const TUNING = preload("res://scripts/tuning.gd")
var failures: Array[String] = []


func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var world: Variant = scene.get_node("HuntWorld")
	var swarm: Variant = scene.get_node("Swarm")
	var hud: Variant = scene.get_node("HUD/Controls")
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)
	world.reset_run()
	var open_spot := _open_spot(world, swarm)
	swarm.position = open_spot

	# Warning precedes damage and locks a fixed zone on the swarm.
	var leaper: Variant = world._spawn_leaper(open_spot + Vector3(-8, 0, 0))
	leaper.state = LEAPER.State.STALK
	leaper.lurk = 0.0
	check(leaper.step(0.01, open_spot, 1) == 0, "Locking the jump deals no damage")
	check(leaper.state == LEAPER.State.WARNING and leaper.warning.visible and leaper.arc.visible, "Visible landing zone and arc before the jump")
	check(leaper.landing_center.distance_to(open_spot) < 0.01, "Zone is placed on the swarm")
	check(absf(leaper.remaining - TUNING.LEAPER_WARNING_SECONDS) < 0.001, "Warning lasts the tuned reaction window")
	var zone: Vector3 = leaper.landing_center
	var aside: Vector3 = open_spot + Vector3(0, 0, 4)
	check(leaper.step(TUNING.LEAPER_WARNING_SECONDS, aside, 1) == 0 and leaper.state == LEAPER.State.LEAP, "Jump starts after warning")
	check(leaper.landing_center == zone and leaper.warning.visible, "Zone stays fixed and visible during flight")
	leaper.step(TUNING.LEAPER_FLIGHT_SECONDS * 0.5, aside, 1)
	check(not leaper.can_be_hit() and leaper.body.position.y > 1.0, "Leaper is airborne and untouchable mid-flight")
	check(leaper.step(TUNING.LEAPER_FLIGHT_SECONDS, aside, 1) == 0, "Leaving the zone evades the landing")
	check(leaper.state == LEAPER.State.EXHAUSTED and leaper.position.distance_to(zone) < 0.01 and not leaper.warning.visible, "Lands in the zone, exhausted, warning cleared")
	check(leaper.can_be_hit(), "Exhausted leaper is vulnerable")
	check(leaper.step(0.1, zone, 1) == 0, "Exhaustion never repeats a hit")
	leaper.step(TUNING.LEAPER_EXHAUST_SECONDS, open_spot, 1)
	# Etappe 09: no retreat; it chases on and prepares the next jump quickly.
	check(leaper.state == LEAPER.State.STALK and leaper.position.distance_to(zone) < 0.01, "Chases on after exhaustion (no hop back)")
	check(leaper.lurk <= TUNING.LEAPER_CHASE_LURK_SECONDS + 0.001, "Next jump is prepared after a short breath")
	var far_swarm: Vector3 = zone + Vector3(0, 0, 4)
	var before_gap: float = leaper.position.distance_to(far_swarm)
	leaper.lurk = 100.0
	for tick in 10:
		leaper.step(0.05, far_swarm, 1)
	check(leaper.position.distance_to(far_swarm) < before_gap - 0.3, "Walks straight at the swarm while lurking (%.2f -> %.2f m)" % [before_gap, leaper.position.distance_to(far_swarm)])
	for tick in 200:
		leaper.step(0.05, far_swarm, 1)
	check(leaper.position.distance_to(far_swarm) >= TUNING.LEAPER_CONTACT_DISTANCE - 0.3, "Stops at the swarm's edge, never inside")
	leaper.position = zone

	# Standing in the zone takes exactly one hit per jump.
	leaper.lurk = 0.0
	leaper.step(0.01, open_spot, 1)
	var hits := 0
	var total := 0
	for tick in 120:
		var loss: int = leaper.step(0.05, open_spot, 1)
		if loss > 0:
			hits += 1
			total += loss
		if leaper.state == LEAPER.State.STALK:
			break
	check(hits == 1 and total == int(ceil(TUNING.LEAPER_DAMAGE)), "Standing in the zone takes exactly one hit")

	# Range: never lands further than tuned, and never inside a stone.
	world.reset_run()
	leaper = world._spawn_leaper(open_spot)
	leaper.state = LEAPER.State.STALK
	leaper._lock_zone(open_spot + Vector3(30, 0, 0), 1)
	check(leaper.landing_center.distance_to(open_spot) <= TUNING.LEAPER_RANGE + 2.6, "Landing is limited to leap range")
	var arena: Variant = scene.get_node("Arena")
	check(arena.is_open(leaper.landing_center, 0.69), "Landing zone is never inside stone")

	# Damage reaches world and HUD once.
	world.reset_run()
	# Stage 09 lone start: the hit check uses a 25-strong swarm.
	world.model.population = 25
	swarm.set_population(25, false)
	swarm.position = open_spot
	leaper = world._spawn_leaper(open_spot + Vector3(-6, 0, 0))
	leaper.state = LEAPER.State.LEAP
	leaper.remaining = 0.01
	leaper.jump_start = open_spot + Vector3(-6, 0, 0)
	leaper.landing_center = open_spot
	leaper.damage = 5
	leaper.warning.visible = true
	world.step(0.05)
	check(world.model.population == 20 and hud.last_loss == 5 and leaper.state == LEAPER.State.EXHAUSTED, "Landing damage reaches world and HUD")
	world.step(0.05)
	check(world.model.population == 20, "Single resolved landing")

	# Director: nothing before the start time, then a small budget.
	world.reset_run()
	# Stage 09: leapers join once the swarm has LEAPER_POPULATION_STEP x 4 animals.
	world.model.population = TUNING.LEAPER_POPULATION_STEP * 4
	swarm.set_population(world.model.population, false)
	world.model.elapsed = TUNING.FIRST_LEAPER_SECONDS - 5.0
	world.leaper_clock = 0.0
	world.step(0.05)
	check(world.leapers.is_empty(), "No leaper before its start time")
	world.model.elapsed = TUNING.FIRST_LEAPER_SECONDS + 1.0
	world.step(0.05)
	check(world.leapers.size() == 1 and world.leaper_clock > 0.0, "Director spawns first leaper")
	if "leapers" in hud:
		check(hud.get("leapers") == 1, "HUD counts leapers")
	world.model.elapsed = 5000.0
	for tick in 200:
		world.leaper_clock = 0.0
		world.step(0.01)
		if world.model.extinct:
			break
	check(world.leapers.size() <= TUNING.MAX_LEAPERS, "Leaper budget stays capped")

	# Kill: DNA once, persistent biomass, visuals removed.
	world.reset_run()
	world.model.population = 250
	swarm.set_population(250)
	swarm.position = open_spot
	leaper = world._spawn_leaper(open_spot + Vector3(0.5, 0, 0))
	leaper.state = LEAPER.State.EXHAUSTED
	leaper.remaining = 5.0
	leaper.health = 0.01
	var zone_node: Variant = leaper.warning
	world.step(0.01)
	world.collect_loot_now()
	check(world.leapers.is_empty() and world.evolution.dna == TUNING.LEAPER_DNA, "Kill awards DNA once")
	check(is_equal_approx(world.loot.total(0), TUNING.LEAPER_BIOMASS), "Leaper leaves persistent biomass crystals at cap")
	check(not is_instance_valid(zone_node) or (not zone_node.visible and leaper.is_queued_for_deletion()), "Zone removed on kill")
	world.step(0.01)
	check(world.evolution.dna == TUNING.LEAPER_DNA, "DNA is not awarded twice")
	world.model.elapsed = 300.0
	for tick in 100:
		world.step(0.01)
	check(is_equal_approx(world.loot.total(0), TUNING.LEAPER_BIOMASS), "Biomass persists while the swarm is full")

	# Airborne leapers cannot be hit by the swarm.
	world.reset_run()
	world.model.population = 250
	swarm.set_population(250)
	swarm.position = open_spot
	leaper = world._spawn_leaper(open_spot + Vector3(0.3, 0, 0))
	leaper.state = LEAPER.State.LEAP
	leaper.remaining = 10.0
	leaper.jump_start = open_spot + Vector3(0.3, 0, 0)
	leaper.landing_center = open_spot + Vector3(0.3, 0, 0)
	var before: float = leaper.health
	world.step(0.05)
	check(leaper.health == before, "Swarm cannot hit a leaper in the air")

	# Pause freezes the jump.
	world.reset_run()
	swarm.position = open_spot
	leaper = world._spawn_leaper(open_spot + Vector3(-6, 0, 0))
	leaper.state = LEAPER.State.WARNING
	leaper.remaining = 0.5
	world.toggle_pause()
	world.step(1.0)
	check(leaper.state == LEAPER.State.WARNING and is_equal_approx(leaper.remaining, 0.5), "Pause freezes the leaper")
	world.toggle_pause()

	# Reset clears leapers, their zones and the clock.
	zone_node = leaper.warning
	world.reset_run()
	await process_frame
	check(world.leapers.is_empty() and world.leaper_clock == TUNING.FIRST_LEAPER_SECONDS, "Restart clears leapers and clock")
	check(not is_instance_valid(zone_node), "Restart removes landing zones")
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
	else:
		print("PASS leaper: warning, fixed zone, dodge, chase (no retreat), single hit, range, airborne, director, DNA, persistent biomass, pause, reset")
		quit(0)


# A spot with open ground around it, so stones never shift test zones.
func _open_spot(world: Variant, swarm: Variant) -> Vector3:
	var arena: Variant = world.get_parent().get_node("Arena")
	for index in 200:
		var candidate := Vector3(float(index) * 3.7, 0.0, float(index % 7) * 2.9)
		var clear := true
		for probe in [Vector3.ZERO, Vector3(-8, 0, 0), Vector3(-6, 0, 0), Vector3(0, 0, 4), Vector3(9, 0, 0), Vector3(-4, 0, 0), Vector3(4, 0, 0), Vector3(0, 0, -4)]:
			if not arena.is_open(candidate + probe, 1.5):
				clear = false
				break
		if clear:
			return candidate
	return swarm.position
