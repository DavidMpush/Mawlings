extends Node3D

const START_POPULATION := 25
const MOVE_SPEED := 7.0
const FOLLOW_SPEED := 7.0
const GOLDEN_ANGLE := 2.39996323
const VISUAL_LIMIT := 120

var movement_vector := Vector2.ZERO
var rally_pressed := false
var units: Array[Node3D] = []
var population := START_POPULATION
var body_material: Material
var head_material: Material
var jaw_material: Material


func _ready() -> void:
	body_material = _material(Color("a92c1a"))
	head_material = _material(Color("f26927"))
	jaw_material = _material(Color("451b20"))
	set_population(START_POPULATION)
	for index in units.size():
		var angle := float(index) * GOLDEN_ANGLE
		var radius := sqrt((float(index) + 0.5) / float(units.size())) * 1.75
		units[index].position = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


func set_population(value: int) -> void:
	population = maxi(0, value)
	var target := mini(population, VISUAL_LIMIT)
	while units.size() < target:
		var index := units.size()
		var unit := _make_unit(body_material, head_material, jaw_material)
		unit.rotation.y = float(index) * GOLDEN_ANGLE
		add_child(unit)
		units.append(unit)
	while units.size() > target:
		units.pop_back().queue_free()


func set_controls(direction: Vector2, rally: bool) -> void:
	movement_vector = direction.limit_length(1.0)
	rally_pressed = rally


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	position += Vector3(movement_vector.x, 0.0, movement_vector.y) * MOVE_SPEED * delta
	var flow_radius := 2.15 + maxf(0.0, sqrt(float(population) / 25.0) - 1.0) * 0.45
	var radius := flow_radius * 0.42 if rally_pressed else flow_radius
	var response := 1.0 - exp(-FOLLOW_SPEED * delta)
	for index in units.size():
		var angle := float(index) * GOLDEN_ANGLE
		var fraction := sqrt((float(index) + 0.5) / float(units.size()))
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
