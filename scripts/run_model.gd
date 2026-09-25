extends RefCounted

const TUNING = preload("res://scripts/tuning.gd")

# Gameplay data stays independent of the 3D nodes. A corpse is removed only
# when its last biomass has actually been consumed.
const MAX_POPULATION := 250
const BIOMASS_PER_MAWLING := 2.0

var population := 25
var biomass_bank := 0.0
var corpses: Array[Dictionary] = []
var next_corpse_id := 1
var kills := 0
var elapsed := 0.0
var peak_population := 25
var consumed_biomass := 0.0
var lost_population := 0
var extinct := false


func advance(delta: float) -> void:
	if not extinct:
		elapsed += maxf(0.0, delta)


func pressure() -> float:
	# Floating-point guard, not a run timer or victory condition.
	return pow(2.0, minf(elapsed / TUNING.PRESSURE_DOUBLING_SECONDS, 40.0))


func apply_loss(amount: int) -> int:
	if extinct:
		return 0
	var loss := mini(maxi(0, amount), population)
	population -= loss
	lost_population += loss
	extinct = population == 0
	return loss


func add_corpse(location: Vector3, biomass: float) -> int:
	if biomass <= 0.0 or extinct:
		return -1
	var id := next_corpse_id
	next_corpse_id += 1
	corpses.append({"id": id, "position": location, "remaining": biomass, "initial": biomass})
	kills += 1
	return id


func remaining_biomass(id: int) -> float:
	for corpse in corpses:
		if corpse.id == id:
			return corpse.remaining
	return 0.0


func harvest(id: int, amount: float) -> float:
	if extinct or amount <= 0.0 or population >= MAX_POPULATION:
		return 0.0
	for index in corpses.size():
		var corpse := corpses[index]
		if corpse.id != id:
			continue
		var capacity := float(MAX_POPULATION - population) * BIOMASS_PER_MAWLING - biomass_bank
		var consumed: float = minf(amount, minf(corpse.remaining, maxf(0.0, capacity)))
		if consumed <= 0.0:
			return 0.0
		corpse.remaining -= consumed
		biomass_bank += consumed
		consumed_biomass += consumed
		var newborn := mini(int(floor((biomass_bank + 0.00001) / BIOMASS_PER_MAWLING)), MAX_POPULATION - population)
		population += newborn
		peak_population = maxi(peak_population, population)
		biomass_bank -= float(newborn) * BIOMASS_PER_MAWLING
		if corpse.remaining <= 0.00001:
			corpses.remove_at(index)
		else:
			corpses[index] = corpse
		return consumed
	return 0.0
