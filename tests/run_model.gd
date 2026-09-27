extends SceneTree

const RUN_MODEL = preload("res://scripts/run_model.gd")
var failures: Array[String] = []


func _initialize() -> void:
	var model = RUN_MODEL.new()
	_check(model.population == 1 and model.leader_hp == 3, "Lone start: one Mawling, the leader with 3 LP (stage 09)")
	model.population = 25
	# Growth cost comes from TUNING (stage 09: 3.5 biomass per Mawling).
	# Etappe 16: biomass arrives through collected loot crystals (absorb()).
	var cost: float = RUN_MODEL.BIOMASS_PER_MAWLING
	_check(is_equal_approx(model.absorb(cost + 0.5), cost + 0.5), "Absorbed amount")
	_check(model.population == 26, "Exact growth cost")
	_check(is_equal_approx(model.biomass_bank, 0.5), "Biomass remainder")
	_check(is_equal_approx(model.consumed_biomass, cost + 0.5), "Consumed biomass counted")
	model.absorb(12.0)
	_check(model.population == 26 + int(floor((12.5) / cost)), "Growth from a big crystal")
	model.population = 249
	model.biomass_bank = 0.0
	_check(is_equal_approx(model.biomass_capacity(), cost), "Capacity = one more Mawling")
	_check(is_equal_approx(model.absorb(5.0), cost), "Capacity limits absorb (the caller keeps the rest)")
	_check(model.population == 250, "Population cap")
	_check(model.absorb(1.0) == 0.0 and model.biomass_capacity() == 0.0, "Full swarm absorbs nothing")
	model.record_kill("prey")
	model.record_kill("boss")
	_check(model.kills == 2 and model.bosses == 1, "record_kill counts kills and bosses")
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS: absorb, exact growth, capacity, kill counts")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
