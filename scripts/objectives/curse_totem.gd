extends Node3D

# Fluch-Totem (stage 06): an optional choice in the world. Holding the swarm
# centre within TOTEM_RADIUS for TOTEM_HOLD_SECONDS accepts the curse (no menu);
# leaving lets the hold drain again. HuntWorld applies the effect and removes it.
# Logic and animation only run in hold_step(), called from HuntWorld.step().

const TUNING = preload("res://scripts/tuning.gd")
const UI_ICONS = preload("res://scripts/ui/ui_icons.gd")
const VIOLET := Color("b07ae8")
const CURSE := Color("ff4a8a")
const STONE := Color("3a2a48")
const BONE := Color("efe2c0")
const HEAD_HEIGHT := 2.25

var radius: float = TUNING.TOTEM_RADIUS
var hold := 0.0            # 0..1 share of the required hold time
var accepted := false
var inside := false
var _time := 0.0
var _fill_disc: MeshInstance3D
var _fill_material: StandardMaterial3D
var _ring_material: StandardMaterial3D
var _eye_material: StandardMaterial3D
var _beam_material: StandardMaterial3D
var _head: Node3D


func _ready() -> void:
	var zone := CylinderMesh.new()
	zone.top_radius = radius
	zone.bottom_radius = radius
	zone.height = 0.02
	zone.radial_segments = 40
	_part(self, zone, _flat(Color(VIOLET, 0.12)), Vector3(0, 0.03, 0))
	_fill_material = _flat(Color(CURSE, 0.35))
	_fill_disc = _part(self, zone, _fill_material, Vector3(0, 0.045, 0))
	_fill_disc.scale = Vector3(0.001, 1.0, 0.001)
	_ring_material = _flat(Color(VIOLET, 0.9))
	var shard := CylinderMesh.new()
	shard.top_radius = 0.0
	shard.bottom_radius = 0.13
	shard.height = 0.5
	shard.radial_segments = 4
	for index in 9:
		var angle := TAU * float(index) / 9.0
		var part := _part(self, shard, _ring_material, Vector3(cos(angle) * radius, 0.2, sin(angle) * radius))
		part.rotation = Vector3(0.0, -angle, 0.35)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = STONE
	stone.roughness = 0.9
	var sizes := [[0.62, 0.62, 0.31], [0.5, 0.6, 0.92], [0.4, 0.58, 1.5]]
	for entry in sizes:
		var block := CylinderMesh.new()
		block.top_radius = entry[0] * 0.8
		block.bottom_radius = entry[0]
		block.height = entry[1]
		block.radial_segments = 7
		var part := _part(self, block, stone, Vector3(0, entry[2], 0))
		part.rotation.y = entry[2] * 2.0
	_head = Node3D.new()
	_head.position = Vector3(0, HEAD_HEIGHT, 0)
	add_child(_head)
	var bone := StandardMaterial3D.new()
	bone.albedo_color = BONE
	bone.roughness = 0.6
	var skull := SphereMesh.new()
	skull.radius = 0.42
	skull.height = 0.72
	_part(_head, skull, bone, Vector3.ZERO)
	var horn := CylinderMesh.new()
	horn.top_radius = 0.0
	horn.bottom_radius = 0.14
	horn.height = 0.7
	for side in [-1.0, 1.0]:
		var part := _part(_head, horn, bone, Vector3(side * 0.42, 0.28, 0))
		part.rotation.z = -side * 0.7
	_eye_material = _flat(CURSE, false)
	var eye := SphereMesh.new()
	eye.radius = 0.09
	eye.height = 0.14
	for side in [-1.0, 1.0]:
		_part(_head, eye, _eye_material, Vector3(side * 0.15, 0.02, 0.36))
	_beam_material = _flat(Color(VIOLET, 0.22))
	var beam := CylinderMesh.new()
	beam.top_radius = 0.05
	beam.bottom_radius = 0.32
	beam.height = 5.0
	_part(self, beam, _beam_material, Vector3(0, 2.5, 0))
	var icon := UI_ICONS.texture("skull")
	if icon != null:
		var sprite := Sprite3D.new()
		sprite.name = "Icon"
		sprite.texture = icon
		sprite.modulate = Color("ffc3dc")
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.pixel_size = 0.9 / float(icon.get_width())
		sprite.position = Vector3(0, 3.6, 0)
		# Stays readable when the swarm stands on the totem.
		sprite.no_depth_test = true
		sprite.render_priority = 10
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sprite)
	_apply(0.0)


func contains(point: Vector3) -> bool:
	return Vector2(point.x - position.x, point.z - position.z).length() <= radius


# Advances the hold with the swarm centre. True exactly once, when accepted.
func hold_step(delta: float, swarm_position: Vector3) -> bool:
	_time += delta
	if accepted:
		return false
	inside = contains(swarm_position)
	if inside:
		hold = minf(1.0, hold + delta / TUNING.TOTEM_HOLD_SECONDS)
	else:
		hold = maxf(0.0, hold - 2.0 * delta / TUNING.TOTEM_HOLD_SECONDS)
	_apply(delta)
	if hold >= 1.0:
		accepted = true
		return true
	return false


func _apply(_delta: float) -> void:
	var pulse := 0.5 + 0.5 * sin(_time * (9.0 if inside else 2.5))
	_fill_disc.scale = Vector3(maxf(0.001, hold), 1.0, maxf(0.001, hold))
	_ring_material.albedo_color = Color(VIOLET.lerp(CURSE, hold), 0.75 + 0.25 * pulse)
	_eye_material.albedo_color = CURSE.lerp(Color.WHITE, 0.4 * pulse)
	_beam_material.albedo_color = Color(VIOLET.lerp(CURSE, hold), 0.14 + 0.1 * pulse)
	_head.position.y = HEAD_HEIGHT + 0.08 * sin(_time * 1.8)
	_head.rotation.y = 0.25 * sin(_time * 0.9)


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
