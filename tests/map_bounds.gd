extends SceneTree

# Stage 18: the bounded map. Swarm, animals and every enemy stay inside the
# playable area even while the swarm pushes into the edge for a long time;
# every spawn (enemies, flood ring, apex, maw, objectives, eruptions) lies
# inside; a migration lands inside on a new map of the same size; spawn_points(4)
# are far apart; the same seed builds the same map; unique region names; the
# minimap overview and the exploration fog API.

const TUNING = preload("res://scripts/tuning.gd")
const DT := 1.0 / 60.0
const SEED := 4242
var failures: Array[String] = []
var scene: Node
var world: Variant
var swarm: Variant
var arena: Variant
var worst_escape := 0.0


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)


func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	arena = scene.get_node("Arena")
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)
	_check_geometry()
	_check_layout_edges()
	_check_edge_runs()
	_check_spawns()
	_check_spawn_points()
	_check_migration()
	await _check_determinism()
	_check_overview()
	scene.queue_free()
	await process_frame
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS map_bounds: 336 m map, 4 edge runs (swarm/animals/enemies/horde inside, worst %.3f m), spawns inside (ring, flood, apex, maw, nest, totem, eruptions), migration lands inside on a new map, spawn_points(4) far apart, same seed same map, 16 unique names, overview + fog" % worst_escape)
	quit(0)


func _fresh(seed_value: int) -> void:
	world.config = {"seed": seed_value}
	arena.set_seed(seed_value)
	world.reset_run()
	world.model.population = 60
	swarm.set_population(60, false)
	world.model.elapsed = 200.0
	world.hunters_unlocked = true
	world.apex_state = 4
	world.model.leader_invulnerable = 1.0e9
	arena.sync(swarm.position)


func _check_geometry() -> void:
	var bounds: Rect2 = arena.bounds()
	var playable: Rect2 = arena.playable_rect()
	_check(is_equal_approx(bounds.size.x, 336.0) and is_equal_approx(bounds.size.y, 336.0), "Solo map is 336 x 336 m (%s)" % bounds)
	_check(bounds.get_center().is_equal_approx(Vector2.ZERO) and arena.map_center().is_equal_approx(Vector3.ZERO), "Solo map centred on the origin")
	_check(bounds.encloses(playable) and playable.size.x > 320.0, "Playable area inside the bounds (%s)" % playable)
	_check(arena.is_inside(Vector3.ZERO, 10.0) and not arena.is_inside(Vector3(400, 0, 0)), "is_inside")
	var clamped: Vector3 = arena.clamp_inside(Vector3(900, 0, -900), 2.0)
	_check(arena.is_inside(clamped, 1.99), "clamp_inside")
	var folded: Vector3 = arena.fold_inside(Vector3(playable.end.x + 5.0, 0, 0), 0.0)
	_check(absf(folded.x - (playable.end.x - 5.0)) < 0.001, "fold_inside mirrors at the edge (%.2f)" % folded.x)
	_check(not arena.is_open(Vector3(playable.end.x + 1.0, 0, 0), 0.5), "The edge is not open ground")
	_check(arena.regions_for_players(1) == 4 and arena.regions_for_players(2) == 5 and arena.regions_for_players(3) == 6 and arena.regions_for_players(4) == 6, "Map size per player count 4/5/6/6")


# Stones keep a passage to the wall, landmarks stay away from it, trails stay in.
func _check_layout_edges() -> void:
	for seed_value in [SEED, 777, 90210]:
		arena.set_seed(seed_value)
		var range_rect: Rect2i = arena.map_overview().chunk_range
		for x in range(range_rect.position.x - 1, range_rect.end.x + 1):
			for z in range(range_rect.position.y - 1, range_rect.end.y + 1):
				var key := Vector2i(x, z)
				for circle in arena.obstacles(key):
					_check(arena.is_inside(Vector3(circle.x, 0, circle.z), circle.w + arena.EDGE_STONE_GAP - 0.01), "Stone keeps a passage to the edge at %s (seed %d)" % [key, seed_value])
				var mark: Dictionary = arena.landmark(key)
				if not mark.is_empty():
					_check(arena.is_inside(mark.center, arena.LANDMARK_FOOTPRINT[int(mark.type)] + arena.EDGE_LANDMARK_GAP - 0.01), "Landmark away from the edge at %s (seed %d)" % [key, seed_value])
				for point in arena.trail_samples(key):
					_check(arena.bounds().has_point(Vector2(point.x, point.z)), "Trail inside the map at %s (seed %d)" % [key, seed_value])
				for site in arena.eruption_sites(key):
					_check(arena.is_inside(Vector3(site.x, 0, site.z), 2.0), "Eruption source inside at %s (seed %d)" % [key, seed_value])
		_check(not arena.in_map(Vector2i(range_rect.end.x, 0)) and arena.obstacles(Vector2i(range_rect.end.x, 0)).is_empty(), "Border chunks carry no gameplay (seed %d)" % seed_value)


# The swarm pushes into each edge (and slides along it) while enemies hunt it.
# Stage 18b: on a seeded map the edge lies behind the walls (map_layout.gd
# checks the walls), so the edge runs use the open classic map (seed 0).
func _check_edge_runs() -> void:
	_fresh(0)
	var playable: Rect2 = arena.playable_rect()
	var runs := [
		[Vector3(20, 0, playable.position.y + 20.0), Vector2(0.35, -1.0)],
		[Vector3(playable.end.x - 20.0, 0, -30), Vector2(1.0, 0.3)],
		[Vector3(-40, 0, playable.end.y - 20.0), Vector2(-0.3, 1.0)],
		[Vector3(playable.position.x + 20.0, 0, playable.position.y + 20.0), Vector2(-1.0, -1.0)],
	]
	for run in runs:
		swarm.position = arena.safe_spawn(run[0], 1.0)
		arena.sync(swarm.position)
		var direction: Vector2 = (run[1] as Vector2).normalized()
		var start: Vector3 = swarm.position
		for step in 900:
			if world.choosing():
				world.choose_mutation(0)
			swarm.set_controls(direction, step % 180 > 150)
			swarm._process(DT)
			world.step(DT)
			arena.sync(swarm.position)
			if step % 3 == 0:
				_check_inside_all("run %s" % [run[1]])
		# Sliding: the swarm moved along the wall instead of sticking.
		var along: float = absf(swarm.position.x - start.x) if absf(direction.x) < absf(direction.y) else absf(swarm.position.z - start.z)
		if absf(direction.x) > 0.2 and absf(direction.y) > 0.2 and absf(absf(direction.x) - absf(direction.y)) > 0.1:
			_check(along > 20.0, "Swarm slides along the edge (%.1f m, %s)" % [along, run[1]])
		# (The diagonal corner run may rest against a stone; the straight runs reach the wall.)
		if absf(absf(direction.x) - absf(direction.y)) > 0.1:
			_check(arena.edge_distance(swarm.position) > -3.0, "Swarm reached the edge (%.1f m, %s)" % [arena.edge_distance(swarm.position), run[1]])
	# A flood wave at the edge: the ring folds inwards, everyone stays inside.
	var wanted: int = world.flood_wave_count()
	for wave in 3:
		world._spawn_flood_wave()
	var horde: Variant = world.horde
	var spawned: int = horde.count() if horde != null else 0
	_check(spawned >= int(0.9 * 3 * wanted), "Flood waves at the edge still spawn in full (%d of %d)" % [spawned, 3 * wanted])
	for step in 240:
		swarm.set_controls(Vector2(-1, -1).normalized(), false)
		swarm._process(DT)
		world.step(DT)
		if step % 4 == 0:
			_check_inside_all("flood")


func _check_inside_all(label: String) -> void:
	var playable: Rect2 = arena.playable_rect()
	var bounds: Rect2 = arena.bounds()
	_escape(swarm.position, playable.grow(-0.749), "swarm " + label)
	for point in swarm.unit_world_points():
		_escape(point, playable.grow(0.01), "animal " + label)
	for group in [world.prey, world.hunters, world.skitters, world.leapers]:
		for enemy in group:
			if is_instance_valid(enemy):
				_escape(enemy.position, playable.grow(0.01), "enemy " + label)
	if world.boss != null and is_instance_valid(world.boss):
		_escape(world.boss.position, playable.grow(0.01), "boss " + label)
	if world.horde != null:
		for point in world.horde.positions():
			_escape(point, playable.grow(0.01), "horde " + label)
	_check(bounds.encloses(playable), "bounds")


func _escape(point: Vector3, area: Rect2, label: String) -> void:
	var dx := maxf(area.position.x - point.x, point.x - area.end.x)
	var dz := maxf(area.position.y - point.z, point.z - area.end.y)
	var out := maxf(dx, dz)
	if out > 0.0:
		worst_escape = maxf(worst_escape, out)
		if failures.size() < 30:
			failures.append("%s left the map by %.3f m at %s" % [label, out, point])


func _check_spawns() -> void:
	_check_layout_spawns()
	# Corner spawns on the open classic map (seed 0); on a seeded map the corners are wall.
	_fresh(0)
	var playable: Rect2 = arena.playable_rect()
	# The swarm stands in each corner; every ring spawn lies inside, not stacked on the edge.
	for corner in [Vector3(playable.position.x + 2.0, 0, playable.position.y + 2.0), Vector3(playable.end.x - 2.0, 0, playable.end.y - 2.0)]:
		swarm.position = corner
		arena.sync(corner)
		for radius in [7.0, 8.0, 9.0, 10.0, 11.0]:
			for repeat in 8:
				var spot: Vector3 = world._spawn_position(radius)
				_check(arena.is_inside(spot, 0.89), "Enemy spawn inside (%s)" % spot)
				_check(spot.distance_to(corner) > 4.0, "Mirrored spawn keeps distance (%.1f m)" % spot.distance_to(corner))
		world.apex_state = 0
		world.begin_apex_warning()
		_check(arena.is_inside(world.apex_spot, TUNING.APEX_BODY_RADIUS), "Apex spot inside with room (%s)" % world.apex_spot)
		_check(world.apex_spot.distance_to(corner) > 6.0, "Apex spot not on top of the swarm")
		world.apex_state = 4
		world._apex_defeated(corner + Vector3(3, 0, 3) * signf(-corner.x))
		_check(arena.is_inside(world.portal_point, TUNING.MIGRATION_RADIUS), "Migration maw inside (%s)" % world.portal_point)
		world.apex_state = 4
		world.portal_clock = -1.0
		for repeat in 6:
			var nest_spot: Vector3 = world._objective_position(4.0, [])
			_check(arena.is_inside(nest_spot, 3.0), "Objective inside (%s)" % nest_spot)
	# Eruptions in the Glutsumpf near the edge.
	arena.set_biome("glutsumpf")
	for key in [Vector2i(-6, -6), Vector2i(5, 5), Vector2i(0, -6), Vector2i(5, 0)]:
		for site in arena.eruption_sites(key):
			_check(arena.is_inside(Vector3(site.x, 0, site.z), 2.0), "Glutsumpf eruption site inside")
	arena.set_biome("verdant_maw")


# Stage 18b: on the path map every spawn is open ground - enemies around the
# swarm in a clearing near the edge, apex in the boss arena, the Schlund in its
# clearing, nests and totems in theirs.
func _check_layout_spawns() -> void:
	_fresh(SEED)
	var maw_spot: Vector3 = arena.poi_slots("maw")[0]
	swarm.position = maw_spot
	arena.finish_flow(swarm.position)
	for radius in [7.0, 8.0, 9.0, 10.0, 11.0]:
		for repeat in 6:
			var spot: Vector3 = world._spawn_position(radius)
			_check(arena.is_open(spot, 0.85) and arena.is_inside(spot, 0.89), "Path map: enemy spawn on open ground (%s)" % spot)
			_check(arena.flow_distance(spot) < radius * 2.6 + 16.0, "Path map: enemy spawn not behind a wall (%.0f m walk for %.0f m)" % [arena.flow_distance(spot), radius])
	world.apex_state = 0
	world.begin_apex_warning()
	var boss_spot: Vector3 = arena.poi_slots("boss")[0]
	_check(world.apex_spot.distance_to(boss_spot) < 3.0 and arena.is_open(world.apex_spot, 3.0), "Path map: apex rises in the boss arena (%s)" % world.apex_spot)
	world.apex_state = 4
	world._apex_defeated(boss_spot)
	_check(world.portal_point.distance_to(maw_spot) < 3.0 and arena.is_open(world.portal_point, TUNING.MIGRATION_RADIUS), "Path map: the Schlund opens in its clearing (%s)" % world.portal_point)
	world.portal_clock = -1.0
	for kind in ["nest", "totem"]:
		var spot: Vector3 = world._objective_position(4.0, [], kind)
		var nearest := INF
		for slot in arena.poi_slots(kind):
			nearest = minf(nearest, spot.distance_to(slot))
		_check(nearest < 3.0 and arena.is_open(spot, 3.0), "Path map: %s in its clearing (%s)" % [kind, spot])


func _check_spawn_points() -> void:
	arena.set_seed(SEED)
	# Stage 18c: solo starts on a random open place well inside the map.
	var solo: Array = arena.spawn_points(1)
	_check(solo.size() == 1 and arena.is_open(solo[0], 3.0) and arena.is_inside(solo[0], 60.0), "Solo starts on open ground well inside the map (%s)" % [solo])
	for count in [2, 3, 4]:
		# Stage 18b: start clearings exist for the configured player count.
		arena.configure_map(arena.regions_for_players(count), count)
		var points: Array = arena.spawn_points(count)
		var regions := {}
		var closest := INF
		for index in points.size():
			var point: Vector3 = points[index]
			_check(arena.is_inside(point, 20.0) and arena.is_open(point, 3.0), "Start point %d/%d inside and open" % [index, count])
			regions[arena.region_at(point)] = true
			for other in range(index + 1, points.size()):
				closest = minf(closest, point.distance_to(points[other]))
		_check(regions.size() == count, "spawn_points(%d) in different regions" % count)
		_check(closest >= 100.0, "spawn_points(%d) far apart (closest %.0f m)" % [count, closest])
	arena.configure_map(4, 1)
	# Multiplayer map: 6 x 6 regions for four players, start clearings kept.
	arena.configure_map(6, 4)
	_check(is_equal_approx(arena.bounds().size.x, 504.0) and arena.map_regions_list().size() == 36, "Quad map is 504 m, 36 regions")
	for point in arena.spawn_points(4):
		for key in [arena.chunk_at(point)]:
			for x in range(key.x - 1, key.x + 2):
				for z in range(key.y - 1, key.y + 2):
					for circle in arena.obstacles(Vector2i(x, z)):
						_check(Vector2(circle.x - point.x, circle.z - point.z).length() - circle.w >= arena.START_CLEARANCE - 3.5, "Quad start clearing free of stones")
	arena.configure_map(5, 2)
	_check(is_equal_approx(arena.bounds().size.x, 420.0) and arena.map_regions_list().size() == 25, "Duo map is 420 m, 25 regions")
	var duo_names := {}
	for region in arena.map_regions_list():
		duo_names[arena.region_name(region)] = true
		_check(arena.bounds().encloses(arena.region_rect(region)), "Duo region %s inside the map" % region)
	_check(duo_names.size() == 25, "25 unique duo names")
	arena.configure_map(4, 1)


func _check_migration() -> void:
	_fresh(SEED)
	var playable: Rect2 = arena.playable_rect()
	var before_seed: int = arena.world_seed
	var before_layout := _layout_snapshot()
	# The maw stands in its clearing near the edge (stage 18b).
	var maw_spot: Vector3 = arena.poi_slots("maw")[0]
	_check(arena.edge_distance(maw_spot) > -70.0, "Schlund clearing near the edge (%.0f m)" % arena.edge_distance(maw_spot))
	swarm.position = maw_spot
	arena.sync(swarm.position)
	world.apex_state = 3
	var maw: Variant = world.open_portal(maw_spot)
	world.portal_clock = -1.0
	for step in 360:
		if world.choosing():
			world.choose_mutation(0)
		swarm.set_controls(Vector2.ZERO, false)
		swarm._process(DT)
		world.step(DT)
		arena.sync(swarm.position)
		if world.migration_state == 2:
			break
	_check(world.migration_state == 2 and world.biome_id == "duerrschlund", "Migration completed into the Dürrschlund (state %d, %s)" % [world.migration_state, world.biome_id])
	_check(arena.world_seed != before_seed and _layout_snapshot() != before_layout, "Migration builds a new map (seed %d -> %d)" % [before_seed, arena.world_seed])
	_check(is_equal_approx(arena.bounds().size.x, 336.0), "New map has the same size")
	_check(arena.is_inside(swarm.position, 0.75) and arena.is_open(swarm.position, 1.0), "Migration lands inside on open ground (%s)" % swarm.position)
	_check(arena.clearing_at(swarm.position) >= 0, "Migration lands in an arrival clearing (%s)" % swarm.position)
	for circle in _stones_near(swarm.position, 2):
		_check(Vector2(circle.x - swarm.position.x, circle.z - swarm.position.z).length() - circle.w >= 8.0, "Arrival clearing free of stones")
	_check(arena.rebuild_pending() >= 0, "rebuild state")
	arena.finish_rebuild()
	# Same run seed, same biome again later: the Verdant map comes back deterministically.
	arena.set_biome("verdant_maw")
	arena.set_seed(SEED)
	_check(_layout_snapshot() == before_layout, "Verdant map of the run seed restored")
	maw = null


func _stones_near(point: Vector3, reach: int) -> Array:
	var result := []
	var key: Vector2i = arena.chunk_at(point)
	for x in range(key.x - reach, key.x + reach + 1):
		for z in range(key.y - reach, key.y + reach + 1):
			result.append_array(arena.obstacles(Vector2i(x, z)))
	return result


func _layout_snapshot() -> Array:
	var result := []
	var range_rect: Rect2i = arena.map_overview().chunk_range
	for x in range(range_rect.position.x, range_rect.end.x):
		for z in range(range_rect.position.y, range_rect.end.y):
			result.append(arena.obstacles(Vector2i(x, z)).duplicate())
			result.append(arena.landmark(Vector2i(x, z)).duplicate())
			result.append(arena.trail_samples(Vector2i(x, z)).size())
	return result


func _check_determinism() -> void:
	arena.set_biome("verdant_maw")
	arena.set_seed(777)
	var first := _layout_snapshot()
	var names := []
	for region in arena.map_regions_list():
		names.append(arena.region_name(region))
	var segments: Array = arena.map_overview().border.segments
	arena.set_seed(SEED)
	_check(_layout_snapshot() != first, "Other seed, other map")
	arena.set_seed(777)
	_check(_layout_snapshot() == first, "Same seed, same map")
	# A second, independent scene with the same seed builds the identical map.
	var other_scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(other_scene)
	await process_frame
	other_scene.set_process(false)
	other_scene.get_node("HuntWorld").set_process(false)
	other_scene.get_node("Swarm").set_process(false)
	var other: Variant = other_scene.get_node("Arena")
	other.set_seed(777)
	var saved: Variant = arena
	arena = other
	var second := _layout_snapshot()
	var other_names := []
	for region in other.map_regions_list():
		other_names.append(other.region_name(region))
	var other_segments: Array = other.map_overview().border.segments
	arena = saved
	_check(second == first and other_names == names and other_segments == segments, "Same seed in a new scene, same map, names and edge")
	other_scene.queue_free()
	await process_frame
	var unique := {}
	for name in names:
		unique[name] = true
	_check(names.size() == 16 and unique.size() == 16, "16 unique region names (%d)" % unique.size())
	arena.set_biome("glutsumpf")
	var glut := {}
	for region in arena.map_regions_list():
		glut[arena.region_name(region)] = true
	_check(glut.size() == 16, "16 unique Glutsumpf names")
	arena.set_biome("verdant_maw")


func _check_overview() -> void:
	_fresh(SEED)
	arena.sync(swarm.position)
	arena.set_seed(SEED)
	var overview: Dictionary = arena.map_overview()
	for key in ["size", "bounds", "playable", "regions_per_side", "region_size", "regions", "border", "spawn_points", "chunk_range"]:
		_check(overview.has(key), "map_overview has %s" % key)
	_check(overview.regions.size() == 16 and overview.regions_per_side == 4, "Overview lists 16 regions")
	for entry in overview.regions:
		_check(String(entry.name) != "" and (entry.rect as Rect2).has_point(entry.center), "Region entry %s" % entry.key)
	var inner: PackedVector2Array = overview.border.inner
	_check(inner.size() >= 40, "Border front line sampled (%d)" % inner.size())
	for point in inner:
		_check(not arena.playable_rect().grow(-0.01).has_point(point) and arena.bounds().has_point(point), "Front line lies in the wall strip (%s)" % point)
	_check(not (overview.border.segments as Array).is_empty(), "Edge segments listed")
	# Exploration fog.
	var fog: Vector2i = arena.fog_size()
	_check(fog.x * fog.y == arena.explored_cells().size() and fog.x >= 28, "Fog grid %s" % fog)
	_check(arena.is_explored(swarm.position) and arena.explored_regions().size() == 1, "Start is explored")
	var share: float = arena.exploration_share()
	var version: int = arena.explore_version
	arena.sync(Vector3(100, 0, 100))
	_check(arena.exploration_share() > share and arena.explore_version > version and arena.explored_regions().size() == 2, "Walking reveals fog and a new region")
	_check(not arena.is_explored(Vector3(-150, 0, 150)), "Far corner still in fog")
	arena.set_seed(SEED)
	_check(arena.explored_regions().size() <= 1, "New map, new fog")
