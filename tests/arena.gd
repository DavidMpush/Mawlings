extends SceneTree

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
	var world: Variant = scene.get_node("HuntWorld")
	var swarm: Variant = scene.get_node("Swarm")
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)
	var key := Vector2i(2, -3)
	var centers: Array[Vector3] = arena.obstacle_centers(key)
	check(arena.chunks.size() == 9, "Bounded initial visual chunks")
	var rock: Vector3 = arena.obstacle_centers(Vector2i.ZERO)[0]
	var start := rock + Vector3(4, 0, 0)
	var stopped: Vector3 = arena.resolve_motion(start, Vector3(-3, 0, 0), 0.75)
	check(stopped.distance_to(rock) >= arena.OBSTACLE_RADIUS + 0.75 - 0.001, "Stone blocks player")
	var slide: Vector3 = arena.resolve_motion(start + Vector3(0, 0, 1), Vector3(-3, 0, 2), 0.75)
	check(slide.z > start.z + 1, "Can slide past stone")
	var safe: Vector3 = arena.safe_spawn(rock, 0.9)
	check(safe.distance_to(rock) >= arena.OBSTACLE_RADIUS + 0.9 - 0.001, "Spawn pushed outside stone")
	world._create_corpse(Vector3(0, 0, 0), 12)
	var corpse_id: int = world.model.corpses[0].id
	for location in [Vector3(57, 0, -85), Vector3(-88, 0, 56), Vector3.ZERO]:
		swarm.position = location
		arena.sync(swarm.position)
		check(arena.chunks.size() == 9, "Visual chunk budget across endless map")
	check(arena.obstacle_centers(key) == centers, "Layout stable after travel")
	check(world.model.remaining_biomass(corpse_id) == 12, "Travel does not remove resources")
	var prey: Node3D = world.prey[0]
	prey.position = rock + Vector3(3.5, 0, 0)
	swarm.position = rock + Vector3(5, 0, 0)
	prey.call("step", 1.0, swarm.position)
	check(prey.position.distance_to(rock) >= arena.OBSTACLE_RADIUS + 0.55 - 0.001, "Prey obeys stone footprint")
	_check_seeds(arena)
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
	else:
		print("PASS arena: bounded chunks, deterministic travel, slide, safe spawn, persistent corpses, prey collision, seeds (classic layout, determinism, start zone, passages, collision share, clear trails, runtime switch)")
		quit(0)

# --- Seeds ---------------------------------------------------------------------

const SEEDS := [4242, 777, 90210, 123456789, 31337]

# The classic hash and layout formulas before seeds existed.
static func _legacy_hash(x: int, z: int, salt: int) -> int:
	var n := x * 374761393 + z * 668265263 + salt * 144269
	n = (n ^ (n >> 13)) * 1274126177
	return abs(n ^ (n >> 16))

static func _legacy_centers(key: Vector2i) -> Array[Vector3]:
	var origin := Vector3(key.x * 28.0, 0, key.y * 28.0)
	var flip := 1.0 if _legacy_hash(key.x, key.y, 4) % 2 == 0 else -1.0
	var shift := float(_legacy_hash(key.x, key.y, 8) % 5 - 2) * 0.75
	return [origin + Vector3(-8.6, 0, flip * 7.6 + shift), origin + Vector3(8.6, 0, -flip * 7.6 + shift)]

static func _legacy_landmark_center(key: Vector2i) -> Variant:
	var region := Vector2i(floori(key.x / 2.0), floori(key.y / 2.0))
	var host := _legacy_hash(region.x, region.y, 700) % 4
	if key != region * 2 + Vector2i(host % 2, host / 2) or _legacy_hash(region.x, region.y, 710) % 5 == 0:
		return null
	var center := Vector3(key.x * 28.0, 0.0, key.y * 28.0 + 14.0 + float(_legacy_hash(key.x, key.y, 720) % 5 - 2) * 0.5)
	return center if Vector2(center.x, center.z).length() >= 22.0 else null

func _classic_matches(arena: Variant) -> bool:
	for x in range(-6, 7):
		for z in range(-6, 7):
			var key := Vector2i(x, z)
			if arena.obstacle_centers(key) != _legacy_centers(key):
				return false
			var mark: Dictionary = arena.landmark(key)
			var expected: Variant = _legacy_landmark_center(key)
			if (expected == null) != mark.is_empty() or (expected != null and mark.center != expected):
				return false
			var circles: Array[Vector4] = arena.obstacles(key)
			if circles[0] != Vector4(_legacy_centers(key)[0].x, 0.0, _legacy_centers(key)[0].z, arena.OBSTACLE_RADIUS):
				return false
	return true

func _snapshot(arena: Variant) -> Array:
	var result := []
	for x in range(-5, 6):
		for z in range(-5, 6):
			result.append(arena.obstacles(Vector2i(x, z)).duplicate())
			result.append(arena.landmark(Vector2i(x, z)).duplicate())
	return result

func _check_seeds(arena: Variant) -> void:
	check(arena.world_seed == 0 and _classic_matches(arena), "Seed 0 keeps the classic layout")
	arena.set_seed(SEEDS[0])
	check(arena.chunks.size() == 9, "set_seed rebuilds the visible chunks")
	var first := _snapshot(arena)
	check(_snapshot(arena) == first, "Same seed, same obstacles (cached)")
	arena.set_seed(SEEDS[1])
	var second := _snapshot(arena)
	var differing := 0
	for index in first.size():
		if first[index] != second[index]:
			differing += 1
	check(differing > first.size() / 3, "Different seed, different map (%d of %d differ)" % [differing, first.size()])
	arena.set_seed(SEEDS[0])
	check(_snapshot(arena) == first, "Same seed after runtime switch, identical obstacles")
	arena.set_seed(0)
	check(_classic_matches(arena) and arena.chunks.size() == 9, "Switching back to seed 0 restores the classic layout")
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var cell: float = arena.CELL
	var worst_gap := INF
	var worst_share := 0.0
	var stones := 0
	var chunks_seen := 0
	var dirs := {}
	var landmarks := 0
	for seed_value in SEEDS:
		arena.set_seed(seed_value)
		# Free start zone: nothing blocks or stands within 22 m of the origin.
		for x in range(-2, 2):
			for z in range(-2, 2):
				var key := Vector2i(x, z)
				for circle in arena.obstacles(key):
					check(Vector2(circle.x, circle.z).length() - circle.w >= arena.START_CLEARANCE - 0.001, "Start zone free of collision (seed %d)" % seed_value)
				var mark: Dictionary = arena.landmark(key)
				if not mark.is_empty():
					check(Vector2(mark.center.x, mark.center.z).length() >= arena.START_CLEARANCE, "Start zone free of landmarks (seed %d)" % seed_value)
		check(arena.is_open(Vector3.ZERO, 3.0), "Start position open (seed %d)" % seed_value)
		for sample in 200:
			var key := Vector2i(rng.randi_range(-400, 400), rng.randi_range(-400, 400))
			chunks_seen += 1
			dirs[int(arena.region_params(arena._region_key(key)).dir)] = true
			var own: Array[Vector4] = arena.obstacles(key)
			stones += arena.obstacle_centers(key).size()
			if not arena.landmark(key).is_empty():
				landmarks += 1
			var share := 0.0
			for circle in own:
				share += PI * circle.w * circle.w
			share /= cell * cell
			worst_share = maxf(worst_share, share)
			check(share <= arena.MAX_COLLISION_SHARE + 0.0001, "Collision share %.3f in %s (seed %d)" % [share, key, seed_value])
			var near: Array[Vector4] = []
			for x in range(key.x - 1, key.x + 2):
				for z in range(key.y - 1, key.y + 2):
					near.append_array(arena.obstacles(Vector2i(x, z)))
			# Every pair is either one touching formation (stone + leaning stone,
			# log knots) or leaves a walkable passage of at least 3 m.
			for circle in own:
				for other in near:
					if other == circle:
						continue
					var gap: float = Vector2(circle.x - other.x, circle.z - other.z).length() - circle.w - other.w
					if gap > 0.9:
						worst_gap = minf(worst_gap, gap)
						check(gap >= arena.MIN_PASSAGE - 0.001, "Passage %.2f m near %s (seed %d)" % [gap, key, seed_value])
			# No collision anywhere on the sand trail.
			var trail: Array[Vector4] = arena.trail_samples(key)
			for point in trail:
				if not arena.is_open(Vector3(point.x, 0.0, point.z), point.w):
					check(false, "Collision on trail at %s (seed %d)" % [Vector2(point.x, point.z), seed_value])
					break
	check(dirs.size() == 4, "All four trail directions occur")
	var mean := float(stones) / float(chunks_seen)
	check(mean > 1.3 and mean < 2.6, "Stone mean per chunk %.2f" % mean)
	print("Seeds: stones/chunk %.2f, landmark chunks %.1f %%, worst passage %.2f m, worst collision share %.1f %%" % [mean, 100.0 * landmarks / chunks_seen, worst_gap, 100.0 * worst_share])
	# Movement helpers follow the seeded obstacles.
	arena.set_seed(SEEDS[2])
	var found := false
	for x in range(1, 8):
		if found:
			break
		for stone in arena.obstacle_centers(Vector2i(x, 0)):
			var start: Vector3 = stone + Vector3(4, 0, 0)
			var stopped: Vector3 = arena.resolve_motion(start, Vector3(-4, 0, 0), 0.75)
			check(not arena.is_open(stone, 0.5) and arena.safe_spawn(stone, 0.9).distance_to(stone) >= 0.9, "Seeded stone blocks and pushes out")
			check(stopped.distance_to(stone) >= 0.75 + 0.9 - 0.001, "Seeded stone stops motion")
			check(arena.clear_line(start, stone, 0.5).distance_to(stone) > 0.5, "clear_line stops at seeded stone")
			found = true
			break
	check(found, "Seeded map has stones near the start row")
	arena.set_seed(0)
