extends SceneTree

# Stage 17d review frames: every tribe ability mid-effect from the game camera,
# plus the ability button (ready / cooling / active). Run WITHOUT --headless:
#   Godot --screen 1 --audio-driver Dummy --path . --script res://tests/capture_abilities.gd
#   preview_ability_<id>.png  (six abilities)
#   preview_ability_button_ready.png / _cooldown.png
#   preview_ability_sheet.png (overview)
# The abilities are not wired into HuntWorld yet: a small adapter drives them.

const ABILITIES = preload("res://scripts/abilities.gd")
const CAMERA_OFFSET := Vector3(0.0, 23.0, 15.0)
const DT := 1.0 / 60.0
const STRAINS := ["glutmaw", "sporling", "knochenkiefer", "flinkzahn", "aetzmaul", "nachtmaul"]

var scene: Node
var world: Variant
var swarm: Variant
var arena: Variant
var camera: Camera3D
var hud: Variant
var shots: Array[Image] = []


class Adapter extends Node3D:
	var world: Variant
	var swarm: Variant
	var arena: Variant
	var enemies: Array = []
	func ability_swarm_position() -> Vector3:
		return swarm.position
	func ability_set_swarm_position(point: Vector3) -> void:
		swarm.position = point
	func ability_targets() -> Array:
		return enemies.filter(func(e): return is_instance_valid(e) and float(e.health) > 0.0)
	func ability_brood() -> Node3D:
		return world.horde
	func ability_arena() -> Node3D:
		return arena
	func ability_damage_scale() -> float:
		return 1.0


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
	hud = scene.get_node("HUD/Controls")
	for connection in hud.pause_requested.get_connections():
		connection.signal.disconnect(connection.callable)
	scene.set_process(false)
	world.set_process(false)
	for target in world.prey:
		target.queue_free()
	world.prey.clear()
	world.model.population = 45
	swarm.set_population(45, false)
	swarm.position = Vector3(0, 0, 30)
	await _settle(60)
	for strain in STRAINS:
		await _ability(strain)
	_sheet()
	print("Saved ability review frames (%d)" % shots.size())
	quit()


func _settle(frames: int) -> void:
	for frame in frames:
		arena.sync(swarm.position)
		camera.position = swarm.position + CAMERA_OFFSET
		camera.look_at(swarm.position, Vector3.UP)
		await process_frame


func _ability(strain: String) -> void:
	var adapter := Adapter.new()
	adapter.world = world
	adapter.swarm = swarm
	adapter.arena = arena
	world.add_child(adapter)
	var ability: Variant = ABILITIES.new()
	world.add_child(ability)
	ability.setup(adapter, strain)
	swarm.position = Vector3(0, 0, 30)
	# A few hunters ahead and around (they hold still: the world does not step).
	for offset in [Vector3(-2.5, 0, -5), Vector3(2.0, 0, -7), Vector3(0.5, 0, -3), Vector3(5, 0, 1), Vector3(-5, 0, 2)]:
		var hunter: Variant = world._spawn_hunter(swarm.position + offset)
		adapter.enemies.append(hunter)
	await _settle(20)
	if strain == STRAINS[0]:
		ability.sync_hud(hud)
		await _save("preview_ability_button_ready.png", "BEREIT · Q / Shift oder Knopf")
	var move := Vector3(0, 0, -1)
	ability.use(move)
	var wait := {"glutsprung": 0.2, "sporenbombe": 0.6, "panzerstoss": 0.12, "hetzjagd": 0.25, "saeureschwall": 0.2, "schattenschleier": 0.3}
	for index in int(float(wait[ability.ability_id]) / DT):
		ability.step(DT, move)
		ability.sync_hud(hud)
		arena.sync(swarm.position)
		camera.position = swarm.position + CAMERA_OFFSET
		camera.look_at(swarm.position, Vector3.UP)
		await process_frame
	await _save("preview_ability_%s.png" % ability.ability_id, ability.definition().text)
	if strain == STRAINS[0]:
		for index in 240:
			ability.step(DT, Vector3.ZERO)
		ability.sync_hud(hud)
		await _save("preview_ability_button_cooldown.png", "ABKLINGZEIT")
	ability.clear()
	for enemy in adapter.enemies:
		if is_instance_valid(enemy):
			world.hunters.erase(enemy)
			enemy.queue_free()
	ability.queue_free()
	adapter.queue_free()
	hud.ability_state = {}
	await _settle(4)


func _save(file_name: String, hint: String) -> void:
	world._update_hud(hint)
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://" + file_name)
	shots.append(image)


func _sheet() -> void:
	var columns := 4
	var w := 270
	var h := 480
	var rows := ceili(float(shots.size()) / columns)
	var sheet := Image.create(w * columns, h * rows, false, Image.FORMAT_RGBA8)
	for index in shots.size():
		var small := shots[index].duplicate() as Image
		small.convert(Image.FORMAT_RGBA8)
		small.resize(w, h)
		sheet.blit_rect(small, Rect2i(0, 0, w, h), Vector2i((index % columns) * w, (index / columns) * h))
	sheet.save_png("res://preview_ability_sheet.png")
