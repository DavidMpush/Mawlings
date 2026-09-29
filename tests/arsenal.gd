extends SceneTree

# Etappe 17 – Spur 2 (Arsenal): Waffenplätze, Rang +1, Relikt-Stapel, Urmutter,
# roll_chest() mit Mindest-Seltenheit, Evolution bereit, Relikt-Hooks.

const ARSENAL = preload("res://scripts/progression/arsenal.gd")
const STATS = preload("res://scripts/progression/stats.gd")
const EVOLUTION = preload("res://scripts/evolution.gd")
const FORMS = preload("res://scripts/attack_forms.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	_test_catalog()
	_test_slots_and_ranks()
	_test_relics()
	_test_relic_limits()
	_test_chests()
	_test_evolution()
	_test_hooks()
	_test_seals()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS arsenal: 10 weapons, 25 relics (5 tiers), 6 evolutions, slots + Urmutter, rank-ups, stacks, 1-of-3 for every cocoon kind with floors, refund, evolution ready, relic hooks")
	quit(0)


# Stage 31 B: sealed weapons and relics never come from any cocoon.
func _test_seals() -> void:
	var arsenal = ARSENAL.new()
	arsenal.sealed = ["giftbiss", "klauenwirbel", "zaehe_haut", "scharfe_zaehne", "flinke_beine", "koenigszahnkette"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for kind in ["start", "map", "elite", "gold", "boss"]:
		for round_index in 40:
			for item in arsenal.roll_chest(rng, 0.0, kind).items:
				_check(not arsenal.sealed.has(String(item.id)), "Sealed %s never in a %s cocoon" % [item.id, kind])
	# A sealed common relic falls through to the other common tiers / higher.
	for round_index in 20:
		var relic: Dictionary = arsenal._pick_relic(rng, "common", [], true)
		_check(relic.is_empty() or not arsenal.sealed.has(String(relic.id)), "_pick_relic skips sealed (%s)" % str(relic.get("id", "")))


func _test_catalog() -> void:
	# Etappe 17c: + Blutzahn (selten) = 21 Relikte; 17d: + 4 Fähigkeits-Relikte = 25.
	_check(ARSENAL.WEAPONS.size() == 10 and ARSENAL.RELICS.size() == 25 and ARSENAL.EVOLVED.size() == 6, "10 Waffen, 25 Relikte, 6 Evolutionen")
	var tiers := {}
	for entry in ARSENAL.RELICS:
		tiers[entry[3]] = int(tiers.get(entry[3], 0)) + 1
	# Etappe 28: Hungerstein, Witterungsnase, DNA-Splitter sind ungewöhnlich.
	_check(tiers.get("common", 0) == 3 and tiers.get("uncommon", 0) == 3 and tiers.get("rare", 0) == 11 and tiers.get("epic", 0) == 5 and tiers.get("legendary", 0) == 3, "Relikt-Seltenheiten 3/3/11/5/3: %s" % str(tiers))
	for entry in ARSENAL.RELICS:
		_check(STATS.RARITIES.has(entry[3]), "Relikt mit unbekannter Seltenheit: " + str(entry[0]))
	for rarity in STATS.RARITIES:
		_check(ARSENAL.RANK_GAIN.has(rarity), "Rangsprung fehlt für " + rarity)
	_check(ARSENAL.RANK_GAIN.uncommon == 1 and ARSENAL.RANK_GAIN.rare == 1 and ARSENAL.RANK_GAIN.epic == 2 and ARSENAL.RANK_GAIN.legendary == 3, "Rangsprung 1/1/1/2/3")
	for entry in ARSENAL.WEAPONS:
		_check(FORMS.FORMS.has(entry[0]) and FORMS.FORMS[entry[0]].ranks.size() == 5, "Waffe ohne 5 Ränge in attack_forms: " + str(entry[0]))
	for rule in ARSENAL.EVOLUTION_RULES:
		_check(ARSENAL.is_weapon(rule.base) and ARSENAL.is_relic(rule.partner) and ARSENAL.is_evolved(rule.id), "Evolutionsregel unvollständig: " + str(rule))
		_check(FORMS.FORMS.has(rule.id) and FORMS.FORMS[rule.id].base == rule.base and FORMS.FORMS[rule.id].requires == rule.partner, "attack_forms kennt die Regel nicht: " + str(rule.id))
	for id in ["klauenwirbel", "giftbiss", "schallbrueller"]:
		_check(ARSENAL.START_WEAPONS.has(id), "Neue Waffe im Start-Pool: " + id)


func _test_slots_and_ranks() -> void:
	var arsenal = ARSENAL.new()
	_check(arsenal.slot_limit() == 4, "4 Waffenplätze")
	for id in ["rudelbiss", "sporenwolke", "klauenwirbel", "giftbiss"]:
		_check(arsenal.grant(arsenal.weapon_item(id, "common")).applied, "Waffe %s passt in einen Platz" % id)
	_check(arsenal.slots_free() == 0 and arsenal.weapons().size() == 4, "Plätze voll")
	var extra: Dictionary = arsenal.grant(arsenal.weapon_item("schallbrueller", "common"))
	_check(not extra.applied and arsenal.rank("schallbrueller") == 0, "Fünfte Waffe ohne Platz wird abgelehnt")
	var up: Dictionary = arsenal.grant(arsenal.weapon_item("rudelbiss", "common"))
	_check(up.applied and up.from == 1 and up.to == 2 and arsenal.rank("rudelbiss") == 2, "Vorhandene Waffe: Rang +1")
	up = arsenal.grant(arsenal.weapon_item("rudelbiss", "legendary"))
	_check(up.to == 5 and arsenal.rank("rudelbiss") == 5, "Legendär +3, gedeckelt auf 5")
	_check(not arsenal.grant(arsenal.weapon_item("rudelbiss", "common")).applied, "Rang 5 steigt nicht weiter")
	# Urmutter: +1 Platz.
	arsenal.grant(arsenal.relic_item("urmutter"))
	_check(arsenal.slot_limit() == 5 and arsenal.grant(arsenal.weapon_item("schallbrueller", "epic")).applied and arsenal.rank("schallbrueller") == 2, "Urmutter gibt +1 Waffenplatz (episch = Rang 2)")
	# Volle Plätze: Kokon bietet nur Rang-Aufstiege vorhandener Waffen.
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in 300:
		var item: Dictionary = arsenal.roll_item(rng, 0.0)
		if item.type == "weapon":
			_check(arsenal.rank(item.id) > 0 and arsenal.rank(item.id) < 5, "Volle Plätze: nur Aufstieg vorhandener Waffen (%s)" % item.id)


func _test_relics() -> void:
	var arsenal = ARSENAL.new()
	var first: Dictionary = arsenal.grant(arsenal.relic_item("hungerstein"))
	var second: Dictionary = arsenal.grant(arsenal.relic_item("hungerstein"))
	_check(first.applied and second.from == 1 and second.to == 2 and arsenal.stacks("hungerstein") == 2, "Relikte stapeln")
	_check(arsenal.relic_item("urmutter").rarity == "legendary" and arsenal.relic_item("zaehe_haut").rarity == "common", "Relikt-Seltenheit ist fest")
	# Preis: 25 · CHEST_GROWTH^n, Glück −3 %/Punkt, Schlundherz −40 %.
	_check(arsenal.chest_price() == 25, "Erster Kokon kostet 25")
	arsenal.chests_opened = 2
	_check(arsenal.chest_price() == int(round(25.0 * ARSENAL.CHEST_GROWTH * ARSENAL.CHEST_GROWTH)), "Preis steigt je Kokon")
	_check(arsenal.chest_price(5.0) < arsenal.chest_price(0.0), "Glück macht Kokons billiger")
	arsenal.grant(arsenal.relic_item("schlundherz"))
	_check(arsenal.chest_price() == int(round(25.0 * ARSENAL.CHEST_GROWTH * ARSENAL.CHEST_GROWTH * 0.6)), "Schlundherz −40 %")


## User decision 28.09.2026: 6 distinct relics, each stacks up to its max
## (RELIC_MAX_STACK, Urmutter 1); full slots only offer stacks of owned relics.
func _test_relic_limits() -> void:
	var arsenal = ARSENAL.new()
	_check(arsenal.relic_slot_limit() == 6 and ARSENAL.RELIC_MAX_STACK == 5 and ARSENAL.max_stacks("urmutter") == 1, "6 Relikt-Plätze, Stapel bis 5, Urmutter 1")
	var owned := ["hungerstein", "zaehe_haut", "scharfe_zaehne", "flinke_beine", "witterungsnase", "koenigszahnkette"]
	for id in owned:
		_check(arsenal.grant(arsenal.relic_item(id)).applied, "Relikt %s passt in einen Platz" % id)
	_check(arsenal.relics_owned() == 6 and arsenal.relic_slots_free() == 0, "Relikt-Plätze voll")
	var seventh: Dictionary = arsenal.grant(arsenal.relic_item("gluecksknochen"))
	_check(not seventh.applied and arsenal.stacks("gluecksknochen") == 0, "Siebtes Relikt ohne Platz wird abgelehnt")
	for i in 4:
		arsenal.grant(arsenal.relic_item("hungerstein"))
	_check(arsenal.stacks("hungerstein") == 5 and not arsenal.grant(arsenal.relic_item("hungerstein")).applied, "Stapel endet bei 5")
	# Full relic and weapon slots: only stacks of owned relics and rank-ups.
	for id in ["rudelbiss", "sporenwolke", "klauenwirbel", "giftbiss"]:
		arsenal.grant(arsenal.weapon_item(id, "common"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for i in 300:
		for kind in ["map", "gold", "boss", "start", "elite"]:
			var chest: Dictionary = arsenal.roll_chest(rng, 0.0, kind)
			_check(_distinct(chest.items), "Volle Plätze: Angebote verschieden")
			for item in chest.items:
				if item.type == "relic":
					_check(owned.has(item.id) and item.id != "hungerstein", "Volle Relikt-Plätze: nur Stapel eigener Relikte unter 5 (%s)" % item.id)
				elif item.type == "weapon":
					_check(arsenal.rank(item.id) > 0 and arsenal.rank(item.id) < 5, "Volle Waffenplätze: nur Rang-Aufstiege (%s)" % item.id)
	# Urmutter: one stack only.
	var mother = ARSENAL.new()
	mother.relic_pool = ["urmutter"]
	mother.weapon_pool = []
	_check(mother.grant(mother.relic_item("urmutter")).applied and not mother.grant(mother.relic_item("urmutter")).applied and mother.slot_limit() == 5, "Urmutter stapelt nicht (ein Zusatzplatz)")
	_check(mother.roll_chest(rng, 0.0, "gold").items.is_empty(), "Urmutter maximal: kein Angebot mehr")
	# Everything owned is maxed: no offer (the caller refunds Bernstein).
	var maxed = EVOLUTION.new()
	for id in ["rudelbiss", "sporenwolke", "klauenwirbel", "giftbiss"]:
		maxed.debug_grant(id, "legendary")
		maxed.debug_grant(id, "legendary")
	for id in owned:
		for i in ARSENAL.max_stacks(id):
			maxed.arsenal.grant(maxed.arsenal.relic_item(id))
	_check(maxed.slots_used("relic") == 6 and maxed.slot_limit("relic") == 6, "Fassade zählt Relikt-Plätze")
	var price: int = maxed.chest_price()
	for kind in ["map", "elite", "gold", "boss"]:
		var result: Dictionary = maxed.open_chest(kind)
		_check(result.items.is_empty() and int(result.refund) == price and maxed.chest_offers.is_empty(), "Alles belegt und maximal: %s-Kokon erstattet Bernstein" % kind)


func _test_chests() -> void:
	var arsenal = ARSENAL.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	# Etappe 28: jede Kokon-Art bietet drei verschiedene Teile zur Wahl.
	var relics := 0
	var items_seen := 0
	for i in 1000:
		var map: Dictionary = arsenal.roll_chest(rng, 0.0, "map")
		_check(map.kind == "map" and map.pick and map.items.size() == 3, "Karten-Kokon: 1 aus 3")
		_check(_distinct(map.items), "Karten-Angebote sind verschieden")
		for item in map.items:
			items_seen += 1
			if item.type == "relic":
				relics += 1
	# Taken relic tiers fall back to weapons, so the share per card sits a bit below 55 %.
	_check(absf(float(relics) / float(items_seen) - ARSENAL.RELIC_SHARE) < 0.08, "Karten-Kokon ~55 %% Relikt (%.2f)" % (float(relics) / float(items_seen)))
	for kind in ["elite", "gold", "boss"]:
		var lowest: String = ARSENAL.CHEST_FLOOR[kind]
		for i in 300:
			var chest: Dictionary = arsenal.roll_chest(rng, 0.0, kind)
			_check(chest.kind == kind and chest.pick and chest.items.size() == 3 and _distinct(chest.items), "%s-Kokon: 1 aus 3, verschieden" % kind)
			for item in chest.items:
				_check(STATS.rarity_at_least(item.rarity, lowest), "%s-Kokon: mindestens %s (%s %s)" % [kind, lowest, item.id, item.rarity])
	# Start-Kokon: mit < 2 Waffen drei neue Waffen, höchstens selten.
	for i in 300:
		var start: Dictionary = arsenal.roll_chest(rng, 20.0, "start")
		_check(start.pick and start.items.size() == 3 and _distinct(start.items), "Start-Kokon: 1 aus 3")
		for item in start.items:
			_check(item.type == "weapon" and arsenal.rank(item.id) == 0, "Start-Kokon bietet neue Waffen (%s)" % item.id)
			_check(not STATS.rarity_at_least(item.rarity, "epic"), "Start-Kokon höchstens selten (%s)" % item.rarity)
	var armed = ARSENAL.new()
	armed.grant(armed.weapon_item("rudelbiss", "common"))
	armed.grant(armed.weapon_item("sporenwolke", "common"))
	for i in 300:
		var later: Dictionary = armed.roll_chest(rng, 20.0, "start")
		for item in later.items:
			_check(not STATS.rarity_at_least(item.rarity, "epic"), "Start-Kokon mit 2 Waffen höchstens selten (%s %s)" % [item.id, item.rarity])
	# Volle Plätze: nur Rang-Aufstiege eigener Waffen und Relikte.
	var full = ARSENAL.new()
	for id in ["rudelbiss", "sporenwolke", "klauenwirbel", "giftbiss"]:
		full.grant(full.weapon_item(id, "common"))
	for i in 200:
		for item in full.roll_chest(rng, 0.0, "map").items:
			_check(item.type == "relic" or (item.type == "weapon" and full.rank(item.id) > 0), "Volle Plätze: nur Aufstieg oder Relikt (%s)" % item.id)
	# Weniger gültige Teile als drei: so viele, wie es gibt; keines: leere Wahl.
	var scarce = ARSENAL.new()
	scarce.relic_pool = []
	scarce.weapon_pool = ["rudelbiss", "sporenwolke"]
	var two: Dictionary = scarce.roll_chest(rng, 0.0, "map")
	_check(two.items.size() == 2 and two.pick and _distinct(two.items), "Nur zwei gültige Teile: zwei Angebote (%d)" % two.items.size())
	scarce.grant(scarce.weapon_item("rudelbiss", "legendary"))
	scarce.grant(scarce.weapon_item("rudelbiss", "legendary"))
	scarce.grant(scarce.weapon_item("sporenwolke", "legendary"))
	scarce.grant(scarce.weapon_item("sporenwolke", "legendary"))
	var none: Dictionary = scarce.roll_chest(rng, 0.0, "boss")
	_check(none.items.is_empty() and not none.pick, "Alles maximal: kein Angebot")
	# Pools: gesperrte Relikte/Waffen kommen nicht vor.
	for i in 500:
		var item: Dictionary = arsenal.roll_item(rng, 30.0, "legendary")
		_check(not ARSENAL.UNLOCK_RELICS.has(item.id) and not ARSENAL.UNLOCK_WEAPONS.has(item.id), "Gesperrtes Teil gewürfelt: " + str(item.id))


static func _distinct(items: Array) -> bool:
	var ids := {}
	for item in items:
		ids[item.id] = true
	return ids.size() == items.size()


func _test_evolution() -> void:
	var evo = EVOLUTION.new()
	evo.debug_grant("rudelbiss", "legendary")
	evo.debug_grant("rudelbiss", "epic")
	_check(evo.rank("rudelbiss") == 5 and evo.evolution_ready().is_empty(), "Rang 5 ohne Relikt: keine Evolution")
	evo.debug_grant("rudelhorn")
	_check(evo.evolution_ready() == ["meute"], "Rudelbiss 5 + Rudelhorn = Meute bereit")
	var chest: Dictionary = evo.open_chest("boss")
	_check(chest.items[0].type == "evolution" and evo.chest_offers[0][0] == "meute" and evo.chest_offers[0][3] == "legendary", "Boss-Kokon bietet die Evolution garantiert an")
	var granted: Dictionary = evo.choose_chest(0)
	_check(granted.applied and evo.evolutions.has("meute") and evo.rank("rudelbiss") == 0 and evo.rank("meute") == 1, "Meute ersetzt Rudelbiss im selben Platz")
	_check(evo.slots_used("attack") == 1 and evo.evolution_ready().is_empty(), "Evolution belegt den Platz der Grundwaffe, danach nicht erneut bereit")
	_check(evo.try_evolve() == "meute" and evo.try_evolve() == "", "Evolutions-Moment genau einmal")
	# Evolvierte Grundwaffe kommt nicht mehr als Beute.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for i in 300:
		_check(evo.arsenal.roll_item(rng, 0.0).get("id", "") != "rudelbiss", "Evolvierte Grundwaffe als Beute angeboten")
	# Etappe 28: Karten-Kokon öffnet eine Wahl (chest_kind "map"), Preis steigt.
	var map_evo = EVOLUTION.new()
	var price: int = map_evo.chest_price()
	var opened: Dictionary = map_evo.open_chest("map")
	_check(opened.pick and map_evo.chest_offers.size() == 3 and map_evo.chest_kind == "map" and map_evo.chest_price() > price, "Karten-Kokon öffnet 1 aus 3, der nächste kostet mehr")
	var revision: int = map_evo.revision
	var chosen_id: String = map_evo.chest_offers[1][0]
	var picked: Dictionary = map_evo.choose_chest(1)
	_check(bool(picked.get("applied", false)) and picked.id == chosen_id and map_evo.chest_offers.is_empty() and map_evo.chest_kind == "", "choose_chest gibt das gewählte Teil zurück (%s)" % chosen_id)
	_check(map_evo.revision > revision, "Beute meldet eine Änderung (revision)")
	for kind in ["start", "elite", "gold", "boss"]:
		var chest_evo = EVOLUTION.new()
		chest_evo.open_chest(kind)
		_check(chest_evo.chest_offers.size() == 3 and chest_evo.chest_kind == kind and chest_evo.revision == 0, "%s-Kokon: Wahl statt Sofort-Beute" % kind)
	# Nichts mehr zu verbessern: Bernstein-Ersatz, keine Wahl, Preis bleibt.
	var spent = EVOLUTION.new()
	spent.arsenal.relic_pool = []
	spent.arsenal.weapon_pool = ["rudelbiss"]
	spent.debug_grant("rudelbiss", "legendary")
	spent.debug_grant("rudelbiss", "legendary")
	var spent_price: int = spent.chest_price()
	var refund: Dictionary = spent.open_chest("map")
	_check(refund.items.is_empty() and int(refund.refund) == spent_price and spent.chest_offers.is_empty() and spent.chest_price() == spent_price, "Alles maximal: Bernstein-Ersatz %d statt Karte" % int(refund.refund))


func _test_hooks() -> void:
	var evo = EVOLUTION.new()
	# Hungerstein: +20 % Biomasse, −5 % Tempo.
	evo.debug_grant("hungerstein")
	_check(is_equal_approx(evo.harvest_multiplier(), 1.2) and is_equal_approx(evo.speed_multiplier(false), 0.95), "Hungerstein")
	evo.debug_grant("zaehe_haut")
	_check(evo.loss_after_armor(100, true) == 96, "Zähe Haut −4 % Verluste")
	evo.debug_grant("scharfe_zaehne")
	evo.debug_grant("blutmond")
	_check(is_equal_approx(evo.damage_multiplier(false), 1.06 * 1.4) and evo.leader_hp_bonus(100) == -EVOLUTION.BLOODMOON_LP, "Scharfe Zähne + Blutmond (−25 Max-LP)")
	evo.debug_grant("flinke_beine")
	evo.debug_grant("rudelhorn")
	_check(is_equal_approx(evo.speed_multiplier(true), 0.95 * 1.06 * 1.15) and is_equal_approx(evo.speed_multiplier(false), 0.95 * 1.06), "Flinke Beine, Rudelhorn nur bei Rally")
	evo.debug_grant("witterungsnase")
	evo.debug_grant("dna_splitter")
	_check(is_equal_approx(evo.magnet_multiplier(), 1.15) and is_equal_approx(evo.dna_multiplier(), 1.1), "Witterungsnase, DNA-Splitter")
	evo.debug_grant("gluecksknochen")
	_check(is_equal_approx(evo.luck(), 2.0), "Glücksknochen +2 Glück")
	evo.debug_grant("magnetkern")
	_check(is_equal_approx(evo.lure_multiplier(), 2.0), "Magnetkern: Lockrufe doppelt so oft")
	evo.debug_grant("aetzdruese")
	evo.debug_grant("grabkralle")
	evo.debug_grant("gewitterfell")
	evo.debug_grant("glutdruese")
	var mods: Dictionary = evo.form_modifiers()
	_check(is_equal_approx(mods.acid_damage, 1.2) and is_equal_approx(mods.dig_radius, 1.0) and is_equal_approx(mods.chain_chance, 0.1) and mods.burn == 1, "Waffen-Relikte über form_modifiers: %s" % str(mods))
	# Zwillingsbrut: jede 4. Zellteilung ergibt 2 Tiere.
	evo.debug_grant("zwillingsbrut")
	_check(evo.note_divisions(3) == 0 and evo.note_divisions(1) == 1 and evo.note_divisions(8) == 2, "Zwillingsbrut jede 4. Teilung")
	# Sporenherz: 15 % je Kill (mit Kokon-/Hook-Zufall).
	evo.debug_grant("sporenherz")
	evo.hook_rng.seed = 2
	var bursts := 0
	for i in 4000:
		if evo.roll_kill_burst():
			bursts += 1
	_check(absf(float(bursts) / 4000.0 - 0.15) < 0.025, "Sporenherz ~15 %% (%.3f)" % (float(bursts) / 4000.0))
	# Königszahnkette mit zwei Stapeln: alle 8 Kills.
	var chain = EVOLUTION.new()
	chain.debug_grant("koenigszahnkette")
	chain.debug_grant("koenigszahnkette")
	_check(chain.note_kills(7) == 0 and chain.note_kills(1) == EVOLUTION.CHAIN_HEAL_LP, "Königszahnkette ×2 heilt alle 8 Kills 15 LP")
	# Alles über debug_grant bleibt in summary() sichtbar.
	_check(evo.summary().contains("Hungerstein ×1"), "summary() nennt Relikte: " + evo.summary())
