extends Node3D

const TUNING = preload("res://scripts/tuning.gd")
const TG = preload("res://scripts/telegraph_style.gd")
const FX_BATCH = preload("res://scripts/fx_batch.gd")
const CREATURE_SHADER = preload("res://shaders/creature.gdshader")
# The user's Hunter Beetle (Hunyuan, reduced by tools/optimize_characters.py).
# Loaded at runtime so the primitive look remains as fallback without the file.
const BEETLE_PATH := "res://assets/gameplay/characters/HunterBeetle_game.glb"
const BEETLE_LENGTH := 2.0
static var _beetle_mesh: Mesh
static var _beetle_base := Transform3D.IDENTITY
static var _beetle_checked := false
# The user's elite crown (Hunyuan). Rendered with its own copy of the creature
# look (not the creature shader resource), so the biome tint never recolours it.
const CROWN_PATH := "res://assets/gameplay/props/EliteCrown_game.glb"
# Crown width relative to the beetle length (before the elite scale).
const CROWN_WIDTH := 1.0
static var _crown_mesh: Mesh
static var _crown_base := Transform3D.IDENTITY
static var _crown_checked := false
static var _crown_skin: ShaderMaterial
# Shared meshes/materials of every hunter (built once, see _shared_parts()).
static var _parts := {}
enum State { ARRIVING, CHASE, WARNING, RECOVERY }
var state := State.ARRIVING
var remaining := TUNING.HUNTER_ARRIVE_SECONDS
var health := TUNING.HUNTER_HEALTH
var max_health := TUNING.HUNTER_HEALTH
var attack_center := Vector3.ZERO
var attack_power := 6
# Base loss of the attack resolved during the last step() (0 = none), whether or
# not the swarm centre was inside; HuntWorld scales it by the share of animals hit.
var resolved_power := 0
var hit_flash := 0.0
var warning: Node3D
var body: Node3D
var body_base_y := 0.6
var skin: ShaderMaterial
var health_fill: MeshInstance3D
# Patterned ground telegraph (telegraph_style.gd "hunter") inside `warning`.
var warning_zone: MeshInstance3D
# Legacy handle (tests/capture_combat.gd sets its colour); no longer rendered.
var warning_material := StandardMaterial3D.new()
# Movement multiplier set by attack forms (e.g. Sporenwolke); 1.0 = normal.
var slow_factor := 1.0
# Elite variant (stage 06): larger, crowned, more health; HuntWorld grants the
# guaranteed Alpha-Kern and the bigger reward.
var elite := false
var crown: Node3D
# Top of the body model in local units (feet at y=0), for the crown seat.
var body_top := 1.0
var crown_base_y := 1.18
var crown_clock := 0.0


func _ready() -> void:
	# Etappe 07: meshes and materials are shared by every hunter; both horns and
	# both eyes are one merged mesh each (fewer draw calls, same look).
	var parts := _shared_parts()
	if _load_beetle():
		_build_beetle()
	else:
		var shell: Material = FX_BATCH.shared_material(Color("834c9f"), false, false, 0.85)
		body = _part(self, parts.armor, shell, Vector3(0, 0.6, 0))
		_part(self, parts.horns, shell, Vector3.ZERO)
		_part(self, parts.face, FX_BATCH.shared_material(Color("4d345f")), Vector3(0, 0.65, 0.56))
		_part(self, parts.eyes, FX_BATCH.shared_material(Color("ff9a55"), true), Vector3.ZERO)
	health_fill = _part(self, parts.bar, FX_BATCH.shared_material(Color("f17e91"), true), Vector3(0, 1.6, 0))
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


# Turns this (already added) hunter into an elite: bigger body, golden crown,
# golden health bar and `health_multiplier` x health. Attack area stays the same.
func make_elite(health_multiplier: float) -> void:
	if elite:
		return
	elite = true
	health *= health_multiplier
	max_health = health
	scale = Vector3.ONE * TUNING.ELITE_SCALE
	var parts := _shared_parts()
	crown = Node3D.new()
	crown.name = "Crown"
	add_child(crown)
	var crown_top := 0.0
	var model_mesh: Mesh = _load_crown()
	if model_mesh != null:
		# Model crown floats clearly above the back (seat from the beetle AABB).
		crown_base_y = body_top + 0.02
		var raw: AABB = Transform3D(_crown_base.basis, Vector3.ZERO) * model_mesh.get_aabb()
		var shape := Basis.from_scale(Vector3.ONE * (CROWN_WIDTH / maxf(0.01, maxf(raw.size.x, raw.size.z)))) * _crown_base.basis
		var bounds: AABB = Transform3D(shape, Vector3.ZERO) * model_mesh.get_aabb()
		var model := MeshInstance3D.new()
		model.name = "Crown model"
		model.mesh = model_mesh
		model.material_override = _crown_skin
		model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		model.transform = Transform3D(shape, Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z))
		crown.add_child(model)
		crown_top = bounds.size.y
	else:
		crown_base_y = maxf(1.18, body_top + 0.1)
		# Band and five spikes are one merged gold mesh.
		_part(crown, parts.crown, parts.gold, Vector3.ZERO)
		_part(crown, parts.gem, FX_BATCH.shared_material(Color("a86bff"), true), Vector3(0, 0.06, 0.46))
		crown_top = 0.5
	crown.position = Vector3(0, crown_base_y, 0)
	health_fill.material_override = FX_BATCH.shared_material(Color("ffd66e"), true)
	health_fill.position.y = maxf(1.85, crown_base_y + crown_top + 0.25)


func take_damage(amount: float) -> void:
	health -= amount
	hit_flash = 0.12


# Returns one resolved hit, once per completed wind-up. Its location is locked.
func step(delta: float, swarm_position: Vector3, pressure: float, swarm_velocity: Vector3 = Vector3.ZERO) -> int:
	resolved_power = 0
	hit_flash = maxf(0.0, hit_flash - delta)
	body.scale = Vector3.ONE * (1.12 if hit_flash > 0.0 else 1.0)
	if skin != null:
		skin.set_shader_parameter("flash", 0.3 if hit_flash > 0.0 else 0.0)
	health_fill.scale.x = clampf(health / max_health, 0.0, 1.0)
	# Face the swarm; the health bar stays screen-aligned.
	var facing := swarm_position - global_position
	if state != State.WARNING and Vector2(facing.x, facing.z).length() > 0.2:
		rotation.y = lerp_angle(rotation.y, atan2(facing.x, facing.z), minf(1.0, delta * 8.0))
	health_fill.rotation.y = -rotation.y
	if crown != null:
		# Slow turn and gentle bob so the crown reads as a separate, special object.
		crown_clock += delta
		crown.rotation.y = crown_clock * 0.9
		crown.position.y = crown_base_y + 0.08 * sin(crown_clock * 2.4)
	if state == State.CHASE:
		var offset := swarm_position - global_position
		offset.y = 0.0
		var arena: Node3D = get_parent().get_parent().get_node("Arena")
		# Etappe 07: the (costly) line test only runs in attack range; same result.
		if offset.length() <= 3.0 and arena.clear_line(position, swarm_position, 0.8).distance_to(position) >= offset.length() - 0.3:
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
		body.position.y = body_base_y + 0.14 * sin((1.0 - remaining / TUNING.HUNTER_WARNING_SECONDS) * PI)
	if remaining > 0.0:
		return 0
	if state == State.ARRIVING:
		state = State.CHASE
		warning.visible = false
	elif state == State.WARNING:
		state = State.RECOVERY
		remaining = TUNING.recovery(TUNING.HUNTER_RECOVERY_SECONDS, pressure, 0.55)
		warning.visible = false
		body.position.y = body_base_y
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


static func _shared_parts() -> Dictionary:
	if not _parts.is_empty():
		return _parts
	var armor := SphereMesh.new()
	armor.radius = 0.72
	armor.height = 1.05
	armor.radial_segments = 24
	armor.rings = 12
	var horn := CylinderMesh.new()
	horn.top_radius = 0.0
	horn.bottom_radius = 0.24
	horn.height = 0.75
	horn.radial_segments = 12
	horn.rings = 1
	var face := BoxMesh.new()
	face.size = Vector3(0.9, 0.25, 0.3)
	var eye := SphereMesh.new()
	eye.radius = 0.10
	eye.height = 0.12
	eye.radial_segments = 10
	eye.rings = 5
	var bar := BoxMesh.new()
	bar.size = Vector3(1.4, 0.07, 0.13)
	var band := CylinderMesh.new()
	band.top_radius = 0.44
	band.bottom_radius = 0.48
	band.height = 0.18
	band.radial_segments = 12
	band.rings = 1
	var spike := CylinderMesh.new()
	spike.top_radius = 0.0
	spike.bottom_radius = 0.13
	spike.height = 0.42
	spike.radial_segments = 6
	spike.rings = 1
	var crown_parts: Array = [[band, Transform3D.IDENTITY]]
	for index in 5:
		var angle := TAU * float(index) / 5.0
		crown_parts.append([spike, Transform3D(Basis.IDENTITY, Vector3(cos(angle) * 0.38, 0.28, sin(angle) * 0.38))])
	var gem := SphereMesh.new()
	gem.radius = 0.09
	gem.height = 0.18
	gem.radial_segments = 8
	gem.rings = 4
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color("ffbf1f")
	gold.metallic = 0.1
	gold.roughness = 0.35
	gold.emission_enabled = true
	gold.emission = Color("ffb347")
	gold.emission_energy_multiplier = 0.9
	_parts = {
		"armor": armor,
		"horns": FX_BATCH.merge([[horn, Transform3D(Basis.IDENTITY, Vector3(-0.5, 1.0, -0.2))], [horn, Transform3D(Basis.IDENTITY, Vector3(0.5, 1.0, -0.2))]]),
		"face": face,
		"eyes": FX_BATCH.merge([[eye, Transform3D(Basis.IDENTITY, Vector3(-0.24, 0.76, 0.73))], [eye, Transform3D(Basis.IDENTITY, Vector3(0.24, 0.76, 0.73))]]),
		"bar": bar,
		"crown": FX_BATCH.merge(crown_parts),
		"gem": gem,
		"gold": gold,
	}
	return _parts


func _part(parent: Node3D, mesh: Mesh, material: Material, location: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = location
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part


static func _load_beetle() -> bool:
	if not _beetle_checked:
		_beetle_checked = true
		if ResourceLoader.exists(BEETLE_PATH):
			var root: Node = (load(BEETLE_PATH) as PackedScene).instantiate()
			var found := root.find_children("*", "MeshInstance3D", true, false)
			if not found.is_empty():
				var source: MeshInstance3D = found[0]
				var base := Transform3D.IDENTITY
				var node: Node = source
				while node != root and node is Node3D:
					base = (node as Node3D).transform * base
					node = node.get_parent()
				_beetle_mesh = source.mesh
				_beetle_base = base
			root.free()
	return _beetle_mesh != null


# Beetle model under a pivot `body` at the feet, head along +Z, scaled so its
# longest ground extent is BEETLE_LENGTH (same footprint as the old shell).
func _build_beetle() -> void:
	body = Node3D.new()
	body.name = "Hunter Beetle"
	body_base_y = 0.0
	add_child(body)
	skin = ShaderMaterial.new()
	skin.shader = CREATURE_SHADER
	skin.set_shader_parameter("brightness", 1.35)
	skin.set_shader_parameter("saturation", 1.25)
	skin.set_shader_parameter("shape_light", 0.3)
	skin.set_shader_parameter("rim_power", 3.2)
	skin.set_shader_parameter("rim_color", Color("ff9a55"))
	skin.set_shader_parameter("rim_strength", 0.6)
	var model := MeshInstance3D.new()
	model.mesh = _beetle_mesh
	model.material_override = skin
	model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var raw: AABB = Transform3D(_beetle_base.basis, Vector3.ZERO) * _beetle_mesh.get_aabb()
	var extent := maxf(raw.size.x, raw.size.z)
	var shape := Basis.from_scale(Vector3.ONE * (BEETLE_LENGTH / maxf(0.01, extent))) * _beetle_base.basis
	var bounds: AABB = Transform3D(shape, Vector3.ZERO) * _beetle_mesh.get_aabb()
	model.transform = Transform3D(shape, Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z))
	body.add_child(model)
	body_top = bounds.size.y


static func _load_crown() -> Mesh:
	if not _crown_checked:
		_crown_checked = true
		if ResourceLoader.exists(CROWN_PATH):
			var root: Node = (load(CROWN_PATH) as PackedScene).instantiate()
			var found := root.find_children("*", "MeshInstance3D", true, false)
			if not found.is_empty():
				var source: MeshInstance3D = found[0]
				var base := Transform3D.IDENTITY
				var node: Node = source
				while node != root and node is Node3D:
					base = (node as Node3D).transform * base
					node = node.get_parent()
				_crown_mesh = source.mesh
				_crown_base = base
			root.free()
		if _crown_mesh != null:
			# Same look as creature.gdshader, but a separate (path-less) shader:
			# gold recolour of the vertex colours and a warm glow.
			var shader := Shader.new()
			shader.code = CREATURE_SHADER.code
			_crown_skin = ShaderMaterial.new()
			_crown_skin.shader = shader
			_crown_skin.set_shader_parameter("brightness", 1.45)
			_crown_skin.set_shader_parameter("saturation", 1.3)
			_crown_skin.set_shader_parameter("body_tint", Color(1.0, 0.76, 0.2, 0.75))
			_crown_skin.set_shader_parameter("shape_light", 0.3)
			_crown_skin.set_shader_parameter("rim_power", 2.2)
			_crown_skin.set_shader_parameter("rim_color", Color("fff1a8"))
			_crown_skin.set_shader_parameter("rim_strength", 0.7)
	return _crown_mesh
