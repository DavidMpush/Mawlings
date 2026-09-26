extends Node3D

# Mire Leaper: lurks crouched at range, locks a landing zone, then jumps there in
# a visible arc. The zone never moves after it is announced. After landing it is
# exhausted (vulnerable) and finally hops back to keep its distance.

const TUNING = preload("res://scripts/tuning.gd")
const FX = preload("res://scripts/fx.gd")
const TG = preload("res://scripts/telegraph_style.gd")
const FX_BATCH = preload("res://scripts/fx_batch.gd")

const ARRIVE_SECONDS := 0.8
const BODY_RADIUS := 0.7
const ARC_DOTS := 11
const LAND_SQUASH_SECONDS := 0.3
const MODEL_SCALE := 1.25
const CREATURE_SHADER = preload("res://shaders/creature.gdshader")
const REAPER_SCENE = preload("res://assets/gameplay/characters/MireReaper_game.glb")
# Model units -> metres before MODEL_SCALE: ~1.55 m tall, ~2.2 m long in play.
const REAPER_SCALE := 1.9
const REAPER_BRIGHTNESS := 1.45
const REAPER_SATURATION := 1.3

const LIME := Color("c8ff5a")

const RIM_STALK := Color("b89cff")
const RIM_WARNING := Color("ff5ad9")
const RIM_EXHAUSTED := Color("ffe07a")
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
# Base loss of the landing resolved during the last step() (0 = none).
var resolved_power := 0
var hit_flash := 0.0
var warning: Node3D
# Jump arc dots: an fx_batch.gd MultiMesh (begin/add/finish); `visible` follows the state.
var arc: MultiMeshInstance3D
# Presentation only: nothing below feeds back into game logic.
var body: Node3D
var hind_legs: Array[Node3D] = []
var skins: Array[ShaderMaterial] = []
var shadow: MeshInstance3D
var health_bar: Node3D
var health_fill: MeshInstance3D
# Patterned landing zone (telegraph_style.gd "leaper") inside `warning`.
var zone: MeshInstance3D
var arrow: MeshInstance3D
var hop_start := Vector3.ZERO
var hop_end := Vector3.ZERO
var _time := 0.0
var _land := 0.0
var _rim := RIM_STALK
var _crouch := 0.0
var _pitch := 0.0
var _stretch := 0.0
var _fold := 0.0
static var _reaper_mesh: Mesh
static var _reaper_base := Transform3D.IDENTITY
# Etappe 07: shared by every leaper (built once).
static var _arc_dot_mesh: SphereMesh
static var _shadow_material: StandardMaterial3D
static var _shadow_plane: PlaneMesh
static var _bar_mesh: BoxMesh


func _ready() -> void:
	body = Node3D.new()
	body.name = "Mire Leaper body"
	add_child(body)
	_build_model(body)
	shadow = _make_shadow()
	health_bar = Node3D.new()
	add_child(health_bar)
	if _bar_mesh == null:
		_bar_mesh = BoxMesh.new()
		_bar_mesh.size = Vector3(1.3, 0.07, 0.12)
	health_fill = _part(health_bar, _bar_mesh, _flat(LIME), Vector3.ZERO)
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
	resolved_power = 0
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
			resolved_power = damage
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


# Locked landing zone footprint.
func contains(point: Vector3) -> bool:
	return _flat_distance(point, landing_center) <= TUNING.LEAPER_ZONE_RADIUS


# Share of the given world points inside the locked attack area (0..1).
func hit_fraction(points: PackedVector3Array) -> float:
	if points.is_empty():
		return 0.0
	var inside := 0
	for point in points:
		if contains(point):
			inside += 1
	return float(inside) / float(points.size())


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

# The leaper look: the user's Mire Reaper model (vertex colours, one shared mesh)
# under `parent`, facing local +Z with its feet at y = 0. Every leaper owns one
# ShaderMaterial (registered as skin) so rim and hit flash stay per creature.
func _build_model(parent: Node3D) -> void:
	if _reaper_mesh == null:
		var root := REAPER_SCENE.instantiate()
		var source: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]
		var base := Transform3D.IDENTITY
		var node: Node = source
		while node != root and node is Node3D:
			base = (node as Node3D).transform * base
			node = node.get_parent()
		_reaper_mesh = source.mesh
		_reaper_base = base
		root.free()
	var skin := ShaderMaterial.new()
	skin.shader = CREATURE_SHADER
	skin.set_shader_parameter("brightness", REAPER_BRIGHTNESS)
	skin.set_shader_parameter("saturation", REAPER_SATURATION)
	skin.set_shader_parameter("shape_light", 0.3)
	skin.set_shader_parameter("rim_power", 3.2)
	skins.append(skin)
	var model := MeshInstance3D.new()
	model.name = "Mire Reaper model"
	model.mesh = _reaper_mesh
	model.material_override = skin
	model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Stand on the ground, centred over the body pivot, head along +Z.
	var shape := Basis.from_scale(Vector3.ONE * REAPER_SCALE) * _reaper_base.basis
	var bounds: AABB = Transform3D(shape, Vector3.ZERO) * _reaper_mesh.get_aabb()
	model.transform = Transform3D(shape, Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z))
	parent.add_child(model)


func _build_warning() -> void:
	warning = Node3D.new()
	warning.name = "Leaper landing zone"
	add_child(warning)
	warning.top_level = true
	zone = TG.build("leaper", TUNING.LEAPER_ZONE_RADIUS)
	zone.position = Vector3(0.0, 0.1, 0.0)
	warning.add_child(zone)
	# Downward arrow over the centre: "something lands here".
	var cone := CylinderMesh.new()
	cone.top_radius = 0.42
	cone.bottom_radius = 0.0
	cone.height = 0.7
	cone.radial_segments = 4
	var palette: Dictionary = TG.PALETTE_COLORBLIND if TG.UI_STYLE.colorblind else TG.PALETTE
	arrow = _part(warning, cone, _flat(palette["leaper"]["pattern"]), Vector3(0.0, 1.2, 0.0))
	warning.visible = false
	# Etappe 07: all arc dots are one MultiMesh (one draw call, shared material).
	if _arc_dot_mesh == null:
		_arc_dot_mesh = SphereMesh.new()
		_arc_dot_mesh.radius = 0.16
		_arc_dot_mesh.height = 0.32
		_arc_dot_mesh.radial_segments = 10
		_arc_dot_mesh.rings = 5
	arc = FX_BATCH.create(_arc_dot_mesh, ARC_DOTS, false, true, "Leaper jump arc")
	add_child(arc)
	arc.top_level = true
	arc.transform = Transform3D.IDENTITY
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
	# One rigid model: crouch widens and flattens, stretch lengthens it along +Z.
	body.scale = Vector3(1.0 + 0.28 * squat, 1.0 - 0.42 * squat, 1.0 + 0.08 * squat + 0.9 * _stretch) * lerpf(0.2, 1.0, appear) * MODEL_SCALE
	for hip in hind_legs:
		hip.rotation.x = _fold
	var shadow_size := clampf(1.0 - height / 5.0, 0.4, 1.0) * lerpf(0.3, 1.0, appear)
	shadow.scale = Vector3(shadow_size, 1.0, shadow_size)
	health_bar.position = Vector3(0.0, 2.15 + height, 0.0)
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
		TG.set_progress(zone, progress)
		arrow.position.y = 1.3 - 0.35 * fposmod(_time * 1.6, 1.0)
		arrow.rotation.y = _time * 1.5
	if state == State.WARNING or state == State.LEAP:
		var start := Vector3(jump_start.x, 0.0, jump_start.z)
		var peak := _arc_height()
		arc.begin()
		for index in ARC_DOTS:
			# Dots march from the leaper to the zone along the flight parabola.
			var t := fposmod((float(index) + _time * 2.2) / float(ARC_DOTS), 1.0)
			var point := start.lerp(landing_center, t)
			point.y = 0.6 + 4.0 * peak * t * (1.0 - t) * 0.85
			var size := lerpf(0.6, 1.2, t)
			arc.add(Transform3D(Basis.from_scale(Vector3.ONE * size), point), ARC_COLOR)
		# Visibility of the arc stays with the state machine.
		arc.finish(false)


func _fx_parent() -> Node:
	return get_parent() if get_parent() != null else self


func _flat(color: Color) -> StandardMaterial3D:
	return FX_BATCH.shared_material(color, true)


func _make_shadow() -> MeshInstance3D:
	if _shadow_material != null:
		var shared := _part(self, _shadow_plane, _shadow_material, Vector3(0.0, 0.06, 0.0))
		shared.name = "Mire Leaper shadow"
		return shared
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
	_shadow_material = StandardMaterial3D.new()
	_shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_material.albedo_texture = texture
	_shadow_plane = PlaneMesh.new()
	_shadow_plane.size = Vector2(2.7, 2.7)
	var part := _part(self, _shadow_plane, _shadow_material, Vector3(0.0, 0.06, 0.0))
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
