extends Node3D

@onready var swarm: Node3D = $Swarm
@onready var camera: Camera3D = $Camera3D
@onready var controls: Control = $HUD/Controls

const CAMERA_OFFSET := Vector3(0.0, 23.0, 15.0)


func _ready() -> void:
	_register_keyboard_input()
	_build_open_arena()
	camera.position = swarm.position + CAMERA_OFFSET
	camera.look_at(swarm.position, Vector3.UP)
	DisplayServer.window_set_title("MAWLINGS — Godot Prototype")


func _process(delta: float) -> void:
	var keyboard := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var movement: Vector2 = controls.movement_vector if controls.movement_vector.length() > 0.05 else keyboard
	swarm.set_controls(movement, controls.rally_pressed or Input.is_key_pressed(KEY_SPACE))
	var target := swarm.position + CAMERA_OFFSET
	camera.position = camera.position.lerp(target, 1.0 - exp(-5.0 * delta))
	camera.look_at(swarm.position, Vector3.UP)


func _register_keyboard_input() -> void:
	var bindings := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN]
	}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key_code in bindings[action]:
			var key := InputEventKey.new()
			key.physical_keycode = key_code
			InputMap.action_add_event(action, key)


func _build_open_arena() -> void:
	var ground_material := _material(Color("73845a"))
	var stone_material := _material(Color("a0a38d"))
	var leaf_material := _material(Color("3f8d4f"))
	var water_material := _material(Color("328d9a"))
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(180.0, 180.0)
	_part("Open ground", floor_mesh, ground_material, Vector3.ZERO, Vector3.ONE)
	_island(Vector3(-9.0, 0.0, -11.0), true, stone_material, leaf_material, water_material)
	_island(Vector3(9.0, 0.0, -11.0), false, stone_material, leaf_material, water_material)
	_island(Vector3(-9.0, 0.0, 11.0), false, stone_material, leaf_material, water_material)
	_island(Vector3(9.0, 0.0, 11.0), true, stone_material, leaf_material, water_material)


func _island(origin: Vector3, pool: bool, stone: Material, leaf: Material, water: Material) -> void:
	if pool:
		var puddle := CylinderMesh.new()
		puddle.top_radius = 1.0
		puddle.bottom_radius = 1.0
		puddle.height = 0.025
		_part("Shallow pool", puddle, water, origin + Vector3(0.0, 0.02, 0.0), Vector3(2.5, 1.0, 1.8))
		for offset in [Vector3(-0.8, 0.06, 0.3), Vector3(0.8, 0.06, -0.4)]:
			var pad := CylinderMesh.new()
			pad.top_radius = 0.34
			pad.bottom_radius = 0.34
			pad.height = 0.025
			_part("Lily pad", pad, leaf, origin + offset, Vector3.ONE)
	else:
		for offset in [Vector3(-1.1, 0.23, 0.0), Vector3(0.65, 0.28, 0.65), Vector3(1.2, 0.18, -0.7)]:
			var rock := SphereMesh.new()
			rock.radius = 0.7
			rock.height = 1.4
			_part("Low stone", rock, stone, origin + offset, Vector3(1.25, 0.42, 0.9))


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	return material


func _part(label: String, mesh: Mesh, material: Material, location: Vector3, mesh_scale: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.material_override = material
	instance.position = location
	instance.scale = mesh_scale
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
