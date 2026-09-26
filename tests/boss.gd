extends SceneTree

const BOG_KING = preload("res://scripts/bog_king.gd")
const TUNING = preload("res://scripts/tuning.gd")
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
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)
	world.reset_run()
	world.boss_clock = 0.0
	world.step(0.01)
	_check(world.boss != null and hud.boss_health > 0.0, "Director spawns Bog King and displays boss HUD")
	var boss: Variant = world.boss
	_check(boss.model.scale.x >= 7.0 and boss.model.get_child_count() > 0, "Large optimized model appears")
	boss.position = Vector3(4.0, 0.0, 0.0)
	boss.state = BOG_KING.State.CHASE
	_check(boss.step(0.01, Vector3.ZERO, 1.0) == 0 and boss.state == BOG_KING.State.WARNING and boss.warning.visible, "Stomp warns before damage")
	var locked: Vector3 = boss.attack_center
	_check(boss.step(TUNING.BOSS_WARNING_SECONDS, Vector3(8, 0, 0), 1.0) == 0 and boss.attack_center == locked, "Leaving fixed stomp circle avoids damage")
	boss.step(TUNING.BOSS_RECOVERY_SECONDS, Vector3.ZERO, 1.0)
	boss.step(0.01, Vector3.ZERO, 1.0)
	_check(boss.step(TUNING.BOSS_WARNING_SECONDS, locked, 1.0) == int(ceil(TUNING.BOSS_DAMAGE)), "Stomp deals one announced hit")
	_check(boss.step(0.1, locked, 1.0) == 0, "Recovery cannot hit twice")
	world.reset_run()
	_check(world.boss == null and world.boss_clock == TUNING.FIRST_BOSS_SECONDS and hud.boss_health == 0.0, "Restart clears boss and UI")
	world.model.population = 250
	swarm.set_population(250)
	swarm.set_controls(Vector2.ZERO, true)
	boss = world._spawn_boss(Vector3(0.5, 0, 0))
	boss.state = BOG_KING.State.RECOVERY
	boss.remaining = 10.0
	boss.health = 0.01
	world.step(0.1)
	_check(world.boss == null and world.evolution.dna == 50, "Boss defeat grants DNA exactly once")
	_check(world.model.remaining_biomass(1) == TUNING.BOSS_BIOMASS and world.boss_clock == TUNING.BOSS_RESPAWN_SECONDS, "Defeat leaves persistent biomass and schedules next boss")
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS boss: appearance, warning, dodge, hit, reward, persistence, respawn, reset")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
