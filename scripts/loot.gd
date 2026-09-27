extends Node3D

# Etappe 16 - Beute-Kristalle und Magnet. Ersetzt die Kadaver-Ernte: jeder Tod
# platzt in 1-6 Kristalle auf (Biomasse Bernstein/Gold, DNA Türkis), die im
# Bogen herausspringen und liegen bleiben, bis sie eingesammelt sind (kein
# Verfall, Ressourcenregel). Kristalle im Magnetradius des Schwarms fliegen
# beschleunigend zu einem Tier und werden beim Ankommen gutgeschrieben; ein
# Lockruf-Drop holt alle Kristalle der Karte als Kette heran.
#
#   loot.setup(arena)
#   loot.burst(at, biomass, dna, rank)            # Tod: 1-6 Kristalle im Bogen
#   loot.drop(kind, value, at, from, hop)         # ein einzelner Kristall
#   loot.step(delta, centre, radius, points, take_biomass) -> {"biomass", "dna", "crystals"}
#   loot.vacuum(centre)                           # Lockruf: alle Kristalle fliegen
#   loot.add_lure(at) / loot.lures                # pulsierender Lockruf-Drop
#
# Leistung: kein Knoten je Kristall. Daten liegen in gepackten Arrays mit
# Freiliste; liegende Kristalle stehen in einem Raster (GRID m), der Magnet
# prüft nur Zellen im Radius. Gezeichnet wird mit einer MultiMesh je Größenstufe
# (klein/mittel/groß, Sorte über INSTANCE_CUSTOM); Drehen/Wippen läuft im
# Vertex-Shader, pro Frame werden nur springende und fliegende Kristalle
# geschrieben.

const CORPSE_VISUALS = preload("res://scripts/corpse_visuals.gd")
const TUNING = preload("res://scripts/tuning.gd")

enum Kind { BIOMASS, DNA }
enum State { FREE, HOP, LYING, WAIT, FLY }
const TIER_LAYERS := ["small", "medium", "big"]
# Crystal model per tier (corpse_visuals drop meshes: the chunky medium gem reads
# better than the slim shard at phone size), its model height (DROP_HEIGHT) and
# the drawn height (m) per sort and tier; within a tier the value adds up to +30 %.
const TIER_MESH := ["drop_medium", "drop_medium", "drop_big"]
const MESH_HEIGHT := [1.0, 1.0, 1.2]
# Handtest (Polier-Runde): 55 % (small) .. 72 % (big) of the first sizes, so
# the flood does not look like confetti; big ones stay recognisable.
const DRAW_HEIGHT := [[0.34, 0.53, 0.86], [0.31, 0.48, 0.78]]
# Soft billboard glow behind every crystal (one more MultiMesh): radius x height.
const GLOW_SIZE := 1.1
# Value thresholds per sort: below [0] small, below [1] medium, else big.
const TIER_VALUE := [[3.0, 9.0], [12.0, 36.0]]
const BIO_COLOR := Color("ffb13b")
const BIO_GLOW := Color("ffe07a")
const DNA_COLOR := Color("35e6d4")
const DNA_GLOW := Color("aefcff")
const LURE_COLOR := Color("ff7ad9")
const LURE_GLOW := Color("fff1a8")

const GRID := 2.5
const LIFT := 0.22            # hover height of a lying crystal (base above ground)
const FLY_LIFT := 0.85        # flight height
const COLLECT_DISTANCE := 0.5

var arena: Node3D
# Crystal data (struct of arrays, slot = id).
var pos := PackedVector3Array()
var start := PackedVector3Array()
var goal := PackedVector3Array()
var value := PackedFloat32Array()
var kind := PackedInt32Array()
var tier := PackedInt32Array()
var state := PackedInt32Array()
var timer := PackedFloat32Array()
var span := PackedFloat32Array()
var speed := PackedFloat32Array()
var top_speed := PackedFloat32Array()
var accel := PackedFloat32Array()
var target := PackedInt32Array()
var phase := PackedFloat32Array()
var _free: Array[int] = []
# Lying crystals per grid cell (Vector2i -> Array[int]).
var grid: Dictionary = {}
var _cell_of: Array[Vector2i] = []
# Crystals that move this frame (hopping, waiting for the vacuum, flying).
var moving: Array[int] = []
var lying := 0
# Above this many lying crystals every landing joins a neighbour (tests/bench raise it).
var soft_cap: int = TUNING.LOOT_SOFT_CAP
# During the flood (HuntWorld sets it) crystals bundle earlier: from
# LOOT_FLOOD_CROWD alike per cell, always above LOOT_FLOOD_SOFT_CAP lying.
var flood := false
# Lockruf drops: {"node": Node3D, "at": Vector3, "age": float, "fly": float, "speed": float}.
var lures: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
# Statistics for tests and the HUD.
var spawned := 0
var merged := 0
var collected := 0
var vacuums := 0
var _layers: Array = []
var _glow: Object
var _clock := 0.0

static var _material: ShaderMaterial
static var _meshes := {}
# Triangle budget per crystal (the import LOD closest below it): 1000 lying
# crystals with the full ~1200-triangle gem were 1.3 M triangles.
const CRYSTAL_TRIS := 160
static var _lure_parts := {}


func _ready() -> void:
	rng.seed = 16016
	for index in TIER_LAYERS.size():
		_layers.append(_make_layer(index))
	_glow = _make_glow_layer()


func setup(arena_node: Node3D) -> void:
	arena = arena_node


## Everything gone (new run).
func clear() -> void:
	for layer in _layers:
		layer.clear()
	_glow.clear()
	for lure in lures:
		if is_instance_valid(lure.node):
			lure.node.queue_free()
	lures.clear()
	pos.clear(); start.clear(); goal.clear(); value.clear(); kind.clear(); tier.clear()
	state.clear(); timer.clear(); span.clear(); speed.clear(); top_speed.clear(); accel.clear(); target.clear(); phase.clear()
	_free.clear()
	_cell_of.clear()
	grid.clear()
	moving.clear()
	lying = 0


# ---------------------------------------------------------------- spawning

## A kill bursts into crystals: biomass split into 1..cap crystals (cap by rank:
## normal 3, mini 4, boss 4), DNA into 1 (normal) or 2 (mini/boss); never more
## than LOOT_MAX_PER_KILL. They hop out in a ring around `at`.
func burst(at: Vector3, biomass: float, dna: int, rank := "normal") -> void:
	# "horde" (Moorbrut bundles of the flood): one biomass crystal at most.
	var bio_cap: int = {"normal": 3, "mini": 4, "boss": 4, "horde": 1}.get(rank, 3)
	var dna_cap: int = 1 if rank == "normal" or rank == "horde" else 2
	var bio_count := clampi(ceili(biomass / TUNING.LOOT_BIO_CHUNK - 0.001), 1, bio_cap) if biomass > 0.0 else 0
	var dna_count := clampi(ceili(float(dna) / TUNING.LOOT_DNA_CHUNK - 0.001), 1, dna_cap) if dna > 0 else 0
	while bio_count + dna_count > TUNING.LOOT_MAX_PER_KILL:
		bio_count -= 1
	var total := bio_count + dna_count
	var reach: float = {"normal": 1.3, "mini": 1.9, "boss": 3.2, "horde": 0.9}.get(rank, 1.3)
	var turn := rng.randf() * TAU
	var slot := 0
	for index in bio_count:
		drop(Kind.BIOMASS, biomass / float(bio_count), at, _ring(at, turn, slot, total, reach))
		slot += 1
	for index in dna_count:
		# DNA whole numbers: the last crystal takes the rest.
		var share := dna / dna_count + (dna % dna_count if index == dna_count - 1 else 0)
		drop(Kind.DNA, float(share), at, _ring(at, turn, slot, total, reach))
		slot += 1


func _ring(at: Vector3, turn: float, slot: int, total: int, reach: float) -> Vector3:
	var angle := turn + TAU * float(slot) / float(maxi(1, total)) + rng.randf_range(-0.35, 0.35)
	var distance := reach * rng.randf_range(0.55, 1.0)
	var spot := at + Vector3(cos(angle), 0.0, sin(angle)) * distance
	spot.y = 0.0
	if arena != null and arena.has_method("is_open") and not arena.is_open(spot, 0.15):
		spot = arena.safe_spawn(spot, 0.2)
		spot.y = 0.0
	return spot


## One crystal of `sort` worth `amount`, hopping from `from` to `landing`
## (hop = false: it lies there at once). Returns its id.
func drop(sort: int, amount: float, from: Vector3, landing: Vector3, hop := true) -> int:
	if amount <= 0.0:
		return -1
	var id := _alloc()
	kind[id] = sort
	value[id] = amount
	tier[id] = _tier_for(sort, amount)
	phase[id] = rng.randf()
	landing.y = 0.0
	goal[id] = landing
	spawned += 1
	if hop:
		start[id] = Vector3(from.x, 0.7, from.z)
		pos[id] = start[id]
		state[id] = State.HOP
		span[id] = rng.randf_range(TUNING.LOOT_HOP_SECONDS[0], TUNING.LOOT_HOP_SECONDS[1])
		timer[id] = 0.0
		moving.append(id)
		_draw(id)
	else:
		pos[id] = landing
		_land(id)
	return id


func _alloc() -> int:
	if not _free.is_empty():
		return _free.pop_back()
	var id := pos.size()
	pos.append(Vector3.ZERO); start.append(Vector3.ZERO); goal.append(Vector3.ZERO)
	value.append(0.0); kind.append(0); tier.append(0); state.append(State.FREE)
	timer.append(0.0); span.append(0.0); speed.append(0.0); top_speed.append(0.0); accel.append(0.0)
	target.append(-1); phase.append(0.0)
	_cell_of.append(Vector2i.ZERO)
	return id


func _release(id: int) -> void:
	_layers[tier[id]].erase(id)
	_glow.erase(id)
	state[id] = State.FREE
	value[id] = 0.0
	_free.append(id)


static func _tier_for(sort: int, amount: float) -> int:
	var limits: Array = TIER_VALUE[sort]
	if amount < float(limits[0]):
		return 0
	return 1 if amount < float(limits[1]) else 2


static func cell_key(at: Vector3) -> Vector2i:
	return Vector2i(floori(at.x / GRID), floori(at.z / GRID))


# Landing: joins a crowded cell's biggest crystal of its sort (bundling keeps
# the count low), otherwise it lies in its own grid cell.
func _land(id: int) -> void:
	var key := cell_key(goal[id])
	var cap: int = mini(soft_cap, TUNING.LOOT_FLOOD_SOFT_CAP) if flood else soft_cap
	var crowd: int = (TUNING.LOOT_FLOOD_CROWD if flood else TUNING.LOOT_CELL_CROWD) if lying < cap else 1
	var host := _host_in(key, kind[id], crowd)
	if host < 0 and lying >= cap:
		for x in range(key.x - 1, key.x + 2):
			for z in range(key.y - 1, key.y + 2):
				if host < 0:
					host = _host_in(Vector2i(x, z), kind[id], 1)
	if host >= 0:
		_absorb_into(host, value[id])
		_release(id)
		merged += 1
		return
	state[id] = State.LYING
	pos[id] = goal[id]
	_cell_of[id] = key
	if not grid.has(key):
		grid[key] = []
	(grid[key] as Array).append(id)
	lying += 1
	_draw(id)


# Biggest lying crystal of `sort` in a cell with at least `crowd` of them; -1 when none.
func _host_in(key: Vector2i, sort: int, crowd: int) -> int:
	var list: Array = grid.get(key, [])
	var best := -1
	var same := 0
	for other: int in list:
		if kind[other] != sort:
			continue
		same += 1
		if best < 0 or value[other] > value[best]:
			best = other
	return best if same >= crowd else -1


func _absorb_into(host: int, amount: float) -> void:
	value[host] += amount
	var grown := _tier_for(kind[host], value[host])
	if grown != tier[host]:
		_layers[tier[host]].erase(host)
		tier[host] = grown
	_draw(host)


# ---------------------------------------------------------------- magnet

## Moves hopping and flying crystals and pulls lying ones within `radius` of
## `centre`. `points` are the visible Mawlings (each flying crystal homes in on
## one of them); biomass crystals only fly while `take_biomass` (a full swarm
## leaves them lying). Returns what arrived this step.
func step(delta: float, centre: Vector3, radius: float, points: PackedVector3Array, take_biomass := true) -> Dictionary:
	_clock += delta
	var result := {"biomass": 0.0, "dna": 0, "crystals": 0, "bio_crystals": 0, "dna_crystals": 0}
	_grab(centre, radius, points, take_biomass)
	var index := moving.size() - 1
	while index >= 0:
		var id: int = moving[index]
		var done := false
		match state[id]:
			State.HOP:
				timer[id] += delta
				var t := clampf(timer[id] / span[id], 0.0, 1.0)
				var flat: Vector3 = start[id].lerp(goal[id], 1.0 - (1.0 - t) * (1.0 - t))
				flat.y = lerpf(start[id].y, LIFT, t) + 4.0 * TUNING.LOOT_HOP_HEIGHT * t * (1.0 - t)
				pos[id] = flat
				if t >= 1.0:
					done = true
					_land(id)
				else:
					_draw(id)
			State.WAIT:
				timer[id] -= delta
				if timer[id] <= 0.0:
					state[id] = State.FLY
				_draw(id)
			State.FLY:
				if kind[id] == Kind.BIOMASS and not take_biomass:
					# The swarm filled up on the way: the crystal lies down where it is.
					done = true
					goal[id] = Vector3(pos[id].x, 0.0, pos[id].z)
					_land(id)
				elif _fly(id, delta, centre, points):
					done = true
					result.crystals += 1
					if kind[id] == Kind.BIOMASS:
						result.biomass += value[id]
						result.bio_crystals += 1
					else:
						result.dna += int(round(value[id]))
						result.dna_crystals += 1
					collected += 1
					_release(id)
			_:
				done = true
		if done:
			moving.remove_at(index)
		index -= 1
	_step_lures(delta, centre, radius)
	return result


# Lying crystals inside the radius start their flight (grid cells only).
func _grab(centre: Vector3, radius: float, points: PackedVector3Array, take_biomass: bool) -> void:
	if lying <= 0 or radius <= 0.0:
		return
	var low := cell_key(centre - Vector3(radius, 0.0, radius))
	var high := cell_key(centre + Vector3(radius, 0.0, radius))
	var reach := radius * radius
	for x in range(low.x, high.x + 1):
		for z in range(low.y, high.y + 1):
			var key := Vector2i(x, z)
			if not grid.has(key):
				continue
			var list: Array = grid[key]
			var index := list.size() - 1
			while index >= 0:
				var id: int = list[index]
				var dx: float = pos[id].x - centre.x
				var dz: float = pos[id].z - centre.z
				if dx * dx + dz * dz <= reach and (take_biomass or kind[id] == Kind.DNA):
					list.remove_at(index)
					lying -= 1
					_launch(id, points, 0.0, TUNING.LOOT_FLY_MAX_SPEED, TUNING.LOOT_FLY_ACCEL)
				index -= 1
			if list.is_empty():
				grid.erase(key)


# Starts the flight of a lying crystal (after `delay` s) towards the nearest of a
# few sampled Mawlings.
func _launch(id: int, points: PackedVector3Array, delay: float, fastest: float, push: float) -> void:
	state[id] = State.WAIT if delay > 0.0 else State.FLY
	timer[id] = delay
	speed[id] = -TUNING.LOOT_FLY_KICK
	top_speed[id] = fastest
	accel[id] = push
	target[id] = _nearest_sample(pos[id], points)
	moving.append(id)


static func _nearest_sample(at: Vector3, points: PackedVector3Array) -> int:
	if points.is_empty():
		return -1
	var stride := maxi(1, points.size() / 12)
	var best := 0
	var best_distance := INF
	var index := 0
	while index < points.size():
		var dx := points[index].x - at.x
		var dz := points[index].z - at.z
		var distance := dx * dx + dz * dz
		if distance < best_distance:
			best_distance = distance
			best = index
		index += stride
	return best


# One flight step; true when the crystal reached its Mawling.
func _fly(id: int, delta: float, centre: Vector3, points: PackedVector3Array) -> bool:
	var aim: Vector3 = centre
	var who: int = target[id]
	if who >= 0 and who < points.size():
		aim = points[who]
	aim.y = FLY_LIFT * 0.6
	var here: Vector3 = pos[id]
	var offset := aim - here
	var distance := offset.length()
	speed[id] = minf(top_speed[id], speed[id] + accel[id] * delta)
	var travel: float = speed[id] * delta
	if distance <= COLLECT_DISTANCE or travel >= distance:
		return true
	var direction := offset / distance
	here += direction * travel
	# Rise into the flight height early, then home in.
	here.y = lerpf(here.y, FLY_LIFT, minf(1.0, delta * 10.0))
	pos[id] = here
	_draw(id)
	return false


## Lockruf: every lying (and hopping) crystal of the map flies to the swarm as a
## chain - the nearest first, the delay grows with the distance (<= LOOT_VACUUM_SPREAD s)
## and far crystals fly faster, so the whole map arrives within ~2.5 s.
## Biomass stays when the swarm is full. Returns the number of crystals called.
func vacuum(centre: Vector3, points: PackedVector3Array, take_biomass := true) -> int:
	vacuums += 1
	var called := 0
	# Hopping crystals land at once so they join the chain.
	for id in moving.duplicate():
		if state[id] == State.HOP:
			moving.erase(id)
			_land(id)
	var far := 1.0
	for key in grid:
		for id: int in grid[key]:
			far = maxf(far, Vector2(pos[id].x - centre.x, pos[id].z - centre.z).length())
	for key in grid.keys():
		var list: Array = grid[key]
		var index := list.size() - 1
		while index >= 0:
			var id: int = list[index]
			if take_biomass or kind[id] == Kind.DNA:
				var distance := Vector2(pos[id].x - centre.x, pos[id].z - centre.z).length()
				var delay: float = TUNING.LOOT_VACUUM_SPREAD * pow(distance / far, 0.75) * rng.randf_range(0.85, 1.0)
				list.remove_at(index)
				lying -= 1
				# Far crystals fly faster: every flight takes about LOOT_VACUUM_FLIGHT s.
				var flight: float = TUNING.LOOT_VACUUM_FLIGHT
				_launch(id, points, delay, maxf(TUNING.LOOT_FLY_MAX_SPEED, 2.0 * distance / flight), maxf(TUNING.LOOT_FLY_ACCEL * 1.5, 2.6 * distance / (flight * flight)))
				called += 1
			index -= 1
		if list.is_empty():
			grid.erase(key)
	return called


## Credits every crystal at once (tests, captures): returns the step() result
## shape; biomass stays when `take_biomass` is false. Lockrufe stay.
func take_all(take_biomass := true) -> Dictionary:
	var result := {"biomass": 0.0, "dna": 0, "crystals": 0, "bio_crystals": 0, "dna_crystals": 0}
	for id in pos.size():
		if state[id] == State.FREE or (kind[id] == Kind.BIOMASS and not take_biomass):
			continue
		if state[id] == State.LYING:
			(grid[_cell_of[id]] as Array).erase(id)
			if (grid[_cell_of[id]] as Array).is_empty():
				grid.erase(_cell_of[id])
			lying -= 1
		else:
			moving.erase(id)
		result.crystals += 1
		if kind[id] == Kind.BIOMASS:
			result.biomass += value[id]
			result.bio_crystals += 1
		else:
			result.dna += int(round(value[id]))
			result.dna_crystals += 1
		collected += 1
		_release(id)
	if not take_biomass:
		# Hopping biomass lands where it was heading.
		for id in moving.duplicate():
			if state[id] == State.HOP:
				moving.erase(id)
				_land(id)
	return result


# ---------------------------------------------------------------- queries

## Crystals alive (lying, hopping, flying).
func count() -> int:
	return pos.size() - _free.size()


func lying_count() -> int:
	return lying


func flying_count() -> int:
	var result := 0
	for id in moving:
		if state[id] == State.FLY or state[id] == State.WAIT:
			result += 1
	return result


## Total value of one sort still out there (lying + moving).
func total(sort: int) -> float:
	var sum := 0.0
	for id in pos.size():
		if state[id] != State.FREE and kind[id] == sort:
			sum += value[id]
	return sum


## Lying crystal ids within `reach` of `at` (tests, bot).
func lying_near(at: Vector3, reach: float) -> Array[int]:
	var result: Array[int] = []
	var low := cell_key(at - Vector3(reach, 0.0, reach))
	var high := cell_key(at + Vector3(reach, 0.0, reach))
	for x in range(low.x, high.x + 1):
		for z in range(low.y, high.y + 1):
			for id: int in grid.get(Vector2i(x, z), []):
				if Vector2(pos[id].x - at.x, pos[id].z - at.z).length() <= reach:
					result.append(id)
	return result


## Nearest lying crystal position (INF when none) - cell rings around `at`, up to `reach` m.
func nearest_lying(at: Vector3, reach := 40.0, sort := -1) -> Vector3:
	var best := Vector3.INF
	var best_distance := INF
	var middle := cell_key(at)
	var rings := ceili(reach / GRID)
	for ring in rings + 1:
		for x in range(middle.x - ring, middle.x + ring + 1):
			for z in range(middle.y - ring, middle.y + ring + 1):
				if absi(x - middle.x) != ring and absi(z - middle.y) != ring:
					continue
				for id: int in grid.get(Vector2i(x, z), []):
					if sort >= 0 and kind[id] != sort:
						continue
					var distance := Vector2(pos[id].x - at.x, pos[id].z - at.z).length_squared()
					if distance < best_distance:
						best_distance = distance
						best = pos[id]
		# A hit in this ring can still lose to a closer one in the next ring only
		# by less than one cell; good enough for pointers and the bot.
		if best_distance < INF and ring >= 1:
			break
	return best


## Lying crystals bundled into coarse map cells: (x, z, size) triples, size 0/1/2
## by total value (minimap "corpses" layer), plus the Lockruf drops as size 3
## (hud_minimap draws them as their own pulsing plate).
func map_marks(cell := 8.0) -> PackedFloat32Array:
	var cells := {}
	for key in grid:
		for id: int in grid[key]:
			var big := Vector2i(floori(pos[id].x / cell), floori(pos[id].z / cell))
			var entry: Vector3 = cells.get(big, Vector3.ZERO)
			var weight := value[id] if kind[id] == Kind.BIOMASS else value[id] * 0.25
			cells[big] = Vector3(entry.x + pos[id].x * weight, entry.y + pos[id].z * weight, entry.z + weight)
	var result := PackedFloat32Array()
	for big in cells:
		var entry: Vector3 = cells[big]
		if entry.z <= 0.0:
			continue
		result.append(entry.x / entry.z)
		result.append(entry.y / entry.z)
		result.append(2.0 if entry.z >= 30.0 else (1.0 if entry.z >= 8.0 else 0.0))
	for lure in lures:
		result.append(lure.at.x)
		result.append(lure.at.z)
		result.append(3.0)
	return result


# ---------------------------------------------------------------- Lockruf

## Drops a pulsing Lockruf beside `at`. It stays until the swarm reaches it (the
## magnet pulls it like a crystal).
func add_lure(at: Vector3) -> Node3D:
	var spot := at
	spot.y = 0.0
	if arena != null and arena.has_method("safe_spawn"):
		spot = arena.safe_spawn(spot, 0.8)
		spot.y = 0.0
	var node := _build_lure()
	node.position = spot
	add_child(node)
	lures.append({"node": node, "at": spot, "age": 0.0, "fly": -1.0, "speed": 0.0})
	return node


## Set by step(): lures that reached the swarm this step (HuntWorld triggers vacuum()).
var lures_taken := 0


func _step_lures(delta: float, centre: Vector3, radius: float) -> void:
	lures_taken = 0
	var index := lures.size() - 1
	while index >= 0:
		var lure: Dictionary = lures[index]
		lure.age += delta
		var node: Node3D = lure.node
		var flat := Vector2(lure.at.x - centre.x, lure.at.z - centre.z)
		var distance := flat.length()
		if lure.fly < 0.0 and distance <= maxf(radius, TUNING.LURE_PICKUP_RADIUS):
			lure.fly = 0.0
			lure.speed = 2.0
		if lure.fly >= 0.0:
			lure.fly += delta
			lure.speed = minf(22.0, lure.speed + 30.0 * delta)
			var step_length: float = lure.speed * delta
			if distance <= TUNING.LURE_PICKUP_RADIUS * 0.6 or step_length >= distance:
				lures_taken += 1
				if is_instance_valid(node):
					node.queue_free()
				lures.remove_at(index)
				index -= 1
				continue
			var move := -flat / maxf(distance, 0.001) * step_length
			lure.at += Vector3(move.x, 0.0, move.y)
		if is_instance_valid(node):
			node.position = lure.at
			var pulse := 0.5 + 0.5 * sin(lure.age * 5.0)
			var gem: Node3D = node.get_node("Gem")
			gem.position.y = 1.0 + 0.18 * sin(lure.age * 2.4)
			gem.rotation.y += delta * 2.2
			gem.scale = Vector3.ONE * (1.0 + 0.12 * pulse)
			var ring: Node3D = node.get_node("Ring")
			var grow := 1.0 + 0.5 * fmod(lure.age * 0.9, 1.0)
			ring.scale = Vector3(grow, 0.25, grow)
			(ring.get("material_override") as ShaderMaterial).set_shader_parameter("fade", 1.0 - fmod(lure.age * 0.9, 1.0))
		index -= 1


func _build_lure() -> Node3D:
	var parts := _lure_meshes()
	var node := Node3D.new()
	node.name = "Lockruf"
	var gem := MeshInstance3D.new()
	gem.name = "Gem"
	gem.mesh = parts.gem
	gem.material_override = parts.gem_material
	gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(gem)
	var halo := MeshInstance3D.new()
	halo.name = "Halo"
	halo.mesh = parts.halo
	halo.material_override = parts.halo_material
	halo.position = Vector3(0.0, 0.05, 0.0)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(halo)
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	ring.mesh = parts.ring
	# Own material instance: the ring fades while it grows.
	ring.material_override = (parts.ring_material as ShaderMaterial).duplicate()
	ring.position = Vector3(0.0, 0.08, 0.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(ring)
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	beam.mesh = parts.beam
	beam.material_override = parts.beam_material
	beam.position = Vector3(0.0, 2.6, 0.0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(beam)
	return node


static func _lure_meshes() -> Dictionary:
	if not _lure_parts.is_empty():
		return _lure_parts
	var gem_material := ShaderMaterial.new()
	var gem_shader := Shader.new()
	gem_shader.code = LURE_GEM_SHADER
	gem_material.shader = gem_shader
	gem_material.set_shader_parameter("tint", LURE_COLOR)
	gem_material.set_shader_parameter("glow", LURE_GLOW)
	var glow_shader := Shader.new()
	glow_shader.code = LURE_GLOW_SHADER
	var halo_material := ShaderMaterial.new()
	halo_material.shader = glow_shader
	halo_material.set_shader_parameter("tint", LURE_COLOR)
	halo_material.set_shader_parameter("strength", 0.85)
	var ring_material := ShaderMaterial.new()
	ring_material.shader = glow_shader
	ring_material.set_shader_parameter("tint", LURE_GLOW)
	ring_material.set_shader_parameter("strength", 1.0)
	ring_material.set_shader_parameter("ring", 1.0)
	var beam_material := ShaderMaterial.new()
	beam_material.shader = glow_shader
	beam_material.set_shader_parameter("tint", LURE_COLOR)
	beam_material.set_shader_parameter("strength", 0.55)
	beam_material.set_shader_parameter("beam", 1.0)
	var gem: Mesh = _crystal_mesh("drop_big")
	var halo := PlaneMesh.new()
	halo.size = Vector2(4.4, 4.4)
	var ring := TorusMesh.new()
	ring.inner_radius = 1.25
	ring.outer_radius = 1.5
	ring.rings = 40
	ring.ring_segments = 4
	var beam := CylinderMesh.new()
	beam.top_radius = 0.06
	beam.bottom_radius = 0.34
	beam.height = 5.2
	beam.radial_segments = 14
	beam.rings = 1
	beam.cap_top = false
	beam.cap_bottom = false
	_lure_parts = {"gem": gem, "gem_material": gem_material, "halo": halo, "halo_material": halo_material, "ring": ring, "ring_material": ring_material, "beam": beam, "beam_material": beam_material}
	return _lure_parts


# ---------------------------------------------------------------- drawing

func _make_layer(index: int) -> Object:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.use_colors = true
	multimesh.mesh = _crystal_mesh(TIER_MESH[index])
	multimesh.instance_count = CORPSE_VISUALS.BATCH_STEP
	multimesh.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.name = "Loot " + String(TIER_LAYERS[index])
	node.multimesh = multimesh
	node.material_override = _crystal_material()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	# Crystals spread over the whole map: never culled by the batch's own box.
	node.custom_aabb = AABB(Vector3(-100000.0, -10.0, -100000.0), Vector3(200000.0, 40.0, 200000.0))
	add_child(node)
	node.top_level = true
	node.transform = Transform3D.IDENTITY
	return CORPSE_VISUALS.Layer.new(node)


# Low-poly crystal mesh (same model as the corpse drops, import LOD baked).
static func _crystal_mesh(drop: String) -> Mesh:
	if _meshes.has(drop):
		return _meshes[drop]
	var b = CORPSE_VISUALS.Builder.new()
	b.glb(CORPSE_VISUALS.DROP_SCENES[drop], 1.0, Basis.IDENTITY, Vector3.ZERO, Color.WHITE, true, CORPSE_VISUALS.DROP_HEIGHT[drop], false, CRYSTAL_TRIS)
	var mesh: Mesh = b.commit()
	_meshes[drop] = mesh
	return mesh


func _draw(id: int) -> void:
	var sort: int = kind[id]
	var level: int = tier[id]
	var limits: Array = TIER_VALUE[sort]
	var low := 0.0 if level == 0 else float(limits[level - 1])
	var high := float(limits[mini(level, 1)]) if level < 2 else float(limits[1]) * 3.0
	var grow := 1.0 + 0.3 * clampf((value[id] - low) / maxf(0.001, high - low), 0.0, 1.0)
	var height: float = float(DRAW_HEIGHT[sort][level]) * grow
	var moving_now := state[id] == State.FLY or state[id] == State.WAIT or state[id] == State.HOP
	var flight := 1.0 if state[id] == State.FLY else (0.5 if moving_now else 0.0)
	var scale := height / float(MESH_HEIGHT[level])
	var basis := Basis(Vector3.UP, phase[id] * TAU).scaled(Vector3.ONE * scale)
	if state[id] == State.FLY:
		# Stretched a little along the flight (reads as speed).
		basis = basis.scaled(Vector3(0.85, 1.25, 0.85))
	var at: Vector3 = pos[id]
	if state[id] == State.LYING:
		at.y = LIFT
	var custom := Color(float(sort), phase[id], 1.0, flight)
	_layers[level].put(id, Transform3D(basis, at), custom)
	var glow := height * GLOW_SIZE * (1.25 if state[id] == State.FLY else 1.0)
	_glow.put(id, Transform3D(Basis.from_scale(Vector3(glow, glow, glow)), at + Vector3(0.0, height * 0.45, 0.0)), custom)


func _make_glow_layer() -> Object:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = CORPSE_VISUALS.BATCH_STEP
	multimesh.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.name = "Loot glow"
	node.multimesh = multimesh
	var shader := Shader.new()
	shader.code = GLOW_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("bio_glow", BIO_COLOR)
	material.set_shader_parameter("dna_glow", DNA_COLOR)
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	node.custom_aabb = AABB(Vector3(-100000.0, -10.0, -100000.0), Vector3(200000.0, 40.0, 200000.0))
	add_child(node)
	node.top_level = true
	node.transform = Transform3D.IDENTITY
	return CORPSE_VISUALS.Layer.new(node)


static func _crystal_material() -> ShaderMaterial:
	if _material != null:
		return _material
	var shader := Shader.new()
	shader.code = CRYSTAL_SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("bio_color", BIO_COLOR)
	_material.set_shader_parameter("bio_glow", BIO_GLOW)
	_material.set_shader_parameter("dna_color", DNA_COLOR)
	_material.set_shader_parameter("dna_glow", DNA_GLOW)
	return _material


# INSTANCE_CUSTOM: x = sort (0 biomass, 1 DNA), y = phase, z = glow, w = flight (0 lying .. 1 flying).
const CRYSTAL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform vec3 bio_color : source_color;
uniform vec3 bio_glow : source_color;
uniform vec3 dna_color : source_color;
uniform vec3 dna_glow : source_color;
uniform float bob = 0.07;
uniform float spin = 1.1;
varying vec4 loot;
void vertex() {
	loot = INSTANCE_CUSTOM;
	float lying = 1.0 - loot.w;
	float phase = loot.y * 6.2832;
	float a = TIME * spin * (1.0 + 2.5 * loot.w) + phase;
	mat2 turn = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
	VERTEX.xz = turn * VERTEX.xz;
	NORMAL.xz = turn * NORMAL.xz;
	VERTEX.y += bob * lying * (0.5 + 0.5 * sin(TIME * 2.2 + phase));
}
void fragment() {
	float dna = step(0.5, loot.x);
	vec3 tint = mix(bio_color, dna_color, dna);
	vec3 glow = mix(bio_glow, dna_glow, dna);
	float grey = dot(COLOR.rgb, vec3(0.3, 0.55, 0.15));
	float facing = clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0);
	float pulse = 0.5 + 0.5 * sin(TIME * 3.0 + loot.y * 6.2832);
	vec3 col = tint * (0.55 + 0.75 * grey) * (0.8 + 0.35 * facing);
	col += glow * pow(1.0 - facing, 2.0) * (0.35 + 0.22 * pulse);
	col += glow * 0.07 * pulse;
	col = mix(col, glow * 1.15, 0.35 * loot.w);
	ALBEDO = col;
}
"""

# Camera-facing additive glow (billboard keeps the instance scale).
const GLOW_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec3 bio_glow : source_color;
uniform vec3 dna_glow : source_color;
varying vec4 loot;
void vertex() {
	loot = INSTANCE_CUSTOM;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float fall = pow(clamp(1.0 - d, 0.0, 1.0), 2.2);
	float pulse = 0.8 + 0.2 * sin(TIME * 3.0 + loot.y * 6.2832);
	ALBEDO = mix(bio_glow, dna_glow, step(0.5, loot.x));
	ALPHA = clamp(fall * pulse * (0.2 + 0.4 * loot.w), 0.0, 1.0);
}
"""

const LURE_GEM_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform vec3 tint : source_color;
uniform vec3 glow : source_color;
void fragment() {
	float grey = dot(COLOR.rgb, vec3(0.3, 0.55, 0.15));
	float facing = clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0);
	float pulse = 0.5 + 0.5 * sin(TIME * 5.0);
	vec3 col = tint * (0.7 + 0.8 * grey) * (0.8 + 0.3 * facing);
	col += glow * pow(1.0 - facing, 1.6) * (0.7 + 0.5 * pulse);
	ALBEDO = col + glow * 0.2 * pulse;
}
"""

# Additive glow for the Lockruf halo (radial), ring (fading) and beam (vertical fade).
const LURE_GLOW_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec3 tint : source_color;
uniform float strength = 1.0;
uniform float fade = 1.0;
uniform float ring = 0.0;
uniform float beam = 0.0;
void fragment() {
	float pulse = 0.75 + 0.25 * sin(TIME * 5.0);
	float a = strength * pulse;
	if (beam > 0.5) {
		a *= pow(1.0 - UV.y, 1.5) * 0.9 + 0.1 * (1.0 - UV.y);
	} else if (ring > 0.5) {
		a *= fade;
	} else {
		float d = length(UV - vec2(0.5)) * 2.0;
		a *= pow(clamp(1.0 - d, 0.0, 1.0), 1.6);
	}
	ALBEDO = tint;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""
