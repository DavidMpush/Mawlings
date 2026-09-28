extends SceneTree

const EVOLUTION = preload("res://scripts/evolution.gd")
const TUNING = preload("res://scripts/tuning.gd")
const STATS = preload("res://scripts/progression/stats.gd")
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var evo = EVOLUTION.new()
	evo.rng.seed = 19
	evo.earn(19)
	check(evo.offers.is_empty(), "No early offer")
	evo.earn(1)
	check(evo.offers.size() == 3, "Three offers at threshold")
	check(evo.offers[0][0] != evo.offers[1][0] and evo.offers[1][0] != evo.offers[2][0] and evo.offers[0][0] != evo.offers[2][0], "Unique offers")
	for offer in evo.offers:
		# Etappe 17: Level geben nur Werte, jede Karte mit Seltenheit.
		check(evo.kind_of(offer[0]) == "trait", "Level offer is a stat (%s)" % offer[0])
		check(offer.size() >= 4 and ["common", "rare", "epic", "legendary"].has(offer[3]), "Offer has a rarity")
	check(not evo.choose(-1) and not evo.choose(3), "Reject invalid selection")
	evo.earn(1000000)
	# Etappe 17c: 14 Standard-Werte (ohne Regeneration, mit Lebensraub) mit je 5 Rängen = 70 Wahlen.
	var picks := 0
	while not evo.offers.is_empty() and picks < 200:
		check(evo.choose(0), "Queued level remains selectable")
		picks += 1
	check(picks == 70, "70 stat picks until complete (%d)" % picks)
	check(evo.complete() and evo.offers.is_empty(), "All stats complete without deadlock")
	check(evo.slots_used("attack") == 0, "Levels never give weapons")
	for id in evo.ranks:
		check(evo.rank(id) == 5, "Rank cap 5 (%s)" % id)
	evo = EVOLUTION.new()
	for id in ["bite", "rally", "brood", "magnet", "armor", "evade"]:
		evo.ranks[id] = 5
	var bite: float = 1.0 + 5.0 * float(STATS.definition("bite").step)
	var rally: float = 1.0 + 5.0 * float(STATS.definition("rally").step)
	check(is_equal_approx(evo.damage_multiplier(false), bite), "Biss je Rang (%.3f)" % evo.damage_multiplier(false))
	check(is_equal_approx(evo.damage_multiplier(true), bite * rally), "Rudelinstinkt je Rang bei Rally")
	check(is_equal_approx(evo.harvest_multiplier(), 1.0 + 5.0 * float(STATS.definition("brood").step)), "Brutrate: biomass per collected crystal")
	check(is_equal_approx(evo.magnet_multiplier(), 1.0 + 5.0 * float(STATS.definition("magnet").step)), "Lockduft: magnet radius")
	check(is_equal_approx(evo.biomass_multiplier(), 1.0), "Future biomass only from the strain")
	var armor: float = 5.0 * float(STATS.definition("armor").step)
	var evade: float = 5.0 * float(STATS.definition("evade").step)
	check(evo.loss_after_armor(100, false) == ceili(100.0 * (1.0 - armor - evade) - 0.0001) and evo.loss_after_armor(100, true) == ceili(100.0 * (1.0 - armor) - 0.0001), "Conditional armor (%d/%d)" % [evo.loss_after_armor(100, false), evo.loss_after_armor(100, true)])
	check(evo.loss_after_armor(1, false) == 1, "No invulnerability")
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	var world: Variant = scene.get_node("HuntWorld")
	var swarm: Variant = scene.get_node("Swarm")
	var hud: Variant = scene.get_node("HUD/Controls")
	world.set_process(false)
	swarm.set_process(false)
	world.reset_run()
	# Etappe 16: DNA arrives with the collected crystals.
	world._kill_prey(world.prey[0])
	check(world.evolution.dna == 0, "No DNA before the crystals arrive")
	world.collect_loot_now()
	check(world.evolution.dna == 10 and not world.choosing(), "Prey DNA exactly once")
	world.collect_loot_now()
	check(world.evolution.dna == 10, "Collected crystals never pay twice")
	hud.movement_vector = Vector2.ONE
	world._kill_prey(world.prey[0])
	world.drop_loot(Vector3(40, 0, 0), 5.0)
	world.collect_loot_now()
	check(world.choosing() and hud.movement_vector == Vector2.ZERO, "Second kill opens and clears input")
	world.drop_loot(Vector3(40, 0, 0), 5.0)
	var before: float = world.model.elapsed
	var biomass: float = world.loot.total(0)
	var spawn_before: float = world.hunter_clock
	world.step(30)
	check(world.model.elapsed == before and world.hunter_clock == spawn_before and world.loot.total(0) == biomass, "Entire world frozen")
	world.toggle_pause()
	world.choose_mutation(0)
	check(world.evolution.level == 0, "Manual pause blocks selection")
	world.toggle_pause()
	hud._press(3, hud._mutation_rect(0).get_center())
	check(world.evolution.level == 1 and not world.choosing(), "Touch selection")
	world._kill_prey(world.prey[0])
	check(is_equal_approx(world.loot.total(0) - biomass, TUNING.CORPSE_BIOMASS), "Prey biomass without multiplier")
	world.collect_loot_now()
	world._award_dna(world.evolution.threshold())
	var key := InputEventKey.new()
	key.keycode = KEY_1
	key.pressed = true
	hud._input(key)
	check(world.evolution.level == 2, "Keyboard selection")
	world.reset_run()
	# Etappe 17: a fresh run (also without RunConfig) keeps only its start weapon.
	var fresh: Dictionary = world.evolution.ranks
	var start_only: bool = fresh.size() == 1 and int(fresh.get(world.evolution.signature, 0)) == world.evolution.SIGNATURE_START_RANK
	check(world.evolution.level == 0 and start_only and world.evolution.dna == 0 and not world.choosing(), "Restart clears all evolution (%s)" % [fresh])
	world.evolution.ranks["brood"] = 3
	world.drop_loot(swarm.position, 12)
	for tick in 30:
		world.step(0.05)
	check(is_equal_approx(world.model.consumed_biomass, 12.0 * (1.0 + 3.0 * float(STATS.definition("brood").step))), "Brutrate: more biomass per collected crystal (%.2f)" % world.model.consumed_biomass)
	world.reset_run()
	world.model.population = 250
	swarm.set_population(250)
	var hunter: Variant = world._spawn_hunter(Vector3.ZERO)
	hunter.state = hunter.State.CHASE
	hunter.health = 0.01
	world.step(0.01)
	world.collect_loot_now()
	world.collect_loot_now()
	check(world.evolution.dna == 20 and world.choosing() and world.hunters.is_empty(), "Hunter kill awards DNA once")
	world.reset_run()
	# Stage 09 lone start: the modifier checks below use a 25-strong swarm.
	world.model.population = 25
	swarm.set_population(25, false)
	world.evolution.ranks["bite"] = 3
	world.evolution.ranks["rally"] = 3
	swarm.rally_pressed = true
	hunter = world._spawn_hunter(Vector3.ZERO)
	hunter.state = hunter.State.RECOVERY
	hunter.remaining = 10
	# Melee counts biting animals: the whole swarm surrounds the hunter.
	for unit in swarm.units:
		unit.position = Vector3.ZERO
	var health: float = hunter.health
	world.step(0.1)
	var expected: float = 4.0 * 1.55 * (1.0 + 3.0 * float(STATS.definition("bite").step)) * (1.0 + 3.0 * float(STATS.definition("rally").step)) * 0.1
	check(is_equal_approx(health - hunter.health, expected), "Damage modifier wired into combat (%.3f / %.3f)" % [health - hunter.health, expected])
	world.reset_run()
	world.model.population = 25
	swarm.set_population(25, false)
	world.evolution.ranks["armor"] = 5
	world.evolution.ranks["evade"] = 5
	hunter = world._spawn_hunter(Vector3(3, 0, 0))
	hunter.state = hunter.State.WARNING
	hunter.remaining = 0.01
	hunter.attack_center = Vector3.ZERO
	hunter.attack_power = 20
	# Hits count per animal: gather the whole swarm inside the ring.
	for unit in swarm.units:
		unit.position = Vector3.ZERO
	world.step(0.02)
	var kept: int = 25 - ceili(20.0 * (1.0 - 5.0 * float(STATS.definition("armor").step) - 5.0 * float(STATS.definition("evade").step)) - 0.0001)
	check(world.model.population == kept, "Armor modifier wired into incoming hit (%d, expected %d)" % [world.model.population, kept])
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
	else:
		print("PASS evolution: stat offers with rarity, 5 ranks, modifiers, freeze, input, persistence, reset, hunter reward")
		quit(0)
