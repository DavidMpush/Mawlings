extends SceneTree

# Etappe 16 - Beute-Kristalle und Magnet: a kill bursts into 1-6 crystals (nothing
# is credited before they arrive), crystals hop out and lie without decay, the
# magnet pulls them in (radius grows with the swarm, Lockduft, Witterung, Rally),
# arrivals grow the swarm / feed DNA and sum up in ONE popup, crowded cells bundle
# into bigger crystals, a Lockruf calls every crystal of the map, a full swarm
# leaves biomass lying, empty remains sink and vanish, 1000 lying crystals are cheap.
const TUNING = preload("res://scripts/tuning.gd")
const LOOT = preload("res://scripts/loot.gd")
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
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)
	var loot: Variant = world.loot
	_check(loot != null and loot.get_parent() == world, "HuntWorld owns the loot layer")
	_quiet()

	# ---- A prey kill bursts into crystals; nothing is credited yet.
	var far := Vector3(30.0, 0.0, 0.0)
	var prey: Variant = world.PREY.new()
	prey.position = far
	world.add_child(prey)
	world.prey.append(prey)
	var dna_before: int = world.evolution.dna
	var population_before: int = world.model.population
	world._kill_prey(prey)
	var dropped: int = loot.count()
	_check(dropped >= 1 and dropped <= TUNING.LOOT_MAX_PER_KILL, "Prey kill drops 1-%d crystals (%d)" % [TUNING.LOOT_MAX_PER_KILL, dropped])
	_check(absf(loot.total(LOOT.Kind.BIOMASS) - TUNING.CORPSE_BIOMASS * world.evolution.biomass_multiplier()) < 0.01, "Crystals hold the prey biomass (%.2f)" % loot.total(LOOT.Kind.BIOMASS))
	_check(int(round(loot.total(LOOT.Kind.DNA))) == 10, "Crystals hold the prey DNA (%.0f)" % loot.total(LOOT.Kind.DNA))
	_check(world.evolution.dna == dna_before and world.model.population == population_before, "Nothing is credited at the kill")
	_check(world.model.kills == 1 and int(world.model.kills_by_type.prey) == 1, "Kill counted once")
	_check(world.corpse_kinds.values().has("prey") and world.corpse_view.empty, "Empty prey remains lie there")
	_check(loot.flying_count() == 0 and loot.lying_count() == 0, "Crystals are still hopping out")
	_steps(0.6)
	_check(loot.lying_count() == dropped, "After the hop they lie on the ground (%d)" % loot.lying_count())
	var spread := 0.0
	for id in loot.lying_near(far, 5.0):
		spread = maxf(spread, Vector2(loot.pos[id].x - far.x, loot.pos[id].z - far.z).length())
	_check(spread > 0.4 and spread < 2.0, "They land in a ring around the kill (%.2f m)" % spread)

	# ---- No decay; empty remains sink and vanish.
	var remains_id: int = world.remains_order[0]
	_steps(float(TUNING.CORPSE_LIFE.normal) - TUNING.CORPSE_SINK_SECONDS * 0.5)
	_check(world.remains.has(remains_id) and float(world.corpse_view.corpses[remains_id].decay) > 0.2, "Remains sink at the end of their life (%.2f)" % float(world.corpse_view.corpses[remains_id].decay) if world.corpse_view.corpses.has(remains_id) else "Remains sink at the end of their life (gone)")
	_steps(TUNING.CORPSE_SINK_SECONDS + 1.0)
	_check(not world.remains.has(remains_id) and not world.corpse_view.has(remains_id), "Remains vanish after %.0f s" % float(TUNING.CORPSE_LIFE.normal))
	_steps(90.0)
	_check(loot.lying_count() == dropped and absf(loot.total(LOOT.Kind.BIOMASS) - TUNING.CORPSE_BIOMASS * world.evolution.biomass_multiplier()) < 0.01, "Crystals never decay (%d after 2 min)" % loot.lying_count())

	# ---- Magnet: in the radius they fly (not teleport) and arrive.
	world.model.population = 10
	swarm.set_population(10, false)
	world.unit_points_valid = false
	var radius: float = world.magnet_radius()
	swarm.position = far + Vector3(-radius + 0.6, 0.0, 0.0)
	world.kill_popups.clear()
	world.step(0.05)
	_check(loot.flying_count() > 0 and loot.count() == dropped, "Crystals in the radius start to fly (%d flying)" % loot.flying_count())
	swarm.position = far
	world.unit_points_valid = false
	_steps(0.5)
	_check(world.kill_popups.size() == 1 and int(world.kill_popups[0].biomass) == int(round(TUNING.CORPSE_BIOMASS)) and int(world.kill_popups[0].dna) == 10, "Arrivals add up into ONE popup (%s)" % str(world.kill_popups))
	_steps(1.5)
	_check(loot.count() == 0, "Every crystal arrived (%d left)" % loot.count())
	_check(world.evolution.dna == dna_before + 10 or world.choosing(), "DNA credited on arrival (%d)" % world.evolution.dna)
	_check(world.model.consumed_biomass > TUNING.CORPSE_BIOMASS - 0.01, "Biomass credited on arrival (%.2f)" % world.model.consumed_biomass)
	_check(world.crystals_collected == dropped, "Collected count (%d)" % world.crystals_collected)
	_check(world.kill_popups.is_empty(), "The popup fades after the burst")

	# ---- Radius grows with the swarm, Lockduft, Witterung and Rally.
	world.model.population = 1
	var r1: float = world.magnet_radius()
	world.model.population = 250
	var r250: float = world.magnet_radius()
	_check(r1 > 3.0 and r1 < 4.0 and r250 > 7.0 and r250 < 8.5, "Radius 1 -> %.1f m, 250 -> %.1f m" % [r1, r250])
	world.evolution.ranks["magnet"] = 2
	_check(absf(world.magnet_radius() - r250 * 1.24) < 0.01, "Lockduft rank 2 = +24 %% (%.2f)" % world.magnet_radius())
	world.evolution.ranks.erase("magnet")
	world.evolution.mods["magnet"] = 1.4
	_check(absf(world.magnet_radius() - r250 * 1.4) < 0.01, "Witterung (meta) scales the radius")
	world.evolution.mods["magnet"] = 1.0
	swarm.rally_pressed = true
	_check(absf(world.magnet_radius() - r250 * TUNING.MAGNET_RALLY) < 0.01, "Rally widens the pull")
	swarm.rally_pressed = false

	# ---- Bundling: a crowded cell merges into bigger crystals, value kept.
	var spot := Vector3(-38.75, 0.0, 11.25)
	for index in 40:
		loot.drop(LOOT.Kind.BIOMASS, 1.0, spot, spot + Vector3(0.1 * float(index % 5), 0.0, 0.1 * float(index / 5)), false)
	var bundled: Array = loot.lying_near(spot, 2.0)
	_check(bundled.size() == TUNING.LOOT_CELL_CROWD, "40 crystals in one cell bundle into %d (got %d)" % [TUNING.LOOT_CELL_CROWD, bundled.size()])
	var bundled_value := 0.0
	var biggest := 0
	for id in bundled:
		bundled_value += loot.value[id]
		biggest = maxi(biggest, loot.tier[id])
	_check(absf(bundled_value - 40.0) < 0.01 and biggest == 2, "Bundled value kept (%.1f), the host grew to a big crystal" % bundled_value)

	# ---- Etappe 17b: no population limit - a swarm of 250 keeps taking biomass.
	world.model.population = 250
	world.model.biomass_bank = 0.0
	swarm.set_population(250, false)
	world.unit_points_valid = false
	swarm.position = spot
	var dna_now: int = world.evolution.dna
	loot.drop(LOOT.Kind.DNA, 5.0, spot, spot + Vector3(0.6, 0.0, 0.0), false)
	_steps(2.5)
	_clear_offers()
	_check(world.model.population > 250, "A swarm of 250 keeps growing (%d)" % world.model.population)
	_check(world.evolution.dna >= dna_now + 5 or world.evolution.level > 0, "DNA still flies")
	_clear_offers()

	# ---- Lockruf: every crystal of the map flies in as a chain.
	world.model.population = 20
	world.model.biomass_bank = 0.0
	swarm.set_population(20, false)
	world.unit_points_valid = false
	swarm.position = Vector3.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for index in 200:
		var at := Vector3(rng.randf_range(-90.0, 90.0), 0.0, rng.randf_range(-90.0, 90.0))
		loot.drop(LOOT.Kind.BIOMASS if index % 4 else LOOT.Kind.DNA, 0.4, at, at, false)
	var before_lure: int = loot.count()
	var bio_before: float = loot.total(LOOT.Kind.BIOMASS)
	var lure: Node3D = world.drop_lure(swarm.position + Vector3(4.0, 0.0, 0.0))
	_check(lure != null and loot.lures.size() == 1, "Lockruf lies on the map")
	_check(world._map_state().corpses.size() >= 6, "Minimap marks crystal cells and the Lockruf")
	# Walk towards it: it jumps into the magnet like a crystal.
	swarm.position = lure.position + Vector3(-2.5, 0.0, 0.0)
	world.unit_points_valid = false
	for index in 40:
		if world.lures_collected > 0:
			break
		world.step(0.05)
	_check(world.lures_collected == 1 and loot.vacuums == 1, "Reaching the Lockruf calls every crystal")
	_check(loot.flying_count() >= before_lure - 5, "The whole map is on its way (%d / %d)" % [loot.flying_count(), before_lure])
	var chain_start: int = loot.count()
	_steps(0.6)
	var mid: int = loot.count()
	_check(mid < chain_start and mid > 0, "They arrive as a chain, not at once (%d -> %d)" % [chain_start, mid])
	_steps(3.0)
	_clear_offers()
	_steps(1.0)
	_clear_offers()
	_check(loot.count() == 0, "Everything arrived within ~4 s (%d left)" % loot.count())
	_check(world.model.consumed_biomass > bio_before * 0.9, "The biomass of the whole map was credited")

	# ---- Guaranteed Lockruf from the elite and the Bog King.
	var elite: Variant = world.spawn_elite(swarm.position + Vector3(20.0, 0.0, 0.0))
	elite.health = 0.0
	world._resolve_death(elite, "hunter")
	_check(loot.lures.size() == 1, "Elite hunter drops a Lockruf")
	var elite_crystals: int = loot.count() - loot.count_of(LOOT.Kind.AMBER)
	_check(elite_crystals >= 2 and elite_crystals <= TUNING.LOOT_MAX_PER_KILL, "Elite bursts into %d crystals" % elite_crystals)
	_check(loot.count_of(LOOT.Kind.AMBER) >= 1, "... plus Bernstein coins (%d)" % loot.count_of(LOOT.Kind.AMBER))

	# ---- Performance: 1000 lying crystals cost little per step.
	for lure_entry in loot.lures:
		lure_entry.node.queue_free()
	loot.lures.clear()
	loot.clear()
	loot.soft_cap = 100000
	rng.seed = 11
	for index in 1000:
		var at := Vector3(rng.randf_range(-120.0, 120.0), 0.0, rng.randf_range(-120.0, 120.0))
		# Distinct cells so none bundle: the worst case for the grid.
		loot.drop(LOOT.Kind.BIOMASS, 1.0, at, at, false)
	_check(loot.lying_count() >= 980, "1000 crystals lie on the map (%d)" % loot.lying_count())
	# Swarm in the middle of them, full (biomass stays): every step scans the
	# cells of a 7 m radius but launches nothing - the steady cost of lying loot.
	swarm.position = Vector3.ZERO
	var points: PackedVector3Array = swarm.unit_world_points()
	var started := Time.get_ticks_usec()
	for index in 200:
		loot.step(0.016, swarm.position, 7.0, points, false)
	var per_step := float(Time.get_ticks_usec() - started) / 200.0
	print("LOOT step with %d lying crystals: %.3f ms" % [loot.lying_count(), per_step / 1000.0])
	_check(per_step < 1000.0, "Magnet step with 1000 crystals under 1 ms (%.3f ms)" % (per_step / 1000.0))

	# ---- Reset clears everything.
	world.reset_run()
	_check(world.loot != null and world.loot.count() == 0 and world.remains.is_empty() and world.crystals_collected == 0, "Reset clears crystals and remains")

	if failures.is_empty():
		print("PASS loot_magnet: burst 1-6 crystals, hop + ring, no decay, remains sink after %.0f s, magnet flight + credit + one popup, radius %.1f-%.1f m (Lockduft/Witterung/Rally), bundling, no population limit, Lockruf chain over the map, elite Lockruf, 1000 crystals %.3f ms" % [float(TUNING.CORPSE_LIFE.normal), r1, r250, per_step / 1000.0])
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


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
	world.hunters_unlocked = true


func _clear_offers() -> void:
	while world.choosing():
		world.choose_mutation(0)


func _steps(seconds: float) -> void:
	for index in int(round(seconds / 0.05)):
		world.step(0.05)
		_clear_offers()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
