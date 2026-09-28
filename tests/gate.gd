extends SceneTree

# Etappe 30 (user request): on a seeded map every world has ONE boss arena where
# the endboss (apex) rises, and next to it the sealed gate (Migrationsschlund)
# stands from the start of the world. It cannot be entered while sealed, shows
# on the map only once discovered, and unseals after the apex falls - no walk
# across the map to a separate maw clearing. After the migration the new world
# gets its own boss arena + sealed gate. The minimap no longer draws type
# symbols on empty clearings (only real objects and the discovered boss arena).

const TUNING = preload("res://scripts/tuning.gd")
const DT := 0.05
var failures: Array[String] = []
var world: Variant
var swarm: Variant
var arena: Variant


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

	world.config = {"strain_id": "glutmaw", "seed": 4242}
	arena.set_seed(4242)
	world.reset_run()
	world.config = {}
	_quiet()
	var gate: Variant = world.gate
	_check(gate != null and is_instance_valid(gate), "A sealed gate stands from the start of the world")
	_check(world.boss_site.is_finite(), "The world has one boss arena")
	if gate == null or not world.boss_site.is_finite():
		_finish(scene)
		return
	_check(bool(gate.sealed), "The gate is sealed")
	var gap: float = Vector2(gate.position.x - world.boss_site.x, gate.position.z - world.boss_site.z).length()
	_check(gap > 6.0 and gap < TUNING.GATE_OFFSET + 8.0, "Gate next to the boss arena (%.1f m)" % gap)
	_check(arena.is_open(gate.position, 1.0) and arena.is_inside(gate.position, 1.0), "Gate on open ground inside the map")
	_check(world.portal == null, "No open maw before the apex")
	# Sealed: standing in it does nothing.
	swarm.position = gate.position
	world.unit_points_valid = false
	for index in 60:
		world.step(DT)
	_check(world.migration_state == 0 and float(gate.hold) == 0.0, "A sealed gate cannot be entered")
	# Map: shown only once discovered.
	var state: Dictionary = world._map_state()
	var shown: bool = (state.get("portal", Vector3.INF) as Vector3).is_finite()
	_check(shown == world._found(gate.position), "Gate on the map exactly when discovered (%s / %s)" % [shown, world._found(gate.position)])

	# The apex rises at the boss arena.
	swarm.position = arena.safe_spawn(world.boss_site + Vector3(0, 0, 30), 1.0)
	world.unit_points_valid = false
	world.apex_state = 0
	world.model.population = 200
	swarm.set_population(200, false)
	world.begin_apex_warning()
	_check(Vector2(world.apex_spot.x - world.boss_site.x, world.apex_spot.z - world.boss_site.z).length() < 6.0, "The apex rises at the world's boss arena (%.1f m off)" % Vector2(world.apex_spot.x - world.boss_site.x, world.apex_spot.z - world.boss_site.z).length())
	# Kill it right there -> the gate unseals (the same node becomes the portal).
	var apex: Variant = world.spawn_apex(world.apex_spot)
	apex.health = 0.0
	world.step(DT)
	_check(world.apex_state == 3, "Apex defeated")
	_check(world.portal_point.distance_to(gate.position) < 0.1, "The maw point is the sealed gate")
	for index in int(ceil((TUNING.APEX_PORTAL_DELAY + 0.5) / DT)):
		world.step(DT)
		if world.choosing():
			world.evolution.chest_offers.clear()
			world.evolution.offers.clear()
	_check(world.portal == gate and world.gate == null, "The gate itself opens (no second maw)")
	_check(not bool(gate.sealed), "Unsealed after the kill")
	# Enter it -> migration -> a new world with its own sealed gate.
	swarm.position = gate.position
	world.unit_points_valid = false
	for index in int(ceil((TUNING.MIGRATION_HOLD_SECONDS + 3.0) / DT)):
		world.step(DT)
		if world.choosing():
			world.evolution.chest_offers.clear()
			world.evolution.offers.clear()
		if world.arrivals > 0 and world.migration_state != 1:
			break
	_check(world.arrivals == 1, "Migration through the unsealed gate")
	var next_gate: Variant = world.gate
	_check(next_gate != null and is_instance_valid(next_gate) and next_gate != gate and bool(next_gate.sealed), "The new world has its own sealed gate")
	_check(world.boss_site.is_finite() and Vector2(next_gate.position.x - world.boss_site.x, next_gate.position.z - world.boss_site.z).length() < TUNING.GATE_OFFSET + 8.0, "... next to its boss arena")

	# Minimap: no symbols on empty clearings any more (only start/arrival dots).
	var source := FileAccess.get_file_as_string("res://scripts/ui/hud_minimap.gd")
	_check(source.find("SITE_MARKS[type]") < 0, "Minimap draws no type symbol on clearings")
	_finish(scene)


func _quiet() -> void:
	for target in world.prey:
		target.queue_free()
	world.prey.clear()
	world.spawn_clock = -1000000.0
	for clock in ["hunter_clock", "skitter_clock", "leaper_clock", "elite_clock", "nest_clock", "boss_clock"]:
		world.set(clock, 1000000.0)
	world.flood_start = 1000000.0
	world.surge_next = 1000000.0
	world.model.leader_invulnerable = 1.0e9


func _finish(scene: Node) -> void:
	arena.set_seed(0)
	scene.queue_free()
	await process_frame
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS gate: one boss arena per world, sealed gate beside it from the start (not enterable, on the map once found), apex rises there, the gate itself unseals after the kill, migration -> new world with its own sealed gate; no symbols on empty clearings")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
