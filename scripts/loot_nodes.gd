extends Node3D

# Stage 18c: Bernsteinknollen - breakable amber nodes strewn over the
# exploration map (map_explore.gd loot_points, like Megabonk's pots). One touch
# of any Mawling breaks a node: it bursts into Bernstein coins and DNA (better
# the deeper in the land and the more dangerous the zone: tier 0..2). Etappe 17
# Welle 2: no biomass, power-ups or relics from nodes (signal `bonus` stays for
# compatibility and is no longer emitted). Nodes stay until broken (resource rule); a new map
# (seed, migration) brings new nodes, a restart restores them all.
# Drawn as one MultiMesh per tier (small / medium / big drop model), no node
# per knot; only nodes near the swarm are tested.

signal bonus(kind: String, at: Vector3)

const TUNING = preload("res://scripts/tuning.gd")

const MODELS := [
	preload("res://assets/gameplay/props/SmallDrop_game.glb"),
	preload("res://assets/gameplay/props/MediumDrop_game.glb"),
	preload("res://assets/gameplay/props/BigDrop_game.glb"),
]
const SIZE := [1.5, 1.9, 2.4]
# Crystal content per tier: [biomass, dna, loot rank].
const CONTENT := [[3.0, 8, "normal"], [6.0, 16, "mini"], [11.0, 30, "boss"]]
const BREAK_RANGE := [0.85, 1.0, 1.2]
const CHECK_RANGE := 14.0

var world: Node3D
var arena: Node3D
var points: Array[Vector4] = []
var alive := PackedByteArray()
var broken := 0
var _layout: RefCounted
var _views: Array[MultiMeshInstance3D] = []
var _slot := PackedInt32Array()
var _rng := RandomNumberGenerator.new()


func setup(world_node: Node3D, arena_node: Node3D) -> void:
	world = world_node
	arena = arena_node
	_rebuild()


# Warm amber, brighter and glowing more for the better tiers.
static func _amber(tier: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = [Color("e89a2e"), Color("f2b640"), Color("ffd35a")][tier]
	material.roughness = 0.3
	material.metallic_specular = 0.7
	material.emission_enabled = true
	material.emission = [Color("7a3a06"), Color("a8580c"), Color("d88a14")][tier]
	material.rim_enabled = true
	material.rim = 0.6
	return material


## Nodes still standing.
func count() -> int:
	return alive.count(1)


func _rebuild() -> void:
	for view in _views:
		view.queue_free()
	_views.clear()
	points.clear()
	alive = PackedByteArray()
	_layout = arena.layout if arena != null else null
	if _layout == null or _layout.get("loot_points") == null:
		return
	points = (_layout.loot_points as Array[Vector4]).duplicate()
	alive.resize(points.size())
	alive.fill(1)
	_rng.seed = hash(["amber", int(arena.world_seed)])
	_slot.resize(points.size())
	for tier in MODELS.size():
		var sample: Node3D = MODELS[tier].instantiate()
		var piece: MeshInstance3D = sample.find_children("*", "MeshInstance3D", true, false)[0]
		var base := Transform3D.IDENTITY
		var node: Node = piece
		while node != sample and node is Node3D:
			base = (node as Node3D).transform * base
			node = node.get_parent()
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = piece.mesh
		var own: Array[int] = []
		for index in points.size():
			if int(points[index].w) == tier:
				own.append(index)
		multimesh.instance_count = own.size()
		var box: AABB = base * piece.mesh.get_aabb()
		for slot in own.size():
			var index: int = own[slot]
			_slot[index] = slot
			var yaw := float(arena._hash(roundi(points[index].x * 10.0), roundi(points[index].z * 10.0), 3200) % 628) * 0.01
			var scale: float = SIZE[tier] / maxf(0.01, maxf(box.size.x, box.size.z))
			var shape := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3.ONE * scale) * base.basis
			var placed := Transform3D(shape, Vector3.ZERO)
			var rest: AABB = placed * piece.mesh.get_aabb()
			placed.origin = Vector3(points[index].x - rest.get_center().x, -rest.position.y, points[index].z - rest.get_center().z)
			multimesh.set_instance_transform(slot, placed)
		var view := MultiMeshInstance3D.new()
		view.name = "Amber nodes %d" % tier
		view.multimesh = multimesh
		view.material_override = _amber(tier)
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(view)
		_views.append(view)
		sample.free()


## Breaks every node a Mawling touches; returns how many broke this step.
func step(centre: Vector3, unit_points: PackedVector3Array) -> int:
	if arena != null and arena.layout != _layout:
		_rebuild()
	var hits := 0
	for index in points.size():
		if alive[index] == 0:
			continue
		var node := points[index]
		if absf(node.x - centre.x) > CHECK_RANGE or absf(node.z - centre.z) > CHECK_RANGE:
			continue
		var reach: float = BREAK_RANGE[int(node.w)]
		var touched := false
		for point in unit_points:
			if absf(point.x - node.x) < reach and absf(point.z - node.z) < reach:
				touched = true
				break
		if touched:
			_break(index)
			hits += 1
	return hits


func _break(index: int) -> void:
	alive[index] = 0
	broken += 1
	var node := points[index]
	var tier := int(node.w)
	var at := Vector3(node.x, 0.0, node.z)
	var view := _views[tier]
	view.multimesh.set_instance_transform(_slot[index], Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), at))
	var content: Array = CONTENT[tier]
	if world != null and world.has_method("drop_loot"):
		# Etappe 17 Welle 2 (Nutzer): the open world gives only coins and XP - an
		# amber node bursts into Bernstein (TUNING.AMBER_NODE by tier) and DNA, no
		# biomass (that comes from kills), no power-ups, no relics (cocoons).
		world.drop_loot(at, 0.0, int(content[1]), String(content[2]), int(TUNING.AMBER_NODE[tier]))
