extends SceneTree

# Stage 18b: the seeded map is a designed level of clearings, paths and walls.
# Checks for three seeds (and a duo map): graph connected without dead ends and
# with loops (two through the hub), every clearing reachable over the flow
# field, every POI slot in a clearing on open ground, walls without gaps (no
# creature and no single Mawling walks through), enemies reach the swarm from
# every clearing, the bot's route finder reaches the boss arena, flood spawns
# on open path ground, flow field cost, same seed = same map.

const SEEDS := [4242, 777, 90210]
const TYPES := ["start", "boss", "maw", "nest", "totem", "cocoon", "grove", "landmark"]

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
	var full_ms := 0.0
	for seed_value in SEEDS:
		arena.set_seed(seed_value)
		_check_graph(arena, seed_value)
		_check_slots(arena, seed_value)
		var cost := _check_flow(arena, seed_value)
		worst_step = maxf(worst_step, cost.x)
		full_ms = maxf(full_ms, cost.y)
		_check_walls(arena, seed_value)
		_check_enemies(arena, seed_value)
		_check_bot_route(arena, seed_value)
		_check_flood(arena, seed_value)
	_check_determinism(arena, scene)
	_check_multiplayer(arena)
	_check_arrival(arena)
	arena.configure_map(4, 1)
	arena.set_seed(0)
	print("Flow field: worst step %.3f ms (%d cells), full field %.2f ms" % [worst_step, arena.FLOW_BUDGET, full_ms])
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS map_layout: %d seeds - connected graph, no dead ends, loops through the hub, reachable clearings, POIs in clearings, gapless walls, enemies reach the swarm, bot routes, flood spawns, deterministic; duo map; arrival clearing" % SEEDS.size())
	quit(0)


func _check_graph(arena: Variant, seed_value: int) -> void:
	var layout: RefCounted = arena.layout
	var stats: Dictionary = layout.stats()
	var clearings: Array = arena.clearings()
	var paths: Array = arena.paths()
	print("Seed %d: %d clearings, %d paths (%d narrow), %d loops, hub degree %d, min degree %d, built in %.1f ms (%d attempts)" % [seed_value, stats.clearings, stats.paths, stats.narrow, stats.loops, stats.hub_degree, stats.min_degree, stats.msec, stats.attempts])
	check(clearings.size() >= 9 and clearings.size() <= 13, "8-12 clearings plus the hub (seed %d: %d)" % [seed_value, clearings.size()])
	check(int(stats.bridges) == 0, "No dead end: every path lies on a loop (seed %d: %d bridges)" % [seed_value, stats.bridges])
	check(int(stats.min_degree) >= 2, "Every clearing has two ways out (seed %d)" % seed_value)
	check(int(stats.loops) >= 3, "At least three loops (seed %d: %d)" % [seed_value, stats.loops])
	# Two loops through the middle: the hub has >= 3 paths and none is a bridge.
	var hub: Dictionary = clearings[layout.hub]
	check((hub.paths as Array).size() >= 3 and float(hub.radius) >= 30.0, "Big hub with at least three paths (seed %d)" % seed_value)
	var narrow := 0
	var wide := 0
	for path in paths:
		var points: PackedVector3Array = path.points
		var a: Dictionary = clearings[path.a]
		var b: Dictionary = clearings[path.b]
		check(points[0].distance_to(a.center) < 0.5 and points[points.size() - 1].distance_to(b.center) < 0.5, "Path %d joins two clearings (seed %d)" % [path.id, seed_value])
		var low := INF
		var high := 0.0
		for half in path.half:
			low = minf(low, half)
			high = maxf(high, half)
		check(low >= 4.0 and high <= 10.5, "Path %d width %.1f-%.1f m within 8-21 m (seed %d)" % [path.id, low * 2.0, high * 2.0, seed_value])
		if path.kind == "narrow" and low <= 5.0:
			narrow += 1
		if path.kind == "main" and low >= 6.0:
			wide += 1
		# Every point of the centreline is open ground.
		for index in range(0, points.size(), 2):
			if arena.wall_distance(points[index]) < 3.0:
				check(false, "Path %d centre is open (seed %d, %.2f m at %s)" % [path.id, seed_value, arena.wall_distance(points[index]), points[index]])
				break
	check(narrow >= 2 and wide >= 4, "Chokes and main roads (seed %d: %d narrow, %d wide)" % [seed_value, narrow, wide])
	# Important clearings: a short narrow and a long open route.
	for clearing in clearings:
		if not (clearing.types.has("boss")):
			continue
		var kinds := {}
		for index in clearing.paths:
			kinds[paths[index].kind] = true
		check(kinds.size() == 2, "Boss arena reached by a narrow and a wide path (seed %d)" % seed_value)


func _check_slots(arena: Variant, seed_value: int) -> void:
	for type in TYPES:
		var slots: Array = arena.poi_slots(type)
		check(not slots.is_empty(), "POI type %s has slots (seed %d)" % [type, seed_value])
		for spot in slots:
			check(arena.clearing_at(spot) >= 0, "%s slot %s lies in a clearing (seed %d)" % [type, spot, seed_value])
			# A landmark slot carries the landmark itself (arch feet, log).
			check(type == "landmark" or arena.is_open(spot, 2.0), "%s slot %s is open ground (seed %d)" % [type, spot, seed_value])
	check(arena.poi_slots("nest").size() >= 2 and arena.poi_slots("cocoon").size() >= 2 and arena.poi_slots("grove").size() >= 4, "Enough nest/cocoon/grove slots (seed %d)" % seed_value)
	var boss: Vector3 = arena.poi_slots("boss")[0]
	var maw: Vector3 = arena.poi_slots("maw")[0]
	check(boss.length() > 90.0 and maw.distance_to(boss) > 150.0, "Boss arena far from the start, Schlund far from the boss (seed %d: %.0f / %.0f m)" % [seed_value, boss.length(), maw.distance_to(boss)])
	check(arena.edge_distance(maw) > -60.0, "Schlund near the map edge (seed %d)" % seed_value)
	var boss_clearing: Dictionary = arena.clearings()[arena.clearing_at(boss)]
	check(float(boss_clearing.radius) >= 25.0, "Boss arena 50-60 m (seed %d)" % seed_value)
	var start: Array = arena.spawn_points(1)
	check(start.size() == 1 and start[0].length() < 3.0 and arena.is_open(start[0], 3.0), "Solo start in the hub (seed %d)" % seed_value)


# Returns Vector2(worst step ms, full field ms).
func _check_flow(arena: Variant, seed_value: int) -> Vector2:
	var started := Time.get_ticks_usec()
	arena.finish_flow(Vector3.ZERO)
	var full := float(Time.get_ticks_usec() - started) / 1000.0
	for clearing in arena.clearings():
		check(is_finite(arena.flow_distance(clearing.center)), "Clearing %d reachable over the flow field (seed %d)" % [clearing.id, seed_value])
	# Incremental: FLOW_BUDGET cells per sync, measured over a whole field.
	var flow: RefCounted = arena.flow
	flow.begin(Vector3(20.0, 0.0, 0.0))
	var worst := 0.0
	var steps := 0
	while true:
		var t0 := Time.get_ticks_usec()
		var done: bool = flow.step(arena.FLOW_BUDGET)
		worst = maxf(worst, float(Time.get_ticks_usec() - t0) / 1000.0)
		steps += 1
		if done:
			break
	print("Seed %d: flow field %d open cells, full %.2f ms, %d steps of %d cells, worst step %.3f ms" % [seed_value, flow.open_cells, full, steps, arena.FLOW_BUDGET, worst])
	check(worst < 1.0, "Flow step under 1 ms (seed %d: %.3f)" % [seed_value, worst])
	arena.finish_flow(Vector3.ZERO)
	return Vector2(worst, full)


# Straight runs from open ground through the walls: every creature size and a
# single Mawling slide along, never enter the wall, never tunnel through.
func _check_walls(arena: Variant, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var worst := INF
	var tunnels := 0
	var runs := 0
	var clearings: Array = arena.clearings()
	for run in 60:
		var from: Dictionary = clearings[run % clearings.size()]
		var angle := rng.randf() * TAU
		var start: Vector3 = arena.safe_spawn(from.center + Vector3(cos(angle), 0.0, sin(angle)) * float(from.radius) * 0.5, 1.0)
		var goal: Vector3 = start + Vector3(cos(angle), 0.0, sin(angle)) * 120.0
		var radius: float = [0.3, 0.55, 0.8, 2.5][run % 4]
		var position: Vector3 = start
		runs += 1
		for step in 400:
			var direction: Vector3 = (goal - position)
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
	# Wall cells are closed: points 0.5 m inside a wall are never open.
	var closed := true
	for sample in 400:
		var point := Vector3(rng.randf_range(-160.0, 160.0), 0.0, rng.randf_range(-160.0, 160.0))
		if arena.wall_distance(point) < -0.5 and arena.is_open(point, 0.2):
			closed = false
	check(closed, "Every point inside a wall is blocked (seed %d)" % seed_value)
	# push_walls (every Mawling of the swarm) always ends outside the wall.
	var squeezed := 0
	for sample in 300:
		var point := Vector3(rng.randf_range(-160.0, 160.0), 0.0, rng.randf_range(-160.0, 160.0))
		if arena.wall_distance(point) > -2.0 and arena.wall_distance(point) < 0.3:
			var pushed: Vector3 = arena.push_walls(point, 0.3)
			if arena.wall_distance(pushed) < 0.25:
				squeezed += 1
	check(squeezed == 0, "Mawlings pushed out of walls (seed %d: %d stuck)" % [seed_value, squeezed])
	print("Seed %d: %d wall runs, deepest %.3f m, tunnels %d" % [seed_value, runs, worst, tunnels])


# From every clearing a hunter (0.8 m), a Bog King (2.5 m) and the apex (3 m)
# walk to the swarm in the hub with steer_direction + resolve_motion.
func _check_enemies(arena: Variant, seed_value: int) -> void:
	var swarm := Vector3(0.0, 0.0, 0.0)
	arena.finish_flow(swarm)
	var slowest := 0.0
	for clearing in arena.clearings():
		for radius in [0.8, 2.5, 3.0]:
			var position: Vector3 = arena.safe_spawn(clearing.center + Vector3(3.0, 0.0, 2.0), radius)
			var reached := false
			var time := 0.0
			while time < 240.0:
				var direction: Vector3 = arena.steer_direction(position, swarm, radius)
				position = arena.resolve_motion(position, direction * 3.0 * 0.1, radius)
				time += 0.1
				if Vector2(position.x - swarm.x, position.z - swarm.z).length() < radius + 3.0:
					reached = true
					break
			slowest = maxf(slowest, time)
			check(reached, "Enemy r=%.1f reaches the swarm from clearing %d (seed %d, stuck at %s)" % [radius, clearing.id, seed_value, position])
	print("Seed %d: enemies from every clearing reach the swarm, slowest %.0f s at 3 m/s" % [seed_value, slowest])


# The bot's route finder walks from the hub into the boss arena and the Schlund.
func _check_bot_route(arena: Variant, seed_value: int) -> void:
	for type in ["boss", "maw", "nest"]:
		var goal: Vector3 = arena.poi_slots(type)[0]
		var position := Vector3.ZERO
		var time := 0.0
		while time < 120.0 and position.distance_to(goal) > 2.0:
			var direction: Vector3 = arena.nav_direction(position, goal, 1.0)
			position = arena.resolve_motion(position, direction * 7.0 * 0.1, 0.75)
			time += 0.1
		check(position.distance_to(goal) <= 2.0, "Bot route reaches the %s clearing (seed %d, stuck at %s)" % [type, seed_value, position])


# Flood points: open ground at walking distance 24-44 m, off the swarm.
func _check_flood(arena: Variant, seed_value: int) -> void:
	var swarm := Vector3(0.0, 0.0, 0.0)
	arena.finish_flow(swarm)
	var found := 0
	for salt in 60:
		var point: Vector3 = arena.flood_point(salt)
		if not point.is_finite():
			continue
		found += 1
		var walk: float = arena.flow_distance(point)
		check(arena.is_open(point, 0.5), "Flood point on open ground (seed %d)" % seed_value)
		check(walk >= 20.0 and walk <= 50.0 and point.distance_to(swarm) >= 18.0, "Flood point at 24-44 m walking distance (seed %d: %.0f m, %.0f straight)" % [seed_value, walk, point.distance_to(swarm)])
	check(found >= 50, "Flood points available (seed %d: %d of 60)" % [seed_value, found])


func _fingerprint(arena: Variant) -> String:
	var text := ""
	for clearing in arena.clearings():
		text += "%s %.2f %s|" % [clearing.center, clearing.radius, ",".join(clearing.types)]
	for path in arena.paths():
		text += "%s %s %.2f|" % [path.kind, path.points[path.points.size() / 2], path.length]
	var layout: RefCounted = arena.layout
	return text.md5_text() + (str(Array(layout.sdf).hash()))


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
	var stats: Dictionary = arena.layout.stats()
	var points: Array = arena.spawn_points(2)
	check(points.size() == 2 and points[0].distance_to(points[1]) >= 100.0, "Duo: two start clearings far apart")
	for point in points:
		check(arena.clearing_at(point) >= 0 and arena.is_open(point, 3.0), "Duo start on an open clearing")
	check(int(stats.bridges) == 0 and int(stats.min_degree) >= 2 and int(stats.clearings) >= 14, "Duo map graph (%s)" % [stats])
	arena.finish_flow(points[0])
	check(is_finite(arena.flow_distance(points[1])), "Duo starts connected")
	print("Duo 5 x 5: %d clearings, %d paths, %d loops" % [stats.clearings, stats.paths, stats.loops])


func _check_arrival(arena: Variant) -> void:
	arena.configure_map(4, 1)
	arena.set_seed(SEEDS[2])
	var arrival: Vector3 = arena.prepare_arrival(Vector3(-120.0, 0.0, 130.0))
	arena.set_biome("glutsumpf")
	check(arena.clearing_at(arrival) >= 0 and arena.is_open(arrival, 3.0), "Migration arrival is a clearing on the new map")
	arena.finish_flow(arrival)
	check(is_finite(arena.flow_distance(Vector3.ZERO)), "Arrival clearing is connected to the hub")
	arena.set_biome("verdant_maw")
