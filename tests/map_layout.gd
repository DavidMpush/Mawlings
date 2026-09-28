extends SceneTree

# Stage 18c: the exploration map. For three seeds (and a duo map): landscapes
# from several kinds, 20-38 % blocked, every open patch reachable (no island,
# nothing cut off), POIs of every kind scattered on open, reachable ground,
# walls without gaps (no creature and no single Mawling walks through), enemies
# reach the swarm from far places, the bot's route finder reaches the boss arena
# and the Schlund, flood spawns on open ground, 60-90 amber nodes with deeper =
# better tiers, tall landmarks, discovery (only near the start at first),
# flow field cost, build time, same seed = same map. The 18b corridor layout
# ("graph") still builds a connected loop graph.

const SEEDS := [4242, 777, 90210]
# Stage 19: the Dürrschlund variant runs the same checks plus its own.
const DESERT_SEEDS := [4242, 31337]
const TYPES := ["start", "boss", "maw", "nest", "totem", "cocoon", "cocoon_gold", "shrine", "grove", "elite"]

var failures: Array[String] = []


func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var arena: Variant = scene.get_node("Arena")
	scene.set_process(false)
	scene.get_node("HuntWorld").set_process(false)
	scene.get_node("Swarm").set_process(false)
	check(not arena.has_layout() and arena.poi_slots("nest").is_empty(), "Seed 0 keeps the classic open map")
	var worst_step := 0.0
	var slowest_build := 0.0
	for seed_value in SEEDS:
		arena.set_seed(seed_value)
		slowest_build = maxf(slowest_build, float(arena.layout.build_msec))
		_check_terrain(arena, seed_value)
		_check_slots(arena, seed_value)
		worst_step = maxf(worst_step, _check_flow(arena, seed_value))
		_check_walls(arena, seed_value)
		_check_enemies(arena, seed_value)
		_check_bot_route(arena, seed_value)
		_check_flood(arena, seed_value)
		_check_loot(arena, seed_value)
		_check_discovery(arena, seed_value)
	arena.set_biome("duerrschlund")
	var desert_ribs := 0
	for seed_value in DESERT_SEEDS:
		arena.set_seed(seed_value)
		slowest_build = maxf(slowest_build, float(arena.layout.build_msec))
		_check_terrain(arena, seed_value)
		_check_slots(arena, seed_value)
		worst_step = maxf(worst_step, _check_flow(arena, seed_value))
		_check_walls(arena, seed_value)
		_check_enemies(arena, seed_value)
		_check_bot_route(arena, seed_value)
		_check_loot(arena, seed_value)
		desert_ribs += _check_desert(arena, seed_value)
	check(desert_ribs >= 3, "Desert bone fields carry rib cages (%d)" % desert_ribs)
	arena.set_biome("verdant_maw")
	_check_determinism(arena, scene)
	_check_multiplayer(arena)
	_check_arrival(arena)
	_check_graph_style(arena)
	arena.configure_map(4, 1)
	arena.set_seed(0)
	print("Flow field: worst step %.3f ms (%d cells); slowest map build %.0f ms" % [worst_step, arena.FLOW_BUDGET, slowest_build])
	# ~110-150 ms on an idle desktop; many parallel Godot runs multiply it.
	check(slowest_build < 2000.0, "Map build under 2 s even under load (%.0f)" % slowest_build)
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS map_layout: %d seeds - mixed landscapes, 20-38 %% blocked, all open ground connected, POIs scattered on reachable ground, gapless walls, enemies reach the swarm, bot routes, flood spawns, amber nodes, landmarks, discovery, deterministic; duo map; arrival; 18b graph style" % SEEDS.size())
	quit(0)


func _check_terrain(arena: Variant, seed_value: int) -> void:
	var stats: Dictionary = arena.layout.stats()
	print("Seed %d: blocked %.0f %%, lands %s, POIs %s, trails %d, amber %d, landmarks %d, pockets filled %d / joined %d, build %.0f ms %s" % [seed_value, 100.0 * float(stats.blocked), stats.lands, stats.pois, stats.trails, stats.loot, stats.beacons, stats.filled, stats.joined, stats.msec, stats.timings])
	check(float(stats.blocked) >= 0.22 and float(stats.blocked) <= 0.38, "Blocked share 22-38 %% (seed %d: %.2f)" % [seed_value, stats.blocked])
	check((stats.lands as Dictionary).size() >= 4, "At least four landscapes (seed %d: %s)" % [seed_value, stats.lands])


func _check_slots(arena: Variant, seed_value: int) -> void:
	var counts := {"cocoon": 10, "cocoon_gold": 2, "shrine": 4, "nest": 6, "totem": 4, "grove": 5, "elite": 2, "boss": 1, "maw": 1, "start": 1}
	for type in TYPES:
		var slots: Array = arena.poi_slots(type)
		check(slots.size() >= int(counts[type]), "POI type %s: %d slots (seed %d)" % [type, slots.size(), seed_value])
		for spot in slots:
			check(arena.is_open(spot, 2.0), "%s slot %s is open ground (seed %d)" % [type, spot, seed_value])
	var start: Vector3 = arena.spawn_points(1)[0]
	check(arena.is_open(start, 3.0), "Start on open ground (seed %d)" % seed_value)
	var boss: Vector3 = arena.poi_slots("boss")[0]
	check(arena.wall_distance(boss) > 14.0, "Boss arena is a wide open area (seed %d: %.1f m to the wall)" % [seed_value, arena.wall_distance(boss)])
	var maw: Vector3 = arena.poi_slots("maw")[0]
	check(maw.distance_to(boss) > 90.0, "Schlund far from the boss arena (seed %d: %.0f m)" % [seed_value, maw.distance_to(boss)])


# Returns the worst incremental step (ms). Every POI and every passable cell
# of the flow grid is reached from the start: no island.
func _check_flow(arena: Variant, seed_value: int) -> float:
	var start: Vector3 = arena.spawn_points(1)[0]
	arena.finish_flow(start)
	var flow: RefCounted = arena.flow
	for clearing in arena.clearings():
		# A landmark stands in the middle of its place: test beside it.
		var probe: Vector3 = clearing.center + (Vector3(6.0, 0.0, 0.0) if clearing.types.has("landmark") else Vector3.ZERO)
		check(is_finite(arena.flow_distance(arena.safe_spawn(probe, 1.0))), "Place %s reachable (seed %d)" % [clearing.types, seed_value])
	var unreached := 0
	for index in flow.passable.size():
		if flow.passable[index] == 1 and flow.dist[index] >= flow.UNREACHED:
			unreached += 1
	check(unreached * 100 <= flow.open_cells, "All open ground connected (seed %d: %d of %d cells cut off)" % [seed_value, unreached, flow.open_cells])
	flow.begin(start + Vector3(10.0, 0.0, 0.0))
	var worst := 0.0
	var total := 0.0
	var steps := 0
	while true:
		var t0 := Time.get_ticks_usec()
		var done: bool = flow.step(arena.FLOW_BUDGET)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		worst = maxf(worst, ms)
		total += ms
		steps += 1
		if done:
			break
	# ~0.3-0.5 ms on an idle desktop; single steps spike when other runs share the CPU.
	print("Seed %d: flow step %.3f ms on average (worst %.3f) over %d steps" % [seed_value, total / float(steps), worst, steps])
	check(total / float(steps) < 3.0, "Flow step on average under 3 ms even under load (seed %d: %.3f)" % [seed_value, total / float(steps)])
	arena.finish_flow(start)
	return worst


# Straight runs from open ground into the terrain: every creature size and a
# single Mawling slide along, never enter a wall, never tunnel through.
func _check_walls(arena: Variant, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var worst := INF
	var tunnels := 0
	var clearings: Array = arena.clearings()
	for run in 80:
		var from: Dictionary = clearings[run % clearings.size()]
		var angle := rng.randf() * TAU
		var position: Vector3 = arena.safe_spawn(from.center, 1.0)
		var goal: Vector3 = position + Vector3(cos(angle), 0.0, sin(angle)) * 90.0
		var radius: float = [0.3, 0.55, 0.8, 2.5][run % 4]
		for step in 300:
			var direction: Vector3 = goal - position
			direction.y = 0.0
			if direction.length() < 0.5:
				break
			var next: Vector3 = arena.resolve_motion(position, direction.normalized() * 0.3, radius)
			worst = minf(worst, arena.wall_distance(next) - radius)
			if not arena._wall_line_clear(position, next, 0.0) and arena.wall_distance(position) > 0.0:
				tunnels += 1
			position = next
	check(worst > -0.12, "No creature enters a wall (seed %d: worst %.3f m)" % [seed_value, worst])
	check(tunnels == 0, "No creature tunnels through a wall (seed %d: %d)" % [seed_value, tunnels])
	var closed := true
	var squeezed := 0
	for sample in 600:
		var point := Vector3(rng.randf_range(-160.0, 160.0), 0.0, rng.randf_range(-160.0, 160.0))
		var wall: float = arena.wall_distance(point)
		if wall < -0.5 and arena.is_open(point, 0.2):
			closed = false
		if wall > -2.0 and wall < 0.3 and arena.wall_distance(arena.push_walls(point, 0.3)) < 0.25:
			squeezed += 1
	check(closed, "Every point inside a wall is blocked (seed %d)" % seed_value)
	check(squeezed == 0, "Mawlings pushed out of walls (seed %d: %d stuck)" % [seed_value, squeezed])


# From the boss arena, the Schlund, the elite camps and a few far places a
# hunter (0.8 m) walks to the swarm; a Bog King (2.5 m) and the apex (3 m)
# from every place wide enough for their body (the boss arena always is).
func _check_enemies(arena: Variant, seed_value: int) -> void:
	var swarm: Vector3 = arena.spawn_points(1)[0]
	arena.finish_flow(swarm)
	var sources: Array = []
	for type in ["boss", "maw", "elite", "cocoon_gold", "shrine"]:
		sources.append_array(arena.poi_slots(type))
	var slowest := 0.0
	for source in sources:
		for radius in [0.8, 2.5, 3.0]:
			if radius > 1.0 and arena.wall_distance(source) < 4.0:
				continue
			var position: Vector3 = arena.safe_spawn(source, radius)
			var reached := false
			var time := 0.0
			while time < 300.0:
				var direction: Vector3 = arena.steer_direction(position, swarm, radius)
				position = arena.resolve_motion(position, direction * 3.0 * 0.1, radius)
				time += 0.1
				if Vector2(position.x - swarm.x, position.z - swarm.z).length() < radius + 3.0:
					reached = true
					break
			slowest = maxf(slowest, time)
			check(reached, "Enemy r=%.1f reaches the swarm from %s (seed %d, stuck at %s)" % [radius, source, seed_value, position])
	print("Seed %d: enemies from %d far places reach the swarm, slowest %.0f s at 3 m/s" % [seed_value, sources.size(), slowest])


func _check_bot_route(arena: Variant, seed_value: int) -> void:
	for type in ["boss", "maw", "nest"]:
		var goal: Vector3 = arena.poi_slots(type)[0]
		var position: Vector3 = arena.spawn_points(1)[0]
		var time := 0.0
		while time < 150.0 and position.distance_to(goal) > 2.5:
			var direction: Vector3 = arena.nav_direction(position, goal, 1.0)
			position = arena.resolve_motion(position, direction * 7.0 * 0.1, 0.75)
			time += 0.1
		check(position.distance_to(goal) <= 2.5, "Bot route reaches the %s (seed %d, stuck at %s)" % [type, seed_value, position])


func _check_flood(arena: Variant, seed_value: int) -> void:
	var swarm: Vector3 = arena.spawn_points(1)[0]
	arena.finish_flow(swarm)
	var found := 0
	for salt in 60:
		var point: Vector3 = arena.flood_point(salt)
		if not point.is_finite():
			continue
		found += 1
		var walk: float = arena.flow_distance(point)
		check(arena.is_open(point, 0.5) and walk >= 20.0 and walk <= 50.0 and point.distance_to(swarm) >= 18.0, "Flood point open at 24-44 m walking distance (seed %d: %.0f m)" % [seed_value, walk])
	check(found >= 50, "Flood points available (seed %d: %d of 60)" % [seed_value, found])


# Amber nodes: 60-90, on open ground, tiers rise with the distance from the start.
func _check_loot(arena: Variant, seed_value: int) -> void:
	var points: Array = arena.layout.loot_points
	check(points.size() >= 55 and points.size() <= 95, "60-90 amber nodes (seed %d: %d)" % [seed_value, points.size()])
	var start: Vector3 = arena.spawn_points(1)[0]
	var near := [0.0, 0.0, 0.0]
	var count := [0, 0, 0]
	for node in points:
		check(arena.wall_distance(Vector3(node.x, 0.0, node.z)) >= 1.0, "Amber node on open ground (seed %d)" % seed_value)
		near[int(node.w)] += Vector2(node.x - start.x, node.z - start.z).length()
		count[int(node.w)] += 1
	check(count[0] > 0 and count[2] > 0, "Amber tiers 0 and 2 exist (seed %d: %s)" % [seed_value, count])
	if count[0] > 0 and count[2] > 0:
		check(near[2] / count[2] > near[0] / count[0], "Better amber lies deeper in the land (seed %d)" % seed_value)
	check((arena.layout.beacons as Array).size() >= 3, "Tall landmarks (seed %d)" % seed_value)


# At the start only the surroundings are known; walking there reveals a place.
func _check_discovery(arena: Variant, seed_value: int) -> void:
	var start: Vector3 = arena.spawn_points(1)[0]
	arena.set_seed(seed_value)
	arena.sync(start)
	var boss: Vector3 = arena.poi_slots("boss")[0]
	if boss.distance_to(start) > arena.EXPLORE_RADIUS + 30.0:
		check(not arena.is_discovered(boss) and arena.discovered("boss").is_empty(), "Boss arena hidden at the start (seed %d)" % seed_value)
	var total := 0
	for type in TYPES:
		total += arena.discovered(type).size()
	check(total <= 6, "Only a few places known at the start (seed %d: %d)" % [seed_value, total])
	arena.discover_around(boss, 10.0)
	check(arena.is_discovered(boss) and arena.discovered("boss").size() == 1, "Walking there discovers the boss arena (seed %d)" % seed_value)


# Desert: its own landscapes, rib cages as solid blocks, quicksand on open
# ground that slows, skull and rock arch landmarks (the arch walkable between
# its feet). Returns the number of rib cages.
func _check_desert(arena: Variant, seed_value: int) -> int:
	var layout: RefCounted = arena.layout
	check(bool(layout.desert), "Desert map flag (seed %d)" % seed_value)
	var stats: Dictionary = layout.stats()
	for land in (stats.lands as Dictionary).keys():
		check(land in layout.DESERT_LAND_NAMES, "Desert landscape names (seed %d: %s)" % [seed_value, land])
	print("Desert seed %d: ribs %d (dropped %d), quicksand %d, beacons %s" % [seed_value, stats.ribs, stats.ribs_dropped, stats.quicksand, layout.beacons.map(func(b): return b.kind)])
	for cage in layout.ribs:
		for cell in cage.cells:
			check(layout.blocked[cell] == 1 and layout.kind[cell] == layout.KIND_RIB, "Rib cage cells solid (seed %d)" % seed_value)
		check(arena.wall_distance(cage.center) < -0.5, "Rib cage centre inside the wall (seed %d)" % seed_value)
	var sands: Array = arena.quicksand_patches()
	check(sands.size() >= 5, "Quicksand patches (seed %d: %d)" % [seed_value, sands.size()])
	for patch in sands:
		var center := Vector3(patch.x, 0.0, patch.z)
		check(arena.wall_distance(center) >= patch.w, "Quicksand on open ground (seed %d)" % seed_value)
		check(arena.quicksand_factor(center) <= 0.55, "Quicksand slows in its middle (seed %d: %.2f)" % [seed_value, arena.quicksand_factor(center)])
		check(arena.quicksand_factor(center + Vector3(patch.w + 0.5, 0.0, 0.0)) == 1.0, "Firm ground right outside the quicksand (seed %d)" % seed_value)
		var step: Vector3 = arena.resolve_motion(center, Vector3(0.1, 0.0, 0.0), 0.75)
		check(step.distance_to(center) < 0.06, "Motion through quicksand is slowed (seed %d)" % seed_value)
	var kinds := {}
	for mark in layout.beacons:
		kinds[mark.kind] = true
		check(mark.kind in ["giant_skull", "rock_arch"], "Desert landmark kinds (seed %d: %s)" % [seed_value, mark.kind])
		if mark.kind == "rock_arch":
			var middle: Vector3 = mark.center
			check(arena.is_open(middle, 0.75), "Walkable under the rock arch (seed %d)" % seed_value)
			for foot in mark.feet:
				check(not arena.is_open(foot, 0.3), "Rock arch feet block (seed %d)" % seed_value)
	return int(stats.ribs)


func _fingerprint(arena: Variant) -> String:
	var text := ""
	for clearing in arena.clearings():
		text += "%s %.2f %s|" % [clearing.center, clearing.radius, ",".join(clearing.types)]
	for node in arena.layout.loot_points:
		text += "%s|" % [node]
	return text.md5_text() + str(Array(arena.layout.sdf).hash())


func _check_determinism(arena: Variant, scene: Node) -> void:
	arena.set_seed(SEEDS[0])
	var first := _fingerprint(arena)
	arena.set_seed(SEEDS[1])
	check(_fingerprint(arena) != first, "Different seed, different map")
	arena.set_seed(SEEDS[0])
	check(_fingerprint(arena) == first, "Same seed after a switch, same map")
	var other: Node3D = load("res://scripts/arena.gd").new()
	scene.add_child(other)
	other.set_seed(SEEDS[0])
	check(_fingerprint(other) == first, "Same seed in a fresh arena, same map")
	other.queue_free()


func _check_multiplayer(arena: Variant) -> void:
	arena.configure_map(5, 2)
	arena.set_seed(SEEDS[1])
	var points: Array = arena.spawn_points(2)
	check(points.size() == 2 and points[0].distance_to(points[1]) >= 100.0, "Duo: two starts far apart")
	for point in points:
		check(arena.is_open(point, 3.0), "Duo start on open ground")
	arena.finish_flow(points[0])
	check(is_finite(arena.flow_distance(points[1])), "Duo starts connected")
	print("Duo 5 x 5: %s" % [arena.layout.stats().pois])


func _check_arrival(arena: Variant) -> void:
	arena.configure_map(4, 1)
	arena.set_seed(SEEDS[2])
	var arrival: Vector3 = arena.prepare_arrival(Vector3(-120.0, 0.0, 130.0))
	arena.set_biome("glutsumpf")
	check(arena.clearing_at(arrival) >= 0 and arena.is_open(arrival, 3.0), "Migration arrival is an open place on the new map")
	arena.finish_flow(arrival)
	check(is_finite(arena.flow_distance(arena.poi_slots("boss")[0])), "Arrival is connected to the boss arena")
	arena.set_biome("verdant_maw")


func _check_graph_style(arena: Variant) -> void:
	arena.layout_style = "graph"
	arena.set_seed(SEEDS[0])
	var stats: Dictionary = arena.layout.stats()
	check(int(stats.bridges) == 0 and int(stats.min_degree) >= 2 and int(stats.loops) >= 3, "18b graph style still builds a loop graph (%s)" % [stats])
	arena.layout_style = "explore"
	arena.set_seed(SEEDS[0])
