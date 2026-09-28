extends Node3D

# MOOSSCHLUND – apex boss of the Verdant Maw (stage 07 building block, wired
# into HuntWorld in stage 10). Much larger and more dangerous than the Bog King,
# but every loss is announced: each attack locks its shape at the start of the
# wind-up, shows its own ground telegraph and resolves exactly once.
#
# Same interface as bog_king.gd:
#   step(delta, swarm_position, pressure) -> int   base loss if the swarm centre is hit
#   take_damage(amount)       scaled by vulnerability() (exhausted = x1.5)
#   contains(point) / hit_fraction(points)         locked area of the last attack
#   resolved_power, state, health, max_health, attack_center
# Extra: phase (1/2), current_pattern, migration_ready + signal defeated(location),
# body_radius / melee_range / body_distance(point) for HuntWorld, hud_message() for the banner text.
#
# Attack patterns (numbers per phase 1 / phase 2, base loss x pressure):
#   ROOTS  "Wurzelbruch" – 3 / 5 root lanes (2.2 / 2.4 m wide, 18 m long) fan out
#          from the boss towards the swarm; wind-up 1.5 / 1.25 s; loss APEX_ROOT_DAMAGE.
#          Dodge: step sideways out of the lane (or between lanes further out).
#   SPORES "Sporenring" – ring around the boss from 3.8 / 3.4 m to 9 / 11 m;
#          wind-up 1.8 / 1.5 s; loss APEX_SPORE_DAMAGE. Dodge: hug the boss (inside) or run out.
#   QUAKE  "Beben" – disc of 13 / 15 m with 3 / 2 safe islands (2.6 / 2.2 m) at
#          7.5 m from the boss; wind-up 2.2 / 1.9 s; loss APEX_QUAKE_DAMAGE. Dodge: stand on a
#          bright island (Rally packs the swarm) or leave the disc.
# After every quake the boss is EXHAUSTED (4.0 / 3.0 s, takes x1.5 damage).
# At 50 % health it roars (PHASE_SHIFT 1.8 s, immune, a pending attack is
# cancelled without damage) and enters phase 2: faster, more lanes, shorter
# wind-ups, pattern cycle ROOTS-SPORES-ROOTS-QUAKE.
# Stage 10: the balance numbers (health, speed, wind-ups, damage, cooldowns)
# live in tuning.gd (APEX_*); shapes and looks stay here.

signal defeated(location: Vector3)
signal phase_changed(phase: int)

const FX = preload("res://scripts/fx.gd")
const TUNING = preload("res://scripts/tuning.gd")
const UI_STYLE = preload("res://scripts/ui/ui_style.gd")
# Own model (stage 11): moss-covered quadruped with root antlers, Z-up storage
# like the Bog King glb (head +Y, soles at z = 0); its node turns it head +Z, feet on 0.
const MODEL = preload("res://assets/gameplay/characters/Moosschlund_game.glb")
const CREATURE_ANIM_SHADER = preload("res://shaders/creature_anim.gdshader")

enum State { ARRIVING, CHASE, WINDUP, STRIKE, EXHAUSTED, PHASE_SHIFT, DEAD }
enum Pattern { ROOTS, SPORES, QUAKE }

const DISPLAY_NAME := "Moosschlund"
const HEALTH := TUNING.APEX_HEALTH
const MODEL_SCALE := 11.0
const BODY_RADIUS := TUNING.APEX_BODY_RADIUS
const MELEE_RANGE := TUNING.APEX_MELEE_RANGE
const MOVE_RADIUS := 3.0
const SPEED := TUNING.APEX_SPEED
const ARRIVE_SECONDS := TUNING.APEX_ARRIVE_SECONDS
const EMERGE_DEPTH := 6.0
const PHASE_TWO_SHARE := TUNING.APEX_PHASE_TWO_SHARE
const PHASE_SHIFT_SECONDS := TUNING.APEX_PHASE_SHIFT_SECONDS
const STRIKE_SECONDS := 0.5
const ATTACK_RANGE := TUNING.APEX_ATTACK_RANGE
const KEEP_DISTANCE := TUNING.APEX_KEEP_DISTANCE
const COOLDOWN := TUNING.APEX_COOLDOWN
const EXHAUSTED_SECONDS := TUNING.APEX_EXHAUSTED_SECONDS
const EXHAUSTED_VULNERABILITY := TUNING.APEX_EXHAUSTED_VULNERABILITY
const CYCLE := [[Pattern.ROOTS, Pattern.SPORES, Pattern.QUAKE], [Pattern.ROOTS, Pattern.SPORES, Pattern.ROOTS, Pattern.QUAKE]]

const ROOT_WINDUP := TUNING.APEX_ROOT_WINDUP
const ROOT_DAMAGE := TUNING.APEX_ROOT_DAMAGE
const ROOT_LANES := [3, 5]
const ROOT_SPREAD := [0.5, 0.42]
const ROOT_WIDTH := [2.2, 2.4]
const ROOT_LENGTH := 18.0
const ROOT_START := 2.0

const SPORE_WINDUP := TUNING.APEX_SPORE_WINDUP
const SPORE_DAMAGE := TUNING.APEX_SPORE_DAMAGE
const SPORE_INNER := [3.8, 3.4]
const SPORE_OUTER := [9.0, 11.0]

const QUAKE_WINDUP := TUNING.APEX_QUAKE_WINDUP
const QUAKE_DAMAGE := TUNING.APEX_QUAKE_DAMAGE
const QUAKE_RADIUS := [13.0, 15.0]
const QUAKE_ISLANDS := [3, 2]
const QUAKE_ISLAND_RADIUS := [2.6, 2.2]
const QUAKE_ISLAND_DISTANCE := 7.5
# Island angles relative to the swarm direction (the swarm never starts on one).
const QUAKE_ISLAND_ANGLES := [[0.9, -0.9, PI], [1.2, -1.2]]

const PATTERN_NAMES := {Pattern.ROOTS: "Wurzelbruch", Pattern.SPORES: "Sporenring", Pattern.QUAKE: "Beben"}
const RIM_CHASE := Color("c8f08a")
const RIM_WARNING := Color("ffd23f")
const RIM_EXHAUSTED := Color("7fe7ff")
const RIM_RAGE := Color("ff9a3c")
# Phase 1 shows the real vertex colours of the model; phase 2 (rage) tints towards
# ember, exhaustion towards a pale cold blue (state cue besides pose and rim).
const SKIN_TINT := Color(1.0, 1.0, 1.0, 0.0)
const SKIN_TINT_RAGE := Color(0.95, 0.46, 0.18, 0.34)
const SKIN_TINT_EXHAUSTED := Color(0.62, 0.86, 1.0, 0.36)
const DUST := Color(0.4, 0.46, 0.26, 0.6)

# Stage 20: the telegraphs use the shared boss style (telegraph_style.gd:
# danger ring exactly on the hit edge, dark contour, wind-up fill, pale marks).
# Each pattern keeps its own shape - lanes with chevrons, a ring, a disc with
# friendly cyan islands - so colour is never the only cue.
const TG = preload("res://scripts/telegraph_style.gd")
const PATTERN_SHAPE := {Pattern.ROOTS: TG.Shape.LANE, Pattern.SPORES: TG.Shape.RING, Pattern.QUAKE: TG.Shape.ISLANDS}

var state := State.ARRIVING
var remaining := ARRIVE_SECONDS
var health := HEALTH
var max_health := HEALTH
var phase := 1
var current_pattern := Pattern.ROOTS
var cycle_index := 0
var cooldown := 1.2
var attack_center := Vector3.ZERO
var attack_power := 0
# Base loss resolved during the last step() (0 = none), like the Bog King.
var resolved_power := 0
var migration_ready := false
var migration_point := Vector3.ZERO
var body_radius := BODY_RADIUS
var melee_range := MELEE_RANGE
# Optional arena (steer_direction / resolve_motion); found via ../../Arena if unset.
var arena: Node3D
# Locked attack shape.
var lane_directions: Array[Vector3] = []
var lane_width := 2.2
var ring_inner := 0.0
var ring_outer := 0.0
var quake_radius := 0.0
var islands: Array[Vector4] = []
var hit_flash := 0.0
var colorblind := false
# Presentation only.
var model: Node3D
var body: Node3D
var skin: ShaderMaterial
var sac_material: StandardMaterial3D
var sacs: Array[MeshInstance3D] = []
var shadow: MeshInstance3D
var warning: Node3D
var telegraphs: Array[MeshInstance3D] = []
var emerge := 0.0
var _windup_total := 1.0
var _time := 0.0
var _gait := 0.0
var _slam := 0.0
var _rim := RIM_CHASE
var _tint := SKIN_TINT
var _lift := 0.0
var _lean := 0.0
var _sway := 0.0
var _stretch := 0.0
var _walk := 0.0
var _stomp_leg := 0.0
var _jaw := 0.0
var _sink := 0.0
var _grow := 1.0


func _ready() -> void:
	colorblind = UI_STYLE.colorblind
	_build_model()
	shadow = _make_shadow()
	warning = Node3D.new()
	warning.name = "Moosschlund warnings"
	add_child(warning)
	warning.top_level = true
	warning.global_transform = Transform3D.IDENTITY
	FX.ring(_fx_parent(), global_position, Color(0.36, 0.5, 0.2, 0.85), 1.0, 7.0, 1.2)
	FX.ring(_fx_parent(), global_position, Color(0.94, 0.86, 0.3, 0.7), 0.6, 5.0, 1.6)
	_shake(0.4)
	_pose(0.0, 0.0, true)


# ------------------------------------------------------------------ rules

func take_damage(amount: float) -> void:
	if state == State.DEAD:
		return
	var scaled := amount * vulnerability()
	if scaled <= 0.0:
		return
	health -= scaled
	hit_flash = 0.12
	if health <= 0.0:
		_die()


# Damage multiplier of the current state (immune while emerging and roaring).
func vulnerability() -> float:
	match state:
		State.ARRIVING, State.PHASE_SHIFT, State.DEAD:
			return 0.0
		State.EXHAUSTED:
			return EXHAUSTED_VULNERABILITY
	return 1.0


# Attack forms skip targets that cannot be hit (immune while emerging/roaring/dead).
func can_be_hit() -> bool:
	return vulnerability() > 0.0


func step(delta: float, swarm_position: Vector3, pressure: float) -> int:
	resolved_power = 0
	var previous_position := position
	var result := _logic(delta, swarm_position, pressure)
	var speed := 0.0
	if delta > 0.0:
		speed = Vector2(position.x - previous_position.x, position.z - previous_position.z).length() / delta
	_pose(delta, speed)
	return result


func _logic(delta: float, swarm_position: Vector3, pressure: float) -> int:
	if state == State.DEAD or delta <= 0.0:
		return 0
	if phase == 1 and health <= max_health * PHASE_TWO_SHARE and state != State.ARRIVING and state != State.PHASE_SHIFT:
		_enter_phase_two()
		return 0
	var offset := swarm_position - position
	offset.y = 0.0
	if state == State.CHASE:
		cooldown -= delta
		if cooldown <= 0.0 and offset.length() <= ATTACK_RANGE:
			begin_attack(CYCLE[phase - 1][cycle_index % CYCLE[phase - 1].size()], swarm_position, pressure)
			cycle_index += 1
			return 0
		if offset.length() > KEEP_DISTANCE:
			_move_towards(swarm_position, delta)
		elif offset.length_squared() > 0.01:
			_face(offset, delta * 3.0)
		return 0
	remaining -= delta
	if state == State.WINDUP:
		if remaining > 0.0:
			return 0
		return _resolve(swarm_position)
	if remaining > 0.0:
		return 0
	match state:
		State.ARRIVING:
			state = State.CHASE
		State.STRIKE:
			if current_pattern == Pattern.QUAKE:
				state = State.EXHAUSTED
				remaining = EXHAUSTED_SECONDS[phase - 1]
			else:
				state = State.CHASE
				cooldown = COOLDOWN[phase - 1]
		State.EXHAUSTED, State.PHASE_SHIFT:
			state = State.CHASE
			cooldown = COOLDOWN[phase - 1] * 0.5
	return 0


## Starts a wind-up now and locks its shape around the current position.
## Public for tests and scripted moments; the normal flow calls it from CHASE.
func begin_attack(pattern: int, swarm_position: Vector3, pressure: float) -> void:
	var index := phase - 1
	current_pattern = pattern
	state = State.WINDUP
	attack_center = Vector3(position.x, 0.0, position.z)
	var toward := swarm_position - attack_center
	toward.y = 0.0
	toward = toward.normalized() if toward.length_squared() > 0.0001 else Vector3(-1, 0, 0)
	rotation.y = atan2(toward.x, toward.z) + PI * 0.5
	lane_directions.clear()
	islands.clear()
	var base := 0.0
	match pattern:
		Pattern.ROOTS:
			remaining = ROOT_WINDUP[index]
			base = ROOT_DAMAGE
			lane_width = ROOT_WIDTH[index]
			var count: int = ROOT_LANES[index]
			for lane in count:
				var angle: float = (float(lane) - float(count - 1) * 0.5) * float(ROOT_SPREAD[index])
				lane_directions.append(toward.rotated(Vector3.UP, angle))
		Pattern.SPORES:
			remaining = SPORE_WINDUP[index]
			base = SPORE_DAMAGE
			ring_inner = SPORE_INNER[index]
			ring_outer = SPORE_OUTER[index]
		Pattern.QUAKE:
			remaining = QUAKE_WINDUP[index]
			base = QUAKE_DAMAGE
			quake_radius = QUAKE_RADIUS[index]
			var radius: float = QUAKE_ISLAND_RADIUS[index]
			for lane in QUAKE_ISLANDS[index]:
				var spot: Vector3 = attack_center + toward.rotated(Vector3.UP, QUAKE_ISLAND_ANGLES[index][lane]) * QUAKE_ISLAND_DISTANCE
				islands.append(Vector4(spot.x, 0.0, spot.z, radius))
	_windup_total = remaining
	attack_power = int(ceil(minf(1000000.0, base * pressure)))
	_build_telegraphs()


func _resolve(swarm_position: Vector3) -> int:
	state = State.STRIKE
	remaining = STRIKE_SECONDS
	resolved_power = attack_power
	_clear_telegraphs()
	_strike_fx()
	return attack_power if contains(swarm_position) else 0


func _enter_phase_two() -> void:
	phase = 2
	state = State.PHASE_SHIFT
	remaining = PHASE_SHIFT_SECONDS
	cycle_index = 0
	_clear_telegraphs()
	FX.ring(_fx_parent(), global_position, Color(1.0, 0.49, 0.76, 0.9), 1.0, 9.0, 0.8)
	FX.ring(_fx_parent(), global_position, Color(0.8, 0.95, 0.5, 0.7), 0.5, 6.0, 1.2)
	_shake(0.6)
	phase_changed.emit(phase)


func _die() -> void:
	health = minf(health, 0.0)
	state = State.DEAD
	remaining = 0.0
	migration_ready = true
	migration_point = Vector3(position.x, 0.0, position.z)
	_clear_telegraphs()
	FX.ring(_fx_parent(), global_position, Color(0.94, 0.9, 0.5, 0.95), 1.0, 11.0, 1.2)
	FX.ring(_fx_parent(), global_position, Color(0.4, 0.8, 0.9, 0.8), 0.6, 7.0, 1.6)
	_shake(0.7)
	defeated.emit(migration_point)


func _move_towards(target: Vector3, delta: float) -> void:
	var speed: float = SPEED[phase - 1]
	var field := _arena()
	var direction := target - position
	direction.y = 0.0
	if field != null:
		direction = field.steer_direction(position, target, MOVE_RADIUS)
		position = field.resolve_motion(position, direction * speed * delta, MOVE_RADIUS)
	else:
		direction = direction.normalized()
		position += direction * speed * delta
	if direction.length_squared() > 0.01:
		_face(direction, delta * 2.5)


func _face(direction: Vector3, weight: float) -> void:
	rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z) + PI * 0.5, minf(1.0, weight))


func _arena() -> Node3D:
	if arena == null and get_parent() != null and get_parent().get_parent() != null:
		arena = get_parent().get_parent().get_node_or_null("Arena") as Node3D
	return arena


# Locked area of the current / last attack.
func contains(point: Vector3) -> bool:
	var flat := Vector2(point.x - attack_center.x, point.z - attack_center.z)
	match current_pattern:
		Pattern.ROOTS:
			for direction in lane_directions:
				var along := flat.dot(Vector2(direction.x, direction.z))
				var across := absf(flat.x * direction.z - flat.y * direction.x)
				if along >= ROOT_START and along <= ROOT_START + ROOT_LENGTH and across <= lane_width * 0.5:
					return true
			return false
		Pattern.SPORES:
			var distance := flat.length()
			return distance >= ring_inner and distance <= ring_outer
		Pattern.QUAKE:
			if flat.length() > quake_radius:
				return false
			for island in islands:
				if Vector2(point.x - island.x, point.z - island.z).length() <= island.w:
					return false
			return true
	return false


func hit_fraction(points: PackedVector3Array) -> float:
	if points.is_empty():
		return 0.0
	var inside := 0
	for point in points:
		if contains(point):
			inside += 1
	return float(inside) / float(points.size())


## Flat distance from `point` to the body rim (0 = touching or inside). Attack
## forms and HuntWorld.melee_factor measure to the rim: the big body is otherwise
## hard to reach from the centre of a swarm that crowds around it.
func body_distance(point: Vector3) -> float:
	return maxf(0.0, Vector2(point.x - position.x, point.z - position.z).length() - body_radius)


# Pure danger check for AI/tests: is `point` safe from the current wind-up?
func is_safe(point: Vector3) -> bool:
	return state != State.WINDUP or not contains(point)


func windup_progress() -> float:
	return clampf(1.0 - remaining / maxf(_windup_total, 0.001), 0.0, 1.0) if state == State.WINDUP else 0.0


# Banner text for the HUD (stage 08); "" = nothing to announce.
func hud_message() -> String:
	match state:
		State.ARRIVING:
			return "DER MOOSSCHLUND ERWACHT"
		State.WINDUP:
			match current_pattern:
				Pattern.ROOTS:
					return "WURZELBRUCH · RAUS AUS DEN BAHNEN!"
				Pattern.SPORES:
					return "SPORENRING · RAN AN IHN ODER WEIT WEG!"
				Pattern.QUAKE:
					return "BEBEN · AB AUF DIE HELLEN INSELN!"
		State.EXHAUSTED:
			return "MOOSSCHLUND ERSCHÖPFT · JETZT ANGREIFEN!"
		State.PHASE_SHIFT:
			return "DER MOOSSCHLUND TOBT!"
		State.DEAD:
			return "DER MIGRATIONSSCHLUND ÖFFNET SICH"
	return ""


static func pattern_name(pattern: int) -> String:
	return String(PATTERN_NAMES.get(pattern, ""))


# --------------------------------------------------------------- telegraphs



static func telegraph_material(pattern: int, colorblind_on: bool) -> ShaderMaterial:
	var result := TG.shape_material(int(PATTERN_SHAPE.get(pattern, TG.Shape.DISC)), "boss", colorblind_on)
	result.set_shader_parameter("pattern", pattern)
	return result


# Swaps the telegraph palette (e.g. when the colour-blind setting changes).
func restyle(colorblind_on: bool) -> void:
	colorblind = colorblind_on
	if state == State.WINDUP:
		_build_telegraphs()


func _build_telegraphs() -> void:
	_clear_telegraphs()
	warning.global_transform = Transform3D.IDENTITY
	var height := 0.12
	var blind := 1 if colorblind else 0
	match current_pattern:
		Pattern.ROOTS:
			for direction in lane_directions:
				var lane := _telegraph_part(TG.build_boss_lane(lane_width, ROOT_LENGTH, blind))
				lane.rotation.y = atan2(direction.x, direction.z)
				lane.position = attack_center + direction * (ROOT_START + ROOT_LENGTH * 0.5) + Vector3(0, height, 0)
				height += 0.004
		Pattern.SPORES:
			var ring := _telegraph_part(TG.build_boss_ring(ring_inner, ring_outer, blind))
			ring.position = attack_center + Vector3(0, height, 0)
		Pattern.QUAKE:
			var local: Array = []
			for island in islands:
				local.append(Vector4(island.x - attack_center.x, 0.0, island.z - attack_center.z, island.w))
			var disc := _telegraph_part(TG.build_boss_islands(quake_radius, local, blind))
			disc.position = attack_center + Vector3(0, height, 0)
	warning.visible = true


func _telegraph_part(part: MeshInstance3D) -> MeshInstance3D:
	part.name = "Apex telegraph %s" % pattern_name(current_pattern)
	(part.material_override as ShaderMaterial).set_shader_parameter("pattern", current_pattern)
	warning.add_child(part)
	telegraphs.append(part)
	return part


func _clear_telegraphs() -> void:
	for part in telegraphs:
		if is_instance_valid(part):
			part.queue_free()
			if part.get_parent() != null:
				part.get_parent().remove_child(part)
	telegraphs.clear()
	if warning != null:
		warning.visible = false


func _strike_fx() -> void:
	var parent := _fx_parent()
	match current_pattern:
		Pattern.ROOTS:
			for direction in lane_directions:
				for step_index in 4:
					var spot: Vector3 = attack_center + direction * (ROOT_START + 2.0 + float(step_index) * 4.5)
					FX.ring(parent, spot, Color(0.96, 0.82, 0.3, 0.85), 0.3, lane_width * 0.9, 0.4 + 0.05 * step_index)
			_shake(0.4)
		Pattern.SPORES:
			FX.ring(parent, attack_center, Color(0.86, 0.72, 1.0, 0.85), ring_inner, ring_outer, 0.5)
			FX.ring(parent, attack_center, Color(0.55, 0.3, 0.8, 0.7), ring_inner * 0.9, ring_outer * 1.05, 0.8)
			_shake(0.3)
		Pattern.QUAKE:
			FX.ring(parent, attack_center, Color(1.0, 0.49, 0.76, 0.95), 1.0, quake_radius * 1.05, 0.55)
			FX.ring(parent, attack_center, DUST, 0.8, quake_radius * 0.75, 0.9)
			_shake(0.7)
	_slam = STRIKE_SECONDS


# ------------------------------------------------------------------ look

## Builds the body from Moosschlund_game.glb (antlers are part of the mesh).
## Everything else only needs `model`, `body` and `skin` (creature_anim material).
func _build_model() -> void:
	body = Node3D.new()
	body.name = "Moosschlund body"
	add_child(body)
	model = MODEL.instantiate()
	model.name = "Moosschlund model"
	model.scale = Vector3.ONE * MODEL_SCALE
	model.rotation.y = -PI * 0.5
	body.add_child(model)
	skin = ShaderMaterial.new()
	skin.shader = CREATURE_ANIM_SHADER
	skin.set_shader_parameter("brightness", 1.35)
	skin.set_shader_parameter("saturation", 1.05)
	skin.set_shader_parameter("shape_light", 0.45)
	skin.set_shader_parameter("rim_color", _rim)
	skin.set_shader_parameter("rim_strength", 0.8)
	skin.set_shader_parameter("rim_power", 2.0)
	skin.set_shader_parameter("body_tint", SKIN_TINT)
	skin.set_shader_parameter("flash", 0.0)
	_setup_limbs()
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = skin
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Spore sacs: pale violet bulbs on the mossy back behind the antlers, they
	# swell during the spore wind-up. (forward, lateral, height) in raw mesh units,
	# sampled from the back surface; body space = (-forward, height, lateral) * scale.
	sac_material = StandardMaterial3D.new()
	sac_material.albedo_color = Color("d9b8ff")
	sac_material.emission_enabled = true
	sac_material.emission = Color("7a3cc8")
	sac_material.roughness = 0.6
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 12
	sphere.rings = 6
	var spots := [Vector3(-0.12, 0.0, 0.52), Vector3(-0.2, 0.12, 0.46), Vector3(-0.2, -0.12, 0.46), Vector3(-0.3, 0.07, 0.41), Vector3(-0.3, -0.07, 0.41)]
	for spot in spots:
		var sac := MeshInstance3D.new()
		sac.name = "Spore sac"
		sac.mesh = sphere
		sac.material_override = sac_material
		sac.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sac.position = Vector3(-spot.x, spot.z, spot.y) * MODEL_SCALE
		sac.scale = Vector3.ONE * MODEL_SCALE * 0.07
		sac.set_meta("base", sac.scale.x)
		body.add_child(sac)
		sacs.append(sac)


# Limb frame for Moosschlund_game.glb, measured in raw mesh space (Z-up storage):
# soles at z = 0 (up = -Z), head with the root antlers towards +Y, lateral = +X.
# Feet centres (forward, lateral) from clustering the lowest 5 % of vertices: four
# pillar legs in a wide rectangle. The jaw is the snout below the eyes in front of
# the antler roots (antlers start above u = 0.4 and stay rigid); no tail.
func _setup_limbs() -> void:
	skin.set_shader_parameter("up_axis", Vector3(0.0, 0.0, -1.0))
	skin.set_shader_parameter("forward_axis", Vector3(0.0, 1.0, 0.0))
	skin.set_shader_parameter("ground_offset", 0.0)
	skin.set_shader_parameter("foot_a_front", Vector2(0.192, -0.229))
	skin.set_shader_parameter("foot_a_back", Vector2(-0.332, 0.247))
	skin.set_shader_parameter("foot_b_front", Vector2(0.189, 0.237))
	skin.set_shader_parameter("foot_b_back", Vector2(-0.331, -0.241))
	skin.set_shader_parameter("foot_radius", 0.14)
	skin.set_shader_parameter("leg_height", 0.2)
	skin.set_shader_parameter("stride", 0.045)
	skin.set_shader_parameter("lift", 0.05)
	skin.set_shader_parameter("stride_centering", 1.0)
	skin.set_shader_parameter("walk_speed", 0.0)
	skin.set_shader_parameter("walk_scale", 1.0)
	skin.set_shader_parameter("jaw_hinge_forward", 0.24)
	skin.set_shader_parameter("jaw_hinge_height", 0.36)
	skin.set_shader_parameter("jaw_floor", 0.16)
	skin.set_shader_parameter("jaw_angle", 0.5)
	skin.set_shader_parameter("tail_start", -1.0)
	skin.set_shader_parameter("tail_length", 0.1)
	skin.set_shader_parameter("tail_floor", 1.0)
	skin.set_shader_parameter("tail_swing", 0.0)
	skin.set_shader_parameter("tail_rate", 0.0)
	skin.set_shader_parameter("stomp_height", 0.14)


func refresh_pose() -> void:
	_pose(0.0, 0.0, true)


func _pose(delta: float, speed: float, snap: bool = false) -> void:
	_time += delta
	hit_flash = maxf(0.0, hit_flash - delta)
	_slam = maxf(0.0, _slam - delta)
	emerge = clampf(1.0 - remaining / ARRIVE_SECONDS, 0.0, 1.0) if state == State.ARRIVING else 1.0
	var lift := 0.0
	var walk := 0.0
	var stomp_leg := 0.0
	var jaw := 0.0
	var lean := 0.0
	var sway := 0.0
	var stretch := 0.0
	var tremble := 0.0
	var sac_swell := 0.0
	var rim_target := RIM_RAGE if phase == 2 else RIM_CHASE
	var rim_strength := 0.8
	match state:
		State.ARRIVING:
			tremble = 0.1 * (1.0 - emerge)
			lean = -0.15 * (1.0 - emerge)
		State.CHASE:
			var stride := minf(1.0, speed / float(SPEED[0]))
			var before := sin(_gait)
			_gait += speed * delta * 1.3
			var wave := sin(_gait)
			if stride > 0.2 and before != 0.0 and signf(wave) != signf(before):
				FX.ring(_fx_parent(), global_position, DUST, 0.6, 2.6, 0.4)
				_shake(0.08)
			lift = absf(wave) * 0.34 * stride
			walk = stride
			sway = wave * 0.07 * stride
			lean = 0.06 * stride
		State.WINDUP:
			var progress := windup_progress()
			var rise := 1.0 - pow(1.0 - minf(1.0, progress / 0.7), 3.0)
			rim_target = RIM_WARNING
			tremble = 0.12 * smoothstep(0.6, 1.0, progress)
			match current_pattern:
				Pattern.ROOTS:
					lean = 0.22 * rise
					lift = -0.2 * rise
					jaw = 0.9 * rise
					stomp_leg = 0.5 * rise
				Pattern.SPORES:
					lean = -0.22 * rise
					stretch = 0.08 * rise
					jaw = 0.6 * rise
					sac_swell = rise
				Pattern.QUAKE:
					lift = 1.1 * rise
					lean = -0.38 * rise
					stretch = 0.07 * rise
					stomp_leg = rise
					jaw = 0.8 * rise
			for part in telegraphs:
				(part.material_override as ShaderMaterial).set_shader_parameter("progress", progress)
		State.EXHAUSTED:
			var breath := sin(_time * 1.8)
			lift = -0.3
			lean = 0.26 + 0.03 * breath
			stretch = 0.04 * breath
			jaw = 0.4 + 0.2 * breath
			rim_target = RIM_EXHAUSTED
			rim_strength = 1.0 + 0.5 * (0.5 + 0.5 * sin(_time * 5.0))
			sac_swell = -0.5
		State.PHASE_SHIFT:
			var roar := clampf(1.0 - remaining / PHASE_SHIFT_SECONDS, 0.0, 1.0)
			lean = -0.36 * sin(roar * PI)
			lift = 0.5 * sin(roar * PI)
			jaw = 1.0
			tremble = 0.12
			sac_swell = 0.6
			rim_target = RIM_RAGE
			rim_strength = 1.1
		State.DEAD:
			_sink = minf(1.0, _sink + delta / 2.4)
			lean = 0.3
			jaw = 0.7
			sway = 0.25 * _sink
	if _slam > 0.0:
		var slam := _slam / STRIKE_SECONDS
		lean += 0.34 * slam
		lift -= 0.16 * slam
		stretch -= 0.2 * slam
		stomp_leg = 0.0
	var flash := 0.0
	if hit_flash > 0.0:
		flash = 0.16 + 0.1 * (0.5 + 0.5 * sin(_time * 55.0))
		tremble += 0.04
	var weight := 1.0 if snap else minf(1.0, delta * 10.0)
	_lift = lerpf(_lift, lift, weight)
	_lean = lerpf(_lean, lean, weight)
	_sway = lerpf(_sway, sway, weight)
	_stretch = lerpf(_stretch, stretch, weight)
	_walk = lerpf(_walk, walk, weight)
	_jaw = lerpf(_jaw, jaw, weight)
	_stomp_leg = stomp_leg if snap or stomp_leg < _stomp_leg else lerpf(_stomp_leg, stomp_leg, weight)
	_rim = rim_target if snap else _rim.lerp(rim_target, minf(1.0, delta * 5.0))
	var grow_target := 1.1 if phase == 2 else 1.0
	_grow = grow_target if snap else lerpf(_grow, grow_target, minf(1.0, delta * 2.0))
	var risen := 1.0 - pow(1.0 - emerge, 3.0)
	var jitter := Vector3(sin(_time * 43.0), 0.0, sin(_time * 37.0 + 1.3)) * tremble
	body.position = Vector3(0.0, _lift - EMERGE_DEPTH * (1.0 - risen) - EMERGE_DEPTH * 0.6 * _sink, 0.0) + jitter
	body.rotation = Vector3(_sway, 0.0, _lean)
	body.scale = Vector3(1.0 - _stretch * 0.5, 1.0 + _stretch, 1.0 - _stretch * 0.5) * _grow
	var shadow_size := lerpf(0.3, 1.0, risen) * (1.0 - 0.18 * clampf(_lift / 1.1, 0.0, 1.0)) * (1.0 - _sink * 0.7) * _grow
	shadow.scale = Vector3(shadow_size, 1.0, shadow_size)
	skin.set_shader_parameter("rim_color", _rim)
	skin.set_shader_parameter("rim_strength", rim_strength)
	skin.set_shader_parameter("flash", flash)
	var tint_target := SKIN_TINT_RAGE if phase == 2 else SKIN_TINT
	if state == State.EXHAUSTED:
		tint_target = SKIN_TINT_EXHAUSTED
	_tint = tint_target if snap else _tint.lerp(tint_target, minf(1.0, delta * 4.0))
	skin.set_shader_parameter("body_tint", _tint)
	skin.set_shader_parameter("walk_amount", _walk)
	skin.set_shader_parameter("walk_phase", _gait + PI * 0.5)
	skin.set_shader_parameter("stomp_lift", _stomp_leg)
	skin.set_shader_parameter("bite_amount", _jaw)
	skin.set_shader_parameter("tail_phase", _time * 1.3)
	var sac_pulse := 1.0 + 0.35 * sac_swell * (0.7 + 0.3 * sin(_time * 12.0))
	for sac in sacs:
		sac.scale = Vector3.ONE * float(sac.get_meta("base")) * sac_pulse
	sac_material.emission_energy_multiplier = maxf(0.0, 0.4 + 1.6 * sac_swell)


func _shake(amount: float) -> void:
	var main: Node = get_parent().get_parent() if get_parent() != null else null
	if main != null and main.has_method("add_shake"):
		main.add_shake(amount)


func _fx_parent() -> Node:
	return get_parent() if get_parent() != null else self


func _make_shadow() -> MeshInstance3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.02, 0.04, 0.02, 0.6))
	gradient.set_color(1, Color(0.02, 0.04, 0.02, 0.0))
	gradient.add_point(0.55, Color(0.02, 0.04, 0.02, 0.4))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = texture
	var plane := PlaneMesh.new()
	plane.size = Vector2(7.6, 7.6)
	var part := MeshInstance3D.new()
	part.name = "Moosschlund shadow"
	part.mesh = plane
	part.material_override = material
	part.position = Vector3(0, 0.06, 0)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
	return part
