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
const STATS = preload("res://scripts/progression/stats.gd")
const HUNTER = preload("res://scripts/hunter.gd")
const SKITTER = preload("res://scripts/skitter.gd")
const MIRE_LEAPER = preload("res://scripts/mire_leaper.gd")
const BOG_KING = preload("res://scripts/bog_king.gd")
const APEX = preload("res://scripts/apex_boss.gd")
const APEX_TOAD = preload("res://scripts/apex_toad.gd")
const ERUPTIONS = preload("res://scripts/eruptions.gd")
var profile_path := "user://balance_sim_%d.json" % OS.get_process_id()
const STEP := 0.05
const TIME_SCALE := 3.0
const REACT := 0.45
const MISS := 0.12
# Stage 08 bot: Moorbrut closer than this is avoided; this many within 2.5 m = surrounded.
const BROOD_ALERT := 5.0
const BROOD_CROWD := 6
# Stage 09: extra dodge margin (m) while the leader is on its last LP.
const LOW_HP_MARGIN := 0.8
# Stage 09: up to this many visible Mawlings the bot also waits for stragglers.
const SMALL_SWARM := 16
# Stage 09: reaction time and overlook chance x this while the leader has 1 LP.
const LOW_HP_FOCUS := 0.5
# Stage 10: the bot collects crystals within this distance before it walks into the
# Migrationsschlund; apex dodge keeps this margin (m) around the leader.
const PORTAL_CORPSE_REACH := 6.0
const APEX_MARGIN := 1.4
# ... and collects crystals closer than this before it engages the Moosschlund.
const APEX_CORPSE_REACH := 8.0
# Etappe 16: crystals farther than this are not worth a detour.
const LOOT_REACH := 30.0
# Etappe 17 Welle 2: power-ups/knolls taken on the way, map cocoons bought as
# soon as the Bernstein suffices (no threat announced), free cocoons far away
# only with a real swarm, shrines charged when no threat is within SHRINE_SAFE m.
const POWERUP_REACH := 14.0
const KNOLL_REACH := 9.0
const COCOON_REACH := 90.0
const CHEST_MIN_POP := 20
const SHRINE_REACH := 70.0
const SHRINE_SAFE := 12.0
const SHRINE_MIN_POP := 15
const FREE_NEAR := 25.0
# Etappe 21: the Bog King counts as fought while it is this close (m).
const KING_ENGAGED := 9.0
var low_hp := false

# Quick regression (~40 s): three seeded runs with wide tolerances. They catch a
# broken loop (no growth, instant death), toothless enemies (Apex must cost Mawlings),
# the stage 09 lone-start curve (Wild: 1 -> 15-80 Mawlings at 2:00, real losses) and
# a missing flood (Apex must reach it and die in it; matrix median ~3:50).
# Runs are near-deterministic; tiny drift between processes stays inside the tolerances.
# Stage 10 part 2: Apex runs often end in the first flood seconds (leapers/hunters in
# the crowd), so the flood only has to take >= 5 Mawlings in the median (was 10).
# Etappe 16: median of five seeds (was three) - the added Lockduft trait reshuffled the
# seeded mutation offers, and seeds 1 and 2 now start glutmaw/Apex with weak early
# picks; with three seeds two such starts decided the median (runtime ~105 s).
# Etappe 17 Welle 2 / 17c: Apex runs reach the flood (min_flood) but end in its
# first seconds by the Moosschlund (now 1700 LP) or hunters, before the Moorbrut
# bites (median 0 Moorbrut losses), so min_flood_lost is no longer required.
# Etappe 21: the Apex spec is Sporling (seeds 2-6), run until it dies (limit 420):
# it reaches the flood and loses Mawlings to the Moorbrut again (median ~46), so
# min_flood_lost 3 is back; the former glutmaw/Apex spec (dies to the Moosschlund
# at ~3:00, flood losses 0) is merged into it, which also shortens the regression.
const REGRESS_SEEDS := 5
const REGRESS_RUNS := [
	{"strain": "glutmaw", "diff": 0, "seed": 1, "strategy": "greedy", "limit": 150.0,
		"min_seconds": 120.0, "min_peak": 20, "min_kills": 15, "min_lost": 10, "min_pop120": 15, "max_pop120": 80},
	{"strain": "sporling", "diff": 2, "seed": 2, "strategy": "attack_first", "limit": 420.0,
		"min_seconds": 150.0, "max_seconds": 330.0, "min_peak": 25, "min_kills": 25, "min_lost": 20,
		"min_flood": 1.0, "min_flood_lost": 3},
]

var rng := RandomNumberGenerator.new()
var skill_rng := RandomNumberGenerator.new()
var react := REACT
var miss := MISS
# instance id + state -> [game time first seen, overlooked]
var seen := {}
var failures: Array[String] = []
# "trace" argument: print every loss / leader hit (debugging the curve).
var trace := false
# "noapex" argument: skip the Moosschlund (stage 10 comparison runs).
var no_apex := false
# "noflood" argument: no flood (measures late fights such as the Aschenkröte,
# which most bot runs never reach before the flood ends them; not for targets).
var no_flood := false


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
	trace = args.has("trace")
	no_apex = args.has("noapex") or OS.get_environment("BALANCE_NOAPEX") != ""
	no_flood = args.has("noflood") or OS.get_environment("BALANCE_NOFLOOD") != ""
	miss = float(args.miss)
	if args.has("regress"):
		for spec in REGRESS_RUNS:
			# Stage 09: the lone start makes single runs chaotic (tiny process drift
			# decides an early dodge), so each spec checks the median of three seeds.
			var runs: Array[Dictionary] = []
			for offset in REGRESS_SEEDS:
				runs.append(await _simulate(spec.strain, spec.diff, int(spec.seed) + offset, spec.strategy, spec.limit))
			var stats := _median_stats(runs)
			_check(stats.seconds >= spec.min_seconds, "%s/%d survives at least %.0f s (got %.1f)" % [spec.strain, spec.diff, spec.min_seconds, stats.seconds])
			_check(stats.seconds <= spec.get("max_seconds", INF), "%s/%d dies before %.0f s (got %.1f)" % [spec.strain, spec.diff, spec.get("max_seconds", INF), stats.seconds])
			_check(stats.peak >= spec.min_peak, "%s/%d grows to %d (peak %d)" % [spec.strain, spec.diff, spec.min_peak, stats.peak])
			_check(stats.lost >= spec.get("min_lost", 0), "%s/%d loses at least %d Mawlings (got %d)" % [spec.strain, spec.diff, spec.get("min_lost", 0), stats.lost])
			_check(stats.kills >= spec.min_kills, "%s/%d kills at least %d (got %d)" % [spec.strain, spec.diff, spec.min_kills, stats.kills])
			_check(stats.pop120 <= spec.get("max_pop120", 1000), "%s/%d population at 2:00 at most %d (got %d)" % [spec.strain, spec.diff, spec.get("max_pop120", 1000), stats.pop120])
			_check(stats.pop120 >= spec.get("min_pop120", -1), "%s/%d population at 2:00 at least %d (got %d)" % [spec.strain, spec.diff, spec.get("min_pop120", -1), stats.pop120])
			_check(stats.flood >= spec.get("min_flood", 0.0), "%s/%d reaches the flood (%.0f s in it)" % [spec.strain, spec.diff, stats.flood])
			# Etappe 28: the Moorbrut must bite in at least one seed (the median run
			# may die at the first apex before the flood; see stages/BACKLOG.md 0a).
			var flood_bite := 0
			for run in runs:
				flood_bite = maxi(flood_bite, int(run.flood_lost))
			_check(flood_bite >= spec.get("min_flood_lost", 0), "%s/%d loses at least %d Mawlings to the Moorbrut in one seed (best %d)" % [spec.strain, spec.diff, spec.get("min_flood_lost", 0), flood_bite])
		_finish("PASS balance_sim regress: %d specs x %d seeds (median) within tolerance in %.1f s" % [REGRESS_RUNS.size(), REGRESS_SEEDS, (Time.get_ticks_msec() - started) / 1000.0])
		return
	var first := int(args.seed)
	for offset in maxi(1, int(args.runs)):
		await _simulate(String(args.strain), int(args.diff), first + offset, String(args.strategy), float(args.limit))
	_finish("")


# Median of every numeric stat over several runs.
func _median_stats(runs: Array[Dictionary]) -> Dictionary:
	var result := {}
	for key in runs[0]:
		if not (runs[0][key] is int or runs[0][key] is float):
			continue
		var values: Array = []
		for run in runs:
			values.append(run[key])
		values.sort()
		result[key] = values[values.size() / 2]
	return result


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
	if no_apex and world.get("apex_state") != null:
		world.apex_state = 4
	if no_flood:
		world.flood_start = 1000000.0
	var losses := {"hunter": 0, "skitter": 0, "leaper": 0, "boss": 0, "other": 0, "flood": 0, "apex": 0, "lava": 0}
	# Stage 10: game time of the apex spawn / kill / migration (-1 = never).
	var apex_seen := -1.0
	var apex_killed := -1.0
	var migrated := -1.0
	# Etappe 27: kills when the first migration landed (activity per minute afterwards).
	var kills_migrated := 0
	# Stage 10 part 3: every apex fight as "kind:seconds" (spawn -> kill, "+" = still alive at the end).
	var fights := PackedStringArray()
	var fight_apex: Variant = null
	var fight_start := 0.0
	var fight_kind := ""
	# Etappe 21: Bog-King-Kämpfe (erster Treffer bis Tod) als "king:<s>" in fights.
	var fight_king := 0
	var king_start := 0.0
	# Seconds the engaged king spent farther than KING_ENGAGED m away (the bot
	# walks off to loot; those seconds are not fight time).
	var king_away := 0.0
	var states := {}
	var cause := "timeout"
	var picks: Array[String] = []
	var guard := int(limit / STEP * 1.6) + 600
	# Population at 1:00 / 2:00 / flood start (stage 09 growth curve; -1 = died before).
	var pop60 := -1
	var level_at := {}
	var pop120 := -1
	var pop_flood := -1
	var lost120 := 0
	var bio120 := 0.0
	while guard > 0 and not world.model.extinct and world.model.elapsed < limit:
		guard -= 1
		# Main resets time_scale when a scene leaves the tree (Königsmoment safety).
		Engine.time_scale = TIME_SCALE
		if world.choosing():
			# Etappe 28: every cocoon (start/map/elite/gold/boss) offers 1 of 3.
			if not world.evolution.chest_offers.is_empty():
				var chest_slot := _pick_chest(world.evolution, strategy)
				picks.append("chest:" + String(world.evolution.chest_offers[chest_slot][0]))
				world.choose_mutation(chest_slot)
				continue
			var slot := _pick(world.evolution, strategy)
			picks.append(String(world.evolution.offers[slot][0]))
			world.choose_mutation(slot)
			continue
		var control := _bot(world, swarm)
		hud.movement_vector = control.move
		hud.rally_pressed = control.rally
		var before: int = world.model.population
		var hp_before: int = int(world.model.get("leader_hp")) if world.model.get("leader_hp") != null else 0
		var before_states := _enemy_states(world)
		await process_frame
		var lost: int = before - world.model.population
		var hp_now: int = int(world.model.get("leader_hp")) if world.model.get("leader_hp") != null else 0
		if lost > 0 or hp_now < hp_before:
			var hitter := _hitter(world, before_states, states)
			losses[hitter] += lost
			if world.model.extinct:
				cause = hitter
			if trace:
				var detail := ""
				for hunter in world.hunters:
					if int(hunter.get("resolved_power")) > 0:
						var lead_point: Vector3 = swarm.unit_world_points()[0] if not swarm.units.is_empty() else swarm.position
						detail += " ring: swarm %.2f leader %.2f seen=%s" % [Vector2(hunter.attack_center.x - swarm.position.x, hunter.attack_center.z - swarm.position.z).length(), Vector2(hunter.attack_center.x - lead_point.x, hunter.attack_center.z - lead_point.z).length(), str(seen.get(hunter.get_instance_id(), "-"))]
				for prey in world.prey:
					if int(prey.get("resolved_power")) > 0:
						var lead: Vector3 = swarm.unit_world_points()[0] if not swarm.units.is_empty() else swarm.position
						detail += " snap: centre->swarm %.2f leader %.2f seen=%s" % [Vector2(prey.snap_center.x - swarm.position.x, prey.snap_center.z - swarm.position.z).length(), Vector2(prey.snap_center.x - lead.x, prey.snap_center.z - lead.z).length(), str(seen.get(prey.get_instance_id(), "-"))]
				var apex_now: Variant = world.get("apex")
				if apex_now != null:
					detail += " apex: pattern=%d state=%d phase=%d power=%d leader_safe=%s seen=%s pop=%d" % [apex_now.current_pattern, apex_now.state, apex_now.phase, apex_now.attack_power, str(apex_now.contains(_leader_point(swarm)) == false), str(seen.get(apex_now.get_instance_id(), "-")), world.model.population]
				print("TRACE t=%.1f by=%s lost=%d pop=%d leader=%d/%d%s" % [world.model.elapsed, hitter, lost, world.model.population, hp_now, int(world.model.get("leader_max_hp")), detail])
		states = before_states
		# Level checkpoints (lv60/lv120/lv240/lv420) for the DNA curve.
		for mark in [60, 120, 240, 420]:
			if not level_at.has(mark) and world.model.elapsed >= float(mark):
				level_at[mark] = int(world.evolution.level)
		if pop60 < 0 and world.model.elapsed >= 60.0:
			pop60 = world.model.population
		if pop120 < 0 and world.model.elapsed >= 120.0:
			pop120 = world.model.population
			lost120 = world.model.lost_population
			bio120 = world.model.consumed_biomass
		if pop_flood < 0 and int(world.get("flood_state")) == 2:
			pop_flood = world.model.population
		if apex_seen < 0.0 and world.get("apex") != null:
			apex_seen = world.model.elapsed
		if apex_killed < 0.0 and int(world.get("apex_kills")) > 0:
			apex_killed = world.model.elapsed
		if migrated < 0.0 and int(world.get("migrations")) > 0:
			migrated = world.model.elapsed
			kills_migrated = world.model.kills
		var apex_live: Variant = world.get("apex")
		if OS.get_environment("BALANCE_TOADTRACE") != "" and apex_live != null and fmod(world.model.elapsed, 2.0) < STEP:
			print("TOAD t=%.0f d=%.1f rim=%.1f state=%d hp=%.0f pop=%d flood=%d brood=%d" % [world.model.elapsed, apex_live.position.distance_to(swarm.position), apex_live.body_distance(swarm.position) if apex_live.has_method("body_distance") else -1.0, apex_live.state, apex_live.health, world.model.population, int(world.flood_state), int(world.horde.count()) if world.get("horde") != null else -1])
		if apex_live != fight_apex:
			if fight_apex != null:
				fights.append("%s:%.0f" % [fight_kind, world.model.elapsed - fight_start])
			fight_apex = apex_live
			fight_kind = "toad" if apex_live is APEX_TOAD else ("worm" if apex_live != null and str(apex_live.get("corpse_kind")) == "apex_sandworm" else "moos")
			fight_start = world.model.elapsed
		# Instance ids: a freed node compares equal to null in Godot 4.
		var king_node: Variant = world.get("boss")
		var king_live: int = king_node.get_instance_id() if king_node != null and is_instance_valid(king_node) else 0
		if king_live != fight_king:
			if fight_king != 0 and king_start >= 0.0:
				fights.append("king:%.0f" % (world.model.elapsed - king_start - king_away))
			fight_king = king_live
			king_start = -1.0
			king_away = 0.0
		elif king_live != 0 and king_start < 0.0 and float(king_node.health) < float(king_node.max_health):
			king_start = world.model.elapsed
		elif king_live != 0 and king_start >= 0.0 and king_node.position.distance_to(swarm.position) > KING_ENGAGED:
			king_away += STEP
		if OS.get_environment("BALANCE_KINGTRACE") != "" and king_live != 0 and fmod(world.model.elapsed, 2.0) < STEP:
			print("KING t=%.0f d=%.1f hp=%.0f/%.0f pop=%d state=%d" % [world.model.elapsed, king_node.position.distance_to(swarm.position), king_node.health, king_node.max_health, world.model.population, int(king_node.state)])
	if fight_apex != null:
		# Still alive at the end: "+" and the health share left.
		fights.append("%s:%.0f+%d%%" % [fight_kind, world.model.elapsed - fight_start, int(100.0 * fight_apex.health / maxf(1.0, fight_apex.max_health))])
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
		"pop60": pop60,
		"pop120": pop120,
		"pop_flood": pop_flood,
		"swaps": int(world.model.get("leader_swaps")) if world.model.get("leader_swaps") != null else 0,
		"flood": float(world.call("flood_seconds")) if world.has_method("flood_seconds") else 0.0,
		"flood_lost": int(losses.flood),
		"apex_seen": apex_seen,
		"apex_killed": apex_killed,
		"migrated": migrated,
		"fights": fights,
	}
	print("BALANCE strain=%s diff=%d seed=%d strategy=%s survived=%.1f peak=%d kills=%d cause=%s extinct=%s bosses=%d level=%d nests=%d losses=h%d/s%d/l%d/b%d/o%d/f%d pop60=%d pop120=%d popflood=%d swaps=%d lost120=%d bio120=%.0f flood=%.0f kinds=%s build=%s forms=%s apex=%.0f apexkill=%.0f migrated=%.0f lossa=%d lava=%d fights=%s migrations=%d cocoons=%s boosts=%d shrines=%d amber=%d ability=%s:%d surges=%d kpm_w1=%.0f kpm_after=%.0f wall=%.1f lv=%s" % [
		strain, difficulty, run_seed, strategy, world.model.elapsed, world.model.peak_population, world.model.kills,
		cause, world.model.extinct, world.model.bosses, world.evolution.level, stats.nests,
		losses.hunter, losses.skitter, losses.leaper, losses.boss, losses.other, losses.flood, pop60, pop120, pop_flood, stats.swaps, lost120, bio120, float(world.call("flood_seconds")) if world.has_method("flood_seconds") else 0.0,
		_kinds(world.model.kills_by_type), _build(world.evolution), ",".join(dealt), apex_seen, apex_killed, migrated, int(losses.apex), int(losses.lava), ",".join(fights) if not fights.is_empty() else "-", int(world.get("migrations")), _cocoon_text(world), int(world.powerups.collected) if world.get("powerups") != null else 0, int(world.shrines.completed) if world.get("shrines") != null else 0, int(world.model.get("amber_collected")) if world.model.get("amber_collected") != null else 0, String(world.abilities.ability_id) if world.get("abilities") != null else "-", int(world.abilities.uses) if world.get("abilities") != null else 0, int(world.get("surge_total")) if world.get("surge_total") != null else 0, (float(kills_migrated if migrated >= 0.0 else world.model.kills) * 60.0 / maxf(1.0, migrated if migrated >= 0.0 else world.model.elapsed)), (float(world.model.kills - kills_migrated) * 60.0 / maxf(1.0, world.model.elapsed - migrated) if migrated >= 0.0 else -1.0), (Time.get_ticks_msec() - wall) / 1000.0, "/".join([60, 120, 240, 420].map(func(mark): return str(level_at.get(mark, -1))))])
	root.remove_child(scene)
	scene.free()
	await process_frame
	return stats


func _kinds(counts: Dictionary) -> String:
	var parts := PackedStringArray()
	for kind in counts:
		if int(counts[kind]) > 0:
			parts.append("%s%d" % [String(kind).left(2), int(counts[kind])])
	return ",".join(parts)


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
		# Etappe 16: like a player, the bot takes the pure pickup trait (Lockduft)
		# only when nothing else is on offer or it already owns it.
		if id == "lockduft" and evolution.rank(id) == 0:
			score -= 0.5
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


# Opened cocoons per kind "map/gold/elite/boss/start" (Etappe 17 Welle 2).
func _cocoon_text(world: Variant) -> String:
	var chests: Variant = world.get("chests")
	if chests == null:
		return "-"
	var counts: Dictionary = chests.opened_by_kind
	return "%d/%d/%d/%d/%d" % [int(counts.get("map", 0)), int(counts.get("gold", 0)), int(counts.get("elite", 0)), int(counts.get("boss", 0)), int(counts.get("start", 0))]


# Every cocoon (stage 28) is a 1-of-3 choice. The bot always takes a ready
# evolution and, with "form:<id>", that weapon; "best" takes the rarest card,
# weapons before relics (a strong player). Otherwise ("greedy", "attack_first",
# "random") it takes the first card: the offers are rolled in random order, so
# this matches the random loot the regression targets were tuned with before
# stage 28. Measured 28.09.2026: a weapon-preferring pick made the Sporling/Apex
# spec survive to the 420 s limit in 3 of 5 seeds (targets: dies by 330 s).
func _pick_chest(evolution: Variant, strategy: String = "greedy") -> int:
	var offers: Array = evolution.chest_offers
	var best := 0
	var best_score := -INF
	for slot in offers.size():
		var entry: Array = offers[slot]
		var item: Dictionary = entry[4] if entry.size() > 4 else {}
		var score := -0.01 * float(slot)
		match String(item.get("type", "")):
			"evolution":
				score += 100.0
			"weapon":
				if strategy.begins_with("form:") and String(item.get("id", "")) == strategy.substr(5):
					score += 50.0
				elif strategy == "best":
					score += 20.0 + (10.0 if int(item.get("from", 0)) > 0 else 0.0)
			"relic":
				if strategy == "best":
					score += 10.0
		if strategy == "best":
			score += 0.5 * float(STATS.RARITIES.find(String(item.get("rarity", "common"))))
		if score > best_score:
			best_score = score
			best = slot
	return best


# Distance to the nearest living enemy (not the Moorbrut).
func _threat_distance(world: Variant, here: Vector3) -> float:
	var nearest := INF
	for enemy in _enemies(world):
		nearest = minf(nearest, enemy.position.distance_to(here))
	return nearest


# --------------------------------------------------------------- bot

# Same priorities as a careful player: never stand in an announced zone, collect
# crystals, hunt prey, grab Alpha-Kerne and Lockrufe, Rally when biting.
func _bot(world: Variant, swarm: Variant) -> Dictionary:
	var here: Vector3 = swarm.position
	_forget(world)
	# Stage 09: dodge with the leader (units[0]) - it trails the swarm centre a
	# little, and only its LP decide the run.
	var dodge := _dodge(world, _leader_point(swarm), world.model.elapsed)
	# Stage 18b: on the path map an escape never runs into a wall.
	var arena: Variant = swarm.get_parent().get_node("Arena")
	if dodge != Vector3.ZERO:
		dodge = arena.open_direction(here, dodge, 1.0, 3.0)
		# Etappe 17d: leap / sprint out, shield up or veil the warning.
		_maybe_ability(world, "dodge")
		return {"move": Vector2(dodge.x, dodge.z).normalized(), "rally": false}
	# Stage 08: keep away from the Moorbrut; Rally (more bite) when surrounded.
	var brood := _brood_escape(world, here)
	# Etappe 21: a player fires the crowd ability into a boss beside the swarm, too.
	if brood.surrounded or _enemies_near(world, here, ABILITY_CROWD_RANGE) >= ABILITY_CROWD or _boss_near(world, here, ABILITY_BOSS_RANGE):
		_maybe_ability(world, "crowd")
	var target := here
	var best := INF
	var harvesting := false
	# Etappe 16: walk towards the nearest lying crystal (biomass only while the
	# swarm has room) until it is inside the magnet; Lockrufe like Alpha-Kerne.
	var loot: Variant = world.get("loot")
	if loot != null:
		var crystal: Vector3 = loot.nearest_lying(here, LOOT_REACH, -1)
		if crystal.is_finite():
			var distance: float = Vector2(crystal.x - here.x, crystal.z - here.z).length()
			if distance < best:
				best = distance
				target = crystal
				harvesting = true
		for lure in loot.lures:
			var distance: float = Vector2(lure.at.x - here.x, lure.at.z - here.z).length()
			if distance < minf(best, 20.0):
				best = distance
				target = lure.at
				harvesting = false
	# Stage 18c: amber nodes close by are broken on the way (like a player).
	var amber: Variant = world.get("loot_nodes")
	if amber != null and amber.get("points") != null:
		for index in amber.points.size():
			if amber.alive[index] == 0:
				continue
			var node: Vector4 = amber.points[index]
			var distance: float = Vector2(node.x - here.x, node.z - here.z).length()
			if distance < minf(best, 12.0):
				best = distance
				target = Vector3(node.x, 0.0, node.z)
				harvesting = false
	for pickup in world.alpha_pickups:
		var distance: float = pickup.position.distance_to(here)
		if distance < minf(best, 14.0):
			best = distance
			target = pickup.position
			harvesting = false
	# Etappe 17 Welle 2: power-ups and mushroom knolls on the way (walk-in only).
	var holding := false
	var boosters: Variant = world.get("powerups")
	if boosters != null:
		for entry in boosters.pickups:
			var distance: float = Vector2(entry.at.x - here.x, entry.at.z - here.z).length()
			if distance < minf(best + 4.0, POWERUP_REACH):
				best = distance
				target = entry.at
				harvesting = false
		for knoll in boosters.knolls:
			if not knoll.alive:
				continue
			var distance: float = Vector2(knoll.at.x - here.x, knoll.at.z - here.z).length()
			if distance < minf(best, KNOLL_REACH):
				best = distance
				target = knoll.at
				harvesting = false
	# Cocoons: free ones always, map cocoons when biomass > 2 x price and pop >= 20;
	# shrines when nothing threatens. The bot stands still inside until it opens.
	var calm: bool = not _any_armed(world) and world.get("apex") == null
	var cocoons: Variant = world.get("chests")
	if cocoons != null and calm and (best == INF or best > 6.0):
		for entry in cocoons.cocoons:
			if int(entry.state) != 0 or bool(entry.denied):
				continue
			var price: int = cocoons.price_of(entry)
			# Welle 2 economy: a map cocoon is bought as soon as the Bernstein suffices.
			if price > 0 and cocoons.available_amber() < price:
				continue
			var distance: float = Vector2(entry.at.x - here.x, entry.at.z - here.z).length()
			# A small swarm only takes free cocoons close by (no long trips into guarded zones).
			var reach: float = COCOON_REACH if world.model.population >= CHEST_MIN_POP or entry.kind in ["start", "map"] else FREE_NEAR
			if distance < minf(best, reach):
				best = distance
				target = entry.at
				harvesting = false
				holding = true
	var altars: Variant = world.get("shrines")
	if altars != null and calm and world.model.population >= SHRINE_MIN_POP and _threat_distance(world, here) > SHRINE_SAFE and (best == INF or best > 6.0):
		for entry in altars.shrines:
			if entry.done:
				continue
			var distance: float = Vector2(entry.at.x - here.x, entry.at.z - here.z).length()
			if distance < minf(best, SHRINE_REACH):
				best = distance
				target = entry.at
				harvesting = false
				holding = true
	# Brutnest (stage 06): walk into it when no enemy is announcing an attack and
	# no crystal lies close by; stay until it hatches.
	var nest: Variant = world.get("nest")
	if nest != null and (best == INF or best > 6.0) and not _any_armed(world) and world.get("apex") == null:
		var inside: float = Vector2(nest.position.x - here.x, nest.position.z - here.z).length()
		best = inside
		target = nest.position if inside > 1.2 else here
		harvesting = false
	# Stage 10: walk into the Migrationsschlund once nothing edible lies close.
	var portal: Variant = world.get("portal")
	# Stage 18b: the Schlund opens in its own clearing across the map - once it
	# is far away the bot commits to the trip (the magnet collects on the way).
	var portal_far: bool = portal != null and Vector2(portal.position.x - here.x, portal.position.z - here.z).length() > 30.0
	if portal != null and (best == INF or best > PORTAL_CORPSE_REACH or portal_far) and not _any_armed(world):
		best = Vector2(portal.position.x - here.x, portal.position.z - here.z).length()
		target = portal.position
		harvesting = false
	# Stage 10: fight the Moosschlund (it is the biggest threat and the best meal).
	var apex: Variant = world.get("apex")
	if apex != null and apex.can_be_hit() and (best == INF or best > APEX_CORPSE_REACH):
		best = apex.position.distance_to(here)
		target = apex.position
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
			enemy_near = minf(enemy_near, enemy.position.distance_to(here) - _body(world, enemy))
	var direction: Vector3 = target - here
	direction.y = 0.0
	if harvesting and direction.length() < world.magnet_radius() * 0.5:
		direction = Vector3.ZERO
	elif holding and direction.length() < 0.8:
		direction = Vector3.ZERO
	elif direction.length() > 0.5:
		# Stage 18b: walk the paths (A* over the flow grid) instead of into walls.
		direction = arena.nav_direction(here, target, 1.0) * minf(direction.length(), 4.0)
	var leap: bool = world.evolution.rank("rudelbiss") > 0 or world.evolution.rank("meute") > 0
	# Etappe 16: no Rally just to collect - a compact swarm without Fluchtreflex
	# lost clearly more to the next ring (tested); the magnet reaches far enough.
	var rally: bool = enemy_near < 1.1 or (leap and enemy_near < 4.0)
	if brood.away != Vector3.ZERO:
		# Mostly away from the brood, a little towards the goal.
		direction = brood.away * 0.75 + direction.normalized() * 0.25 if direction.length() > 0.01 else brood.away
		direction = arena.open_direction(here, direction, 1.0, 3.0)
	if brood.surrounded:
		rally = true
	return {"move": Vector2(direction.x, direction.z).limit_length(1.0), "rally": rally}


func _leader_point(swarm: Variant) -> Vector3:
	if swarm.units.is_empty():
		return swarm.position
	var point: Vector3 = swarm.unit_world_points()[0]
	return Vector3(point.x, 0.0, point.z)


# Escape direction from the Moorbrut within BROOD_ALERT m (weighted by closeness)
# and whether the swarm is surrounded (BROOD_CROWD brood within 2.5 m).
# Etappe 17d: the bot's use of the tribe ability. "dodge" = an announced area is
# coming (Glutsprung / Hetzjagd carry the swarm out, Panzerstoß and
# Schattenschleier blunt it); "crowd" = encircled (Sporenbombe, Säureschwall,
# Panzerstoß clear the ring).
const ABILITY_USE := {
	"dodge": ["glutsprung", "hetzjagd", "panzerstoss", "schattenschleier"],
	"crowd": ["sporenbombe", "saeureschwall", "panzerstoss"],
}
const ABILITY_CROWD := 3
const ABILITY_CROWD_RANGE := 6.0
var ability_uses := 0


func _maybe_ability(world: Variant, reason: String) -> void:
	# BALANCE_NOABILITY=1: baseline without the tribe ability (A/B balance runs).
	if OS.get_environment("BALANCE_NOABILITY") != "":
		return
	var ability: Variant = world.get("abilities")
	if ability == null or not ability.is_ready():
		return
	if not (ABILITY_USE[reason] as Array).has(String(ability.ability_id)):
		return
	world.request_ability()
	ability_uses += 1


const ABILITY_BOSS_RANGE := 7.0


## Bog King or apex (body edge) within `reach` m of the swarm.
func _boss_near(world: Variant, here: Vector3, reach: float) -> bool:
	for boss in [world.get("boss"), world.get("apex")]:
		if boss == null or not is_instance_valid(boss):
			continue
		var edge: float = float(boss.get("body_radius")) if "body_radius" in boss else 1.5
		if Vector2(boss.position.x - here.x, boss.position.z - here.z).length() - edge <= reach:
			return true
	return false


func _enemies_near(world: Variant, here: Vector3, reach: float) -> int:
	var count := 0
	for enemy in _enemies(world):
		if is_instance_valid(enemy) and Vector2(enemy.position.x - here.x, enemy.position.z - here.z).length() <= reach:
			count += 1
	return count


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
	# Stage 09: protect the leader (units[0]) - with 1 LP left the bot keeps a
	# wider berth around every warning zone. A careful player with only a handful
	# of Mawlings also keeps running until the stragglers are out (SMALL_SWARM).
	# Etappe 17c: real LP - "low" is a quarter of the maximum or less.
	var hp: Variant = world.model.get("leader_hp")
	low_hp = hp != null and int(hp) * 4 <= int(world.model.get("leader_max_hp"))
	var extra := LOW_HP_MARGIN if low_hp else 0.0
	var swarm: Variant = world.swarm
	var points: PackedVector3Array = swarm.unit_world_points() if swarm.units.size() <= SMALL_SWARM else PackedVector3Array()
	for hunter in world.hunters:
		if hunter.state == HUNTER.State.WARNING and _noticed(hunter, now):
			escape += _away_all(here, points, hunter.attack_center, TUNING.HUNTER_ATTACK_RADIUS + 0.8 + extra, TUNING.HUNTER_ATTACK_RADIUS + 0.3)
	if world.boss != null and world.boss.state == BOG_KING.State.WARNING and _noticed(world.boss, now):
		escape += _away_all(here, points, world.boss.attack_center, TUNING.BOSS_ATTACK_RADIUS + 0.8 + extra, TUNING.BOSS_ATTACK_RADIUS + 0.3)
	for leaper in world.leapers:
		if leaper.state in [MIRE_LEAPER.State.WARNING, MIRE_LEAPER.State.LEAP] and _noticed(leaper, now):
			var threatened: bool = leaper.zone_margin(here) < 0.6 + extra
			for point in points:
				threatened = threatened or leaper.zone_margin(point) < 0.25
			if threatened:
				escape += leaper.dodge_direction(here).normalized()
	for skitter in world.skitters:
		if skitter.state in [SKITTER.State.WARNING, SKITTER.State.DASH] and _noticed(skitter, now):
			var threatened: bool = skitter.warning_distance(here) < TUNING.SKITTER_WIDTH + 0.7 + extra
			for point in points:
				threatened = threatened or skitter.warning_distance(point) < TUNING.SKITTER_WIDTH + 0.25
			if threatened:
				escape += skitter.dodge_direction(here).normalized()
	# Stage 08: Nibbler snap (small circle, short warning).
	for prey in world.prey:
		if int(prey.get("snap_state")) == 1 and _noticed(prey, now):
			escape += _away_all(here, points, prey.snap_center, TUNING.NIBBLER_SNAP_RADIUS + 0.6 + extra, TUNING.NIBBLER_SNAP_RADIUS + 0.25)
	# Stage 10: Moosschlund wind-ups (lanes, ring, quake with islands).
	var apex: Variant = world.get("apex")
	if apex != null and apex.state == APEX.State.WINDUP and _noticed(apex, now):
		# The whole swarm must leave the locked shape: margin = its spread.
		var spread := 0.0
		for point in swarm.unit_world_points():
			spread = maxf(spread, Vector2(point.x - here.x, point.z - here.z).length())
		escape += _apex_escape(apex, here, points, minf(spread, 4.0) + APEX_MARGIN * 0.5 + extra)
	# Aschenkröte: stay out of the visible Glutpfützen.
	var puddles: Variant = apex.get("puddles") if apex != null else null
	if puddles != null:
		for spot in puddles.spots:
			escape += _away_all(here, points, spot.center, float(spot.radius) + 0.8 + extra, float(spot.radius) + 0.3)
	# Stage 10: Glutsumpf eruptions (announced lava rings).
	var eruptions: Variant = world.get("eruptions")
	if eruptions != null:
		for eruption in eruptions.pending:
			if _noticed(eruption.node, now):
				escape += _away_all(here, points, eruption.center, ERUPTIONS.RADIUS + 0.8 + extra, ERUPTIONS.RADIUS + 0.3)
	return escape


# Nearest safe spot around the leader (and the stragglers) from the locked apex
# shape; ZERO when already safe with margin.
func _apex_escape(apex: Variant, here: Vector3, points: PackedVector3Array, margin: float) -> Vector3:
	if _apex_safe(apex, here, points, margin):
		return Vector3.ZERO
	for distance in [1.5, 3.0, 4.5, 6.0, 8.0, 10.0, 13.0]:
		for index in 16:
			var angle := TAU * float(index) / 16.0
			var spot: Vector3 = here + Vector3(cos(angle), 0.0, sin(angle)) * float(distance)
			if _apex_safe(apex, spot, PackedVector3Array(), margin):
				return (spot - here).normalized()
	var away: Vector3 = here - apex.attack_center
	away.y = 0.0
	return away.normalized() if away.length() > 0.01 else Vector3.RIGHT


func _apex_safe(apex: Variant, spot: Vector3, points: PackedVector3Array, margin: float) -> bool:
	if not apex.is_safe(spot):
		return false
	for index in 8:
		var angle := TAU * float(index) / 8.0
		if not apex.is_safe(spot + Vector3(cos(angle), 0.0, sin(angle)) * margin):
			return false
	for point in points:
		if not apex.is_safe(point):
			return false
	return true


func _body(world: Variant, enemy: Variant) -> float:
	if enemy == world.boss:
		return 2.0
	if enemy is APEX or enemy is APEX_TOAD:
		return float(enemy.body_radius)
	return 0.0


# Away from `center` while the leader is within `reach` or any straggler within `inner`.
func _away_all(here: Vector3, points: PackedVector3Array, center: Vector3, reach: float, inner: float) -> Vector3:
	var direction := _away(here, center, reach)
	if direction != Vector3.ZERO:
		return direction
	for point in points:
		if Vector2(point.x - center.x, point.z - center.z).length() < inner:
			var away := here - center
			away.y = 0.0
			return away.normalized() if away.length() > 0.01 else Vector3.RIGHT
	return Vector3.ZERO


func _away(here: Vector3, center: Vector3, reach: float) -> Vector3:
	var away := here - center
	away.y = 0.0
	if away.length() >= reach:
		return Vector3.ZERO
	return away.normalized() if away.length() > 0.01 else Vector3.RIGHT


# A telegraph counts once the reaction time has passed, unless the bot overlooks it.
# WARNING and the following strike phase share one decision; _forget() resets it.
# Stage 09: with the leader on its last LP the bot is more alert (LOW_HP_FOCUS:
# shorter reaction, fewer overlooked telegraphs) - "protect the leader".
func _noticed(enemy: Variant, now: float) -> bool:
	var key: int = enemy.get_instance_id()
	var alert := low_hp
	if not seen.has(key):
		seen[key] = [now, skill_rng.randf() < miss * (LOW_HP_FOCUS if alert else 1.0)]
	var entry: Array = seen[key]
	return not entry[1] and now - float(entry[0]) >= react * (LOW_HP_FOCUS if alert else 1.0)


func _forget(world: Variant) -> void:
	var armed := {}
	for enemy in _enemies(world):
		if _is_armed(enemy):
			armed[enemy.get_instance_id()] = true
	for prey in world.prey:
		if int(prey.get("snap_state")) == 1:
			armed[prey.get_instance_id()] = true
	var eruptions: Variant = world.get("eruptions")
	if eruptions != null:
		for eruption in eruptions.pending:
			armed[(eruption.node as Object).get_instance_id()] = true
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
	if enemy is APEX or enemy is APEX_TOAD:
		return enemy.state == APEX.State.WINDUP
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
	if world.get("apex") != null:
		result.append(world.apex)
	return result


func _hittable(enemy: Variant) -> bool:
	if enemy is MIRE_LEAPER or enemy is APEX or enemy is APEX_TOAD:
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
	if enemy is APEX or enemy is APEX_TOAD:
		return "apex"
	return "boss"


# The enemy whose strike resolved during the last step (its state left the
# announced phase). Falls back to the closest armed enemy.
func _hitter(world: Variant, before: Dictionary, _older: Dictionary) -> String:
	var armed := {"hunter": [HUNTER.State.WARNING], "skitter": [SKITTER.State.DASH, SKITTER.State.WARNING],
		"leaper": [MIRE_LEAPER.State.LEAP, MIRE_LEAPER.State.WARNING], "boss": [BOG_KING.State.WARNING], "apex": [APEX.State.WINDUP]}
	# Without an armed enemy the loss came from Moorbrut (flood) or a Nibbler snap (other).
	var fallback := "flood" if int(world.get("flood_state")) == 2 else "other"
	var eruptions: Variant = world.get("eruptions")
	if eruptions != null and int(eruptions.resolved_power) > 0:
		fallback = "lava"
	var apex_now: Variant = world.get("apex")
	if apex_now != null and apex_now.get("puddles") != null and int(apex_now.puddles.resolved_power) > 0:
		fallback = "apex"
	for id in before:
		var entry: Array = before[id]
		if not (entry[1] in armed[entry[0]]):
			continue
		fallback = entry[0]
		var enemy: Variant = entry[2]
		if not is_instance_valid(enemy) or int(enemy.state) != entry[1]:
			return entry[0]
	return fallback
