extends Node3D

# Etappe 17 Welle 2 – Power-ups (kurze Booster, wie in Megabonk).
#
# Sechs Booster, die man durch Hinlaufen einsammelt (kein Magnet, kein Lockruf):
# rausch, blutrausch, magnetsturm, chitinschild, raserei, brutwelle (sofort).
# Wirkung über evolution.boosts (damage, speed, magnet, cooldown, loss,
# leader_immune); gleiche Booster verlängern die Dauer bis höchstens zum
# Doppelten, verschiedene laufen parallel.
# Quellen (Nutzerentscheidung 28.09.2026): NUR Mini-Bosse - Elite-Jäger,
# Bog King und die Apex-Bosse lassen garantiert einen zufälligen Booster
# fallen. Keine Drops von normalen Kills, Flutstufen oder Knollen mehr. Die
# Hain-Plätze (arena.poi_slots("grove")) tragen stattdessen einen Bernstein-Schatz:
# 2-3 goldene Knollen dicht beieinander, ein Biss bricht sie in Bernstein-Münzen.
# Liegende Booster bleiben (Ressourcenregel); nach BLINK_AFTER s blinken sie.
# Welt: schwebende, rotierende Plakette mit Symbol und Lichtsäule in der Farbe
# des Boosters. Am Schwarm: Rausch Tempo-Linien, Schild Kuppel, Raserei roter
# Rand, Magnetsturm der vergrößerte Sammelkreis, Blutrausch ein Glutring.

const FX = preload("res://scripts/fx.gd")
const TUNING = preload("res://scripts/tuning.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiIcons = preload("res://scripts/ui/ui_icons.gd")

## id -> [Name, Dauer s (0 = sofort), Kit-Ton, Symbol-ID, Band-Text]
const DEFS := {
	"rausch": ["Rausch", 8.0, "action", "pu_rausch", "RAUSCH! +45 % TEMPO"],
	"blutrausch": ["Blutrausch", 8.0, "ember", "pu_blutrausch", "BLUTRAUSCH! WAFFEN −40 %"],
	"magnetsturm": ["Magnetsturm", 10.0, "loot", "pu_magnetsturm", "MAGNETSTURM! SOG ×3"],
	"chitinschild": ["Chitinschild", 6.0, "info", "pu_chitinschild", "CHITINSCHILD! UNVERWUNDBAR"],
	"raserei": ["Raserei", 7.0, "ember", "pu_raserei", "RASEREI! DOPPELTER SCHADEN"],
	"brutwelle": ["Brutwelle", 0.0, "special", "pu_brutwelle", "BRUTWELLE! +3 TIERE"],
}
const ORDER := ["rausch", "blutrausch", "magnetsturm", "chitinschild", "raserei", "brutwelle"]
const SPEED := 1.45
const COOLDOWN := 0.6
const MAGNET := 3.0
const SHIELD_LOSS := 0.3
const DAMAGE := 2.0
const BROOD_DIVISIONS := 3
## Mini-Bosse, die einen Booster fallen lassen (Art im HuntWorld-Tod-Pfad).
const MINI_BOSSES := ["boss", "apex"]
const BLINK_AFTER := 45.0
const PICKUP_REACH := 1.1
const HOVER := 1.35
const KNOLL_REACH := 1.0
const KNOLLS := Vector2i(2, 3)
const FALLBACK_GROVES := 3
const BAND_SECONDS := 1.6

## Lying boosters: {id, at, age, node, pivot, column}
var pickups: Array[Dictionary] = []
## Active boosters: id -> {left, full}
var active: Dictionary = {}
## Mushroom knolls: {at, alive, node}
var knolls: Array[Dictionary] = []
var collected := 0
## Arten, die in diesem Run eingesammelt wurden (KODEX, RunStats „powerups_taken“).
var taken: Array[String] = []
var dropped := 0
var band: Dictionary = {}
var world: Node3D
var arena: Node3D
var rng := RandomNumberGenerator.new()
var _time := 0.0
var _layout: RefCounted
var _layout_known := false
var _cooldown_boost := 1.0
var _aura: Node3D
var _aura_parts: Dictionary = {}
var _lines: Array[MeshInstance3D] = []
static var _meshes := {}
static var _materials := {}


func setup(world_node: Node3D, arena_node: Node3D) -> void:
	world = world_node
	arena = arena_node
	var seed_value := int(arena.get("world_seed")) if arena != null and arena.get("world_seed") != null else 0
	rng.seed = hash(["powerups", seed_value])
	_build_aura()
	_rebuild()


# ---------------------------------------------------------------- groves

func _rebuild() -> void:
	_layout = arena.get("layout") if arena != null else null
	_layout_known = true
	for knoll in knolls:
		if knoll.node != null:
			knoll.node.queue_free()
	knolls.clear()
	var groves: Array[Vector3] = []
	if arena != null and arena.has_method("poi_slots"):
		groves = arena.poi_slots("grove")
	if groves.is_empty():
		groves = _fallback_groves()
	var grove_rng := RandomNumberGenerator.new()
	grove_rng.seed = hash(["groves", int(arena.get("world_seed")) if arena != null and arena.get("world_seed") != null else 0])
	for centre in groves:
		var count := grove_rng.randi_range(KNOLLS.x, KNOLLS.y)
		var start := grove_rng.randf() * TAU
		for i in count:
			var angle := start + TAU * float(i) / float(count) + grove_rng.randf_range(-0.3, 0.3)
			var at := centre + Vector3(cos(angle), 0.0, sin(angle)) * grove_rng.randf_range(1.4, 2.6)
			if arena != null and arena.has_method("safe_spawn"):
				at = arena.safe_spawn(at, 0.6)
			at.y = 0.0
			_add_knoll(at, grove_rng.randf_range(0.85, 1.15))
	# Lying boosters of the old map come along to the arrival.
	for entry in pickups:
		var here: Vector3 = world.swarm.position if world != null else Vector3.ZERO
		entry.at = _open_spot(here + Vector3(3.0, 0.0, 0.0).rotated(Vector3.UP, float(pickups.find(entry)) * 2.0))
		entry.node.position = entry.at


func _fallback_groves() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var centre: Vector3 = arena.map_center() if arena != null and arena.has_method("map_center") else Vector3.ZERO
	for index in FALLBACK_GROVES:
		var angle := float(index) * TAU / float(FALLBACK_GROVES) + 1.1
		out.append(_open_spot(centre + Vector3(cos(angle), 0.0, sin(angle)) * (30.0 + 12.0 * float(index))))
	return out


func _open_spot(point: Vector3) -> Vector3:
	if arena != null and arena.has_method("safe_spawn"):
		point = arena.safe_spawn(point, 0.8)
	point.y = 0.0
	return point


func _add_knoll(at: Vector3, size_value: float) -> Dictionary:
	var root := Node3D.new()
	root.name = "Bernsteinschatz"
	root.position = at
	root.scale = Vector3.ONE * size_value
	add_child(root)
	var cap_tone: Dictionary = UiStyle.brawl_tone("loot")
	_piece(root, _mesh("stem"), _material("stem", Color("efe3c6")), Vector3(0, 0.28, 0))
	_piece(root, _mesh("cap"), _material("cap", cap_tone["face"], 0.25), Vector3(0, 0.5, 0), Basis.from_scale(Vector3(1.0, 0.8, 1.0)))
	var dot := _material("dot", cap_tone["light"], 1.2, true)
	for i in 4:
		var angle := TAU * float(i) / 4.0 + 0.4
		_piece(root, _mesh("dot"), dot, Vector3(cos(angle) * 0.32, 0.66, sin(angle) * 0.32))
	_piece(root, _mesh("dot"), dot, Vector3(0, 0.83, 0))
	var knoll := {"at": at, "alive": true, "node": root}
	knolls.append(knoll)
	return knoll


## Knolls still standing.
func knoll_count() -> int:
	var count := 0
	for knoll in knolls:
		if knoll.alive:
			count += 1
	return count


# ---------------------------------------------------------------- drops

## A random booster id (Brutwelle a little rarer).
func roll_id() -> String:
	var weights := [1.0, 1.0, 1.0, 1.0, 1.0, 0.7]
	var total := 0.0
	for w in weights:
		total += w
	var pick := rng.randf() * total
	for index in ORDER.size():
		pick -= weights[index]
		if pick <= 0.0:
			return ORDER[index]
	return ORDER[0]


## Drops booster `id` ("" = random) at `at`. Returns the pickup.
func drop(at: Vector3, id: String = "") -> Dictionary:
	if id == "" or not DEFS.has(id):
		id = roll_id()
	at = _open_spot(at)
	var entry := {"id": id, "at": at, "age": 0.0}
	_build_pickup(entry)
	pickups.append(entry)
	dropped += 1
	FX.ring(world if world != null else self, at, Color(_tone(id)["light"], 0.85), 0.3, 2.4, 0.5)
	return entry


## Kill hook: every mini boss (elite hunter, Mire Leaper, Bog King, apex) drops
## one random booster; ordinary kills drop none.
func on_kill(kind: String, at: Vector3, elite: bool, _now: float = 0.0) -> bool:
	if not elite and not MINI_BOSSES.has(kind):
		return false
	drop(at + Vector3(-1.4, 0.0, 0.6))
	return true


# ---------------------------------------------------------------- step

func step(delta: float, centre: Vector3, unit_points: PackedVector3Array) -> void:
	_time += delta
	if arena != null and (arena.get("layout") != _layout or not _layout_known):
		_rebuild()
	# Knolls: one touch breaks them into a booster.
	for knoll in knolls:
		if not knoll.alive:
			continue
		var at: Vector3 = knoll.at
		if absf(at.x - centre.x) > 14.0 or absf(at.z - centre.z) > 14.0:
			continue
		if _touched(at, KNOLL_REACH, centre, unit_points):
			knoll.alive = false
			knoll.node.queue_free()
			knoll.node = null
			FX.ring(world, at, Color(UiStyle.brawl_tone("loot")["light"], 0.8), 0.2, 1.8, 0.35)
			if world != null and world.has_method("_sfx"):
				world._sfx("kill", 10)
			# Bernstein-Schatz: the knoll bursts into coins (the magnet brings them).
			if world != null and world.has_method("drop_loot"):
				world.drop_loot(at, 0.0, 0, "mini", int(TUNING.AMBER_GROVE))
	# Lying boosters: walk-in pickup only.
	for index in range(pickups.size() - 1, -1, -1):
		var entry: Dictionary = pickups[index]
		entry.age += delta
		var at: Vector3 = entry.at
		var near := absf(at.x - centre.x) < 30.0 and absf(at.z - centre.z) < 30.0
		if near:
			_animate_pickup(entry)
		if near and _touched(at, PICKUP_REACH, centre, unit_points):
			pickups.remove_at(index)
			entry.node.queue_free()
			collect(String(entry.id))
	# Timers.
	for id in active.keys():
		var state: Dictionary = active[id]
		state.left = float(state.left) - delta
		if float(state.left) <= 0.0:
			active.erase(id)
	_apply()
	_animate_aura(delta, centre)


func _touched(at: Vector3, reach: float, centre: Vector3, unit_points: PackedVector3Array) -> bool:
	if unit_points.is_empty():
		return Vector2(at.x - centre.x, at.z - centre.z).length() <= reach + 0.6
	for point in unit_points:
		if absf(point.x - at.x) < reach and absf(point.z - at.z) < reach:
			return true
	return false


## Activates booster `id` (stacking: the same one extends up to double its duration).
func collect(id: String) -> void:
	if not DEFS.has(id):
		return
	collected += 1
	if not taken.has(id):
		taken.append(id)
	var def: Array = DEFS[id]
	var duration: float = def[1]
	var tone: Dictionary = _tone(id)
	band = {"id": id, "text": String(def[4]), "tone": String(def[2]), "t0": _time}
	if world != null:
		var at: Vector3 = world.swarm.position
		FX.ring(world, at, Color(tone["light"], 0.9), 0.4, 4.5, 0.5)
		FX.ring(world, at, Color(Color.WHITE, 0.6), 0.2, 2.5, 0.35)
		if world.has_method("_sfx"):
			world._sfx("lure" if id == "brutwelle" else "alpha_core", 50)
	if duration <= 0.0:
		_brood_wave()
		return
	if active.has(id):
		var state: Dictionary = active[id]
		state.left = minf(float(state.left) + duration, duration * 2.0)
		state.full = maxf(float(state.full), float(state.left))
	else:
		active[id] = {"left": duration, "full": duration}
	_apply()


# Brutwelle: biomass for BROOD_DIVISIONS cell divisions bursts at the swarm.
func _brood_wave() -> void:
	if world == null or not world.has_method("drop_loot"):
		return
	world.drop_loot(world.swarm.position, float(BROOD_DIVISIONS) * TUNING.BIOMASS_PER_MAWLING + 0.2, 0, "mini")


func left(id: String) -> float:
	return float(active[id].left) if active.has(id) else 0.0


func is_active(id: String) -> bool:
	return active.has(id)


# Writes the product of the active boosters into evolution.boosts; a changed
# cooldown bumps evolution.revision (HuntWorld resyncs the weapons).
func _apply() -> void:
	if world == null or world.evolution == null:
		return
	var boosts: Dictionary = world.evolution.boosts
	boosts["speed"] = SPEED if active.has("rausch") else 1.0
	boosts["cooldown"] = COOLDOWN if active.has("blutrausch") else 1.0
	boosts["magnet"] = MAGNET if active.has("magnetsturm") else 1.0
	boosts["loss"] = SHIELD_LOSS if active.has("chitinschild") else 1.0
	boosts["leader_immune"] = active.has("chitinschild")
	boosts["damage"] = DAMAGE if active.has("raserei") else 1.0
	if not is_equal_approx(float(boosts.cooldown), _cooldown_boost):
		_cooldown_boost = float(boosts.cooldown)
		world.evolution.revision += 1


## Clears every active booster (tests).
func clear_active() -> void:
	active.clear()
	_apply()


# ---------------------------------------------------------------- HUD & map

## HUD: active boosters [{id, icon, tone, left, fraction, blink}] and the band.
func hud_state() -> Dictionary:
	var list: Array = []
	for id in ORDER:
		if active.has(id):
			var state: Dictionary = active[id]
			list.append({"id": id, "icon": String(DEFS[id][3]), "tone": String(DEFS[id][2]),
				"left": float(state.left), "fraction": clampf(float(state.left) / maxf(0.01, float(state.full)), 0.0, 1.0)})
	var shown := {}
	if not band.is_empty() and _time - float(band.t0) <= BAND_SECONDS:
		shown = {"text": band.text, "tone": band.tone, "id": band.id, "t": (_time - float(band.t0)) / BAND_SECONDS}
	return {"active": list, "band": shown}


## Minimap marks: lying boosters [{at, id}] and standing knolls [{at}].
func map_marks() -> Array:
	var out: Array = []
	for entry in pickups:
		out.append({"at": entry.at, "id": entry.id})
	return out


func knoll_marks() -> Array:
	var out: Array = []
	for knoll in knolls:
		if knoll.alive:
			out.append({"at": knoll.at})
	return out


# ---------------------------------------------------------------- look

static func _tone(id: String) -> Dictionary:
	return UiStyle.brawl_tone(String(DEFS[id][2]) if DEFS.has(id) else "neutral")


static func _mesh(key: String) -> Mesh:
	if _meshes.has(key):
		return _meshes[key]
	var mesh: Mesh
	match key:
		"plate":
			var plate := CylinderMesh.new()
			plate.top_radius = 0.62
			plate.bottom_radius = 0.62
			plate.height = 0.16
			plate.radial_segments = 24
			plate.rings = 1
			mesh = plate
		"rim":
			var rim := TorusMesh.new()
			rim.inner_radius = 0.58
			rim.outer_radius = 0.74
			rim.rings = 28
			rim.ring_segments = 8
			mesh = rim
		"column":
			var column := CylinderMesh.new()
			column.top_radius = 0.12
			column.bottom_radius = 0.42
			column.height = 1.0
			column.radial_segments = 16
			column.rings = 1
			column.cap_top = false
			column.cap_bottom = false
			mesh = column
		"ring":
			var ring := TorusMesh.new()
			ring.inner_radius = 0.92
			ring.outer_radius = 1.0
			ring.rings = 64
			ring.ring_segments = 4
			mesh = ring
		"dome":
			var dome := SphereMesh.new()
			dome.radius = 1.0
			dome.height = 1.0
			dome.is_hemisphere = true
			dome.radial_segments = 32
			dome.rings = 10
			mesh = dome
		"line":
			var line := BoxMesh.new()
			line.size = Vector3(0.13, 0.04, 1.0)
			mesh = line
		"stem":
			var stem := CylinderMesh.new()
			stem.top_radius = 0.16
			stem.bottom_radius = 0.22
			stem.height = 0.56
			stem.radial_segments = 10
			stem.rings = 1
			mesh = stem
		"cap":
			var cap := SphereMesh.new()
			cap.radius = 0.5
			cap.height = 0.5
			cap.is_hemisphere = true
			cap.radial_segments = 16
			cap.rings = 6
			mesh = cap
		"dot":
			var dot := SphereMesh.new()
			dot.radius = 0.07
			dot.height = 0.1
			dot.radial_segments = 6
			dot.rings = 3
			mesh = dot
	_meshes[key] = mesh
	return mesh


static func _material(key: String, color: Color, glow: float = 0.0, unshaded := false, transparent := false, additive := false) -> StandardMaterial3D:
	var id := "%s:%s:%.2f:%s:%s:%s" % [key, color.to_html(true), glow, unshaded, transparent, additive]
	if _materials.has(id):
		return _materials[id]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.5
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if transparent or additive:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if not unshaded:
		material.rim_enabled = true
		material.rim = 0.5
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


# Floating plaque: coloured disc with a dark rim and the booster symbol on both
# faces, a light column and a ground ring in the booster colour.
func _build_pickup(entry: Dictionary) -> void:
	var id: String = entry.id
	var tone := _tone(id)
	var root := Node3D.new()
	root.name = "Power-up %s" % id
	root.position = entry.at
	add_child(root)
	_piece(root, _mesh("ring"), _material("ground", Color(tone["light"], 0.75), 0.0, true, true), Vector3(0, 0.05, 0), Basis.from_scale(Vector3(0.95, 0.3, 0.95)))
	var column := _piece(root, _mesh("column"), _material("column", Color(tone["light"], 0.32), 0.0, true, false, true), Vector3(0, 2.4, 0), Basis.from_scale(Vector3(1.0, 4.8, 1.0)))
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	pivot.position = Vector3(0, HOVER, 0)
	root.add_child(pivot)
	var upright := Basis(Vector3.RIGHT, PI * 0.5)
	_piece(pivot, _mesh("plate"), _material("plate", tone["face"], 0.35), Vector3.ZERO, upright)
	_piece(pivot, _mesh("rim"), _material("rim", UiStyle.BRAWL_INK), Vector3.ZERO, upright)
	var texture := UiIcons.texture(String(DEFS[id][3]))
	if texture != null:
		for side in [1.0, -1.0]:
			var sprite := Sprite3D.new()
			sprite.texture = texture
			sprite.pixel_size = 0.95 / maxf(1.0, float(texture.get_width()))
			sprite.position = Vector3(0, 0, 0.09 * side)
			sprite.rotation.y = 0.0 if side > 0.0 else PI
			sprite.double_sided = false
			sprite.shaded = false
			sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
			sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pivot.add_child(sprite)
	entry["node"] = root
	entry["pivot"] = pivot
	entry["column"] = column


func _animate_pickup(entry: Dictionary) -> void:
	var pivot: Node3D = entry.pivot
	var phase := float(entry.at.x) * 0.7
	# Swings instead of spinning all the way, so the face always reads; tilted
	# back towards the camera.
	pivot.rotation = Vector3(-0.45, sin(_time * 2.4 + phase) * 0.75, 0.0)
	pivot.position.y = HOVER + 0.16 * sin(_time * 2.6 + phase)
	# After BLINK_AFTER s it blinks as a hint (it never disappears).
	var shown := true
	if float(entry.age) >= BLINK_AFTER:
		shown = fmod(_time * 3.0, 1.0) < 0.62
	pivot.visible = shown
	(entry.column as MeshInstance3D).visible = shown


# Swarm aura of the active boosters (one node that follows the swarm).
func _build_aura() -> void:
	_aura = Node3D.new()
	_aura.name = "Power-up aura"
	_aura.top_level = true
	add_child(_aura)
	var info := UiStyle.brawl_tone("info")
	var loot := UiStyle.brawl_tone("loot")
	var ember := UiStyle.brawl_tone("ember")
	_aura_parts = {
		"dome": _piece(_aura, _mesh("dome"), _material("dome", Color(info["face"], 0.16), 0.0, true, true), Vector3.ZERO),
		"dome_rim": _piece(_aura, _mesh("ring"), _material("dome_rim", Color(info["light"], 0.85), 0.0, true, true), Vector3(0, 0.08, 0)),
		# Stage 20 (S1): the frenzy is the swarm's own power - ember, not danger.
		"frenzy": _piece(_aura, _mesh("ring"), _material("frenzy", Color(ember["face"], 0.85), 0.0, true, true), Vector3(0, 0.1, 0)),
		"frenzy_glow": _piece(_aura, _mesh("ring"), _material("frenzy_glow", Color(ember["light"], 0.35), 0.0, true, false, true), Vector3(0, 0.09, 0)),
		"magnet": _piece(_aura, _mesh("ring"), _material("magnet", Color(loot["light"], 0.7), 0.0, true, true), Vector3(0, 0.07, 0)),
		"haste": _piece(_aura, _mesh("ring"), _material("haste", Color(ember["light"], 0.7), 0.0, true, true), Vector3(0, 0.12, 0)),
	}
	var action := UiStyle.brawl_tone("action")
	for i in 7:
		_lines.append(_piece(_aura, _mesh("line"), _material("speedline", Color(action["light"].lerp(Color.WHITE, 0.3), 0.85), 0.0, true, true), Vector3.ZERO))
	for part in _aura_parts.values():
		part.visible = false
	for line in _lines:
		line.visible = false


func _swarm_radius() -> float:
	var population := int(world.model.population) if world != null else 1
	return 1.2 + 0.32 * sqrt(float(maxi(1, population)))


func _animate_aura(_delta: float, centre: Vector3) -> void:
	if _aura == null:
		return
	_aura.global_position = Vector3(centre.x, 0.0, centre.z)
	var radius := _swarm_radius()
	var shield := active.has("chitinschild")
	var ending := func(id: String) -> float:
		# Blink during the last 1.5 s.
		if left(id) > 1.5:
			return 1.0
		return 0.35 + 0.65 * (0.5 + 0.5 * cos(_time * 18.0))
	_aura_parts.dome.visible = shield
	_aura_parts.dome_rim.visible = shield
	if shield:
		var r := radius + 0.9
		var wobble := 1.0 + 0.03 * sin(_time * 5.0)
		_aura_parts.dome.scale = Vector3(r, r * 0.75, r) * wobble
		_aura_parts.dome_rim.scale = Vector3(r, 0.4, r) * wobble
		_aura_parts.dome.transparency = 1.0 - ending.call("chitinschild")
	var frenzy := active.has("raserei")
	_aura_parts.frenzy.visible = frenzy
	_aura_parts.frenzy_glow.visible = frenzy
	if frenzy:
		var pulse := 1.0 + 0.06 * sin(_time * 12.0)
		var r2 := (radius + 0.5) * pulse
		_aura_parts.frenzy.scale = Vector3(r2, 0.5, r2)
		_aura_parts.frenzy_glow.scale = Vector3(r2 + 0.35, 0.3, r2 + 0.35)
		_aura_parts.frenzy.transparency = 1.0 - ending.call("raserei")
	var magnet := active.has("magnetsturm")
	_aura_parts.magnet.visible = magnet
	if magnet and world != null and world.has_method("magnet_radius"):
		var m: float = world.magnet_radius()
		_aura_parts.magnet.scale = Vector3(m, 0.35, m)
		_aura_parts.magnet.rotation.y = _time * 0.6
		_aura_parts.magnet.transparency = 1.0 - ending.call("magnetsturm")
	var haste := active.has("blutrausch")
	_aura_parts.haste.visible = haste
	if haste:
		var h := radius * (0.75 + 0.2 * fmod(_time * 2.5, 1.0))
		_aura_parts.haste.scale = Vector3(h, 0.4, h)
		_aura_parts.haste.transparency = fmod(_time * 2.5, 1.0) * 0.9
	# Speed lines trail behind the swarm while it moves.
	var rush := active.has("rausch")
	var heading := Vector2.ZERO
	if world != null and world.swarm != null and "movement_vector" in world.swarm:
		heading = world.swarm.movement_vector
	var moving := heading.length() > 0.2
	for i in _lines.size():
		var line := _lines[i]
		line.visible = rush
		if not rush:
			continue
		var direction := Vector3(heading.x, 0.0, heading.y).normalized() if moving else Vector3(0, 0, 1)
		var side := Vector3(-direction.z, 0.0, direction.x)
		var cycle := fmod(_time * 2.2 + float(i) * 0.37, 1.0)
		var offset := (float(i) - 3.0) / 3.0 * (radius + 0.4)
		var back := radius * 0.4 + cycle * (radius + 2.0)
		var length := 1.6 * (1.0 - cycle) + 0.4
		line.position = direction * -back + side * offset + Vector3(0, 0.35 + 0.1 * float(i % 3), 0)
		line.basis = Basis.looking_at(direction, Vector3.UP) * Basis.from_scale(Vector3(1.0, 1.0, length))
		line.transparency = cycle * 0.9 if moving else 0.6 + cycle * 0.4
