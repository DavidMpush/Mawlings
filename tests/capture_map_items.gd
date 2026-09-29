extends SceneTree

# Etappe 31 D: Glutpilze and instant map items from the real game camera.
# Run WITHOUT --headless (frame_post_draw), with --screen 1 --audio-driver Dummy.
# Result: previews/preview_map_items_*.png (900 x 1600).
#   baskets     two Glutpilze beside the swarm
#   items       Heilpilz, Zeitstarre, Bildschirm-Biss and a Lockruf lying in the world
#   pop         an item popping out of a broken basket
#   freeze      Zeitstarre: frozen hunters/skitters/brood, ice tint and band
#   bite        Bildschirm-Biss the moment it is taken (rings, band)

const DT := 1.0 / 60.0

var scene: Node
var world: Node3D
var swarm: Node3D
var arena: Node3D
var items: Node3D
var origin := Vector3.ZERO
var only := ""


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	for raw in OS.get_cmdline_user_args():
		only = String(raw).trim_prefix("--")
	root.size = Vector2i(900, 1600)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	arena = scene.get_node("Arena")
	var controls: Node = scene.get_node("HUD/Controls")
	if controls.pause_requested.is_connected(world.toggle_pause):
		controls.pause_requested.disconnect(world.toggle_pause)
	arena.set_seed(424242)
	world.reset_run()
	_population(36)
	for i in 30:
		await process_frame
	if world.paused:
		world.toggle_pause()
	scene.set_process(false)
	world.set_process(false)
	_quiet()
	items = world.map_items
	origin = swarm.position
	await _run(0.3)

	if _want("baskets"):
		_place([origin + Vector3(-4.5, 0, -6.0), origin + Vector3(4.8, 0, -2.5)])
		await _run(0.5)
		await _save("baskets")

	if _want("items"):
		_place([origin + Vector3(-5.0, 0, 5.5)])
		items.spawn_item("heilpilz", origin + Vector3(-3.8, 0, -5.5))
		items.spawn_item("zeitstarre", origin + Vector3(0.6, 0, -7.0))
		items.spawn_item("bildschirmbiss", origin + Vector3(4.6, 0, -4.8))
		world.drop_lure(origin + Vector3(7.0, 0, 3.5))
		await _run(1.2)
		await _save("items")
		_clear_items()

	if _want("pop"):
		_place([origin + Vector3(0.5, 0, -5.0)])
		await _run(0.2)
		items.break_mushroom(0, "zeitstarre")
		await _run(0.2)
		await _save("pop")
		_clear_items()

	if _want("freeze"):
		_place([])
		for offset in [Vector3(6, 0, -3), Vector3(-5, 0, -6), Vector3(3, 0, 6)]:
			world._spawn_hunter(arena.safe_spawn(origin + offset, 1.0))
		world._spawn_skitter(arena.safe_spawn(origin + Vector3(-6, 0, 3), 1.0))
		world.horde.spawn_ring(origin, 26, 8.0, world.flood_stats())
		await _run(1.6)
		items.collect("zeitstarre")
		await _run(0.35)
		await _save("freeze")
		await _run(5.0)
		_clear_enemies()

	if _want("bite"):
		for offset in [Vector3(7, 0, -5), Vector3(-6, 0, -7), Vector3(5, 0, 7)]:
			world._spawn_hunter(arena.safe_spawn(origin + offset, 1.0))
		world.horde.spawn_ring(origin, 26, 9.0, world.flood_stats())
		await _run(1.0)
		items.collect("bildschirmbiss")
		await _run(0.25)
		await _save("bite")
		_clear_enemies()
	quit()


# Moves the first baskets to `points` (the rest far away) and redraws them.
func _place(points: Array) -> void:
	for index in items.mushrooms.size():
		var mushroom: Dictionary = items.mushrooms[index]
		mushroom.alive = true
		mushroom.at = points[index] if index < points.size() else Vector3(4000, 0, 4000 + index * 10)
	for view in items._views:
		view.queue_free()
	items._views.clear()
	items._build_views()


func _clear_items() -> void:
	for entry in items.items:
		entry.node.queue_free()
	items.items.clear()
	world.collect_loot_now()


func _clear_enemies() -> void:
	for group in [world.hunters, world.skitters, world.leapers]:
		for enemy in group:
			enemy.queue_free()
		group.clear()
	if world.horde != null:
		world.horde.clear()
	world.freeze_left = 0.0


func _want(key: String) -> bool:
	return only == "" or key.begins_with(only) or only.begins_with(key)


func _population(count: int) -> void:
	world.model.population = count
	swarm.set_population(count, false)
	world.unit_points_valid = false


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
	world.surge_next = 1000000.0
	world.apex_state = 4
	world.totem_offered = true
	for entry in world.chests.cocoons:
		entry.node.position = Vector3(900, 0, 900)
		entry.at = Vector3(900, 0, 900)
	for entry in world.shrines.shrines:
		entry.node.position = Vector3(-900, 0, 900)
		entry.at = Vector3(-900, 0, 900)


# Advances the world (and draws) for `seconds`, keeping the swarm in place.
func _run(seconds: float) -> void:
	for i in int(round(seconds / DT)):
		swarm.position = origin
		world.unit_points_valid = false
		world.step(DT)
		while not world.evolution.offers.is_empty():
			world.choose_mutation(0)
		await process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/preview_map_items_%s.png" % name)
