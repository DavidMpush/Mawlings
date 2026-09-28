extends RefCounted

# Natural map edge (stage 18). The playable rectangle of arena.gd ends in a
# wall of dense, staggered props on a jittered 2.8 m grid: jungle thicket
# (leaves, logs, rocks), rock cliffs and swamp water in Verdant Maw; charred
# stumps, basalt columns and lava in the Glutsumpf. Segments of ~36 m along
# each side pick their character from the seed, the front line waves softly,
# low props stand in front and tall ones behind. Beyond the wall the ground
# darkens (vertex-colour band) and two fog layers close it off; a single skirt
# mesh in the fog colour covers everything past the border chunks, so the world
# visibly ends without a straight "wall".
#
# Performance: per chunk one MultiMesh per (mesh, material) plus three flat
# meshes (ground band, low fog, high fog); no node per prop. Only chunks that
# touch the edge build anything here.

const GRID := 2.8                   # placement grid (10 cells per 28 m chunk)
const PER_CHUNK := 10
const DEPTH := 30.0                 # decorated depth beyond the playable edge
const SEGMENT := 36.0               # edge length with one character
# Stage 18c follow-up: the visible front stays within 0.3 m of the collision edge.
const WAVE_MAX := 0.3               # front line waves 0..WAVE_MAX m outwards (< BORDER_INSET)
const BAND_Y := 0.009
const FOG_LOW_Y := 1.2
const FOG_HIGH_Y := 5.0
const SKIRT_REACH := 600.0
const TOUCH_MARGIN := 4.0           # chunks this close to the edge get border parts
enum Side { NORTH, EAST, SOUTH, WEST }   # -z, +x, +z, -x
enum Kind { THICKET, CLIFF, WATER }
const KIND_NAMES := [["thicket", "cliff", "water"], ["char", "basalt", "lava"]]
const DEFAULT_LOOK := {"floor": Color("4a6a34"), "fog": Color(0.16, 0.23, 0.18), "water": Color("2f9ea6"), "shore": Color("5d7a3a")}

const QUALITY = preload("res://scripts/quality.gd")

var arena: Node3D
var look: Dictionary = DEFAULT_LOOK
var band_material: StandardMaterial3D
var fog_low_material: StandardMaterial3D
var fog_high_material: StandardMaterial3D
var skirt_material: StandardMaterial3D
var water_material: StandardMaterial3D
var shore_material: StandardMaterial3D
var crust_material: StandardMaterial3D
var skirt: MeshInstance3D
# Instance colour of the prop being placed: darkens towards the fog with depth.
var _tint := Color.WHITE
# Stage 19: the Dürrschlund builds dunes, sandstone, bones and cacti.
var _desert := false
# Etappe 22: quality "wall_detail" (1 = every prop; lower thins deep interiors).
var _detail := clampf(float(QUALITY.value("wall_detail", 1.0)), 0.3, 1.0)
# Placed props per chunk key (revisits only rebuild the MultiMeshes); cleared
# with every new layout or biome.
var _cache: Dictionary = {}
const CACHE_LIMIT := 48


func _init(owner: Node3D) -> void:
	arena = owner
	band_material = StandardMaterial3D.new()
	band_material.vertex_color_use_as_albedo = true
	band_material.vertex_color_is_srgb = true
	band_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	band_material.roughness = 1.0
	fog_low_material = _fog_material(1)
	fog_high_material = _fog_material(2)
	skirt_material = StandardMaterial3D.new()
	skirt_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	water_material = StandardMaterial3D.new()
	# Rough enough that the sun does not glare white off whole swamp walls.
	water_material.roughness = 0.65
	water_material.vertex_color_use_as_albedo = true
	shore_material = StandardMaterial3D.new()
	shore_material.roughness = 0.95
	shore_material.vertex_color_use_as_albedo = true
	# Glutsumpf lava field: cooled dark crust (no big orange areas next to the
	# ember-red swarm), small glowing pools in it.
	crust_material = StandardMaterial3D.new()
	crust_material.roughness = 0.9
	crust_material.vertex_color_use_as_albedo = true
	skirt = MeshInstance3D.new()
	skirt.name = "Edge fog skirt"
	skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	skirt.material_override = skirt_material
	arena.add_child(skirt)
	rebuild_skirt()


static func _fog_material(priority: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = priority
	return material


## Restyles the shared edge materials for a biome (biomes.gd "border").
func apply_biome(data: Dictionary) -> void:
	look = DEFAULT_LOOK.duplicate()
	look.merge(data.get("border", {}), true)
	_cache.clear()
	_wall_cache.clear()
	skirt_material.albedo_color = look.fog
	water_material.albedo_color = look.water
	shore_material.albedo_color = look.shore
	crust_material.albedo_color = look.get("crust", look.shore)
	crust_material.emission_enabled = look.has("crust_glow")
	crust_material.emission = look.get("crust_glow", Color.BLACK)


## The fog-coloured ground past the border chunks (one mesh for the whole map).
func rebuild_skirt() -> void:
	_cache.clear()
	_wall_cache.clear()
	var inner: Rect2 = arena.bounds().grow(arena.BORDER_CHUNKS * arena.CELL - 0.3)
	var outer := inner.grow(SKIRT_REACH)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var strips := [
		Rect2(outer.position.x, outer.position.y, outer.size.x, inner.position.y - outer.position.y),
		Rect2(outer.position.x, inner.end.y, outer.size.x, outer.end.y - inner.end.y),
		Rect2(outer.position.x, inner.position.y, inner.position.x - outer.position.x, inner.size.y),
		Rect2(inner.end.x, inner.position.y, outer.end.x - inner.end.x, inner.size.y),
	]
	for strip in strips:
		var a := Vector3(strip.position.x, -0.03, strip.position.y)
		var b := Vector3(strip.end.x, -0.03, strip.position.y)
		var c := Vector3(strip.end.x, -0.03, strip.end.y)
		var d := Vector3(strip.position.x, -0.03, strip.end.y)
		for point in [a, b, c, a, c, d]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(point)
	skirt.mesh = surface.commit()


# ------------------------------------------------------------------ geometry

# Side of the map a point beyond (or near) the edge belongs to, and the
# coordinate along that side: Vector2(side, along).
func _side_along(x: float, z: float) -> Vector2:
	var rect: Rect2 = arena.playable_rect()
	var values := [rect.position.y - z, x - rect.end.x, z - rect.end.y, rect.position.x - x]
	var side := 0
	for index in range(1, 4):
		if values[index] > values[side]:
			side = index
	var along := x if side == Side.NORTH or side == Side.SOUTH else z
	return Vector2(side, along)


## How far the visual front of the wall lies beyond the playable edge (0..WAVE_MAX).
func wave(side: int, along: float) -> float:
	var phase := float(arena._hash(side, 0, 1950) % 628) * 0.01
	var value := 1.3 + 0.9 * sin(along * 0.105 + phase) + 0.55 * sin(along * 0.27 + phase * 2.3)
	return clampf(value, 0.0, WAVE_MAX)


func _kind(side: int, along: float) -> int:
	var index := floori((along + 1000.0) / SEGMENT)
	var roll: int = arena._hash(side, index, 1960) % 100
	return Kind.THICKET if roll < 42 else (Kind.CLIFF if roll < 76 else Kind.WATER)


# Depth behind the wavy front line (negative = in front of it).
func _depth(x: float, z: float) -> float:
	var info := _side_along(x, z)
	return arena.edge_distance(Vector3(x, 0.0, z)) - wave(int(info.x), info.y)


## True if a chunk reaches within TOUCH_MARGIN of the playable edge.
func touches(key: Vector2i) -> bool:
	var cell: float = arena.CELL
	var rect: Rect2 = arena.playable_rect().grow(-TOUCH_MARGIN)
	var chunk := Rect2(key.x * cell, key.y * cell, cell, cell)
	return not rect.encloses(chunk)


## Closed organic front line of the wall (world x, z), sampled every `step` m.
func front_line(step: float) -> PackedVector2Array:
	var rect: Rect2 = arena.playable_rect()
	var result := PackedVector2Array()
	var count := maxi(4, ceili(rect.size.x / step))
	# Clockwise: north (west -> east), east, south (east -> west), west.
	for index in count:
		var x := rect.position.x + rect.size.x * float(index) / float(count)
		result.append(Vector2(x, rect.position.y - wave(Side.NORTH, x)))
	for index in count:
		var z := rect.position.y + rect.size.y * float(index) / float(count)
		result.append(Vector2(rect.end.x + wave(Side.EAST, z), z))
	for index in count:
		var x := rect.end.x - rect.size.x * float(index) / float(count)
		result.append(Vector2(x, rect.end.y + wave(Side.SOUTH, x)))
	for index in count:
		var z := rect.end.y - rect.size.y * float(index) / float(count)
		result.append(Vector2(rect.position.x - wave(Side.WEST, z), z))
	return result


## Edge segments with their character: [{kind, side, from, to}] (world x, z on
## the playable edge), neighbouring segments of one kind merged.
func segments() -> Array:
	var rect: Rect2 = arena.playable_rect()
	var names: Array = KIND_NAMES[1 if arena._ember_look() else 0]
	var result := []
	for side in 4:
		var horizontal := side == Side.NORTH or side == Side.SOUTH
		var low := rect.position.x if horizontal else rect.position.y
		var high := rect.end.x if horizontal else rect.end.y
		var fixed: float = [rect.position.y, rect.end.x, rect.end.y, rect.position.x][side]
		var start := low
		var kind := _kind(side, low)
		var along := (floorf((low + 1000.0) / SEGMENT) + 1.0) * SEGMENT - 1000.0
		while true:
			var stop := minf(along, high)
			var next_kind := _kind(side, stop + 0.01) if stop < high else -1
			if next_kind != kind:
				var a := Vector2(start, fixed) if horizontal else Vector2(fixed, start)
				var b := Vector2(stop, fixed) if horizontal else Vector2(fixed, stop)
				result.append({"kind": names[kind], "side": side, "from": a, "to": b})
				start = stop
				kind = next_kind
			if stop >= high:
				break
			along += SEGMENT
	return result


# ------------------------------------------------------------------ building

## Adds the edge parts of one chunk (props, ground band, fog) to `chunk`.
func build(chunk: Node3D, key: Vector2i) -> void:
	var origin := chunk.position
	var ember: bool = arena._ember_look()
	_desert = arena._desert_look()
	var groups: Dictionary = _cache.get(key, {})
	if groups.is_empty():
		groups = _place_all(key, origin, ember)
		if _cache.size() >= CACHE_LIMIT:
			_cache.clear()
		_cache[key] = groups
	for id in groups:
		var group: Array = groups[id]
		_multimesh(chunk, String(id), group[0], group[1], group[2])
	# One depth per grid vertex, shared by the ground band and both fog layers.
	var depths := PackedFloat32Array()
	for gz in PER_CHUNK + 1:
		for gx in PER_CHUNK + 1:
			depths.append(_depth((key.x * PER_CHUNK + gx) * GRID, (key.y * PER_CHUNK + gz) * GRID))
	_ground_band(chunk, key, depths)
	_fog(chunk, key, depths, FOG_LOW_Y, fog_low_material, 2.0, 16.0, 0.75, "Edge fog low")
	_fog(chunk, key, depths, FOG_HIGH_Y, fog_high_material, 6.0, 20.0, 1.0, "Edge fog high")


# Every prop of a chunk as {id: [mesh, material, [[transform, colour], ...]]}.
func _place_all(key: Vector2i, origin: Vector3, ember: bool) -> Dictionary:
	var groups := {}
	for gz in PER_CHUNK:
		for gx in PER_CHUNK:
			var ix := key.x * PER_CHUNK + gx
			var iz := key.y * PER_CHUNK + gz
			var wx: float = float(ix) * GRID + (0.15 + 0.7 * arena._unit(ix, iz, 1970)) * GRID
			var wz: float = float(iz) * GRID + (0.15 + 0.7 * arena._unit(ix, iz, 1971)) * GRID
			var info := _side_along(wx, wz)
			var side := int(info.x)
			var depth: float = arena.edge_distance(Vector3(wx, 0.0, wz)) - wave(side, info.y)
			if depth < -0.3 or depth > DEPTH:
				continue
			# Segment borders are dithered, so two characters interlock.
			var kind := _kind(side, info.y + (arena._unit(ix, iz, 1972) - 0.5) * 9.0)
			_tint = _shade(depth)
			var local := Vector3(wx - origin.x, 0.0, wz - origin.z)
			_fit = 2
			_origin = origin
			_place(groups, ember, kind, side, depth, local, ix, iz)
			_fit = 0
	return groups


# Deep props darken towards the fog colour (instance colour, multiplied).
func _shade(depth: float) -> Color:
	var fog: Color = look.fog
	var dark := Color(minf(1.0, fog.r * 1.5), minf(1.0, fog.g * 1.5), minf(1.0, fog.b * 1.5))
	return Color.WHITE.lerp(dark, smoothstep(1.5, 20.0, depth))


# One grid point: picks the prop(s) by character and depth. Tall props stand
# behind low ones; on the south side (between camera and swarm) the front rows
# stay low so the swarm is never hidden.
func _place(groups: Dictionary, ember: bool, kind: int, side: int, depth: float, local: Vector3, ix: int, iz: int) -> void:
	var roll: float = arena._unit(ix, iz, 1980)
	var size_roll: float = arena._unit(ix, iz, 1981)
	var yaw: float = arena._unit(ix, iz, 1982) * TAU
	var tall := 0.55 if side == Side.SOUTH and depth < 12.0 else 1.0
	# Along-edge yaw for logs (the log model is long along z).
	var along_yaw := (PI * 0.5 if side == Side.NORTH or side == Side.SOUTH else 0.0) + (roll - 0.5) * 0.5
	if depth > 14.0 * _detail and roll < 0.35 + 0.5 * (1.0 - _detail):
		return  # deep in the fog: thinner (quality "wall_detail" thins more)
	if _desert:
		_place_desert(groups, kind, depth, local, roll, size_roll, yaw, tall)
		return
	match kind:
		Kind.THICKET:
			if depth < 2.5:
				if ember:
					if roll < 0.55:
						_leaf(groups, local, 1.4 + size_roll * 0.6, yaw, 1.0)
					else:
						_lump(groups, local, 0.8 + size_roll * 0.5, yaw)
				else:
					_leaf(groups, local, 1.5 + size_roll * 0.8, yaw, 1.0)
					if roll > 0.72:
						_rock(groups, local + Vector3(0.6, 0.0, 0.4), Vector3(0.8, 0.6, 0.75) * (0.8 + size_roll * 0.4), yaw)
			elif depth < 10.0:
				if ember:
					if roll < 0.45:
						_stump(groups, local, 1.3 + size_roll * 0.8, (1.6 + size_roll * 1.8) * tall, yaw)
					elif roll < 0.7:
						_log(groups, local, arena.char_material, 0.8 + size_roll * 0.3, along_yaw)
					else:
						_lump(groups, local, 1.2 + size_roll * 0.8, yaw)
				elif roll < 0.62:
					_leaf(groups, local, 2.4 + size_roll * 1.0, yaw, tall)
				elif roll < 0.8:
					_rock(groups, local, Vector3(2.2, 1.9 * tall, 2.0) * (0.9 + size_roll * 0.4), yaw)
				else:
					_log(groups, local, arena.log_material, 0.8 + size_roll * 0.3, along_yaw)
			else:
				if ember:
					if roll < 0.6:
						_stump(groups, local, 1.8 + size_roll * 1.0, (3.0 + size_roll * 2.2) * tall, yaw)
					else:
						_basalt(groups, local, 1.6 + size_roll * 0.8, (3.0 + size_roll * 2.0) * tall, yaw)
				elif roll < 0.75:
					_leaf(groups, local, 3.2 + size_roll * 1.4, yaw, tall)
				else:
					_rock(groups, local, Vector3(3.2, 2.8 * tall, 3.0) * (0.9 + size_roll * 0.3), yaw)
		Kind.CLIFF:
			if depth < 1.8:
				if ember:
					if roll < 0.15:
						_mushroom(groups, local, 1.5 + size_roll * 0.4, yaw)
					else:
						_lump(groups, local, 0.9 + size_roll * 0.5, yaw)
				elif roll < 0.5:
					_rock(groups, local, Vector3(1.3, 0.95, 1.2) * (0.8 + size_roll * 0.5), yaw)
				else:
					_leaf(groups, local, 1.5 + size_roll * 0.5, yaw, 1.0)
			else:
				var height := (2.4 + size_roll * 1.8) * tall * (1.0 + clampf(depth / 16.0, 0.0, 0.5))
				if ember:
					_basalt(groups, local, 1.7 + roll * 0.9, height * 1.25, yaw)
				else:
					_rock(groups, local, Vector3(3.2 + roll * 1.4, height, 3.0 + size_roll * 1.4), yaw)
					if depth < 6.0 and roll > 0.7:
						_leaf(groups, local + Vector3(-0.9, 0.0, 0.7), 2.0 + size_roll * 0.6, yaw + 1.3, 1.0)
		_:
			if depth < 1.6:
				if ember:
					if roll < 0.3:
						_mushroom(groups, local, 1.4 + size_roll * 0.5, yaw)
					elif roll < 0.55:
						_lump(groups, local, 0.6 + size_roll * 0.4, yaw)
				elif roll < 0.6:
					_add(groups, "reed", arena.reed_mesh, arena.reed_base, arena.reed_material, local, Vector3.ONE * (1.4 + size_roll * 0.7), yaw)
				else:
					_leaf(groups, local, 1.6 + size_roll * 0.5, yaw, 1.0)
			elif depth < 11.0:
				# Overlapping flat discs form a swamp lake with a shore rim; in the
				# Glutsumpf a dark crust field with a few small glowing lava pools.
				var size := 2.5 + size_roll * 0.7
				if ember:
					_disc(groups, "crust", arena.shore_mesh, crust_material, local + Vector3(0, 0.016, 0), size * 1.1)
					if roll > 0.74 and depth > 2.5:
						_disc(groups, "lava", arena.pool_mesh, arena.lava_material, local + Vector3(0, 0.024, 0), 1.0 + size_roll * 0.7)
					elif roll < 0.14:
						_lump(groups, local, 0.9 + size_roll * 0.6, yaw)
				else:
					_disc(groups, "shore", arena.shore_mesh, shore_material, local + Vector3(0, 0.014, 0), size * 1.05)
					_disc(groups, "water", arena.pool_mesh, water_material, local + Vector3(0, 0.022, 0), size)
					if depth > 3.0 and roll > 0.84:
						_add(groups, "reed", arena.reed_mesh, arena.reed_base, arena.reed_material, local, Vector3.ONE * (1.6 + size_roll * 0.6), yaw)
			elif ember:
				_basalt(groups, local, 1.6 + size_roll * 0.8, (3.0 + size_roll * 2.0) * tall, yaw)
			elif roll < 0.7:
				_leaf(groups, local, 3.2 + size_roll * 1.2, yaw, tall)
			else:
				_rock(groups, local, Vector3(3.0, 2.6 * tall, 2.8) * (0.9 + size_roll * 0.3), yaw)


# Dürrschlund edge: THICKET = high dune ridges (the rock model in sand colour,
# flat and wide), CLIFF = rust sandstone blocks with standing slabs, WATER =
# the dune sea (flat sand discs). Tall parts stay behind, low ones in front.
func _place_desert(groups: Dictionary, kind: int, depth: float, local: Vector3, roll: float, size_roll: float, yaw: float, tall: float) -> void:
	match kind:
		Kind.THICKET:
			if depth < 2.5:
				_dune(groups, local, Vector3(2.6, 0.7, 2.3) * (0.9 + size_roll * 0.4), yaw)
			elif depth < 10.0:
				_dune(groups, local, Vector3(4.6, 1.6 * tall, 4.0) * (0.9 + size_roll * 0.3), yaw)
			else:
				_dune(groups, local, Vector3(6.2, 2.6 * tall, 5.4) * (0.9 + size_roll * 0.3), yaw)
		Kind.CLIFF:
			if depth < 1.8:
				_sandstone(groups, local, Vector3(1.4, 1.0, 1.3) * (0.8 + size_roll * 0.5), yaw)
			else:
				var height := (2.4 + size_roll * 1.8) * tall * (1.0 + clampf(depth / 16.0, 0.0, 0.5))
				_sandstone(groups, local, Vector3(3.2 + roll * 1.4, height, 3.0 + size_roll * 1.4), yaw)
				if depth > 4.0 and roll > 0.7:
					_slab(groups, local, 3.6 + size_roll * 1.2, height * 1.1, yaw)
		_:
			if depth < 11.0:
				var size := 2.5 + size_roll * 0.7
				_disc(groups, "shore", arena.shore_mesh, shore_material, local + Vector3(0, 0.014, 0), size * 1.05)
				_disc(groups, "water", arena.pool_mesh, water_material, local + Vector3(0, 0.022, 0), size)
			else:
				_dune(groups, local, Vector3(5.6, 2.2 * tall, 5.0) * (0.9 + size_roll * 0.3), yaw)


func _dune(groups: Dictionary, local: Vector3, size: Vector3, yaw: float) -> void:
	_add(groups, "dune", arena.rock_mesh, arena.rock_base, arena.dune_material, local + Vector3(0, -0.1 * size.y, 0), size, yaw)


func _sandstone(groups: Dictionary, local: Vector3, size: Vector3, yaw: float) -> void:
	_add(groups, "sandstone", arena.rock_mesh, arena.rock_base, arena.sandstone_material, local + Vector3(0, -0.1 * size.y, 0), size, yaw)


# Standing sandstone slab (the flat SandstoneCliff model on its edge), `length`
# along its long side, stretched to `height`.
func _slab(groups: Dictionary, local: Vector3, length: float, height: float, yaw: float) -> void:
	var part: Array = arena.desert_part("sandstone")
	var mesh: Mesh = part[0]
	var base: Transform3D = part[1]
	var box: AABB = Transform3D(base.basis, Vector3.ZERO) * mesh.get_aabb()
	var scale := length / maxf(0.01, maxf(box.size.x, box.size.z))
	_add(groups, "slab", mesh, base, arena.sandstone_material, local, Vector3(scale, height / maxf(0.01, box.size.y), scale), yaw)


func _leaf(groups: Dictionary, local: Vector3, size: float, yaw: float, tall: float) -> void:
	_add(groups, "leaf", arena.leaf_mesh, arena.leaf_base, arena.leaf_material, local, Vector3(size, size * tall, size), yaw)


func _rock(groups: Dictionary, local: Vector3, size: Vector3, yaw: float) -> void:
	# Big rocks sink a little so their round base does not float.
	_add(groups, "rock", arena.rock_mesh, arena.rock_base, arena.rock_material, local + Vector3(0, -0.12 * size.y, 0), size, yaw)


func _lump(groups: Dictionary, local: Vector3, size: float, yaw: float) -> void:
	# Same mesh and material as the basalt columns: one MultiMesh for both.
	_add(groups, "basalt", arena.rock_mesh, arena.rock_base, arena.basalt_material, local, Vector3(size * 1.3, size, size * 1.2), yaw)


# Basalt column cluster: one tall column and two shorter ones leaning on it.
func _basalt(groups: Dictionary, local: Vector3, width: float, height: float, yaw: float) -> void:
	_add(groups, "basalt", arena.rock_mesh, arena.rock_base, arena.basalt_material, local, Vector3(width, height, width), yaw)
	for index in 2:
		var angle := yaw + 2.1 + float(index) * 2.2
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * width * 0.55
		_add(groups, "basalt", arena.rock_mesh, arena.rock_base, arena.basalt_material, local + offset, Vector3(width * 0.75, height * (0.55 + 0.15 * index), width * 0.75), angle * 1.7)


func _mushroom(groups: Dictionary, local: Vector3, size: float, yaw: float) -> void:
	_add(groups, "mushroom", arena.flower_mesh, arena.flower_base, arena.mushroom_material, local, Vector3.ONE * size, yaw)


func _log(groups: Dictionary, local: Vector3, material: Material, size: float, yaw: float) -> void:
	_add(groups, "log %d" % material.get_instance_id(), arena.log_mesh, arena.log_base, material, local, arena.LOG_SIZE * size, yaw)


# Pale weathered stone for ruin walls (Verdant; created once).
var _ruin: ShaderMaterial
func _ruin_material() -> ShaderMaterial:
	if _ruin == null:
		_ruin = (arena.rock_material as ShaderMaterial).duplicate()
		arena.fade_materials.append(_ruin)
		_ruin.set_shader_parameter("body_tint", Color(0.78, 0.72, 0.6, 0.55))
		_ruin.set_shader_parameter("brightness", 1.05)
	return _ruin


# Upright tree trunk (log model standing), any material.
func _trunk(groups: Dictionary, local: Vector3, material: Material, diameter: float, height: float, yaw: float) -> void:
	var mesh: Mesh = arena.log_mesh
	var base: Transform3D = arena.log_base
	var box: AABB = Transform3D(base.basis, Vector3.ZERO) * mesh.get_aabb()
	var fit := Basis.from_scale(Vector3(diameter / maxf(box.size.x, 0.01), diameter / maxf(box.size.y, 0.01), height / maxf(box.size.z, 0.01)))
	var shape := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5) * fit * base.basis
	_append(groups, "trunk %d" % material.get_instance_id(), mesh, material, _rest(mesh, shape, local))


# Upright piece of the log model (like arena._stump).
func _stump(groups: Dictionary, local: Vector3, diameter: float, height: float, yaw: float) -> void:
	var mesh: Mesh = arena.log_mesh
	var base: Transform3D = arena.log_base
	var box: AABB = Transform3D(base.basis, Vector3.ZERO) * mesh.get_aabb()
	var fit := Basis.from_scale(Vector3(diameter / maxf(box.size.x, 0.01), diameter / maxf(box.size.y, 0.01), height / maxf(box.size.z, 0.01)))
	var shape := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5) * fit * base.basis
	_append(groups, "stump", mesh, arena.stump_material, _rest(mesh, shape, local))


func _disc(groups: Dictionary, id: String, mesh: Mesh, material: Material, local: Vector3, size: float) -> void:
	_append(groups, id, mesh, material, Transform3D(Basis.from_scale(Vector3(size, 1.0, size * 0.85)), local))


func _add(groups: Dictionary, id: String, mesh: Mesh, base: Transform3D, material: Material, local: Vector3, size: Vector3, yaw: float) -> void:
	var shape := Basis(Vector3.UP, yaw) * Basis.from_scale(size) * base.basis
	var placed := _rest(mesh, shape, Vector3(local.x, 0.0, local.z))
	placed.origin.y += local.y
	_append(groups, id, mesh, material, placed)


# Rests a shaped mesh on the ground, centred over its footprint (arena._prop_shape).
static func _rest(mesh: Mesh, shape: Basis, local: Vector3) -> Transform3D:
	var box: AABB = Transform3D(shape, Vector3.ZERO) * mesh.get_aabb()
	return Transform3D(shape, local + Vector3(-box.get_center().x, -box.position.y, -box.get_center().z))


# Stage 18c follow-up ("collision = look"): while a fit mode is set, a prop's
# footprint (its oriented bounding box: edge midpoints within 0.3 m, corners
# within 0.8 m for the rounded models) must lie inside the collision - the wall
# (mode 1, layout wall distance) or beyond the map edge (mode 2). Too big props
# shrink step by step (height too); what ends up smaller than MIN_PROP is left
# out, so no tiny pieces stand at a wall.
const MIN_PROP := 0.75
var _fit := 0
var _origin := Vector3.ZERO


func _outside(x: float, z: float) -> float:
	if _fit == 1:
		return arena.layout.sample(x, z)
	return -arena.edge_distance(Vector3(x, 0.0, z))


func _fits(mesh: Mesh, placed: Transform3D) -> bool:
	var box := mesh.get_aabb()
	var lo := box.position
	var hi := box.end
	for u in [0.0, 0.5, 1.0]:
		for v in [0.0, 0.5, 1.0]:
			if u == 0.5 and v == 0.5:
				continue
			var corner: bool = u != 0.5 and v != 0.5
			var local := Vector3(lerpf(lo.x, hi.x, float(u)), lo.y, lerpf(lo.z, hi.z, float(v)))
			var world := placed * local + _origin
			if _outside(world.x, world.z) > (0.8 if corner else 0.3):
				return false
	return true


func _append(groups: Dictionary, id: String, mesh: Mesh, material: Material, placed: Transform3D) -> void:
	if _fit != 0 and not _fits(mesh, placed):
		var box: AABB = placed * mesh.get_aabb()
		var middle := Vector3(box.get_center().x, 0.0, box.get_center().z)
		var lift := placed.origin.y - _rest(mesh, placed.basis, middle).origin.y
		var half := maxf(box.size.x, box.size.z) * 0.5
		var fitted := false
		for step in 6:
			half *= 0.8
			if half < MIN_PROP:
				break
			var shape := Basis.from_scale(Vector3.ONE * pow(0.8, step + 1)) * placed.basis
			var trial := _rest(mesh, shape, middle)
			trial.origin.y += lift * pow(0.8, step + 1)
			if _fits(mesh, trial):
				placed = trial
				fitted = true
				break
		if not fitted:
			return
	if not groups.has(id):
		groups[id] = [mesh, material, []]
	(groups[id][2] as Array).append([placed, _tint])


static func _multimesh(chunk: Node3D, id: String, mesh: Mesh, material: Material, entries: Array) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = entries.size()
	for index in entries.size():
		multimesh.set_instance_transform(index, entries[index][0])
		multimesh.set_instance_color(index, entries[index][1])
	var part := MultiMeshInstance3D.new()
	part.name = "Edge %s" % id
	part.multimesh = multimesh
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(part)


# ------------------------------------------------------------ walls (stage 18b)

# Inner walls of a seeded map (arena.layout): every point of a jittered
# WALL_GRID grid whose wall distance is <= 0 carries props by wall character
# (thicket / cliff / roots / swamp water; Glutsumpf charred wood / basalt /
# charred roots / lava crust) and depth: a dense low rim, big props behind,
# a thinner dark canopy deep inside. Walls with open ground to their north
# stand between the camera and the swarm: their height is capped by depth.
# Under the walls the ground turns into dark forest floor.
const WALL_PER_CHUNK := 12
const WALL_GRID := 28.0 / 12.0
const WALL_ZONE := 46.0             # size of one wall character patch
enum Wall { THICKET, CLIFF, ROOTS, WATER, RUIN, TREE, PILLAR }
var _wall_cache: Dictionary = {}
var _heights: Dictionary = {}


## Adds the wall props and the dark wall floor of one map chunk.
func build_walls(chunk: Node3D, key: Vector2i) -> void:
	var layout: RefCounted = arena.layout
	if layout == null:
		return
	var groups: Dictionary
	if _wall_cache.has(key):
		groups = _wall_cache[key]
	else:
		groups = _place_walls(key, chunk.position, arena._ember_look(), layout)
		if _wall_cache.size() >= CACHE_LIMIT * 2:
			_wall_cache.clear()
		_wall_cache[key] = groups
	for id in groups:
		var group: Array = groups[id]
		_multimesh(chunk, "Wall " + String(id), group[0], group[1], group[2])
	_wall_floor(chunk, key, layout)


## Drops the cached wall props (new layout or biome).
func clear_walls() -> void:
	_wall_cache.clear()


# Character of the wall around a point: organic seeded patches (Voronoi cells
# of a jittered WALL_ZONE grid).
func wall_kind(x: float, z: float) -> int:
	var cx := floori((x + 1000.0) / WALL_ZONE)
	var cz := floori((z + 1000.0) / WALL_ZONE)
	var best := INF
	var roll := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var gx := cx + dx
			var gz := cz + dz
			var px: float = (float(gx) + 0.1 + 0.8 * arena._unit(gx, gz, 2961)) * WALL_ZONE - 1000.0
			var pz: float = (float(gz) + 0.1 + 0.8 * arena._unit(gx, gz, 2962)) * WALL_ZONE - 1000.0
			var d := (x - px) * (x - px) + (z - pz) * (z - pz)
			if d < best:
				best = d
				roll = arena._hash(gx, gz, 2960) % 100
	return Wall.THICKET if roll < 46 else (Wall.CLIFF if roll < 72 else (Wall.ROOTS if roll < 88 else Wall.WATER))


func _mesh_height(mesh: Mesh, base: Transform3D) -> float:
	var id := mesh.get_instance_id()
	if not _heights.has(id):
		_heights[id] = maxf(0.01, (Transform3D(base.basis, Vector3.ZERO) * mesh.get_aabb()).size.y)
	return _heights[id]


func _place_walls(key: Vector2i, origin: Vector3, ember: bool, layout: RefCounted) -> Dictionary:
	var groups := {}
	_desert = arena._desert_look()
	# Exploration map: walls from the grid cells (see _cell_walls).
	if layout.get("kind") != null:
		_fit = 0
		_cell_walls(groups, key, origin, ember, layout)
		if _desert:
			_rib_cages(groups, key, origin, layout)
		return groups
	for gz in WALL_PER_CHUNK:
		for gx in WALL_PER_CHUNK:
			var ix := key.x * WALL_PER_CHUNK + gx
			var iz := key.y * WALL_PER_CHUNK + gz
			var wx: float = float(ix) * WALL_GRID + (0.15 + 0.7 * arena._unit(ix, iz, 2970)) * WALL_GRID
			var wz: float = float(iz) * WALL_GRID + (0.15 + 0.7 * arena._unit(ix, iz, 2971)) * WALL_GRID
			var depth: float = -layout.sample(wx, wz)
			if depth < -0.35:
				continue
			# The map edge carries its own wall (build()).
			if arena.edge_distance(Vector3(wx, 0.0, wz)) > -2.5:
				continue
			var slope: Vector2 = layout.gradient(wx, wz)
			slope = slope.normalized() if slope.length_squared() > 0.000001 else Vector2(0.0, 1.0)
			# Open ground north of the wall (slope towards -z): camera side, keep low.
			var low := clampf(-slope.y * 1.6 - 0.2, 0.0, 1.0)
			# On the camera side the front row starts a little behind the wall line
			# and stays knee-high, so a swarm pressed against it stays visible.
			if low > 0.5 and depth < 0.4:
				continue
			var cap := lerpf(30.0, 0.5 + 0.95 * maxf(depth, 0.0), low)
			var jitter: float = (arena._unit(ix, iz, 2972) - 0.5) * 12.0
			# Stage 18c: the exploration map knows the character of every wall cell.
			var kind: int = layout.kind_at(wx, wz) if layout.has_method("kind_at") else wall_kind(wx + jitter, wz - jitter)
			_tint = _shade(depth * 1.3 + 1.0)
			var tangent := atan2(slope.x, -slope.y)
			_fit = 1
			_origin = origin
			_place_wall(groups, ember, kind, depth, Vector3(wx - origin.x, 0.0, wz - origin.z), ix, iz, cap, tangent)
			_fit = 0
	return groups


func _place_wall(groups: Dictionary, ember: bool, kind: int, depth: float, local: Vector3, ix: int, iz: int, cap: float, tangent: float) -> void:
	var roll: float = arena._unit(ix, iz, 2980)
	var size_roll: float = arena._unit(ix, iz, 2981)
	var yaw: float = arena._unit(ix, iz, 2982) * TAU
	# Logs lie along the wall (the log model is long along z).
	var along := tangent + (roll - 0.5) * 0.4
	if depth > 12.0 and roll < 0.3:
		return  # deep canopy: thinner
	# Glutsumpf: cold-glowing Glutpilze line every wall front (readable edge).
	if ember and depth < 1.2 and arena._unit(ix, iz, 2983) < 0.3:
		_mushroom(groups, local, 1.3 + size_roll * 0.5, yaw)
		return
	match kind:
		Wall.THICKET:
			if depth < 1.6:
				if ember:
					if roll < 0.5:
						_wall_leaf(groups, local, 1.4 + size_roll * 0.6, yaw, cap)
					else:
						_lump(groups, local, 0.8 + size_roll * 0.5, yaw)
				else:
					_wall_leaf(groups, local, 1.5 + size_roll * 0.7, yaw, cap)
					if roll > 0.7:
						_wall_rock(groups, local + Vector3(0.5, 0.0, 0.4), Vector3(0.8, 0.6, 0.75) * (0.8 + size_roll * 0.4), yaw, cap)
			elif depth < 8.0:
				if ember:
					if roll < 0.5:
						_stump(groups, local, 1.3 + size_roll * 0.8, minf(cap, 1.6 + size_roll * 2.0), yaw)
					elif roll < 0.75:
						_log(groups, local, arena.char_material, 0.8 + size_roll * 0.3, along)
					else:
						_lump(groups, local, 1.2 + size_roll * 0.8, yaw)
				elif roll < 0.68:
					_wall_leaf(groups, local, 2.3 + size_roll * 1.0, yaw, cap)
				elif roll < 0.93:
					_wall_rock(groups, local, Vector3(2.2, 1.9, 2.0) * (0.9 + size_roll * 0.4), yaw, cap)
				else:
					_log(groups, local, arena.log_material, 0.8 + size_roll * 0.3, along)
			else:
				if ember:
					if roll < 0.6:
						_stump(groups, local, 1.8 + size_roll * 1.0, minf(cap, 3.0 + size_roll * 2.2), yaw)
					else:
						_basalt(groups, local, 1.6 + size_roll * 0.8, minf(cap, 3.0 + size_roll * 2.0), yaw)
				elif roll < 0.72:
					_wall_leaf(groups, local, 3.1 + size_roll * 1.3, yaw, cap)
				else:
					_wall_rock(groups, local, Vector3(3.2, 2.8, 3.0) * (0.9 + size_roll * 0.3), yaw, cap)
		Wall.CLIFF:
			if depth < 1.4:
				if ember:
					if roll < 0.15:
						_mushroom(groups, local, 1.5 + size_roll * 0.4, yaw)
					else:
						_lump(groups, local, 0.9 + size_roll * 0.5, yaw)
				elif roll < 0.55:
					_wall_rock(groups, local, Vector3(1.3, 0.95, 1.2) * (0.8 + size_roll * 0.5), yaw, cap)
				else:
					_wall_leaf(groups, local, 1.5 + size_roll * 0.5, yaw, cap)
			else:
				var height := (2.2 + size_roll * 1.6) * (1.0 + clampf(depth / 16.0, 0.0, 0.5))
				if ember:
					_basalt(groups, local, 1.7 + roll * 0.9, minf(cap, height * 1.2), yaw)
				else:
					_wall_rock(groups, local, Vector3(3.0 + roll * 1.4, height, 2.8 + size_roll * 1.4), yaw, cap)
					if depth < 5.0 and roll > 0.72:
						_wall_leaf(groups, local + Vector3(-0.9, 0.0, 0.7), 2.0 + size_roll * 0.6, yaw + 1.3, cap)
		Wall.ROOTS:
			if depth < 1.6:
				if ember:
					_lump(groups, local, 0.7 + size_roll * 0.5, yaw)
				else:
					_wall_leaf(groups, local, 1.4 + size_roll * 0.6, yaw, cap)
			elif depth < 7.0:
				if roll < 0.4:
					_log(groups, local, arena.char_material if ember else arena.log_material, 0.95 + size_roll * 0.3, along)
					if not ember:
						_wall_leaf(groups, local + Vector3(0.8, 0.0, -0.6), 1.8 + size_roll * 0.5, yaw, cap)
				elif roll < 0.72 and cap > 3.0:
					# A sunken root arch as a hump in the wall.
					_add(groups, "root", arena.arch_mesh, arena.arch_base, arena.char_material if ember else arena.arch_material, local, arena.ARCH_SIZE * (0.42 + size_roll * 0.12), along + PI * 0.5)
				elif ember:
					_stump(groups, local, 1.2 + size_roll * 0.7, minf(cap, 1.8 + size_roll * 1.4), yaw)
				else:
					_wall_leaf(groups, local, 2.4 + size_roll * 0.8, yaw, cap)
			elif ember:
				_stump(groups, local, 1.8 + size_roll * 1.0, minf(cap, 2.6 + size_roll * 2.0), yaw)
			elif roll < 0.7:
				_wall_leaf(groups, local, 3.0 + size_roll * 1.2, yaw, cap)
			else:
				_log(groups, local, arena.log_material, 1.0 + size_roll * 0.3, along)
		Wall.RUIN, Wall.PILLAR:
			return  # built from the grid cells (_masonry)
		Wall.RUIN:
			# Broken walls: pale box-like blocks along the wall, rubble in front.
			var stone: Material = arena.basalt_material if ember else _ruin_material()
			if depth >= -0.3:
				# Every point of the thin wall carries an overlapping block along the
				# wall line, so the outline (corners, door gaps) reads continuous.
				var rock_h := maxf(0.01, _mesh_height(arena.rock_mesh, arena.rock_base))
				var wall_h := minf(cap, 1.8 + size_roll * 1.6) / rock_h
				_add(groups, "ruin", arena.rock_mesh, arena.rock_base, stone, local, Vector3(3.2, wall_h, 2.1), tangent + (roll - 0.5) * 0.12)
				if roll > 0.82:
					_add(groups, "ruin", arena.rock_mesh, arena.rock_base, stone, local + Vector3(cos(yaw) * 1.8, 0.0, sin(yaw) * 1.8), Vector3(0.9, 0.6, 0.8), yaw)
			elif depth < 0.25:
				if roll < 0.6:
					_add(groups, "ruin", arena.rock_mesh, arena.rock_base, stone, local, Vector3(1.0, 0.7, 0.9) * (0.8 + size_roll * 0.5), yaw)
				elif not ember:
					_wall_leaf(groups, local, 1.3 + size_roll * 0.5, yaw, cap)
			elif depth < 9.0 or roll < 0.5:
				var block := minf(cap, 2.4 + size_roll * 1.4) / maxf(0.01, _mesh_height(arena.rock_mesh, arena.rock_base))
				_add(groups, "ruin", arena.rock_mesh, arena.rock_base, stone, local, Vector3(2.5, block, 1.5), tangent + (roll - 0.5) * 0.2)
				if not ember and roll > 0.8:
					_wall_leaf(groups, local + Vector3(0.6, 0.0, 0.5), 1.6 + size_roll * 0.5, yaw, cap)
		Wall.PILLAR:
			# Broken column: a tall narrow shaft, a fallen drum beside it.
			var column: Material = arena.basalt_material if ember else _ruin_material()
			var rock_h := maxf(0.01, _mesh_height(arena.rock_mesh, arena.rock_base))
			var tall := minf(cap, 2.6 + size_roll * 2.2) / rock_h
			_add(groups, "ruin", arena.rock_mesh, arena.rock_base, column, local, Vector3(1.25, tall, 1.25), yaw)
			if roll > 0.45:
				_add(groups, "ruin", arena.rock_mesh, arena.rock_base, column, local + Vector3(cos(yaw) * 1.6, 0.0, sin(yaw) * 1.6), Vector3(1.1, 0.8, 1.9), yaw + 1.2)
		Wall.TREE:
			# Tree groups of the light forest: trunks with a leaf crown, bushes in front.
			if depth < 0.9 or cap < 2.6:
				if ember:
					_lump(groups, local, 0.8 + size_roll * 0.4, yaw)
				else:
					_wall_leaf(groups, local, 1.6 + size_roll * 0.6, yaw, cap)
			else:
				var height := minf(cap, 3.6 + size_roll * 1.8)
				_trunk(groups, local, arena.char_material if ember else arena.log_material, 0.9 + roll * 0.5, height, yaw)
				if ember:
					if roll < 0.3:
						_mushroom(groups, local + Vector3(0.8, 0.0, 0.4), 1.2, yaw)
				else:
					_add(groups, "leaf", arena.leaf_mesh, arena.leaf_base, arena.leaf_material, local + Vector3(0.0, height * 0.72, 0.0), Vector3.ONE * (3.0 + size_roll * 1.2), yaw)
		_:
			if depth < 1.0:
				if ember:
					if roll < 0.3:
						_mushroom(groups, local, 1.4 + size_roll * 0.5, yaw)
					else:
						_lump(groups, local, 0.6 + size_roll * 0.4, yaw)
				elif roll < 0.6:
					_add(groups, "reed", arena.reed_mesh, arena.reed_base, arena.reed_material, local, Vector3.ONE * (1.4 + size_roll * 0.7), yaw)
				else:
					_wall_leaf(groups, local, 1.5 + size_roll * 0.5, yaw, cap)
			elif depth < 10.0:
				var size := 2.1 + size_roll * 0.6
				if ember:
					_disc(groups, "crust", arena.shore_mesh, crust_material, local + Vector3(0, 0.016, 0), size * 1.1)
					if roll > 0.95 and depth > 3.0:
						_disc(groups, "lava", arena.pool_mesh, arena.lava_material, local + Vector3(0, 0.024, 0), 0.8 + size_roll * 0.4)
					elif roll < 0.14:
						_lump(groups, local, 0.9 + size_roll * 0.6, yaw)
				else:
					_disc(groups, "shore", arena.shore_mesh, shore_material, local + Vector3(0, 0.014, 0), size * 1.05)
					_disc(groups, "water", arena.pool_mesh, water_material, local + Vector3(0, 0.022, 0), size)
					if depth > 2.5 and roll > 0.86:
						_add(groups, "reed", arena.reed_mesh, arena.reed_base, arena.reed_material, local, Vector3.ONE * (1.6 + size_roll * 0.6), yaw)
			elif ember:
				_basalt(groups, local, 1.6 + size_roll * 0.8, minf(cap, 3.0 + size_roll * 2.0), yaw)
			elif roll < 0.7:
				_wall_leaf(groups, local, 3.0 + size_roll * 1.2, yaw, cap)
			else:
				_wall_rock(groups, local, Vector3(3.0, 2.6, 2.8) * (0.9 + size_roll * 0.3), yaw, cap)


# Stage 18c follow-up ("big, clear obstacles; collision = look"): on the
# exploration map every blocked 2 m grid cell carries one big element of its
# wall character - rock block, bush mass, tree, water, masonry - sized to its
# cell, so the walls are continuous, have no loose small bits and end exactly
# at the collision edge. Taller inside, low on the camera side (open ground to
# the north), deep inside thinner (the dark floor carries it).
var _block_mesh: BoxMesh
var _masonry_material: ShaderMaterial

func _mesh_width(mesh: Mesh, base: Transform3D) -> float:
	var box: AABB = Transform3D(base.basis, Vector3.ZERO) * mesh.get_aabb()
	return maxf(0.01, maxf(box.size.x, box.size.z))


func _cell_walls(groups: Dictionary, key: Vector2i, origin: Vector3, ember: bool, layout: RefCounted) -> void:
	if _block_mesh == null:
		_block_mesh = BoxMesh.new()
	var nav: float = layout.NAV
	var grid: int = layout.grid
	var grid_origin: Vector2 = layout.grid_origin
	var lo := Vector2i(floori((key.x * 28.0 - grid_origin.x) / nav), floori((key.y * 28.0 - grid_origin.y) / nav))
	var cells := int(round(28.0 / nav))
	var kinds: PackedByteArray = layout.kind
	var closed: PackedByteArray = layout.blocked
	var rock_w := _mesh_width(arena.rock_mesh, arena.rock_base)
	var rock_h := _mesh_height(arena.rock_mesh, arena.rock_base)
	var leaf_w := _mesh_width(arena.leaf_mesh, arena.leaf_base)
	var leaf_h := _mesh_height(arena.leaf_mesh, arena.leaf_base)
	for dz in cells:
		for dx in cells:
			var ix := lo.x + dx
			var iz := lo.y + dz
			if ix < 1 or iz < 1 or ix >= grid - 1 or iz >= grid - 1:
				continue
			var index := iz * grid + ix
			if closed[index] == 0:
				continue
			var cx: float = grid_origin.x + (float(ix) + 0.5) * nav
			var cz: float = grid_origin.y + (float(iz) + 0.5) * nav
			if arena.edge_distance(Vector3(cx, 0.0, cz)) > -2.5:
				continue
			var depth: float = -float(layout.sdf[index])
			var roll: float = arena._unit(ix, iz, 3300)
			var yaw: float = arena._unit(ix, iz, 3301) * TAU
			var inner := closed[index - 1] == 1 and closed[index + 1] == 1 and closed[index - grid] == 1 and closed[index + grid] == 1
			var camera_side := closed[index - grid] == 0
			# Etappe 22: quality "wall_detail" thins the deep inside (the rim stays).
			if depth > 9.0 * _detail and roll < 1.0 - 0.5 * _detail:
				continue
			var local := Vector3(cx - origin.x, 0.0, cz - origin.z)
			_tint = _shade(depth * 1.3 + 1.0)
			var type: int = kinds[index]
			if _desert:
				_desert_cell(groups, type, local, roll, yaw, inner, camera_side, nav, origin)
				continue
			match type:
				Wall.RUIN, Wall.PILLAR:
					var height := (3.4 + roll * 1.4) if type == Wall.PILLAR else (1.5 + roll * 1.3)
					if camera_side:
						height = minf(height, 1.8)
					_tint = Color("4a4046").lerp(Color("5c5157"), roll) if ember else Color("8f8676").lerp(Color("aaa08a"), roll)
					_append(groups, "masonry", _block_mesh, _masonry(ember), Transform3D(Basis.from_scale(Vector3(nav, height, nav)), local + Vector3(0.0, height * 0.5, 0.0)))
				Wall.CLIFF:
					var height := (2.2 + roll * 1.6) if inner else (1.4 + roll * 0.8)
					if camera_side:
						height = minf(height, 1.4)
					var footprint := nav * 1.35
					_add(groups, "basalt" if ember else "rock", arena.rock_mesh, arena.rock_base, arena.basalt_material if ember else arena.rock_material, local, Vector3(footprint / rock_w, height / rock_h, footprint / rock_w), yaw)
				Wall.WATER:
					if ember:
						_disc(groups, "crust", arena.shore_mesh, crust_material, local + Vector3(0, 0.016, 0), 1.25)
						if inner and roll > 0.93:
							_disc(groups, "lava", arena.pool_mesh, arena.lava_material, local + Vector3(0, 0.024, 0), 0.9)
					else:
						_disc(groups, "shore", arena.shore_mesh, shore_material, local + Vector3(0, 0.014, 0), 1.2)
						_disc(groups, "water", arena.pool_mesh, water_material, local + Vector3(0, 0.022, 0), 1.15 if inner else 0.95)
				Wall.TREE:
					if inner and roll < 0.55:
						var height := minf(4.2 + roll * 2.0, 1.6 if camera_side else 99.0)
						_trunk(groups, local, arena.char_material if ember else arena.log_material, 1.2, height, yaw)
						if not ember and height > 3.0:
							_add(groups, "leaf", arena.leaf_mesh, arena.leaf_base, arena.leaf_material, local + Vector3(0.0, height * 0.72, 0.0), Vector3.ONE * (nav * 1.5 / leaf_w), yaw)
					elif ember:
						_add(groups, "basalt", arena.rock_mesh, arena.rock_base, arena.basalt_material, local, Vector3(nav * 1.3 / rock_w, 0.9 / rock_h, nav * 1.3 / rock_w), yaw)
					else:
						_add(groups, "leaf", arena.leaf_mesh, arena.leaf_base, arena.leaf_material, local, Vector3(nav * 1.4 / leaf_w, minf(1.3, 2.0) / leaf_h, nav * 1.4 / leaf_w), yaw)
				_:
					# Thicket and root walls: one dense bush (charred stump) per cell,
					# logs lying in the inside of root walls.
					var height := (2.0 + roll * 1.2) if inner else 1.4
					if camera_side:
						height = minf(height, 1.3)
					if ember:
						_stump(groups, local, nav * 1.1, height, yaw)
					elif type == Wall.ROOTS and inner and roll < 0.3:
						_log(groups, local, arena.log_material, 0.55, yaw)
					else:
						_add(groups, "leaf", arena.leaf_mesh, arena.leaf_base, arena.leaf_material, local, Vector3(nav * 1.45 / leaf_w, height / leaf_h, nav * 1.45 / leaf_w), yaw)


# Stage 19 (Dürrschlund): one big element per blocked cell, like the green
# map - sandstone block (CLIFF, standing slabs inside), oasis water with a
# green rim (WATER), a cactus (CACTUS); rib cells stay empty (one RibBones model
# per cage, _rib_cages). Collision = look: every piece is checked against the
# wall distance (fit mode 1) and shrinks or drops when it would stick out.
func _desert_cell(groups: Dictionary, type: int, local: Vector3, roll: float, yaw: float, inner: bool, camera_side: bool, nav: float, origin: Vector3) -> void:
	var rock_w := _mesh_width(arena.rock_mesh, arena.rock_base)
	var rock_h := _mesh_height(arena.rock_mesh, arena.rock_base)
	match type:
		Wall.CLIFF:
			var height := (2.4 + roll * 1.8) if inner else (1.5 + roll * 0.8)
			if camera_side:
				height = minf(height, 1.4)
			var footprint := nav * 1.35
			_add(groups, "sandstone", arena.rock_mesh, arena.rock_base, arena.sandstone_material, local, Vector3(footprint / rock_w, height / rock_h, footprint / rock_w), yaw)
			if inner and not camera_side and roll < 0.28:
				_fit = 1
				_origin = origin
				_slab(groups, local, nav * 2.2, height + 1.2, yaw)
				_fit = 0
		Wall.WATER:
			# Inner discs overlap the cell corners (no shore showing through).
			_disc(groups, "oasis shore", arena.shore_mesh, arena.shore_material, local + Vector3(0, 0.014, 0), 1.35 if inner else 1.15)
			_disc(groups, "oasis", arena.pool_mesh, arena.water_material, local + Vector3(0, 0.022, 0), 1.5 if inner else 0.95)
		8:  # map_explore.KIND_CACTUS
			var part: Array = arena.desert_part("cactus")
			var mesh: Mesh = part[0]
			var base: Transform3D = part[1]
			var width := _mesh_width(mesh, base)
			var high := _mesh_height(mesh, base)
			var size := nav * 1.5 / width
			var height := size * high * (1.5 if inner else 1.05)
			if camera_side:
				height = minf(height, 1.5)
			_add(groups, "cactus", mesh, base, arena.cactus_material, local, Vector3(size, height / high, size), yaw)
		7:  # map_explore.KIND_RIB: the cage model covers it
			pass
		_:
			_add(groups, "sandstone", arena.rock_mesh, arena.rock_base, arena.sandstone_material, local, Vector3(nav * 1.35 / rock_w, 1.6 / rock_h, nav * 1.35 / rock_w), yaw)


# One RibBones model per intact rib cage whose centre lies in this chunk,
# stretched over the stamped block (fit-checked against the wall distance).
func _rib_cages(groups: Dictionary, key: Vector2i, origin: Vector3, layout: RefCounted) -> void:
	var cages: Variant = layout.get("ribs")
	if not cages is Array:
		return
	var part: Array = arena.desert_part("ribs")
	var mesh: Mesh = part[0]
	var base: Transform3D = part[1]
	var box: AABB = Transform3D(base.basis, Vector3.ZERO) * mesh.get_aabb()
	for cage in cages:
		var center: Vector3 = cage.center
		if floori(center.x / 28.0) != key.x or floori(center.z / 28.0) != key.y:
			continue
		var scale := float(cage.length) / maxf(0.01, box.size.z)
		_tint = Color.WHITE
		_fit = 1
		_origin = origin
		_add(groups, "ribs", mesh, base, arena.bone_material, center - origin, Vector3(scale, scale * 1.15, scale), float(cage.yaw))
		_fit = 0


# Stone material of the masonry blocks (instance colours carry the stone).
func _masonry(ember: bool) -> Material:
	if ember:
		return arena.basalt_material
	if _masonry_material == null:
		_masonry_material = (arena.rock_material as ShaderMaterial).duplicate()
		_masonry_material.set_shader_parameter("body_tint", Color(0.72, 0.68, 0.6, 0.35))
		arena.fade_materials.append(_masonry_material)
	return _masonry_material

# Leaf clump with its height limited to `cap` metres.
func _wall_leaf(groups: Dictionary, local: Vector3, size: float, yaw: float, cap: float) -> void:
	var height := size * _mesh_height(arena.leaf_mesh, arena.leaf_base)
	_leaf(groups, local, size, yaw, minf(1.0, cap / height))


func _wall_rock(groups: Dictionary, local: Vector3, size: Vector3, yaw: float, cap: float) -> void:
	var height := size.y * _mesh_height(arena.rock_mesh, arena.rock_base)
	if height > cap:
		size.y *= cap / height
	_rock(groups, local, size, yaw)


# Dark forest floor under the walls (fully dark 1 m behind the wall line,
# darker still deep inside); transparent on open ground.
# Finer grid than the props: the edge of the dark floor follows the collision.
const FLOOR_PER_CHUNK := 24


func _wall_floor(chunk: Node3D, key: Vector2i, layout: RefCounted) -> void:
	# Glutsumpf: the ember ground is dark itself, so its walls go darker still.
	var floor_color: Color = look.floor if not arena._ember_look() else (look.fog as Color).lerp(look.floor, 0.3)
	var deep: Color = floor_color.lerp(look.fog, 0.45)
	var count := FLOOR_PER_CHUNK + 1
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var colors: Array[Color] = []
	var points: Array[Vector3] = []
	for gz in count:
		for gx in count:
			var wx := key.x * 28.0 + float(gx) * 28.0 / FLOOR_PER_CHUNK
			var wz := key.y * 28.0 + float(gz) * 28.0 / FLOOR_PER_CHUNK
			var depth: float = -layout.sample(wx, wz)
			var color := floor_color.lerp(deep, smoothstep(4.0, 18.0, depth))
			# A dark contact shadow right at the collision edge (the border reads
			# as "solid here"), sharp towards the open ground.
			color = color.darkened(0.45 * (1.0 - smoothstep(0.0, 1.6, depth)))
			color.a = smoothstep(-0.35, 0.25, depth) * 0.97
			colors.append(color)
			points.append(Vector3(wx - chunk.position.x, 0.012, wz - chunk.position.z))
	var quads := 0
	for gz in FLOOR_PER_CHUNK:
		for gx in FLOOR_PER_CHUNK:
			var a := gz * count + gx
			var corners := [a, a + 1, a + count + 1, a + count]
			var visible := false
			for corner in corners:
				if colors[corner].a > 0.004:
					visible = true
			if not visible:
				continue
			for index in [0, 1, 2, 0, 2, 3]:
				var corner: int = corners[index]
				surface.set_color(colors[corner])
				surface.set_normal(Vector3.UP)
				surface.add_vertex(points[corner])
			quads += 1
	if quads == 0:
		return
	var part := MeshInstance3D.new()
	part.name = "Wall floor"
	part.mesh = surface.commit()
	part.material_override = band_material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(part)


# Ground darkening behind the front line: forest floor fading into the fog
# colour; transparent towards the open ground so it blends with any tint.
func _ground_band(chunk: Node3D, key: Vector2i, depths: PackedFloat32Array) -> void:
	var floor_color: Color = look.floor
	var fog_color: Color = look.fog
	var mesh := _grid_mesh(chunk, key, depths, BAND_Y, func(depth: float) -> Color:
		var color := floor_color.lerp(fog_color, smoothstep(3.0, 24.0, depth))
		color.a = smoothstep(-2.5, 0.0, depth)
		return color)
	if mesh == null:
		return
	var part := MeshInstance3D.new()
	part.name = "Edge ground"
	part.mesh = mesh
	part.material_override = band_material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(part)


func _fog(chunk: Node3D, key: Vector2i, depths: PackedFloat32Array, height: float, material: Material, start: float, full: float, strength: float, label: String) -> void:
	var fog_color: Color = look.fog
	var mesh := _grid_mesh(chunk, key, depths, height, func(depth: float) -> Color:
		return Color(fog_color, strength * smoothstep(start, full, depth)))
	if mesh == null:
		return
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = mesh
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(part)


# Flat grid over the chunk with a colour per vertex from the depth behind the
# front line; quads that stay fully transparent are left out.
func _grid_mesh(chunk: Node3D, key: Vector2i, depths: PackedFloat32Array, height: float, paint: Callable) -> ArrayMesh:
	var count := PER_CHUNK + 1
	var colors: Array[Color] = []
	var points: Array[Vector3] = []
	for gz in count:
		for gx in count:
			var world := Vector3((key.x * PER_CHUNK + gx) * GRID, 0.0, (key.y * PER_CHUNK + gz) * GRID)
			colors.append(paint.call(depths[gz * count + gx]))
			points.append(Vector3(world.x - chunk.position.x, height, world.z - chunk.position.z))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := 0
	for gz in PER_CHUNK:
		for gx in PER_CHUNK:
			var a := gz * count + gx
			var corners := [a, a + 1, a + count + 1, a + count]
			var visible := false
			for corner in corners:
				if colors[corner].a > 0.004:
					visible = true
			if not visible:
				continue
			for index in [0, 1, 2, 0, 2, 3]:
				var corner: int = corners[index]
				surface.set_color(colors[corner])
				surface.set_normal(Vector3.UP)
				surface.add_vertex(points[corner])
			quads += 1
	if quads == 0:
		return null
	return surface.commit()
