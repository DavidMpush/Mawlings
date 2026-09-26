extends Node3D

# Short-lived, purely visual ground effects (shockwaves, dust, spawn marks).
# They never touch game state. Etappe 07: every ring of one parent is an
# instance of ONE pooled MultiMesh ("FX rings", one draw call, one shared
# vertex-colour material); finished rings just leave the active list.

const FX_BATCH = preload("res://scripts/fx_batch.gd")
const QUALITY = preload("res://scripts/quality.gd")
const POOL_NAME := "FX rings"
const CAPACITY := 48
const HEIGHT := 0.14

static var shared_torus: TorusMesh
# Quality "effect_density" < 1 thins decorative rings out evenly.
static var _density_credit := 0.0

# {"at": Vector3, "color": Color, "from": float, "to": float, "duration": float, "age": float}
var rings: Array[Dictionary] = []
var batch: MultiMeshInstance3D


static func ring(parent: Node, location: Vector3, tint: Color, start_radius: float, end_radius: float, seconds: float) -> Node3D:
	if parent == null or seconds <= 0.0:
		return null
	var density := float(QUALITY.value("effect_density", 1.0))
	if density < 1.0:
		_density_credit += density
		if _density_credit < 1.0:
			return null
		_density_credit -= 1.0
	var pool: Node3D = parent.get_node_or_null(POOL_NAME)
	if pool == null or pool.is_queued_for_deletion():
		pool = load("res://scripts/fx.gd").new()
		pool.name = POOL_NAME
		parent.add_child(pool)
		# Top level at the origin: ring transforms are world space.
		pool.top_level = true
		pool.transform = Transform3D.IDENTITY
	pool.add_ring(Vector3(location.x, HEIGHT, location.z), tint, start_radius, end_radius, seconds)
	return pool


func _init() -> void:
	if shared_torus == null:
		shared_torus = TorusMesh.new()
		shared_torus.inner_radius = 0.84
		shared_torus.outer_radius = 1.0
		shared_torus.rings = 48
		shared_torus.ring_segments = 6
	batch = FX_BATCH.create(shared_torus, CAPACITY, true, true, "Ring batch")
	add_child(batch)


func add_ring(at: Vector3, tint: Color, from_radius: float, to_radius: float, seconds: float) -> void:
	if rings.size() >= CAPACITY:
		# Pool full: the oldest ring makes room.
		rings.pop_front()
	rings.append({"at": at, "color": tint, "from": from_radius, "to": to_radius, "duration": seconds, "age": 0.0})
	_apply()


func active_count() -> int:
	return rings.size()


func _process(delta: float) -> void:
	if rings.is_empty():
		return
	for index in range(rings.size() - 1, -1, -1):
		rings[index].age += delta
		if rings[index].age >= rings[index].duration:
			rings.remove_at(index)
	_apply()


func _apply() -> void:
	batch.begin()
	for entry in rings:
		var progress := clampf(entry.age / entry.duration, 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - progress, 3.0)
		var radius := lerpf(entry.from, entry.to, eased)
		var tint: Color = entry.color
		var xform := Transform3D(Basis.from_scale(Vector3(radius, 0.35, radius)), entry.at)
		batch.add(xform, Color(tint.r, tint.g, tint.b, tint.a * (1.0 - progress)))
	batch.finish()
