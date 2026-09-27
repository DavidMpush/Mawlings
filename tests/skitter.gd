extends SceneTree

const SKITTER = preload("res://scripts/skitter.gd")
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
	var arena: Variant = scene.get_node("Arena")
	var hud: Variant = scene.get_node("HUD/Controls")
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)
	var skitter: Variant = world._spawn_skitter(Vector3(-4, 0, 0))
	skitter.state = SKITTER.State.CHASE
	skitter.step(0.01, Vector3.ZERO, 1)
	check(skitter.state == SKITTER.State.WARNING and skitter.warning.visible, "Locked visible sprint warning")
	var end: Vector3 = skitter.dash_end
	check(skitter.warning_distance(Vector3.ZERO) < 0.01, "Lane points through original target")
	skitter.step(1.0, Vector3(0, 0, 3), 1)
	check(skitter.dash_end == end and skitter.state == SKITTER.State.DASH, "Lane stays fixed after dodge")
	check(skitter.step(0.4, Vector3(0, 0, 3), 1) == 0, "Side step evades sprint")
	check(not skitter.warning.visible and skitter.step(0.1, Vector3.ZERO, 1) == 0, "Recovery never repeats hit")
	skitter.step(2.0, Vector3.ZERO, 1)
	skitter.position = Vector3(-4, 0, 0)
	skitter.step(0.01, Vector3.ZERO, 1)
	skitter.step(1.0, Vector3.ZERO, 1)
	check(skitter.step(0.4, Vector3.ZERO, 1) == 4, "Standing in sprint takes exactly one hit")
	world.reset_run()
	var rock: Vector3 = arena.obstacle_centers(Vector2i.ZERO)[0]
	var before := rock + Vector3(4, 0, 0)
	var blocked: Vector3 = arena.clear_line(before, rock - Vector3(3, 0, 0), 0.6)
	check(blocked.distance_to(before) < 3.0 and blocked.distance_to(rock) >= arena.OBSTACLE_RADIUS + 0.6 - 0.01, "Stone stops sprint before cover")
	skitter = world._spawn_skitter(rock + Vector3(arena.OBSTACLE_RADIUS + 0.61, 0, 0))
	skitter._lock_dash(rock - Vector3(4, 0, 0), 1)
	check(skitter.state == SKITTER.State.RECOVERY and not skitter.warning.visible, "Blocked zero-length dash never hits invisibly")
	world.reset_run()
	skitter = world._spawn_skitter(before)
	skitter.state = SKITTER.State.CHASE
	var behind := rock - Vector3(4, 0, 0)
	for tick in 600:
		skitter.step(0.05, behind, 1)
		if skitter.position.distance_to(behind) < 3:
			break
	check(skitter.position.distance_to(behind) < 3, "Skitter routes around stone toward swarm")
	world.reset_run()
	# Stage 09: skitters start later and join once the swarm has grown.
	world.model.population = TUNING.SKITTER_POPULATION_STEP * 2
	swarm.set_population(world.model.population, false)
	world.model.elapsed = TUNING.FIRST_SKITTER_SECONDS + 1.0
	world.skitter_clock = 0
	world.step(0.05)
	check(world.skitters.size() == 1 and hud.skitters == 1, "Director and HUD spawn Skitter")
	world.reset_run()
	world.model.population = 250
	swarm.set_population(250)
	skitter = world._spawn_skitter(Vector3(0.5, 0, 0))
	skitter.state = SKITTER.State.CHASE
	skitter.health = 0.01
	world.step(0.01)
	check(world.skitters.is_empty() and world.evolution.dna == 15, "Kill awards DNA once")
	check(world.model.corpses.size() == 1 and is_equal_approx(world.model.corpses[0].remaining, TUNING.SKITTER_BIOMASS), "Skitter leaves persistent biomass at cap")
	check(not is_instance_valid(skitter.warning) or skitter.warning.is_queued_for_deletion(), "Warning removed on kill")
	world.reset_run()
	# Stage 09 lone start: the hit check uses a 25-strong swarm.
	world.model.population = 25
	swarm.set_population(25, false)
	skitter = world._spawn_skitter(Vector3(-4, 0, 0))
	skitter.state = SKITTER.State.DASH
	skitter.remaining = 0.01
	skitter.dash_start = Vector3(-4, 0, 0)
	skitter.dash_end = Vector3(3, 0, 0)
	skitter.damage = 4
	# Hits count per animal: gather the whole swarm inside the lane.
	for unit in swarm.units:
		unit.position = Vector3.ZERO
	world.step(0.05)
	check(world.model.population == 21 and hud.last_loss == 4, "Sprint damage reaches world and HUD")
	world.step(0.05)
	check(world.model.population == 21, "Single resolved hit")
	world.reset_run()
	check(world.skitters.is_empty() and world.skitter_clock > 0 and hud.skitters == 0, "Restart clears second threat")
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
	else:
		print("PASS skitter: warning, lateral dodge, single hit, stone cover, director, DNA, persistent biomass, reset")
		quit(0)
