extends Node3D

const MAWLING_SCENE = preload("res://assets/gameplay/characters/Mawling_game.glb")
const CREATURE_SHADER = preload("res://shaders/creature_anim.gdshader")
const FX = preload("res://scripts/fx.gd")

const START_POPULATION := 25
const MOVE_SPEED := 7.0
const FOLLOW_SPEED := 7.0
const GOLDEN_ANGLE := 2.39996323
const VISUAL_LIMIT := 120

# Purely visual tuning; none of this feeds back into game state.
const WANDER := 0.15
const TRAIL_SECONDS := 0.07
const HOP_HEIGHT := 0.2
const GAIT_RATE := 11.0
const HATCH_SECONDS := 0.3
const FLASH_SECONDS := 0.25
const PUSH_RADIUS := 5.0
const PUSH_SPEED := 9.0
const PUSH_DAMPING := 6.0
const MAX_GHOSTS := 28
const MAX_HIT_COPIES := 12
const GHOST_FLIGHT := 0.8
const GHOST_SHRINK := 0.3
const GHOST_GRAVITY := 16.0
const GHOST_AXIS := Vector3(0.8, 0.0, 0.6)
const SHADOW_Y := 0.03
const HALO_Y := 0.012
const CORAL := Color(1.0, 0.45, 0.25)
const CORAL_LIGHT := Color(1.0, 0.68, 0.48)

enum Focus { NONE, ATTACK, HARVEST }

var movement_vector := Vector2.ZERO
var rally_pressed := false
var units: Array[Node3D] = []
var population := START_POPULATION
var game_material: ShaderMaterial
var ghost_material: ShaderMaterial

# Per-unit animation state, index-aligned with `units`.
var unit_phase := PackedFloat32Array()
var unit_follow := PackedFloat32Array()
var unit_gait := PackedFloat32Array()
var unit_speed := PackedFloat32Array()
var unit_hatch := PackedFloat32Array()
var unit_push := PackedVector3Array()

# Falling-away ghosts of removed units; they are no longer part of `units`.
var ghosts: Array[Node3D] = []
var ghost_velocity := PackedVector3Array()
var ghost_age := PackedFloat32Array()
var ghost_spin := PackedFloat32Array()
var fresh_ghost_from := 0
var removed_since_frame := 0
var pending_loss := 0
var pending_impact := Vector3.ZERO

var focus_position := Vector3.ZERO
var focus_mode := 0
var attack_blend := 0.0
var harvest_blend := 0.0
var rally_blend := 0.0
var flash := 0.0
var clock := 0.0
var swarm_velocity := Vector3.ZERO
var display_scale := 0.91

var shadows: MultiMeshInstance3D
var halo: MeshInstance3D
var halo_material: StandardMaterial3D
var ring: MeshInstance3D
var ring_material: StandardMaterial3D


func _ready() -> void:
	game_material = _creature_material(0.0)
	ghost_material = _creature_material(0.4)
	_build_ground_marks()
	set_population(START_POPULATION, false)
	for index in units.size():
		var angle := float(index) * GOLDEN_ANGLE
		var radius := sqrt((float(index) + 0.5) / float(units.size())) * 2.65
		units[index].position = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	_update_ground_marks(2.65)


func set_population(value: int, animate: bool = true) -> void:
	# Without processing nothing would finish animating, so fall back to instant.
	animate = animate and is_inside_tree() and is_processing()
	population = maxi(0, value)
	var target := mini(population, VISUAL_LIMIT)
	while units.size() < target:
		var index := units.size()
		var unit := _make_unit()
		unit.rotation.y = float(index) * GOLDEN_ANGLE
		if animate:
			unit.position = Vector3(cos(float(index)) * 0.25, 0.0, sin(float(index)) * 0.25)
		add_child(unit)
		units.append(unit)
		unit_phase.append(fposmod(float(index) * 0.7548777, 1.0) * TAU)
		unit_follow.append(0.7 + 0.6 * fposmod(float(index) * 0.618034 + 0.31, 1.0))
		unit_gait.append(fposmod(float(index) * 1.3247, 1.0) * TAU)
		unit_speed.append(0.0)
		unit_hatch.append(0.0 if animate else 1.0)
		unit_push.append(Vector3.ZERO)
		_pose_model(unit, 0.0, 0.0, 0.0, 0.0 if animate else 1.0, 0.0)
	while units.size() > target:
		var unit: Node3D = units.pop_back()
		if animate:
			_launch_ghost(unit, Vector3.ZERO)
			removed_since_frame += 1
		else:
			unit.queue_free()
	var count := units.size()
	unit_phase.resize(count)
	unit_follow.resize(count)
	unit_gait.resize(count)
	unit_speed.resize(count)
	unit_hatch.resize(count)
	unit_push.resize(count)
	if not animate:
		_clear_ghosts()
	display_scale = lerpf(0.91, 0.58, clampf(float(population - 25) / 225.0, 0.0, 1.0))
	for unit in units:
		unit.scale = Vector3.ONE * display_scale
	if shadows != null:
		shadows.multimesh.visible_instance_count = count


func set_controls(direction: Vector2, rally: bool) -> void:
	if rally and not rally_pressed and is_inside_tree() and not units.is_empty():
		var radius := _flow_radius() + 0.6
		FX.ring(self, global_position, Color(CORAL_LIGHT.r, CORAL_LIGHT.g, CORAL_LIGHT.b, 0.55), radius, radius * 0.42, 0.3)
	movement_vector = direction.limit_length(1.0)
	rally_pressed = rally


func set_focus(world_position: Vector3, mode: int) -> void:
	focus_mode = mode
	if mode != Focus.NONE:
		focus_position = world_position


func clear_focus() -> void:
	focus_mode = Focus.NONE


# Visual reaction to a resolved hit: flash, shove survivors, fling extra losses.
func react_to_hit(loss: int, impact: Vector3) -> void:
	if loss <= 0:
		return
	flash = 1.0
	game_material.set_shader_parameter("flash", flash)
	var local_impact := impact - global_position if is_inside_tree() else impact - position
	local_impact.y = 0.0
	for index in units.size():
		var away := units[index].position - local_impact
		away.y = 0.0
		var distance := away.length()
		if distance >= PUSH_RADIUS:
			continue
		var direction := away / distance if distance > 0.05 else Vector3(cos(unit_phase[index]), 0.0, sin(unit_phase[index]))
		unit_push[index] += direction * PUSH_SPEED * (1.0 - distance / PUSH_RADIUS)
	if is_processing():
		pending_loss += loss
		pending_impact = local_impact


# Set by Main while paused, choosing a mutation or extinct: poses hold still,
# only already-launched falling ghosts and the hit flash finish.
var frozen := false


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	if frozen:
		_update_ghosts(delta)
		if flash > 0.0:
			flash = maxf(0.0, flash - delta / FLASH_SECONDS)
			game_material.set_shader_parameter("flash", flash * flash)
		game_material.set_shader_parameter("idle_motion", 0.0)
		return
	game_material.set_shader_parameter("idle_motion", 1.0)
	var before := position
	var motion := Vector3(movement_vector.x, 0.0, movement_vector.y) * MOVE_SPEED * delta
	position = get_parent().get_node("Arena").resolve_motion(position, motion, 0.75)
	swarm_velocity = (position - before) / delta if delta > 0.0 else Vector3.ZERO
	swarm_velocity.y = 0.0
	clock += delta
	_resolve_pending_hit()
	_animate_units(delta)
	_update_ghosts(delta)
	if flash > 0.0:
		flash = maxf(0.0, flash - delta / FLASH_SECONDS)
		game_material.set_shader_parameter("flash", flash * flash)


func _animate_units(delta: float) -> void:
	var fade := 1.0 - exp(-6.0 * delta)
	rally_blend = lerpf(rally_blend, 1.0 if rally_pressed else 0.0, 1.0 - exp(-9.0 * delta))
	attack_blend = lerpf(attack_blend, 1.0 if focus_mode == Focus.ATTACK else 0.0, fade)
	harvest_blend = lerpf(harvest_blend, 1.0 if focus_mode == Focus.HARVEST else 0.0, fade)
	var flow_radius := _flow_radius()
	var radius := lerpf(flow_radius, flow_radius * 0.42, rally_blend)
	var focus_local := focus_position - global_position
	focus_local.y = 0.0
	var focus_strength := attack_blend * 0.5 + harvest_blend * 0.3
	var reach := radius * 2.2 + 1.0
	var count := units.size()
	var damping := exp(-PUSH_DAMPING * delta)
	var multimesh := shadows.multimesh
	# Jaw values only need refreshing while (or just after) attacking or harvesting.
	var bite_active := attack_blend + harvest_blend > 0.002
	for index in count:
		var unit := units[index]
		var phase := unit_phase[index]
		var follow := unit_follow[index]
		var angle := float(index) * GOLDEN_ANGLE
		var fraction := sqrt((float(index) + 0.5) / float(count))
		var goal := Vector3(cos(angle) * fraction * radius, 0.0, sin(angle) * fraction * radius)
		goal.x += WANDER * sin(clock * 0.7 + phase)
		goal.z += WANDER * cos(clock * 0.53 + phase * 1.7)
		# Slower followers hang further back and stretch the swarm while moving.
		goal -= swarm_velocity * TRAIL_SECONDS * (2.3 - follow)
		var pull := 0.0
		if focus_strength > 0.01:
			var to_focus := focus_local - goal
			var distance := to_focus.length()
			pull = focus_strength * clampf(1.0 - distance / reach, 0.2, 1.0)
			goal += to_focus.limit_length(2.6) * pull
		var old := unit.position
		var response := 1.0 - exp(-FOLLOW_SPEED * follow * delta)
		var next := old.lerp(Vector3(goal.x, 0.0, goal.z), response)
		var push := unit_push[index]
		if push.length_squared() > 0.0001:
			next += push * delta
			unit_push[index] = push * damping
		next.y = 0.0
		unit.position = next
		# Own world velocity drives facing and gait.
		var velocity := (next - old) / maxf(delta, 0.001) + swarm_velocity
		velocity.y = 0.0
		var speed := velocity.length()
		var speed_share := lerpf(unit_speed[index], clampf(speed / MOVE_SPEED, 0.0, 1.0), 1.0 - exp(-8.0 * delta))
		unit_speed[index] = speed_share
		var turn := 1.0 - exp(-10.0 * delta)
		if speed > 0.45:
			unit.rotation.y = lerp_angle(unit.rotation.y, atan2(velocity.x, velocity.z) + PI * 0.5, turn)
		elif pull > 0.05:
			var look := focus_local - next
			if look.length_squared() > 0.04:
				unit.rotation.y = lerp_angle(unit.rotation.y, atan2(look.x, look.z) + PI * 0.5, turn * 0.6)
		# Waddling hop gait; its phase advances with speed so idle animals rest.
		var gait := unit_gait[index] + delta * GAIT_RATE * (0.85 + 0.3 * follow) * speed_share
		unit_gait[index] = fmod(gait, TAU * 8.0)
		var hop := absf(sin(gait)) * HOP_HEIGHT * speed_share
		var roll := sin(gait) * 0.16 * speed_share
		var pitch := 0.12 * speed_share
		var jaw := 0.0
		if pull > 0.05:
			var bite := pow(maxf(0.0, sin(clock * 14.0 + phase * 3.0)), 3.0) * 0.5
			var peck := pow(0.5 + 0.5 * sin(clock * 4.5 + phase * 2.0), 2.0) * 0.55
			var weight := clampf(pull / 0.3, 0.0, 1.0)
			pitch += (bite * attack_blend + peck * harvest_blend) * weight
			jaw = clampf((bite * 2.0 * attack_blend + peck * harvest_blend) * weight, 0.0, 1.0)
		var breath := sin(clock * 2.2 + phase) * 0.035 * (1.0 - speed_share)
		var hatch := unit_hatch[index]
		if hatch < 1.0:
			hatch = minf(1.0, hatch + delta / HATCH_SECONDS)
			unit_hatch[index] = hatch
		var grown := _back_out(hatch)
		_pose_model(unit, hop, roll, pitch, grown, breath)
		# Leg cycle (creature_anim.gdshader) locked to the hop: feet land as the hop ends.
		var mesh := _unit_mesh(unit)
		mesh.set_instance_shader_parameter("instance_walk", speed_share)
		mesh.set_instance_shader_parameter("instance_phase", fmod(gait, TAU) + PI * 0.5)
		if bite_active:
			mesh.set_instance_shader_parameter("instance_bite", jaw)
		var shadow_size := display_scale * 1.05 * grown * (1.0 - hop * 1.4)
		multimesh.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3(shadow_size, 1.0, shadow_size)), Vector3(next.x, SHADOW_Y, next.z)))
	multimesh.visible_instance_count = count
	_update_ground_marks(radius)


func _unit_mesh(unit: Node3D) -> GeometryInstance3D:
	return unit.get_child(0).get_child(0)


func _pose_model(unit: Node3D, hop: float, roll: float, pitch: float, grown: float, breath: float) -> void:
	var model: Node3D = unit.get_child(0)
	var size := Vector3(grown * (1.0 - breath * 0.5), grown * (1.0 + breath), grown * (1.0 - breath * 0.5))
	model.transform = Transform3D(Basis.from_euler(Vector3(roll, 0.0, pitch)).scaled(size), Vector3(0.0, hop, 0.0))


func _update_ground_marks(radius: float) -> void:
	var visible_swarm := not units.is_empty()
	var halo_radius := radius + 0.6
	halo.visible = visible_swarm
	halo.scale = Vector3(halo_radius, 1.0, halo_radius)
	halo_material.albedo_color = Color(CORAL.r, CORAL.g, CORAL.b, lerpf(0.10, 0.2, rally_blend))
	ring.visible = visible_swarm and rally_blend > 0.01
	var pulse := 1.0 + 0.04 * sin(clock * 9.0)
	ring.scale = Vector3(halo_radius * pulse, 0.3, halo_radius * pulse)
	ring_material.albedo_color = Color(CORAL_LIGHT.r, CORAL_LIGHT.g, CORAL_LIGHT.b, 0.6 * rally_blend)


func _resolve_pending_hit() -> void:
	if pending_loss > 0:
		# Aim this frame's fallen units away from the impact.
		for index in range(fresh_ghost_from, ghosts.size()):
			ghost_velocity[index] = _fling_velocity(ghosts[index].global_position - global_position, pending_impact, ghost_spin[index])
		var copies := mini(pending_loss - removed_since_frame, MAX_HIT_COPIES)
		for copy in copies:
			if units.is_empty() or ghosts.size() >= MAX_GHOSTS:
				break
			var source := units[(copy * 37 + pending_loss) % units.size()]
			var ghost := _make_unit()
			add_child(ghost)
			ghost.transform = source.transform
			_pose_model(ghost, 0.0, 0.0, 0.0, 1.0, 0.0)
			_launch_ghost(ghost, pending_impact)
	pending_loss = 0
	removed_since_frame = 0
	fresh_ghost_from = ghosts.size()


func _launch_ghost(unit: Node3D, impact: Vector3) -> void:
	if ghosts.size() >= MAX_GHOSTS:
		unit.queue_free()
		return
	var local := unit.position
	var world := unit.global_transform
	unit.top_level = true
	unit.global_transform = world
	for mesh in unit.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = ghost_material
	var spin := (fposmod(float(ghosts.size() + unit.get_instance_id()) * 0.618034, 1.0) - 0.5) * 16.0
	ghosts.append(unit)
	ghost_velocity.append(_fling_velocity(local, impact, spin))
	ghost_age.append(0.0)
	ghost_spin.append(spin)


func _fling_velocity(local: Vector3, impact: Vector3, spin: float) -> Vector3:
	var away := local - impact
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3(cos(spin), 0.0, sin(spin))
	return away.normalized() * 3.2 + Vector3(0.0, 5.0 + absf(spin) * 0.1, 0.0)


func _update_ghosts(delta: float) -> void:
	var index := ghosts.size() - 1
	while index >= 0:
		var ghost := ghosts[index]
		var age := ghost_age[index] + delta
		if age >= GHOST_FLIGHT + GHOST_SHRINK or not is_instance_valid(ghost):
			if is_instance_valid(ghost):
				ghost.queue_free()
			_remove_ghost(index)
			index -= 1
			continue
		ghost_age[index] = age
		var velocity := ghost_velocity[index]
		velocity.y -= GHOST_GRAVITY * delta
		var next := ghost.global_position + velocity * delta
		if next.y < 0.0:
			next.y = 0.0
			velocity = Vector3(velocity.x * 0.4, -velocity.y * 0.25, velocity.z * 0.4)
		ghost_velocity[index] = velocity
		ghost.global_position = next
		ghost.rotate_object_local(GHOST_AXIS, ghost_spin[index] * delta)
		var shrink := clampf((age - GHOST_FLIGHT) / GHOST_SHRINK, 0.0, 1.0)
		var size := display_scale * (1.0 - shrink * shrink)
		ghost.scale = Vector3.ONE * maxf(size, 0.001)
		index -= 1


func _remove_ghost(index: int) -> void:
	ghosts.remove_at(index)
	ghost_velocity.remove_at(index)
	ghost_age.remove_at(index)
	ghost_spin.remove_at(index)
	if index < fresh_ghost_from:
		fresh_ghost_from -= 1


func _clear_ghosts() -> void:
	for ghost in ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()
	ghosts.clear()
	ghost_velocity.resize(0)
	ghost_age.resize(0)
	ghost_spin.resize(0)
	fresh_ghost_from = 0
	removed_since_frame = 0
	pending_loss = 0


func _flow_radius() -> float:
	return 2.65 + maxf(0.0, sqrt(float(population) / 25.0) - 1.0) * 0.55


# Ease-out with a slight overshoot so hatchlings pop into place.
func _back_out(t: float) -> float:
	var s := t - 1.0
	return 1.0 + 2.70158 * s * s * s + 1.70158 * s * s


func _make_unit() -> Node3D:
	var unit := Node3D.new()
	unit.name = "Mawling"
	var model: Node3D = MAWLING_SCENE.instantiate()
	model.name = "Game model"
	model.scale = Vector3.ONE
	unit.add_child(model)
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = game_material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return unit


func _creature_material(base_flash: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CREATURE_SHADER
	material.set_shader_parameter("brightness", 1.2)
	material.set_shader_parameter("saturation", 1.15)
	material.set_shader_parameter("shape_light", 0.35)
	material.set_shader_parameter("rim_color", Color("ffb27a"))
	material.set_shader_parameter("rim_strength", 0.45)
	material.set_shader_parameter("flash_color", Color("ffd9c9"))
	material.set_shader_parameter("flash", base_flash)
	# Limb animation frame for Mawling_game.glb, measured in raw mesh space (Z-up
	# storage): soles at z = +0.0008 (up = -Z), head/jaw towards -X, tail towards +X,
	# lateral = +Y. Feet centres (forward, lateral) from clustering the lowest 5 %
	# of vertices; the rest pose is already mid-stride (pair A spread, pair B tucked).
	material.set_shader_parameter("up_axis", Vector3(0.0, 0.0, -1.0))
	material.set_shader_parameter("forward_axis", Vector3(-1.0, 0.0, 0.0))
	material.set_shader_parameter("ground_offset", -0.0008)
	material.set_shader_parameter("foot_a_front", Vector2(0.239, -0.287))
	material.set_shader_parameter("foot_a_back", Vector2(-0.286, 0.205))
	material.set_shader_parameter("foot_b_front", Vector2(0.063, 0.239))
	material.set_shader_parameter("foot_b_back", Vector2(-0.052, -0.191))
	material.set_shader_parameter("foot_radius", 0.15)
	material.set_shader_parameter("leg_height", 0.22)
	material.set_shader_parameter("stride", 0.09)
	material.set_shader_parameter("lift", 0.09)
	material.set_shader_parameter("stride_centering", 0.5)
	# Script drives the cycle per instance (instance_phase / instance_walk); ghosts stay still.
	material.set_shader_parameter("walk_speed", 0.0)
	material.set_shader_parameter("walk_amount", 0.0)
	material.set_shader_parameter("walk_scale", 1.0 if base_flash <= 0.0 else 0.0)
	material.set_shader_parameter("jaw_hinge_forward", 0.12)
	material.set_shader_parameter("jaw_hinge_height", 0.47)
	material.set_shader_parameter("jaw_floor", 0.22)
	material.set_shader_parameter("jaw_angle", 0.45)
	material.set_shader_parameter("bite_amount", 0.0)
	material.set_shader_parameter("tail_start", -0.34)
	material.set_shader_parameter("tail_length", 0.26)
	material.set_shader_parameter("tail_floor", 0.1)
	material.set_shader_parameter("tail_swing", 0.06)
	material.set_shader_parameter("tail_rate", 3.0)
	return material


func _build_ground_marks() -> void:
	var shadow_gradient := Gradient.new()
	shadow_gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	shadow_gradient.colors = PackedColorArray([Color(0, 0, 0, 1), Color(0, 0, 0, 0.6), Color(0, 0, 0, 0)])
	var shadow_material := _ground_material(_radial_texture(shadow_gradient), Color(0, 0, 0, 0.38))
	shadow_material.render_priority = 1
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = plane
	multimesh.instance_count = VISUAL_LIMIT
	multimesh.visible_instance_count = 0
	shadows = MultiMeshInstance3D.new()
	shadows.name = "Shadows"
	shadows.multimesh = multimesh
	shadows.material_override = shadow_material
	shadows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadows)

	var halo_gradient := Gradient.new()
	halo_gradient.offsets = PackedFloat32Array([0.0, 0.78, 1.0])
	halo_gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	halo_material = _ground_material(_radial_texture(halo_gradient), Color(CORAL.r, CORAL.g, CORAL.b, 0.1))
	var disc := PlaneMesh.new()
	disc.size = Vector2(2.0, 2.0)
	halo = MeshInstance3D.new()
	halo.name = "Swarm halo"
	halo.mesh = disc
	halo.material_override = halo_material
	halo.position.y = HALO_Y
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)

	ring_material = _ground_material(null, Color(CORAL_LIGHT.r, CORAL_LIGHT.g, CORAL_LIGHT.b, 0.0))
	var torus := TorusMesh.new()
	torus.inner_radius = 0.93
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 6
	ring = MeshInstance3D.new()
	ring.name = "Rally ring"
	ring.mesh = torus
	ring.material_override = ring_material
	ring.position.y = HALO_Y + 0.005
	ring.visible = false
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)


func _ground_material(texture: Texture2D, tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = tint
	material.albedo_texture = texture
	return material


func _radial_texture(gradient: Gradient) -> GradientTexture2D:
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture
