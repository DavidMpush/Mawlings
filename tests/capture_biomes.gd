extends SceneTree

# Review frames for the Glutsumpf look and its eruptions (run WITHOUT --headless,
# e.g. `--screen 1 --audio-driver Dummy`). Everything from the real game camera:
#   preview_biome_verdant.png / _verdant_pool.png  – reference, same spots
#   preview_biome_glut_start.png                  – Glutsumpf at the start
#   preview_biome_glut_pool.png                   – lava pool + glow channel
#   preview_biome_glut_arch.png / _stumps / _meadow – Glutsumpf landmarks
#   preview_biome_glut_overview.png               – pulled-back overview
#   preview_biome_glut_seeded.png                 – a seeded map in the Glutsumpf
#   preview_biome_eruption_warning.png            – eruption announced next to a hunter ring
#   preview_biome_eruption_burst.png              – eruption active
# HuntWorld runs its own eruptions (world.eruptions); the capture drives a separate
# instance itself so it can frame one chosen pool (world processing is off here).

const BIOMES = preload("res://scripts/biomes.gd")
const ERUPTIONS = preload("res://scripts/eruptions.gd")
const NAMES := ["arch", "stumps", "pond", "meadow"]
const CAMERA_OFFSET := Vector3(0.0, 23.0, 15.0)

var scene: Node
var world: Variant
var swarm: Variant
var arena: Variant
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
	sun = scene.get_node("Sun")
	var controls: Variant = scene.get_node("HUD/Controls")
	for connection in controls.pause_requested.get_connections():
		controls.pause_requested.disconnect(connection.callable)
	scene.set_process(false)
	world.set_process(false)
	for prey in world.prey:
		prey.visible = false
	world.model.population = 70
	swarm.set_population(70)
	var pool_spot := _pool_spot()
	# --- Verdant reference ---------------------------------------------------
	await _shot(Vector3.ZERO, "preview_biome_verdant.png", "VERDANT MAW")
	await _shot(pool_spot + Vector3(3.0, 0.0, 4.5), "preview_biome_verdant_pool.png", "VERDANT MAW · TEICH")
	# --- Glutsumpf ------------------------------------------------------------
	_biome("glutsumpf")
	await _shot(Vector3.ZERO, "preview_biome_glut_start.png", "GLUTSUMPF")
	await _shot(pool_spot + Vector3(3.0, 0.0, 4.5), "preview_biome_glut_pool.png", "GLUTSUMPF · LAVA UND GLUTRINNE")
	var marks := _landmarks()
	for type in [0, 1, 3]:
		if marks.has(type):
			var spot: Vector3 = arena.safe_spawn(marks[type].center + Vector3(0.0, 0.0, 5.5), 0.75)
			await _shot(spot, "preview_biome_glut_%s.png" % NAMES[type], "GLUTSUMPF · " + NAMES[type].to_upper())
	await _shot(pool_spot, "preview_biome_glut_overview.png", "GLUTSUMPF · ÜBERSICHT", 2.1)
	# --- Eruption next to a hunter ring -------------------------------------
	await _eruption(pool_spot)
	# --- Seeded map -----------------------------------------------------------
	arena.set_seed(4242)
	await _shot(arena.safe_spawn(Vector3(30, 0, 30), 1.0), "preview_biome_glut_seeded.png", "GLUTSUMPF · SEED 4242")
	arena.set_seed(0)
	print("Saved biome review frames")
	quit()


func _biome(id: String) -> void:
	arena.set_biome(id)
	var light: Dictionary = BIOMES.get_data(id).light
	sun.light_color = light.color
	sun.light_energy = light.energy


func _eruption(spot: Vector3) -> void:
	var eruptions: Variant = ERUPTIONS.new()
	eruptions.name = "Eruptions"
	scene.add_child(eruptions)
	eruptions.colorblind = 0
	# The swarm half overlaps the pool: the eruption rises from the lava under
	# part of the swarm, a hunter ring beside it (readability of both warnings).
	var swarm_spot: Vector3 = spot + Vector3(1.2, 0.0, 2.2)
	await _frame(swarm_spot)
	# Roll the seeded counter until the event picks this pool (review framing only).
	for attempt in 40:
		eruptions.clear()
		eruptions.count = attempt
		eruptions.erupt_soon()
		eruptions.step(1.0 / 60.0, swarm_spot, 1.0)
		if not eruptions.pending.is_empty() and (eruptions.pending[0].center as Vector3).distance_to(spot) < 0.5:
			break
	var hunter: Variant = world._spawn_hunter(swarm_spot + Vector3(-5.5, 0.0, 1.0))
	hunter.state = hunter.State.CHASE
	hunter.remaining = 0.0
	hunter.position = swarm_spot + Vector3(-2.6, 0.0, 0.8)
	hunter.step(1.0 / 60.0, swarm_spot + Vector3(-1.2, 0.0, 0.6), 1.0)
	var target := int(ERUPTIONS.WARNING_SECONDS * 0.6 * 60.0)
	for frame in target:
		eruptions.step(1.0 / 60.0, swarm_spot, 1.0)
		if frame < 40:
			hunter.step(1.0 / 60.0, swarm_spot, 1.0)
		await process_frame
	await _save("preview_biome_eruption_warning.png", "AUSBRUCH! RAUS AUS DEM GLUTKREIS")
	hunter.visible = false
	var burst := false
	for frame in 120:
		if not eruptions.step(1.0 / 60.0, swarm_spot, 1.0).is_empty():
			burst = true
		await process_frame
		if burst and frame % 1 == 0:
			for extra in 7:
				eruptions.step(1.0 / 60.0, swarm_spot, 1.0)
				await process_frame
			break
	await _save("preview_biome_eruption_burst.png", "AUSBRUCH")
	eruptions.clear()


func _shot(spot: Vector3, file_name: String, message: String, zoom := 1.0) -> void:
	await _frame(spot, zoom)
	await _save(file_name, message)


func _frame(spot: Vector3, zoom := 1.0) -> void:
	swarm.position = spot
	arena.sync(spot)
	arena.finish_rebuild()
	scene._snap_camera()
	var camera: Camera3D = scene.get_node("Camera3D")
	camera.position = spot + CAMERA_OFFSET * zoom
	camera.look_at(spot, Vector3.UP)
	for index in 20:
		await process_frame


func _save(file_name: String, message: String) -> void:
	world._update_hud(message)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/" + file_name)


# A lava pool well outside the start zone (the swarm stands beside it).
func _pool_spot() -> Vector3:
	var saved: String = arena.biome_id
	arena.set_biome("glutsumpf")
	var best := Vector3.INF
	for radius in range(1, 7):
		for x in range(-radius, radius + 1):
			for z in range(-radius, radius + 1):
				for site in arena.eruption_sites(Vector2i(x, z)):
					var point := Vector3(site.x, 0.0, site.z)
					if site.w == 0.0 and point.length() > 30.0 and point.length() < best.length():
						best = point
	arena.set_biome(saved)
	return best if best != Vector3.INF else Vector3(40, 0, 40)


func _landmarks() -> Dictionary:
	var found := {}
	for ring in 12:
		for x in range(-ring, ring + 1):
			for z in range(-ring, ring + 1):
				var mark: Dictionary = arena.landmark(Vector2i(x, z))
				if not mark.is_empty() and not found.has(mark.type):
					found[mark.type] = mark
	return found
