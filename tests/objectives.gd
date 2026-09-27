extends SceneTree

# Stage 06 ZIELE: Brutnest fills by share and keeps progress, hatches exactly once
# into persistent loot crystals (biomass + DNA); Fluch-Totem hold, boss curse and doubled
# rewards; elite hunter with guaranteed Alpha-Kern; pause, reset, seed determinism.
const TUNING = preload("res://scripts/tuning.gd")
var failures: Array[String] = []
var world: Variant
var swarm: Variant


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	var hud: Variant = scene.get_node("HUD/Controls")
	var arena: Variant = scene.get_node("Arena")
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)
	_check(hud.get_node_or_null("hud_objectives") != null, "Objective HUD component is added to the HUD")

	# ---- Placement: seeded, open ground, 14-22 m from the swarm, outside the start.
	var first := _first_nest(77)
	var again := _first_nest(77)
	var other := _first_nest(78)
	_check(first.is_equal_approx(again), "Same seed places the first nest at the same spot (%s / %s)" % [first, again])
	_check(not first.is_equal_approx(other), "Another seed moves the nest")
	for seed_value in [1, 2, 3, 4, 5, 77]:
		var at := _first_nest(seed_value)
		var distance: float = Vector2(at.x - swarm.position.x, at.z - swarm.position.z).length()
		_check(distance >= TUNING.OBJECTIVE_MIN_DISTANCE - 0.01 and distance <= TUNING.OBJECTIVE_MAX_DISTANCE + 0.01, "Seed %d: nest %.1f m from the swarm" % [seed_value, distance])
		_check(Vector2(at.x, at.z).length() >= TUNING.OBJECTIVE_START_CLEARANCE, "Seed %d: nest outside the start zone" % seed_value)
		_check(arena.is_open(at, 1.8), "Seed %d: nest on open ground" % seed_value)
	world.config = {}

	# ---- Nest fills by share, keeps progress, hatches once.
	_quiet()
	world.model.population = 25
	swarm.set_population(25, false)
	# Stage 09 lone start: the 24 new animals appear on the leader; spread them
	# into the usual golden-angle formation (radius 2.65 m) as a real swarm does.
	for index in swarm.units.size():
		var angle := float(index) * 2.39996323
		swarm.units[index].position = Vector3(cos(angle), 0.0, sin(angle)) * sqrt((float(index) + 0.5) / 25.0) * 2.65
	world.unit_points_valid = false
	var nest: Variant = world.spawn_nest(swarm.position)
	_steps(2.0)
	var full_rate: float = nest.progress / 2.0
	_check(absf(full_rate - 1.0 / TUNING.NEST_FILL_SECONDS) < 0.02, "Whole swarm of 25 fills the nest in ~%.0f s (rate %.3f/s)" % [TUNING.NEST_FILL_SECONDS, full_rate])
	var before: float = nest.progress
	nest.position = swarm.position + Vector3(TUNING.NEST_RADIUS, 0, 0)
	_steps(2.0)
	var half_rate: float = (nest.progress - before) / 2.0
	_check(half_rate > 0.05 * full_rate and half_rate < 0.8 * full_rate, "Partly inside fills slower (%.3f vs %.3f)" % [half_rate, full_rate])
	before = nest.progress
	nest.position = swarm.position + Vector3(30, 0, 0)
	_steps(3.0)
	_check(is_equal_approx(nest.progress, before) and not nest.complete, "Progress stays when the swarm leaves")
	# A bigger swarm fills faster.
	var big: Variant = world.BROOD_NEST.speed_factor(150)
	_check(big > 1.9, "150 animals fill about twice as fast (factor %.2f)" % big)
	# Pause freezes logic and animation.
	nest.position = swarm.position
	world.paused = true
	var paused_time: float = nest.get("_time")
	_steps(2.0)
	_check(is_equal_approx(nest.progress, before) and is_equal_approx(nest.get("_time"), paused_time), "Pause freezes nest progress and animation")
	world.paused = false
	var kills: int = world.model.kills
	var crystals: int = world.loot.count()
	var dna_before: int = world.evolution.dna
	var nest_at: Vector3 = nest.position
	nest.progress = 0.9999
	world.step(0.05)
	_check(world.nest == null and world.nests_completed == 1, "Full nest hatches and disappears")
	_check(world.loot.count() > crystals and world.loot.count() - crystals <= TUNING.LOOT_MAX_PER_KILL, "Hatching bursts into %d crystals" % (world.loot.count() - crystals))
	var expected: float = TUNING.NEST_BIOMASS * world.evolution.biomass_multiplier()
	_check(absf(world.loot.total(0) - expected) < 0.01, "Clutch biomass %.1f = %.1f" % [world.loot.total(0), expected])
	_check(world.model.kills == kills, "A hatched nest does not count as a kill")
	_check(int(round(world.loot.total(1))) == TUNING.NEST_DNA, "Nest drops %d DNA" % TUNING.NEST_DNA)
	_check(is_equal_approx(world.nest_clock, TUNING.NEST_RESPAWN_SECONDS), "Next nest is scheduled")
	world.evolution.offers.clear()
	swarm.position = Vector3(-40, 0, 0)
	var remaining_before: float = world.loot.total(0)
	_steps(5.0)
	_check(absf(world.loot.total(0) - remaining_before) < 0.001 and world.nests_completed == 1, "Clutch biomass stays on the ground and is paid once")
	swarm.position = nest_at
	_steps(2.0)
	world.evolution.offers.clear()
	_check(world.loot.total(0) < remaining_before and (world.evolution.dna - dna_before >= TUNING.NEST_DNA or world.evolution.level > 0), "Clutch crystals are collected like any other")
	_check(int(world.run_stats().get("nests", -1)) == 1, "RunStats count nests")

	# ---- Fluch-Totem: hold to accept, leaving drains.
	_quiet()
	swarm.position = Vector3.ZERO
	var totem: Variant = world.spawn_totem(swarm.position + Vector3(1.0, 0, 0))
	_steps(1.0)
	_check(totem.hold > 0.6 and world.curse_state == 0, "Totem needs the full hold")
	totem.position = swarm.position + Vector3(10, 0, 0)
	_steps(0.3)
	_check(totem.hold < 0.4, "Leaving drains the hold")
	totem.position = swarm.position + Vector3(1.0, 0, 0)
	_steps(1.6)
	_check(world.totem == null and world.curse_state == 1 and world.totems_taken == 1, "Holding 1.5 s accepts the curse")
	_check(is_equal_approx(world.reward_multiplier(), TUNING.CURSE_REWARD_MULTIPLIER), "Rewards doubled after accepting")
	# Doubled prey reward.
	var prey: Variant = world.PREY.new()
	prey.position = Vector3(25, 0, 0)
	world.add_child(prey)
	world.prey.append(prey)
	var bio_before: float = world.loot.total(0)
	var dna_lying: float = world.loot.total(1)
	world._kill_prey(prey)
	world.evolution.offers.clear()
	_check(is_equal_approx(world.loot.total(0) - bio_before, TUNING.CORPSE_BIOMASS * world.evolution.biomass_multiplier() * 2.0), "Prey biomass doubled under the curse")
	_check(int(round(world.loot.total(1) - dna_lying)) == 20, "Prey DNA doubled under the curse")
	# Cursed boss: +50 % health and damage.
	world.model.population = 120
	swarm.set_population(120, false)
	var pressure: float = world.model.pressure()
	var boss: Variant = world._spawn_boss(Vector3(30, 0, 0))
	_check(boss.has_meta("cursed") and world.curse_state == 2, "Next boss is cursed")
	_check(is_equal_approx(boss.health, TUNING.BOSS_HEALTH * sqrt(pressure) * world.enemy_hp * TUNING.CURSE_BOSS_MULTIPLIER), "Cursed boss has +50 % health")
	boss.attack_center = swarm.position
	boss.resolved_power = 10
	world.unit_points_valid = false
	world._resolve_area_hit(boss, swarm.position, 0.0)
	_check(world.last_loss == 15, "Cursed boss hits +50 percent (loss %d)" % world.last_loss)
	boss.resolved_power = 0
	boss.health = 0.0
	bio_before = world.loot.total(0)
	world._resolve_death(boss, "boss")
	world.evolution.offers.clear()
	_check(is_equal_approx(world.loot.total(0) - bio_before, TUNING.BOSS_BIOMASS * world.evolution.biomass_multiplier() * 2.0), "Cursed boss crystals are still doubled")
	_check(world.curse_state == 0 and is_equal_approx(world.reward_multiplier(), 1.0), "Curse ends with the boss")
	# An ignored totem crumbles when the boss arrives; that boss stays normal.
	world.spawn_totem(Vector3(15, 0, 0))
	var plain: Variant = world._spawn_boss(Vector3(-30, 0, 0))
	_check(world.totem == null and not plain.has_meta("cursed") and world.curse_state == 0, "Ignored totem vanishes, boss stays normal")
	world.boss = null
	plain.queue_free()
	# Director: the first boss cycle always offers a totem.
	world.reset_run()
	_quiet()
	world.boss_clock = TUNING.TOTEM_LEAD_SECONDS - 1.0
	world.step(0.05)
	_check(world.totem != null and world.totem_offered, "Totem appears before the first boss")

	# ---- Elite hunter.
	world.reset_run()
	_quiet()
	world.elite_clock = 0.01
	world.step(0.05)
	var elite: Variant = null
	for hunter in world.hunters:
		if hunter.elite:
			elite = hunter
	_check(elite != null and is_equal_approx(world.elite_clock, TUNING.ELITE_INTERVAL_SECONDS), "Elite hunter spawns on schedule")
	if elite != null:
		_check(is_equal_approx(elite.max_health, TUNING.HUNTER_HEALTH * sqrt(world.model.pressure()) * world.enemy_hp * TUNING.ELITE_HEALTH_MULTIPLIER), "Elite has x4 health")
		_check(elite.scale.x > 1.3 and elite.crown != null, "Elite is larger and crowned")
		var cores: int = world.alpha_pickups.size()
		var elite_dna: float = world.loot.total(1)
		elite.health = 0.0
		world._resolve_death(elite, "hunter")
		world.evolution.offers.clear()
		# Etappe 17: kein Alpha-Kern mehr (Welle 2: Elite-Kokon).
		_check(world.alpha_pickups.size() == cores, "Elite drops no Alpha-Kern any more")
		_check(int(round(world.loot.total(1) - elite_dna)) == TUNING.ELITE_DNA, "Elite drops %d DNA" % TUNING.ELITE_DNA)
		_check(world.loot.lures.size() >= 1, "Elite always drops a Lockruf")

	# ---- Pause freezes timers; reset clears everything.
	world.reset_run()
	_quiet()
	world.spawn_nest(Vector3(20, 0, 0))
	world.spawn_totem(Vector3(-20, 0, 0))
	world.curse_state = 1
	world.nests_completed = 3
	world.paused = true
	var clocks := [world.elite_clock, world.totem.hold, world.nest.progress]
	_steps(2.0)
	_check(clocks == [world.elite_clock, world.totem.hold, world.nest.progress], "Pause freezes elite timer, totem and nest")
	world.paused = false
	world.reset_run()
	await process_frame
	var leftovers := 0
	for child in world.get_children():
		if not child.is_queued_for_deletion() and (String(child.name).begins_with("Brood") or String(child.name).begins_with("Curse")):
			leftovers += 1
	_check(world.nest == null and world.totem == null and world.curse_state == 0 and world.nests_completed == 0 and leftovers == 0, "Reset clears nest, totem and curse")
	_check(is_equal_approx(world.nest_clock, TUNING.NEST_FIRST_SECONDS) and is_equal_approx(world.elite_clock, TUNING.ELITE_FIRST_SECONDS), "Reset restores objective timers")
	_check(world.run_stats().has("totems") and world.run_stats().has("nests"), "RunStats carry nests and totems")

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS objectives: seeded nest, share fill, persistence, one-time clutch, totem hold/curse/rewards, elite core, pause, reset")
	quit(0)


# First nest position for a seed, with the swarm at the origin.
func _first_nest(seed_value: int) -> Vector3:
	world.config = {"seed": seed_value}
	world.reset_run()
	_quiet()
	world.nest_clock = 0.01
	world.step(0.05)
	return world.nest.position if world.nest != null else Vector3.INF


# No enemies, no new prey: only the objectives act.
func _quiet() -> void:
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


func _steps(seconds: float) -> void:
	for index in int(round(seconds / 0.05)):
		world.step(0.05)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
