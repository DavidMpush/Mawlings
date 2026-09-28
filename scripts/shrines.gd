extends Node3D

# Etappe 17 Welle 2 – Schreine (wie die Charge-Schreine in Megabonk).
#
# Steinkreise an arena.poi_slots("shrine"): Steht die Schwarm-Mitte im Ring,
# lädt der Schrein in CHARGE_SECONDS auf; Verlassen pausiert (die Ladung
# bleibt). Voll: eine Werte-Wahl 1 aus 3, mindestens selten, über den
# vorhandenen Level-up-Screen (evolution.open_shrine(); kostet keine DNA, zählt
# kein Level). Jeder Schrein wirkt einmal. Ohne Plätze (Seed 0) gibt es
# FALLBACK Schreine auf offenem Boden. Logik und Animation laufen nur in step().

const FX = preload("res://scripts/fx.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")

const CHARGE_SECONDS := 4.0
const RADIUS := 3.4
const SEGMENTS := 16
const FALLBACK := 2

## {at, charge (0..1), done, pending, node, crystal, segments: Array[MeshInstance3D], lit}
var shrines: Array[Dictionary] = []
var completed := 0
var world: Node3D
var arena: Node3D
var _layout: RefCounted
var _layout_known := false
var _time := 0.0
static var _meshes := {}
static var _materials := {}


func setup(world_node: Node3D, arena_node: Node3D) -> void:
	world = world_node
	arena = arena_node
	_rebuild()


func _rebuild() -> void:
	_layout = arena.get("layout") if arena != null else null
	_layout_known = true
	for entry in shrines:
		if entry.node != null:
			entry.node.queue_free()
	shrines.clear()
	var slots: Array[Vector3] = []
	if arena != null and arena.has_method("poi_slots"):
		slots = arena.poi_slots("shrine")
	if slots.is_empty():
		var centre: Vector3 = arena.map_center() if arena != null and arena.has_method("map_center") else Vector3.ZERO
		for index in FALLBACK:
			var angle := float(index) * PI + 0.5
			slots.append(centre + Vector3(cos(angle), 0.0, sin(angle)) * 38.0)
	for at in slots:
		if arena != null and arena.has_method("safe_spawn"):
			at = arena.safe_spawn(at, 2.0)
		spawn(at)


## Adds a shrine at `at` (tests, captures).
func spawn(at: Vector3) -> Dictionary:
	at.y = 0.0
	var entry := {"at": at, "charge": 0.0, "done": false, "pending": false, "lit": -1}
	_build(entry)
	shrines.append(entry)
	return entry


func open_count() -> int:
	var count := 0
	for entry in shrines:
		if not entry.done:
			count += 1
	return count


## Nearest unused shrine within `reach` ({} = none).
func nearest(point: Vector3, reach: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := reach
	for entry in shrines:
		if entry.done:
			continue
		var d := Vector2(entry.at.x - point.x, entry.at.z - point.z).length()
		if d < best_d:
			best_d = d
			best = entry
	return best


## Charges the shrine the swarm centre stands in; a full one opens the choice.
## Returns true when a choice opened this step.
func step(delta: float, centre: Vector3) -> bool:
	_time += delta
	if arena != null and (arena.get("layout") != _layout or not _layout_known):
		_rebuild()
	var opened := false
	for entry in shrines:
		var near := absf(entry.at.x - centre.x) < 30.0 and absf(entry.at.z - centre.z) < 30.0
		if entry.done:
			continue
		# A full shrine waits until no other choice is open.
		if entry.pending:
			opened = _fire(entry) or opened
			continue
		var inside := Vector2(entry.at.x - centre.x, entry.at.z - centre.z).length() <= RADIUS
		if inside:
			entry.charge = minf(1.0, float(entry.charge) + delta / CHARGE_SECONDS)
			_charge_tick(entry)
			if float(entry.charge) >= 1.0:
				entry.pending = true
				opened = _fire(entry) or opened
		if near:
			_animate(entry, inside)
	return opened


func _fire(entry: Dictionary) -> bool:
	var evo: RefCounted = world.evolution
	if not evo.open_shrine():
		# Another choice is open (or every stat is maxed: then the shrine is spent).
		if evo.complete():
			_finish(entry)
		return false
	_finish(entry)
	return true


func _finish(entry: Dictionary) -> void:
	entry.pending = false
	entry.done = true
	entry.charge = 1.0
	completed += 1
	var tone := UiStyle.brawl_tone("special")
	FX.ring(world, entry.at, Color(tone["light"], 0.9), 0.5, RADIUS * 2.2, 0.6)
	FX.ring(world, entry.at, Color(Color.WHITE, 0.6), 0.3, RADIUS * 1.2, 0.4)
	if world.has_method("_sfx"):
		world._sfx("shrine_done", 60)
	if entry.crystal != null:
		entry.crystal.visible = false
	_light(entry, SEGMENTS, true)


# Etappe 23: while the swarm charges a shrine, a glass tick every eighth of
# the charge, one step higher each time (a pentatonic run up to "shrine_done").
const TICK_STEPS := [0, 2, 4, 7, 9, 12, 14, 16]


func _charge_tick(entry: Dictionary) -> void:
	var step := mini(TICK_STEPS.size() - 1, int(floor(float(entry.charge) * TICK_STEPS.size())))
	if step <= int(entry.get("tick", -1)):
		return
	entry["tick"] = step
	var sfx: Node = world._sfx_node() if world != null and world.has_method("_sfx_node") else null
	if sfx != null and sfx.has_method("play"):
		sfx.play("shrine_tick", 0.0, 0.0, pow(2.0, float(TICK_STEPS[step]) / 12.0))


## Charges a shrine to full at once (tests/captures). Returns true when the choice opened.
func charge_now(entry: Dictionary) -> bool:
	entry.charge = 1.0
	entry.pending = true
	return _fire(entry)


## Minimap marks: [{at, done, charge}].
func map_marks() -> Array:
	var out: Array = []
	for entry in shrines:
		out.append({"at": entry.at, "done": entry.done, "charge": float(entry.charge)})
	return out


## HUD: charge labels over shrines near the swarm (screen space).
func hud_state(camera: Camera3D, centre: Vector3) -> Array:
	var out: Array = []
	if camera == null:
		return out
	for entry in shrines:
		if entry.done:
			continue
		var flat := Vector2(entry.at.x - centre.x, entry.at.z - centre.z).length()
		if flat > 16.0:
			continue
		var top: Vector3 = entry.at + Vector3(0, 4.4, -RADIUS * 0.6)
		if camera.is_position_behind(top):
			continue
		out.append({"screen": camera.unproject_position(top), "charge": float(entry.charge), "inside": flat <= RADIUS})
	return out


# ---------------------------------------------------------------- look

static func _mesh(key: String) -> Mesh:
	if _meshes.has(key):
		return _meshes[key]
	var mesh: Mesh
	match key:
		"base":
			var base := CylinderMesh.new()
			base.top_radius = 1.0
			base.bottom_radius = 1.0
			base.height = 0.12
			base.radial_segments = 40
			base.rings = 1
			mesh = base
		"ring":
			var ring := TorusMesh.new()
			ring.inner_radius = 0.93
			ring.outer_radius = 1.0
			ring.rings = 64
			ring.ring_segments = 4
			mesh = ring
		"stone":
			var stone := BoxMesh.new()
			stone.size = Vector3(0.7, 1.9, 0.5)
			mesh = stone
		"cap":
			var cap := BoxMesh.new()
			cap.size = Vector3(0.9, 0.22, 0.65)
			mesh = cap
		"segment":
			var segment := BoxMesh.new()
			segment.size = Vector3(0.9, 0.08, 0.34)
			mesh = segment
		"crystal":
			var crystal := CylinderMesh.new()
			crystal.top_radius = 0.0
			crystal.bottom_radius = 0.42
			crystal.height = 1.0
			crystal.radial_segments = 5
			crystal.rings = 1
			mesh = crystal
		"plinth":
			var plinth := CylinderMesh.new()
			plinth.top_radius = 0.55
			plinth.bottom_radius = 0.75
			plinth.height = 0.5
			plinth.radial_segments = 8
			plinth.rings = 1
			mesh = plinth
	_meshes[key] = mesh
	return mesh


static func _material(key: String, color: Color, glow: float = 0.0, unshaded := false, transparent := false) -> StandardMaterial3D:
	var id := "%s:%s:%.2f:%s:%s" % [key, color.to_html(true), glow, unshaded, transparent]
	if _materials.has(id):
		return _materials[id]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if not unshaded:
		material.rim_enabled = true
		material.rim = 0.4
	_materials[id] = material
	return material


static func _piece(parent: Node3D, mesh: Mesh, material: Material, at: Vector3, basis := Basis.IDENTITY) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.transform = Transform3D(basis, at)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part


# A worn stone circle: flat pale base, four standing stones with caps, a violet
# crystal on a plinth in the middle and SEGMENTS charge tiles around the rim
# that light up one by one.
func _build(entry: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Shrine"
	root.position = entry.at
	add_child(root)
	var special := UiStyle.brawl_tone("special")
	var stone := _material("stone", Color("a8a3b8"))
	_piece(root, _mesh("base"), _material("base", Color(special["dark"], 0.35), 0.0, true, true), Vector3(0, 0.03, 0), Basis.from_scale(Vector3(RADIUS, 1.0, RADIUS)))
	_piece(root, _mesh("ring"), _material("rim", Color(special["light"], 0.7), 0.0, true, true), Vector3(0, 0.08, 0), Basis.from_scale(Vector3(RADIUS, 0.3, RADIUS)))
	for i in 4:
		var angle := TAU * float(i) / 4.0 + PI * 0.25
		var at := Vector3(cos(angle), 0.0, sin(angle)) * (RADIUS + 0.55)
		var yaw := Basis(Vector3.UP, -angle + PI * 0.5)
		_piece(root, _mesh("stone"), stone, at + Vector3(0, 0.95, 0), yaw * Basis(Vector3.FORWARD, 0.06 * float(i % 2 * 2 - 1)))
		_piece(root, _mesh("cap"), stone, at + Vector3(0, 1.98, 0), yaw)
	_piece(root, _mesh("plinth"), stone, Vector3(0, 0.25, 0))
	var crystal := _piece(root, _mesh("crystal"), _material("crystal", special["face"], 1.4), Vector3(0, 1.1, 0), Basis.from_scale(Vector3(1.0, 1.25, 1.0)))
	var segments: Array = []
	var off := _material("seg_off", Color(special["dark"], 0.6), 0.0, true, true)
	for i in SEGMENTS:
		var angle := TAU * float(i) / float(SEGMENTS)
		var at := Vector3(cos(angle), 0.0, sin(angle)) * (RADIUS - 0.45) + Vector3(0, 0.1, 0)
		segments.append(_piece(root, _mesh("segment"), off, at, Basis(Vector3.UP, -angle + PI * 0.5)))
	entry["node"] = root
	entry["crystal"] = crystal
	entry["segments"] = segments


func _light(entry: Dictionary, count: int, done: bool = false) -> void:
	if int(entry.lit) == count and not done:
		return
	entry.lit = count
	var special := UiStyle.brawl_tone("special")
	var on := _material("seg_on", special["light"], 0.0, true)
	var spent := _material("seg_spent", Color(UiStyle.brawl_tone("neutral")["dark"], 0.7), 0.0, true, true)
	var off := _material("seg_off", Color(special["dark"], 0.6), 0.0, true, true)
	for i in (entry.segments as Array).size():
		var part: MeshInstance3D = entry.segments[i]
		part.material_override = spent if done else (on if i < count else off)


func _animate(entry: Dictionary, inside: bool) -> void:
	_light(entry, int(floor(float(entry.charge) * SEGMENTS + 0.001)))
	var crystal: MeshInstance3D = entry.crystal
	if crystal == null:
		return
	var charge := float(entry.charge)
	crystal.position.y = 1.1 + 0.12 * sin(_time * 2.0) + 0.3 * charge
	crystal.rotation.y = _time * (0.8 + (3.0 if inside else 0.0))
	var s := 1.0 + 0.25 * charge + (0.05 * sin(_time * 14.0) if inside else 0.0)
	crystal.scale = Vector3(s, 1.25 * s, s)
