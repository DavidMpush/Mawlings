extends SceneTree

# Etappe 31 D - Glutpilze and instant map items: 8-12 mushroom baskets per map
# on open ground (no collision), a touch breaks one, items pop out (Heilpilz,
# Zeitstarre, Bildschirm-Biss, Lockruf), walk-in pickup only (no magnet), the
# effects (heal, freeze of enemies / boss / brood with melee still working,
# screen bite with boss share), blinking after 45 s without vanishing, minimap
# data only once discovered, a new map rebuilds them, a restart restores them.

const TUNING = preload("res://scripts/tuning.gd")
const MAP_ITEMS = preload("res://scripts/map_items.gd")
var failures: Array[String] = []
var world: Variant
var swarm: Variant
var arena: Variant
var items: Variant


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	arena = scene.get_node("Arena")
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)
	# A real exploration map.
	arena.set_seed(424242)
	world.reset_run()
	items = world.map_items
	_check(items != null and items.get_parent() == world, "HuntWorld owns the map item layer")
	_check("freeze_left" in world and is_equal_approx(float(world.freeze_left), 0.0), "HuntWorld.freeze_left starts at 0")
	_quiet()
	_population(20)

	# ---- Placement: 8-12 baskets on open ground, spread out, away from the start.
	var total: int = items.count()
	_check(total >= TUNING.MAP_ITEM_COUNT.x and total <= TUNING.MAP_ITEM_COUNT.y, "8-12 Glutpilze on the solo map (%d)" % total)
	var start: Vector3 = swarm.position
	var open := true
	var spaced := true
	for index in items.mushrooms.size():
		var at: Vector3 = items.mushrooms[index].at
		if not arena.is_open(at, 1.2):
			open = false
		for other in range(index + 1, items.mushrooms.size()):
			if Vector3(items.mushrooms[other].at).distance_to(at) < 12.0:
				spaced = false
		_check(Vector2(at.x - start.x, at.z - start.z).length() >= TUNING.MAP_ITEM_START_GAP - 0.5, "No Glutpilz at the start")
	_check(open, "Every Glutpilz stands on open ground")
	_check(spaced, "Glutpilze are spread over the map")
	# Decoration only: the baskets add no obstacle.
	var first: Vector3 = items.mushrooms[0].at
	_check(arena.is_open(first, 0.4) and arena.safe_spawn(first, 0.4).distance_to(first) < 0.01, "A Glutpilz has no collision")
	# A same-seed restart places the same baskets.
	var seen: Array = items.mushrooms.map(func(m): return m.at)

	# ---- A touch breaks one.
	var target: Dictionary = items.mushrooms[0]
	swarm.position = target.at
	_steps(0.1)
	_check(not target.alive and items.count() == total - 1 and items.broken == 1, "One touch breaks a Glutpilz")
	_clear_items()
	# With chance: roughly MAP_ITEM_CHANCE of the rolls give an item.
	var got := 0
	for index in 400:
		if items.rng.randf() < TUNING.MAP_ITEM_CHANCE:
			got += 1
	_check(got > 200 and got < 280, "Item chance about 60 %% (%d / 400)" % got)
	var kinds := {}
	for index in 200:
		kinds[items.roll_id()] = true
	_check(kinds.size() == MAP_ITEMS.ORDER.size(), "All four item kinds roll (%d)" % kinds.size())

	# ---- Heilpilz: walk-in only (no magnet), +30 % max LP.
	swarm.position = Vector3(first.x + 40.0, 0.0, first.z)
	var heal: Dictionary = items.spawn_item("heilpilz", swarm.position + Vector3(3.0, 0, 0))
	world.evolution.boosts["magnet"] = 1.0
	_check(world.magnet_radius() > 3.2, "Test setup: the item lies inside the magnet")
	_steps(1.5)
	_check(items.items.has(heal), "The magnet does not pull map items")
	world.model.leader_hp = 20
	var max_hp: int = world.model.leader_max_hp
	swarm.position = heal.at
	_steps(0.1)
	_check(not items.items.has(heal), "Walking in collects the Heilpilz")
	_check(world.model.leader_hp == mini(max_hp, 20 + ceili(max_hp * TUNING.MAP_ITEM_HEAL)), "Heilpilz heals 30 %% (%d of %d)" % [world.model.leader_hp, max_hp])
	_check(String(items.band_state().get("text", "")).begins_with("HEILPILZ +"), "HUD band: HEILPILZ +N LP")
	_check(String(world._arsenal_hud().band.get("text", "")).begins_with("HEILPILZ"), "The band reaches the arsenal HUD")

	# ---- Zeitstarre: enemies, boss and brood stand; melee still hurts them.
	var home: Vector3 = arena.safe_spawn(Vector3(first.x - 30.0, 0, first.z), 1.0)
	swarm.position = home
	var hunter: Variant = world._spawn_hunter(home + Vector3(6.0, 0, 0))
	var skitter: Variant = world._spawn_skitter(home + Vector3(-6.0, 0, 3.0))
	_steps(1.0)
	var moving_from: Vector3 = hunter.position
	_steps(1.0)
	_check(hunter.position.distance_to(moving_from) > 0.2, "Test setup: an unfrozen hunter moves")
	items.collect("zeitstarre")
	_check(is_equal_approx(float(world.freeze_left), TUNING.MAP_ITEM_FREEZE), "Zeitstarre: freeze_left = %.1f s" % float(world.freeze_left))
	var hunter_at: Vector3 = hunter.position
	var hunter_state: int = int(hunter.state)
	var skitter_at: Vector3 = skitter.position
	_steps(2.0)
	_check(hunter.position.distance_to(hunter_at) < 0.01 and int(hunter.state) == hunter_state, "A frozen hunter neither moves nor attacks")
	_check(skitter.position.distance_to(skitter_at) < 0.01, "A frozen skitter holds still")
	var health: float = hunter.health
	swarm.position = hunter.position + Vector3(0.6, 0, 0)
	_steps(0.5)
	_check(not is_instance_valid(hunter) or hunter.health < health or not world.hunters.has(hunter), "Melee still hurts a frozen enemy")
	_steps(3.0)
	_check(is_equal_approx(float(world.freeze_left), 0.0), "Zeitstarre ends after 5 s")
	_clear_enemies()
	# The brood holds still and does not bite.
	swarm.position = home
	world.horde.spawn_ring(home, 24, 5.0, world.flood_stats())
	_steps(0.6)
	_check(world.horde.count() >= 20, "Test setup: brood around the swarm (%d)" % world.horde.count())
	world.freeze_left = 3.0
	var before: PackedVector3Array = world.horde.positions()
	var population: int = world.model.population
	var bites: int = world.horde.total_bites
	_steps(1.5)
	var after: PackedVector3Array = world.horde.positions()
	var moved := 0.0
	for index in mini(before.size(), after.size()):
		moved = maxf(moved, before[index].distance_to(after[index]))
	_check(moved < 0.05 and world.horde.total_bites == bites, "Frozen brood neither moves nor bites (%.2f m, %d bites)" % [moved, world.horde.total_bites - bites])
	_check(world.model.population >= population, "No losses while frozen")
	world.freeze_left = 0.0
	world.horde.clear()
	# A frozen Bog King does not stomp.
	var boss: Variant = world._spawn_boss(home + Vector3(0, 0, -7.0))
	world.freeze_left = 3.0
	var boss_state: int = int(boss.state)
	var boss_at: Vector3 = boss.position
	_steps(2.0)
	_check(int(boss.state) == boss_state and boss.position.distance_to(boss_at) < 0.01, "A frozen Bog King holds still")
	world.freeze_left = 0.0

	# ---- Bildschirm-Biss: enemies in ~18 m die, the boss loses 10 %, brood dies.
	swarm.position = home
	var near: Variant = world._spawn_hunter(home + Vector3(10.0, 0, 4.0))
	var near_skitter: Variant = world._spawn_skitter(home + Vector3(-8.0, 0, -6.0))
	var far: Variant = world._spawn_hunter(home + Vector3(0, 0, 30.0))
	world.horde.spawn_ring(home, 20, 9.0, world.flood_stats())
	world.horde.step(0.01, PackedVector3Array())
	boss.health = boss.max_health
	var kills: int = world.model.kills if "kills" in world.model else 0
	items.collect("bildschirmbiss")
	_check(absf(boss.health - boss.max_health * (1.0 - TUNING.MAP_ITEM_BITE_BOSS)) < 0.5, "Bog King loses 10 %% (%.0f of %.0f)" % [boss.health, boss.max_health])
	_check(world.horde.count() == 0, "Brood in the radius dies (%d left)" % world.horde.count())
	_steps(0.1)
	_check(not world.hunters.has(near) and not world.skitters.has(near_skitter), "Enemies in the radius die")
	_check(world.hunters.has(far), "An enemy outside the radius lives")
	_check(String(items.band_state().get("text", "")) == "BILDSCHIRM-BISS!", "HUD band: BILDSCHIRM-BISS!")
	if "kills" in world.model:
		_check(int(world.model.kills) > kills, "Screen bite kills count")
	_clear_enemies()

	# ---- Lockruf: the existing Lockruf drops out of the basket.
	var lures: int = world.loot.lures.size()
	var index_lure := _alive_index()
	_check(items.break_mushroom(index_lure, "lockruf") == "lockruf" and world.loot.lures.size() == lures + 1, "Lockruf item = HuntWorld.drop_lure")
	# Empty basket: a few coins.
	var amber_before: float = world.loot.total(world.LOOT.Kind.AMBER)
	items.break_mushroom(_alive_index(), "none")
	_check(world.loot.total(world.LOOT.Kind.AMBER) > amber_before, "An empty basket gives a few Bernstein coins")

	# ---- Lying items blink after 45 s but stay.
	var lying: Dictionary = items.spawn_item("zeitstarre", home + Vector3(12.0, 0, 0))
	swarm.position = home
	_steps(46.0)
	_check(items.items.has(lying), "A lying item never vanishes")
	var hidden := false
	for step_index in 20:
		world.step(0.05)
		if not (lying.pivot as Node3D).visible:
			hidden = true
	_check(hidden, "After 45 s it blinks")

	# ---- Minimap: only discovered ones.
	var state: Dictionary = world._map_state()
	_check(state.has("items") and state["items"] is PackedVector3Array, "Minimap data carries items")
	var listed: PackedVector3Array = state["items"]
	var all_points: PackedVector3Array = items.map_points()
	_check(listed.size() < all_points.size(), "Undiscovered Glutpilze stay hidden (%d of %d)" % [listed.size(), all_points.size()])
	for point in listed:
		_check(world._found(point), "Listed item lies in discovered land")

	# ---- Restart restores; a new map rebuilds.
	world.reset_run()
	items = world.map_items
	_check(items.count() == total and items.items.is_empty(), "Restart restores every Glutpilz (%d)" % items.count())
	_check(items.mushrooms.map(func(m): return m.at) == seen, "Same seed, same places")
	_check(is_equal_approx(float(world.freeze_left), 0.0), "Restart clears the freeze")
	items.spawn_item("heilpilz", swarm.position + Vector3(20, 0, 0))
	arena.set_seed(777001)
	_steps(0.1)
	_check(items.mushrooms.map(func(m): return m.at) != seen and items.count() >= TUNING.MAP_ITEM_COUNT.x, "A new map brings new Glutpilze (%d)" % items.count())
	_check(items.items.size() == 1, "Lying items come along to the new map")
	_finish()


func _alive_index() -> int:
	for index in items.mushrooms.size():
		if items.mushrooms[index].alive:
			return index
	return 0


func _clear_items() -> void:
	for entry in items.items:
		entry.node.queue_free()
	items.items.clear()


func _clear_enemies() -> void:
	for group in [world.hunters, world.skitters, world.leapers]:
		for enemy in group:
			enemy.queue_free()
		group.clear()
	if world.boss != null:
		world.boss.queue_free()
		world.boss = null
	if world.horde != null:
		world.horde.clear()


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
	world.surge_next = 1000000.0
	for shrine in world.shrines.shrines:
		shrine.at = Vector3(5000, 0, -5000)
	for cocoon in world.chests.cocoons:
		cocoon.at = Vector3(5000, 0, 5000)


func _steps(seconds: float) -> void:
	for index in int(round(seconds / 0.05)):
		world.unit_points_valid = false
		world.step(0.05)
		while world.choosing():
			world.choose_mutation(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("PASS map_items: 8-12 Glutpilze on open ground without collision, touch breaks, 60 % items, Heilpilz +30 %, Zeitstarre holds enemies/boss/brood (melee still hits), Bildschirm-Biss (boss 10 %), Lockruf, coins, blink, minimap after discovery, restart + new map")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL map_items: %d" % failures.size())
		quit(1)
