extends SceneTree

# Etappe 17 Welle 2 - Schreine: the swarm centre in the ring charges a shrine
# in ~4 s, leaving pauses (the charge stays), a full shrine opens a 1-of-3 stat
# choice of at least rare through the level-up screen (no DNA, no level), and
# every shrine works once.
const STATS = preload("res://scripts/progression/stats.gd")
const SHRINES = preload("res://scripts/shrines.gd")
var failures: Array[String] = []
var world: Variant
var swarm: Variant
var shrines: Variant


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
	shrines = world.shrines
	_check(shrines != null and shrines.shrines.size() >= 1, "Seed 0: fallback shrines exist (%d)" % shrines.shrines.size())
	_quiet()
	for entry in shrines.shrines:
		entry.at = Vector3(600, 0, 600)
	var shrine: Dictionary = shrines.spawn(Vector3(25, 0, 0))
	var evo: Variant = world.evolution
	var level: int = evo.level
	var dna: int = evo.dna

	# ---- Charging, pause on leaving.
	swarm.position = shrine.at + Vector3(10, 0, 0)
	_steps(1.0)
	_check(float(shrine.charge) == 0.0, "Outside the ring nothing charges")
	swarm.position = shrine.at + Vector3(1.5, 0, 0)
	_steps(2.0)
	_check(absf(float(shrine.charge) - 0.5) < 0.03, "Two seconds inside: half charged (%.2f)" % float(shrine.charge))
	swarm.position = shrine.at + Vector3(10, 0, 0)
	_steps(3.0)
	_check(absf(float(shrine.charge) - 0.5) < 0.03, "Leaving pauses, the charge stays (%.2f)" % float(shrine.charge))
	_check(not world.choosing(), "No choice yet")
	swarm.position = shrine.at
	var opened := false
	for index in 60:
		world.unit_points_valid = false
		world.step(0.05)
		if world.choosing():
			opened = true
			break
	_check(opened and float(shrine.charge) >= 1.0, "Full after ~4 s in total: the choice opens")
	_check(evo.offer_source == "shrine" and evo.offers.size() == 3, "Three stat cards from the shrine (%s, %d)" % [evo.offer_source, evo.offers.size()])
	var rare := true
	for entry in evo.offers:
		if evo.kind_of(String(entry[0])) != "trait" or not STATS.rarity_at_least(String(entry[3]), "rare"):
			rare = false
	_check(rare, "Only stats, each at least rare")
	var id := String(evo.offers[0][0])
	var rank_before: int = evo.rank(id)
	world.choose_mutation(0)
	_check(not world.choosing() or evo.offer_source == "level", "Choosing closes the shrine choice")
	_check(evo.rank(id) == rank_before + 1, "The stat rose (%s %d -> %d)" % [id, rank_before, evo.rank(id)])
	_check(evo.level == level and evo.dna == dna, "A shrine costs no DNA and counts no level")
	_check(shrine.done and shrines.completed == 1, "The shrine is spent")

	# ---- Once per shrine.
	_steps(6.0)
	_check(not world.choosing(), "A spent shrine never opens again")

	# ---- Reroll keeps the shrine quality.
	var second: Dictionary = shrines.spawn(Vector3(-25, 0, 0))
	evo.rerolls = 1
	_check(shrines.charge_now(second), "A second shrine opens its own choice")
	evo.reroll()
	var still_rare: bool = evo.offer_source == "shrine" and evo.offers.size() == 3
	for entry in evo.offers:
		if not STATS.rarity_at_least(String(entry[3]), "rare"):
			still_rare = false
	_check(still_rare, "A reroll keeps shrine cards (rare or better)")
	evo.skips = 1
	var dna_skip: int = evo.dna
	evo.skip()
	_check(evo.dna == dna_skip and evo.offers.is_empty(), "Skipping a shrine choice costs no DNA")

	# ---- A shrine waits while another choice is open.
	var third: Dictionary = shrines.spawn(Vector3(0, 0, 25))
	evo.dna = evo.threshold()
	evo.earn(0)
	_check(world.choosing() and evo.offer_source == "level", "Setup: a level choice is open")
	_check(not shrines.charge_now(third) and third.pending, "A full shrine waits for the open level choice")
	world.choose_mutation(0)
	swarm.position = Vector3(0, 0, 70)
	world.unit_points_valid = false
	world.step(0.05)
	_check(world.choosing() and evo.offer_source == "shrine", "... and opens right after it")
	world.choose_mutation(0)
	_check(world._map_state().has("shrines"), "The minimap data carries shrines")

	_finish()


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
	for cocoon in world.chests.cocoons:
		cocoon.at = Vector3(500, 0, 500)
	for knoll in world.powerups.knolls:
		knoll.at = Vector3(-500, 0, 500)


func _steps(seconds: float) -> void:
	for index in int(round(seconds / 0.05)):
		world.unit_points_valid = false
		world.step(0.05)
		while world.choosing() and world.evolution.offer_source == "level":
			world.choose_mutation(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("PASS shrines: charge, pause, 1 of 3 rare stats, no DNA, once, reroll/skip, waits for other choices")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL shrines: %d" % failures.size())
		quit(1)
