extends SceneTree

# Etappe 17 Welle 2 - Power-ups: drop rules (only mini bosses - elite, leaper,
# Bog King, apex - one guaranteed random booster; none from ordinary kills,
# flood stages or knolls; grove knolls are a Bernstein treasure), walk-in pickup only (no magnet, no Lockruf), timers, stacking up to
# double the duration, blinking after 45 s without vanishing, the effects
# through evolution.boosts and the Chitinschild leader immunity.
const TUNING = preload("res://scripts/tuning.gd")
const POWERUPS = preload("res://scripts/powerups.gd")
var failures: Array[String] = []
var world: Variant
var swarm: Variant
var power: Variant


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)
	power = world.powerups
	_check(power != null and power.get_parent() == world, "HuntWorld owns the power-up layer")
	# Etappe 30: the golden grove knolls (coins only) are gone.
	_check(power.knoll_count() == 0 and not POWERUPS.GROVE_TREASURE, "No grove treasure knolls any more (%d)" % power.knoll_count())
	_quiet()
	_population(20)
	swarm.position = Vector3.ZERO

	# ---- Drop rules: only mini bosses drop a booster (guaranteed, random of the 6).
	var normal := 0
	for kind in ["prey", "hunter", "skitter", "leaper", "horde"]:
		for index in 200:
			if power.on_kill(kind, Vector3(200, 0, 200), false, 0.0):
				normal += 1
	_check(normal == 0 and power.pickups.is_empty(), "Ordinary kills never drop a power-up (%d)" % normal)
	for kind in ["boss", "apex"]:
		_check(power.on_kill(kind, Vector3(200, 0, 200), false, 0.0), "%s always drops a power-up" % kind)
	_check(power.pickups.size() == 2, "One booster per mini boss (%d)" % power.pickups.size())
	var ids := {}
	for index in 60:
		ids[power.roll_id()] = true
	_check(ids.size() == POWERUPS.ORDER.size(), "Random of all six (%d kinds seen)" % ids.size())
	_clear_pickups()
	# Elite through the real death path.
	var elite: Variant = world.spawn_elite(Vector3(40, 0, 0))
	elite.health = 0.0
	world._resolve_death(elite, "hunter")
	_check(power.pickups.size() == 1, "A dead elite always drops a power-up (%d)" % power.pickups.size())
	_clear_pickups()
	# No booster from a new flood stage any more.
	world.flood_start = 0.0
	world.flood_state = 2
	world.flood_lure_stage = 0
	world.model.elapsed = TUNING.FLOOD_DOUBLING_SECONDS * 1.2
	world._step_flood(0.05, 1.0)
	_check(power.pickups.is_empty(), "A new flood stage drops no power-up (%d)" % power.pickups.size())
	world.flood_state = 0
	world.flood_start = 1000000.0
	if world.horde != null:
		world.horde.clear()
	_clear_pickups()

	# ---- No magnet: a booster inside the magnet radius does not move; walking in takes it.
	swarm.position = Vector3.ZERO
	var entry: Dictionary = power.drop(Vector3(3.2, 0, 0), "rausch")
	var at: Vector3 = entry.at
	world.evolution.boosts["magnet"] = 1.0
	_check(world.magnet_radius() > 3.4, "Test setup: the booster lies inside the magnet (%.1f m)" % world.magnet_radius())
	_steps(2.0)
	_check(power.pickups.has(entry) and Vector3(entry.at).distance_to(at) < 0.01, "The magnet does not pull power-ups")
	world.drop_lure(swarm.position + Vector3(0, 0, 1))
	_steps(1.0)
	_check(power.pickups.has(entry), "A Lockruf does not call power-ups")
	swarm.position = at
	_steps(0.1)
	_check(not power.pickups.has(entry) and power.is_active("rausch"), "Walking in collects it")
	_check(is_equal_approx(float(world.evolution.boosts.speed), POWERUPS.SPEED), "Rausch: +45 %% speed (%.2f)" % float(world.evolution.boosts.speed))
	_check(world.evolution.speed_multiplier() > 1.4, "Swarm speed follows")
	_check(not (power.hud_state().band as Dictionary).is_empty(), "A short band announces it")
	_check((power.hud_state().active as Array).size() == 1, "The HUD row shows it with its timer")

	# ---- Timer and stacking (max double).
	_steps(4.0)
	_check(absf(power.left("rausch") - 4.0) < 0.2, "Timer runs (%.1f s left)" % power.left("rausch"))
	power.collect("rausch")
	_check(absf(power.left("rausch") - 12.0) < 0.2, "Same booster extends (%.1f s)" % power.left("rausch"))
	power.collect("rausch")
	_check(absf(power.left("rausch") - 16.0) < 0.01, "At most double the duration (%.1f s)" % power.left("rausch"))
	power.collect("raserei")
	_check(power.is_active("rausch") and power.is_active("raserei"), "Different boosters run in parallel")
	_check(is_equal_approx(float(world.evolution.boosts.damage), 2.0), "Raserei doubles the damage")
	_steps(16.5)
	_check(not power.is_active("rausch") and not power.is_active("raserei"), "They run out")
	_check(is_equal_approx(float(world.evolution.boosts.speed), 1.0) and is_equal_approx(float(world.evolution.boosts.damage), 1.0), "Boosts return to neutral")

	# ---- Blutrausch: weapon cooldown -40 % (weapons resynced).
	var revision: int = world.evolution.revision
	var cooldown_before: float = world.evolution.cooldown_scale()
	power.collect("blutrausch")
	_check(world.evolution.revision > revision and absf(world.evolution.cooldown_scale() - 0.6 * cooldown_before) < 0.001, "Blutrausch: -40 %% cooldown (%.2f of %.2f)" % [world.evolution.cooldown_scale(), cooldown_before])
	# Magnetsturm: radius x3.
	var radius: float = world.magnet_radius()
	power.collect("magnetsturm")
	_check(absf(world.magnet_radius() - radius * 3.0) < 0.01, "Magnetsturm: collect radius x3")
	# Brutwelle: biomass for 3 divisions right away.
	var population: int = world.model.population
	power.collect("brutwelle")
	_steps(2.0)
	_check(world.model.population >= population + 3, "Brutwelle: +3 Mawlings (%d -> %d)" % [population, world.model.population])
	power.clear_active()

	# ---- Chitinschild: leader immune, -70 % losses.
	_population(30)
	power.collect("chitinschild")
	var hp: int = world.model.leader_hp
	world._apply_hit(10, swarm.position, 0.0, null, true)
	_check(world.model.leader_hp == hp, "Chitinschild: the leader takes no hit")
	_check(world.model.population == 27, "Chitinschild: -70 %% losses (10 -> %d)" % (30 - world.model.population))
	power.clear_active()
	world.model.leader_invulnerable = 0.0
	world._apply_hit(0, swarm.position, 0.0, null, true)
	_check(world.model.leader_hp == hp - world.leader_damage(null), "Without it the leader is struck again")

	# ---- Lying boosters blink after 45 s but never vanish.
	var lying: Dictionary = power.drop(Vector3(-60, 0, 0), "raserei")
	swarm.position = Vector3(-40, 0, 0)
	_steps(60.0)
	_check(power.pickups.has(lying), "A lying power-up never vanishes")
	var hidden := false
	for index in 20:
		world.step(0.05)
		if not (lying.pivot as Node3D).visible:
			hidden = true
	_check(hidden, "After 45 s it blinks")
	_check(world._map_state().has("powerups"), "The minimap data carries power-ups")

	_finish()


func _clear_pickups() -> void:
	for entry in power.pickups:
		entry.node.queue_free()
	power.pickups.clear()


func _population(count: int) -> void:
	world.model.population = count
	world.model.biomass_bank = 0.0
	swarm.set_population(count, false)
	world.unit_points_valid = false


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
	world.flood_start = 1000000.0
	world.apex_state = 4
	world.totem_offered = true
	for shrine in world.shrines.shrines:
		shrine.at = Vector3(500, 0, -500)
	for cocoon in world.chests.cocoons:
		cocoon.at = Vector3(500, 0, 500)


func _steps(seconds: float) -> void:
	for index in int(round(seconds / 0.05)):
		world.unit_points_valid = false
		world.step(0.05)
		while world.choosing():
			world.choose_mutation(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("PASS powerups: mini-boss drops only, grove treasure, no magnet, timers, stacking, effects, shield immunity, blink")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL powerups: %d" % failures.size())
		quit(1)
