extends Node3D

const TUNING = preload("res://scripts/tuning.gd")
const TG = preload("res://scripts/telegraph_style.gd")
enum State { ARRIVING, CHASE, WARNING, RECOVERY }
var state := State.ARRIVING
var remaining := 1.0
var health := TUNING.HUNTER_HEALTH
var max_health := TUNING.HUNTER_HEALTH
var attack_center := Vector3.ZERO
var attack_power := 6
# Base loss of the attack resolved during the last step() (0 = none), whether or
# not the swarm centre was inside; HuntWorld scales it by the share of animals hit.
var resolved_power := 0
var hit_flash := 0.0
var warning: Node3D
var body: MeshInstance3D
var health_fill: MeshInstance3D
# Patterned ground telegraph (telegraph_style.gd "hunter") inside `warning`.
var warning_zone: MeshInstance3D
# Legacy handle (tests/capture_combat.gd sets its colour); no longer rendered.
var warning_material := StandardMaterial3D.new()
# Movement multiplier set by attack forms (e.g. Sporenwolke); 1.0 = normal.
var slow_factor := 1.0


func _ready() -> void:
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color("834c9f")
	shell.roughness = 0.85
	var armor := SphereMesh.new()
	armor.radius = 0.72
	armor.height = 1.05
	body = _part(self, armor, shell, Vector3(0, 0.6, 0))
	for side in [-1.0, 1.0]:
		var horn := CylinderMesh.new()
		horn.top_radius = 0.0
		horn.bottom_radius = 0.24
		horn.height = 0.75
		_part(self, horn, shell, Vector3(side * 0.5, 1.0, -0.2))
	var mask := StandardMaterial3D.new()
	mask.albedo_color = Color("4d345f")
	var face := BoxMesh.new()
	face.size = Vector3(0.9, 0.25, 0.3)
	_part(self, face, mask, Vector3(0, 0.65, 0.56))
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("ff9a55")
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var eye := SphereMesh.new()
	eye.radius = 0.10
	eye.height = 0.12
	for side in [-1.0, 1.0]:
		_part(self, eye, glow, Vector3(side * 0.24, 0.76, 0.73))
	var bar := BoxMesh.new()
	bar.size = Vector3(1.4, 0.07, 0.13)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color("f17e91")
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	health_fill = _part(self, bar, red, Vector3(0, 1.6, 0))
	warning = Node3D.new()
	add_child(warning)
	warning.top_level = true
	warning_zone = TG.build("hunter", TUNING.HUNTER_ATTACK_RADIUS)
	warning_zone.position = Vector3(0, 0.10, 0)
	warning.add_child(warning_zone)
	# Approach preview: faint contour only until the attack is locked.
	TG.set_armed(warning_zone, false)
	warning.global_position = global_position
	warning.scale = Vector3.ONE * 0.45


func take_damage(amount: float) -> void:
	health -= amount
	hit_flash = 0.12


# Returns one resolved hit, once per completed wind-up. Its location is locked.
func step(delta: float, swarm_position: Vector3, pressure: float, swarm_velocity: Vector3 = Vector3.ZERO) -> int:
	resolved_power = 0
	hit_flash = maxf(0.0, hit_flash - delta)
	body.scale = Vector3.ONE * (1.12 if hit_flash > 0.0 else 1.0)
	health_fill.scale.x = clampf(health / max_health, 0.0, 1.0)
	if state == State.CHASE:
		var offset := swarm_position - global_position
		offset.y = 0.0
		var arena: Node3D = get_parent().get_parent().get_node("Arena")
		var line_clear: bool = arena.clear_line(position, swarm_position, 0.8).distance_to(position) >= offset.length() - 0.3
		if offset.length() <= 3.0 and line_clear:
			state = State.WARNING
			remaining = TUNING.HUNTER_WARNING_SECONDS
			# Later hunters lead straight-line movement, but the announced area
			# remains fixed so a deliberate direction change can evade it.
			var lead := minf(1.0, log(pressure) * 0.6)
			attack_center = swarm_position + swarm_velocity * lead
			attack_power = int(ceil(minf(1000000.0, TUNING.HUNTER_DAMAGE * pressure)))
			warning.global_position = attack_center
			warning.scale = Vector3.ONE
			TG.set_armed(warning_zone, true)
			TG.set_progress(warning_zone, 0.0)
			warning.visible = true
		else:
			var direction: Vector3 = arena.steer_direction(position, swarm_position, 0.8)
			position = arena.resolve_motion(position, direction * minf(8.2, TUNING.HUNTER_SPEED + log(pressure) * 0.9) * slow_factor * delta, 0.8)
		return 0
	remaining -= delta
	if state == State.WARNING:
		# Area keeps its full footprint; the pattern fills with the wind-up.
		TG.set_armed(warning_zone, true)
		TG.set_progress(warning_zone, 1.0 - remaining / TUNING.HUNTER_WARNING_SECONDS)
		body.position.y = 0.6 + 0.14 * sin((1.0 - remaining / TUNING.HUNTER_WARNING_SECONDS) * PI)
	if remaining > 0.0:
		return 0
	if state == State.ARRIVING:
		state = State.CHASE
		warning.visible = false
	elif state == State.WARNING:
		state = State.RECOVERY
		remaining = TUNING.HUNTER_RECOVERY_SECONDS
		warning.visible = false
		body.position.y = 0.6
		resolved_power = attack_power
		if swarm_position.distance_to(attack_center) <= TUNING.HUNTER_ATTACK_RADIUS:
			return attack_power
	elif state == State.RECOVERY:
		state = State.CHASE
	return 0


# Locked ring footprint (flat), valid from the warning until the hit resolves.
func contains(point: Vector3) -> bool:
	return Vector2(point.x - attack_center.x, point.z - attack_center.z).length() <= TUNING.HUNTER_ATTACK_RADIUS


# Share of the given world points inside the locked attack area (0..1).
func hit_fraction(points: PackedVector3Array) -> float:
	if points.is_empty():
		return 0.0
	var inside := 0
	for point in points:
		if contains(point):
			inside += 1
	return float(inside) / float(points.size())


func _part(parent: Node3D, mesh: Mesh, material: Material, location: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = location
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part
