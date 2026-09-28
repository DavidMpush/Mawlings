extends SceneTree

# Stage 29 (lakes and moors with a shallow shore): every swamp region holds 1-2
# big basins (14-30 m) and 0-3 small ponds (4-8 m), the oasis one big pond; the
# shallow band slows (swarm, enemies, horde) and the deep middle blocks; the
# drawn deep edge (bicubic water field of the chunk, as in water.gdshader) is the
# collision edge within 0.3 m; open ground stays connected, no place and no
# amber node lies in the water; the chunks draw one water surface instead of
# disc chains; the Glutsumpf draws lava with a walkable crust ring.

const SEEDS := [4242, 777, 90210, 31337, 5150, 2024]
const DESERT_SEEDS := [4242, 31337, 777]
const HORDE_SCRIPT = preload("res://scripts/horde.gd")
const TUNING = preload("res://scripts/tuning.gd")
const WATER_SHADER = preload("res://shaders/water.gdshader")

var failures: Array[String] = []
var arena: Variant
var scene: Node
var big_sizes: Array[float] = []
var small_sizes: Array[float] = []
var edge_errors: Array[float] = []


func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	arena = scene.get_node("Arena")
	scene.set_process(false)
	scene.get_node("HuntWorld").set_process(false)
	scene.get_node("Swarm").set_process(false)
	var swamps := 0
	for seed_value in SEEDS:
		arena.set_seed(seed_value)
		swamps += _check_basins(seed_value, false)
		_check_places(seed_value)
		_check_motion(seed_value)
		_check_edge(seed_value)
	check(swamps >= 4, "Swamp regions tested (%d)" % swamps)
	check(big_sizes.size() >= 6 and small_sizes.size() >= 3, "Basins measured (%d big, %d small)" % [big_sizes.size(), small_sizes.size()])
	arena.set_seed(SEEDS[0])
	await _check_render()
	await _check_horde()
	arena.set_biome("duerrschlund")
	var oases := 0
	for seed_value in DESERT_SEEDS:
		arena.set_seed(seed_value)
		oases += _check_basins(seed_value, true)
		_check_places(seed_value)
		_check_edge(seed_value)
	check(oases >= 2, "Oasis regions tested (%d)" % oases)
	arena.set_biome("glutsumpf")
	arena.set_seed(SEEDS[0])
	_check_basins(SEEDS[0], false)
	_check_motion(SEEDS[0])
	await _check_render(true)
	arena.set_biome("verdant_maw")
	arena.set_seed(0)
	big_sizes.sort()
	small_sizes.sort()
	edge_errors.sort()
	print("Big basins %d: %.1f-%.1f m, small ponds %d: %.1f-%.1f m, deep edge look vs collision worst %.3f m over %d samples" % [big_sizes.size(), big_sizes[0], big_sizes[-1], small_sizes.size(), small_sizes[0], small_sizes[-1], edge_errors[-1] if not edge_errors.is_empty() else -1.0, edge_errors.size()])
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS water: basins per swamp region (1-2 big 14-30 m, 0-3 small), one oasis pond, shallow shore slows swarm/enemies/horde, deep water blocks, deep edge drawn = collision (+-0.3 m), connected, places and amber dry, one surface per chunk, Glutsumpf lava")
	quit(0)


# Counts and sizes of the basins per swamp (oasis) region. Returns the number
# of swamp regions checked.
func _check_basins(seed_value: int, desert: bool) -> int:
	var layout: RefCounted = arena.layout
	var regions := 0
	for key in layout.region_lands:
		if int(layout.region_lands[key]) != layout.Land.SWAMP:
			continue
		regions += 1
		var bigs := 0
		var smalls := 0
		for basin in layout.basins:
			if basin.region != key:
				continue
			var size := _diameter(layout, basin)
			if basin.big:
				bigs += 1
				big_sizes.append(size)
				check(size >= 13.0 and size <= 32.0, "Big basin 14-30 m across (seed %d: %.1f m)" % [seed_value, size])
				check(_deep_cells(layout, basin) >= 12, "Big basin has a deep middle (seed %d)" % seed_value)
			else:
				smalls += 1
				small_sizes.append(size)
				check(size >= 3.0 and size <= 9.5, "Small pond 4-8 m across (seed %d: %.1f m)" % [seed_value, size])
				check(_deep_cells(layout, basin) == 0, "Small pond stays shallow (seed %d)" % seed_value)
		if desert:
			check(bigs == 1 and smalls == 0, "Oasis: one big pond (seed %d region %s: %d / %d)" % [seed_value, key, bigs, smalls])
		else:
			check(bigs >= 1 and bigs <= 2 and smalls <= 3, "Swamp region %s: 1-2 big basins, 0-3 small (seed %d: %d / %d)" % [key, seed_value, bigs, smalls])
	return regions


# Equivalent diameter of the water area of a basin (cells nearest to it).
func _diameter(layout: RefCounted, basin: Dictionary) -> float:
	var cells := 0
	for index in _cells_of(layout, basin):
		if layout.water[index] < 0.0:
			cells += 1
	return 2.0 * sqrt(float(cells) * layout.NAV * layout.NAV / PI)


func _deep_cells(layout: RefCounted, basin: Dictionary) -> int:
	var cells := 0
	for index in _cells_of(layout, basin):
		if layout.water_deep[index] < 0.0:
			cells += 1
	return cells


func _cells_of(layout: RefCounted, basin: Dictionary) -> PackedInt32Array:
	var result := PackedInt32Array()
	var center: Vector3 = basin.center
	var reach := float(basin.radius) + 5.0
	var grid: int = layout.grid
	for iz in grid:
		for ix in grid:
			var p: Vector2 = layout._cell_center(ix, iz)
			if Vector2(p.x - center.x, p.y - center.z).length() <= reach:
				result.append(iz * grid + ix)
	return result


# No place (clearing) and no amber node in the water; every lake's shallow
# shore is reachable over open ground.
func _check_places(seed_value: int) -> void:
	var layout: RefCounted = arena.layout
	for node in layout.nodes:
		var center: Vector3 = node.center
		check(layout.water_at(center.x, center.z) > float(node.radius), "Place %s dry (seed %d: %.1f m to the shore)" % [node.types, seed_value, layout.water_at(center.x, center.z)])
	for amber in layout.loot_points:
		check(layout.water_at(amber.x, amber.z) > 0.5, "Amber node dry (seed %d)" % seed_value)
	var start: Vector3 = arena.spawn_points(1)[0]
	arena.finish_flow(start)
	for basin in layout.basins:
		var spot := _shallow_spot(layout, basin)
		if spot.is_finite():
			check(is_finite(arena.flow_distance(spot)), "Shallow shore reachable (seed %d, %s)" % [seed_value, spot])


# A point on a ray from the basin centre, in the middle of the shallow band.
func _shallow_spot(layout: RefCounted, basin: Dictionary, angle := PI * 0.5) -> Vector3:
	var center: Vector3 = basin.center
	var direction := Vector3(cos(angle), 0.0, sin(angle))
	for step in 120:
		var point := center + direction * float(step) * 0.25
		if layout.deep_at(point.x, point.z) > 1.1 and layout.water_at(point.x, point.z) < -0.9:
			return point
	return Vector3.INF


# The shallow band slows, dry ground does not, deep water blocks; walking into
# a lake ends in the shallow band at the deep edge.
func _check_motion(seed_value: int) -> void:
	var layout: RefCounted = arena.layout
	for basin in layout.basins:
		if not basin.big:
			continue
		var center: Vector3 = basin.center
		var spot := _shallow_spot(layout, basin)
		if not spot.is_finite():
			continue
		var factor: float = arena.shallow_factor(spot)
		check(absf(factor - TUNING.SHALLOW_SLOW) < 0.02, "Shallow water slows to %.2f (seed %d: %.2f)" % [TUNING.SHALLOW_SLOW, seed_value, factor])
		var out := Vector3(spot.x - center.x, 0.0, spot.z - center.z).normalized()
		var moved: Vector3 = arena.resolve_motion(spot, out * 0.3, 0.75)
		check(absf(moved.distance_to(spot) - 0.3 * TUNING.SHALLOW_SLOW) < 0.02, "Motion in the shallows is slowed (seed %d: %.3f m of 0.3)" % [seed_value, moved.distance_to(spot)])
		var dry := spot + out * 8.0
		if layout.water_at(dry.x, dry.z) > 1.0 and arena.wall_distance(dry) > 1.5:
			check(arena.shallow_factor(dry) == 1.0, "Dry ground does not slow (seed %d)" % seed_value)
		check(arena.wall_distance(center) < -1.0 and not arena.is_open(center, 0.1), "Deep middle blocks (seed %d)" % seed_value)
		# Walk straight in from the dry side: stop in the shallows at the deep edge.
		var walker := spot + out * 6.0
		for step in 120:
			walker = arena.resolve_motion(walker, -out * 0.3, 0.75)
		check(arena.wall_distance(walker) > 0.6, "Walker never enters deep water (seed %d: %.2f)" % [seed_value, arena.wall_distance(walker)])
		check(layout.water_at(walker.x, walker.z) < 0.0 and layout.deep_at(walker.x, walker.z) < 1.4, "Walker ends in the shallows at the deep edge (seed %d)" % seed_value)


# Collision = look: on rays around every big basin the deep edge of the chunk's
# water field (bicubic, like water.gdshader) lies within 0.3 m of the collision edge.
func _check_edge(seed_value: int) -> void:
	var layout: RefCounted = arena.layout
	for basin in layout.basins:
		if not basin.big:
			continue
		var center: Vector3 = basin.center
		for ray in 24:
			var direction := Vector3(cos(TAU * ray / 24.0), 0.0, sin(TAU * ray / 24.0))
			# Collision edge: first point where the wall distance turns positive.
			var inside := 0.0
			var outside := float(basin.radius) + 4.0
			if arena.wall_distance(center + direction * outside) <= 0.0:
				continue
			for step in 30:
				var middle := (inside + outside) * 0.5
				if arena.wall_distance(center + direction * middle) < 0.0:
					inside = middle
				else:
					outside = middle
			var edge: Vector3 = center + direction * outside
			var drawn := _drawn_deep(edge)
			edge_errors.append(absf(drawn))
			check(absf(drawn) < 0.3, "Deep edge drawn at the collision edge (seed %d: %.2f m off at %s)" % [seed_value, drawn, edge])


# Deep-edge distance the shader draws at a point: cubic B-spline over the
# chunk's field texture (texel centres = layout cell centres).
func _drawn_deep(point: Vector3) -> float:
	var key := Vector2i(floori(point.x / arena.CELL), floori(point.z / arena.CELL))
	var image: Image = arena.border.water_field(key)
	if image == null:
		return INF
	var step: float = arena.border.FIELD_STEP
	var margin: float = arena.border.FIELD_MARGIN
	var origin: Vector2 = Vector2(key.x * arena.CELL, key.y * arena.CELL) - Vector2.ONE * step * margin
	var u: float = (point.x - origin.x) / step - 0.5
	var v: float = (point.z - origin.y) / step - 0.5
	var iu := floori(u)
	var iv := floori(v)
	var wu := _bspline(u - float(iu))
	var wv := _bspline(v - float(iv))
	var total := 0.0
	for j in 4:
		for i in 4:
			var pixel := image.get_pixel(clampi(iu - 1 + i, 0, image.get_width() - 1), clampi(iv - 1 + j, 0, image.get_height() - 1))
			total += pixel.g * wu[i] * wv[j]
	return total


static func _bspline(t: float) -> PackedFloat32Array:
	var s := 1.0 - t
	return PackedFloat32Array([s * s * s / 6.0, (3.0 * t * t * t - 6.0 * t * t + 4.0) / 6.0, (-3.0 * t * t * t + 3.0 * t * t + 3.0 * t + 1.0) / 6.0, t * t * t / 6.0])


# The chunk at a lake carries one water surface (the water shader) and no
# disc chains; in the Glutsumpf the same surface draws lava.
func _check_render(lava := false) -> void:
	var layout: RefCounted = arena.layout
	var basin: Dictionary = layout.basins[0]
	for candidate in layout.basins:
		if candidate.big:
			basin = candidate
			break
	var center: Vector3 = basin.center
	arena.sync(center)
	arena.finish_rebuild()
	await process_frame
	var key := Vector2i(floori(center.x / arena.CELL), floori(center.z / arena.CELL))
	var chunk: Node3D = arena.chunks.get(key)
	check(chunk != null, "Lake chunk built")
	if chunk == null:
		return
	var surfaces := 0
	var discs := 0
	for child in chunk.get_children():
		if child.name == "Water" and child is MeshInstance3D:
			surfaces += 1
			var material: ShaderMaterial = child.material_override
			check(material != null and material.shader == WATER_SHADER, "Water surface uses water.gdshader")
			if material != null:
				check(bool(material.get_shader_parameter("lava")) == lava, "Lava look only in the Glutsumpf (%s)" % lava)
		var label := String(child.name).to_lower()
		if label.contains("wall water") or label.contains("wall shore") or label.contains("wall crust") or label.contains("wall lava"):
			discs += 1
	check(surfaces == 1, "One water surface per chunk (%d)" % surfaces)
	check(discs == 0, "No disc chains any more (%d)" % discs)


# The horde brood wades slower through the shallows than over dry ground.
func _check_horde() -> void:
	var layout: RefCounted = arena.layout
	var basin: Dictionary = {}
	var spot := Vector3.INF
	for candidate in layout.basins:
		if candidate.big:
			spot = _shallow_spot(layout, candidate)
			if spot.is_finite():
				basin = candidate
				break
	check(spot.is_finite(), "Horde test lake found")
	if not spot.is_finite():
		return
	var center: Vector3 = basin.center
	var out := Vector3(spot.x - center.x, 0.0, spot.z - center.z).normalized()
	var tangent := Vector3(-out.z, 0.0, out.x)
	var horde: Node3D = HORDE_SCRIPT.new()
	scene.add_child(horde)
	horde.setup(scene, scene.get_node("Swarm"), arena)
	var wet := _horde_run(horde, spot, spot + tangent * 14.0 + out * 1.0)
	var dry_start := spot + out * 12.0
	var dry := _horde_run(horde, dry_start, dry_start + tangent * 14.0)
	horde.queue_free()
	await process_frame
	check(wet < dry * 0.85, "Horde brood slower in the shallows (%.2f vs %.2f m)" % [wet, dry])


func _horde_run(horde: Node3D, from: Vector3, target: Vector3) -> float:
	horde.clear()
	horde.spawn_ring(from, 1, 0.1, {"hp": 50.0, "speed": 5.0, "bite": 0.0})
	if horde.count() == 0:
		return 0.0
	horde._pos[0] = from
	horde._vel[0] = Vector3.ZERO
	var points := PackedVector3Array([target])
	for frame in 20:
		horde.step(1.0 / 60.0, points)
	return horde.positions()[0].distance_to(from)
