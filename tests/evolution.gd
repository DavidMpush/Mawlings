extends SceneTree

const EVOLUTION = preload("res://scripts/evolution.gd")
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
	check(not evo.choose(-1) and not evo.choose(3), "Reject invalid selection")
	evo.earn(10000)
	for i in 18:
		check(evo.choose(0), "Queued evolution remains selectable")
	check(evo.complete() and evo.offers.is_empty(), "All ranks complete without deadlock")
	for mutation in evo.TRAITS:
		check(evo.rank(mutation[0]) == 3, "Rank cap")
	check(is_equal_approx(evo.damage_multiplier(false), 1.75), "Jaws damage")
	check(is_equal_approx(evo.damage_multiplier(true), 2.8), "Rally damage")
	check(is_equal_approx(evo.harvest_multiplier(), 1.9), "Brood harvest")
	check(is_equal_approx(evo.biomass_multiplier(), 1.75), "Future biomass")
	check(evo.loss_after_armor(100, false) == 40 and evo.loss_after_armor(100, true) == 70, "Conditional armor")
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
	world._kill_prey(world.prey[0])
	check(world.evolution.dna == 10 and not world.choosing(), "Prey DNA exactly once")
	hud.movement_vector = Vector2.ONE
	world._kill_prey(world.prey[0])
	check(world.choosing() and hud.movement_vector == Vector2.ZERO, "Second kill opens and clears input")
	var before: float = world.model.elapsed
	var biomass: float = world.model.corpses[0].remaining
	var spawn_before: float = world.hunter_clock
	world.step(30)
	check(world.model.elapsed == before and world.hunter_clock == spawn_before and world.model.corpses[0].remaining == biomass, "Entire world frozen")
	world.toggle_pause()
	world.choose_mutation(0)
	check(world.evolution.level == 0, "Manual pause blocks selection")
	world.toggle_pause()
	hud._press(3, hud._mutation_rect(0).get_center())
	check(world.evolution.level == 1 and not world.choosing(), "Touch selection")
	world.evolution.ranks["glutton"] = 3
	world._kill_prey(world.prey[0])
	check(world.model.corpses[0].remaining == biomass and world.model.corpses[-1].initial == 21, "Only future kills gain biomass")
	world._award_dna(20)
	var key := InputEventKey.new()
	key.keycode = KEY_1
	key.pressed = true
	hud._input(key)
	check(world.evolution.level == 2, "Keyboard selection")
	world.reset_run()
	check(world.evolution.level == 0 and world.evolution.ranks.is_empty() and world.evolution.dna == 0 and not world.choosing(), "Restart clears all evolution")
	world.evolution.ranks["brood"] = 3
	world._create_corpse(Vector3.ZERO, 12)
	world.step(0.5)
	check(is_equal_approx(world.model.consumed_biomass, 3.8), "Harvest modifier wired into world")
	world.reset_run()
	world.model.population = 250
	swarm.set_population(250)
	var hunter: Variant = world._spawn_hunter(Vector3.ZERO)
	hunter.state = hunter.State.CHASE
	hunter.health = 0.01
	world.step(0.01)
	check(world.evolution.dna == 20 and world.choosing() and world.hunters.is_empty(), "Hunter kill awards DNA once")
	world.reset_run()
	world.evolution.ranks["jaws"] = 3
	world.evolution.ranks["pack"] = 3
	swarm.rally_pressed = true
	hunter = world._spawn_hunter(Vector3.ZERO)
	hunter.state = hunter.State.RECOVERY
	hunter.remaining = 10
	var health: float = hunter.health
	world.step(0.1)
	check(is_equal_approx(health - hunter.health, 4.0 * 1.55 * 2.8 * 0.1), "Damage modifier wired into combat")
	world.reset_run()
	world.evolution.ranks["armor"] = 3
	world.evolution.ranks["scatter"] = 3
	hunter = world._spawn_hunter(Vector3(3, 0, 0))
	hunter.state = hunter.State.WARNING
	hunter.remaining = 0.01
	hunter.attack_center = Vector3.ZERO
	hunter.attack_power = 20
	world.step(0.02)
	check(world.model.population == 17, "Armor modifier wired into incoming hit")
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
	else:
		print("PASS evolution: ranks, modifiers, freeze, input, persistence, reset, hunter reward")
		quit(0)
