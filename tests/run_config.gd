extends SceneTree

# Stage 03 RUN: RunConfig reaches the game, slots/signature/difficulty apply,
# Alpha-Kern persists and evolves, ranged kills reward once, stats reach Session.
const SESSION = preload("res://scripts/meta/session.gd")
const HUNTER = preload("res://scripts/hunter.gd")
const TUNING = preload("res://scripts/tuning.gd")
const STATS = preload("res://scripts/progression/stats.gd")
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
	# Etappe 17 Welle 1: die Startwaffe beginnt auf SIGNATURE_START_RANK (ohne Kokons).
	var start_rank: int = evo.SIGNATURE_START_RANK
	_check(evo.rank("saeurespucker") == start_rank and evo.slots_used("attack") == 1, "Signature attack starts at rank %d" % start_rank)
	_check(world.attack_forms != null and world.attack_forms.rank("saeurespucker") == start_rank, "Signature reaches AttackForms")
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
	_check(world.model.population == 40 and evo.rank("saeurespucker") == evo.SIGNATURE_START_RANK, "Restart keeps the run config")
	evo.rng.seed = 7
	world._award_dna(20)
	_check(world.choosing(), "Offer opens at threshold")
	for offer in evo.offers:
		_check(evo.pool.has(offer[0]), "Offer comes from the pool")
		# Etappe 17: Level geben nur Werte; alte Anlagen-IDs im Pool werden abgebildet.
		_check(evo.kind_of(offer[0]) == "trait", "Level offers only stats (%s)" % offer[0])
		_check(offer[0] in ["bite", "brood", "rally", "armor", "evade"], "Old trait IDs are migrated (%s)" % offer[0])
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
	var stat_id: String = evo.offers[0][0]
	var rarity: String = evo.offers[0][3]
	world.choose_mutation(0)
	_check(evo.rank(stat_id) == 1 and is_equal_approx(evo.stats.units_of(stat_id), float(STATS.RARITY_FACTOR[rarity])), "Stat rank and rarity value (%s %s)" % [stat_id, rarity])
	_check(evo.slots_used("attack") == 1 and evo.slot_limit("attack") == 1, "Weapon slots come from the config")
	_check(evo.arsenal.weapon_pool.has("rudelbiss") and not evo.arsenal.weapon_pool.has("klauenwirbel"), "Weapon pool comes from the config")

	# Stage 15: in the brawl skin taps hit the cards mutation_screen draws
	# (touch_controls asks it for card/banish rects).
	var ms: Variant = hud.get_node_or_null("mutation_screen")
	var brawl: bool = load("res://scripts/ui/ui_style.gd").is_brawl()
	_check(ms != null or not brawl, "Brawl skin has the mutation_screen component")
	if ms != null and brawl:
		world.reset_run()
		evo = world.evolution
		evo.rng.seed = 11
		world._award_dna(20)
		_check(world.choosing() and evo.offers.size() >= 2, "Brawl tap test has two offers")
		if evo.offers.size() >= 2:
			var target: String = evo.offers[1][0]
			hud._press(-2, ms.banish_rect(1).get_center())
			hud._release(-2)
			_check(evo.banished.has(target), "Brawl: tap on banish_rect banishes the card")
			if world.choosing() and evo.offers.size() >= 2:
				var pick: String = evo.offers[1][0]
				var rank_before: int = evo.rank(pick)
				hud._press(-2, ms.card_rect(1).get_center())
				hud._release(-2)
				_check(evo.rank(pick) == rank_before + 1, "Brawl: tap on card_rect(1) chooses card 1")

	# Etappe 17: der Alpha-Kern entfällt; Evolution = Waffe Rang 5 + Relikt,
	# angeboten im Boss-Kokon (1 aus 3).
	world.reset_run()
	evo = world.evolution
	_quiet(world)
	_check(world._drop_alpha_core(swarm.position + Vector3(8, 0, 0)) == null and world.alpha_pickups.is_empty(), "No Alpha-Kern drops any more")
	var king: Variant = world._spawn_boss(swarm.position + Vector3(20, 0, 0))
	king.health = -1.0
	world.step(0.01)
	_check(world.boss == null and world.alpha_pickups.is_empty() and world.model.bosses == 1, "Bog King drops no Alpha-Kern")
	evo.debug_grant("saeurespucker", "legendary")
	evo.debug_grant("saeurespucker", "common")
	_check(evo.rank("saeurespucker") == 5 and evo.evolution_ready().is_empty(), "Rank 5 alone is not enough")
	evo.debug_grant("aetzdruese")
	_check(evo.evolution_ready() == ["aetzflut"], "Rank 5 + Ätzdrüse makes Ätzflut ready")
	var chest: Dictionary = evo.open_chest("boss")
	_check(bool(chest.pick) and evo.chest_offers.size() == 3 and evo.chest_offers[0][0] == "aetzflut", "Boss-Kokon offers the ready evolution")
	_check(world.choosing(), "An open Boss-Kokon choice holds the world")
	world.choose_mutation(0)
	_check(not world.choosing() and evo.chest_offers.is_empty(), "Card choice takes the Boss-Kokon item")
	world.step(0.01)
	_check(evo.evolutions.has("aetzflut") and evo.rank("aetzflut") == 1 and evo.rank("saeurespucker") == 0, "Ätzflut replaces Säurespucker")
	_check(world.attack_forms.rank("aetzflut") == 1 and world.attack_forms.rank("saeurespucker") == 0, "Evolution reaches AttackForms")
	_check(world.evolve_flash > 0.0 and hud.evolve_name == "Ätzflut", "Evolution banner")

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
	_check(is_equal_approx(world.loot.total(0), TUNING.HUNTER_BIOMASS * evo.biomass_multiplier()), "Ranged kill leaves full biomass as crystals")
	world.collect_loot_now()
	_check(evo.dna == 20 and world.loot.count() == 0 and world.model.kills == 1, "Ranged kill gives DNA and biomass once")
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
	# Stage 15: brawl result/pause buttons are touch-sized and separate; the
	# pause panel restarts the run (hud_overlays draws on these rects).
	if brawl:
		var result_rects: Array = [hud._action_rect(), hud._hub_rect(), hud._share_rect()]
		for i in result_rects.size():
			_check(result_rects[i].size.x >= 96.0 and result_rects[i].size.y >= 96.0, "Result button %d is at least TOUCH_MIN" % i)
			for j in range(i + 1, result_rects.size()):
				_check(not result_rects[i].intersects(result_rects[j]), "Result buttons %d/%d do not overlap" % [i, j])
		_check(hud._restart_rect().size == Vector2.ZERO, "No pause restart button on the result screen")
		_check(hud._pause_rect().size.x >= 96.0 and hud._pause_rect().size.y >= 96.0, "Pause button is at least TOUCH_MIN")
	SESSION.last_result = {}
	if brawl:
		world.reset_run()
		world.toggle_pause()
		world.step(0.01)
		var pause_rects: Array = [hud._action_rect(), hud._restart_rect(), hud._hub_rect()]
		for i in pause_rects.size():
			_check(pause_rects[i].size.y >= 96.0, "Pause button %d is at least TOUCH_MIN" % i)
			for j in range(i + 1, pause_rects.size()):
				_check(not pause_rects[i].intersects(pause_rects[j]), "Pause buttons %d/%d do not overlap" % [i, j])
		var restarts := [0]
		if hud.restart_requested.is_connected(scene._restart):
			hud.restart_requested.disconnect(scene._restart)
		hud.restart_requested.connect(func(): restarts[0] += 1)
		hud._press(-2, hud._restart_rect().get_center())
		_check(restarts[0] == 1, "Pause NEUSTART requests a restart")

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS run_config: config, signature, slots, pool, reroll/banish/skip, difficulty, stats with rarity, boss-chest evolution, ranged kill, RunStats, result buttons")
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
