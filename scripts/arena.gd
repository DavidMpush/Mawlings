extends Node3D

# A bounded, deterministic layout (stage 18). The map is map_regions x
# map_regions regions of REGION x REGION chunks, centred on the world origin for
# even sizes (solo 4 x 4 regions = 336 x 336 m). Only nearby visual chunks
# exist; obstacle positions are computed from coordinates, so moving away never
# changes them. One ring of border chunks around the map carries the natural
# edge (arena_border.gd: jungle walls, cliffs and swamp water / basalt and lava,
# fading into fog); the playable rectangle is an obstacle for every creature.
# Stage 18b: every seeded map is a designed level from map_layout.gd -
# clearings joined by paths, impassable walls in between (collision through a
# signed wall-distance grid, walls drawn by arena_border.build_walls) - and all
# enemies walk the paths along one shared flow field (flow_field.gd).
const CELL := 28.0
const VISIBLE_RADIUS := 1
const OBSTACLE_RADIUS := 1.85
const CREATURE_SHADER = preload("res://shaders/creature.gdshader")
# Stage 18c: props see-through between camera and swarm (fade window).
const PROP_SHADER = preload("res://shaders/prop_fade.gdshader")
const FADE_RADIUS := 6.5
const BIOMES = preload("res://scripts/biomes.gd")
const TUNING = preload("res://scripts/tuning.gd")
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
# Dürrschlund look (stage 19; biomes with a "desert" block). Models load lazily.
const DESERT_GROUND_SHADER = preload("res://shaders/desert_ground.gdshader")
const QUICKSAND_SHADER = preload("res://shaders/quicksand.gdshader")
const DESERT_MODELS := {
	"sandstone": "res://assets/gameplay/props/SandstoneCliff_game.glb",
	"ribs": "res://assets/gameplay/props/RibBones_game.glb",
	"cactus": "res://assets/gameplay/props/Cactus_game.glb",
	"skull": "res://assets/gameplay/props/GiantSkull_game.glb",
	"rock_arch": "res://assets/gameplay/props/RockArch_game.glb",
}
# Layout seed salt per biome (kept stable when the biome order changes).
const LAYOUT_SALT := {"glutsumpf": 2, "duerrschlund": 3}
# Movement radius of the swarm in resolve_motion (everything else counts as a
# creature that a sandstorm hastens).
const SWARM_MOTION_RADIUS := 0.75
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
# World seed: 0 is the hand-tuned classic open layout (columns of trails, two
# stones per chunk; tests and F5). Any other seed builds the clearing/path map
# of map_layout.gd; regions of REGION x REGION chunks keep a soft ground tint.
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
# --- Bounded map (stage 18) ---
const ARENA_BORDER = preload("res://scripts/arena_border.gd")
# Regions per side: solo 4 (336 m), duo 5 (420 m), trio/quad 6 (504 m).
const DEFAULT_MAP_REGIONS := 4
const MAP_REGIONS_BY_PLAYERS := [4, 4, 5, 6, 6]
# The playable rectangle ends this far inside the map bounds; the wall starts there.
const BORDER_INSET := 3.0
# Rings of border chunks (edge decoration only, no gameplay) around the map.
const BORDER_CHUNKS := 1
# Stones keep this gap to the playable edge (a walkable passage), landmarks more.
const EDGE_STONE_GAP := 4.0
const EDGE_LANDMARK_GAP := 12.0
# Multiplayer start points sit this share of the map size from the centre.
const SPAWN_RING_SHARE := 0.33
# Exploration fog: cells of FOG_CELL metres, revealed within EXPLORE_RADIUS.
const FOG_CELL := 12.0
# Stage 18c: the swarm sees ~28 m; the fog lifts only there (POIs included).
const EXPLORE_RADIUS := 28.0
# --- Map layout (stage 18b): clearings, paths and walls for every seeded map ---
const MAP_LAYOUT = preload("res://scripts/map_layout.gd")
# Stage 18c: the exploration map is the standard for seeded maps; "graph"
# keeps the clearing/corridor layout of stage 18b (MAP_LAYOUT).
const MAP_EXPLORE = preload("res://scripts/map_explore.gd")
const BEACONS = preload("res://scripts/map_beacons.gd")
var layout_style := "explore"
## Prop materials with the see-through window (fed with the swarm position in sync()).
var fade_materials: Array[ShaderMaterial] = []
# Stage 18c: 1 per layout place (POI node) once the swarm has seen it.
var _discovered := PackedByteArray()
## Off for top-down review shots (the window would cut into the overview).
var fade_enabled := true
var _beacons: Node3D
const FLOW_FIELD = preload("res://scripts/flow_field.gd")
# Flow field cell (m) and cells expanded per sync() (one frame, ~0.3 ms):
# a full field over ~7 000 open cells takes ~22 frames (~0.37 s at 60 fps).
const FLOW_CELL := 2.0
const FLOW_BUDGET := 320
# A new field starts once the swarm moved this far from the last source.
const FLOW_MOVE := 2.0
# Enemies walk straight at the target when the line is clear within this range.
const LOS_RANGE := 14.0
# Sand share of a path's walkable half width (the rest is verge up to the wall).
const SAND_SHARE := 0.42
# Wall samples per chunk side in map_features() (minimap bake).
const WALL_SAMPLES := 12
## Map layout of a seeded map (null on the classic seed-0 map).
var layout: RefCounted
## Shared enemy navigation field (null on the classic map).
var flow: RefCounted
## Stage 18c: the same for big bodies (Bog King, apex): only ground with
## BIG_CLEARANCE of wall distance, so they never aim into gaps too narrow.
var flow_big: RefCounted
const BIG_CLEARANCE := 3.4
const BIG_RADIUS := 1.5
var _flow_turn := 0
# Layout data per chunk key: stones (Vector4), landmark, path samples, eruptions.
var _chunk_stones: Dictionary = {}
var _chunk_marks: Dictionary = {}
var _chunk_trails: Dictionary = {}
var _chunk_eruptions: Dictionary = {}
# Round sand caps where a path's sand ends in a clearing; per path the sample
# points that carry sand (1) or lie in a clearing core (0).
var _chunk_caps: Dictionary = {}
var _sand_keep: Array[PackedByteArray] = []
# Last finished flow step cost (ms) for perf probes.
var flow_step_ms := 0.0
var map_regions := DEFAULT_MAP_REGIONS
var player_count := 1
# Seed of the run (menu); world_seed is the layout seed of the active biome
# (run seed for Verdant Maw, a derived seed per other biome, 0 stays classic).
var run_seed := 0
var _chunk_lo := -6
var _chunk_hi := 5
var _region_lo := -2
var _region_origin := 0.0
var _bounds := Rect2()
var _playable := Rect2()
# Points kept clear of stones and landmarks (start points, migration arrival).
var _clear_points: Array[Vector3] = [Vector3.ZERO]
var _arrival: Array[Vector3] = []
# Unique region names of the whole map per biome id: {biome: {Vector2i: name}}.
var _map_names: Dictionary = {}
var _explored := PackedByteArray()
var _fog_size := Vector2i.ZERO
var _explore_at := Vector3.INF
var _explored_regions: Dictionary = {}
## Grows whenever a fog cell is revealed (cheap change check for the minimap).
var explore_version := 0
var border: RefCounted
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
# Dürrschlund-only materials and meshes (created on the first switch to a desert biome).
var desert_ground_material: ShaderMaterial
var desert_ground_tint_material: ShaderMaterial
var quicksand_material: ShaderMaterial
var sandstone_material: ShaderMaterial
var bone_material: ShaderMaterial
var cactus_material: ShaderMaterial
var dune_material: ShaderMaterial
## Desert model parts {name: [mesh, base transform]} (DESERT_MODELS).
var desert_parts: Dictionary = {}
var quicksand_mesh: PlaneMesh
## Stage 19: creature speed factor during a sandstorm (1 = calm); the swarm never.
var enemy_haste := 1.0
# Quicksand patches per chunk key (Vector4 x, 0, z, radius).
var _chunk_sands: Dictionary = {}
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
	_update_map_geometry()
	border = ARENA_BORDER.new(self)
	border.apply_biome(biome)
	sync(Vector3.ZERO)

func sync(position: Vector3) -> void:
	_last_sync = position
	_explore(position)
	_step_flow(position)
	_update_fade(position)
	var center := _cell(position)
	var wanted: Dictionary = {}
	var missing: Array[Vector2i] = []
	# Only map chunks plus the border ring exist; beyond it lies the fog skirt.
	var low := _chunk_lo - BORDER_CHUNKS
	var high := _chunk_hi + BORDER_CHUNKS
	for x in range(maxi(low, center.x - view_radius), mini(high, center.x + view_radius) + 1):
		for z in range(maxi(low, center.y - view_radius), mini(high, center.y + view_radius) + 1):
			var key := Vector2i(x, z)
			wanted[key] = true
			if not chunks.has(key):
				missing.append(key)
	# Etappe 22: a new row of chunks is built over several frames (nearest first,
	# the chunk under the swarm always at once); chunk_budget 0 = all at once.
	if not missing.is_empty():
		missing.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - center).length_squared() < (b - center).length_squared())
		var built := 0
		for key in missing:
			if chunk_budget > 0 and built >= chunk_budget and key != center:
				continue
			var started := Time.get_ticks_usec()
			chunks[key] = _make_chunk(key)
			var ms := float(Time.get_ticks_usec() - started) / 1000.0
			chunk_build_ms_max = maxf(chunk_build_ms_max, ms)
			chunk_builds += 1
			built += 1
	for key in chunks.keys():
		if not wanted.has(key):
			chunks[key].queue_free()
			chunks.erase(key)
			_stale.erase(key)
	if not _stale.is_empty():
		_rebuild_stale(REBUILDS_PER_SYNC)

## Etappe 22: chunks built per sync() while moving (0 = all at once; main.gd sets 1).
var chunk_budget := 0
## Longest single chunk build (ms) and number of builds, for the perf bench.
var chunk_build_ms_max := 0.0
var chunk_builds := 0


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
## Also resets the migration arrival clearing and the exploration fog.
func set_seed(value: int) -> void:
	run_seed = value
	_arrival.clear()
	_relayout(layout_seed(value, biome_id), false)

## Layout seed of a run seed in a biome: Verdant Maw uses the run seed itself,
## every other biome a derived one (a migration lands on a new map). Seed 0
## stays the classic layout everywhere.
static func layout_seed(seed_value: int, id: String) -> int:
	if seed_value == 0 or id == BIOMES.DEFAULT or not BIOMES.has(id):
		return seed_value
	var mixed := _scramble(seed_value ^ int(LAYOUT_SALT.get(id, BIOMES.ORDER.find(id) + 1)) * 0x9E3779B9) & 0x3FFFFFFF
	return mixed if mixed != 0 else 1

## Map size for a player count (1 solo .. 4 quad): 4, 5 or 6 regions per side.
static func regions_for_players(players: int) -> int:
	return MAP_REGIONS_BY_PLAYERS[clampi(players, 1, 4)]

## Sets the map size (regions per side) and the number of start points kept
## clear; rebuilds the layout. Solo defaults: 4 regions, 1 player.
func configure_map(regions: int, players := 1) -> void:
	map_regions = maxi(1, regions)
	player_count = clampi(players, 1, 4)
	_relayout(world_seed, false)

# Drops every cached layout value and rebuilds the visible chunks (staggered =
# one chunk per sync(), nearest first; used by a migration).
func _relayout(seed_value: int, staggered: bool) -> void:
	world_seed = seed_value
	_seed_mix = 0 if seed_value == 0 else _scramble(seed_value)
	for cache in [_obstacle_cache, _landmark_cache, _region_cache, _region_names, _map_names]:
		cache.clear()
	_update_map_geometry()
	_build_layout()
	_reset_exploration()
	if border != null:
		border.rebuild_skirt()
	if ground_mesh == null:
		return
	if staggered:
		for key in chunks.keys():
			_stale[key] = true
		sync(_last_sync)
		return
	for key in chunks.keys():
		var chunk: Node = chunks[key]
		remove_child(chunk)
		chunk.queue_free()
	chunks.clear()
	_stale.clear()
	sync(_last_sync)

## Switches the biome at runtime: the shared materials are restyled and the map
## is regenerated with the layout seed of the new biome (same size). Unknown ids
## fall back to verdant_maw. staggered = true (migration in a running game):
## shared colours switch at once, the chunks are rebuilt one per sync() call,
## nearest first, so the frame time never spikes; finish_rebuild() completes it.
## A point handed to prepare_arrival() before stays clear of stones/landmarks.
func set_biome(id: String, staggered := false) -> void:
	biome_id = id if BIOMES.has(id) else BIOMES.DEFAULT
	biome = BIOMES.get_data(biome_id)
	if ground_material == null:
		return
	_apply_biome_colors()
	if border != null:
		border.apply_biome(biome)
	var next_seed := layout_seed(run_seed, biome_id)
	if next_seed != world_seed:
		_relayout(next_seed, staggered)
	else:
		_restage(staggered)

# ------------------------------------------------------------ stage 22: map prefetch
# Building an exploration map costs a few hundred ms of GDScript. When the next
# map is known in advance (the Migrationsschlund opened), it is built on a
# worker thread; the switch then only takes the finished data. Same inputs =
# same map, so the result is identical to building it on the spot.
var _prefetch_key := ""
var _prefetch_task := -1
var _prefetch_result: RefCounted
var _prefetch_mutex := Mutex.new()


func _layout_key(seed_value: int, id: String, starts: Array[Vector3], arrivals: Array[Vector3]) -> String:
	return "%d|%s|%d|%s|%s|%s|%s" % [seed_value, id, map_regions, _playable, _bounds, starts, arrivals]


## Starts building the map of biome `id` for an arrival at `point` in the
## background (the migration will use it). Safe to call more than once.
func prefetch_layout(id: String, point: Vector3) -> void:
	if layout_style != "explore" or not BIOMES.has(id):
		return
	var next_seed := layout_seed(run_seed, id)
	if next_seed == 0:
		return
	var safe := clamp_inside(Vector3(point.x, 0.0, point.z), START_CLEARANCE * 0.5)
	var arrivals: Array[Vector3] = [safe]
	var starts := _raw_spawn_points(player_count)
	var key := _layout_key(next_seed, id, starts, arrivals)
	if key == _prefetch_key:
		return
	_finish_prefetch()
	_prefetch_key = key
	_prefetch_result = null
	var playable := _playable
	var map_bounds := _bounds
	var regions := map_regions
	_prefetch_task = WorkerThreadPool.add_task(func() -> void:
		var built: RefCounted = MAP_EXPLORE.new(next_seed, playable, map_bounds, regions, starts, arrivals, id)
		_prefetch_mutex.lock()
		_prefetch_result = built
		_prefetch_mutex.unlock(), false, "Map prefetch")


func _finish_prefetch() -> void:
	if _prefetch_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_prefetch_task)
		_prefetch_task = -1


# The prefetched map when it matches `key` (waits for the worker if needed).
func _take_prefetch(key: String) -> RefCounted:
	if _prefetch_key == "" or key != _prefetch_key:
		return null
	_finish_prefetch()
	_prefetch_mutex.lock()
	var result := _prefetch_result
	_prefetch_mutex.unlock()
	_prefetch_key = ""
	_prefetch_result = null
	return result


func _exit_tree() -> void:
	_finish_prefetch()


## Migration: the swarm will arrive at `point` on the next map. Returns the safe
## arrival point (inside the playable area); the next set_biome() keeps a
## START_CLEARANCE clearing around it.
func prepare_arrival(point: Vector3) -> Vector3:
	var safe := clamp_inside(Vector3(point.x, 0.0, point.z), START_CLEARANCE * 0.5)
	_arrival = [safe]
	_update_clear_points()
	return safe

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
	if biome.has("desert"):
		_apply_desert(biome.desert)

func _ember_look() -> bool:
	return biome.has("ember")

## Stage 19: the Dürrschlund look (shader sand, sandstone, bones, cacti, quicksand).
func _desert_look() -> bool:
	return biome.has("desert")

# Creates (once) and restyles the Dürrschlund-only materials and meshes.
func _apply_desert(look: Dictionary) -> void:
	if desert_ground_material == null:
		desert_ground_material = _shader_material(DESERT_GROUND_SHADER)
		desert_ground_tint_material = _shader_material(DESERT_GROUND_SHADER)
		desert_ground_tint_material.set_shader_parameter("use_vertex_tint", true)
		quicksand_material = _shader_material(QUICKSAND_SHADER)
		sandstone_material = _prop_material(1.05, 0.8, 0.5, 0.18)
		bone_material = _prop_material(1.05, 0.95, 0.55, 0.3)
		cactus_material = _prop_material(1.1, 1.15, 0.45, 0.15)
		dune_material = _prop_material(1.0, 0.9, 0.35, 0.06)
		quicksand_mesh = PlaneMesh.new()
		quicksand_mesh.size = Vector2(2.0, 2.0)
		for key in DESERT_MODELS:
			desert_parts[key] = _extract_mesh(load(DESERT_MODELS[key]))
	for target in [desert_ground_material, desert_ground_tint_material]:
		target.set_shader_parameter("dune_light", look.dune_light)
		target.set_shader_parameter("dune_shadow", look.dune_shadow)
		target.set_shader_parameter("shadow_cool", look.shadow_cool)
		target.set_shader_parameter("ripple", look.ripple)
		target.set_shader_parameter("ripple_amount", look.ripple_amount)
		target.set_shader_parameter("bone_fleck", look.bone_fleck)
		target.set_shader_parameter("reference_color", ground_color)
	quicksand_material.set_shader_parameter("sand_color", look.quicksand)
	quicksand_material.set_shader_parameter("swirl_color", look.quicksand_swirl)
	quicksand_material.set_shader_parameter("rim_color", look.dune_light)
	for target in [sandstone_material, bone_material, cactus_material, dune_material]:
		target.set_shader_parameter("rim_color", biome.prop_rim)
	sandstone_material.set_shader_parameter("body_tint", biome.get("wall_tint", Color(1, 1, 1, 0)))
	bone_material.set_shader_parameter("body_tint", biome.get("bone_tint", Color(1, 1, 1, 0)))
	cactus_material.set_shader_parameter("body_tint", Color(0.5, 0.7, 0.36, 0.3))
	# Dunes: the rock model coloured almost fully in shadowed sand.
	var dune: Color = look.dune_shadow
	dune_material.set_shader_parameter("body_tint", Color(dune.r, dune.g, dune.b, 0.85))

## Mesh and base transform of a desert model ("sandstone", "ribs", "cactus", "skull", "rock_arch").
func desert_part(key: String) -> Array:
	return desert_parts.get(key, [rock_mesh, rock_base])

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
	if layout != null:
		var stones: Array[Vector3] = []
		for stone in _chunk_stones.get(key, []):
			stones.append(Vector3(stone.x, 0.0, stone.z))
		return stones
	var origin := Vector3(key.x * CELL, 0, key.y * CELL)
	var flip := 1.0 if _hash(key.x, key.y, 4) % 2 == 0 else -1.0
	var shift := float(_hash(key.x, key.y, 8) % 5 - 2) * 0.75
	var result: Array[Vector3] = []
	# Stones at the map edge would pinch the passage to the wall: left out.
	for center in [origin + Vector3(-8.6, 0, flip * 7.6 + shift), origin + Vector3(8.6, 0, -flip * 7.6 + shift)]:
		if _stone_allowed(center, OBSTACLE_RADIUS):
			result.append(center)
	return result

# A stone (circle) keeps EDGE_STONE_GAP to the playable edge.
func _stone_allowed(center: Vector3, radius: float) -> bool:
	return is_inside(center, radius + EDGE_STONE_GAP)

# A landmark stays well inside the map (its footprint plus EDGE_LANDMARK_GAP).
func _landmark_allowed(center: Vector3, footprint: float) -> bool:
	return is_inside(center, footprint + EDGE_LANDMARK_GAP)

# True if the chunk belongs to the map (not the border ring).
func in_map(key: Vector2i) -> bool:
	return key.x >= _chunk_lo and key.x <= _chunk_hi and key.y >= _chunk_lo and key.y <= _chunk_hi

# Distance to the nearest point kept clear (start points, migration arrival).
func _clear_distance(x: float, z: float) -> float:
	var best := INF
	for point in _clear_points:
		best = minf(best, Vector2(x - point.x, z - point.z).length())
	return best

# The seed only enters as an additive constant, so seed 0 keeps the classic hash.
func _hash(x: int, z: int, salt: int) -> int:
	var n := x * 374761393 + z * 668265263 + salt * 144269 + _seed_mix
	n = (n ^ (n >> 13)) * 1274126177
	return abs(n ^ (n >> 16))

func _unit(x: int, z: int, salt: int) -> float:
	return float(_hash(x, z, salt) % 1000) / 999.0

# The landmark hosted by this chunk, or {} (type, world centre, yaw).
func landmark(key: Vector2i) -> Dictionary:
	if layout != null:
		return _chunk_marks.get(key, {})
	if _landmark_cache.has(key):
		return _landmark_cache[key]
	if _landmark_cache.size() > CACHE_LIMIT:
		_landmark_cache.clear()
	if not in_map(key):
		_landmark_cache[key] = {}
		return {}
	var result := {}
	var region := Vector2i(floori(float(key.x) / LANDMARK_REGION), floori(float(key.y) / LANDMARK_REGION))
	var host := _hash(region.x, region.y, 700) % (LANDMARK_REGION * LANDMARK_REGION)
	var host_key := region * LANDMARK_REGION + Vector2i(host % LANDMARK_REGION, host / LANDMARK_REGION)
	# Most regions carry one; a few stay completely open.
	if key == host_key and _hash(region.x, region.y, 710) % 5 != 0:
		var shift := float(_hash(key.x, key.y, 720) % 5 - 2) * 0.5
		var center := Vector3(key.x * CELL, 0.0, key.y * CELL + CELL * 0.5 + shift)
		var type: int = posmod(region.x + 2 * region.y, 4)
		if Vector2(center.x, center.z).length() >= LANDMARK_START_CLEARANCE and _landmark_allowed(center, LANDMARK_FOOTPRINT[type]):
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

# Every collision circle owned by a chunk as Vector4(x, 0, z, radius): the
# stones plus the small blocking parts of its landmark (arch feet, log). The
# walls of a seeded map are not circles: see wall_distance().
func obstacles(key: Vector2i) -> Array[Vector4]:
	if _obstacle_cache.has(key):
		return _obstacle_cache[key]
	if _obstacle_cache.size() > CACHE_LIMIT:
		_obstacle_cache.clear()
	var result: Array[Vector4] = []
	if not in_map(key):
		_obstacle_cache[key] = result
		return result
	if layout != null:
		for stone in _chunk_stones.get(key, []):
			result.append(stone)
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

# --- Regions -------------------------------------------------------------------

# Regions are aligned to the map's first chunk; for even map sizes this is the
# same grid as floor(chunk / REGION).
func _region_key(key: Vector2i) -> Vector2i:
	return Vector2i(floori(float(key.x - _chunk_lo) / REGION) + _region_lo, floori(float(key.y - _chunk_lo) / REGION) + _region_lo)

## Soft colour shift of one region (seeded maps only): hue and value.
func region_params(region: Vector2i) -> Dictionary:
	if _region_cache.has(region):
		return _region_cache[region]
	if _region_cache.size() > CACHE_LIMIT:
		_region_cache.clear()
	var result := {
		"hue": float(_hash(region.x, region.y, 910) % 9 - 4) * 0.005,
		"value": float(_hash(region.x, region.y, 911) % 9 - 4) * 0.01,
	}
	_region_cache[region] = result
	return result

static func _segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
	return point.distance_to(a + ab * t)

## Distance from a point to the sand edge of the nearest trail (negative = on it).
func trail_clearance(world: Vector3) -> float:
	var key := _cell(world)
	if layout == null:
		return absf(world.x - key.x * CELL - _trail_center(key, world.z - key.y * CELL)) - TRAIL_HALF_WIDTH
	var point := Vector2(world.x, world.z)
	var best := INF
	for x in range(key.x - 1, key.x + 2):
		for z in range(key.y - 1, key.y + 2):
			var samples: Array = _chunk_trails.get(Vector2i(x, z), [])
			for sample in samples:
				best = minf(best, point.distance_to(Vector2(sample.x, sample.z)) - sample.w)
	return best

## Centreline samples (x, 0, z, sand half width) of every trail crossing this chunk.
func trail_samples(key: Vector2i) -> Array[Vector4]:
	var result: Array[Vector4] = []
	if layout == null:
		for step in 29:
			var z := float(step)
			result.append(Vector4(key.x * CELL + _trail_center(key, z), 0.0, key.y * CELL + z, TRAIL_HALF_WIDTH))
		return result
	for sample in _chunk_trails.get(key, []):
		result.append(sample)
	return result

# --- Map layout (stage 18b) ---------------------------------------------------------

# Builds the clearing/path layout of a seeded map and buckets its parts per chunk.
func _build_layout() -> void:
	_discovered = PackedByteArray()
	_astar = null
	_route_key = Vector4i(-1, -1, -1, -1)
	_route = PackedVector3Array()
	for cache in [_chunk_stones, _chunk_marks, _chunk_trails, _chunk_eruptions, _chunk_caps, _chunk_sands]:
		cache.clear()
	if world_seed == 0:
		layout = null
		flow = null
		flow_big = null
		_refresh_beacons()
		return
	var starts := _raw_spawn_points(player_count)
	if layout_style == "graph":
		layout = MAP_LAYOUT.new(world_seed, _playable, _bounds, map_regions, starts, _arrival)
	else:
		layout = _take_prefetch(_layout_key(world_seed, biome_id, starts, _arrival))
		if layout == null:
			layout = MAP_EXPLORE.new(world_seed, _playable, _bounds, map_regions, starts, _arrival, biome_id)
	for stone in layout.stones:
		_bucket(_chunk_stones, Vector3(stone.x, 0.0, stone.z), stone)
	for mark in layout.landmarks:
		_chunk_marks[_cell(mark.center)] = {"type": int(mark.type), "center": mark.center, "yaw": float(mark.yaw)}
	_sand_keep.clear()
	for edge in layout.edges:
		var points: PackedVector3Array = edge.points
		var halves: PackedFloat32Array = edge.half
		# The sand runs from clearing to clearing and ends a little way into
		# each one with a round cap (start clearings: on to the central plaza).
		var keep := PackedByteArray()
		keep.resize(points.size())
		for index in points.size():
			keep[index] = 1
			for end in [edge.a, edge.b]:
				var node: Dictionary = layout.nodes[end]
				if _has_plaza(node):
					continue
				if points[index].distance_to(node.center) < float(node.radius) * 0.55:
					keep[index] = 0
		_sand_keep.append(keep)
		for index in points.size():
			if keep[index] == 0:
				continue
			var sand := _sand(halves[index])
			_bucket(_chunk_trails, points[index], Vector4(points[index].x, 0.0, points[index].z, sand))
			if index + 1 < points.size() and keep[index + 1] == 1:
				# Samples every ~1.5 m (half steps) so the minimap brushes join.
				var middle := (points[index] + points[index + 1]) * 0.5
				_bucket(_chunk_trails, middle, Vector4(middle.x, 0.0, middle.z, _sand((halves[index] + halves[index + 1]) * 0.5)))
			var open_end := (index == 0 or keep[index - 1] == 0) or (index == points.size() - 1 or keep[index + 1] == 0)
			if open_end and not _plaza_at(points[index]):
				_bucket(_chunk_caps, points[index], Vector4(points[index].x, 0.0, points[index].z, sand))
	for node in layout.nodes:
		if _has_plaza(node):
			var center: Vector3 = node.center
			_bucket(_chunk_trails, center, Vector4(center.x, 0.0, center.z, _plaza_radius(node)))
	for point in layout.eruption_points:
		_bucket(_chunk_eruptions, Vector3(point.x, 0.0, point.z), point)
	# Stage 19: quicksand patches, in every chunk they reach (motion lookup).
	var sands: Variant = layout.get("quicksand")
	if sands is Array:
		for patch in sands:
			var lo := _cell(Vector3(patch.x - patch.w, 0.0, patch.z - patch.w))
			var hi := _cell(Vector3(patch.x + patch.w, 0.0, patch.z + patch.w))
			for cx in range(lo.x, hi.x + 1):
				for cz in range(lo.y, hi.y + 1):
					var key := Vector2i(cx, cz)
					if not _chunk_sands.has(key):
						_chunk_sands[key] = []
					_chunk_sands[key].append(patch)
	flow = FLOW_FIELD.new(layout, FLOW_CELL)
	flow_big = FLOW_FIELD.new(layout, FLOW_CELL, BIG_CLEARANCE)
	_discovered.resize(layout.nodes.size())
	_refresh_beacons()

# Stage 18c: the tall landmarks (outside the chunks, always in the picture).
func _refresh_beacons() -> void:
	if ground_mesh == null:
		return
	if _beacons == null:
		_beacons = Node3D.new()
		_beacons.name = "Beacons"
		add_child(_beacons)
	BEACONS.build(self, _beacons)

func _bucket(target: Dictionary, point: Vector3, value: Variant) -> void:
	var key := _cell(point)
	if not target.has(key):
		target[key] = []
	target[key].append(value)

# Tells every prop material where the swarm stands (see-through window).
func _update_fade(position: Vector3) -> void:
	for material in fade_materials:
		material.set_shader_parameter("fade_center", Vector3(position.x, 0.0, position.z))
		material.set_shader_parameter("fade_radius", FADE_RADIUS if fade_enabled else 0.0)


# Advances the shared flow fields towards the swarm (a few hundred cells per
# frame; the normal and the big-body field take turns).
func _step_flow(position: Vector3) -> void:
	if flow == null:
		return
	var started := Time.get_ticks_usec()
	_flow_turn += 1
	var field: RefCounted = flow if flow_big == null or _flow_turn % 2 == 0 else flow_big
	if not field.is_running():
		var source: Vector3 = field.source
		if not source.is_finite() or Vector2(source.x - position.x, source.z - position.z).length() >= FLOW_MOVE:
			field.begin(position)
	if field.is_running():
		field.step(FLOW_BUDGET)
	flow_step_ms = float(Time.get_ticks_usec() - started) / 1000.0

## Runs the flow fields to completion from `position` (tests, map start).
func finish_flow(position: Vector3) -> void:
	for field in [flow, flow_big]:
		if field == null:
			continue
		field.begin(position)
		while not field.step(100000):
			pass
## True on a seeded map with clearings, paths and walls.
func has_layout() -> bool:
	return layout != null

## Signed distance to the nearest wall (+ open ground, - inside a wall); the
## map edge counts as a wall. Classic map: distance to the playable edge.
func wall_distance(point: Vector3) -> float:
	if layout == null:
		return -edge_distance(point)
	return layout.sample(point.x, point.z)

## POI positions of one clearing type over the whole map: "start", "arrival",
## "boss" (Bog King / Apex arena), "maw" (Migrationsschlund), "nest", "totem",
## "cocoon" (Kokons, stage 17), "grove" (Pilzknollen-Hain), "landmark".
## Empty on the classic map.
func poi_slots(type: String) -> Array[Vector3]:
	if layout == null:
		var none: Array[Vector3] = []
		return none
	return layout.slots(type)

## Every clearing: [{id, center: Vector3, radius, types: Array[String],
## slots: {type: Array[Vector3]}, paths: Array[int]}].
func clearings() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if layout == null:
		return result
	for index in layout.nodes.size():
		var node: Dictionary = layout.nodes[index]
		result.append({"id": index, "center": node.center, "radius": float(node.radius), "types": (node.types as Array).duplicate(), "slots": node.slots, "paths": (node.edges as Array).duplicate()})
	return result

## Every path: [{id, a, b (clearing ids), kind "main"/"narrow", points
## (PackedVector3Array centreline), half (PackedFloat32Array walkable half
## width per point), length}].
func paths() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if layout == null:
		return result
	for index in layout.edges.size():
		var edge: Dictionary = layout.edges[index]
		result.append({"id": index, "a": int(edge.a), "b": int(edge.b), "kind": String(edge.kind), "points": edge.points, "half": edge.half, "length": float(edge.length)})
	return result

## Index of the clearing containing `point`, or -1 (on a path / classic map).
func clearing_at(point: Vector3) -> int:
	return layout.clearing_at(point) if layout != null else -1

## Walking direction towards the swarm (the flow field source) from `point`;
## ZERO when there is no field (classic map) or the point lies in a wall.
func flow_direction(point: Vector3) -> Vector3:
	if flow == null:
		return Vector3.ZERO
	return flow.direction(point)

## Walking distance (m) from `point` to the swarm over the paths; INF if unknown.
func flow_distance(point: Vector3) -> float:
	if flow == null:
		return INF
	return flow.distance(point)

# True if the line keeps `radius` of wall distance (samples every 2 m).
func _wall_line_clear(start: Vector3, end: Vector3, radius: float) -> bool:
	var length := Vector2(end.x - start.x, end.z - start.z).length()
	var samples := maxi(1, ceili(length / 2.0))
	for index in range(1, samples + 1):
		var point := start.lerp(end, float(index) / float(samples))
		if layout.sample(point.x, point.z) < radius + 0.15:
			return false
	return true

# Moves a point out of the walls along the distance gradient (slides along them).
func _push_walls(point: Vector3, radius: float) -> Vector3:
	for attempt in 5:
		var value: float = layout.sample(point.x, point.z)
		if value >= radius:
			break
		var slope: Vector2 = layout.gradient(point.x, point.z)
		if slope.length_squared() < 0.00000001:
			# Deep inside a wall (flat distance field, e.g. after a migration onto
			# a new map): jump to the nearest open ground.
			point = _nearest_open(point, radius)
			continue
		slope = slope.normalized()
		var push := radius - value + 0.02
		point.x += slope.x * push
		point.z += slope.y * push
	return point

## Pushes a point (circle of `radius`) out of the walls; classic map: unchanged.
func push_walls(point: Vector3, radius: float) -> Vector3:
	if layout == null:
		return point
	return _push_walls(point, radius)

# Nearest point with `radius` of wall distance (square rings on the SDF grid).
func _nearest_open(point: Vector3, radius: float) -> Vector3:
	var grid: int = layout.grid
	var origin: Vector2 = layout.grid_origin
	var nav: float = layout.NAV
	var values: PackedFloat32Array = layout.sdf
	var cx := clampi(floori((point.x - origin.x) / nav), 0, grid - 1)
	var cz := clampi(floori((point.z - origin.y) / nav), 0, grid - 1)
	var best := Vector3.INF
	var best_d := INF
	for ring in range(0, 60):
		if best.is_finite() and float(ring - 1) * nav > best_d:
			break
		for dz in range(-ring, ring + 1):
			var step := 1 if absi(dz) == ring else ring * 2
			for dx in range(-ring, ring + 1, maxi(1, step)):
				var x := cx + dx
				var z := cz + dz
				if x < 0 or z < 0 or x >= grid or z >= grid:
					continue
				if values[z * grid + x] < radius + 0.6:
					continue
				var candidate := Vector3(origin.x + (float(x) + 0.5) * nav, 0.0, origin.y + (float(z) + 0.5) * nav)
				var d := Vector2(candidate.x - point.x, candidate.z - point.z).length()
				if d < best_d:
					best_d = d
					best = candidate
	return best if best.is_finite() else map_center()

## An open, reachable spawn point about `distance` from `center` near the
## direction `angle` (tries neighbouring angles and distances). On a seeded
## map the walking distance may be at most about twice the straight one, so
## nothing spawns behind a thick wall. INF if nothing fits (or classic map).
func spawn_point_near(center: Vector3, distance: float, angle: float, clearance: float) -> Vector3:
	if layout == null:
		return Vector3.INF
	var field_ok: bool = flow != null and flow.ready and Vector2(flow.source.x - center.x, flow.source.z - center.z).length() < 10.0
	for attempt in 14:
		var turn := angle + float((attempt + 1) / 2) * 0.47 * (1.0 if attempt % 2 == 0 else -1.0)
		for reach in [1.0, 1.3, 0.8, 1.6]:
			var point := center + Vector3(cos(turn), 0.0, sin(turn)) * distance * float(reach)
			if not is_open(point, clearance + 0.3):
				continue
			if field_ok and flow.distance(point) > distance * float(reach) * 2.2 + 12.0:
				continue
			return point
	return Vector3.INF

## A flood spawn point: a random cell at 24-44 m walking distance from the
## swarm (the path mouths just out of view), at least 18 m away in a straight
## line. `salt` varies the pick. INF without a finished field.
func flood_point(salt: int) -> Vector3:
	if flow == null or not flow.ready:
		return Vector3.INF
	var ring: PackedInt32Array = flow.ring
	if ring.is_empty():
		return Vector3.INF
	var source: Vector3 = flow.source
	for attempt in 6:
		var roll := _scramble(salt * 7919 + attempt * 104729 + world_seed)
		var cell: int = ring[posmod(roll, ring.size())]
		var point: Vector3 = flow.cell_center(cell)
		point.x += (float(posmod(roll >> 12, 100)) / 100.0 - 0.5) * 2.4
		point.z += (float(posmod(roll >> 20, 100)) / 100.0 - 0.5) * 2.4
		if Vector2(point.x - source.x, point.z - source.z).length() < 18.0:
			continue
		if is_open(point, 0.5):
			return point
	return Vector3.INF

# Cached A* grid over the flow cells (native) for nav_direction().
var _astar: AStarGrid2D
var _route_key := Vector4i(-1, -1, -1, -1)
var _route := PackedVector3Array()

## Walking direction from `from` towards any `to` over the paths (the bot and
## other seekers): straight when the line is clear, else along an A* route on
## the flow grid (cached while both ends stay in their cells). Classic map:
## the straight direction.
func nav_direction(from: Vector3, to: Vector3, radius := 0.8) -> Vector3:
	var straight := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if straight.length_squared() < 0.0001:
		return Vector3.ZERO
	if layout == null or _wall_line_clear(from, to, radius):
		return straight.normalized()
	if _astar == null:
		_astar = AStarGrid2D.new()
		_astar.region = Rect2i(0, 0, flow.size, flow.size)
		_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		_astar.update()
		for index in flow.passable.size():
			if flow.passable[index] == 0:
				_astar.set_point_solid(Vector2i(index % flow.size, index / flow.size), true)
	var a: int = flow.index_of(from)
	var b: int = flow.index_of(to)
	if a < 0 or b < 0:
		return straight.normalized()
	var key := Vector4i(a % flow.size, a / flow.size, b % flow.size, b / flow.size)
	if key != _route_key:
		_route_key = key
		_route = PackedVector3Array()
		var start := Vector2i(key.x, key.y)
		var goal := Vector2i(key.z, key.w)
		if _astar.is_point_solid(start):
			start = _open_cell_near(start)
		if _astar.is_point_solid(goal):
			goal = _open_cell_near(goal)
		if start.x >= 0 and goal.x >= 0:
			for cell in _astar.get_id_path(start, goal):
				_route.append(flow.cell_center(cell.y * flow.size + cell.x))
	# Head for the farthest route point that is in clear sight.
	var aim := to
	for index in range(mini(_route.size() - 1, 8), 0, -1):
		if _wall_line_clear(from, _route[index], radius):
			aim = _route[index]
			break
	if aim == to and _route.size() > 1:
		aim = _route[1]
	var direction := Vector3(aim.x - from.x, 0.0, aim.z - from.z)
	return direction.normalized() if direction.length_squared() > 0.0001 else straight.normalized()

func _open_cell_near(cell: Vector2i) -> Vector2i:
	for ring in range(1, 4):
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				var other := cell + Vector2i(dx, dz)
				if _astar.is_in_boundsv(other) and not _astar.is_point_solid(other):
					return other
	return Vector2i(-1, -1)

## A direction close to `direction` that does not run into a wall within
## `probe` m (tries +-25, 50, 75, 100 degrees). Classic map: unchanged.
func open_direction(from: Vector3, direction: Vector3, radius := 0.8, probe := 3.0) -> Vector3:
	if layout == null or direction.length_squared() < 0.0001:
		return direction
	var forward := Vector3(direction.x, 0.0, direction.z).normalized()
	for turn in [0.0, 0.44, -0.44, 0.87, -0.87, 1.31, -1.31, 1.75, -1.75]:
		var candidate := forward.rotated(Vector3.UP, float(turn))
		var point := from + candidate * probe
		if layout.sample(point.x, point.z) >= radius + 0.2:
			return candidate * direction.length()
	return direction

# Smooth ground tint: region colours blended bilinearly between region centres.
func _ground_tint(x: float, z: float) -> Color:
	var fx := (x - _region_origin) / (REGION * CELL) - 0.5
	var fz := (z - _region_origin) / (REGION * CELL) - 0.5
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

# Sand band of this chunk's share of the paths: every path segment whose
# midpoint lies inside the chunk (so neighbours tile seamlessly) plus the round
# plaza at each clearing centre (quads of a polar grid, each owned by the chunk
# holding its centre). `extra` widens the band (edge strip).
func _path_mesh(key: Vector2i, extra: float, height: float) -> Mesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var origin := Vector3(key.x * CELL, 0.0, key.y * CELL)
	var area := Rect2(origin.x, origin.z, CELL, CELL)
	var reach := area.grow(4.0)
	var lift := Vector3(0.0, height, 0.0)
	var count := 0
	for edge_index in layout.edges.size():
		var edge: Dictionary = layout.edges[edge_index]
		var points: PackedVector3Array = edge.points
		var halves: PackedFloat32Array = edge.half
		var keep: PackedByteArray = _sand_keep[edge_index]
		for index in points.size() - 1:
			var middle := (points[index] + points[index + 1]) * 0.5
			if keep[index] == 0 or keep[index + 1] == 0 or not area.has_point(Vector2(middle.x, middle.z)):
				continue
			var side0 := _side(points, index) * (_sand(halves[index]) + extra)
			var side1 := _side(points, index + 1) * (_sand(halves[index + 1]) + extra)
			var a := points[index] - origin + lift
			var b := points[index + 1] - origin + lift
			for point in [a - side0, a + side0, b - side1, a + side0, b + side1, b - side1]:
				surface.set_normal(Vector3.UP)
				surface.add_vertex(point)
			count += 1
	for cap in _chunk_caps.get(key, []):
		var hub := Vector3(cap.x, 0.0, cap.z) - origin + lift
		for index in 14:
			var d0: Vector3 = Vector3(cos(TAU * float(index) / 14.0), 0.0, sin(TAU * float(index) / 14.0)) * (float(cap.w) + extra)
			var d1: Vector3 = Vector3(cos(TAU * float(index + 1) / 14.0), 0.0, sin(TAU * float(index + 1) / 14.0)) * (float(cap.w) + extra)
			for point in [hub, hub + d0, hub + d1]:
				surface.set_normal(Vector3.UP)
				surface.add_vertex(point)
		count += 1
	for node in layout.nodes:
		var center: Vector3 = node.center
		var radius := _plaza_radius(node) + extra
		if not _has_plaza(node) or not reach.grow(radius).has_point(Vector2(center.x, center.z)):
			continue
		for ring in 3:
			var r0 := radius * float(ring) / 3.0
			var r1 := radius * float(ring + 1) / 3.0
			for index in 24:
				var d0 := Vector3(cos(TAU * float(index) / 24.0), 0.0, sin(TAU * float(index) / 24.0))
				var d1 := Vector3(cos(TAU * float(index + 1) / 24.0), 0.0, sin(TAU * float(index + 1) / 24.0))
				var mid := center + (d0 + d1) * 0.25 * (r0 + r1)
				if not area.has_point(Vector2(mid.x, mid.z)):
					continue
				var base := center - origin + lift
				for point in [base + d0 * r0, base + d0 * r1, base + d1 * r1, base + d0 * r0, base + d1 * r1, base + d1 * r0]:
					surface.set_normal(Vector3.UP)
					surface.add_vertex(point)
				count += 1
	if count == 0:
		return null
	return surface.commit()

# Sand half width of a path point with walkable half width `half`.
func _sand(half: float) -> float:
	# Stage 18c: loose trails are narrower than the 18b roads.
	if layout != null and layout.get("sand_share") != null:
		return maxf(float(layout.sand_min), half * float(layout.sand_share))
	return maxf(2.4, half * SAND_SHARE)

# Start and arrival clearings carry a round sand plaza where the paths meet.
func _has_plaza(node: Dictionary) -> bool:
	var types: Array = node.types
	return types.has("start") or types.has("arrival")

# True if a point lies on the plaza of a start clearing.
func _plaza_at(point: Vector3) -> bool:
	for node in layout.nodes:
		if _has_plaza(node) and point.distance_to(node.center) < _plaza_radius(node):
			return true
	return false

# Round sand plaza where the paths meet in a clearing.
func _plaza_radius(node: Dictionary) -> float:
	var widest := 2.4
	for edge_index in node.edges:
		var halves: PackedFloat32Array = layout.edges[edge_index].half
		widest = maxf(widest, _sand(halves[0]))
		widest = maxf(widest, _sand(halves[halves.size() - 1]))
	return maxf(widest + 1.5, float(node.radius) * 0.26)

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
	# Stage 19: quicksand slows everything crossing it; a sandstorm hastens every
	# creature except the swarm.
	if not _chunk_sands.is_empty():
		motion *= quicksand_factor(start)
	if enemy_haste != 1.0 and radius != SWARM_MOTION_RADIUS:
		motion *= enemy_haste
	var result := start + motion
	# Resolve X and Z separately so the joystick naturally slides along stone.
	result.x = _push_out(Vector3(result.x, 0, start.z), radius).x
	result.z = _push_out(Vector3(result.x, 0, result.z), radius).z
	if layout != null:
		# Walls: pushed out along the distance gradient = sliding along the wall.
		result = _push_walls(result, radius)
		if layout.sample(result.x, result.z) < radius - 0.1:
			# Wedged in a corner: keep whichever single axis still fits, else stay.
			var along_x := _push_walls(Vector3(start.x + motion.x, 0.0, start.z), radius)
			var along_z := _push_walls(Vector3(start.x, 0.0, start.z + motion.z), radius)
			if layout.sample(along_x.x, along_x.z) >= radius - 0.1:
				result = along_x
			elif layout.sample(along_z.x, along_z.z) >= radius - 0.1:
				result = along_z
			else:
				result = start
	# The map edge is an obstacle too: clamping per axis slides along the wall.
	return clamp_inside(result, radius)

## Stage 19: speed factor of the ground at a point (1 = firm, TUNING.QUICKSAND_SLOW
## inside a quicksand patch, eased over QUICKSAND_RIM at its edge).
func quicksand_factor(point: Vector3) -> float:
	var patches: Array = _chunk_sands.get(_cell(point), [])
	if patches.is_empty():
		return 1.0
	var factor := 1.0
	for patch in patches:
		var distance := Vector2(point.x - patch.x, point.z - patch.z).length()
		if distance < patch.w:
			var depth := smoothstep(0.0, TUNING.QUICKSAND_RIM, patch.w - distance)
			factor = minf(factor, lerpf(1.0, TUNING.QUICKSAND_SLOW, depth))
	return factor

## Stage 19: quicksand patches of the map (empty outside the desert).
func quicksand_patches() -> Array[Vector4]:
	var result: Array[Vector4] = []
	if layout != null and layout.get("quicksand") is Array:
		for patch in layout.quicksand:
			result.append(patch)
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
	if not is_inside(location, radius):
		return false
	if layout != null and layout.sample(location.x, location.z) < radius:
		return false
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

## Walking direction from `start` towards `target` for a creature of `radius`.
## Seeded maps (stage 18b): straight when the line is clear within LOS_RANGE,
## otherwise along the shared flow field (every enemy targets the swarm, the
## field's source) or, for other targets, along the wall; stones ahead are
## passed on their free side. Classic map: straight with a stone sidestep.
func steer_direction(start: Vector3, target: Vector3, radius: float) -> Vector3:
	var desired := target - start
	desired.y = 0
	if desired.length_squared() < 0.0001:
		return Vector3.ZERO
	var forward := desired.normalized()
	if layout != null:
		var distance := desired.length()
		if distance > LOS_RANGE or not _wall_line_clear(start, target, radius):
			var guided := Vector3.ZERO
			var field: RefCounted = flow_big if radius >= BIG_RADIUS and flow_big != null else flow
			if field != null and field.ready and Vector2(field.source.x - target.x, field.source.z - target.z).length() < 8.0:
				guided = field.direction(start)
				# A big body outside the wide ground follows the normal field out.
				if guided == Vector3.ZERO and field == flow_big and flow.ready:
					guided = flow.direction(start)
			if guided != Vector3.ZERO:
				forward = guided
			else:
				forward = _along_wall(start, forward, radius)
		return _around_stones(start, forward, radius)
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

# Heading into a wall: turned along it (the side closer to the wish).
func _along_wall(start: Vector3, forward: Vector3, radius: float) -> Vector3:
	var probe := start + forward * 2.0
	if layout.sample(probe.x, probe.z) >= radius + 0.3:
		return forward
	var slope: Vector2 = layout.gradient(probe.x, probe.z)
	if slope.length_squared() < 0.00000001:
		return forward
	slope = slope.normalized()
	var tangent := Vector3(-slope.y, 0.0, slope.x)
	if tangent.dot(forward) < 0.0:
		tangent = -tangent
	return (tangent + Vector3(slope.x, 0.0, slope.y) * 0.3).normalized()

# A stone right ahead: bend past it on the side it leaves free.
func _around_stones(start: Vector3, forward: Vector3, radius: float) -> Vector3:
	var best := INF
	var side := 0.0
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
	if side == 0.0:
		return forward
	return (forward + Vector3(forward.z * side, 0, -forward.x * side) * 1.3).normalized()

## Nearest free spot: inside the playable area, outside every stone and (on a
## seeded map) out of the walls.
func safe_spawn(location: Vector3, radius: float) -> Vector3:
	var point := clamp_inside(location, radius)
	if layout != null and layout.sample(point.x, point.z) < radius:
		if layout.sample(point.x, point.z) < radius - 3.0:
			point = _nearest_open(point, radius)
		point = _push_walls(point, radius)
	point = _push_out(point, radius)
	if layout != null:
		point = _push_walls(point, radius)
	return clamp_inside(point, radius)

# --- Map bounds (stage 18) -----------------------------------------------------

func _update_map_geometry() -> void:
	var chunks_per_side := map_regions * REGION
	_chunk_lo = -(chunks_per_side / 2)
	_chunk_hi = _chunk_lo + chunks_per_side - 1
	_region_lo = -(map_regions / 2)
	_region_origin = float(_chunk_lo - _region_lo * REGION) * CELL
	_bounds = Rect2(_chunk_lo * CELL, _chunk_lo * CELL, chunks_per_side * CELL, chunks_per_side * CELL)
	_playable = _bounds.grow(-BORDER_INSET)
	_update_clear_points()

func _update_clear_points() -> void:
	var points: Array[Vector3] = []
	points.append_array(_raw_spawn_points(player_count))
	points.append_array(_arrival)
	_clear_points = points

## Map bounds in world metres (x, z) including the wall strip.
func bounds() -> Rect2:
	return _bounds

## Area creatures may use (bounds minus BORDER_INSET).
func playable_rect() -> Rect2:
	return _playable

## Centre of the map (the origin for even region counts).
func map_center() -> Vector3:
	var middle := _bounds.get_center()
	return Vector3(middle.x, 0.0, middle.y)

## Map side length in metres.
func map_size() -> float:
	return _bounds.size.x

## True if a circle of `margin` around the point lies in the playable area.
func is_inside(point: Vector3, margin := 0.0) -> bool:
	return point.x >= _playable.position.x + margin and point.x <= _playable.end.x - margin and point.z >= _playable.position.y + margin and point.z <= _playable.end.y - margin

## The point moved (per axis) so a circle of `margin` fits in the playable area.
func clamp_inside(point: Vector3, margin := 0.0) -> Vector3:
	var half := minf(margin, _playable.size.x * 0.5)
	point.x = clampf(point.x, _playable.position.x + half, _playable.end.x - half)
	point.z = clampf(point.z, _playable.position.y + half, _playable.end.y - half)
	return point

## A spawn candidate beyond the edge is mirrored at the edge to the inner side
## (a ring around the swarm keeps its distance), then clamped as a last resort.
func fold_inside(point: Vector3, margin := 0.0) -> Vector3:
	var low := Vector2(_playable.position.x + margin, _playable.position.y + margin)
	var high := Vector2(_playable.end.x - margin, _playable.end.y - margin)
	if point.x < low.x:
		point.x = 2.0 * low.x - point.x
	elif point.x > high.x:
		point.x = 2.0 * high.x - point.x
	if point.z < low.y:
		point.z = 2.0 * low.y - point.z
	elif point.z > high.y:
		point.z = 2.0 * high.y - point.z
	return clamp_inside(point, margin)

## Signed distance to the playable edge: negative inside, positive beyond it.
func edge_distance(point: Vector3) -> float:
	var dx := maxf(_playable.position.x - point.x, point.x - _playable.end.x)
	var dz := maxf(_playable.position.y - point.z, point.z - _playable.end.y)
	if dx > 0.0 and dz > 0.0:
		return Vector2(dx, dz).length()
	return maxf(dx, dz)

## Start points for `count` players (1 = the map centre). Several players start
## in different regions on a seeded ring around the centre, far apart, each on
## open ground (stones and landmarks keep clear of them for the configured
## player_count).
func spawn_points(count: int) -> Array[Vector3]:
	var result: Array[Vector3] = []
	# Seeded map: the start clearings (built for the configured player count).
	if layout != null and count == player_count:
		for point in layout.slots("start"):
			result.append(_open_spot(point, 3.0))
		if result.size() == count:
			return result
		result.clear()
	for point in _raw_spawn_points(count):
		result.append(_open_spot(point, 3.0))
	return result

# The point itself if a circle of `radius` is free there, else the nearest free
# spot on rings of growing size (deterministic), else safe_spawn().
func _open_spot(point: Vector3, radius: float) -> Vector3:
	if is_open(point, radius):
		return point
	for ring in range(1, 13):
		for index in 12:
			var angle := TAU * float(index) / 12.0 + float(ring) * 0.37
			var candidate := point + Vector3(cos(angle), 0.0, sin(angle)) * float(ring) * 1.5
			if is_open(candidate, radius):
				return candidate
	return safe_spawn(point, radius)

func _raw_spawn_points(count: int) -> Array[Vector3]:
	var center := map_center()
	var result: Array[Vector3] = []
	if count <= 1:
		result.append(center)
		return result
	var start := float(_hash(count, 0, 1900) % 628) * 0.01
	var reach := _bounds.size.x * SPAWN_RING_SHARE
	for index in count:
		var angle := start + TAU * float(index) / float(count)
		var point := center + Vector3(cos(angle), 0.0, sin(angle)) * reach
		result.append(clamp_inside(point, START_CLEARANCE + EDGE_LANDMARK_GAP))
	return result

func _make_chunk(key: Vector2i) -> Node3D:
	var chunk := Node3D.new()
	chunk.name = "Jungle %d %d" % [key.x, key.y]
	chunk.position = Vector3(key.x * CELL, 0, key.y * CELL)
	add_child(chunk)
	# Border ring: only the natural edge (walls, water, ground fade, fog).
	if not in_map(key):
		chunk.name = "Edge %d %d" % [key.x, key.y]
		border.build(chunk, key)
		return chunk
	if border.touches(key):
		border.build(chunk, key)
	var seeded := layout != null
	var ember := _ember_look()
	if ember:
		# Glutsumpf: shader ground and one glow-channel mesh instead of edge + trail.
		if seeded:
			_part(chunk, "Open ground", _ground_mesh(key), ember_ground_tint_material, Vector3(0, -0.02, 0))
		else:
			_part(chunk, "Open ground", ground_mesh, ember_ground_material, Vector3(CELL * 0.5, -0.02, CELL * 0.5))
		_part(chunk, "Glow channel", _channel_mesh(key), channel_material, Vector3.ZERO)
	elif seeded:
		_part(chunk, "Open ground", _ground_mesh(key), desert_ground_tint_material if _desert_look() else ground_tint_material, Vector3(0, -0.02, 0))
		_part(chunk, "Trail edge", _path_mesh(key, TRAIL_EDGE_WIDTH - TRAIL_HALF_WIDTH, 0.003), path_edge_material, Vector3.ZERO)
		_part(chunk, "Broad trail", _path_mesh(key, 0.0, 0.007), path_material, Vector3.ZERO)
	else:
		_part(chunk, "Open ground", ground_mesh, desert_ground_material if _desert_look() else ground_material, Vector3(CELL * 0.5, -0.02, CELL * 0.5))
		_part(chunk, "Trail edge", _trail_mesh(key, TRAIL_EDGE_WIDTH, 0.003), path_edge_material, Vector3.ZERO)
		_part(chunk, "Broad trail", _trail_mesh(key, TRAIL_HALF_WIDTH, 0.007), path_material, Vector3.ZERO)
	if seeded:
		# Stage 18b: the walls between clearings and paths (dark floor + props).
		border.build_walls(chunk, key)
	# Calm ground variation: soft moss tints, a few sand/earth spots, small pebbles
	# (Glutsumpf: ash, slag and slag lumps). Thinned by the quality decor density.
	for index in QUALITY.scaled_count(int(biome.moss_patches), decor_density):
		var spot := Vector3(2.0 + float(_hash(key.x, key.y, index + 30) % 24), 0.001, 2.0 + float(_hash(key.x, key.y, index + 60) % 24))
		if _near_trail(chunk.position + spot, 1.0) or _in_wall(chunk.position + spot, 1.5):
			continue
		var tint := moss_materials[_hash(key.x, key.y, index + 90) % moss_materials.size()]
		var moss := _part(chunk, "Low leaf cover", patch_mesh, tint, spot)
		var size := 1.3 + float(_hash(key.x, key.y, index + 120) % 5) * 0.3
		moss.scale = Vector3(size * 1.5, 1, size)
		moss.rotation.y = float(_hash(key.x, key.y, index + 150) % 628) * 0.01
	for index in QUALITY.scaled_count(int(biome.sand_patches), decor_density):
		var spot := Vector3(2.0 + float(_hash(key.x, key.y, index + 180) % 24), 0.002, 2.0 + float(_hash(key.x, key.y, index + 210) % 24))
		if _near_trail(chunk.position + spot, 1.5) or _in_wall(chunk.position + spot, 1.5):
			continue
		var dirt := _part(chunk, "Sand patch", patch_mesh, sand_material if index % 3 != 2 else earth_material, spot)
		var size := 1.2 + float(_hash(key.x, key.y, index + 240) % 4) * 0.3
		dirt.scale = Vector3(size * 1.4, 1, size)
		dirt.rotation.y = float(_hash(key.x, key.y, index + 270) % 628) * 0.01
	# Stage 18c follow-up: no pebbles, leaf clumps or single flowers on walkable
	# ground any more - small 3D bits read like obstacles. Only flat patches stay.
	if seeded:
		var desert := _desert_look()
		for stone in _chunk_stones.get(key, []):
			# Desert landmark feet (skull, rock arch) carry their own model.
			if desert and _beacon_stone(stone):
				continue
			if ember:
				_basalt(chunk, Vector3(stone.x, 0.0, stone.z), stone.w)
			else:
				_boulder(chunk, Vector3(stone.x, 0.0, stone.z), stone.w)
		# Stage 19: quicksand patches (flat, walkable, animated swirl).
		if desert and quicksand_material != null:
			for patch in _chunk_sands.get(key, []):
				if _cell(Vector3(patch.x, 0.0, patch.z)) != key:
					continue
				var sand := _part(chunk, "Quicksand", quicksand_mesh, quicksand_material, Vector3(patch.x, 0.011, patch.z) - chunk.position)
				sand.scale = Vector3(patch.w, 1.0, patch.w)
	else:
		for center in obstacle_centers(key):
			if ember:
				_basalt(chunk, center, OBSTACLE_RADIUS)
			else:
				_boulder(chunk, center, OBSTACLE_RADIUS)
	# A rare flat, walkable puddle on the classic map (no reeds: nothing that
	# looks solid without a collision).
	if not seeded and _hash(key.x, key.y, 13) % int(biome.pond_one_in) == 0 and not near_landmark(chunk.position + Vector3(4, 0, 22), 3.0) and is_inside(chunk.position + Vector3(4, 0, 22), 3.0):
		_pool(chunk, Vector3(4, 0, 22), Vector3(1.8, 1, 1.1))
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
			# Walkable flat water (stage 18c follow-up: no reeds, nothing tall).
			_pool(chunk, local, Vector3(3.2, 1, 2.3))
		Landmark.MEADOW:
			# A calm clearing dotted with 5-9 flowers: pure colour, no collision.
			var ground := _part(chunk, "Meadow", meadow_mesh, moss_materials[0], local + Vector3(0, 0.003, 0))
			ground.scale = Vector3(4.6, 1, 3.8)
			ground.rotation.y = yaw



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
			# Flat lava pool (stage 18c follow-up: nothing tall around it).
			_pool(chunk, local, Vector3(3.2, 1, 2.3))
		Landmark.MEADOW:
			# A clearing of pale ash dotted with 5-9 Glutpilze.
			var ground := _part(chunk, "Ash clearing", meadow_mesh, moss_materials[2], local + Vector3(0, 0.003, 0))
			ground.scale = Vector3(4.6, 1, 3.8)
			ground.rotation.y = yaw



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
	# Stage 18c follow-up: one big column cluster instead of three small shafts
	# (one clear obstacle, no loose parts); it covers the collision circle.
	var width := 2.1 * stone_scale
	var height := 3.6 * stone_scale * (0.9 + float((roll >> 12) % 5) * 0.05)
	_prop(chunk, "Basalt column", rock_mesh, rock_base, basalt_material, location, Vector3(width, height, width), yaw)

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
	if layout == null:
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
	for edge_index in layout.edges.size():
		var edge: Dictionary = layout.edges[edge_index]
		var points: PackedVector3Array = edge.points
		var halves: PackedFloat32Array = edge.half
		var keep: PackedByteArray = _sand_keep[edge_index]
		for index in points.size() - 1:
			var middle := (points[index] + points[index + 1]) * 0.5
			if keep[index] == 0 or keep[index + 1] == 0 or not area.has_point(Vector2(middle.x, middle.z)):
				continue
			var half := _sand((halves[index] + halves[index + 1]) * 0.5)
			_channel_strip(surface, points[index] - origin + lift, points[index + 1] - origin + lift, _side(points, index), _side(points, index + 1), half)
			count += 1
	for node in layout.nodes:
		var center: Vector3 = node.center
		var junction := _plaza_radius(node)
		if _has_plaza(node) and area.grow(junction + 4.0).has_point(Vector2(center.x, center.z)):
			count += _channel_disc(surface, center, junction, origin, lift, area)
	# Round ends where a channel stops inside a clearing.
	for x in range(key.x - 1, key.x + 2):
		for z in range(key.y - 1, key.y + 2):
			for cap in _chunk_caps.get(Vector2i(x, z), []):
				count += _channel_disc(surface, Vector3(cap.x, 0.0, cap.z), float(cap.w), origin, lift, area)
	if count == 0:
		return null
	return surface.commit()

# Round glow-channel disc (plaza or channel end): glowing centre, crust ring,
# rim; slightly higher than the strips. Every quad belongs to the chunk
# holding its middle. Returns the number of quads added.
func _channel_disc(surface: SurfaceTool, center: Vector3, junction: float, origin: Vector3, lift: Vector3, area: Rect2) -> int:
	var count := 0
	var hub := center - origin + lift + Vector3(0.0, 0.002, 0.0)
	var rings := [[0.0, 0.0, 1.0], [CHANNEL_CORE, 0.0, 0.1], [junction * 0.5, 0.0, 0.0], [junction, 0.35, 0.0], [junction + TRAIL_EDGE_WIDTH - TRAIL_HALF_WIDTH, 1.0, 0.0]]
	for index in 20:
		var d0 := Vector3(cos(TAU * float(index) / 20.0), 0.0, sin(TAU * float(index) / 20.0))
		var d1 := Vector3(cos(TAU * float(index + 1) / 20.0), 0.0, sin(TAU * float(index + 1) / 20.0))
		for ring in rings.size() - 1:
			var r0: Array = rings[ring]
			var r1: Array = rings[ring + 1]
			var mid := center + (d0 + d1) * 0.25 * (float(r0[0]) + float(r1[0]))
			if not area.has_point(Vector2(mid.x, mid.z)):
				continue
			var c0 := Color(r0[1], 0.0, 0.0, r0[2])
			var c1 := Color(r1[1], 0.0, 0.0, r1[2])
			var quad := [[hub + d0 * r0[0], c0], [hub + d0 * r1[0], c1], [hub + d1 * r1[0], c1], [hub + d0 * r0[0], c0], [hub + d1 * r1[0], c1], [hub + d1 * r0[0], c0]]
			for vertex in quad:
				surface.set_color(vertex[1])
				surface.set_normal(Vector3.UP)
				surface.add_vertex(vertex[0])
			count += 1
	return count

## Eruption sources of a chunk (scripts/eruptions.gd) as Vector4(x, 0, z, kind):
## kind 0 = lava pool centre, 1 = point on a glow channel (seeded map: on the
## paths and clearings). Deterministic from the layout; only meaningful in
## biomes with "eruptions": true.
func eruption_sites(key: Vector2i) -> Array[Vector4]:
	var result: Array[Vector4] = []
	if not in_map(key):
		return result
	var origin := Vector3(key.x * CELL, 0, key.y * CELL)
	if layout == null:
		if _hash(key.x, key.y, 13) % int(biome.pond_one_in) == 0 and not near_landmark(origin + Vector3(4, 0, 22), 3.0) and is_inside(origin + Vector3(4, 0, 22), 3.0):
			result.append(Vector4(origin.x + 4.0, 0.0, origin.z + 22.0, 0.0))
	var mark := landmark(key)
	if not mark.is_empty() and int(mark.type) == Landmark.POND:
		result.append(Vector4(mark.center.x, 0.0, mark.center.z, 0.0))
	if layout != null:
		for site in _chunk_eruptions.get(key, []):
			if is_open(Vector3(site.x, 0.0, site.z), 1.0):
				result.append(site)
		return result
	var samples := trail_samples(key)
	for index in range(2, samples.size(), 4):
		var point := Vector3(samples[index].x, 0.0, samples[index].z)
		# Rare trail points under an arch foot or stone are skipped.
		if is_open(point, 1.0):
			result.append(Vector4(point.x, 0.0, point.z, 1.0))
	return result

# True if the point lies within `margin` of a wall (seeded map).
# True for a stone that belongs to a tall landmark of the exploration map.
func _beacon_stone(stone: Vector4) -> bool:
	if layout == null or layout.get("beacons") == null:
		return false
	for mark in layout.beacons:
		var center: Vector3 = mark.center
		if Vector2(stone.x - center.x, stone.z - center.z).length() <= float(mark.radius) + 0.5:
			return true
	return false

func _in_wall(world: Vector3, margin: float) -> bool:
	return layout != null and layout.sample(world.x, world.z) < margin


func _boulder(chunk: Node3D, center: Vector3, radius: float) -> void:
	var location := center - chunk.position
	var roll := _hash(roundi(center.x * 10.0), roundi(center.z * 10.0), 7)
	var stone_scale := radius / OBSTACLE_RADIUS
	var plinth := _part(chunk, "Stone footprint", plinth_mesh, plinth_material, location + Vector3(0, 0.02, 0))
	plinth.scale = Vector3(stone_scale, 1.0, stone_scale)
	var size := (0.92 + float(roll % 9) * 0.02) * stone_scale
	var yaw := float((roll >> 4) % 628) * 0.01
	_prop(chunk, "Low stone", rock_mesh, rock_base, rock_material, location, Vector3(3.9, 3.2, 3.6) * size, yaw)
	# Stage 18c follow-up: no loose leaves around the stone (they stuck out past
	# the collision circle).


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
	material.shader = PROP_SHADER
	fade_materials.append(material)
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
	return Vector3((region.x + 0.5) * REGION * CELL + _region_origin, 0.0, (region.y + 0.5) * REGION * CELL + _region_origin)

## Landmark types (Landmark enum) standing in a region, in chunk order.
func region_landmarks(region: Vector2i) -> Array:
	var result := []
	var first := Vector2i((region.x - _region_lo) * REGION + _chunk_lo, (region.y - _region_lo) * REGION + _chunk_lo)
	for x in range(first.x, first.x + REGION):
		for z in range(first.y, first.y + REGION):
			var mark := landmark(Vector2i(x, z))
			if not mark.is_empty():
				result.append(int(mark.type))
	return result

## Region name in the words of the active biome ("Moosgrund"). All map regions
## (16 for solo) get unique names, fixed per seed and biome; a region key outside
## the map answers with the name of the nearest map region.
func region_name(region: Vector2i) -> String:
	if not _map_names.has(biome_id):
		_map_names[biome_id] = REGION_NAMES.map_names(world_seed, map_regions_list(), biome_id)
	var names: Dictionary = _map_names[biome_id]
	var inside := Vector2i(clampi(region.x, _region_lo, _region_lo + map_regions - 1), clampi(region.y, _region_lo, _region_lo + map_regions - 1))
	return String(names.get(inside, ""))

## Every region key of the map, row by row (z, then x).
func map_regions_list() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for z in range(_region_lo, _region_lo + map_regions):
		for x in range(_region_lo, _region_lo + map_regions):
			result.append(Vector2i(x, z))
	return result

## World rectangle (x, z) of a region.
func region_rect(region: Vector2i) -> Rect2:
	var span := REGION * CELL
	return Rect2(region.x * span + _region_origin, region.y * span + _region_origin, span, span)

## Everything the minimap needs to draw the whole map at once:
##   size: map side in metres; bounds / playable: Rect2 in world x, z;
##   regions_per_side, region_size, cell; chunk_range: Rect2i of map chunks;
##   regions: [{key, name, phrase, center: Vector2, rect: Rect2}];
##   border: {outer: PackedVector2Array (end of the fog skirt's inner edge),
##            inner: PackedVector2Array (closed, organic front line of the wall),
##            segments: [{kind: "thicket"/"cliff"/"water" (Glutsumpf "char"/
##            "basalt"/"lava"), side: 0..3, from: Vector2, to: Vector2}]};
##   spawn_points: Array[Vector3] for the configured player count;
##   clearings: [{center: Vector2, radius, types: Array[String]}] and
##   paths: [{points: PackedVector2Array, kind}] (seeded maps, stage 18b);
##   seed, biome.
func map_overview() -> Dictionary:
	var regions := []
	for region in map_regions_list():
		var center := region_center(region)
		regions.append({"key": region, "name": region_name(region), "phrase": region_phrase(region), "center": Vector2(center.x, center.z), "rect": region_rect(region)})
	var outer_rect := _bounds.grow(BORDER_CHUNKS * CELL)
	var outer := PackedVector2Array([outer_rect.position, Vector2(outer_rect.end.x, outer_rect.position.y), outer_rect.end, Vector2(outer_rect.position.x, outer_rect.end.y)])
	return {
		"size": _bounds.size.x,
		"bounds": _bounds,
		"playable": _playable,
		"regions_per_side": map_regions,
		"region_size": REGION * CELL,
		"cell": CELL,
		"chunk_range": Rect2i(_chunk_lo, _chunk_lo, _chunk_hi - _chunk_lo + 1, _chunk_hi - _chunk_lo + 1),
		"regions": regions,
		"border": {"outer": outer, "inner": border.front_line(4.0), "segments": border.segments()},
		"spawn_points": spawn_points(player_count),
		"clearings": _overview_clearings(),
		"paths": _overview_paths(),
		"seed": world_seed,
		"biome": biome_id,
	}

func _overview_clearings() -> Array:
	var result := []
	for node in clearings():
		result.append({"center": Vector2(node.center.x, node.center.z), "radius": node.radius, "types": node.types, "id": node.id})
	return result

func _overview_paths() -> Array:
	var result := []
	for path in paths():
		var flat := PackedVector2Array()
		for point in path.points:
			flat.append(Vector2(point.x, point.z))
		result.append({"points": flat, "kind": path.kind})
	return result

# --- Discovery (stage 18c) ---------------------------------------------------------

## Marks every place (POI) within `radius` of `point` as discovered; returns
## how many were new. Runs with the exploration fog (radius EXPLORE_RADIUS).
func discover_around(point: Vector3, radius: float) -> int:
	if layout == null or _discovered.size() != layout.nodes.size():
		return 0
	var found := 0
	for index in layout.nodes.size():
		if _discovered[index] != 0:
			continue
		var node: Dictionary = layout.nodes[index]
		var center: Vector3 = node.center
		if Vector2(center.x - point.x, center.z - point.z).length() <= radius + float(node.radius) * 0.5:
			_discovered[index] = 1
			found += 1
	if found > 0:
		explore_version += 1
	return found

## True if the place at `point` was discovered (a POI within 4 m of it), else
## whether its fog cell was seen. The classic map knows only the fog.
func is_discovered(point: Vector3) -> bool:
	if layout != null and _discovered.size() == layout.nodes.size():
		for index in layout.nodes.size():
			var node: Dictionary = layout.nodes[index]
			var center: Vector3 = node.center
			if Vector2(center.x - point.x, center.z - point.z).length() <= maxf(4.0, float(node.radius) * 0.6):
				return _discovered[index] != 0
	return is_explored(point)

## Slots of `type` in places the swarm has discovered.
func discovered(type: String) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if layout == null:
		return result
	for index in layout.nodes.size():
		if index < _discovered.size() and _discovered[index] != 0 and layout.nodes[index].slots.has(type):
			for spot in layout.nodes[index].slots[type]:
				result.append(spot)
	return result

# --- Exploration fog (stage 18) ----------------------------------------------------

func _reset_exploration() -> void:
	_fog_size = Vector2i(ceili(_bounds.size.x / FOG_CELL), ceili(_bounds.size.y / FOG_CELL))
	_explored = PackedByteArray()
	_explored.resize(_fog_size.x * _fog_size.y)
	_explored_regions.clear()
	_explore_at = Vector3.INF
	explore_version += 1

# Reveals the fog cells within EXPLORE_RADIUS; runs after 2 m of movement.
func _explore(position: Vector3) -> void:
	if _explored.is_empty() or (_explore_at.is_finite() and position.distance_squared_to(_explore_at) < 4.0):
		return
	_explore_at = position
	explore(position, EXPLORE_RADIUS)

## Reveals every fog cell whose nearest point is within `radius` of `point`
## and marks the region under the point as visited.
func explore(point: Vector3, radius: float) -> void:
	var local := Vector2(point.x - _bounds.position.x, point.z - _bounds.position.y)
	var low := Vector2i(maxi(0, floori((local.x - radius) / FOG_CELL)), maxi(0, floori((local.y - radius) / FOG_CELL)))
	var high := Vector2i(mini(_fog_size.x - 1, floori((local.x + radius) / FOG_CELL)), mini(_fog_size.y - 1, floori((local.y + radius) / FOG_CELL)))
	var changed := false
	for z in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var index := z * _fog_size.x + x
			if _explored[index] != 0:
				continue
			var near := Vector2(clampf(local.x, x * FOG_CELL, (x + 1) * FOG_CELL), clampf(local.y, z * FOG_CELL, (z + 1) * FOG_CELL))
			if near.distance_squared_to(local) <= radius * radius:
				_explored[index] = 1
				changed = true
	if discover_around(point, radius) > 0:
		changed = true
	if is_inside(point):
		var region := region_at(point)
		if not _explored_regions.has(region):
			_explored_regions[region] = true
			changed = true
	if changed:
		explore_version += 1

## Fog grid size in cells (FOG_CELL metres each, starting at bounds().position).
func fog_size() -> Vector2i:
	return _fog_size

## Revealed fog cells, row-major (index = z * fog_size().x + x), 1 = visited.
func explored_cells() -> PackedByteArray:
	return _explored

## True if the fog cell under a world point was visited.
func is_explored(point: Vector3) -> bool:
	var x := floori((point.x - _bounds.position.x) / FOG_CELL)
	var z := floori((point.z - _bounds.position.y) / FOG_CELL)
	if x < 0 or z < 0 or x >= _fog_size.x or z >= _fog_size.y:
		return false
	return _explored[z * _fog_size.x + x] != 0

## Region keys the swarm has stood in on this map.
func explored_regions() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for region in _explored_regions.keys():
		result.append(region)
	return result

## Share of revealed fog cells (0..1).
func exploration_share() -> float:
	if _explored.is_empty():
		return 0.0
	return float(_explored.count(1)) / float(_explored.size())

## Landmark phrase of a region in the active biome ("am Wurzelbogen") or "".
func region_phrase(region: Vector2i) -> String:
	return REGION_NAMES.phrase_for(world_seed, region, biome_id, region_landmarks(region))

## Soft ground tint shift at a world point as Vector2(hue, value) - the same
## blend the seeded ground mesh uses; (0, 0) on the classic map.
func map_tint(x: float, z: float) -> Vector2:
	if world_seed == 0:
		return Vector2.ZERO
	var fx := (x - _region_origin) / (REGION * CELL) - 0.5
	var fz := (z - _region_origin) / (REGION * CELL) - 0.5
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
##           this and the neighbouring chunks when their shapes reach in;
##   walls:  seeded map only - wall distance (m, + open) at WALL_SAMPLES^2
##           square centres of the chunk, row by row (empty on seed 0).
## Depends on the active biome only for the classic map's pool frequency.
func map_features(key: Vector2i) -> Dictionary:
	var margin := TRAIL_EDGE_WIDTH + 1.0
	var area := Rect2(key.x * CELL - margin, key.y * CELL - margin, CELL + 2.0 * margin, CELL + 2.0 * margin)
	var origin := Vector3(key.x * CELL, 0.0, key.y * CELL)
	var trails: Array[Vector4] = []
	var stones: Array[Vector4] = []
	var pools: Array[Vector4] = []
	var walls := PackedFloat32Array()
	if not in_map(key):
		var none: Array[Dictionary] = []
		return {"trails": trails, "stones": stones, "pools": pools, "marks": none, "walls": walls}
	if layout == null:
		for step in range(-6, int(CELL) + 7):
			var z := float(step)
			trails.append(Vector4(origin.x + _trail_center(key, z), 0.0, origin.z + z, TRAIL_HALF_WIDTH))
		for center in obstacle_centers(key):
			stones.append(Vector4(center.x, 0.0, center.z, OBSTACLE_RADIUS))
		if _hash(key.x, key.y, 13) % int(biome.pond_one_in) == 0 and not near_landmark(origin + Vector3(4, 0, 22), 3.0):
			if is_inside(origin + Vector3(4, 0, 22), 3.0):
				pools.append(Vector4(origin.x + 4.0, origin.z + 22.0, 1.1 * 1.8, 1.1 * 1.1))
	else:
		for x in range(key.x - 1, key.x + 2):
			for z in range(key.y - 1, key.y + 2):
				for sample in _chunk_trails.get(Vector2i(x, z), []):
					if area.has_point(Vector2(sample.x, sample.z)):
						trails.append(sample)
		for stone in _chunk_stones.get(key, []):
			stones.append(stone)
		# Wall distance at WALL_SAMPLES x WALL_SAMPLES points (centres of equal
		# squares of the chunk, row by row) for the dark walls of the minimap.
		for gz in WALL_SAMPLES:
			for gx in WALL_SAMPLES:
				walls.append(layout.sample(origin.x + (float(gx) + 0.5) * CELL / WALL_SAMPLES, origin.z + (float(gz) + 0.5) * CELL / WALL_SAMPLES))
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
	return {"trails": trails, "stones": stones, "pools": pools, "marks": marks, "walls": walls}
