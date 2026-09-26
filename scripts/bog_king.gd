extends Node3D

const TUNING = preload("res://scripts/tuning.gd")
const MODEL = preload("res://assets/gameplay/characters/BogKing_game.glb")

enum State { ARRIVING, CHASE, WARNING, RECOVERY }

var state := State.ARRIVING
var remaining := 1.4
var health := TUNING.BOSS_HEALTH
var max_health := TUNING.BOSS_HEALTH
var attack_center := Vector3.ZERO
var attack_power := 0
var hit_flash := 0.0
var model: Node3D
var warning: Node3D
var danger_material: StandardMaterial3D
var health_fill: MeshInstance3D


func _ready() -> void:
	model = MODEL.instantiate()
	model.name = "Bog King game model"
	model.scale = Vector3.ONE * 7.0
	add_child(model)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.roughness = 0.88
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bar_back := BoxMesh.new()
	bar_back.size = Vector3(4.2, 0.16, 0.24)
	_part(self, bar_back, _material(Color("243025")), Vector3(0, 4.25, 0))
	var bar := BoxMesh.new()
	bar.size = Vector3(4.0, 0.12, 0.27)
	health_fill = _part(self, bar, _material(Color("f5b966"), true), Vector3(0, 4.25, 0.01))
	warning = Node3D.new()
	warning.name = "Bog King stomp warning"
	add_child(warning)
	warning.top_level = true
	var disc := CylinderMesh.new()
	disc.top_radius = TUNING.BOSS_ATTACK_RADIUS
	disc.bottom_radius = TUNING.BOSS_ATTACK_RADIUS
	disc.height = 0.025
	danger_material = _material(Color(1.0, 0.25, 0.12, 0.27), true)
	danger_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_part(warning, disc, danger_material, Vector3(0, 0.11, 0))
	var ring := TorusMesh.new()
	ring.inner_radius = TUNING.BOSS_ATTACK_RADIUS - 0.15
	ring.outer_radius = TUNING.BOSS_ATTACK_RADIUS
	ring.rings = 48
	ring.ring_segments = 8
	_part(warning, ring, _material(Color("ff7250"), true), Vector3(0, 0.15, 0))
	warning.visible = false
	warning.global_position = global_position


func take_damage(amount: float) -> void:
	health -= amount
	hit_flash = 0.12


func step(delta: float, swarm_position: Vector3, pressure: float) -> int:
	hit_flash = maxf(0.0, hit_flash - delta)
	model.scale = Vector3.ONE * (7.25 if hit_flash > 0.0 else 7.0)
	health_fill.scale.x = clampf(health / max_health, 0.0, 1.0)
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
	if state == State.WARNING:
		warning.scale = Vector3.ONE * (0.96 + 0.04 * sin(remaining * 13.0))
	if remaining > 0.0:
		return 0
	if state == State.ARRIVING:
		state = State.CHASE
	elif state == State.WARNING:
		state = State.RECOVERY
		remaining = TUNING.BOSS_RECOVERY_SECONDS
		warning.visible = false
		if swarm_position.distance_to(attack_center) <= TUNING.BOSS_ATTACK_RADIUS:
			return attack_power
	elif state == State.RECOVERY:
		state = State.CHASE
	return 0


func _material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var value := StandardMaterial3D.new()
	value.albedo_color = color
	value.roughness = 0.8
	if unshaded:
		value.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return value


func _part(parent: Node3D, mesh: Mesh, material: Material, location: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = location
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part
