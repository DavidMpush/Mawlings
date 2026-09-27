extends SceneTree

# Stage 05 KAMPF: area attacks hit per animal, melee scales with biting animals,
# kill popups bundle rewards, and the Königsmoment always restores time.

const HUNTER = preload("res://scripts/hunter.gd")
const SKITTER = preload("res://scripts/skitter.gd")
const BOG_KING = preload("res://scripts/bog_king.gd")
const TUNING = preload("res://scripts/tuning.gd")
var failures: Array[String] = []
var world: Variant
var swarm: Variant
var main: Variant


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	world = main.get_node("HuntWorld")
	swarm = main.get_node("Swarm")
	main.set_process(false)
	world.set_process(false)
	swarm.set_process(false)

	# ---- Area hits: only the animals inside the locked ring fall.
	_fresh(25)
	_place(12, Vector3.ZERO, Vector3(10, 0, 0))
	var hunter: Variant = _ring_hunter(10)
	world.step(0.02)
	_check(world.model.population == 20 and world.last_loss == 5, "Half the swarm in the ring takes about half the loss (12/25 of 10 -> 5), got %d" % world.last_loss)
	_check(_count_inside(hunter) == 7 and swarm.units.size() == 20, "The fallen animals are the ones inside the ring")

	_fresh(25)
	_place(0, Vector3.ZERO, Vector3(10, 0, 0))
	_ring_hunter(10)
	world.step(0.02)
	_check(world.model.population == 25 and world.last_loss == 0, "Centre in the ring but every animal outside -> no loss")

	_fresh(25)
	_place(25, Vector3.ZERO, Vector3(10, 0, 0))
	_ring_hunter(10)
	world.step(0.02)
	_check(world.model.population == 15, "Whole swarm in the ring -> full loss")

	# Logical population above the visual limit: the visible share scales it.
	_fresh(250)
	_place(60, Vector3.ZERO, Vector3(10, 0, 0))
	_ring_hunter(100)
	world.step(0.02)
	_check(world.model.population == 200, "60/120 visible inside scales to half of the logical loss (250 -> 200), got %d" % world.model.population)

	# Skitter lane: a sideways step saves the animals beside the lane.
	_fresh(25)
	_place(10, Vector3.ZERO, Vector3(0, 0, 3))
	var skitter: Variant = world._spawn_skitter(Vector3(-4, 0, 0))
	skitter.state = SKITTER.State.DASH
	skitter.remaining = 0.01
	skitter.dash_start = Vector3(-4, 0, 0)
	skitter.dash_end = Vector3(4, 0, 0)
	skitter.damage = 5
	world.step(0.05)
	_check(world.model.population == 23, "Skitter lane hits only the 10/25 animals on it (ceil 2 of 5)")
	_check(skitter.contains(Vector3(0, 0, 1.0)) and not skitter.contains(Vector3(0, 0, 1.5)), "Lane geometry has the telegraphed half-width")

	# Leaper and Bog King share the same geometry query.
	_fresh(25)
	var leaper: Variant = world._spawn_leaper(Vector3(-20, 0, 0))
	leaper.landing_center = Vector3(1, 0, 0)
	_check(leaper.contains(Vector3(3.5, 0, 0)) and not leaper.contains(Vector3(3.8, 0, 0)), "Leaper zone geometry")
	_check(is_equal_approx(leaper.hit_fraction(PackedVector3Array([Vector3.ZERO, Vector3(10, 0, 0)])), 0.5), "Leaper hit_fraction counts points")
	var king: Variant = world._spawn_boss(Vector3(30, 0, 0))
	king.attack_center = Vector3.ZERO
	_check(king.contains(Vector3(3.5, 0, 0)) and not king.contains(Vector3(3.8, 0, 0)), "Bog King circle geometry")

	# ---- Melee: damage follows the number of animals within reach.
	_fresh(25)
	var target: Variant = world._spawn_hunter(Vector3(6, 0, 0))
	target.state = HUNTER.State.RECOVERY
	target.remaining = 1000.0
	_place(6, Vector3(6, 0, 0), Vector3(0, 0, -8))
	var expected: float = (6.0 / 25.0) / world.MELEE_FULL_SHARE
	_check(is_equal_approx(world.melee_factor(target.position, "hunter", 1.5), expected), "6 of 25 animals in reach bite with their share")
	var health: float = target.health
	world.step(0.1)
	var full := minf(32.0, 1.0 + 25.0 * 0.12) * 0.1
	_check(absf((health - target.health) - full * expected) < 0.001, "Melee damage scales with animals in reach")
	_place(25, Vector3(6, 0, 0), Vector3.ZERO)
	_check(is_equal_approx(world.melee_factor(target.position, "hunter", 1.5), 1.0), "Surrounded target takes full damage")
	_place(0, Vector3(6, 0, 0), Vector3(0, 0, -8))
	_check(world.melee_factor(target.position, "hunter", 1.5) == 0.0, "No animal in reach -> no damage")
	_check(is_equal_approx(world.melee_factor(swarm.position + Vector3(0.5, 0, 0), "hunter", 1.5), world.MELEE_MIN_ENGAGE), "Target inside the swarm keeps the minimum engagement")

	# ---- Kill popups: bundled at the kill spot, capped, gone after ~0.9 s.
	_fresh(25)
	world._kill_prey(world.prey[0])
	world._kill_prey(world.prey[0])
	world.evolution.offers.clear()
	_check(world.kill_popups.size() == 2 and world.kill_popups[0].dna == 10 and world.kill_popups[0].biomass == int(round(TUNING.CORPSE_BIOMASS)), "Prey kill shows +10 DNA and its biomass")
	var spot: Vector3 = world.kill_popups[0].at
	world._add_popup(spot + Vector3(0.5, 0, 0), 20, 26.0)
	_check(world.kill_popups[0].dna == 30 and world.kill_popups[0].biomass == 26 + int(round(TUNING.CORPSE_BIOMASS)), "Close kills merge into one popup")
	for index in 10:
		world._add_popup(Vector3(index * 10.0, 0, 50), 10, 12.0)
	_check(world.kill_popups.size() == world.POPUP_MAX, "At most %d popups at once" % world.POPUP_MAX)
	world.step(1.0)
	_check(world.kill_popups.is_empty(), "Popups vanish after their short life")

	# ---- Königsmoment: headless default never slows time.
	_fresh(25)
	_check(not main.slow_motion_enabled, "Headless runs keep time at normal speed by default")
	_kill_king()
	_check(Engine.time_scale == 1.0 and world.king_moments == 1 and main.king_zoom_left > 0.0, "Headless king kill: moment and zoom without slow motion")
	main.slow_motion_enabled = true
	_fresh(25)
	_kill_king()
	_check(is_equal_approx(Engine.time_scale, main.KING_SLOW_SCALE), "King kill slows time")
	main.update_king_moment(0.3)
	_check(is_equal_approx(Engine.time_scale, main.KING_SLOW_SCALE), "Slow motion lasts ~0.6 s real time")
	main.update_king_moment(0.35)
	_check(Engine.time_scale == 1.0, "Slow motion ends by itself")
	main.king_moment(Vector3.ZERO)
	world.toggle_pause()
	main.update_king_moment(0.01)
	_check(Engine.time_scale == 1.0, "Pause restores normal time")
	world.toggle_pause()
	main.king_moment(Vector3.ZERO)
	main._restart()
	_check(Engine.time_scale == 1.0 and main.king_zoom_left == 0.0, "Restart restores normal time and camera")
	main.king_moment(Vector3.ZERO)
	# Stage 09: only the leader's last LP ends the run.
	world.model.leader_hp = 1
	world._apply_hit(100000, swarm.position, 0.0, null, true)
	main.update_king_moment(0.01)
	_check(world.model.extinct and Engine.time_scale == 1.0, "Extinction restores normal time")
	main.king_moment(Vector3.ZERO)
	main.queue_free()
	await process_frame
	_check(Engine.time_scale == 1.0, "Leaving the scene restores normal time")
	Engine.time_scale = 1.0

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS per_unit_hits: ring share, outside=0, inside=full, logical scaling, skitter lane, geometry, melee share, popups, Königsmoment time reset")
	quit(0)


func _fresh(population: int) -> void:
	world.reset_run()
	world.hunter_clock = 1e9
	world.skitter_clock = 1e9
	world.leaper_clock = 1e9
	world.boss_clock = 1e9
	world.model.population = population
	swarm.set_population(population, false)


# First `inside` visible units at `a` (world), the rest at `b`.
func _place(inside: int, a: Vector3, b: Vector3) -> void:
	for index in swarm.units.size():
		swarm.units[index].position = (a if index < inside else b) - swarm.position
	# Positions changed outside a world step: drop the cached unit points.
	world.unit_points_valid = false


func _ring_hunter(power: int) -> Variant:
	var hunter: Variant = world._spawn_hunter(swarm.position + Vector3(0, 0, 20))
	hunter.state = HUNTER.State.WARNING
	hunter.remaining = 0.01
	hunter.attack_center = swarm.position
	hunter.attack_power = power
	return hunter


func _count_inside(enemy: Variant) -> int:
	var count := 0
	for point in swarm.unit_world_points():
		if enemy.contains(point):
			count += 1
	return count


func _kill_king() -> void:
	var king: Variant = world._spawn_boss(swarm.position + Vector3(20, 0, 0))
	king.state = BOG_KING.State.RECOVERY
	king.remaining = 100.0
	king.health = -1.0
	world.step(0.01)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
