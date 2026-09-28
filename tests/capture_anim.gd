extends SceneTree

# Review frames for the vertex-shader limb animation (creature_anim.gdshader).
# Run WITHOUT --headless (frame_post_draw hangs headless):
#   Godot_console.exe --path . --script res://tests/capture_anim.gd
# Writes:
#   preview_anim_mawling_side.png   sheet: rest, walk 0/90/180/270 deg, bite (side view)
#   preview_anim_mawling_top.png    same six from an elevated front three-quarter view
#   preview_anim_boss.png           sheet: rest, 4 walk phases, stomp raise, roar
#   preview_anim_game.png           running swarm from the real game camera
#   preview_anim_game_boss.png      chasing Bog King from the real game camera

const SWARM = preload("res://scripts/swarm.gd")
const BOG_KING = preload("res://scripts/bog_king.gd")
const MAWLING = preload("res://assets/gameplay/characters/Mawling_game.glb")

var stage: Node3D
var camera: Camera3D
var view: SubViewport


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	await _closeups()
	await _game_shots()
	print("Saved limb animation review frames")
	quit()


func _closeups() -> void:
	# Own SubViewport: the window size is clamped by the project's portrait override.
	view = SubViewport.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.own_world_3d = true
	root.add_child(view)
	stage = Node3D.new()
	view.add_child(stage)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ground_material.albedo_color = Color(0.36, 0.52, 0.3)
	ground.material_override = ground_material
	stage.add_child(ground)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	camera.make_current()

	# Six Mawlings in a row: rest, walk phase 0/90/180/270 degrees, bite.
	var helper: Node3D = SWARM.new()
	var material: ShaderMaterial = helper._creature_material(0.0)
	helper.free()
	var labels := ["rest", "0", "90", "180", "270", "bite"]
	for index in labels.size():
		var model: Node3D = MAWLING.instantiate()
		model.scale = Vector3.ONE * 1.6
		model.position = Vector3(float(index) * 2.2, 0.0, 0.0)
		stage.add_child(model)
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			var geometry: GeometryInstance3D = mesh
			geometry.material_override = material
			if index >= 1 and index <= 4:
				geometry.set_instance_shader_parameter("instance_walk", 1.0)
				geometry.set_instance_shader_parameter("instance_phase", float(index - 1) * PI * 0.5)
			elif index == 5:
				geometry.set_instance_shader_parameter("instance_bite", 1.0)
	# Sheet per view: one cell per model, camera moved along the row.
	var cell := Vector2i(440, 300)
	view.size = cell
	for view_index in 2:
		var sheet := Image.create(cell.x * 3, cell.y * 2, false, Image.FORMAT_RGBA8)
		for index in labels.size():
			var x := float(index) * 2.2
			if view_index == 0:
				camera.projection = Camera3D.PROJECTION_ORTHOGONAL
				camera.size = 1.35
				camera.position = Vector3(x, 1.0, 6.0)
				camera.look_at(Vector3(x, 0.55, 0.0), Vector3.UP)
			else:
				camera.projection = Camera3D.PROJECTION_PERSPECTIVE
				camera.fov = 22.0
				camera.position = Vector3(x - 1.6, 2.6, 3.2)
				camera.look_at(Vector3(x, 0.35, 0.0), Vector3.UP)
			await RenderingServer.frame_post_draw
			var shot := view.get_texture().get_image()
			shot.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(shot, Rect2i(Vector2i.ZERO, cell), Vector2i((index % 3) * cell.x, (index / 3) * cell.y))
		sheet.save_png("res://previews/preview_anim_mawling_%s.png" % ["side", "top"][view_index])

	# Bog King: one instance, walk phase is a material uniform, so shoot a sheet.
	for child in stage.get_children():
		if child != ground and child != camera:
			child.queue_free()
	var boss: Node3D = BOG_KING.new()
	stage.add_child(boss)
	boss.position = Vector3(40.0, 0.0, 0.0)
	boss.state = boss.State.CHASE
	boss.emerge = 1.0
	boss.refresh_pose()
	var skin: ShaderMaterial = boss.skin
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.2
	camera.position = Vector3(41.2, 3.6, 12.0)
	camera.look_at(Vector3(41.2, 2.0, 0.0), Vector3.UP)
	var frame_size := Vector2i(560, 380)
	view.size = frame_size
	var sheet := Image.create(frame_size.x * 4, frame_size.y * 2, false, Image.FORMAT_RGBA8)
	var poses := [
		[0.0, 0.0, 0.0, 0.0],
		[1.0, 0.0, 0.0, 0.0],
		[1.0, PI * 0.5, 0.0, 0.0],
		[1.0, PI, 0.0, 0.0],
		[1.0, PI * 1.5, 0.0, 0.0],
		[0.0, 0.0, 1.0, 0.8],
		[0.0, 0.0, 0.0, 1.0],
	]
	for index in poses.size():
		var pose: Array = poses[index]
		skin.set_shader_parameter("walk_amount", pose[0])
		skin.set_shader_parameter("walk_phase", pose[1])
		skin.set_shader_parameter("stomp_lift", pose[2])
		skin.set_shader_parameter("bite_amount", pose[3])
		await RenderingServer.frame_post_draw
		var image := view.get_texture().get_image()
		image.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(image, Rect2i(Vector2i.ZERO, frame_size), Vector2i((index % 4) * frame_size.x, (index / 4) * frame_size.y))
	# Last cell: front three-quarter close-up of the raised stomp foot and open jaw.
	skin.set_shader_parameter("walk_amount", 0.0)
	skin.set_shader_parameter("stomp_lift", 1.0)
	skin.set_shader_parameter("bite_amount", 0.8)
	camera.size = 3.2
	camera.position = Vector3(38.2, 2.2, 12.0)
	camera.look_at(Vector3(38.2, 1.6, 0.0), Vector3.UP)
	await RenderingServer.frame_post_draw
	var last := view.get_texture().get_image()
	last.convert(Image.FORMAT_RGBA8)
	sheet.blit_rect(last, Rect2i(Vector2i.ZERO, frame_size), Vector2i(3 * frame_size.x, frame_size.y))
	sheet.save_png("res://previews/preview_anim_boss.png")
	view.queue_free()
	await process_frame


func _game_shots() -> void:
	root.size = Vector2i(540, 960)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var world: Variant = scene.get_node("HuntWorld")
	var swarm: Variant = scene.get_node("Swarm")
	await create_timer(0.3).timeout
	Input.action_press("move_right")
	Input.action_press("move_up")
	await create_timer(0.6).timeout
	await _save("preview_anim_game.png")
	# Time the per-frame instance-uniform upload for the whole visible swarm.
	var start := Time.get_ticks_usec()
	for repeat in 20:
		for unit in swarm.units:
			var mesh: GeometryInstance3D = swarm._unit_mesh(unit)
			mesh.set_instance_shader_parameter("instance_walk", 0.5)
			mesh.set_instance_shader_parameter("instance_phase", 1.0)
	print("instance uniform upload: %.3f ms per frame for %d units" % [float(Time.get_ticks_usec() - start) / 20000.0, swarm.units.size()])
	Input.action_release("move_right")
	Input.action_release("move_up")
	var boss: Variant = world._spawn_boss(swarm.position + Vector3(-9.0, 0.0, -7.0))
	boss.state = boss.State.CHASE
	boss.remaining = 0.0
	await create_timer(0.8).timeout
	await _save("preview_anim_game_boss.png")
	Input.action_release("move_right")


func _save_view(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png("res://previews/" + file_name)


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/" + file_name)
