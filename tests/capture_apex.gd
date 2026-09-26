extends SceneTree

# Review frames for the stage 07 APEX building blocks (run WITHOUT --headless):
# Moosschlund patterns in Verdant Maw and Glutsumpf plus a Glutsumpf overview.
# The apex is not wired into HuntWorld yet, so it is placed by hand; the camera
# uses the pulled-back boss framing HuntWorld would use in stage 08.

const APEX = preload("res://scripts/apex_boss.gd")
const BIOMES = preload("res://scripts/biomes.gd")
const CAMERA_OFFSET := Vector3(0, 23, 15)
const APEX_ZOOM := 1.38

var scene: Node
var world: Variant
var swarm: Variant
var arena: Variant
var camera: Camera3D
var sun: DirectionalLight3D


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
	sun = scene.get_node("Sun")
	# Background capture windows lose focus; the auto-pause must not end up in the frames.
	var controls: Variant = scene.get_node("HUD/Controls")
	if controls.pause_requested.is_connected(world.toggle_pause):
		controls.pause_requested.disconnect(world.toggle_pause)
	scene.set_process(false)
	world.set_process(false)
	for prey in world.prey:
		prey.visible = false
	world.model.population = 120
	swarm.set_population(120)
	await _settle(0.6)
	# --- Verdant Maw ---------------------------------------------------------
	var boss: Variant = await _spawn_apex(Vector3(0, 0, -8.5))
	await _save("preview_apex_verdant.png", "DER MOOSSCHLUND ERWACHT")
	await _windup(boss, APEX.Pattern.ROOTS, 0.7)
	await _save("preview_apex_roots.png", boss.hud_message())
	await _finish(boss)
	boss.position = Vector3(0, 0, -6.0)
	await _windup(boss, APEX.Pattern.SPORES, 0.65)
	await _save("preview_apex_spores.png", boss.hud_message())
	await _finish(boss)
	boss.position = Vector3(0, 0, -7.5)
	await _windup(boss, APEX.Pattern.QUAKE, 0.6)
	await _save("preview_apex_quake.png", boss.hud_message())
	await _finish(boss)
	await _advance(boss, 0.8, Vector3(0, 0, 0))
	await _save("preview_apex_exhausted.png", boss.hud_message())
	boss.queue_free()
	await process_frame
	# --- Glutsumpf -----------------------------------------------------------
	arena.set_biome("glutsumpf")
	var light: Dictionary = BIOMES.get_data("glutsumpf").light
	sun.light_color = light.color
	sun.light_energy = light.energy
	_frame(Vector3.ZERO, 1.0)
	await _settle(1.2)
	await _save("preview_apex_glutsumpf.png", "GLUTSUMPF")
	# A second view with a lava pool / landmark nearby.
	var spot := _find_pool_spot()
	swarm.position = spot
	arena.sync(spot)
	_frame(spot, 1.15)
	await _settle(0.5)
	await _save("preview_apex_glutsumpf_pools.png", "GLUTSUMPF · GLUTRINNEN UND GLUTPFÜTZEN")
	swarm.position = Vector3.ZERO
	arena.sync(Vector3.ZERO)
	await _settle(0.3)
	boss = await _spawn_apex(Vector3(0, 0, -7.5))
	await _windup(boss, APEX.Pattern.QUAKE, 0.6)
	await _save("preview_apex_glut_quake.png", boss.hud_message())
	await _finish(boss)
	boss.health = boss.max_health * 0.4
	await _advance(boss, APEX.PHASE_SHIFT_SECONDS + 0.2, Vector3(0, 0, 3))
	boss.position = Vector3(0, 0, -8.0)
	await _windup(boss, APEX.Pattern.ROOTS, 0.75)
	await _save("preview_apex_glut_roots_phase2.png", "PHASE 2 · " + boss.hud_message())
	await _finish(boss)
	boss.position = Vector3(0, 0, -6.0)
	await _windup(boss, APEX.Pattern.SPORES, 0.7)
	await _save("preview_apex_glut_spores.png", boss.hud_message())
	print("Saved apex review frames")
	quit()


func _spawn_apex(location: Vector3) -> Variant:
	var boss: Variant = APEX.new()
	boss.name = "Moosschlund"
	boss.position = location
	world.add_child(boss)
	boss.state = APEX.State.CHASE
	boss.cooldown = 999.0
	boss.remaining = 0.0
	var facing: Vector3 = swarm.position - boss.position
	boss.rotation.y = atan2(facing.x, facing.z) + PI * 0.5
	boss.refresh_pose()
	_frame(swarm.position, APEX_ZOOM)
	await _settle(0.3)
	return boss


func _windup(boss: Variant, pattern: int, share: float) -> void:
	boss.state = APEX.State.CHASE
	boss.begin_attack(pattern, swarm.position, 1.0)
	var total: float = boss.remaining
	while boss.remaining > total * (1.0 - share):
		boss.step(1.0 / 60.0, swarm.position, 1.0)
		await process_frame


# Resolves the wind-up with the swarm out of the area (visual only).
func _finish(boss: Variant) -> void:
	while boss.state == APEX.State.WINDUP:
		boss.step(1.0 / 60.0, Vector3(0, 0, 40), 1.0)
	for i in 40:
		boss.step(1.0 / 60.0, Vector3(0, 0, 40), 1.0)
		await process_frame
	boss.cooldown = 999.0
	# Let the strike rings fade so frames show one pattern at a time.
	await _settle(0.9)


func _advance(boss: Variant, seconds: float, target: Vector3) -> void:
	var steps := int(seconds * 60.0)
	for i in steps:
		boss.step(1.0 / 60.0, target, 1.0)
		await process_frame


func _frame(target: Vector3, zoom: float) -> void:
	camera.position = target + CAMERA_OFFSET * zoom
	camera.look_at(target, Vector3.UP)


func _settle(seconds: float) -> void:
	await create_timer(seconds).timeout


# First chunk near the start that shows a lava pool (walkable decoration).
func _find_pool_spot() -> Vector3:
	for radius in range(1, 6):
		for x in range(-radius, radius + 1):
			for z in range(-radius, radius + 1):
				var key := Vector2i(x, z)
				if arena._hash(key.x, key.y, 13) % int(arena.biome.pond_one_in) == 0 and not arena.near_landmark(Vector3(key.x * arena.CELL + 4, 0, key.y * arena.CELL + 22), 3.0):
					return Vector3(key.x * arena.CELL + 6.0, 0, key.y * arena.CELL + 19.0)
	return Vector3(10, 0, 11)


func _save(file_name: String, message: String) -> void:
	world._update_hud(message)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + file_name)
