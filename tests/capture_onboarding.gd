extends SceneTree

# Preview for the Einstieg tips (stage 06) inside the real game. Run without --headless:
#   Godot_console.exe --path . --script res://tests/capture_onboarding.gd
# Frames: movement tip (pointer to the joystick), Rally tip with a hunter close
# by (pointer to Rally, warning banner below), corpse tip.

const TEST_PROFILE := "user://capture_onboarding_profile.json"

var scene: Node
var world: Variant
var controls: Variant
var tips: Node


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	_delete(TEST_PROFILE)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	world = scene.get_node("HuntWorld")
	controls = scene.get_node("HUD/Controls")
	# Background capture windows lose focus; the auto-pause must not end up in the frames.
	controls.pause_requested.disconnect(world.toggle_pause)
	tips = load("res://scripts/onboarding.gd").new()
	tips.name = "Onboarding"
	scene.add_child(tips)
	tips.setup(world, controls, scene.get_node("Swarm"), TEST_PROFILE)
	# First tip appears after the start delay, then fades in.
	await create_timer(tips.FIRST_DELAY + 0.9).timeout
	await _save("preview_onboarding_move.png")

	tips._hide()
	await create_timer(0.5).timeout
	var swarm: Node3D = scene.get_node("Swarm")
	world._spawn_hunter(swarm.position + Vector3(-4.0, 0.0, -2.0))
	await create_timer(0.3).timeout
	tips._show("rally")
	await create_timer(1.1).timeout
	await _save("preview_onboarding_rally.png")

	tips._hide()
	await create_timer(0.5).timeout
	tips._show("corpse")
	await create_timer(0.9).timeout
	await _save("preview_onboarding_corpse.png")
	_delete(TEST_PROFILE)
	print("Saved onboarding preview frames")
	quit()


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/" + file_name)


func _delete(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
