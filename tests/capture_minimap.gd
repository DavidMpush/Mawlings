extends SceneTree

# Review frames for the minimap stage (run WITHOUT --headless):
#   preview_minimap_verdant.png  seeded Verdant run: minimap with Bog King, nest,
#                                corpses (boss corpse), hunters and prey
#   preview_minimap_banner.png   entering a new region: banner + label
#   preview_minimap_bigmap.png   big map after a longer walk (explored chunks,
#                                fog, region names, POIs, legend)
#   preview_minimap_glut.png     Glutsumpf minimap with apex-like POIs and horde
#   preview_minimap_bigglut.png  big map in the Glutsumpf
#   preview_minimap_calm.png     calm UI skin

const SEED := 90210

var scene: Node
var world: Variant
var swarm: Variant
var controls: Variant
var arena: Variant


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	controls = scene.get_node("HUD/Controls")
	arena = scene.get_node("Arena")
	controls.pause_requested.disconnect(world.toggle_pause)
	arena.set_seed(SEED)
	world.reset_run()
	await create_timer(0.3).timeout
	_quiet()
	world.model.population = 70
	swarm.set_population(70, false)
	# 1: Verdant minimap with objectives around the swarm.
	var here: Vector3 = swarm.position
	world._spawn_boss(here + Vector3(14, 0, -18))
	world.spawn_nest(here + Vector3(-20, 0, 8))
	world.spawn_totem(here + Vector3(70, 0, 40))
	world._create_corpse(here + Vector3(9, 0, 12), 3.0, "prey")
	world._create_corpse(here + Vector3(-12, 0, -9), 3.0, "hunter")
	world._create_corpse(here + Vector3(24, 0, 20), 30.0, "boss")
	for offset in [Vector3(-8, 0, -14), Vector3(18, 0, 4)]:
		var hunter: Variant = world._spawn_hunter(here + offset)
		hunter.state = hunter.State.CHASE
	for offset in [Vector3(4, 0, -6), Vector3(-6, 0, 3), Vector3(28, 0, -10)]:
		world._spawn_prey(here + offset)
	await create_timer(1.6).timeout
	await _save("preview_minimap_verdant.png")
	# 2: walk into a new region: banner.
	_clear_threats()
	var entries: int = world.region_entries
	var target := _next_region_point()
	await _walk_to(target, 0.9)
	var waited := 0.0
	while world.region_entries == entries and waited < 2.0:
		await process_frame
		waited += 0.016
	await create_timer(0.45).timeout
	await _save("preview_minimap_banner.png")
	# 3: a longer exploration loop, then the big map.
	var loop := [Vector3(60, 0, -40), Vector3(120, 0, 10), Vector3(90, 0, 110), Vector3(-10, 0, 140), Vector3(-80, 0, 60), Vector3(-60, 0, -60), Vector3(20, 0, -90)]
	for point in loop:
		await _walk_to(point, 0.8)
	world._create_corpse(swarm.position + Vector3(40, 0, 30), 3.0, "prey")
	world.spawn_nest(swarm.position + Vector3(-60, 0, 20))
	await create_timer(0.8).timeout
	controls.set_map_open(true)
	await create_timer(1.2).timeout
	await _save("preview_minimap_bigmap.png")
	controls._map_toggled_at = -100000
	controls.set_map_open(false)
	# 4: Glutsumpf with a horde and the migration maw.
	world._set_world_biome("glutsumpf", false)
	arena.finish_rebuild()
	here = swarm.position
	world.open_portal(here + Vector3(-16, 0, -22))
	if world.horde != null and world.horde.has_method("spawn_ring"):
		world.horde.spawn_ring(here + Vector3(30, 0, 18), 40, 6.0, {})
	world._spawn_boss(here + Vector3(10, 0, 26))
	world._create_corpse(here + Vector3(-9, 0, 11), 3.0, "prey")
	world._create_corpse(here + Vector3(6, 0, -14), 30.0, "boss")
	await create_timer(1.8).timeout
	await _save("preview_minimap_glut.png")
	controls._map_toggled_at = -100000
	controls.set_map_open(true)
	await create_timer(1.2).timeout
	await _save("preview_minimap_bigglut.png")
	# 6: calm UI skin (UiStyle.skin), Glutsumpf minimap.
	controls._map_toggled_at = -100000
	controls.set_map_open(false)
	var style: Script = load("res://scripts/ui/ui_style.gd")
	style.set_skin("calm")
	await create_timer(0.8).timeout
	await _save("preview_minimap_calm.png")
	style.set_skin("organic")
	print("Saved minimap review frames (bakes %d)" % controls.get_node("hud_minimap").bakes)
	quit()


func _quiet() -> void:
	for target in world.prey:
		target.queue_free()
	world.prey.clear()
	world.spawn_clock = -1000000.0
	world.hunter_clock = 1000000.0
	world.skitter_clock = 1000000.0
	world.leaper_clock = 1000000.0
	world.boss_clock = 1000000.0
	world.elite_clock = 1000000.0
	world.nest_clock = 1000000.0
	world.flood_start = 1000000.0
	world.model.leader_invulnerable = 1000000.0


func _clear_threats() -> void:
	for list in [world.hunters, world.prey]:
		for enemy in list:
			enemy.queue_free()
		list.clear()
	if world.boss != null:
		world.boss.queue_free()
		world.boss = null


# A point a little inside the next region to the east.
func _next_region_point() -> Vector3:
	var region: Vector2i = arena.region_at(swarm.position)
	var center: Vector3 = arena.region_center(region + Vector2i(1, 0))
	return arena.safe_spawn(center - Vector3(30, 0, 0), 1.0)


# Moves the swarm in steps (the world tracks exploration every frame).
func _walk_to(target: Vector3, seconds: float) -> void:
	var start: Vector3 = swarm.position
	var steps := maxi(1, int(seconds * 60.0))
	for step in steps:
		var t := float(step + 1) / float(steps)
		var point: Vector3 = start.lerp(target, t)
		swarm.movement_vector = Vector2(target.x - start.x, target.z - start.z).normalized()
		swarm.position = point
		arena.sync(point)
		scene._snap_camera()
		await process_frame
	arena.finish_rebuild()


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + file_name)
