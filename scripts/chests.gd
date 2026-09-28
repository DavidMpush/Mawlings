extends Node3D

# Etappe 17 Welle 2 – Kokons in der Welt (Spur 2: Waffen und Relikte).
#
#   map    Brutkokon an arena.poi_slots("cocoon"): kostet Bernstein (die
#          In-Run-Währung, evolution.chest_price(), steigt je Kokon), Beute sofort.
#   start  Start-Kokon 15-30 m um den Start: kostenlos, gewöhnlich/selten, bringt
#          eine zweite Waffe, solange der zweite Waffenplatz leer ist.
#   gold   goldener Kokon an poi_slots("cocoon_gold") (18c: bewacht): kostenlos,
#          Beute sofort, mindestens episch.
#   elite  kleiner Kokon beim Tod eines Elite-Jägers: kostenlos, mindestens selten.
#   boss   großer goldener Kokon (Bog King, Moosschlund, Aschenkröte): kostenlos,
#          1 aus 3 (evolution.chest_offers, mutation_screen Modus „chest“).
#
# Öffnen: den Schwarm HOLD_SECONDS im Kokon halten (Mitte im Haltekreis); dann
# zahlt ein Karten-Kokon seinen Preis in Bernstein (nie Tiere oder Biomasse). Zu
# teuer: der Kokon bleibt zu, die Preis-Pille wird rot. Öffnungsmoment: Pulsieren, Platzen, Lichtstrahl in Seltenheitsfarbe,
# Beute-Karte im HUD (hud_loot.gd) und ein Klang je Seltenheit.
# Kokons bleiben liegen, bis sie geöffnet sind (Ressourcenregel). Eine neue Karte
# (Migration) bringt neue Karten-Kokons; fallen gelassene (Elite/Boss) wandern mit
# an den Ankunftsort. Logik und Animation laufen nur in step() (Pause/Wahl frieren ein).

const FX = preload("res://scripts/fx.gd")
const TUNING = preload("res://scripts/tuning.gd")
const STATS = preload("res://scripts/progression/stats.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")

const HOLD_SECONDS := 1.0
const HOLD_RADIUS := {"map": 2.3, "gold": 2.6, "elite": 2.0, "boss": 3.2, "start": 2.3}
const SIZE := {"map": 1.0, "gold": 1.15, "elite": 0.72, "boss": 1.55, "start": 1.0}
## Start-Kokon (Welle 2): gratis, 15-30 m um den Start auf offenem Boden, immer sichtbar.
const START_RANGE := Vector2(15.0, 30.0)
const PULSE_SECONDS := 0.45
const BEAM_SECONDS := 1.6
const CARD_SECONDS := 2.0
## Preis-Pillen nur in der Nähe (m).
const TAG_RANGE := 20.0
## Rückfall ohne Karten-Plätze (Seed 0 / klassische Karte).
const FALLBACK_MAP := 6
const FALLBACK_GOLD := 1
# Etappe 23: own opening sounds, more festive with every rarity (legendary adds "fanfare").
const SOUND := {"common": "cocoon_common", "rare": "cocoon_rare", "epic": "cocoon_epic", "legendary": "cocoon_legendary"}
const SILK := Color("f4ead2")
const SILK_DARK := Color("cdb994")

## Every cocoon: {at, kind, hold, state (0 closed, 1 pulsing, 2 opened),
## anim, denied, node, body, ring, origin ("slot"/"drop")}
var cocoons: Array[Dictionary] = []
## Opened map cocoons (for statistics and the bot).
var opened := 0
var opened_by_kind := {"map": 0, "gold": 0, "elite": 0, "boss": 0, "start": 0}
var _start_placed := false
## Last loot card {item, t0} (HUD); t0 = world time of the opening.
var card: Dictionary = {}
var world: Node3D
var arena: Node3D
var _layout: RefCounted
var _layout_known := false
var _time := 0.0
var _beams: Array[Dictionary] = []
static var _meshes := {}
static var _materials := {}


func setup(world_node: Node3D, arena_node: Node3D) -> void:
	world = world_node
	arena = arena_node
	_rebuild()


# ---------------------------------------------------------------- placement

func _rebuild() -> void:
	_layout = arena.get("layout") if arena != null else null
	_layout_known = true
	var kept: Array[Dictionary] = []
	for entry in cocoons:
		if entry.origin == "drop" and int(entry.state) == 0:
			kept.append(entry)
		elif entry.node != null:
			entry.node.queue_free()
	cocoons.clear()
	var map_slots: Array[Vector3] = []
	var gold_slots: Array[Vector3] = []
	if arena != null and arena.has_method("poi_slots"):
		map_slots = arena.poi_slots("cocoon")
		gold_slots = arena.poi_slots("cocoon_gold")
	if map_slots.is_empty() and gold_slots.is_empty():
		var spots := _fallback_spots(FALLBACK_MAP + FALLBACK_GOLD)
		map_slots = spots.slice(0, FALLBACK_MAP)
		gold_slots = spots.slice(FALLBACK_MAP)
	for at in map_slots:
		_add("map", at, "slot")
	for at in gold_slots:
		_add("gold", at, "slot")
	if not _start_placed:
		_start_placed = true
		_add("start", _start_spot(), "drop")
	# Dropped cocoons travel with the swarm to the new map.
	for entry in kept:
		if entry.kind == "start":
			entry.at = _start_spot()
			entry.node.position = entry.at
			cocoons.append(entry)
			continue
		var here: Vector3 = world.swarm.position if world != null else Vector3.ZERO
		var offset := Vector3(2.5, 0.0, 0.0).rotated(Vector3.UP, float(cocoons.size()) * 2.1)
		entry.at = _open_spot(here + offset, 1.2)
		entry.node.position = entry.at
		cocoons.append(entry)


# A seeded open spot 15-30 m around the swarm's start.
func _start_spot() -> Vector3:
	var here: Vector3 = world.swarm.position if world != null and world.get("swarm") != null else Vector3.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["start_cocoon", int(arena.get("world_seed")) if arena != null and arena.get("world_seed") != null else 0])
	var best := here + Vector3(0, 0, -START_RANGE.x)
	for attempt in 12:
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(START_RANGE.x, START_RANGE.y)
		var point := here + Vector3(cos(angle), 0.0, sin(angle)) * distance
		var open := _open_spot(point, 1.4)
		var off := Vector2(open.x - here.x, open.z - here.z).length()
		best = open
		if off >= START_RANGE.x - 1.0 and off <= START_RANGE.y + 2.0 and (arena == null or not arena.has_method("wall_distance") or arena.wall_distance(open) >= 1.5):
			break
	return best


# Seeded open spots in rings around the map centre (classic map, tests).
func _fallback_spots(count: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var centre: Vector3 = arena.map_center() if arena != null and arena.has_method("map_center") else Vector3.ZERO
	var reach := 60.0
	if arena != null and arena.has_method("playable_rect"):
		reach = minf(reach, (arena.playable_rect() as Rect2).size.x * 0.4)
	var seed_value := int(arena.get("world_seed")) if arena != null and arena.get("world_seed") != null else 0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["cocoons", seed_value])
	for index in count:
		var angle := float(index) * 2.39996323 + rng.randf() * 0.6
		var distance := lerpf(22.0, reach, float(index + 1) / float(count + 1)) + rng.randf_range(-4.0, 4.0)
		out.append(_open_spot(centre + Vector3(cos(angle), 0.0, sin(angle)) * distance, 1.4))
	return out


func _open_spot(point: Vector3, radius: float) -> Vector3:
	if arena != null and arena.has_method("safe_spawn"):
		point = arena.safe_spawn(point, radius)
	point.y = 0.0
	return point


func _add(kind: String, at: Vector3, origin: String) -> Dictionary:
	at.y = 0.0
	var entry := {"at": at, "kind": kind, "hold": 0.0, "state": 0, "anim": 0.0, "denied": false, "origin": origin,
		"phase": float(cocoons.size()) * 1.7}
	_build_node(entry)
	cocoons.append(entry)
	return entry


## Drops a free cocoon (kind "elite" or "boss") beside `location`.
func drop(kind: String, location: Vector3) -> Dictionary:
	var offset := Vector3(1.8 if kind == "elite" else 2.6, 0.0, 0.0).rotated(Vector3.UP, float(cocoons.size()) * 2.4 + 0.7)
	var at := _open_spot(location + offset, 1.2)
	var entry := _add(kind, at, "drop")
	FX.ring(world if world != null else self, at, Color(_glow(kind), 0.8), 0.3, 3.2 * float(SIZE[kind]), 0.6)
	return entry


## Adds a cocoon at a fixed spot (tests, captures).
func spawn(kind: String, at: Vector3) -> Dictionary:
	return _add(kind, at, "drop" if kind in ["elite", "boss"] else "slot")


func closed_count(kind: String = "") -> int:
	var count := 0
	for entry in cocoons:
		if int(entry.state) == 0 and (kind == "" or entry.kind == kind):
			count += 1
	return count


## Nearest closed cocoon within `reach` (INF = none); `kinds` filters.
func nearest(point: Vector3, reach: float, kinds: Array = []) -> Dictionary:
	var best: Dictionary = {}
	var best_d := reach
	for entry in cocoons:
		if int(entry.state) != 0 or (not kinds.is_empty() and not kinds.has(entry.kind)):
			continue
		var d := Vector2(entry.at.x - point.x, entry.at.z - point.z).length()
		if d < best_d:
			best_d = d
			best = entry
	return best


# ---------------------------------------------------------------- price

## Bernstein the swarm holds (Etappe 17 Welle 2: cocoons cost Bernstein, never
## biomass or animals).
func available_amber() -> int:
	return int(world.model.amber) if world != null else 0


func price_of(entry: Dictionary) -> int:
	return world.evolution.chest_price() if entry.kind == "map" else 0


func affordable(entry: Dictionary) -> bool:
	return price_of(entry) <= 0 or available_amber() >= price_of(entry)


# Pays `amount` Bernstein.
func _pay(amount: int) -> bool:
	if amount <= 0:
		return true
	if available_amber() < amount:
		return false
	world.model.amber -= amount
	return true


# ---------------------------------------------------------------- step

## Holds, opens and animates the cocoons. `centre` = swarm centre.
func step(delta: float, centre: Vector3) -> void:
	_time += delta
	if arena != null and (arena.get("layout") != _layout or not _layout_known):
		_rebuild()
	for index in range(cocoons.size() - 1, -1, -1):
		var entry: Dictionary = cocoons[index]
		match int(entry.state):
			0:
				_step_closed(entry, delta, centre)
			1:
				entry.anim += delta
				if float(entry.anim) >= PULSE_SECONDS:
					_burst(entry)
				else:
					_animate_pulse(entry)
			2:
				entry.anim += delta
				if float(entry.anim) >= 0.5:
					if entry.node != null:
						entry.node.queue_free()
					cocoons.remove_at(index)
				else:
					_animate_shards(entry)
	_step_beams(delta)


func _step_closed(entry: Dictionary, delta: float, centre: Vector3) -> void:
	var flat := Vector2(entry.at.x - centre.x, entry.at.z - centre.z).length()
	var near := flat < 30.0
	var inside := flat <= float(HOLD_RADIUS[entry.kind])
	if inside and not bool(entry.denied):
		entry.hold = minf(HOLD_SECONDS, float(entry.hold) + delta)
		if float(entry.hold) >= HOLD_SECONDS:
			if affordable(entry):
				_begin_open(entry)
				return
			entry.denied = true
			if world != null and world.has_method("_sfx"):
				world._sfx("cocoon_denied", 30)
	elif not inside:
		entry.hold = maxf(0.0, float(entry.hold) - delta * 2.0)
		entry.denied = false
	if near:
		_animate_idle(entry)


func _begin_open(entry: Dictionary) -> void:
	var price := price_of(entry)
	if price > 0 and not _pay(price):
		entry.denied = true
		return
	entry.state = 1
	entry.anim = 0.0
	entry["paid"] = price
	if world != null and world.has_method("_sfx"):
		world._sfx("cocoon_open", 20)


## Opens a closed cocoon at once (tests/captures; pays like a hold would).
func open_now(entry: Dictionary) -> bool:
	if int(entry.state) != 0 or not affordable(entry):
		return false
	_begin_open(entry)
	if int(entry.state) != 1:
		return false
	_burst(entry)
	return true


# The cocoon bursts: loot, beam, card, sound.
func _burst(entry: Dictionary) -> void:
	entry.state = 2
	entry.anim = 0.0
	opened_by_kind[entry.kind] = int(opened_by_kind.get(entry.kind, 0)) + 1
	var evo: RefCounted = world.evolution
	var result: Dictionary = {}
	match String(entry.kind):
		"map":
			opened += 1
			result = evo.open_chest("map")
		"gold":
			# Free and guarded: one item right away, at least epic (no price step).
			result = evo.open_chest("elite", "epic")
		"elite":
			result = evo.open_chest("elite")
		"boss":
			result = evo.open_chest("boss")
		"start":
			result = evo.open_chest("start")
	entry["result"] = result
	var shown := {}
	if not bool(result.get("pick", false)):
		var granted: Array = result.get("granted", [])
		if not granted.is_empty():
			shown = granted[0]
	play_moment(entry, _best_rarity(result), shown)


## The opening moment: beam in the rarity colour, rings, shake, sound, shards
## and (with an item) the loot card. Public for captures.
func play_moment(entry: Dictionary, rarity: String, item: Dictionary = {}) -> void:
	entry["rarity"] = rarity
	entry.state = 2
	entry.anim = 0.0
	if not item.is_empty():
		show_card(item)
	_beam(entry.at, rarity, float(SIZE[entry.kind]))
	FX.ring(world, entry.at, Color(_rarity_color(rarity), 0.9), 0.4, 4.5 * float(SIZE[entry.kind]), 0.55)
	FX.ring(world, entry.at, Color(SILK, 0.7), 0.2, 2.4 * float(SIZE[entry.kind]), 0.4)
	if world.has_method("_shake"):
		world._shake(0.18 if entry.kind != "boss" else 0.35)
	if world.has_method("_sfx"):
		world._sfx(String(SOUND.get(rarity, "cocoon_common")), 40 if rarity in ["epic", "legendary"] else 20)
		if rarity == "legendary":
			world._sfx("fanfare", 80)
	if entry.body != null:
		entry.body.visible = false
	if entry.ring != null:
		entry.ring.visible = false
	_spawn_shards(entry, rarity)


static func _best_rarity(result: Dictionary) -> String:
	var best := "common"
	for item in result.get("items", []):
		var r := String(item.get("rarity", "common"))
		if STATS.RARITIES.find(r) > STATS.RARITIES.find(best):
			best = r
	return best


## Shows the loot card in the HUD (hud_loot.gd reads `card`).
func show_card(item: Dictionary) -> void:
	if item.is_empty():
		return
	card = {"item": item.duplicate(), "t0": _time}


## HUD state: price pills (screen space) and the loot card.
func hud_state(camera: Camera3D, centre: Vector3) -> Dictionary:
	var tags: Array = []
	if camera != null:
		for entry in cocoons:
			if int(entry.state) != 0:
				continue
			var flat := Vector2(entry.at.x - centre.x, entry.at.z - centre.z).length()
			if flat > TAG_RANGE:
				continue
			var top: Vector3 = entry.at + Vector3.UP * (2.5 * float(SIZE[entry.kind]) + 0.4)
			if camera.is_position_behind(top):
				continue
			tags.append({"screen": camera.unproject_position(top), "kind": entry.kind, "price": price_of(entry),
				"afford": affordable(entry), "hold": float(entry.hold) / HOLD_SECONDS, "denied": bool(entry.denied),
				"near": flat <= float(HOLD_RADIUS[entry.kind]) + 1.0})
	var shown := {}
	if not card.is_empty() and _time - float(card.t0) <= CARD_SECONDS:
		shown = {"item": card.item, "t": (_time - float(card.t0)) / CARD_SECONDS}
	return {"tags": tags, "card": shown}


## Minimap marks: [{at, kind}] for every closed cocoon.
func map_marks() -> Array:
	var out: Array = []
	for entry in cocoons:
		if int(entry.state) == 0:
			# Dropped and start cocoons are always shown (no discovery needed).
			out.append({"at": entry.at, "kind": entry.kind, "dropped": entry.origin == "drop"})
	return out


# ---------------------------------------------------------------- look

static func _rarity_color(rarity: String) -> Color:
	return UiStyle.brawl_tone(String(STATS.RARITY_TONE.get(rarity, "neutral")))["light"]


# Beam colour: the tone face (saturated) so the rarity reads on bright ground.
static func _beam_color(rarity: String) -> Color:
	return UiStyle.brawl_tone(String(STATS.RARITY_TONE.get(rarity, "neutral")))["face"]


static func _glow(kind: String) -> Color:
	match kind:
		"gold", "boss":
			return UiStyle.brawl_tone("loot")["light"]
		"elite":
			return UiStyle.brawl_tone("special")["light"]
		"start":
			return UiStyle.brawl_tone("action")["light"]
	# Stage 20 (S1): a map cocoon is loot (gold), never the swarm's ember colour.
	return UiStyle.brawl_tone("loot")["face"]


static func _shell(kind: String) -> Color:
	return UiStyle.brawl_tone("loot")["face"] if kind in ["gold", "boss"] else SILK


static func _mesh(key: String) -> Mesh:
	if _meshes.has(key):
		return _meshes[key]
	var mesh: Mesh
	match key:
		"egg":
			var egg := SphereMesh.new()
			egg.radius = 0.74
			egg.height = 2.0
			egg.radial_segments = 20
			egg.rings = 12
			mesh = egg
		"band":
			var band := TorusMesh.new()
			band.inner_radius = 0.62
			band.outer_radius = 0.8
			band.rings = 24
			band.ring_segments = 6
			mesh = band
		"seam":
			var seam := CapsuleMesh.new()
			seam.radius = 0.13
			seam.height = 1.35
			seam.radial_segments = 8
			seam.rings = 2
			mesh = seam
		"mound":
			var mound := SphereMesh.new()
			mound.radius = 0.95
			mound.height = 0.7
			mound.radial_segments = 16
			mound.rings = 6
			mound.is_hemisphere = true
			mesh = mound
		"ring":
			var ring := TorusMesh.new()
			ring.inner_radius = 0.9
			ring.outer_radius = 1.0
			ring.rings = 48
			ring.ring_segments = 4
			mesh = ring
		"spike":
			var spike := CylinderMesh.new()
			spike.top_radius = 0.0
			spike.bottom_radius = 0.13
			spike.height = 0.55
			spike.radial_segments = 6
			spike.rings = 1
			mesh = spike
		"beam":
			var beam := CylinderMesh.new()
			beam.top_radius = 0.25
			beam.bottom_radius = 0.75
			beam.height = 1.0
			beam.radial_segments = 20
			beam.rings = 1
			beam.cap_top = false
			beam.cap_bottom = false
			mesh = beam
		"halo":
			var halo := CylinderMesh.new()
			halo.top_radius = 1.0
			halo.bottom_radius = 1.0
			halo.height = 0.02
			halo.radial_segments = 32
			halo.rings = 1
			mesh = halo
		"shard":
			var shard := SphereMesh.new()
			shard.radius = 0.16
			shard.height = 0.26
			shard.radial_segments = 6
			shard.rings = 3
			mesh = shard
	_meshes[key] = mesh
	return mesh


static func _material(key: String, color: Color, glow: float = 0.0, unshaded := false, transparent := false) -> StandardMaterial3D:
	var id := "%s:%s:%.2f:%s:%s" % [key, color.to_html(true), glow, unshaded, transparent]
	if _materials.has(id):
		return _materials[id]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.55
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if not unshaded:
		material.rim_enabled = true
		material.rim = 0.55
		material.rim_tint = 0.3
	_materials[id] = material
	return material


static func _piece(parent: Node3D, mesh: Mesh, material: Material, at: Vector3, basis := Basis.IDENTITY) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.transform = Transform3D(basis, at)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part


# A silk cocoon on a small mound: egg body wrapped in three bands, a glowing
# seam facing the camera (+Z), a hold ring on the ground; gold/boss cocoons
# are golden, the boss one wears a crown of bone spikes.
func _build_node(entry: Dictionary) -> void:
	var kind: String = entry.kind
	var scale_value: float = SIZE[kind]
	var root := Node3D.new()
	root.name = "Cocoon %s" % kind
	root.position = entry.at
	add_child(root)
	var shell := _shell(kind)
	var glow := _glow(kind)
	var dark: Color = shell.darkened(0.25)
	# Hold ring (fills brighter while the swarm holds).
	var ring := _piece(root, _mesh("ring"), _material("ring", Color(glow, 0.55), 0.0, true, true), Vector3(0, 0.05, 0), Basis.from_scale(Vector3(HOLD_RADIUS[kind], 0.3, HOLD_RADIUS[kind])))
	var body := Node3D.new()
	body.name = "Body"
	body.scale = Vector3.ONE * scale_value
	root.add_child(body)
	_piece(root, _mesh("halo"), _material("halo", Color(glow, 0.22), 0.0, true, true), Vector3(0, 0.035, 0), Basis.from_scale(Vector3(1.7, 1.0, 1.7) * scale_value))
	_piece(body, _mesh("mound"), _material("mound", SILK_DARK.darkened(0.25) if kind in ["map", "elite", "start"] else dark.darkened(0.1)), Vector3.ZERO, Basis.from_scale(Vector3(1.2, 0.45, 1.2)))
	# Silk tufts around the foot.
	var tuft_material := _material("tuft", SILK if kind in ["map", "elite", "start"] else shell.lightened(0.15))
	for i in 6:
		var angle := TAU * float(i) / 6.0 + 0.3
		_piece(body, _mesh("shard"), tuft_material, Vector3(cos(angle) * 0.95, 0.12, sin(angle) * 0.95), Basis.from_scale(Vector3(1.8, 0.9, 1.8)))
	_piece(body, _mesh("egg"), _material("shell", shell, 0.12), Vector3(0, 1.1, 0), Basis.from_scale(Vector3(0.95, 1.08, 0.9)))
	var band_material := _material("band", SILK_DARK if kind in ["map", "elite", "start"] else dark)
	_piece(body, _mesh("band"), band_material, Vector3(0, 0.62, 0), Basis(Vector3.RIGHT, 0.22) * Basis.from_scale(Vector3(0.98, 1.0, 0.92)))
	_piece(body, _mesh("band"), band_material, Vector3(0, 1.05, 0), Basis(Vector3.FORWARD, -0.32) * Basis.from_scale(Vector3(1.06, 1.0, 1.0)))
	_piece(body, _mesh("band"), band_material, Vector3(0, 1.5, 0), Basis(Vector3.RIGHT, -0.25) * Basis.from_scale(Vector3(0.84, 1.0, 0.8)))
	# The glowing slit faces the camera (+Z); a second, softer slit on the back.
	_piece(body, _mesh("seam"), _material("seam", glow, 2.6, true), Vector3(0, 1.08, 0.64), Basis(Vector3.RIGHT, -0.2) * Basis.from_scale(Vector3(0.8, 0.8, 0.8)))
	_piece(body, _mesh("seam"), _material("seam_soft", Color(glow, 0.45), 0.0, true, true), Vector3(0, 1.08, 0.7), Basis(Vector3.RIGHT, -0.2) * Basis.from_scale(Vector3(1.9, 0.9, 1.0)))
	if kind == "boss":
		var bone := _material("bone", Color("f3e7c8"))
		for i in 5:
			var angle := TAU * float(i) / 5.0
			var tilt := Basis(Vector3.UP, angle) * Basis(Vector3.RIGHT, 0.45)
			_piece(body, _mesh("spike"), bone, Vector3(sin(angle) * 0.42, 1.95, cos(angle) * 0.42), tilt)
	entry.node = root
	entry.body = body
	entry.ring = ring


func _animate_idle(entry: Dictionary) -> void:
	var body: Node3D = entry.body
	if body == null:
		return
	var base: float = SIZE[entry.kind]
	var hold := float(entry.hold) / HOLD_SECONDS
	# Breathing; while held it swells and trembles.
	var breathe := 1.0 + 0.035 * sin(_time * 2.2 + float(entry.phase))
	var swell := 1.0 + 0.12 * hold
	body.scale = Vector3(breathe * swell, (2.0 - breathe) * swell, breathe * swell) * base
	body.rotation.z = sin(_time * 40.0) * 0.05 * hold
	var ring: MeshInstance3D = entry.ring
	if ring != null:
		var radius: float = HOLD_RADIUS[entry.kind]
		var grow := 1.0 + 0.06 * sin(_time * 3.0 + float(entry.phase)) - 0.12 * hold
		ring.scale = Vector3(radius * grow, 0.3, radius * grow)
		# Alpha in 5 steps: the shared material cache stays small.
		var level := roundf(hold * 4.0) / 4.0
		ring.material_override = _material("ring", Color(Color.WHITE if hold > 0.0 else _glow(entry.kind), 0.55 + 0.4 * level), 0.0, true, true) if not bool(entry.denied) else _material("ring", Color(UiStyle.brawl_tone("neutral")["light"], 0.85), 0.0, true, true)


func _animate_pulse(entry: Dictionary) -> void:
	var body: Node3D = entry.body
	if body == null:
		return
	var t := float(entry.anim) / PULSE_SECONDS
	var beat := 1.0 + 0.22 * t + 0.1 * sin(t * TAU * 3.0)
	body.scale = Vector3.ONE * float(SIZE[entry.kind]) * beat
	body.rotation.z = sin(float(entry.anim) * 60.0) * 0.08 * t


func _spawn_shards(entry: Dictionary, rarity: String) -> void:
	var shards: Array = []
	var material := _material("shard", _shell(entry.kind), 0.1)
	var tint := _material("shardglow", _rarity_color(rarity), 1.8, true)
	for i in 8:
		var angle := TAU * float(i) / 8.0 + 0.3
		var part := _piece(entry.node, _mesh("shard"), material if i % 2 == 0 else tint, Vector3(0, 1.0 * float(SIZE[entry.kind]), 0))
		shards.append([part, Vector3(cos(angle) * 4.5, 5.0 + float(i % 3), sin(angle) * 4.5)])
	entry["shards"] = shards


func _animate_shards(entry: Dictionary) -> void:
	var t := float(entry.anim)
	for pair in entry.get("shards", []):
		var part: MeshInstance3D = pair[0]
		var velocity: Vector3 = pair[1]
		part.position = Vector3(velocity.x * t, 1.0 * float(SIZE[entry.kind]) + velocity.y * t - 12.0 * t * t, velocity.z * t)
		part.scale = Vector3.ONE * maxf(0.05, 1.0 - t * 1.6)


# A light beam in the rarity colour rises from the cocoon and fades.
func _beam(at: Vector3, rarity: String, size_value: float) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(_beam_color(rarity), 0.9)
	var holder := Node3D.new()
	holder.name = "Beam"
	holder.position = Vector3(at.x, 0.0, at.z)
	add_child(holder)
	var height := 9.0 + 5.0 * float(STATS.RARITIES.find(rarity))
	var beam := _piece(holder, _mesh("beam"), material, Vector3.ZERO)
	var core_material := material.duplicate() as StandardMaterial3D
	core_material.albedo_color = Color(Color.WHITE, 0.35)
	var core := _piece(holder, _mesh("beam"), core_material, Vector3.ZERO)
	_beams.append({"node": holder, "beam": beam, "core": core, "material": material, "core_material": core_material,
		"age": 0.0, "height": height, "width": size_value * (1.0 + 0.25 * float(STATS.RARITIES.find(rarity)))})
	_step_beams(0.0)


func _step_beams(delta: float) -> void:
	for index in range(_beams.size() - 1, -1, -1):
		var entry: Dictionary = _beams[index]
		entry.age += delta
		var t := float(entry.age) / BEAM_SECONDS
		if t >= 1.0:
			entry.node.queue_free()
			_beams.remove_at(index)
			continue
		var rise := clampf(t / 0.18, 0.0, 1.0)
		var height: float = float(entry.height) * (1.0 - pow(1.0 - rise, 3.0))
		var width: float = float(entry.width) * (1.0 + 0.4 * (1.0 - rise)) * (1.0 - 0.5 * t)
		var fade := 1.0 - smoothstep(0.35, 1.0, t)
		(entry.beam as MeshInstance3D).transform = Transform3D(Basis.from_scale(Vector3(width, height, width)), Vector3(0, height * 0.5, 0))
		(entry.core as MeshInstance3D).transform = Transform3D(Basis.from_scale(Vector3(width * 0.25, height * 0.98, width * 0.25)), Vector3(0, height * 0.49, 0))
		var tint: Color = (entry.material as StandardMaterial3D).albedo_color
		tint.a = 0.62 * fade
		(entry.material as StandardMaterial3D).albedo_color = tint
		(entry.core_material as StandardMaterial3D).albedo_color = Color(1, 1, 1, 0.3 * fade)


func active_beams() -> int:
	return _beams.size()
