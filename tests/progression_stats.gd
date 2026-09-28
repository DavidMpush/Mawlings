extends SceneTree

# Etappe 17 – Spur 1 (Werte): 14 Werte mit 5 Rängen, Seltenheitswurf mit und
# ohne Glück, roll_offers(), Wirkung über die Fassade (evolution.gd).

const STATS = preload("res://scripts/progression/stats.gd")
const EVOLUTION = preload("res://scripts/evolution.gd")
const DATA = preload("res://scripts/meta/meta_data.gd")
const ROLLS := 40000

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	_test_catalog()
	_test_rarity_distribution()
	_test_offers()
	_test_ranks_and_values()
	_test_effects()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS progression_stats: 15 stats, 5 ranks, 5 rarity tiers 55/25/13/6/1 + luck, offers, values, effects")
	quit(0)


func _test_catalog() -> void:
	# Etappe 17c: + Lebensraub = 15 Werte.
	_check(STATS.STATS.size() == 15, "15 Werte (%d)" % STATS.STATS.size())
	var ids := STATS.ids()
	for id in ["bite", "crit", "haste", "reach", "rally", "armor", "evade", "vigor", "regen", "lifesteal", "brood", "magnet", "gene", "speed", "luck"]:
		_check(ids.has(id), "Wert fehlt: " + id)
	# Die TRAITS-Liste der Fassade spiegelt die Werte (alte Aufrufer, HUD).
	_check(EVOLUTION.TRAITS.size() == 15, "evolution.TRAITS hat 15 Einträge")
	for entry in EVOLUTION.TRAITS:
		_check(STATS.has(entry[0]) and STATS.info(entry[0])[1] == entry[1], "TRAITS-Name passt nicht: " + str(entry[0]))
		_check(STATS.describe_step(entry[0]) == entry[2], "TRAITS-Text passt nicht zu describe_step: %s (%s)" % [entry[0], STATS.describe_step(entry[0])])
	# Alte Anlagen gehen in Werten auf; dornenhaut ist ein Relikt.
	for old in ["jaws", "pack", "scatter", "armor", "brood", "glutton", "lockduft", "regeneration"]:
		_check(STATS.has(STATS.migrate(old)), "Alte Anlage %s hat keinen Wert" % old)
	_check(not STATS.has("dornenhaut") and EVOLUTION.new().kind_of("dornenhaut") == "relic", "Dornenhaut ist ein Relikt")
	for id in DATA.TRAIT_IDS:
		_check(STATS.has(id), "meta TRAIT_IDS enthält unbekannten Wert " + id)
	_check(not DATA.TRAIT_IDS.has("regen"), "Regeneration nur über Trophäe")


func _test_rarity_distribution() -> void:
	# Etappe 28: fünf Stufen, 55/25/13/6/1 %.
	_check(STATS.RARITIES == ["common", "uncommon", "rare", "epic", "legendary"], "Fünf Stufen in Rangfolge")
	for rarity in STATS.RARITIES:
		_check(STATS.RARITY_FACTOR.has(rarity) and STATS.RARITY_CHANCE.has(rarity) and STATS.RARITY_NAME.has(rarity) and STATS.RARITY_TONE.has(rarity), "Tabellen kennen " + rarity)
	_check(STATS.RARITY_NAME.uncommon == "UNGEWÖHNLICH" and is_equal_approx(STATS.RARITY_FACTOR.uncommon, 1.25), "ungewöhnlich: Name und Faktor 1,25")
	var base := STATS.rarity_chances(0.0)
	_check(is_equal_approx(base.common, 0.55) and is_equal_approx(base.uncommon, 0.25) and is_equal_approx(base.rare, 0.13) and is_equal_approx(base.epic, 0.06) and is_equal_approx(base.legendary, 0.01), "Basischancen 55/25/13/6/1")
	var lucky := STATS.rarity_chances(5.0)
	_check(is_equal_approx(lucky.uncommon, 0.25 * 1.5) and is_equal_approx(lucky.rare, 0.13 * 1.5) and is_equal_approx(lucky.legendary, 0.015), "Glück 5 = +50 % relativ auf alle Stufen ab ungewöhnlich")
	_check(is_equal_approx(lucky.common + lucky.uncommon + lucky.rare + lucky.epic + lucky.legendary, 1.0), "Chancen summieren sich zu 1")
	var floor_epic := STATS.rarity_chances(0.0, "epic")
	_check(floor_epic.common == 0.0 and floor_epic.uncommon == 0.0 and floor_epic.rare == 0.0 and is_equal_approx(floor_epic.epic + floor_epic.legendary, 1.0), "Mindest-Seltenheit schneidet ab")
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var counts := {"common": 0, "uncommon": 0, "rare": 0, "epic": 0, "legendary": 0}
	for i in ROLLS:
		counts[STATS.roll_rarity(rng, 0.0)] += 1
	_check(absf(float(counts.common) / ROLLS - 0.55) < 0.012, "gewöhnlich ~55 %% (%.3f)" % (float(counts.common) / ROLLS))
	_check(absf(float(counts.uncommon) / ROLLS - 0.25) < 0.012, "ungewöhnlich ~25 %% (%.3f)" % (float(counts.uncommon) / ROLLS))
	_check(absf(float(counts.rare) / ROLLS - 0.13) < 0.010, "selten ~13 %% (%.3f)" % (float(counts.rare) / ROLLS))
	_check(absf(float(counts.epic) / ROLLS - 0.06) < 0.008, "episch ~6 %% (%.3f)" % (float(counts.epic) / ROLLS))
	_check(absf(float(counts.legendary) / ROLLS - 0.01) < 0.004, "legendär ~1 %% (%.4f)" % (float(counts.legendary) / ROLLS))
	var lucky_counts := {"common": 0, "uncommon": 0, "rare": 0, "epic": 0, "legendary": 0}
	for i in ROLLS:
		lucky_counts[STATS.roll_rarity(rng, 10.0)] += 1
	_check(lucky_counts.legendary > counts.legendary * 1.5 and lucky_counts.common < counts.common, "Glück 10 verschiebt spürbar nach oben (%s)" % str(lucky_counts))
	for i in 500:
		_check(STATS.rarity_at_least(STATS.roll_rarity(rng, 0.0, "rare"), "rare"), "Mindest-Seltenheit selten gebrochen")


func _test_offers() -> void:
	var stats = STATS.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var offers: Array = stats.roll_offers(rng, 0.0, STATS.ids(), [])
	_check(offers.size() == 3, "Drei Angebote")
	var seen := {}
	for offer in offers:
		_check(offer.size() == 4 and STATS.has(offer[0]) and STATS.RARITIES.has(offer[3]), "Angebot [id, Name, Text, Seltenheit]: %s" % str(offer))
		seen[offer[0]] = true
	_check(seen.size() == 3, "Angebote sind verschieden")
	# Pool, Verbannen, Rang 5 und Frische nach Neu würfeln.
	offers = stats.roll_offers(rng, 0.0, ["bite", "crit", "haste", "armor"], ["crit"])
	for offer in offers:
		_check(offer[0] != "crit" and ["bite", "haste", "armor"].has(offer[0]), "Pool/Verbannen verletzt: " + str(offer[0]))
	stats.ranks["bite"] = 5
	offers = stats.roll_offers(rng, 0.0, ["bite", "haste"], [])
	_check(offers.size() == 1 and offers[0][0] == "haste", "Rang 5 wird nicht mehr angeboten")
	offers = stats.roll_offers(rng, 0.0, ["crit", "haste", "armor", "evade", "speed", "luck"], [], ["crit", "haste", "armor"])
	for offer in offers:
		_check(not ["crit", "haste", "armor"].has(offer[0]), "Neu würfeln bevorzugt frische Karten")


func _test_ranks_and_values() -> void:
	var stats = STATS.new()
	stats.apply("bite", "common")
	stats.apply("bite", "rare")
	stats.apply("bite", "legendary")
	_check(stats.rank("bite") == 3 and is_equal_approx(stats.units_of("bite"), 5.5), "Rang zählt Wahlen, Wert Seltenheitsfaktoren (1 + 1,5 + 3)")
	_check(is_equal_approx(stats.amount("bite"), float(STATS.definition("bite").step) * 5.5), "Biss-Wirkung = Basis × Wert")
	for i in 4:
		stats.apply("bite", "common")
	_check(stats.rank("bite") == 5, "Rang bleibt bei 5 gedeckelt")
	var step: float = float(STATS.definition("armor").step) * 100.0
	var preview: Dictionary = stats.preview("armor", "epic")
	_check(preview.before == "0 %" and preview.after == "−%d %%" % int(roundf(step * 2.0)) and preview.label == "Verluste", "Vorschau Knochenpanzer episch: %s" % str(preview))
	stats.apply("armor", "common")
	preview = stats.preview("armor", "common")
	_check(preview.before == "−%d %%" % int(roundf(step)) and preview.after == "−%d %%" % int(roundf(step * 2.0)), "Vorschau vorher/nachher: %s" % str(preview))
	_check(STATS.format_value("vigor", 1.0) == "+15 %" and STATS.format_value("vigor", 3.0) == "+45 %", "Anführerherz +15 %% Max-LP je Wert (%s)" % STATS.format_value("vigor", 1.0))
	_check(STATS.format_value("regen", 0.0) == "–" and STATS.format_value("regen", 2.0) == "+1/s", "Regeneration-Anzeige in LP/s (%s)" % STATS.format_value("regen", 2.0))
	_check(STATS.format_value("lifesteal", 1.0) == "+0,4 %", "Lebensraub-Anzeige (%s)" % STATS.format_value("lifesteal", 1.0))
	_check(STATS.format_value("luck", 1.5) == "+1,5", "Glück-Anzeige (%s)" % STATS.format_value("luck", 1.5))


func _test_effects() -> void:
	var evo = EVOLUTION.new()
	_check(is_equal_approx(evo.damage_multiplier(false), 1.0) and is_equal_approx(evo.cooldown_scale(), 1.0) and is_equal_approx(evo.area_scale(), 1.0), "Neutral ohne Werte")
	var crit: float = float(STATS.definition("crit").step) * 2.0
	evo.debug_grant("crit", "epic")
	_check(is_equal_approx(evo.crit_chance(), crit) and is_equal_approx(evo.damage_multiplier(false), 1.0 + crit), "Kritbiss als Erwartungswert")
	evo.debug_grant("haste", "common")
	evo.debug_grant("reach", "rare")
	var haste: float = 1.0 - float(STATS.definition("haste").step)
	var reach: float = 1.0 + float(STATS.definition("reach").step) * 1.5
	_check(is_equal_approx(evo.cooldown_scale(), haste) and is_equal_approx(evo.area_scale(), reach), "Angriffstempo/Reichweite")
	var mods: Dictionary = evo.form_modifiers()
	_check(is_equal_approx(mods.cooldown, haste) and is_equal_approx(mods.area, reach), "form_modifiers trägt Werte weiter")
	evo.debug_grant("speed", "legendary")
	_check(is_equal_approx(evo.speed_multiplier(false), 1.0 + float(STATS.definition("speed").step) * 3.0), "Sprinter legendär = Basis × 3")
	evo.debug_grant("gene", "common")
	evo.dna = 0
	evo.earn(100)
	_check(evo.dna == int(round(100.0 * (1.0 + float(STATS.definition("gene").step)))), "Genfluss mehr DNA (%d)" % evo.dna)
	evo.debug_grant("vigor", "legendary")
	_check(evo.leader_hp_bonus(100) == 45, "Anführerherz legendär (Wert 3) = +45 %% Max-LP (%d)" % evo.leader_hp_bonus(100))
	evo.debug_grant("lifesteal", "common")
	_check(is_equal_approx(evo.lifesteal(), 0.004), "Lebensraub +0,4 %")
	evo.debug_grant("blutzahn")
	_check(is_equal_approx(evo.lifesteal(), 0.034), "Blutzahn +3 %")
	evo.debug_grant("luck", "rare")
	_check(is_equal_approx(evo.luck(), 1.5), "Glück selten = 1,5")
	evo.debug_grant("magnet", "common")
	_check(is_equal_approx(evo.magnet_multiplier(), 1.0 + float(STATS.definition("magnet").step)), "Lockduft")
	# Level-Offers der Fassade haben die Seltenheit und wirken beim Wählen.
	var level = EVOLUTION.new()
	level.rng.seed = 5
	level.earn(20)
	var id: String = level.offers[0][0]
	var rarity: String = level.offers[0][3]
	level.choose(0)
	_check(level.rank(id) == 1 and is_equal_approx(level.stats.units_of(id), float(STATS.RARITY_FACTOR[rarity])), "choose() wendet Seltenheit an")
