extends SceneTree

const RUN_MODEL = preload("res://scripts/run_model.gd")
const HUNTER = preload("res://scripts/hunter.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var model = RUN_MODEL.new()
	var id: int = model.add_corpse(Vector3(12, 0, 0), 12.0)
	model.advance(90.0)
	_check(is_equal_approx(model.pressure(), 2.0), "Pressure doubles after 90 seconds")
	model.advance(86400.0)
	_check(not model.extinct and is_finite(model.pressure()), "24-hour model remains finite and has no timer ending")
	_check(model.remaining_biomass(id) == 12.0, "Long run preserves biomass")
	model.apply_loss(1000)
	var stopped: float = model.elapsed
	model.advance(100.0)
	_check(model.extinct and model.population == 0 and model.elapsed == stopped, "Extinction freezes run time")
	_check(model.harvest(id, 12.0) == 0.0 and model.add_corpse(Vector3.ZERO, 1.0) == -1, "Dead run cannot revive from harvesting")

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
	var hunter: Variant = world._spawn_hunter(Vector3(2.5, 0, 0))
	hunter.step(1.1, Vector3.ZERO, 1.0)
	hunter.step(0.01, Vector3.ZERO, 1.0)
	_check(hunter.state == HUNTER.State.WARNING and hunter.warning.visible, "Hunter announces attack")
	var locked: Vector3 = hunter.attack_center
	var dodge: int = hunter.step(1.3, Vector3(6, 0, 0), 1.0)
	_check(hunter.attack_center == locked and dodge == 0, "Warning stays fixed and leaving avoids damage")
	hunter.step(2.0, Vector3.ZERO, 1.0)
	hunter.step(0.01, Vector3.ZERO, 1.0)
	_check(hunter.step(1.3, Vector3.ZERO, 1.0) == 6, "Standing in the ring resolves one hit")
	_check(hunter.step(0.1, Vector3.ZERO, 1.0) == 0, "Recovery never repeats a hit")
	hunter.step(2.0, Vector3.ZERO, 8.0)
	hunter.step(0.01, Vector3.ZERO, 8.0, Vector3(7, 0, 0))
	_check(hunter.attack_center.distance_to(Vector3(7, 0, 0)) < 0.01, "High-pressure hunter leads movement")
	_check(hunter.step(1.25, Vector3(8.75, 0, 0), 8.0) > 0, "Blind straight-line running can be intercepted")

	world.reset_run()
	world._create_corpse(Vector3(30, 0, 0), 12.0)
	world.model.population = 250
	swarm.set_population(250)
	swarm.set_controls(Vector2.ZERO, true)
	hunter = world._spawn_hunter(Vector3(0.5, 0, 0))
	hunter.state = HUNTER.State.CHASE
	for tick in 60:
		world.step(1.0 / 60.0)
	_check(world.hunters.is_empty(), "Normal swarm combat defeats hunter before its attack")
	_check(world.model.corpses.size() == 2 and world.model.population == 250, "Hunter yields biomass without consuming it at cap")
	_check(world.model.remaining_biomass(1) == 12.0, "Old corpse survives hunter defeat")

	world.reset_run()
	world._create_corpse(Vector3(30, 0, 0), 12.0)
	world._spawn_hunter(Vector3(2.5, 0, 0))
	# Hits count per animal and swarm processing is off, so the formation never
	# closes ranks by itself: gather it inside the ring.
	for unit in swarm.units:
		unit.position = Vector3.ZERO
	for tick in 1500:
		world.step(1.0 / 60.0)
		if world.model.extinct:
			break
	_check(world.model.extinct and hud.extinct and swarm.units.is_empty(), "Repeated real attacks produce extinction and result screen")
	stopped = world.model.elapsed
	world.step(30.0)
	_check(world.model.elapsed == stopped and world.model.corpses.size() == 1, "Extinction freezes spawns and preserves run resources")
	hud._press(-2, hud._action_rect().get_center())
	_check(world.model.population == 25 and not world.model.extinct, "Result button starts another run")
	_check(world.model.corpses.is_empty() and world.prey.size() == 3 and world.hunters.is_empty(), "Restart clears previous world")
	_check(world.model.elapsed == 0.0 and world.model.kills == 0 and hud.movement_pointer == -1, "Restart resets statistics and input")

	world.toggle_pause()
	world.step(60.0)
	_check(world.model.elapsed == 0.0 and hud.paused, "Pause freezes elapsed time and spawns")
	world.toggle_pause()
	world.model.elapsed = 720.0
	world._create_corpse(Vector3(-50, 0, -50), 12.0)
	for tick in 600:
		swarm.position.x += 1.0
		world.step(0.1)
	_check(not world.model.extinct and world.model.elapsed > 720.0, "Survival continues beyond twelve minutes")
	_check(world.hunters.size() <= 12 and world.prey.size() <= 5, "Endless spawns respect active budgets")
	_check(world.model.remaining_biomass(1) == 12.0, "Distant corpse survives director and enemy recycling")
	await process_frame
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS: pressure, warning, dodge, damage, hunter kill, extinction, restart, pause, spawn budgets, persistence")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
