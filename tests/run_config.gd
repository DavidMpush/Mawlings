extends SceneTree

# Stage 03 RUN: RunConfig reaches the game, slots/signature/difficulty apply,
# Alpha-Kern persists and evolves, ranged kills reward once, stats reach Session.
const SESSION = preload("res://scripts/meta/session.gd")
const HUNTER = preload("res://scripts/hunter.gd")
const TUNING = preload("res://scripts/tuning.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	SESSION.last_result = {}
	SESSION.pending_config = {
		"strain_id": "testmaw", "biome_id": "verdant_maw", "difficulty": 1,
		"start_population": 40, "tint": Color("5fb8ff"),
		"signature_attack": "saeurespucker",
		"mods": {"damage": 1.0, "armor": 0.0, "speed": 1.2, "harvest": 1.0, "dna": 1.0, "growth": 1.0},
		"enemy_hp": 2.0, "enemy_damage": 2.0, "pressure_doubling": 45.0,
		"slots": {"attack": 1, "trait": 1}, "rerolls": 1, "banishes": 1, "skips": 1,
		"pool": ["jaws", "brood", "glutton", "pack", "armor", "scatter", "saeurespucker", "rudelbiss", "sporenwolke"],
	}
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var world: Variant = scene.get_node("HuntWorld")
	var swarm: Variant = scene.get_node("Swarm")
	var hud: Variant = scene.get_node("HUD/Controls")
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)
	var evo: Variant = world.evolution

	# Config applied and consumed.
	_check(SESSION.pending_config.is_empty(), "Main clears the pending config")
	_check(world.model.population == 40 and swarm.population == 40 and swarm.units.size() == 40, "Start population from config")
	_check(evo.rank("saeurespucker") == 1 and evo.slots_used("attack") == 1, "Signature attack starts at rank 1")
	_check(world.attack_forms != null and world.attack_forms.rank("saeurespucker") == 1, "Signature reaches AttackForms")
	_check(is_equal_approx(swarm.move_speed(), swarm.MOVE_SPEED * 1.2), "Strain speed reaches the swarm")
	world.model.elapsed = 45.0
	_check(is_equal_approx(world.model.pressure(), 2.0), "Difficulty pressure doubling")
	# Stage 08: the difficulty multipliers ramp in over DIFFICULTY_RAMP_SECONDS.
	world.model.elapsed = 0.0
	var hunter: Variant = world._spawn_hunter(Vector3(30, 0, 0))
	_check(is_equal_approx(hunter.health, TUNING.HUNTER_HEALTH), "Difficulty enemy health starts at x1")
	world.model.elapsed = TUNING.DIFFICULTY_RAMP_SECONDS
	hunter = world._spawn_hunter(Vector3(-30, 0, 0))
	_check(is_equal_approx(hunter.health, TUNING.HUNTER_HEALTH * sqrt(world.model.pressure()) * 2.0), "Difficulty enemy health")
	world._apply_hit(3, swarm.position, 0.0)
	_check(world.model.population == 34, "Difficulty enemy damage")
	world.model.elapsed = 0.0

	# Offers respect the pool and free slots; counters work once.
	world.reset_run()
	evo = world.evolution
	_check(world.model.population == 40 and evo.rank("saeurespucker") == 1, "Restart keeps the run config")
	evo.rng.seed = 7
	world._award_dna(20)
	_check(world.choosing(), "Offer opens at threshold")
	for offer in evo.offers:
		_check(evo.pool.has(offer[0]), "Offer comes from the pool")
		_check(not (offer[0] in ["rudelbiss", "sporenwolke", "stachelruecken"]), "Full attack slot offers no new attack form")
	var before: Array = evo.offers.map(func(entry): return entry[0])
	world.reroll_mutations()
	_check(evo.rerolls == 0 and evo.offers.size() > 0, "Reroll spends its charge")
	world.reroll_mutations()
	_check(evo.rerolls == 0, "No reroll without charges")
	var banished: String = evo.offers[0][0]
	world.banish_mutation(0)
	_check(evo.banishes == 0 and evo.banished.has(banished), "Banish removes the mutation")
	for offer in evo.offers:
		_check(offer[0] != banished, "Banished mutation is not offered again")
	world._award_dna(30)
	var dna_before: int = evo.dna
	world.skip_mutation()
	_check(evo.skips == 0 and evo.dna == dna_before - 20 and evo.level == 0, "Skip spends the level-up")
	if not world.choosing():
		world._award_dna(20)
	var trait_slot := -1
	for slot in evo.offers.size():
		if evo.kind_of(evo.offers[slot][0]) == "trait":
			trait_slot = slot
	if trait_slot < 0:
		evo.offers[0] = evo.info("jaws")
		trait_slot = 0
	var trait_id: String = evo.offers[trait_slot][0]
	world.choose_mutation(trait_slot)
	evo.dna = 1000
	evo.offers.clear()
	evo._prepare()
	for offer in evo.offers:
		_check(evo.rank(offer[0]) > 0, "Full slots offer only rank-ups (%s)" % offer[0])
	_check(evo.rank(trait_id) == 1 and evo.slots_used("trait") == 1, "Trait took its slot")
	var hud_slots: String = hud._slot_text()
	_check(hud_slots == "Angriff 1/1 · Anlagen 1/1", "HUD shows slot usage")

	# Alpha-Kern: stays on the ground, then evolves on touch.
	world.reset_run()
	evo = world.evolution
	_quiet(world)
	var core: Node3D = world._drop_alpha_core(swarm.position + Vector3(8, 0, 0))
	for tick in 120:
		world.step(0.05)
	_check(world.alpha_pickups.size() == 1 and is_instance_valid(core) and evo.alpha_cores == 0, "Alpha-Kern stays until touched")
	evo.ranks["saeurespucker"] = 3
	evo.ranks["glutton"] = 1
	swarm.position = core.position
	world.step(0.05)
	_check(world.alpha_pickups.is_empty() and evo.alpha_cores == 0, "Touch collects the Alpha-Kern")
	_check(evo.evolutions.has("aetzflut") and evo.rank("aetzflut") == 1 and evo.rank("saeurespucker") == 0, "Ätzflut replaces Säurespucker")
	_check(world.attack_forms.rank("aetzflut") == 1 and world.attack_forms.rank("saeurespucker") == 0, "Evolution reaches AttackForms")
	_check(world.evolve_flash > 0.0 and hud.evolve_name == "Ätzflut", "Evolution banner")
	evo.dna = 1000
	evo.offers.clear()
	evo._prepare()
	for offer in evo.offers:
		_check(offer[0] != "saeurespucker", "Evolved base form is not offered again")

	# Stored core evolves later when the rules are met.
	world.reset_run()
	evo = world.evolution
	_quiet(world)
	evo.ranks.erase("saeurespucker")
	evo.ranks["rudelbiss"] = 3
	world.collect_alpha_core()
	_check(evo.alpha_cores == 1 and evo.evolutions.is_empty(), "Alpha-Kern is stored without rules met")
	evo.offers = [evo.info("pack")]
	evo.dna = 20
	world.choose_mutation(0)
	_check(evo.alpha_cores == 0 and evo.evolutions.has("meute") and evo.rank("rudelbiss") == 0, "Stored core evolves Meute after Rudelinstinkt")

	# Drop rules: Bog King always drops a core.
	world.reset_run()
	_quiet(world)
	var king: Variant = world._spawn_boss(swarm.position + Vector3(20, 0, 0))
	king.health = -1.0
	world.step(0.01)
	_check(world.boss == null and world.alpha_pickups.size() == 1 and world.model.bosses == 1, "Bog King drops an Alpha-Kern")

	# Ranged kill (Säurespucker) far outside melee reach rewards exactly once.
	world.reset_run()
	evo = world.evolution
	_quiet(world)
	evo.ranks["saeurespucker"] = 3
	world._sync_attack_forms()
	hunter = world._spawn_hunter(swarm.position + Vector3(5, 0, 0))
	hunter.state = HUNTER.State.RECOVERY
	hunter.remaining = 1000.0
	for tick in 600:
		world.step(0.05)
		if not world.hunters.has(hunter):
			break
	_check(world.hunters.is_empty() and world.model.kills_by_type.hunter == 1, "Ranged damage kills the hunter")
	_check(evo.dna == 20 and world.model.corpses.size() == 1 and world.model.kills == 1, "Ranged kill gives DNA and biomass once")
	_check(world.model.corpses[0].initial == TUNING.HUNTER_BIOMASS * evo.biomass_multiplier(), "Ranged kill leaves full biomass")
	_check(not world._resolve_death(hunter, "hunter") and evo.dna == 20, "Dead hunter never rewards twice")

	# Extinction hands RunStats to the Session and shows both result buttons.
	swarm.rally_pressed = true
	evo.offers.clear()
	world.step(0.01)
	# Stage 09: only the leader's last LP ends the run.
	world.model.leader_hp = 1
	world.model.leader_invulnerable = 0.0
	world._apply_hit(100000, swarm.position, 0.0, null, true)
	var stats: Dictionary = SESSION.last_result
	_check(world.model.extinct and not stats.is_empty(), "Extinction stores RunStats in Session")
	for key in ["strain_id", "biome_id", "difficulty", "seconds", "peak_population", "final_population", "kills", "kills_by_type", "biomass", "lost", "bosses", "evolutions", "mutations", "used_rally"]:
		_check(stats.has(key), "RunStats has %s" % key)
	_check(stats.get("strain_id") == "testmaw" and stats.get("difficulty") == 1 and stats.get("final_population") == 0, "RunStats carries config and outcome")
	_check(stats.get("kills_by_type", {}).get("hunter", 0) == 1 and stats.get("used_rally") == true, "RunStats counts kills by type and Rally")
	_check(stats.get("mutations", {}).get("saeurespucker", 0) == 3, "RunStats lists mutations")
	var hub_calls := [0]
	if hud.hub_requested.is_connected(scene._open_hub):
		hud.hub_requested.disconnect(scene._open_hub)
	hud.hub_requested.connect(func(): hub_calls[0] += 1)
	hud._press(-2, hud._hub_rect().get_center())
	_check(hub_calls[0] == 1, "BRUTSTÄTTE button requests the hub")
	_check(not hud._hub_rect().intersects(hud._action_rect()), "Result buttons do not overlap")
	SESSION.last_result = {}

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS run_config: config, signature, slots, pool, reroll/banish/skip, difficulty, alpha core, evolutions, ranged kill, RunStats, result buttons")
	quit(0)


# No director spawns and no prey: only what the test places acts.
func _quiet(world: Variant) -> void:
	for target in world.prey:
		target.queue_free()
	world.prey.clear()
	world.spawn_clock = -100000.0
	world.hunter_clock = 100000.0
	world.skitter_clock = 100000.0
	world.leaper_clock = 100000.0
	world.boss_clock = 100000.0


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
