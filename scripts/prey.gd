extends Node3D

const MAX_HEALTH := 8.0
const FLEE_SPEED := 1.8

var health := MAX_HEALTH
var wander_phase := 0.0
var health_fill: MeshInstance3D


func _ready() -> void:
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color("43d5bc")
	shell.roughness = 0.8
	var eye := StandardMaterial3D.new()
	eye.albedo_color = Color("142f39")
	var body := SphereMesh.new()
	body.radius = 0.52
	body.height = 0.9
	_piece(body, shell, Vector3(0.0, 0.48, 0.0), Vector3.ONE)
	var spot := SphereMesh.new()
	spot.radius = 0.09
	spot.height = 0.16
	_piece(spot, eye, Vector3(-0.25, 0.68, 0.34), Vector3.ONE)
	_piece(spot, eye, Vector3(0.25, 0.68, 0.34), Vector3.ONE)
	var shell_back := StandardMaterial3D.new()
	shell_back.albedo_color = Color("278e80")
	var cap := SphereMesh.new()
	cap.radius = 0.45
	cap.height = 0.18
	_piece(cap, shell_back, Vector3(0, 0.80, -0.10), Vector3.ONE)
	var fin := SphereMesh.new()
	fin.radius = 0.35
	fin.height = 0.12
	for side in [-1.0, 1.0]:
		var leaf := _piece(fin, shell, Vector3(side * 0.46, 0.45, -0.27), Vector3(0.72, 1, 1.25))
		leaf.rotation.y = side * 0.5
	var bar := BoxMesh.new()
	bar.size = Vector3(0.95, 0.06, 0.1)
	var fill := StandardMaterial3D.new()
	fill.albedo_color = Color("9ef1cf")
	fill.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	health_fill = MeshInstance3D.new()
	health_fill.mesh = bar
	health_fill.material_override = fill
	health_fill.position = Vector3(0, 1.05, 0)
	add_child(health_fill)


func step(delta: float, swarm_position: Vector3) -> void:
	health_fill.visible = health < MAX_HEALTH
	health_fill.scale.x = clampf(health / MAX_HEALTH, 0.001, 1.0)
	wander_phase += delta
	var away := global_position - swarm_position
	away.y = 0.0
	if away.length() < 4.0 and away.length() > 0.01:
		position = get_parent().get_parent().get_node("Arena").resolve_motion(position, away.normalized() * FLEE_SPEED * delta, 0.55)
	else:
		position = get_parent().get_parent().get_node("Arena").resolve_motion(position, Vector3(sin(wander_phase * 1.3), 0.0, cos(wander_phase * 0.8)) * 0.25 * delta, 0.55)


func _piece(mesh: Mesh, material: Material, location: Vector3, mesh_scale: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = location
	part.scale = mesh_scale
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
	return part
