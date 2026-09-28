extends SceneTree

# Ash Toad model review (run WITHOUT --headless, e.g. --screen 1 --audio-driver Dummy):
# 1. the bare AshToad_game.glb from the side with a red marker on local +Z (head
#    must point at it, feet on the grey ground line y = 0);
# 2. the Aschenkröte (scripts/apex_toad.gd) from the side in its animation states:
#    rest, leap crouch, take-off, mid-air, landing squash, spit, tongue, exhausted,
#    phase-2 roar. Frames: preview_ash_toad_model_*.png in the project root.

const TOAD = preload("res://scripts/apex_toad.gd")
const MODEL = preload("res://assets/gameplay/characters/AshToad_game.glb")

var stage: Node3D
var camera: Camera3D


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	stage = Node3D.new()
	root.add_child(stage)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	stage.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("c9c2b4")
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.6
	stage.add_child(environment)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color("8f877a")
	ground.material_override = grey
	stage.add_child(ground)
	camera = Camera3D.new()
	stage.add_child(camera)
	camera.current = true

	# 1. Raw model, +Z marker.
	var raw := MODEL.instantiate() as Node3D
	stage.add_child(raw)
	var painted := StandardMaterial3D.new()
	painted.vertex_color_use_as_albedo = true
	for mesh in raw.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_override = painted
	var marker := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.05
	ball.height = 0.1
	marker.mesh = ball
	var red := StandardMaterial3D.new()
	red.albedo_color = Color.RED
	marker.material_override = red
	marker.position = Vector3(0, 0.1, 0.75)
	stage.add_child(marker)
	camera.look_at_from_position(Vector3(2.4, 0.6, 0.1), Vector3(0, 0.25, 0.1))
	await _save("preview_ash_toad_model_raw_side.png")
	camera.look_at_from_position(Vector3(0.1, 2.6, 0.1), Vector3(0, 0, 0.05), Vector3(0, 0, 1))
	await _save("preview_ash_toad_model_raw_top.png")
	raw.free()
	marker.free()

	# 2. The boss in its states; body faces -X, camera on +Z looks at its left flank.
	var toad: Variant = TOAD.new()
	stage.add_child(toad)
	toad.step(TOAD.ARRIVE_SECONDS + 0.1, Vector3(-30, 0, 0), 1.0)
	toad.cooldown = 999.0
	camera.look_at_from_position(Vector3(-3.0, 5.0, 30.0), Vector3(-3.0, 3.0, 0))
	await _pose(toad, 0.5)
	await _save("preview_ash_toad_model_rest.png")
	# Aschensprung towards -X (13 m).
	toad.begin_attack(TOAD.Pattern.LEAP, Vector3(-13, 0, 0), 1.0)
	await _windup(toad, TOAD.LEAP_CROUCH * 0.95)
	await _save("preview_ash_toad_model_crouch.png")
	await _windup(toad, TOAD.LEAP_CROUCH + 0.1)
	await _save("preview_ash_toad_model_takeoff.png")
	await _windup(toad, 0.72)
	await _save("preview_ash_toad_model_air.png")
	await _windup(toad, 2.0)
	await _pose(toad, 0.06)
	await _save("preview_ash_toad_model_landing.png")
	await _reset(toad)
	toad.begin_attack(TOAD.Pattern.SPIT, toad.position + Vector3(-12, 0, 0), 1.0)
	await _windup(toad, 0.8)
	await _save("preview_ash_toad_model_spit.png")
	await _reset(toad)
	toad.begin_attack(TOAD.Pattern.TONGUE, toad.position + Vector3(-8, 0, 0), 1.0)
	await _windup(toad, 0.9)
	await _save("preview_ash_toad_model_tongue.png")
	await _windup(toad, 2.0)
	await _pose(toad, 0.2)
	await _save("preview_ash_toad_model_tongue_strike.png")
	await _reset(toad)
	toad.state = TOAD.State.EXHAUSTED
	toad.remaining = 99.0
	await _pose(toad, 0.8)
	await _save("preview_ash_toad_model_exhausted.png")
	toad.state = TOAD.State.CHASE
	toad.health = toad.max_health * 0.4
	toad.step(1.0 / 60.0, toad.position + Vector3(-5, 0, 0), 1.0)
	await _pose(toad, TOAD.PHASE_SHIFT_SECONDS * 0.5)
	await _save("preview_ash_toad_model_phase2.png")
	print("Saved Ash Toad model frames")
	quit()


func _windup(toad: Variant, share: float) -> void:
	var target: Vector3 = toad.attack_center
	while toad.state == TOAD.State.WINDUP and toad.windup_progress() < share:
		toad.step(1.0 / 60.0, target, 1.0)
		await process_frame


func _pose(toad: Variant, seconds: float) -> void:
	for i in int(seconds * 60.0):
		toad.cooldown = 999.0
		toad.step(1.0 / 60.0, toad.position + Vector3(-5, 0, 0), 1.0)
		await process_frame


func _reset(toad: Variant) -> void:
	toad.state = TOAD.State.CHASE
	toad.cooldown = 999.0
	toad.position = Vector3.ZERO
	toad.rotation.y = 0.0
	toad.refresh_pose()
	await _pose(toad, 0.6)


func _save(file_name: String) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/" + file_name)
