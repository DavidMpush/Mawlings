extends Node3D

const TUNING = preload("res://scripts/tuning.gd")
const FX = preload("res://scripts/fx.gd")
const TG = preload("res://scripts/telegraph_style.gd")
# Stage 11: the user's reworked Bog King (BogKing_game.glb stays for the Aschenkroete).
const MODEL = preload("res://assets/gameplay/characters/BogKingNew_game.glb")
const CREATURE_SHADER = preload("res://shaders/creature_anim.gdshader")

const ARRIVE_SECONDS := 1.4
const EMERGE_DEPTH := 4.0
const RIM_CHASE := Color("d8b8ff")
const RIM_WARNING := Color("ff8a5c")
const RIM_RECOVERY := Color("ffe07a")
const DUST := Color(0.56, 0.42, 0.28, 0.6)
const SLAM_SECONDS := 0.4

enum State { ARRIVING, CHASE, WARNING, RECOVERY }

var state := State.ARRIVING
var remaining := ARRIVE_SECONDS
var health := TUNING.BOSS_HEALTH
var max_health := TUNING.BOSS_HEALTH
var attack_center := Vector3.ZERO
var attack_power := 0
# Base loss of the stomp resolved during the last step() (0 = none).
var resolved_power := 0
var hit_flash := 0.0
var model: Node3D
var warning: Node3D
# Presentation only: nothing below feeds back into game logic.
var emerge := 0.0
var body: Node3D
var skin: ShaderMaterial
var shadow: MeshInstance3D
# Patterned stomp area (telegraph_style.gd "boss") inside `warning`.
var zone: MeshInstance3D
var _time := 0.0
var _gait := 0.0
var _slam := 0.0
var _rim := RIM_CHASE
var _lift := 0.0
var _lean := 0.0
var _sway := 0.0
var _stretch := 0.0
# Limb uniforms for creature_anim.gdshader (smoothed like the body pose).
var _walk := 0.0
var _stomp_leg := 0.0
var _jaw := 0.0


func _ready() -> void:
	body = Node3D.new()
	body.name = "Bog King body"
	add_child(body)
	model = MODEL.instantiate()
	model.name = "Bog King game model"
	model.scale = Vector3.ONE * 7.0
	# The glb faces local +Z; turn it so it faces the boss's -X heading (see rotation.y in _logic).
	model.rotation.y = -PI * 0.5
	body.add_child(model)
	skin = ShaderMaterial.new()
	skin.shader = CREATURE_SHADER
	skin.set_shader_parameter("brightness", 1.4)
	skin.set_shader_parameter("saturation", 1.1)
	skin.set_shader_parameter("shape_light", 0.4)
	skin.set_shader_parameter("rim_color", _rim)
	skin.set_shader_parameter("rim_strength", 0.85)
	skin.set_shader_parameter("rim_power", 2.0)
	skin.set_shader_parameter("flash", 0.0)
	_setup_limbs()
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = skin
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow = _make_shadow()
	warning = Node3D.new()
	warning.name = "Bog King stomp warning"
	add_child(warning)
	warning.top_level = true
	zone = TG.build("boss", TUNING.BOSS_ATTACK_RADIUS)
	zone.position = Vector3(0, 0.11, 0)
	warning.add_child(zone)
	warning.visible = false
	warning.global_position = global_position
	FX.ring(self, global_position, Color(0.48, 0.34, 0.2, 0.85), 0.8, 4.2, 0.9)
	FX.ring(self, global_position, Color(0.66, 0.45, 0.95, 0.75), 0.4, 3.0, 1.2)
	_shake(0.25)
	_pose(0.0, 0.0, true)


func take_damage(amount: float) -> void:
	health -= amount
	hit_flash = 0.12


func step(delta: float, swarm_position: Vector3, pressure: float) -> int:
	resolved_power = 0
	var previous_state := state
	var previous_position := position
	var result := _logic(delta, swarm_position, pressure)
	if previous_state == State.WARNING and state == State.RECOVERY:
		_stomp()
	var speed := 0.0
	if delta > 0.0:
		speed = Vector2(position.x - previous_position.x, position.z - previous_position.z).length() / delta
	_pose(delta, speed)
	return result


# Game rules only (unchanged state machine, timing and damage).
func _logic(delta: float, swarm_position: Vector3, pressure: float) -> int:
	if state == State.CHASE:
		var offset := swarm_position - position
		offset.y = 0.0
		if offset.length() <= 4.7:
			state = State.WARNING
			remaining = TUNING.BOSS_WARNING_SECONDS
			attack_center = position
			attack_power = int(ceil(minf(1000000.0, TUNING.BOSS_DAMAGE * pressure)))
			warning.global_position = attack_center
			warning.visible = true
		else:
			var arena: Node3D = get_parent().get_parent().get_node("Arena")
			var direction: Vector3 = arena.steer_direction(position, swarm_position, 2.5)
			position = arena.resolve_motion(position, direction * minf(4.5, TUNING.BOSS_SPEED + log(pressure) * 0.35) * delta, 2.5)
			if direction.length_squared() > 0.01:
				rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z) + PI * 0.5, minf(1.0, delta * 3.0))
		return 0
	remaining -= delta
	if remaining > 0.0:
		return 0
	if state == State.ARRIVING:
		state = State.CHASE
	elif state == State.WARNING:
		state = State.RECOVERY
		remaining = TUNING.BOSS_RECOVERY_SECONDS
		warning.visible = false
		resolved_power = attack_power
		if swarm_position.distance_to(attack_center) <= TUNING.BOSS_ATTACK_RADIUS:
			return attack_power
	elif state == State.RECOVERY:
		state = State.CHASE
	return 0


# Locked stomp circle footprint.
func contains(point: Vector3) -> bool:
	return Vector2(point.x - attack_center.x, point.z - attack_center.z).length() <= TUNING.BOSS_ATTACK_RADIUS


# Share of the given world points inside the locked attack area (0..1).
func hit_fraction(points: PackedVector3Array) -> float:
	if points.is_empty():
		return 0.0
	var inside := 0
	for point in points:
		if contains(point):
			inside += 1
	return float(inside) / float(points.size())


# Updates body pose, rim, shadow and warning visuals. Model faces local -X:
# +body.rotation.z leans forward, -z rears up, body.rotation.x rocks sideways.
func refresh_pose() -> void:
	_pose(0.0, 0.0, true)


func _pose(delta: float, speed: float, snap: bool = false) -> void:
	_time += delta
	hit_flash = maxf(0.0, hit_flash - delta)
	_slam = maxf(0.0, _slam - delta)
	emerge = clampf(1.0 - remaining / ARRIVE_SECONDS, 0.0, 1.0) if state == State.ARRIVING else 1.0
	var lift := 0.0
	var walk := 0.0
	var stomp_leg := 0.0
	var jaw := 0.0
	var lean := 0.0
	var sway := 0.0
	var stretch := 0.0
	var tremble := 0.0
	var rim_target := RIM_CHASE
	var rim_strength := 0.85
	match state:
		State.ARRIVING:
			tremble = 0.07 * (1.0 - emerge)
			lean = -0.12 * (1.0 - emerge)
		State.CHASE:
			var stride := minf(1.0, speed / TUNING.BOSS_SPEED)
			var before := sin(_gait)
			_gait += speed * delta * 1.9
			var wave := sin(_gait)
			if stride > 0.2 and before != 0.0 and signf(wave) != signf(before):
				FX.ring(_fx_parent(), global_position, DUST, 0.4, 1.6, 0.35)
				_shake(0.05)
			lift = absf(wave) * 0.28 * stride
			walk = stride
			sway = wave * 0.075 * stride
			lean = 0.07 * stride
		State.WARNING:
			var progress := clampf(1.0 - remaining / TUNING.BOSS_WARNING_SECONDS, 0.0, 1.0)
			var rise := 1.0 - pow(1.0 - minf(1.0, progress / 0.7), 3.0)
			lift = 0.7 * rise
			lean = -0.3 * rise
			stretch = 0.06 * rise
			stomp_leg = rise
			jaw = 0.8 * rise
			tremble = 0.09 * smoothstep(0.6, 1.0, progress)
			rim_target = RIM_WARNING
			TG.set_progress(zone, progress)
		State.RECOVERY:
			var breath := sin(_time * 2.1)
			lift = -0.12
			lean = 0.2 + 0.03 * breath
			stretch = 0.035 * breath
			jaw = 0.35 + 0.15 * breath
			rim_target = RIM_RECOVERY
			rim_strength = 0.8 + 0.35 * (0.5 + 0.5 * sin(_time * 5.0))
	if state != State.WARNING:
		TG.set_progress(zone, 0.0)
	if _slam > 0.0:
		var slam := _slam / SLAM_SECONDS
		lean += 0.32 * slam
		lift -= 0.12 * slam
		stretch -= 0.2 * slam
		stomp_leg = 0.0
	var flash := 0.0
	if hit_flash > 0.0:
		flash = 0.18 + 0.12 * (0.5 + 0.5 * sin(_time * 55.0))
		tremble += 0.05
	var weight := 1.0 if snap else minf(1.0, delta * 12.0)
	_lift = lerpf(_lift, lift, weight)
	_lean = lerpf(_lean, lean, weight)
	_sway = lerpf(_sway, sway, weight)
	_stretch = lerpf(_stretch, stretch, weight)
	_walk = lerpf(_walk, walk, weight)
	_jaw = lerpf(_jaw, jaw, weight)
	# The stomping foot slams down much faster than it rises.
	_stomp_leg = stomp_leg if snap or stomp_leg < _stomp_leg else lerpf(_stomp_leg, stomp_leg, weight)
	_rim = rim_target if snap else _rim.lerp(rim_target, minf(1.0, delta * 5.0))
	var risen := 1.0 - pow(1.0 - emerge, 3.0)
	var jitter := Vector3(sin(_time * 47.0), 0.0, sin(_time * 39.0 + 1.3)) * tremble
	body.position = Vector3(0.0, _lift - EMERGE_DEPTH * (1.0 - risen), 0.0) + jitter
	body.rotation = Vector3(_sway, 0.0, _lean)
	body.scale = Vector3(1.0 - _stretch * 0.5, 1.0 + _stretch, 1.0 - _stretch * 0.5)
	var shadow_size := lerpf(0.3, 1.0, risen) * (1.0 - 0.18 * clampf(_lift / 0.7, 0.0, 1.0))
	shadow.scale = Vector3(shadow_size, 1.0, shadow_size)
	skin.set_shader_parameter("rim_color", _rim)
	skin.set_shader_parameter("rim_strength", rim_strength)
	skin.set_shader_parameter("flash", flash)
	skin.set_shader_parameter("walk_amount", _walk)
	# Footfall of each diagonal pair lands on a sign change of the body wave (dust ring).
	skin.set_shader_parameter("walk_phase", _gait + PI * 0.5)
	skin.set_shader_parameter("stomp_lift", _stomp_leg)
	skin.set_shader_parameter("bite_amount", _jaw)
	skin.set_shader_parameter("tail_phase", _time * 1.6)


# Limb animation frame for BogKingNew_game.glb, measured in raw mesh space (Z-up
# storage): soles at z = 0 (up = -Z), head towards +Y, long low tail towards -Y
# (tip at -0.74), lateral = +X. Feet centres (forward, lateral) from clustering the
# lowest 5 % of vertices: hands close together in front, hind feet splayed wide at
# the sides (stomp foot nudged outwards, small radius: the two hands stand only
# 0.2 apart and the lifted one must not stretch its neighbour; lower stomp height
# keeps the raised hand below the jaw floor). Mouth: upper jaw ends at u ~0.31.
func _setup_limbs() -> void:
	skin.set_shader_parameter("up_axis", Vector3(0.0, 0.0, -1.0))
	skin.set_shader_parameter("forward_axis", Vector3(0.0, 1.0, 0.0))
	skin.set_shader_parameter("ground_offset", 0.0)
	skin.set_shader_parameter("foot_a_front", Vector2(0.281, -0.13))
	skin.set_shader_parameter("foot_a_back", Vector2(-0.02, 0.238))
	skin.set_shader_parameter("foot_b_front", Vector2(0.277, 0.089))
	skin.set_shader_parameter("foot_b_back", Vector2(-0.028, -0.23))
	skin.set_shader_parameter("foot_radius", 0.11)
	skin.set_shader_parameter("leg_height", 0.2)
	skin.set_shader_parameter("stride", 0.05)
	skin.set_shader_parameter("lift", 0.05)
	skin.set_shader_parameter("stride_centering", 1.0)
	skin.set_shader_parameter("walk_speed", 0.0)
	skin.set_shader_parameter("walk_scale", 1.0)
	skin.set_shader_parameter("jaw_hinge_forward", 0.2)
	skin.set_shader_parameter("jaw_hinge_height", 0.315)
	skin.set_shader_parameter("jaw_floor", 0.2)
	skin.set_shader_parameter("jaw_angle", 0.6)
	skin.set_shader_parameter("tail_start", -0.32)
	skin.set_shader_parameter("tail_length", 0.42)
	skin.set_shader_parameter("tail_floor", 0.03)
	skin.set_shader_parameter("tail_swing", 0.04)
	skin.set_shader_parameter("tail_rate", 0.0)
	skin.set_shader_parameter("stomp_height", 0.11)


func _stomp() -> void:
	var parent := _fx_parent()
	FX.ring(parent, attack_center, Color(1.0, 0.56, 0.24, 0.95), 0.8, TUNING.BOSS_ATTACK_RADIUS * 1.15, 0.45)
	FX.ring(parent, attack_center, DUST, 0.6, TUNING.BOSS_ATTACK_RADIUS * 0.8, 0.7)
	_shake(0.5)
	_slam = SLAM_SECONDS


func _shake(amount: float) -> void:
	var main: Node = get_parent().get_parent() if get_parent() else null
	if main != null and main.has_method("add_shake"):
		main.add_shake(amount)


func _fx_parent() -> Node:
	return get_parent() if get_parent() != null else self


func _make_shadow() -> MeshInstance3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.02, 0.04, 0.02, 0.55))
	gradient.set_color(1, Color(0.02, 0.04, 0.02, 0.0))
	gradient.add_point(0.55, Color(0.02, 0.04, 0.02, 0.38))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = texture
	var plane := PlaneMesh.new()
	plane.size = Vector2(4.8, 4.8)
	var part := _part(self, plane, material, Vector3(0, 0.06, 0))
	part.name = "Bog King shadow"
	return part


func _part(parent: Node3D, mesh: Mesh, material: Material, location: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = location
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part
