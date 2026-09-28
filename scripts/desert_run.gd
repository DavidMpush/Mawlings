extends Node3D

# Stage 19 phase 2: the Dürrschlund part of a run, kept out of hunt_world.gd.
# HuntWorld creates it next to the Moorbrut horde and calls step() once per
# frame (after the flood). It owns
#   grubs      sand grubs (scripts/sandgrub.gd, same contract as horde.gd): the
#              Sandwurm's grubs (apex.take_grubs()) and small, rare ambush groups
#              in the desert; bites and kills go through HuntWorld's Moorbrut
#              paths (_flood_bites, flood bundles -> crystals);
#   storm      sandstorm waves (scripts/sandstorm.gd): hint, edge veil, haste;
#   brood      one proxy for the attack forms (horde + grubs, brood_pair.gd).
# Quicksand itself lives in the arena (resolve_motion); here only its hint.
#
#   setup(world, swarm, arena)
#   step(delta, damage, message) -> {"ended": bool, "message": String}
#   active() -> bool   (the current biome is the desert)

const TUNING = preload("res://scripts/tuning.gd")
const SANDGRUB = preload("res://scripts/sandgrub.gd")
const SANDSTORM = preload("res://scripts/sandstorm.gd")
const BROOD_PAIR = preload("res://scripts/brood_pair.gd")
const DESERT_ID := "duerrschlund"
# Same bite reach as HuntWorld.MELEE_REACH.
const MELEE_REACH := 1.2

var world: Node3D
var swarm: Node3D
var arena: Node3D
var grubs: Node3D
var storm: Node
var brood: Node3D
var ambush_clock := TUNING.SANDGRUB_FIRST_SECONDS
var ambushes := 0
var grubs_spawned := 0
var grub_kills := 0
var quicksand_seconds := 0.0
var _bundle_clock := 0.0
var _rng := RandomNumberGenerator.new()


func setup(world_node: Node3D, swarm_node: Node3D, arena_node: Node3D) -> void:
	world = world_node
	swarm = swarm_node
	arena = arena_node
	_rng.seed = 190219
	grubs = SANDGRUB.new()
	grubs.name = "Sandgrubs"
	add_child(grubs)
	grubs.setup(world, swarm, arena)
	storm = SANDSTORM.new()
	storm.name = "Sandstorm"
	add_child(storm)
	storm.setup(arena)
	brood = BROOD_PAIR.new()
	brood.name = "Brood pair"
	add_child(brood)
	brood.setup(world.get("horde"), grubs)


# The veil must not stay over the result screen after an extinction.
func _process(_delta: float) -> void:
	if storm != null and world != null and world.get("model") != null and bool(world.model.extinct) and storm.strength > 0.0:
		storm.clear()


func active() -> bool:
	return world != null and String(world.get("biome_id")) == DESERT_ID


# Grub stats: HP grows with the square root of the pressure (gentler than the
# Moorbrut), bite and reward stay fixed (the loss scales with the population).
func grub_stats() -> Dictionary:
	var pressure: float = world.model.pressure() if world.get("model") != null else 1.0
	return {
		"hp": TUNING.SANDGRUB_HP * pow(maxf(1.0, pressure), TUNING.SANDGRUB_PRESSURE_EXPONENT) * float(world.get("enemy_hp")),
		"speed": TUNING.SANDGRUB_SPEED,
		"bite": TUNING.SANDGRUB_BITE * float(world.get("enemy_damage")),
		"bite_cooldown": TUNING.SANDGRUB_BITE_COOLDOWN,
		"biomass": TUNING.SANDGRUB_BIOMASS,
		"dna": TUNING.SANDGRUB_DNA,
	}


## Spawns `amount` grubs bursting out of the sand at `center` (tests, captures).
func spawn_grubs(center: Vector3, amount: int) -> int:
	var made: int = grubs.spawn_burst(Vector3(center.x, 0.0, center.z), amount, grub_stats())
	grubs_spawned += made
	return made


func step(delta: float, damage: float, message: String) -> Dictionary:
	var result := {"ended": false, "message": message}
	var desert := active()
	var hint: String = storm.step(delta, desert)
	if not desert:
		if grubs.count() > 0:
			grubs.clear()
		return result
	# The Sandwurm's grubs (phase 2 rage and every breakthrough).
	var apex: Variant = world.get("apex")
	if apex != null and is_instance_valid(apex) and apex.has_method("take_grubs"):
		for burst in apex.take_grubs():
			spawn_grubs(burst.center, int(burst.count))
	_ambush(delta)
	if grubs.count() > 0 or grubs.get("_kills") != null and not (grubs.get("_kills") as Array).is_empty():
		var points: PackedVector3Array = world._unit_points()
		if not points.is_empty():
			grubs.melee(points, MELEE_REACH, damage, delta)
		var bites: Dictionary = grubs.step(delta, points)
		_collect_kills()
		if world._flood_bites(bites, points):
			result.ended = true
			return result
	_bundle_clock += delta
	if _bundle_clock >= TUNING.FLOOD_BUNDLE_SECONDS and not (world.flood_bundles as Dictionary).is_empty():
		_bundle_clock = 0.0
		if world.flush_flood_bundles():
			result.ended = true
			return result
	# Hints: storm first, then grubs, then quicksand under the swarm (calm only).
	var in_sand: bool = arena != null and arena.has_method("quicksand_factor") and float(arena.quicksand_factor(swarm.position)) < 0.95
	if in_sand:
		quicksand_seconds += delta
	if world._is_calm(String(result.message)):
		if hint != "":
			result.message = hint
		elif grubs.count() > 0:
			result.message = "SANDMADEN · zusammenbleiben und zerbeißen"
		elif apex != null and is_instance_valid(apex) and apex.has_method("is_buried") and apex.is_buried():
			result.message = "SANDWURM GRÄBT · auf die Sandspur achten"
		elif in_sand:
			result.message = "TREIBSAND · bremst, raus auf festen Sand"
	elif hint.begins_with("SANDSTURM ZIEHT") and not String(result.message).begins_with("RAUS"):
		result.message = hint
	return result


# Rare small ambush: a few grubs break out of the sand beside the swarm.
func _ambush(delta: float) -> void:
	var model: Variant = world.get("model")
	if model == null or int(model.population) < TUNING.SANDGRUB_MIN_POPULATION:
		return
	if grubs.count() > 0:
		return
	ambush_clock -= delta
	if ambush_clock > 0.0:
		return
	var pressure: float = model.pressure()
	ambush_clock = TUNING.SANDGRUB_AMBUSH_SECONDS / sqrt(maxf(1.0, pressure)) * _rng.randf_range(0.8, 1.25)
	var amount := _rng.randi_range(TUNING.SANDGRUB_AMBUSH_MIN, TUNING.SANDGRUB_AMBUSH_MAX)
	var angle := _rng.randf() * TAU
	var spot: Vector3 = swarm.position + Vector3(cos(angle), 0.0, sin(angle)) * TUNING.SANDGRUB_AMBUSH_DISTANCE
	if arena != null and arena.has_method("spawn_point_near"):
		spot = arena.spawn_point_near(swarm.position, TUNING.SANDGRUB_AMBUSH_DISTANCE, angle, 1.2)
	elif arena != null and arena.has_method("safe_spawn"):
		spot = arena.safe_spawn(spot, 1.0)
	spawn_grubs(spot, amount)
	ambushes += 1


# Grub kills join HuntWorld's brood bundles (crystals + small remains).
func _collect_kills() -> void:
	for kill in grubs.take_kills():
		var at: Vector3 = kill.get("position", swarm.position)
		var key := Vector2i(floori(at.x / TUNING.FLOOD_BUNDLE_CELL), floori(at.z / TUNING.FLOOD_BUNDLE_CELL))
		var bundles: Dictionary = world.flood_bundles
		var bundle: Dictionary = bundles.get(key, {"sum": Vector3.ZERO, "n": 0, "biomass": 0.0, "dna": 0})
		var count := maxi(1, int(kill.get("count", 1)))
		bundle.sum += Vector3(at.x, 0.0, at.z) * float(count)
		bundle.n += count
		bundle.biomass += float(kill.get("biomass", TUNING.SANDGRUB_BIOMASS * count))
		bundle.dna += int(kill.get("dna", TUNING.SANDGRUB_DNA * count))
		bundles[key] = bundle
		grub_kills += count
		for index in count:
			world.model.record_kill("sandgrub")
		world._note_kills(count, 1.0)


func clear() -> void:
	if grubs != null:
		grubs.clear()
	if storm != null:
		storm.clear()
