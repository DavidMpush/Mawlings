extends SceneTree

# Stage 20: how long an apex fight lasts inside a real run (HuntWorld), on
# Brutal and Apex. A dodging bot: during a wind-up it leaves the locked area by
# the shortest way, otherwise it stays at the rim with Rally whenever the boss
# can be hit and waits near it while it cannot (burrowed worm, jumping toad).
# The swarm has the minimum population of the apex and a mid-run build (start
# weapon + Sporenwolke, Biss 2, Kritbiss 1, Angriffstempo 1) - roughly what the
# balance bot carries at 3 minutes. Target band 25-35 s (stages/20).
# Run: Godot --headless --fixed-fps 60 --audio-driver Dummy --path . --script res://tests/apex_duration.gd
# Prints one line per fight; exits 1 only if a fight does not end at all.

const TUNING = preload("res://scripts/tuning.gd")
const PROFILE = preload("res://scripts/meta/profile.gd")
const DT := 1.0 / 60.0
const CASES := [
	["verdant_maw", "apex", TUNING.APEX_MIN_POPULATION],
	["duerrschlund", "apex_sandworm", TUNING.APEX_SANDWORM_MIN_POPULATION],
	["glutsumpf", "apex_toad", TUNING.APEX_TOAD_MIN_POPULATION],
]
const LIMIT := 150.0

var scene: Node
var world: Variant
var swarm: Variant
var arena: Variant
var results: Array[String] = []
var stuck := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	arena = scene.get_node("Arena")
	scene.set_process(false)
	world.set_process(false)
	swarm.set_process(false)
	var path := "user://apex_duration_profile.json"
	var profile: Variant = PROFILE.load_or_create(path)
	profile.unlocked_difficulties = [0, 1, 2]
	profile.records.total_moss = 1
	for difficulty in [1, 2]:
		for entry in CASES:
			var config: Dictionary = profile.build_run_config("glutmaw", String(entry[0]), difficulty)
			var seconds := _fight(config, String(entry[1]), int(entry[2]))
			results.append("%s %s: %s" % [["Wild", "Brutal", "Apex"][difficulty], entry[1], ("%.1f s" % seconds) if seconds < LIMIT else "> %.0f s" % LIMIT])
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for line in results:
		print("APEX_FIGHT ", line)
	quit(1 if stuck else 0)


func _fight(config: Dictionary, kind: String, population: int) -> float:
	world.apply_config(config)
	world.model.population = population
	swarm.set_population(population, false)
	world.model.elapsed = float(TUNING.APEX_SPAWN_SECONDS[int(config.difficulty)])
	world.hunters_unlocked = true
	for clock in ["hunter_clock", "skitter_clock", "leaper_clock", "elite_clock", "nest_clock", "boss_clock", "flood_wave_clock"]:
		world.set(clock, 9999.0)
	world.flood_start = 100000.0
	for prey in world.prey:
		prey.queue_free()
	world.prey.clear()
	world.spawn_clock = -9999.0
	# Mid-run build.
	world.evolution.debug_grant("sporenwolke")
	for id in ["bite", "bite", "crit", "haste"]:
		world.evolution.debug_grant(id)
	world._sync_attack_forms()
	_spread()
	var apex: Variant = world.spawn_apex(swarm.position + Vector3(0, 0, -12), kind)
	var time := 0.0
	while time < LIMIT and world.apex != null:
		if world.choosing():
			world.choose_mutation(0)
		world.model.leader_invulnerable = 99.0
		# Keep a playable swarm (the losses would otherwise decide the time).
		if world.model.population < population / 2:
			world.model.population = population / 2
			swarm.set_population(population / 2, false)
			_spread()
		_steer(apex)
		world.unit_points_valid = false
		world.step(DT)
		arena.sync(swarm.position)
		time += DT
	if world.apex != null:
		stuck = true
		print("APEX_FIGHT stuck: %s hp %.0f / %.0f state %d" % [kind, float(apex.health), float(apex.max_health), int(apex.state)])
	return time


func _spread() -> void:
	for index in swarm.units.size():
		var angle := float(index) * 2.39996
		swarm.units[index].position = Vector3(cos(angle), 0.0, sin(angle)) * 0.42 * sqrt(float(index))
	world.unit_points_valid = false


# One bot step: dodge, attack or wait near the boss.
func _steer(apex: Variant) -> void:
	var here: Vector3 = swarm.position
	var speed: float = swarm.move_speed() * DT
	var target := here
	swarm.rally_pressed = false
	if int(apex.state) == 2 and _danger(apex, here):
		target = _escape(apex, here)
	elif apex.can_be_hit():
		var rim: float = apex.body_distance(here) if apex.has_method("body_distance") else here.distance_to(apex.position) - 3.0
		swarm.rally_pressed = true
		if rim > 0.8:
			target = apex.position
	else:
		var away: Vector3 = here - apex.position
		away.y = 0.0
		if away.length() > 7.0:
			target = apex.position
	var step: Vector3 = target - here
	step.y = 0.0
	if step.length() > speed:
		step = step.normalized() * speed
	swarm.position = arena.resolve_motion(here, step, 0.75)


# The swarm (~2.8 m wide) touches the locked area.
func _danger(apex: Variant, point: Vector3) -> bool:
	for offset in [Vector3.ZERO, Vector3(2.4, 0, 0), Vector3(-2.4, 0, 0), Vector3(0, 0, 2.4), Vector3(0, 0, -2.4)]:
		if apex.contains(point + offset):
			return true
	return false


func _escape(apex: Variant, from: Vector3) -> Vector3:
	var best := from
	var best_distance := INF
	for ring in range(1, 9):
		for index in 16:
			var angle := TAU * float(index) / 16.0
			var spot: Vector3 = from + Vector3(cos(angle), 0.0, sin(angle)) * float(ring) * 1.5
			if not _danger(apex, spot) and from.distance_to(spot) < best_distance:
				best_distance = from.distance_to(spot)
				best = spot
		if best_distance < INF:
			break
	return best
