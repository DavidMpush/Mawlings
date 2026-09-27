extends Node3D

const MAX_HEALTH := 8.0
const FLEE_SPEED := 1.8            # reference speed of the running animation (no fleeing since stage 09)
const NIBBLER_SCENE = preload("res://assets/gameplay/characters/Nibbler_game.glb")
const TUNING = preload("res://scripts/tuning.gd")
const TG = preload("res://scripts/telegraph_style.gd")
const UI_STYLE = preload("res://scripts/ui/ui_style.gd")
# Snap telegraph: the "hunter" ring pattern, small and in the Nibbler's teal.
const SNAP_FILL := Color("0e9c93")
const SNAP_PATTERN := Color("e9fffb")
const SNAP_EDGE := Color("f4fffb")
const CREATURE_SHADER = preload("res://shaders/creature.gdshader")
# Display only: target height in metres (a Mawling stands ~0.64 m in game).
const MODEL_HEIGHT := 1.0
const SHADOW_Y := 0.025
const FLEE_HOP := 0.26
const WANDER_HOP := 0.035

# Built once and shared by every Nibbler.
static var shadow_mesh: PlaneMesh
static var shadow_material: StandardMaterial3D
static var bar_mesh: BoxMesh
static var bar_material: StandardMaterial3D
# Etappe 08 Teil 2: bright outer contour of the snap circle, drawn above the swarm
# (no depth test) so the warning stays visible when Mawlings stand on the circle.
static var snap_ring_mesh: TorusMesh
static var snap_ring_material: StandardMaterial3D
static var snap_ring_dark_mesh: TorusMesh
static var snap_ring_dark_material: StandardMaterial3D
const SNAP_RING_LIFT := 0.2
const SNAP_RING_START := 0.45     # extra radius at the start; closes to SNAP_RING_END
const SNAP_RING_END := 0.06

var health := MAX_HEALTH
var wander_phase := 0.0
var health_fill: MeshInstance3D

# Presentation state; advanced only in step() so pause freezes it.
var body: Node3D
var shadow: MeshInstance3D
var material: ShaderMaterial
var model_scale := 1.0
var yaw := 0.0
var gait := 0.0
var clock := 0.0
var flee_share := 0.0
var last_position := Vector3.ZERO
var last_health := MAX_HEALTH
var flash := 0.0
var twitch := 0.0
var hit_cooldown := 0.0
# Movement multiplier set by attack forms (e.g. Sporenwolke); 1.0 = normal.
var slow_factor := 1.0
# Stage 08 · Nibbler wehren sich: bitten or surrounded, a Nibbler stops, announces
# a small locked circle (NIBBLER_SNAP_WARNING s) and snaps. HuntWorld resolves the
# hit per animal via resolved_power/contains() like every other area attack.
var snap_state := 0                 # 0 = free (approaching/holding), 1 = announcing a snap
var snap_remaining := 0.0
var snap_cooldown: float = TUNING.NIBBLER_SNAP_FIRST
# Set by HuntWorld before step(): true while another Nibbler announces or the
# shared gap after the last snap runs (no new snap may be locked then).
var snap_blocked := false
var snap_center := Vector3.ZERO
var snap_power := 0
var resolved_power := 0
var provoked := 0.0
var snap_zone: MeshInstance3D
var snap_ring: Node3D
var _provoke_health := MAX_HEALTH


func _ready() -> void:
	_build_shadow()
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	var model: Node3D = NIBBLER_SCENE.instantiate()
	model.name = "Game model"
	body.add_child(model)
	# One material per Nibbler (at most a handful live) so the bite flash stays individual.
	material = ShaderMaterial.new()
	material.shader = CREATURE_SHADER
	material.set_shader_parameter("brightness", 1.2)
	material.set_shader_parameter("saturation", 1.15)
	material.set_shader_parameter("shape_light", 0.35)
	material.set_shader_parameter("rim_color", Color("b4ffe8"))
	material.set_shader_parameter("rim_strength", 0.55)
	material.set_shader_parameter("flash_color", Color("fff6e6"))
	material.set_shader_parameter("flash", 0.0)
	# The mesh node carries a baked rotation; measure its bounds in model space. Head faces +Z.
	var bounds := AABB()
	var first := true
	var inverse := model.global_transform.affine_inverse()
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var local: AABB = (inverse * mesh.global_transform) * mesh.get_aabb()
		bounds = local if first else bounds.merge(local)
		first = false
	model_scale = MODEL_HEIGHT / maxf(bounds.size.y, 0.01)
	var center := bounds.get_center()
	model.scale = Vector3.ONE * model_scale
	model.position = Vector3(-center.x, -bounds.position.y, -center.z) * model_scale

	# Etappe 07: health bar mesh and material are shared by every Nibbler.
	if bar_mesh == null:
		bar_mesh = BoxMesh.new()
		bar_mesh.size = Vector3(0.95, 0.06, 0.1)
		bar_material = StandardMaterial3D.new()
		bar_material.albedo_color = Color("9ef1cf")
		bar_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	health_fill = MeshInstance3D.new()
	health_fill.mesh = bar_mesh
	health_fill.material_override = bar_material
	health_fill.position = Vector3(0, MODEL_HEIGHT + 0.3, 0)
	health_fill.visible = false
	health_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(health_fill)

	# Deterministic start heading and phase per spawn position.
	yaw = fmod(position.x * 1.7 + position.z * 2.3, TAU)
	clock = fmod(absf(position.x * 0.37 + position.z * 0.61), 10.0)
	last_position = position
	last_health = health
	_pose(0.0, 0.0)


func step(delta: float, swarm_position: Vector3, pressure: float = 1.0) -> void:
	resolved_power = 0
	health_fill.visible = health < MAX_HEALTH
	health_fill.scale.x = clampf(health / MAX_HEALTH, 0.001, 1.0)
	wander_phase += delta
	var away := global_position - swarm_position
	away.y = 0.0
	if _step_snap(delta, swarm_position, away.length(), pressure):
		_animate(delta)
		return
	# Etappe 09 – alle greifen an: the Nibbler walks up to the swarm (slower than
	# it, so it can always be outrun) and holds at snapping distance.
	var arena: Node3D = get_parent().get_parent().get_node("Arena")
	var distance := away.length()
	if distance > TUNING.NIBBLER_HOLD_DISTANCE:
		var speed := minf(TUNING.NIBBLER_APPROACH_SPEED_MAX, TUNING.NIBBLER_APPROACH_SPEED + 0.25 * log(maxf(1.0, pressure)) / log(2.0))
		var direction: Vector3 = arena.steer_direction(position, swarm_position, 0.55) if arena.has_method("steer_direction") else -away.normalized()
		position = arena.resolve_motion(position, direction * minf(speed * delta, distance - TUNING.NIBBLER_HOLD_DISTANCE) * slow_factor, 0.55)
	else:
		# Small sidestep while holding, so it does not stand frozen.
		var side := Vector3(-away.z, 0.0, away.x).normalized() if distance > 0.01 else Vector3.RIGHT
		position = arena.resolve_motion(position, side * sin(wander_phase * 1.3) * 0.35 * delta, 0.55)
	_animate(delta)


# Snap state machine. Returns true while the Nibbler stands still to snap.
func _step_snap(delta: float, swarm_position: Vector3, distance: float, pressure: float) -> bool:
	snap_cooldown = maxf(0.0, snap_cooldown - delta)
	if health < _provoke_health - 0.0001:
		provoked = TUNING.NIBBLER_PROVOKED_SECONDS
	_provoke_health = health
	provoked = maxf(0.0, provoked - delta)
	if snap_state == 1:
		snap_remaining -= delta
		var progress := 1.0 - maxf(0.0, snap_remaining) / TUNING.NIBBLER_SNAP_WARNING
		TG.set_progress(snap_zone, progress)
		_pose_snap_ring(progress)
		twitch = maxf(twitch, 0.35)
		# Pulsing white flash: the attacker is visible even when the swarm hides the circle.
		flash = maxf(flash, 0.55 + 0.35 * sin(clock * 30.0))
		if snap_remaining <= 0.0:
			snap_state = 0
			snap_cooldown = TUNING.recovery(TUNING.NIBBLER_SNAP_COOLDOWN, pressure, TUNING.NIBBLER_SNAP_COOLDOWN_MIN)
			snap_zone.visible = false
			resolved_power = snap_power
			flash = 1.0
		return true
	var cornered := distance < TUNING.NIBBLER_SNAP_RANGE
	if snap_blocked or snap_cooldown > 0.0 or distance > TUNING.NIBBLER_SNAP_RANGE + 1.2 or not (cornered or provoked > 0.0):
		return false
	_lock_snap(swarm_position, pressure)
	return true


func _lock_snap(swarm_position: Vector3, pressure: float) -> void:
	var toward := swarm_position - position
	toward.y = 0.0
	var reach := minf(TUNING.NIBBLER_SNAP_REACH, toward.length())
	snap_center = position + (toward.normalized() * reach if toward.length() > 0.01 else Vector3.ZERO)
	snap_center.y = 0.0
	snap_power = int(ceil(minf(1000000.0, TUNING.NIBBLER_SNAP_DAMAGE * pow(maxf(1.0, pressure), 0.6))))
	snap_state = 1
	snap_remaining = TUNING.NIBBLER_SNAP_WARNING
	if toward.length() > 0.01:
		yaw = atan2(toward.x, toward.z)
	_ensure_snap_zone()
	snap_zone.global_position = snap_center + Vector3(0.0, 0.1, 0.0)
	TG.set_armed(snap_zone, true)
	TG.set_progress(snap_zone, 0.0)
	_pose_snap_ring(0.0)
	snap_zone.visible = true


# Locked snap circle (flat), valid from the warning until the hit resolves.
func contains(point: Vector3) -> bool:
	return Vector2(point.x - snap_center.x, point.z - snap_center.z).length() <= TUNING.NIBBLER_SNAP_RADIUS


func hit_fraction(points: PackedVector3Array) -> float:
	if points.is_empty():
		return 0.0
	var inside := 0
	for point in points:
		if contains(point):
			inside += 1
	return float(inside) / float(points.size())


func _ensure_snap_zone() -> void:
	if snap_zone != null:
		return
	snap_zone = TG.build("hunter", TUNING.NIBBLER_SNAP_RADIUS)
	snap_zone.name = "Nibbler snap"
	add_child(snap_zone)
	snap_zone.top_level = true
	snap_zone.visible = false
	if not UI_STYLE.colorblind:
		var shader_material := snap_zone.material_override as ShaderMaterial
		shader_material.set_shader_parameter("fill_color", SNAP_FILL)
		shader_material.set_shader_parameter("pattern_color", SNAP_PATTERN)
		shader_material.set_shader_parameter("edge_color", SNAP_EDGE)
		shader_material.set_shader_parameter("fill_alpha", 0.42)
	_build_snap_ring()


# Outer contour ring (child of the snap zone, so it shows and hides with it): a
# bright band inside a dark hairline, closing in on the circle as the snap nears.
func _build_snap_ring() -> void:
	if snap_ring_mesh == null:
		snap_ring_mesh = TorusMesh.new()
		snap_ring_mesh.inner_radius = 0.9
		snap_ring_mesh.outer_radius = 1.0
		snap_ring_mesh.rings = 40
		snap_ring_mesh.ring_segments = 4
		snap_ring_material = _ring_material(Color("f4fffb", 0.95), 3)
		snap_ring_dark_mesh = TorusMesh.new()
		snap_ring_dark_mesh.inner_radius = 1.0
		snap_ring_dark_mesh.outer_radius = 1.05
		snap_ring_dark_mesh.rings = 40
		snap_ring_dark_mesh.ring_segments = 4
		snap_ring_dark_material = _ring_material(Color(0.02, 0.1, 0.09, 0.8), 2)
	snap_ring = Node3D.new()
	snap_ring.name = "Snap ring"
	snap_zone.add_child(snap_ring)
	snap_ring.position = Vector3(0.0, SNAP_RING_LIFT, 0.0)
	for pair in [[snap_ring_dark_mesh, snap_ring_dark_material], [snap_ring_mesh, snap_ring_material]]:
		var part := MeshInstance3D.new()
		part.mesh = pair[0]
		part.material_override = pair[1]
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		snap_ring.add_child(part)
	_pose_snap_ring(0.0)


static func _ring_material(color: Color, priority: int) -> StandardMaterial3D:
	var ring := StandardMaterial3D.new()
	ring.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.no_depth_test = true
	ring.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.albedo_color = color
	ring.render_priority = priority
	return ring


func _pose_snap_ring(progress: float) -> void:
	if snap_ring == null:
		return
	var eased := 1.0 - (1.0 - progress) * (1.0 - progress)
	var radius := TUNING.NIBBLER_SNAP_RADIUS + lerpf(SNAP_RING_START, SNAP_RING_END, eased)
	snap_ring.scale = Vector3(radius, 0.2, radius)


func _animate(delta: float) -> void:
	if delta <= 0.0:
		return
	clock += delta
	var moved := position - last_position
	moved.y = 0.0
	last_position = position
	# Teleports (spawn, tests) are not motion.
	if moved.length() > 1.0:
		moved = Vector3.ZERO
	var speed := moved.length() / delta
	var run := clampf(speed / FLEE_SPEED, 0.0, 1.0)
	flee_share = lerpf(flee_share, run, 1.0 - exp(-6.0 * delta))
	if speed > 0.03:
		var turn_rate := lerpf(2.5, 11.0, flee_share)
		yaw = lerp_angle(yaw, atan2(moved.x, moved.z), 1.0 - exp(-turn_rate * delta))
	gait += delta * lerpf(2.2, 11.5, flee_share)
	# Bite reaction: pulse while health keeps dropping.
	hit_cooldown -= delta
	if health < last_health - 0.0001 and hit_cooldown <= 0.0:
		flash = 1.0
		twitch = 1.0
		hit_cooldown = 0.32
	last_health = health
	flash = maxf(0.0, flash - delta * 5.0)
	twitch = maxf(0.0, twitch - delta * 4.0)
	material.set_shader_parameter("flash", flash * flash * 0.85)
	var hop := absf(sin(gait)) * lerpf(WANDER_HOP, FLEE_HOP, flee_share)
	_pose(hop, delta)


func _pose(hop: float, _delta: float) -> void:
	var calm := 1.0 - flee_share
	# Standing/wandering: sweep the body to look around; fleeing: lean into the run.
	var look := (sin(clock * 0.9) * 0.55 + sin(clock * 2.3 + 1.1) * 0.15) * calm
	var lean := 0.14 * flee_share + cos(gait * 2.0) * 0.09 * flee_share
	var roll := sin(gait) * lerpf(0.04, 0.1, flee_share) + sin(clock * 47.0) * 0.2 * twitch
	var breath := sin(clock * 2.6) * 0.03 * calm
	var squash := 1.0 + breath - twitch * 0.12
	var stretch := 1.0 / sqrt(maxf(squash, 0.5))
	# Snap wind-up (presentation): rears up, grows and leans back, then lunges.
	var rear := 0.0
	if snap_state == 1:
		rear = 1.0 - maxf(0.0, snap_remaining) / TUNING.NIBBLER_SNAP_WARNING
		lean -= 0.35 * rear
		hop += 0.18 * rear
	var grow := 1.0 + 0.3 * rear
	var pose_basis := Basis.from_euler(Vector3(lean, yaw + look, roll), EULER_ORDER_YXZ)
	body.transform = Transform3D(pose_basis.scaled_local(Vector3(stretch, squash, stretch) * grow), Vector3(0.0, hop, 0.0))
	var shadow_size := 1.15 * (1.0 - hop * 1.3)
	shadow.scale = Vector3(shadow_size, 1.0, shadow_size * 1.25)
	shadow.rotation.y = yaw


func _build_shadow() -> void:
	if shadow_material == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		gradient.colors = PackedColorArray([Color(0, 0, 0, 1), Color(0, 0, 0, 0.6), Color(0, 0, 0, 0)])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.width = 64
		texture.height = 64
		shadow_material = StandardMaterial3D.new()
		shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shadow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		shadow_material.albedo_color = Color(0, 0, 0, 0.45)
		shadow_material.albedo_texture = texture
		shadow_material.render_priority = 1
		shadow_mesh = PlaneMesh.new()
		shadow_mesh.size = Vector2(1.0, 1.0)
	shadow = MeshInstance3D.new()
	shadow.name = "Shadow"
	shadow.mesh = shadow_mesh
	shadow.material_override = shadow_material
	shadow.position.y = SHADOW_Y
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow)
