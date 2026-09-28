extends SceneTree

# Etappe 24: the onboarding tips of the new systems in the real run HUD (brawl).
# Run WITHOUT --headless:
#   Godot_console.exe --path . --screen 1 --audio-driver Dummy --script res://tests/capture_onboarding_tips.gd
# Frames (540 x 960, the real phone downscale): previews/preview_tip_<id>.png
# and previews/preview_tips_sheet.png (all tips side by side).

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const ONBOARDING := preload("res://scripts/onboarding.gd")
const IDS := ["amber", "cocoon", "boss_cocoon", "powerup", "shrine", "xp", "leader_low", "explore", "sandstorm", "ability"]

var scene: Node
var world: Variant
var controls: Variant
var shots: Array[Image] = []


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	UiStyle.set_skin("brawl")
	root.size = Vector2i(540, 960)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	world = scene.get_node("HuntWorld")
	controls = scene.get_node("HUD/Controls")
	if controls.pause_requested.is_connected(world.toggle_pause):
		controls.pause_requested.disconnect(world.toggle_pause)
	var tips := scene.find_child("Onboarding", true, false)
	if tips != null:
		tips.set_process(false)
	await create_timer(0.8).timeout
	world.set_process(false)
	controls.hint = ""
	for id: String in IDS:
		_tip(ONBOARDING.TIPS[id], id)
		await create_timer(0.9).timeout
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.save_png("res://previews/preview_tip_%s.png" % id)
		shots.append(image)
		_tip("", "")
		await create_timer(0.5).timeout
	_sheet()
	print("Saved onboarding tip frames (%d)" % shots.size())
	quit()


func _tip(text: String, icon: String) -> void:
	for pair in [["tutorial_tip", text], ["tutorial_icon", icon]]:
		if pair[0] in controls:
			controls.set(pair[0], pair[1])
		else:
			controls.set_meta(pair[0], pair[1])


# Lower half of every frame (tip + controls), five per row.
func _sheet() -> void:
	var w := 270
	var h := 240
	var columns := 5
	var rows := ceili(float(shots.size()) / columns)
	var sheet := Image.create(w * columns, h * rows, false, Image.FORMAT_RGBA8)
	for index in shots.size():
		var crop := shots[index].get_region(Rect2i(0, 480, 540, 480))
		crop.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(crop, Rect2i(0, 0, w, h), Vector2i((index % columns) * w, (index / columns) * h))
	sheet.save_png("res://previews/preview_tips_sheet.png")
