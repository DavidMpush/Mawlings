extends Node3D

# Mire Leaper: lurks crouched at range, locks a landing zone, then jumps there in
# a visible arc. The zone never moves after it is announced. After landing it is
# exhausted (vulnerable) and finally hops back to keep its distance.

const TUNING = preload("res://scripts/tuning.gd")
const FX = preload("res://scripts/fx.gd")

const ARRIVE_SECONDS := 0.8
const BODY_RADIUS := 0.7
const ARC_DOTS := 11
const LAND_SQUASH_SECONDS := 0.3
const MODEL_SCALE := 1.25

const TEAL := Color("2e9e97")
const TEAL_DARK := Color("1f6f73")
const VIOLET := Color("5a3d9e")
const INDIGO := Color("2b2a5c")
const BONE := Color("d8cca8")
const LIME := Color("c8ff5a")

const RIM_STALK := Color("b89cff")
const RIM_WARNING := Color("ff5ad9")
const RIM_EXHAUSTED := Color("ffe07a")
const ZONE_RING := Color("ff4fd8")
const ZONE_BRIGHT := Color("ffe3fa")
const ZONE_FILL := Color(0.62, 0.22, 0.95, 0.2)
const ARC_COLOR := Color("ff8ae6")

enum State { ARRIVING, STALK, WARNING, LEAP, EXHAUSTED, RETREAT }

var state := State.ARRIVING
var remaining := ARRIVE_SECONDS
var lurk := TUNING.LEAPER_LURK_SECONDS
var health := TUNING.LEAPER_HEALTH
var max_health := TUNING.LEAPER_HEALTH
var jump_start := Vector3.ZERO
var landing_center := Vector3.ZERO
var damage := 0
var hit_flash := 0.0
var warning: Node3D
var arc: Node3D
# Presentation only: nothing below feeds back into game logic.
var body: Node3D
var hind_legs: Array[Node3D] = []
var skins: Array[ShaderMaterial] = []
var shadow: MeshInstance3D
var health_bar: Node3D
var health_fill: MeshInstance3D
var zone_fill: MeshInstance3D
var zone_ring: MeshInstance3D
var closing_ring: MeshInstance3D
var arrow: MeshInstance3D
var ring_material: StandardMaterial3D
var arc_dots: Array[MeshInstance3D] = []
var hop_start := Vector3.ZERO
var hop_end := Vector3.ZERO
var _time := 0.0
var _land := 0.0
var _rim := RIM_STALK
var _crouch := 0.0
var _pitch := 0.0
var _stretch := 0.0
var _fold := 0.0
static var _skin_shader: Shader


func _ready() -> void:
	body = Node3D.new()
	body.name = "Mire Leaper body"
	add_child(body)
	_build_model(body)
	shadow = _make_shadow()
	health_bar = Node3D.new()
	add_child(health_bar)
	var bar := BoxMesh.new()
	bar.size = Vector3(1.3, 0.07, 0.12)
	health_fill = _part(health_bar, bar, _flat(LIME), Vector3.ZERO)
	_build_warning()
	FX.ring(_fx_parent(), global_position, Color(0.45, 0.3, 0.85, 0.8), 0.3, 2.0, 0.6)
	_pose(0.0, 0.0, true)


func take_damage(amount: float) -> void:
	health -= amount
	hit_flash = 0.12


# True while grounded and reachable by the swarm's automatic attack.
func can_be_hit() -> bool:
	return state in [State.STALK, State.WARNING, State.EXHAUSTED]


# Returns the loss of exactly one resolved landing, otherwise 0.
func step(delta: float, swarm_position: Vector3, pressure: float) -> int:
	var previous_state := state
	var previous_position := position
	var result := _logic(delta, swarm_position, pressure)
	if previous_state == State.LEAP and state != State.LEAP:
		_on_landing()
	var speed := 0.0
	if delta > 0.0:
		speed = Vector2(position.x - previous_position.x, position.z - previous_position.z).length() / delta
	_pose(delta, speed)
	return result


# Game rules only: state machine, locked zone, timing and damage.
func _logic(delta: float, swarm_position: Vector3, pressure: float) -> int:
	if state == State.STALK:
		var offset := swarm_position - position
		offset.y = 0.0
		var distance := offset.length()
		if distance > 0.01:
			rotation.y = lerp_angle(rotation.y, atan2(offset.x, offset.z), minf(1.0, delta * 6.0))
		if distance <= TUNING.LEAPER_RANGE:
			lurk -= delta
			if lurk <= 0.0:
				_lock_zone(swarm_position, pressure)
				return 0
		if distance > TUNING.LEAPER_RANGE * 0.8:
			var arena: Node3D = _arena()
			var direction: Vector3 = arena.steer_direction(position, swarm_position, BODY_RADIUS)
			position = arena.resolve_motion(position, direction * minf(6.0, TUNING.LEAPER_SPEED + 0.6 * log(pressure)) * delta, BODY_RADIUS)
		return 0
	remaining -= delta
	if state == State.LEAP:
		var fraction := clampf(1.0 - remaining / TUNING.LEAPER_FLIGHT_SECONDS, 0.0, 1.0)
		position = jump_start.lerp(landing_center, fraction)
	elif state == State.RETREAT:
		var fraction := clampf(1.0 - remaining / TUNING.LEAPER_RETREAT_SECONDS, 0.0, 1.0)
		position = hop_start.lerp(hop_end, fraction)
	if remaining > 0.0:
		return 0
	match state:
		State.ARRIVING:
			state = State.STALK
			lurk = TUNING.LEAPER_LURK_SECONDS
		State.WARNING:
			state = State.LEAP
			remaining = TUNING.LEAPER_FLIGHT_SECONDS
		State.LEAP:
			position = landing_center
			state = State.EXHAUSTED
			remaining = TUNING.LEAPER_EXHAUST_SECONDS
			warning.visible = false
			arc.visible = false
			if _flat_distance(swarm_position, landing_center) <= TUNING.LEAPER_ZONE_RADIUS:
				return damage
		State.EXHAUSTED:
			_start_retreat(swarm_position)
		State.RETREAT:
			position = hop_end
			state = State.STALK
			lurk = TUNING.LEAPER_LURK_SECONDS
	return 0


func _lock_zone(swarm_position: Vector3, pressure: float) -> void:
	jump_start = position
	var offset := swarm_position - position
	offset.y = 0.0
	var target := Vector3(swarm_position.x, 0.0, swarm_position.z)
	if offset.length() > TUNING.LEAPER_RANGE:
		target = position + offset.normalized() * TUNING.LEAPER_RANGE
	# Jumps clear stones, but never lands inside one.
	landing_center = _arena().safe_spawn(target, BODY_RADIUS)
	landing_center.y = 0.0
	damage = int(ceil(minf(1000000.0, TUNING.LEAPER_DAMAGE * pressure)))
	state = State.WARNING
	remaining = TUNING.LEAPER_WARNING_SECONDS
	var line := landing_center - jump_start
	if line.length() > 0.05:
		rotation.y = atan2(line.x, line.z)
	warning.global_position = landing_center
	warning.visible = true
	arc.visible = true


func _start_retreat(swarm_position: Vector3) -> void:
	var away := position - swarm_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = -Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	hop_start = position
	hop_end = _arena().clear_line(position, position + away.normalized() * TUNING.LEAPER_RETREAT_DISTANCE, BODY_RADIUS)
	hop_end.y = 0.0
	if hop_end.distance_to(hop_start) < 0.3:
		state = State.STALK
		lurk = TUNING.LEAPER_LURK_SECONDS
		return
	state = State.RETREAT
	remaining = TUNING.LEAPER_RETREAT_SECONDS


# Distance from the locked landing zone edge; negative means inside the zone.
func zone_margin(location: Vector3) -> float:
	return _flat_distance(location, landing_center) - TUNING.LEAPER_ZONE_RADIUS


func dodge_direction(location: Vector3) -> Vector3:
	var away := location - landing_center
	away.y = 0.0
	if away.length_squared() < 0.01:
		var line := landing_center - jump_start
		away = Vector3(line.z, 0.0, -line.x)
	return away.normalized() if away.length_squared() > 0.0001 else Vector3.RIGHT


func cleanup() -> void:
	if is_instance_valid(warning):
		warning.visible = false
	if is_instance_valid(arc):
		arc.visible = false


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _arena() -> Node3D:
	return get_parent().get_parent().get_node("Arena")


# ---------------------------------------------------------------- presentation

# Swap point for a real model: build everything the leaper looks like under
# `parent` (faces local +Z, feet at y = 0). Register skins with _skin() so rim
# and hit flash keep working; hind_legs pivots are optional.
func _build_model(parent: Node3D) -> void:
	var teal := _skin(TEAL)
	var teal_dark := _skin(TEAL_DARK)
	var violet := _skin(VIOLET)
	var indigo := _skin(INDIGO)
	var bone := _skin(BONE)
	var glow := _flat(LIME)
	var torso := SphereMesh.new()
	torso.radius = 0.55
	torso.height = 1.0
	var chest := _part(parent, torso, violet, Vector3(0.0, 0.62, 0.05))
	chest.scale = Vector3(1.15, 0.72, 1.2)
	var belly := SphereMesh.new()
	belly.radius = 0.42
	belly.height = 0.6
	var under := _part(parent, belly, bone, Vector3(0.0, 0.42, 0.22))
	under.scale = Vector3(1.0, 0.8, 1.1)
	# Angular back plates along the spine.
	for index in 3:
		var plate := PrismMesh.new()
		plate.size = Vector3(0.5 - index * 0.08, 0.42 - index * 0.06, 0.34)
		var spine := _part(parent, plate, teal if index != 1 else teal_dark, Vector3(0.0, 0.98 - index * 0.04, 0.28 - index * 0.32))
		spine.rotation.x = -0.35
		var spot := SphereMesh.new()
		spot.radius = 0.07
		spot.height = 0.1
		_part(parent, spot, glow, Vector3(0.0, 0.95 - index * 0.05, 0.36 - index * 0.32))
	# Blocky head with bone jaw and lime eyes.
	var skull := BoxMesh.new()
	skull.size = Vector3(0.74, 0.36, 0.58)
	var head := _part(parent, skull, teal, Vector3(0.0, 0.7, 0.72))
	head.rotation.x = 0.12
	var brow := PrismMesh.new()
	brow.size = Vector3(0.78, 0.2, 0.5)
	_part(parent, brow, indigo, Vector3(0.0, 0.92, 0.68))
	var jaw := BoxMesh.new()
	jaw.size = Vector3(0.62, 0.16, 0.52)
	_part(parent, jaw, bone, Vector3(0.0, 0.5, 0.78))
	for side in [-1.0, 1.0]:
		var eye := SphereMesh.new()
		eye.radius = 0.085
		eye.height = 0.12
		_part(parent, eye, glow, Vector3(side * 0.24, 0.76, 1.0))
		# Oversized folded hind leg on a hip pivot so the pose can fold/extend it.
		var hip := Node3D.new()
		hip.name = "Hind leg"
		hip.position = Vector3(side * 0.62, 0.62, -0.35)
		parent.add_child(hip)
		hind_legs.append(hip)
		var thigh_mesh := SphereMesh.new()
		thigh_mesh.radius = 0.36
		thigh_mesh.height = 1.15
		var thigh := _part(hip, thigh_mesh, teal, Vector3(0.0, -0.05, 0.1))
		thigh.rotation.x = 0.9
		var thigh_glow := SphereMesh.new()
		thigh_glow.radius = 0.09
		thigh_glow.height = 0.16
		_part(hip, thigh_glow, glow, Vector3(side * 0.3, 0.02, 0.1))
		var shin_mesh := CapsuleMesh.new()
		shin_mesh.radius = 0.12
		shin_mesh.height = 0.75
		var shin := _part(hip, shin_mesh, indigo, Vector3(0.0, -0.3, -0.3))
		shin.rotation.x = -0.7
		var foot := BoxMesh.new()
		foot.size = Vector3(0.28, 0.1, 0.45)
		_part(hip, foot, indigo, Vector3(0.0, -0.57, -0.05))
		# Short front legs.
		var arm_mesh := CapsuleMesh.new()
		arm_mesh.radius = 0.1
		arm_mesh.height = 0.55
		var arm := _part(parent, arm_mesh, teal_dark, Vector3(side * 0.42, 0.28, 0.6))
		arm.rotation.z = side * 0.25
		var claw := BoxMesh.new()
		claw.size = Vector3(0.22, 0.08, 0.3)
		_part(parent, claw, indigo, Vector3(side * 0.46, 0.04, 0.7))


func _build_warning() -> void:
	warning = Node3D.new()
	warning.name = "Leaper landing zone"
	add_child(warning)
	warning.top_level = true
	var disc := CylinderMesh.new()
	disc.top_radius = TUNING.LEAPER_ZONE_RADIUS
	disc.bottom_radius = TUNING.LEAPER_ZONE_RADIUS
	disc.height = 0.02
	disc.radial_segments = 48
	var fill_material := _flat(ZONE_FILL)
	fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	zone_fill = _part(warning, disc, fill_material, Vector3(0.0, 0.1, 0.0))
	var ring := TorusMesh.new()
	ring.inner_radius = TUNING.LEAPER_ZONE_RADIUS - 0.2
	ring.outer_radius = TUNING.LEAPER_ZONE_RADIUS
	ring.rings = 56
	ring.ring_segments = 6
	ring_material = _flat(ZONE_RING)
	zone_ring = _part(warning, ring, ring_material, Vector3(0.0, 0.13, 0.0))
	# Reticle that closes in on the fixed zone edge: remaining warning time.
	var thin := TorusMesh.new()
	thin.inner_radius = TUNING.LEAPER_ZONE_RADIUS - 0.08
	thin.outer_radius = TUNING.LEAPER_ZONE_RADIUS
	thin.rings = 56
	thin.ring_segments = 6
	var closing_material := _flat(Color(1.0, 0.72, 0.96, 0.85))
	closing_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	closing_ring = _part(warning, thin, closing_material, Vector3(0.0, 0.14, 0.0))
	# Downward arrow over the centre: "something lands here".
	var cone := CylinderMesh.new()
	cone.top_radius = 0.42
	cone.bottom_radius = 0.0
	cone.height = 0.7
	cone.radial_segments = 4
	arrow = _part(warning, cone, _flat(ZONE_RING), Vector3(0.0, 1.2, 0.0))
	warning.visible = false
	arc = Node3D.new()
	arc.name = "Leaper jump arc"
	add_child(arc)
	arc.top_level = true
	var dot := SphereMesh.new()
	dot.radius = 0.16
	dot.height = 0.32
	var dot_material := _flat(ARC_COLOR)
	for index in ARC_DOTS:
		arc_dots.append(_part(arc, dot, dot_material, Vector3.ZERO))
	arc.visible = false


func _arc_height() -> float:
	return 1.2 + 0.2 * _flat_distance(jump_start, landing_center)


func _on_landing() -> void:
	var parent := _fx_parent()
	FX.ring(parent, landing_center, Color(1.0, 0.4, 0.88, 0.95), 0.6, TUNING.LEAPER_ZONE_RADIUS * 1.2, 0.45)
	FX.ring(parent, landing_center, Color(0.4, 0.33, 0.25, 0.6), 0.4, TUNING.LEAPER_ZONE_RADIUS * 0.8, 0.6)
	_land = LAND_SQUASH_SECONDS
	var main: Node = get_parent().get_parent() if get_parent() != null else null
	if main != null and main.has_method("add_shake"):
		main.add_shake(0.2)


func _pose(delta: float, speed: float, snap: bool = false) -> void:
	_time += delta
	hit_flash = maxf(0.0, hit_flash - delta)
	_land = maxf(0.0, _land - delta)
	var crouch := 0.0
	var pitch := 0.0
	var stretch := 0.0
	var fold := 0.35
	var height := 0.0
	var tremble := 0.0
	var rim_target := RIM_STALK
	var rim_strength := 0.7
	var appear := 1.0
	match state:
		State.ARRIVING:
			appear = clampf(1.0 - remaining / ARRIVE_SECONDS, 0.0, 1.0)
			crouch = 0.3
		State.STALK:
			var stride := minf(1.0, speed / TUNING.LEAPER_SPEED)
			height = absf(sin(_time * 7.0)) * 0.18 * stride
			crouch = 0.18 + 0.04 * sin(_time * 2.4)
			fold = 0.45
		State.WARNING:
			var progress := clampf(1.0 - remaining / TUNING.LEAPER_WARNING_SECONDS, 0.0, 1.0)
			var rise := 1.0 - pow(1.0 - minf(1.0, progress / 0.6), 3.0)
			crouch = 0.18 + 0.2 * rise
			pitch = -0.22 * rise
			fold = 0.45 + 0.4 * rise
			tremble = 0.05 * smoothstep(0.55, 1.0, progress)
			rim_target = RIM_WARNING
			rim_strength = 0.9
		State.LEAP:
			var fraction := clampf(1.0 - remaining / TUNING.LEAPER_FLIGHT_SECONDS, 0.0, 1.0)
			height = 4.0 * _arc_height() * fraction * (1.0 - fraction)
			stretch = 0.2
			pitch = lerpf(-0.55, 0.5, fraction)
			fold = -0.6
			rim_target = RIM_WARNING
			rim_strength = 0.9
		State.EXHAUSTED:
			var breath := sin(_time * 3.2)
			crouch = 0.22 + 0.04 * breath
			pitch = 0.16
			fold = 0.2
			rim_target = RIM_EXHAUSTED
			rim_strength = 0.75 + 0.35 * (0.5 + 0.5 * sin(_time * 6.0))
		State.RETREAT:
			var fraction := clampf(1.0 - remaining / TUNING.LEAPER_RETREAT_SECONDS, 0.0, 1.0)
			height = 4.0 * 0.9 * fraction * (1.0 - fraction)
			stretch = 0.1
			pitch = lerpf(0.25, -0.25, fraction)
			fold = -0.2
	if _land > 0.0:
		var squash := _land / LAND_SQUASH_SECONDS
		crouch += 0.35 * squash
		fold += 0.5 * squash
	var weight := 1.0 if snap else minf(1.0, delta * 14.0)
	_crouch = lerpf(_crouch, crouch, weight)
	_pitch = lerpf(_pitch, pitch, weight)
	_stretch = lerpf(_stretch, stretch, weight)
	_fold = lerpf(_fold, fold, weight)
	_rim = rim_target if snap else _rim.lerp(rim_target, minf(1.0, delta * 6.0))
	var jitter := Vector3(sin(_time * 51.0), 0.0, sin(_time * 43.0 + 0.7)) * tremble
	var squat := _crouch - _stretch
	body.position = Vector3(0.0, height - 0.12 * _crouch, 0.0) + jitter
	body.rotation = Vector3(_pitch, 0.0, 0.0)
	body.scale = Vector3(1.0 + 0.3 * squat, 1.0 - 0.45 * squat, 1.0 + 0.1 * squat) * lerpf(0.2, 1.0, appear) * MODEL_SCALE
	for hip in hind_legs:
		hip.rotation.x = _fold
	var shadow_size := clampf(1.0 - height / 5.0, 0.4, 1.0) * lerpf(0.3, 1.0, appear)
	shadow.scale = Vector3(shadow_size, 1.0, shadow_size)
	health_bar.position = Vector3(0.0, 1.9 + height, 0.0)
	health_bar.rotation.y = -rotation.y
	health_fill.scale.x = clampf(health / max_health, 0.0, 1.0)
	var flash := 0.0
	if hit_flash > 0.0:
		flash = 0.2 + 0.15 * (0.5 + 0.5 * sin(_time * 55.0))
	for skin in skins:
		skin.set_shader_parameter("rim_color", _rim)
		skin.set_shader_parameter("rim_strength", rim_strength)
		skin.set_shader_parameter("flash", flash)
	_pose_warning()


func _pose_warning() -> void:
	if state == State.WARNING or state == State.LEAP:
		var progress := 0.0
		if state == State.WARNING:
			progress = clampf(1.0 - remaining / TUNING.LEAPER_WARNING_SECONDS, 0.0, 1.0)
		else:
			progress = 1.0
		var closing := lerpf(1.8, 1.0, progress)
		closing_ring.scale = Vector3(closing, 1.0, closing)
		var pulse := 0.5 + 0.5 * sin(_time * lerpf(9.0, 26.0, progress))
		ring_material.albedo_color = ZONE_RING.lerp(ZONE_BRIGHT, pulse * (0.3 + 0.6 * progress))
		arrow.position.y = 1.3 - 0.35 * fposmod(_time * 1.6, 1.0)
		arrow.rotation.y = _time * 1.5
	if state == State.WARNING or state == State.LEAP:
		var start := Vector3(jump_start.x, 0.0, jump_start.z)
		var peak := _arc_height()
		for index in arc_dots.size():
			# Dots march from the leaper to the zone along the flight parabola.
			var t := fposmod((float(index) + _time * 2.2) / float(arc_dots.size()), 1.0)
			var point := start.lerp(landing_center, t)
			point.y = 0.6 + 4.0 * peak * t * (1.0 - t) * 0.85
			arc_dots[index].global_position = point
			var size := lerpf(0.6, 1.2, t)
			arc_dots[index].scale = Vector3.ONE * size


func _fx_parent() -> Node:
	return get_parent() if get_parent() != null else self


func _skin(color: Color) -> ShaderMaterial:
	if _skin_shader == null:
		_skin_shader = Shader.new()
		# Same look as shaders/creature.gdshader, with a flat tint instead of vertex colour.
		_skin_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 tint : source_color = vec4(1.0);
uniform float shape_light = 0.4;
uniform vec4 rim_color : source_color = vec4(1.0);
uniform float rim_strength = 0.0;
uniform float rim_power = 2.2;
uniform float flash = 0.0;
void fragment() {
	vec3 base = tint.rgb * 1.15;
	vec3 normal = normalize(NORMAL);
	if (!FRONT_FACING) {
		normal = -normal;
	}
	float key = clamp(dot(normal, normalize(vec3(-0.35, 0.75, 0.55))) * 0.5 + 0.5, 0.0, 1.0);
	base *= mix(1.0 - shape_light, 1.0 + shape_light * 0.45, key);
	float rim = pow(1.0 - clamp(abs(dot(normal, VIEW)), 0.0, 1.0), rim_power) * rim_strength;
	base = mix(base, rim_color.rgb, clamp(rim, 0.0, 1.0));
	base = mix(base, vec3(1.0), clamp(flash, 0.0, 1.0));
	ALBEDO = base;
}
"""
	var material := ShaderMaterial.new()
	material.shader = _skin_shader
	material.set_shader_parameter("tint", color)
	skins.append(material)
	return material


func _flat(color: Color) -> StandardMaterial3D:
	var value := StandardMaterial3D.new()
	value.albedo_color = color
	value.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return value


func _make_shadow() -> MeshInstance3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.02, 0.04, 0.02, 0.55))
	gradient.set_color(1, Color(0.02, 0.04, 0.02, 0.0))
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
	plane.size = Vector2(2.7, 2.7)
	var part := _part(self, plane, material, Vector3(0.0, 0.06, 0.0))
	part.name = "Mire Leaper shadow"
	return part


func _part(parent: Node3D, mesh: Mesh, material: Material, location: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = location
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part
