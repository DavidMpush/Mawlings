extends SceneTree

# Stage 17d: tribe abilities (scripts/abilities.gd) on a test host, plus the
# button in touch_controls.gd. Cooldown, every effect, pause freezes the
# cooldown (no step = no time), relic hooks, walking direction, HUD state,
# button hit (touch >= 96 px, Q / Shift) without stealing Rally or movement.

const ABILITIES = preload("res://scripts/abilities.gd")
const TOUCH = preload("res://scripts/touch_controls.gd")
const DT := 1.0 / 60.0

var failures: Array[String] = []


class Enemy extends Node3D:
	var health := 100.0
	var slow_factor := 1.0
	func take_damage(amount: float) -> void:
		health -= amount


class BossEnemy extends Enemy:
	func body_distance(point: Vector3) -> float:
		return Vector2(point.x - position.x, point.z - position.z).length() - 3.0


class Brood extends Node3D:
	var hits := 0
	func damage_circle(_center: Vector3, _radius: float, _amount: float) -> int:
		hits += 1
		return 1


class Wall extends Node3D:
	# Blocks everything beyond x = 5 (a wall to the east).
	func resolve_motion(start: Vector3, motion: Vector3, _radius: float) -> Vector3:
		var next := start + motion
		next.x = minf(next.x, 5.0)
		return next


class Field extends Node3D:
	# Stage 27 E: a square map of +-`half` m with a wall band lo_x..hi_x across
	# the whole map (like arena.is_open: edge margin + wall clearance).
	var half := 30.0
	var lo_x := 3.0
	var hi_x := 4.0
	func is_open(point: Vector3, radius: float) -> bool:
		if absf(point.x) > half - radius or absf(point.z) > half - radius:
			return false
		return point.x + radius <= lo_x or point.x - radius >= hi_x
	func resolve_motion(start: Vector3, motion: Vector3, radius: float) -> Vector3:
		var next := start + motion
		if start.x <= lo_x:
			next.x = minf(next.x, lo_x - radius)
		next.x = clampf(next.x, -half + radius, half - radius)
		next.z = clampf(next.z, -half + radius, half - radius)
		return next


class Host extends Node3D:
	var swarm := Vector3.ZERO
	var enemies: Array = []
	var brood: Node3D
	var arena: Node3D
	func ability_swarm_position() -> Vector3:
		return swarm
	func ability_set_swarm_position(point: Vector3) -> void:
		swarm = point
	func ability_targets() -> Array:
		return enemies.filter(func(e): return is_instance_valid(e) and e.health > 0.0)
	func ability_brood() -> Node3D:
		return brood
	func ability_arena() -> Node3D:
		return arena
	func ability_damage_scale() -> float:
		return 1.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_strains()
	_check_cooldown()
	_check_leap()
	_check_spores()
	_check_shock()
	_check_haste()
	_check_acid()
	_check_veil()
	_check_button()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS abilities: 6 strains, cooldown + ring share, pause freezes, relic hooks, Glutsprung (path bite, invulnerable, hops narrow obstacles, stops at wide walls + map edge), Sporenbombe (slow + poison 5 s), Panzerstoß (push, bosses firm, -60 %), Hetzjagd (x1.7, line), Säureschwall (cone + puddles), Schattenschleier (decoy, warnings miss), button hit + Q/Shift")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _make(strain: String) -> Array:
	var host := Host.new()
	root.add_child(host)
	host.brood = Brood.new()
	host.add_child(host.brood)
	var ability: Variant = ABILITIES.new()
	host.add_child(ability)
	ability.setup(host, strain)
	return [host, ability]


func _enemy(host: Host, at: Vector3, boss := false) -> Enemy:
	var enemy: Enemy = BossEnemy.new() if boss else Enemy.new()
	host.add_child(enemy)
	enemy.position = at
	host.enemies.append(enemy)
	return enemy


func _steps(ability: Variant, seconds: float, move := Vector3.ZERO) -> void:
	for index in int(ceil(seconds / DT)):
		ability.step(DT, move)


func _check_strains() -> void:
	var expected := {"glutmaw": "glutsprung", "sporling": "sporenbombe", "knochenkiefer": "panzerstoss", "flinkzahn": "hetzjagd", "aetzmaul": "saeureschwall", "nachtmaul": "schattenschleier"}
	for strain in expected:
		var pair := _make(strain)
		var ability: Variant = pair[1]
		_check(ability.ability_id == expected[strain], "%s gets %s" % [strain, expected[strain]])
		var cooldown: float = ability.cooldown_total()
		_check(cooldown >= 20.0 and cooldown <= 40.0, "%s cooldown 20-40 s (%.0f)" % [strain, cooldown])
		pair[0].free()
	var fallback := _make("unknown")
	_check(fallback[1].ability_id == "glutsprung", "Unknown strain -> Glutsprung")
	fallback[1].configure({"strain_id": "nachtmaul"})
	_check(fallback[1].ability_id == "schattenschleier", "configure() reads strain_id")
	fallback[0].free()


func _check_cooldown() -> void:
	var pair := _make("flinkzahn")
	var ability: Variant = pair[1]
	_check(ability.is_ready() and ability.ready_share() == 1.0, "Ready at the start")
	_check(ability.use(Vector3(1, 0, 0)), "Use when ready")
	_check(not ability.is_ready() and not ability.use(), "Refused while cooling down")
	_check(ability.ready_share() == 0.0, "Ring empty right after use")
	# Pause: the run does not step -> no time passes; step(0) changes nothing.
	var left: float = ability.cooldown_left
	ability.step(0.0)
	_check(ability.cooldown_left == left, "Pause freezes the cooldown")
	_steps(ability, 10.0)
	_check(absf(ability.ready_share() - 0.5) < 0.02, "Half the ring after half the cooldown (%.2f)" % ability.ready_share())
	_steps(ability, 10.2)
	_check(ability.is_ready(), "Ready again after 20 s")
	var state: Dictionary = ability.hud_state()
	_check(state.id == "hetzjagd" and state.ready and state.name == "Hetzjagd" and String(state.icon) != "", "HUD state")
	# Relic hooks.
	_check(ability.apply_relic("glutkern") and is_equal_approx(ability.cooldown_total(), 16.0), "Relic -20 %% cooldown (%.1f)" % ability.cooldown_total())
	_check(not ability.apply_relic("nothing"), "Unknown relic ignored")
	pair[0].free()


func _check_leap() -> void:
	var pair := _make("glutmaw")
	var host: Host = pair[0]
	var ability: Variant = pair[1]
	var on_path := _enemy(host, Vector3(0, 0, -4))
	var aside := _enemy(host, Vector3(6, 0, -4))
	# Standing: the last walking direction counts.
	ability.step(DT, Vector3(0, 0, -1))
	ability.use(Vector3.ZERO)
	_check(ability.invulnerable(), "Invulnerable during the leap")
	_steps(ability, 0.4)
	_check(absf(host.swarm.z + 8.0) < 0.05 and absf(host.swarm.x) < 0.05, "Leap 8 m forward in the last direction (%s)" % host.swarm)
	_check(on_path.health < 100.0 and aside.health == 100.0, "Bites along the path only (%.0f / %.0f)" % [on_path.health, aside.health])
	_check(host.brood.hits > 0, "The leap bites brood too")
	_steps(ability, 0.5)
	_check(not ability.invulnerable(), "Grace ends shortly after landing")
	# Fire trail relic leaves own areas; a wall stops the leap.
	ability.apply_relic("feuerspur")
	ability.cooldown_left = 0.0
	host.arena = Wall.new()
	host.add_child(host.arena)
	host.swarm = Vector3.ZERO
	ability.use(Vector3(1, 0, 0))
	_steps(ability, 0.4)
	_check(host.swarm.x <= 5.01, "A wall ends the leap (x %.2f)" % host.swarm.x)
	_check(ability.areas.size() > 0, "Feuerspur leaves burning ground")
	var area: MeshInstance3D = ability.areas[0].node
	_check((area.material_override as ShaderMaterial).get_shader_parameter("fill_color") == Color("ff6a1f"), "Own areas in ember, never danger pink")
	host.free()
	_check_leap_hop()


# Stage 27 E: the leap hops narrow obstacles (<= LEAP_HOP_MAX along the line),
# stops in front of wide walls and never leaves the map.
func _check_leap_hop() -> void:
	var pair := _make("glutmaw")
	var host: Host = pair[0]
	var ability: Variant = pair[1]
	var field := Field.new()
	host.arena = field
	host.add_child(field)
	var east := Vector3(1, 0, 0)
	# A narrow stone band (1 m, 2.5 m blocked with clearance): landing behind it.
	var peak := 0.0
	ability.cooldown_left = 0.0
	ability.use(east)
	for index in int(ceil(0.5 / DT)):
		ability.step(DT, Vector3.ZERO)
		peak = maxf(peak, ability.leap_height())
	_check(absf(host.swarm.x - 8.0) < 0.05 and absf(host.swarm.z) < 0.05, "Glutsprung hops a narrow stone (x %.2f)" % host.swarm.x)
	_check(field.is_open(host.swarm, 0.75), "Hop landing is open ground")
	_check(peak > ability.LEAP_ARC + 0.1 and peak <= ability.LEAP_ARC * 1.5 + 0.01, "Hopping arc is higher (%.2f m)" % peak)
	# Obstacle close to the end of the line: land in front of it, not inside.
	field.lo_x = 7.0
	field.hi_x = 8.5
	var landing: Vector3 = ability._leap_landing(Vector3.ZERO, east, 8.0)
	_check(landing.x <= 6.25 + 0.01 and landing.x > 5.9 and field.is_open(landing, 0.75), "Obstacle at the end: land in front (x %.2f)" % landing.x)
	# Two narrow bands, each hoppable: land behind both.
	field.lo_x = 1.5
	field.hi_x = 2.5
	landing = ability._leap_landing(Vector3.ZERO, east, 8.0)
	_check(absf(landing.x - 8.0) < 0.05, "Band right in front is hopped (x %.2f)" % landing.x)
	# Wide wall (4.5 m thick = 6 m blocked along the line > LEAP_HOP_MAX): stop in front.
	field.lo_x = 2.5
	field.hi_x = 7.0
	landing = ability._leap_landing(Vector3.ZERO, east, 8.0)
	_check(landing.x <= 1.75 + 0.01 and landing.x > 1.4, "A wide wall stops the leap in front (x %.2f)" % landing.x)
	host.swarm = Vector3.ZERO
	ability.cooldown_left = 0.0
	ability.use(east)
	_steps(ability, 0.5)
	_check(host.swarm.x <= 1.76 and field.is_open(host.swarm, 0.75), "Leap never passes a wide wall (x %.2f)" % host.swarm.x)
	# Standing right at the wide wall: no open sample beyond, old walk = stay.
	landing = ability._leap_landing(Vector3(1.75, 0, 0), east, 8.0)
	_check(landing.x <= 1.76, "At a wide wall the leap stays in front (x %.2f)" % landing.x)
	# Map edge: never beyond it, also not hopping a stone into the edge.
	field.half = 6.0
	field.lo_x = 100.0
	field.hi_x = 101.0
	for dir in [east, Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0.7, 0, -0.7)]:
		landing = ability._leap_landing(Vector3(1, 0, 1), dir, 8.0)
		_check(field.is_open(landing, 0.75), "Leap toward the edge lands inside (%s)" % landing)
	field.lo_x = 3.0
	field.hi_x = 4.0
	landing = ability._leap_landing(Vector3.ZERO, east, 8.0)
	_check(absf(landing.x - 5.25) < 0.01 and field.is_open(landing, 0.75), "Stone before the edge: land between stone and edge (x %.2f)" % landing.x)
	field.hi_x = 5.0
	landing = ability._leap_landing(Vector3.ZERO, east, 8.0)
	_check(landing.x <= 2.25 + 0.01, "Stone reaching the edge: no landing beyond (x %.2f)" % landing.x)
	host.free()


func _check_spores() -> void:
	var pair := _make("sporling")
	var host: Host = pair[0]
	var ability: Variant = pair[1]
	var inside := _enemy(host, Vector3(3, 0, 0))
	var outside := _enemy(host, Vector3(12, 0, 0))
	ability.use()
	_steps(ability, 1.0)
	_check(is_equal_approx(inside.slow_factor, ABILITIES.SPORE_SLOW) and outside.slow_factor == 1.0, "Cloud slows inside only")
	_check(inside.health < 100.0 and outside.health == 100.0, "Poison inside only")
	_steps(ability, 4.2)
	var poisoned := 100.0 - inside.health
	_check(absf(poisoned - ABILITIES.SPORE_DPS * 5.0) < 2.0, "Poison for 5 s (%.1f)" % poisoned)
	_check(inside.slow_factor == 1.0 and ability.areas.is_empty(), "Cloud gone, speed back")
	host.free()


func _check_shock() -> void:
	var pair := _make("knochenkiefer")
	var host: Host = pair[0]
	var ability: Variant = pair[1]
	var near := _enemy(host, Vector3(2, 0, 0))
	var boss := _enemy(host, Vector3(0, 0, 4), true)
	var far := _enemy(host, Vector3(20, 0, 0))
	ability.use()
	_check(near.position.x > 4.0 and near.health < 100.0, "Shock throws back and hurts (x %.1f)" % near.position.x)
	_check(boss.position == Vector3(0, 0, 4) and boss.health < 100.0, "Bosses stand firm but take damage")
	_check(far.health == 100.0, "Out of range untouched")
	_check(is_equal_approx(ability.damage_taken_multiplier(), 0.4), "-60 % losses while active")
	_steps(ability, 2.1)
	_check(ability.damage_taken_multiplier() == 1.0, "Protection ends after 2 s")
	host.free()


func _check_haste() -> void:
	var pair := _make("flinkzahn")
	var ability: Variant = pair[1]
	ability.use(Vector3(0, 0, 1))
	_check(is_equal_approx(ability.speed_multiplier(), 1.7) and ability.line_formation(), "Hetzjagd: +70 % and a line")
	_steps(ability, 4.1)
	_check(ability.speed_multiplier() == 1.0 and not ability.line_formation(), "Hetzjagd ends after 4 s")
	pair[0].free()


func _check_acid() -> void:
	var pair := _make("aetzmaul")
	var host: Host = pair[0]
	var ability: Variant = pair[1]
	var ahead := _enemy(host, Vector3(0, 0, -6))
	var behind := _enemy(host, Vector3(0, 0, 6))
	ability.use(Vector3(0, 0, -1))
	_check(ahead.health < 100.0 and behind.health == 100.0, "Acid cone hits forward only")
	_check(ability.areas.size() == ABILITIES.ACID_PUDDLES.size(), "Three puddles")
	var before := ahead.health
	_steps(ability, 1.0)
	_check(ahead.health < before, "Standing in a puddle burns")
	host.free()


func _check_veil() -> void:
	var pair := _make("nachtmaul")
	var host: Host = pair[0]
	var ability: Variant = pair[1]
	host.swarm = Vector3(10, 0, 10)
	ability.use(Vector3(1, 0, 0))
	_check(ability.warnings_miss(), "Warnings miss under the veil")
	var decoy: Vector3 = ability.decoy_position()
	_check(decoy.is_finite() and decoy.x < 10.0, "Enemies chase a decoy behind the swarm (%s)" % decoy)
	_steps(ability, 3.1)
	_check(not ability.warnings_miss() and not ability.decoy_position().is_finite(), "Veil ends after 3 s")
	pair[0].free()


func _check_button() -> void:
	var hud: Control = TOUCH.new()
	root.add_child(hud)
	hud.size = Vector2(900, 1600)
	var pair := _make("glutmaw")
	pair[1].sync_hud(hud)
	_check(not (hud.ability_state as Dictionary).is_empty(), "HUD gets the ability state")
	var requested := [0]
	hud.ability_requested.connect(func() -> void: requested[0] += 1)
	_check(hud.ABILITY_TOUCH_R * 2.0 >= 96.0, "Touch area >= 96 px")
	var center: Vector2 = hud._ability_center()
	_check(center.distance_to(hud._rally_center()) > 150.0 and center.y < hud._rally_center().y, "Button up-right of Rally, apart")
	hud._press(0, center + Vector2(20, 20))
	_check(hud.ability_requests == 1 and requested[0] == 1 and not hud.rally_pressed, "Tap on the button fires the ability")
	hud._press(1, hud._rally_center())
	_check(hud.rally_pressed and hud.ability_requests == 1, "Rally stays Rally")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_Q
	hud._input(key)
	key.keycode = KEY_SHIFT
	hud._input(key)
	_check(hud.ability_requests == 3, "Q and Shift fire the ability")
	hud.ability_state = {}
	hud._release(0)
	hud._press(2, center)
	_check(hud.ability_requests == 3, "No button without a state")
	hud.free()
	pair[0].free()
