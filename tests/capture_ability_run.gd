extends SceneTree

# Stage 17d: every tribe ability in a real run (HuntWorld steps, the swarm
# moves, hunters close in). Run WITHOUT --headless:
#   Godot --screen 1 --audio-driver Dummy --path . --script res://tests/capture_ability_run.gd
#   preview_ability_run_<id>.png, preview_ability_run_sheet.png

const CAMERA_OFFSET := Vector3(0.0, 23.0, 15.0)
const DT := 1.0 / 60.0
const STRAINS := ["glutmaw", "sporling", "knochenkiefer", "flinkzahn", "aetzmaul", "nachtmaul"]
# Seconds after the button press for the picture.
const WAIT := {"glutsprung": 0.18, "sporenbombe": 0.8, "panzerstoss": 0.15, "hetzjagd": 1.0, "saeureschwall": 0.25, "schattenschleier": 0.6}

var scene: Node
var world: Variant
var swarm: Variant
var arena: Variant
var camera: Camera3D
var shots: Array[Image] = []


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	arena = scene.get_node("Arena")
	camera = scene.get_node("Camera3D")
	var hud: Variant = scene.get_node("HUD/Controls")
	for connection in hud.pause_requested.get_connections():
		connection.signal.disconnect(connection.callable)
	scene.set_process(false)
	world.set_process(false)
	for strain in STRAINS:
		await _shot(strain)
	_sheet()
	print("Saved ability run frames (%d)" % shots.size())
	quit()


func _shot(strain: String) -> void:
	world.config = {"strain_id": strain}
	world.reset_run()
	world.set_process(false)
	world.model.population = 50
	swarm.set_population(50, false)
	world.model.elapsed = 60.0
	for clock in ["hunter_clock", "skitter_clock", "leaper_clock", "elite_clock", "nest_clock", "boss_clock"]:
		world.set(clock, 9999.0)
	world.flood_start = 100000.0
	world.model.leader_invulnerable = 99.0
	for offset in [Vector3(-3, 0, -6), Vector3(3, 0, -7), Vector3(6, 0, 1), Vector3(-6, 0, 2), Vector3(0, 0, 6)]:
		world._spawn_hunter(swarm.position + offset)
	await _run(1.0, Vector2.ZERO)
	var move := Vector2(0, -1) if strain != "flinkzahn" else Vector2(0.6, -0.8)
	swarm.movement_vector = move
	world.request_ability()
	await _run(float(WAIT[world.abilities.ability_id]), move)
	var id: String = world.abilities.ability_id
	world._update_hud(world.abilities.definition().text)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://preview_ability_run_%s.png" % id)
	shots.append(image)
	swarm.movement_vector = Vector2.ZERO


func _run(seconds: float, move: Vector2) -> void:
	for frame in int(round(seconds / DT)):
		swarm.movement_vector = move
		world.step(DT)
		world.model.leader_invulnerable = 99.0
		arena.sync(swarm.position)
		camera.position = swarm.position + CAMERA_OFFSET
		camera.look_at(swarm.position, Vector3.UP)
		await process_frame


func _sheet() -> void:
	var w := 270
	var h := 480
	var sheet := Image.create(w * 3, h * 2, false, Image.FORMAT_RGBA8)
	for index in shots.size():
		var small := shots[index].duplicate() as Image
		small.convert(Image.FORMAT_RGBA8)
		small.resize(w, h)
		sheet.blit_rect(small, Rect2i(0, 0, w, h), Vector2i((index % 3) * w, (index / 3) * h))
	sheet.save_png("res://preview_ability_run_sheet.png")
