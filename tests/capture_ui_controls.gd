extends SceneTree

# Preview for the stage-04 CONTROLS component (Rally button, joystick, hint
# banner) inside the real game. Run without --headless:
#   Godot_console.exe --path . --script res://tests/capture_ui_controls.gd
# Frames: rest, Rally held + moving up-right, warning hint.

var scene: Node
var world: Variant
var controls: Variant


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	world = scene.get_node("HuntWorld")
	controls = scene.get_node("HUD/Controls")
	# Background capture windows lose focus; the auto-pause must not end up in the frames.
	controls.pause_requested.disconnect(world.toggle_pause)
	controls.legacy["controls"] = false
	var component: Control = load("res://scripts/ui/hud_controls.gd").new()
	component.name = "HudControls"
	controls.add_child(component)
	await create_timer(0.6).timeout
	await _save("preview_ui_controls_rest.png")

	controls.rally_pressed = true
	controls.movement_vector = Vector2(0.72, -0.62)
	Input.action_press("move_right")
	Input.action_press("move_up")
	await create_timer(0.5).timeout
	await _save("preview_ui_controls_active.png")
	Input.action_release("move_right")
	Input.action_release("move_up")
	controls.rally_pressed = false
	controls.movement_vector = Vector2.ZERO

	# The world rewrites the hint every frame; freeze it for the warning frame.
	world.set_process(false)
	controls.hint = "RAUS AUS DEM ROTEN RING!"
	await create_timer(0.25).timeout
	await _save("preview_ui_controls_warn.png")
	controls.hint = "Alpha-Kern gelagert · wartet auf eine Evolution"
	await create_timer(0.1).timeout
	await _save("preview_ui_controls_hint.png")
	print("Saved UI controls preview frames")
	quit()


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + file_name)
