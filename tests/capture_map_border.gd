extends SceneTree

# Review frames for the bounded map (stage 18). Run WITHOUT --headless, e.g.
#   Godot --screen 1 --audio-driver Dummy --path . --script res://tests/capture_map_border.gd
# The swarm walks into the edge from the real game camera:
#   preview_border_verdant_north/east/south/corner.png
#   preview_border_glut_north/east/south/corner.png
#   preview_border_verdant_far.png / _glut_far.png  – pulled-back camera at the edge
#   preview_map_overview_verdant.png / _glut.png      – the whole map from above

const BIOMES = preload("res://scripts/biomes.gd")
const CAMERA_OFFSET := Vector3(0.0, 23.0, 15.0)
const SEED := 4242

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
	arena.set_seed(SEED)
	for id in ["verdant_maw", "glutsumpf"]:
		_biome(id)
		var tag := "verdant" if id == "verdant_maw" else "glut"
		var label := BIOMES.display_name(id).to_upper()
		var rect: Rect2 = arena.playable_rect()
		var mid := rect.get_center()
		await _walk(Vector3(mid.x + 20.0, 0.0, rect.position.y + 14.0), Vector2(0.15, -1.0), "preview_border_%s_north.png" % tag, label + " · NORDRAND")
		await _walk(Vector3(rect.end.x - 14.0, 0.0, mid.y - 30.0), Vector2(1.0, 0.1), "preview_border_%s_east.png" % tag, label + " · OSTRAND")
		await _walk(Vector3(mid.x - 40.0, 0.0, rect.end.y - 14.0), Vector2(0.0, 1.0), "preview_border_%s_south.png" % tag, label + " · SÜDRAND")
		await _walk(Vector3(rect.position.x + 14.0, 0.0, rect.position.y + 14.0), Vector2(-0.7, -0.7), "preview_border_%s_corner.png" % tag, label + " · ECKE")
		await _walk(Vector3(mid.x - 60.0, 0.0, rect.position.y + 14.0), Vector2(0.0, -1.0), "preview_border_%s_far.png" % tag, label + " · RAND (WEIT)", 1.45)
		await _overview("preview_map_overview_%s.png" % tag)
	print("Saved map border review frames")
	quit()


func _biome(id: String) -> void:
	arena.set_biome(id)
	arena.finish_rebuild()
	var light: Dictionary = BIOMES.get_data(id).light
	sun.light_color = light.color
	sun.light_energy = light.energy


# The swarm walks towards the edge for ~2.5 s (joystick held), camera follows.
func _walk(start: Vector3, direction: Vector2, file_name: String, message: String, zoom := 1.0) -> void:
	scene.get_node("HUD").visible = true
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	swarm.position = arena.safe_spawn(start, 1.0)
	arena.sync(swarm.position)
	arena.finish_rebuild()
	swarm.set_controls(direction.normalized(), false)
	for frame in 150:
		arena.sync(swarm.position)
		arena.finish_rebuild()
		camera.position = swarm.position + CAMERA_OFFSET * zoom
		camera.look_at(swarm.position, Vector3.UP)
		await process_frame
	swarm.set_controls(Vector2.ZERO, false)
	world._update_hud(message)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/" + file_name)


# The whole map from straight above (orthographic, square SubViewport sharing
# the game world), every chunk built.
func _overview(file_name: String) -> void:
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
