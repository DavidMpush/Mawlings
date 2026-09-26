extends Node3D

# Brutnest (stage 06): a round zone of NEST_RADIUS metres. The share of visible
# Mawlings inside fills it; progress stays when the swarm leaves. HuntWorld turns
# a full nest into a clutch of ordinary corpses (resource rule) plus DNA.
# Logic and animation run only in fill()/animate(), called from HuntWorld.step(),
# so pause and mutation choice freeze the nest.

const TUNING = preload("res://scripts/tuning.gd")
const UI_ICONS = preload("res://scripts/ui/ui_icons.gd")
const FX_BATCH = preload("res://scripts/fx_batch.gd")
static var _claw_meshes := {}
const CYAN := Color("3fe6d8")
const BONE := Color("efe2c0")
const TWIG := Color("6b4a2f")
const EGG := Color("bff5ec")
const BAR_WIDTH := 2.8

var radius: float = TUNING.NEST_RADIUS
var progress := 0.0
var complete := false
var inside_share := 0.0
var _time := 0.0
var _fill_disc: MeshInstance3D
var _edge: MeshInstance3D
var _bar_fill: MeshInstance3D
var _eggs: Array[MeshInstance3D] = []
var _egg_material: StandardMaterial3D
var _edge_material: StandardMaterial3D
var _fill_material: StandardMaterial3D


func _ready() -> void:
	var zone_material := _flat(Color(CYAN, 0.10))
	var zone := CylinderMesh.new()
	zone.top_radius = radius
	zone.bottom_radius = radius
	zone.height = 0.02
	zone.radial_segments = 48
	_part(self, zone, zone_material, Vector3(0, 0.03, 0))
	_fill_material = _flat(Color(CYAN, 0.26))
	_fill_disc = _part(self, zone, _fill_material, Vector3(0, 0.045, 0))
	_fill_disc.scale = Vector3(0.001, 1.0, 0.001)
	var ring := TorusMesh.new()
	ring.inner_radius = radius - 0.16
	ring.outer_radius = radius
	ring.rings = 64
	ring.ring_segments = 4
	_edge_material = _flat(Color(CYAN, 0.85))
	_edge = _part(self, ring, _edge_material, Vector3(0, 0.06, 0))
	_edge.scale = Vector3(1.0, 0.25, 1.0)
	# Bone claws around the rim read as "a place" rather than an attack ring.
	# Etappe 07: all twelve claws are one merged mesh (one draw call).
	var bone: Material = FX_BATCH.shared_material(BONE, false, false, 0.7)
	_part(self, _claw_ring(radius), bone, Vector3.ZERO)
	# Twig mound with a glowing clutch of eggs.
	var twig: Material = FX_BATCH.shared_material(TWIG)
	var mound := TorusMesh.new()
	mound.inner_radius = 0.55
	mound.outer_radius = 1.35
	mound.rings = 20
	mound.ring_segments = 10
	var mound_part := _part(self, mound, twig, Vector3(0, 0.16, 0))
	mound_part.scale = Vector3(1.0, 0.55, 1.0)
	var moss: Material = FX_BATCH.shared_material(Color("3d5a2c"))
	var bed := CylinderMesh.new()
	bed.top_radius = 0.75
	bed.bottom_radius = 0.9
	bed.height = 0.14
	bed.radial_segments = 20
	bed.rings = 1
	_part(self, bed, moss, Vector3(0, 0.07, 0))
	_egg_material = StandardMaterial3D.new()
	_egg_material.albedo_color = EGG
	_egg_material.roughness = 0.35
	_egg_material.emission_enabled = true
	_egg_material.emission = CYAN
	_egg_material.emission_energy_multiplier = 0.2
	var egg := SphereMesh.new()
	egg.radius = 0.26
	egg.height = 0.62
	egg.radial_segments = 12
	egg.rings = 6
	var spots := [Vector3(0, 0.36, 0), Vector3(0.38, 0.3, 0.12), Vector3(-0.33, 0.3, 0.2), Vector3(0.1, 0.3, -0.38), Vector3(-0.2, 0.3, -0.3)]
	for index in spots.size():
		var part := _part(self, egg, _egg_material, spots[index])
		part.rotation = Vector3(0.18 * sin(index * 1.7), 0.0, 0.2 * cos(index * 2.3))
		_eggs.append(part)
	# World fill bar and brood icon above the clutch.
	var track := BoxMesh.new()
	track.size = Vector3(BAR_WIDTH + 0.14, 0.06, 0.34)
	var dark := _flat(Color("0c1d17"), false)
	_part(self, track, dark, Vector3(0, 2.3, 0))
	var fill := BoxMesh.new()
	fill.size = Vector3(BAR_WIDTH, 0.08, 0.24)
	_bar_fill = _part(self, fill, _flat(CYAN, false), Vector3(0, 2.32, 0))
	var icon := UI_ICONS.texture("brood")
	if icon != null:
		var sprite := Sprite3D.new()
		sprite.name = "Icon"
		sprite.texture = icon
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.pixel_size = 1.1 / float(icon.get_width())
		sprite.position = Vector3(0, 3.1, 0)
		sprite.no_depth_test = true
		sprite.render_priority = 10
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sprite)
	animate(0.0, false)


func contains(point: Vector3) -> bool:
	return Vector2(point.x - position.x, point.z - position.z).length() <= radius


# Share of the given world points inside the zone (0..1).
func hit_fraction(points: PackedVector3Array) -> float:
	if points.is_empty():
		return 0.0
	var inside := 0
	for point in points:
		if contains(point):
			inside += 1
	return float(inside) / float(points.size())


# Fill speed factor for a swarm of `population` animals (1.0 at 25 animals).
static func speed_factor(population: int) -> float:
	return clampf(1.0 + float(population - 25) / TUNING.NEST_POPULATION_STEP, 1.0, TUNING.NEST_MAX_SPEED)


# Adds progress for `share` of the swarm standing inside. True exactly once, when full.
func fill(delta: float, share: float, population: int) -> bool:
	inside_share = share
	if complete or share <= 0.0:
		return false
	progress = minf(1.0, progress + share * speed_factor(population) * delta / TUNING.NEST_FILL_SECONDS)
	if progress >= 1.0:
		complete = true
		return true
	return false


func animate(delta: float, occupied: bool) -> void:
	_time += delta
	var pulse := 0.5 + 0.5 * sin(_time * (6.0 if occupied else 2.2))
	_fill_disc.scale = Vector3(maxf(0.001, progress), 1.0, maxf(0.001, progress))
	_fill_material.albedo_color = Color(CYAN, 0.2 + 0.12 * pulse * (1.0 if occupied else 0.4))
	_edge_material.albedo_color = Color(CYAN.lerp(Color.WHITE, 0.35 * pulse if occupied else 0.0), 0.7 + 0.25 * pulse)
	_bar_fill.scale.x = maxf(0.001, progress)
	_bar_fill.position.x = -BAR_WIDTH * 0.5 * (1.0 - progress)
	_egg_material.emission_energy_multiplier = 0.2 + 1.6 * progress + (0.5 * pulse if occupied else 0.0)
	for index in _eggs.size():
		var wobble := (0.05 + 0.1 * progress) * sin(_time * (5.0 + index) + index) if occupied else 0.0
		_eggs[index].scale = Vector3.ONE * (0.85 + 0.35 * progress) * (1.0 + wobble)


# Twelve bone claws around the rim as one mesh (cached per radius).
static func _claw_ring(zone_radius: float) -> ArrayMesh:
	var key := snappedf(zone_radius, 0.01)
	if _claw_meshes.has(key):
		return _claw_meshes[key]
	var claw := CylinderMesh.new()
	claw.top_radius = 0.0
	claw.bottom_radius = 0.16
	claw.height = 0.75
	claw.radial_segments = 6
	claw.rings = 1
	var parts: Array = []
	for index in 12:
		var angle := TAU * float(index) / 12.0 + 0.13
		var basis := Basis.from_euler(Vector3(0.0, -angle, -0.45))
		parts.append([claw, Transform3D(basis, Vector3(cos(angle) * (zone_radius + 0.15), 0.3, sin(angle) * (zone_radius + 0.15)))])
	var merged := FX_BATCH.merge(parts)
	_claw_meshes[key] = merged
	return merged


func _flat(color: Color, transparent := true) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _part(parent: Node3D, mesh: Mesh, material: Material, location: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = location
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part
