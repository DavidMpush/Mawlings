extends RefCounted

# Stage 18c: the exploration map (replaces the clearing/corridor graph of
# map_layout.gd as the standard for seeded maps; same data interface, so
# arena.gd, flow_field.gd, the wall builder and the minimap keep working).
#
# Every region rolls a landscape - open meadow, light forest (tree groups with
# gaps), dense thicket, ruin field (broken walls, pillars), rock ridge, swamp
# ponds, rock labyrinth - blended organically (warped Voronoi between region
# seeds). Terrain is a blocked mask on the NAV grid (~25-35 % blocked); choke
# points arise between thicket, rock and water, open ground stays connected
# (small pockets filled, larger ones joined by a carved gap). POIs are scattered
# seeded (Poisson disc, a small clearing carved around each), loose trampled
# trails wind between some of them (A* over open ground, visual only), amber
# nodes (loot) are strewn everywhere, a few tall landmarks lure from afar.
#
#   nodes      POI sites [{center, radius (cleared), types, slots, amp, phase, edges}]
#   edges      trails [{a, b, kind "trail", points, half, length}]
#   sdf        signed wall distance (m, + open) on the NAV grid, map edge included
#   kind       wall character per cell (Wall enum of arena_border.gd + RUIN)
#   loot_points  Vector4(x, 0, z, tier 0..2) amber nodes
#   beacons    tall landmarks [{kind, center, radius}]

const NAV := 2.0
const STYLE := "explore"
# Sand of the loose trails: narrow, never a rail.
const SAND_SHARE := 0.5
const SAND_MIN := 1.1
enum Land { MEADOW, FOREST, THICKET, RUINS, RIDGE, SWAMP, LABYRINTH }
const LAND_NAMES := ["meadow", "forest", "thicket", "ruins", "ridge", "swamp", "labyrinth"]
# Region weights (meadow and forest most common, labyrinth rare).
const LAND_WEIGHTS := [18, 22, 14, 12, 10, 12, 8]
# Wall characters (arena_border.gd Wall enum; RUIN is new).
const KIND_THICKET := 0
const KIND_CLIFF := 1
const KIND_ROOTS := 2
const KIND_WATER := 3
const KIND_RUIN := 4
const KIND_TREE := 5
const BLOCKED_SHARE := Vector2(0.25, 0.35)
const EDGE_KEEP := 10.0
# POI types: [count (solo 4 x 4, scaled by area), clear radius, min spacing].
const POI := {
	"cocoon": [12, 4.0, 20.0], "cocoon_gold": [3, 5.0, 40.0], "shrine": [5, 6.0, 45.0],
	"nest": [8, 7.0, 30.0], "totem": [5, 5.0, 40.0], "grove": [7, 8.0, 30.0],
	"elite": [3, 9.0, 60.0],
}
const LOOT_COUNT := Vector2i(60, 90)

var rng := RandomNumberGenerator.new()
# Read by arena.gd (sand band of the trails; null on the 18b layout).
var sand_share := SAND_SHARE
var sand_min := SAND_MIN
var style := STYLE
var playable := Rect2()
var bounds := Rect2()
var center := Vector3.ZERO
var regions := 4
var grid := 0
var grid_origin := Vector2.ZERO
var sdf := PackedFloat32Array()
var blocked := PackedByteArray()
var kind := PackedByteArray()
var land := PackedByteArray()
var nodes: Array[Dictionary] = []
var edges: Array[Dictionary] = []
var hub := 0
var boss := -1
var maw := -1
var landmarks: Array[Dictionary] = []
var stones: Array[Vector4] = []
var eruption_points: Array[Vector4] = []
var loot_points: Array[Vector4] = []
var beacons: Array[Dictionary] = []
var region_lands: Dictionary = {}
var attempts := 1
var build_msec := 0.0
var _region_seeds: Dictionary = {}
var _noise_a := FastNoiseLite.new()
var _noise_b := FastNoiseLite.new()
var _warp := FastNoiseLite.new()
var _cells := FastNoiseLite.new()
var _filled := 0
var _joined := 0


func _init(seed_value: int, playable_rect: Rect2, bounds_rect: Rect2, map_regions: int, starts: Array[Vector3], arrivals: Array[Vector3]) -> void:
	var started := Time.get_ticks_usec()
	playable = playable_rect
	bounds = bounds_rect
	regions = map_regions
	center = Vector3(playable.get_center().x, 0.0, playable.get_center().y)
	rng.seed = hash("mawlings-explore:%d:%d" % [seed_value, regions])
	for noise in [_noise_a, _noise_b, _warp, _cells]:
		noise.seed = rng.randi()
	_noise_a.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_a.frequency = 1.0 / 30.0
	_noise_a.fractal_octaves = 2
	_noise_b.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_b.frequency = 1.0 / 13.0
	_noise_b.fractal_octaves = 1
	_warp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_warp.frequency = 1.0 / 60.0
	_warp.fractal_octaves = 1
	_cells.noise_type = FastNoiseLite.TYPE_CELLULAR
	_cells.frequency = 1.0 / 11.0
	_cells.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	_cells.cellular_jitter = 0.9
	_cells.fractal_type = FastNoiseLite.FRACTAL_NONE
	grid = ceili(bounds.size.x / NAV)
	grid_origin = bounds.position
	var start := _pick_start(starts)
	_roll_regions(start)
	_build_mask()
	_place_pois(start, starts, arrivals)
	_carve_pois()
	_join_open()
	_bake_sdf()
	_trails()
	_place_loot()
	_eruptions()
	build_msec = float(Time.get_ticks_usec() - started) / 1000.0


# ------------------------------------------------------------------ helpers

func _cell_center(ix: int, iz: int) -> Vector2:
	return Vector2(grid_origin.x + (float(ix) + 0.5) * NAV, grid_origin.y + (float(iz) + 0.5) * NAV)


func _cell_of(point: Vector3) -> Vector2i:
	return Vector2i(clampi(floori((point.x - grid_origin.x) / NAV), 0, grid - 1), clampi(floori((point.z - grid_origin.y) / NAV), 0, grid - 1))


func _region_size() -> float:
	return bounds.size.x / float(regions)


func _region_of(x: float, z: float) -> Vector2i:
	var size := _region_size()
	return Vector2i(clampi(floori((x - bounds.position.x) / size), 0, regions - 1), clampi(floori((z - bounds.position.y) / size), 0, regions - 1))


func _inner(margin: float) -> Rect2:
	return playable.grow(-margin)


func _random_point(margin: float) -> Vector3:
	var inner := _inner(margin)
	return Vector3(rng.randf_range(inner.position.x, inner.end.x), 0.0, rng.randf_range(inner.position.y, inner.end.y))


# Solo: a random open spot away from the edge; multiplayer keeps the given ring.
func _pick_start(starts: Array[Vector3]) -> Vector3:
	if starts.size() > 1:
		return starts[0]
	var inner := _inner(playable.size.x * 0.22)
	return Vector3(rng.randf_range(inner.position.x, inner.end.x), 0.0, rng.randf_range(inner.position.y, inner.end.y))


# ------------------------------------------------------------------ landscape

func _roll_regions(start: Vector3) -> void:
	var total := 0
	for weight in LAND_WEIGHTS:
		total += weight
	var size := _region_size()
	var start_region := _region_of(start.x, start.z)
	for rz in regions:
		for rx in regions:
			var key := Vector2i(rx, rz)
			var roll := rng.randi() % total
			var pick := 0
			for index in LAND_WEIGHTS.size():
				roll -= LAND_WEIGHTS[index]
				if roll < 0:
					pick = index
					break
			# The start region is walkable at first glance.
			if key == start_region:
				pick = Land.MEADOW if rng.randf() < 0.6 else Land.FOREST
			region_lands[key] = pick
			_region_seeds[key] = Vector2(bounds.position.x + (float(rx) + rng.randf_range(0.25, 0.75)) * size, bounds.position.y + (float(rz) + rng.randf_range(0.25, 0.75)) * size)
	# No two neighbouring regions of the same rare, heavy kind.
	for rz in regions:
		for rx in regions:
			var here: int = region_lands[Vector2i(rx, rz)]
			if here in [Land.THICKET, Land.LABYRINTH, Land.SWAMP]:
				for other in [Vector2i(rx - 1, rz), Vector2i(rx, rz - 1)]:
					if region_lands.has(other) and region_lands[other] == here:
						region_lands[Vector2i(rx, rz)] = Land.FOREST if rng.randf() < 0.5 else Land.MEADOW


# Landscape of a point: nearest region seed after a domain warp (organic borders).
func _land_at(x: float, z: float) -> int:
	var wx := x + _warp.get_noise_2d(x, z) * 26.0
	var wz := z + _warp.get_noise_2d(z + 500.0, x - 300.0) * 26.0
	var home := _region_of(wx, wz)
	var best := INF
	var pick := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := home + Vector2i(dx, dz)
			if not _region_seeds.has(key):
				continue
			var seed_point: Vector2 = _region_seeds[key]
			var d := Vector2(wx - seed_point.x, wz - seed_point.y).length_squared()
			if d < best:
				best = d
				pick = region_lands[key]
	return pick


# Density of a landscape at a point (> 0 = blocked) and its wall character.
func _terrain(type: int, x: float, z: float) -> Vector2:
	var a := _noise_a.get_noise_2d(x, z)
	var b := _noise_b.get_noise_2d(x, z)
	match type:
		Land.MEADOW:
			# Rare rock clusters on open grass.
			return Vector2(b * 0.8 + a * 0.5 - 0.72, KIND_CLIFF)
		Land.FOREST:
			# Tree groups: blobs around cellular feature points, gaps between.
			var cell := _cells.get_noise_2d(x, z)
			return Vector2(0.18 - (cell + 1.0) * 0.5 + a * 0.12, KIND_TREE)
		Land.THICKET:
			# Mostly blocked mass with winding gaps.
			return Vector2(a * 0.9 + b * 0.35 + 0.12, KIND_THICKET if b > -0.2 else KIND_ROOTS)
		Land.RUINS:
			# Broken walls on a skewed 12 m grid plus pillars.
			var angle := 0.35 + a * 0.08
			var u := x * cos(angle) + z * sin(angle)
			var v := -x * sin(angle) + z * cos(angle)
			var fu := absf(fposmod(u / 13.0, 1.0) - 0.5)
			var fv := absf(fposmod(v / 13.0, 1.0) - 0.5)
			var wall := (0.08 - minf(fu, fv)) * 6.0
			var broken := b * 0.9
			var pillar := 0.12 - Vector2(fu, fv).length() * 2.2
			return Vector2(maxf(minf(wall, broken + 0.05), pillar) - 0.02, KIND_RUIN)
		Land.RIDGE:
			# Winding rock ridges along a noise contour with rare breaches.
			var ridge := 0.11 - absf(a)
			var breach := b - 0.55
			return Vector2(ridge * 4.0 - maxf(0.0, breach) * 3.0 + (b * 0.5 - 0.62), KIND_CLIFF)
		Land.SWAMP:
			# Ponds (water walls) with reedy rims.
			return Vector2(a * 0.75 + b * 0.25 - 0.1, KIND_WATER)
		_:
			# Labyrinth: rock seams along two noise contours.
			var seam := 0.1 - minf(absf(a * 1.3), absf(b))
			return Vector2(seam * 5.0, KIND_CLIFF)


func _build_mask() -> void:
	var count := grid * grid
	var density := PackedFloat32Array()
	density.resize(count)
	blocked.resize(count)
	kind.resize(count)
	land.resize(count)
	for iz in grid:
		for ix in grid:
			var p := _cell_center(ix, iz)
			var type := _land_at(p.x, p.y)
			var value := _terrain(type, p.x, p.y)
			var index := iz * grid + ix
			density[index] = value.x
			kind[index] = int(value.y)
			land[index] = type
	# One global threshold keeps the blocked share in 25-35 %.
	var inside := PackedFloat32Array()
	for iz in range(0, grid, 2):
		for ix in range(0, grid, 2):
			var p := _cell_center(ix, iz)
			if playable.grow(-EDGE_KEEP).has_point(p):
				inside.append(density[iz * grid + ix])
	inside.sort()
	var natural := 0
	for value in inside:
		if value > 0.0:
			natural += 1
	var share := clampf(float(natural) / float(maxi(1, inside.size())), BLOCKED_SHARE.x, BLOCKED_SHARE.y)
	var threshold: float = inside[clampi(roundi((1.0 - share) * float(inside.size())), 0, inside.size() - 1)]
	for iz in grid:
		for ix in grid:
			var p := _cell_center(ix, iz)
			var index := iz * grid + ix
			var edge := minf(minf(p.x - playable.position.x, playable.end.x - p.x), minf(p.y - playable.position.y, playable.end.y - p.y))
			if edge < 1.0:
				blocked[index] = 1
			elif edge < EDGE_KEEP:
				blocked[index] = 0
			else:
				blocked[index] = 1 if density[index] > threshold else 0


# ------------------------------------------------------------------ POIs

func _poi_count(base: int) -> int:
	return maxi(1, roundi(float(base) * float(regions * regions) / 16.0))


func _free(point: Vector3, radius: float, spacing: float) -> bool:
	if not _inner(radius + 12.0).has_point(Vector2(point.x, point.z)):
		return false
	for node in nodes:
		var other: Vector3 = node.center
		if Vector2(point.x - other.x, point.z - other.z).length() < radius + float(node.radius) + spacing * 0.5:
			return false
	return true


# Open share around a point (0..1) - POIs prefer places that are already open.
func _openness(point: Vector3, radius: float) -> float:
	var open := 0
	var total := 0
	for step in 12:
		var angle := TAU * float(step) / 12.0
		for reach in [0.0, radius * 0.5, radius]:
			var cell := _cell_of(point + Vector3(cos(angle), 0.0, sin(angle)) * reach)
			total += 1
			if blocked[cell.y * grid + cell.x] == 0:
				open += 1
	return float(open) / float(total)


func _add_node(point: Vector3, radius: float, type: String) -> int:
	var node := {
		"center": Vector3(point.x, 0.0, point.z), "radius": radius, "types": [type],
		"amp": Vector3(rng.randf_range(0.04, 0.09), rng.randf_range(0.03, 0.06), rng.randf_range(0.02, 0.05)),
		"phase": Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU),
		"slots": {type: [Vector3(point.x, 0.0, point.z)]}, "edges": [],
	}
	nodes.append(node)
	return nodes.size() - 1


# Best of `tries` random candidates: free, as open as possible, scored by `score`.
func _scatter(radius: float, spacing: float, tries: int, score: Callable) -> Vector3:
	var best := Vector3.INF
	var best_score := -INF
	for attempt in tries:
		var point := _random_point(radius + 14.0)
		if not _free(point, radius, spacing):
			continue
		var value: float = score.call(point) + _openness(point, radius) * 2.0 + rng.randf() * 0.5
		if value > best_score:
			best_score = value
			best = point
	return best


func _danger(point: Vector3) -> float:
	var cell := _cell_of(point)
	var type: int = land[cell.y * grid + cell.x]
	return 1.0 if type in [Land.THICKET, Land.LABYRINTH, Land.SWAMP, Land.RUINS] else 0.0


func _place_pois(start: Vector3, starts: Array[Vector3], arrivals: Array[Vector3]) -> void:
	nodes.clear()
	var solo := starts.size() <= 1
	if solo:
		hub = _add_node(start, 14.0, "start")
	else:
		for point in starts:
			var index := _add_node(point, 14.0, "start")
			if index == 0:
				hub = index
	for point in arrivals:
		_add_node(point, 12.0, "arrival")
	var start_point: Vector3 = nodes[hub].center
	var span := playable.size.x
	# Boss arena: a wide open area somewhere far enough from the start.
	var boss_point := _scatter(24.0, 30.0, 60, func(p: Vector3) -> float:
		return minf(p.distance_to(start_point), span * 0.5) / span * 4.0)
	if boss_point.is_finite():
		boss = _add_node(boss_point, 24.0, "boss")
	# Migrationsschlund: far from the boss arena.
	var maw_point := _scatter(10.0, 30.0, 60, func(p: Vector3) -> float:
		return (p.distance_to(nodes[boss].center) if boss >= 0 else p.distance_to(start_point)) / span * 4.0)
	if maw_point.is_finite():
		maw = _add_node(maw_point, 10.0, "maw")
	for type in ["elite", "shrine", "cocoon_gold", "nest", "totem", "grove", "cocoon"]:
		var spec: Array = POI[type]
		for index in _poi_count(int(spec[0])):
			var golden: bool = type == "cocoon_gold" or type == "elite"
			var point := _scatter(float(spec[1]), float(spec[2]), 30, func(p: Vector3) -> float:
				var away := minf(p.distance_to(start_point), span * 0.6) / span
				return (_danger(p) * 2.0 + away * 2.0) if golden else (-0.5 if p.distance_to(start_point) < 20.0 else 0.0))
			if point.is_finite():
				_add_node(point, float(spec[1]), type)
	# Tall landmarks: 4 (solo), spread far apart, never on a POI.
	var lure_kinds := ["giant_tree", "bone_pillar", "mushroom_tower", "stone_needle"]
	lure_kinds.shuffle()
	for index in _poi_count(4):
		var point := _scatter(6.0, 70.0, 40, func(p: Vector3) -> float:
			var near := INF
			for mark in beacons:
				near = minf(near, p.distance_to(mark.center))
			return minf(near, span) / span * 3.0)
		if point.is_finite():
			var node := _add_node(point, 6.0, "landmark")
			beacons.append({"kind": lure_kinds[index % lure_kinds.size()], "center": point, "radius": 2.6, "node": node})
			stones.append(Vector4(point.x, 0.0, point.z, 2.6))


# Clears an organic disc around every POI.
func _carve_pois() -> void:
	for node in nodes:
		var c: Vector3 = node.center
		var reach := float(node.radius) * 1.2 + 2.0
		var lo := _cell_of(c - Vector3(reach, 0.0, reach))
		var hi := _cell_of(c + Vector3(reach, 0.0, reach))
		for iz in range(lo.y, hi.y + 1):
			for ix in range(lo.x, hi.x + 1):
				var p := _cell_center(ix, iz)
				if _clearing_value(node, p.x, p.y) >= -0.5 and playable.grow(-1.0).has_point(p):
					blocked[iz * grid + ix] = 0


# Every open pocket joins the main ground: small ones are filled, bigger ones
# get a carved gap to the nearest main cell (so nothing is ever cut off).
func _join_open() -> void:
	var count := grid * grid
	var component := PackedInt32Array()
	component.resize(count)
	component.fill(-1)
	var start_cell := _cell_of(nodes[hub].center)
	var sizes: Array[int] = []
	var cells_of: Array = []
	var seeds: Array[int] = [start_cell.y * grid + start_cell.x]
	for index in count:
		if blocked[index] == 0:
			seeds.append(index)
	for seed_cell in seeds:
		if blocked[seed_cell] != 0 or component[seed_cell] >= 0:
			continue
		var id := sizes.size()
		var members := PackedInt32Array([seed_cell])
		component[seed_cell] = id
		var head := 0
		while head < members.size():
			var here := members[head]
			head += 1
			var x := here % grid
			var z := here / grid
			for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + offset.x
				var nz: int = z + offset.y
				if nx < 0 or nz < 0 or nx >= grid or nz >= grid:
					continue
				var next := nz * grid + nx
				if blocked[next] == 0 and component[next] < 0:
					component[next] = id
					members.append(next)
		sizes.append(members.size())
		cells_of.append(members)
	for id in range(1, sizes.size()):
		var members: PackedInt32Array = cells_of[id]
		if sizes[id] < 40:
			for cell in members:
				blocked[cell] = 1
			_filled += 1
			continue
		_bridge(members, component)
		_joined += 1


# Multi-source BFS through the wall from a pocket to the main ground; the path
# found is carved 3 cells wide.
func _bridge(members: PackedInt32Array, component: PackedInt32Array) -> void:
	var count := grid * grid
	var parent := PackedInt32Array()
	parent.resize(count)
	parent.fill(-2)
	var queue := PackedInt32Array()
	for cell in members:
		parent[cell] = -1
		queue.append(cell)
	var head := 0
	var goal := -1
	while head < queue.size() and goal < 0:
		var here := queue[head]
		head += 1
		var x := here % grid
		var z := here / grid
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + offset.x
			var nz: int = z + offset.y
			if nx < 2 or nz < 2 or nx >= grid - 2 or nz >= grid - 2:
				continue
			var next := nz * grid + nx
			if parent[next] != -2:
				continue
			parent[next] = here
			if blocked[next] == 0 and component[next] == 0:
				goal = next
				break
			queue.append(next)
	var cell := goal
	while cell >= 0 and parent[cell] != -1:
		var x := cell % grid
		var z := cell / grid
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var nx := clampi(x + dx, 1, grid - 2)
				var nz := clampi(z + dz, 1, grid - 2)
				if playable.grow(-1.0).has_point(_cell_center(nx, nz)):
					blocked[nz * grid + nx] = 0
					component[nz * grid + nx] = 0
		cell = parent[cell]
	for member in members:
		component[member] = 0


# ------------------------------------------------------------------ distance field

# Two-pass chamfer distance (cell units) to the nearest cell with mask == target.
func _chamfer(target: int) -> PackedFloat32Array:
	var count := grid * grid
	var dist := PackedFloat32Array()
	dist.resize(count)
	var far := float(grid * 2)
	for index in count:
		dist[index] = 0.0 if blocked[index] == target else far
	var diag := 1.4142
	for z in grid:
		for x in grid:
			var i := z * grid + x
			var d := dist[i]
			if d == 0.0:
				continue
			if x > 0:
				d = minf(d, dist[i - 1] + 1.0)
			if z > 0:
				d = minf(d, dist[i - grid] + 1.0)
				if x > 0:
					d = minf(d, dist[i - grid - 1] + diag)
				if x < grid - 1:
					d = minf(d, dist[i - grid + 1] + diag)
			dist[i] = d
	for z in range(grid - 1, -1, -1):
		for x in range(grid - 1, -1, -1):
			var i := z * grid + x
			var d := dist[i]
			if d == 0.0:
				continue
			if x < grid - 1:
				d = minf(d, dist[i + 1] + 1.0)
			if z < grid - 1:
				d = minf(d, dist[i + grid] + 1.0)
				if x < grid - 1:
					d = minf(d, dist[i + grid + 1] + diag)
				if x > 0:
					d = minf(d, dist[i + grid - 1] + diag)
			dist[i] = d
	return dist


func _bake_sdf() -> void:
	var to_wall := _chamfer(1)
	var to_open := _chamfer(0)
	var count := grid * grid
	var values := PackedFloat32Array()
	values.resize(count)
	for iz in grid:
		var z := grid_origin.y + (float(iz) + 0.5) * NAV
		var dz := minf(z - playable.position.y, playable.end.y - z)
		for ix in grid:
			var index := iz * grid + ix
			var value := 0.0
			if blocked[index] == 0:
				value = (to_wall[index] - 0.5) * NAV
			else:
				value = -(to_open[index] - 0.5) * NAV
			var x := grid_origin.x + (float(ix) + 0.5) * NAV
			var inside := minf(minf(x - playable.position.x, playable.end.x - x), dz)
			values[index] = minf(value, inside)
	sdf = values


# ------------------------------------------------------------------ trails

# Loose trampled trails: from the start to its three nearest POIs and between a
# few neighbouring POIs, found by A* over open ground (they wind with the land).
func _trails() -> void:
	edges.clear()
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, grid, grid)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for index in grid * grid:
		if sdf[index] < 1.5:
			astar.set_point_solid(Vector2i(index % grid, index / grid), true)
	var pairs: Array = []
	var start_point: Vector3 = nodes[hub].center
	var order: Array = []
	for index in nodes.size():
		if index != hub and nodes[index].types[0] != "landmark":
			order.append([start_point.distance_to(nodes[index].center), index])
	order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for entry in order.slice(0, 3):
		pairs.append([hub, entry[1]])
	# A handful of links between neighbouring POIs, picked at random.
	var wanted := _poi_count(7)
	for attempt in 40:
		if pairs.size() >= wanted + 3:
			break
		var a := rng.randi() % nodes.size()
		var best := -1
		var best_d := INF
		for b in nodes.size():
			if b == a or nodes[b].types[0] == "landmark":
				continue
			var d: float = (nodes[a].center as Vector3).distance_to(nodes[b].center)
			if d > 25.0 and d < best_d and not _paired(pairs, a, b):
				best_d = d
				best = b
		if best >= 0 and best_d < playable.size.x * 0.4:
			pairs.append([a, best])
	for pair in pairs:
		var a_cell := _cell_of(nodes[pair[0]].center)
		var b_cell := _cell_of(nodes[pair[1]].center)
		if astar.is_point_solid(a_cell) or astar.is_point_solid(b_cell):
			continue
		var path := astar.get_id_path(a_cell, b_cell)
		if path.size() < 6:
			continue
		var raw := PackedVector3Array()
		for step in range(0, path.size(), 3):
			var c := _cell_center(path[step].x, path[step].y)
			raw.append(Vector3(c.x, 0.0, c.y))
		var last := _cell_center(path[path.size() - 1].x, path[path.size() - 1].y)
		raw.append(Vector3(last.x, 0.0, last.y))
		var points := _smooth(_smooth(raw))
		var half := PackedFloat32Array()
		var wobble := rng.randf() * TAU
		for index in points.size():
			half.append(2.2 + 0.5 * sin(float(index) * 0.7 + wobble))
		var total := 0.0
		for index in points.size() - 1:
			total += points[index].distance_to(points[index + 1])
		edges.append({"a": pair[0], "b": pair[1], "kind": "trail", "points": points, "half": half, "length": total, "mst": false})
		(nodes[pair[0]].edges as Array).append(edges.size() - 1)
		(nodes[pair[1]].edges as Array).append(edges.size() - 1)


func _paired(pairs: Array, a: int, b: int) -> bool:
	for pair in pairs:
		if (pair[0] == a and pair[1] == b) or (pair[0] == b and pair[1] == a):
			return true
	return false


# Chaikin corner cutting (keeps the end points).
static func _smooth(points: PackedVector3Array) -> PackedVector3Array:
	if points.size() < 3:
		return points
	var result := PackedVector3Array([points[0]])
	for index in points.size() - 1:
		result.append(points[index].lerp(points[index + 1], 0.25))
		result.append(points[index].lerp(points[index + 1], 0.75))
	result.append(points[points.size() - 1])
	return result


# ------------------------------------------------------------------ loot and eruptions

# Amber nodes: denser in forest, ruins, thicket edges and near the map edge,
# rarer on open meadow; tier 0..2 grows with the distance from the start and
# in dangerous land.
func _place_loot() -> void:
	loot_points.clear()
	var target := rng.randi_range(LOOT_COUNT.x, LOOT_COUNT.y) * regions * regions / 16
	var start_point: Vector3 = nodes[hub].center
	var span := playable.size.x
	var tries := 0
	while loot_points.size() < target and tries < target * 40:
		tries += 1
		var point := _random_point(6.0)
		var value := sample(point.x, point.z)
		if value < 1.2:
			continue
		var cell := _cell_of(point)
		var type: int = land[cell.y * grid + cell.x]
		var weight: float = [0.35, 1.0, 1.0, 1.0, 0.7, 0.8, 0.9][type]
		# Close to a wall (in the nooks) and near the map edge: more.
		if value < 5.0:
			weight += 0.4
		if -_edge_distance(point) < 40.0:
			weight += 0.3
		if rng.randf() > weight * 0.6:
			continue
		var clash := false
		for node in nodes:
			if point.distance_to(node.center) < float(node.radius) + 2.0:
				clash = true
				break
		if clash:
			continue
		for other in loot_points:
			if Vector2(other.x - point.x, other.z - point.z).length() < 7.0:
				clash = true
				break
		if clash:
			continue
		var depth := clampf(point.distance_to(start_point) / (span * 0.6), 0.0, 1.0) + _danger(point) * 0.5
		var tier := 0 if depth < 0.45 else (1 if depth < 1.05 else 2)
		loot_points.append(Vector4(point.x, 0.0, point.z, float(tier)))


func _eruptions() -> void:
	eruption_points.clear()
	for attempt in 600:
		var point := _random_point(4.0)
		if sample(point.x, point.z) > 2.5:
			eruption_points.append(Vector4(point.x, 0.0, point.z, 1.0))


# ------------------------------------------------------------------ queries (map_layout.gd interface)

func _clearing_rim(node: Dictionary, angle: float) -> float:
	var amp: Vector3 = node.amp
	var phase: Vector3 = node.phase
	return float(node.radius) * (1.0 + amp.x * sin(3.0 * angle + phase.x) + amp.y * sin(5.0 * angle + phase.y) + amp.z * sin(2.0 * angle + phase.z))


func _clearing_value(node: Dictionary, x: float, z: float) -> float:
	var c: Vector3 = node.center
	var dx := x - c.x
	var dz := z - c.z
	return _clearing_rim(node, atan2(dz, dx)) - sqrt(dx * dx + dz * dz)


func _edge_distance(point: Vector3) -> float:
	var dx := maxf(playable.position.x - point.x, point.x - playable.end.x)
	var dz := maxf(playable.position.y - point.z, point.z - playable.end.y)
	if dx > 0.0 and dz > 0.0:
		return Vector2(dx, dz).length()
	return maxf(dx, dz)


## Signed wall distance at a world point (bilinear; + open, - inside a wall).
func sample(x: float, z: float) -> float:
	var fx := (x - grid_origin.x) / NAV - 0.5
	var fz := (z - grid_origin.y) / NAV - 0.5
	var ix := clampi(floori(fx), 0, grid - 2)
	var iz := clampi(floori(fz), 0, grid - 2)
	var tx := clampf(fx - float(ix), 0.0, 1.0)
	var tz := clampf(fz - float(iz), 0.0, 1.0)
	var i := iz * grid + ix
	var top := sdf[i] + (sdf[i + 1] - sdf[i]) * tx
	var bottom := sdf[i + grid] + (sdf[i + grid + 1] - sdf[i + grid]) * tx
	return top + (bottom - top) * tz


## Direction of rising wall distance (towards open ground), not normalised.
func gradient(x: float, z: float) -> Vector2:
	var fx := (x - grid_origin.x) / NAV - 0.5
	var fz := (z - grid_origin.y) / NAV - 0.5
	var ix := clampi(floori(fx), 0, grid - 2)
	var iz := clampi(floori(fz), 0, grid - 2)
	var tx := clampf(fx - float(ix), 0.0, 1.0)
	var tz := clampf(fz - float(iz), 0.0, 1.0)
	var i := iz * grid + ix
	var gx := (sdf[i + 1] - sdf[i]) * (1.0 - tz) + (sdf[i + grid + 1] - sdf[i + grid]) * tz
	var gz := (sdf[i + grid] - sdf[i]) * (1.0 - tx) + (sdf[i + grid + 1] - sdf[i + 1]) * tx
	return Vector2(gx, gz)


## Wall character at a point (arena_border.gd Wall enum, 4 = ruin, 5 = tree group).
func kind_at(x: float, z: float) -> int:
	var cell := _cell_of(Vector3(x, 0.0, z))
	return kind[cell.y * grid + cell.x]


## Landscape name at a point ("meadow", "forest", ...).
func land_at(x: float, z: float) -> String:
	var cell := _cell_of(Vector3(x, 0.0, z))
	return LAND_NAMES[land[cell.y * grid + cell.x]]


func clearing_at(point: Vector3) -> int:
	for index in nodes.size():
		if _clearing_value(nodes[index], point.x, point.z) >= 0.0:
			return index
	return -1


func slots(type: String) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for node in nodes:
		if node.slots.has(type):
			for spot in node.slots[type]:
				result.append(spot)
	return result


func stats() -> Dictionary:
	var inside := 0
	var closed := 0
	for iz in grid:
		for ix in grid:
			if playable.grow(-EDGE_KEEP).has_point(_cell_center(ix, iz)):
				inside += 1
				if blocked[iz * grid + ix] == 1:
					closed += 1
	var counts := {}
	for node in nodes:
		var type: String = node.types[0]
		counts[type] = int(counts.get(type, 0)) + 1
	var lands := {}
	for key in region_lands:
		var name: String = LAND_NAMES[region_lands[key]]
		lands[name] = int(lands.get(name, 0)) + 1
	return {"blocked": float(closed) / float(maxi(1, inside)), "pois": counts, "trails": edges.size(), "loot": loot_points.size(), "beacons": beacons.size(), "filled": _filled, "joined": _joined, "lands": lands, "msec": build_msec, "clearings": nodes.size(), "paths": edges.size(), "bridges": 0, "min_degree": 0, "loops": 0, "hub_degree": (nodes[hub].edges as Array).size(), "attempts": attempts, "narrow": 0}
