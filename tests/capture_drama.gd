extends SceneTree

# Etappe 25: boss entrances (comment + edge vignette + camera pull-back) and a
# few leader shouts in the real run HUD (brawl, 540 x 960). Run WITHOUT --headless:
#   Godot_console.exe --path . --screen 1 --audio-driver Dummy --script res://tests/capture_drama.gd
# Frames: previews/preview_drama_<name>.png and previews/preview_drama_sheet.png.

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const DT := 1.0 / 60.0

var scene: Node
var world: Variant
var swarm: Variant
var drama: Variant
var shots: Array[Image] = []
var names: Array[String] = []


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	UiStyle.set_skin("brawl")
	root.size = Vector2i(540, 960)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	drama = scene.get_node("Drama")
	var controls: Variant = scene.get_node("HUD/Controls")
	if controls.pause_requested.is_connected(world.toggle_pause):
		controls.pause_requested.disconnect(world.toggle_pause)
	world.model.population = 40
	swarm.set_population(40, false)
	world.hunter_clock = 999.0
	await create_timer(0.8).timeout
	# Bog King: spawn right in front of the swarm; the drama node notices it.
	world._spawn_boss(swarm.position + Vector3(0.0, 0.0, -12.0))
	await _shot("bog_king", 0.35)
	_clear_boss()
	for kind: String in ["apex", "apex_sandworm", "apex_toad"]:
		_quiet()
		world.spawn_apex(swarm.position + Vector3(0.0, 0.0, -16.0), kind)
		await _shot(kind, 0.35)
		_clear_boss()
	for event: String in ["milestone", "low_hp", "victory"]:
		_quiet()
		drama._leader_ready_at = -INF
		drama.say("leader", event)
		await _shot("leader_" + event, 0.6)
	_sheet()
	print("Saved drama frames (%d) said=%s" % [shots.size(), str(drama.said)])
	quit()


func _quiet() -> void:
	drama.current = {}
	drama.queue.clear()
	drama.gap = 0.0


func _clear_boss() -> void:
	if world.boss != null:
		world.boss.queue_free()
		world.boss = null
	if world.apex != null:
		world.apex.queue_free()
		world.apex = null
	world.apex_state = 0
	_quiet()


func _shot(label: String, wait: float) -> void:
	await create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://previews/preview_drama_%s.png" % label)
	shots.append(image)
	names.append(label)


func _sheet() -> void:
	var w := 270
	var h := 480
	var columns := 4
	var rows := ceili(float(shots.size()) / columns)
	var sheet := Image.create(w * columns, h * rows, false, Image.FORMAT_RGBA8)
	for index in shots.size():
		var small := shots[index].duplicate() as Image
		small.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(small, Rect2i(0, 0, w, h), Vector2i((index % columns) * w, (index / columns) * h))
	sheet.save_png("res://previews/preview_drama_sheet.png")
