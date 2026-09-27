extends RefCounted

const TUNING = preload("res://scripts/tuning.gd")

# Gameplay data stays independent of the 3D nodes. Etappe 16: biomass arrives
# through collected loot crystals (scripts/loot.gd) and absorb(); the crystals
# lying on the map are the run's stored resources. apply_loss() is the raw loss
# (tests, direct use); HuntWorld resolves hits through apply_hit() (leader rules).
const MAX_POPULATION := 250
const BIOMASS_PER_MAWLING: float = TUNING.BIOMASS_PER_MAWLING

var population: int = TUNING.START_POPULATION
var biomass_bank := 0.0
var kills := 0
var elapsed := 0.0
var peak_population: int = TUNING.START_POPULATION
var consumed_biomass := 0.0
var lost_population := 0
var extinct := false
# Run configuration (difficulty); defaults reproduce the unconfigured prototype.
var pressure_doubling: float = TUNING.PRESSURE_DOUBLING_SECONDS
# Run statistics for the meta layer (see RunStats in stages/03_progression.md).
var kills_by_type: Dictionary = {"prey": 0, "hunter": 0, "skitter": 0, "leaper": 0, "boss": 0}
var bosses := 0
var used_rally := false
# Anführer (Etappe 09): units[0]; Lebenspunkte, Unverwundbarkeit (Sekunden),
# Wechsel- und Trefferzähler. Meilensteine zählen je Run einmal (auch nach Verlust).
var leader_max_hp: int = TUNING.LEADER_HP
var leader_hp: int = TUNING.LEADER_HP
var leader_invulnerable := 0.0
var leader_swaps := 0
var leader_hits := 0
var milestones_reached: Array[int] = []
# Neuester erstmals erreichter Meilenstein seit dem letzten take_milestone() (0 = keiner).
var pending_milestone := 0
var heal_steps := 0


func _init() -> void:
	_mark_reached()


func configure(start_population: int, doubling_seconds: float, leader_hp_value: int = TUNING.LEADER_HP) -> void:
	population = clampi(start_population, 1, MAX_POPULATION)
	peak_population = population
	pressure_doubling = maxf(1.0, doubling_seconds)
	leader_max_hp = maxi(1, leader_hp_value)
	leader_hp = leader_max_hp
	leader_invulnerable = 0.0
	milestones_reached.clear()
	_mark_reached()


# Start population counts as already reached (no banner, no heal).
func _mark_reached() -> void:
	for step in TUNING.MILESTONES:
		if population >= int(step) and not milestones_reached.has(int(step)):
			milestones_reached.append(int(step))
	heal_steps = peak_population / TUNING.LEADER_HEAL_STEP
	pending_milestone = 0


# Returns and clears the newest milestone reached for the first time.
func take_milestone() -> int:
	var value := pending_milestone
	pending_milestone = 0
	return value


# First-time population steps: milestones once per run, +1 leader LP per 25.
func _note_growth() -> void:
	for step in TUNING.MILESTONES:
		if population >= int(step) and not milestones_reached.has(int(step)):
			milestones_reached.append(int(step))
			pending_milestone = maxi(pending_milestone, int(step))
	var steps := peak_population / TUNING.LEADER_HEAL_STEP
	while heal_steps < steps:
		heal_steps += 1
		leader_hp = mini(leader_max_hp, leader_hp + 1)


# One resolved hit under the leader rules. `followers` animals other than the
# leader die (never the leader: at most population - 1); a struck leader loses
# 1 LP unless invulnerable (and a `nonlethal` source never takes its last LP).
# At 0 LP the leader dies: the next animal leads with max(1, old max - 1) LP, or
# the run ends when it was the last one.
# Result: {"lost": animals lost, "leader": "none" | "blocked" | "hit" | "swap" | "extinct"}.
func apply_hit(followers: int, leader_struck: bool, nonlethal: bool = false) -> Dictionary:
	if extinct:
		return {"lost": 0, "leader": "none"}
	var loss := clampi(followers, 0, population - 1)
	population -= loss
	lost_population += loss
	var leader := "none"
	if leader_struck:
		if leader_invulnerable > 0.0 or (nonlethal and leader_hp <= 1):
			leader = "blocked"
		else:
			leader_hp -= 1
			leader_hits += 1
			leader_invulnerable = TUNING.LEADER_INVULNERABLE_SECONDS
			leader = "hit"
			if leader_hp <= 0:
				population -= 1
				lost_population += 1
				loss += 1
				if population <= 0:
					population = 0
					leader_hp = 0
					extinct = true
					leader = "extinct"
				else:
					leader_max_hp = maxi(1, leader_max_hp - 1)
					leader_hp = leader_max_hp
					leader_swaps += 1
					leader = "swap"
	return {"lost": loss, "leader": leader}


# Counts one defeated creature by type; called exactly once per death.
func record_kill(kind: String) -> void:
	kills += 1
	kills_by_type[kind] = int(kills_by_type.get(kind, 0)) + 1
	if kind == "boss":
		bosses += 1


func advance(delta: float) -> void:
	if not extinct:
		elapsed += maxf(0.0, delta)
		leader_invulnerable = maxf(0.0, leader_invulnerable - maxf(0.0, delta))


func pressure() -> float:
	# Floating-point guard, not a run timer or victory condition.
	return pow(2.0, minf(elapsed / pressure_doubling, 40.0))


func apply_loss(amount: int) -> int:
	if extinct:
		return 0
	var loss := mini(maxi(0, amount), population)
	population -= loss
	lost_population += loss
	extinct = population == 0
	if extinct:
		leader_hp = 0
	return loss


# Biomass the swarm can still take before it reaches MAX_POPULATION.
func biomass_capacity() -> float:
	if extinct:
		return 0.0
	return maxf(0.0, float(MAX_POPULATION - population) * BIOMASS_PER_MAWLING - biomass_bank)


# Collected biomass (a loot crystal reached the swarm): banks it and grows one
# Mawling per BIOMASS_PER_MAWLING. Returns the amount taken (never above the
# capacity; the caller drops the rest back as a crystal).
func absorb(amount: float) -> float:
	if extinct or amount <= 0.0:
		return 0.0
	var consumed: float = minf(amount, biomass_capacity())
	if consumed <= 0.0:
		return 0.0
	biomass_bank += consumed
	consumed_biomass += consumed
	var newborn := mini(int(floor((biomass_bank + 0.00001) / BIOMASS_PER_MAWLING)), MAX_POPULATION - population)
	population += newborn
	peak_population = maxi(peak_population, population)
	biomass_bank -= float(newborn) * BIOMASS_PER_MAWLING
	if newborn > 0:
		_note_growth()
	return consumed
