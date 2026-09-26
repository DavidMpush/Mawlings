extends Node3D

const TUNING = preload("res://scripts/tuning.gd")
const TG = preload("res://scripts/telegraph_style.gd")
const FX_BATCH = preload("res://scripts/fx_batch.gd")
# Shared meshes of every skitter (built once, see _shared_parts()).
static var _parts := {}
enum State { ARRIVING, CHASE, WARNING, DASH, RECOVERY }
var state := State.ARRIVING
var remaining := TUNING.SKITTER_ARRIVE_SECONDS
var health := TUNING.SKITTER_HEALTH
var max_health := TUNING.SKITTER_HEALTH
var dash_start := Vector3.ZERO
var dash_end := Vector3.ZERO
var damage := 0
# Base loss of the dash resolved during the last step() (0 = none).
var resolved_power := 0
var hit_flash := 0.0
var body: MeshInstance3D
var health_fill: MeshInstance3D
var warning: MeshInstance3D
# Movement multiplier set by attack forms (e.g. Sporenwolke); 1.0 = normal.
var slow_factor := 1.0

func _ready() -> void:
	# Etappe 07: shared meshes/materials; both blades and both eyes are one
	# merged mesh each (fewer draw calls, same look).
	var parts := _shared_parts()
	body = _part(self, parts.armor, _material(Color("3874ba")), Vector3(0, 0.36, 0))
	_part(self, parts.blades, _material(Color("de5b99")), Vector3.ZERO)
	_part(self, parts.eyes, _material(Color("ffe06b"), true), Vector3.ZERO)
	health_fill = _part(self, parts.bar, _material(Color("ffb36b"), true), Vector3(0, 1.14, 0))
	# Patterned lane (telegraph_style.gd "skitter"): chevrons along local +Z.
	warning = TG.build("skitter", TUNING.SKITTER_WIDTH * 2.0)
	get_parent().add_child(warning)
	warning.top_level = true
	warning.visible = false
	warning.name = "Locked dash lane"

func take_damage(amount: float) -> void:
	health -= amount
	hit_flash = 0.12

func step(delta: float, swarm_position: Vector3, pressure: float) -> int:
	resolved_power = 0
	hit_flash = maxf(0.0, hit_flash - delta)
	body.scale = Vector3.ONE * (1.16 if hit_flash > 0.0 else 1.0)
	health_fill.scale.x = clampf(health / max_health, 0, 1)
	if state == State.CHASE:
		var offset := swarm_position - position
		offset.y = 0
		# Etappe 07: the (costly) line test only runs in dash range; same result.
		if offset.length() <= 5.5 and _arena().clear_line(position, swarm_position, 0.6).distance_to(position) >= offset.length() - 0.3:
			_lock_dash(swarm_position, pressure)
		else:
			var direction: Vector3 = _arena().steer_direction(position, swarm_position, 0.6)
			position = _arena().resolve_motion(position, direction * minf(9, TUNING.SKITTER_SPEED + 0.6 * log(pressure)) * slow_factor * delta, 0.6)
		return 0
	remaining -= delta
	# Presentation only: lane fills over the wind-up and stays full during the dash.
	if state == State.WARNING:
		TG.set_progress(warning, 1.0 - maxf(0, remaining) / TUNING.SKITTER_WARNING_SECONDS)
	elif state == State.DASH:
		TG.set_progress(warning, 1.0)
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
			remaining = TUNING.recovery(TUNING.SKITTER_RECOVERY_SECONDS, pressure, 0.7)
			warning.visible = false
			resolved_power = damage
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
	TG.set_progress(warning, 0.0)
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

# Locked dash lane footprint: capsule of half-width SKITTER_WIDTH along the lane.
func contains(point: Vector3) -> bool:
	return warning_distance(point) <= TUNING.SKITTER_WIDTH

# Share of the given world points inside the locked attack area (0..1).
func hit_fraction(points: PackedVector3Array) -> float:
	if points.is_empty():
		return 0.0
	var inside := 0
	for point in points:
		if contains(point):
			inside += 1
	return float(inside) / float(points.size())

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
	return FX_BATCH.shared_material(color, unshaded, false, 0.8)

static func _shared_parts() -> Dictionary:
	if not _parts.is_empty():
		return _parts
	var armor := SphereMesh.new()
	armor.radius = 0.55
	armor.height = 0.65
	armor.radial_segments = 24
	armor.rings = 12
	var blade := SphereMesh.new()
	blade.radius = 0.6
	blade.height = 0.14
	blade.radial_segments = 20
	blade.rings = 6
	var dot := SphereMesh.new()
	dot.radius = 0.09
	dot.height = 0.10
	dot.radial_segments = 10
	dot.rings = 5
	var blades: Array = []
	var eyes: Array = []
	for side in [-1.0, 1.0]:
		blades.append([blade, Transform3D(Basis(Vector3.UP, side * 0.5), Vector3(side * 0.52, 0.36, -0.2))])
		eyes.append([dot, Transform3D(Basis.IDENTITY, Vector3(side * 0.22, 0.52, 0.43))])
	var bar := BoxMesh.new()
	bar.size = Vector3(1.25, 0.07, 0.12)
	_parts = {"armor": armor, "blades": FX_BATCH.merge(blades), "eyes": FX_BATCH.merge(eyes), "bar": bar}
	return _parts

func _part(parent: Node3D, mesh: Mesh, material: Material, location: Vector3) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.mesh = mesh
	result.material_override = material
	result.position = location
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(result)
	return result
