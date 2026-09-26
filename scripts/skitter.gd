extends Node3D

const TUNING = preload("res://scripts/tuning.gd")
enum State { ARRIVING, CHASE, WARNING, DASH, RECOVERY }
var state := State.ARRIVING
var remaining := 0.8
var health := TUNING.SKITTER_HEALTH
var max_health := TUNING.SKITTER_HEALTH
var dash_start := Vector3.ZERO
var dash_end := Vector3.ZERO
var damage := 0
var hit_flash := 0.0
var body: MeshInstance3D
var health_fill: MeshInstance3D
var warning: MeshInstance3D

func _ready() -> void:
	var shell := _material(Color("3874ba"))
	var crest := _material(Color("de5b99"))
	var eye := _material(Color("ffe06b"), true)
	var armor := SphereMesh.new()
	armor.radius = 0.55
	armor.height = 0.65
	body = _part(self, armor, shell, Vector3(0, 0.36, 0))
	for side in [-1.0, 1.0]:
		var blade := SphereMesh.new()
		blade.radius = 0.6
		blade.height = 0.14
		var wing := _part(self, blade, crest, Vector3(side * 0.52, 0.36, -0.2))
		wing.rotation.y = side * 0.5
		var dot := SphereMesh.new()
		dot.radius = 0.09
		dot.height = 0.10
		_part(self, dot, eye, Vector3(side * 0.22, 0.52, 0.43))
	var bar := BoxMesh.new()
	bar.size = Vector3(1.25, 0.07, 0.12)
	health_fill = _part(self, bar, _material(Color("ffb36b"), true), Vector3(0, 1.14, 0))
	var strip := BoxMesh.new()
	strip.size = Vector3(TUNING.SKITTER_WIDTH * 2.0, 0.035, 1.0)
	warning = _part(get_parent(), strip, _material(Color("ffc268"), true), Vector3.ZERO)
	warning.top_level = true
	warning.visible = false
	warning.name = "Locked dash lane"

func take_damage(amount: float) -> void:
	health -= amount
	hit_flash = 0.12

func step(delta: float, swarm_position: Vector3, pressure: float) -> int:
	hit_flash = maxf(0.0, hit_flash - delta)
	body.scale = Vector3.ONE * (1.16 if hit_flash > 0.0 else 1.0)
	health_fill.scale.x = clampf(health / max_health, 0, 1)
	if state == State.CHASE:
		var offset := swarm_position - position
		offset.y = 0
		var line_clear: bool = _arena().clear_line(position, swarm_position, 0.6).distance_to(position) >= offset.length() - 0.3
		if offset.length() <= 5.5 and line_clear:
			_lock_dash(swarm_position, pressure)
		else:
			var direction: Vector3 = _arena().steer_direction(position, swarm_position, 0.6)
			position = _arena().resolve_motion(position, direction * minf(9, TUNING.SKITTER_SPEED + 0.6 * log(pressure)) * delta, 0.6)
		return 0
	remaining -= delta
	if state == State.ARRIVING and remaining <= 0:
		state = State.CHASE
	elif state == State.WARNING and remaining <= 0:
		state = State.DASH
		remaining = TUNING.SKITTER_DASH_SECONDS
	elif state == State.DASH:
		var fraction := 1.0 - maxf(0, remaining) / TUNING.SKITTER_DASH_SECONDS
		position = dash_start.lerp(dash_end, fraction)
		if remaining <= 0:
			position = dash_end
			state = State.RECOVERY
			remaining = TUNING.SKITTER_RECOVERY_SECONDS
			warning.visible = false
			if warning_distance(swarm_position) <= TUNING.SKITTER_WIDTH:
				return damage
	elif state == State.RECOVERY and remaining <= 0:
		state = State.CHASE
	return 0

func _lock_dash(swarm_position: Vector3, pressure: float) -> void:
	state = State.WARNING
	remaining = TUNING.SKITTER_WARNING_SECONDS
	dash_start = position
	var direction := (swarm_position - position).normalized()
	dash_end = _arena().clear_line(position, position + direction * TUNING.SKITTER_RANGE, 0.6)
	damage = int(ceil(minf(1000000, TUNING.SKITTER_DAMAGE * pressure)))
	var line := dash_end - dash_start
	if line.length() <= 0.05:
		state = State.RECOVERY
		remaining = TUNING.SKITTER_RECOVERY_SECONDS
		warning.visible = false
		return
	warning.global_position = (dash_start + dash_end) * 0.5 + Vector3(0, 0.09, 0)
	warning.rotation.y = atan2(line.x, line.z)
	warning.scale = Vector3(1, 1, line.length())
	warning.visible = line.length() > 0.05

func warning_distance(location: Vector3) -> float:
	var start := Vector2(dash_start.x, dash_start.z)
	var end := Vector2(dash_end.x, dash_end.z)
	var point := Vector2(location.x, location.z)
	var segment := end - start
	if segment.length_squared() < 0.001:
		return point.distance_to(start)
	return point.distance_to(start + segment * clampf((point - start).dot(segment) / segment.length_squared(), 0, 1))

func dodge_direction(location: Vector3) -> Vector3:
	var line := dash_end - dash_start
	var side := Vector3(line.z, 0, -line.x).normalized()
	if side.length_squared() < 0.001:
		return Vector3.RIGHT
	return side if (location - dash_start).dot(side) >= 0 else -side

func cleanup() -> void:
	if is_instance_valid(warning):
		warning.queue_free()

func _arena() -> Node3D:
	return get_parent().get_parent().get_node("Arena")

func _material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var value := StandardMaterial3D.new()
	value.albedo_color = color
	value.roughness = 0.8
	if unshaded:
		value.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return value

func _part(parent: Node3D, mesh: Mesh, material: Material, location: Vector3) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.mesh = mesh
	result.material_override = material
	result.position = location
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(result)
	return result
