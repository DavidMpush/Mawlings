extends SceneTree

# Aschenkröte (scripts/apex_toad.gd), second apex for the Glutsumpf. Building
# block tests like tests/apex.gd: telegraph before damage, every pattern
# dodgeable in both phases, partial hits, glow puddles, phase change,
# exhaustion, defeated exactly once, pause freeze, colour-blind palette, body
# rim helpers, State enum compatible with apex_boss, and a bot fight measuring
# the fight length at an average swarm DPS.

const TOAD = preload("res://scripts/apex_toad.gd")
const APEX = preload("res://scripts/apex_boss.gd")
const SWARM_SPEED := 7.0
# Share of the wind-up lost to reaction time before moving (same as tests/apex.gd).
const REACTION := 0.45
const DT := 1.0 / 60.0
var failures: Array[String] = []
var defeats := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_flow()
	_check_leap()
	_check_spit_and_puddles()
	_check_tongue()
	_check_dodgeable()
	_check_phase_two()
	_check_death_and_pause()
	_check_colorblind()
	_check_body()
	_check_look()
	var lengths := _check_fight_length()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS apex_toad: telegraph before damage, leap/spit/tongue/combo dodgeable (both phases), partial hits, puddles, phase 2 chain, exhaustion, defeated once, pause, colour-blind, body rim, Ash Toad model + whole-body animation, fight %.0f s @30 / %.0f s @40 / %.0f s @55 DPS" % lengths)
	quit(0)


func _spawn() -> Variant:
	var main := Node3D.new()
	main.name = "Main"
	root.add_child(main)
	var world := Node3D.new()
	world.name = "World"
	main.add_child(world)
	var toad: Variant = TOAD.new()
	world.add_child(toad)
	return toad


# Whole-body animation of the Ash Toad model: crouch squashes, take-off stretches,
# the veins flare before a spit and go dim while exhausted, feet stay on the ground.
func _check_look() -> void:
	var toad: Variant = _ready_toad()
	var rest_glow: float = toad.skin.get_shader_parameter("ember_glow")
	var rest_height: float = toad.body.scale.y
	toad.begin_attack(TOAD.Pattern.LEAP, toad.position + Vector3(-10, 0, 0), 1.0)
	while toad.windup_progress() < TOAD.LEAP_CROUCH * 0.95:
		toad.step(DT, Vector3(-10, 0, 0), 1.0)
	var crouch: float = toad.body.scale.y
	while toad.windup_progress() < TOAD.LEAP_CROUCH + 0.12:
		toad.step(DT, Vector3(-10, 0, 0), 1.0)
	var takeoff: float = toad.body.scale.y
	var air: float = toad.body.position.y
	_check(crouch < rest_height - 0.12 and takeoff > rest_height + 0.08 and air > 1.0, "Leap: crouch squash %.2f, take-off stretch %.2f, airborne %.1f m" % [crouch, takeoff, air])
	toad.state = TOAD.State.CHASE
	toad.position = Vector3.ZERO
	toad.begin_attack(TOAD.Pattern.SPIT, Vector3(-10, 0, 0), 1.0)
	while toad.windup_progress() < 0.8:
		toad.step(DT, Vector3(-10, 0, 0), 1.0)
	var spit_glow: float = toad.skin.get_shader_parameter("ember_glow")
	# Rearing up for the spit lifts the nose; the pivot compensation keeps the rump from
	# digging in (AABB of the tilted mesh, so a little below 0 is expected).
	var bounds: AABB = TOAD._bounds(toad.model, toad)
	_check(spit_glow > rest_glow + 0.15 and bounds.position.y > -0.9, "Spit: veins flare %.2f -> %.2f, lowest point %.2f m" % [rest_glow, spit_glow, bounds.position.y])
	toad.state = TOAD.State.EXHAUSTED
	toad.remaining = 99.0
	for i in 60:
		toad.step(DT, Vector3(-10, 0, 0), 1.0)
	var tired_glow: float = toad.skin.get_shader_parameter("ember_glow")
	_check(tired_glow < rest_glow - 0.3, "Exhausted: veins dim %.2f" % tired_glow)
	_free(toad)


func _free(toad: Variant) -> void:
	toad.get_parent().get_parent().free()


func _ready_toad() -> Variant:
	var toad: Variant = _spawn()
	toad.state = TOAD.State.CHASE
	toad.cooldown = 99.0
	toad.refresh_pose()
	return toad


# Steps through a wind-up; returns [first non-zero result or 0, elapsed at resolve].
func _run_windup(toad: Variant, swarm: Vector3, pressure: float = 1.0) -> Array:
	var elapsed := 0.0
	while toad.state == TOAD.State.WINDUP and elapsed < 10.0:
		var result: int = toad.step(DT, swarm, pressure)
		elapsed += DT
		if toad.resolved_power > 0:
			return [result, elapsed]
	return [0, elapsed]


func _check_flow() -> void:
	var toad: Variant = _spawn()
	# Standalone HEALTH (1500) is only for the fixed-DPS fight below; in a run HuntWorld
	# sets TUNING.APEX_TOAD_HEALTH (stage 10 part 3), which must stay well above the Moosschlund.
	# Orchestrator 28.09.2026: in a run the toad has 2000 LP vs the Moosschlund's 1700
	# (fights 25-35 s); the standalone HEALTH stays the fixed-DPS test value.
	_check(toad.state == TOAD.State.ARRIVING and preload("res://scripts/tuning.gd").APEX_TOAD_HEALTH > preload("res://scripts/tuning.gd").APEX_HEALTH, "Toad arrives with more health than the Moosschlund")
	# Own model (AshToad_game.glb) in its real colours, ember veins glow via the skin shader.
	var mesh_path: String = (toad.model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh.resource_path
	var bounds: AABB = TOAD._bounds(toad.model, toad.body)
	_check(TOAD.MODEL.resource_path.ends_with("AshToad_game.glb") and toad.skin.shader.code.contains("ember_glow"), "Ash Toad model with ember-vein glow (%s)" % mesh_path)
	_check(absf(bounds.position.y) < 0.3 and bounds.size.x > 10.0 and bounds.size.x < 14.0 and bounds.size.z > 10.0 and bounds.size.y < bounds.size.x * 0.6, "Squat footprint %.1f x %.1f m, %.1f m high, feet at %.2f" % [bounds.size.x, bounds.size.z, bounds.size.y, bounds.position.y])
	_check(Color(toad.skin.get_shader_parameter("body_tint")).a < 0.01, "No recolour in phase 1")
	_check(toad.corpse_kind == "apex_toad", "Corpse kind flag")
	# Same enum values as apex_boss, so HuntWorld's state checks work for both apexes.
	for key in ["ARRIVING", "CHASE", "WINDUP", "STRIKE", "EXHAUSTED", "PHASE_SHIFT", "DEAD"]:
		_check(TOAD.State[key] == APEX.State[key], "State %s matches apex_boss" % key)
	var before: float = toad.health
	toad.take_damage(50.0)
	_check(toad.health == before and not toad.can_be_hit(), "Immune while emerging")
	toad.step(TOAD.ARRIVE_SECONDS + 0.01, Vector3(20, 0, 0), 1.0)
	_check(toad.state == TOAD.State.CHASE and toad.hud_message() == "", "Arrival ends in chase")
	var start: Vector3 = toad.position
	toad.cooldown = 99.0
	toad.step(0.5, Vector3(30, 0, 0), 1.0)
	_check(toad.position.x > start.x, "Hops towards the swarm")
	var seen: Array[int] = []
	for attack in 3:
		toad.position = Vector3.ZERO
		toad.cooldown = 0.0
		toad.step(0.01, Vector3(8, 0, 0), 1.0)
		seen.append(toad.current_pattern)
		_check(toad.state == TOAD.State.WINDUP and toad.warning.visible and toad.telegraphs.size() > 0 and toad.hud_message() != "", "Attack %d shows telegraph + banner" % attack)
		_run_windup(toad, Vector3(0, 0, 40))
		for i in 600:
			if toad.state == TOAD.State.CHASE:
				break
			toad.step(DT, toad.position + Vector3(4, 0, 0), 1.0)
	_check(seen == [TOAD.Pattern.LEAP, TOAD.Pattern.SPIT, TOAD.Pattern.TONGUE], "Phase 1 cycle leap-spit-tongue")
	_free(toad)


func _check_leap() -> void:
	var toad: Variant = _ready_toad()
	var swarm := Vector3(9, 0, 0)
	toad.begin_attack(TOAD.Pattern.LEAP, swarm, 2.0)
	_check(toad.telegraphs.size() == 1 and toad.attack_center == swarm, "Leap marks one landing zone on the swarm")
	_check(toad.step(0.01, swarm, 2.0) == 0 and toad.resolved_power == 0 and toad.can_be_hit(), "No loss while crouching (still hittable)")
	toad.step(TOAD.LEAP_WINDUP[0] * TOAD.LEAP_CROUCH + 0.05, swarm, 2.0)
	_check(toad.is_airborne() and not toad.can_be_hit() and toad.position.x > 0.0, "Airborne: immune and flying towards the zone")
	var health: float = toad.health
	toad.take_damage(30.0)
	_check(toad.health == health, "No damage in the air")
	var hit := _run_windup(toad, swarm, 2.0)
	_check(hit[0] == int(ceil(TOAD.LEAP_DAMAGE * 2.0)), "Landing on the swarm costs LEAP_DAMAGE x pressure")
	_check(Vector2(toad.position.x, toad.position.z).distance_to(Vector2(swarm.x, swarm.z)) < 0.01, "Toad lands on the marked spot")
	_check(toad.step(0.1, swarm, 2.0) == 0, "Leap resolves only once")
	for i in 40:
		toad.step(DT, swarm + Vector3(6, 0, 0), 1.0)
	_check(toad.state == TOAD.State.EXHAUSTED and toad.hud_message().contains("ERSCHÖPFT"), "Leap leaves the toad exhausted (phase 1)")
	health = toad.health
	toad.take_damage(10.0)
	_check(is_equal_approx(health - toad.health, 10.0 * TOAD.EXHAUSTED_VULNERABILITY), "Exhausted toad takes bonus damage")
	toad.step(TOAD.EXHAUSTED_SECONDS[0] + 0.01, swarm, 1.0)
	_check(toad.state == TOAD.State.CHASE, "Exhaustion window ends")
	_free(toad)
	# Far swarm: the jump is capped, a swarm beyond the zone is safe.
	toad = _ready_toad()
	toad.begin_attack(TOAD.Pattern.LEAP, Vector3(30, 0, 0), 1.0)
	_check(is_equal_approx(toad.attack_center.x, TOAD.LEAP_MAX), "Leap distance capped at LEAP_MAX")
	hit = _run_windup(toad, Vector3(30, 0, 0))
	_check(hit[0] == 0 and toad.resolved_power > 0, "Swarm beyond the capped landing zone is safe")
	_free(toad)
	# Partial hit.
	toad = _ready_toad()
	toad.begin_attack(TOAD.Pattern.LEAP, swarm, 1.0)
	var points := PackedVector3Array([swarm, swarm + Vector3(0, 0, 2.0), swarm + Vector3(0, 0, 5.0), swarm + Vector3(-6.0, 0, 0)])
	_check(is_equal_approx(toad.hit_fraction(points), 0.5), "hit_fraction counts units in the landing zone")
	_free(toad)


func _check_spit_and_puddles() -> void:
	var toad: Variant = _ready_toad()
	var swarm := Vector3(8, 0, 0)
	toad.begin_attack(TOAD.Pattern.SPIT, swarm, 1.0)
	_check(toad.zones.size() == 3 and toad.telegraphs.size() == 3, "Phase 1 spit: three marked circles")
	_check(toad.contains(swarm) and not toad.contains(swarm + Vector3(3.2, 0, 0)), "Spit circle on the swarm, gap towards the toad side")
	_check(toad.step(0.01, swarm, 1.0) == 0 and toad.resolved_power == 0, "No loss during spit wind-up")
	var hit := _run_windup(toad, swarm)
	_check(hit[0] == int(ceil(TOAD.SPIT_DAMAGE)) and hit[1] >= TOAD.SPIT_WINDUP[0] - 0.02, "Spit hits after the full wind-up")
	_check(toad.puddles.spots.size() == 3 and toad.puddles.active(), "Each circle leaves a glow puddle")
	_check(toad.puddles.resolved_power == 0, "Puddles do not tick on the spit step itself")
	# Puddle ticks: announced (visible), first tick PUDDLE_TICK later, only inside.
	var ticks := 0
	var elapsed := 0.0
	var first_tick := -1.0
	while toad.puddles.active() and elapsed < 10.0:
		toad.step(DT, Vector3(0, 0, 40), 1.0)
		elapsed += DT
		if toad.puddles.resolved_power > 0:
			ticks += 1
			if first_tick < 0.0:
				first_tick = elapsed
				_check(toad.puddles.contains(swarm) and not toad.puddles.contains(swarm + Vector3(0, 0, 2.5)), "Puddle area = circle x PUDDLE_SHARE")
	_check(first_tick >= TOAD.PUDDLE_TICK - 0.05 and ticks == int(TOAD.PUDDLE_SECONDS[0] / TOAD.PUDDLE_TICK), "Puddles tick every %.1f s (%d ticks, first at %.2f s)" % [TOAD.PUDDLE_TICK, ticks, first_tick])
	_check(elapsed <= TOAD.PUDDLE_SECONDS[0] + 0.1 and toad.puddles.spots.is_empty(), "Puddles fade after PUDDLE_SECONDS")
	_free(toad)
	# Partial hit on the spit.
	toad = _ready_toad()
	toad.begin_attack(TOAD.Pattern.SPIT, swarm, 1.0)
	var points := PackedVector3Array([swarm, swarm + Vector3(3.0, 0, 0), swarm + Vector3(-3.0, 0, 0), swarm + Vector3(0, 0, 5.0)])
	_check(is_equal_approx(toad.hit_fraction(points), 0.5), "Spit partial hit")
	_free(toad)


func _check_tongue() -> void:
	var toad: Variant = _ready_toad()
	var swarm := Vector3(9, 0, 0)
	toad.begin_attack(TOAD.Pattern.TONGUE, swarm, 1.0)
	_check(toad.telegraphs.size() == 1 and toad.remaining == TOAD.TONGUE_WINDUP[0] and toad.remaining < TOAD.SPIT_WINDUP[0], "Tongue: one lane, shortest wind-up")
	_check(toad.contains(swarm) and toad.contains(Vector3(15, 0, 0)) and not toad.contains(swarm + Vector3(0, 0, 1.2)) and not toad.contains(Vector3(1.0, 0, 0)), "Lane is narrow and long, starts at the mouth")
	var hit := _run_windup(toad, swarm + Vector3(0, 0, 1.5))
	_check(hit[0] == 0 and toad.resolved_power == int(ceil(TOAD.TONGUE_DAMAGE)), "Side step dodges the tongue")
	_check(toad.tongue.visible or toad.state == TOAD.State.STRIKE, "Tongue shoots out on the strike")
	var points := PackedVector3Array([swarm, swarm + Vector3(0.5, 0, 0.3), swarm + Vector3(0, 0, 2.0), swarm + Vector3(0, 0, -2.0)])
	_check(is_equal_approx(toad.hit_fraction(points), 0.5), "Tongue partial hit")
	_free(toad)


# Every pattern in both phases leaves a safe spot (1 m clear) the swarm reaches
# in time after a reaction delay, from near/mid/far and several directions.
func _check_dodgeable() -> void:
	var patterns := {1: [TOAD.Pattern.LEAP, TOAD.Pattern.SPIT, TOAD.Pattern.TONGUE], 2: [TOAD.Pattern.LEAP, TOAD.Pattern.SPIT, TOAD.Pattern.TONGUE, TOAD.Pattern.COMBO]}
	for phase in [1, 2]:
		for pattern in patterns[phase]:
			for distance in [4.5, 7.0, 10.0, 14.0]:
				for angle in [0.0, 1.3, 2.9, 4.4]:
					var toad: Variant = _ready_toad()
					toad.phase = phase
					var swarm: Vector3 = Vector3(cos(angle), 0, sin(angle)) * distance
					toad.begin_attack(pattern, swarm, 1.0)
					var reach: float = toad.remaining * (1.0 - REACTION) * SWARM_SPEED
					var best := _nearest_safe(toad, swarm)
					_check(best <= reach, "%s phase %d from %.1f m dodgeable (%.1f m needed, %.1f m reachable)" % [TOAD.pattern_name(pattern), phase, distance, best, reach])
					_free(toad)


func _nearest_safe(toad: Variant, swarm: Vector3) -> float:
	var best := INF
	for x in range(-40, 41):
		for z in range(-40, 41):
			var point: Vector3 = swarm + Vector3(x * 0.25, 0, z * 0.25)
			var distance := point.distance_to(swarm)
			if distance < best and _safe_with_margin(toad, point, 1.0):
				best = distance
	return best


func _safe_with_margin(toad: Variant, point: Vector3, margin: float) -> bool:
	for offset in [Vector3.ZERO, Vector3(margin, 0, 0), Vector3(-margin, 0, 0), Vector3(0, 0, margin), Vector3(0, 0, -margin)]:
		if toad.contains(point + offset):
			return false
	return true


func _check_phase_two() -> void:
	var toad: Variant = _ready_toad()
	var swarm := Vector3(8, 0, 0)
	toad.begin_attack(TOAD.Pattern.TONGUE, swarm, 1.0)
	toad.step(0.3, swarm, 1.0)
	var changed := [0]
	toad.phase_changed.connect(func(value: int) -> void: changed[0] = value)
	toad.health = toad.max_health * 0.49
	var result: int = toad.step(0.01, swarm, 1.0)
	_check(toad.phase == 2 and toad.state == TOAD.State.PHASE_SHIFT and changed[0] == 2, "Phase 2 at 50 % health")
	_check(result == 0 and toad.resolved_power == 0 and toad.telegraphs.is_empty(), "Phase change cancels the pending attack without loss")
	var health: float = toad.health
	toad.take_damage(40.0)
	_check(toad.health == health and toad.hud_message().contains("KOCHT"), "Immune while boiling over")
	toad.step(TOAD.PHASE_SHIFT_SECONDS + 0.01, swarm, 1.0)
	_check(toad.state == TOAD.State.CHASE, "Roar ends in chase")
	toad.begin_attack(TOAD.Pattern.SPIT, swarm, 1.0)
	_check(toad.zones.size() == 5 and toad.remaining == TOAD.SPIT_WINDUP[1], "Phase 2 spit: five circles, shorter wind-up")
	toad.state = TOAD.State.CHASE
	toad.begin_attack(TOAD.Pattern.COMBO, swarm, 1.0)
	var lanes := 0
	for zone in toad.zones:
		if int(zone.shape) == TOAD.SHAPE_TONGUE:
			lanes += 1
	_check(lanes == 1 and toad.zones.size() == 4 and toad.telegraphs.size() == 4, "Combo = tongue lane + spit circles in one wind-up")
	_free(toad)
	# Phase 2 leap chain: leap -> spit volley -> exhausted.
	toad = _ready_toad()
	toad.phase = 2
	toad.begin_attack(TOAD.Pattern.LEAP, swarm, 1.0)
	_run_windup(toad, Vector3(0, 0, 30))
	var dodge := Vector3(0, 0, 30)
	for i in 60:
		toad.step(DT, dodge, 1.0)
		if toad.state == TOAD.State.WINDUP:
			break
	_check(toad.state == TOAD.State.WINDUP and toad.current_pattern == TOAD.Pattern.SPIT and toad.chained, "Phase 2 leap chains into a spit volley")
	_run_windup(toad, dodge)
	for i in 60:
		toad.step(DT, dodge, 1.0)
	_check(toad.state == TOAD.State.EXHAUSTED and not toad.chained, "Exhausted after the chain")
	_free(toad)
	# Phase change mid-air: lands on the announced spot, no loss.
	toad = _ready_toad()
	toad.begin_attack(TOAD.Pattern.LEAP, swarm, 1.0)
	toad.step(TOAD.LEAP_WINDUP[0] * 0.7, swarm, 1.0)
	toad.health = toad.max_health * 0.4
	result = toad.step(DT, swarm, 1.0)
	_check(result == 0 and toad.state == TOAD.State.PHASE_SHIFT and Vector2(toad.position.x, toad.position.z).distance_to(Vector2(swarm.x, swarm.z)) < 0.01, "Phase change in the air sets down without loss")
	_free(toad)


func _check_death_and_pause() -> void:
	var toad: Variant = _ready_toad()
	var swarm := Vector3(8, 0, 0)
	toad.begin_attack(TOAD.Pattern.SPIT, swarm, 1.0)
	_run_windup(toad, Vector3(0, 0, 40))
	toad.begin_attack(TOAD.Pattern.LEAP, swarm, 1.0)
	toad.step(0.8, swarm, 1.0)
	var snapshot := [toad.state, toad.remaining, toad.position, toad.health, toad.cooldown, toad.puddles.tick_clock, toad.puddles.spots.size(), toad.puddles.spots[0].remaining]
	var total := 0
	for i in 120:
		total += toad.step(0.0, swarm, 1.0)
	_check(not toad.is_processing() and not toad.is_physics_processing() and not toad.puddles.is_processing(), "Toad has no own clock (pause = no step)")
	_check(total == 0 and toad.puddles.resolved_power == 0 and [toad.state, toad.remaining, toad.position, toad.health, toad.cooldown, toad.puddles.tick_clock, toad.puddles.spots.size(), toad.puddles.spots[0].remaining] == snapshot, "Zero-delta steps freeze toad and puddles")
	toad.state = TOAD.State.CHASE
	toad._clear_telegraphs()
	toad.defeated.connect(func(_location: Vector3) -> void: defeats += 1)
	toad.position = Vector3(3, 0, 4)
	toad.take_damage(toad.health + 1.0)
	toad.take_damage(500.0)
	toad.step(1.0, toad.position, 1.0)
	toad.take_damage(500.0)
	_check(defeats == 1, "defeated emitted exactly once (%d)" % defeats)
	_check(toad.state == TOAD.State.DEAD and toad.migration_ready and toad.migration_point == Vector3(3, 0, 4), "Death flags + migration point")
	_check(toad.puddles.spots.is_empty() and toad.telegraphs.is_empty() and toad.step(1.0, toad.position, 1.0) == 0, "Dead toad clears puddles and never attacks")
	_check(toad.hud_message().contains("BEZWUNGEN"), "Victory banner")
	_free(toad)


func _check_colorblind() -> void:
	var looks := {}
	for shape in [TOAD.SHAPE_LEAP, TOAD.SHAPE_SPIT, TOAD.SHAPE_TONGUE, TOAD.SHAPE_PUDDLE]:
		var normal: ShaderMaterial = TOAD.telegraph_material(shape, false)
		var blind: ShaderMaterial = TOAD.telegraph_material(shape, true)
		_check(normal.get_shader_parameter("pattern") == shape and blind.get_shader_parameter("pattern") == shape, "Shape %d keeps its pattern in colour-blind mode" % shape)
		_check(blind.get_shader_parameter("fill_color") == TOAD.PALETTE_COLORBLIND[shape].fill and normal.get_shader_parameter("fill_color") == TOAD.PALETTE[shape].fill, "Shape %d palettes applied" % shape)
		# Stage 20: one boss style; neighbouring shapes differ by form (circle,
		# lane, filled area), not by colour.
		looks[shape] = "%s/%s" % [blind.shader.resource_path, blind.get_shader_parameter("shape")]
	_check(looks[TOAD.SHAPE_SPIT] != looks[TOAD.SHAPE_TONGUE] and looks[TOAD.SHAPE_LEAP] != looks[TOAD.SHAPE_PUDDLE], "Neighbouring shapes differ in form (%s)" % [looks])
	# Restyle swaps a live telegraph and the puddles.
	var toad: Variant = _ready_toad()
	toad.begin_attack(TOAD.Pattern.SPIT, Vector3(8, 0, 0), 1.0)
	_run_windup(toad, Vector3(0, 0, 40))
	toad.begin_attack(TOAD.Pattern.TONGUE, Vector3(8, 0, 0), 1.0)
	toad.restyle(true)
	var lane: ShaderMaterial = toad.telegraphs[0].material_override
	var puddle: ShaderMaterial = toad.puddles.spots[0].node.material_override
	_check(lane.get_shader_parameter("fill_color") == TOAD.PALETTE_COLORBLIND[TOAD.SHAPE_TONGUE].fill and puddle.get_shader_parameter("fill_color") == TOAD.PALETTE_COLORBLIND[TOAD.SHAPE_PUDDLE].fill, "restyle() swaps lane and puddle palettes")
	_free(toad)


func _check_body() -> void:
	var toad: Variant = _ready_toad()
	toad.position = Vector3(10, 0, 0)
	_check(toad.contains_body(Vector3(10 + TOAD.BODY_RADIUS - 0.1, 0, 0)) and not toad.contains_body(Vector3(10 + TOAD.BODY_RADIUS + 0.2, 0, 0)), "contains_body uses the body rim")
	_check(is_equal_approx(toad.body_distance(Vector3(10, 0, 6)), 6.0 - TOAD.BODY_RADIUS) and toad.body_distance(Vector3(10, 0, 1)) == 0.0, "body_distance measures to the rim")
	_check(toad.melee_range > toad.body_radius + 1.5, "Melee range reaches past the body")
	_free(toad)


# One bot step towards `goal` that never walks into a glow puddle (a player
# steers around the visible lava); stays put if every direction is blocked.
func _walk_around_puddles(toad: Variant, from: Vector3, goal: Vector3) -> Vector3:
	var next := from.move_toward(goal, SWARM_SPEED * DT)
	if toad.puddles.contains(from) or not toad.puddles.contains(next):
		return next
	var step := next - from
	for turn in [0.6, -0.6, 1.2, -1.2, 1.8, -1.8, 2.4, -2.4]:
		var candidate: Vector3 = from + step.rotated(Vector3.UP, turn)
		if not toad.puddles.contains(candidate):
			return candidate
	return from


# Bot fight: the swarm dodges every wind-up to the nearest safe spot after a
# reaction delay, otherwise hugs the body and bites with `dps` (x vulnerability)
# while its centre is within 2 m of the rim. Returns seconds until death.
func _fight(dps: float) -> float:
	var toad: Variant = _ready_toad()
	toad.cooldown = 1.0
	var swarm := Vector3(0, 0, 9)
	var goal := swarm
	var windup_seen := -1
	var react := 0.0
	var losses := 0
	var elapsed := 0.0
	var attacks := 0
	while toad.state != TOAD.State.DEAD and elapsed < 150.0:
		elapsed += DT
		if toad.state == TOAD.State.WINDUP:
			var id: int = toad.cycle_index * 10 + int(toad.current_pattern) + (5 if toad.chained else 0)
			if id != windup_seen:
				windup_seen = id
				attacks += 1
				react = toad.remaining * REACTION
				var best := INF
				for x in range(-24, 25):
					for z in range(-24, 25):
						var point: Vector3 = swarm + Vector3(x * 0.5, 0, z * 0.5)
						if point.distance_to(swarm) < best and _safe_with_margin(toad, point, 1.0) and not toad.puddles.contains(point) and toad.body_distance(point) > 0.5:
							best = point.distance_to(swarm)
							goal = point
			react -= DT
			if react <= 0.0:
				swarm = swarm.move_toward(goal, SWARM_SPEED * DT)
		else:
			var offset: Vector3 = swarm - toad.position
			offset.y = 0.0
			var direction: Vector3 = offset.normalized() if offset.length_squared() > 0.01 else Vector3(0, 0, 1)
			var spot: Vector3 = toad.position + direction * (toad.body_radius + 1.2)
			spot.y = 0.0
			if toad.puddles.contains(spot):
				spot = toad.position + direction.rotated(Vector3.UP, 1.2) * (toad.body_radius + 1.2)
			swarm = _walk_around_puddles(toad, swarm, spot)
		if toad.body_distance(swarm) <= 2.0:
			toad.take_damage(dps * DT)
		losses += toad.step(DT, swarm, 1.0)
		if toad.puddles.resolved_power > 0 and toad.puddles.contains(swarm):
			losses += toad.puddles.resolved_power
	_check(losses == 0, "Dodging bot (%.0f DPS) takes no loss (%d)" % [dps, losses])
	_check(attacks >= 6, "Bot fight sees the pattern cycle (%d attacks)" % attacks)
	_free(toad)
	return elapsed


func _check_fight_length() -> Array:
	var slow := _fight(30.0)
	var average := _fight(40.0)
	var strong := _fight(55.0)
	_check(average >= 35.0 and average <= 50.0, "Average build (40 DPS) fight lasts 35-50 s (%.1f s)" % average)
	_check(strong < average and average < slow and slow < 80.0, "Fight length scales with DPS (%.1f / %.1f / %.1f s)" % [slow, average, strong])
	return [slow, average, strong]


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
