extends SceneTree

# Stage 01 contract: visual motion and feedback never change game state.
const BOG_KING = preload("res://scripts/bog_king.gd")
const FX = preload("res://scripts/fx.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var world: Variant = scene.get_node("HuntWorld")
	var swarm: Variant = scene.get_node("Swarm")
	var hud: Variant = scene.get_node("HUD/Controls")
	world.set_process(false)

	swarm.set_population(10)
	_check(swarm.units.size() == 10, "Animated shrink removes units from the live list at once")
	swarm.set_population(25, false)
	_check(swarm.units.size() == 25, "Instant regrow restores visible units")
	swarm.react_to_hit(3, swarm.position + Vector3(1.0, 0.0, 0.0))
	_check(swarm.units.size() == 25 and swarm.population == 25, "Hit reaction alone never changes population")
	swarm.set_focus(swarm.position + Vector3(2.0, 0.0, 0.0), 1)
	swarm.clear_focus()

	world.reset_run()
	# Stage 09 lone start: use a 25-strong swarm for the hit checks.
	world.model.population = 25
	swarm.set_population(25, false)
	_check(not world._apply_hit(3, swarm.position, 0.2), "Survivable hit does not end the run")
	_check(world.model.population == 22 and swarm.units.size() == 22 and world.hit_feedback > 0.0, "Resolved hit updates population, visuals and HUD feedback once")

	var boss: Variant = world._spawn_boss(swarm.position + Vector3(40.0, 0.0, 0.0))
	world._update_hud("")
	_check(hud.boss_pointer.is_finite(), "Off-screen Bog King gets an edge pointer")
	var pointer: Vector2 = hud.boss_pointer
	_check(pointer.x > hud.size.x * 0.5, "Pointer sits on the side of the boss")
	boss.position = swarm.position + Vector3(0.0, 0.0, -3.0)
	world._update_hud("")
	_check(not hud.boss_pointer.is_finite(), "Visible Bog King has no pointer")

	boss.state = BOG_KING.State.CHASE
	boss.emerge = 1.0
	boss.step(0.05, swarm.position + Vector3(20.0, 0.0, 0.0), 1.0)
	world.paused = true
	var pose: Transform3D = boss.body.transform
	var health: float = boss.health
	world.step(0.3)
	_check(boss.body.transform == pose and boss.health == health, "Pause freezes Bog King pose and state")
	await process_frame
	await process_frame
	var unit_pose: Transform3D = swarm.units[3].get_node("Game model").transform
	var unit_place: Vector3 = swarm.units[3].position
	await create_timer(0.25).timeout
	_check(swarm.frozen and swarm.units[3].get_node("Game model").transform == unit_pose and swarm.units[3].position == unit_place, "Pause freezes Mawling poses")
	world.paused = false

	world.reset_run()
	_check(world.boss == null and swarm.units.size() == 1 and swarm.population == 1, "Restart resets swarm visuals and boss (lone start)")

	FX.ring(world, Vector3.ZERO, Color.WHITE, 0.2, 2.0, 0.2)
	await create_timer(0.5).timeout
	_check(world.find_children("Ground ring*", "", true, false).is_empty(), "Ground effects free themselves")

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS motion: shrink/regrow, hit reaction, resolved hit, boss pointer, boss+swarm pause freeze, reset, effect cleanup")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
