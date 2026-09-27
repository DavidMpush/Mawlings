extends RefCounted

# Run-bound mutation state. Two slot kinds: attack forms ("attack") and the
# passive traits ("trait"). Offers come only from the configured pool and never
# propose a new ID for a full slot kind; rank-ups of owned mutations stay open.

const TRAITS = [
	["jaws", "Reißzähne", "+25 % Angriffsschaden pro Rang"],
	["brood", "Schnelle Brut", "+30 % Erntetempo pro Rang"],
	["glutton", "Vielfraß", "+25 % Biomasse bei künftigen Kills"],
	["pack", "Rudelinstinkt", "+20 % Schaden bei Rally pro Rang"],
	["scatter", "Fluchtreflex", "−10 % Verluste ohne Rally pro Rang"],
	["armor", "Knochenpanzer", "−10 % Verluste pro Rang"],
	# Etappe 10 (nur über Trophäen freischaltbar, nicht im Standard-Pool):
	["regeneration", "Regeneration", "+1 LP für den Anführer je 12/9/6 Kills (höchstens alle 30/25/20 s)"],
	["dornenhaut", "Dornenhaut", "+40 % Rückschaden pro Rang"]
]
const ATTACKS = [
	["rudelbiss", "Rudelbiss", "Rally löst Sprungangriffe auf nahe Gegner aus"],
	["sporenwolke", "Sporenwolke", "Aura: Schaden über Zeit und Verlangsamung"],
	["saeurespucker", "Säurespucker", "Spuckt Säure auf den nächsten Gegner"],
	["stachelruecken", "Stachelrücken", "Wer den Schwarm trifft, erleidet Schaden"],
	# Etappe 10 (nur über Trophäen freischaltbar, nicht im Standard-Pool):
	["graeber", "Gräber", "Tunnelstoß bricht beim entferntesten Gegner aus"],
	["blitzbiss", "Blitzbiss", "Kettenbiss springt zwischen nahen Gegnern"],
	["brutsack", "Brutsack", "Platzende Brutblasen setzen Hilfs-Beißer frei"]
]
# Evolved attack forms replace their base form and occupy its slot.
const EVOLVED = [
	["aetzflut", "Ätzflut", "Säureflut: durchschlagende Salven, ätzende Pfützen"],
	["meute", "Meute", "Rally entfesselt eine jagende Meute"],
	["erdbeben", "Erdbeben", "Drei Tunnelstöße zugleich, jeder mit Nachbeben"],
	["sturmrudel", "Sturmrudel", "Kettenbiss über sechs Ziele ohne Abschwächung"]
]
# base form at MAX_RANK + partner trait >= 1 + one Alpha-Kern.
const EVOLUTION_RULES = [
	{"id": "aetzflut", "base": "saeurespucker", "partner": "glutton"},
	{"id": "meute", "base": "rudelbiss", "partner": "pack"},
	{"id": "erdbeben", "base": "graeber", "partner": "armor"},
	{"id": "sturmrudel", "base": "blitzbiss", "partner": "jaws"}
]
# Etappe 10: IDs, die nur über Trophäen (meta_data "mutation:<id>") in den Pool
# kommen. Ohne RunConfig bleibt der Standard-Pool der von Etappe 03.
const UNLOCK_ONLY = ["regeneration", "dornenhaut", "graeber", "blitzbiss", "brutsack"]

# --- Etappe 10: Schnittstellen der neuen Anlagen für HuntWorld ---------------
# Regeneration: HuntWorld meldet jeden Kill mit note_kills(n); der Rückgabewert
# (und das Signal leader_regenerated) sind die LP, die der Anführer zurückbekommt
# (HuntWorld kappt auf leader_max_hp). regen_kills = Fortschritt zum nächsten LP.
# Etappe 10 Teil 2: Kills zählen gewichtet (Moorbrut nur REGEN_HORDE_WEIGHT), und mit
# Spielzeit `now` heilt Regeneration höchstens 1 LP je REGEN_GAP[Rang] s; Fortschritt
# über ein volles Intervall hinaus verfällt in der Pause (kein Ansparen).
# Dornenhaut: thorn_factor() (0 ohne Anlage, 0,4 je Rang) und thorn_damage(loss,
# leader_struck) = Rückschaden für einen Gegner, der den Schwarm im Nahkampf trifft
# (vor enemy_scale). Anwenden z. B. über AttackForms.reflect_thorns().
const REGEN_KILLS = [12, 9, 6]
const REGEN_HORDE_WEIGHT = 0.15
const REGEN_GAP = [30.0, 25.0, 20.0]
const THORN_STEP = 0.40
const THORN_BASE = 30.0
const THORN_PER_LOSS = 4.0
const THORN_LEADER = 10.0
signal leader_regenerated(amount: int)
const MAX_RANK = 3
const DEFAULT_SLOTS = {"attack": 2, "trait": 3}

var ranks: Dictionary = {}
var dna := 0
var level := 0
var offers: Array = []
var rng := RandomNumberGenerator.new()

var slots: Dictionary = DEFAULT_SLOTS.duplicate()
var pool: Array = []
var banished: Array = []
var rerolls := 0
var banishes := 0
var skips := 0
var alpha_cores := 0
var evolutions: Array[String] = []
var signature := ""
# Meta multipliers (1.0 neutral); armor is an additive loss reduction share.
var mods: Dictionary = {"damage": 1.0, "armor": 0.0, "harvest": 1.0, "dna": 1.0, "growth": 1.0, "rally_damage": 1.0}
# Etappe 10: Kills seit dem letzten Regenerations-LP.
var regen_kills := 0.0
# Spielzeit, ab der das nächste Regenerations-LP frühestens kommt.
var regen_ready_at := 0.0


func _init() -> void:
	rng.randomize()
	pool = _default_pool()


static func _default_pool() -> Array:
	var ids: Array = []
	for entry in TRAITS:
		if not UNLOCK_ONLY.has(entry[0]):
			ids.append(entry[0])
	for entry in ATTACKS:
		if not UNLOCK_ONLY.has(entry[0]):
			ids.append(entry[0])
	return ids


# Applies a RunConfig (see stages/03_progression.md). Missing keys keep defaults.
func configure(config: Dictionary) -> void:
	var slot_config: Dictionary = config.get("slots", {})
	slots = {"attack": int(slot_config.get("attack", DEFAULT_SLOTS.attack)), "trait": int(slot_config.get("trait", DEFAULT_SLOTS.trait))}
	var configured_pool: Array = config.get("pool", [])
	pool = []
	for id in (configured_pool if not configured_pool.is_empty() else _default_pool()):
		if info(str(id)).size() > 0 and kind_of(str(id)) != "evolved" and not pool.has(str(id)):
			pool.append(str(id))
	rerolls = int(config.get("rerolls", 0))
	banishes = int(config.get("banishes", 0))
	skips = int(config.get("skips", 0))
	var meta: Dictionary = config.get("mods", {})
	for key in ["damage", "harvest", "dna", "growth", "rally_damage"]:
		mods[key] = float(meta.get(key, 1.0))
	# Negative armor (e.g. a fast strain) means extra losses.
	mods["armor"] = clampf(float(meta.get("armor", 0.0)), -0.5, 0.6)
	signature = str(config.get("signature_attack", ""))
	if signature != "" and kind_of(signature) == "attack":
		ranks[signature] = maxi(1, rank(signature))
		if not pool.has(signature):
			pool.append(signature)


func threshold() -> int:
	return 20 + level * 10


# True when no further mutation can ever be offered in this run.
func complete() -> bool:
	return _candidates().is_empty()


func earn(amount: int) -> void:
	if complete():
		return
	dna += maxi(0, int(round(float(maxi(0, amount)) * float(mods.dna))))
	_prepare()


func _candidates() -> Array:
	var result: Array = []
	for id in pool:
		if banished.has(id) or _base_evolved(id):
			continue
		var current := rank(id)
		if current >= MAX_RANK:
			continue
		if current == 0 and slots_used(kind_of(id)) >= slot_limit(kind_of(id)):
			continue
		result.append(info(id))
	return result


func _prepare(exclude: Array = []) -> void:
	if not offers.is_empty() or dna < threshold():
		return
	var candidates := _candidates()
	if candidates.is_empty():
		return
	# Prefer fresh cards after a reroll, but never show fewer than possible.
	var fresh: Array = candidates.filter(func(entry): return not exclude.has(entry[0]))
	var source: Array = fresh if fresh.size() >= mini(3, candidates.size()) else candidates
	while offers.size() < 3 and not source.is_empty():
		offers.append(source.pop_at(rng.randi_range(0, source.size() - 1)))


func choose(slot: int) -> bool:
	if slot < 0 or slot >= offers.size():
		return false
	var id: String = offers[slot][0]
	dna -= threshold()
	ranks[id] = rank(id) + 1
	level += 1
	offers.clear()
	_prepare()
	return true


func reroll() -> bool:
	if rerolls <= 0 or offers.is_empty():
		return false
	rerolls -= 1
	var previous: Array = offers.map(func(entry): return entry[0])
	offers.clear()
	_prepare(previous)
	return true


# Removes the offered mutation from this run's pool and refills the offer.
func banish(slot: int) -> bool:
	if banishes <= 0 or slot < 0 or slot >= offers.size():
		return false
	banishes -= 1
	var id: String = offers[slot][0]
	banished.append(id)
	var kept: Array = offers.map(func(entry): return entry[0])
	offers.clear()
	_prepare()
	# Keep the other two cards where possible so a banish is not a free reroll.
	var ordered: Array = []
	for entry in offers:
		if kept.has(entry[0]):
			ordered.append(entry)
	for entry in offers:
		if not kept.has(entry[0]):
			ordered.append(entry)
	offers = ordered
	return true


# Declines this level-up: the DNA for it is spent, no mutation is gained.
func skip() -> bool:
	if skips <= 0 or offers.is_empty():
		return false
	skips -= 1
	dna -= threshold()
	offers.clear()
	_prepare()
	return true


func add_alpha_core() -> void:
	alpha_cores += 1


# Consumes one stored Alpha-Kern for the first evolution whose rules hold.
# Returns the evolved ID or "".
func try_evolve() -> String:
	if alpha_cores <= 0:
		return ""
	for rule in EVOLUTION_RULES:
		if evolutions.has(rule.id) or rank(rule.base) < MAX_RANK or rank(rule.partner) < 1:
			continue
		alpha_cores -= 1
		ranks.erase(rule.base)
		ranks[rule.id] = 1
		evolutions.append(rule.id)
		return rule.id
	return ""


# Next evolution the player is working towards, for hints ("" when none).
func evolution_hint() -> String:
	for rule in EVOLUTION_RULES:
		if evolutions.has(rule.id) or rank(rule.base) <= 0:
			continue
		var needs := PackedStringArray()
		if rank(rule.base) < MAX_RANK:
			needs.append("%s Rang 3" % info(rule.base)[1])
		if rank(rule.partner) < 1:
			needs.append(info(rule.partner)[1])
		if alpha_cores <= 0:
			needs.append("Alpha-Kern")
		return "%s braucht: %s" % [info(rule.id)[1], ", ".join(needs)]
	return ""


func rank(id: String) -> int:
	return ranks.get(id, 0)


func _base_evolved(id: String) -> bool:
	for rule in EVOLUTION_RULES:
		if rule.base == id and evolutions.has(rule.id):
			return true
	return false


func kind_of(id: String) -> String:
	for entry in TRAITS:
		if entry[0] == id:
			return "trait"
	for entry in ATTACKS:
		if entry[0] == id:
			return "attack"
	for entry in EVOLVED:
		if entry[0] == id:
			return "evolved"
	return ""


func info(id: String) -> Array:
	for group in [TRAITS, ATTACKS, EVOLVED]:
		for entry in group:
			if entry[0] == id:
				return entry
	return []


func slot_limit(kind: String) -> int:
	return int(slots.get(kind, 0))


# Evolved forms count as attack forms.
func slots_used(kind: String) -> int:
	var used := 0
	for id in ranks:
		if ranks[id] <= 0:
			continue
		var own := kind_of(id)
		if own == kind or (kind == "attack" and own == "evolved"):
			used += 1
	return used


# Attack forms (incl. evolved) with their rank, for AttackForms.set_ranks.
func attack_ranks() -> Dictionary:
	var result := {}
	for id in ranks:
		if kind_of(id) in ["attack", "evolved"] and ranks[id] > 0:
			result[id] = ranks[id]
	return result


func damage_multiplier(rally: bool) -> float:
	return (1.0 + 0.25 * rank("jaws")) * ((1.0 + 0.20 * rank("pack")) * float(mods.rally_damage) if rally else 1.0) * float(mods.damage)


func harvest_multiplier() -> float:
	return (1.0 + 0.30 * rank("brood")) * float(mods.harvest)


func biomass_multiplier() -> float:
	return (1.0 + 0.25 * rank("glutton")) * float(mods.growth)


func loss_after_armor(amount: int, rally: bool) -> int:
	if amount <= 0:
		return 0
	var reduction := 0.10 * rank("armor") + (0.0 if rally else 0.10 * rank("scatter")) + float(mods.armor)
	return maxi(1, ceili(amount * (1.0 - clampf(reduction, -0.5, 0.85))))


func summary() -> String:
	var parts := PackedStringArray()
	for group in [ATTACKS, EVOLVED, TRAITS]:
		for mutation in group:
			if rank(mutation[0]) > 0:
				parts.append("%s %d" % [mutation[1], rank(mutation[0])])
	return " · ".join(parts)


# --- Etappe 10: Regeneration ---------------------------------------------

# Kills je Anführer-LP (0 = Anlage fehlt).
func regeneration_interval() -> int:
	var level := rank("regeneration")
	return int(REGEN_KILLS[mini(level, MAX_RANK) - 1]) if level > 0 else 0


# Mindestabstand zwischen zwei Regenerations-LP in Sekunden (0 = Anlage fehlt).
func regeneration_gap() -> float:
	var level := rank("regeneration")
	return float(REGEN_GAP[mini(level, MAX_RANK) - 1]) if level > 0 else 0.0


# Zählt `count` Kills mit Gewicht `weight` (Moorbrut: REGEN_HORDE_WEIGHT); liefert die
# LP, die der Anführer dafür zurückbekommt. Mit `now` >= 0 (Spielzeit) höchstens 1 LP
# je regeneration_gap(); ohne `now` (Tests/Werkzeuge) ohne Zeitdeckel.
func note_kills(count: int = 1, weight: float = 1.0, now: float = -1.0) -> int:
	var interval := regeneration_interval()
	if interval <= 0 or count <= 0 or weight <= 0.0:
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
	if healed > 0:
		leader_regenerated.emit(healed)
	return healed


# --- Etappe 10: Dornenhaut -----------------------------------------------

func thorn_factor() -> float:
	return THORN_STEP * float(mini(rank("dornenhaut"), MAX_RANK))


func thorn_damage(loss: int, leader_struck: bool = false) -> float:
	var factor := thorn_factor()
	if factor <= 0.0:
		return 0.0
	return factor * (THORN_BASE + THORN_PER_LOSS * float(maxi(0, loss)) + (THORN_LEADER if leader_struck else 0.0))
