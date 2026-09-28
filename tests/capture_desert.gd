extends SceneTree

# Review frames for the Dürrschlund (stage 19 phase 2). Run WITHOUT --headless:
#   Godot --screen 1 --audio-driver Dummy --path . --script res://tests/capture_desert.gd
#   preview_desert_{seed}.png          whole desert map from above (two seeds)
#   preview_desert_dunes.png            game camera: open dunes (sandstone outcrops)
#   preview_desert_cliffs.png           sandstone cliff field / ridge / canyon
#   preview_desert_ribs.png (+ _top, _collision)   bone field with rib cages
#   preview_desert_oasis.png            oasis clearing with turquoise ponds
#   preview_desert_cactus.png           cactus grove
#   preview_desert_quicksand.png        swarm crossing a quicksand patch
#   preview_desert_landmarks.png        rock arch / giant skull
#   preview_desert_sandstorm.png        sandstorm wave (edge veil, HUD hint)
#   preview_desert_worm_*.png           the Sandwurm in a real run (warning, strike, exhausted, grubs)
#   preview_desert_portal.png           the desert Migrationsschlund (SandPortal)
#   preview_desert_card.png             480 x 320 crop for the menu biome tile
#   preview_desert_minimap.png          big map with the desert palette

const CAMERA_OFFSET := Vector3(0.0, 23.0, 15.0)
const SEEDS := [4242, 31337]

var scene: Node
var world: Variant
var swarm: Variant
var arena: Variant
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
	camera = scene.get_node("Camera3D")
	var controls: Variant = scene.get_node("HUD/Controls")
	for connection in controls.pause_requested.get_connections():
		connection.signal.disconnect(connection.callable)
	scene.set_process(false)
	world.set_process(false)
	world._set_world_biome("duerrschlund", false)
	for seed_value in SEEDS:
		arena.set_seed(seed_value)
		arena.finish_rebuild()
		await _overview("preview_desert_%d.png" % seed_value)
	arena.set_seed(SEEDS[1])
	_quiet_run()
	var start: Vector3 = arena.spawn_points(1)[0]
	for entry in [["dunes", "preview_desert_dunes.png", "OFFENE DÜNEN"], ["cliffs", "preview_desert_cliffs.png", "SANDSTEIN-KLIPPEN"], ["oasis", "preview_desert_oasis.png", "OASE"], ["cactus", "preview_desert_cactus.png", "KAKTUSHAIN"]]:
		var spot := _find_land(String(entry[0]), start)
		if spot == start and String(entry[0]) == "cliffs":
			spot = _find_land("ridge", start)
		if spot == start:
			spot = _find_land("canyon", start)
		_frame_at(spot)
		await _save(String(entry[1]), String(entry[2]))
	await _minimap("preview_desert_minimap.png")
	var ribs := _near_ribs()
	if ribs.is_finite():
		_frame_at(ribs)
		await _save("preview_desert_ribs.png", "KNOCHENFELD · RIPPEN ALS WAND")
		await _overview("preview_desert_ribs_top.png", ribs, 70.0)
		var overlay := _collision_overlay(ribs, 70.0)
		await _overview("preview_desert_ribs_collision.png", ribs, 70.0)
		overlay.queue_free()
	var sands: Array = arena.quicksand_patches()
	if not sands.is_empty():
		var patch: Vector4 = sands[0]
		_frame_at(Vector3(patch.x, 0.0, patch.z))
		swarm.position = Vector3(patch.x - patch.w * 0.3, 0.0, patch.z)
		await _save("preview_desert_quicksand.png", "TREIBSAND · bremst, raus auf festen Sand")
	for mark in arena.layout.beacons:
		if mark.kind == "rock_arch":
			_frame_at(mark.center + Vector3(0.0, 0.0, 9.0), 1.35)
			await _save("preview_desert_landmarks.png", "FELSBOGEN · DARUNTER BEGEHBAR")
			break
	for mark in arena.layout.beacons:
		if mark.kind == "giant_skull":
			_frame_at(mark.center + Vector3(0.0, 0.0, 9.0), 1.2)
			await _save("preview_desert_skull.png", "RIESENSCHÄDEL")
			break
	# Menu card: a calm dune shot with the swarm, cropped to 480 x 320.
	_frame_at(_find_land("dunes", start), 1.1)
	await _save("preview_desert_card_full.png", "")
	var full := Image.load_from_file(ProjectSettings.globalize_path("res://preview_desert_card_full.png"))
	full.crop(540, 960)
	var card := full.get_region(Rect2i(30, 330, 480, 320))
	card.save_png("res://preview_desert_card.png")
	# Sandstorm: announced, then the edge veil (centre free).
	_frame_at(_find_land("dunes", start))
	world.desert.storm.force(0.0)
	await _run(6.5)
	await _save("preview_desert_sandstorm.png", "", false)
	await _run(4.0)
	world.desert.storm.clear()
	# The Sandwurm in a real run: rises, warns, breaks through, lies exhausted.
	_quiet_run()
	_frame_at(_find_open(start))
	world.model.population = 60
	swarm.set_population(60)
	var worm: Variant = world.spawn_apex(swarm.position + Vector3(0.0, 0.0, -12.0), "apex_sandworm")
	var shots := {}
	var elapsed := 0.0
	while elapsed < 40.0 and shots.size() < 5:
		await _run(0.1)
		elapsed += 0.1
		if world.apex == null:
			break
		var state := int(worm.state)
		var pattern := int(worm.current_pattern)
		if state == worm.State.WINDUP and pattern == worm.Pattern.BREACH and not shots.has("breach_warning") and float(worm.remaining) < 0.8:
			shots["breach_warning"] = true
			await _save("preview_desert_worm_breach_warning.png", "", false)
		elif state == worm.State.STRIKE and pattern == worm.Pattern.BREACH and not shots.has("breach"):
			shots["breach"] = true
			await _save("preview_desert_worm_breach.png", "", false)
		elif state == worm.State.EXHAUSTED and not shots.has("exhausted"):
			shots["exhausted"] = true
			await _save("preview_desert_worm_exhausted.png", "", false)
		elif state == worm.State.WINDUP and pattern == worm.Pattern.SWEEP and not shots.has("sweep") and float(worm.remaining) < 0.7:
			shots["sweep"] = true
			await _save("preview_desert_worm_sweep.png", "", false)
		elif state == worm.State.CHASE and not shots.has("chase") and elapsed > 3.0:
			shots["chase"] = true
			await _save("preview_desert_worm_chase.png", "", false)
		# The swarm keeps its leader alive for the review (no extinction).
		world.model.leader_hp = world.model.leader_max_hp
		if world.model.population < 30:
			world.model.population = 60
			swarm.set_population(60)
	# Phase two: grubs in the picture.
	if world.apex != null:
		world.apex.health = world.apex.max_health * 0.49
		for step in 60:
			await _run(0.1)
			world.model.leader_hp = world.model.leader_max_hp
			if world.desert.grubs.count() >= 4:
				break
		await _save("preview_desert_worm_grubs.png", "", false)
		world.apex.health = 0.0
		await _run(1.5)
		await _save("preview_desert_worm_dead.png", "", false)
		# Portal: the SandPortal maw opens behind the corpse.
		for step in 80:
			await _run(0.1)
			if world.portal != null:
				break
		if world.portal != null:
			_frame_at(world.portal.position + Vector3(0.0, 0.0, 7.0))
			await _run(1.5)
			await _save("preview_desert_portal.png", "", false)
	print("Saved desert review frames (%d worm shots)" % shots.size())
	quit()


func _quiet_run() -> void:
	world.reset_run()
	world._set_world_biome("duerrschlund", false)
	world.set_process(false)
	for prey in world.prey:
		prey.visible = false
	world.model.population = 40
	swarm.set_population(40)


# Steps the real HuntWorld for `seconds` (60 fps), the camera follows the swarm.
func _run(seconds: float) -> void:
	var frames := int(round(seconds * 60.0))
	for frame in frames:
		world.step(1.0 / 60.0)
		arena.sync(swarm.position)
		camera.position = swarm.position + CAMERA_OFFSET
		camera.look_at(swarm.position, Vector3.UP)
		await process_frame


func _frame_at(point: Vector3, zoom := 1.0) -> void:
	swarm.position = arena.safe_spawn(point, 1.0)
	arena.sync(swarm.position)
	arena.finish_rebuild()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.position = swarm.position + CAMERA_OFFSET * zoom
	camera.look_at(swarm.position, Vector3.UP)


func _save(file_name: String, message: String, settle := true) -> void:
	scene.get_node("HUD").visible = true
	if message != "":
		world._update_hud(message)
	if settle:
		for frame in 70:
			arena.sync(swarm.position)
			await process_frame
	else:
		for frame in 2:
			await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + file_name)


func _find_land(name: String, start: Vector3) -> Vector3:
	var layout: RefCounted = arena.layout
	var best := start
	var best_score := -INF
	for step in 4000:
		var point := Vector3(fmod(float(step) * 37.3, 300.0) - 150.0, 0.0, fmod(float(step) * 61.7, 300.0) - 150.0)
		if layout.land_at(point.x, point.z) != name:
			continue
		var wall: float = arena.wall_distance(point)
		if wall < 2.5 or wall > 6.0:
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


# Big map with fog: the swarm walks a little first (minimap palette check).
func _minimap(file_name: String) -> void:
	scene.get_node("HUD").visible = true
	for spot in [Vector3(0, 0, 0), Vector3(40, 0, 20), Vector3(-30, 0, -40)]:
		swarm.position = arena.safe_spawn(arena.map_center() + spot, 1.0)
		arena.sync(swarm.position)
		arena.discover_around(swarm.position, 40.0)
	await _run(0.5)
	var hud: Variant = scene.get_node("HUD/Controls")
	if hud.get("map_open") != null:
		hud.map_open = true
		for frame in 20:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://" + file_name)
		hud.map_open = false
		for frame in 3:
			await process_frame


func _find_open(start: Vector3) -> Vector3:
	var boss: Array = arena.poi_slots("boss")
	return boss[0] if not boss.is_empty() else start


# Open ground south of a rib cage (the camera looks north onto it).
func _near_ribs() -> Vector3:
	var cages: Array = arena.layout.ribs
	for cage in cages:
		for reach in [5.0, 6.5, 8.0]:
			var point: Vector3 = cage.center + Vector3(0.0, 0.0, reach)
			if arena.wall_distance(point) > 2.0:
				return point
	return Vector3.INF


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


func _overview(file_name: String, focus := Vector3.INF, span := 0.0) -> void:
	scene.get_node("HUD").visible = false
	var old_radius: int = arena.view_radius
	arena.view_radius = 9
	arena.fade_enabled = false
	var middle: Vector3 = arena.map_center() if not focus.is_finite() else focus
	arena.sync(middle)
	arena.finish_rebuild()
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
	view.get_texture().get_image().save_png("res://" + file_name)
	view.queue_free()
	arena.view_radius = old_radius
	arena.fade_enabled = true
	arena.sync(middle)
