extends RefCounted

# Stage 18c: tall landmarks of the exploration map, visible from afar so they
# lure the player (map_explore.gd `beacons`). Built from the existing props,
# scaled up: a giant tree (upright trunk, root arch at its foot, leaf crown),
# a bone pillar (stacked pale rocks), a glowing mushroom tower, a stone needle.
# Glutsumpf: charred and basalt materials. They live outside the chunks (only a
# handful of meshes), so they stay in the picture before their chunk loads.


static func build(arena: Node3D, parent: Node3D) -> void:
	for child in parent.get_children():
		child.queue_free()
	var layout: RefCounted = arena.layout
	if layout == null or layout.get("beacons") == null:
		return
	var ember: bool = arena._ember_look()
	for mark in layout.beacons:
		var root := Node3D.new()
		root.name = "Beacon %s" % mark.kind
		parent.add_child(root)
		root.position = mark.center
		var yaw: float = float(arena._hash(roundi(mark.center.x), roundi(mark.center.z), 3100) % 628) * 0.01
		match String(mark.kind):
			"giant_tree":
				var wood: Material = arena.char_material if ember else arena.log_material
				_trunk(arena, root, wood, 3.4, 13.0, yaw)
				arena._prop(root, "Tree roots", arena.arch_mesh, arena.arch_base, wood, Vector3.ZERO, arena.ARCH_SIZE * 0.75, yaw)
				if not ember:
					for index in 6:
						var angle := yaw + float(index) * TAU / 6.0
						var leaf: MeshInstance3D = arena._prop(root, "Tree crown", arena.leaf_mesh, arena.leaf_base, arena.leaf_material, Vector3(cos(angle) * 2.2, 0.0, sin(angle) * 2.2), Vector3.ONE * 6.5, angle)
						leaf.position.y += 9.5 + float(index % 2) * 1.6
			"bone_pillar":
				var stone: Material = arena.basalt_material if ember else arena.rock_material
				var height := 0.0
				for index in 4:
					var size := 3.6 - float(index) * 0.6
					var part: MeshInstance3D = arena._prop(root, "Pillar stone", arena.rock_mesh, arena.rock_base, stone, Vector3.ZERO, Vector3(size, size * 1.2, size), yaw + float(index) * 1.3)
					part.position.y += height
					height += size * 1.05
			"mushroom_tower":
				var cap: Material = arena.mushroom_material if ember else _glow_material(arena)
				arena._prop(root, "Mushroom tower", arena.flower_mesh, arena.flower_base, cap, Vector3.ZERO, Vector3.ONE * 8.0, yaw)
			_:
				var needle: Material = arena.basalt_material if ember else arena.rock_material
				arena._prop(root, "Stone needle", arena.rock_mesh, arena.rock_base, needle, Vector3.ZERO, Vector3(3.2, 13.0, 3.0), yaw)
				arena._prop(root, "Needle foot", arena.rock_mesh, arena.rock_base, needle, Vector3(1.6, 0.0, 0.8), Vector3(2.2, 2.0, 2.0), yaw + 1.0)


# Upright piece of the log model (like arena._stump, any material).
static func _trunk(arena: Node3D, root: Node3D, material: Material, diameter: float, height: float, yaw: float) -> void:
	var box: AABB = Transform3D(arena.log_base.basis, Vector3.ZERO) * arena.log_mesh.get_aabb()
	var fit := Basis.from_scale(Vector3(diameter / maxf(box.size.x, 0.01), diameter / maxf(box.size.y, 0.01), height / maxf(box.size.z, 0.01)))
	var base: Transform3D = arena.log_base
	var shape: Basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5) * fit * base.basis
	arena._prop_shape(root, "Giant trunk", arena.log_mesh, material, Vector3.ZERO, shape)


# Teal glowing petal material for the Verdant mushroom tower (cached on the arena).
static func _glow_material(arena: Node3D) -> Material:
	if arena.has_meta("beacon_glow"):
		return arena.get_meta("beacon_glow")
	var material: ShaderMaterial = arena._prop_material(1.35, 1.25, 0.3, 0.5)
	material.set_shader_parameter("recolor_dark", Color("1d6f7a"))
	material.set_shader_parameter("recolor_light", Color("8ff7ea"))
	material.set_shader_parameter("recolor_amount", 0.95)
	material.set_shader_parameter("rim_color", Color("c9fff6"))
	arena.set_meta("beacon_glow", material)
	return material
