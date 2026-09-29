extends RefCounted

# Stage 33 - Mutationskerne ("Arcana"): few rule-changing cards that give a run
# its identity. Each core has a clear bonus AND a noticeable price; they take no
# build slot. Offered 1 of 3 at the run start and after every endboss kill, at
# most MAX_PER_RUN per run (evolution.gd: cores, core_offers, choose_core()).
#
# Effects (all optional; evolution.core_value() combines the taken cores):
#   multiplicative (neutral 1.0): harvest (biomass per crystal, i.e. cheaper
#     division), loss (animals lost per hit), melee, forms (weapon damage),
#     normal_damage (all damage vs. non-boss targets), major_damage (vs. bosses
#     and elites), magnet, speed, ability_cooldown, rally_bonus (share of the
#     rally damage bonus kept), leader_hit (LP a leader hit costs), heal (leader
#     heals), brood_crystals (Moorbrut kill rewards), amber, chest_price, dna,
#     level_curve (DNA per level)
#   additive (neutral 0): crit (crit chance), leader_hp (share of the base
#     leader LP), rerolls, skips, flood_offset (seconds, negative = earlier),
#     lure_every (seconds between free Lockrufe; 0 = none)
#   override: successor_share (share of the old max LP a successor leads with),
#     poison_crit (true: crits leave a poison cloud)

const MAX_PER_RUN := 3
const OFFER_COUNT := 3
## Card rarity of every core (always legendary gold).
const RARITY := "legendary"

const MUL_KEYS := ["harvest", "loss", "melee", "forms", "normal_damage", "major_damage", "magnet", "speed",
	"ability_cooldown", "rally_bonus", "leader_hit", "heal", "brood_crystals", "amber", "chest_price", "dna", "level_curve"]
const ADD_KEYS := ["crit", "leader_hp", "rerolls", "skips", "flood_offset", "lure_every"]

## Catalogue order: the first DEFAULT_UNLOCKED ids are unlocked from the start,
## the others come from trophies (meta layer).
const ORDER := ["hungrige_brut", "rudelgeist", "arsenal_kult", "panzerherz", "bernsteinblut", "magnetsturm",
	"giftblut", "koenigsjaeger", "wandernde_brut", "flutfresser", "schwarmgedaechtnis", "letzter_biss"]
const DEFAULT_UNLOCKED := 6

# Etappe 33 orchestrator pass: Rudelgeist, Arsenal-Kult, Königsjäger and
# Bernsteinblut were ~50 % weaker than no core in the reduced matrix (3 seeds,
# noisy); their price was softened. A 5-7 seed core matrix is still open.
const CORES := {
	"hungrige_brut": {"name": "Hungrige Brut",
		"plus": "Zellteilung braucht 30 % weniger Biomasse", "minus": "Tiere haben −25 % LP (mehr Verluste pro Treffer)",
		"effects": {"harvest": 1.0 / 0.7, "loss": 1.0 / 0.75}},
	"rudelgeist": {"name": "Rudelgeist",
		"plus": "Nahkampf +40 %", "minus": "Waffen −10 %",
		"effects": {"melee": 1.4, "forms": 0.9}},
	"arsenal_kult": {"name": "Arsenal-Kult",
		"plus": "Waffen +30 %", "minus": "Nahkampf −15 %",
		"effects": {"forms": 1.3, "melee": 0.85}},
	"panzerherz": {"name": "Panzerherz",
		"plus": "Anführer +50 % LP, Treffer auf ihn −30 %", "minus": "Heilung −50 %",
		"effects": {"leader_hp": 0.5, "leader_hit": 0.7, "heal": 0.5}},
	"bernsteinblut": {"name": "Bernsteinblut",
		"plus": "+50 % Bernstein, Kokons −20 % Preis", "minus": "DNA −8 %",
		"effects": {"amber": 1.5, "chest_price": 0.8, "dna": 0.92}},
	"magnetsturm": {"name": "Magnetsturm-Herz",
		"plus": "Magnet ×2, Lockruf alle 90 s", "minus": "Tempo −8 %",
		"effects": {"magnet": 2.0, "lure_every": 90.0, "speed": 0.92}},
	"giftblut": {"name": "Giftblut",
		"plus": "Kritbisse hinterlassen eine Giftwolke (2 s)", "minus": "Krit-Chance −5 %",
		"effects": {"poison_crit": true, "crit": -0.05}},
	"koenigsjaeger": {"name": "Königsjäger",
		"plus": "Bosse und Elite +50 % Schaden", "minus": "Normale Gegner −5 % Schaden",
		"effects": {"major_damage": 1.5, "normal_damage": 0.95}},
	"wandernde_brut": {"name": "Wandernde Brut",
		"plus": "Tempo +15 %, Fähigkeit −25 % Abklingzeit", "minus": "Rally-Bonus −50 %",
		"effects": {"speed": 1.15, "ability_cooldown": 0.75, "rally_bonus": 0.5}},
	"flutfresser": {"name": "Flutfresser",
		"plus": "Brut-Kills geben doppelte Kristalle", "minus": "Die Flut beginnt 20 s früher",
		"effects": {"brood_crystals": 2.0, "flood_offset": -20.0}},
	"schwarmgedaechtnis": {"name": "Schwarmgedächtnis",
		"plus": "+2 Neu würfeln und +2 Überspringen", "minus": "Level-Kurve +10 %",
		"effects": {"rerolls": 2, "skips": 2, "level_curve": 1.1}},
	"letzter_biss": {"name": "Letzter Biss",
		"plus": "Nachfolger übernimmt mit 100 % statt 80 % LP", "minus": "Anführer-Max-LP −20 %",
		"effects": {"successor_share": 1.0, "leader_hp": -0.2}},
}


static func has(id: String) -> bool:
	return CORES.has(id)


static func definition(id: String) -> Dictionary:
	return CORES.get(id, {})


static func display_name(id: String) -> String:
	return String(definition(id).get("name", id))


## Two-line card text: "+ bonus" / "− price".
static func describe(id: String) -> String:
	var d := definition(id)
	if d.is_empty():
		return ""
	return "+ %s\n− %s" % [d.plus, d.minus]


static func effects(id: String) -> Dictionary:
	return definition(id).get("effects", {})


## Unlocked ids when the RunConfig has no "cores_unlocked": the first six.
static func default_unlocked() -> Array[String]:
	var ids: Array[String] = []
	for index in mini(DEFAULT_UNLOCKED, ORDER.size()):
		ids.append(String(ORDER[index]))
	return ids


## Choice card: [id, Name, "+ …\n− …", "legendary", {kind:"core", id, plus, minus}].
static func card(id: String) -> Array:
	var d := definition(id)
	return [id, display_name(id), describe(id), RARITY,
		{"kind": "core", "type": "core", "id": id, "name": display_name(id), "plus": String(d.get("plus", "")), "minus": String(d.get("minus", "")), "rarity": RARITY}]


## Candidates: unlocked, not sealed, not taken (catalogue order).
static func candidates(unlocked: Array, sealed: Array, taken: Array) -> Array[String]:
	var result: Array[String] = []
	for id in ORDER:
		if unlocked.has(id) and not sealed.has(id) and not taken.has(id):
			result.append(String(id))
	return result


## Rolls up to OFFER_COUNT distinct cards from the candidates.
static func roll_offers(rng: RandomNumberGenerator, unlocked: Array, sealed: Array, taken: Array) -> Array:
	var source := candidates(unlocked, sealed, taken)
	var cards: Array = []
	while cards.size() < OFFER_COUNT and not source.is_empty():
		cards.append(card(source.pop_at(rng.randi_range(0, source.size() - 1))))
	return cards


## Combined value of effect `key` over the taken cores (neutral without one).
static func combined(taken: Array, key: String) -> Variant:
	if key in MUL_KEYS:
		var product := 1.0
		for id in taken:
			product *= float(effects(String(id)).get(key, 1.0))
		return product
	if key in ADD_KEYS:
		var total := 0.0
		for id in taken:
			total += float(effects(String(id)).get(key, 0.0))
		return total
	if key == "successor_share":
		var share := -1.0
		for id in taken:
			share = maxf(share, float(effects(String(id)).get(key, -1.0)))
		return share
	for id in taken:
		if bool(effects(String(id)).get(key, false)):
			return true
	return false
