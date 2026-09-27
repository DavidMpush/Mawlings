extends Node3D

# MIGRATIONSSCHLUND (stage 10) – opens where the Moosschlund fell and stays until
# the swarm walks in (resource rule: it never expires; ignoring it is allowed,
# the run stays endless). Purely a landmark: no collision, never hurts.
#
# Look: the delivered pit model as the rim (was: violet lip + bone teeth), a
# swirling vortex that shows the destination biome's colours (Glutsumpf: lava
# gold/orange, Verdant: pool teal) and a tall soft light column, so it reads
# from far away and never like a danger telegraph (those are dark fills with a
# bright contour; this is a bright centre with a fleshy 3D rim).
#
# API (HuntWorld):
#   setup(target_biome)                 before add_child
#   contains(point) / hit_fraction(points)
#   step(delta, share) -> bool          true exactly once, when the swarm share
#                                       inside stayed >= MIGRATION_SHARE for
#                                       MIGRATION_HOLD_SECONDS (hold 0..1 rises
#                                       with 1/HOLD, falls twice as fast outside)
#   hold, inside_share, radius, target_biome, entered

const TUNING = preload("res://scripts/tuning.gd")
const BIOMES = preload("res://scripts/biomes.gd")
const FX_BATCH = preload("res://scripts/fx_batch.gd")
const CREATURE_SHADER = preload("res://shaders/creature.gdshader")
## Optimised "migration pit" model (tools/optimize_characters.py migration_pit):
## a crater 1.12 m wide whose rim crest (0.38 m high) sits at 0.25 m from the
## centre. At load the bowl is flattened (the vortex must stay visible inside)
## and the outer slope pulled in, then the crest is scaled to just outside the
## radius and PIT_CREST_HEIGHT high.
const PIT_MODEL = preload("res://assets/gameplay/props/MigrationPit_game.glb")
const PIT_CREST := 0.25
const PIT_CREST_OUT := 1.15       # crest radius in units of the maw radius
const PIT_CREST_HEIGHT := 0.6    # metres
const PIT_MODEL_HEIGHT := 0.383
const PIT_SLOPE_PULL := 0.5       # outer slope width factor (smaller footprint)

const OPEN_SECONDS := 1.2
const LIP_RIM := Color("ffb8d8")
const BEAM_HEIGHT := 9.0

const VORTEX_CODE := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Migration vortex: spiral arms turning inward towards a bright core, a dark
// throat ring just inside the lip and a hold arc (entering progress) on the rim.
uniform vec4 core_color : source_color = vec4(1.0, 0.9, 0.5, 1.0);
uniform vec4 mid_color : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform vec4 deep_color : source_color = vec4(0.16, 0.05, 0.14, 1.0);
uniform vec4 hold_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float hold = 0.0;
uniform float open = 1.0;
uniform float time = -1.0;
uniform float radius = 4.0;
varying vec2 local_m;

void vertex() {
	local_m = VERTEX.xz / radius;
}

float aa(float e, float v) {
	float w = max(fwidth(v), 1e-4);
	return smoothstep(e - w, e + w, v);
}

void fragment() {
	float t = time >= 0.0 ? time : TIME;
	vec2 p = local_m;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float ang = atan(p.y, p.x);
	float swirl = fract(ang / 6.2832 * 3.0 + log(max(r, 0.02)) * 1.6 + t * 0.55);
	float arm = smoothstep(0.0, 0.18, swirl) * (1.0 - smoothstep(0.42, 0.62, swirl));
	float depth = smoothstep(0.0, 0.85, r);
	vec3 color = mix(core_color.rgb, mid_color.rgb, smoothstep(0.05, 0.45, r));
	color = mix(color, deep_color.rgb, smoothstep(0.35, 0.92, r) * (1.0 - arm * 0.65));
	color = mix(color, mix(mid_color.rgb, core_color.rgb, 0.5), arm * (1.0 - depth) * 0.6);
	float glow = (1.0 - smoothstep(0.0, 0.3, r)) * (0.75 + 0.25 * sin(t * 4.0));
	color = mix(color, vec3(1.0), glow * 0.45);
	float alpha = mix(0.98, 0.9, depth);
	// Hold arc: fills clockwise from the top while the swarm stands inside.
	float a = fract(0.25 - ang / 6.2832);
	float band = aa(0.86, r) * (1.0 - aa(0.97, r));
	float filled = 1.0 - aa(hold, a);
	color = mix(color, hold_color.rgb, band * filled * step(0.001, hold));
	ALBEDO = color;
	ALPHA = clamp(alpha * open, 0.0, 1.0);
}
"""
static var _vortex_shader: Shader
static var _pit_mesh: Array = []

var radius := TUNING.MIGRATION_RADIUS
var target_biome := "glutsumpf"
var hold := 0.0
var inside_share := 0.0
var entered := false
var opened := 0.0
var rim: Node3D
var vortex: MeshInstance3D
var vortex_material: ShaderMaterial
var lip: MeshInstance3D
var teeth: MeshInstance3D
var beam: MeshInstance3D
var _time := 0.0


func setup(target: String) -> void:
	target_biome = target


func _ready() -> void:
	rim = Node3D.new()
	rim.name = "Rim"
	add_child(rim)
	vortex_material = ShaderMaterial.new()
	if _vortex_shader == null:
		_vortex_shader = Shader.new()
		_vortex_shader.code = VORTEX_CODE
	vortex_material.shader = _vortex_shader
	vortex_material.set_shader_parameter("radius", radius)
	_apply_target_colors()
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.0, radius * 2.0)
	vortex = _part(self, "Vortex", plane, vortex_material, Vector3(0, 0.1, 0))
	# Rim: the delivered pit model (vertex colours, creature look with a pink
	# rim light); `lip` and `teeth` both point at it (kept for callers).
	var pit := _pit()
	var lip_material := ShaderMaterial.new()
	lip_material.shader = CREATURE_SHADER
	lip_material.set_shader_parameter("brightness", 1.3)
	lip_material.set_shader_parameter("saturation", 0.7)
	# Calm the mottled texture towards the fleshy violet of the stage 10 lip.
	lip_material.set_shader_parameter("body_tint", Color(0.62, 0.36, 0.52, 0.45))
	lip_material.set_shader_parameter("shape_light", 0.45)
	lip_material.set_shader_parameter("rim_color", LIP_RIM)
	lip_material.set_shader_parameter("rim_strength", 0.35)
	var k := radius * PIT_CREST_OUT / PIT_CREST
	lip = _part(rim, "Lip", pit[0], lip_material, Vector3.ZERO)
	lip.transform = Transform3D(Basis.from_scale(Vector3(k, PIT_CREST_HEIGHT / PIT_MODEL_HEIGHT, k)), Vector3.ZERO) * pit[1]
	teeth = lip
	var column := CylinderMesh.new()
	column.top_radius = radius * 0.25
	column.bottom_radius = radius * 0.62
	column.height = BEAM_HEIGHT
	column.radial_segments = 20
	column.rings = 1
	column.cap_top = false
	column.cap_bottom = false
	var core: Color = vortex_material.get_shader_parameter("core_color")
	beam = _part(self, "Beam", column, FX_BATCH.shared_material(Color(core, 0.22), true, true, 1.0, true), Vector3(0, BEAM_HEIGHT * 0.5, 0))
	_animate(0.0)


func _apply_target_colors() -> void:
	var data: Dictionary = BIOMES.get_data(target_biome)
	var core: Color = Color(data.pool).lightened(0.45)
	var mid: Color = data.pool
	var deep: Color = Color(data.ground).darkened(0.7)
	if data.has("ember"):
		core = data.ember.lava_core
		mid = data.ember.lava_mid
		deep = Color("2a0c22")
	vortex_material.set_shader_parameter("core_color", core)
	vortex_material.set_shader_parameter("mid_color", mid)
	vortex_material.set_shader_parameter("deep_color", deep)
	vortex_material.set_shader_parameter("hold_color", Color("fff6e0"))


## [mesh, node transform] of the pit model, loaded once.
static func _pit() -> Array:
	if _pit_mesh.is_empty():
		var root := PIT_MODEL.instantiate()
		var model: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]
		var base := Transform3D.IDENTITY
		var node: Node = model
		while node != root and node is Node3D:
			base = (node as Node3D).transform * base
			node = node.get_parent()
		_pit_mesh = [_reshape(model.mesh), base]
		root.free()
	return _pit_mesh


## Model space: x/y is the ground plane, -z is up (the node turns it upright).
## Inside the crest the height falls off steeply towards a flat floor; outside
## it the slope is pulled towards the crest.
static func _reshape(source: Mesh) -> ArrayMesh:
	var arrays := source.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in points.size():
		var v := points[i]
		var flat := Vector2(v.x, v.y)
		var r := flat.length()
		if r < PIT_CREST:
			# Flat floor out to 90 % of the crest, then a short steep inner wall.
			var wall := clampf((r / PIT_CREST - 0.9) / 0.1, 0.0, 1.0)
			v.z *= wall * wall
		elif r > 0.0:
			flat *= (PIT_CREST + (r - PIT_CREST) * PIT_SLOPE_PULL) / r
			v.x = flat.x
			v.y = flat.y
		points[i] = v
	arrays[Mesh.ARRAY_VERTEX] = points
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func contains(point: Vector3) -> bool:
	return Vector2(point.x - position.x, point.z - position.z).length() <= radius


func hit_fraction(points: PackedVector3Array) -> float:
	if points.is_empty():
		return 0.0
	var inside := 0
	for point in points:
		if contains(point):
			inside += 1
	return float(inside) / float(points.size())


## Advances opening, hold and animation. True exactly once when entered.
func step(delta: float, share: float) -> bool:
	inside_share = share
	opened = minf(1.0, opened + delta / OPEN_SECONDS)
	if not entered and opened >= 1.0:
		if share >= TUNING.MIGRATION_SHARE:
			hold = minf(1.0, hold + delta / TUNING.MIGRATION_HOLD_SECONDS)
		else:
			hold = maxf(0.0, hold - 2.0 * delta / TUNING.MIGRATION_HOLD_SECONDS)
	_animate(delta)
	if not entered and hold >= 1.0:
		entered = true
		return true
	return false


func _animate(delta: float) -> void:
	_time += delta
	var grow := 1.0 - pow(1.0 - opened, 3.0)
	var breath := 1.0 + 0.045 * sin(_time * 2.4) + 0.06 * hold
	rim.scale = Vector3(breath, 1.0, breath) * maxf(0.01, grow)
	vortex.scale = Vector3.ONE * maxf(0.01, grow)
	vortex_material.set_shader_parameter("open", grow)
	vortex_material.set_shader_parameter("hold", hold)
	vortex_material.set_shader_parameter("time", _time)
	beam.scale = Vector3(1.0, maxf(0.01, grow), 1.0)
	beam.position.y = BEAM_HEIGHT * 0.5 * grow
	rim.rotation.y = 0.05 * sin(_time * 1.3)


func _part(parent: Node3D, label: String, mesh: Mesh, material: Material, location: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = mesh
	part.material_override = material
	part.position = location
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part
