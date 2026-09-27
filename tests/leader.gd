extends SceneTree

# Stage 09 KERN: lone start, leader LP, invulnerability, one LP per frame,
# takeover with -1 max LP, last animal -> extinction, milestone heal,
# Rückeroberung biomass, the leader is never removed by prefer_removal,
# Nibbler snaps never take the last LP, first hunter gate.

const HUNTER = preload("res://scripts/hunter.gd")
const PREY = preload("res://scripts/prey.gd")
const TUNING = preload("res://scripts/tuning.gd")
const RUN_MODEL = preload("res://scripts/run_model.gd")
var failures: Array[String] = []
var world: Variant
var swarm: Variant
var hud: Variant
var main: Variant


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	world = main.get_node("HuntWorld")
	swarm = main.get_node("Swarm")
	hud = main.get_node("HUD/Controls")
	main.set_process(false)
	world.set_process(false)
	swarm.set_process(false)

	# ---- Lone start (no config) and model rules.
	world.reset_run()
	_check(world.model.population == 1 and swarm.units.size() == 1, "Run starts with one Mawling (got %d)" % world.model.population)
	_check(world.model.leader_hp == TUNING.LEADER_HP and world.model.leader_max_hp == TUNING.LEADER_HP, "Leader starts with %d LP" % TUNING.LEADER_HP)
	var model = RUN_MODEL.new()
	model.configure(1, 80.0, 5)
	_check(model.leader_hp == 5 and model.leader_max_hp == 5, "Config leader_hp raises the leader's LP")

	# ---- A hit on the lone leader costs 1 LP, then 1.2 s invulnerability.
	_fresh(1)
	_ring_hunter(20)
	world.step(0.02)
	_check(world.model.population == 1 and world.model.leader_hp == TUNING.LEADER_HP - 1, "Leader hit costs exactly 1 LP (hp %d, pop %d)" % [world.model.leader_hp, world.model.population])
	_check(world.model.leader_invulnerable > 1.1, "Leader hit starts the invulnerability window")
	_check(_hud("leader_hp") == TUNING.LEADER_HP - 1 and _hud("leader_max_hp") == TUNING.LEADER_HP and bool(_hud("leader_invulnerable")), "HUD shows leader LP and invulnerability")
	_ring_hunter(20)
	world.step(0.02)
	_check(world.model.leader_hp == TUNING.LEADER_HP - 1, "Invulnerable leader ignores a second hit")
	_steps(TUNING.LEADER_INVULNERABLE_SECONDS)
	_check(world.model.leader_invulnerable == 0.0 and not bool(_hud("leader_invulnerable")), "Invulnerability ends after %.1f s" % TUNING.LEADER_INVULNERABLE_SECONDS)
	_ring_hunter(20)
	world.step(0.02)
	_check(world.model.leader_hp == TUNING.LEADER_HP - 2, "After the window the leader can be hit again")

	# ---- Several sources in one frame cost only one LP; followers die normally.
	_fresh(10)
	_place(10, swarm.position)
	_ring_hunter(10)
	_ring_hunter(10)
	world.step(0.02)
	_check(world.model.leader_hp == TUNING.LEADER_HP - 1, "Two hits in one frame cost only 1 LP (hp %d)" % world.model.leader_hp)
	_check(world.model.population == 1 and not world.model.extinct, "Followers inside die, the leader survives (pop %d)" % world.model.population)
	_check(is_equal_approx(world.last_loss_fraction, 0.9), "last_loss_fraction = loss / population before (%.2f)" % world.last_loss_fraction)

	# ---- Loss without the leader: leader outside the ring loses nothing.
	_fresh(10)
	_place(10, swarm.position + Vector3(0, 0, 10))
	swarm.units[0].position = Vector3(0, 0, -10)
	world.unit_points_valid = false
	var leader_unit: Variant = swarm.units[0]
	_ring_hunter(10, swarm.position + Vector3(0, 0, 10))
	world.step(0.02)
	_check(world.model.leader_hp == TUNING.LEADER_HP and world.model.population == 1, "Leader outside the ring keeps its LP, the nine inside fall")
	_check(swarm.units.size() == 1 and swarm.units[0] == leader_unit, "The leader stays units[0] after followers fall")

	# ---- prefer_removal never removes the leader.
	_fresh(6)
	leader_unit = swarm.units[0]
	swarm.prefer_removal(PackedInt32Array([0, 1, 2]))
	world.model.population = 3
	swarm.set_population(3, false)
	_check(swarm.units.size() == 3 and swarm.units[0] == leader_unit, "prefer_removal never removes the leader (index 0)")
	_fresh(8)
	leader_unit = swarm.units[0]
	_place(8, swarm.position)
	_ring_hunter(4)
	world.step(0.02)
	_check(swarm.units[0] == leader_unit and world.model.population == 4, "An area hit on the leader keeps the same leader at index 0 (pop %d)" % world.model.population)

	# ---- Takeover: LP 0 -> next animal leads with max(1, max - 1) LP.
	_fresh(5)
	world.model.leader_hp = 1
	_place(1, swarm.position, swarm.position + Vector3(0, 0, 12))
	swarm.units[0].position = Vector3.ZERO
	world.unit_points_valid = false
	var old_leader: Variant = swarm.units[0]
	_ring_hunter(20)
	world.step(0.02)
	_check(world.model.population == 4 and world.model.leader_swaps == 1, "Leader death costs one animal and promotes another (pop %d)" % world.model.population)
	_check(world.model.leader_max_hp == TUNING.LEADER_HP - 1 and world.model.leader_hp == TUNING.LEADER_HP - 1, "New leader: max(1, old max - 1) LP, fully healed (%d/%d)" % [world.model.leader_hp, world.model.leader_max_hp])
	_check(swarm.units.size() == 4 and swarm.units[0] != old_leader, "Another animal is units[0] now")
	_check(world.run_stats().get("leader_swaps", 0) == 1, "RunStats count leader swaps")
	# The chain never drops below 1 max LP.
	world.model.leader_max_hp = 1
	world.model.leader_hp = 1
	world.model.leader_invulnerable = 0.0
	var outcome: Dictionary = world.model.apply_hit(0, true)
	_check(outcome.leader == "swap" and world.model.leader_max_hp == 1 and world.model.leader_hp == 1, "Max LP never drops below 1")

	# ---- Last animal on its last LP -> extinction.
	_fresh(1)
	world.model.leader_hp = 1
	_ring_hunter(3)
	world.step(0.02)
	_check(world.model.extinct and world.model.population == 0 and hud.extinct, "The last leader's last LP ends the run (extinct %s, pop %d, hp %d, hud %s)" % [world.model.extinct, world.model.population, world.model.leader_hp, hud.extinct])

	# ---- Nibbler snap: hits the leader, never takes the last LP.
	_fresh(1)
	world.snap_gap = 0.0
	world._spawn_prey(swarm.position + Vector3(1.2, 0, 0))
	var nibbler: Variant = world.prey[-1]
	await process_frame
	nibbler.snap_cooldown = 0.0
	world.step(0.05)
	_check(nibbler.snap_state == 1, "A Nibbler next to the lone leader announces a snap")
	nibbler.snap_center = swarm.position
	_steps(TUNING.NIBBLER_SNAP_WARNING + 0.1)
	_check(world.model.leader_hp == TUNING.LEADER_HP - 1, "Nibbler snap costs the leader 1 LP (hp %d, snap %d, points %s, centre %s)" % [world.model.leader_hp, nibbler.snap_state, str(swarm.unit_world_points()), str(nibbler.snap_center)])
	world.model.leader_hp = 1
	world.model.leader_invulnerable = 0.0
	world.snap_gap = 0.0
	nibbler.snap_cooldown = 0.0
	nibbler.position = swarm.position + Vector3(1.2, 0, 0)
	world.step(0.05)
	nibbler.snap_center = swarm.position
	_steps(TUNING.NIBBLER_SNAP_WARNING + 0.1)
	_check(world.model.leader_hp == 1 and not world.model.extinct, "A Nibbler snap never takes the leader's last LP")
	# Only one snap circle at a time.
	_fresh(1)
	world.snap_gap = 0.0
	world._spawn_prey(swarm.position + Vector3(1.2, 0, 0))
	world._spawn_prey(swarm.position + Vector3(-1.2, 0, 0))
	await process_frame
	for target in world.prey:
		target.snap_cooldown = 0.0
	world.step(0.05)
	var snapping := 0
	for target in world.prey:
		if target.snap_state == 1:
			snapping += 1
	_check(snapping == 1, "Only one Nibbler announces a snap at a time (%d)" % snapping)
	# Nibblers close in on the swarm.
	_fresh(1)
	world._spawn_prey(swarm.position + Vector3(6, 0, 0))
	nibbler = world.prey[-1]
	await process_frame
	_steps(1.0)
	_check(nibbler.position.distance_to(swarm.position) < 5.0, "Nibblers walk towards the swarm (%.1f m)" % nibbler.position.distance_to(swarm.position))

	# ---- Rückeroberung: fallen Mawlings leave bundled biomass.
	_fresh(11)
	_place(11, swarm.position + Vector3(0, 0, 6))
	swarm.units[0].position = Vector3(0, 0, -10)
	world.unit_points_valid = false
	_ring_hunter(10, swarm.position + Vector3(0, 0, 6))
	world.step(0.02)
	_check(world.model.population == 1 and world.model.corpses.size() == 1, "Ten fallen Mawlings leave one corpse (%d)" % world.model.corpses.size())
	var fallen_id: int = world.model.corpses[0].id if not world.model.corpses.is_empty() else -1
	_check(is_equal_approx(world.model.remaining_biomass(fallen_id), 10.0 * TUNING.FALLEN_BIOMASS), "It holds %.1f biomass per fallen Mawling" % TUNING.FALLEN_BIOMASS)
	_check(world.corpse_kinds.get(fallen_id, "") == "mawling" and world.model.kills == 0, "Fallen corpse is kind 'mawling' and no kill")
	world.model.population = 4
	swarm.set_population(4, false)
	_place(4, swarm.position + Vector3(0.5, 0, 6))
	swarm.units[0].position = Vector3(0, 0, -10)
	world.unit_points_valid = false
	_ring_hunter(3, swarm.position + Vector3(0.5, 0, 6))
	world.step(0.02)
	_check(world.model.corpses.size() == 1 and is_equal_approx(world.model.remaining_biomass(fallen_id), 13.0 * TUNING.FALLEN_BIOMASS), "Later losses nearby join the same corpse")

	# ---- Milestones and +1 LP per 25.
	var cost: float = RUN_MODEL.BIOMASS_PER_MAWLING
	_fresh(24)
	world.model.leader_hp = 1
	world._create_corpse(swarm.position, cost)
	world.step(1.0)
	_check(world.model.population == 25, "Harvest grows to 25 (got %d)" % world.model.population)
	_check(world.model.leader_hp == 2, "Reaching 25 heals the leader by 1 LP (hp %d)" % world.model.leader_hp)
	_check(world.milestone_value == 25 and _hud("milestone") == 25, "Milestone 25 is announced")
	_steps(world.MILESTONE_SHOW_SECONDS + 0.1)
	_check(_hud("milestone") == 0, "Milestone banner value clears again")
	world.model.leader_hp = 3
	world.model.apply_hit(3, false)
	swarm.set_population(world.model.population, false)
	world.model.leader_hp = 1
	world._create_corpse(swarm.position, cost * 3.0)
	world.step(3.0)
	_check(world.model.population == 25 and world.model.leader_hp == 1 and world.milestone_value == 0, "Reaching 25 again neither heals nor announces (hp %d, milestone %d)" % [world.model.leader_hp, world.milestone_value])
	model = RUN_MODEL.new()
	var id: int = model.add_corpse(Vector3.ZERO, 100.0)
	model.harvest(id, cost * 4.0 + 0.01)
	_check(model.population == 5 and model.take_milestone() == 5 and model.take_milestone() == 0, "Milestone 5 once, then consumed (pop %d)" % model.population)
	model.leader_hp = 1
	var huge: int = model.add_corpse(Vector3.ZERO, 1000.0)
	model.harvest(huge, cost * 45.0 + 0.01)
	_check(model.population == 50 and model.leader_hp == 3, "25 and 50 each heal one LP up to the max (hp %d)" % model.leader_hp)

	# ---- First hunter waits for 4 Mawlings or 50 s.
	world.reset_run()
	_quiet_prey()
	world.model.elapsed = 30.0
	world.hunter_clock = 0.0
	world.step(0.05)
	_check(world.hunters.is_empty(), "No hunter for a lone leader at 30 s")
	world.model.population = TUNING.FIRST_HUNTER_POPULATION
	swarm.set_population(TUNING.FIRST_HUNTER_POPULATION, false)
	world.step(0.05)
	_check(world.hunters_unlocked and world.hunters.is_empty(), "Four Mawlings unlock the hunters after a short grace")
	_steps(TUNING.FIRST_HUNTER_GRACE + 0.1)
	_check(world.hunters.size() == 1, "The first hunter arrives after the grace (%d)" % world.hunters.size())
	world.reset_run()
	_quiet_prey()
	world.model.elapsed = TUNING.FIRST_HUNTER_LATEST
	world.step(0.05)
	_check(world.hunters_unlocked, "At %.0f s hunters come even for a lone leader" % TUNING.FIRST_HUNTER_LATEST)

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS leader: lone start, 1 LP per hit, invulnerability, one LP per frame, takeover -1 max, extinction, Nibbler never lethal, one snap at a time, Rückeroberung, milestones + heal, hunter gate")
	quit(0)


func _fresh(population: int) -> void:
	world.reset_run()
	world.hunter_clock = 1e9
	world.skitter_clock = 1e9
	world.leaper_clock = 1e9
	world.boss_clock = 1e9
	world.nest_clock = 1e9
	world.elite_clock = 1e9
	_quiet_prey()
	world.model.population = population
	world.model.peak_population = population
	swarm.set_population(population, false)
	# Swarm processing is off: gather everyone on the swarm centre (earlier checks
	# moved units around).
	for unit in swarm.units:
		unit.position = Vector3.ZERO
	world.unit_points_valid = false


func _quiet_prey() -> void:
	for target in world.prey:
		target.queue_free()
	world.prey.clear()
	world.spawn_clock = -1e9


# All visible units at world point `a` (optionally the first `count` at a, rest at b).
func _place(count: int, a: Vector3, b: Vector3 = Vector3(0, 0, 50)) -> void:
	for index in swarm.units.size():
		swarm.units[index].position = (a if index < count else b) - swarm.position
	world.unit_points_valid = false


func _ring_hunter(power: int, center: Variant = null) -> Variant:
	var hunter: Variant = world._spawn_hunter(swarm.position + Vector3(0, 0, 20))
	hunter.state = HUNTER.State.WARNING
	hunter.remaining = 0.01
	hunter.attack_center = swarm.position if center == null else center
	hunter.attack_power = power
	return hunter


func _steps(seconds: float) -> void:
	for index in int(round(seconds / 0.05)):
		world.step(0.05)


func _hud(key: String) -> Variant:
	if key in hud:
		return hud.get(key)
	return hud.get_meta(key, null)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
