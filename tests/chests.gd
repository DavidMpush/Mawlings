extends SceneTree

# Etappe 17 Welle 2 - Kokons: map cocoons cost biomass (price rises per opened
# cocoon), open after the swarm held 1 s inside, pay with the bank + Mawlings
# (never the leader), grant their loot at once, stay closed and red when too
# expensive, stay on the map until opened; golden cocoons are free (at least
# epic); elites drop a free small cocoon (at least rare); bosses drop a golden
# one that offers 1 of 3 (evolution guaranteed when ready); amber relic finds.
const TUNING = preload("res://scripts/tuning.gd")
const STATS = preload("res://scripts/progression/stats.gd")
var failures: Array[String] = []
var world: Variant
var swarm: Variant
var chests: Variant


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)
	chests = world.chests
	_check(chests != null and chests.get_parent() == world, "HuntWorld owns the cocoon layer")
	_quiet()
	_check(chests.closed_count("map") >= 3 and chests.closed_count("gold") >= 1, "Seed 0: fallback map and golden cocoons lie on open ground (%d/%d)" % [chests.closed_count("map"), chests.closed_count("gold")])
	# ---- Start cocoon: free, 15-30 m around the start, always on the minimap.
	var start: Dictionary = {}
	for entry in chests.cocoons:
		if entry.kind == "start":
			start = entry
	_check(not start.is_empty(), "A start cocoon lies near the start")
	if not start.is_empty():
		var off := Vector2(start.at.x - swarm.position.x, start.at.z - swarm.position.z).length()
		_check(off >= 13.0 and off <= 33.0, "Start cocoon 15-30 m from the start (%.1f m)" % off)
		_check(world._arsenal_marks(chests).any(func(mark): return mark.kind == "start"), "Start cocoon is on the minimap without discovery")
		var weapons_before: int = world.evolution.arsenal.weapons().size()
		_population(10)
		swarm.position = start.at
		_steps(1.7)
		_check(start.has("rarity") and String(start.rarity) in ["common", "rare"] and world.model.population >= 10, "Start cocoon is free, common or rare (%s)" % str(start.get("rarity", "-")))
		_check(world.evolution.arsenal.weapons().size() == weapons_before + 1, "With one weapon the start cocoon brings a second weapon")
		_check(world.evolution.arsenal.chests_opened == 0, "It does not raise the map price")
		swarm.position = Vector3.ZERO
	# Park the fallback cocoons far away (they are tested through their own spawns).
	for entry in chests.cocoons:
		entry.at = Vector3(400, 0, 400)

	# ---- Price rises per opened map cocoon; luck discounts it.
	var evo: Variant = world.evolution
	var p0: int = evo.chest_price()
	_check(p0 == 25, "First map cocoon costs 25 biomass (%d)" % p0)

	# ---- Hold 1 s inside: pays and grants at once.
	var spot := Vector3(20, 0, 0)
	var cocoon: Dictionary = chests.spawn("map", spot)
	_population(40)
	world.model.amber = 40
	swarm.position = spot + Vector3(9, 0, 0)
	_steps(0.5)
	_check(int(cocoon.state) == 0 and float(cocoon.hold) == 0.0, "Outside the cocoon nothing happens")
	swarm.position = spot
	_steps(0.6)
	_check(int(cocoon.state) == 0 and float(cocoon.hold) > 0.4, "Holding fills (%.2f s), not open yet" % float(cocoon.hold))
	swarm.position = spot + Vector3(9, 0, 0)
	_steps(0.5)
	_check(float(cocoon.hold) < 0.1, "Leaving drains the hold (%.2f)" % float(cocoon.hold))
	swarm.position = spot
	var revision: int = evo.revision
	_steps(1.0)
	_check(int(cocoon.state) >= 1, "After 1 s inside the cocoon opens")
	_steps(1.1)
	_check(world.model.amber == 40 - p0, "It cost exactly %d Bernstein (left %d)" % [p0, world.model.amber])
	_check(world.model.population >= 40, "No Mawling is spent on a cocoon (40 -> %d)" % world.model.population)
	_check(evo.revision > revision, "The loot was granted at once (revision %d -> %d)" % [revision, evo.revision])
	_check(evo.chest_offers.is_empty() and not world.choosing(), "A map cocoon never pauses")
	var p1: int = evo.chest_price()
	_check(p1 == int(round(evo.arsenal.CHEST_BASE * evo.arsenal.CHEST_GROWTH)) and p1 > p0, "The next one costs more (%d)" % p1)
	_check(chests.opened == 1 and not chests.cocoons.has(cocoon), "Opened cocoon is gone after its burst")
	_check(chests.active_beams() >= 1, "A light beam rises in the rarity colour")
	var state: Dictionary = chests.hud_state(null, swarm.position)
	_check(not (state.card as Dictionary).is_empty(), "A loot card pops up in the HUD")
	evo.ranks["luck"] = 5
	evo.stats.units["luck"] = 5.0
	_check(evo.chest_price() < p1, "Glück makes it cheaper (%d < %d)" % [evo.chest_price(), p1])
	evo.ranks.erase("luck")
	evo.stats.units.erase("luck")

	# ---- Too expensive: stays closed, the pill turns red, the swarm keeps its animals.
	var dear: Dictionary = chests.spawn("map", Vector3(-20, 0, 0))
	_population(40)
	world.model.amber = 5
	swarm.position = dear.at
	_steps(1.4)
	_check(int(dear.state) == 0 and bool(dear.denied), "Too expensive: the cocoon stays closed")
	_check(world.model.population == 40 and world.model.amber == 5, "Nothing is taken (pop %d, Bernstein %d)" % [world.model.population, world.model.amber])
	var tags: Array = []
	var camera: Camera3D = scene.get_viewport().get_camera_3d()
	tags = chests.hud_state(camera, swarm.position).tags
	var red := false
	for tag in tags:
		if int(tag.price) > 0 and not bool(tag.afford):
			red = true
	_check(camera == null or red, "Its price pill shows red (too expensive)")
	# ---- It stays on the map until opened.
	swarm.position = Vector3(60, 0, 60)
	_steps(90.0)
	_check(chests.cocoons.has(dear) and int(dear.state) == 0, "An unopened cocoon stays on the map")
	world.model.amber = 200
	swarm.position = dear.at
	_steps(1.6)
	_check(int(dear.state) != 0 or not chests.cocoons.has(dear), "With enough Bernstein it opens later")

	# ---- Bernstein drops from kills and is collected by the magnet.
	var amber_before: int = world.model.amber
	var prey_target: Variant = world.PREY.new()
	prey_target.position = Vector3(60, 0, -60)
	world.add_child(prey_target)
	world.prey.append(prey_target)
	world._kill_prey(prey_target)
	var coins := 0.0
	coins = world.loot.total(world.LOOT.Kind.AMBER)
	_check(coins >= 1.0, "A kill drops Bernstein coins (%.0f)" % coins)
	swarm.position = Vector3(60, 0, -60)
	_steps(2.5)
	_check(world.model.amber > amber_before, "The magnet brings the Bernstein in (%d -> %d)" % [amber_before, world.model.amber])

	# ---- Golden map cocoon: free, at least epic, no price step.
	var opened_gold: int = evo.arsenal.chests_opened
	var gold: Dictionary = chests.spawn("gold", Vector3(0, 0, 30))
	var pop_before: int = world.model.population
	swarm.position = gold.at
	_steps(1.7)
	_check(gold.has("result") and pop_before == world.model.population, "Golden cocoon is free")
	_check(gold.has("rarity") and STATS.rarity_at_least(String(gold.rarity), "epic"), "Golden cocoon gives at least epic (%s)" % str(gold.get("rarity", "-")))
	_check(evo.arsenal.chests_opened == opened_gold, "It does not raise the map price")

	# ---- Elite: a free small cocoon instead of the Alpha-Kern, at least rare.
	var elite: Variant = world.spawn_elite(Vector3(0, 0, -30))
	elite.health = 0.0
	world._resolve_death(elite, "hunter")
	var dropped: Dictionary = chests.nearest(Vector3(0, 0, -30), 6.0, ["elite"])
	_check(not dropped.is_empty(), "A dead elite drops a small cocoon")
	_check(world.alpha_pickups.is_empty(), "No Alpha-Kern any more")
	pop_before = world.model.population
	var opened_before: int = evo.arsenal.chests_opened
	swarm.position = dropped.at
	_steps(1.7)
	_check(dropped.has("rarity") and STATS.rarity_at_least(String(dropped.rarity), "rare"), "Elite cocoon: at least rare (%s)" % str(dropped.get("rarity", "-")))
	_check(world.model.population >= pop_before and evo.arsenal.chests_opened == opened_before, "Elite cocoon is free (pop %d -> %d)" % [pop_before, world.model.population])

	# ---- Boss: golden cocoon, 1 of 3 through the chest choice; evolution guaranteed.
	evo.ranks["rudelbiss"] = 5
	evo.relics["rudelhorn"] = 1
	world._drop_cocoon("boss", Vector3(30, 0, 30))
	var boss_cocoon: Dictionary = chests.nearest(Vector3(30, 0, 30), 6.0, ["boss"])
	_check(not boss_cocoon.is_empty(), "A dead boss leaves a golden cocoon")
	swarm.position = boss_cocoon.at
	for index in 60:
		world.step(0.05)
		if world.choosing():
			break
	_check(world.choosing() and evo.chest_offers.size() == 3, "Boss cocoon opens the 1-of-3 choice (%d)" % evo.chest_offers.size())
	var ids: Array = evo.chest_offers.map(func(entry): return entry[0])
	_check(ids.has("meute"), "The ready evolution is guaranteed (%s)" % str(ids))
	var epic := true
	for entry in evo.chest_offers:
		if not STATS.rarity_at_least(String(entry[3]), "epic"):
			epic = false
	_check(epic, "Boss cocoon offers are at least epic")
	var slot: int = ids.find("meute")
	world.choose_mutation(slot)
	_check(not world.choosing() and evo.evolutions.has("meute"), "Choosing takes the evolution")
	_check(world.evolve_name != "", "The evolution pick plays the evolution moment")

	# ---- Only the first boss cocoon of a biome cycle guarantees the evolution.
	evo.ranks["sporenwolke"] = 5
	evo.relics["sporenherz"] = 1
	for round_index in 2:
		if round_index == 1:
			evo.evolution_guarantee = true   # what HuntWorld does on arrival in a new biome
		world._drop_cocoon("boss", Vector3(-30, 0, 30))
		var next_boss: Dictionary = chests.nearest(Vector3(-30, 0, 30), 6.0, ["boss"])
		swarm.position = next_boss.at
		for index in 60:
			world.step(0.05)
			if world.choosing():
				break
		var offered: Array = evo.chest_offers.map(func(entry): return entry[0])
		if round_index == 0:
			_check(not offered.has("pilzreich") and offered.size() == 3, "The second boss cocoon of a cycle offers no guaranteed evolution (%s)" % str(offered))
		else:
			_check(offered.has("pilzreich"), "A new biome cycle guarantees it again (%s)" % str(offered))
		world.choose_mutation(0)
		_steps(0.6)

	# ---- Amber nodes give only Bernstein and DNA (no biomass, no relic/booster bonus).
	var nodes: Variant = world.loot_nodes
	if nodes != null and nodes.points.size() > 0:
		var relic_count := 0
		for id in evo.relics:
			relic_count += int(evo.relics[id])
		var bio_before: float = world.loot.total(world.LOOT.Kind.BIOMASS)
		var amber_items: float = world.loot.total(world.LOOT.Kind.AMBER)
		nodes._break(0)
		_check(world.loot.total(world.LOOT.Kind.AMBER) > amber_items and is_equal_approx(world.loot.total(world.LOOT.Kind.BIOMASS), bio_before), "An amber node bursts into Bernstein, no biomass")
		var relic_after := 0
		for id in evo.relics:
			relic_after += int(evo.relics[id])
		_check(relic_after == relic_count and world.powerups.pickups.is_empty(), "No relic or power-up from amber nodes")

	# ---- Minimap marks.
	world._drop_cocoon("elite", Vector3(-40, 0, -40))
	var marks: Array = world._map_state().chests
	_check(marks.any(func(mark): return bool(mark.dropped)), "Dropped cocoons are on the minimap data (%d marks)" % marks.size())
	_check(not marks.any(func(mark): return Vector3(mark.at).distance_to(Vector3(400, 0, 400)) < 1.0), "Undiscovered cocoons stay hidden")

	# ---- HUD: Bernstein pill value, violet XP bar without numbers.
	world._update_hud("")
	var controls: Node = scene.get_node("HUD/Controls")
	_check(int(controls.get_meta("amber", -1)) == world.model.amber or int(controls.get("amber") if "amber" in controls else -1) == world.model.amber, "The HUD carries the Bernstein count")
	var top: Node = controls.get_node_or_null("hud_top")
	_check(top != null and top.has_method("_xp_fill") and top.has_method("_b_draw_xp"), "hud_top has the XP bar")
	if top != null:
		var xp_source: String = (top.get_script() as Script).source_code
		var body := xp_source.substr(xp_source.find("func _b_draw_xp"), 1400)
		body = body.substr(0, body.find("
# ----"))
		_check(not body.contains("text_outlined") and not body.contains("Kit.number") and not body.contains("draw_string"), "The XP bar shows no numbers")
		world.evolution.dna = world.evolution.threshold() / 2
		_check(absf(top._xp_fill() - 0.5) < 0.05, "The XP bar fills with DNA (%.2f)" % top._xp_fill())

	_finish()


func _population(count: int) -> void:
	world.model.population = count
	world.model.biomass_bank = 0.0
	swarm.set_population(count, false)
	world.unit_points_valid = false


func _quiet() -> void:
	for target in world.prey:
		target.queue_free()
	world.prey.clear()
	world.spawn_clock = -1000000.0
	world.hunter_clock = 1000000.0
	world.skitter_clock = 1000000.0
	world.leaper_clock = 1000000.0
	world.boss_clock = 1000000.0
	world.elite_clock = 1000000.0
	world.nest_clock = 1000000.0
	world.flood_start = 1000000.0
	world.apex_state = 4
	world.totem_offered = true
	# Keep the shrines and knolls out of the way.
	for shrine in world.shrines.shrines:
		shrine.at = Vector3(500, 0, -500)
	for knoll in world.powerups.knolls:
		knoll.at = Vector3(-500, 0, 500)


func _steps(seconds: float) -> void:
	for index in int(round(seconds / 0.05)):
		world.unit_points_valid = false
		world.step(0.05)
		while not world.evolution.offers.is_empty():
			world.choose_mutation(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("PASS chests: price, hold, payment, loot, too expensive, stays, golden, elite, boss 1 of 3, Bernstein economy, amber nodes, XP bar")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL chests: %d" % failures.size())
		quit(1)
