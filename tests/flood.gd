extends SceneTree

# Stage 08 FLOOD: announcement 10 s before the start, start time per difficulty,
# exponential stage (x2 every 40 s) with speed and wave caps, bites remove exactly
# the bitten animals (scaled to the logical population), extinction by the flood,
# bundled horde kills, pause and reset. Also "alle greifen an": Nibbler snap
# (announced small circle, per-animal loss, dodgeable) and faster enemy cycles.
const TUNING = preload("res://scripts/tuning.gd")
const META = preload("res://scripts/meta/meta_data.gd")
const HUD_FLOOD = preload("res://scripts/ui/hud_flood.gd")
var failures: Array[String] = []
var world: Variant
var swarm: Variant
var hud: Variant


# Deterministic stand-in with the horde contract: bites exactly the indices it is
# told to, reports queued kills, counts its calls.
class FakeHorde extends Node3D:
	var bite_next := PackedInt32Array()
	var losses_next := 0
	var kills_next: Array = []
	var steps := 0
	var rings := 0
	var living := 0
	var last_stats := {}

	func setup(_world: Node3D, _swarm: Node3D, _arena: Node3D) -> void:
		pass

	func spawn_ring(_center: Vector3, amount: int, _radius: float, stats: Dictionary, _heading := Vector3.ZERO) -> int:
		rings += 1
		last_stats = stats
		return amount

	func step(_delta: float, _points: PackedVector3Array) -> Dictionary:
		steps += 1
		var result := {"bitten_indices": bite_next, "losses": losses_next}
		bite_next = PackedInt32Array()
		losses_next = 0
		return result

	func damage_circle(_center: Vector3, _radius: float, _amount: float) -> int:
		return 0

	func damage_nearest(_point: Vector3, _max_range: float, _amount: float) -> Vector3:
		return Vector3.INF

	func melee(_points: PackedVector3Array, _reach: float, _dps: float, _delta: float) -> int:
		return 0

	func take_kills() -> Array:
		var result := kills_next
		kills_next = []
		return result

	func count() -> int:
		return living

	func nearest(_point: Vector3) -> Vector3:
		return Vector3.INF

	func clear() -> void:
		living = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	hud = scene.get_node("HUD/Controls")
	var arena: Variant = scene.get_node("Arena")
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)
	_check(hud.get_node_or_null("hud_flood") != null, "Flood HUD component is added to the HUD")

	# ---- Start time per difficulty (Wild without config).
	_check(is_equal_approx(world.flood_start, 300.0), "Wild/no config: flood at 5:00 (got %.0f)" % world.flood_start)
	# Etappe 17c balance: Wild floods at 4:30 (was 5:00).
	var expected := [270.0, 210.0, 180.0]   # Etappe 21: Brutal 240 -> 210
	for difficulty in 3:
		world.config = {"difficulty": difficulty}
		world.reset_run()
		_check(is_equal_approx(world.flood_start, expected[difficulty]), "Difficulty %d: flood at %.0f s (got %.0f)" % [difficulty, expected[difficulty], world.flood_start])
		_check(is_equal_approx(float(META.DIFFICULTIES[difficulty].flood_start), expected[difficulty]), "meta_data lists the flood start of difficulty %d" % difficulty)
	world.config = {}
	world.reset_run()

	# ---- Announcement exactly 10 s before, countdown in the HUD, then the start.
	_quiet()
	world.model.elapsed = 289.0
	world.step(0.05)
	_check(world.flood_state == 0, "No announcement 11 s before the flood")
	world.model.elapsed = 290.0
	world.step(0.05)
	var meta: Dictionary = hud.get_meta("flood", {})
	_check(world.flood_state == 1 and int(meta.get("state", -1)) == 1, "Announcement 10 s before the flood")
	_check(absf(float(meta.get("countdown", 0.0)) - 9.95) < 0.2, "HUD countdown ~10 s (got %.2f)" % float(meta.get("countdown", 0.0)))
	_check(String(hud.hint).begins_with("DIE FLUT KOMMT"), "Hint announces the flood (%s)" % hud.hint)
	_check(world.horde == null or world.horde.count() == 0, "No Moorbrut during the announcement")
	world.model.elapsed = 299.9
	world.step(0.05)
	_check(world.flood_state == 1, "Still counting down at 4:59.95")
	world.step(0.1)
	_check(world.flood_state == 2 and world.flood_reached, "Flood running at 5:00")
	meta = hud.get_meta("flood", {})
	_check(int(meta.get("stage", 0)) == 1, "HUD shows stage 1 at the start")
	_check(HUD_FLOOD.chip_text(3, 95.0) == "FLUT · STUFE 3 · 01:35", "Chip text format (%s)" % HUD_FLOOD.chip_text(3, 95.0))
	# Real horde (if present): first wave rings the swarm off-screen, on open ground.
	if world.horde != null and world.horde.has_method("positions"):
		var ring: PackedVector3Array = world.horde.positions()
		_check(ring.size() > 0, "First wave spawned (%d Moorbrut)" % ring.size())
		var close := 0
		var blocked := 0
		for point in ring:
			if Vector2(point.x - swarm.position.x, point.z - swarm.position.z).length() < 14.0:
				close += 1
			if not arena.is_open(point, 0.2):
				blocked += 1
		_check(close == 0, "Wave spawns at least 14 m away (outside the portrait view), %d too close" % close)
		_check(blocked == 0, "No Moorbrut spawns inside stones (%d blocked)" % blocked)

	# ---- Exponential stage, speed cap, wave cap.
	var base: Dictionary = world.flood_stats()
	world.model.elapsed = world.flood_start + TUNING.FLOOD_DOUBLING_SECONDS
	_check(is_equal_approx(world.flood_level(), 1.0), "Stage k = 1 after 40 s (got %.2f)" % world.flood_level())
	var one: Dictionary = world.flood_stats()
	world.model.elapsed = world.flood_start + 2.0 * TUNING.FLOOD_DOUBLING_SECONDS
	var two: Dictionary = world.flood_stats()
	_check(absf(float(one.hp) / float(base.hp) - 2.0) < 0.01 and absf(float(two.hp) / float(base.hp) - 4.0) < 0.01, "HP doubles every 40 s (%.1f / %.1f / %.1f)" % [base.hp, one.hp, two.hp])
	_check(absf(float(two.bite) / float(base.bite) - 4.0) < 0.01, "Bite strength doubles every 40 s")
	world.model.elapsed = world.flood_start + 10.0 * TUNING.FLOOD_DOUBLING_SECONDS
	var late: Dictionary = world.flood_stats()
	_check(float(late.speed) <= swarm.move_speed() * TUNING.FLOOD_SPEED_SHARE + 0.001 and float(late.speed) <= TUNING.FLOOD_SPEED_CAP + 0.001, "Late Moorbrut stays slower than the swarm (%.2f vs %.2f)" % [late.speed, swarm.move_speed()])
	_check(float(late.hp) > 1000.0, "Late Moorbrut is very tough (%.0f HP)" % late.hp)

	# ---- Fake horde: deterministic bites, kills, pause.
	var fake := FakeHorde.new()
	fake.name = "FakeHorde"
	if world.horde != null:
		world.horde.clear()
		world.horde.queue_free()
	world.add_child(fake)
	world.horde = fake
	if world.attack_forms != null and world.attack_forms.has_method("set_horde"):
		world.attack_forms.set_horde(fake)
	_check(world.flood_wave_count() == TUNING.FLOOD_WAVE_MAX, "Wave size capped at %d (got %d)" % [TUNING.FLOOD_WAVE_MAX, world.flood_wave_count()])
	fake.living = TUNING.FLOOD_MAX_ACTIVE - 7
	_check(world.flood_wave_count() == 7, "Waves never exceed %d living Moorbrut (got %d)" % [TUNING.FLOOD_MAX_ACTIVE, world.flood_wave_count()])
	fake.living = 0
	world.model.elapsed = world.flood_start + 1.0
	world.flood_wave_clock = 0.0
	world.step(0.05)
	_check(fake.rings == 1 and float(fake.last_stats.get("hp", 0.0)) > 0.0, "A wave is spawned with the contract stats")
	world.step(0.05)
	_check(fake.rings == 1, "Next wave waits %.0f s" % TUNING.FLOOD_WAVE_SECONDS)

	# Bites: exactly the bitten animals fall, loss scaled to the logical population.
	world.model.population = 100
	swarm.set_population(100, false)
	world.unit_points_valid = false
	# Index 0 is the leader (stage 09, tests/leader.gd): bite three followers.
	var victims: Array = [swarm.units[4], swarm.units[5], swarm.units[9]]
	var keeper: Variant = swarm.units[1]
	fake.bite_next = PackedInt32Array([4, 5, 9])
	fake.losses_next = 3
	world.step(0.05)
	_check(world.model.population == 97, "Three bites at 100 visible cost three Mawlings (population %d)" % world.model.population)
	var gone := 0
	for unit in victims:
		if not is_instance_valid(unit) or not swarm.units.has(unit):
			gone += 1
	_check(gone == 3 and swarm.units.has(keeper), "Exactly the bitten animals were removed (%d/3)" % gone)
	# Above the visual limit every visible animal stands for several Mawlings.
	world.model.population = 240
	swarm.set_population(240, false)
	world.unit_points_valid = false
	var visible: int = swarm.units.size()
	fake.bite_next = PackedInt32Array([2, 3])
	fake.losses_next = 2
	world.step(0.05)
	var scaled := ceili(2.0 * 240.0 / float(visible) - 0.0001)
	_check(world.model.population == 240 - scaled, "Bites scale to the logical population (lost %d, expected %d)" % [240 - world.model.population, scaled])
	_check(world.hit_feedback > 0.0, "A flood bite gives hit feedback")

	# Horde kills: bundled per cell into persistent crystals (Etappe 16), counted per kill.
	var kills_before: int = world.model.kills
	var bio_before: float = world.loot.total(0)
	var dna_before: float = world.loot.total(1)
	fake.kills_next = [{"position": swarm.position + Vector3(4.0, 0, 1.0), "biomass": 3.0, "dna": 2, "count": 3},
		{"position": swarm.position + Vector3(4.5, 0, 1.2), "biomass": 1.0, "dna": 1, "count": 1}]
	world.step(0.05)
	world.flush_flood_bundles()
	_check(world.horde_kills == 4 and int(world.model.kills_by_type.get("horde", 0)) == 4, "Four horde kills counted (%d)" % world.horde_kills)
	_check(world.model.kills - kills_before == 4, "Kills grow by four (got %d)" % (world.model.kills - kills_before))
	_check(absf(world.loot.total(0) + world.model.consumed_biomass - bio_before - 4.0 * world.evolution.biomass_multiplier()) < 0.01, "Crystals hold the bundled biomass (%.2f)" % (world.loot.total(0) - bio_before))
	# Flood DNA is saved up until a whole crystal (LOOT_DNA_CHUNK) comes together.
	_check(int(round(world.loot.total(1) - dna_before)) + int(world.flood_dna_pending) == 3 or world.evolution.dna > 0, "Crystals (or the pending flood DNA) hold the bundled DNA")
	_check(world.corpse_kinds.values().has("horde"), "Horde remains lie there as decoration")

	# Pause freezes the flood (no horde step, no clock).
	var steps_before: int = fake.steps
	var elapsed_before: float = world.model.elapsed
	world.paused = true
	_steps(1.0)
	_check(fake.steps == steps_before and is_equal_approx(world.model.elapsed, elapsed_before), "Pause freezes the flood")
	world.paused = false

	# Extinction by the flood ends the run and fills RunStats.
	world.model.population = 20
	swarm.set_population(20, false)
	world.unit_points_valid = false
	var all := PackedInt32Array()
	for index in swarm.units.size():
		all.append(index)
	fake.bite_next = all
	fake.losses_next = 40
	# Stage 09: the leader on its last LP falls with the rest.
	world.model.leader_hp = 1
	world.model.leader_invulnerable = 0.0
	world.step(0.05)
	_check(world.model.extinct, "Flood bites can wipe out the swarm")
	var stats: Dictionary = world.run_stats()
	_check(bool(stats.get("flood_reached", false)) and float(stats.get("flood_seconds", 0.0)) > 0.0 and int(stats.get("horde_kills", 0)) == 4, "RunStats: flood_reached, flood_seconds, horde_kills (%s)" % str(stats))

	# ---- Reset clears the flood.
	world.reset_run()
	await process_frame
	_check(world.flood_state == 0 and not world.flood_reached and world.horde_kills == 0 and world.flood_bundles.is_empty(), "Reset clears the flood state")
	_check(world.horde == null or (world.horde != fake and world.horde.count() == 0), "Reset brings a fresh, empty horde")
	_check(int(hud.get_meta("flood", {}).get("state", -1)) == 0, "HUD flood state reset")

	# ---- Alle greifen an: Nibbler snap.
	_quiet()
	world.model.population = 40
	swarm.set_population(40, false)
	world.unit_points_valid = false
	world._spawn_prey(swarm.position + Vector3(1.4, 0, 0))
	var nibbler: Variant = world.prey[-1]
	await process_frame
	nibbler.snap_cooldown = 0.0
	world.step(0.05)
	_check(nibbler.snap_state == 1, "A surrounded Nibbler announces a snap")
	_check(nibbler.snap_zone != null and nibbler.snap_zone.visible, "Snap telegraph is visible")
	_check(Vector2(nibbler.snap_center.x - nibbler.position.x, nibbler.snap_center.z - nibbler.position.z).length() <= TUNING.NIBBLER_SNAP_REACH + 0.01, "Snap circle sits right in front of the Nibbler")
	var locked: Vector3 = nibbler.snap_center
	var before: int = world.model.population
	_steps(TUNING.NIBBLER_SNAP_WARNING - 0.15)
	_check(world.model.population == before, "No loss during the snap warning")
	_check(nibbler.snap_center.is_equal_approx(locked), "Snap circle stays locked")
	_steps(0.3)
	var lost: int = before - world.model.population
	_check(lost >= 1 and lost <= 12, "Snap costs a few Mawlings (%d)" % lost)
	_check(nibbler.snap_state == 0 and not nibbler.snap_zone.visible, "Snap resolves and the telegraph hides")
	# Dodging the locked circle avoids the loss.
	nibbler.snap_cooldown = 0.0
	nibbler.position = swarm.position + Vector3(1.4, 0, 0)
	# Stage 09: the shared snap gap blocks every Nibbler for a moment first.
	_check(world.snap_gap > 0.0, "A resolved snap starts the shared snap gap")
	world.snap_gap = 0.0
	world.step(0.05)
	_check(nibbler.snap_state == 1, "Nibbler snaps again after its cooldown")
	swarm.position += Vector3(-6.0, 0, 0)
	world.unit_points_valid = false
	before = world.model.population
	_steps(TUNING.NIBBLER_SNAP_WARNING + 0.1)
	_check(world.model.population == before, "Leaving the circle dodges the snap (lost %d)" % (before - world.model.population))
	# A bitten Nibbler fights back even when the swarm is not on top of it.
	world.prey.clear()
	world._spawn_prey(swarm.position + Vector3(3.0, 0, 0))
	var angry: Variant = world.prey[-1]
	await process_frame
	angry.snap_cooldown = 0.0
	var approach_from: float = angry.position.distance_to(swarm.position)
	angry.step(0.05, swarm.position, 1.0)
	_check(angry.snap_state == 0 and angry.position.distance_to(swarm.position) < approach_from, "A calm Nibbler 3 m away closes in instead of snapping (stage 09)")
	angry.health -= 1.0
	angry.step(0.05, swarm.position, 1.0)
	_check(angry.snap_state == 1, "A bitten Nibbler snaps back")

	# ---- Alle greifen an: shorter enemy cycles, faster under pressure.
	var hunter: Variant = world._spawn_hunter(swarm.position + Vector3(20, 0, 0))
	_check(hunter.remaining <= TUNING.HUNTER_ARRIVE_SECONDS + 0.001 and TUNING.HUNTER_ARRIVE_SECONDS <= 0.6, "Hunters join the chase almost at once")
	_check(TUNING.recovery(TUNING.HUNTER_RECOVERY_SECONDS, 8.0, 0.55) < TUNING.HUNTER_RECOVERY_SECONDS * 0.7, "Hunter recovery shrinks under pressure")
	_check(TUNING.recovery(TUNING.SKITTER_RECOVERY_SECONDS, 1.0, 0.7) <= 1.3 and TUNING.LEAPER_LURK_SECONDS <= 1.6, "Skitter/Leaper idle phases are short")

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS flood: announcement 10 s, start per difficulty, x2 per %d s with speed/wave caps, exact bites, bundled kills, extinction, pause, reset; Nibbler snap + faster enemies" % int(TUNING.FLOOD_DOUBLING_SECONDS))
	quit(0)


func _quiet() -> void:
	for target in world.prey:
		target.queue_free()
	world.prey.clear()
	world.spawn_clock = -1000000.0
	world.hunter_clock = 1000000.0
	world.skitter_clock = 1000000.0
	world.leaper_clock = 1000000.0
	world.boss_clock = 1000000.0
	world.elite_clock = 1000000.0
	world.nest_clock = 1000000.0


func _steps(seconds: float) -> void:
	for index in int(round(seconds / 0.05)):
		world.step(0.05)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
