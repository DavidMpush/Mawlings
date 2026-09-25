extends Node3D

const MAX_HEALTH := 8.0
const FLEE_SPEED := 1.8

var health := MAX_HEALTH
var wander_phase := 0.0


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


func step(delta: float, swarm_position: Vector3) -> void:
	wander_phase += delta
	var away := global_position - swarm_position
	away.y = 0.0
	if away.length() < 4.0 and away.length() > 0.01:
		position += away.normalized() * FLEE_SPEED * delta
	else:
		position += Vector3(sin(wander_phase * 1.3), 0.0, cos(wander_phase * 0.8)) * 0.25 * delta


func _piece(mesh: Mesh, material: Material, location: Vector3, mesh_scale: Vector3) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = location
	part.scale = mesh_scale
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
