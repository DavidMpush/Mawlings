extends SceneTree

# Balance harness (Etappe 05, Kriterium 3). Loads main.tscn with a real RunConfig
# built by Profile on a throw-away test profile, drives a simple bot through the
# same controls as the player and prints one BALANCE line per run.
#
# Always run headless with a fixed frame rate; time_scale 3 turns every frame into
# exactly one 0.05 s gameplay step (the clamp in HuntWorld/Swarm), i.e. 3x speed:
#   godot --headless --fixed-fps 60 --path . --script res://tests/balance_sim.gd -- strain=glutmaw diff=0 seed=1 strategy=greedy limit=900
# Arguments (after "--", or as env BALANCE_<KEY>): strain, diff, seed, strategy
# (greedy | random | attack_first | form:<id>), limit (game seconds), runs (seeds seed..seed+runs-1),
# react (seconds before the bot reacts to a telegraph), miss (chance to overlook one),
# regress (quick tolerance test, exit 1 on failure).
#
# The bot is deliberately human-like, not perfect: a perfect dodger never loses a
# Mawling (every telegraph is escapable), so balance would be meaningless. It sees
# each telegraph only after REACT seconds and overlooks a seeded MISS share of them.

const SESSION = preload("res://scripts/meta/session.gd")
const PROFILE = preload("res://scripts/meta/profile.gd")
const DATA = preload("res://scripts/meta/meta_data.gd")
const TUNING = preload("res://scripts/tuning.gd")
const HUNTER = preload("res://scripts/hunter.gd")
const SKITTER = preload("res://scripts/skitter.gd")
const MIRE_LEAPER = preload("res://scripts/mire_leaper.gd")
const BOG_KING = preload("res://scripts/bog_king.gd")
var profile_path := "user://balance_sim_%d.json" % OS.get_process_id()
const STEP := 0.05
const TIME_SCALE := 3.0
const REACT := 0.45
const MISS := 0.12
# Stage 08 bot: Moorbrut closer than this is avoided; this many within 2.5 m = surrounded.
const BROOD_ALERT := 5.0
const BROOD_CROWD := 6

# Quick regression (~40 s): three seeded runs with wide tolerances. They catch a
# broken loop (no growth, instant death), toothless enemies (Apex must cost Mawlings),
# a too easy start (Wild: clear losses and population below the cap at 2:00, stage 08)
# and a missing flood (Apex must reach it and die in it; matrix median ~4:20).
# Runs are near-deterministic; tiny drift between processes stays inside the tolerances.
const REGRESS_RUNS := [
	{"strain": "glutmaw", "diff": 0, "seed": 1, "strategy": "greedy", "limit": 150.0,
		"min_seconds": 120.0, "min_peak": 30, "min_kills": 15, "min_lost": 20, "max_pop120": 200},
	{"strain": "sporling", "diff": 2, "seed": 2, "strategy": "attack_first", "limit": 180.0,
		"min_seconds": 60.0, "min_peak": 40, "min_kills": 25, "min_lost": 40},
	{"strain": "glutmaw", "diff": 2, "seed": 1, "strategy": "attack_first", "limit": 420.0,
		"min_seconds": 150.0, "max_seconds": 400.0, "min_peak": 60, "min_kills": 40, "min_flood": 1.0, "min_flood_lost": 10},
]

var rng := RandomNumberGenerator.new()
var skill_rng := RandomNumberGenerator.new()
var react := REACT
var miss := MISS
# instance id + state -> [game time first seen, overlooked]
var seen := {}
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _args() -> Dictionary:
	var result := {"strain": "glutmaw", "diff": "0", "seed": "1", "strategy": "greedy", "limit": "900", "runs": "1", "react": str(REACT), "miss": str(MISS)}
	for key in result.keys() + ["regress"]:
		var env := OS.get_environment("BALANCE_" + String(key).to_upper())
		if env != "":
			result[key] = env
	for raw in OS.get_cmdline_user_args():
		var arg := String(raw).trim_prefix("--")
		var parts := arg.split("=", true, 1)
		result[parts[0]] = parts[1] if parts.size() > 1 else "1"
	return result


func _run() -> void:
	Engine.time_scale = TIME_SCALE
	var args := _args()
	var started := Time.get_ticks_msec()
	react = float(args.react)
	miss = float(args.miss)
	if args.has("regress"):
		for spec in REGRESS_RUNS:
			var stats := await _simulate(spec.strain, spec.diff, spec.seed, spec.strategy, spec.limit)
			_check(stats.seconds >= spec.min_seconds, "%s/%d survives at least %.0f s (got %.1f)" % [spec.strain, spec.diff, spec.min_seconds, stats.seconds])
			_check(stats.seconds <= spec.get("max_seconds", INF), "%s/%d dies before %.0f s (got %.1f)" % [spec.strain, spec.diff, spec.get("max_seconds", INF), stats.seconds])
			_check(stats.peak >= spec.min_peak, "%s/%d grows to %d (peak %d)" % [spec.strain, spec.diff, spec.min_peak, stats.peak])
			_check(stats.lost >= spec.get("min_lost", 0), "%s/%d loses at least %d Mawlings (got %d)" % [spec.strain, spec.diff, spec.get("min_lost", 0), stats.lost])
			_check(stats.kills >= spec.min_kills, "%s/%d kills at least %d (got %d)" % [spec.strain, spec.diff, spec.min_kills, stats.kills])
			_check(stats.pop120 <= spec.get("max_pop120", 1000), "%s/%d population at 2:00 at most %d (got %d)" % [spec.strain, spec.diff, spec.get("max_pop120", 1000), stats.pop120])
			_check(stats.flood >= spec.get("min_flood", 0.0), "%s/%d reaches the flood (%.0f s in it)" % [spec.strain, spec.diff, stats.flood])
			_check(stats.flood_lost >= spec.get("min_flood_lost", 0), "%s/%d loses at least %d Mawlings to the Moorbrut (got %d)" % [spec.strain, spec.diff, spec.get("min_flood_lost", 0), stats.flood_lost])
		_finish("PASS balance_sim regress: %d runs within tolerance in %.1f s" % [REGRESS_RUNS.size(), (Time.get_ticks_msec() - started) / 1000.0])
		return
	var first := int(args.seed)
	for offset in maxi(1, int(args.runs)):
		await _simulate(String(args.strain), int(args.diff), first + offset, String(args.strategy), float(args.limit))
	_finish("")


func _finish(message: String) -> void:
	Engine.time_scale = 1.0
	if FileAccess.file_exists(profile_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(profile_path))
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	if message != "":
		print(message)
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


# Fresh profile with every strain, difficulty and attack form available, but no
# meta upgrades: the balance target is a new account on each difficulty.
func _config(strain: String, difficulty: int, run_seed: int) -> Dictionary:
	var profile: RefCounted = PROFILE.load_or_create(profile_path)
	profile.owned_strains = DATA.STRAIN_ORDER.duplicate()
	profile.unlocked_strains = DATA.STRAIN_ORDER.duplicate()
	profile.unlocked_difficulties = [0, 1, 2]
	profile.unlocked_mutations = DATA.MUTATION_NAMES.keys()
	return profile.build_run_config(strain, "verdant_maw", difficulty, run_seed)


func _simulate(strain: String, difficulty: int, run_seed: int, strategy: String, limit: float) -> Dictionary:
	var wall := Time.get_ticks_msec()
	rng.seed = run_seed * 7919 + 13
	skill_rng.seed = run_seed * 104729 + 7
	seen.clear()
	SESSION.pending_config = _config(strain, difficulty, run_seed)
	SESSION.last_result = {}
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var world: Variant = scene.get_node("HuntWorld")
	var swarm: Variant = scene.get_node("Swarm")
	var hud: Variant = scene.get_node("HUD/Controls")
	world.evolution.rng.seed = run_seed
	world.drop_rng.seed = run_seed + 101
	var losses := {"hunter": 0, "skitter": 0, "leaper": 0, "boss": 0, "other": 0, "flood": 0}
	var states := {}
	var cause := "timeout"
	var picks: Array[String] = []
	var guard := int(limit / STEP * 1.6) + 600
	# Population at 2:00 (stage 08: early pressure; -1 = died before).
	var pop120 := -1
	var lost120 := 0
	var bio120 := 0.0
	while guard > 0 and not world.model.extinct and world.model.elapsed < limit:
		guard -= 1
		# Main resets time_scale when a scene leaves the tree (Königsmoment safety).
		Engine.time_scale = TIME_SCALE
		if world.choosing():
			var slot := _pick(world.evolution, strategy)
			picks.append(String(world.evolution.offers[slot][0]))
			world.choose_mutation(slot)
			continue
		var control := _bot(world, swarm)
		hud.movement_vector = control.move
		hud.rally_pressed = control.rally
		var before: int = world.model.population
		var before_states := _enemy_states(world)
		await process_frame
		var lost: int = before - world.model.population
		if lost > 0:
			var hitter := _hitter(world, before_states, states)
			losses[hitter] += lost
			if world.model.extinct:
				cause = hitter
		states = before_states
		if pop120 < 0 and world.model.elapsed >= 120.0:
			pop120 = world.model.population
			lost120 = world.model.lost_population
			bio120 = world.model.consumed_biomass
	if world.model.extinct and cause == "timeout":
		cause = "other"
	var forms: Array = world.attack_forms.damage_dealt.keys() if world.attack_forms != null else []
	var dealt := PackedStringArray()
	for id in forms:
		dealt.append("%s:%d" % [id, int(world.attack_forms.damage_dealt[id])])
	var stats := {
		"seconds": world.model.elapsed, "peak": world.model.peak_population, "kills": world.model.kills,
		"extinct": world.model.extinct, "cause": cause, "lost": world.model.lost_population,
		"nests": int(world.get("nests_completed")) if world.get("nests_completed") != null else 0,
		"pop120": pop120,
		"flood": float(world.call("flood_seconds")) if world.has_method("flood_seconds") else 0.0,
		"flood_lost": int(losses.flood),
	}
	print("BALANCE strain=%s diff=%d seed=%d strategy=%s survived=%.1f peak=%d kills=%d cause=%s extinct=%s bosses=%d level=%d nests=%d losses=h%d/s%d/l%d/b%d/o%d/f%d pop120=%d lost120=%d bio120=%.0f flood=%.0f build=%s forms=%s wall=%.1f" % [
		strain, difficulty, run_seed, strategy, world.model.elapsed, world.model.peak_population, world.model.kills,
		cause, world.model.extinct, world.model.bosses, world.evolution.level, stats.nests,
		losses.hunter, losses.skitter, losses.leaper, losses.boss, losses.other, losses.flood, pop120, lost120, bio120, float(world.call("flood_seconds")) if world.has_method("flood_seconds") else 0.0,
		_build(world.evolution), ",".join(dealt), (Time.get_ticks_msec() - wall) / 1000.0])
	root.remove_child(scene)
	scene.free()
	await process_frame
	return stats


func _build(evolution: Variant) -> String:
	var parts := PackedStringArray()
	for id in evolution.ranks:
		if evolution.ranks[id] > 0:
			parts.append("%s%d" % [id, evolution.ranks[id]])
	return ",".join(parts)


# --------------------------------------------------------------- mutation choice

func _pick(evolution: Variant, strategy: String) -> int:
	var offers: Array = evolution.offers
	if strategy == "random":
		return rng.randi_range(0, offers.size() - 1)
	var best := 0
	var best_score := -INF
	for slot in offers.size():
		var id: String = offers[slot][0]
		var kind: String = evolution.kind_of(id)
		var score := float(evolution.rank(id)) + rng.randf() * 0.1
		if strategy == "attack_first" and kind in ["attack", "evolved"]:
			score += 10.0
		elif strategy.begins_with("form:"):
			if id == strategy.substr(5):
				score += 20.0
			elif kind == "attack":
				score -= 10.0
		if score > best_score:
			best_score = score
			best = slot
	return best


# --------------------------------------------------------------- bot

# Same priorities as a careful player: never stand in an announced zone, eat
# corpses, hunt prey, grab Alpha-Kerne, Rally when biting or harvesting.
func _bot(world: Variant, swarm: Variant) -> Dictionary:
	var here: Vector3 = swarm.position
	_forget(world)
	var dodge := _dodge(world, here, world.model.elapsed)
	if dodge != Vector3.ZERO:
		return {"move": Vector2(dodge.x, dodge.z).normalized(), "rally": false}
	# Stage 08: keep away from the Moorbrut; Rally (more bite) when surrounded.
	var brood := _brood_escape(world, here)
	var target := here
	var best := INF
	var harvesting := false
	if world.model.population < 250:
		for corpse in world.model.corpses:
			var distance: float = corpse.position.distance_to(here)
			if distance < best:
				best = distance
				target = corpse.position
				harvesting = true
	for pickup in world.alpha_pickups:
		var distance: float = pickup.position.distance_to(here)
		if distance < minf(best, 14.0):
			best = distance
			target = pickup.position
			harvesting = false
	# Brutnest (stage 06): walk into it when no enemy is announcing an attack and
	# no corpse lies close by; stay until it hatches.
	var nest: Variant = world.get("nest")
	if nest != null and (best == INF or best > 6.0) and not _any_armed(world):
		var inside: float = Vector2(nest.position.x - here.x, nest.position.z - here.z).length()
		best = inside
		target = nest.position if inside > 1.2 else here
		harvesting = false
	if best == INF:
		for prey in world.prey:
			var distance: float = prey.position.distance_to(here)
			if distance < best:
				best = distance
				target = prey.position
	var enemy_near := INF
	for enemy in _enemies(world):
		if _hittable(enemy):
			enemy_near = minf(enemy_near, enemy.position.distance_to(here) - (2.0 if enemy == world.boss else 0.0))
	var direction: Vector3 = target - here
	direction.y = 0.0
	if harvesting and direction.length() < 1.0:
		direction = Vector3.ZERO
	var leap: bool = world.evolution.rank("rudelbiss") > 0 or world.evolution.rank("meute") > 0
	var rally: bool = (harvesting and best < 1.05) or enemy_near < 1.1 or (leap and enemy_near < 4.0)
	if brood.away != Vector3.ZERO:
		# Mostly away from the brood, a little towards the goal.
		direction = brood.away * 0.75 + direction.normalized() * 0.25 if direction.length() > 0.01 else brood.away
	if brood.surrounded:
		rally = true
	return {"move": Vector2(direction.x, direction.z).limit_length(1.0), "rally": rally}


# Escape direction from the Moorbrut within BROOD_ALERT m (weighted by closeness)
# and whether the swarm is surrounded (BROOD_CROWD brood within 2.5 m).
func _brood_escape(world: Variant, here: Vector3) -> Dictionary:
	var result := {"away": Vector3.ZERO, "surrounded": false}
	var horde: Variant = world.get("horde")
	if horde == null or not horde.has_method("positions") or horde.count() == 0:
		return result
	var push := Vector3.ZERO
	var close := 0
	for point in horde.positions():
		var offset: Vector3 = here - point
		offset.y = 0.0
		var distance := offset.length()
		if distance > BROOD_ALERT or distance < 0.01:
			continue
		push += offset / distance * (BROOD_ALERT - distance)
		if distance < 2.5:
			close += 1
	result.surrounded = close >= BROOD_CROWD
	if push.length() > 0.01:
		result.away = push.normalized()
	return result


# Sum of escape directions out of every noticed announced zone, or ZERO when safe.
func _dodge(world: Variant, here: Vector3, now: float) -> Vector3:
	var escape := Vector3.ZERO
	for hunter in world.hunters:
		if hunter.state == HUNTER.State.WARNING and _noticed(hunter, now):
			escape += _away(here, hunter.attack_center, TUNING.HUNTER_ATTACK_RADIUS + 0.8)
	if world.boss != null and world.boss.state == BOG_KING.State.WARNING and _noticed(world.boss, now):
		escape += _away(here, world.boss.attack_center, TUNING.BOSS_ATTACK_RADIUS + 0.8)
	for leaper in world.leapers:
		if leaper.state in [MIRE_LEAPER.State.WARNING, MIRE_LEAPER.State.LEAP] and _noticed(leaper, now) and leaper.zone_margin(here) < 0.6:
			escape += leaper.dodge_direction(here).normalized()
	for skitter in world.skitters:
		if skitter.state in [SKITTER.State.WARNING, SKITTER.State.DASH] and _noticed(skitter, now) and skitter.warning_distance(here) < TUNING.SKITTER_WIDTH + 0.7:
			escape += skitter.dodge_direction(here).normalized()
	# Stage 08: Nibbler snap (small circle, short warning).
	for prey in world.prey:
		if int(prey.get("snap_state")) == 1 and _noticed(prey, now):
			escape += _away(here, prey.snap_center, TUNING.NIBBLER_SNAP_RADIUS + 0.6)
	return escape


func _away(here: Vector3, center: Vector3, reach: float) -> Vector3:
	var away := here - center
	away.y = 0.0
	if away.length() >= reach:
		return Vector3.ZERO
	return away.normalized() if away.length() > 0.01 else Vector3.RIGHT


# A telegraph counts once the reaction time has passed, unless the bot overlooks it.
# WARNING and the following strike phase share one decision; _forget() resets it.
func _noticed(enemy: Variant, now: float) -> bool:
	var key: int = enemy.get_instance_id()
	if not seen.has(key):
		seen[key] = [now, skill_rng.randf() < miss]
	var entry: Array = seen[key]
	return not entry[1] and now - float(entry[0]) >= react


func _forget(world: Variant) -> void:
	var armed := {}
	for enemy in _enemies(world):
		if _is_armed(enemy):
			armed[enemy.get_instance_id()] = true
	for prey in world.prey:
		if int(prey.get("snap_state")) == 1:
			armed[prey.get_instance_id()] = true
	for key in seen.keys():
		if not armed.has(key):
			seen.erase(key)


func _is_armed(enemy: Variant) -> bool:
	if enemy is HUNTER:
		return enemy.state == HUNTER.State.WARNING
	if enemy is SKITTER:
		return enemy.state in [SKITTER.State.WARNING, SKITTER.State.DASH]
	if enemy is MIRE_LEAPER:
		return enemy.state in [MIRE_LEAPER.State.WARNING, MIRE_LEAPER.State.LEAP]
	return enemy.state == BOG_KING.State.WARNING


func _any_armed(world: Variant) -> bool:
	for enemy in _enemies(world):
		if _is_armed(enemy):
			return true
	return false


func _enemies(world: Variant) -> Array:
	var result: Array = []
	result.append_array(world.hunters)
	result.append_array(world.skitters)
	result.append_array(world.leapers)
	if world.boss != null:
		result.append(world.boss)
	return result


func _hittable(enemy: Variant) -> bool:
	if enemy is MIRE_LEAPER:
		return enemy.can_be_hit()
	return enemy.state != 0


# --------------------------------------------------------------- loss attribution

func _enemy_states(world: Variant) -> Dictionary:
	var result := {}
	for enemy in _enemies(world):
		result[enemy.get_instance_id()] = [_kind(enemy), int(enemy.state), enemy]
	return result


func _kind(enemy: Variant) -> String:
	if enemy is HUNTER:
		return "hunter"
	if enemy is SKITTER:
		return "skitter"
	if enemy is MIRE_LEAPER:
		return "leaper"
	return "boss"


# The enemy whose strike resolved during the last step (its state left the
# announced phase). Falls back to the closest armed enemy.
func _hitter(world: Variant, before: Dictionary, _older: Dictionary) -> String:
	var armed := {"hunter": [HUNTER.State.WARNING], "skitter": [SKITTER.State.DASH, SKITTER.State.WARNING],
		"leaper": [MIRE_LEAPER.State.LEAP, MIRE_LEAPER.State.WARNING], "boss": [BOG_KING.State.WARNING]}
	# Without an armed enemy the loss came from Moorbrut (flood) or a Nibbler snap (other).
	var fallback := "flood" if int(world.get("flood_state")) == 2 else "other"
	for id in before:
		var entry: Array = before[id]
		if not (entry[1] in armed[entry[0]]):
			continue
		fallback = entry[0]
		var enemy: Variant = entry[2]
		if not is_instance_valid(enemy) or int(enemy.state) != entry[1]:
			return entry[0]
	return fallback
