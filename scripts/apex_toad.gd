extends Node3D

# ASCHENKRÖTE – apex of the Glutsumpf (stage 10 follow-up, second apex). A huge,
# squat lava toad (user model AshToad_game.glb): ash-black rock hide cracked by
# glowing ember veins, which the skin shader lets glow (brighter before a spit and
# in phase 2). Like the
# Moosschlund every loss is announced: each attack locks its shape at the start
# of the wind-up, shows its own ground telegraph (pattern AND colour, so it reads
# without colour) and resolves exactly once.
#
# Same interface as apex_boss.gd (HuntWorld can hold either in `apex`):
#   step(delta, swarm_position, pressure) -> int   base loss if the swarm centre is hit
#   take_damage(amount)       scaled by vulnerability() (exhausted = x1.6, airborne = 0)
#   can_be_hit(), contains(point) / hit_fraction(points)  locked area of the last attack
#   resolved_power, state, health, max_health, attack_center, body_radius, melee_range
#   phase, current_pattern, hud_message(), migration_ready / migration_point,
#   signals phase_changed(phase), defeated(location)
# The State enum has the same names AND values as apex_boss.State, so HuntWorld's
# `apex.state == APEX_BOSS.State.WINDUP / EXHAUSTED / PHASE_SHIFT` checks keep working.
# Extra:
#   contains_body(point) / body_distance(point)  edge of the body (attack forms should
#       measure to the rim instead of the centre: big bodies are otherwise hard to hit)
#   puddles   child node with resolved_power + contains(): the lingering Glutpfützen,
#       resolve it like an enemy area (_resolve_area_hit(apex.puddles, ...)) after step()
#   corpse_kind = "apex_toad" (own corpse design), DISPLAY_NAME
#
# Attack patterns (phase 1 / phase 2, base loss x pressure):
#   LEAP   "Aschensprung" – marks a landing disc (4.2 / 4.6 m) on the swarm (at most
#          16 m away), crouches, jumps (immune in the air) and lands after 1.7 / 1.55 s;
#          shock ring on impact. Loss LEAP_DAMAGE 12. Dodge: leave the hatched disc.
#          Afterwards EXHAUSTED 4.0 / 3.2 s (x1.6 damage) right where the swarm stood.
#          Phase 2: after landing it spits a volley first (chain), then is exhausted.
#   SPIT   "Glutspucke" – 3 / 5 lava balls on marked circles: one on the swarm
#          (2.6 / 2.8 m, stays visible around the clump), the others (1.9 / 2.0 m)
#          5 m around it (sideways in phase 1, a loose ring with gaps towards and
#          away from the toad in phase 2); wind-up 1.5 / 1.3 s, loss 5. Every
#          circle leaves a Glutpfütze (0.85 x radius) for 3.0 / 3.5 s that burns 2 x
#          pressure every 0.8 s – visible the whole time, so it is an announced area.
#   TONGUE "Zungenpeitsche" – narrow lane (1.8 / 2.0 m wide, 15 / 17 m long) from the
#          mouth through the swarm; short wind-up 0.95 / 0.8 s, loss 7. Dodge: sidestep.
#   COMBO  (phase 2 only) tongue lane + phase-1 spit circles in one wind-up (1.35 s,
#          loss 7); the gap lies diagonally behind the swarm.
# Cycle phase 1: LEAP, SPIT, TONGUE. Phase 2 (at 50 % health, 1.8 s immune roar that
# cancels a pending attack without loss): LEAP(+SPIT), COMBO, TONGUE; faster steps.
#
# Fight length (target ~35-50 s with an average build, the Moosschlund lasts 15-22 s
# with 650 HP, i.e. ~36 swarm DPS at ~3:45). The toad comes later (Glutsumpf), the
# swarm is bigger, but it spends ~15 % of the fight immune in the air or roaring and
# the swarm must leave melee for every dodge. HEALTH 1500 gives ~40 s against a
# 40 DPS bot that dodges everything (tests/apex_toad.gd measures it), ~33 s at
# 55 DPS and ~52 s at 30 DPS. Balance numbers live here until the toad is wired
# into HuntWorld; then they can move to tuning.gd (APEX_TOAD_*).

signal defeated(location: Vector3)
signal phase_changed(phase: int)

const FX = preload("res://scripts/fx.gd")
const UI_STYLE = preload("res://scripts/ui/ui_style.gd")
const MODEL = preload("res://assets/gameplay/characters/AshToad_game.glb")
const CREATURE_ANIM_SHADER = preload("res://shaders/creature_anim.gdshader")

enum State { ARRIVING, CHASE, WINDUP, STRIKE, EXHAUSTED, PHASE_SHIFT, DEAD }
enum Pattern { LEAP, SPIT, TONGUE, COMBO }

const DISPLAY_NAME := "Aschenkröte"
const CORPSE_KIND := "apex_toad"
# See "Fight length" above.
const HEALTH := 1500.0
# AshToad_game.glb is ~1.05 x 1.04 m in plan and 0.56 m high (feet at 0, head +Z);
# scaled to the footprint of the former stand-in (~12 m). The hull flattens it a
# little so the back does not tower over the swarm in the top-down camera
# (body space: x = length, head towards -x; y = height; z = width).
const MODEL_SCALE := 11.2
const HULL_SCALE := Vector3(1.0, 0.8, 1.0)
# Mouth corner in raw mesh units (forward, height): spit balls and the tongue start here.
const MOUTH := Vector2(0.46, 0.29)
# Distance (m) from the centre to the front feet / haunches: pitch pivots.
const LEAN_PIVOT_FRONT := 3.4
const LEAN_PIVOT_BACK := 3.0
const BODY_RADIUS := 3.6
# Centre distance for HuntWorld's melee_factor fallback (body edge + ~2 m).
const MELEE_RANGE := 5.6
const MOVE_RADIUS := 3.2
# Toads hop slowly; the leap brings it to the swarm anyway.
const SPEED := [1.2, 1.55]
const ARRIVE_SECONDS := 2.4
const EMERGE_DEPTH := 5.0
const PHASE_TWO_SHARE := 0.5
const PHASE_SHIFT_SECONDS := 1.8
const STRIKE_SECONDS := 0.5
const ATTACK_RANGE := 15.0
const KEEP_DISTANCE := 6.5
const COOLDOWN := [2.0, 1.3]
const EXHAUSTED_SECONDS := [4.0, 3.2]
const EXHAUSTED_VULNERABILITY := 1.6
const CYCLE := [[Pattern.LEAP, Pattern.SPIT, Pattern.TONGUE], [Pattern.LEAP, Pattern.COMBO, Pattern.TONGUE]]

const LEAP_WINDUP := [1.7, 1.55]
# Share of the leap wind-up spent crouching on the ground (hittable) before take-off.
const LEAP_CROUCH := 0.4
const LEAP_DAMAGE := 12.0
const LEAP_RADIUS := [4.2, 4.6]
const LEAP_MAX := 16.0
const LEAP_HEIGHT := 5.5

const SPIT_WINDUP := [1.5, 1.3]
const SPIT_DAMAGE := 5.0
const SPIT_RADIUS := [1.9, 2.0]
# The circle on the swarm is larger so its contour stays visible around a big clump.
const SPIT_CENTER_RADIUS := [2.6, 2.8]
const SPIT_DISTANCE := 5.0
# Extra blobs around the swarm; angle 0 = from the swarm towards the toad.
const SPIT_ANGLES := [[PI * 0.5, -PI * 0.5], [1.2, -1.2, 2.45, -2.45]]
const PUDDLE_SHARE := 0.85
const PUDDLE_SECONDS := [3.0, 3.5]
const PUDDLE_TICK := 0.8
const PUDDLE_DAMAGE := 2.0

const TONGUE_WINDUP := [0.95, 0.8]
const TONGUE_DAMAGE := 7.0
const TONGUE_WIDTH := [1.8, 2.0]
const TONGUE_LENGTH := [15.0, 17.0]
const TONGUE_START := 2.4

const COMBO_WINDUP := 1.35

const PATTERN_NAMES := {Pattern.LEAP: "Aschensprung", Pattern.SPIT: "Glutspucke", Pattern.TONGUE: "Zungenpeitsche", Pattern.COMBO: "Glutpeitsche"}
# Shader pattern ids: 0 leap disc, 1 spit circle, 2 tongue lane, 3 puddle.
const SHAPE_LEAP := 0
const SHAPE_SPIT := 1
const SHAPE_TONGUE := 2
const SHAPE_PUDDLE := 3

const RIM_CHASE := Color("ffb45a")
const RIM_WARNING := Color("ffe45a")
const RIM_EXHAUSTED := Color("7fe7ff")
const RIM_RAGE := Color("ff6a2a")
# The model's own colours stay (no recolour); phase 2 only warms them slightly.
const SKIN_TINT := Color(1.0, 1.0, 1.0, 0.0)
const SKIN_TINT_RAGE := Color(1.0, 0.42, 0.16, 0.16)
const ASH := Color(0.55, 0.5, 0.5, 0.7)
# Ember veins: orange vertex colours are pushed towards this glow colour.
const EMBER_COLOR := Color("ff7a1e")
const EMBER_COLOR_RAGE := Color("ffa23a")
const TONGUE_COLOR := Color("d8506e")

# Stage 20: shared boss telegraph style (telegraph_style.gd). Leap and spit are
# the SVG boss circle, the tongue a boss lane with chevrons, the Glutpfützen a
# filled hazard area ("liegt da"); shapes differ, so colour is never the only cue.
const TG = preload("res://scripts/telegraph_style.gd")
const PALETTE := {
	SHAPE_LEAP: TG.PALETTE["boss"],
	SHAPE_SPIT: TG.PALETTE["boss"],
	SHAPE_TONGUE: TG.PALETTE["boss"],
	SHAPE_PUDDLE: TG.PALETTE["hazard"],
}
const PALETTE_COLORBLIND := {
	SHAPE_LEAP: TG.PALETTE_COLORBLIND["boss"],
	SHAPE_SPIT: TG.PALETTE_COLORBLIND["boss"],
	SHAPE_TONGUE: TG.PALETTE_COLORBLIND["boss"],
	SHAPE_PUDDLE: TG.PALETTE_COLORBLIND["hazard"],
}

var state := State.ARRIVING
var remaining := ARRIVE_SECONDS
var health := HEALTH
var max_health := HEALTH
var phase := 1
var current_pattern := Pattern.LEAP
var cycle_index := 0
var cooldown := 1.2
var attack_center := Vector3.ZERO
var attack_power := 0
var resolved_power := 0
var migration_ready := false
var migration_point := Vector3.ZERO
var body_radius := BODY_RADIUS
var melee_range := MELEE_RANGE
var corpse_kind := CORPSE_KIND
var arena: Node3D
# Locked attack shape: {"shape": SHAPE_*, "center": Vector3, "radius": float} for discs,
# {"shape": SHAPE_TONGUE, "center": origin, "direction": Vector3, "width", "length"} for the lane.
var zones: Array[Dictionary] = []
var leap_from := Vector3.ZERO
var leap_to := Vector3.ZERO
# Phase 2: a leap is followed by a spit volley; the boss is exhausted after the chain.
var chained := false
var puddles: Puddles
var hit_flash := 0.0
var colorblind := false
# Presentation only.
var model: Node3D
var hull: Node3D
var body: Node3D
var skin: ShaderMaterial
# Ember vein glow of the skin (0..1), raised before a spit and in phase 2.
var ember := 0.0
var shadow: MeshInstance3D
var warning: Node3D
var telegraphs: Array[MeshInstance3D] = []
var balls: Array[MeshInstance3D] = []
var tongue: MeshInstance3D
var emerge := 0.0
var _windup_total := 1.0
var _time := 0.0
var _gait := 0.0
var _slam := 0.0
var _rim := RIM_CHASE
var _lift := 0.0
var _lean := 0.0
var _sway := 0.0
var _stretch := 0.0
var _walk := 0.0
var _jaw := 0.0
var _sink := 0.0
var _grow := 1.0
var _air := 0.0


func _ready() -> void:
	colorblind = UI_STYLE.colorblind
	_build_model()
	shadow = _make_shadow()
	warning = Node3D.new()
	warning.name = "Aschenkröte warnings"
	add_child(warning)
	warning.top_level = true
	warning.global_transform = Transform3D.IDENTITY
	puddles = Puddles.new()
	puddles.name = "Glutpfützen"
	puddles.owner_toad = self
	add_child(puddles)
	puddles.top_level = true
	puddles.global_transform = Transform3D.IDENTITY
	_build_projectiles()
	FX.ring(_fx_parent(), global_position, Color(0.55, 0.48, 0.48, 0.85), 1.0, 7.5, 1.2)
	FX.ring(_fx_parent(), global_position, Color(1.0, 0.62, 0.2, 0.75), 0.6, 5.0, 1.6)
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


# Damage multiplier of the current state (immune while emerging, roaring or airborne).
func vulnerability() -> float:
	match state:
		State.ARRIVING, State.PHASE_SHIFT, State.DEAD:
			return 0.0
		State.EXHAUSTED:
			return EXHAUSTED_VULNERABILITY
	if is_airborne():
		return 0.0
	return 1.0


func can_be_hit() -> bool:
	return vulnerability() > 0.0


func is_airborne() -> bool:
	return state == State.WINDUP and current_pattern == Pattern.LEAP and windup_progress() >= LEAP_CROUCH


func step(delta: float, swarm_position: Vector3, pressure: float) -> int:
	resolved_power = 0
	if puddles != null:
		puddles.resolved_power = 0
	var previous_position := position
	var result := _logic(delta, swarm_position, pressure)
	if puddles != null and delta > 0.0 and state != State.DEAD:
		puddles.advance(delta, pressure)
	var speed := 0.0
	if delta > 0.0 and not is_airborne():
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
		if current_pattern == Pattern.LEAP:
			_fly()
		if remaining > 0.0:
			return 0
		return _resolve(swarm_position)
	if remaining > 0.0:
		return 0
	match state:
		State.ARRIVING:
			state = State.CHASE
		State.STRIKE:
			if current_pattern == Pattern.LEAP and phase == 2 and not chained:
				chained = true
				begin_attack(Pattern.SPIT, swarm_position, pressure)
			elif current_pattern == Pattern.LEAP or chained:
				chained = false
				state = State.EXHAUSTED
				remaining = EXHAUSTED_SECONDS[phase - 1]
			else:
				state = State.CHASE
				cooldown = COOLDOWN[phase - 1]
		State.EXHAUSTED, State.PHASE_SHIFT:
			state = State.CHASE
			cooldown = COOLDOWN[phase - 1] * 0.5
	return 0


## Starts a wind-up now and locks its shape. Public for tests and scripted
## moments; the normal flow calls it from CHASE.
func begin_attack(pattern: int, swarm_position: Vector3, pressure: float) -> void:
	var index := phase - 1
	current_pattern = pattern
	state = State.WINDUP
	zones.clear()
	var here := Vector3(position.x, 0.0, position.z)
	var target := Vector3(swarm_position.x, 0.0, swarm_position.z)
	var toward := target - here
	toward = toward.normalized() if toward.length_squared() > 0.0001 else Vector3(-1, 0, 0)
	rotation.y = atan2(toward.x, toward.z) + PI * 0.5
	attack_center = here
	var base := 0.0
	match pattern:
		Pattern.LEAP:
			remaining = LEAP_WINDUP[index]
			base = LEAP_DAMAGE
			var jump := target - here
			if jump.length() > LEAP_MAX:
				jump = jump.normalized() * LEAP_MAX
			var land := here + jump
			var field := _arena()
			if field != null and field.has_method("safe_spawn"):
				land = field.safe_spawn(land, MOVE_RADIUS)
				land.y = 0.0
			leap_from = here
			leap_to = land
			attack_center = land
			zones.append({"shape": SHAPE_LEAP, "center": land, "radius": float(LEAP_RADIUS[index])})
		Pattern.SPIT:
			remaining = SPIT_WINDUP[index]
			base = SPIT_DAMAGE
			attack_center = target
			_add_spit(target, -toward, SPIT_ANGLES[index], SPIT_RADIUS[index], SPIT_CENTER_RADIUS[index])
		Pattern.TONGUE:
			remaining = TONGUE_WINDUP[index]
			base = TONGUE_DAMAGE
			_add_tongue(here, toward, TONGUE_WIDTH[index], TONGUE_LENGTH[index])
		Pattern.COMBO:
			remaining = COMBO_WINDUP
			base = maxf(TONGUE_DAMAGE, SPIT_DAMAGE)
			_add_tongue(here, toward, TONGUE_WIDTH[1], TONGUE_LENGTH[1])
			_add_spit(target, -toward, SPIT_ANGLES[0], SPIT_RADIUS[0], SPIT_CENTER_RADIUS[0])
	_windup_total = remaining
	attack_power = int(ceil(minf(1000000.0, base * pressure)))
	_build_telegraphs()


func _add_spit(center: Vector3, to_toad: Vector3, angles: Array, radius: float, center_radius: float) -> void:
	zones.append({"shape": SHAPE_SPIT, "center": center, "radius": center_radius})
	for angle in angles:
		var spot: Vector3 = center + to_toad.rotated(Vector3.UP, float(angle)) * SPIT_DISTANCE
		zones.append({"shape": SHAPE_SPIT, "center": spot, "radius": radius})


func _add_tongue(origin: Vector3, direction: Vector3, width: float, length: float) -> void:
	zones.append({"shape": SHAPE_TONGUE, "center": origin, "direction": direction, "width": width, "length": length})


func _fly() -> void:
	var t := clampf((windup_progress() - LEAP_CROUCH) / (1.0 - LEAP_CROUCH), 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	var flat := leap_from.lerp(leap_to, eased)
	position = Vector3(flat.x, position.y, flat.z)
	_air = 4.0 * t * (1.0 - t) * LEAP_HEIGHT


func _resolve(swarm_position: Vector3) -> int:
	state = State.STRIKE
	remaining = STRIKE_SECONDS
	resolved_power = attack_power
	if current_pattern == Pattern.LEAP:
		position = Vector3(leap_to.x, position.y, leap_to.z)
		_air = 0.0
	if current_pattern == Pattern.SPIT or current_pattern == Pattern.COMBO:
		for zone in zones:
			if int(zone.shape) == SHAPE_SPIT:
				puddles.add(zone.center, float(zone.radius) * PUDDLE_SHARE, PUDDLE_SECONDS[phase - 1], telegraph_material(SHAPE_PUDDLE, colorblind))
	_clear_telegraphs()
	_strike_fx()
	return attack_power if contains(swarm_position) else 0


func _enter_phase_two() -> void:
	phase = 2
	if state == State.WINDUP and current_pattern == Pattern.LEAP:
		# Cancelled mid-air: set down on the (announced) landing spot without damage.
		position = Vector3(leap_to.x, position.y, leap_to.z)
	_air = 0.0
	chained = false
	state = State.PHASE_SHIFT
	remaining = PHASE_SHIFT_SECONDS
	cycle_index = 0
	_clear_telegraphs()
	FX.ring(_fx_parent(), global_position, Color(1.0, 0.49, 0.76, 0.9), 1.0, 9.5, 0.8)
	FX.ring(_fx_parent(), global_position, Color(0.6, 0.55, 0.55, 0.7), 0.5, 6.5, 1.2)
	_shake(0.6)
	phase_changed.emit(phase)


func _die() -> void:
	health = minf(health, 0.0)
	state = State.DEAD
	remaining = 0.0
	_air = 0.0
	chained = false
	migration_ready = true
	migration_point = Vector3(position.x, 0.0, position.z)
	_clear_telegraphs()
	if puddles != null:
		puddles.clear()
	FX.ring(_fx_parent(), global_position, Color(1.0, 0.78, 0.4, 0.95), 1.0, 11.0, 1.2)
	FX.ring(_fx_parent(), global_position, Color(0.55, 0.5, 0.5, 0.8), 0.6, 7.0, 1.6)
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


# ------------------------------------------------------------------ areas

# Locked area of the current / last attack.
func contains(point: Vector3) -> bool:
	for zone in zones:
		if zone_contains(zone, point):
			return true
	return false


static func zone_contains(zone: Dictionary, point: Vector3) -> bool:
	var center: Vector3 = zone.center
	var flat := Vector2(point.x - center.x, point.z - center.z)
	if int(zone.shape) == SHAPE_TONGUE:
		var direction: Vector3 = zone.direction
		var along := flat.dot(Vector2(direction.x, direction.z))
		var across := absf(flat.x * direction.z - flat.y * direction.x)
		return along >= TONGUE_START and along <= TONGUE_START + float(zone.length) and across <= float(zone.width) * 0.5
	return flat.length() <= float(zone.radius)


func hit_fraction(points: PackedVector3Array) -> float:
	if points.is_empty():
		return 0.0
	var inside := 0
	for point in points:
		if contains(point):
			inside += 1
	return float(inside) / float(points.size())


func is_safe(point: Vector3) -> bool:
	return state != State.WINDUP or not contains(point)


## Flat distance from `point` to the body rim (0 = touching or inside).
func body_distance(point: Vector3) -> float:
	return maxf(0.0, Vector2(point.x - position.x, point.z - position.z).length() - body_radius)


func contains_body(point: Vector3) -> bool:
	return body_distance(point) <= 0.0


func windup_progress() -> float:
	return clampf(1.0 - remaining / maxf(_windup_total, 0.001), 0.0, 1.0) if state == State.WINDUP else 0.0


func hud_message() -> String:
	match state:
		State.ARRIVING:
			return "DIE ASCHENKRÖTE ERWACHT"
		State.WINDUP:
			match current_pattern:
				Pattern.LEAP:
					return "ASCHENSPRUNG · RAUS AUS DER LANDEZONE!"
				Pattern.SPIT:
					return "GLUTSPUCKE · WEG VON DEN KREISEN!"
				Pattern.TONGUE:
					return "ZUNGENPEITSCHE · SEITLICH AUSWEICHEN!"
				Pattern.COMBO:
					return "GLUTPEITSCHE · LÜCKE SCHRÄG HINTEN!"
		State.EXHAUSTED:
			return "ASCHENKRÖTE ERSCHÖPFT · JETZT ANGREIFEN!"
		State.PHASE_SHIFT:
			return "DIE ASCHENKRÖTE KOCHT ÜBER!"
		State.DEAD:
			return "DIE ASCHENKRÖTE IST BEZWUNGEN"
	if puddles != null and puddles.active():
		return "GLUTPFÜTZEN MEIDEN"
	return ""


static func pattern_name(pattern: int) -> String:
	return String(PATTERN_NAMES.get(pattern, ""))


# ------------------------------------------------------------ glow puddles

## Lingering Glutpfützen after a spit. Visible from the moment they form (the
## spit circle announced them), tick every PUDDLE_TICK s. Resolve like an enemy
## area: resolved_power (> 0 only in a tick step) + contains(point).
class Puddles extends Node3D:
	var owner_toad: Node3D
	var spots: Array[Dictionary] = []
	var resolved_power := 0
	var last_center := Vector3.ZERO
	var tick_clock := 0.0

	func active() -> bool:
		return not spots.is_empty()

	func add(center: Vector3, radius: float, seconds: float, material: ShaderMaterial) -> void:
		if spots.is_empty():
			tick_clock = PUDDLE_TICK
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(radius * 2.0, radius * 2.0) + Vector2.ONE * TG.SHAPE_MARGIN * 2.0
		material.set_shader_parameter("outer", radius)
		var part := MeshInstance3D.new()
		part.name = "Glutpfütze"
		part.mesh = mesh
		part.material_override = material
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		part.position = Vector3(center.x, 0.1, center.z)
		add_child(part)
		spots.append({"center": Vector3(center.x, 0.0, center.z), "radius": radius, "remaining": seconds, "total": seconds, "node": part})

	func advance(delta: float, pressure: float) -> void:
		resolved_power = 0
		if spots.is_empty():
			return
		tick_clock -= delta
		if tick_clock <= 0.0:
			tick_clock += PUDDLE_TICK
			resolved_power = int(ceil(minf(1000000.0, PUDDLE_DAMAGE * pressure)))
			last_center = spots[0].center
		for index in range(spots.size() - 1, -1, -1):
			var spot: Dictionary = spots[index]
			spot.remaining = float(spot.remaining) - delta
			var node: MeshInstance3D = spot.node
			if float(spot.remaining) <= 0.0:
				node.queue_free()
				spots.remove_at(index)
				continue
			var life := float(spot.remaining) / float(spot.total)
			var material := node.material_override as ShaderMaterial
			material.set_shader_parameter("progress", 1.0 - life)
			material.set_shader_parameter("opacity", clampf(life * 4.0, 0.0, 1.0))
		if spots.is_empty():
			resolved_power = 0

	func contains(point: Vector3) -> bool:
		for spot in spots:
			var center: Vector3 = spot.center
			if Vector2(point.x - center.x, point.z - center.z).length() <= float(spot.radius):
				return true
		return false

	func restyle(factory: Callable) -> void:
		for spot in spots:
			var node: MeshInstance3D = spot.node
			var fresh: ShaderMaterial = factory.call()
			var old := node.material_override as ShaderMaterial
			fresh.set_shader_parameter("progress", old.get_shader_parameter("progress"))
			fresh.set_shader_parameter("outer", old.get_shader_parameter("outer"))
			node.material_override = fresh

	func clear() -> void:
		for spot in spots:
			var node: MeshInstance3D = spot.node
			if is_instance_valid(node):
				node.queue_free()
		spots.clear()
		resolved_power = 0


# --------------------------------------------------------------- telegraphs

static func telegraph_material(shape: int, colorblind_on: bool) -> ShaderMaterial:
	var result: ShaderMaterial
	match shape:
		SHAPE_TONGUE:
			result = TG.shape_material(TG.Shape.LANE, "boss", colorblind_on)
		SHAPE_PUDDLE:
			result = TG.shape_material(TG.Shape.HAZARD, "hazard", colorblind_on)
		_:
			result = TG.material("boss", colorblind_on)
	result.set_shader_parameter("pattern", shape)
	return result


func restyle(colorblind_on: bool) -> void:
	colorblind = colorblind_on
	if state == State.WINDUP:
		_build_telegraphs()
	if puddles != null:
		puddles.restyle(telegraph_material.bind(SHAPE_PUDDLE, colorblind_on))


func _build_telegraphs() -> void:
	_clear_telegraphs()
	warning.global_transform = Transform3D.IDENTITY
	var height := 0.12
	for zone in zones:
		var shape := int(zone.shape)
		var part := MeshInstance3D.new()
		part.name = "Toad telegraph %s" % pattern_name(current_pattern)
		var material := telegraph_material(shape, colorblind)
		part.material_override = material
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var center: Vector3 = zone.center
		if shape == SHAPE_TONGUE:
			var direction: Vector3 = zone.direction
			var length := float(zone.length)
			var mesh := PlaneMesh.new()
			mesh.size = Vector2(float(zone.width), length) + Vector2.ONE * TG.SHAPE_MARGIN * 2.0
			part.mesh = mesh
			material.set_shader_parameter("half_width", float(zone.width) * 0.5)
			material.set_shader_parameter("lane_length", length)
			part.rotation.y = atan2(direction.x, direction.z)
			part.position = center + direction * (TONGUE_START + length * 0.5) + Vector3(0, height + 0.01, 0)
		else:
			# SVG boss circle: its hit ring lies exactly on the zone radius.
			part.mesh = TG.boss_circle_mesh(float(zone.radius))
			part.position = center + Vector3(0, height, 0)
		height += 0.004
		warning.add_child(part)
		telegraphs.append(part)
	warning.visible = true


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
	for zone in zones:
		var center: Vector3 = zone.center
		match int(zone.shape):
			SHAPE_LEAP:
				var radius := float(zone.radius)
				FX.ring(parent, center, Color(0.95, 0.92, 0.86, 0.95), 1.0, radius * 1.05, 0.45)
				# Shock ring: runs past the zone edge (visual only, the loss is the disc).
				FX.ring(parent, center, Color(1.0, 0.49, 0.76, 0.85), radius * 0.8, radius * 1.7, 0.7)
				FX.ring(parent, center, ASH, 0.6, radius * 0.9, 1.0)
				_shake(0.75)
			SHAPE_SPIT:
				FX.ring(parent, center, Color(1.0, 0.49, 0.76, 0.95), 0.3, float(zone.radius) * 1.1, 0.4)
				_shake(0.2)
			SHAPE_TONGUE:
				var direction: Vector3 = zone.direction
				for step_index in 4:
					var spot: Vector3 = center + direction * (TONGUE_START + 2.0 + float(step_index) * float(zone.length) / 4.0)
					FX.ring(parent, spot, Color(1.0, 0.6, 0.85, 0.85), 0.2, float(zone.width) * 0.9, 0.35 + 0.04 * step_index)
				_shake(0.3)
	_slam = STRIKE_SECONDS


# ------------------------------------------------------------------ look

## Builds the body from AshToad_game.glb (user model, head +Z, feet at y = 0).
## Everything else only needs `model`, `body` and `skin` (creature_anim material
## plus the ember-vein glow, see _skin_shader()).
func _build_model() -> void:
	body = Node3D.new()
	body.name = "Aschenkröte body"
	add_child(body)
	hull = Node3D.new()
	hull.name = "Aschenkröte hull"
	hull.scale = HULL_SCALE
	body.add_child(hull)
	model = MODEL.instantiate()
	model.name = "Aschenkröte model"
	model.scale = Vector3.ONE * MODEL_SCALE
	# Head (+Z) towards body -X, the facing direction of _forward().
	model.rotation.y = -PI * 0.5
	hull.add_child(model)
	skin = ShaderMaterial.new()
	skin.shader = _skin_shader()
	skin.set_shader_parameter("brightness", 1.1)
	skin.set_shader_parameter("saturation", 0.2)
	skin.set_shader_parameter("shape_light", 0.5)
	skin.set_shader_parameter("rim_color", _rim)
	skin.set_shader_parameter("rim_strength", 0.8)
	skin.set_shader_parameter("rim_power", 2.6)
	skin.set_shader_parameter("body_tint", SKIN_TINT)
	skin.set_shader_parameter("flash", 0.0)
	skin.set_shader_parameter("ember_color", EMBER_COLOR)
	skin.set_shader_parameter("ember_glow", 0.7)
	_setup_limbs()
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = skin
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# creature_anim.gdshader plus an ember-vein glow: vertex colours that are clearly
# orange (red well above blue) are pushed towards `ember_color` by `ember_glow`.
# Built from the shared shader's source so the limb animation stays identical.
static var _ember_shader: Shader


static func _skin_shader() -> Shader:
	if _ember_shader != null:
		return _ember_shader
	var code: String = CREATURE_ANIM_SHADER.code
	var uniforms := "uniform vec4 ember_color : source_color = vec4(1.0, 0.69, 0.25, 1.0);
uniform float ember_glow = 0.5;

void vertex()"
	var glow := "float ember_mask = smoothstep(0.34, 0.6, COLOR.r - COLOR.b) * smoothstep(0.48, 0.7, COLOR.r);
	look = mix(look, ember_color.rgb, clamp(ember_mask * ember_glow, 0.0, 0.92));
	ALBEDO = look;"
	if code.count("void vertex()") != 1 or code.count("ALBEDO = look;") != 1:
		push_warning("Aschenkröte: creature_anim shader changed, ember glow disabled")
		_ember_shader = CREATURE_ANIM_SHADER
		return _ember_shader
	var shader := Shader.new()
	shader.code = code.replace("void vertex()", uniforms).replace("ALBEDO = look;", glow)
	_ember_shader = shader
	return _ember_shader


# Limb frame for AshToad_game.glb in raw mesh space (Z-up storage): soles and belly
# at z = 0 (up = -Z), head towards +Y, lateral = +X. Feet centres (forward,
# lateral) from the lowest vertices outside the belly: short front legs under the
# head, wide sprawled haunches. The belly rests on the ground, so the legs only
# shuffle a little (the toad hops with the whole body, see _pose). The jaw is the
# pale throat below the mouth line (u = 0.29) in front of the forelegs; no tail.
func _setup_limbs() -> void:
	skin.set_shader_parameter("up_axis", Vector3(0.0, 0.0, -1.0))
	skin.set_shader_parameter("forward_axis", Vector3(0.0, 1.0, 0.0))
	skin.set_shader_parameter("ground_offset", 0.0)
	skin.set_shader_parameter("foot_a_front", Vector2(0.3, -0.26))
	skin.set_shader_parameter("foot_a_back", Vector2(-0.19, 0.4))
	skin.set_shader_parameter("foot_b_front", Vector2(0.3, 0.26))
	skin.set_shader_parameter("foot_b_back", Vector2(-0.19, -0.4))
	skin.set_shader_parameter("foot_radius", 0.13)
	skin.set_shader_parameter("leg_height", 0.16)
	skin.set_shader_parameter("stride", 0.035)
	skin.set_shader_parameter("lift", 0.04)
	skin.set_shader_parameter("stride_centering", 0.0)
	skin.set_shader_parameter("walk_speed", 0.0)
	skin.set_shader_parameter("walk_scale", 1.0)
	skin.set_shader_parameter("jaw_hinge_forward", 0.3)
	skin.set_shader_parameter("jaw_hinge_height", 0.29)
	skin.set_shader_parameter("jaw_floor", 0.12)
	skin.set_shader_parameter("jaw_angle", 0.38)
	skin.set_shader_parameter("tail_start", -1.0)
	skin.set_shader_parameter("tail_length", 0.1)
	skin.set_shader_parameter("tail_floor", 1.0)
	skin.set_shader_parameter("tail_swing", 0.0)
	skin.set_shader_parameter("tail_rate", 0.0)
	skin.set_shader_parameter("stomp_height", 0.1)


# Lava balls (spit) and the tongue (strike), top-level, hidden until used.
func _build_projectiles() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.45
	sphere.height = 0.9
	sphere.radial_segments = 10
	sphere.rings = 5
	var lava := StandardMaterial3D.new()
	lava.albedo_color = Color("ffc24a")
	lava.emission_enabled = true
	lava.emission = Color("ff7a1a")
	lava.emission_energy_multiplier = 1.6
	for index in 5:
		var ball := MeshInstance3D.new()
		ball.name = "Lava ball"
		ball.mesh = sphere
		ball.material_override = lava
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ball.visible = false
		warning.add_child(ball)
		balls.append(ball)
	var box := BoxMesh.new()
	box.size = Vector3(0.8, 0.35, 1.0)
	var flesh := StandardMaterial3D.new()
	flesh.albedo_color = TONGUE_COLOR
	flesh.roughness = 0.4
	tongue = MeshInstance3D.new()
	tongue.name = "Tongue"
	tongue.mesh = box
	tongue.material_override = flesh
	tongue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tongue.top_level = true
	tongue.visible = false
	add_child(tongue)


func refresh_pose() -> void:
	_pose(0.0, 0.0, true)


func _forward() -> Vector3:
	var forward := -transform.basis.x
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.0001 else Vector3(0, 0, -1)


func _pose(delta: float, speed: float, snap: bool = false) -> void:
	_time += delta
	hit_flash = maxf(0.0, hit_flash - delta)
	_slam = maxf(0.0, _slam - delta)
	emerge = clampf(1.0 - remaining / ARRIVE_SECONDS, 0.0, 1.0) if state == State.ARRIVING else 1.0
	var lift := 0.0
	var walk := 0.0
	var jaw := 0.0
	var lean := 0.0
	var sway := 0.0
	var stretch := 0.0
	var tremble := 0.0
	var swell := 0.0
	var rim_target := RIM_RAGE if phase == 2 else RIM_CHASE
	var rim_strength := 0.9
	var progress := windup_progress()
	match state:
		State.ARRIVING:
			tremble = 0.1 * (1.0 - emerge)
			lean = -0.12 * (1.0 - emerge)
		State.CHASE:
			var stride := minf(1.0, speed / float(SPEED[0]))
			var before := sin(_gait)
			_gait += speed * delta * 1.1
			var wave := sin(_gait)
			if stride > 0.2 and before != 0.0 and signf(wave) != signf(before):
				FX.ring(_fx_parent(), global_position, ASH, 0.6, 3.0, 0.45)
				_shake(0.1)
			# Hops with the whole body: up and stretched in the air, squashed on contact.
			var hop := absf(wave)
			lift = hop * 0.8 * stride
			stretch = (hop - 0.45) * 0.14 * stride
			walk = stride * 0.4
			lean = -0.07 * wave * stride
		State.WINDUP:
			var rise := 1.0 - pow(1.0 - minf(1.0, progress / 0.7), 3.0)
			rim_target = RIM_WARNING
			tremble = 0.1 * smoothstep(0.6, 1.0, progress)
			match current_pattern:
				Pattern.LEAP:
					if progress < LEAP_CROUCH:
						# Loads up: squashes low, nose down, trembling.
						var crouch := sin(progress / LEAP_CROUCH * PI * 0.5)
						stretch = -0.22 * crouch
						lean = 0.12 * crouch
						tremble = 0.07 * crouch
					else:
						# Take-off stretch, nose up; tips forward towards the landing.
						var flight := (progress - LEAP_CROUCH) / (1.0 - LEAP_CROUCH)
						stretch = 0.24 * pow(1.0 - flight, 2.0) + 0.06 * flight
						lean = lerpf(-0.32, 0.14, flight)
						jaw = 0.25
						tremble = 0.0
				Pattern.SPIT:
					# Rears up with a swelling throat, veins flare, mouth opens.
					lean = -0.18 * rise
					stretch = 0.07 * rise
					jaw = 0.85 * rise * (0.85 + 0.15 * sin(_time * 14.0))
					swell = rise
				Pattern.TONGUE:
					# Ducks low with the head forward, mouth wide open.
					lean = 0.16 * rise
					stretch = -0.1 * rise
					jaw = 1.0 * rise
				Pattern.COMBO:
					lean = -0.08 * rise
					stretch = 0.03 * rise
					jaw = 1.0 * rise
					swell = rise
			for part in telegraphs:
				(part.material_override as ShaderMaterial).set_shader_parameter("progress", progress)
		State.EXHAUSTED:
			# Slumped flat, chin on the ground, veins almost out, slow heavy breath.
			var breath := sin(_time * 1.6)
			lean = 0.14 + 0.02 * breath
			stretch = -0.14 + 0.04 * breath
			jaw = 0.45 + 0.2 * breath
			rim_target = RIM_EXHAUSTED
			# The craggy rock hide has many grazing facets: a softer rim than the
			# Moosschlund keeps the model readable under the pulsing blue.
			rim_strength = 0.7 + 0.35 * (0.5 + 0.5 * sin(_time * 5.0))
			swell = -0.7
		State.PHASE_SHIFT:
			var roar := clampf(1.0 - remaining / PHASE_SHIFT_SECONDS, 0.0, 1.0)
			lean = -0.34 * sin(roar * PI)
			stretch = 0.15 * sin(roar * PI)
			jaw = 1.0
			tremble = 0.12
			swell = 1.0
			rim_target = RIM_RAGE
			rim_strength = 1.2
		State.DEAD:
			_sink = minf(1.0, _sink + delta / 2.4)
			lean = 0.2
			jaw = 0.8
			sway = 0.22 * _sink
			stretch = -0.15 * _sink
			swell = -1.0
	if _slam > 0.0:
		var slam := _slam / STRIKE_SECONDS
		if current_pattern == Pattern.LEAP:
			# Landing squash.
			stretch -= 0.32 * slam
			lean *= 1.0 - slam
		else:
			lean += 0.2 * slam
			jaw = maxf(jaw, slam)
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
	_rim = rim_target if snap else _rim.lerp(rim_target, minf(1.0, delta * 5.0))
	var grow_target := 1.1 if phase == 2 else 1.0
	_grow = grow_target if snap else lerpf(_grow, grow_target, minf(1.0, delta * 2.0))
	if not is_airborne():
		_air = 0.0
	var risen := 1.0 - pow(1.0 - emerge, 3.0)
	var jitter := Vector3(sin(_time * 43.0), 0.0, sin(_time * 37.0 + 1.3)) * tremble
	# Pitch pivots on the lower end (front feet when the nose dips, haunches when it
	# rises), so the feet stay on the ground instead of sinking into it.
	var pivot := LEAN_PIVOT_FRONT if _lean > 0.0 else LEAN_PIVOT_BACK
	var level := absf(sin(_lean)) * pivot * _grow
	body.position = Vector3(0.0, _lift + _air + level - EMERGE_DEPTH * (1.0 - risen) - EMERGE_DEPTH * 0.6 * _sink, 0.0) + jitter
	body.rotation = Vector3(_sway, 0.0, _lean)
	body.scale = Vector3(1.0 - _stretch * 0.5, 1.0 + _stretch, 1.0 - _stretch * 0.5) * _grow
	var shadow_size := lerpf(0.3, 1.0, risen) * (1.0 - 0.4 * clampf(_air / LEAP_HEIGHT, 0.0, 1.0)) * (1.0 - _sink * 0.7) * _grow
	shadow.scale = Vector3(shadow_size, 1.0, shadow_size)
	skin.set_shader_parameter("rim_color", _rim)
	skin.set_shader_parameter("rim_strength", rim_strength)
	skin.set_shader_parameter("flash", flash)
	skin.set_shader_parameter("body_tint", SKIN_TINT_RAGE if phase == 2 else SKIN_TINT)
	skin.set_shader_parameter("walk_amount", _walk)
	skin.set_shader_parameter("walk_phase", _gait + PI * 0.5)
	skin.set_shader_parameter("stomp_lift", 0.0)
	skin.set_shader_parameter("bite_amount", _jaw)
	skin.set_shader_parameter("tail_phase", _time * 1.1)
	var ember_target := clampf(0.7 * (1.0 + minf(swell, 0.0)) + 0.3 * maxf(swell, 0.0) + (0.2 if phase == 2 else 0.0), 0.04, 1.0)
	ember = ember_target if snap else lerpf(ember, ember_target, minf(1.0, delta * 6.0))
	var flicker := 1.0 + 0.08 * sin(_time * 7.0) * (0.3 + 0.7 * maxf(swell, 0.0))
	skin.set_shader_parameter("ember_glow", clampf(ember * flicker, 0.0, 1.0))
	skin.set_shader_parameter("ember_color", EMBER_COLOR_RAGE if phase == 2 else EMBER_COLOR)
	_pose_projectiles(progress)


func _pose_projectiles(progress: float) -> void:
	if balls.is_empty():
		return
	var spit := state == State.WINDUP and (current_pattern == Pattern.SPIT or current_pattern == Pattern.COMBO)
	var ball_index := 0
	var mouth := _mouth()
	var launch := 0.45
	for zone in zones:
		if not spit or ball_index >= balls.size():
			break
		if int(zone.shape) != SHAPE_SPIT:
			continue
		var ball := balls[ball_index]
		var t := clampf((progress - launch - 0.05 * ball_index) / (1.0 - launch - 0.05 * ball_index), 0.0, 1.0)
		ball.visible = t > 0.0
		var target: Vector3 = zone.center
		var arc := 4.0 * t * (1.0 - t) * 5.0
		ball.global_position = mouth.lerp(target, t) + Vector3(0, arc, 0)
		ball_index += 1
	for index in range(ball_index, balls.size()):
		balls[index].visible = false
	# Tongue: shoots out along the lane during the strike, then snaps back.
	var lane: Dictionary = {}
	for zone in zones:
		if int(zone.shape) == SHAPE_TONGUE:
			lane = zone
	if tongue != null:
		tongue.visible = state == State.STRIKE and not lane.is_empty()
		if tongue.visible:
			# From the mouth down to the lane tip on the ground.
			var reach := sin(clampf(1.0 - remaining / STRIKE_SECONDS, 0.0, 1.0) * PI)
			var direction: Vector3 = lane.direction
			var origin: Vector3 = lane.center
			var start := _mouth()
			var near := Vector2(start.x - origin.x, start.z - origin.z).length()
			var far := maxf(near + 0.3, (TONGUE_START + float(lane.length)) * reach)
			var tip := origin + direction * far + Vector3(0, 0.45, 0)
			var span := tip - start
			var shape := Basis.looking_at(span.normalized(), Vector3.UP) * Basis.from_scale(Vector3(float(lane.width) * 0.6, 1.0, span.length()))
			tongue.global_transform = Transform3D(shape, (start + tip) * 0.5)


## World position of the mouth (spit balls and the tongue start there).
func _mouth() -> Vector3:
	var height := MOUTH.y * MODEL_SCALE * HULL_SCALE.y * _grow * (1.0 + _stretch) + body.position.y
	return Vector3(position.x, 0.0, position.z) + _forward() * MOUTH.x * MODEL_SCALE * _grow + Vector3(0, height, 0)


# Bounds of every mesh below `root`, expressed in `space` coordinates.
static func _bounds(root: Node3D, space: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		var instance := mesh as MeshInstance3D
		var local := _relative(instance, space)
		var box: AABB = local * instance.mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


static func _relative(node: Node3D, space: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != space:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


func _shake(amount: float) -> void:
	var main: Node = get_parent().get_parent() if get_parent() != null else null
	if main != null and main.has_method("add_shake"):
		main.add_shake(amount)


func _fx_parent() -> Node:
	return get_parent() if get_parent() != null else self


func _make_shadow() -> MeshInstance3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.03, 0.02, 0.02, 0.62))
	gradient.set_color(1, Color(0.03, 0.02, 0.02, 0.0))
	gradient.add_point(0.55, Color(0.03, 0.02, 0.02, 0.42))
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
	plane.size = Vector2(8.6, 8.6)
	var part := MeshInstance3D.new()
	part.name = "Aschenkröte shadow"
	part.mesh = plane
	part.material_override = material
	part.position = Vector3(0, 0.06, 0)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
	return part
