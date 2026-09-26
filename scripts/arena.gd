extends Node3D

# An endless, deterministic layout. Only nearby visual chunks exist; obstacle
# positions are computed from coordinates, so moving away never changes them.
const CELL := 28.0
const VISIBLE_RADIUS := 1
const OBSTACLE_RADIUS := 1.85
const CREATURE_SHADER = preload("res://shaders/creature.gdshader")
const BIOMES = preload("res://scripts/biomes.gd")
const ROCK_SCENE = preload("res://assets/gameplay/props/Rock_game.glb")
const LEAF_SCENE = preload("res://assets/gameplay/props/Leaf_game.glb")
const ROOT_ARCH_SCENE = preload("res://assets/gameplay/props/RootArch_game.glb")
const FALLEN_LOG_SCENE = preload("res://assets/gameplay/props/FallenLog_game.glb")
const POND_SEEDS_SCENE = preload("res://assets/gameplay/props/PondSeeds_game.glb")
const FLOWER_SCENE = preload("res://assets/gameplay/props/Flower_game.glb")
const TRAIL_HALF_WIDTH := 3.6
const TRAIL_EDGE_WIDTH := 4.5
# Landmarks (concept V3, made endless): at most one per region of 2 x 2 chunks,
# alternating by region so neighbours always differ. They sit on the open band
# between two trails, halfway between the stone pairs, never near the start.
enum Landmark { ROOT_ARCH, FALLEN_LOG, POND, MEADOW }
const LANDMARK_REGION := 2
const LANDMARK_START_CLEARANCE := 22.0
# Visual footprint used to keep leaf clumps and deco flowers off a landmark.
const LANDMARK_FOOTPRINT := [5.6, 4.2, 5.4, 4.6]
const ARCH_SIZE := Vector3(10.0, 8.0, 10.0)
# Arch feet relative to the model's footprint centre (model units, before scale).
const ARCH_FEET := [Vector2(-0.335, 0.055), Vector2(0.345, 0.065)]
const ARCH_FOOT_RADIUS := 1.5
const LOG_SIZE := Vector3(4.2, 3.6, 5.6)
const LOG_KNOTS := [-0.36, 0.0, 0.36]
const LOG_RADIUS := 0.75
const CACHE_LIMIT := 4096
# World seed: 0 is the hand-tuned classic layout (columns of trails, two stones
# per chunk). Any other seed builds a Megabonk/Minecraft-style variant from the
# same rules: regions of REGION x REGION chunks pick their own trail direction,
# curve, width, stone density, landmark mix and a soft ground tint.
const REGION := 3
const START_CLEARANCE := 22.0
# Minimum free gap between two collision formations (a walkable passage).
const MIN_PASSAGE := 3.0
# Upper bound for the collision area owned by one chunk.
const MAX_COLLISION_SHARE := 0.12
# Classic Verdant Maw values; the active colours come from scripts/biomes.gd.
const GROUND_COLOR := Color("80a04c")
# Flower petal ramp (dark -> light); see creature_look.gdshaderinc recolour.
const FLOWER_DARK := Color("6a5a8e")
const FLOWER_LIGHT := Color("c3b3de")
# Positive neighbour offsets; every trail edge is owned by its lower node.
const EDGE_OFFSETS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
const NEIGHBOURS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]
enum TrailDir { NORTH_SOUTH, EAST_WEST, DIAGONAL_NE, DIAGONAL_NW }
var world_seed := 0
# Active biome (scripts/biomes.gd): colours and decoration counts only; the
# layout (trails, stones, landmarks, collisions) never depends on it.
var biome_id: String = BIOMES.DEFAULT
var biome: Dictionary = BIOMES.get_data(BIOMES.DEFAULT)
var ground_color := GROUND_COLOR
var _seed_mix := 0
var view_radius := VISIBLE_RADIUS
var _last_sync := Vector3.ZERO
var _region_cache: Dictionary = {}
var _edge_cache: Dictionary = {}
var _near_edges_cache: Dictionary = {}
var _stone_cache: Dictionary = {}
var _block_cache: Dictionary = {}
var ground_tint_material: StandardMaterial3D
var chunks: Dictionary = {}
# Deterministic per-chunk data, cached because every creature queries it each frame.
var _obstacle_cache: Dictionary = {}
var _landmark_cache: Dictionary = {}
var ground_material: StandardMaterial3D
var path_material: StandardMaterial3D
var path_edge_material: StandardMaterial3D
var moss_materials: Array[StandardMaterial3D] = []
var sand_material: StandardMaterial3D
var earth_material: StandardMaterial3D
var plinth_material: StandardMaterial3D
var water_material: StandardMaterial3D
var shore_material: StandardMaterial3D
var rock_material: ShaderMaterial
var leaf_material: ShaderMaterial
var arch_material: ShaderMaterial
var log_material: ShaderMaterial
var reed_material: ShaderMaterial
var flower_material: ShaderMaterial
# Shared geometry: every chunk only adds instances of these.
var rock_mesh: Mesh
var rock_base: Transform3D
var leaf_mesh: Mesh
var leaf_base: Transform3D
var arch_mesh: Mesh
var arch_base: Transform3D
var log_mesh: Mesh
var log_base: Transform3D
var reed_mesh: Mesh
var reed_base: Transform3D
var flower_mesh: Mesh
var flower_base: Transform3D
var meadow_mesh: CylinderMesh
var ground_mesh: PlaneMesh
var patch_mesh: CylinderMesh
var plinth_mesh: CylinderMesh
var pool_mesh: CylinderMesh
var shore_mesh: CylinderMesh

func _ready() -> void:
	ground_material = _material(GROUND_COLOR)
	ground_tint_material = _material(Color.WHITE)
	ground_tint_material.vertex_color_use_as_albedo = true
	ground_tint_material.vertex_color_is_srgb = true
	path_material = _material(Color("d4b377"))
	path_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	path_edge_material = _material(Color("aeaa62"))
	path_edge_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for index in 3:
		moss_materials.append(_material(Color.WHITE))
	sand_material = _material(Color("c8ab6e"))
	earth_material = _material(Color("b39862"))
	plinth_material = _material(Color("62883a"))
	water_material = _material(Color("3fc0c4"))
	water_material.roughness = 0.35
	shore_material = _material(Color("dcd296"))
	rock_material = _prop_material(1.15, 1.0, 0.45, 0.12)
	leaf_material = _prop_material(1.1, 1.2, 0.4, 0.08)
	var rock_parts := _extract_mesh(ROCK_SCENE)
	rock_mesh = rock_parts[0]
	rock_base = rock_parts[1]
	var leaf_parts := _extract_mesh(LEAF_SCENE)
	leaf_mesh = leaf_parts[0]
	leaf_base = leaf_parts[1]
	arch_material = _prop_material(1.2, 1.05, 0.45, 0.12)
	log_material = _prop_material(1.2, 1.05, 0.45, 0.1)
	reed_material = _prop_material(1.2, 1.15, 0.4, 0.1)
	flower_material = _prop_material(1.05, 1.2, 0.3, 0.1)
	# Stage 05: petals move off the Mawling red/orange (and off the prey
	# turquoise) to a muted lavender that matches no strain; green leaves stay.
	flower_material.set_shader_parameter("recolor_dark", FLOWER_DARK)
	flower_material.set_shader_parameter("recolor_light", FLOWER_LIGHT)
	flower_material.set_shader_parameter("recolor_amount", 0.92)
	_apply_biome_colors()
	var arch_parts := _extract_mesh(ROOT_ARCH_SCENE)
	arch_mesh = arch_parts[0]
	arch_base = arch_parts[1]
	var log_parts := _extract_mesh(FALLEN_LOG_SCENE)
	log_mesh = log_parts[0]
	log_base = log_parts[1]
	var reed_parts := _extract_mesh(POND_SEEDS_SCENE)
	reed_mesh = reed_parts[0]
	reed_base = reed_parts[1]
	var flower_parts := _extract_mesh(FLOWER_SCENE)
	flower_mesh = flower_parts[0]
	flower_base = flower_parts[1]
	ground_mesh = PlaneMesh.new()
	ground_mesh.size = Vector2(CELL, CELL)
	patch_mesh = _disc(0.5, 0.5, 0.018)
	plinth_mesh = _disc(OBSTACLE_RADIUS + 0.1, OBSTACLE_RADIUS + 0.45, 0.06)
	pool_mesh = _disc(1.1, 1.1, 0.025)
	shore_mesh = _disc(1.45, 1.55, 0.02)
	meadow_mesh = _disc(1.0, 1.0, 0.012)
	sync(Vector3.ZERO)

func sync(position: Vector3) -> void:
	_last_sync = position
	var center := _cell(position)
	var wanted: Dictionary = {}
	for x in range(center.x - view_radius, center.x + view_radius + 1):
		for z in range(center.y - view_radius, center.y + view_radius + 1):
			var key := Vector2i(x, z)
			wanted[key] = true
			if not chunks.has(key):
				chunks[key] = _make_chunk(key)
	for key in chunks.keys():
		if not wanted.has(key):
			chunks[key].queue_free()
			chunks.erase(key)

func _cell(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / CELL), floori(position.z / CELL))

## Switches the map to another seed at runtime: every cache is dropped and the
## visible chunks are rebuilt around the last synced position. 0 = classic map.
func set_seed(value: int) -> void:
	world_seed = value
	_seed_mix = 0 if value == 0 else _scramble(value)
	for cache in [_obstacle_cache, _landmark_cache, _region_cache, _edge_cache, _near_edges_cache, _stone_cache, _block_cache]:
		cache.clear()
	for key in chunks.keys():
		var chunk: Node = chunks[key]
		remove_child(chunk)
		chunk.queue_free()
	chunks.clear()
	if ground_mesh != null:
		sync(_last_sync)

## Switches the biome at runtime (colours and decoration counts): the shared
## materials are restyled and the visible chunks rebuilt around the last synced
## position. Unknown ids fall back to verdant_maw. Layout and collisions stay.
func set_biome(id: String) -> void:
	biome_id = id if BIOMES.has(id) else BIOMES.DEFAULT
	biome = BIOMES.get_data(biome_id)
	if ground_material == null:
		return
	_apply_biome_colors()
	for key in chunks.keys():
		var chunk: Node = chunks[key]
		remove_child(chunk)
		chunk.queue_free()
	chunks.clear()
	sync(_last_sync)

# Writes the biome colours into the shared materials (every chunk uses them).
func _apply_biome_colors() -> void:
	ground_color = biome.ground
	ground_material.albedo_color = ground_color
	path_material.albedo_color = biome.path
	path_edge_material.albedo_color = biome.path_edge
	_set_glow(path_material, biome.path_emission)
	_set_glow(path_edge_material, biome.path_edge_emission)
	for index in moss_materials.size():
		moss_materials[index].albedo_color = biome.moss[index]
	sand_material.albedo_color = biome.sand
	earth_material.albedo_color = biome.earth
	plinth_material.albedo_color = biome.plinth
	water_material.albedo_color = biome.pool
	water_material.roughness = biome.pool_roughness
	_set_glow(water_material, biome.pool_emission)
	shore_material.albedo_color = biome.shore
	flower_material.set_shader_parameter("recolor_dark", biome.flower_dark)
	flower_material.set_shader_parameter("recolor_light", biome.flower_light)
	for pair in [[rock_material, "rock_tint"], [leaf_material, "leaf_tint"], [arch_material, "wood_tint"], [log_material, "wood_tint"], [reed_material, "reed_tint"], [flower_material, ""]]:
		var target: ShaderMaterial = pair[0]
		target.set_shader_parameter("rim_color", biome.prop_rim)
		# Flowers keep their own petal ramp; a tint would also grey their green leaves.
		target.set_shader_parameter("body_tint", biome[pair[1]] if pair[1] != "" else Color(1, 1, 1, 0))

static func _set_glow(target: StandardMaterial3D, glow: Color) -> void:
	target.emission_enabled = glow.r + glow.g + glow.b > 0.0
	target.emission = glow

static func _scramble(value: int) -> int:
	var n := (value ^ 0x2545F4914F6CDD1D) * 6364136223846793005
	n = (n ^ (n >> 29)) * 1442695040888963407
	n = n ^ (n >> 32)
	return n if n != 0 else 1

func obstacle_centers(key: Vector2i) -> Array[Vector3]:
	if world_seed != 0:
		var stones: Array[Vector3] = []
		for stone in _stones(key):
			stones.append(Vector3(stone.x, 0.0, stone.z))
		return stones
	var origin := Vector3(key.x * CELL, 0, key.y * CELL)
	var flip := 1.0 if _hash(key.x, key.y, 4) % 2 == 0 else -1.0
	var shift := float(_hash(key.x, key.y, 8) % 5 - 2) * 0.75
	return [origin + Vector3(-8.6, 0, flip * 7.6 + shift), origin + Vector3(8.6, 0, -flip * 7.6 + shift)]

# The seed only enters as an additive constant, so seed 0 keeps the classic hash.
func _hash(x: int, z: int, salt: int) -> int:
	var n := x * 374761393 + z * 668265263 + salt * 144269 + _seed_mix
	n = (n ^ (n >> 13)) * 1274126177
	return abs(n ^ (n >> 16))

func _unit(x: int, z: int, salt: int) -> float:
	return float(_hash(x, z, salt) % 1000) / 999.0

# The landmark hosted by this chunk, or {} (type, world centre, yaw).
func landmark(key: Vector2i) -> Dictionary:
	if _landmark_cache.has(key):
		return _landmark_cache[key]
	if _landmark_cache.size() > CACHE_LIMIT:
		_landmark_cache.clear()
	if world_seed != 0:
		var block := Vector2i(floori(float(key.x) / LANDMARK_REGION), floori(float(key.y) / LANDMARK_REGION))
		var seeded: Dictionary = _block_landmark(block)
		if seeded.is_empty() or _cell(seeded.center) != key:
			seeded = {}
		_landmark_cache[key] = seeded
		return seeded
	var result := {}
	var region := Vector2i(floori(float(key.x) / LANDMARK_REGION), floori(float(key.y) / LANDMARK_REGION))
	var host := _hash(region.x, region.y, 700) % (LANDMARK_REGION * LANDMARK_REGION)
	var host_key := region * LANDMARK_REGION + Vector2i(host % LANDMARK_REGION, host / LANDMARK_REGION)
	# Most regions carry one; a few stay completely open.
	if key == host_key and _hash(region.x, region.y, 710) % 5 != 0:
		var shift := float(_hash(key.x, key.y, 720) % 5 - 2) * 0.5
		var center := Vector3(key.x * CELL, 0.0, key.y * CELL + CELL * 0.5 + shift)
		if Vector2(center.x, center.z).length() >= LANDMARK_START_CLEARANCE:
			var type: int = posmod(region.x + 2 * region.y, 4)
			var yaw := 0.0
			match type:
				Landmark.ROOT_ARCH:
					yaw = float(_hash(key.x, key.y, 730) % 7 - 3) * 0.08
				Landmark.FALLEN_LOG:
					yaw = PI * 0.5 + float(_hash(key.x, key.y, 730) % 9 - 4) * 0.1
				_:
					yaw = float(_hash(key.x, key.y, 730) % 628) * 0.01
			result = {"type": type, "center": center, "yaw": yaw}
	_landmark_cache[key] = result
	return result

# Every collision circle owned by a chunk as Vector4(x, 0, z, radius): the two
# stones plus the small blocking parts of its landmark (arch feet, log).
func obstacles(key: Vector2i) -> Array[Vector4]:
	if _obstacle_cache.has(key):
		return _obstacle_cache[key]
	if _obstacle_cache.size() > CACHE_LIMIT:
		_obstacle_cache.clear()
	var result: Array[Vector4] = []
	if world_seed != 0:
		result.append_array(_stones(key))
	else:
		for center in obstacle_centers(key):
			result.append(Vector4(center.x, 0.0, center.z, OBSTACLE_RADIUS))
	result.append_array(_landmark_circles(landmark(key)))
	_obstacle_cache[key] = result
	return result

# The small blocking parts of a landmark (arch feet, log knots).
func _landmark_circles(mark: Dictionary) -> Array[Vector4]:
	var result: Array[Vector4] = []
	if mark.is_empty():
		return result
	var center: Vector3 = mark.center
	var turn := Basis(Vector3.UP, mark.yaw)
	match int(mark.type):
		Landmark.ROOT_ARCH:
			for foot in ARCH_FEET:
				var point: Vector3 = center + turn * Vector3(foot.x * ARCH_SIZE.x, 0.0, foot.y * ARCH_SIZE.z)
				result.append(Vector4(point.x, 0.0, point.z, ARCH_FOOT_RADIUS))
		Landmark.FALLEN_LOG:
			var length := _model_length(log_mesh, log_base) * LOG_SIZE.z
			for knot in LOG_KNOTS:
				var point: Vector3 = center + turn * Vector3(0.0, 0.0, knot * length)
				result.append(Vector4(point.x, 0.0, point.z, LOG_RADIUS))
	return result

# --- Seeded layout -------------------------------------------------------------

func _region_key(key: Vector2i) -> Vector2i:
	return Vector2i(floori(float(key.x) / REGION), floori(float(key.y) / REGION))

## Parameters shared by all chunks of one region (seeded maps only).
func region_params(region: Vector2i) -> Dictionary:
	if _region_cache.has(region):
		return _region_cache[region]
	if _region_cache.size() > CACHE_LIMIT:
		_region_cache.clear()
	var roll := _hash(region.x, region.y, 900) % 100
	var dir := TrailDir.NORTH_SOUTH if roll < 34 else (TrailDir.EAST_WEST if roll < 68 else (TrailDir.DIAGONAL_NE if roll < 84 else TrailDir.DIAGONAL_NW))
	var result := {
		"dir": dir,
		"amplitude": 1.2 + float(_hash(region.x, region.y, 901) % 23) * 0.1,
		"frequency": 1.0 + float(_hash(region.x, region.y, 902) % 3) * 0.5,
		"phase": float(_hash(region.x, region.y, 903) % 628) * 0.01,
		"half_width": 3.0 + float(_hash(region.x, region.y, 904) % 9) * 0.1,
		"stones": 1.5 + float(_hash(region.x, region.y, 905) % 11) * 0.1,
		"landmark_chance": 0.55 + float(_hash(region.x, region.y, 906) % 8) * 0.05,
		"landmark_type": _hash(region.x, region.y, 907) % 4,
		"pond_chance": 0.08 + float(_hash(region.x, region.y, 908) % 5) * 0.05,
		"flower_chance": 0.2 + float(_hash(region.x, region.y, 909) % 5) * 0.08,
		"hue": float(_hash(region.x, region.y, 910) % 9 - 4) * 0.005,
		"value": float(_hash(region.x, region.y, 911) % 9 - 4) * 0.01,
	}
	_region_cache[region] = result
	return result

func _chunk_params(key: Vector2i) -> Dictionary:
	return region_params(_region_key(key))

# Trail junction of a chunk, always well inside it.
func _node(key: Vector2i) -> Vector3:
	return Vector3(key.x * CELL + 10.0 + float(_hash(key.x, key.y, 912) % 81) * 0.1, 0.0, key.y * CELL + 10.0 + float(_hash(key.x, key.y, 913) % 81) * 0.1)

# Straight regions leave about every third lane without a trail, so the map
# is not a regular ladder and keeps wide open bands.
func _links(key: Vector2i) -> Array:
	var region := _region_key(key)
	match int(_chunk_params(key).dir):
		TrailDir.NORTH_SOUTH:
			return [Vector2i(0, 1), Vector2i(0, -1)] if _hash(key.x, region.y, 915) % 10 < 7 else []
		TrailDir.EAST_WEST:
			return [Vector2i(1, 0), Vector2i(-1, 0)] if _hash(region.x, key.y, 916) % 10 < 7 else []
		TrailDir.DIAGONAL_NE:
			return [Vector2i(1, 1), Vector2i(-1, -1)] if posmod(key.x - key.y, 2) == 0 else []
		_:
			return [Vector2i(1, -1), Vector2i(-1, 1)] if posmod(key.x + key.y, 2) == 0 else []

# An edge exists if either end asks for it, so trails always continue across
# chunk and region borders (a region change becomes a junction).
func _has_edge(a: Vector2i, b: Vector2i) -> bool:
	return _links(a).has(b - a) or _links(b).has(a - b)

func _edge(a: Vector2i, index: int) -> Dictionary:
	var id := Vector3i(a.x, a.y, index)
	if _edge_cache.has(id):
		return _edge_cache[id]
	if _edge_cache.size() > CACHE_LIMIT:
		_edge_cache.clear()
	var b: Vector2i = a + EDGE_OFFSETS[index]
	var params := _chunk_params(a)
	var start := _node(a)
	var along := _node(b) - start
	var length := along.length()
	var side := Vector3(along.z, 0.0, -along.x) / length
	var steps := maxi(10, ceili(length / 1.2))
	var phase: float = params.phase + float(_hash(a.x, a.y, 920 + index) % 100) * 0.02
	var points := PackedVector3Array()
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for step in steps + 1:
		var t := float(step) / float(steps)
		var point: Vector3 = start + along * t + side * (float(params.amplitude) * sin(PI * t) * sin(PI * t * float(params.frequency) + phase))
		points.append(point)
		low = Vector2(minf(low.x, point.x), minf(low.y, point.z))
		high = Vector2(maxf(high.x, point.x), maxf(high.y, point.z))
	var result := {"points": points, "half": float(params.half_width), "low": low, "high": high}
	_edge_cache[id] = result
	return result

# Every trail edge that may come within 12 m of this chunk.
func _edges_near(key: Vector2i) -> Array:
	if _near_edges_cache.has(key):
		return _near_edges_cache[key]
	if _near_edges_cache.size() > CACHE_LIMIT:
		_near_edges_cache.clear()
	var low := Vector2(key.x * CELL - 12.0, key.y * CELL - 12.0)
	var high := low + Vector2(CELL + 24.0, CELL + 24.0)
	var result := []
	for x in range(key.x - 2, key.x + 3):
		for z in range(key.y - 2, key.y + 3):
			var a := Vector2i(x, z)
			for index in EDGE_OFFSETS.size():
				if not _has_edge(a, a + EDGE_OFFSETS[index]):
					continue
				var edge := _edge(a, index)
				if edge.high.x >= low.x and edge.low.x <= high.x and edge.high.y >= low.y and edge.low.y <= high.y:
					result.append(edge)
	_near_edges_cache[key] = result
	return result

static func _segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
	return point.distance_to(a + ab * t)

## Distance from a point to the sand edge of the nearest trail (negative = on it).
func trail_clearance(world: Vector3) -> float:
	var key := _cell(world)
	if world_seed == 0:
		return absf(world.x - key.x * CELL - _trail_center(key, world.z - key.y * CELL)) - TRAIL_HALF_WIDTH
	var point := Vector2(world.x, world.z)
	var best := INF
	for edge in _edges_near(key):
		var half: float = edge.half
		var low: Vector2 = edge.low
		var high: Vector2 = edge.high
		if point.x < low.x - best - half or point.x > high.x + best + half or point.y < low.y - best - half or point.y > high.y + best + half:
			continue
		var points: PackedVector3Array = edge.points
		for index in points.size() - 1:
			var distance := _segment_distance(point, Vector2(points[index].x, points[index].z), Vector2(points[index + 1].x, points[index + 1].z)) - half
			best = minf(best, distance)
	return best

## Centreline samples (x, 0, z, half width) of every trail crossing this chunk.
func trail_samples(key: Vector2i) -> Array[Vector4]:
	var result: Array[Vector4] = []
	var area := Rect2(key.x * CELL, key.y * CELL, CELL, CELL)
	if world_seed == 0:
		for step in 29:
			var z := float(step)
			result.append(Vector4(key.x * CELL + _trail_center(key, z), 0.0, key.y * CELL + z, TRAIL_HALF_WIDTH))
		return result
	for edge in _edges_near(key):
		for point in edge.points:
			if area.has_point(Vector2(point.x, point.z)):
				result.append(Vector4(point.x, 0.0, point.z, edge.half))
	return result

# A trail stone group: one main stone, sometimes with a smaller stone leaning on
# it. Groups keep MIN_PASSAGE to everything else and stay inside their chunk.
func _stones(key: Vector2i) -> Array[Vector4]:
	if _stone_cache.has(key):
		return _stone_cache[key]
	if _stone_cache.size() > CACHE_LIMIT:
		_stone_cache.clear()
	var params := _chunk_params(key)
	var count := clampi(floori(float(params.stones) + (_unit(key.x, key.y, 940) - 0.5) * 2.0 + 0.5), 0, 3)
	var blockers: Array[Vector4] = []
	var marks: Array[Dictionary] = []
	for x in range(key.x - 1, key.x + 2):
		for z in range(key.y - 1, key.y + 2):
			var mark := landmark(Vector2i(x, z))
			if not mark.is_empty():
				marks.append(mark)
				blockers.append_array(_landmark_circles(mark))
	var result: Array[Vector4] = []
	var area := 0.0
	for landmark_circle in _landmark_circles(landmark(key)):
		area += PI * landmark_circle.w * landmark_circle.w
	for group_index in count:
		for attempt in 10:
			var salt := 1000 + group_index * 60 + attempt * 5
			var main_radius := OBSTACLE_RADIUS * (0.88 + float(_hash(key.x, key.y, salt) % 5) * 0.06)
			var group: Array[Vector4] = []
			var reach := main_radius
			var side_stone := _hash(key.x, key.y, salt + 1) % 3 == 0
			var side_radius := 0.9 + float(_hash(key.x, key.y, salt + 2) % 4) * 0.1
			if side_stone:
				reach = (main_radius + side_radius) * 0.8 + side_radius
			var inset := reach + MIN_PASSAGE * 0.5
			var center := Vector3(key.x * CELL + inset + _unit(key.x, key.y, salt + 3) * (CELL - 2.0 * inset), 0.0, key.y * CELL + inset + _unit(key.x, key.y, salt + 4) * (CELL - 2.0 * inset))
			group.append(Vector4(center.x, 0.0, center.z, main_radius))
			if side_stone:
				var angle := float(_hash(key.x, key.y, salt + 2) % 628) * 0.01
				var offset := Vector3(cos(angle), 0.0, sin(angle)) * (main_radius + side_radius) * 0.8
				group.append(Vector4(center.x + offset.x, 0.0, center.z + offset.z, side_radius))
			var group_area := 0.0
			for stone in group:
				group_area += PI * stone.w * stone.w
			if area + group_area > MAX_COLLISION_SHARE * CELL * CELL:
				continue
			if Vector2(center.x, center.z).length() - reach < START_CLEARANCE:
				continue
			var fits := true
			for mark in marks:
				var mark_center: Vector3 = mark.center
				if Vector2(center.x - mark_center.x, center.z - mark_center.z).length() < LANDMARK_FOOTPRINT[int(mark.type)] + reach + 0.3:
					fits = false
			for stone in group:
				if not fits:
					break
				if trail_clearance(Vector3(stone.x, 0.0, stone.z)) < stone.w + 1.3:
					fits = false
				for other in blockers + result:
					if Vector2(stone.x - other.x, stone.z - other.z).length() - stone.w - other.w < MIN_PASSAGE:
						fits = false
						break
			if fits:
				result.append_array(group)
				area += group_area
				break
	_stone_cache[key] = result
	return result

# One landmark per block of LANDMARK_REGION x LANDMARK_REGION chunks, inset so
# landmarks of neighbouring blocks never crowd each other; owned by the chunk
# that holds its centre.
func _block_landmark(block: Vector2i) -> Dictionary:
	if _block_cache.has(block):
		return _block_cache[block]
	if _block_cache.size() > CACHE_LIMIT:
		_block_cache.clear()
	var result := {}
	var params := _chunk_params(block * LANDMARK_REGION)
	if _unit(block.x, block.y, 700) < float(params.landmark_chance):
		var type: int = int(params.landmark_type) if _hash(block.x, block.y, 705) % 100 < 55 else _hash(block.x, block.y, 706) % 4
		var footprint: float = LANDMARK_FOOTPRINT[type]
		var span := CELL * LANDMARK_REGION
		var inset := footprint + MIN_PASSAGE * 0.5
		for attempt in 12:
			var center := Vector3(block.x * span + inset + _unit(block.x, block.y, 710 + attempt * 2) * (span - 2.0 * inset), 0.0, block.y * span + inset + _unit(block.x, block.y, 711 + attempt * 2) * (span - 2.0 * inset))
			if Vector2(center.x, center.z).length() < START_CLEARANCE + footprint:
				continue
			if trail_clearance(center) < footprint + 0.3:
				continue
			var yaw := float(_hash(block.x, block.y, 730) % 628) * 0.01
			if type == Landmark.ROOT_ARCH or type == Landmark.FALLEN_LOG:
				# Gate and log follow the local trail direction, so they frame the route.
				var along: float = [0.0, PI * 0.5, PI * 0.25, PI * 0.75][int(_chunk_params(_cell(center)).dir)]
				yaw = along + float(_hash(block.x, block.y, 731) % 7 - 3) * 0.08
			result = {"type": type, "center": center, "yaw": yaw}
			break
	_block_cache[block] = result
	return result

# Smooth ground tint: region colours blended bilinearly between region centres.
func _ground_tint(x: float, z: float) -> Color:
	var fx := x / (REGION * CELL) - 0.5
	var fz := z / (REGION * CELL) - 0.5
	var ix := floori(fx)
	var iz := floori(fz)
	var tx := smoothstep(0.0, 1.0, fx - ix)
	var tz := smoothstep(0.0, 1.0, fz - iz)
	var hue := 0.0
	var value := 0.0
	for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		var weight := (tx if corner.x == 1 else 1.0 - tx) * (tz if corner.y == 1 else 1.0 - tz)
		var params := region_params(Vector2i(ix + corner.x, iz + corner.y))
		hue += float(params.hue) * weight
		value += float(params.value) * weight
	return Color.from_hsv(ground_color.h + hue, ground_color.s, ground_color.v * (1.0 + value))

func _ground_mesh(key: Vector2i) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector3(0, 0, 0), Vector3(CELL, 0, 0), Vector3(CELL, 0, CELL), Vector3(0, 0, CELL)]
	for index in [0, 1, 2, 0, 2, 3]:
		var corner: Vector3 = corners[index]
		surface.set_color(_ground_tint(key.x * CELL + corner.x, key.y * CELL + corner.z))
		surface.set_normal(Vector3.UP)
		surface.add_vertex(corner)
	return surface.commit()

# Trail band of this chunk: every segment whose midpoint lies inside the chunk
# (so neighbours tile seamlessly) plus a round junction at the chunk's node.
func _network_mesh(key: Vector2i, extra: float, height: float) -> Mesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var origin := Vector3(key.x * CELL, 0.0, key.y * CELL)
	var area := Rect2(origin.x, origin.z, CELL, CELL)
	var lift := Vector3(0.0, height, 0.0)
	var count := 0
	for edge in _edges_near(key):
		var points: PackedVector3Array = edge.points
		var half: float = edge.half + extra
		for index in points.size() - 1:
			var middle := (points[index] + points[index + 1]) * 0.5
			if not area.has_point(Vector2(middle.x, middle.z)):
				continue
			var side0 := _side(points, index) * half
			var side1 := _side(points, index + 1) * half
			var a := points[index] - origin + lift
			var b := points[index + 1] - origin + lift
			for point in [a - side0, a + side0, b - side1, a + side0, b + side1, b - side1]:
				surface.set_normal(Vector3.UP)
				surface.add_vertex(point)
			count += 1
	var junction := 0.0
	for offset in NEIGHBOURS:
		if _has_edge(key, key + offset):
			var owner: Vector2i = key if EDGE_OFFSETS.has(offset) else key + offset
			junction = maxf(junction, float(_chunk_params(owner).half_width))
	if junction > 0.0:
		var node := _node(key) - origin + lift
		var radius := junction + extra
		for index in 16:
			var angle0 := TAU * float(index) / 16.0
			var angle1 := TAU * float(index + 1) / 16.0
			for point in [node, node + Vector3(cos(angle0), 0.0, sin(angle0)) * radius, node + Vector3(cos(angle1), 0.0, sin(angle1)) * radius]:
				surface.set_normal(Vector3.UP)
				surface.add_vertex(point)
			count += 1
	if count == 0:
		return null
	return surface.commit()

static func _side(points: PackedVector3Array, index: int) -> Vector3:
	var direction := points[mini(index + 1, points.size() - 1)] - points[maxi(index - 1, 0)]
	return Vector3(direction.z, 0.0, -direction.x).normalized()

func _model_length(mesh: Mesh, base: Transform3D) -> float:
	if mesh == null:
		return 1.157
	return (base * mesh.get_aabb()).size.z

# True if a landmark of this or a neighbouring chunk covers the spot visually.
func near_landmark(location: Vector3, margin: float) -> bool:
	var middle := _cell(location)
	for x in range(middle.x - 1, middle.x + 2):
		for z in range(middle.y - 1, middle.y + 2):
			var mark := landmark(Vector2i(x, z))
			if not mark.is_empty():
				var center: Vector3 = mark.center
				if Vector2(location.x - center.x, location.z - center.z).length() < LANDMARK_FOOTPRINT[int(mark.type)] + margin:
					return true
	return false

func resolve_motion(start: Vector3, motion: Vector3, radius: float) -> Vector3:
	var result := start + motion
	# Resolve X and Z separately so the joystick naturally slides along stone.
	result.x = _push_out(Vector3(result.x, 0, start.z), radius).x
	result.z = _push_out(Vector3(result.x, 0, result.z), radius).z
	return result

func _push_out(point: Vector3, radius: float) -> Vector3:
	var middle := _cell(point)
	# Log knots overlap, so a push out of one may land in the next: repeat a few
	# times until nothing moves (lone stones always settle in the first pass).
	for attempt in 4:
		var moved := false
		for x in range(middle.x - 1, middle.x + 2):
			for z in range(middle.y - 1, middle.y + 2):
				for circle in obstacles(Vector2i(x, z)):
					var offset := Vector2(point.x - circle.x, point.z - circle.z)
					var minimum := circle.w + radius
					if offset.length_squared() < minimum * minimum - 0.000001:
						var normal := offset.normalized() if offset.length_squared() > 0.0001 else Vector2.RIGHT
						point.x = circle.x + normal.x * minimum
						point.z = circle.z + normal.y * minimum
						moved = true
		if not moved:
			break
	return point

func is_open(location: Vector3, radius: float) -> bool:
	var middle := _cell(location)
	for x in range(middle.x - 1, middle.x + 2):
		for z in range(middle.y - 1, middle.y + 2):
			for circle in obstacles(Vector2i(x, z)):
				if Vector2(location.x - circle.x, location.z - circle.z).length() < circle.w + radius:
					return false
	return true

func clear_line(start: Vector3, desired_end: Vector3, radius: float) -> Vector3:
	var distance := start.distance_to(desired_end)
	var samples := maxi(1, ceili(distance / 0.25))
	var clear := start
	for index in range(1, samples + 1):
		var candidate := start.lerp(desired_end, float(index) / samples)
		if not is_open(candidate, radius):
			break
		clear = candidate
	return clear

func steer_direction(start: Vector3, target: Vector3, radius: float) -> Vector3:
	var desired := target - start
	desired.y = 0
	if desired.length_squared() < 0.0001:
		return Vector3.ZERO
	var forward := desired.normalized()
	if clear_line(start, start + forward * minf(3.5, desired.length()), radius).distance_to(start) >= minf(3.5, desired.length()) - 0.2:
		return forward
	var best := INF
	var side := 1.0
	var middle := _cell(start)
	for x in range(middle.x - 1, middle.x + 2):
		for z in range(middle.y - 1, middle.y + 2):
			for circle in obstacles(Vector2i(x, z)):
				var offset := Vector3(circle.x - start.x, 0.0, circle.z - start.z)
				var ahead := offset.dot(forward)
				var cross := forward.x * offset.z - forward.z * offset.x
				if ahead > 0 and ahead < 4.5 and absf(cross) < circle.w + radius + 0.5 and ahead < best:
					best = ahead
					side = 1.0 if cross >= 0 else -1.0
	return Vector3(forward.z * side, 0, -forward.x * side)

func safe_spawn(location: Vector3, radius: float) -> Vector3:
	return _push_out(location, radius)

func _make_chunk(key: Vector2i) -> Node3D:
	var chunk := Node3D.new()
	chunk.name = "Jungle %d %d" % [key.x, key.y]
	chunk.position = Vector3(key.x * CELL, 0, key.y * CELL)
	add_child(chunk)
	var seeded := world_seed != 0
	if seeded:
		_part(chunk, "Open ground", _ground_mesh(key), ground_tint_material, Vector3(0, -0.02, 0))
		_part(chunk, "Trail edge", _network_mesh(key, TRAIL_EDGE_WIDTH - TRAIL_HALF_WIDTH, 0.003), path_edge_material, Vector3.ZERO)
		_part(chunk, "Broad trail", _network_mesh(key, 0.0, 0.007), path_material, Vector3.ZERO)
	else:
		_part(chunk, "Open ground", ground_mesh, ground_material, Vector3(CELL * 0.5, -0.02, CELL * 0.5))
		_part(chunk, "Trail edge", _trail_mesh(key, TRAIL_EDGE_WIDTH, 0.003), path_edge_material, Vector3.ZERO)
		_part(chunk, "Broad trail", _trail_mesh(key, TRAIL_HALF_WIDTH, 0.007), path_material, Vector3.ZERO)
	# Calm ground variation: soft moss tints, a few sand/earth spots, small pebbles.
	for index in int(biome.moss_patches):
		var spot := Vector3(2.0 + float(_hash(key.x, key.y, index + 30) % 24), 0.001, 2.0 + float(_hash(key.x, key.y, index + 60) % 24))
		if _near_trail(chunk.position + spot, 1.0):
			continue
		var tint := moss_materials[_hash(key.x, key.y, index + 90) % moss_materials.size()]
		var moss := _part(chunk, "Low leaf cover", patch_mesh, tint, spot)
		var size := 1.3 + float(_hash(key.x, key.y, index + 120) % 5) * 0.3
		moss.scale = Vector3(size * 1.5, 1, size)
		moss.rotation.y = float(_hash(key.x, key.y, index + 150) % 628) * 0.01
	for index in int(biome.sand_patches):
		var spot := Vector3(2.0 + float(_hash(key.x, key.y, index + 180) % 24), 0.002, 2.0 + float(_hash(key.x, key.y, index + 210) % 24))
		if _near_trail(chunk.position + spot, 1.5):
			continue
		var dirt := _part(chunk, "Sand patch", patch_mesh, sand_material if index % 3 != 2 else earth_material, spot)
		var size := 1.2 + float(_hash(key.x, key.y, index + 240) % 4) * 0.3
		dirt.scale = Vector3(size * 1.4, 1, size)
		dirt.rotation.y = float(_hash(key.x, key.y, index + 270) % 628) * 0.01
	for index in int(biome.pebbles):
		var spot := Vector3(1.0 + float(_hash(key.x, key.y, index + 300) % 26), 0, 1.0 + float(_hash(key.x, key.y, index + 330) % 26))
		var size := 0.32 + float(_hash(key.x, key.y, index + 360) % 4) * 0.07
		_prop(chunk, "Pebble", rock_mesh, rock_base, rock_material, spot, Vector3(size, size * 0.8, size), float(_hash(key.x, key.y, index + 390) % 628) * 0.01)
	if seeded:
		for stone in _stones(key):
			_boulder(chunk, Vector3(stone.x, 0.0, stone.z), stone.w)
	else:
		for center in obstacle_centers(key):
			_boulder(chunk, center, OBSTACLE_RADIUS)
	# Scattered leaf clumps at the edges of the open ground: never on the trail,
	# never in the middle of the chunk, never inside a stone footprint.
	var placed := 0
	var wanted := int(biome.leaf_clumps_min) + _hash(key.x, key.y, 400) % 3
	for index in 14:
		if placed >= wanted:
			break
		var local := Vector3(1.0 + float(_hash(key.x, key.y, index + 410) % 26), 0, 1.0 + float(_hash(key.x, key.y, index + 440) % 26))
		var world := chunk.position + local
		if local.distance_to(Vector3(CELL * 0.5, 0, CELL * 0.5)) < 7.0 or _near_trail(world, 1.2) or not is_open(world, 0.6) or near_landmark(world, 0.5):
			continue
		var size := 1.05 + float(_hash(key.x, key.y, index + 470) % 5) * 0.1
		_prop(chunk, "Leaf clump", leaf_mesh, leaf_base, leaf_material, local, Vector3.ONE * size, float(_hash(key.x, key.y, index + 500) % 628) * 0.01)
		placed += 1
	if seeded:
		_seeded_decor(chunk, key)
	# A rare water landmark is flat and traversable; the route stays open.
	elif _hash(key.x, key.y, 13) % int(biome.pond_one_in) == 0 and not near_landmark(chunk.position + Vector3(4, 0, 22), 3.0):
		_pool(chunk, Vector3(4, 0, 22), Vector3(1.8, 1, 1.1))
		# A single reed clump on the far shore.
		_prop(chunk, "Pond reeds", reed_mesh, reed_base, reed_material, Vector3(6.3, 0, 21.1), Vector3.ONE * 1.5, float(_hash(key.x, key.y, 14) % 628) * 0.01)
	# Rare single flowers as colour accents on the open ground.
	if not seeded and _hash(key.x, key.y, 800) % int(biome.flower_one_in) == 0:
		var local := Vector3(2.0 + float(_hash(key.x, key.y, 810) % 24), 0, 2.0 + float(_hash(key.x, key.y, 820) % 24))
		var world := chunk.position + local
		if not _near_trail(world, 1.2) and is_open(world, 1.0) and not near_landmark(world, 1.0):
			_prop(chunk, "Wild flower", flower_mesh, flower_base, flower_material, local, Vector3.ONE * 2.1, float(_hash(key.x, key.y, 830) % 628) * 0.01)
	var mark := landmark(key)
	if not mark.is_empty():
		_landmark(chunk, key, mark)
	return chunk

func _pool(chunk: Node3D, location: Vector3, size: Vector3) -> void:
	var shore := _part(chunk, "Pool shore", shore_mesh, shore_material, location + Vector3(0, 0.01, 0))
	shore.scale = size
	var water := _part(chunk, "Shallow pool", pool_mesh, water_material, location + Vector3(0, 0.02, 0))
	water.scale = size

func _landmark(chunk: Node3D, key: Vector2i, mark: Dictionary) -> void:
	var local: Vector3 = mark.center - chunk.position
	var yaw: float = mark.yaw
	match int(mark.type):
		Landmark.ROOT_ARCH:
			# A gate over open ground: only the two feet block, the passage stays free.
			for foot in ARCH_FEET:
				var spot: Vector3 = local + Basis(Vector3.UP, yaw) * Vector3(foot.x * ARCH_SIZE.x, 0.0, foot.y * ARCH_SIZE.z)
				var moss := _part(chunk, "Arch foot moss", patch_mesh, plinth_material, spot + Vector3(0, 0.01, 0))
				moss.scale = Vector3(4.4, 1, 4.4)
			_prop(chunk, "Root arch", arch_mesh, arch_base, arch_material, local, ARCH_SIZE, yaw)
		Landmark.FALLEN_LOG:
			var moss := _part(chunk, "Log moss", patch_mesh, moss_materials[1], local + Vector3(0, 0.004, 0))
			moss.scale = Vector3(3.2, 1, 7.6)
			moss.rotation.y = yaw
			_prop(chunk, "Fallen log", log_mesh, log_base, log_material, local, LOG_SIZE, yaw)
		Landmark.POND:
			# Walkable water with reeds and seed pods along the shore; no collision.
			var size := Vector3(3.2, 1, 2.3)
			_pool(chunk, local, size)
			var count := 3 + _hash(key.x, key.y, 740) % 2
			for index in count:
				var angle := yaw + float(index) * TAU / float(count) + float(_hash(key.x, key.y, 750 + index) % 5) * 0.1
				var spot := local + Vector3(cos(angle) * 1.3 * size.x, 0, sin(angle) * 1.3 * size.z)
				var reed_size := 1.6 + float(_hash(key.x, key.y, 760 + index) % 4) * 0.15
				_prop(chunk, "Pond reeds", reed_mesh, reed_base, reed_material, spot, Vector3.ONE * reed_size, angle)
		Landmark.MEADOW:
			# A calm clearing dotted with 5-9 flowers: pure colour, no collision.
			var ground := _part(chunk, "Meadow", meadow_mesh, moss_materials[0], local + Vector3(0, 0.003, 0))
			ground.scale = Vector3(4.6, 1, 3.8)
			ground.rotation.y = yaw
			var count := 5 + _hash(key.x, key.y, 740) % 5
			for index in count:
				var angle := float(index) * 2.39996 + yaw
				var distance := 1.0 + 3.8 * sqrt((float(index) + 0.5) / float(count))
				var spot := local + Vector3(cos(angle) * distance, 0, sin(angle) * distance * 0.85)
				var flower_size := 1.7 + float(_hash(key.x, key.y, 760 + index) % 5) * 0.15
				_prop(chunk, "Meadow flower", flower_mesh, flower_base, flower_material, spot, Vector3.ONE * flower_size, float(_hash(key.x, key.y, 780 + index) % 628) * 0.01)

func _trail_center(key: Vector2i, local_z: float) -> float:
	return 14.0 + 3.2 * sin((key.y * CELL + local_z) * 0.09 + key.x * 0.7)

func _near_trail(world: Vector3, margin: float) -> bool:
	if world_seed != 0:
		return trail_clearance(world) < margin
	var key := _cell(world)
	var local_x := world.x - key.x * CELL
	return absf(local_x - _trail_center(key, world.z - key.y * CELL)) < TRAIL_HALF_WIDTH + margin

func _trail_mesh(key: Vector2i, half_width: float, height: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for step_index in 8:
		var z0 := float(step_index) * CELL / 8.0
		var z1 := float(step_index + 1) * CELL / 8.0
		var center0 := _trail_center(key, z0)
		var center1 := _trail_center(key, z1)
		var left0 := Vector3(center0 - half_width, height, z0)
		var right0 := Vector3(center0 + half_width, height, z0)
		var left1 := Vector3(center1 - half_width, height, z1)
		var right1 := Vector3(center1 + half_width, height, z1)
		for point in [left0, right0, left1, right0, right1, left1]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(point)
	return surface.commit()

func _seeded_decor(chunk: Node3D, key: Vector2i) -> void:
	var params := _chunk_params(key)
	# Small flat pools: walkable, placed on open ground away from trail and stones.
	if _unit(key.x, key.y, 13) < float(params.pond_chance):
		for attempt in 4:
			var local := Vector3(5.0 + _unit(key.x, key.y, 15 + attempt * 2) * 18.0, 0, 5.0 + _unit(key.x, key.y, 16 + attempt * 2) * 18.0)
			var world := chunk.position + local
			if _near_trail(world, 3.2) or not is_open(world, 3.2) or near_landmark(world, 3.0):
				continue
			var size := Vector3(1.5 + _unit(key.x, key.y, 24) * 0.6, 1, 1.0 + _unit(key.x, key.y, 25) * 0.3)
			_pool(chunk, local, size)
			var angle := float(_hash(key.x, key.y, 14) % 628) * 0.01
			_prop(chunk, "Pond reeds", reed_mesh, reed_base, reed_material, local + Vector3(cos(angle) * 1.4 * size.x, 0, sin(angle) * 1.4 * size.z), Vector3.ONE * 1.5, angle)
			break
	# Single wild flowers as colour accents; flowery regions get a second one.
	var flowers := 0
	if _unit(key.x, key.y, 800) < float(params.flower_chance):
		flowers = 1 + (1 if float(params.flower_chance) > 0.4 else 0)
	for index in flowers:
		var local := Vector3(2.0 + float(_hash(key.x, key.y, 810 + index * 3) % 24), 0, 2.0 + float(_hash(key.x, key.y, 820 + index * 3) % 24))
		var world := chunk.position + local
		if not _near_trail(world, 1.2) and is_open(world, 1.0) and not near_landmark(world, 1.0):
			_prop(chunk, "Wild flower", flower_mesh, flower_base, flower_material, local, Vector3.ONE * 2.1, float(_hash(key.x, key.y, 830 + index) % 628) * 0.01)

func _boulder(chunk: Node3D, center: Vector3, radius: float) -> void:
	var location := center - chunk.position
	var roll := _hash(roundi(center.x * 10.0), roundi(center.z * 10.0), 7)
	var stone_scale := radius / OBSTACLE_RADIUS
	var plinth := _part(chunk, "Stone footprint", plinth_mesh, plinth_material, location + Vector3(0, 0.02, 0))
	plinth.scale = Vector3(stone_scale, 1.0, stone_scale)
	var size := (0.92 + float(roll % 9) * 0.02) * stone_scale
	var yaw := float((roll >> 4) % 628) * 0.01
	_prop(chunk, "Low stone", rock_mesh, rock_base, rock_material, location, Vector3(3.9, 3.2, 3.6) * size, yaw)
	var count := 2 + (roll >> 8) % 2
	for index in count:
		var angle := yaw + float(index) * TAU / float(count) + float((roll >> (10 + index * 3)) % 7) * 0.12
		var foot := location + Vector3(cos(angle), 0, sin(angle)) * (radius + 0.1)
		if _near_trail(chunk.position + foot, 0.3):
			continue
		var leaf_size := 1.15 + float((roll >> (14 + index)) % 4) * 0.1
		_prop(chunk, "Broad leaf", leaf_mesh, leaf_base, leaf_material, foot, Vector3.ONE * leaf_size, angle)

func _prop(parent: Node3D, label: String, mesh: Mesh, base: Transform3D, material: Material, location: Vector3, size: Vector3, yaw: float) -> MeshInstance3D:
	var part := _part(parent, label, mesh, material, location)
	var shape := Basis(Vector3.UP, yaw) * Basis.from_scale(size) * base.basis
	# Rest the model on the ground and centre it over its footprint.
	var bounds: AABB = Transform3D(shape, Vector3.ZERO) * mesh.get_aabb()
	part.transform = Transform3D(shape, location + Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z))
	return part

func _extract_mesh(scene: PackedScene) -> Array:
	var root := scene.instantiate()
	var model: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]
	var base := Transform3D.IDENTITY
	var node: Node = model
	while node != root and node is Node3D:
		base = (node as Node3D).transform * base
		node = node.get_parent()
	var result := [model.mesh, base]
	root.free()
	return result

func _disc(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 24
	mesh.rings = 1
	return mesh

func _prop_material(brightness: float, saturation: float, shape_light: float, rim: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CREATURE_SHADER
	material.set_shader_parameter("brightness", brightness)
	material.set_shader_parameter("saturation", saturation)
	material.set_shader_parameter("shape_light", shape_light)
	material.set_shader_parameter("rim_color", Color("f2f0c8"))
	material.set_shader_parameter("rim_strength", rim)
	return material

func _material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.95
	return result

func _part(parent: Node3D, label: String, mesh: Mesh, material: Material, location: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = mesh
	part.material_override = material
	part.position = location
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part


