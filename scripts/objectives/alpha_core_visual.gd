extends RefCounted

# Alpha-Kern model (user delivery assets/alphacore.glb, optimised to
# assets/gameplay/props/AlphaCore_game.glb by tools/optimize_characters.py
# alpha_core). Replaces the primitive gem + violet shell of the pickup:
#   ALPHA_CORE_VISUAL.attach(float_root)   # inside HuntWorld._drop_alpha_core
# The ground halo and the light beam stay primitives (readable from afar).

const MODEL = preload("res://assets/gameplay/props/AlphaCore_game.glb")
const CREATURE_SHADER = preload("res://shaders/creature.gdshader")
## Model is ~0.95 m high and 0.9 m wide; this makes it ~1.2 m, a little
## larger than the old 0.84 m gem inside its 1.24 m shell.
const SCALE := 1.25
const CENTER_HEIGHT := 1.3
const AMBER := Color("ffc24a")

static var _mesh: Array = []
static var _material: ShaderMaterial


## Adds the core model to `float_root` (the bobbing, turning node); returns it.
static func attach(float_root: Node3D, center_height := CENTER_HEIGHT) -> MeshInstance3D:
	var data := _model()
	var part := MeshInstance3D.new()
	part.name = "CoreModel"
	part.mesh = data[0]
	part.material_override = _shared_material()
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.transform = Transform3D(Basis.from_scale(Vector3.ONE * SCALE), Vector3(0.0, center_height - 0.475 * SCALE, 0.0)) * data[1]
	float_root.add_child(part)
	return part


static func _model() -> Array:
	if _mesh.is_empty():
		var root := MODEL.instantiate()
		var model: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]
		var base := Transform3D.IDENTITY
		var node: Node = model
		while node != root and node is Node3D:
			base = (node as Node3D).transform * base
			node = node.get_parent()
		_mesh = [model.mesh, base]
		root.free()
	return _mesh


# Bright, unshaded look with an amber rim so the core glows on moss and ash.
static func _shared_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = CREATURE_SHADER
		_material.set_shader_parameter("brightness", 1.45)
		_material.set_shader_parameter("saturation", 1.2)
		_material.set_shader_parameter("shape_light", 0.35)
		_material.set_shader_parameter("rim_color", AMBER)
		_material.set_shader_parameter("rim_strength", 0.55)
		_material.set_shader_parameter("rim_power", 2.0)
	return _material
