extends SceneTree

# Close-up orientation check of the raw Nibbler model: a red marker stands at +Z,
# a blue marker at +X. Output: preview_nibbler_axes.png (side view from +X).
# Also renders the in-game prey node close up: preview_nibbler_prey.png.

const NIBBLER = preload("res://assets/gameplay/characters/Nibbler_game.glb")
const PREY = preload("res://scripts/prey.gd")


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 540)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("8a8a84")
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.9, 0.6, 0.0)
	stage.add_child(light)
	var model: Node3D = NIBBLER.instantiate()
	stage.add_child(model)
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		print("Mesh ", mesh.name, " aabb ", mesh.get_aabb(), " xform ", mesh.transform)
	_marker(stage, Vector3(0, 0, 0.9), Color.RED)
	_marker(stage, Vector3(0.9, 0, 0), Color.BLUE)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(3.2, 0.9, 0.0)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	for frame in 4:
		await process_frame
	await _save("preview_nibbler_axes.png")
	model.queue_free()
	var prey: Node3D = PREY.new()
	prey.set("health", 5.0)
	stage.add_child(prey)
	camera.position = Vector3(2.4, 2.2, 2.4)
	camera.look_at(Vector3(0, 0.4, 0))
	for frame in 4:
		await process_frame
	await _save("preview_nibbler_prey.png")
	quit(0)


func _marker(parent: Node3D, location: Vector3, color: Color) -> void:
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.15, 0.15, 0.15)
	box.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material_override = material
	box.position = location
	parent.add_child(box)


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + file_name)
	print("Saved ", file_name)
