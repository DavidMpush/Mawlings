extends SceneTree

# Minimap stage: world -> map conversion (stage 18: the whole bounded map),
# POIs, exploration fog, region names (deterministic per seed), no region banner (Etappe 27),
# big map open/close by touch, and steering/Rally unchanged while the big map
# is open; Kokon/Pilzknolle markers prepared.

const REGION_NAMES = preload("res://scripts/region_names.gd")
const MINIMAP = preload("res://scripts/ui/hud_minimap.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	# --- Region names ---------------------------------------------------------
	var a := REGION_NAMES.name_for(123, Vector2i(2, 3), "verdant_maw")
	check(a == REGION_NAMES.name_for(123, Vector2i(2, 3), "verdant_maw"), "Region name is deterministic")
	var distinct := {}
	var too_long := 0
	var differs_by_seed := 0
	for x in range(-3, 3):
		for z in range(-3, 3):
			var name := REGION_NAMES.name_for(77, Vector2i(x, z), "verdant_maw")
			distinct[name] = true
			if name.length() > REGION_NAMES.MAX_LENGTH:
				too_long += 1
			if name != REGION_NAMES.name_for(78, Vector2i(x, z), "verdant_maw"):
				differs_by_seed += 1
			var glut := REGION_NAMES.name_for(77, Vector2i(x, z), "glutsumpf")
			if glut.length() > REGION_NAMES.MAX_LENGTH:
				too_long += 1
	check(distinct.size() >= 20, "36 regions get varied names (%d distinct)" % distinct.size())
	check(too_long == 0, "Names fit the minimap label (%d too long)" % too_long)
	check(differs_by_seed >= 25, "Another seed renames most regions (%d/36)" % differs_by_seed)
	check(REGION_NAMES.phrase_for(5, Vector2i(1, 1), "verdant_maw", []) == "", "No landmark, no phrase")

	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var world: Variant = scene.get_node("HuntWorld")
	var swarm: Variant = scene.get_node("Swarm")
	var controls: Variant = scene.get_node("HUD/Controls")
	var arena: Variant = scene.get_node("Arena")
	controls.pause_requested.disconnect(world.toggle_pause)
	var minimap: Variant = controls.get_node_or_null("hud_minimap")
	check(minimap != null and controls.minimap_enabled, "Minimap component is installed")
	if minimap == null:
		_finish()
		return
	arena.set_seed(4242)
	var first_name: String = arena.region_name(Vector2i(1, -2))
	arena.set_seed(99)
	arena.set_seed(4242)
	check(arena.region_name(Vector2i(1, -2)) == first_name, "Arena region names repeat for the same seed")
	world.reset_run()
	_quiet(world)
	world.model.leader_invulnerable = 100000.0
	await _frames(20)

	# --- World -> map (the whole map) -------------------------------------------
	var map_rect: Rect2 = minimap.minimap_rect()
	var disc: Vector2 = controls._minimap_rect().get_center()
	# Stage 18c: the start is random now - the map centre maps to the middle.
	var center: Vector2 = minimap.world_to_minimap(arena.map_center())
	check(center.distance_to(map_rect.get_center()) < 0.5, "The map centre sits in the middle of the map square")
	check(map_rect.get_center().distance_to(disc) < 1.0 and controls._minimap_rect().encloses(map_rect), "Map square inside the minimap plaque")
	var bounds: Rect2 = arena.bounds()
	var corner: Vector2 = minimap.world_to_minimap(Vector3(bounds.position.x, 0, bounds.position.y))
	var far_corner: Vector2 = minimap.world_to_minimap(Vector3(bounds.end.x, 0, bounds.end.y))
	check(corner.distance_to(map_rect.position) < 0.5 and far_corner.distance_to(map_rect.end) < 0.5, "The whole map fits the square")
	var east: Vector2 = minimap.world_to_minimap(arena.map_center() + Vector3(10, 0, 0))
	var north: Vector2 = minimap.world_to_minimap(arena.map_center() + Vector3(0, 0, -10))
	var scale: float = minimap.minimap_scale()
	check(absf(east.x - center.x - 10.0 * scale) < 0.01 and absf(east.y - center.y) < 0.01, "East is right")
	check(absf(north.y - center.y + 10.0 * scale) < 0.01 and absf(north.x - center.x) < 0.01, "North is up")
	check(minimap.bakes > 0, "Chunks were baked (%d)" % minimap.bakes)
	var image: Image = minimap.bake_chunk(Vector2i(3, 1), 0)
	check(image.get_width() == MINIMAP.CHUNK_PX and image.get_height() == MINIMAP.CHUNK_PX, "Chunk bake size")

	# --- POIs and rim arrows ---------------------------------------------------
	var here: Vector3 = swarm.position
	world.spawn_nest(here + Vector3(15, 0, 0))
	world._spawn_boss(here + Vector3(0, 0, -120))
	var loot_at: Vector3 = here + Vector3(-8, 0, 6)
	world.loot.drop(0, 3.0, loot_at, loot_at, false)
	world._spawn_hunter(here + Vector3(6, 0, 6))
	world._map_clock = 0.0
	await _frames(12)
	var marks: Array = minimap.markers()
	var nest := _find(marks, MINIMAP.Mark.NEST)
	var boss := _find(marks, MINIMAP.Mark.BOSS)
	check(not nest.is_empty() and not nest[2], "Nest inside the minimap")
	if not nest.is_empty():
		var expected: Vector2 = minimap.world_to_minimap(world.nest.position)
		check(nest[1].distance_to(expected) < 4.0, "Nest marker at its map position (%s vs %s)" % [nest[1], expected])
	check(not boss.is_empty() and not boss[2], "Far Bog King on the whole map")
	if not boss.is_empty():
		check(boss[1].distance_to(minimap.world_to_minimap(world.boss.position)) < 4.0 and boss[1].y < center.y - 100.0 * scale, "Bog King marker far north")
	check(not _find(marks, MINIMAP.Mark.CORPSE).is_empty(), "Corpse drop on the minimap")
	check(not _find(marks, MINIMAP.Mark.HUNTER).is_empty(), "Hunter dot on the minimap")
	# Second wave: Kokons (chests) and Pilzknollen (power-ups) have marker kinds.
	var injected: Dictionary = (controls.get_meta("map") as Dictionary).duplicate()
	injected["chests"] = PackedVector3Array([here + Vector3(20, 0, 10)])
	injected["powerups"] = PackedVector3Array([here + Vector3(-20, 0, 10)])
	minimap._state = injected
	minimap._collect_markers()
	var future: Array = minimap.markers()
	check(not _find(future, MINIMAP.Mark.CHEST).is_empty() and not _find(future, MINIMAP.Mark.POWERUP).is_empty(), "Kokon and Pilzknolle markers")
	check(minimap._legend().size() == MINIMAP.LEGEND.size() + 2, "Legend grows by Kokon and Pilzknolle")
	world.boss.queue_free()
	world.boss = null

	# --- Exploration grows ------------------------------------------------------
	var explored_before: int = world.explored.size()
	var version_before: int = world.explored_version
	check(explored_before > 0, "Start area is explored (%d chunks)" % explored_before)
	var entries_before: int = world.region_entries
	var target: Vector3 = arena.region_center(arena.region_at(here) + Vector2i(1, 0))
	for step in 60:
		swarm.position = here.lerp(target, float(step + 1) / 60.0)
		await process_frame
	await _frames(4)
	check(world.explored.size() > explored_before and world.explored_version > version_before, "Exploration grows (%d -> %d)" % [explored_before, world.explored.size()])
	check(arena.explored_regions().size() >= 2 and minimap._fog_tex != null, "Arena fog follows (%d regions)" % arena.explored_regions().size())
	check(world.region_entries > entries_before, "A new region was entered")
	check(int(world.run_stats().get("regions_visited", 0)) >= 2, "RunStats count regions")
	check(String(world.region_name) == String(arena.region_name(arena.region_at(swarm.position))), "Current region name follows the swarm")
	# Etappe 27 (S25 feedback): entering a region shows no name banner any more.
	for frame in 30:
		await process_frame
		check(minimap.banner_time() < 0.0, "No region banner on entering a region")
		if minimap.banner_time() >= 0.0:
			break

	# --- Big map by touch --------------------------------------------------------
	controls._map_toggled_at = -100000
	_touch(controls, 3, controls._minimap_rect().get_center(), true)
	_touch(controls, 3, controls._minimap_rect().get_center(), false)
	check(controls.map_open, "Tapping the minimap opens the big map")
	# The emulated mouse click of the same tap must not close it again.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = controls._minimap_rect().get_center()
	click.pressed = true
	controls._input(click)
	click.pressed = false
	controls._input(click)
	check(controls.map_open, "Duplicate click of the same tap is ignored")
	await _frames(4)
	check(minimap.get_node("BigMap").visible, "Big map layer visible")
	check(minimap._big_tex != null, "Big map composed its terrain")
	check(minimap.minimap_rect().size.x > 0.0 and minimap.world_to_bigmap(Vector3.ZERO).distance_to(minimap._big_rect_px.get_center()) < 1.0, "Big map shows the whole map")
	check(not minimap._big_labels.is_empty(), "Big map names the explored regions")
	# Steering and Rally stay active while the big map is open.
	var move_center: Vector2 = controls._movement_center()
	_touch(controls, 1, move_center, true)
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = move_center + Vector2(66.0, 0.0)
	controls._input(drag)
	_touch(controls, 2, controls._rally_center(), true)
	check(controls.movement_vector.x > 0.9 and controls.rally_pressed, "Movement and Rally work with the big map open")
	check(controls.map_open, "Steering does not close the big map")
	_touch(controls, 1, move_center, false)
	_touch(controls, 2, controls._rally_center(), false)
	check(controls.movement_vector == Vector2.ZERO and not controls.rally_pressed, "Releases still work")
	controls._map_toggled_at = -100000
	_touch(controls, 4, controls._map_close_rect().get_center(), true)
	check(not controls.map_open, "X closes the big map")
	controls._map_toggled_at = -100000
	_touch(controls, 5, controls._minimap_rect().get_center(), true)
	controls._map_toggled_at = -100000
	_touch(controls, 6, controls._minimap_rect().get_center(), true)
	check(not controls.map_open, "Second tap on the map spot closes it")
	await _frames(2)
	check(not minimap.get_node("BigMap").visible, "Big map layer hidden again")
	# Pause hides the big map.
	controls._map_toggled_at = -100000
	controls.set_map_open(true)
	world.toggle_pause()
	await _frames(2)
	check(not minimap.get_node("BigMap").visible, "Big map hidden while paused")
	world.toggle_pause()
	_finish()


func _find(marks: Array, kind: int) -> Array:
	for entry in marks:
		if int(entry[0]) == kind:
			return entry
	return []


func _touch(controls: Variant, index: int, at: Vector2, pressed: bool) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = index
	touch.position = at
	touch.pressed = pressed
	controls._input(touch)


func _frames(count: int) -> void:
	for index in count:
		await process_frame


func _quiet(world: Variant) -> void:
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


func _finish() -> void:
	if failures > 0:
		print("MINIMAP FAILED: %d" % failures)
		quit(1)
		return
	print("PASS: minimap whole-map conversion, POIs, Kokon/Pilzknolle kinds, exploration fog, region names, no region banner, big map input")
	quit(0)
