extends Node3D

const MAX_HEALTH := 8.0
const FLEE_SPEED := 1.8
const NIBBLER_SCENE = preload("res://assets/gameplay/characters/Nibbler_game.glb")
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


func step(delta: float, swarm_position: Vector3) -> void:
	health_fill.visible = health < MAX_HEALTH
	health_fill.scale.x = clampf(health / MAX_HEALTH, 0.001, 1.0)
	wander_phase += delta
	var away := global_position - swarm_position
	away.y = 0.0
	if away.length() < 4.0 and away.length() > 0.01:
		position = get_parent().get_parent().get_node("Arena").resolve_motion(position, away.normalized() * FLEE_SPEED * slow_factor * delta, 0.55)
	else:
		position = get_parent().get_parent().get_node("Arena").resolve_motion(position, Vector3(sin(wander_phase * 1.3), 0.0, cos(wander_phase * 0.8)) * 0.25 * delta, 0.55)
	_animate(delta)


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
	var pose_basis := Basis.from_euler(Vector3(lean, yaw + look, roll), EULER_ORDER_YXZ)
	body.transform = Transform3D(pose_basis.scaled_local(Vector3(stretch, squash, stretch)), Vector3(0.0, hop, 0.0))
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
