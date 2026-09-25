extends Node3D

const START_POPULATION := 25
const MOVE_SPEED := 7.0
const FOLLOW_SPEED := 7.0
const GOLDEN_ANGLE := 2.39996323

var movement_vector := Vector2.ZERO
var rally_pressed := false
var units: Array[Node3D] = []


func _ready() -> void:
	var body_material := _material(Color("a92c1a"))
	var head_material := _material(Color("f26927"))
	var jaw_material := _material(Color("451b20"))
	for index in START_POPULATION:
		var unit := _make_unit(body_material, head_material, jaw_material)
		var angle := float(index) * GOLDEN_ANGLE
		var radius := sqrt((float(index) + 0.5) / float(START_POPULATION)) * 1.75
		unit.position = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		unit.rotation.y = angle
		add_child(unit)
		units.append(unit)


func set_controls(direction: Vector2, rally: bool) -> void:
	movement_vector = direction.limit_length(1.0)
	rally_pressed = rally


func _process(delta: float) -> void:
	position += Vector3(movement_vector.x, 0.0, movement_vector.y) * MOVE_SPEED * delta
	var radius := 0.85 if rally_pressed else 2.15
	var response := 1.0 - exp(-FOLLOW_SPEED * delta)
	for index in units.size():
		var angle := float(index) * GOLDEN_ANGLE
		var fraction := sqrt((float(index) + 0.5) / float(START_POPULATION))
		var drift := 0.07 * sin(Time.get_ticks_msec() * 0.002 + float(index))
		var goal := Vector3(cos(angle) * fraction * radius, drift, sin(angle) * fraction * radius)
		units[index].position = units[index].position.lerp(goal, response)
		if movement_vector.length_squared() > 0.01:
			units[index].rotation.y = lerp_angle(units[index].rotation.y,
				atan2(movement_vector.x, movement_vector.y), response)


func _make_unit(body: Material, head: Material, jaw: Material) -> Node3D:
	var unit := Node3D.new()
	unit.name = "Mawling"
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.26
	body_mesh.height = 0.48
	_piece(unit, body_mesh, body, Vector3(0.0, 0.22, -0.12), Vector3(0.85, 0.65, 1.0))
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.29
	head_mesh.height = 0.52
	_piece(unit, head_mesh, head, Vector3(0.0, 0.25, 0.19), Vector3(1.08, 0.72, 0.9))
	var jaw_mesh := BoxMesh.new()
	jaw_mesh.size = Vector3(0.48, 0.08, 0.20)
	_piece(unit, jaw_mesh, jaw, Vector3(0.0, 0.12, 0.40), Vector3.ONE)
	return unit


func _piece(parent: Node3D, mesh: Mesh, material: Material, location: Vector3, mesh_scale: Vector3) -> void:
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.material_override = material
	piece.position = location
	piece.scale = mesh_scale
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(piece)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material
