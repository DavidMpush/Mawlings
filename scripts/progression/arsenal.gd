extends RefCounted
## Etappe 17 – Spur 2: Arsenal (Waffen und Relikte). Nur Kokons und Bosse geben
## Waffen und Relikte, nie Level.
##
## Waffen: 4 Plätze (+1 mit Relikt „Urmutter“, +Meta-Angriffsslot), Ränge 1–5.
## Findet man eine vorhandene Waffe, steigt ihr Rang. Relikte: 6 Plätze, je
## Relikt bis RELIC_MAX_STACK Stapel (Urmutter 1, Zwillingsbrut 3).
## Evolution: Waffe Rang 5 + passendes Relikt -> der nächste Boss-Kokon bietet sie
## garantiert an; gewählt ersetzt sie die Grundwaffe im selben Platz.
##
## Beute-Einträge (Dictionaries) für Kokons, HUD und grant():
##   {"type": "weapon"|"relic"|"evolution", "id", "name", "desc", "rarity",
##    "gain" (Waffe: Ränge), "from", "to" (Rang/Stapel vorher, nachher)}
## Seltenheit einer Waffe = Rang-Sprung: gewöhnlich/ungewöhnlich/selten +1,
## episch +2, legendär +3. Relikte haben eine feste Seltenheit; der Wurf wählt die Stufe.
##
## Etappe 28: Jeder Kokon (start/map/elite/gold/boss) bietet 1 aus 3
## (roll_chest -> "pick" immer true); nichts wird mehr ohne Wahl vergeben.

const STATS = preload("res://scripts/progression/stats.gd")

const MAX_RANK := 5
const BASE_SLOTS := 4
## Build slots (user decision 28.09.2026): at most RELIC_SLOTS distinct relics;
## once all are taken, cocoons only offer further stacks of owned relics.
const RELIC_SLOTS := 6
## Stacks per relic (like the 5 ranks), so "maxed" exists. Exceptions:
## Urmutter is a slot (one extra weapon slot, like the meta upgrade), and
## Zwillingsbrut already hits its floor (every 2nd division) at 3 stacks.
const RELIC_MAX_STACK := 5
const RELIC_STACK_LIMIT := {"urmutter": 1, "zwillingsbrut": 3}
const RANK_GAIN := {"common": 1, "uncommon": 1, "rare": 1, "epic": 2, "legendary": 3}
## Karten-/Elite-Kokon: Anteil Relikt (Rest Waffe).
const RELIC_SHARE := 0.55
## Etappe 28: Mindest-Seltenheit je Kokon-Art (Start: höchstens selten, CHEST_CAP).
const CHEST_FLOOR := {"start": "common", "map": "common", "elite": "rare", "gold": "epic", "boss": "epic"}
const CHEST_CAP := {"start": "rare"}
## Angebote je Kokon (Etappe 28: jeder Kokon ist eine Wahl).
const CHEST_CHOICES := 3
## Karten-Kokon-Preis in Bernstein: 25 · 1,85^n, Glück −3 % je Punkt, Schlundherz −40 % je Stapel.
const CHEST_BASE := 25.0
## Welle 2: 1,35 -> 1,85; Preis in Bernstein (In-Run-Währung); ~5-7 Karten-Kokons je langem Run.
const CHEST_GROWTH := 1.85
const CHEST_LUCK_DISCOUNT := 0.03
const CHEST_MIN_FACTOR := 0.25
## Alt-Name (Welle 2: nur der Boss-Kokon bot eine Wahl).
const BOSS_CHOICES := CHEST_CHOICES

## [id, Name, Kurzbeschreibung]
const WEAPONS := [
	["rudelbiss", "Rudelbiss", "Rally löst Sprungangriffe auf nahe Gegner aus"],
	["sporenwolke", "Sporenwolke", "Aura: Schaden über Zeit und Verlangsamung"],
	["saeurespucker", "Säurespucker", "Spuckt Säure auf den nächsten Gegner"],
	["stachelruecken", "Stachelrücken", "Wer den Schwarm trifft, erleidet Schaden"],
	["graeber", "Gräber", "Tunnelstoß bricht beim entferntesten Gegner aus"],
	["blitzbiss", "Blitzbiss", "Kettenbiss springt zwischen nahen Gegnern"],
	["brutsack", "Brutsack", "Platzende Brutblasen setzen Hilfs-Beißer frei"],
	["klauenwirbel", "Klauenwirbel", "Knochenklingen kreisen um den Schwarm"],
	["giftbiss", "Giftbiss", "Giftfänge schnappen zu und vergiften (Schaden über Zeit)"],
	["schallbrueller", "Schallbrüller", "Brüllt einen Schallkegel nach vorn und wirft zurück"],
]
const EVOLVED := [
	["meute", "Meute", "Rally entfesselt eine jagende Meute"],
	["pilzreich", "Pilzreich", "Riesige Sporenwolke, Kills platzen als Pilzwolke"],
	["aetzflut", "Ätzflut", "Säureflut: durchschlagende Salven, ätzende Pfützen"],
	["dornenwall", "Dornenwall", "Ein Ring aus Dornen umgibt den Schwarm"],
	["erdbeben", "Erdbeben", "Drei Tunnelstöße zugleich, jeder mit Nachbeben"],
	["sturmrudel", "Sturmrudel", "Kettenbiss über sechs Ziele ohne Abschwächung"],
]
## Waffe Rang 5 + Relikt (mindestens 1 Stapel).
const EVOLUTION_RULES := [
	{"id": "meute", "base": "rudelbiss", "partner": "rudelhorn"},
	{"id": "pilzreich", "base": "sporenwolke", "partner": "sporenherz"},
	{"id": "aetzflut", "base": "saeurespucker", "partner": "aetzdruese"},
	{"id": "dornenwall", "base": "stachelruecken", "partner": "dornenhaut"},
	{"id": "erdbeben", "base": "graeber", "partner": "grabkralle"},
	{"id": "sturmrudel", "base": "blitzbiss", "partner": "gewitterfell"},
]
## [id, Name, Wirkung je Stapel, Seltenheit]
## Etappe 28: Hungerstein, Witterungsnase und DNA-Splitter (Wirtschafts-Relikte)
## rücken auf „ungewöhnlich“, damit die neue Stufe eigene Relikte hat (sonst
## fiele jeder ungewöhnliche Relikt-Wurf auf gewöhnlich zurück); 3/3/11/5/3.
const RELICS := [
	["hungerstein", "Hungerstein", "+20 % Biomasse je Kristall, −5 % Tempo", "uncommon"],
	["zaehe_haut", "Zähe Haut", "−4 % Verluste", "common"],
	["scharfe_zaehne", "Scharfe Zähne", "+6 % Schaden", "common"],
	["flinke_beine", "Flinke Beine", "+6 % Tempo", "common"],
	["witterungsnase", "Witterungsnase", "+15 % Sammelradius", "uncommon"],
	["dna_splitter", "DNA-Splitter", "+10 % DNA", "uncommon"],
	["sporenherz", "Sporenherz", "Kills platzen mit 15 % als Sporenwolke", "rare"],
	["aetzdruese", "Ätzdrüse", "Säurespucker +20 % Schaden", "rare"],
	["rudelhorn", "Rudelhorn", "Rally +15 % Tempo", "rare"],
	["gewitterfell", "Gewitterfell", "10 % Chance auf Kettenblitz bei Treffern", "rare"],
	["dornenhaut", "Dornenhaut", "+40 % Rückschaden, wenn der Schwarm getroffen wird", "rare"],
	["grabkralle", "Grabkralle", "Gräber-Stöße +1 m Radius", "rare"],
	["gluecksknochen", "Glücksknochen", "+2 Glück", "rare"],
	["blutzahn", "Blutzahn", "+3 % des Schwarm-Schadens heilt den Anführer", "rare"],
	["koenigszahnkette", "Königszahnkette", "Jeder 15. Kill heilt den Anführer um 15 LP", "epic"],
	["glutdruese", "Glutdrüse", "Bisse setzen Gegner in Brand", "epic"],
	["zwillingsbrut", "Zwillingsbrut", "Jede 4. Zellteilung ergibt 2 Tiere", "epic"],
	["magnetkern", "Magnetkern", "Lockrufe erscheinen doppelt so oft", "epic"],
	["urmutter", "Urmutter", "+1 Waffenplatz", "legendary"],
	["blutmond", "Blutmond", "+40 % Schaden, Anführer −25 Max-LP", "legendary"],
	["schlundherz", "Schlundherz", "Kokons 40 % billiger", "legendary"],
	# Etappe 17d: Relikte der Stammesfähigkeit (abilities.gd RELIC_HOOKS).
	["glutkern", "Glutkern", "Stammesfähigkeit −20 % Abklingzeit", "rare"],
	["feuerspur", "Feuerspur", "Die Fähigkeit hinterlässt 3 s brennenden Boden", "rare"],
	["sporenhall", "Sporenhall", "Wirkung der Fähigkeit +40 % länger", "rare"],
	["weiter_schlund", "Weiter Schlund", "Fähigkeit +25 % Reichweite", "epic"],
]
## Standard-Pools; weitere IDs kommen über Trophäen (meta_data „weapon:“/„relic:“).
const START_WEAPONS := ["rudelbiss", "sporenwolke", "klauenwirbel", "giftbiss", "schallbrueller"]
const UNLOCK_WEAPONS := ["saeurespucker", "stachelruecken", "graeber", "blitzbiss", "brutsack"]
const UNLOCK_RELICS := ["dornenhaut", "urmutter", "blutmond", "schlundherz"]

var ranks: Dictionary = {}
var relics: Dictionary = {}
var evolutions: Array[String] = []
var slots := BASE_SLOTS
var relic_slots := RELIC_SLOTS
var weapon_pool: Array = []
var relic_pool: Array = []
## Geöffnete Karten-Kokons (Preis steigt je Kokon).
var chests_opened := 0


func _init() -> void:
	weapon_pool = default_weapon_pool()
	relic_pool = default_relic_pool()


static func default_weapon_pool() -> Array:
	return START_WEAPONS.duplicate()


static func default_relic_pool() -> Array:
	var out: Array = []
	for entry in RELICS:
		if not UNLOCK_RELICS.has(entry[0]):
			out.append(entry[0])
	return out


# ---------------------------------------------------------------- Katalog

static func is_weapon(id: String) -> bool:
	return _row(WEAPONS, id).size() > 0


static func is_evolved(id: String) -> bool:
	return _row(EVOLVED, id).size() > 0


static func is_relic(id: String) -> bool:
	return _row(RELICS, id).size() > 0


static func _row(table: Array, id: String) -> Array:
	for entry in table:
		if entry[0] == id:
			return entry
	return []


static func info(id: String) -> Array:
	for table in [WEAPONS, EVOLVED, RELICS]:
		var row := _row(table, id)
		if row.size() > 0:
			return row.slice(0, 3)
	return []


static func relic_rarity(id: String) -> String:
	var row := _row(RELICS, id)
	return String(row[3]) if row.size() > 3 else "common"


static func max_stacks(id: String) -> int:
	return int(RELIC_STACK_LIMIT.get(id, RELIC_MAX_STACK))


static func rule_for(evolution_id: String) -> Dictionary:
	for rule in EVOLUTION_RULES:
		if rule.id == evolution_id:
			return rule
	return {}


# ---------------------------------------------------------------- Zustand

func rank(id: String) -> int:
	return int(ranks.get(id, 0))


func stacks(id: String) -> int:
	return int(relics.get(id, 0))


func clear() -> void:
	for id in ranks.keys():
		if is_weapon(id) or is_evolved(id):
			ranks.erase(id)
	relics.clear()
	evolutions.clear()
	chests_opened = 0


## Belegte Waffenplätze (Evolutionen belegen den Platz ihrer Grundwaffe).
func weapons() -> Array:
	var out: Array = []
	for id in ranks:
		if int(ranks[id]) > 0 and (is_weapon(id) or is_evolved(id)):
			out.append(id)
	return out


func slot_limit() -> int:
	return slots + stacks("urmutter")


func slots_free() -> int:
	return maxi(0, slot_limit() - weapons().size())


## Distinct relics owned (occupied relic slots).
func relics_owned() -> int:
	var used := 0
	for id in relics:
		if int(relics[id]) > 0 and is_relic(String(id)):
			used += 1
	return used


func relic_slot_limit() -> int:
	return relic_slots


func relic_slots_free() -> int:
	return maxi(0, relic_slot_limit() - relics_owned())


## True when this relic may gain a stack: below its max and (new) a free slot.
func relic_open(id: String) -> bool:
	var owned := stacks(id)
	if owned >= max_stacks(id):
		return false
	return owned > 0 or relic_slots_free() > 0


## Waffen-Ränge für AttackForms.set_ranks (Evolutionen als Rang 1).
func attack_ranks() -> Dictionary:
	var out := {}
	for id in weapons():
		out[id] = int(ranks[id])
	return out


## Evolutionen, deren Regel erfüllt ist (Waffe Rang 5 + Relikt), noch nicht genommen.
func evolution_ready() -> Array:
	var out: Array = []
	for rule in EVOLUTION_RULES:
		if evolutions.has(rule.id):
			continue
		if rank(rule.base) >= MAX_RANK and stacks(rule.partner) >= 1:
			out.append(rule.id)
	return out


# ---------------------------------------------------------------- Kokon-Beute

## Preis des nächsten Karten-Kokons in Biomasse.
func chest_price(luck: float = 0.0) -> int:
	var factor := (1.0 - CHEST_LUCK_DISCOUNT * maxf(0.0, luck)) * pow(0.6, stacks("schlundherz"))
	return maxi(1, int(round(CHEST_BASE * pow(CHEST_GROWTH, chests_opened) * maxf(CHEST_MIN_FACTOR, factor))))


## Würfelt die Angebote eines Kokons (Etappe 28: jeder Kokon ist eine 1-aus-3-Wahl).
## kind: "start" (höchstens selten; mit < 2 Waffen drei neue Waffen), "map"
## (ab gewöhnlich), "elite" (ab selten), "gold" (ab episch), "boss" (ab episch,
## Evolution garantiert, wenn eine bereitsteht). Unbekannte Arten gelten als "map".
## Die Angebote sind verschieden und immer anwendbar (volle Waffenplätze: nur
## Rang-Aufstiege eigener Waffen und Relikte); gibt es weniger als drei, kommen
## weniger, gibt es keines, ist "items" leer (der Aufrufer zahlt Bernstein-Ersatz).
## Rückgabe: {"kind", "pick": bool (true = 1 aus N wählen), "items": Array}.
## `minimum` hebt die Mindest-Seltenheit an (auch über die Start-Obergrenze).
## `guarantee` = false: der Boss-Kokon bietet keine garantierte Evolution
## (Welle 2: nur der erste Boss-Kokon je Biom-Zyklus garantiert sie).
func roll_chest(rng: RandomNumberGenerator, luck: float, kind: String, minimum: String = "", guarantee: bool = true) -> Dictionary:
	if not CHEST_FLOOR.has(kind):
		kind = "map"
	var lowest := _higher(String(CHEST_FLOOR[kind]), minimum)
	var cap := _higher(String(CHEST_CAP.get(kind, "legendary")), lowest)
	var items: Array = []
	if kind == "boss" and guarantee:
		var ready := evolution_ready()
		if not ready.is_empty():
			items.append(evolution_item(String(ready[rng.randi_range(0, ready.size() - 1)])))
	if kind == "start" and weapons().size() < 2:
		# The second weapon is the start cocoon's job: three fresh weapons to pick from.
		var fresh: Array = _weapon_candidates([]).filter(func(id): return rank(String(id)) == 0)
		while items.size() < CHEST_CHOICES and not fresh.is_empty():
			var id := String(fresh.pop_at(rng.randi_range(0, fresh.size() - 1)))
			items.append(weapon_item(id, _roll_capped(rng, luck, lowest, cap)))
	var guard := 24
	while items.size() < CHEST_CHOICES and guard > 0:
		guard -= 1
		var item := roll_item(rng, luck, lowest, items, cap)
		if item.is_empty():
			break
		items.append(item)
	return {"kind": kind, "pick": not items.is_empty(), "items": items}


static func _higher(a: String, b: String) -> String:
	return b if STATS.RARITIES.find(b) > STATS.RARITIES.find(a) else a


static func _lower(a: String, b: String) -> String:
	return b if STATS.RARITIES.find(b) < STATS.RARITIES.find(a) else a


static func _roll_capped(rng: RandomNumberGenerator, luck: float, minimum: String, cap: String) -> String:
	return _lower(STATS.roll_rarity(rng, luck, minimum), cap)


## Ein zufälliges Teil: 55 % Relikt, 45 % Waffe (neu oder Rang +1). Bei vollen
## Plätzen nur Rang-Aufstiege vorhandener Waffen. `taken` verhindert Dopplungen,
## `cap` begrenzt die gewürfelte Seltenheit (Start-Kokon: höchstens selten).
func roll_item(rng: RandomNumberGenerator, luck: float, minimum: String = "common", taken: Array = [], cap: String = "legendary") -> Dictionary:
	var rarity := _roll_capped(rng, luck, minimum, cap)
	var weapon_ids := _weapon_candidates(taken)
	var want_relic := rng.randf() < RELIC_SHARE
	if (want_relic or weapon_ids.is_empty()):
		var relic := _pick_relic(rng, rarity, taken)
		if not relic.is_empty():
			return relic
	if weapon_ids.is_empty():
		return _pick_relic(rng, rarity, taken, true)
	return weapon_item(String(weapon_ids[rng.randi_range(0, weapon_ids.size() - 1)]), rarity)


func _weapon_candidates(taken: Array) -> Array:
	var skip: Array = taken.map(func(item): return item.get("id", ""))
	var out: Array = []
	var free := slots_free() > 0
	for id in weapon_pool:
		if skip.has(id) or not is_weapon(String(id)) or _evolved_from(String(id)):
			continue
		var current := rank(String(id))
		if current >= MAX_RANK:
			continue
		if current == 0 and not free:
			continue
		out.append(String(id))
	return out


func _evolved_from(base: String) -> bool:
	for rule in EVOLUTION_RULES:
		if rule.base == base and evolutions.has(rule.id):
			return true
	return false


## Relikt der gewürfelten Seltenheit; fehlt eines, die nächst niedrigere Stufe
## (`any` = danach auch höhere).
func _pick_relic(rng: RandomNumberGenerator, rarity: String, taken: Array, any: bool = false) -> Dictionary:
	var skip: Array = taken.map(func(item): return item.get("id", ""))
	var order: Array = []
	var index := STATS.RARITIES.find(rarity)
	for i in range(index, -1, -1):
		order.append(STATS.RARITIES[i])
	if any:
		for i in range(index + 1, STATS.RARITIES.size()):
			order.append(STATS.RARITIES[i])
	for tier in order:
		var ids: Array = []
		for id in relic_pool:
			if is_relic(String(id)) and relic_rarity(String(id)) == tier and not skip.has(id) and relic_open(String(id)) and not ids.has(String(id)):
				ids.append(String(id))
		if not ids.is_empty():
			return relic_item(String(ids[rng.randi_range(0, ids.size() - 1)]))
	return {}


func weapon_item(id: String, rarity: String) -> Dictionary:
	var row := info(id)
	var from := rank(id)
	var gain := int(RANK_GAIN.get(rarity, 1))
	return {"type": "weapon", "id": id, "name": row[1] if row.size() > 1 else id, "desc": row[2] if row.size() > 2 else "",
		"rarity": rarity, "gain": gain, "from": from, "to": mini(MAX_RANK, from + gain)}


func relic_item(id: String) -> Dictionary:
	var row := info(id)
	var from := stacks(id)
	return {"type": "relic", "id": id, "name": row[1] if row.size() > 1 else id, "desc": row[2] if row.size() > 2 else "",
		"rarity": relic_rarity(id), "gain": 1, "from": from, "to": from + 1}


func evolution_item(id: String) -> Dictionary:
	var row := info(id)
	var rule := rule_for(id)
	return {"type": "evolution", "id": id, "name": row[1] if row.size() > 1 else id, "desc": row[2] if row.size() > 2 else "",
		"rarity": "legendary", "gain": 1, "from": 0, "to": 1, "base": String(rule.get("base", "")), "partner": String(rule.get("partner", ""))}


## Wendet ein Beute-Teil an. Rückgabe: das Teil mit tatsächlichem "from"/"to"
## und "applied" (false = nichts geändert, z. B. kein freier Platz).
## `force` (debug/tests only) ignores the relic slot and stack limits.
func grant(item: Dictionary, force: bool = false) -> Dictionary:
	var out := item.duplicate()
	out["applied"] = false
	var id := String(item.get("id", ""))
	match String(item.get("type", "")):
		"weapon":
			if not is_weapon(id) or _evolved_from(id):
				return out
			var from := rank(id)
			if from == 0 and slots_free() <= 0:
				return out
			var to := mini(MAX_RANK, from + maxi(1, int(item.get("gain", 1))))
			ranks[id] = to
			out["from"] = from
			out["to"] = to
			out["applied"] = to != from
		"relic":
			if not is_relic(id) or (not force and not relic_open(id)):
				return out
			var before := stacks(id)
			relics[id] = before + 1
			out["from"] = before
			out["to"] = before + 1
			out["applied"] = true
		"evolution":
			var rule := rule_for(id)
			if rule.is_empty() or evolutions.has(id):
				return out
			ranks.erase(String(rule.base))
			ranks[id] = 1
			evolutions.append(id)
			out["applied"] = true
	return out


func summary() -> PackedStringArray:
	var parts := PackedStringArray()
	for table in [WEAPONS, EVOLVED]:
		for entry in table:
			if rank(entry[0]) > 0:
				parts.append("%s %d" % [entry[1], rank(entry[0])])
	for entry in RELICS:
		if stacks(entry[0]) > 0:
			parts.append("%s ×%d" % [entry[1], stacks(entry[0])])
	return parts
