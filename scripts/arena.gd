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
const QUALITY = preload("res://scripts/quality.gd")
const REGION_NAMES = preload("res://scripts/region_names.gd")
# Glutsumpf look (biomes with an "ember" block); Verdant never touches these.
const EMBER_GROUND_SHADER = preload("res://shaders/ember_ground.gdshader")
const EMBER_CHANNEL_SHADER = preload("res://shaders/ember_channel.gdshader")
const LAVA_SHADER = preload("res://shaders/lava.gdshader")
# Half width of the glowing core of a glow channel (metres).
const CHANNEL_CORE := 1.0
# Extinct stumps standing on the three collision knots of a fallen-log landmark.
const STUMP_HEIGHTS := [1.3, 2.2, 0.9]
# Biome/density switches rebuild at most this many chunks per sync() (one frame),
# nearest first, so a migration never builds nine chunks in one frame.
const REBUILDS_PER_SYNC := 1
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
# Share of purely decorative chunk parts (quality.gd "decor_density"): moss,
# sand/ash patches, pebbles, leaf clumps, flowers, leaves at stones. Stones,
# trails, pools and landmarks always stay. 1.0 = full classic decoration.
var decor_density := 1.0
# Chunks still showing the previous biome/density (rebuilt gradually in sync()).
var _stale: Dictionary = {}
var ground_color := GROUND_COLOR
var _seed_mix := 0
var view_radius := VISIBLE_RADIUS
var _last_sync := Vector3.ZERO
var _region_cache: Dictionary = {}
var _edge_cache: Dictionary = {}
var _near_edges_cache: Dictionary = {}
var _stone_cache: Dictionary = {}
var _block_cache: Dictionary = {}
# Region names per (region, biome) for the minimap (region_name()).
var _region_names: Dictionary = {}
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
# Glutsumpf-only materials (created on the first switch to an ember biome).
var ember_ground_material: ShaderMaterial
var ember_ground_tint_material: ShaderMaterial
var channel_material: ShaderMaterial
var lava_material: ShaderMaterial
var basalt_material: ShaderMaterial
var char_material: ShaderMaterial
var stump_material: ShaderMaterial
var mushroom_material: ShaderMaterial
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
	decor_density = clampf(float(QUALITY.value("decor_density", 1.0)), 0.0, 1.0)
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
			_stale.erase(key)
	if not _stale.is_empty():
		_rebuild_stale(REBUILDS_PER_SYNC)

## Chunks still waiting for a staggered rebuild (biome or density switch).
func rebuild_pending() -> int:
	return _stale.size()

## Rebuilds every stale chunk now (tests, captures, loading screens).
func finish_rebuild() -> void:
	_rebuild_stale(_stale.size())

# Rebuilds up to `limit` stale chunks, nearest to the last synced position first.
func _rebuild_stale(limit: int) -> void:
	var center := _cell(_last_sync)
	var keys: Array = _stale.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - center).length_squared() < (b - center).length_squared())
	for index in mini(limit, keys.size()):
		var key: Vector2i = keys[index]
		_stale.erase(key)
		if not chunks.has(key):
			continue
		var old: Node = chunks[key]
		remove_child(old)
		old.queue_free()
		chunks[key] = _make_chunk(key)

func _cell(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / CELL), floori(position.z / CELL))

## Switches the map to another seed at runtime: every cache is dropped and the
## visible chunks are rebuilt around the last synced position. 0 = classic map.
func set_seed(value: int) -> void:
	world_seed = value
	_seed_mix = 0 if value == 0 else _scramble(value)
	for cache in [_obstacle_cache, _landmark_cache, _region_cache, _edge_cache, _near_edges_cache, _stone_cache, _block_cache, _region_names]:
		cache.clear()
	for key in chunks.keys():
		var chunk: Node = chunks[key]
		remove_child(chunk)
		chunk.queue_free()
	chunks.clear()
	_stale.clear()
	if ground_mesh != null:
		sync(_last_sync)

## Switches the biome at runtime (colours and decoration counts): the shared
## materials are restyled and the visible chunks rebuilt around the last synced
## position. Unknown ids fall back to verdant_maw. Layout and collisions stay.
## staggered = true (migration in a running game): shared colours switch at
## once, the chunk decoration is rebuilt one chunk per sync() call, nearest
## first, so the frame time never spikes; finish_rebuild() completes it at once.
func set_biome(id: String, staggered := false) -> void:
	biome_id = id if BIOMES.has(id) else BIOMES.DEFAULT
	biome = BIOMES.get_data(biome_id)
	if ground_material == null:
		return
	_apply_biome_colors()
	_restage(staggered)

## Quality "decor_density" (0..1). Rebuilds the visible chunks (staggered by default).
func set_decor_density(value: float, staggered := true) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	if is_equal_approx(clamped, decor_density):
		return
	decor_density = clamped
	if ground_mesh != null:
		_restage(staggered)

func _restage(staggered: bool) -> void:
	if staggered:
		for key in chunks.keys():
			_stale[key] = true
		return
	_stale.clear()
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
	if biome.has("ember"):
		_apply_ember(biome.ember)

func _ember_look() -> bool:
	return biome.has("ember")

# Creates (once) and restyles the Glutsumpf-only materials.
func _apply_ember(look: Dictionary) -> void:
	if ember_ground_material == null:
		ember_ground_material = _shader_material(EMBER_GROUND_SHADER)
		ember_ground_tint_material = _shader_material(EMBER_GROUND_SHADER)
		ember_ground_tint_material.set_shader_parameter("use_vertex_tint", true)
		channel_material = _shader_material(EMBER_CHANNEL_SHADER)
		lava_material = _shader_material(LAVA_SHADER)
		basalt_material = _prop_material(1.3, 0.9, 0.6, 0.4)
		char_material = _prop_material(1.2, 1.0, 0.5, 0.34)
		stump_material = _prop_material(1.2, 1.0, 0.5, 0.3)
		mushroom_material = _prop_material(1.35, 1.2, 0.3, 0.45)
		mushroom_material.set_shader_parameter("recolor_amount", 0.95)
	for target in [ember_ground_material, ember_ground_tint_material]:
		target.set_shader_parameter("dark_color", look.ground_dark)
		target.set_shader_parameter("light_color", look.ground_light)
		target.set_shader_parameter("ash_color", look.ash)
		target.set_shader_parameter("vein_color", look.vein)
		target.set_shader_parameter("vein_amount", look.vein_amount)
		target.set_shader_parameter("reference_color", ground_color)
	channel_material.set_shader_parameter("crust_color", look.crust)
	channel_material.set_shader_parameter("rim_color", look.crust_rim)
	channel_material.set_shader_parameter("core_color", look.core)
	channel_material.set_shader_parameter("hot_color", look.core_hot)
	lava_material.set_shader_parameter("core_color", look.lava_core)
	lava_material.set_shader_parameter("mid_color", look.lava_mid)
	lava_material.set_shader_parameter("crust_color", look.lava_crust)
	lava_material.set_shader_parameter("radius", 1.1)
	basalt_material.set_shader_parameter("body_tint", look.basalt_tint)
	basalt_material.set_shader_parameter("rim_color", look.char_rim)
	char_material.set_shader_parameter("body_tint", biome.wood_tint)
	char_material.set_shader_parameter("rim_color", look.char_rim)
	stump_material.set_shader_parameter("body_tint", biome.wood_tint)
	stump_material.set_shader_parameter("rim_color", look.char_rim)
	mushroom_material.set_shader_parameter("recolor_dark", look.mushroom_dark)
	mushroom_material.set_shader_parameter("recolor_light", look.mushroom_light)
	mushroom_material.set_shader_parameter("rim_color", look.mushroom_rim)

static func _shader_material(shader: Shader) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = shader
	return result

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
	var ember := _ember_look()
	if ember:
		# Glutsumpf: shader ground and one glow-channel mesh instead of edge + trail.
		if seeded:
			_part(chunk, "Open ground", _ground_mesh(key), ember_ground_tint_material, Vector3(0, -0.02, 0))
		else:
			_part(chunk, "Open ground", ground_mesh, ember_ground_material, Vector3(CELL * 0.5, -0.02, CELL * 0.5))
		_part(chunk, "Glow channel", _channel_mesh(key), channel_material, Vector3.ZERO)
	elif seeded:
		_part(chunk, "Open ground", _ground_mesh(key), ground_tint_material, Vector3(0, -0.02, 0))
		_part(chunk, "Trail edge", _network_mesh(key, TRAIL_EDGE_WIDTH - TRAIL_HALF_WIDTH, 0.003), path_edge_material, Vector3.ZERO)
		_part(chunk, "Broad trail", _network_mesh(key, 0.0, 0.007), path_material, Vector3.ZERO)
	else:
		_part(chunk, "Open ground", ground_mesh, ground_material, Vector3(CELL * 0.5, -0.02, CELL * 0.5))
		_part(chunk, "Trail edge", _trail_mesh(key, TRAIL_EDGE_WIDTH, 0.003), path_edge_material, Vector3.ZERO)
		_part(chunk, "Broad trail", _trail_mesh(key, TRAIL_HALF_WIDTH, 0.007), path_material, Vector3.ZERO)
	# Calm ground variation: soft moss tints, a few sand/earth spots, small pebbles
	# (Glutsumpf: ash, slag and slag lumps). Thinned by the quality decor density.
	for index in QUALITY.scaled_count(int(biome.moss_patches), decor_density):
		var spot := Vector3(2.0 + float(_hash(key.x, key.y, index + 30) % 24), 0.001, 2.0 + float(_hash(key.x, key.y, index + 60) % 24))
		if _near_trail(chunk.position + spot, 1.0):
			continue
		var tint := moss_materials[_hash(key.x, key.y, index + 90) % moss_materials.size()]
		var moss := _part(chunk, "Low leaf cover", patch_mesh, tint, spot)
		var size := 1.3 + float(_hash(key.x, key.y, index + 120) % 5) * 0.3
		moss.scale = Vector3(size * 1.5, 1, size)
		moss.rotation.y = float(_hash(key.x, key.y, index + 150) % 628) * 0.01
	for index in QUALITY.scaled_count(int(biome.sand_patches), decor_density):
		var spot := Vector3(2.0 + float(_hash(key.x, key.y, index + 180) % 24), 0.002, 2.0 + float(_hash(key.x, key.y, index + 210) % 24))
		if _near_trail(chunk.position + spot, 1.5):
			continue
		var dirt := _part(chunk, "Sand patch", patch_mesh, sand_material if index % 3 != 2 else earth_material, spot)
		var size := 1.2 + float(_hash(key.x, key.y, index + 240) % 4) * 0.3
		dirt.scale = Vector3(size * 1.4, 1, size)
		dirt.rotation.y = float(_hash(key.x, key.y, index + 270) % 628) * 0.01
	for index in QUALITY.scaled_count(int(biome.pebbles), decor_density):
		var spot := Vector3(1.0 + float(_hash(key.x, key.y, index + 300) % 26), 0, 1.0 + float(_hash(key.x, key.y, index + 330) % 26))
		var size := 0.32 + float(_hash(key.x, key.y, index + 360) % 4) * 0.07
		_prop(chunk, "Pebble", rock_mesh, rock_base, rock_material, spot, Vector3(size, size * 0.8, size), float(_hash(key.x, key.y, index + 390) % 628) * 0.01)
	if seeded:
		for stone in _stones(key):
			if ember:
				_basalt(chunk, Vector3(stone.x, 0.0, stone.z), stone.w)
			else:
				_boulder(chunk, Vector3(stone.x, 0.0, stone.z), stone.w)
	else:
		for center in obstacle_centers(key):
			if ember:
				_basalt(chunk, center, OBSTACLE_RADIUS)
			else:
				_boulder(chunk, center, OBSTACLE_RADIUS)
	# Scattered leaf clumps at the edges of the open ground: never on the trail,
	# never in the middle of the chunk, never inside a stone footprint.
	var placed := 0
	var wanted := QUALITY.scaled_count(int(biome.leaf_clumps_min) + _hash(key.x, key.y, 400) % 3, decor_density)
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
		# A single reed clump on the far shore (Glutsumpf: a cold-glowing Glutpilz).
		if ember:
			_prop(chunk, "Glutpilz", flower_mesh, flower_base, mushroom_material, Vector3(6.4, 0, 21.0), Vector3.ONE * 1.6, float(_hash(key.x, key.y, 14) % 628) * 0.01)
		else:
			_prop(chunk, "Pond reeds", reed_mesh, reed_base, reed_material, Vector3(6.3, 0, 21.1), Vector3.ONE * 1.5, float(_hash(key.x, key.y, 14) % 628) * 0.01)
	# Rare single flowers as colour accents on the open ground.
	if not seeded and _hash(key.x, key.y, 800) % int(biome.flower_one_in) == 0 and _decor_kept(key, 845):
		var local := Vector3(2.0 + float(_hash(key.x, key.y, 810) % 24), 0, 2.0 + float(_hash(key.x, key.y, 820) % 24))
		var world := chunk.position + local
		if not _near_trail(world, 1.2) and is_open(world, 1.0) and not near_landmark(world, 1.0):
			_prop(chunk, "Wild flower", flower_mesh, flower_base, mushroom_material if ember else flower_material, local, Vector3.ONE * 2.1, float(_hash(key.x, key.y, 830) % 628) * 0.01)
	var mark := landmark(key)
	if not mark.is_empty():
		_landmark(chunk, key, mark)
	return chunk

func _pool(chunk: Node3D, location: Vector3, size: Vector3) -> void:
	var shore := _part(chunk, "Pool shore", shore_mesh, shore_material, location + Vector3(0, 0.01, 0))
	shore.scale = size
	var water := _part(chunk, "Shallow pool", pool_mesh, lava_material if _ember_look() else water_material, location + Vector3(0, 0.02, 0))
	water.scale = size

# Decorative extras beyond fixed counts survive the quality density by a stable roll.
func _decor_kept(key: Vector2i, salt: int) -> bool:
	return decor_density >= 1.0 or _unit(key.x, key.y, salt) < decor_density

func _landmark(chunk: Node3D, key: Vector2i, mark: Dictionary) -> void:
	var local: Vector3 = mark.center - chunk.position
	var yaw: float = mark.yaw
	if _ember_look():
		_ember_landmark(chunk, key, mark, local, yaw)
		return
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

# Glutsumpf landmarks: same footprint and collision circles as Verdant, other look.
func _ember_landmark(chunk: Node3D, key: Vector2i, mark: Dictionary, local: Vector3, yaw: float) -> void:
	match int(mark.type):
		Landmark.ROOT_ARCH:
			# Charred root arch: charcoal body with an ember rim, slag at the feet.
			for foot in ARCH_FEET:
				var spot: Vector3 = local + Basis(Vector3.UP, yaw) * Vector3(foot.x * ARCH_SIZE.x, 0.0, foot.y * ARCH_SIZE.z)
				var slag := _part(chunk, "Arch foot slag", patch_mesh, plinth_material, spot + Vector3(0, 0.01, 0))
				slag.scale = Vector3(4.4, 1, 4.4)
			_prop(chunk, "Charred root arch", arch_mesh, arch_base, char_material, local, ARCH_SIZE, yaw)
		Landmark.FALLEN_LOG:
			# Three extinct stumps standing exactly on the log's collision knots.
			var ash := _part(chunk, "Stump ash", patch_mesh, moss_materials[0], local + Vector3(0, 0.004, 0))
			ash.scale = Vector3(3.2, 1, 7.6)
			ash.rotation.y = yaw
			var length := _model_length(log_mesh, log_base) * LOG_SIZE.z
			for index in LOG_KNOTS.size():
				var spot: Vector3 = local + Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, LOG_KNOTS[index] * length)
				var turn := yaw + float(_hash(key.x, key.y, 732 + index) % 628) * 0.01
				_stump(chunk, spot, LOG_RADIUS * (2.3 if index == 1 else 2.0), STUMP_HEIGHTS[index], turn)
		Landmark.POND:
			# Lava pool ringed by low slag lumps and cold Glutpilze; no collision.
			var size := Vector3(3.2, 1, 2.3)
			_pool(chunk, local, size)
			var count := 3 + _hash(key.x, key.y, 740) % 2
			for index in count:
				var angle := yaw + float(index) * TAU / float(count) + float(_hash(key.x, key.y, 750 + index) % 5) * 0.1
				var spot := local + Vector3(cos(angle) * 1.3 * size.x, 0, sin(angle) * 1.3 * size.z)
				if index % 2 == 0:
					var lump := 0.55 + float(_hash(key.x, key.y, 760 + index) % 4) * 0.08
					_prop(chunk, "Slag lump", rock_mesh, rock_base, basalt_material, spot, Vector3(lump * 1.3, lump, lump * 1.2), angle)
				else:
					_prop(chunk, "Glutpilz", flower_mesh, flower_base, mushroom_material, spot, Vector3.ONE * 1.7, angle)
		Landmark.MEADOW:
			# A clearing of pale ash dotted with 5-9 Glutpilze.
			var ground := _part(chunk, "Ash clearing", meadow_mesh, moss_materials[2], local + Vector3(0, 0.003, 0))
			ground.scale = Vector3(4.6, 1, 3.8)
			ground.rotation.y = yaw
			var count := 5 + _hash(key.x, key.y, 740) % 5
			for index in count:
				var angle := float(index) * 2.39996 + yaw
				var distance := 1.0 + 3.8 * sqrt((float(index) + 0.5) / float(count))
				var spot := local + Vector3(cos(angle) * distance, 0, sin(angle) * distance * 0.85)
				var cap := 1.7 + float(_hash(key.x, key.y, 760 + index) % 5) * 0.15
				_prop(chunk, "Glutpilz", flower_mesh, flower_base, mushroom_material, spot, Vector3.ONE * cap, float(_hash(key.x, key.y, 780 + index) % 628) * 0.01)

# An upright piece of the fallen-log model: the extinct stump of a burnt tree.
func _stump(chunk: Node3D, location: Vector3, diameter: float, height: float, yaw: float) -> void:
	var box: AABB = Transform3D(log_base.basis, Vector3.ZERO) * log_mesh.get_aabb()
	var fit := Basis.from_scale(Vector3(diameter / maxf(box.size.x, 0.01), diameter / maxf(box.size.y, 0.01), height / maxf(box.size.z, 0.01)))
	var shape := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5) * fit * log_base.basis
	_prop_shape(chunk, "Extinct stump", log_mesh, stump_material, location, shape)

# Basalt column cluster on a stone's collision circle: three stretched rocks.
func _basalt(chunk: Node3D, center: Vector3, radius: float) -> void:
	var location := center - chunk.position
	var roll := _hash(roundi(center.x * 10.0), roundi(center.z * 10.0), 7)
	var stone_scale := radius / OBSTACLE_RADIUS
	var plinth := _part(chunk, "Basalt footprint", plinth_mesh, plinth_material, location + Vector3(0, 0.02, 0))
	plinth.scale = Vector3(stone_scale, 1.0, stone_scale)
	var yaw := float((roll >> 4) % 628) * 0.01
	var heights := [3.8, 2.8, 2.0]
	var widths := [1.25, 1.05, 0.95]
	for index in 3:
		var angle := yaw + float(index) * TAU / 3.0
		var offset := Vector3(cos(angle), 0, sin(angle)) * radius * (0.0 if index == 0 else 0.5)
		if index == 0:
			offset = Vector3(cos(yaw + PI), 0, sin(yaw + PI)) * radius * 0.18
		var width: float = widths[index] * stone_scale * (0.94 + float((roll >> (8 + index * 3)) % 5) * 0.03)
		var height: float = heights[index] * stone_scale * (0.9 + float((roll >> (12 + index * 2)) % 5) * 0.05)
		_prop(chunk, "Basalt column", rock_mesh, rock_base, basalt_material, location + offset, Vector3(width, height, width), angle * 1.7)

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

# Glow channel (Glutsumpf trail): one strip across the full edge width with a
# vertex-colour profile. COLOR.r = rim share, COLOR.a = glow (1 on the centre).
const CHANNEL_PROFILE := [
	[-1.0, 1.0, 0.0], [-0.8, 0.35, 0.0], [-0.5, 0.0, 0.1], [0.0, 0.0, 1.0],
	[0.5, 0.0, 0.1], [0.8, 0.35, 0.0], [1.0, 1.0, 0.0],
]

func _channel_offset(entry: Array, half: float) -> float:
	# Profile entries: +-1 = outer edge, +-0.8 = trail half width, +-0.5 = core.
	var t: float = absf(entry[0])
	var sign_value := signf(entry[0])
	if t >= 1.0:
		return sign_value * (half + TRAIL_EDGE_WIDTH - TRAIL_HALF_WIDTH)
	if t >= 0.8:
		return sign_value * half
	if t >= 0.5:
		return sign_value * CHANNEL_CORE
	return 0.0

func _channel_strip(surface: SurfaceTool, a: Vector3, b: Vector3, side0: Vector3, side1: Vector3, half: float) -> void:
	for band in CHANNEL_PROFILE.size() - 1:
		var inner: Array = CHANNEL_PROFILE[band]
		var outer: Array = CHANNEL_PROFILE[band + 1]
		var o0 := _channel_offset(inner, half)
		var o1 := _channel_offset(outer, half)
		var c0 := Color(inner[1], 0.0, 0.0, inner[2])
		var c1 := Color(outer[1], 0.0, 0.0, outer[2])
		var quad := [[a + side0 * o0, c0], [a + side0 * o1, c1], [b + side1 * o0, c0], [a + side0 * o1, c1], [b + side1 * o1, c1], [b + side1 * o0, c0]]
		for vertex in quad:
			surface.set_color(vertex[1])
			surface.set_normal(Vector3.UP)
			surface.add_vertex(vertex[0])

func _channel_mesh(key: Vector2i) -> Mesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lift := Vector3(0.0, 0.005, 0.0)
	var count := 0
	if world_seed == 0:
		for step_index in 8:
			var z0 := float(step_index) * CELL / 8.0
			var z1 := float(step_index + 1) * CELL / 8.0
			var a := Vector3(_trail_center(key, z0), 0.0, z0) + lift
			var b := Vector3(_trail_center(key, z1), 0.0, z1) + lift
			_channel_strip(surface, a, b, Vector3.RIGHT, Vector3.RIGHT, TRAIL_HALF_WIDTH)
			count += 1
		return surface.commit()
	var origin := Vector3(key.x * CELL, 0.0, key.y * CELL)
	var area := Rect2(origin.x, origin.z, CELL, CELL)
	for edge in _edges_near(key):
		var points: PackedVector3Array = edge.points
		var half: float = edge.half
		for index in points.size() - 1:
			var middle := (points[index] + points[index + 1]) * 0.5
			if not area.has_point(Vector2(middle.x, middle.z)):
				continue
			_channel_strip(surface, points[index] - origin + lift, points[index + 1] - origin + lift, _side(points, index), _side(points, index + 1), half)
			count += 1
	var junction := 0.0
	for offset in NEIGHBOURS:
		if _has_edge(key, key + offset):
			var owner: Vector2i = key if EDGE_OFFSETS.has(offset) else key + offset
			junction = maxf(junction, float(_chunk_params(owner).half_width))
	if junction > 0.0:
		# Round junction: glowing centre, crust ring, rim; slightly higher than the strips.
		var node := _node(key) - origin + lift + Vector3(0.0, 0.002, 0.0)
		var rings := [[0.0, 0.0, 1.0], [CHANNEL_CORE, 0.0, 0.1], [junction, 0.35, 0.0], [junction + TRAIL_EDGE_WIDTH - TRAIL_HALF_WIDTH, 1.0, 0.0]]
		for index in 16:
			var d0 := Vector3(cos(TAU * float(index) / 16.0), 0.0, sin(TAU * float(index) / 16.0))
			var d1 := Vector3(cos(TAU * float(index + 1) / 16.0), 0.0, sin(TAU * float(index + 1) / 16.0))
			for ring in rings.size() - 1:
				var r0: Array = rings[ring]
				var r1: Array = rings[ring + 1]
				var c0 := Color(r0[1], 0.0, 0.0, r0[2])
				var c1 := Color(r1[1], 0.0, 0.0, r1[2])
				var quad := [[node + d0 * r0[0], c0], [node + d0 * r1[0], c1], [node + d1 * r1[0], c1], [node + d0 * r0[0], c0], [node + d1 * r1[0], c1], [node + d1 * r0[0], c0]]
				for vertex in quad:
					surface.set_color(vertex[1])
					surface.set_normal(Vector3.UP)
					surface.add_vertex(vertex[0])
		count += 1
	if count == 0:
		return null
	return surface.commit()

# Small walkable pool of a seeded chunk: {"local": Vector3, "size": Vector3} or {}.
func _seeded_pool(key: Vector2i) -> Dictionary:
	var params := _chunk_params(key)
	if _unit(key.x, key.y, 13) >= float(params.pond_chance):
		return {}
	var chunk_origin := Vector3(key.x * CELL, 0, key.y * CELL)
	for attempt in 4:
		var local := Vector3(5.0 + _unit(key.x, key.y, 15 + attempt * 2) * 18.0, 0, 5.0 + _unit(key.x, key.y, 16 + attempt * 2) * 18.0)
		var world := chunk_origin + local
		if _near_trail(world, 3.2) or not is_open(world, 3.2) or near_landmark(world, 3.0):
			continue
		return {"local": local, "size": Vector3(1.5 + _unit(key.x, key.y, 24) * 0.6, 1, 1.0 + _unit(key.x, key.y, 25) * 0.3)}
	return {}

## Eruption sources of a chunk (scripts/eruptions.gd) as Vector4(x, 0, z, kind):
## kind 0 = lava pool centre, 1 = point on a glow channel. Deterministic from the
## layout; only meaningful in biomes with "eruptions": true.
func eruption_sites(key: Vector2i) -> Array[Vector4]:
	var result: Array[Vector4] = []
	var origin := Vector3(key.x * CELL, 0, key.y * CELL)
	if world_seed == 0:
		if _hash(key.x, key.y, 13) % int(biome.pond_one_in) == 0 and not near_landmark(origin + Vector3(4, 0, 22), 3.0):
			result.append(Vector4(origin.x + 4.0, 0.0, origin.z + 22.0, 0.0))
	else:
		var pool := _seeded_pool(key)
		if not pool.is_empty():
			var local: Vector3 = pool.local
			result.append(Vector4(origin.x + local.x, 0.0, origin.z + local.z, 0.0))
	var mark := landmark(key)
	if not mark.is_empty() and int(mark.type) == Landmark.POND:
		result.append(Vector4(mark.center.x, 0.0, mark.center.z, 0.0))
	var samples := trail_samples(key)
	for index in range(2, samples.size(), 4):
		var point := Vector3(samples[index].x, 0.0, samples[index].z)
		# Rare trail points under an arch foot or stone are skipped.
		if is_open(point, 1.0):
			result.append(Vector4(point.x, 0.0, point.z, 1.0))
	return result

func _seeded_decor(chunk: Node3D, key: Vector2i) -> void:
	var params := _chunk_params(key)
	var ember := _ember_look()
	# Small flat pools: walkable, placed on open ground away from trail and stones.
	var pool := _seeded_pool(key)
	if not pool.is_empty():
		var local: Vector3 = pool.local
		var size: Vector3 = pool.size
		_pool(chunk, local, size)
		var angle := float(_hash(key.x, key.y, 14) % 628) * 0.01
		var shore := local + Vector3(cos(angle) * 1.4 * size.x, 0, sin(angle) * 1.4 * size.z)
		if ember:
			_prop(chunk, "Glutpilz", flower_mesh, flower_base, mushroom_material, shore, Vector3.ONE * 1.6, angle)
		else:
			_prop(chunk, "Pond reeds", reed_mesh, reed_base, reed_material, shore, Vector3.ONE * 1.5, angle)
	# Single wild flowers as colour accents; flowery regions get a second one.
	var flowers := 0
	if _unit(key.x, key.y, 800) < float(params.flower_chance):
		flowers = 1 + (1 if float(params.flower_chance) > 0.4 else 0)
	for index in flowers:
		if not _decor_kept(key, 845 + index):
			continue
		var local := Vector3(2.0 + float(_hash(key.x, key.y, 810 + index * 3) % 24), 0, 2.0 + float(_hash(key.x, key.y, 820 + index * 3) % 24))
		var world := chunk.position + local
		if not _near_trail(world, 1.2) and is_open(world, 1.0) and not near_landmark(world, 1.0):
			_prop(chunk, "Wild flower", flower_mesh, flower_base, mushroom_material if ember else flower_material, local, Vector3.ONE * 2.1, float(_hash(key.x, key.y, 830 + index) % 628) * 0.01)

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
	for index in QUALITY.scaled_count(count, decor_density):
		var angle := yaw + float(index) * TAU / float(count) + float((roll >> (10 + index * 3)) % 7) * 0.12
		var foot := location + Vector3(cos(angle), 0, sin(angle)) * (radius + 0.1)
		if _near_trail(chunk.position + foot, 0.3):
			continue
		var leaf_size := 1.15 + float((roll >> (14 + index)) % 4) * 0.1
		_prop(chunk, "Broad leaf", leaf_mesh, leaf_base, leaf_material, foot, Vector3.ONE * leaf_size, angle)

func _prop(parent: Node3D, label: String, mesh: Mesh, base: Transform3D, material: Material, location: Vector3, size: Vector3, yaw: float) -> MeshInstance3D:
	return _prop_shape(parent, label, mesh, material, location, Basis(Vector3.UP, yaw) * Basis.from_scale(size) * base.basis)

func _prop_shape(parent: Node3D, label: String, mesh: Mesh, material: Material, location: Vector3, shape: Basis) -> MeshInstance3D:
	var part := _part(parent, label, mesh, material, location)
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



# --- Map data (minimap stage; read only, never changes the world) ---------------

## Chunk key of a world position.
func chunk_at(world: Vector3) -> Vector2i:
	return _cell(world)

## Region key (REGION x REGION chunks) of a world position.
func region_at(world: Vector3) -> Vector2i:
	return _region_key(_cell(world))

## World-space centre of a region.
func region_center(region: Vector2i) -> Vector3:
	return Vector3((region.x + 0.5) * REGION * CELL, 0.0, (region.y + 0.5) * REGION * CELL)

## Landmark types (Landmark enum) standing in a region, in chunk order.
func region_landmarks(region: Vector2i) -> Array:
	var result := []
	for x in range(region.x * REGION, region.x * REGION + REGION):
		for z in range(region.y * REGION, region.y * REGION + REGION):
			var mark := landmark(Vector2i(x, z))
			if not mark.is_empty():
				result.append(int(mark.type))
	return result

## Region name in the words of the active biome ("Moosgrund"), cached.
func region_name(region: Vector2i) -> String:
	var key := Vector3i(region.x, region.y, BIOMES.ORDER.find(biome_id))
	if _region_names.has(key):
		return _region_names[key]
	if _region_names.size() > CACHE_LIMIT:
		_region_names.clear()
	var result: String = REGION_NAMES.name_for(world_seed, region, biome_id)
	_region_names[key] = result
	return result

## Landmark phrase of a region in the active biome ("am Wurzelbogen") or "".
func region_phrase(region: Vector2i) -> String:
	return REGION_NAMES.phrase_for(world_seed, region, biome_id, region_landmarks(region))

## Soft ground tint shift at a world point as Vector2(hue, value) - the same
## blend the seeded ground mesh uses; (0, 0) on the classic map.
func map_tint(x: float, z: float) -> Vector2:
	if world_seed == 0:
		return Vector2.ZERO
	var fx := x / (REGION * CELL) - 0.5
	var fz := z / (REGION * CELL) - 0.5
	var ix := floori(fx)
	var iz := floori(fz)
	var tx := smoothstep(0.0, 1.0, fx - ix)
	var tz := smoothstep(0.0, 1.0, fz - iz)
	var shift := Vector2.ZERO
	for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		var weight := (tx if corner.x == 1 else 1.0 - tx) * (tz if corner.y == 1 else 1.0 - tz)
		var params := region_params(Vector2i(ix + corner.x, iz + corner.y))
		shift += Vector2(float(params.hue), float(params.value)) * weight
	return shift

## Flat map shapes of one chunk in world metres (for the minimap bake):
##   trails: Vector4(x, 0, z, half width) centreline samples, including those
##           up to one trail width outside the chunk so borders join;
##   stones: Vector4(x, 0, z, radius) stone circles (landmark parts excluded);
##   pools:  Vector4(x, z, radius x, radius z) water / lava pools;
##   marks:  landmark dictionaries (type, center, yaw) plus "circles" - of
##           this and the neighbouring chunks when their shapes reach in.
## Depends on the active biome only for the classic map's pool frequency.
func map_features(key: Vector2i) -> Dictionary:
	var margin := TRAIL_EDGE_WIDTH + 1.0
	var area := Rect2(key.x * CELL - margin, key.y * CELL - margin, CELL + 2.0 * margin, CELL + 2.0 * margin)
	var origin := Vector3(key.x * CELL, 0.0, key.y * CELL)
	var trails: Array[Vector4] = []
	var stones: Array[Vector4] = []
	var pools: Array[Vector4] = []
	if world_seed == 0:
		for step in range(-6, int(CELL) + 7):
			var z := float(step)
			trails.append(Vector4(origin.x + _trail_center(key, z), 0.0, origin.z + z, TRAIL_HALF_WIDTH))
		for center in obstacle_centers(key):
			stones.append(Vector4(center.x, 0.0, center.z, OBSTACLE_RADIUS))
		if _hash(key.x, key.y, 13) % int(biome.pond_one_in) == 0 and not near_landmark(origin + Vector3(4, 0, 22), 3.0):
			pools.append(Vector4(origin.x + 4.0, origin.z + 22.0, 1.1 * 1.8, 1.1 * 1.1))
	else:
		for edge in _edges_near(key):
			var half: float = edge.half
			for point in edge.points:
				if area.has_point(Vector2(point.x, point.z)):
					trails.append(Vector4(point.x, 0.0, point.z, half))
		stones.append_array(_stones(key))
		var pool := _seeded_pool(key)
		if not pool.is_empty():
			var local: Vector3 = pool.local
			var size: Vector3 = pool.size
			pools.append(Vector4(origin.x + local.x, origin.z + local.z, 1.1 * size.x, 1.1 * size.z))
	# Landmarks of this and the neighbouring chunks: their shapes may reach over
	# the chunk border, so every chunk paints its share of them.
	var marks: Array[Dictionary] = []
	for x in range(key.x - 1, key.x + 2):
		for z in range(key.y - 1, key.y + 2):
			var mark := landmark(Vector2i(x, z))
			if mark.is_empty():
				continue
			var mark_center: Vector3 = mark.center
			if not area.grow(LANDMARK_FOOTPRINT[int(mark.type)]).has_point(Vector2(mark_center.x, mark_center.z)):
				continue
			var entry := mark.duplicate()
			entry["circles"] = _landmark_circles(mark)
			marks.append(entry)
			if int(mark.type) == Landmark.POND:
				pools.append(Vector4(mark_center.x, mark_center.z, 1.1 * 3.2, 1.1 * 2.3))
	return {"trails": trails, "stones": stones, "pools": pools, "marks": marks}
