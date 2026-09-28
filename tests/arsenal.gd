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
	_test_chests()
	_test_evolution()
	_test_hooks()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS arsenal: 10 weapons, 20 relics, 6 evolutions, slots + Urmutter, rank-ups, stacks, chest rarity floors, evolution ready, relic hooks")
	quit(0)


func _test_catalog() -> void:
	# Etappe 17c: + Blutzahn (selten) = 21 Relikte; 17d: + 4 Fähigkeits-Relikte = 25.
	_check(ARSENAL.WEAPONS.size() == 10 and ARSENAL.RELICS.size() == 25 and ARSENAL.EVOLVED.size() == 6, "10 Waffen, 25 Relikte, 6 Evolutionen")
	var tiers := {}
	for entry in ARSENAL.RELICS:
		tiers[entry[3]] = int(tiers.get(entry[3], 0)) + 1
	_check(tiers.get("common", 0) == 6 and tiers.get("rare", 0) == 11 and tiers.get("epic", 0) == 5 and tiers.get("legendary", 0) == 3, "Relikt-Seltenheiten 6/11/5/3: %s" % str(tiers))
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


func _test_chests() -> void:
	var arsenal = ARSENAL.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var relics := 0
	for i in 2000:
		var map: Dictionary = arsenal.roll_chest(rng, 0.0, "map")
		_check(map.kind == "map" and not map.pick and map.items.size() == 1, "Karten-Kokon: genau ein Teil sofort")
		if map.items[0].type == "relic":
			relics += 1
	_check(absf(float(relics) / 2000.0 - ARSENAL.RELIC_SHARE) < 0.05, "Karten-Kokon ~55 %% Relikt (%.2f)" % (float(relics) / 2000.0))
	for i in 400:
		var elite: Dictionary = arsenal.roll_chest(rng, 0.0, "elite")
		var item: Dictionary = elite.items[0]
		if item.type == "weapon":
			_check(STATS.rarity_at_least(item.rarity, "rare"), "Elite-Kokon: Waffe mindestens selten")
		else:
			_check(STATS.rarity_at_least(item.rarity, "rare"), "Elite-Kokon: Relikt mindestens selten (%s)" % item.id)
	for i in 300:
		var boss: Dictionary = arsenal.roll_chest(rng, 0.0, "boss")
		_check(boss.pick and boss.items.size() == 3, "Boss-Kokon: 1 aus 3")
		var ids := {}
		for item in boss.items:
			_check(STATS.rarity_at_least(item.rarity, "epic"), "Boss-Kokon: mindestens episch (%s %s)" % [item.id, item.rarity])
			ids[item.id] = true
		_check(ids.size() == 3, "Boss-Angebote sind verschieden")
	# Pools: gesperrte Relikte/Waffen kommen nicht vor.
	for i in 500:
		var item: Dictionary = arsenal.roll_item(rng, 30.0, "legendary")
		_check(not ARSENAL.UNLOCK_RELICS.has(item.id) and not ARSENAL.UNLOCK_WEAPONS.has(item.id), "Gesperrtes Teil gewürfelt: " + str(item.id))


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
	# Karten-Kokon: Beute sofort, Preis steigt.
	var map_evo = EVOLUTION.new()
	var price: int = map_evo.chest_price()
	var opened: Dictionary = map_evo.open_chest("map")
	_check(not opened.pick and opened.granted.size() == 1 and bool(opened.granted[0].applied) and map_evo.chest_price() > price and map_evo.chest_offers.is_empty(), "Karten-Kokon gibt sofort ein Teil, der nächste kostet mehr")
	_check(map_evo.revision > 0, "Beute meldet eine Änderung (revision)")


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
