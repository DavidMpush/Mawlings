extends Node3D

# Short-lived, purely visual ground effects (shockwaves, dust, spawn marks).
# They never touch game state and free themselves when finished.

var duration := 0.5
var age := 0.0
var from_radius := 0.5
var to_radius := 3.0
var color := Color.WHITE
var material: StandardMaterial3D
static var shared_torus: TorusMesh


static func ring(parent: Node, location: Vector3, tint: Color, start_radius: float, end_radius: float, seconds: float) -> Node3D:
	var effect: Node3D = load("res://scripts/fx.gd").new()
	effect.name = "Ground ring"
	effect.duration = seconds
	effect.from_radius = start_radius
	effect.to_radius = end_radius
	effect.color = tint
	parent.add_child(effect)
	effect.top_level = true
	effect.global_position = Vector3(location.x, 0.14, location.z)
	return effect


func _ready() -> void:
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if shared_torus == null:
		shared_torus = TorusMesh.new()
		shared_torus.inner_radius = 0.84
		shared_torus.outer_radius = 1.0
		shared_torus.rings = 48
		shared_torus.ring_segments = 6
	var part := MeshInstance3D.new()
	part.mesh = shared_torus
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
	_apply(0.0)


func _process(delta: float) -> void:
	age += delta
	var progress := clampf(age / duration, 0.0, 1.0)
	_apply(progress)
	if progress >= 1.0:
		queue_free()


func _apply(progress: float) -> void:
	var eased := 1.0 - pow(1.0 - progress, 3.0)
	var radius := lerpf(from_radius, to_radius, eased)
	scale = Vector3(radius, 0.35, radius)
	material.albedo_color = Color(color.r, color.g, color.b, color.a * (1.0 - progress))
