extends Node3D

# An endless, deterministic layout. Only nearby visual chunks exist; obstacle
# positions are computed from coordinates, so moving away never changes them.
const CELL := 28.0
const VISIBLE_RADIUS := 1
const OBSTACLE_RADIUS := 1.85
var chunks: Dictionary = {}
var ground_material: StandardMaterial3D
var path_material: StandardMaterial3D
var stone_material: StandardMaterial3D
var moss_material: StandardMaterial3D
var leaf_material: StandardMaterial3D
var water_material: StandardMaterial3D

func _ready() -> void:
	ground_material = _material(Color("647c56"))
	path_material = _material(Color("ac9866"))
	path_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	stone_material = _material(Color("7b8879"))
	moss_material = _material(Color("456e4c"))
	leaf_material = _material(Color("59a358"))
	water_material = _material(Color("3e91a0"))
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

func safe_spawn(location: Vector3, radius: float) -> Vector3:
	return _push_out(location, radius)

func _make_chunk(key: Vector2i) -> Node3D:
	var chunk := Node3D.new()
	chunk.name = "Jungle %d %d" % [key.x, key.y]
	chunk.position = Vector3(key.x * CELL, 0, key.y * CELL)
	add_child(chunk)
	var ground := PlaneMesh.new()
	ground.size = Vector2(CELL, CELL)
	_part(chunk, "Open ground", ground, ground_material, Vector3(CELL * 0.5, -0.02, CELL * 0.5))
	var lane := _part(chunk, "Broad trail", _trail_mesh(key), path_material, Vector3.ZERO)
	lane.transparency = 0.0
	for index in 6:
		var x := 2.0 + float(_hash(key.x, key.y, index + 30) % 24)
		var z := 2.0 + float(_hash(key.x, key.y, index + 60) % 24)
		var patch := CylinderMesh.new()
		patch.top_radius = 0.5
		patch.bottom_radius = 0.5
		patch.height = 0.018
		var mark := _part(chunk, "Low leaf cover", patch, moss_material, Vector3(x, 0.003, z))
		mark.scale = Vector3(1.4, 1, 0.65)
	for center in obstacle_centers(key):
		var local := center - chunk.position
		_boulder(chunk, local)
	# A rare water landmark is flat and traversable; the route stays open.
	if _hash(key.x, key.y, 13) % 5 == 0:
		var pool := CylinderMesh.new()
		pool.top_radius = 1.1
		pool.bottom_radius = 1.1
		pool.height = 0.025
		var water := _part(chunk, "Shallow pool", pool, water_material, Vector3(4, 0.015, 22))
		water.scale = Vector3(1.8, 1, 1.1)
	return chunk

func _trail_mesh(key: Vector2i) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for step_index in 8:
		var z0 := float(step_index) * CELL / 8.0
		var z1 := float(step_index + 1) * CELL / 8.0
		var center0 := 14.0 + 3.2 * sin((key.y * CELL + z0) * 0.09 + key.x * 0.7)
		var center1 := 14.0 + 3.2 * sin((key.y * CELL + z1) * 0.09 + key.x * 0.7)
		var left0 := Vector3(center0 - 3.6, 0.006, z0)
		var right0 := Vector3(center0 + 3.6, 0.006, z0)
		var left1 := Vector3(center1 - 3.6, 0.006, z1)
		var right1 := Vector3(center1 + 3.6, 0.006, z1)
		for point in [left0, right0, left1, right0, right1, left1]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(point)
	return surface.commit()

func _boulder(chunk: Node3D, location: Vector3) -> void:
	var foot := CylinderMesh.new()
	foot.top_radius = OBSTACLE_RADIUS
	foot.bottom_radius = OBSTACLE_RADIUS + 0.25
	foot.height = 0.35
	_part(chunk, "Stone footprint", foot, moss_material, location + Vector3(0, 0.16, 0))
	var rock := SphereMesh.new()
	rock.radius = 1.65
	rock.height = 2.2
	var body := _part(chunk, "Low stone", rock, stone_material, location + Vector3(0, 0.53, 0))
	body.scale = Vector3(1.0, 0.55, 0.95)
	for side in [-1.0, 1.0]:
		var frond := SphereMesh.new()
		frond.radius = 0.75
		frond.height = 0.28
		var leaf := _part(chunk, "Broad leaf", frond, leaf_material, location + Vector3(side * 1.05, 0.48, 0.45))
		leaf.rotation.y = side * 0.4
	var bright := SphereMesh.new()
	bright.radius = 0.22
	bright.height = 0.25
	for offset in [Vector3(-1.0, 0.68, -0.55), Vector3(0.85, 0.75, 0.6)]:
		_part(chunk, "Leaf tip", bright, leaf_material, location + offset)

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


