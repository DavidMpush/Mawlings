extends Node3D

# An endless, deterministic layout. Only nearby visual chunks exist; obstacle
# positions are computed from coordinates, so moving away never changes them.
const CELL := 28.0
const VISIBLE_RADIUS := 1
const OBSTACLE_RADIUS := 1.85
const CREATURE_SHADER = preload("res://shaders/creature.gdshader")
const ROCK_SCENE = preload("res://assets/gameplay/props/Rock_game.glb")
const LEAF_SCENE = preload("res://assets/gameplay/props/Leaf_game.glb")
const TRAIL_HALF_WIDTH := 3.6
const TRAIL_EDGE_WIDTH := 4.5
var chunks: Dictionary = {}
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
# Shared geometry: every chunk only adds instances of these.
var rock_mesh: Mesh
var rock_base: Transform3D
var leaf_mesh: Mesh
var leaf_base: Transform3D
var ground_mesh: PlaneMesh
var patch_mesh: CylinderMesh
var plinth_mesh: CylinderMesh
var pool_mesh: CylinderMesh
var shore_mesh: CylinderMesh

func _ready() -> void:
	ground_material = _material(Color("80a04c"))
	path_material = _material(Color("d4b377"))
	path_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	path_edge_material = _material(Color("aeaa62"))
	path_edge_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for tint in [Color("88a852"), Color("718f40"), Color("7a9844")]:
		moss_materials.append(_material(tint))
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
	ground_mesh = PlaneMesh.new()
	ground_mesh.size = Vector2(CELL, CELL)
	patch_mesh = _disc(0.5, 0.5, 0.018)
	plinth_mesh = _disc(OBSTACLE_RADIUS + 0.1, OBSTACLE_RADIUS + 0.45, 0.06)
	pool_mesh = _disc(1.1, 1.1, 0.025)
	shore_mesh = _disc(1.45, 1.55, 0.02)
	sync(Vector3.ZERO)

func sync(position: Vector3) -> void:
	var center := _cell(position)
	var wanted: Dictionary = {}
	for x in range(center.x - VISIBLE_RADIUS, center.x + VISIBLE_RADIUS + 1):
		for z in range(center.y - VISIBLE_RADIUS, center.y + VISIBLE_RADIUS + 1):
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

func obstacle_centers(key: Vector2i) -> Array[Vector3]:
	var origin := Vector3(key.x * CELL, 0, key.y * CELL)
	var flip := 1.0 if _hash(key.x, key.y, 4) % 2 == 0 else -1.0
	var shift := float(_hash(key.x, key.y, 8) % 5 - 2) * 0.75
	return [origin + Vector3(-8.6, 0, flip * 7.6 + shift), origin + Vector3(8.6, 0, -flip * 7.6 + shift)]

func _hash(x: int, z: int, salt: int) -> int:
	var n := x * 374761393 + z * 668265263 + salt * 144269
	n = (n ^ (n >> 13)) * 1274126177
	return abs(n ^ (n >> 16))

func resolve_motion(start: Vector3, motion: Vector3, radius: float) -> Vector3:
	var result := start + motion
	# Resolve X and Z separately so the joystick naturally slides along stone.
	result.x = _push_out(Vector3(result.x, 0, start.z), radius).x
	result.z = _push_out(Vector3(result.x, 0, result.z), radius).z
	return result

func _push_out(point: Vector3, radius: float) -> Vector3:
	var middle := _cell(point)
	for x in range(middle.x - 1, middle.x + 2):
		for z in range(middle.y - 1, middle.y + 2):
			for center in obstacle_centers(Vector2i(x, z)):
				var offset := Vector2(point.x - center.x, point.z - center.z)
				var minimum := OBSTACLE_RADIUS + radius
				if offset.length_squared() < minimum * minimum:
					var normal := offset.normalized() if offset.length_squared() > 0.0001 else Vector2.RIGHT
					point.x = center.x + normal.x * minimum
					point.z = center.z + normal.y * minimum
	return point

func is_open(location: Vector3, radius: float) -> bool:
	var middle := _cell(location)
	for x in range(middle.x - 1, middle.x + 2):
		for z in range(middle.y - 1, middle.y + 2):
			for center in obstacle_centers(Vector2i(x, z)):
				if location.distance_to(center) < OBSTACLE_RADIUS + radius:
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
			for center in obstacle_centers(Vector2i(x, z)):
				var offset := center - start
				var ahead := offset.dot(forward)
				var cross := forward.x * offset.z - forward.z * offset.x
				if ahead > 0 and ahead < 4.5 and absf(cross) < OBSTACLE_RADIUS + radius + 0.5 and ahead < best:
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
	_part(chunk, "Open ground", ground_mesh, ground_material, Vector3(CELL * 0.5, -0.02, CELL * 0.5))
	_part(chunk, "Trail edge", _trail_mesh(key, TRAIL_EDGE_WIDTH, 0.003), path_edge_material, Vector3.ZERO)
	_part(chunk, "Broad trail", _trail_mesh(key, TRAIL_HALF_WIDTH, 0.007), path_material, Vector3.ZERO)
	# Calm ground variation: soft moss tints, a few sand/earth spots, small pebbles.
	for index in 6:
		var spot := Vector3(2.0 + float(_hash(key.x, key.y, index + 30) % 24), 0.001, 2.0 + float(_hash(key.x, key.y, index + 60) % 24))
		if _near_trail(chunk.position + spot, 1.0):
			continue
		var tint := moss_materials[_hash(key.x, key.y, index + 90) % moss_materials.size()]
		var moss := _part(chunk, "Low leaf cover", patch_mesh, tint, spot)
		var size := 1.3 + float(_hash(key.x, key.y, index + 120) % 5) * 0.3
		moss.scale = Vector3(size * 1.5, 1, size)
		moss.rotation.y = float(_hash(key.x, key.y, index + 150) % 628) * 0.01
	for index in 3:
		var spot := Vector3(2.0 + float(_hash(key.x, key.y, index + 180) % 24), 0.002, 2.0 + float(_hash(key.x, key.y, index + 210) % 24))
		if _near_trail(chunk.position + spot, 1.5):
			continue
		var dirt := _part(chunk, "Sand patch", patch_mesh, sand_material if index != 2 else earth_material, spot)
		var size := 1.2 + float(_hash(key.x, key.y, index + 240) % 4) * 0.3
		dirt.scale = Vector3(size * 1.4, 1, size)
		dirt.rotation.y = float(_hash(key.x, key.y, index + 270) % 628) * 0.01
	for index in 5:
		var spot := Vector3(1.0 + float(_hash(key.x, key.y, index + 300) % 26), 0, 1.0 + float(_hash(key.x, key.y, index + 330) % 26))
		var size := 0.32 + float(_hash(key.x, key.y, index + 360) % 4) * 0.07
		_prop(chunk, "Pebble", rock_mesh, rock_base, rock_material, spot, Vector3(size, size * 0.8, size), float(_hash(key.x, key.y, index + 390) % 628) * 0.01)
	for center in obstacle_centers(key):
		_boulder(chunk, center)
	# Scattered leaf clumps at the edges of the open ground: never on the trail,
	# never in the middle of the chunk, never inside a stone footprint.
	var placed := 0
	var wanted := 3 + _hash(key.x, key.y, 400) % 3
	for index in 14:
		if placed >= wanted:
			break
		var local := Vector3(1.0 + float(_hash(key.x, key.y, index + 410) % 26), 0, 1.0 + float(_hash(key.x, key.y, index + 440) % 26))
		var world := chunk.position + local
		if local.distance_to(Vector3(CELL * 0.5, 0, CELL * 0.5)) < 7.0 or _near_trail(world, 1.2) or not is_open(world, 0.6):
			continue
		var size := 1.05 + float(_hash(key.x, key.y, index + 470) % 5) * 0.1
		_prop(chunk, "Leaf clump", leaf_mesh, leaf_base, leaf_material, local, Vector3.ONE * size, float(_hash(key.x, key.y, index + 500) % 628) * 0.01)
		placed += 1
	# A rare water landmark is flat and traversable; the route stays open.
	if _hash(key.x, key.y, 13) % 5 == 0:
		var shore := _part(chunk, "Pool shore", shore_mesh, shore_material, Vector3(4, 0.01, 22))
		shore.scale = Vector3(1.8, 1, 1.1)
		var water := _part(chunk, "Shallow pool", pool_mesh, water_material, Vector3(4, 0.02, 22))
		water.scale = Vector3(1.8, 1, 1.1)
	return chunk

func _trail_center(key: Vector2i, local_z: float) -> float:
	return 14.0 + 3.2 * sin((key.y * CELL + local_z) * 0.09 + key.x * 0.7)

func _near_trail(world: Vector3, margin: float) -> bool:
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

func _boulder(chunk: Node3D, center: Vector3) -> void:
	var location := center - chunk.position
	var roll := _hash(roundi(center.x * 10.0), roundi(center.z * 10.0), 7)
	_part(chunk, "Stone footprint", plinth_mesh, plinth_material, location + Vector3(0, 0.02, 0))
	var size := 0.92 + float(roll % 9) * 0.02
	var yaw := float((roll >> 4) % 628) * 0.01
	_prop(chunk, "Low stone", rock_mesh, rock_base, rock_material, location, Vector3(3.9, 3.2, 3.6) * size, yaw)
	var count := 2 + (roll >> 8) % 2
	for index in count:
		var angle := yaw + float(index) * TAU / float(count) + float((roll >> (10 + index * 3)) % 7) * 0.12
		var foot := location + Vector3(cos(angle), 0, sin(angle)) * (OBSTACLE_RADIUS + 0.1)
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


