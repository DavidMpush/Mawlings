extends SceneTree

const RUN_MODEL = preload("res://scripts/run_model.gd")
var failures: Array[String] = []


func _initialize() -> void:
	var model = RUN_MODEL.new()
	_check(model.population == 1 and model.leader_hp == 100 and model.leader_max_hp == 100, "Lone start: one Mawling, the leader with 100 LP (stage 17c)")
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
	# Etappe 17b: no population limit.
	model.population = 249
	model.biomass_bank = 0.0
	_check(model.biomass_capacity() == INF, "Unlimited capacity")
	_check(is_equal_approx(model.absorb(cost * 10.0), cost * 10.0) and model.population == 259, "Growth past 250 (%d)" % model.population)
	model.absorb(cost * 10000.0)
	_check(model.population == 10259, "Ten thousand more Mawlings (%d)" % model.population)
	# Etappe 17c: real LP per hit, successor with 80 %.
	var hit: Dictionary = model.apply_hit(3, true, false, 30)
	_check(model.leader_hp == 70 and hit.damage == 30 and model.population == 10256, "A leader hit costs its damage in LP (%d)" % model.leader_hp)
	model.leader_invulnerable = 0.0
	_check(model.apply_hit(0, true, true, 500).leader == "hit" and model.leader_hp == 1, "A nonlethal hit never takes the last LP")
	model.leader_invulnerable = 0.0
	_check(model.apply_hit(0, true, false, 5).leader == "swap" and model.leader_max_hp == 80 and model.leader_hp == 80, "The successor leads with 80 %% of the old maximum, fully healed (%d/%d)" % [model.leader_hp, model.leader_max_hp])
	_check(model.heal_leader(50) == 0 and model.leader_hp == 80, "Heal is capped at the maximum")
	model.record_kill("prey")
	model.record_kill("boss")
	_check(model.kills == 2 and model.bosses == 1, "record_kill counts kills and bosses")
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS: absorb, exact growth, no limit, leader LP/heal/successor, kill counts")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
