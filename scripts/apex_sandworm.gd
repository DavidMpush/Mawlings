extends Node3D

# SANDWURM – apex of the desert "Dürrschlund" (stage 19, phase 1). A colossal
# armoured worm (user model Sandwurm_game.glb, head +Z, round tooth maw) that
# lives under the sand. Like the other apexes every loss is announced: each
# attack locks its shape at the start of the wind-up, shows its ground telegraph
# (telegraph_style.gd boss circle / boss cone, pattern AND colour) and resolves
# exactly once.
#
# Same interface as apex_boss.gd / apex_toad.gd (HuntWorld can hold it in `apex`):
#   step(delta, swarm_position, pressure) -> int   base loss if the swarm centre is hit
#   take_damage(amount)       scaled by vulnerability() (buried = 0, exhausted = x1.6)
#   can_be_hit(), contains(point) / hit_fraction(points)  locked area of the last attack
#   resolved_power, state, health, max_health, attack_center, body_radius, melee_range
#   phase, current_pattern, hud_message(), migration_ready / migration_point,
#   contains_body(point) / body_distance(point) (capsule of the surfaced body),
#   restyle(colorblind), refresh_pose(), windup_progress(), is_safe(point)
#   signals phase_changed(phase), defeated(location)
# The State enum has the same names AND values as apex_boss.State, so HuntWorld's
# `apex.state == APEX_BOSS.State.WINDUP / EXHAUSTED / PHASE_SHIFT` checks keep
# working (EXHAUSTED = the gold "attack now" state of the HUD).
# Extra for the integration (stage 19 phase 2):
#   signal grubs_released(center: Vector3, count: int)  phase 2: Sandmaden break out
#   take_grubs() -> Array[{center, count}]  the same releases as a queue (poll per frame)
#   is_buried()   true while it only shows as a sand trail (never hittable then)
#   corpse_kind = "apex_sandworm" (own corpse design), DISPLAY_NAME
#
# States:
#   ARRIVING    2.4 s: rumbles under the spawn point, bursts up vertically, roars
#               and dives again. Immune.
#   CHASE       buried: only a wandering sand trail with dust. Immune. Circles the
#               swarm at ORBIT_RADIUS until the cooldown ends, then attacks.
#   WINDUP      BREACH: buried (immune), the trail runs into the warning ring.
#               SWEEP: half surfaced beside the swarm, coils (hittable, x1.0).
#   STRIKE      BREACH: stands vertically out of the hole (hittable). SWEEP: whip.
#   EXHAUSTED   after a breach (chain): slumps over beside the hole, maw open.
#               x1.6 damage – the attack window.
#   PHASE_SHIFT at 50 % health: bursts up and rages 1.8 s (immune), frees grubs.
#
# Attack patterns (phase 1 / phase 2, base loss x pressure):
#   BREACH "Durchbruch" – ring (4.2 / 4.0 m) under the swarm, shifted ahead of its
#          movement (lead 0.35 s, max 2.5 m); wind-up 1.6 / 1.4 s, loss 12. The worm
#          bursts out vertically with its round maw. Dodge: leave the ring.
#          Phase 2: two breaches in a row (the second locks on the swarm again),
#          each frees GRUBS_PER_BREACH Sandmaden; exhausted after the chain.
#   SWEEP  "Schwanzfeger" – surfaces half 6 m beside the swarm and sweeps a cone
#          (reach 12 / 14 m, half angle 0.55 rad) through it; wind-up
#          1.35 / 1.2 s, loss 8. Dodge: sideways out of the cone or behind the worm.
# Cycle phase 1: BREACH, SWEEP. Phase 2: BREACH x2, SWEEP; burrows faster
# (5.2 -> 6.8 m/s), shorter cooldowns (1.6 -> 0.9 s), shorter exhaustion.
#
# Fight length: the worm is hittable only surfaced (about half of a cycle, the
# toad ~85 %) and the swarm has to run back to it after every dodge, so it gets
# less standalone health than the toad (1500): HEALTH 1000 gives ~39 s against a
# 40 DPS bot that dodges everything (59 s @30, 35 s @55; tests/apex_sandworm.gd, same
# target band as the toad: 35-50 s; 1250 gave 53 s). Like the toad, a run will
# not use this constant: HuntWorld scales TUNING.APEX_SANDWORM_HEALTH (stage 19
# phase 2; proposal ~2500, between Moosschlund 1400 and Aschenkröte 3600, since
# the desert lies between them). Damage numbers match the toad (breach = leap
# 12, sweep 8 just above the tongue 7). Balance numbers live here until
# the worm is wired into HuntWorld; then they move to tuning.gd (APEX_SANDWORM_*).

signal defeated(location: Vector3)
signal phase_changed(phase: int)
signal grubs_released(center: Vector3, count: int)

const FX = preload("res://scripts/fx.gd")
const FX_BATCH = preload("res://scripts/fx_batch.gd")
const TG = preload("res://scripts/telegraph_style.gd")
const UI_STYLE = preload("res://scripts/ui/ui_style.gd")
const MODEL = preload("res://assets/gameplay/characters/Sandwurm_game.glb")
const CREATURE_ANIM_SHADER = preload("res://shaders/creature_anim.gdshader")

enum State { ARRIVING, CHASE, WINDUP, STRIKE, EXHAUSTED, PHASE_SHIFT, DEAD }
enum Pattern { BREACH, SWEEP }

const DISPLAY_NAME := "Sandwurm"
const CORPSE_KIND := "apex_sandworm"
# See "Fight length" above.
const HEALTH := 1000.0
# Sandwurm_game.glb: ~0.48 m wide, 0.5 m high, 1.09 m long (tail mound at -0.66,
# maw at +0.43 along +Z). At 11 x the surfaced head reaches ~8 m from the hole.
const MODEL_SCALE := 11.0
# Raw +Z coordinate where the neck leaves the model's sand mound: the hole.
const HOLE_Z := -0.3
# Maw centre in raw units (forward, height) and its radius (maw flare in the shader).
const MAW := Vector2(0.43, 0.3)
# Capsule of the surfaced body (hole -> head) for melee and body_distance().
const BODY_RADIUS := 2.4
const HEAD_REACH := 6.5
const SWEEP_REACH_BODY := 3.5
const MELEE_RANGE := 6.0
const BURROW_SPEED := [5.2, 6.8]
const ORBIT_RADIUS := 8.5
const ARRIVE_SECONDS := 2.4
const PHASE_TWO_SHARE := 0.5
const PHASE_SHIFT_SECONDS := 1.8
const DIVE_SECONDS := 0.7
const ATTACK_RANGE := 16.0
const COOLDOWN := [1.6, 0.9]
const EXHAUSTED_SECONDS := [3.6, 2.8]
const EXHAUSTED_VULNERABILITY := 1.6
const CYCLE := [[Pattern.BREACH, Pattern.SWEEP], [Pattern.BREACH, Pattern.SWEEP]]

const BREACH_WINDUP := [1.6, 1.4]
const BREACH_DAMAGE := 12.0
const BREACH_RADIUS := [4.2, 4.0]
const BREACH_LEAD := 0.35
const BREACH_LEAD_MAX := 2.5
const BREACH_STRIKE := 0.6
const GRUBS_PER_BREACH := 4
const GRUBS_ON_RAGE := 6

const SWEEP_WINDUP := [1.35, 1.2]
const SWEEP_DAMAGE := 8.0
const SWEEP_DISTANCE := 6.0
const SWEEP_REACH := [12.0, 14.0]
# Stage 20: exactly the SVG cone's opening (29.2 deg), so the drawn arc is a true
# circle of the reach (other angles stretch the art sideways).
const SWEEP_HALF_ANGLE := [TG.CONE_DEFAULT_ANGLE, TG.CONE_DEFAULT_ANGLE]
# Stage 20: the hit cone starts at its drawn origin (hit edge = drawn edge); the
# worm body covers that spot anyway.
const SWEEP_INNER := 0.0
const SWEEP_STRIKE := 0.45

const PATTERN_NAMES := {Pattern.BREACH: "Durchbruch", Pattern.SWEEP: "Schwanzfeger"}
const SHAPE_BREACH := 0
const SHAPE_SWEEP := 1

const RIM_CHASE := Color("ffd89a")
const RIM_WARNING := Color("ffe45a")
const RIM_EXHAUSTED := Color("7fe7ff")
const RIM_RAGE := Color("ff7a3a")
const SKIN_TINT := Color(1.0, 1.0, 1.0, 0.0)
const SKIN_TINT_RAGE := Color(1.0, 0.55, 0.32, 0.18)
# Sand look of trail and dust: pale ochre, darker churned sand in the furrow.
const SAND_DUST := Color(0.93, 0.85, 0.68, 0.55)
const SAND_MOUND := Color("d6bd8e")
const SAND_FURROW := Color("a88c60")
const SAND_CREST := Color("efe0bb")
const ROCK_CHUNK := Color("7a5a3c")
const TRAIL_STEP := 0.6
const TRAIL_SECONDS := 2.4
const TRAIL_MAX := 64
const DUST_MAX := 64
const DUST_EVERY := 0.06

var state := State.ARRIVING
var remaining := ARRIVE_SECONDS
var health := HEALTH
var max_health := HEALTH
var phase := 1
var current_pattern := Pattern.BREACH
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
# Locked attack shape: {"shape": SHAPE_BREACH, "center", "radius"} or
# {"shape": SHAPE_SWEEP, "center": origin, "direction", "reach", "half_angle"}.
var zones: Array[Dictionary] = []
# Phase 2: the first breach chains into a second one; exhausted after the chain.
var chained := false
# Remaining seconds of the dive at the start of CHASE (sinks in place, immune).
var dive := 0.0
var hit_flash := 0.0
var colorblind := false
var pending_grubs: Array[Dictionary] = []
# Presentation only.
var model: Node3D
var body: Node3D
var skin: ShaderMaterial
var shadow: MeshInstance3D
var warning: Node3D
var telegraphs: Array[MeshInstance3D] = []
var trail_batch: MultiMeshInstance3D
var dust_batch: MultiMeshInstance3D
var chunk_batch: MultiMeshInstance3D
var emerge := 0.0
# Pose (smoothed): rise 0 = buried .. 1 = fully out; pitch 0 = native lying pose ..
# 1 = vertical (maw up); yaw_swing = extra yaw of the sweep; slump = head down.
var _rise := 0.0
var _pitch := 1.0
var _swing := 0.0
var _slump := 0.0
var _maw := 0.0
var _wave := 0.0
var _windup_total := 1.0
var _time := 0.0
var _sink := 0.0
var _grow := 1.0
var _rim := RIM_CHASE
var _swarm_last := Vector3.INF
var _swarm_velocity := Vector3.ZERO
var _fall_yaw := 0.0
var _trail: Array[Dictionary] = []
var _trail_last := Vector3.INF
var _dust: Array[Dictionary] = []
var _dust_clock := 0.0
var _chunks: Array[Dictionary] = []


func _ready() -> void:
	colorblind = UI_STYLE.colorblind
	_build_model()
	shadow = _make_shadow()
	warning = Node3D.new()
	warning.name = "Sandwurm warnings"
	add_child(warning)
	warning.top_level = true
	warning.global_transform = Transform3D.IDENTITY
	_build_sand_fx()
	FX.ring(_fx_parent(), global_position, Color(0.9, 0.8, 0.6, 0.85), 1.0, 7.5, 1.2)
	_shake(0.4)
	_pose(0.0, true)


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


## Damage multiplier of the current state: only a surfaced worm can be hurt.
func vulnerability() -> float:
	match state:
		State.EXHAUSTED:
			return EXHAUSTED_VULNERABILITY
		State.STRIKE:
			return 1.0
		State.WINDUP:
			return 1.0 if current_pattern == Pattern.SWEEP else 0.0
	return 0.0


func can_be_hit() -> bool:
	return vulnerability() > 0.0


## Buried: nothing but the sand trail is visible.
func is_buried() -> bool:
	return state == State.CHASE or (state == State.WINDUP and current_pattern == Pattern.BREACH)


func step(delta: float, swarm_position: Vector3, pressure: float) -> int:
	resolved_power = 0
	if delta > 0.0:
		_track_swarm(delta, swarm_position)
	var result := _logic(delta, swarm_position, pressure)
	_pose(delta)
	return result


func _track_swarm(delta: float, swarm_position: Vector3) -> void:
	var flat := Vector3(swarm_position.x, 0.0, swarm_position.z)
	if _swarm_last.is_finite():
		var velocity := (flat - _swarm_last) / delta
		if velocity.length() > 14.0:
			velocity = Vector3.ZERO  # teleport (migration, test setup)
		_swarm_velocity = _swarm_velocity.lerp(velocity, minf(1.0, delta * 6.0))
	_swarm_last = flat


func _logic(delta: float, swarm_position: Vector3, pressure: float) -> int:
	if state == State.DEAD or delta <= 0.0:
		return 0
	if phase == 1 and health <= max_health * PHASE_TWO_SHARE and state != State.ARRIVING and state != State.PHASE_SHIFT:
		_enter_phase_two()
		return 0
	var offset := swarm_position - position
	offset.y = 0.0
	if state == State.CHASE:
		if dive > 0.0:
			dive = maxf(0.0, dive - delta)
			return 0
		cooldown -= delta
		if cooldown <= 0.0 and offset.length() <= ATTACK_RANGE:
			begin_attack(CYCLE[phase - 1][cycle_index % CYCLE[phase - 1].size()], swarm_position, pressure)
			cycle_index += 1
			return 0
		_burrow(swarm_position, delta)
		return 0
	remaining -= delta
	if state == State.WINDUP:
		if current_pattern == Pattern.BREACH:
			_approach(attack_center, delta)
		if remaining > 0.0:
			return 0
		return _resolve(swarm_position)
	if remaining > 0.0:
		return 0
	match state:
		State.ARRIVING:
			_start_dive()
		State.STRIKE:
			if current_pattern == Pattern.BREACH and phase == 2 and not chained:
				chained = true
				begin_attack(Pattern.BREACH, swarm_position, pressure)
			elif current_pattern == Pattern.BREACH:
				chained = false
				state = State.EXHAUSTED
				remaining = EXHAUSTED_SECONDS[phase - 1]
			else:
				_start_dive()
				cooldown = COOLDOWN[phase - 1]
		State.EXHAUSTED:
			_start_dive()
			cooldown = COOLDOWN[phase - 1]
		State.PHASE_SHIFT:
			_start_dive()
			cooldown = COOLDOWN[phase - 1] * 0.5
	return 0


func _start_dive() -> void:
	state = State.CHASE
	dive = DIVE_SECONDS
	remaining = 0.0


## Starts a wind-up now and locks its shape. Public for tests and scripted
## moments; the normal flow calls it from CHASE.
func begin_attack(pattern: int, swarm_position: Vector3, pressure: float) -> void:
	var index := phase - 1
	current_pattern = pattern
	state = State.WINDUP
	dive = 0.0
	zones.clear()
	var target := Vector3(swarm_position.x, 0.0, swarm_position.z)
	var here := Vector3(position.x, 0.0, position.z)
	var base := 0.0
	match pattern:
		Pattern.BREACH:
			remaining = BREACH_WINDUP[index]
			base = BREACH_DAMAGE
			var lead := _swarm_velocity * BREACH_LEAD
			if lead.length() > BREACH_LEAD_MAX:
				lead = lead.normalized() * BREACH_LEAD_MAX
			attack_center = target + Vector3(lead.x, 0.0, lead.z)
			zones.append({"shape": SHAPE_BREACH, "center": attack_center, "radius": float(BREACH_RADIUS[index])})
		Pattern.SWEEP:
			remaining = SWEEP_WINDUP[index]
			base = SWEEP_DAMAGE
			var side := here - target
			side = side.normalized() if side.length_squared() > 0.01 else Vector3(1, 0, 0)
			var origin := target + side * SWEEP_DISTANCE
			var field := _arena()
			if field != null and field.has_method("safe_spawn"):
				origin = field.safe_spawn(origin, 2.0)
				origin.y = 0.0
			var direction := target - origin
			direction = direction.normalized() if direction.length_squared() > 0.01 else -side
			# The worm surfaces at the cone origin (the trail jumps there underground).
			position = Vector3(origin.x, position.y, origin.z)
			attack_center = origin
			rotation.y = atan2(direction.x, direction.z)
			zones.append({"shape": SHAPE_SWEEP, "center": origin, "direction": direction, "reach": float(SWEEP_REACH[index]), "half_angle": float(SWEEP_HALF_ANGLE[index])})
			_burst(origin, 0.6)
	_windup_total = remaining
	attack_power = int(ceil(minf(1000000.0, base * pressure)))
	_build_telegraphs()


func _resolve(swarm_position: Vector3) -> int:
	state = State.STRIKE
	resolved_power = attack_power
	if current_pattern == Pattern.BREACH:
		remaining = BREACH_STRIKE
		position = Vector3(attack_center.x, position.y, attack_center.z)
		# It will keel over sideways (never onto the swarm): perpendicular to the swarm,
		# on the side facing the camera (+Z), so the maw stays in view.
		var toward := swarm_position - position
		toward.y = 0.0
		var base_yaw := atan2(toward.x, toward.z) if toward.length_squared() > 0.01 else rotation.y
		_fall_yaw = base_yaw + PI * 0.5
		if cos(_fall_yaw) < 0.0:
			_fall_yaw -= PI
		rotation.y = _fall_yaw
		_burst(attack_center, 1.0)
		if phase == 2:
			_release_grubs(attack_center, GRUBS_PER_BREACH)
	else:
		remaining = SWEEP_STRIKE
	_clear_telegraphs()
	_strike_fx()
	return attack_power if contains(swarm_position) else 0


func _enter_phase_two() -> void:
	phase = 2
	chained = false
	dive = 0.0
	state = State.PHASE_SHIFT
	remaining = PHASE_SHIFT_SECONDS
	cycle_index = 0
	_clear_telegraphs()
	_burst(Vector3(position.x, 0.0, position.z), 1.2)
	FX.ring(_fx_parent(), global_position, Color(1.0, 0.49, 0.76, 0.9), 1.0, 9.5, 0.8)
	_shake(0.6)
	_release_grubs(Vector3(position.x, 0.0, position.z), GRUBS_ON_RAGE)
	phase_changed.emit(phase)


func _die() -> void:
	health = minf(health, 0.0)
	state = State.DEAD
	remaining = 0.0
	chained = false
	dive = 0.0
	migration_ready = true
	migration_point = Vector3(position.x, 0.0, position.z)
	_clear_telegraphs()
	FX.ring(_fx_parent(), global_position, Color(1.0, 0.86, 0.5, 0.95), 1.0, 11.0, 1.2)
	FX.ring(_fx_parent(), global_position, Color(0.85, 0.75, 0.58, 0.8), 0.6, 7.0, 1.6)
	_shake(0.7)
	defeated.emit(migration_point)


func _release_grubs(center: Vector3, count: int) -> void:
	if count <= 0:
		return
	var flat := Vector3(center.x, 0.0, center.z)
	pending_grubs.append({"center": flat, "count": count})
	grubs_released.emit(flat, count)


## Grub releases since the last call (HuntWorld spawns them via scripts/sandgrub.gd).
func take_grubs() -> Array[Dictionary]:
	var result := pending_grubs.duplicate()
	pending_grubs.clear()
	return result


# Buried: circles the swarm at ORBIT_RADIUS (the trail stays in view), closing in
# from afar. Ignores walls (it is under them) but stays inside the map.
func _burrow(swarm_position: Vector3, delta: float) -> void:
	var from_swarm := position - swarm_position
	from_swarm.y = 0.0
	var distance := from_swarm.length()
	var goal := swarm_position
	if distance < ORBIT_RADIUS * 1.6:
		var around := from_swarm.normalized() if distance > 0.1 else Vector3(1, 0, 0)
		goal = swarm_position + around.rotated(Vector3.UP, 0.7) * ORBIT_RADIUS
	_approach(goal, delta, float(BURROW_SPEED[phase - 1]))


func _approach(goal: Vector3, delta: float, speed: float = -1.0) -> void:
	var offset := goal - position
	offset.y = 0.0
	if offset.length_squared() < 0.0001:
		return
	if speed < 0.0:
		# Breach wind-up: reach the ring centre by 80 % of the wind-up.
		speed = maxf(float(BURROW_SPEED[phase - 1]), offset.length() / maxf(remaining - _windup_total * 0.2, 0.05))
	var move := offset.limit_length(speed * delta)
	var next := position + move
	var field := _arena()
	if field != null and field.has_method("fold_inside"):
		var inside: Vector3 = field.fold_inside(Vector3(next.x, 0.0, next.z), 2.0)
		next = Vector3(inside.x, position.y, inside.z)
	position = next
	rotation.y = lerp_angle(rotation.y, atan2(move.x, move.z), minf(1.0, delta * 6.0))


func _arena() -> Node3D:
	if arena == null and get_parent() != null and get_parent().get_parent() != null:
		arena = get_parent().get_parent().get_node_or_null("Arena") as Node3D
	return arena


# ------------------------------------------------------------------ areas

func contains(point: Vector3) -> bool:
	for zone in zones:
		if zone_contains(zone, point):
			return true
	return false


static func zone_contains(zone: Dictionary, point: Vector3) -> bool:
	var center: Vector3 = zone.center
	var flat := Vector2(point.x - center.x, point.z - center.z)
	if int(zone.shape) == SHAPE_SWEEP:
		var distance := flat.length()
		if distance < SWEEP_INNER or distance > float(zone.reach):
			return false
		var direction: Vector3 = zone.direction
		var along := flat.dot(Vector2(direction.x, direction.z))
		return along > 0.0 and acos(clampf(along / distance, -1.0, 1.0)) <= float(zone.half_angle)
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


## Flat distance from `point` to the surfaced body (0 = touching or inside):
## a capsule from the hole towards the head (lying / sweeping) or a column
## around the hole (vertical). A buried worm has no body (INF).
func body_distance(point: Vector3) -> float:
	if is_buried() and dive <= 0.0:
		return INF
	var flat := Vector2(point.x - position.x, point.z - position.z)
	var reach := 0.0
	match state:
		State.EXHAUSTED, State.DEAD:
			reach = HEAD_REACH
		State.WINDUP, State.STRIKE:
			reach = SWEEP_REACH_BODY if current_pattern == Pattern.SWEEP else 0.0
	var forward := Vector2(sin(rotation.y), cos(rotation.y))
	var along := clampf(flat.dot(forward), 0.0, reach)
	return maxf(0.0, (flat - forward * along).length() - body_radius)


func contains_body(point: Vector3) -> bool:
	return body_distance(point) <= 0.0


func windup_progress() -> float:
	return clampf(1.0 - remaining / maxf(_windup_total, 0.001), 0.0, 1.0) if state == State.WINDUP else 0.0


func hud_message() -> String:
	match state:
		State.ARRIVING:
			return "DER SANDWURM ERWACHT"
		State.WINDUP:
			match current_pattern:
				Pattern.BREACH:
					return "DURCHBRUCH · RAUS AUS DEM RING!"
				Pattern.SWEEP:
					return "SCHWANZFEGER · RAUS AUS DEM BOGEN!"
		State.EXHAUSTED:
			return "SANDWURM ERSCHÖPFT · JETZT ANGREIFEN!"
		State.PHASE_SHIFT:
			return "DER SANDWURM TOBT!"
		State.DEAD:
			return "DER SANDWURM IST BEZWUNGEN"
	return ""


static func pattern_name(pattern: int) -> String:
	return String(PATTERN_NAMES.get(pattern, ""))


# --------------------------------------------------------------- telegraphs

func restyle(colorblind_on: bool) -> void:
	colorblind = colorblind_on
	for part in telegraphs:
		var kind := "boss_cone" if String(part.get_meta("kind", "boss")) == "boss_cone" else "boss"
		TG.restyle(part.material_override as ShaderMaterial, kind, colorblind_on)


func _build_telegraphs() -> void:
	_clear_telegraphs()
	warning.global_transform = Transform3D.IDENTITY
	var height := 0.12
	for zone in zones:
		var part: MeshInstance3D
		var center: Vector3 = zone.center
		if int(zone.shape) == SHAPE_SWEEP:
			part = TG.build_boss_cone(float(zone.reach), float(zone.half_angle), 1 if colorblind else 0)
			part.set_meta("kind", "boss_cone")
			var direction: Vector3 = zone.direction
			part.rotation.y = atan2(direction.x, direction.z)
		else:
			part = TG.build("boss", float(zone.radius), 1 if colorblind else 0)
			part.set_meta("kind", "boss")
		part.name = "Sandwurm telegraph %s" % pattern_name(current_pattern)
		part.position = Vector3(center.x, height, center.z)
		TG.set_armed(part, true)
		TG.set_progress(part, 0.0)
		height += 0.004
		warning.add_child(part)
		telegraphs.append(part)
	warning.visible = true


func _clear_telegraphs() -> void:
	for part in telegraphs:
		if is_instance_valid(part):
			if part.get_parent() != null:
				part.get_parent().remove_child(part)
			part.queue_free()
	telegraphs.clear()
	if warning != null:
		warning.visible = false


func _strike_fx() -> void:
	var parent := _fx_parent()
	for zone in zones:
		var center: Vector3 = zone.center
		match int(zone.shape):
			SHAPE_BREACH:
				var radius := float(zone.radius)
				FX.ring(parent, center, Color(0.98, 0.92, 0.78, 0.95), 1.0, radius * 1.05, 0.45)
				FX.ring(parent, center, Color(0.85, 0.66, 0.4, 0.85), radius * 0.8, radius * 1.7, 0.7)
				_shake(0.75)
			SHAPE_SWEEP:
				var direction: Vector3 = zone.direction
				var reach := float(zone.reach)
				for index in 5:
					var angle := lerpf(-float(zone.half_angle), float(zone.half_angle), float(index) / 4.0)
					var spot: Vector3 = center + direction.rotated(Vector3.UP, angle) * reach * 0.65
					FX.ring(parent, spot, Color(0.95, 0.86, 0.66, 0.85), 0.4, 2.6, 0.4 + 0.05 * index)
				_shake(0.35)


# ------------------------------------------------------------------ look

## Body from Sandwurm_game.glb (head +Z, mound at the tail). Pivot = the hole:
## body.rotation.x tips the worm from its native lying pose (0) to vertical
## (-PI/2, maw up); body.position.y sinks it into the sand.
func _build_model() -> void:
	body = Node3D.new()
	body.name = "Sandwurm body"
	add_child(body)
	model = MODEL.instantiate()
	model.name = "Sandwurm model"
	model.scale = Vector3.ONE * MODEL_SCALE
	model.position = Vector3(0.0, 0.0, -HOLE_Z * MODEL_SCALE)
	body.add_child(model)
	skin = ShaderMaterial.new()
	skin.shader = _skin_shader()
	skin.set_shader_parameter("brightness", 1.08)
	skin.set_shader_parameter("saturation", 0.95)
	skin.set_shader_parameter("shape_light", 0.55)
	skin.set_shader_parameter("rim_color", _rim)
	skin.set_shader_parameter("rim_strength", 0.75)
	skin.set_shader_parameter("rim_power", 2.6)
	skin.set_shader_parameter("body_tint", SKIN_TINT)
	skin.set_shader_parameter("flash", 0.0)
	# Raw frame (Z-up storage like every Hunyuan glb): up -Z, forward +Y. No legs,
	# no jaw hinge, no tail pendulum: the segment wave below does the motion.
	skin.set_shader_parameter("up_axis", Vector3(0.0, 0.0, -1.0))
	skin.set_shader_parameter("forward_axis", Vector3(0.0, 1.0, 0.0))
	skin.set_shader_parameter("ground_offset", 0.0)
	for key in ["foot_a_front", "foot_a_back", "foot_b_front", "foot_b_back"]:
		skin.set_shader_parameter(key, Vector2(9.0, 9.0))
	skin.set_shader_parameter("foot_radius", 0.01)
	skin.set_shader_parameter("leg_height", 0.001)
	skin.set_shader_parameter("walk_amount", 0.0)
	skin.set_shader_parameter("jaw_angle", 0.0)
	skin.set_shader_parameter("tail_swing", 0.0)
	skin.set_shader_parameter("stomp_height", 0.0)
	skin.set_shader_parameter("maw_center", MAW)
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = skin
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# creature_anim.gdshader plus two worm deformations in raw mesh space:
#  - segment wave: the armour rings slide sideways and heave in a travelling sine
#    (stronger towards the tail, driven by `wave_time` so pause freezes it);
#  - maw flare: vertices in front of the maw ring are pushed away from the maw
#    centre, so the round tooth maw gapes wider (`maw_open` 0..1).
static var _worm_shader: Shader


static func _skin_shader() -> Shader:
	if _worm_shader != null:
		return _worm_shader
	var code: String = CREATURE_ANIM_SHADER.code
	var uniforms := "uniform float wave_amount = 0.0;
uniform float wave_time = 0.0;
uniform float maw_open = 0.0;
uniform vec2 maw_center = vec2(0.43, 0.3);

void vertex()"
	var anchor := "VERTEX = fwd * f + up * (u + ground_offset) + lat * l;"
	var wave := "float seg = smoothstep(maw_center.x + 0.02, -0.66, f);
	l += wave_amount * (0.35 + 0.65 * seg) * sin(f * 11.0 - wave_time * 5.0) * 0.035;
	u += wave_amount * seg * sin(f * 8.0 - wave_time * 4.0 + 1.3) * 0.012;
	float maw_w = smoothstep(maw_center.x - 0.2, maw_center.x - 0.02, f);
	vec2 around = vec2(l, u - maw_center.y);
	l += around.x * maw_w * maw_open * 0.3;
	u += around.y * maw_w * maw_open * 0.3;
	f += maw_w * maw_open * 0.03;
	" + anchor
	if code.count("void vertex()") != 1 or code.count(anchor) != 1:
		push_warning("Sandwurm: creature_anim shader changed, segment waves disabled")
		_worm_shader = CREATURE_ANIM_SHADER
		return _worm_shader
	var shader := Shader.new()
	shader.code = code.replace("void vertex()", uniforms).replace(anchor, wave)
	_worm_shader = shader
	return _worm_shader


func _build_sand_fx() -> void:
	var mound := SphereMesh.new()
	mound.radius = 0.5
	mound.height = 1.0
	mound.radial_segments = 10
	mound.rings = 5
	# Unshaded: lit spheres turned black on their far side; the sand tones carry
	# the depth instead (darker furrow, pale crest on the head mound).
	trail_batch = FX_BATCH.create(mound, TRAIL_MAX + 2, false, true, "Sandwurm trail")
	var puff := SphereMesh.new()
	puff.radius = 0.5
	puff.height = 1.0
	puff.radial_segments = 8
	puff.rings = 4
	dust_batch = FX_BATCH.create(puff, DUST_MAX, true, true, "Sandwurm dust")
	var rock := BoxMesh.new()
	rock.size = Vector3.ONE
	chunk_batch = FX_BATCH.create(rock, 24, false, false, "Sandwurm chunks")
	for batch in [trail_batch, dust_batch, chunk_batch]:
		add_child(batch)
		batch.top_level = true
		batch.global_transform = Transform3D.IDENTITY


## Sand burst where the worm breaks through: flying rock chunks and a dust cloud.
func _burst(center: Vector3, strength: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(roundi(center.x * 10.0), roundi(center.z * 10.0), cycle_index))
	for index in int(10.0 * strength) + 4:
		if _chunks.size() >= 24:
			_chunks.remove_at(0)
		var angle := rng.randf() * TAU
		var speed := rng.randf_range(3.0, 7.0) * strength
		_chunks.append({"at": center + Vector3(cos(angle), 0.4, sin(angle)) * 1.5, "vel": Vector3(cos(angle) * speed, rng.randf_range(6.0, 11.0) * strength, sin(angle) * speed), "age": 0.0, "life": rng.randf_range(0.8, 1.2), "size": rng.randf_range(0.35, 0.8), "spin": rng.randf() * TAU})
	for index in int(14.0 * strength):
		var angle := rng.randf() * TAU
		_add_dust(center + Vector3(cos(angle), 0.2, sin(angle)) * rng.randf_range(0.5, 3.5), Vector3(cos(angle), 0.6, sin(angle)) * rng.randf_range(1.5, 4.0), rng.randf_range(0.8, 1.3), 1.6)


func _add_dust(at: Vector3, velocity: Vector3, life: float, size: float) -> void:
	if _dust.size() >= DUST_MAX:
		_dust.remove_at(0)
	_dust.append({"at": at, "vel": velocity, "age": 0.0, "life": life, "size": size})


func _step_sand_fx(delta: float) -> void:
	var here := Vector3(position.x, 0.0, position.z)
	var digging := _rise < 0.35 and state != State.DEAD
	if digging and delta > 0.0:
		if not _trail_last.is_finite() or here.distance_to(_trail_last) >= TRAIL_STEP:
			if _trail.size() >= TRAIL_MAX:
				_trail.remove_at(0)
			_trail.append({"at": here, "age": 0.0, "yaw": rotation.y})
			_trail_last = here
		_dust_clock -= delta
		while _dust_clock <= 0.0:
			_dust_clock += DUST_EVERY
			var side := Vector3(cos(_time * 7.3), 0.0, sin(_time * 5.1)) * 0.9
			_add_dust(here + side + Vector3(0, 0.3, 0), side * 1.4 + Vector3(0, 1.6, 0), 0.9, 1.1)
	for index in range(_trail.size() - 1, -1, -1):
		_trail[index].age = float(_trail[index].age) + delta
		if float(_trail[index].age) >= TRAIL_SECONDS:
			_trail.remove_at(index)
	for index in range(_dust.size() - 1, -1, -1):
		var puff: Dictionary = _dust[index]
		puff.age = float(puff.age) + delta
		puff.at = Vector3(puff.at) + Vector3(puff.vel) * delta
		puff.vel = Vector3(puff.vel) * maxf(0.0, 1.0 - delta * 2.2)
		if float(puff.age) >= float(puff.life):
			_dust.remove_at(index)
	for index in range(_chunks.size() - 1, -1, -1):
		var chunk: Dictionary = _chunks[index]
		chunk.age = float(chunk.age) + delta
		chunk.vel = Vector3(chunk.vel) + Vector3(0, -24.0, 0) * delta
		chunk.at = Vector3(chunk.at) + Vector3(chunk.vel) * delta
		if float(chunk.age) >= float(chunk.life) or Vector3(chunk.at).y < -0.5:
			_chunks.remove_at(index)
	# Draw: furrow mounds (older = flatter, darker), the head mound, dust, chunks.
	trail_batch.begin()
	for mark in _trail:
		var life := 1.0 - float(mark.age) / TRAIL_SECONDS
		var width := 2.4 * (0.55 + 0.45 * life)
		var basis := Basis(Vector3.UP, float(mark.yaw)).scaled(Vector3(width, 0.22 * life + 0.02, width * 1.6))
		trail_batch.add(Transform3D(basis, Vector3(mark.at) + Vector3(0, -0.02, 0)), SAND_FURROW.lerp(SAND_MOUND, 0.35 + life * 0.65))
	if digging:
		var bump := 1.0 + 0.15 * sin(_time * 9.0)
		var head := Basis(Vector3.UP, rotation.y).scaled(Vector3(3.4, 0.7 * bump, 4.6))
		trail_batch.add(Transform3D(head, here + Vector3(0, -0.1, 0)), SAND_FURROW)
		var crest := Basis(Vector3.UP, rotation.y).scaled(Vector3(2.3, 0.9 * bump, 3.1))
		trail_batch.add(Transform3D(crest, here + Vector3(0, 0.0, 0.25)), SAND_CREST)
	trail_batch.finish()
	dust_batch.begin()
	for puff in _dust:
		var t := float(puff.age) / float(puff.life)
		var size := float(puff.size) * (0.6 + 1.2 * t)
		dust_batch.add(Transform3D(Basis.from_scale(Vector3(size, size * 0.7, size)), puff.at), Color(SAND_DUST, SAND_DUST.a * (1.0 - t) * (1.0 - t)))
	dust_batch.finish()
	chunk_batch.begin()
	for chunk in _chunks:
		var size := float(chunk.size)
		var spin := float(chunk.spin) + float(chunk.age) * 7.0
		chunk_batch.add(Transform3D(Basis(Vector3(0.4, 1.0, 0.2).normalized(), spin).scaled(Vector3(size, size * 0.7, size * 0.85)), chunk.at), ROCK_CHUNK)
	chunk_batch.finish()


func refresh_pose() -> void:
	_pose(0.0, true)


func _pose(delta: float, snap: bool = false) -> void:
	_time += delta
	hit_flash = maxf(0.0, hit_flash - delta)
	var rise := 0.0
	var pitch := 0.0
	var swing := 0.0
	var slump := 0.0
	var maw := 0.0
	var wave := 0.35
	var tremble := 0.0
	var rim_target := RIM_RAGE if phase == 2 else RIM_CHASE
	var rim_strength := 0.85
	var progress := windup_progress()
	match state:
		State.ARRIVING:
			var t := 1.0 - remaining / ARRIVE_SECONDS
			emerge = t
			# Rumble (buried) - bursts up vertically - roars - sinks at the end.
			rise = smoothstep(0.3, 0.55, t) * (1.0 - smoothstep(0.85, 1.0, t))
			pitch = 1.0
			maw = smoothstep(0.45, 0.7, t)
			wave = 1.0
			tremble = 0.1 * (1.0 - smoothstep(0.3, 0.5, t))
		State.CHASE:
			# Dive: sinks from whatever pose it had (native lying pose).
			rise = 0.0
			pitch = _pitch if dive > 0.0 else 0.0
			wave = 0.6
		State.WINDUP:
			rim_target = RIM_WARNING
			if current_pattern == Pattern.BREACH:
				rise = 0.0
				pitch = 1.0
			else:
				# Half surfaced, coils back to one cone edge, maw opening.
				var coil := smoothstep(0.0, 0.5, progress)
				rise = 0.6 * smoothstep(0.0, 0.25, progress)
				pitch = 0.6
				swing = -float(zones[0].half_angle if not zones.is_empty() else 0.6) * coil
				maw = 0.5 * coil
				wave = 0.8 + 0.6 * progress
				tremble = 0.08 * smoothstep(0.7, 1.0, progress)
			for part in telegraphs:
				TG.set_progress(part, progress)
		State.STRIKE:
			if current_pattern == Pattern.BREACH:
				var t := 1.0 - remaining / BREACH_STRIKE
				# Bursts up vertically, maw wide, then starts to keel over.
				rise = minf(1.0, t * 4.0)
				pitch = 1.0 - smoothstep(0.55, 1.0, t) * 0.5
				maw = 1.0
				wave = 1.2
			else:
				var t := 1.0 - remaining / SWEEP_STRIKE
				var half := float(zones[0].half_angle if not zones.is_empty() else 0.6)
				rise = 0.6
				pitch = 0.45
				swing = lerpf(-half, half * 1.15, smoothstep(0.0, 0.6, t))
				maw = 0.7
				wave = 1.4
		State.EXHAUSTED:
			# Slumped over beside the hole, maw gaping, slow heavy breath.
			var breath := sin(_time * 1.8)
			rise = 0.82
			pitch = 0.0
			slump = 0.14 + 0.03 * breath
			maw = 0.55 + 0.25 * breath
			wave = 0.25
			rim_target = RIM_EXHAUSTED
			rim_strength = 0.75 + 0.4 * (0.5 + 0.5 * sin(_time * 5.0))
		State.PHASE_SHIFT:
			var t := 1.0 - remaining / PHASE_SHIFT_SECONDS
			rise = smoothstep(0.0, 0.2, t) * (1.0 - smoothstep(0.85, 1.0, t))
			pitch = 1.0
			maw = 1.0
			wave = 2.2
			tremble = 0.12
			rim_target = RIM_RAGE
			rim_strength = 1.2
		State.DEAD:
			_sink = minf(1.0, _sink + delta / 2.4)
			rise = 0.8 - 0.25 * _sink
			pitch = 0.0
			slump = 0.2 + 0.12 * _sink
			maw = 0.7
			wave = 0.0
	var flash := 0.0
	if hit_flash > 0.0:
		flash = 0.16 + 0.1 * (0.5 + 0.5 * sin(_time * 55.0))
		tremble += 0.04
	var weight := 1.0 if snap else minf(1.0, delta * 9.0)
	# Rising and bursting are fast, sinking a bit slower.
	var rise_weight := 1.0 if snap else minf(1.0, delta * (18.0 if rise > _rise else 5.0))
	_rise = lerpf(_rise, rise, rise_weight)
	_pitch = lerpf(_pitch, pitch, weight)
	_swing = lerpf(_swing, swing, 1.0 if snap else minf(1.0, delta * 14.0))
	_slump = lerpf(_slump, slump, weight)
	_maw = lerpf(_maw, maw, weight)
	_wave = lerpf(_wave, wave, weight)
	_rim = rim_target if snap else _rim.lerp(rim_target, minf(1.0, delta * 5.0))
	var grow_target := 1.08 if phase == 2 else 1.0
	_grow = grow_target if snap else lerpf(_grow, grow_target, minf(1.0, delta * 2.0))
	# Depth that hides the whole worm: the vertical worm is taller than the lying one.
	var depth := lerpf(6.5, 9.5, _pitch) * _grow
	var jitter := Vector3(sin(_time * 43.0), 0.0, sin(_time * 37.0 + 1.3)) * tremble
	body.position = Vector3(0.0, -depth * (1.0 - _rise), 0.0) + jitter
	body.rotation = Vector3(-PI * 0.5 * _pitch + _slump, _swing, 0.0)
	body.scale = Vector3.ONE * _grow
	model.visible = _rise > 0.02
	var shadow_size := clampf(_rise * 1.3, 0.0, 1.0) * _grow
	shadow.visible = shadow_size > 0.02
	shadow.scale = Vector3(shadow_size, 1.0, shadow_size)
	skin.set_shader_parameter("rim_color", _rim)
	skin.set_shader_parameter("rim_strength", rim_strength)
	skin.set_shader_parameter("flash", flash)
	skin.set_shader_parameter("body_tint", SKIN_TINT_RAGE if phase == 2 else SKIN_TINT)
	skin.set_shader_parameter("wave_amount", _wave)
	skin.set_shader_parameter("wave_time", _time)
	skin.set_shader_parameter("maw_open", _maw)
	if trail_batch != null:
		_step_sand_fx(delta)


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
	gradient.set_color(0, Color(0.12, 0.08, 0.04, 0.55))
	gradient.set_color(1, Color(0.12, 0.08, 0.04, 0.0))
	gradient.add_point(0.55, Color(0.12, 0.08, 0.04, 0.38))
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
	plane.size = Vector2(8.0, 8.0)
	var part := MeshInstance3D.new()
	part.name = "Sandwurm shadow"
	part.mesh = plane
	part.material_override = material
	part.position = Vector3(0, 0.06, 0)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
	return part
