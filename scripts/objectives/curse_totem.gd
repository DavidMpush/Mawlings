extends Node3D

# Fluch-Totem (stage 06): an optional choice in the world. Holding the swarm
# centre within TOTEM_RADIUS for TOTEM_HOLD_SECONDS accepts the curse (no menu);
# leaving lets the hold drain again. HuntWorld applies the effect and removes it.
# Logic and animation only run in hold_step(), called from HuntWorld.step().

const TUNING = preload("res://scripts/tuning.gd")
const UI_ICONS = preload("res://scripts/ui/ui_icons.gd")
const FX_BATCH = preload("res://scripts/fx_batch.gd")
static var _parts := {}
const VIOLET := Color("b07ae8")
const CURSE := Color("ff4a8a")
const MODEL := preload("res://assets/gameplay/props/CurseTotem_game.glb")
## Height of the optimised model (1.04 m upright) scaled to the old primitive
## totem (~2.8 m), and its yaw so the carved face looks at the game camera.
const MODEL_SCALE := 2.7
const MODEL_YAW := 0.0
# Totem look: creature_look (vertex colours, key light, contour) plus glowing
# violet veins picked out of the vertex colours (blue clearly above green).
const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled;
#define OUTLINE_DEFAULT 0.3
#include "res://shaders/creature_look.gdshaderinc"
uniform vec4 vein_color : source_color = vec4(0.8, 0.45, 1.0, 1.0);
uniform float vein_glow = 1.0;
void fragment() {
	vec3 look = creature_look(COLOR.rgb, NORMAL, VIEW, FRONT_FACING);
	float vein = smoothstep(0.1, 0.28, COLOR.b - COLOR.g) * step(COLOR.r, COLOR.b);
	ALBEDO = mix(look, vein_color.rgb * (0.9 + 0.8 * vein_glow), vein * 0.85);
}
"""
static var _shader: Shader
static var _model_mesh: Array = []

var radius: float = TUNING.TOTEM_RADIUS
var hold := 0.0            # 0..1 share of the required hold time
var accepted := false
var inside := false
var _time := 0.0
var _fill_disc: MeshInstance3D
var _fill_material: StandardMaterial3D
var _ring_material: StandardMaterial3D
var _beam_material: StandardMaterial3D
var _totem_material: ShaderMaterial


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
	# Etappe 07: same-material parts are merged meshes (shards, stone stack,
	# skull + horns, eyes), built once per radius and shared.
	var parts := _shared_parts(radius)
	_part(self, parts.shards, _ring_material, Vector3.ZERO)
	_totem_material = _make_totem_material()
	var model_mesh := _totem_mesh()
	var totem := _part(self, model_mesh[0], _totem_material, Vector3.ZERO)
	totem.name = "Totem"
	totem.transform = Transform3D(Basis(Vector3.UP, MODEL_YAW).scaled(Vector3.ONE * MODEL_SCALE), Vector3.ZERO) * model_mesh[1]
	_beam_material = _flat(Color(VIOLET, 0.22))
	_part(self, parts.beam, _beam_material, Vector3(0, 2.5, 0))
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
	_beam_material.albedo_color = Color(VIOLET.lerp(CURSE, hold), 0.14 + 0.1 * pulse)
	_totem_material.set_shader_parameter("vein_glow", pulse * (0.6 + 0.4 * hold))
	_totem_material.set_shader_parameter("vein_color", VIOLET.lerp(CURSE, hold * 0.8).lightened(0.15))


static func _shared_parts(zone_radius: float) -> Dictionary:
	var key := snappedf(zone_radius, 0.01)
	if _parts.has(key):
		return _parts[key]
	var shard := CylinderMesh.new()
	shard.top_radius = 0.0
	shard.bottom_radius = 0.13
	shard.height = 0.5
	shard.radial_segments = 4
	shard.rings = 1
	var shards: Array = []
	for index in 9:
		var angle := TAU * float(index) / 9.0
		shards.append([shard, Transform3D(Basis.from_euler(Vector3(0.0, -angle, 0.35)), Vector3(cos(angle) * zone_radius, 0.2, sin(angle) * zone_radius))])
	var beam := CylinderMesh.new()
	beam.top_radius = 0.05
	beam.bottom_radius = 0.32
	beam.height = 5.0
	beam.radial_segments = 20
	beam.rings = 1
	var result := {
		"shards": FX_BATCH.merge(shards),
		"beam": beam,
	}
	_parts[key] = result
	return result


## [mesh, node transform] of the optimised CurseTotem model, loaded once.
static func _totem_mesh() -> Array:
	if _model_mesh.is_empty():
		var root := MODEL.instantiate()
		var model: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]
		var base := Transform3D.IDENTITY
		var node: Node = model
		while node != root and node is Node3D:
			base = (node as Node3D).transform * base
			node = node.get_parent()
		_model_mesh = [model.mesh, base]
		root.free()
	return _model_mesh


func _make_totem_material() -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("brightness", 1.35)
	material.set_shader_parameter("saturation", 1.1)
	material.set_shader_parameter("shape_light", 0.45)
	material.set_shader_parameter("rim_color", VIOLET)
	material.set_shader_parameter("rim_strength", 0.35)
	return material


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
