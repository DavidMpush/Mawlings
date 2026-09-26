extends Node3D

@onready var swarm: Node3D = $Swarm
@onready var camera: Camera3D = $Camera3D
@onready var controls: Control = $HUD/Controls
@onready var world: Node3D = $HuntWorld
@onready var arena: Node3D = $Arena

const CAMERA_OFFSET := Vector3(0.0, 23.0, 15.0)

var shake := 0.0
var zoom := 1.0
var camera_base := Vector3.ZERO


func _ready() -> void:
	_register_keyboard_input()
	controls.restart_requested.connect(_restart)
	controls.pause_requested.connect(world.toggle_pause)
	controls.mutation_chosen.connect(world.choose_mutation)
	_snap_camera()
	DisplayServer.window_set_title("MAWLINGS — Godot Prototype")


# Purely visual camera kick; stacks but saturates so big hits stay readable.
func add_shake(amount: float) -> void:
	shake = minf(1.0, shake + amount)


func _process(delta: float) -> void:
	var keyboard := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var movement: Vector2 = controls.movement_vector if controls.movement_vector.length() > 0.05 else keyboard
	var active: bool = not world.paused and not world.model.extinct and not world.choosing()
	swarm.frozen = not active
	swarm.set_controls(movement if active else Vector2.ZERO, active and (controls.rally_pressed or Input.is_key_pressed(KEY_SPACE)))
	arena.sync(swarm.position)
	# Pull back for a large swarm and a nearby boss so both fit the portrait frame.
	var wanted := 1.0 + clampf(float(swarm.population - 25) / 225.0, 0.0, 1.0) * 0.12
	if world.boss != null and world.boss.position.distance_to(swarm.position) < 16.0:
		wanted += 0.14
	zoom = lerpf(zoom, wanted, 1.0 - exp(-1.5 * delta))
	camera_base = camera_base.lerp(swarm.position + CAMERA_OFFSET * zoom, 1.0 - exp(-5.0 * delta))
	shake = maxf(0.0, shake - delta * 2.4)
	var jitter := Vector3(randf_range(-1.0, 1.0), randf_range(-0.4, 0.4), randf_range(-1.0, 1.0)) * shake * shake * 0.8
	camera.position = camera_base + jitter
	camera.look_at(swarm.position + jitter * 0.5, Vector3.UP)


func _restart() -> void:
	world.reset_run()
	shake = 0.0
	_snap_camera()


func _snap_camera() -> void:
	zoom = 1.0
	camera_base = swarm.position + CAMERA_OFFSET
	camera.position = camera_base
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
