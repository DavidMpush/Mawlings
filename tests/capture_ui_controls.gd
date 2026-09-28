extends SceneTree

# Preview of the CONTROLS component (Rally button, joystick, hint banner,
# onboarding tip) inside the real game. Run WITHOUT --headless:
#   Godot_console.exe --path . --screen 1 --audio-driver Dummy --script res://tests/capture_ui_controls.gd
# Frames (900 x 1600 and the real 540 x 960 downscale as *_540.png):
#   preview_ui_controls_rest.png    at rest
#   preview_ui_controls_active.png  Rally held + joystick pushed up-right
#   preview_ui_controls_warn.png    danger banner "RAUS AUS DEM ROTEN RING!"
#   preview_ui_controls_hint.png    neutral hint (longest world hint)
#   preview_ui_controls_tip.png     onboarding tip pointing at Rally
#   preview_ui_controls_tip_long.png  longest tip (three lines) + movement pointer

const UiStyle := preload("res://scripts/ui/ui_style.gd")

var scene: Node
var world: Variant
var controls: Variant


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var skin := OS.get_environment("MAWLINGS_SKIN")
	UiStyle.set_skin(skin if skin != "" else "brawl")
	root.size = Vector2i(900, 1600)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	world = scene.get_node("HuntWorld")
	controls = scene.get_node("HUD/Controls")
	# Background capture windows lose focus; the auto-pause must not end up in the frames.
	if controls.pause_requested.is_connected(world.toggle_pause):
		controls.pause_requested.disconnect(world.toggle_pause)
	# While another component is half edited (parse error) the HUD stops adding
	# components after it; add this one directly so the frames stay usable.
	if controls.get_node_or_null("hud_controls") == null:
		push_warning("capture_ui_controls: hud_controls missing from the HUD, adding it directly")
		for key in controls.legacy:
			controls.legacy[key] = false
		var component: Control = load("res://scripts/ui/hud_controls.gd").new()
		component.name = "hud_controls"
		controls.add_child(component)
	# No onboarding tips of their own (a fresh profile would show "move").
	var tips := scene.find_child("Onboarding", true, false)
	if tips != null:
		tips.set_process(false)
	await create_timer(0.8).timeout
	for size in [Vector2i(900, 1600), Vector2i(540, 960)]:
		root.size = size
		var suffix := "" if size.x == 900 else "_540"
		await create_timer(0.3).timeout
		await _frames(suffix)
	print("Saved UI controls preview frames")
	quit()


func _frames(suffix: String) -> void:
	world.set_process(true)
	_tip("", "")
	await create_timer(0.3).timeout
	# The world rewrites the hint every frame; freeze it for the fixed frames.
	world.set_process(false)
	controls.hint = ""
	await create_timer(0.3).timeout
	await _save("preview_ui_controls_rest%s.png" % suffix)

	controls.rally_pressed = true
	controls.movement_vector = Vector2(0.72, -0.62)
	await create_timer(0.35).timeout
	await _save("preview_ui_controls_active%s.png" % suffix)
	controls.rally_pressed = false
	controls.movement_vector = Vector2.ZERO

	controls.hint = "RAUS AUS DEM ROTEN RING!"
	await create_timer(0.3).timeout
	await _save("preview_ui_controls_warn%s.png" % suffix)
	controls.hint = "Alpha-Kern gelagert · wartet auf eine Evolution"
	await create_timer(0.3).timeout
	await _save("preview_ui_controls_hint%s.png" % suffix)
	controls.hint = ""

	_tip("Halte links RALLY: dichter Schwarm, stärkerer Biss", "rally")
	await create_timer(0.9).timeout
	await _save("preview_ui_controls_tip%s.png" % suffix)
	_tip("", "")
	await create_timer(0.6).timeout
	_tip("Der Bog King! Weiche dem Stampfen aus und beiß zu, wenn er erschöpft ist", "boss")
	await create_timer(0.9).timeout
	await _save("preview_ui_controls_tip_long%s.png" % suffix)
	_tip("", "")
	await create_timer(0.6).timeout
	_tip("Ziehe rechts, um den Schwarm zu führen", "move")
	controls.hint = "RAUS AUS DER SPRUNGZONE!"
	await create_timer(0.9).timeout
	await _save("preview_ui_controls_tip_move%s.png" % suffix)
	_tip("", "")
	controls.hint = ""
	await create_timer(0.6).timeout


func _tip(text: String, icon: String) -> void:
	for pair in [["tutorial_tip", text], ["tutorial_icon", icon]]:
		if pair[0] in controls:
			controls.set(pair[0], pair[1])
		else:
			controls.set_meta(pair[0], pair[1])


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/" + file_name)
