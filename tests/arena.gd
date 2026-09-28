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
	world.drop_loot(Vector3(0, 0, 0), 12)
	for location in [Vector3(57, 0, -85), Vector3(-88, 0, 56), Vector3.ZERO]:
		swarm.position = location
		arena.sync(swarm.position)
		check(arena.chunks.size() == 9, "Visual chunk budget across endless map")
	check(arena.obstacle_centers(key) == centers, "Layout stable after travel")
	check(is_equal_approx(world.loot.total(0), 12.0), "Travel does not remove resources")
	var prey: Node3D = world.prey[0]
	prey.position = rock + Vector3(3.5, 0, 0)
	swarm.position = rock + Vector3(5, 0, 0)
	prey.call("step", 1.0, swarm.position)
	check(prey.position.distance_to(rock) >= arena.OBSTACLE_RADIUS + 0.55 - 0.001, "Prey obeys stone footprint")
	_check_seeds(arena)
	_check_biome_transition(arena)
	_check_decor_density(arena)
	# Last: after the Glutsumpf round trips Verdant must still be built exactly as before.
	_check_verdant_exact(arena)
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
	else:
		print("PASS arena: bounded chunks, deterministic travel, slide, safe spawn, persistent loot crystals, prey collision, seeds (classic layout, determinism, start zone, passages, collision share, clear trails, runtime switch), staggered biome switch, glutsumpf part budget, decor density, verdant exact")
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

# Stage 18: the map is bounded (chunks -6..5); only chunks well inside the
# edge keep every classic stone and landmark (edge ones make room for the wall).
func _classic_matches(arena: Variant) -> bool:
	for x in range(-4, 5):
		for z in range(-4, 5):
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
			# Stage 18b: walls and paths are part of the layout too.
			result.append(arena.trail_samples(Vector2i(x, z)).size())
			result.append(snappedf(arena.wall_distance(Vector3((x + 0.5) * arena.CELL, 0.0, (z + 0.5) * arena.CELL)), 0.01))
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
	var clearings := 0
	var landmarks := 0
	for seed_value in SEEDS:
		arena.set_seed(seed_value)
		# Free start zone (stage 18c: the start is a random open place).
		var start: Vector3 = arena.spawn_points(1)[0]
		var home: Vector2i = arena.chunk_at(start)
		for x in range(home.x - 1, home.x + 2):
			for z in range(home.y - 1, home.y + 2):
				for circle in arena.obstacles(Vector2i(x, z)):
					check(Vector2(circle.x - start.x, circle.z - start.z).length() - circle.w >= 10.0, "Start zone free of collision (seed %d)" % seed_value)
		check(arena.is_open(start, 3.0), "Start position open (seed %d)" % seed_value)
		# Stage 18c: the collision circles are the tall landmarks, each in its own place.
		clearings += arena.clearings().size()
		stones += arena.layout.stones.size()
		landmarks += (arena.layout.beacons as Array).size()
		for stone in arena.layout.stones:
			check(arena.clearing_at(Vector3(stone.x, 0.0, stone.z)) >= 0 and arena.wall_distance(Vector3(stone.x, 0.0, stone.z)) >= stone.w + 3.0, "Landmark with a passage to the wall (seed %d)" % seed_value)
		for sample in 200:
			var key := Vector2i(rng.randi_range(-6, 5), rng.randi_range(-6, 5))
			var own: Array[Vector4] = arena.obstacles(key)
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
			# Every pair is either one touching formation (log knots) or leaves a
			# walkable passage of at least 3 m.
			for circle in own:
				for other in near:
					if other == circle:
						continue
					var gap: float = Vector2(circle.x - other.x, circle.z - other.z).length() - circle.w - other.w
					if gap > 0.9:
						worst_gap = minf(worst_gap, gap)
						check(gap >= arena.MIN_PASSAGE - 0.001, "Passage %.2f m near %s (seed %d)" % [gap, key, seed_value])
			# No collision anywhere on the sand of a path.
			var trail: Array[Vector4] = arena.trail_samples(key)
			for point in trail:
				if not arena.is_open(Vector3(point.x, 0.0, point.z), minf(point.w, 2.0)):
					check(false, "Collision on trail at %s (seed %d)" % [Vector2(point.x, point.z), seed_value])
					break
	var mean := float(stones) / float(clearings)
	check(stones >= 3 * SEEDS.size(), "Landmark stones on every map (%d)" % stones)
	print("Seeds: %d clearings, stones/clearing %.2f, landmarks %d, worst passage %.2f m, worst collision share %.1f %%" % [clearings, mean, landmarks, worst_gap, 100.0 * worst_share])
	# Movement helpers follow the seeded obstacles.
	arena.set_seed(SEEDS[2])
	var found := false
	for stone4 in arena.layout.stones:
		var stone := Vector3(stone4.x, 0.0, stone4.z)
		var start: Vector3 = stone + Vector3(4, 0, 0)
		if not arena.is_open(start, 0.8):
			continue
		var stopped: Vector3 = arena.resolve_motion(start, Vector3(-4, 0, 0), 0.75)
		check(not arena.is_open(stone, 0.5) and arena.safe_spawn(stone, 0.9).distance_to(stone) >= 0.9, "Seeded stone blocks and pushes out")
		check(stopped.distance_to(stone) >= 0.75 + stone4.w - 0.001, "Seeded stone stops motion")
		check(arena.clear_line(start, stone, 0.5).distance_to(stone) > 0.5, "clear_line stops at seeded stone")
		found = true
		break
	check(found, "Seeded map has a free-standing cover stone")
	arena.set_seed(0)

# --- Biome transition and decoration density ----------------------------------

func _parts(arena: Variant) -> int:
	var total := 0
	for key in arena.chunks:
		total += arena.chunks[key].get_child_count()
	return total


func _check_biome_transition(arena: Variant) -> void:
	for seed_value in [0, 4242]:
		arena.set_seed(seed_value)
		var verdant_parts := 0
		var glut_parts := 0
		for spot in FINGERPRINT_SPOTS:
			arena.set_biome("verdant_maw")
			arena.sync(spot)
			verdant_parts += _parts(arena)
			arena.set_biome("glutsumpf")
			glut_parts += _parts(arena)
		print("Parts (draw calls) in 3 x 9 chunks, seed %d: verdant %d, glutsumpf %d" % [seed_value, verdant_parts, glut_parts])
		check(glut_parts <= verdant_parts, "Glutsumpf is not heavier than Verdant (%d > %d parts, seed %d)" % [glut_parts, verdant_parts, seed_value])
		var sites := 0
		for x in range(-3, 4):
			for z in range(-3, 4):
				for site in arena.eruption_sites(Vector2i(x, z)):
					sites += 1
					check(arena.is_open(Vector3(site.x, 0.0, site.z), 0.5), "Eruption source on open ground (seed %d)" % seed_value)
		check(sites > 20, "Glutsumpf has eruption sources (seed %d: %d)" % [seed_value, sites])
	arena.set_seed(0)
	arena.set_biome("verdant_maw")
	arena.sync(Vector3.ZERO)
	var layout: Array = arena.obstacles(Vector2i(1, 2)).duplicate()
	# Staggered switch: colours at once, one chunk rebuilt per sync, nearest first.
	arena.set_biome("glutsumpf", true)
	check(arena.chunks.size() == 9 and arena.rebuild_pending() == 9, "Staggered switch keeps all chunks and queues nine rebuilds")
	var slowest := 0.0
	var order: Array[Vector2i] = []
	for frame in 12:
		var before: Array = arena.chunks.values()
		var started := Time.get_ticks_usec()
		arena.sync(Vector3.ZERO)
		slowest = maxf(slowest, float(Time.get_ticks_usec() - started) / 1000.0)
		for key in arena.chunks:
			if not before.has(arena.chunks[key]):
				order.append(key)
		check(arena.chunks.size() == 9, "Chunk budget during staggered switch")
	print("Staggered biome switch: slowest sync %.2f ms (one chunk per frame)" % slowest)
	check(arena.rebuild_pending() == 0 and order.size() == 9 and order[0] == Vector2i(0, 0), "Nine rebuilds, one per sync, nearest first (%s)" % [order])
	var channels := 0
	for key in arena.chunks:
		if arena.chunks[key].get_node_or_null("Glow channel") != null:
			channels += 1
	check(channels == 9 and arena.obstacles(Vector2i(1, 2)) == layout, "Every chunk shows the Glutsumpf, layout unchanged")
	arena.set_biome("verdant_maw", true)
	arena.finish_rebuild()
	check(arena.rebuild_pending() == 0 and arena.chunks[Vector2i(0, 0)].get_node_or_null("Glow channel") == null, "finish_rebuild completes a staggered switch")


func _check_decor_density(arena: Variant) -> void:
	arena.set_seed(0)
	arena.sync(Vector3.ZERO)
	var full := _parts(arena)
	var layout: Array = arena.obstacles(Vector2i(1, 2)).duplicate()
	arena.set_decor_density(0.5, false)
	var half := _parts(arena)
	check(half < full and arena.obstacles(Vector2i(1, 2)) == layout, "Lower decor density thins decoration only (%d -> %d)" % [full, half])
	arena.set_decor_density(0.5, false)
	check(_parts(arena) == half, "Same density, same decoration")
	arena.set_decor_density(1.0)
	check(arena.rebuild_pending() == 9, "Density change rebuilds staggered by default")
	arena.finish_rebuild()
	check(_parts(arena) == full, "Full density restores the classic decoration")


# --- Verdant Maw pixel guard ----------------------------------------------------

# Fingerprint of the Verdant Maw chunks as built before the Glutsumpf work (stage
# 09 prep): every part's name, transform, mesh shape and material values for the
# classic map and one seeded map. Any drift here would change the Verdant image.
# Stage 18c: re-baselined - seed 4242 is an exploration map; every prop (also on
# the classic seed-0 map, whose layout is unchanged) uses the see-through prop
# shader (prop_fade.gdshader) instead of creature.gdshader; stage 18c follow-up:
# no pebbles, leaf clumps, flowers, reeds or loose leaves on walkable ground,
# walls built per grid cell (big, continuous, collision = look).
const VERDANT_FINGERPRINT := "6f615839655c6aedc2f912601f88fe82"
const FINGERPRINT_SPOTS := [Vector3.ZERO, Vector3(57, 0, -85), Vector3(-88, 0, 56)]


func _check_verdant_exact(arena: Variant) -> void:
	var print_only := OS.get_environment("MAWLINGS_PRINT_FINGERPRINT") == "1"
	var text := _verdant_text(arena)
	var digest := text.md5_text()
	if print_only:
		print("VERDANT_FINGERPRINT ", digest, " parts ", text.count("
"))
		var dump := FileAccess.open(OS.get_environment("MAWLINGS_FINGERPRINT_DUMP"), FileAccess.WRITE)
		if dump != null:
			dump.store_string(text)
	check(digest == VERDANT_FINGERPRINT, "Verdant Maw chunks unchanged (fingerprint %s)" % digest)


func _verdant_text(arena: Variant) -> String:
	var lines := PackedStringArray()
	for seed_value in [0, 4242]:
		arena.set_seed(seed_value)
		for spot in FINGERPRINT_SPOTS:
			arena.sync(spot)
			if arena.has_method("finish_rebuild"):
				arena.finish_rebuild()
			var keys: Array = arena.chunks.keys()
			keys.sort()
			for key in keys:
				lines.append("chunk %s" % [key])
				_describe(arena.chunks[key], lines)
	arena.set_seed(0)
	arena.sync(Vector3.ZERO)
	return "
".join(lines)


func _describe(node: Node, lines: PackedStringArray) -> void:
	for child in node.get_children():
		if not child is MeshInstance3D:
			# Stage 19: wall group names carry material instance ids ("trunk <id>"),
			# which shift whenever another script preloads more resources; drop them.
			var label := String(child.name)
			var cut := label.rfind(" ")
			if cut > 0 and label.substr(cut + 1).lstrip("-").is_valid_int() and label.substr(cut + 1).length() > 6:
				label = label.substr(0, cut)
			lines.append("other %s" % label)
			continue
		var part := child as MeshInstance3D
		var t := part.transform
		var line := "%s|%s|%s" % [String(part.name).rstrip("0123456789@"), _round_basis(t), _mesh_text(part.mesh)]
		line += "|" + _material_text(part.material_override)
		lines.append(line)


static func _round_basis(t: Transform3D) -> String:
	var values := [t.basis.x, t.basis.y, t.basis.z, t.origin]
	var out := PackedStringArray()
	for v in values:
		out.append("%.3f,%.3f,%.3f" % [v.x, v.y, v.z])
	return ";".join(out)


static func _mesh_text(mesh: Mesh) -> String:
	if mesh == null:
		return "none"
	var box := mesh.get_aabb()
	var verts := 0
	for surface in mesh.get_surface_count():
		verts += (mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return "%s %.3f,%.3f,%.3f %.3f,%.3f,%.3f v%d" % [mesh.get_class(), box.position.x, box.position.y, box.position.z, box.size.x, box.size.y, box.size.z, verts]


static func _material_text(material: Material) -> String:
	if material is StandardMaterial3D:
		var m := material as StandardMaterial3D
		return "std %s r%.2f e%s %s vc%s cull%d" % [m.albedo_color.to_html(), m.roughness, m.emission_enabled, m.emission.to_html(), m.vertex_color_use_as_albedo, m.cull_mode]
	if material is ShaderMaterial:
		var m := material as ShaderMaterial
		var out := PackedStringArray([m.shader.resource_path])
		for key in ["brightness", "saturation", "shape_light", "rim_color", "rim_strength", "body_tint", "recolor_dark", "recolor_light", "recolor_amount"]:
			out.append("%s=%s" % [key, m.get_shader_parameter(key)])
		return " ".join(out)
	return "none" if material == null else material.get_class()
