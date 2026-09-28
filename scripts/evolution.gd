extends RefCounted

# Etappe 17: Fassade der dualen Progression für HuntWorld und HUD.
#   Spur 1 – Werte (scripts/progression/stats.gd): nur über Level (DNA).
#   Spur 2 – Arsenal (scripts/progression/arsenal.gd): Waffen und Relikte, nur
#            über Kokons und Bosse (Welle 2: chests.gd), Evolution = Waffe Rang 5
#            + passendes Relikt, angeboten im Boss-Kokon.
# Level-Angebote: `offers` = [[id, Name, Beschreibung, Seltenheit], ...] (id an
# Stelle 0 wie bisher; der Balance-Bot und das HUD lesen nur das).
# `ranks` ist ein gemeinsames Dictionary (Werte + Waffen), das Stats und Arsenal
# mitbenutzen; Tests dürfen es direkt setzen. Relikt-Stapel liegen in `relics`.
# Alle Relikt-Hooks (Kill, Treffer, Zellteilung) laufen hier bzw. über
# form_modifiers() gebündelt; HuntWorld ruft nur note_kills(), note_divisions()
# und roll_kill_burst().

const STATS = preload("res://scripts/progression/stats.gd")
const ARSENAL = preload("res://scripts/progression/arsenal.gd")

# Werte im alten Format [id, Name, Beschreibung] (Texte = Stats.describe_step).
const TRAITS = [
	["bite", "Biss", "+8 % Schaden pro Rang"],
	["crit", "Kritbiss", "+4 % Chance auf doppelten Schaden pro Rang"],
	["haste", "Angriffstempo", "−6 % Abklingzeit der Waffen pro Rang"],
	["reach", "Reichweite", "+8 % Fläche und Reichweite der Waffen pro Rang"],
	["rally", "Rudelinstinkt", "+10 % Schaden während Rally pro Rang"],
	["armor", "Knochenpanzer", "−6 % Verluste pro Rang"],
	["evade", "Fluchtreflex", "−6 % Verluste ohne Rally pro Rang"],
	["vigor", "Anführerherz", "+15 % Anführer-Max-LP pro Rang"],
	["regen", "Regeneration", "Anführer +0,5 LP je Sekunde pro Rang"],
	["lifesteal", "Lebensraub", "+0,4 % des Schwarm-Schadens heilt den Anführer pro Rang"],
	["brood", "Brutrate", "+6 % Biomasse je Kristall pro Rang"],
	["magnet", "Lockduft", "+12 % Sammelradius pro Rang"],
	["gene", "Genfluss", "+8 % DNA pro Rang"],
	["speed", "Sprinter", "+5 % Tempo pro Rang"],
	["luck", "Glück", "+1 Glück pro Rang: seltenere Karten, Kokons 3 % billiger"],
]
const ATTACKS = ARSENAL.WEAPONS
const EVOLVED = ARSENAL.EVOLVED
const RELICS = ARSENAL.RELICS
const EVOLUTION_RULES = ARSENAL.EVOLUTION_RULES
# Nur über Trophäen (meta_data „mutation:“, „weapon:“, „relic:“) im Pool.
const UNLOCK_ONLY = ["regen", "saeurespucker", "stachelruecken", "graeber", "blitzbiss", "brutsack",
	"dornenhaut", "urmutter", "blutmond", "schlundherz"]
const MAX_RANK = 5
## Etappe 17c: Königszahnkette heilt so viele LP, Blutmond kostet so viele Max-LP.
const CHAIN_HEAL_LP := 15
const BLOODMOON_LP := 25
## Schrein-Karten: Mindest-Seltenheit.
const SHRINE_MINIMUM := "rare"

# Regeneration/Königszahnkette: Moorbrut zählt nur REGEN_HORDE_WEIGHT Kill.
const REGEN_HORDE_WEIGHT = 0.15
# Dornenhaut (Relikt): +40 % Rückschaden je Stapel.
const THORN_STEP = 0.40
const THORN_BASE = 30.0
const THORN_PER_LOSS = 4.0
const THORN_LEADER = 10.0
# Relikt-Zahlen (je Stapel).
const RELIC = {
	"hungerstein_harvest": 0.20, "hungerstein_speed": -0.05, "zaehe_haut": 0.04, "scharfe_zaehne": 0.06,
	"flinke_beine": 0.06, "witterungsnase": 0.15, "dna_splitter": 0.10, "sporenherz": 0.15,
	"aetzdruese": 0.20, "rudelhorn": 0.15, "gewitterfell": 0.10, "grabkralle": 1.0, "gluecksknochen": 2.0,
	"koenigszahnkette": 15, "zwillingsbrut": 4, "blutmond": 0.40, "blutzahn": 0.03,
}
# Waffen: Angriffstempo höchstens −60 % Abklingzeit.
const HASTE_FLOOR = 0.4
# Vorhandene Symbole (ui_icons.gd) für neue IDs, bis eigene Icons geliefert sind
# (stages/ICON_REQUESTS.md). Fehlt ein Eintrag, zeichnet die Karte eine Plakette.
const ICON_IDS = {
	"bite": "jaws", "crit": "crit", "haste": "haste", "reach": "reach", "rally": "pack",
	"evade": "scatter", "vigor": "vigor", "regen": "regeneration", "magnet": "magnet",
	"gene": "gene", "speed": "speed", "luck": "luck", "lifesteal": "regeneration", "blutzahn": "jaws",
	"pilzreich": "pilzreich", "dornenwall": "dornenwall",
	"hungerstein": "glutton", "zaehe_haut": "armor", "scharfe_zaehne": "jaws", "flinke_beine": "scatter",
	"witterungsnase": "branch_growth", "dna_splitter": "dna", "sporenherz": "sporenwolke",
	"aetzdruese": "saeurespucker", "rudelhorn": "pack", "gewitterfell": "blitzbiss", "grabkralle": "graeber",
	"gluecksknochen": "crown_tooth", "koenigszahnkette": "crown", "zwillingsbrut": "brood",
	"magnetkern": "alpha_core", "urmutter": "nest", "blutmond": "skull", "schlundherz": "biomass",
	# Alt-IDs (Etappe 16) für alte Build-Anzeigen.
	"lockduft": "magnet",
}
const DEFAULT_SLOTS = {"attack": ARSENAL.BASE_SLOTS, "trait": 14}
## Etappe 17 Welle 2: Die Startwaffe beginnt auf Rang 1; weitere Ränge kommen
## nur aus Kokons (Welle 1 hatte sie ohne Kokons auf Rang 4 gesetzt).
const SIGNATURE_START_RANK = 1

signal leader_regenerated(amount: int)

var stats = STATS.new()
var arsenal = ARSENAL.new()
var ranks: Dictionary = {}:
	set(value):
		ranks = value
		if stats != null:
			stats.ranks = value
		if arsenal != null:
			arsenal.ranks = value
var relics: Dictionary = {}:
	set(value):
		relics = value
		if arsenal != null:
			arsenal.relics = value
var evolutions: Array[String] = []
var dna := 0
var level := 0
var offers: Array = []
## Herkunft der offenen Werte-Karten: "level" (DNA) oder "shrine" (Schrein,
## kostenlos, zählt kein Level).
var offer_source := "level"
## Boss-Kokon: 1 aus 3 (Welle 2 öffnet ihn; die Karten zeigt mutation_screen im
## Modus „chest“). Einträge [id, Name, Beschreibung, Seltenheit, item].
var chest_offers: Array = []
## Welle 2: der erste Boss-Kokon je Biom-Zyklus garantiert eine bereite
## Evolution; HuntWorld setzt das bei jeder Ankunft in einem neuen Biom zurück.
var evolution_guarantee := true
var rng := RandomNumberGenerator.new()
## Eigener Zufall für Kokons und Relikt-Hooks (ändert die Level-Angebote nicht).
var chest_rng := RandomNumberGenerator.new()
var hook_rng := RandomNumberGenerator.new()

var slots: Dictionary = DEFAULT_SLOTS.duplicate()
var pool: Array = []
var banished: Array = []
var rerolls := 0
var banishes := 0
var skips := 0
## Etappe 17: Alpha-Kern entfällt; bleibt 0 (Altaufrufer, HUD-Chip).
var alpha_cores := 0
var signature := ""
# Meta-Multiplikatoren (1.0 neutral); armor = additiver Verlust-Abzug.
var mods: Dictionary = {"damage": 1.0, "armor": 0.0, "harvest": 1.0, "dna": 1.0, "growth": 1.0, "rally_damage": 1.0, "magnet": 1.0, "speed": 1.0}
## Kurzzeit-Multiplikatoren (Welle 2: Power-ups). damage/speed/magnet ×,
## cooldown × Abklingzeit, loss × Verluste, leader_immune = Anführer unverwundbar.
var boosts: Dictionary = {"damage": 1.0, "speed": 1.0, "magnet": 1.0, "cooldown": 1.0, "loss": 1.0, "leader_immune": false}
## Steigt bei jeder Änderung an Werten/Arsenal; HuntWorld synchronisiert dann
## Waffen, Anführer-LP und Modifikatoren.
var revision := 0
## Letzte Evolution (für den Evolutions-Moment im HUD).
var last_evolution := ""
# Hook-Zähler.
var regen_kills := 0.0
var regen_ready_at := 0.0
var chain_kills := 0.0
var divisions := 0


func _init() -> void:
	rng.randomize()
	chest_rng.randomize()
	hook_rng.randomize()
	stats.ranks = ranks
	arsenal.ranks = ranks
	arsenal.relics = relics
	evolutions = arsenal.evolutions
	pool = _default_pool()


static func _default_pool() -> Array:
	var ids: Array = []
	for entry in TRAITS:
		if not UNLOCK_ONLY.has(entry[0]):
			ids.append(entry[0])
	for id in ARSENAL.default_weapon_pool():
		ids.append(id)
	for id in ARSENAL.default_relic_pool():
		ids.append(id)
	return ids


## Alte IDs (Etappe 03–16) auf die neuen abbilden (Profile, RunConfigs, Tests).
static func migrate_id(id: String) -> String:
	return STATS.migrate(id)


# Applies a RunConfig (see stages/03_progression.md, 17). Missing keys keep defaults.
func configure(config: Dictionary) -> void:
	var slot_config: Dictionary = config.get("slots", {})
	arsenal.slots = maxi(1, int(slot_config.get("attack", DEFAULT_SLOTS.attack)))
	slots = {"attack": arsenal.slots, "trait": DEFAULT_SLOTS.trait}
	var configured: Array = []
	for raw in config.get("pool", []):
		var id := migrate_id(str(raw))
		if info(id).size() > 0 and kind_of(id) != "evolved" and not configured.has(id):
			configured.append(id)
	var has_stats := configured.any(func(id): return kind_of(id) == "trait")
	var has_weapons := configured.any(func(id): return kind_of(id) == "attack")
	var has_relics := configured.any(func(id): return kind_of(id) == "relic")
	var defaults := _default_pool()
	pool = []
	for id in configured + defaults:
		var kind := kind_of(id)
		var from_config: bool = (kind == "trait" and has_stats) or (kind == "attack" and has_weapons) or (kind == "relic" and has_relics)
		if (from_config and configured.has(id)) or (not from_config and defaults.has(id)):
			if not pool.has(id):
				pool.append(id)
	arsenal.weapon_pool = pool.filter(func(id): return kind_of(id) == "attack")
	arsenal.relic_pool = pool.filter(func(id): return kind_of(id) == "relic")
	rerolls = int(config.get("rerolls", 0))
	banishes = int(config.get("banishes", 0))
	skips = int(config.get("skips", 0))
	var meta: Dictionary = config.get("mods", {})
	for key in ["damage", "harvest", "dna", "growth", "rally_damage", "magnet", "speed"]:
		mods[key] = float(meta.get(key, 1.0))
	mods["speed"] = clampf(float(mods.speed), 0.5, 2.0)
	# Negative armor (e.g. a fast strain) means extra losses.
	mods["armor"] = clampf(float(meta.get("armor", 0.0)), -0.5, 0.6)
	if config.has("seed"):
		var run_seed := int(config.get("seed", 0))
		chest_rng.seed = hash([run_seed, "chest"])
		hook_rng.seed = hash([run_seed, "hook"])
	# Die Startwaffe des Stammes (Welle 1: einzige Waffe ohne Kokons).
	signature = str(config.get("signature_attack", ""))
	if signature != "" and kind_of(signature) == "attack":
		ranks[signature] = maxi(SIGNATURE_START_RANK, rank(signature))
		if not pool.has(signature):
			pool.append(signature)
		if not arsenal.weapon_pool.has(signature):
			arsenal.weapon_pool.append(signature)
	revision += 1


# ---------------------------------------------------------------- Level (Werte)

## DNA for the next level. Welle 2: a small quadratic term makes late levels
## dearer (the flood's DNA no longer maxes every stat), early ones stay cheap.
func threshold() -> int:
	return 20 + level * 10 + int(1.5 * level * level)


# True when no further stat can ever be offered in this run.
func complete() -> bool:
	return stats.candidates(_stat_pool(), banished).is_empty()


func earn(amount: int) -> void:
	if complete():
		return
	dna += maxi(0, int(round(float(maxi(0, amount)) * dna_multiplier())))
	_prepare()


func _stat_pool() -> Array:
	return pool.filter(func(id): return kind_of(id) == "trait")


func _prepare(exclude: Array = []) -> void:
	if not offers.is_empty() or dna < threshold():
		return
	offer_source = "level"
	offers = stats.roll_offers(rng, luck(), _stat_pool(), banished, exclude)


## Schrein (Etappe 17 Welle 2): 1 aus 3 Werten, mindestens selten, kostenlos.
## Liefert false, wenn gerade eine andere Wahl offen ist oder kein Wert mehr steigt.
func open_shrine() -> bool:
	if not offers.is_empty() or not chest_offers.is_empty():
		return false
	offers = stats.roll_offers(rng, luck(), _stat_pool(), banished, [], 3, SHRINE_MINIMUM)
	offer_source = "shrine" if not offers.is_empty() else "level"
	return not offers.is_empty()


# Refills after reroll/banish in the same mode (shrine cards stay shrine cards).
func _refill(exclude: Array = []) -> void:
	if offer_source == "shrine":
		offers = stats.roll_offers(rng, luck(), _stat_pool(), banished, exclude, 3, SHRINE_MINIMUM)
		if offers.is_empty():
			offer_source = "level"
			_prepare()
		return
	_prepare(exclude)


func choose(slot: int) -> bool:
	if slot < 0 or slot >= offers.size():
		return false
	var entry: Array = offers[slot]
	var shrine := offer_source == "shrine"
	if not shrine:
		dna -= threshold()
		level += 1
	stats.apply(str(entry[0]), str(entry[3]) if entry.size() > 3 else "common")
	revision += 1
	offers.clear()
	offer_source = "level"
	_prepare()
	return true


func reroll() -> bool:
	if rerolls <= 0 or offers.is_empty():
		return false
	rerolls -= 1
	var previous: Array = offers.map(func(entry): return entry[0])
	offers.clear()
	_refill(previous)
	return true


# Removes the offered stat from this run's pool and refills the offer.
func banish(slot: int) -> bool:
	if banishes <= 0 or slot < 0 or slot >= offers.size():
		return false
	banishes -= 1
	var id: String = offers[slot][0]
	banished.append(id)
	var kept: Array = offers.filter(func(entry): return entry[0] != id)
	offers.clear()
	_refill()
	# Keep the other two cards (with their rarity) so a banish is not a free reroll.
	var ordered: Array = kept.duplicate()
	for entry in offers:
		if ordered.size() >= offers.size():
			break
		if not ordered.any(func(k): return k[0] == entry[0]):
			ordered.append(entry)
	offers = ordered
	return true


# Declines this level-up: the DNA for it is spent, no stat is gained.
func skip() -> bool:
	if skips <= 0 or offers.is_empty():
		return false
	skips -= 1
	if offer_source != "shrine":
		dna -= threshold()
	offers.clear()
	offer_source = "level"
	_prepare()
	return true


# ---------------------------------------------------------------- Arsenal

## Würfelt einen Kokon (kind = map/elite/boss) mit dem Kokon-Zufall und Glück.
func roll_chest(kind: String) -> Dictionary:
	return arsenal.roll_chest(chest_rng, luck(), kind)


## Öffnet einen Kokon: Karte/Elite = Beute sofort anwenden, Boss = chest_offers
## füllen (1 aus 3, die Welt pausiert, bis choose_chest()). Rückgabe wie
## roll_chest() plus "granted" (angewandte Teile) bei sofortiger Beute.
func open_chest(kind: String, minimum: String = "") -> Dictionary:
	var result: Dictionary
	if kind == "start":
		var item: Dictionary = arsenal.roll_start(chest_rng, luck())
		result = {"kind": "start", "pick": false, "items": [item] if not item.is_empty() else []}
	else:
		result = arsenal.roll_chest(chest_rng, luck(), kind, minimum, evolution_guarantee)
	# Only the first boss cocoon of a biome cycle guarantees a ready evolution.
	if kind == "boss" and result.items.any(func(item): return String(item.get("type", "")) == "evolution"):
		evolution_guarantee = false
	if kind == "map":
		arsenal.chests_opened += 1
	if bool(result.get("pick", false)):
		chest_offers = []
		for item in result.items:
			chest_offers.append(chest_entry(item))
		return result
	var granted: Array = []
	for item in result.items:
		granted.append(grant(item))
	result["granted"] = granted
	return result


## Karten-Eintrag für mutation_screen (Modus „chest“).
static func chest_entry(item: Dictionary) -> Array:
	return [String(item.get("id", "")), String(item.get("name", "")), String(item.get("desc", "")), String(item.get("rarity", "common")), item]


func choose_chest(slot: int) -> Dictionary:
	if slot < 0 or slot >= chest_offers.size():
		return {}
	var entry: Array = chest_offers[slot]
	chest_offers.clear()
	return grant(entry[4] if entry.size() > 4 else {})


## Wendet ein Beute-Teil an (Waffe/Relikt/Evolution) und meldet die Änderung.
func grant(item: Dictionary) -> Dictionary:
	var result: Dictionary = arsenal.grant(item)
	if bool(result.get("applied", false)):
		revision += 1
		if String(result.get("type", "")) == "evolution":
			last_evolution = String(result.id)
	return result


func chest_price() -> int:
	return arsenal.chest_price(luck())



func evolution_ready() -> Array:
	return arsenal.evolution_ready()


## Test/Debug: gibt einen Wert, eine Waffe, ein Relikt oder eine Evolution direkt.
func debug_grant(id: String, rarity: String = "common") -> Dictionary:
	id = migrate_id(id)
	match kind_of(id):
		"trait":
			stats.apply(id, rarity)
			revision += 1
			return {"type": "stat", "id": id, "rarity": rarity, "applied": true, "to": rank(id)}
		"attack":
			return grant(arsenal.weapon_item(id, rarity))
		"relic":
			return grant(arsenal.relic_item(id))
		"evolved":
			return grant(arsenal.evolution_item(id))
	return {"applied": false}


# ---------------------------------------------------------------- Alt-Aufrufer

## Etappe 17: Alpha-Kern entfällt (Welle 2: Elite-Kokon). Stub für Altaufrufer.
func add_alpha_core() -> void:
	pass


## Evolutionen kommen nur noch über den Boss-Kokon (grant()). try_evolve()
## liefert die zuletzt gewährte Evolution genau einmal (HuntWorld zeigt dann den
## Evolutions-Moment), sonst "".
func try_evolve() -> String:
	var evolved := last_evolution
	last_evolution = ""
	return evolved


# Next evolution the player is working towards, for hints ("" when none).
func evolution_hint() -> String:
	for rule in EVOLUTION_RULES:
		if evolutions.has(rule.id) or rank(rule.base) <= 0:
			continue
		var needs := PackedStringArray()
		if rank(rule.base) < MAX_RANK:
			needs.append("%s Rang %d" % [info(rule.base)[1], MAX_RANK])
		if arsenal.stacks(rule.partner) < 1:
			needs.append(info(rule.partner)[1])
		needs.append("Boss-Kokon")
		return "%s braucht: %s" % [info(rule.id)[1], ", ".join(needs)]
	return ""


# ---------------------------------------------------------------- Katalog

func rank(id: String) -> int:
	return int(ranks.get(id, 0))


func stacks(id: String) -> int:
	return arsenal.stacks(id)


## "trait" (Wert), "attack" (Waffe), "evolved", "relic" oder "".
func kind_of(id: String) -> String:
	if STATS.has(id):
		return "trait"
	if ARSENAL.is_weapon(id):
		return "attack"
	if ARSENAL.is_evolved(id):
		return "evolved"
	if ARSENAL.is_relic(id):
		return "relic"
	return ""


func info(id: String) -> Array:
	if STATS.has(id):
		return STATS.info(id)
	return ARSENAL.info(id)


func slot_limit(kind: String) -> int:
	if kind == "attack":
		return arsenal.slot_limit()
	return int(slots.get(kind, 0))


# Evolved forms count as attack forms.
func slots_used(kind: String) -> int:
	if kind == "attack":
		return arsenal.weapons().size()
	var used := 0
	for id in ranks:
		if int(ranks[id]) > 0 and kind_of(id) == kind:
			used += 1
	return used


# Attack forms (incl. evolved) with their rank, for AttackForms.set_ranks.
func attack_ranks() -> Dictionary:
	return arsenal.attack_ranks()


# Existing UI icon for an id (itself when ui_icons.gd has one).
static func icon_id(id: String) -> String:
	return String(ICON_IDS.get(id, id))


## Wert-Vorschau für eine Karte: {before, after, label}.
func stat_preview(id: String, rarity: String) -> Dictionary:
	return stats.preview(id, rarity)


# ---------------------------------------------------------------- Wirkung

func luck() -> float:
	return stats.amount("luck") + RELIC.gluecksknochen * stacks("gluecksknochen")


## Kritbiss als Erwartungswert (jeder Treffer ×2 mit Chance crit).
func crit_chance() -> float:
	return clampf(stats.amount("crit"), 0.0, 1.0)


func damage_multiplier(rally: bool) -> float:
	var value := (1.0 + stats.amount("bite")) * (1.0 + crit_chance())
	if rally:
		value *= (1.0 + stats.amount("rally")) * float(mods.rally_damage)
	value *= 1.0 + RELIC.scharfe_zaehne * stacks("scharfe_zaehne")
	value *= 1.0 + RELIC.blutmond * stacks("blutmond")
	return value * float(mods.damage) * float(boosts.damage)


## Tempo des Schwarms (Stamm/Meta × Sprinter × Relikte × Power-up).
func speed_multiplier(rally: bool = false) -> float:
	var value := float(mods.speed) * (1.0 + stats.amount("speed"))
	value *= 1.0 + RELIC.flinke_beine * stacks("flinke_beine")
	value *= maxf(0.5, 1.0 + RELIC.hungerstein_speed * stacks("hungerstein"))
	if rally:
		value *= 1.0 + RELIC.rudelhorn * stacks("rudelhorn")
	return value * float(boosts.speed)


## Faktor auf alle Waffen-Abklingzeiten (Angriffstempo, Power-up).
func cooldown_scale() -> float:
	return maxf(HASTE_FLOOR, 1.0 - stats.amount("haste")) * float(boosts.cooldown)


## Faktor auf Fläche und Reichweite der Waffen.
func area_scale() -> float:
	return 1.0 + stats.amount("reach")


# Biomasse je eingesammeltem Kristall (Brutrate, Hungerstein, Meta "harvest" = Verdauung).
func harvest_multiplier() -> float:
	return (1.0 + stats.amount("brood")) * (1.0 + RELIC.hungerstein_harvest * stacks("hungerstein")) * float(mods.harvest)


# Magnetradius-Faktor (Lockduft, Witterungsnase, Meta "magnet" = Witterung, Power-up).
func magnet_multiplier() -> float:
	return (1.0 + stats.amount("magnet")) * (1.0 + RELIC.witterungsnase * stacks("witterungsnase")) * float(mods.magnet) * float(boosts.magnet)


# Biomasse künftiger Kills (Stamm "growth"; Vielfraß ist in Brutrate aufgegangen).
func biomass_multiplier() -> float:
	return float(mods.growth)


func dna_multiplier() -> float:
	return (1.0 + stats.amount("gene")) * (1.0 + RELIC.dna_splitter * stacks("dna_splitter")) * float(mods.dna)


## Lockruf-Chance (Magnetkern: doppelt so oft je Stapel).
func lure_multiplier() -> float:
	return 1.0 + float(stacks("magnetkern"))


## Zusätzliche Anführer-LP: Anführerherz minus Blutmond.
## Zusätzliche Anführer-LP (Etappe 17c): Anführerherz +15 % des Grund-Maximums je
## Wert, Blutmond −BLOODMOON_LP je Stapel.
func leader_hp_bonus(base: int = 100) -> int:
	return int(round(float(base) * stats.amount("vigor"))) - BLOODMOON_LP * stacks("blutmond")


## Anteil des ausgeteilten Schwarm-Schadens, der den Anführer heilt (Lebensraub + Blutzahn).
func lifesteal() -> float:
	return stats.amount("lifesteal") + RELIC.blutzahn * stacks("blutzahn")


## Regeneration in LP je Sekunde.
func regen_rate() -> float:
	return stats.amount("regen")


func loss_after_armor(amount: int, rally: bool) -> int:
	if amount <= 0:
		return 0
	var reduction := stats.amount("armor") + (0.0 if rally else stats.amount("evade")) + RELIC.zaehe_haut * stacks("zaehe_haut") + float(mods.armor)
	var scaled := float(amount) * (1.0 - clampf(reduction, -0.5, 0.85)) * float(boosts.loss)
	return maxi(1, ceili(scaled - 0.0001))


## Waffen-Modifikatoren für AttackForms.set_modifiers().
func form_modifiers() -> Dictionary:
	return {
		"cooldown": cooldown_scale(),
		"area": area_scale(),
		"acid_damage": 1.0 + RELIC.aetzdruese * stacks("aetzdruese"),
		"dig_radius": RELIC.grabkralle * stacks("grabkralle"),
		"chain_chance": 1.0 - pow(1.0 - RELIC.gewitterfell, stacks("gewitterfell")),
		"burn": stacks("glutdruese"),
	}


func summary() -> String:
	var parts := arsenal.summary()
	parts.append_array(stats.summary())
	return " · ".join(parts)


# ---------------------------------------------------------------- Hooks

## Kills je Regenerations-LP (0 = kein Wert Regeneration).
func regeneration_interval() -> int:
	return STATS.regen_kills(stats.units_of("regen"))


func regeneration_gap() -> float:
	return STATS.regen_gap(stats.units_of("regen"))


## Kill-Hook: zählt `count` Kills mit Gewicht `weight` (Moorbrut:
## REGEN_HORDE_WEIGHT) für Regeneration und Königszahnkette; liefert die LP, die
## der Anführer zurückbekommt (HuntWorld kappt auf leader_max_hp). Regeneration
## heilt mit Spielzeit `now` >= 0 höchstens 1 LP je regeneration_gap().
func note_kills(count: int = 1, weight: float = 1.0, now: float = -1.0) -> int:
	if count <= 0 or weight <= 0.0:
		return 0
	# Etappe 17c: Regeneration heals LP per second (HuntWorld), not per kill.
	var healed := 0
	var chain := stacks("koenigszahnkette")
	if chain > 0:
		var every := maxf(1.0, ceilf(float(RELIC.koenigszahnkette) / float(chain)))
		chain_kills += float(count) * weight
		var chain_heal := int(floor((chain_kills + 0.00001) / every))
		chain_kills -= float(chain_heal) * every
		healed += chain_heal * CHAIN_HEAL_LP
	if healed > 0:
		leader_regenerated.emit(healed)
	return healed


func _regen(count: int, weight: float, now: float) -> int:
	var interval := regeneration_interval()
	if interval <= 0:
		return 0
	regen_kills += float(count) * weight
	var healed := int(floor((regen_kills + 0.00001) / float(interval)))
	if now >= 0.0:
		if healed > 0 and now >= regen_ready_at:
			healed = 1
			regen_ready_at = now + regeneration_gap()
		else:
			healed = 0
		regen_kills = minf(regen_kills - float(healed * interval), float(interval))
	else:
		regen_kills -= float(healed * interval)
	return healed


## Zellteilungs-Hook (Zwillingsbrut): liefert zusätzliche Tiere für `count` neue.
func note_divisions(count: int) -> int:
	var twins := stacks("zwillingsbrut")
	if twins <= 0 or count <= 0:
		return 0
	var every := maxi(2, int(RELIC.zwillingsbrut) + 1 - twins)
	var before := divisions
	divisions += count
	return floori(float(divisions) / every) - floori(float(before) / every)


## Kill-Hook (Sporenherz): platzt dieser Kill als Sporenwolke?
func roll_kill_burst() -> bool:
	var hearts := stacks("sporenherz")
	if hearts <= 0:
		return false
	return hook_rng.randf() < 1.0 - pow(1.0 - RELIC.sporenherz, hearts)


func thorn_factor() -> float:
	return THORN_STEP * float(stacks("dornenhaut"))


func thorn_damage(loss: int, leader_struck: bool = false) -> float:
	var factor := thorn_factor()
	if factor <= 0.0:
		return 0.0
	return factor * (THORN_BASE + THORN_PER_LOSS * float(maxi(0, loss)) + (THORN_LEADER if leader_struck else 0.0))
