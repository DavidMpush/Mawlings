extends Node3D

# Stage 17d: the tribe ability. Exactly one active ability per strain, fired
# by its own round button (above Rally, left hand) or Q / Shift; no aiming: it
# acts in the walking direction (the last one while standing) or around the
# swarm. Cooldown 20-40 s, drawn as a ring on the button.
#
#   Glutmaw       glutsprung        8 m leap forward, bites along the path, briefly invulnerable
#   Sporling      sporenbombe       spore cloud at the swarm: slows and poisons 5 s
#   Knochenkiefer panzerstoss       shock wave throws enemies back, 2 s -60 % losses
#   Flinkzahn     hetzjagd          4 s +70 % speed, the swarm stretches into a line
#   Ätzmaul       saeureschwall     acid cone forward + burning puddles
#   Nachtmaul     schattenschleier  3 s enemies lose the target, warnings miss
#
# Everything the ability does to the world goes through a small host interface
# (HuntWorld later, a test double now); every method is optional:
#   ability_swarm_position() -> Vector3
#   ability_set_swarm_position(point: Vector3)
#   ability_targets() -> Array            living enemies (Node3D with health /
#                                         take_damage, optional slow_factor)
#   ability_brood() -> Node3D             horde / grubs with damage_circle()
#   ability_arena() -> Node3D             resolve_motion, push_walls
#   ability_damage_scale() -> float       pressure / build scaling of damage
# What the run must honour while an ability is active, read by HuntWorld:
#   damage_taken_multiplier()  Panzerstoß 0.4 (losses x0.4), else 1
#   invulnerable()             Glutsprung (leap + short grace)
#   speed_multiplier()         Hetzjagd 1.7
#   line_formation()           Hetzjagd: the swarm stretches along the direction
#   warnings_miss()            Schattenschleier: announced areas resolve empty
#   decoy_position()           Schattenschleier: enemies walk here (INF = none)
# Call order in HuntWorld: after attack_forms.step() (it resets slow_factor) and
# before the enemies step, so slows and knock-backs take effect this frame.
#
# Relic hooks (entries come with the integration round): apply_relic(id) or
# set_modifier(key, value) with keys
#   cooldown   multiplier of the cooldown (e.g. 0.8 = -20 %)
#   duration   multiplier of every effect duration
#   radius     multiplier of every radius / reach
#   power      multiplier of every damage
#   fire_trail Glutsprung leaves a burning trail (own ember area, 3 s)

signal used(id: String)

const TG = preload("res://scripts/telegraph_style.gd")
const FX = preload("res://scripts/fx.gd")
const VFX_SPRITES = preload("res://scripts/vfx_sprites.gd")
const UI_STYLE = preload("res://scripts/ui/ui_style.gd")

const STRAIN_ABILITY := {
	"glutmaw": "glutsprung", "sporling": "sporenbombe", "knochenkiefer": "panzerstoss",
	"flinkzahn": "hetzjagd", "aetzmaul": "saeureschwall", "nachtmaul": "schattenschleier",
}
# name, cooldown (s), effect duration (s), icon (ui_icons id), short HUD text.
const DEFS := {
	"glutsprung": {"name": "Glutsprung", "cooldown": 25.0, "duration": 0.35, "icon": "mawling_head_glutmaw", "text": "GLUTSPRUNG!"},
	"sporenbombe": {"name": "Sporenbombe", "cooldown": 30.0, "duration": 5.0, "icon": "mawling_head_sporling", "text": "SPORENBOMBE!"},
	"panzerstoss": {"name": "Panzerstoß", "cooldown": 30.0, "duration": 2.0, "icon": "mawling_head_knochenkiefer", "text": "PANZERSTOSS!"},
	"hetzjagd": {"name": "Hetzjagd", "cooldown": 20.0, "duration": 4.0, "icon": "mawling_head_flinkzahn", "text": "HETZJAGD!"},
	"saeureschwall": {"name": "Säureschwall", "cooldown": 30.0, "duration": 5.0, "icon": "mawling_head_aetzmaul", "text": "SÄURESCHWALL!"},
	"schattenschleier": {"name": "Schattenschleier", "cooldown": 40.0, "duration": 3.0, "icon": "mawling_head_nachtmaul", "text": "SCHATTENSCHLEIER!"},
}
const ORDER := ["glutsprung", "sporenbombe", "panzerstoss", "hetzjagd", "saeureschwall", "schattenschleier"]
# Relics that change the ability (hooks; the relic entries come later).
const RELIC_HOOKS := {
	"glutkern": {"cooldown": 0.8},
	"feuerspur": {"fire_trail": true},
	"sporenhall": {"duration": 1.4},
	"weiter_schlund": {"radius": 1.25},
}

# Glutsprung
const LEAP_DISTANCE := 8.0
const LEAP_WIDTH := 2.2
const LEAP_DAMAGE := 30.0
const LEAP_GRACE := 0.4
const LEAP_ARC := 1.6
const TRAIL_SECONDS := 3.0
const TRAIL_RADIUS := 1.3
const TRAIL_DPS := 8.0
# Sporenbombe
const SPORE_RADIUS := 6.5
const SPORE_SLOW := 0.45
const SPORE_DPS := 12.0
# Panzerstoß
const SHOCK_RADIUS := 7.0
const SHOCK_PUSH := 4.0
const SHOCK_DAMAGE := 15.0
const SHOCK_LOSS_MULT := 0.4
# Hetzjagd
const HASTE_MULT := 1.7
# Säureschwall
const ACID_REACH := 9.0
const ACID_HALF_ANGLE := 0.5
const ACID_DAMAGE := 25.0
const ACID_PUDDLES := [3.0, 6.0, 8.5]
const ACID_PUDDLE_RADIUS := 1.8
const ACID_DPS := 10.0
# Schattenschleier
const VEIL_DECOY_BACK := 6.0
const OWN := Color("ff6a1f")
const OWN_LIGHT := Color("ffa340")

var host: Object
var ability_id := ""
var cooldown_left := 0.0
var active_left := 0.0
var grace_left := 0.0
var direction := Vector3(0, 0, -1)
var uses := 0
var modifiers := {"cooldown": 1.0, "duration": 1.0, "radius": 1.0, "power": 1.0, "fire_trail": false}
var decoy := Vector3.INF
# Leap in progress.
var _leap_from := Vector3.ZERO
var _leap_to := Vector3.ZERO
var _leap_t := 1.0
var _leap_hit: Dictionary = {}
# Areas lying in the world: {center, radius, dps, left, node, slow}.
var areas: Array[Dictionary] = []
var _vfx: Node3D
var _slowed: Dictionary = {}


func setup(host_object: Object, strain_id: String) -> void:
	host = host_object
	ability_id = String(STRAIN_ABILITY.get(strain_id, "glutsprung"))
	cooldown_left = 0.0


## RunConfig (strain_id); unknown or missing -> Glutmaw.
func configure(config: Dictionary) -> void:
	ability_id = String(STRAIN_ABILITY.get(String(config.get("strain_id", "glutmaw")), "glutsprung"))
	cooldown_left = 0.0
	active_left = 0.0


func _ready() -> void:
	_vfx = VFX_SPRITES.create("Ability VFX")
	add_child(_vfx)


# ------------------------------------------------------------------ state

func definition() -> Dictionary:
	return DEFS.get(ability_id, DEFS.glutsprung)


func cooldown_total() -> float:
	return float(definition().cooldown) * float(modifiers.cooldown)


func duration_total() -> float:
	return float(definition().duration) * float(modifiers.duration)


func is_ready() -> bool:
	return cooldown_left <= 0.0 and ability_id != ""


## 0 right after use .. 1 ready (ring on the button).
func ready_share() -> float:
	return 1.0 - clampf(cooldown_left / maxf(0.01, cooldown_total()), 0.0, 1.0)


func active() -> bool:
	return active_left > 0.0


func damage_taken_multiplier() -> float:
	return SHOCK_LOSS_MULT if ability_id == "panzerstoss" and active() else 1.0


func invulnerable() -> bool:
	return ability_id == "glutsprung" and (_leap_t < 1.0 or grace_left > 0.0)


func speed_multiplier() -> float:
	return HASTE_MULT if ability_id == "hetzjagd" and active() else 1.0


## Height of the Glutsprung arc right now (m; 0 on the ground).
func leap_height() -> float:
	return sin(_leap_t * PI) * LEAP_ARC if ability_id == "glutsprung" and _leap_t < 1.0 else 0.0


func line_formation() -> bool:
	return ability_id == "hetzjagd" and active()


func warnings_miss() -> bool:
	return ability_id == "schattenschleier" and active()


func decoy_position() -> Vector3:
	return decoy if ability_id == "schattenschleier" and active() else Vector3.INF


## Button state for hud_controls.gd (touch_controls.ability_state).
func hud_state() -> Dictionary:
	var def := definition()
	return {"id": ability_id, "name": def.name, "icon": def.icon, "ready": is_ready(), "share": ready_share(),
		"seconds": ceili(cooldown_left), "active": active_left / maxf(0.01, duration_total()) if active() else 0.0}


func sync_hud(hud: Object) -> void:
	if hud != null and "ability_state" in hud:
		hud.set("ability_state", hud_state())


# ------------------------------------------------------------------ relic hooks

func set_modifier(key: String, value: Variant) -> void:
	if modifiers.has(key):
		modifiers[key] = value


func apply_relic(id: String) -> bool:
	if not RELIC_HOOKS.has(id):
		return false
	for key in RELIC_HOOKS[id]:
		var value: Variant = RELIC_HOOKS[id][key]
		if value is float and modifiers[key] is float:
			modifiers[key] = float(modifiers[key]) * float(value)
		else:
			modifiers[key] = value
	return true


# ------------------------------------------------------------------ use

## Fires the ability in `move` (x/z; zero = the last direction). False while cooling down.
func use(move := Vector3.ZERO) -> bool:
	if not is_ready():
		return false
	remember_direction(move)
	cooldown_left = cooldown_total()
	active_left = duration_total()
	uses += 1
	match ability_id:
		"glutsprung":
			_start_leap()
		"sporenbombe":
			_spore_bomb()
		"panzerstoss":
			_shock()
		"hetzjagd":
			_haste()
		"saeureschwall":
			_acid()
		"schattenschleier":
			_veil()
	# Feuerspur on the other abilities: burning ground where the swarm stood.
	if bool(modifiers.fire_trail) and ability_id != "glutsprung":
		_add_area(_swarm(), 2.4 * float(modifiers.radius), TRAIL_DPS, TRAIL_SECONDS, 1.0)
	used.emit(ability_id)
	return true


func remember_direction(move: Vector3) -> void:
	var flat := Vector3(move.x, 0.0, move.z)
	if flat.length_squared() > 0.0025:
		direction = flat.normalized()


## Advances cooldown and effects (only while the run steps: pause freezes all).
func step(delta: float, move := Vector3.ZERO) -> void:
	if delta <= 0.0:
		return
	remember_direction(move)
	cooldown_left = maxf(0.0, cooldown_left - delta)
	active_left = maxf(0.0, active_left - delta)
	grace_left = maxf(0.0, grace_left - delta)
	if _leap_t < 1.0:
		_step_leap(delta)
	_step_areas(delta)
	if _vfx != null:
		_vfx.step(delta, _swarm())


## Ends every running effect but keeps the cooldown (migration, map change).
func clear_effects() -> void:
	var keep := cooldown_left
	clear()
	cooldown_left = keep


func clear() -> void:
	cooldown_left = 0.0
	active_left = 0.0
	grace_left = 0.0
	_leap_t = 1.0
	decoy = Vector3.INF
	for area in areas:
		if is_instance_valid(area.node):
			area.node.queue_free()
	areas.clear()
	_release_slows()
	if _vfx != null:
		_vfx.clear()


# ------------------------------------------------------------------ host

func _call(method: String, args: Array = []) -> Variant:
	if host != null and is_instance_valid(host) and host.has_method(method):
		return host.callv(method, args)
	return null


func _swarm() -> Vector3:
	var value: Variant = _call("ability_swarm_position")
	return value if value is Vector3 else global_position


func _targets() -> Array:
	var value: Variant = _call("ability_targets")
	return value if value is Array else []


func _scale() -> float:
	var value: Variant = _call("ability_damage_scale")
	return (float(value) if value != null else 1.0) * float(modifiers.power)


func _hit(target: Object, amount: float) -> void:
	if target == null or not is_instance_valid(target) or amount <= 0.0:
		return
	if target.has_method("take_damage"):
		target.take_damage(amount)
	elif "health" in target:
		target.set("health", float(target.get("health")) - amount)


func _brood_circle(center: Vector3, radius: float, amount: float) -> void:
	var brood: Variant = _call("ability_brood")
	if brood != null and is_instance_valid(brood) and brood.has_method("damage_circle"):
		brood.damage_circle(center, radius, amount)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _world_parent() -> Node:
	return get_parent() if get_parent() != null else self


# ------------------------------------------------------------------ Glutsprung

func _start_leap() -> void:
	_leap_from = _swarm()
	var target := _leap_from + direction * LEAP_DISTANCE * float(modifiers.radius)
	var arena: Variant = _call("ability_arena")
	if arena != null and is_instance_valid(arena) and arena.has_method("resolve_motion"):
		# Walk the line in 1 m steps: a wall ends the leap early (never through it).
		var at := _leap_from
		var steps := ceili(LEAP_DISTANCE * float(modifiers.radius))
		for index in steps:
			var next: Vector3 = arena.resolve_motion(at, direction * (LEAP_DISTANCE * float(modifiers.radius) / steps), 0.75)
			if next.distance_to(at) < 0.2:
				break
			at = next
		target = at
	_leap_to = Vector3(target.x, 0.0, target.z)
	_leap_t = 0.0
	_leap_hit.clear()
	grace_left = duration_total() + LEAP_GRACE
	_vfx_spawn("shock", _leap_from, 4.0)
	FX.ring(_world_parent(), _leap_from, Color(OWN_LIGHT, 0.85), 0.6, 3.0, 0.4)


func _step_leap(delta: float) -> void:
	_leap_t = minf(1.0, _leap_t + delta / maxf(0.05, duration_total()))
	var at := _leap_from.lerp(_leap_to, _leap_t)
	_call("ability_set_swarm_position", [at])
	var reach := LEAP_WIDTH * float(modifiers.radius)
	var travelled := _leap_from.lerp(_leap_to, _leap_t)
	for target in _targets():
		if not is_instance_valid(target) or _leap_hit.has(target.get_instance_id()):
			continue
		if _segment_distance(target.global_position, _leap_from, travelled) <= reach:
			_leap_hit[target.get_instance_id()] = true
			_hit(target, LEAP_DAMAGE * _scale())
			_vfx_spawn("bite", target.global_position, 1.2)
	_brood_circle(at, reach, LEAP_DAMAGE * _scale() * delta / maxf(0.05, duration_total()))
	if bool(modifiers.fire_trail) and fposmod(_leap_t * 4.0, 1.0) < delta / maxf(0.05, duration_total()) * 4.0:
		_add_area(at, TRAIL_RADIUS * float(modifiers.radius), TRAIL_DPS, TRAIL_SECONDS, 1.0)
	if _leap_t >= 1.0:
		_vfx_spawn("shock", _leap_to, 5.0)
		FX.ring(_world_parent(), _leap_to, Color(OWN, 0.9), 0.8, 3.6, 0.45)


static func _segment_distance(point: Vector3, a: Vector3, b: Vector3) -> float:
	var p := Vector2(point.x, point.z)
	var s := Vector2(a.x, a.z)
	var e := Vector2(b.x, b.z)
	var along := e - s
	var t := 0.0 if along.length_squared() < 0.0001 else clampf((p - s).dot(along) / along.length_squared(), 0.0, 1.0)
	return (p - (s + along * t)).length()


# ------------------------------------------------------------------ Sporenbombe

func _spore_bomb() -> void:
	var center := _swarm()
	_add_area(center, SPORE_RADIUS * float(modifiers.radius), SPORE_DPS, duration_total(), SPORE_SLOW)
	for index in 5:
		var angle := TAU * float(index) / 5.0
		_vfx_spawn("spore", center + Vector3(cos(angle), 0, sin(angle)) * 3.0, 1.4)
	FX.ring(_world_parent(), center, Color(OWN_LIGHT, 0.8), 1.0, SPORE_RADIUS * float(modifiers.radius), 0.6)


# ------------------------------------------------------------------ Panzerstoß

func _shock() -> void:
	var center := _swarm()
	var radius := SHOCK_RADIUS * float(modifiers.radius)
	var arena: Variant = _call("ability_arena")
	for target in _targets():
		if not is_instance_valid(target):
			continue
		var offset: Vector3 = target.global_position - center
		offset.y = 0.0
		if offset.length() > radius:
			continue
		_hit(target, SHOCK_DAMAGE * _scale())
		# Light enemies fly back; bosses (body_distance) stand firm.
		if "slow_factor" in target and not target.has_method("body_distance"):
			var away := offset.normalized() if offset.length() > 0.05 else direction
			var push := away * SHOCK_PUSH * (1.0 - offset.length() / radius * 0.5)
			if arena != null and is_instance_valid(arena) and arena.has_method("resolve_motion"):
				target.position = arena.resolve_motion(target.position, push, 0.6)
			else:
				target.position += push
	_brood_circle(center, radius, SHOCK_DAMAGE * _scale())
	_vfx_spawn("shock", center, radius * 2.2)
	FX.ring(_world_parent(), center, Color(OWN_LIGHT, 0.9), 1.0, radius, 0.45)
	FX.ring(_world_parent(), center, Color(1, 1, 1, 0.6), 0.6, radius * 0.7, 0.35)


# ------------------------------------------------------------------ Hetzjagd

func _haste() -> void:
	var center := _swarm()
	for index in 3:
		FX.ring(_world_parent(), center - direction * float(index) * 1.6, Color(OWN_LIGHT, 0.7 - 0.2 * index), 0.8, 3.0, 0.35 + 0.1 * index)


# ------------------------------------------------------------------ Säureschwall

func _acid() -> void:
	var origin := _swarm()
	var reach := ACID_REACH * float(modifiers.radius)
	for target in _targets():
		if is_instance_valid(target) and cone_contains(origin, direction, reach, ACID_HALF_ANGLE, target.global_position):
			_hit(target, ACID_DAMAGE * _scale())
			_vfx_spawn("acid", target.global_position, 1.0)
	for spot in ACID_PUDDLES:
		var center: Vector3 = origin + direction * float(spot) * float(modifiers.radius)
		_add_area(center, ACID_PUDDLE_RADIUS * float(modifiers.radius), ACID_DPS, duration_total(), 1.0)
		_vfx_spawn("acid", center, 1.6)
		_brood_circle(center, ACID_PUDDLE_RADIUS * 1.6, ACID_DAMAGE * _scale() * 0.5)


static func cone_contains(origin: Vector3, forward: Vector3, reach: float, half_angle: float, point: Vector3) -> bool:
	var flat := Vector2(point.x - origin.x, point.z - origin.z)
	var distance := flat.length()
	if distance > reach:
		return false
	if distance < 0.5:
		return true
	return flat.normalized().dot(Vector2(forward.x, forward.z).normalized()) >= cos(half_angle)


# ------------------------------------------------------------------ Schattenschleier

func _veil() -> void:
	var center := _swarm()
	decoy = center - direction * VEIL_DECOY_BACK
	for index in 4:
		var angle := TAU * float(index) / 4.0
		_vfx_spawn("spore", center + Vector3(cos(angle), 0, sin(angle)) * 1.6, 1.0)
	FX.ring(_world_parent(), center, Color(0.55, 0.42, 0.9, 0.8), 3.2, 0.8, 0.5)
	FX.ring(_world_parent(), decoy, Color(OWN_LIGHT, 0.6), 0.5, 2.4, 0.6)


# ------------------------------------------------------------------ own areas

# An own (ember) area lying on the ground: damage per second, optional slow.
func _add_area(center: Vector3, radius: float, dps: float, seconds: float, slow: float) -> void:
	var node := TG.build_hazard(radius, -1, "own")
	node.name = "Ability area"
	_world_parent().add_child(node)
	node.global_position = Vector3(center.x, 0.09 + 0.002 * areas.size(), center.z)
	areas.append({"center": Vector3(center.x, 0.0, center.z), "radius": radius, "dps": dps, "left": seconds, "total": seconds, "node": node, "slow": slow})


func _step_areas(delta: float) -> void:
	var before := _slowed
	_slowed = {}
	for index in range(areas.size() - 1, -1, -1):
		var area: Dictionary = areas[index]
		area.left = float(area.left) - delta
		var node: MeshInstance3D = area.node
		if float(area.left) <= 0.0:
			if is_instance_valid(node):
				node.queue_free()
			areas.remove_at(index)
			continue
		if is_instance_valid(node):
			TG.set_opacity(node, clampf(float(area.left) / 0.6, 0.0, 1.0))
		var center: Vector3 = area.center
		var radius := float(area.radius)
		# Spore clouds keep puffing (the painted spore burst, own sprite pool).
		if float(area.slow) < 1.0:
			area["puff"] = float(area.get("puff", 0.0)) - delta
			if float(area.puff) <= 0.0:
				area.puff = 0.18
				var angle := randf() * TAU
				_vfx_spawn("spore", center + Vector3(cos(angle), 0, sin(angle)) * radius * sqrt(randf()) * 0.8, 1.2)
		for target in _targets():
			if not is_instance_valid(target) or _flat_distance(target.global_position, center) > radius:
				continue
			_hit(target, float(area.dps) * _scale() * delta)
			if float(area.slow) < 1.0 and "slow_factor" in target:
				var id: int = target.get_instance_id()
				_slowed[id] = target
				target.set("slow_factor", minf(float(target.get("slow_factor")), float(area.slow)))
		_brood_circle(center, radius, float(area.dps) * _scale() * delta)
	# Whoever left every cloud walks at full speed again.
	for id in before:
		if not _slowed.has(id):
			var target: Variant = before[id]
			if is_instance_valid(target) and "slow_factor" in target:
				target.set("slow_factor", 1.0)


# Frees every target this ability slowed (clear / reset).
func _release_slows() -> void:
	for id in _slowed:
		var target: Variant = _slowed[id]
		if is_instance_valid(target) and "slow_factor" in target:
			target.set("slow_factor", 1.0)
	_slowed.clear()


func _vfx_spawn(kind: String, at: Vector3, size: float) -> void:
	if _vfx != null and is_instance_valid(_vfx) and _vfx.is_inside_tree():
		_vfx.spawn(kind, at, size)
