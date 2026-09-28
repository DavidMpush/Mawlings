extends SceneTree

# Review frames for the designed map (stage 18b). Run WITHOUT --headless, e.g.
#   Godot --screen 1 --audio-driver Dummy --path . --script res://tests/capture_map_layout.gd
# Environment: MAWLINGS_CAPTURE_ONLY=overview|game (default: both).
#   preview_layout_{verdant,glut}_{seed}.png  whole map from above, three seeds per biome
#   preview_layout_choke.png     game camera at a narrow path, the flood streams in
#   preview_layout_southwall.png swarm pressed against a wall between camera and swarm
#   preview_layout_nest.png      a nest clearing with its nest
#   preview_layout_boss.png      the boss arena with the Moosschlund
#   preview_layout_routes.png    pulled-back camera over two routes to one clearing
#   preview_layout_glut_path.png Glutsumpf path with walls from the game camera

const BIOMES = preload("res://scripts/biomes.gd")
const CAMERA_OFFSET := Vector3(0.0, 23.0, 15.0)
const SEEDS := [4242, 777, 90210]

var scene: Node
var world: Variant
var swarm: Variant
var arena: Variant
var sun: DirectionalLight3D
var camera: Camera3D


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
	sun = scene.get_node("Sun")
	camera = scene.get_node("Camera3D")
	var controls: Variant = scene.get_node("HUD/Controls")
	for connection in controls.pause_requested.get_connections():
		controls.pause_requested.disconnect(connection.callable)
	scene.set_process(false)
	world.set_process(false)
	for prey in world.prey:
		prey.visible = false
	world.model.population = 60
	swarm.set_population(60)
	var only := OS.get_environment("MAWLINGS_CAPTURE_ONLY")
	if only == "" or only == "overview":
		for id in ["verdant_maw", "glutsumpf"]:
			for seed_value in SEEDS:
				arena.set_seed(seed_value)
				_biome(id)
				await _overview("preview_layout_%s_%d.png" % ["verdant" if id == "verdant_maw" else "glut", seed_value])
	if only == "" or only == "game":
		await _game_frames()
	print("Saved map layout review frames")
	quit()


func _biome(id: String) -> void:
	arena.set_biome(id)
	arena.finish_rebuild()
	var light: Dictionary = BIOMES.get_data(id).light
	sun.light_color = light.color
	sun.light_energy = light.energy


func _frame_at(point: Vector3, zoom := 1.0) -> void:
	swarm.position = arena.safe_spawn(point, 1.0)
	arena.sync(swarm.position)
	arena.finish_rebuild()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.position = swarm.position + CAMERA_OFFSET * zoom
	camera.look_at(swarm.position, Vector3.UP)


func _save(file_name: String, message: String) -> void:
	world._update_hud(message)
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/" + file_name)


func _game_frames() -> void:
	arena.set_seed(SEEDS[0])
	_biome("verdant_maw")
	scene.get_node("HUD").visible = true
	# 1. A narrow path: the swarm stands at the choke, the flood streams in.
	var choke := _choke_point()
	_frame_at(choke)
	arena.finish_flow(swarm.position)
	world.horde.clear()
	for index in 6:
		world.horde.spawn_ring(swarm.position, 12, 16.0 + float(index) * 3.0, {})
	for frame in 70:
		arena.sync(swarm.position)
		world.horde.step(1.0 / 30.0, swarm.unit_world_points())
		await process_frame
	await _save("preview_layout_choke.png", "ENGPASS · DIE FLUT STRÖMT DURCH DEN WEG")
	world.horde.clear()
	# 1b. Pressed against a wall south of the swarm (between camera and swarm):
	# the wall must stay low enough that every Mawling stays visible.
	var south := _south_wall_point()
	_frame_at(south)
	swarm.set_controls(Vector2(0.0, 1.0), false)
	for frame in 40:
		swarm._process(1.0 / 60.0)
		arena.sync(swarm.position)
		camera.position = swarm.position + CAMERA_OFFSET
		camera.look_at(swarm.position, Vector3.UP)
		await process_frame
	swarm.set_controls(Vector2.ZERO, false)
	await _save("preview_layout_southwall.png", "WAND SÜDLICH DES SCHWARMS · BLEIBT NIEDRIG")
	# 2. A nest clearing with its nest.
	var nest_spot: Vector3 = arena.poi_slots("nest")[0]
	world.spawn_nest(nest_spot)
	_frame_at(nest_spot + Vector3(0.0, 0.0, 8.0))
	await _save("preview_layout_nest.png", "LICHTUNG MIT BRUTNEST")
	# 3. The boss arena with the Moosschlund.
	var boss_spot: Vector3 = arena.poi_slots("boss")[0]
	var apex: Node3D = world.spawn_apex(boss_spot)
	_frame_at(boss_spot + Vector3(0.0, 0.0, 14.0), 1.35)
	# Let the apex rise out of the ground (its own animation) before the shot.
	if apex != null:
		for frame in 90:
			apex.step(1.0 / 60.0, swarm.position, 1.0)
			await process_frame
	await _save("preview_layout_boss.png", "BOSS-ARENA")
	if apex != null:
		apex.queue_free()
		world.apex = null
	# 4. Two routes: pulled back over a clearing with a narrow and a wide path.
	var hub: Vector3 = _routes_point()
	_frame_at(hub, 3.6)
	await _save("preview_layout_routes.png", "ZWEI WEGE: KURZ UND ENG · LANG UND OFFEN")
	# 5. Glutsumpf path.
	_biome("glutsumpf")
	_frame_at(_choke_point() + Vector3(0.0, 0.0, 4.0), 1.1)
	await _save("preview_layout_glut_path.png", "GLUTSUMPF · WEG ZWISCHEN BASALT")


# Middle of the pinch of the first narrow path.
func _choke_point() -> Vector3:
	for path in arena.paths():
		if path.kind != "narrow":
			continue
		var halves: PackedFloat32Array = path.half
		var best := 0
		for index in halves.size():
			if halves[index] < halves[best]:
				best = index
		return path.points[best]
	return Vector3.ZERO


# Open ground right north of a wall: from a clearing centre straight south
# until the wall is 1.5 m away.
func _south_wall_point() -> Vector3:
	for clearing in arena.clearings():
		if clearing.types.has("start"):
			continue
		var point: Vector3 = clearing.center
		for step in 120:
			var next: Vector3 = point + Vector3(0.0, 0.0, 0.5)
			if arena.wall_distance(next) < 1.5:
				return point
			point = next
	return Vector3.ZERO


# A clearing (not the hub) with one narrow and one main path.
func _routes_point() -> Vector3:
	var paths: Array = arena.paths()
	for clearing in arena.clearings():
		var kinds := {}
		for index in clearing.paths:
			kinds[paths[index].kind] = true
		if kinds.size() == 2 and not clearing.types.has("start"):
			return clearing.center
	return Vector3.ZERO


# The whole map from straight above (orthographic, square SubViewport sharing
# the game world), every chunk built.
func _overview(file_name: String) -> void:
	scene.get_node("HUD").visible = false
	var old_radius: int = arena.view_radius
	arena.view_radius = 9
	var middle: Vector3 = arena.map_center()
	arena.sync(middle)
	arena.finish_rebuild()
	swarm.position = middle
	var view := SubViewport.new()
	view.size = Vector2i(1024, 1024)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	scene.add_child(view)
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = arena.bounds().size.y + 60.0
	top.far = 400.0
	view.add_child(top)
	top.position = middle + Vector3(0.0, 150.0, 0.0)
	top.look_at(middle, Vector3(0, 0, -1))
	top.current = true
	for frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png("res://previews/" + file_name)
	view.queue_free()
	arena.view_radius = old_radius
	arena.sync(middle)
