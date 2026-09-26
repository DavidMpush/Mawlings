extends RefCounted

const TRAITS = [
	["jaws", "Reißzähne", "+25 % Angriffsschaden pro Rang"],
	["brood", "Schnelle Brut", "+30 % Erntetempo pro Rang"],
	["glutton", "Vielfraß", "+25 % Biomasse bei künftigen Kills"],
	["pack", "Rudelinstinkt", "+20 % Schaden bei Rally pro Rang"],
	["scatter", "Fluchtreflex", "−10 % Verluste ohne Rally pro Rang"],
	["armor", "Knochenpanzer", "−10 % Verluste pro Rang"]
]
const MAX_RANK = 3
var ranks: Dictionary = {}
var dna := 0
var level := 0
var offers: Array = []
var rng := RandomNumberGenerator.new()

func _init() -> void:
	rng.randomize()

func threshold() -> int:
	return 20 + level * 10

func complete() -> bool:
	return level >= TRAITS.size() * MAX_RANK

func earn(amount: int) -> void:
	if complete():
		return
	dna += maxi(0, amount)
	_prepare()

func _prepare() -> void:
	if complete() or dna < threshold() or not offers.is_empty():
		return
	var pool: Array = []
	for mutation in TRAITS:
		if rank(mutation[0]) < MAX_RANK:
			pool.append(mutation)
	while offers.size() < 3 and not pool.is_empty():
		offers.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))

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

func rank(id: String) -> int:
	return ranks.get(id, 0)

func damage_multiplier(rally: bool) -> float:
	return (1.0 + 0.25 * rank("jaws")) * (1.0 + 0.20 * rank("pack") if rally else 1.0)

func harvest_multiplier() -> float:
	return 1.0 + 0.30 * rank("brood")

func biomass_multiplier() -> float:
	return 1.0 + 0.25 * rank("glutton")

func loss_after_armor(amount: int, rally: bool) -> int:
	if amount <= 0:
		return 0
	var reduction := 0.10 * rank("armor") + (0.0 if rally else 0.10 * rank("scatter"))
	return maxi(1, ceili(amount * (1.0 - reduction)))

func summary() -> String:
	var parts := PackedStringArray()
	for mutation in TRAITS:
		if rank(mutation[0]) > 0:
			parts.append("%s %d" % [mutation[1], rank(mutation[0])])
	return " · ".join(parts)
