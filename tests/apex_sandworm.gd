extends SceneTree

# Sandwurm (scripts/apex_sandworm.gd), apex of the desert "Dürrschlund" (stage 19,
# phase 1). Building-block tests like tests/apex_toad.gd: buried = immune, trail
# while digging, breach ring before damage and per-unit hits, tail sweep cone,
# exhaustion window, phase 2 (double breach, grubs), death -> corpse design,
# pause freeze, colour-blind restyle, State enum compatible with apex_boss, and a
# bot fight measuring the fight length at an average swarm DPS.

const WORM = preload("res://scripts/apex_sandworm.gd")
const APEX = preload("res://scripts/apex_boss.gd")
const CORPSES = preload("res://scripts/corpse_visuals.gd")
const TG = preload("res://scripts/telegraph_style.gd")
const SWARM_SPEED := 7.0
const REACTION := 0.45
const DT := 1.0 / 60.0
var failures: Array[String] = []
var defeats := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_flow()
	_check_burrow()
	_check_breach()
	_check_sweep()
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
	print("PASS apex_sandworm: buried immune + sand trail, breach ring before damage with per-unit hits, sweep cone, exhaustion x%.1f, phase 2 double breach + grubs, defeated once -> corpse 'apex_sandworm', pause, colour-blind, capsule body, Sandwurm model + segment waves, fight %.0f s @30 / %.0f s @40 / %.0f s @55 DPS" % [WORM.EXHAUSTED_VULNERABILITY, lengths[0], lengths[1], lengths[2]])
	quit(0)


func _spawn() -> Variant:
	var main := Node3D.new()
	main.name = "Main"
	root.add_child(main)
	var world := Node3D.new()
	world.name = "World"
	main.add_child(world)
	var worm: Variant = WORM.new()
	world.add_child(worm)
	return worm


func _free(worm: Variant) -> void:
	worm.get_parent().get_parent().free()


func _ready_worm() -> Variant:
	var worm: Variant = _spawn()
	worm.state = WORM.State.CHASE
	worm.cooldown = 99.0
	worm.refresh_pose()
	return worm


func _run_windup(worm: Variant, swarm: Vector3, pressure: float = 1.0) -> Array:
	var elapsed := 0.0
	while worm.state == WORM.State.WINDUP and elapsed < 10.0:
		var result: int = worm.step(DT, swarm, pressure)
		elapsed += DT
		if worm.resolved_power > 0:
			return [result, elapsed]
	return [0, elapsed]


func _check_flow() -> void:
	var worm: Variant = _spawn()
	_check(WORM.MODEL.resource_path.ends_with("Sandwurm_game.glb"), "Sandwurm model")
	# Standalone HEALTH is only the fixed-DPS reference of the bot fight below; in a
	# run HuntWorld will set TUNING.APEX_SANDWORM_HEALTH (stage 19 phase 2).
	_check(worm.state == WORM.State.ARRIVING and worm.max_health == WORM.HEALTH, "Worm arrives with full health")
	for key in ["ARRIVING", "CHASE", "WINDUP", "STRIKE", "EXHAUSTED", "PHASE_SHIFT", "DEAD"]:
		_check(WORM.State[key] == APEX.State[key], "State %s matches apex_boss" % key)
	_check(worm.corpse_kind == "apex_sandworm" and CORPSES.KIND_DESIGN.get("apex_sandworm", "") == "apex_sandworm", "Corpse kind flag + design")
	var before: float = worm.health
	worm.take_damage(50.0)
	_check(worm.health == before and not worm.can_be_hit(), "Immune while arriving")
	_check(worm.hud_message().contains("ERWACHT"), "Arrival banner")
	for i in int(WORM.ARRIVE_SECONDS / DT) + 2:
		worm.step(DT, Vector3(30, 0, 0), 1.0)
	_check(worm.state == WORM.State.CHASE and worm.is_buried() and worm.hud_message() == "", "Arrival ends buried (chase)")
	var seen: Array[int] = []
	for attack in 4:
		worm.state = WORM.State.CHASE
		worm.dive = 0.0
		worm.position = Vector3.ZERO
		worm.cooldown = 0.0
		worm.step(0.01, Vector3(8, 0, 0), 1.0)
		seen.append(worm.current_pattern)
		_check(worm.state == WORM.State.WINDUP and worm.warning.visible and worm.telegraphs.size() > 0 and worm.hud_message() != "", "Attack %d shows telegraph + banner" % attack)
		_run_windup(worm, Vector3(0, 0, 40))
		worm._clear_telegraphs()
	_check(seen == [WORM.Pattern.BREACH, WORM.Pattern.SWEEP, WORM.Pattern.BREACH, WORM.Pattern.SWEEP], "Phase 1 cycle breach-sweep")
	_free(worm)


# Buried: never hittable, moves under the sand towards / around the swarm and
# leaves a trail of sand mounds with dust.
func _check_burrow() -> void:
	var worm: Variant = _ready_worm()
	worm.dive = 0.0
	worm.position = Vector3(-30, 0, 0)
	var health: float = worm.health
	for i in 60:
		worm.step(DT, Vector3(0, 0, 0), 1.0)
		worm.take_damage(20.0)
	_check(worm.health == health and not worm.can_be_hit() and worm.vulnerability() == 0.0, "Buried worm takes no damage")
	_check(worm.position.x > -30.0 + WORM.BURROW_SPEED[0] * 0.9, "Burrows towards the swarm (%.1f)" % worm.position.x)
	_check(worm.trail_batch.multimesh.visible_instance_count >= 3 and worm.dust_batch.multimesh.visible_instance_count > 3, "Sand trail (%d mounds) and dust (%d puffs) while digging" % [worm.trail_batch.multimesh.visible_instance_count, worm.dust_batch.multimesh.visible_instance_count])
	_check(not worm.model.visible, "Worm model hidden under the sand")
	_check(worm.body_distance(Vector3(-28, 0, 0)) == INF, "No body to bite while buried")
	# Close to the swarm with the cooldown running: circles instead of standing on it.
	worm.position = Vector3(5, 0, 0)
	for i in 120:
		worm.step(DT, Vector3.ZERO, 1.0)
	var distance: float = Vector2(worm.position.x, worm.position.z).length()
	_check(distance > WORM.ORBIT_RADIUS * 0.7 and distance < WORM.ORBIT_RADIUS * 1.3, "Circles the swarm at the orbit radius (%.1f m)" % distance)
	_free(worm)


func _check_breach() -> void:
	var worm: Variant = _ready_worm()
	var swarm := Vector3(9, 0, 0)
	worm.position = Vector3(-4, 0, 0)
	worm.begin_attack(WORM.Pattern.BREACH, swarm, 2.0)
	_check(worm.telegraphs.size() == 1 and worm.attack_center == swarm and worm.zones[0].radius == WORM.BREACH_RADIUS[0], "Breach marks one ring on the (still) swarm")
	_check(worm.step(0.01, swarm, 2.0) == 0 and worm.resolved_power == 0 and not worm.can_be_hit() and worm.is_buried(), "No loss and immune during the breach wind-up (buried)")
	var hit := _run_windup(worm, swarm, 2.0)
	_check(hit[0] == int(ceil(WORM.BREACH_DAMAGE * 2.0)) and hit[1] >= WORM.BREACH_WINDUP[0] - 0.02, "Breach on the swarm costs BREACH_DAMAGE x pressure after the full wind-up")
	_check(Vector2(worm.position.x, worm.position.z).distance_to(Vector2(swarm.x, swarm.z)) < 0.01, "Worm bursts out in the ring centre")
	_check(worm.state == WORM.State.STRIKE and worm.can_be_hit() and not worm.is_buried(), "Surfaced after the breach: hittable")
	_check(worm.step(0.1, swarm, 2.0) == 0, "Breach resolves only once")
	# Per-unit hits: only animals inside the ring.
	var points := PackedVector3Array([swarm, swarm + Vector3(0, 0, 2.0), swarm + Vector3(0, 0, 5.0), swarm + Vector3(-6.0, 0, 0)])
	_check(is_equal_approx(worm.hit_fraction(points), 0.5), "hit_fraction counts units in the ring")
	for i in 60:
		worm.step(DT, swarm + Vector3(6, 0, 0), 1.0)
	_check(worm.state == WORM.State.EXHAUSTED and worm.hud_message().contains("ERSCHÖPFT"), "Breach leaves the worm exhausted (phase 1)")
	var health: float = worm.health
	worm.take_damage(10.0)
	_check(is_equal_approx(health - worm.health, 10.0 * WORM.EXHAUSTED_VULNERABILITY), "Exhausted worm takes bonus damage")
	worm.step(WORM.EXHAUSTED_SECONDS[0] + 0.01, swarm, 1.0)
	_check(worm.state == WORM.State.CHASE and worm.dive > 0.0 and not worm.can_be_hit(), "Exhaustion ends in a dive (immune)")
	_free(worm)
	# Moving swarm: the ring lies ahead of it (under / in front of the swarm).
	worm = _ready_worm()
	var moving := Vector3.ZERO
	for i in 30:
		moving += Vector3(SWARM_SPEED * DT, 0, 0)
		worm.step(DT, moving, 1.0)
	worm.begin_attack(WORM.Pattern.BREACH, moving, 1.0)
	var lead: float = worm.attack_center.x - moving.x
	_check(lead > 1.0 and lead <= WORM.BREACH_LEAD_MAX + 0.01 and worm.contains(moving), "Ring shifted %.1f m ahead of a moving swarm, still under it" % lead)
	_free(worm)


func _check_sweep() -> void:
	var worm: Variant = _ready_worm()
	var swarm := Vector3(0, 0, 10)
	worm.position = Vector3(0, 0, 0)
	worm.begin_attack(WORM.Pattern.SWEEP, swarm, 1.0)
	var origin: Vector3 = worm.attack_center
	_check(is_equal_approx(origin.distance_to(swarm), WORM.SWEEP_DISTANCE) and worm.telegraphs.size() == 1, "Sweep: surfaces %.1f m beside the swarm, one cone" % WORM.SWEEP_DISTANCE)
	_check(worm.can_be_hit() and not worm.is_buried() and worm.vulnerability() == 1.0, "Half surfaced during the sweep wind-up: hittable")
	_check(worm.contains(swarm) and worm.contains(swarm + Vector3(0, 0, 4.0)) and not worm.contains(swarm + Vector3(4.5, 0, 0)) and not worm.contains(origin - Vector3(0, 0, 2.0)), "Cone covers the swarm, not the side or behind the worm")
	_check(worm.contains(origin + (swarm - origin).normalized() * 0.5), "Cone starts at its drawn origin (stage 20: hit edge = drawn edge)")
	var hit := _run_windup(worm, swarm + Vector3(4.5, 0, 0))
	_check(hit[0] == 0 and worm.resolved_power == int(ceil(WORM.SWEEP_DAMAGE)), "Side step dodges the sweep")
	var points := PackedVector3Array([swarm, swarm + Vector3(0.5, 0, 0.3), swarm + Vector3(5.0, 0, 0), swarm + Vector3(-5.0, 0, 0)])
	_check(is_equal_approx(worm.hit_fraction(points), 0.5), "Sweep partial hit")
	for i in int(WORM.SWEEP_STRIKE / DT) + 3:
		worm.step(DT, swarm, 1.0)
	_check(worm.state == WORM.State.CHASE and worm.dive > 0.0, "Sweep ends in a dive, no exhaustion")
	_free(worm)
	worm = _ready_worm()
	worm.begin_attack(WORM.Pattern.SWEEP, swarm, 1.0)
	hit = _run_windup(worm, swarm)
	_check(hit[0] == int(ceil(WORM.SWEEP_DAMAGE)), "Sweep on the swarm costs SWEEP_DAMAGE")
	_free(worm)


func _check_dodgeable() -> void:
	for phase in [1, 2]:
		for pattern in [WORM.Pattern.BREACH, WORM.Pattern.SWEEP]:
			for distance in [3.0, 7.0, 12.0]:
				for angle in [0.0, 1.3, 2.9, 4.4]:
					var worm: Variant = _ready_worm()
					worm.phase = phase
					var swarm: Vector3 = Vector3(cos(angle), 0, sin(angle)) * distance
					worm.begin_attack(pattern, swarm, 1.0)
					var reach: float = worm.remaining * (1.0 - REACTION) * SWARM_SPEED
					var best := _nearest_safe(worm, swarm)
					_check(best <= reach, "%s phase %d from %.1f m dodgeable (%.1f m needed, %.1f m reachable)" % [WORM.pattern_name(pattern), phase, distance, best, reach])
					_free(worm)


func _nearest_safe(worm: Variant, swarm: Vector3) -> float:
	var best := INF
	for x in range(-40, 41):
		for z in range(-40, 41):
			var point: Vector3 = swarm + Vector3(x * 0.25, 0, z * 0.25)
			var distance := point.distance_to(swarm)
			if distance < best and _safe_with_margin(worm, point, 1.0):
				best = distance
	return best


func _safe_with_margin(worm: Variant, point: Vector3, margin: float) -> bool:
	for offset in [Vector3.ZERO, Vector3(margin, 0, 0), Vector3(-margin, 0, 0), Vector3(0, 0, margin), Vector3(0, 0, -margin)]:
		if worm.contains(point + offset):
			return false
	return true


func _check_phase_two() -> void:
	var worm: Variant = _ready_worm()
	var swarm := Vector3(8, 0, 0)
	worm.begin_attack(WORM.Pattern.SWEEP, swarm, 1.0)
	worm.step(0.3, swarm, 1.0)
	var changed := [0]
	var released := [0]
	worm.phase_changed.connect(func(value: int) -> void: changed[0] = value)
	worm.grubs_released.connect(func(_center: Vector3, amount: int) -> void: released[0] += amount)
	worm.health = worm.max_health * 0.49
	var result: int = worm.step(0.01, swarm, 1.0)
	_check(worm.phase == 2 and worm.state == WORM.State.PHASE_SHIFT and changed[0] == 2, "Phase 2 at 50 % health")
	_check(result == 0 and worm.resolved_power == 0 and worm.telegraphs.is_empty(), "Phase change cancels the pending attack without loss")
	_check(released[0] == WORM.GRUBS_ON_RAGE, "Rage frees %d grubs (signal)" % released[0])
	var queued: Array = worm.take_grubs()
	_check(queued.size() == 1 and int(queued[0].count) == WORM.GRUBS_ON_RAGE and worm.take_grubs().is_empty(), "take_grubs() hands the release over once")
	var health: float = worm.health
	worm.take_damage(40.0)
	_check(worm.health == health and worm.hud_message().contains("TOBT"), "Immune while raging")
	worm.step(WORM.PHASE_SHIFT_SECONDS + 0.01, swarm, 1.0)
	_check(worm.state == WORM.State.CHASE, "Rage ends in a dive / chase")
	worm.state = WORM.State.CHASE
	worm.dive = 0.0
	worm.begin_attack(WORM.Pattern.BREACH, swarm, 1.0)
	_check(worm.remaining == WORM.BREACH_WINDUP[1] and worm.remaining < WORM.BREACH_WINDUP[0], "Phase 2 breach: shorter wind-up")
	# Double breach: the first strike chains into a second ring, exhausted after it.
	var dodge := Vector3(0, 0, 30)
	_run_windup(worm, dodge)
	_check(worm.pending_grubs.size() == 1 and int(worm.pending_grubs[0].count) == WORM.GRUBS_PER_BREACH, "Phase 2 breach frees %d grubs at the hole" % WORM.GRUBS_PER_BREACH)
	for i in 60:
		worm.step(DT, dodge, 1.0)
		if worm.state == WORM.State.WINDUP:
			break
	_check(worm.state == WORM.State.WINDUP and worm.current_pattern == WORM.Pattern.BREACH and worm.chained, "Phase 2 breach chains into a second breach")
	_check(worm.attack_center.distance_to(dodge) < 0.5, "Second ring locks on the swarm again")
	_run_windup(worm, Vector3(0, 0, -30))
	for i in 60:
		worm.step(DT, Vector3(0, 0, -30), 1.0)
	_check(worm.state == WORM.State.EXHAUSTED and not worm.chained, "Exhausted after the chain")
	_check(worm.body_radius > 0.0 and worm._grow > 1.0, "Phase 2 worm grows a little")
	_free(worm)
	# Faster burrowing in phase 2.
	_check(WORM.BURROW_SPEED[1] > WORM.BURROW_SPEED[0] and WORM.COOLDOWN[1] < WORM.COOLDOWN[0] and WORM.EXHAUSTED_SECONDS[1] < WORM.EXHAUSTED_SECONDS[0], "Phase 2 burrows faster, attacks more often, rests shorter")


func _check_death_and_pause() -> void:
	var worm: Variant = _ready_worm()
	var swarm := Vector3(8, 0, 0)
	worm.begin_attack(WORM.Pattern.BREACH, swarm, 1.0)
	worm.step(0.5, swarm, 1.0)
	var snapshot := [worm.state, worm.remaining, worm.position, worm.health, worm.cooldown, worm._time, worm.trail_batch.multimesh.visible_instance_count]
	var total := 0
	for i in 120:
		total += worm.step(0.0, swarm, 1.0)
	_check(not worm.is_processing() and not worm.is_physics_processing(), "Worm has no own clock (pause = no step)")
	_check(total == 0 and [worm.state, worm.remaining, worm.position, worm.health, worm.cooldown, worm._time, worm.trail_batch.multimesh.visible_instance_count] == snapshot, "Zero-delta steps freeze the worm and its trail")
	# Kill it while exhausted.
	_run_windup(worm, Vector3(0, 0, 40))
	worm.state = WORM.State.EXHAUSTED
	worm.remaining = 5.0
	worm.defeated.connect(func(_location: Vector3) -> void: defeats += 1)
	worm.position = Vector3(3, 0, 4)
	worm.take_damage(worm.health + 1.0)
	worm.take_damage(500.0)
	worm.step(1.0, worm.position, 1.0)
	worm.take_damage(500.0)
	_check(defeats == 1, "defeated emitted exactly once (%d)" % defeats)
	_check(worm.state == WORM.State.DEAD and worm.migration_ready and worm.migration_point == Vector3(3, 0, 4), "Death flags + migration point")
	_check(worm.telegraphs.is_empty() and worm.step(1.0, worm.position, 1.0) == 0, "Dead worm never attacks")
	_check(worm.hud_message().contains("BEZWUNGEN"), "Victory banner")
	# Corpse: own design (lying Sandwurm model), ash look when empty.
	var visuals: Variant = CORPSES.new()
	root.add_child(visuals)
	visuals.add(1, worm.corpse_kind, worm.migration_point, 60.0)
	visuals.add(2, "sandgrub", Vector3(6, 0, 0), 0.6)
	_check(visuals.design_of(1) == "apex_sandworm" and CORPSES.rank_of("apex_sandworm") == "boss" and visuals.design_of(2) == "sandgrub", "Corpse designs apex_sandworm (boss) and sandgrub")
	var mesh: Mesh = CORPSES._mesh("apex_sandworm")
	var box := mesh.get_aabb()
	_check(box.size.y <= 3.0 and maxf(box.size.x, box.size.z) > 8.0, "Worm corpse lies flat (%.1f m long, %.1f m high)" % [maxf(box.size.x, box.size.z), box.size.y])
	var grub: Mesh = CORPSES._mesh("sandgrub")
	_check(grub.get_aabb().size.x < 1.5, "Grub corpse is small")
	visuals.free()
	var empty: Variant = CORPSES.new()
	empty.empty = true
	root.add_child(empty)
	empty.add(3, "apex_sandworm", Vector3.ZERO, 60.0)
	_check(empty.drops_of(3) == 0, "Empty (Etappe 16) worm corpse: no crystals, ash look")
	empty.free()
	_free(worm)


func _check_colorblind() -> void:
	var worm: Variant = _ready_worm()
	worm.begin_attack(WORM.Pattern.BREACH, Vector3(8, 0, 0), 1.0)
	var ring: ShaderMaterial = worm.telegraphs[0].material_override
	worm.restyle(true)
	_check(ring.get_shader_parameter("fill_color") == TG.PALETTE_COLORBLIND["boss"].fill, "restyle() swaps the ring palette")
	worm._clear_telegraphs()
	worm.state = WORM.State.CHASE
	worm.begin_attack(WORM.Pattern.SWEEP, Vector3(8, 0, 0), 1.0)
	var cone: ShaderMaterial = worm.telegraphs[0].material_override
	_check(cone.get_shader_parameter("fill_color") == TG.PALETTE_COLORBLIND["boss_cone"].fill and cone.get_shader_parameter("shape") == 1, "Cone built in colour-blind palette, cone shape")
	worm.restyle(false)
	_check(cone.get_shader_parameter("fill_color") == TG.PALETTE["boss_cone"].fill, "restyle(false) restores the cone palette")
	_free(worm)


func _check_body() -> void:
	var worm: Variant = _ready_worm()
	worm.position = Vector3(10, 0, 0)
	worm.rotation.y = 0.0
	worm.state = WORM.State.EXHAUSTED
	# Lying: capsule from the hole along +Z (head).
	_check(worm.contains_body(Vector3(10, 0, WORM.HEAD_REACH)) and worm.contains_body(Vector3(10 + WORM.BODY_RADIUS - 0.1, 0, 2.0)), "Lying body = capsule towards the head")
	_check(is_equal_approx(worm.body_distance(Vector3(16, 0, 3)), 6.0 - WORM.BODY_RADIUS) and not worm.contains_body(Vector3(10, 0, WORM.HEAD_REACH + WORM.BODY_RADIUS + 0.5)), "body_distance measures to the capsule rim")
	worm.state = WORM.State.STRIKE
	worm.current_pattern = WORM.Pattern.BREACH
	_check(not worm.contains_body(Vector3(10, 0, 4.0)) and worm.contains_body(Vector3(11, 0, 0)), "Vertical worm = column around the hole")
	_check(worm.melee_range > worm.body_radius + 1.5, "Melee range reaches past the body")
	_free(worm)


# The worm model: head +Z, rises from the hole; vertical in a breach, lying when
# exhausted; segment waves and maw flare in the skin shader.
func _check_look() -> void:
	var worm: Variant = _ready_worm()
	_check(worm.skin.shader.code.contains("wave_amount") and worm.skin.shader.code.contains("maw_open"), "Skin shader with segment wave + maw flare")
	worm.state = WORM.State.EXHAUSTED
	worm.remaining = 99.0
	worm.rotation.y = 0.0
	for i in 90:
		worm.step(DT, Vector3(0, 0, -20), 1.0)
	var lying: AABB = WORM._bounds(worm.model, worm)
	_check(worm.model.visible and lying.end.z > 5.0 and lying.size.y < lying.size.z, "Exhausted: lies out of the hole towards +Z (%.1f m long, %.1f m high)" % [lying.size.z, lying.size.y])
	_check(float(worm.skin.get_shader_parameter("maw_open")) > 0.25, "Maw gapes while exhausted")
	worm.state = WORM.State.CHASE
	worm.cooldown = 99.0
	worm.begin_attack(WORM.Pattern.BREACH, Vector3(0, 0, 0), 1.0)
	_run_windup(worm, Vector3(0, 0, 30))
	for i in 12:
		worm.step(DT, Vector3(0, 0, 30), 1.0)
	var upright: AABB = WORM._bounds(worm.model, worm)
	_check(upright.end.y > 6.0 and upright.size.y > upright.size.z, "Breach: stands vertically out of the ground (%.1f m high)" % upright.end.y)
	_free(worm)


# Bot fight: dodges every wind-up after a reaction delay (like tests/apex_toad.gd),
# otherwise hugs the surfaced body and bites with `dps` (x vulnerability) while
# within 2 m of the body rim. Returns seconds until death.
func _fight(dps: float) -> float:
	var worm: Variant = _ready_worm()
	worm.cooldown = 1.0
	worm.dive = 0.0
	worm.position = Vector3(0, 0, -6)
	var swarm := Vector3(0, 0, 9)
	var goal := swarm
	var windup_seen := -1
	var react := 0.0
	var losses := 0
	var elapsed := 0.0
	var attacks := 0
	while worm.state != WORM.State.DEAD and elapsed < 180.0:
		elapsed += DT
		if worm.state == WORM.State.WINDUP:
			var id: int = worm.cycle_index * 10 + int(worm.current_pattern) + (5 if worm.chained else 0)
			if id != windup_seen:
				windup_seen = id
				attacks += 1
				react = worm.remaining * REACTION
				var best := INF
				for x in range(-24, 25):
					for z in range(-24, 25):
						var point: Vector3 = swarm + Vector3(x * 0.5, 0, z * 0.5)
						if point.distance_to(swarm) < best and _safe_with_margin(worm, point, 1.0):
							best = point.distance_to(swarm)
							goal = point
			react -= DT
			if react <= 0.0:
				swarm = swarm.move_toward(goal, SWARM_SPEED * DT)
		elif worm.can_be_hit():
			var nearest := _nearest_body_point(worm, swarm)
			swarm = swarm.move_toward(nearest, SWARM_SPEED * DT)
		if worm.can_be_hit() and worm.body_distance(swarm) <= 2.0:
			worm.take_damage(dps * DT)
		losses += worm.step(DT, swarm, 1.0)
		worm.take_grubs()
	_check(losses == 0, "Dodging bot (%.0f DPS) takes no loss (%d)" % [dps, losses])
	_check(attacks >= 5, "Bot fight sees the pattern cycle (%d attacks)" % attacks)
	_free(worm)
	return elapsed


# A spot 1.2 m outside the body rim on the swarm's side.
func _nearest_body_point(worm: Variant, swarm: Vector3) -> Vector3:
	var best := swarm
	var best_distance := INF
	for step in 24:
		var angle := TAU * float(step) / 24.0
		for reach in [2.0, 4.0, 6.0, 8.0, 10.0]:
			var point: Vector3 = worm.position + Vector3(cos(angle), 0, sin(angle)) * reach
			var rim: float = worm.body_distance(point)
			if rim > 0.6 and rim < 1.6 and point.distance_to(swarm) < best_distance:
				best_distance = point.distance_to(swarm)
				best = point
	return best


func _check_fight_length() -> Array:
	var slow := _fight(30.0)
	var average := _fight(40.0)
	var strong := _fight(55.0)
	_check(average >= 35.0 and average <= 50.0, "Average build (40 DPS) fight lasts 35-50 s (%.1f s)" % average)
	_check(strong < average and average < slow and slow < 90.0, "Fight length scales with DPS (%.1f / %.1f / %.1f s)" % [slow, average, strong])
	return [slow, average, strong]


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
