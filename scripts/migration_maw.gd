extends Node3D

# MIGRATIONSSCHLUND (stage 10) – opens where the Moosschlund fell and stays until
# the swarm walks in (resource rule: it never expires; ignoring it is allowed,
# the run stays endless). Purely a landmark: no collision, never hurts.
#
# Look: a fleshy violet lip with a ring of bone teeth that breathes slowly, a
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

const OPEN_SECONDS := 1.2
const LIP_COLOR := Color("7a3558")
const LIP_RIM := Color("ffb8d8")
const TOOTH_COLOR := Color("f2e8cc")
const TEETH := 9
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
static var _teeth_mesh: ArrayMesh

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
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.25
	torus.outer_radius = radius + 0.55
	torus.rings = 40
	torus.ring_segments = 8
	var lip_material := StandardMaterial3D.new()
	lip_material.albedo_color = LIP_COLOR
	lip_material.roughness = 0.55
	lip_material.rim_enabled = true
	lip_material.rim = 0.6
	lip_material.rim_tint = 0.2
	lip_material.emission_enabled = true
	lip_material.emission = LIP_COLOR.darkened(0.4)
	lip = _part(rim, "Lip", torus, lip_material, Vector3(0, 0.12, 0))
	lip.scale = Vector3(1.0, 0.45, 1.0)
	teeth = _part(rim, "Teeth", _teeth(), FX_BATCH.shared_material(TOOTH_COLOR, false, false, 0.7), Vector3.ZERO)
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


static func _teeth() -> ArrayMesh:
	if _teeth_mesh != null:
		return _teeth_mesh
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.3
	cone.height = 1.2
	cone.radial_segments = 6
	cone.rings = 1
	var parts: Array = []
	var ring := TUNING.MIGRATION_RADIUS + 0.1
	for index in TEETH:
		var angle := TAU * float(index) / float(TEETH)
		var out := Vector3(cos(angle), 0.0, sin(angle))
		# Teeth lean inward over the throat, alternating long and short.
		var tilt := Basis(out.cross(Vector3.UP).normalized(), -0.55)
		var size := 1.0 if index % 2 == 0 else 0.72
		var basis := tilt * Basis.from_scale(Vector3.ONE * size)
		parts.append([cone, Transform3D(basis, out * ring + Vector3(0, 0.45 * size, 0))])
	_teeth_mesh = FX_BATCH.merge(parts)
	return _teeth_mesh


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
	teeth.rotation.y = 0.05 * sin(_time * 1.3)


func _part(parent: Node3D, label: String, mesh: Mesh, material: Material, location: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = mesh
	part.material_override = material
	part.position = location
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part
