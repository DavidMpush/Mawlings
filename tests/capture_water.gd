extends SceneTree

# Review frames for stage 29 (lakes with a shallow shore). Run WITHOUT --headless:
#   Godot --screen 1 --audio-driver Dummy --path . --script res://tests/capture_water.gd
#   preview_water_lake.png          game camera: swarm on the shallow shore of a Verdant lake
#   preview_water_lake_top.png      the same lake from above
#   preview_water_lake_collision.png  collision edge (red) over the lake from above
#   preview_water_edge.png          game camera: edge water at the map border (Verdant)
#   preview_water_oasis.png / _top  Dürrschlund oasis pond
#   preview_water_lava.png / _top   Glutsumpf lava lake with its crust ring
#   preview_water_lava_edge.png     Glutsumpf edge lava

const CAMERA_OFFSET := Vector3(0.0, 23.0, 15.0)
const SEED := 90210

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
		controls.pause_requested.disconnect(connection.callable)
	scene.set_process(false)
	world.set_process(false)
	arena.set_seed(SEED)
	_hide_prey()
	world.model.population = 40
	swarm.set_population(40)
	var lake := _lake()
	var shore := _shore_spot(lake)
	_frame_at(shore)
	await _save("preview_water_lake.png", "SEE · FLACHUFER BREMST")
	await _overview("preview_water_lake_top.png", lake.center, 60.0)
	var overlay := _collision_overlay(lake.center, 60.0)
	await _overview("preview_water_lake_collision.png", lake.center, 60.0)
	overlay.queue_free()
	_frame_at(_edge_spot())
	await _save("preview_water_edge.png", "RANDWASSER")
	arena.set_biome("duerrschlund")
	arena.finish_rebuild()
	_hide_prey()
	lake = _lake()
	_frame_at(_shore_spot(lake))
	await _save("preview_water_oasis.png", "OASE")
	await _overview("preview_water_oasis_top.png", lake.center, 60.0)
	arena.set_biome("glutsumpf")
	arena.finish_rebuild()
	_hide_prey()
	lake = _lake()
	_frame_at(_shore_spot(lake))
	await _save("preview_water_lava.png", "LAVASEE · KRUSTE BREMST")
	await _overview("preview_water_lava_top.png", lake.center, 60.0)
	_frame_at(_edge_spot())
	await _save("preview_water_lava_edge.png", "LAVA AM RAND")
	print("Saved water review frames")
	quit()


func _hide_prey() -> void:
	for prey in world.prey:
		prey.visible = false


# The biggest lake of the map.
func _lake() -> Dictionary:
	var best: Dictionary = {}
	for basin in arena.layout.basins:
		if best.is_empty() or float(basin.radius) > float(best.radius):
			best = basin
	return best


# A point in the shallow band on the camera side (south) of a lake.
func _shore_spot(lake: Dictionary) -> Vector3:
	var center: Vector3 = lake.center
	for step in 80:
		var point := center + Vector3(0.0, 0.0, float(step) * 0.5)
		if arena.layout.deep_at(point.x, point.z) > 1.2 and arena.layout.water_at(point.x, point.z) < -0.4:
			return point
	return center + Vector3(0.0, 0.0, float(lake.radius))


# A point in front of the first edge-water run of the north side.
func _edge_spot() -> Vector3:
	var rect: Rect2 = arena.playable_rect()
	for step in 200:
		var x := rect.position.x + 20.0 + float(step) * 1.5
		var probe := Vector2(x, rect.position.y - 3.0)
		if arena.border._edge_water(probe.x, probe.y).x < -1.0:
			return Vector3(x, 0.0, rect.position.y + 9.0)
	return Vector3(0.0, 0.0, rect.position.y + 9.0)


func _frame_at(point: Vector3, zoom := 1.0) -> void:
	swarm.position = arena.safe_spawn(point, 1.0)
	arena.sync(swarm.position)
	arena.finish_rebuild()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.position = swarm.position + CAMERA_OFFSET * zoom
	camera.look_at(swarm.position, Vector3.UP)


func _save(file_name: String, message: String) -> void:
	scene.get_node("HUD").visible = true
	world._update_hud(message)
	for frame in 70:
		arena.sync(swarm.position)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/" + file_name)


func _overview(file_name: String, focus: Vector3, span: float) -> void:
	scene.get_node("HUD").visible = false
	var old_radius: int = arena.view_radius
	arena.view_radius = 2
	arena.fade_enabled = false
	arena.sync(focus)
	arena.finish_rebuild()
	var view := SubViewport.new()
	view.size = Vector2i(768, 768)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	scene.add_child(view)
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = span
	top.far = 400.0
	view.add_child(top)
	top.position = focus + Vector3(0.0, 150.0, 0.0)
	top.look_at(focus, Vector3(0, 0, -1))
	top.current = true
	for frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png("res://previews/" + file_name)
	view.queue_free()
	arena.view_radius = old_radius
	arena.fade_enabled = true


# The collision edge (red) over the look, 0.1 m raster.
func _collision_overlay(focus: Vector3, span: float) -> MeshInstance3D:
	var px := 600
	var image := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var step := span / float(px)
	var open := PackedByteArray()
	open.resize(px * px)
	for iz in px:
		for ix in px:
			var point := focus + Vector3(-span * 0.5 + (float(ix) + 0.5) * step, 0.0, -span * 0.5 + (float(iz) + 0.5) * step)
			open[iz * px + ix] = 1 if arena.wall_distance(point) >= 0.0 else 0
	for iz in range(1, px - 1):
		for ix in range(1, px - 1):
			var here := open[iz * px + ix]
			if here != open[iz * px + ix + 1] or here != open[(iz + 1) * px + ix]:
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
