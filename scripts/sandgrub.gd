extends Node3D

# SANDMADE (stage 19, desert "Dürrschlund"): small, pale, fast segmented grubs
# (user model Sandgrub_game.glb, head +Z) that the Sandwurm frees in phase 2 and
# that later can join desert spawns. They burst out of the sand, run straight at
# the nearest Mawling and bite (a small, quick horde – Moorbrut logic, but faster
# and only a handful at a time).
#
# Same contract as scripts/horde.gd, so HuntWorld can drive it like the Moorbrut:
#   setup(world, swarm, arena)                optional (arena: fold_inside / resolve_motion)
#   spawn_burst(center, amount, stats := {})  emerge in a small cluster (worm hole)
#   spawn_ring(center, amount, radius, stats) horde-compatible ring spawn
#   step(delta, swarm_points) -> {"bitten_indices": PackedInt32Array, "losses": float}
#   melee(swarm_points, reach, dps, delta) -> killed   (the swarm bites back)
#   damage_circle(center, radius, amount) -> killed, damage_nearest(point, range, amount)
#   take_kills() -> [{position, biomass, dna, count}]   (bundled like the horde)
#   count(), positions(), nearest(point), clear()
# Everything runs in step()/the damage calls only: pause freezes the grubs.
# Drawn with ONE MultiMesh (creature_anim.gdshader via INSTANCE_CUSTOM: walk,
# gait phase, jaw, glow) plus one shadow MultiMesh and one dust MultiMesh.
#
# Numbers (per grub, before HuntWorld's pressure scaling in phase 2):
#   hp 8 (a Moorbrut has 6), speed 5.6 m/s (Moorbrut 4.8, swarm ~7: it can be
#   outrun, but not by much), bite 1 per 0.9 s, 0.6 biomass, 1 DNA.
#   MAX_GRUBS 32 alive; a phase-2 breach frees 4, the rage 6.

const CREATURE_SHADER = preload("res://shaders/creature_anim.gdshader")
const MODEL_SCENE = preload("res://assets/gameplay/characters/Sandgrub_game.glb")
const FX_BATCH = preload("res://scripts/fx_batch.gd")

const MAX_GRUBS := 32
const DEFAULT_STATS := {"hp": 8.0, "speed": 5.6, "bite": 1.0, "bite_cooldown": 0.9, "biomass": 0.6, "dna": 1}
const BITE_RANGE := 0.6
const LUNGE_RANGE := 1.8
const LUNGE_BOOST := 1.5
# Beyond this distance the grubs follow the arena flow field (stage 19).
const FLOW_NEAR := 5.0
const BODY_RADIUS := 0.32
const SEPARATION := 0.7
const SEPARATION_PUSH := 2.4
const EMERGE_SECONDS := 0.45
# Outside the worm's column (body radius 2.4), so the grubs are seen breaking out.
const BURST_RADIUS := 3.6
const SNAP_SECONDS := 0.2
const KILL_BUNDLE_RADIUS := 3.2
# Raw model: ~1.03 m long, 0.54 m high; at 0.85 x a grub is ~0.87 m long
# (a Mawling stands ~0.64 m), clearly smaller than a Nibbler.
const MODEL_SCALE := 0.85
# Pale sand body: a warm ochre pull, dark contour and amber rim keep it
# readable on light desert sand (the model itself is almost sand-coloured).
const BODY_TINT := Color(0.66, 0.42, 0.22, 0.42)
const RIM := Color("ffb347")
const DUST := Color(0.93, 0.85, 0.68, 0.6)
const SHADOW_Y := 0.03
const GAIT_RATE := 16.0
const HOP := 0.05
const DUST_MAX := 48

var world: Node3D
var swarm: Node3D
var arena: Node3D

var _pos := PackedVector3Array()
var _hp := PackedFloat32Array()
var _max_hp := PackedFloat32Array()
var _speed := PackedFloat32Array()
var _bite := PackedFloat32Array()
var _bite_cd := PackedFloat32Array()
var _cd := PackedFloat32Array()
var _yaw := PackedFloat32Array()
var _gait := PackedFloat32Array()
var _walk := PackedFloat32Array()
var _snap := PackedFloat32Array()
var _flash := PackedFloat32Array()
var _appear := PackedFloat32Array()
var _biomass := PackedFloat32Array()
var _dna := PackedInt32Array()
var _kills: Array = []
var _bite_carry := 0.0
var _frame := 0
var last_hit_count := 0
var total_kills := 0
var total_bites := 0

var _built := false
var _bodies: MultiMeshInstance3D
var _shadows: MultiMeshInstance3D
var _dust_batch: MultiMeshInstance3D
var _base := Transform3D.IDENTITY
var _dust: Array[Dictionary] = []


func setup(world_node: Node3D, swarm_node: Node3D, arena_node: Node3D) -> void:
	world = world_node
	swarm = swarm_node
	arena = arena_node
	_build()


func count() -> int:
	return _pos.size()


func positions() -> PackedVector3Array:
	return _pos.duplicate()


## Grubs break out of the sand in a cluster around `center` (e.g. a worm hole).
func spawn_burst(center: Vector3, amount: int, stats: Dictionary = {}) -> int:
	var spawned := 0
	var offset := fposmod(float(_frame) * 0.618034 + center.x * 0.13, 1.0) * TAU
	for k in mini(amount, MAX_GRUBS - count()):
		var angle := offset + TAU * float(k) / float(maxi(1, amount))
		var reach := BURST_RADIUS * (0.55 + 0.45 * fposmod(float(k) * 0.7548777, 1.0))
		if _add(Vector3(center.x + cos(angle) * reach, 0.0, center.z + sin(angle) * reach), angle, stats, k):
			spawned += 1
	return spawned


## Horde-compatible ring spawn (desert spawns later can reuse HuntWorld's code).
func spawn_ring(center: Vector3, amount: int, radius: float, stats: Dictionary) -> int:
	var spawned := 0
	var offset := fposmod(float(_frame) * 0.618034 + center.x * 0.13, 1.0) * TAU
	for k in mini(amount, MAX_GRUBS - count()):
		var angle := offset + TAU * float(k) / float(maxi(1, amount))
		if _add(Vector3(center.x + cos(angle) * radius, 0.0, center.z + sin(angle) * radius), angle + PI, stats, k):
			spawned += 1
	return spawned


func _add(place: Vector3, facing: float, stats: Dictionary, k: int) -> bool:
	_build()
	if count() >= MAX_GRUBS:
		return false
	if arena != null and is_instance_valid(arena) and arena.has_method("fold_inside"):
		place = arena.fold_inside(place, BODY_RADIUS + 1.0)
	# Stage 19: the worm digs under walls; its grubs break out on open sand.
	if arena != null and is_instance_valid(arena) and arena.has_method("safe_spawn"):
		place = arena.safe_spawn(place, BODY_RADIUS + 0.2)
	place.y = 0.0
	var hp := maxf(0.1, float(stats.get("hp", DEFAULT_STATS.hp)))
	var cooldown := maxf(0.05, float(stats.get("bite_cooldown", DEFAULT_STATS.bite_cooldown)))
	_pos.append(place)
	_hp.append(hp)
	_max_hp.append(hp)
	_speed.append(maxf(0.1, float(stats.get("speed", DEFAULT_STATS.speed))) * (0.93 + 0.14 * fposmod(float(k) * 0.381966, 1.0)))
	_bite.append(maxf(0.0, float(stats.get("bite", DEFAULT_STATS.bite))))
	_bite_cd.append(cooldown)
	_cd.append(cooldown * 0.5 + cooldown * 0.5 * fposmod(float(k) * 0.618034, 1.0))
	_yaw.append(facing)
	_gait.append(fposmod(float(k) * 1.3247, 1.0) * TAU)
	_walk.append(0.0)
	_snap.append(0.0)
	_flash.append(0.0)
	_appear.append(0.0)
	_biomass.append(maxf(0.0, float(stats.get("biomass", DEFAULT_STATS.biomass))))
	_dna.append(maxi(0, int(stats.get("dna", DEFAULT_STATS.dna))))
	for puff in 3:
		var angle := facing + TAU * float(puff) / 3.0
		_add_dust(place + Vector3(cos(angle) * 0.3, 0.15, sin(angle) * 0.3), Vector3(cos(angle), 1.4, sin(angle)) * 1.2, 0.6, 0.7)
	_draw()
	return true


func step(delta: float, swarm_points: PackedVector3Array) -> Dictionary:
	var bitten := PackedInt32Array()
	var losses := 0.0
	if delta <= 0.0:
		return {"bitten_indices": bitten, "losses": 0.0}
	_build()
	_frame += 1
	var n := count()
	var center := Vector3.ZERO
	for point in swarm_points:
		center += point
	if not swarm_points.is_empty():
		center /= float(swarm_points.size())
	elif swarm != null and is_instance_valid(swarm):
		center = swarm.position
	for i in n:
		var p := _pos[i]
		_flash[i] = maxf(0.0, _flash[i] - delta * 6.0)
		_snap[i] = maxf(0.0, _snap[i] - delta / SNAP_SECONDS)
		_cd[i] = maxf(0.0, _cd[i] - delta)
		if _appear[i] < 1.0:
			# Breaking out of the sand: no movement, no bite yet.
			_appear[i] = minf(1.0, _appear[i] + delta / EMERGE_SECONDS)
			continue
		# Target: nearest Mawling (or the swarm centre without visible points).
		var target := center
		var target_index := -1
		var best := INF
		for j in swarm_points.size():
			var q := swarm_points[j]
			var d2 := (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z)
			if d2 < best:
				best = d2
				target = q
				target_index = j
		var to_target := Vector3(target.x - p.x, 0.0, target.z - p.z)
		var distance := to_target.length()
		if target_index < 0:
			best = distance * distance
		var move := Vector3.ZERO
		if distance > BITE_RANGE * 0.8:
			var boost := LUNGE_BOOST if distance < LUNGE_RANGE else 1.0
			move = to_target / maxf(distance, 0.001) * _speed[i] * boost
			# Stage 19: far from the swarm the grubs follow the paths (flow
			# field) instead of pressing into a wall between them and the swarm.
			if distance > FLOW_NEAR and arena != null and is_instance_valid(arena) and arena.has_method("flow_direction"):
				var guide: Vector3 = arena.flow_direction(p)
				if guide != Vector3.ZERO:
					move = Vector3(guide.x, 0.0, guide.z).normalized() * _speed[i]
		# Separation from the other grubs.
		for j in n:
			if j == i:
				continue
			var other := _pos[j]
			var away := Vector3(p.x - other.x, 0.0, p.z - other.z)
			var gap := away.length()
			if gap < SEPARATION and gap > 0.0001:
				move += away / gap * (SEPARATION - gap) * SEPARATION_PUSH / SEPARATION * _speed[i]
		var next := p + move * delta
		if arena != null and is_instance_valid(arena) and arena.has_method("resolve_motion"):
			next = arena.resolve_motion(p, move * delta, BODY_RADIUS)
		next.y = 0.0
		_pos[i] = next
		var speed := move.length()
		_walk[i] = lerpf(_walk[i], clampf(speed / 5.0, 0.0, 1.0), minf(1.0, delta * 10.0))
		_gait[i] = fposmod(_gait[i] + delta * GAIT_RATE * _walk[i], TAU * 8.0)
		if to_target.length_squared() > 0.0001:
			_yaw[i] = lerp_angle(_yaw[i], atan2(to_target.x, to_target.z), minf(1.0, delta * 12.0))
		# Bite: the nearest Mawling within reach.
		if target_index >= 0 and best <= BITE_RANGE * BITE_RANGE and _cd[i] <= 0.0:
			_cd[i] = _bite_cd[i]
			_snap[i] = 1.0
			bitten.append(target_index)
			losses += _bite[i]
			total_bites += 1
		elif target_index < 0 and distance <= BITE_RANGE * 1.5 and _cd[i] <= 0.0:
			_cd[i] = _bite_cd[i]
			_snap[i] = 1.0
			losses += _bite[i]
			total_bites += 1
	_step_dust(delta)
	_draw()
	return {"bitten_indices": bitten, "losses": losses}


func melee(swarm_points: PackedVector3Array, reach: float, dps: float, delta: float) -> int:
	if swarm_points.is_empty() or dps <= 0.0 or delta <= 0.0:
		return 0
	var killed := 0
	var r2 := reach * reach
	var i := count() - 1
	while i >= 0:
		var p := _pos[i]
		for q in swarm_points:
			if (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z) <= r2:
				if _hurt(i, dps * delta):
					killed += 1
				break
		i -= 1
	return killed


func damage_circle(center: Vector3, radius: float, amount: float) -> int:
	last_hit_count = 0
	if amount <= 0.0 or radius <= 0.0:
		return 0
	var killed := 0
	var r2 := radius * radius
	var i := count() - 1
	while i >= 0:
		var p := _pos[i]
		if (p.x - center.x) * (p.x - center.x) + (p.z - center.z) * (p.z - center.z) <= r2:
			last_hit_count += 1
			if _hurt(i, amount):
				killed += 1
		i -= 1
	return killed


func damage_nearest(point: Vector3, max_range: float, amount: float) -> Vector3:
	last_hit_count = 0
	var index := _nearest_index(point, max_range)
	if index < 0:
		return Vector3.INF
	var hit := _pos[index]
	last_hit_count = 1
	if amount > 0.0:
		_hurt(index, amount)
	return hit


func nearest(point: Vector3) -> Vector3:
	var index := _nearest_index(point, INF)
	return _pos[index] if index >= 0 else Vector3.INF


func take_kills() -> Array:
	if _kills.is_empty():
		return []
	var bundles: Array = []
	for kill in _kills:
		var merged := false
		for bundle in bundles:
			var at: Vector3 = bundle.position
			if Vector2(at.x - kill.position.x, at.z - kill.position.z).length() <= KILL_BUNDLE_RADIUS:
				var weight := float(bundle.count)
				bundle.position = (at * weight + kill.position) / (weight + 1.0)
				bundle.biomass += kill.biomass
				bundle.dna += kill.dna
				bundle.count += 1
				merged = true
				break
		if not merged:
			bundles.append({"position": kill.position, "biomass": kill.biomass, "dna": kill.dna, "count": 1})
	_kills.clear()
	return bundles


func clear() -> void:
	# Packed arrays are values: clear each member itself.
	_pos.clear()
	_hp.clear()
	_max_hp.clear()
	_speed.clear()
	_bite.clear()
	_bite_cd.clear()
	_cd.clear()
	_yaw.clear()
	_gait.clear()
	_walk.clear()
	_snap.clear()
	_flash.clear()
	_appear.clear()
	_biomass.clear()
	_dna.clear()
	_kills.clear()
	_dust.clear()
	last_hit_count = 0
	total_kills = 0
	total_bites = 0
	_draw()


func _nearest_index(point: Vector3, max_range: float) -> int:
	var best := max_range * max_range if max_range < INF else INF
	var result := -1
	for i in count():
		var p := _pos[i]
		var d2 := (p.x - point.x) * (p.x - point.x) + (p.z - point.z) * (p.z - point.z)
		if d2 <= best:
			best = d2
			result = i
	return result


func _hurt(i: int, amount: float) -> bool:
	_hp[i] -= amount
	_flash[i] = maxf(_flash[i], 1.0 if amount >= _max_hp[i] * 0.25 else 0.35)
	if _hp[i] > 0.0:
		return false
	_kill(i)
	return true


func _kill(i: int) -> void:
	var at := _pos[i]
	_kills.append({"position": at, "biomass": _biomass[i], "dna": _dna[i]})
	total_kills += 1
	for puff in 4:
		var angle := TAU * float(puff) / 4.0 + float(total_kills)
		_add_dust(at + Vector3(0, 0.2, 0), Vector3(cos(angle), 1.0, sin(angle)) * 1.6, 0.5, 0.6)
	# Swap-remove (order does not matter).
	var last := count() - 1
	_pos[i] = _pos[last]
	_hp[i] = _hp[last]
	_max_hp[i] = _max_hp[last]
	_speed[i] = _speed[last]
	_bite[i] = _bite[last]
	_bite_cd[i] = _bite_cd[last]
	_cd[i] = _cd[last]
	_yaw[i] = _yaw[last]
	_gait[i] = _gait[last]
	_walk[i] = _walk[last]
	_snap[i] = _snap[last]
	_flash[i] = _flash[last]
	_appear[i] = _appear[last]
	_biomass[i] = _biomass[last]
	_dna[i] = _dna[last]
	_pos.resize(last)
	_hp.resize(last)
	_max_hp.resize(last)
	_speed.resize(last)
	_bite.resize(last)
	_bite_cd.resize(last)
	_cd.resize(last)
	_yaw.resize(last)
	_gait.resize(last)
	_walk.resize(last)
	_snap.resize(last)
	_flash.resize(last)
	_appear.resize(last)
	_biomass.resize(last)
	_dna.resize(last)


func _add_dust(at: Vector3, velocity: Vector3, life: float, size: float) -> void:
	if _dust.size() >= DUST_MAX:
		_dust.remove_at(0)
	_dust.append({"at": at, "vel": velocity, "age": 0.0, "life": life, "size": size})


func _step_dust(delta: float) -> void:
	for index in range(_dust.size() - 1, -1, -1):
		var puff: Dictionary = _dust[index]
		puff.age = float(puff.age) + delta
		puff.at = Vector3(puff.at) + Vector3(puff.vel) * delta
		puff.vel = Vector3(puff.vel) * maxf(0.0, 1.0 - delta * 3.0)
		if float(puff.age) >= float(puff.life):
			_dust.remove_at(index)


# ------------------------------------------------------------------ look

func _build() -> void:
	if _built:
		return
	_built = true
	var sample: Node3D = MODEL_SCENE.instantiate()
	var piece: MeshInstance3D = sample.find_children("*", "MeshInstance3D", true, false)[0]
	var mesh := piece.mesh
	var mesh_local := Transform3D.IDENTITY
	var node: Node = piece
	while node != sample:
		mesh_local = (node as Node3D).transform * mesh_local
		node = node.get_parent()
	sample.free()
	# Sandgrub_game.glb lies Z-up (head raw +Y = world +Z after mesh_local, soles at 0).
	_base = Transform3D(Basis.from_scale(Vector3.ONE * MODEL_SCALE), Vector3.ZERO) * mesh_local
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = MAX_GRUBS
	multimesh.visible_instance_count = 0
	_bodies = MultiMeshInstance3D.new()
	_bodies.name = "Sandmaden"
	_bodies.multimesh = multimesh
	_bodies.material_override = _creature_material()
	_bodies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bodies)
	_bodies.top_level = true
	_bodies.global_transform = Transform3D.IDENTITY
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	var shadow_multimesh := MultiMesh.new()
	shadow_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	shadow_multimesh.mesh = plane
	shadow_multimesh.instance_count = MAX_GRUBS
	shadow_multimesh.visible_instance_count = 0
	_shadows = MultiMeshInstance3D.new()
	_shadows.name = "Sandmaden shadows"
	_shadows.multimesh = shadow_multimesh
	_shadows.material_override = _shadow_material()
	_shadows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadows)
	_shadows.top_level = true
	_shadows.global_transform = Transform3D.IDENTITY
	var puff := SphereMesh.new()
	puff.radius = 0.5
	puff.height = 1.0
	puff.radial_segments = 8
	puff.rings = 4
	_dust_batch = FX_BATCH.create(puff, DUST_MAX, true, true, "Sandmaden dust")
	add_child(_dust_batch)
	_dust_batch.top_level = true
	_dust_batch.global_transform = Transform3D.IDENTITY


func _creature_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CREATURE_SHADER
	material.set_shader_parameter("use_instance_custom", true)
	material.set_shader_parameter("brightness", 1.0)
	material.set_shader_parameter("saturation", 1.3)
	material.set_shader_parameter("shape_light", 0.5)
	material.set_shader_parameter("body_tint", BODY_TINT)
	material.set_shader_parameter("rim_color", RIM)
	material.set_shader_parameter("rim_strength", 0.9)
	material.set_shader_parameter("rim_power", 2.4)
	material.set_shader_parameter("outline_strength", 1.0)
	material.set_shader_parameter("flash_color", Color("fff3b0"))
	material.set_shader_parameter("flash", 0.0)
	# Limb/jaw frame for Sandgrub_game.glb in raw space (up -Z, head +Y, lateral
	# +X), measured from the vertex spread: four stubby feet (soles u < 0.07) at
	# f 0.2 / -0.35, l +-0.27; the round mouth at the front (f > 0.33, u 0.18..0.36).
	material.set_shader_parameter("up_axis", Vector3(0.0, 0.0, -1.0))
	material.set_shader_parameter("forward_axis", Vector3(0.0, 1.0, 0.0))
	material.set_shader_parameter("ground_offset", 0.0)
	material.set_shader_parameter("foot_a_front", Vector2(0.2, -0.27))
	material.set_shader_parameter("foot_a_back", Vector2(-0.35, 0.27))
	material.set_shader_parameter("foot_b_front", Vector2(0.2, 0.27))
	material.set_shader_parameter("foot_b_back", Vector2(-0.35, -0.27))
	material.set_shader_parameter("foot_radius", 0.15)
	material.set_shader_parameter("leg_height", 0.18)
	material.set_shader_parameter("stride", 0.08)
	material.set_shader_parameter("lift", 0.07)
	material.set_shader_parameter("stride_centering", 0.0)
	material.set_shader_parameter("walk_speed", 0.0)
	material.set_shader_parameter("walk_amount", 0.0)
	material.set_shader_parameter("walk_scale", 1.0)
	material.set_shader_parameter("jaw_hinge_forward", 0.33)
	material.set_shader_parameter("jaw_hinge_height", 0.3)
	material.set_shader_parameter("jaw_floor", 0.16)
	material.set_shader_parameter("jaw_angle", 0.5)
	material.set_shader_parameter("bite_amount", 0.0)
	# Segmented body: the rear wiggles like a tail while running.
	material.set_shader_parameter("tail_start", -0.2)
	material.set_shader_parameter("tail_length", 0.35)
	material.set_shader_parameter("tail_floor", 0.05)
	material.set_shader_parameter("tail_swing", 0.07)
	material.set_shader_parameter("tail_rate", 14.0)
	return material


func _shadow_material() -> StandardMaterial3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.14, 0.09, 0.04, 0.5))
	gradient.set_color(1, Color(0.14, 0.09, 0.04, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 32
	texture.height = 32
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = texture
	return material


func _draw() -> void:
	if not _built:
		return
	var n := count()
	var multimesh := _bodies.multimesh
	var shadows := _shadows.multimesh
	for i in n:
		var grow := _appear[i]
		# Breaking out: rises from below the sand with a little overshoot.
		var g := grow - 1.0
		var eased := 1.0 + 2.70158 * g * g * g + 1.70158 * g * g
		var sunk := (1.0 - minf(1.0, grow * 1.4)) * 0.5
		var hop := absf(sin(_gait[i])) * HOP * _walk[i]
		var lunge := sin(_snap[i] * PI) * 0.12
		var yaw := _yaw[i]
		var facing := Basis(Vector3.UP, yaw)
		var forward := facing * Vector3(0, 0, 1)
		var xform := Transform3D(facing, _pos[i] + Vector3(0, hop - sunk, 0) + forward * lunge) * Transform3D(Basis.from_scale(Vector3.ONE * maxf(0.05, eased)), Vector3.ZERO) * _base
		multimesh.set_instance_transform(i, xform)
		var glow := 1.0 + _flash[i] * 1.4
		multimesh.set_instance_color(i, Color(glow, glow, glow * (1.0 - 0.25 * _flash[i]), 1.0))
		var jaw := maxf(_snap[i], 0.2 * _walk[i])
		multimesh.set_instance_custom_data(i, Color(_walk[i], _gait[i] + PI * 0.5, jaw, 0.0))
		var size := 0.7 * minf(1.0, grow * 1.5) * (1.0 - hop * 2.0)
		shadows.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(size, 1.0, size * 1.2)).rotated(Vector3.UP, yaw), Vector3(_pos[i].x, SHADOW_Y, _pos[i].z)))
	multimesh.visible_instance_count = n
	shadows.visible_instance_count = n
	_bodies.visible = n > 0
	_shadows.visible = n > 0
	_dust_batch.begin()
	for puff in _dust:
		var t := float(puff.age) / float(puff.life)
		var size := float(puff.size) * (0.6 + 1.2 * t)
		_dust_batch.add(Transform3D(Basis.from_scale(Vector3(size, size * 0.7, size)), Vector3(puff.at)), Color(DUST, DUST.a * (1.0 - t) * (1.0 - t)))
	_dust_batch.finish()
