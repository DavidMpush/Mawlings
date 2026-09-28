extends SceneTree

# Review frames for the exploration map (stage 18c). Run WITHOUT --headless:
#   Godot --screen 1 --audio-driver Dummy --path . --script res://tests/capture_map_explore.gd
#   preview_explore_{seed}.png      whole map from above (Verdant, three seeds, no fog)
#   preview_explore_minimap.png     minimap + big map with fog right after the start
#   preview_explore_forest.png      game camera: light forest with gaps and a choke
#   preview_explore_ruins.png       game camera: ruin field with amber nodes, landmark far off
#   preview_explore_glut.png / preview_explore_glut_forest.png   Glutsumpf variant

const BIOMES = preload("res://scripts/biomes.gd")
const CAMERA_OFFSET := Vector3(0.0, 23.0, 15.0)
const SEEDS := [4242, 777, 90210]

var scene: Node
var world: Variant
var swarm: Variant
var arena: Variant
var camera: Camera3D


func _initialize() -> void:
	call_deferred("_capture")


# Debug: the collision edge (red) over the look - every border between open and
# blocked ground (walls, stones, landmarks) on a 0.2 m raster around `focus`.
func _collision_overlay(focus: Vector3, span: float) -> MeshInstance3D:
	var px := 360
	var image := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var step := span / float(px)
	var open := PackedByteArray()
	open.resize(px * px)
	for iz in px:
		for ix in px:
			var point := focus + Vector3(-span * 0.5 + (float(ix) + 0.5) * step, 0.0, -span * 0.5 + (float(iz) + 0.5) * step)
			open[iz * px + ix] = 1 if arena.is_open(point, 0.01) else 0
	for iz in range(1, px - 1):
		for ix in range(1, px - 1):
			var here := open[iz * px + ix]
			if here != open[iz * px + ix + 1] or here != open[(iz + 1) * px + ix] or here != open[iz * px + ix - 1] or here != open[(iz - 1) * px + ix]:
				image.set_pixel(ix, iz, Color(1.0, 0.1, 0.1, 1.0))
	var quad := PlaneMesh.new()
	quad.size = Vector2(span, span)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.render_priority = 100
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var view := MeshInstance3D.new()
	view.mesh = quad
	view.material_override = material
	view.position = Vector3(focus.x, 0.08, focus.z)
	scene.add_child(view)
	return view


func _capture() -> void:
	root.size = Vector2i(540, 960)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	arena = scene.get_node("Arena")
	camera = scene.get_node("Camera3D")
	var controls: Variant = scene.get_node("HUD/Controls")
	for connection in controls.pause_requested.get_connections():
		controls.pause_requested.disconnect(connection.callable)
	scene.set_process(false)
	world.set_process(false)
	for prey in world.prey:
		prey.visible = false
	world.model.population = 40
	swarm.set_population(40)
	for seed_value in SEEDS:
		arena.set_seed(seed_value)
		arena.finish_rebuild()
		await _overview("preview_explore_%d.png" % seed_value)
	# The run of the first seed: amber nodes of this map, fog fresh at the start.
	arena.set_seed(SEEDS[0])
	world.reset_run()
	world.set_process(false)
	for prey in world.prey:
		prey.visible = false
	world.model.population = 40
	swarm.set_population(40)
	var start: Vector3 = arena.spawn_points(1)[0]
	_frame_at(start)
	await _minimap("preview_explore_minimap.png")
	var forest := _find_land("forest", start)
	_frame_at(forest)
	await _save("preview_explore_forest.png", "LICHTER WALD · LÜCKEN UND ENGPÄSSE")
	var overlay := _collision_overlay(swarm.position, 70.0)
	await _save("preview_explore_forest_collision.png", "KOLLISION (ROT) ÜBER DER OPTIK")
	overlay.queue_free()
	var rocks_done := false
	for pair in [["ridge", "preview_explore_rocks.png", "FELSRÜCKEN"], ["labyrinth", "preview_explore_rocks.png", "FELSLABYRINTH"], ["swamp", "preview_explore_swamp.png", "SUMPF"]]:
		if rocks_done and String(pair[0]) == "labyrinth":
			continue
		var spot := _find_land(String(pair[0]), start)
		if spot == start:
			continue
		if String(pair[0]) == "ridge":
			rocks_done = true
		_frame_at(spot)
		await _save(String(pair[1]), String(pair[2]))
	# The ruin shot on the first seed that has a ruin field.
	for seed_value in SEEDS:
		if int(arena.layout.stats().lands.get("ruins", 0)) > 0:
			break
		arena.set_seed(seed_value)
		world.reset_run()
		world.set_process(false)
		for prey in world.prey:
			prey.visible = false
	world.model.population = 40
	swarm.set_population(40)
	var ruins := _find_ruins_with_loot(start)
	await _overview("preview_explore_ruins_top.png", ruins, 80.0)
	var ruin_overlay := _collision_overlay(ruins, 80.0)
	await _overview("preview_explore_ruins_collision.png", ruins, 80.0)
	ruin_overlay.queue_free()
	_frame_at(ruins, 1.25)
	# Look towards the nearest landmark: the camera sits south, so it shows north.
	await _save("preview_explore_ruins.png", "RUINENFELD · BERNSTEINKNOLLEN")
	# Glutsumpf: the same generator with charred wood, basalt and lava crust.
	arena.set_biome("glutsumpf")
	arena.finish_rebuild()
	await _overview("preview_explore_glut.png")
	_frame_at(_find_land("forest", arena.spawn_points(1)[0]))
	await _save("preview_explore_glut_forest.png", "GLUTSUMPF · VERKOHLTER WALD")
	print("Saved exploration map review frames")
	quit()


func _frame_at(point: Vector3, zoom := 1.0) -> void:
	swarm.position = arena.safe_spawn(point, 1.0)
	arena.sync(swarm.position)
	arena.finish_rebuild()
	world.loot_nodes.step(swarm.position, PackedVector3Array())
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.position = swarm.position + CAMERA_OFFSET * zoom
	camera.look_at(swarm.position, Vector3.UP)


func _save(file_name: String, message: String) -> void:
	scene.get_node("HUD").visible = true
	world._update_hud(message)
	# New Mawlings hatch out of the leader over ~1 s: let them spread first.
	for frame in 70:
		arena.sync(swarm.position)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/" + file_name)


# A forest spot next to a wall (gaps and a choke in the picture).
func _find_land(name: String, start: Vector3) -> Vector3:
	var layout: RefCounted = arena.layout
	var best := start
	var best_score := -INF
	for step in 4000:
		var point := Vector3(fmod(float(step) * 37.3, 300.0) - 150.0, 0.0, fmod(float(step) * 61.7, 300.0) - 150.0)
		if layout.land_at(point.x, point.z) != name:
			continue
		var wall: float = arena.wall_distance(point)
		if wall < 2.5 or wall > 5.0:
			continue
		var score := 0.0
		for angle in 8:
			var probe := point + Vector3(cos(angle * TAU / 8.0), 0.0, sin(angle * TAU / 8.0)) * 8.0
			if arena.wall_distance(probe) < 0.0:
				score += 1.0
		if score > best_score and score <= 5.0:
			best_score = score
			best = point
	return best


# A ruin spot with amber nodes around and a landmark to the north.
func _find_ruins_with_loot(start: Vector3) -> Vector3:
	var layout: RefCounted = arena.layout
	var best := start
	var best_score := -INF
	for node in layout.loot_points:
		var point := Vector3(node.x, 0.0, node.z + 6.0)
		var score := 0.0
		if layout.land_at(node.x, node.z) == "ruins":
			score += 12.0
		for other in layout.loot_points:
			if Vector2(other.x - node.x, other.z - node.z).length() < 16.0:
				score += 1.0
		for mark in layout.beacons:
			var off: Vector3 = mark.center - point
			if off.z < -15.0 and off.z > -60.0 and absf(off.x) < 20.0:
				score += 4.0
		if score > best_score:
			best_score = score
			best = point
	return best


func _minimap(file_name: String) -> void:
	scene.get_node("HUD").visible = true
	world.set_process(true)
	for frame in 20:
		await process_frame
	world.set_process(false)
	await RenderingServer.frame_post_draw
	var hud: Variant = scene.get_node("HUD/Controls")
	if hud.get("map_open") != null:
		hud.map_open = true
		for frame in 10:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://previews/" + file_name)
		hud.map_open = false
		for frame in 3:
			await process_frame
	else:
		root.get_texture().get_image().save_png("res://previews/" + file_name)


func _overview(file_name: String, focus := Vector3.INF, span := 0.0) -> void:
	scene.get_node("HUD").visible = false
	var old_radius: int = arena.view_radius
	arena.view_radius = 9
	arena.fade_enabled = false
	var middle: Vector3 = arena.map_center() if not focus.is_finite() else focus
	arena.sync(middle)
	arena.finish_rebuild()
	world.loot_nodes.setup(world, arena)
	swarm.position = middle
	var view := SubViewport.new()
	view.size = Vector2i(1024, 1024)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	scene.add_child(view)
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = arena.bounds().size.y + 60.0 if span <= 0.0 else span
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
	arena.fade_enabled = true
	arena.sync(middle)
