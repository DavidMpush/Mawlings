extends SceneTree

# Stage 17d: the tribe ability inside a real run (HuntWorld + Swarm + HUD).
# Strain -> ability, HUD button state, Q key, cooldown, pause and reset,
# Glutsprung (moves the swarm, arc, no losses), Panzerstoß (-60 % losses and
# leader LP), Hetzjagd (speed x1.7, line formation), Schattenschleier (announced
# areas miss, enemies aim at the decoy), migration ends effects, relics.

const TUNING = preload("res://scripts/tuning.gd")
const ABILITIES = preload("res://scripts/abilities.gd")
const DT := 1.0 / 60.0

var failures: Array[String] = []
var scene: Node
var world: Variant
var swarm: Variant
var hud: Variant


class FakeArea extends Node3D:
	var resolved_power := 20
	func contains(_point: Vector3) -> bool:
		return true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	hud = scene.get_node("HUD/Controls")
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)
	_check_strain_and_button()
	_check_leap()
	_check_shock()
	_check_haste()
	_check_veil()
	_check_pause_reset_migration()
	_check_relic()
	scene.queue_free()
	await process_frame
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS ability_run: strain ability + HUD button, Q key, cooldown, Glutsprung (8 m, arc, no losses), Panzerstoß (-60 % animals + leader), Hetzjagd (x1.7, line), Schattenschleier (areas miss, decoy), pause/reset/migration, relic")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _fresh(strain: String) -> void:
	world.config = {"strain_id": strain}
	world.reset_run()
	world.config = {}
	world.model.population = 40
	swarm.set_population(40, false)
	world.model.elapsed = 30.0
	for clock in ["hunter_clock", "skitter_clock", "leaper_clock", "elite_clock", "nest_clock", "boss_clock"]:
		world.set(clock, 9999.0)
	world.flood_start = 100000.0
	world.model.leader_invulnerable = 0.0


func _steps(seconds: float) -> void:
	for index in int(ceil(seconds / DT)):
		if world.choosing():
			world.choose_mutation(0)
		world.step(DT)


func _check_strain_and_button() -> void:
	_fresh("sporling")
	_check(world.abilities != null and world.abilities.ability_id == "sporenbombe", "Sporling run has the Sporenbombe")
	_steps(0.1)
	var state: Dictionary = hud.ability_state
	_check(String(state.get("id", "")) == "sporenbombe" and bool(state.get("ready", false)), "HUD button shows the ready ability")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_Q
	hud._input(key)
	_steps(0.05)
	_check(world.abilities.uses == 1 and not world.abilities.is_ready(), "Q fires the ability in the next step")
	_check(not bool(hud.ability_state.get("ready", true)) and int(hud.ability_state.get("seconds", 0)) > 20, "Button shows the cooldown")


func _check_leap() -> void:
	_fresh("glutmaw")
	var start: Vector3 = swarm.position
	swarm.movement_vector = Vector2(0, -1)
	world.request_ability()
	_steps(0.15)
	_check(swarm.leap_height > 0.3, "The swarm is in the air (%.2f m)" % swarm.leap_height)
	var before: int = world.model.population
	var ended: bool = world._apply_hit(10, swarm.position, 0.0, null, true)
	_check(not ended and world.model.population == before, "No losses during the leap")
	_steps(0.4)
	swarm.movement_vector = Vector2.ZERO
	var moved := Vector2(swarm.position.x - start.x, swarm.position.z - start.z)
	_check(moved.length() > 6.0 and moved.y < -5.0, "Glutsprung carries the swarm forward (%.1f m)" % moved.length())
	_check(swarm.leap_height == 0.0, "Landed")


func _check_shock() -> void:
	_fresh("knochenkiefer")
	var hp_before: int = world.model.leader_hp
	var before: int = world.model.population
	world._apply_hit(10, swarm.position, 0.0, null, true)
	var normal_loss: int = before - world.model.population
	var normal_hp: int = hp_before - world.model.leader_hp
	world.model.leader_invulnerable = 0.0
	world.request_ability()
	_steps(0.05)
	hp_before = world.model.leader_hp
	before = world.model.population
	world._apply_hit(10, swarm.position, 0.0, null, true)
	var shield_loss: int = before - world.model.population
	var shield_hp: int = hp_before - world.model.leader_hp
	_check(normal_loss > 0 and shield_loss <= ceili(normal_loss * 0.4) and shield_loss < normal_loss, "Panzerstoß: -60 %% animals (%d -> %d)" % [normal_loss, shield_loss])
	_check(normal_hp > 0 and shield_hp < normal_hp, "Panzerstoß: less leader LP (%d -> %d)" % [normal_hp, shield_hp])


func _check_haste() -> void:
	_fresh("flinkzahn")
	_steps(0.05)
	var base: float = swarm.speed_multiplier
	swarm.movement_vector = Vector2(1, 0)
	world.request_ability()
	_steps(0.05)
	_check(absf(swarm.speed_multiplier / base - 1.7) < 0.01, "Hetzjagd: speed x1.7 (%.2f)" % (swarm.speed_multiplier / base))
	_check(swarm.line_formation and swarm.line_direction.x > 0.9, "Hetzjagd: line along the direction")
	_steps(4.2)
	swarm.movement_vector = Vector2.ZERO
	_check(not swarm.line_formation and absf(swarm.speed_multiplier - base) < 0.01, "Hetzjagd ends")


func _check_veil() -> void:
	_fresh("nachtmaul")
	var area := FakeArea.new()
	world.add_child(area)
	world.request_ability()
	_steps(0.05)
	var before: int = world.model.population
	_check(not world._resolve_area_hit(area, swarm.position, 0.0) and world.model.population == before, "Announced areas miss under the veil")
	var aim: Vector3 = world._aim_point()
	_check(aim.distance_to(swarm.position) > 4.0, "Enemies aim at the decoy")
	_steps(3.2)
	_check(world._aim_point() == swarm.position, "Veil over: enemies aim at the swarm again")
	world.model.leader_invulnerable = 0.0
	world._resolve_area_hit(area, swarm.position, 0.0)
	_check(world.model.population < before, "Areas hit again after the veil")
	area.free()


func _check_pause_reset_migration() -> void:
	_fresh("sporling")
	world.request_ability()
	_steps(0.05)
	var left: float = world.abilities.cooldown_left
	world.toggle_pause()
	_steps(2.0)
	_check(world.abilities.cooldown_left == left, "Pause freezes the cooldown")
	world.toggle_pause()
	_steps(1.0)
	_check(world.abilities.cooldown_left < left, "Cooldown runs again")
	_check(world.abilities.areas.size() > 0, "Cloud lies")
	world.apex_state = 3
	var maw: Variant = world.open_portal(swarm.position + Vector3(0, 0, -3))
	_steps(1.3)
	swarm.position = maw.position
	world.unit_points_valid = false
	_steps(TUNING.MIGRATION_HOLD_SECONDS + 0.1)
	_check(world.migrating() and world.abilities.areas.is_empty() and world.abilities.cooldown_left > 0.0, "Migration ends effects, keeps the cooldown")
	world.reset_run()
	_check(world.abilities != null and world.abilities.is_ready() and world.abilities.areas.is_empty(), "Reset: fresh ability")


func _check_relic() -> void:
	_fresh("glutmaw")
	var base: float = world.abilities.cooldown_total()
	world.evolution.debug_grant("glutkern")
	_steps(0.05)
	_check(is_equal_approx(world.abilities.cooldown_total(), base * 0.8), "Glutkern: -20 %% cooldown (%.1f -> %.1f)" % [base, world.abilities.cooldown_total()])
