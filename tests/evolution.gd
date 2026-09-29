extends SceneTree

const EVOLUTION = preload("res://scripts/evolution.gd")
const TUNING = preload("res://scripts/tuning.gd")
const STATS = preload("res://scripts/progression/stats.gd")
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var evo = EVOLUTION.new()
	evo.rng.seed = 19
	# Level curve (stage 28 addendum): 60 + 25 L + 6 L², first level at 60 DNA.
	check(evo.threshold() == 60, "First level at 60 DNA (%d)" % evo.threshold())
	evo.level = 3
	check(evo.threshold() == 60 + 75 + 54, "Level curve 60 + 25 L + 6 L² (%d)" % evo.threshold())
	evo.level = 0
	evo.earn(59)
	check(evo.offers.is_empty(), "No early offer")
	evo.earn(1)
	check(evo.offers.size() == 3, "Three offers at threshold")
	check(evo.offers[0][0] != evo.offers[1][0] and evo.offers[1][0] != evo.offers[2][0] and evo.offers[0][0] != evo.offers[2][0], "Unique offers")
	for offer in evo.offers:
		# Etappe 17: Level geben nur Werte, jede Karte mit Seltenheit.
		check(evo.kind_of(offer[0]) == "trait", "Level offer is a stat (%s)" % offer[0])
		check(offer.size() >= 4 and ["common", "uncommon", "rare", "epic", "legendary"].has(offer[3]), "Offer has a rarity")
	check(not evo.choose(-1) and not evo.choose(3), "Reject invalid selection")
	evo.earn(1000000)
	# User decision 28.09.2026: 6 distinct stat slots with 5 ranks each = 30 picks;
	# once 6 are owned, offers only raise owned stats.
	var picks := 0
	while not evo.offers.is_empty() and not evo.offer_overdrive and picks < 200:
		if evo.slots_used("trait") >= 6:
			for offer in evo.offers:
				check(evo.rank(offer[0]) > 0 and evo.rank(offer[0]) < 5, "Full stat slots: only rank-ups of owned stats (%s)" % offer[0])
		check(evo.choose(0), "Queued level remains selectable")
		check(evo.slots_used("trait") <= 6, "Never more than 6 distinct stats")
		picks += 1
	check(picks == 30, "30 stat picks until complete (%d)" % picks)
	check(evo.slot_limit("trait") == 6 and evo.slots_used("trait") == 6, "6 stat slots")
	check(evo.complete(), "All stats complete without deadlock")
	check(evo.slots_used("attack") == 0, "Levels never give weapons")
	for id in evo.ranks:
		check(evo.rank(id) == 5, "Rank cap 5 (%s)" % id)
	# Stage 31 A: everything maxed -> the next level is a 1-of-3 overdrive choice.
	check(evo.offer_overdrive and evo.offers.size() == 3 and evo.take_max_heals() == 0, "Complete: level-up opens the overdrive choice (%s)" % str(evo.offers))
	for offer in evo.offers:
		check(str(offer[0]).begins_with("od_") and evo.kind_of(offer[0]) == "overdrive" and str(offer[2]).contains("gesamt"), "Overdrive card id/kind/total (%s)" % str(offer))
	# Picking overdrive cards until every one is capped, then the level-ups heal
	# (all start just below their cap: each pick caps one).
	for entry in EVOLUTION.OVERDRIVE:
		evo.overdrive[entry.id] = EVOLUTION.overdrive_cap(entry.id) - 0.001
	var od_picks := 0
	while evo.offer_overdrive and od_picks < 2000:
		check(evo.choose(od_picks % evo.offers.size()), "Overdrive card selectable")
		od_picks += 1
	for entry in EVOLUTION.OVERDRIVE:
		var cap: float = EVOLUTION.overdrive_cap(entry.id)
		check(is_equal_approx(evo.overdrive_amount(entry.id), cap), "Overdrive %s reaches exactly its cap (%.4f / %.2f)" % [entry.id, evo.overdrive_amount(entry.id), cap])
	check(od_picks == EVOLUTION.OVERDRIVE.size(), "One pick per overdrive until every cap (%d)" % od_picks)
	var heals: int = evo.take_max_heals()
	check(heals > 0 and evo.take_max_heals() == 0 and evo.dna < evo.threshold() and evo.offers.is_empty(), "Every overdrive capped: levels become leader heals (%d)" % heals)
	var level_before: int = evo.level
	evo.earn(evo.threshold())
	check(evo.level == level_before + 1 and evo.take_max_heals() == 1 and evo.offers.is_empty(), "A maxed level-up heals once every overdrive is capped")
	check(not evo.open_shrine() and evo.take_max_heals() == 1, "A shrine with everything capped heals too")
	_overdrive_rules()
	_seal_rules()
	# Reroll/banish/skip at full slots never bring a new stat.
	var full = EVOLUTION.new()
	full.rng.seed = 23
	full.rerolls = 20
	full.banishes = 2
	full.skips = 2
	for id in ["bite", "crit", "haste", "armor", "brood", "speed"]:
		full.ranks[id] = 2
	full.earn(1000)
	var owned := ["bite", "crit", "haste", "armor", "brood", "speed"]
	for round_index in 20:
		for offer in full.offers:
			check(owned.has(offer[0]), "Full slots: reroll only rank-ups (%s)" % offer[0])
		full.reroll()
	full.banish(0)
	for offer in full.offers:
		check(owned.has(offer[0]), "Full slots: banish refill only rank-ups (%s)" % offer[0])
	full.skip()
	for offer in full.offers:
		check(owned.has(offer[0]), "Full slots: next level after skip only rank-ups (%s)" % offer[0])
	# Fewer than three upgradable stats: fewer cards.
	var few = EVOLUTION.new()
	few.rng.seed = 5
	for id in ["bite", "crit", "haste", "armor", "brood"]:
		few.ranks[id] = 5
	few.ranks["speed"] = 3
	few.earn(few.threshold())
	check(few.offers.size() == 1 and few.offers[0][0] == "speed", "One upgradable stat: one card (%s)" % str(few.offers))
	evo = EVOLUTION.new()
	for id in ["bite", "rally", "brood", "magnet", "armor", "evade"]:
		evo.ranks[id] = 5
	var bite: float = 1.0 + 5.0 * float(STATS.definition("bite").step)
	var rally: float = 1.0 + 5.0 * float(STATS.definition("rally").step)
	check(is_equal_approx(evo.damage_multiplier(false), bite), "Biss je Rang (%.3f)" % evo.damage_multiplier(false))
	check(is_equal_approx(evo.damage_multiplier(true), bite * rally), "Rudelinstinkt je Rang bei Rally")
	check(is_equal_approx(evo.harvest_multiplier(), 1.0 + 5.0 * float(STATS.definition("brood").step)), "Brutrate: biomass per collected crystal")
	check(is_equal_approx(evo.magnet_multiplier(), 1.0 + 5.0 * float(STATS.definition("magnet").step)), "Lockduft: magnet radius")
	check(is_equal_approx(evo.biomass_multiplier(), 1.0), "Future biomass only from the strain")
	var armor: float = 5.0 * float(STATS.definition("armor").step)
	var evade: float = 5.0 * float(STATS.definition("evade").step)
	check(evo.loss_after_armor(100, false) == ceili(100.0 * (1.0 - armor - evade) - 0.0001) and evo.loss_after_armor(100, true) == ceili(100.0 * (1.0 - armor) - 0.0001), "Conditional armor (%d/%d)" % [evo.loss_after_armor(100, false), evo.loss_after_armor(100, true)])
	check(evo.loss_after_armor(1, false) == 1, "No invulnerability")
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	var world: Variant = scene.get_node("HuntWorld")
	var swarm: Variant = scene.get_node("Swarm")
	var hud: Variant = scene.get_node("HUD/Controls")
	world.set_process(false)
	swarm.set_process(false)
	world.reset_run()
	# Etappe 16: DNA arrives with the collected crystals.
	world._kill_prey(world.prey[0])
	check(world.evolution.dna == 0, "No DNA before the crystals arrive")
	world.collect_loot_now()
	check(world.evolution.dna == 10 and not world.choosing(), "Prey DNA exactly once")
	world.collect_loot_now()
	check(world.evolution.dna == 10, "Collected crystals never pay twice")
	hud.movement_vector = Vector2.ONE
	# The second prey's 10 DNA completes the (60 DNA) first level.
	world.evolution.dna = world.evolution.threshold() - 10
	world._kill_prey(world.prey[0])
	world.drop_loot(Vector3(40, 0, 0), 5.0)
	world.collect_loot_now()
	check(world.choosing() and hud.movement_vector == Vector2.ZERO, "Second kill opens and clears input")
	world.drop_loot(Vector3(40, 0, 0), 5.0)
	var before: float = world.model.elapsed
	var biomass: float = world.loot.total(0)
	var spawn_before: float = world.hunter_clock
	world.step(30)
	check(world.model.elapsed == before and world.hunter_clock == spawn_before and world.loot.total(0) == biomass, "Entire world frozen")
	world.toggle_pause()
	world.choose_mutation(0)
	check(world.evolution.level == 0, "Manual pause blocks selection")
	world.toggle_pause()
	hud._press(3, hud._mutation_rect(0).get_center())
	check(world.evolution.level == 1 and not world.choosing(), "Touch selection")
	world._kill_prey(world.prey[0])
	check(is_equal_approx(world.loot.total(0) - biomass, TUNING.CORPSE_BIOMASS), "Prey biomass without multiplier")
	world.collect_loot_now()
	world._award_dna(world.evolution.threshold())
	var key := InputEventKey.new()
	key.keycode = KEY_1
	key.pressed = true
	hud._input(key)
	check(world.evolution.level == 2, "Keyboard selection")
	world.reset_run()
	# Etappe 17: a fresh run (also without RunConfig) keeps only its start weapon.
	var fresh: Dictionary = world.evolution.ranks
	var start_only: bool = fresh.size() == 1 and int(fresh.get(world.evolution.signature, 0)) == world.evolution.SIGNATURE_START_RANK
	check(world.evolution.level == 0 and start_only and world.evolution.dna == 0 and not world.choosing(), "Restart clears all evolution (%s)" % [fresh])
	world.evolution.ranks["brood"] = 3
	world.drop_loot(swarm.position, 12)
	for tick in 30:
		world.step(0.05)
	check(is_equal_approx(world.model.consumed_biomass, 12.0 * (1.0 + 3.0 * float(STATS.definition("brood").step))), "Brutrate: more biomass per collected crystal (%.2f)" % world.model.consumed_biomass)
	world.reset_run()
	world.model.population = 250
	swarm.set_population(250)
	var hunter: Variant = world._spawn_hunter(Vector3.ZERO)
	hunter.state = hunter.State.CHASE
	hunter.health = 0.01
	world.step(0.01)
	world.collect_loot_now()
	world.collect_loot_now()
	check(world.evolution.dna == 20 and not world.choosing() and world.hunters.is_empty(), "Hunter kill awards DNA once (below the 60 DNA first level)")
	# Every stat slot maxed: a level-up heals the leader (+20 % max LP) instead of a card.
	world.reset_run()
	for id in ["bite", "crit", "haste", "armor", "brood", "speed"]:
		world.evolution.ranks[id] = 5
	# Stage 31 A: the level-up opens the overdrive choice; below 60 % LP its last
	# card is "Anführer heilen" (+20 % max LP).
	world.model.leader_hp = 10
	var level_now: int = world.evolution.level
	world._award_dna(world.evolution.threshold())
	var od_offers: Array = world.evolution.offers
	check(world.choosing() and world.evolution.offer_overdrive and od_offers.size() == 3 and str(od_offers[2][0]) == "od_heal", "Maxed level-up: overdrive choice with heal card (%s)" % str(od_offers))
	var heal_lp: int = int(round(float(world.model.leader_max_hp) * world.evolution.MAX_HEAL_SHARE))
	world.choose_mutation(2)
	world._step_arsenal_world(0.01)
	check(not world.choosing() and world.evolution.level == level_now + 1 and world.model.leader_hp == mini(world.model.leader_max_hp, 10 + heal_lp), "Heal card heals the leader (%d LP, expected %d)" % [world.model.leader_hp, 10 + heal_lp])
	check(world.leader_heal_shown >= heal_lp and world.hud.hint.contains("LP"), "Heal card shows the heal (+%d, '%s')" % [world.leader_heal_shown, world.hud.hint])
	# Full LP: three bonuses, no heal card; a picked "vigor" overdrive raises max LP.
	world.model.leader_hp = world.model.leader_max_hp
	world._award_dna(world.evolution.threshold())
	check(world.evolution.offers.size() == 3 and not world.evolution.offers.any(func(o): return str(o[0]) == "od_heal"), "Healthy leader: no heal card (%s)" % str(world.evolution.offers))
	var max_before: int = world.model.leader_max_hp
	world.evolution.offers = [world.evolution.overdrive_card("vigor", "legendary")]
	world.choose_mutation(0)
	check(world.model.leader_max_hp == max_before + int(round(float(TUNING.LEADER_HP) * 0.12)), "Overdrive vigor wired into leader max LP (%d -> %d)" % [max_before, world.model.leader_max_hp])
	world.reset_run()
	# Stage 09 lone start: the modifier checks below use a 25-strong swarm.
	world.model.population = 25
	swarm.set_population(25, false)
	world.evolution.ranks["bite"] = 3
	world.evolution.ranks["rally"] = 3
	swarm.rally_pressed = true
	hunter = world._spawn_hunter(Vector3.ZERO)
	hunter.state = hunter.State.RECOVERY
	hunter.remaining = 10
	# Melee counts biting animals: the whole swarm surrounds the hunter.
	for unit in swarm.units:
		unit.position = Vector3.ZERO
	var health: float = hunter.health
	world.step(0.1)
	var expected: float = 4.0 * 1.55 * (1.0 + 3.0 * float(STATS.definition("bite").step)) * (1.0 + 3.0 * float(STATS.definition("rally").step)) * 0.1
	check(is_equal_approx(health - hunter.health, expected), "Damage modifier wired into combat (%.3f / %.3f)" % [health - hunter.health, expected])
	world.reset_run()
	world.model.population = 25
	swarm.set_population(25, false)
	world.evolution.ranks["armor"] = 5
	world.evolution.ranks["evade"] = 5
	hunter = world._spawn_hunter(Vector3(3, 0, 0))
	hunter.state = hunter.State.WARNING
	hunter.remaining = 0.01
	hunter.attack_center = Vector3.ZERO
	hunter.attack_power = 20
	# Hits count per animal: gather the whole swarm inside the ring.
	for unit in swarm.units:
		unit.position = Vector3.ZERO
	world.step(0.02)
	var kept: int = 25 - ceili(20.0 * (1.0 - 5.0 * float(STATS.definition("armor").step) - 5.0 * float(STATS.definition("evade").step)) - 0.0001)
	check(world.model.population == kept, "Armor modifier wired into incoming hit (%d, expected %d)" % [world.model.population, kept])
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
	else:
		print("PASS evolution: stat offers with rarity, 5 ranks, modifiers, overdrive, seals, freeze, input, persistence, reset, hunter reward")
		quit(0)


# A run with every stat at rank 5 (6 slots) and `dna` DNA on hand.
func _maxed(seed_value: int) -> Variant:
	var evo = EVOLUTION.new()
	evo.rng.seed = seed_value
	for id in ["bite", "crit", "haste", "armor", "brood", "speed"]:
		evo.ranks[id] = 5
	return evo


# Stage 31 A: Limit Break ("Überladung").
func _overdrive_rules() -> void:
	var evo = _maxed(41)
	check(evo.complete(), "Six stats at rank 5 = complete")
	var plain_damage: float = evo.damage_multiplier(false)
	var plain_cooldown: float = evo.cooldown_scale()
	var plain_loss: int = evo.loss_after_armor(1000, false)
	evo.earn(evo.threshold())
	check(evo.offer_overdrive and evo.offers.size() == 3 and evo.offer_source == "level", "Level-up opens 3 overdrive cards")
	# Rarity scales the value (stats.RARITY_FACTOR); values add up.
	evo.offers = [evo.overdrive_card("bite", "common")]
	check(evo.choose(0) and is_equal_approx(evo.overdrive_amount("bite"), 0.02) and evo.level == 1, "Common Biss overdrive +2 %% (%.3f)" % evo.overdrive_amount("bite"))
	evo.earn(evo.threshold())
	evo.offers = [evo.overdrive_card("bite", "rare")]
	check(str(evo.offers[0][2]).contains("gesamt +5 %"), "Card shows the running total (%s)" % str(evo.offers[0][2]))
	evo.choose(0)
	check(is_equal_approx(evo.overdrive_amount("bite"), 0.05), "Overdrive values add up (%.3f)" % evo.overdrive_amount("bite"))
	check(is_equal_approx(evo.damage_multiplier(false), plain_damage * 1.05), "Overdrive Biss feeds damage_multiplier")
	# Caps: +50 % / −30 %; the last pick is clamped and the stat leaves the pool.
	evo.overdrive["bite"] = 0.49
	evo.earn(evo.threshold())
	evo.offers = [evo.overdrive_card("bite", "legendary")]
	check(str(evo.offers[0][2]).contains("(max.)"), "Capped card says max. (%s)" % str(evo.offers[0][2]))
	evo.choose(0)
	check(is_equal_approx(evo.overdrive_amount("bite"), EVOLUTION.OVERDRIVE_CAP) and not evo.overdrive_candidates().has("bite"), "Biss capped at +50 %")
	evo.overdrive["haste"] = 0.29
	check(is_equal_approx(evo.overdrive_gain("haste", "epic"), 0.01) and is_equal_approx(EVOLUTION.overdrive_cap("haste"), 0.3), "Reductions capped at −30 %")
	# Every effect is wired into its multiplier.
	var wired = _maxed(3)
	var before := {"cool": wired.cooldown_scale(), "area": wired.area_scale(), "speed": wired.speed_multiplier(), "magnet": wired.magnet_multiplier(),
		"harvest": wired.harvest_multiplier(), "steal": wired.lifesteal(), "hp": wired.leader_hp_bonus(100)}
	for id in ["haste", "reach", "speed", "magnet", "brood", "armor", "lifesteal", "vigor"]:
		wired.overdrive[id] = 0.1
	check(is_equal_approx(wired.cooldown_scale(), before.cool * 0.9), "Overdrive Angriffstempo feeds cooldown_scale")
	check(is_equal_approx(wired.area_scale(), before.area * 1.1), "Overdrive Reichweite feeds area_scale")
	check(is_equal_approx(wired.speed_multiplier(), before.speed * 1.1), "Overdrive Tempo feeds speed_multiplier")
	check(is_equal_approx(wired.magnet_multiplier(), before.magnet * 1.1), "Overdrive Magnet feeds magnet_multiplier")
	check(is_equal_approx(wired.harvest_multiplier(), before.harvest * 1.1), "Overdrive Brutrate feeds harvest_multiplier")
	check(is_equal_approx(wired.lifesteal(), before.steal + 0.1), "Overdrive Lebensraub feeds lifesteal")
	check(wired.leader_hp_bonus(100) == before.hp + 10, "Overdrive Anführer-LP feeds leader_hp_bonus")
	check(wired.loss_after_armor(1000, false) == ceili(float(plain_loss) * 0.9 - 0.0001), "Overdrive Rüstung reduces losses (%d / %d)" % [wired.loss_after_armor(1000, false), plain_loss])
	check(plain_cooldown > 0.0, "Cooldown scale positive")
	# Reroll and skip work; banish is disabled for overdrive cards.
	var flow = _maxed(7)
	flow.rerolls = 3
	flow.banishes = 3
	flow.skips = 2
	flow.earn(flow.threshold() + flow.threshold() * 4)
	var first: Array = flow.offers.map(func(o): return o[0])
	check(flow.reroll() and flow.offer_overdrive and flow.offers.size() == 3 and flow.rerolls == 2, "Overdrive reroll")
	for offer in flow.offers:
		check(not first.has(offer[0]), "Reroll brings fresh overdrive cards (%s)" % offer[0])
	check(not flow.banish(0) and flow.banishes == 3, "Overdrive cards cannot be banished")
	var dna_before: int = flow.dna
	var threshold_before: int = flow.threshold()
	check(flow.skip() and flow.dna == dna_before - threshold_before and flow.skips == 1 and flow.overdrive.is_empty(), "Overdrive skip spends the level without a bonus")
	check(flow.offer_overdrive and flow.offers.size() == 3, "Next overdrive choice after the skip")
	# Heal card only while the leader is below 60 % LP (it takes the third place).
	var hurt = _maxed(9)
	hurt.leader_share_source = func() -> float: return 0.4
	hurt.earn(hurt.threshold())
	check(hurt.offers.size() == 3 and str(hurt.offers[2][0]) == "od_heal" and hurt.kind_of("od_heal") == "overdrive", "Hurt leader: heal card (%s)" % str(hurt.offers))
	check(hurt.choose(2) and hurt.take_max_heals() == 1 and hurt.overdrive.is_empty(), "Heal card queues one leader heal")
	var fine = _maxed(9)
	fine.leader_share_source = func() -> float: return 0.6
	fine.earn(fine.threshold())
	check(not fine.offers.any(func(o): return str(o[0]) == "od_heal"), "No heal card at 60 % LP")
	# Shrine: free overdrive choice (at least rare); while another choice is
	# open it waits and opens after that one.
	var shrine = _maxed(11)
	check(shrine.open_shrine() and shrine.offer_overdrive and shrine.offer_source == "shrine", "Shrine opens overdrive when complete")
	for offer in shrine.offers:
		check(STATS.rarity_at_least(str(offer[3]), "rare"), "Shrine overdrive at least rare (%s)" % str(offer))
	var level_now: int = shrine.level
	shrine.rerolls = 1
	check(shrine.reroll() and shrine.offer_source == "shrine" and shrine.offer_overdrive, "Shrine overdrive reroll stays a shrine choice")
	check(shrine.choose(0) and shrine.level == level_now and shrine.overdrive.size() == 1, "Shrine overdrive costs no level")
	shrine.earn(shrine.threshold())
	check(shrine.offer_overdrive and not shrine.open_shrine() and shrine.queued_shrines == 1, "Shrine during an open choice is queued")
	shrine.choose(0)
	check(shrine.offer_source == "shrine" and shrine.offer_overdrive and shrine.queued_shrines == 0, "Queued shrine opens after the choice")


# Stage 31 B: seals.
func _seal_rules() -> void:
	var evo = EVOLUTION.new()
	evo.rng.seed = 5
	evo.chest_rng.seed = 6
	evo.configure({"signature_attack": "rudelbiss", "sealed": ["bite", "crit", "sporenwolke", "rudelbiss", "zaehe_haut", "scharfe_zaehne"]})
	check(not evo.is_sealed("rudelbiss") and not evo.seals_ignored, "Start weapon can never be sealed")
	check(evo.is_sealed("bite") and evo.is_sealed("sporenwolke") and evo.is_sealed("zaehe_haut"), "Seals of every kind stored (%s)" % str(evo.sealed))
	var sealed := ["bite", "crit", "sporenwolke", "zaehe_haut", "scharfe_zaehne"]
	for round_index in 60:
		evo.earn(evo.threshold())
		for offer in evo.offers:
			check(not sealed.has(offer[0]), "Level offer never sealed (%s)" % offer[0])
		evo.choose(0)
	for kind in ["start", "map", "elite", "gold", "boss"]:
		for round_index in 25:
			var rolled: Dictionary = evo.roll_chest(kind)
			for item in rolled.items:
				check(not sealed.has(String(item.id)), "Cocoon %s never offers sealed %s" % [kind, item.id])
	var shrine = EVOLUTION.new()
	shrine.configure({"sealed": ["bite", "crit", "haste"]})
	for round_index in 20:
		shrine.open_shrine()
		for offer in shrine.offers:
			check(not ["bite", "crit", "haste"].has(offer[0]), "Shrine offer never sealed (%s)" % offer[0])
		shrine.offers.clear()
	# Fewer than three candidates of a kind: that kind's seals are ignored.
	var few = EVOLUTION.new()
	few.configure({"pool": ["bite", "crit", "haste", "armor"], "signature_attack": "rudelbiss",
		"sealed": ["bite", "crit", "giftbiss", "klauenwirbel", "schallbrueller"]})
	check(few.seals_ignored and not few.is_sealed("bite") and not few.is_sealed("giftbiss"), "Too few candidates: seals of that kind ignored (%s)" % str(few.sealed))
	var ok = EVOLUTION.new()
	ok.configure({"signature_attack": "rudelbiss", "sealed": ["giftbiss", "klauenwirbel"]})
	check(not ok.seals_ignored and ok.is_sealed("giftbiss") and ok.is_sealed("klauenwirbel"), "Three weapons left: seals kept")
	var start: Dictionary = ok.roll_chest("start")
	var fresh: Array = start.items.filter(func(i): return String(i.type) == "weapon" and int(i.from) == 0).map(func(i): return String(i.id))
	check(fresh.size() == 2 and fresh.has("sporenwolke") and fresh.has("schallbrueller") and not start.items.any(func(i): return ["giftbiss", "klauenwirbel"].has(String(i.id))), "Start cocoon: only unsealed new weapons (%s)" % str(start.items.map(func(i): return i.id)))
