extends SceneTree

const RUN_MODEL = preload("res://scripts/run_model.gd")
var failures: Array[String] = []


func _initialize() -> void:
	var model = RUN_MODEL.new()
	var first: int = model.add_corpse(Vector3(3, 0, 4), 12.0)
	_check(model.population == 1 and model.leader_hp == 3, "Lone start: one Mawling, the leader with 3 LP (stage 09)")
	model.population = 25
	# Growth cost comes from TUNING (stage 09: 3.5 biomass per Mawling).
	var cost: float = RUN_MODEL.BIOMASS_PER_MAWLING
	_check(model.corpses.size() == 1, "Corpse created")
	_check(is_equal_approx(model.harvest(first, cost + 0.5), cost + 0.5), "Partial harvest amount")
	_check(model.population == 26, "Exact growth cost")
	_check(is_equal_approx(model.biomass_bank, 0.5), "Biomass remainder")
	_check(is_equal_approx(model.remaining_biomass(first), 12.0 - cost - 0.5), "Corpse keeps remainder")
	var second: int = model.add_corpse(Vector3(-8, 0, 0), 5.0)
	_check(model.corpses.size() == 2, "Old corpse survives new kill")
	_check(is_equal_approx(model.remaining_biomass(first), 12.0 - cost - 0.5), "Old resource did not decay")
	model.harvest(first, 12.0 - cost - 0.5)
	_check(model.remaining_biomass(first) == 0.0, "Fully consumed corpse removed")
	_check(model.corpses.size() == 1 and model.corpses[0].id == second, "Other corpse remains")
	_check(model.population == 25 + int(floor(12.0 / cost)), "Growth from full first corpse")
	model.population = 249
	model.biomass_bank = 0.0
	_check(is_equal_approx(model.harvest(second, 5.0), cost), "Capacity limits harvest")
	_check(model.population == 250, "Population cap")
	_check(is_equal_approx(model.remaining_biomass(second), 5.0 - cost), "Biomass remains at cap")
	_check(model.harvest(second, 1.0) == 0.0, "Full swarm does not consume corpse")
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS: persistent corpses, exact growth, depletion, capacity")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
