extends RefCounted
## Etappe 17 – Spur 1: Werte (Mutationen). Nur Level geben Werte.
##
## 14 Werte mit je 5 Rängen. Jede Wahl erhöht den Rang um 1 und den „Wert“ um den
## Seltenheitsfaktor der Karte (Etappe 28: gewöhnlich 1,0 · ungewöhnlich 1,25 ·
## selten 1,5 · episch 2,0 · legendär 3,0). Die Wirkung ist Basis je Rang × Wert,
## z. B. Biss selten = +12 %.
##
## Die Ränge liegen in einem Dictionary, das sich Stats, Arsenal und die Fassade
## (evolution.gd) teilen: `ranks` (id -> Rang). `units` (id -> Wert) fehlt für
## Werte, die Tests direkt in `ranks` setzen; dann gilt Wert = Rang (gewöhnlich).

const MAX_RANK := 5

## Etappe 28: fünf Stufen (neu: ungewöhnlich). Die Reihenfolge ist der Rang der
## Stufe (Böden, Strahlhöhe, beste Seltenheit); alle alten Ids bleiben gültig.
const RARITIES := ["common", "uncommon", "rare", "epic", "legendary"]
const RARITY_FACTOR := {"common": 1.0, "uncommon": 1.25, "rare": 1.5, "epic": 2.0, "legendary": 3.0}
const RARITY_CHANCE := {"common": 0.55, "uncommon": 0.25, "rare": 0.13, "epic": 0.06, "legendary": 0.01}
const RARITY_NAME := {"common": "GEWÖHNLICH", "uncommon": "UNGEWÖHNLICH", "rare": "SELTEN", "epic": "EPISCH", "legendary": "LEGENDÄR"}
## Kit-Töne (UiStyle.BRAWL_TONES) des Seltenheitsrands. Die Farben selbst liefert
## ab Etappe 28 UiStyle.rarity_tone(id); dies bleibt der Ton-Name für Altaufrufer.
const RARITY_TONE := {"common": "neutral", "uncommon": "action", "rare": "info", "epic": "special", "legendary": "loot"}
## Glück: je Punkt +10 % relativ auf alle Stufen ab ungewöhnlich.
const LUCK_STEP := 0.10

## id, Name, Kategorie (attack/protect/growth/special), Basis je Rang, Einheit.
## Welle 2 (mit Kokons, Bernstein und Power-ups): die Basiswerte sind wieder auf
## dem Konzept (Biss 8, Kritbiss 4, Angriffstempo 6, Reichweite 8, Rudelinstinkt
## 10, Knochenpanzer 6, Fluchtreflex 6, Brutrate 6, je %).
## Einheiten: "pct" (+x %), "neg" (−x %), "hp" (+x % Anführer-LP, Etappe 17c),
## "lps" (LP je Sekunde), "luck" (+x Glück).
const STATS := [
	{"id": "bite", "name": "Biss", "cat": "attack", "step": 0.08, "unit": "pct", "label": "Schaden"},
	{"id": "crit", "name": "Kritbiss", "cat": "attack", "step": 0.04, "unit": "pct", "label": "Chance auf doppelten Schaden"},
	{"id": "haste", "name": "Angriffstempo", "cat": "attack", "step": 0.06, "unit": "neg", "label": "Abklingzeit der Waffen"},
	{"id": "reach", "name": "Reichweite", "cat": "attack", "step": 0.08, "unit": "pct", "label": "Fläche und Reichweite der Waffen"},
	{"id": "rally", "name": "Rudelinstinkt", "cat": "attack", "step": 0.1, "unit": "pct", "label": "Schaden während Rally"},
	{"id": "armor", "name": "Knochenpanzer", "cat": "protect", "step": 0.06, "unit": "neg", "label": "Verluste"},
	{"id": "evade", "name": "Fluchtreflex", "cat": "protect", "step": 0.06, "unit": "neg", "label": "Verluste ohne Rally"},
	{"id": "vigor", "name": "Anführerherz", "cat": "protect", "step": 0.15, "unit": "hp", "label": "Anführer-Max-LP"},
	{"id": "regen", "name": "Regeneration", "cat": "protect", "step": 0.5, "unit": "lps", "label": "Anführer-LP je Sekunde"},
	{"id": "lifesteal", "name": "Lebensraub", "cat": "protect", "step": 0.004, "unit": "pct", "label": "des Schwarm-Schadens heilt den Anführer"},
	{"id": "brood", "name": "Brutrate", "cat": "growth", "step": 0.06, "unit": "pct", "label": "Biomasse je Kristall"},
	{"id": "magnet", "name": "Lockduft", "cat": "growth", "step": 0.12, "unit": "pct", "label": "Sammelradius"},
	{"id": "gene", "name": "Genfluss", "cat": "growth", "step": 0.08, "unit": "pct", "label": "DNA"},
	{"id": "speed", "name": "Sprinter", "cat": "special", "step": 0.05, "unit": "pct", "label": "Tempo"},
	{"id": "luck", "name": "Glück", "cat": "special", "step": 1.0, "unit": "luck", "label": "Glück (Seltenheit, Kokon-Rabatt)"},
]
## Nur über Trophäen („mutation:<id>“) im Pool.
const UNLOCK_ONLY := ["regen"]
## Alte Anlagen-IDs (Etappe 03–16) -> neue Werte. dornenhaut ist jetzt ein Relikt.
const LEGACY := {"jaws": "bite", "pack": "rally", "scatter": "evade", "armor": "armor", "brood": "brood",
	"glutton": "brood", "lockduft": "magnet", "regeneration": "regen"}

## Regeneration: N Kills je LP und Mindestabstand in s, beide nach Wert 1..5.
const REGEN_KILLS_START := 14.0
const REGEN_KILLS_STEP := 1.5
const REGEN_KILLS_MIN := 5.0
const REGEN_GAP_START := 30.0
const REGEN_GAP_STEP := 2.5
const REGEN_GAP_MIN := 12.0
## Anführerherz: +1 LP ab Wert 1, 3 und 5.
const VIGOR_STEPS := [1.0, 3.0, 5.0]

var ranks: Dictionary = {}
var units: Dictionary = {}


static func ids() -> Array:
	var out: Array = []
	for entry in STATS:
		out.append(entry.id)
	return out


static func has(id: String) -> bool:
	return not definition(id).is_empty()


static func definition(id: String) -> Dictionary:
	for entry in STATS:
		if entry.id == id:
			return entry
	return {}


static func migrate(id: String) -> String:
	return String(LEGACY.get(id, id))


## [id, Name, Beschreibung] wie die alten TRAITS-Einträge.
static func info(id: String) -> Array:
	var d := definition(id)
	if d.is_empty():
		return []
	return [id, d.name, describe_step(id)]


## Kurztext je Rang, z. B. „+8 % Schaden pro Rang“.
static func describe_step(id: String) -> String:
	var d := definition(id)
	match String(d.get("unit", "")):
		"pct":
			return "+%s %% %s pro Rang" % [_num(d.step * 100.0), d.label]
		"neg":
			return "−%s %% %s pro Rang" % [_num(d.step * 100.0), d.label]
		"hp":
			return "+%s %% Anführer-Max-LP pro Rang" % _num(d.step * 100.0)
		"lps":
			return "Anführer +%s LP je Sekunde pro Rang" % _num(d.step)
		"luck":
			return "+1 Glück pro Rang: seltenere Karten, Kokons 3 % billiger"
	return ""


static func _num(value: float) -> String:
	if absf(value) < 10.0 and not is_equal_approx(value * 10.0, roundf(value * 10.0)):
		return String.num(value, 2).replace(".", ",")
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return String.num(value, 1).replace(".", ",")


func rank(id: String) -> int:
	return int(ranks.get(id, 0))


## Summe der Seltenheitsfaktoren (Wert); ohne Eintrag = Rang (gewöhnlich).
func units_of(id: String) -> float:
	if units.has(id):
		return float(units[id])
	return float(rank(id))


func clear() -> void:
	for id in ids():
		ranks.erase(id)
	units.clear()


## Eine Wahl: Rang +1, Wert + Seltenheitsfaktor.
func apply(id: String, rarity: String) -> void:
	if not has(id):
		return
	var before := units_of(id)
	ranks[id] = mini(MAX_RANK, rank(id) + 1)
	units[id] = before + float(RARITY_FACTOR.get(rarity, 1.0))


## Wirkung eines Werts (Basis × Wert), z. B. 0,16 für Biss mit Wert 2.
func amount(id: String) -> float:
	var d := definition(id)
	if d.is_empty():
		return 0.0
	return float(d.step) * units_of(id)


# ---------------------------------------------------------------- Seltenheit

## Chancen je Seltenheit mit Glück; `minimum` schneidet niedrigere Stufen ab.
static func rarity_chances(luck: float, minimum: String = "common") -> Dictionary:
	var boost := 1.0 + LUCK_STEP * maxf(0.0, luck)
	var out := {}
	var upper := 0.0
	for rarity in RARITIES.slice(1):
		out[rarity] = float(RARITY_CHANCE[rarity]) * boost
		upper += out[rarity]
	out["common"] = maxf(0.0, 1.0 - upper)
	var floor_index := RARITIES.find(minimum)
	var total := 0.0
	for index in RARITIES.size():
		if index < floor_index:
			out[RARITIES[index]] = 0.0
		total += out[RARITIES[index]]
	for rarity in RARITIES:
		out[rarity] = out[rarity] / total if total > 0.0 else (1.0 if rarity == minimum else 0.0)
	return out


static func roll_rarity(rng: RandomNumberGenerator, luck: float, minimum: String = "common") -> String:
	var chances := rarity_chances(luck, minimum)
	var roll := rng.randf()
	var sum := 0.0
	for rarity in RARITIES:
		sum += float(chances[rarity])
		if roll < sum:
			return rarity
	return minimum if RARITIES.find(minimum) >= 0 else "common"


static func rarity_at_least(rarity: String, minimum: String) -> bool:
	return RARITIES.find(rarity) >= RARITIES.find(minimum)


# ---------------------------------------------------------------- Angebote

## Werte, die noch steigen können (Pool, nicht verbannt, unter Rang 5).
func candidates(pool: Array, banished: Array) -> Array:
	var out: Array = []
	for id in pool:
		if has(String(id)) and not banished.has(id) and rank(String(id)) < MAX_RANK and not out.has(id):
			out.append(String(id))
	return out


## Drei (oder weniger) verschiedene Werte mit gewürfelter Seltenheit:
## [id, Name, Beschreibung, Seltenheit]. `exclude` bevorzugt frische Karten.
func roll_offers(rng: RandomNumberGenerator, luck: float, pool: Array = [], banished: Array = [], exclude: Array = [], count: int = 3, minimum: String = "common") -> Array:
	var source := candidates(pool if not pool.is_empty() else ids(), banished)
	var fresh: Array = source.filter(func(id): return not exclude.has(id))
	if fresh.size() >= mini(count, source.size()):
		source = fresh
	var offers: Array = []
	while offers.size() < count and not source.is_empty():
		var id: String = source.pop_at(rng.randi_range(0, source.size() - 1))
		var entry := info(id)
		entry.append(roll_rarity(rng, luck, minimum))
		offers.append(entry)
	return offers


# ---------------------------------------------------------------- Anzeige

## Wert vorher/nachher als Text für die Karte: {before, after, label}.
func preview(id: String, rarity: String) -> Dictionary:
	var d := definition(id)
	if d.is_empty():
		return {}
	var now := units_of(id)
	var next := now + float(RARITY_FACTOR.get(rarity, 1.0))
	return {"before": format_value(id, now), "after": format_value(id, next), "label": _label(id)}


static func _label(id: String) -> String:
	var d := definition(id)
	match String(d.get("unit", "")):
		"hp":
			return "Anführer-Max-LP"
		"lps":
			return "Anführer-LP je Sekunde"
		"luck":
			return "Glück: seltenere Karten und Kokon-Beute"
	return String(d.get("label", ""))


static func format_value(id: String, value: float) -> String:
	var d := definition(id)
	match String(d.get("unit", "")):
		"pct":
			return "0 %" if value <= 0.0 else "+%s %%" % _num(float(d.step) * value * 100.0)
		"neg":
			return "0 %" if value <= 0.0 else "−%s %%" % _num(float(d.step) * value * 100.0)
		"hp":
			return "0 %" if value <= 0.0 else "+%s %%" % _num(float(d.step) * value * 100.0)
		"lps":
			return "–" if value <= 0.0 else "+%s/s" % _num(float(d.step) * value)
		"luck":
			return "+%s" % _num(value)
	return str(value)


static func vigor_hp(value: float) -> int:
	var hp := 0
	for step in VIGOR_STEPS:
		if value + 0.001 >= float(step):
			hp += 1
	# Über Wert 5 hinaus (legendäre Karten): je 2 weitere Punkte +1 LP.
	if value > 5.0:
		hp += int(floor((value - 5.0 + 0.001) / 2.0))
	return hp


## Kills je Regenerations-LP (0 = keine Regeneration).
static func regen_kills(value: float) -> int:
	if value <= 0.0:
		return 0
	return int(maxf(REGEN_KILLS_MIN, roundf(REGEN_KILLS_START - REGEN_KILLS_STEP * (value - 1.0))))


static func regen_gap(value: float) -> float:
	if value <= 0.0:
		return 0.0
	return maxf(REGEN_GAP_MIN, REGEN_GAP_START - REGEN_GAP_STEP * (value - 1.0))


func summary() -> PackedStringArray:
	var parts := PackedStringArray()
	for entry in STATS:
		if rank(entry.id) > 0:
			parts.append("%s %d" % [entry.name, rank(entry.id)])
	return parts
