extends SceneTree

# Glutsumpf eruptions (scripts/eruptions.gd): telegraph before damage, seeded
# determinism, free start zone, frequency rising with pressure, pause (delta 0),
# Verdant stays calm, contains()/clear() and the colour-blind palette.

const ARENA = preload("res://scripts/arena.gd")
const ERUPTIONS = preload("res://scripts/eruptions.gd")
const STEP := 1.0 / 60.0

var failures: Array[String] = []
var holder: Node3D
var arena: Variant
var eruptions: Variant


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_setup(0)
	var spot := _swarm_spot()
	_check(spot != Vector3.INF, "Found a Glutsumpf spot with eruption sources")
	_check_verdant_calm(spot)
	arena.set_biome("glutsumpf")
	_check_telegraph(spot)
	_check_pause(spot)
	_check_contains_and_clear(spot)
	_check_frequency(spot)
	_check_start_zone()
	_check_determinism(spot)
	_check_colorblind()
	holder.queue_free()
	await process_frame
	await _check_hunt_world()
	if failures.is_empty():
		print("PASS eruptions: telegraph %.1f s before damage, radius %.1f m, seeded determinism, start zone free, frequency rises with pressure, pause, verdant calm, contains/clear, colour-blind, HuntWorld hit path + hint + reset" % [ERUPTIONS.WARNING_SECONDS, ERUPTIONS.RADIUS])
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


# Etappe 09: HuntWorld owns an Eruptions node and resolves each impact through
# the enemy area path (per animal, leader loses 1 LP); hint during the warning.
func _check_hunt_world() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var world: Variant = scene.get_node("HuntWorld")
	var swarm: Variant = scene.get_node("Swarm")
	var hud: Variant = scene.get_node("HUD/Controls")
	var main_arena: Variant = scene.get_node("Arena")
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)
	world.reset_run()
	_check(world.eruptions != null and world.eruptions.arena == main_arena, "HuntWorld creates its eruptions with the arena")
	main_arena.set_biome("glutsumpf")
	arena = main_arena
	var spot := _swarm_spot()
	main_arena.set_biome("glutsumpf")
	world.model.population = 25
	swarm.set_population(25, false)
	swarm.position = spot
	for prey in world.prey:
		prey.position = spot + Vector3(40, 0, 40)
	world.eruptions.erupt_soon()
	world.step(STEP)
	_check(not world.eruptions.pending.is_empty(), "Eruption announced in the running world")
	if world.eruptions.pending.is_empty():
		scene.queue_free()
		return
	_check(String(hud.hint) == "LAVA BRICHT AUS!", "HUD hint during the warning (got '%s')" % hud.hint)
	# Move the pending eruption onto the swarm (unit points sit around the centre).
	var pending: Dictionary = world.eruptions.pending[0]
	pending.center = Vector3(spot.x, 0.0, spot.z)
	pending.remaining = STEP * 0.5
	var hp_before: int = world.model.leader_hp
	world.step(STEP)
	_check(world.model.population < 25, "Eruption kills Mawlings inside (population %d)" % world.model.population)
	_check(world.model.leader_hp == hp_before - 1, "Leader inside loses 1 LP (hp %d -> %d)" % [hp_before, world.model.leader_hp])
	world.eruptions.erupt_soon()
	world.step(STEP)
	var old: Variant = world.eruptions
	world.reset_run()
	await process_frame
	_check(not is_instance_valid(old) and world.eruptions != null and world.eruptions.pending.is_empty(), "Reset replaces eruptions without pending warnings")
	scene.queue_free()
	await process_frame


func _setup(seed_value: int) -> void:
	if holder != null:
		holder.free()
	holder = Node3D.new()
	holder.name = "World"
	root.add_child(holder)
	arena = ARENA.new()
	arena.name = "Arena"
	holder.add_child(arena)
	if seed_value != 0:
		arena.set_seed(seed_value)
	eruptions = ERUPTIONS.new()
	eruptions.name = "Eruptions"
	holder.add_child(eruptions)
	eruptions.colorblind = 0


# A swarm position well outside the start zone with sources in reach.
func _swarm_spot() -> Vector3:
	var saved: String = arena.biome_id
	arena.set_biome("glutsumpf")
	for radius in range(2, 8):
		for x in range(-radius, radius + 1):
			for z in [-radius, radius]:
				for site in arena.eruption_sites(Vector2i(x, z)):
					# Stage 18b: the path map erupts on its paths and clearings (kind 1).
					if (site.w == 0.0 or arena.has_layout()) and Vector2(site.x, site.z).length() > 50.0:
						var spot := Vector3(site.x + 5.0, 0.0, site.z)
						arena.set_biome(saved)
						return spot
	arena.set_biome(saved)
	return Vector3.INF


func _check_verdant_calm(spot: Vector3) -> void:
	arena.set_biome("verdant_maw")
	var hits := 0
	for frame in 60 * 60:
		hits += eruptions.step(STEP, spot, 8.0).size()
	_check(hits == 0 and eruptions.pending.is_empty(), "Verdant Maw never erupts")


# Every impact is preceded by its own warning at the same spot for the full wind-up.
func _check_telegraph(spot: Vector3) -> void:
	eruptions.clear()
	var seen := {}
	var impacts := 0
	var time := 0.0
	var first_warning := -1.0
	for frame in 60 * 40:
		time += STEP
		for eruption in eruptions.pending:
			var id: int = (eruption.node as Node).get_instance_id()
			if not seen.has(id):
				seen[id] = {"center": eruption.center, "since": time}
				if first_warning < 0.0:
					first_warning = time
				_check((eruption.node as Node3D).visible and (eruption.node as MeshInstance3D).material_override.get_shader_parameter("mode") == 0, "Warning plane visible in warning mode")
		var ids := {}
		for eruption in eruptions.pending:
			ids[(eruption.node as Node).get_instance_id()] = eruption
		var result: Array = eruptions.step(STEP, spot, 1.0)
		for impact in result:
			impacts += 1
			var matched := false
			for id in seen:
				var info: Dictionary = seen[id]
				if not ids.has(id):
					continue
				if (info.center as Vector3).distance_to(impact.center) < 0.01:
					matched = true
					_check(time + STEP - float(info.since) >= ERUPTIONS.WARNING_SECONDS - 0.02, "Warning shown %.2f s before the burst" % (time - float(info.since)))
			_check(matched, "Impact at %s had a warning first" % [impact.center])
			_check(is_equal_approx(float(impact.radius), ERUPTIONS.RADIUS) and int(impact.power) == ERUPTIONS.damage(1.0), "Impact radius and power")
			_check(eruptions.resolved_power == int(impact.power) and eruptions.contains(impact.center), "resolved_power/contains follow the impact")
			var center: Vector3 = impact.center
			_check(Vector2(center.x - spot.x, center.z - spot.z).length() <= ERUPTIONS.REACH_MAX + 0.01, "Eruption near the swarm")
		if result.is_empty():
			_check(eruptions.resolved_power == 0 and not eruptions.contains(spot), "No damage without an impact")
	_check(impacts >= 2, "Eruptions happen in the Glutsumpf (%d in 40 s)" % impacts)
	_check(first_warning >= ERUPTIONS.FIRST_DELAY - 0.05, "Quiet start delay before the first warning (%.2f s)" % first_warning)


func _check_pause(spot: Vector3) -> void:
	eruptions.clear()
	eruptions.clock = 0.0
	eruptions.step(STEP, spot, 1.0)
	_check(eruptions.pending.size() >= 1, "Warning scheduled for the pause test")
	if eruptions.pending.is_empty():
		return
	var remaining: float = eruptions.pending[0].remaining
	var clock: float = eruptions.clock
	var count: int = eruptions.count
	var hits := 0
	for frame in 600:
		hits += eruptions.step(0.0, spot, 64.0).size()
	_check(hits == 0 and is_equal_approx(eruptions.pending[0].remaining, remaining) and is_equal_approx(eruptions.clock, clock) and eruptions.count == count, "delta 0 (pause) freezes warnings and the clock")


func _check_contains_and_clear(spot: Vector3) -> void:
	var impact := {"center": Vector3(10, 0, 10), "radius": ERUPTIONS.RADIUS, "power": 6}
	_check(ERUPTIONS.impact_contains(impact, Vector3(10 + ERUPTIONS.RADIUS - 0.05, 0, 10)) and not ERUPTIONS.impact_contains(impact, Vector3(10 + ERUPTIONS.RADIUS + 0.1, 0, 10)), "impact_contains uses the radius")
	eruptions.clock = 0.0
	eruptions.step(STEP, spot, 16.0)
	eruptions.clear()
	_check(eruptions.pending.is_empty() and eruptions.bursts.is_empty() and eruptions.resolved_power == 0 and is_equal_approx(eruptions.clock, ERUPTIONS.FIRST_DELAY), "clear() drops warnings and restarts the quiet delay")


# Events per minute rise with pressure (same spot, same seed).
func _check_frequency(spot: Vector3) -> void:
	var counts := []
	for pressure in [1.0, 4.0, 16.0]:
		eruptions.clear()
		eruptions.count = 0
		var warnings := 0
		for frame in 60 * 120:
			var before: int = eruptions.count
			eruptions.step(STEP, spot, pressure)
			warnings += eruptions.count - before
		counts.append(warnings)
	print("Eruptions per 2 min at pressure 1/4/16: %s (interval %.1f/%.1f/%.1f s)" % [counts, ERUPTIONS.interval(1.0), ERUPTIONS.interval(4.0), ERUPTIONS.interval(16.0)])
	_check(counts[0] >= 8 and counts[1] > counts[0] and counts[2] > counts[1], "Frequency rises with pressure %s" % [counts])
	_check(ERUPTIONS.interval(1.0) > ERUPTIONS.interval(4.0) and ERUPTIONS.interval(1000.0) >= ERUPTIONS.MIN_INTERVAL, "Interval shrinks with pressure, bounded")


# A swarm wandering around the start never gets an eruption inside the start zone.
func _check_start_zone() -> void:
	for seed_value in [0, 4242, 777]:
		_setup(seed_value)
		arena.set_biome("glutsumpf")
		var closest := INF
		var warnings := 0
		for frame in 60 * 90:
			var t := float(frame) * STEP
			var swarm := Vector3(cos(t * 0.21) * 24.0, 0.0, sin(t * 0.17) * 24.0)
			eruptions.step(STEP, swarm, 32.0)
			for eruption in eruptions.pending:
				closest = minf(closest, Vector2(eruption.center.x, eruption.center.z).length())
			warnings = eruptions.count
		_check(closest - ERUPTIONS.RADIUS >= ERUPTIONS.START_CLEARANCE - 0.001, "Start zone free (seed %d, closest %.1f m)" % [seed_value, closest])
		_check(warnings > 0, "Eruptions happen around the start zone edge (seed %d)" % seed_value)
	# An extra safe zone (e.g. a migration arrival point) is honoured too.
	_setup(0)
	arena.set_biome("glutsumpf")
	var spot := _swarm_spot()
	eruptions.safe_zones.assign([Vector4(spot.x, 0.0, spot.z, 30.0)])
	var any := 0
	for frame in 60 * 60:
		any += eruptions.step(STEP, spot, 16.0).size()
	_check(any == 0, "Extra safe zone keeps eruptions away")


func _run_sequence(seed_value: int, spot: Vector3) -> Array:
	_setup(seed_value)
	arena.set_biome("glutsumpf")
	var log := []
	for frame in 60 * 90:
		var t := float(frame) * STEP
		var swarm := spot + Vector3(sin(t * 0.3) * 4.0, 0.0, cos(t * 0.25) * 4.0)
		for impact in eruptions.step(STEP, swarm, 2.0 + t * 0.05):
			log.append([frame, impact.center, impact.power])
	return log


func _check_determinism(spot: Vector3) -> void:
	var first := _run_sequence(0, spot)
	var second := _run_sequence(0, spot)
	_check(first.size() >= 5 and first == second, "Same seed and path, same eruptions (%d)" % first.size())
	var seed_spot := spot
	_setup(4242)
	arena.set_biome("glutsumpf")
	seed_spot = _swarm_spot()
	var third := _run_sequence(4242, seed_spot)
	var fourth := _run_sequence(4242, seed_spot)
	_check(third.size() >= 3 and third == fourth, "Seeded map replays identically (%d)" % third.size())
	_check(third != first, "Different seed, different eruptions")


func _check_colorblind() -> void:
	var normal := ShaderMaterial.new()
	var blind := ShaderMaterial.new()
	ERUPTIONS.restyle(normal, false)
	ERUPTIONS.restyle(blind, true)
	_check(normal.get_shader_parameter("pattern_color") != blind.get_shader_parameter("pattern_color"), "Colour-blind palette differs")
	var pattern: Color = blind.get_shader_parameter("pattern_color")
	var fill: Color = blind.get_shader_parameter("fill_color")
	_check(pattern.get_luminance() - fill.get_luminance() > 0.6, "Colour-blind rings contrast by brightness")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
