extends Node3D

const MAWLING_SCENE = preload("res://assets/gameplay/characters/Mawling_game.glb")

const START_POPULATION := 25
const MOVE_SPEED := 7.0
const FOLLOW_SPEED := 7.0
const GOLDEN_ANGLE := 2.39996323
const VISUAL_LIMIT := 120

var movement_vector := Vector2.ZERO
var rally_pressed := false
var units: Array[Node3D] = []
var population := START_POPULATION
var game_material: StandardMaterial3D


func _ready() -> void:
	game_material = StandardMaterial3D.new()
	game_material.vertex_color_use_as_albedo = true
	game_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	game_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	set_population(START_POPULATION)
	for index in units.size():
		var angle := float(index) * GOLDEN_ANGLE
		var radius := sqrt((float(index) + 0.5) / float(units.size())) * 2.65
		units[index].position = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


func set_population(value: int) -> void:
	population = maxi(0, value)
	var target := mini(population, VISUAL_LIMIT)
	while units.size() < target:
		var index := units.size()
		var unit := _make_unit()
		unit.rotation.y = float(index) * GOLDEN_ANGLE
		add_child(unit)
		units.append(unit)
	while units.size() > target:
		units.pop_back().queue_free()
	var display_scale := lerpf(0.91, 0.58, clampf(float(population - 25) / 225.0, 0.0, 1.0))
	for unit in units:
		unit.scale = Vector3.ONE * display_scale


func set_controls(direction: Vector2, rally: bool) -> void:
	movement_vector = direction.limit_length(1.0)
	rally_pressed = rally


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	var motion := Vector3(movement_vector.x, 0.0, movement_vector.y) * MOVE_SPEED * delta
	position = get_parent().get_node("Arena").resolve_motion(position, motion, 0.75)
	var flow_radius := 2.65 + maxf(0.0, sqrt(float(population) / 25.0) - 1.0) * 0.55
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
				atan2(movement_vector.x, movement_vector.y) + PI * 0.5, response)


func _make_unit() -> Node3D:
	var unit := Node3D.new()
	unit.name = "Mawling"
	var model: Node3D = MAWLING_SCENE.instantiate()
	model.name = "Game model"
	model.scale = Vector3.ONE
	unit.add_child(model)
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = game_material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return unit
