extends SceneTree

# Stage 33 - Mutationskerne: catalogue, start offer at the first step, core
# choice after an endboss kill, at most 3 per run, pause while choosing,
# unlock/seal filters and the effect of every core on its multiplier or hook.

const CORES = preload("res://scripts/progression/cores.gd")
const EVOLUTION = preload("res://scripts/evolution.gd")
const RUN_MODEL = preload("res://scripts/run_model.gd")
const TUNING = preload("res://scripts/tuning.gd")
const DT := 0.05
var failures: Array[String] = []
var world: Variant
var swarm: Variant
var main: Variant


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_catalogue()
	_evolution_rules()
	_effects()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	world = main.get_node("HuntWorld")
	swarm = main.get_node("Swarm")
	main.set_process(false)
	world.set_process(false)
	swarm.set_process(false)
	_world_flow()
	_world_hooks()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS cores: 12 cores, start offer, endboss offer, max 3, pause, unlock/seal filter, multipliers and hooks")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _catalogue() -> void:
	_check(CORES.ORDER.size() == 12 and CORES.CORES.size() == 12, "12 cores in the catalogue")
	for id in CORES.ORDER:
		var d: Dictionary = CORES.definition(id)
		_check(String(d.get("plus", "")) != "" and String(d.get("minus", "")) != "" and not (d.get("effects", {}) as Dictionary).is_empty(), "%s has plus, minus and effects" % id)
		var card: Array = CORES.card(id)
		_check(card.size() == 5 and card[0] == id and card[3] == "legendary" and String(card[4].kind) == "core", "%s card = [id, name, desc, legendary, {kind: core}]" % id)
		_check(String(card[2]).begins_with("+ ") and String(card[2]).contains("\n− "), "%s text has a + and a − line" % id)
	_check(CORES.default_unlocked().size() == 6 and CORES.default_unlocked()[0] == CORES.ORDER[0], "Default: the first six are unlocked")


func _evolution_rules() -> void:
	var evo = EVOLUTION.new()
	evo.configure({"seed": 7})
	_check(not evo.cores_enabled, "Without cores_unlocked the automatic offers stay off")
	_check(evo.cores_unlocked.size() == 6, "Missing cores_unlocked -> first six")
	_check(evo.offer_core() and evo.core_offers.size() == 3, "offer_core opens 1 of 3")
	for card in evo.core_offers:
		_check(CORES.default_unlocked().has(String(card[0])), "Offer only from unlocked cores (%s)" % card[0])
	_check(not evo.offer_core(), "No second offer while one is open")
	var first: String = evo.choose_core(0)
	_check(first != "" and evo.cores == [first] and evo.core_offers.is_empty(), "choose_core takes the card")
	for index in 5:
		if evo.offer_core():
			for card in evo.core_offers:
				_check(not evo.cores.has(String(card[0])), "Taken cores are not offered again")
			evo.choose_core(0)
	_check(evo.cores.size() == CORES.MAX_PER_RUN, "At most 3 cores per run (got %d)" % evo.cores.size())
	_check(not evo.offer_core() and evo.core_offers.is_empty(), "No offer with 3 cores")
	_check(not evo.add_core("letzter_biss") or evo.cores.size() <= 3, "add_core respects the maximum")
	# Unlock + seal filter.
	var sealed = EVOLUTION.new()
	sealed.configure({"seed": 3, "cores_unlocked": ["rudelgeist", "giftblut", "panzerherz", "flutfresser", "letzter_biss"], "sealed": ["giftblut", "flutfresser"]})
	_check(sealed.cores_enabled, "cores_unlocked in the RunConfig enables the offers")
	_check(sealed.core_sealed == ["giftblut", "flutfresser"], "Sealed core ids are kept (%s)" % str(sealed.core_sealed))
	_check(sealed.core_candidates() == ["rudelgeist", "panzerherz", "letzter_biss"], "Candidates = unlocked minus sealed (%s)" % str(sealed.core_candidates()))
	for probe_seed in 10:
		var probe = EVOLUTION.new()
		probe.configure({"seed": probe_seed, "cores_unlocked": ["rudelgeist", "giftblut", "panzerherz", "flutfresser", "letzter_biss"], "sealed": ["giftblut", "flutfresser"]})
		probe.offer_core()
		for card in probe.core_offers:
			_check(not ["giftblut", "flutfresser", "hungrige_brut"].has(String(card[0])), "Sealed/locked core never offered (%s)" % card[0])
	var too_many = EVOLUTION.new()
	too_many.configure({"cores_unlocked": ["rudelgeist", "giftblut", "panzerherz"], "sealed": ["giftblut"]})
	_check(too_many.core_sealed.is_empty() and too_many.seals_ignored, "Seals ignored when fewer than 3 cores would stay open")
	# Other choices wait while the core choice is open.
	var shrine = EVOLUTION.new()
	shrine.configure({})
	shrine.offer_core()
	_check(not shrine.open_shrine() and shrine.offers.is_empty(), "A shrine does not open over a core choice")


func _with(id: String) -> Variant:
	var evo = EVOLUTION.new()
	evo.configure({})
	evo.add_core(id)
	return evo


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.001


func _effects() -> void:
	var base = EVOLUTION.new()
	base.configure({})
	_check(_near(base.melee_multiplier(false), base.damage_multiplier(false)) and _near(base.form_multiplier(), base.damage_multiplier(false)) and _near(base.major_target_factor(), 1.0), "Without cores every multiplier is neutral")
	var e = _with("hungrige_brut")
	_check(_near(e.harvest_multiplier(), base.harvest_multiplier() / 0.7), "Hungrige Brut: -30 % biomass per division")
	_check(e.loss_after_armor(30, false) > base.loss_after_armor(30, false), "Hungrige Brut: more losses per hit (%d > %d)" % [e.loss_after_armor(30, false), base.loss_after_armor(30, false)])
	e = _with("rudelgeist")
	_check(_near(e.melee_multiplier(false), 1.4) and _near(e.form_multiplier(), 0.9), "Rudelgeist: melee +40 %, weapons -10 %")
	e = _with("arsenal_kult")
	_check(_near(e.melee_multiplier(false), 0.85) and _near(e.form_multiplier(), 1.3), "Arsenal-Kult: weapons +30 %, melee -15 %")
	e = _with("giftblut")
	e.debug_grant("crit", "legendary")
	var crit_before: float = e.stats.amount("crit")
	_check(_near(e.crit_chance(), crit_before - 0.05) and e.poison_crits(), "Giftblut: crit -5 %, poison clouds on")
	_check(_near(float(e.form_modifiers().poison_cloud), TUNING.CORE_POISON_BASE_CHANCE + e.crit_chance()), "Giftblut: cloud chance = base + crit")
	_check(_near(float(base.form_modifiers().poison_cloud), 0.0), "No clouds without Giftblut")
	e = _with("magnetsturm")
	_check(_near(e.magnet_multiplier(), 2.0) and _near(e.speed_multiplier(), 0.92) and _near(e.lure_interval(), 90.0), "Magnetsturm-Herz: magnet x2, Lockruf every 90 s, speed -8 %")
	e = _with("koenigsjaeger")
	_check(_near(e.melee_multiplier(false), 0.95) and _near(e.melee_multiplier(false) * e.major_target_factor(), 1.5), "Königsjäger: normal -5 %, bosses/elites +50 %")
	_check(_near(float(e.form_modifiers().major_damage), 1.5 / 0.95), "Königsjäger: weapon factor vs. bosses")
	e = _with("wandernde_brut")
	_check(_near(e.speed_multiplier(), 1.15) and _near(e.ability_cooldown_scale(), 0.75) and _near(e.rally_bonus_scale(), 0.5), "Wandernde Brut: speed +15 %, ability -25 %, rally bonus -50 %")
	e.mods.rally_damage = 1.2
	base.mods.rally_damage = 1.2
	_check(_near(e.damage_multiplier(true), 1.1) and _near(base.damage_multiplier(true), 1.2), "Wandernde Brut halves the rally damage bonus")
	base.mods.rally_damage = 1.0
	e = _with("panzerherz")
	_check(e.leader_hp_bonus(100) == 50 and _near(e.leader_hit_scale(), 0.7) and _near(e.heal_scale(), 0.5), "Panzerherz: +50 % LP, hits -30 %, heals -50 %")
	e = _with("flutfresser")
	_check(_near(e.brood_reward_multiplier(), 2.0) and _near(e.flood_offset(), -20.0), "Flutfresser: double brood crystals, flood 20 s earlier")
	e = _with("bernsteinblut")
	_check(_near(e.amber_multiplier(), 1.5) and _near(e.dna_multiplier(), 0.92) and e.chest_price() == int(round(float(base.chest_price()) * 0.8)), "Bernsteinblut: amber +50 %, cocoons -20 %, DNA -8 %")
	e = EVOLUTION.new()
	e.configure({"rerolls": 1, "skips": 0})
	var threshold_before: int = e.threshold()
	e.add_core("schwarmgedaechtnis")
	_check(e.rerolls == 3 and e.skips == 2 and e.threshold() == int(round(float(threshold_before) * 1.1)), "Schwarmgedächtnis: +2 rerolls/skips, level curve +10 %")
	e = _with("letzter_biss")
	_check(e.leader_hp_bonus(100) == -20 and _near(e.successor_share(0.8), 1.0) and _near(base.successor_share(0.8), 0.8), "Letzter Biss: successor 100 %, max LP -20 %")
	var model = RUN_MODEL.new()
	model.configure(5, 80.0, 100)
	model.successor_share = 1.0
	model.apply_hit(0, true, false, 200)
	_check(model.leader_max_hp == 100 and model.leader_hp == 100, "Successor share 1.0 keeps the full maximum (%d)" % model.leader_max_hp)


func _menu_config(extra: Dictionary = {}) -> Dictionary:
	var config := {"strain_id": "glutmaw", "seed": 4242, "cores_unlocked": CORES.ORDER.duplicate()}
	config.merge(extra, true)
	return config


func _world_flow() -> void:
	# No cores_unlocked (tests, F5): no automatic offer.
	world.config = {}
	world.reset_run()
	world.step(DT)
	_check(world.evolution.core_offers.is_empty() and world.model.elapsed > 0.0, "Config without cores_unlocked: no start offer")
	# Menu run: the start offer opens at the first step, before time runs.
	world.config = _menu_config()
	world.reset_run()
	world.step(DT)
	_check(world.evolution.core_offers.size() == 3 and world.choosing(), "Start: core choice 1 of 3 at the first step")
	_check(world.model.elapsed == 0.0, "Start offer opens before anything happens (elapsed %.2f)" % world.model.elapsed)
	world.step(DT)
	world.step(DT)
	_check(world.model.elapsed == 0.0, "The world pauses while the core choice is open")
	var picked: String = String(world.evolution.core_offers[1][0])
	world.choose_mutation(1)
	_check(world.evolution.cores == [picked] and not world.choosing(), "choose_mutation takes the core (%s)" % picked)
	_check(world.run_stats().get("cores", []) == [picked], "run_stats lists the cores")
	var picks: Array = world.run_stats().picks
	_check(not picks.is_empty() and String(picks[-1][1]) == "core" and String(picks[-1][2]) == picked, "The pick timeline records the core")
	world.step(DT)
	_check(world.model.elapsed > 0.0 and world.evolution.core_offers.is_empty(), "After the choice the run starts, no second start offer")
	# Endboss kill -> core choice (before the boss cocoon is picked up).
	for kill_index in 2:
		var arena: Node3D = main.get_node("Arena")
		world.apex_state = 0
		world.model.population = 200
		swarm.set_population(200, false)
		var apex: Variant = world.spawn_apex(arena.safe_spawn(swarm.position + Vector3(0, 0, -12), 3.0))
		apex.health = 0.0
		world.step(DT)
		_check(world.apex_state == 3, "Endboss %d defeated" % (kill_index + 1))
		_check(world.evolution.core_offers.size() >= 1 and world.evolution.chest_offers.is_empty(), "Endboss %d: core choice opens (before the boss cocoon)" % (kill_index + 1))
		world.choose_mutation(0)
		for index in 40:
			if world.evolution.chest_offers.size() > 0 or world.evolution.offers.size() > 0:
				world.evolution.chest_offers.clear()
				world.evolution.offers.clear()
			world.step(DT)
		world.apex_state = 0
	_check(world.evolution.cores.size() == 3, "Three cores after start + two endbosses (%d)" % world.evolution.cores.size())
	var apex3: Variant = world.spawn_apex(main.get_node("Arena").safe_spawn(swarm.position + Vector3(0, 0, -12), 3.0))
	apex3.health = 0.0
	world.step(DT)
	_check(world.evolution.core_offers.is_empty() and world.evolution.cores.size() == 3, "A fourth endboss opens no core choice (max 3)")
	# Sealed + locked cores never appear in the start offer.
	for seed_value in 6:
		world.config = _menu_config({"seed": seed_value, "cores_unlocked": ["rudelgeist", "panzerherz", "giftblut", "letzter_biss"], "sealed": ["giftblut"]})
		world.reset_run()
		world.step(DT)
		for card in world.evolution.core_offers:
			_check(["rudelgeist", "panzerherz", "letzter_biss"].has(String(card[0])), "Start offer respects unlock and seals (%s)" % card[0])


func _take_core(id: String, extra: Dictionary = {}) -> void:
	world.config = _menu_config(extra)
	world.reset_run()
	world.evolution.core_offers = [CORES.card(id)]
	world.core_start_pending = false
	world.choose_mutation(0)


func _world_hooks() -> void:
	# Flutfresser: the flood starts 20 s earlier.
	world.config = _menu_config()
	world.reset_run()
	world.core_start_pending = false
	var plain: float = world.world_flood_start()
	_take_core("flutfresser")
	_check(absf(world.world_flood_start() - (plain - 20.0)) < 0.01, "Flutfresser: world_flood_start %.0f -> %.0f" % [plain, world.world_flood_start()])
	# Panzerherz: leader LP +50 %, hits -30 %.
	world.config = _menu_config()
	world.reset_run()
	world.core_start_pending = false
	var hit_plain: int = world.leader_damage(null, "hunter")
	var hp_plain: int = world.model.leader_max_hp
	_take_core("panzerherz")
	world.step(DT)
	_check(world.model.leader_max_hp == hp_plain + int(round(float(TUNING.LEADER_HP) * 0.5)), "Panzerherz: leader max LP %d -> %d" % [hp_plain, world.model.leader_max_hp])
	_check(world.leader_damage(null, "hunter") <= hit_plain, "Panzerherz: a hit costs less LP")
	world.model.leader_hp = 10
	var gained: int = world._heal_leader(20)
	_check(gained == 10, "Panzerherz: heals are halved (got %d)" % gained)
	# Letzter Biss: the model's successor share follows the core.
	_take_core("letzter_biss")
	world.step(DT)
	_check(absf(world.model.successor_share - 1.0) < 0.001, "Letzter Biss: successor share 100 %")
	# Magnetsturm-Herz: a free Lockruf every 90 s.
	_take_core("magnetsturm")
	var lures_before: int = world.lures_collected
	world.core_lure_clock = 89.99
	world.step(DT)
	_check(world.lures_collected == lures_before + 1, "Magnetsturm-Herz: Lockruf after 90 s (%d)" % world.lures_collected)
	# Wandernde Brut: ability cooldown -25 %.
	world.config = _menu_config()
	world.reset_run()
	world.core_start_pending = false
	world.step(DT)
	var cooldown_plain: float = world.abilities.cooldown_total()
	_take_core("wandernde_brut")
	world.step(DT)
	_check(absf(world.abilities.cooldown_total() - cooldown_plain * 0.75) < 0.01, "Wandernde Brut: ability cooldown %.1f -> %.1f" % [cooldown_plain, world.abilities.cooldown_total()])
	# Königsjäger: weapons hit bosses harder.
	_take_core("koenigsjaeger")
	world.step(DT)
	_check(absf(float(world.attack_forms.modifiers.major_damage) - 1.5 / 0.95) < 0.01, "Königsjäger reaches the attack forms")
	# Giftblut: a crit leaves a poison cloud (attack forms).
	_take_core("giftblut")
	world.step(DT)
	var clouds: int = world.attack_forms.active_count("puffs")
	world.attack_forms.poison_cloud(swarm.position)
	_check(world.attack_forms.active_count("puffs") == clouds + 1, "Giftblut: poison cloud appears")
	_check(float(world.attack_forms.modifiers.poison_cloud) > 0.0, "Giftblut: cloud chance reaches the attack forms")
	# Bernsteinblut: 2 coins -> 3 Bernstein.
	_take_core("bernsteinblut")
	var amber_before: int = world.model.amber
	world._credit_loot({"crystals": 2, "biomass": 0.0, "dna": 0, "amber": 2, "bio_crystals": 0, "dna_crystals": 0, "coins": 2})
	_check(world.model.amber == amber_before + 3, "Bernsteinblut: 2 coins give 3 Bernstein (%d)" % (world.model.amber - amber_before))
