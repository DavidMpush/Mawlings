extends Node3D

@onready var swarm: Node3D = $Swarm
@onready var camera: Camera3D = $Camera3D
@onready var controls: Control = $HUD/Controls
@onready var world: Node3D = $HuntWorld
@onready var arena: Node3D = $Arena

const CAMERA_OFFSET := Vector3(0.0, 23.0, 15.0)


func _ready() -> void:
	_register_keyboard_input()
	controls.restart_requested.connect(_restart)
	controls.pause_requested.connect(world.toggle_pause)
	controls.mutation_chosen.connect(world.choose_mutation)
	camera.position = swarm.position + CAMERA_OFFSET
	camera.look_at(swarm.position, Vector3.UP)
	DisplayServer.window_set_title("MAWLINGS — Godot Prototype")


func _process(delta: float) -> void:
	var keyboard := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var movement: Vector2 = controls.movement_vector if controls.movement_vector.length() > 0.05 else keyboard
	var active: bool = not world.paused and not world.model.extinct and not world.choosing()
	swarm.set_controls(movement if active else Vector2.ZERO, active and (controls.rally_pressed or Input.is_key_pressed(KEY_SPACE)))
	arena.sync(swarm.position)
	var target := swarm.position + CAMERA_OFFSET
	camera.position = camera.position.lerp(target, 1.0 - exp(-5.0 * delta))
	camera.look_at(swarm.position, Vector3.UP)


func _restart() -> void:
	world.reset_run()
	camera.position = swarm.position + CAMERA_OFFSET
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
