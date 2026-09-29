extends Node3D

# Etappe 31 D - Glutpilze and instant map items.
#
# 8-12 Glutpilze (glowing ember mushroom baskets) lie per map on open, reachable
# ground (random points of the layout, away from walls, amber nodes and places).
# They are decoration without collision. A bite (one touching Mawling) breaks
# one; with TUNING.MAP_ITEM_CHANCE an instant item pops out of the basket:
#   heilpilz        (green)     leader +30 % max LP
#   zeitstarre      (ice blue)  HuntWorld.freeze_left = 5 s: enemies, bosses and
#                               the brood stop moving and attacking, telegraphs hold
#   bildschirmbiss  (ember)     every enemy within ~18 m dies, Bog King / apex
#                               lose 10 % max HP, brood in the radius dies
#   lockruf         the existing Lockruf (HuntWorld.drop_lure)
# Otherwise a few Bernstein coins. Items are walk-in pickups (no magnet, no
# Lockruf), stay until collected (resource rule) and blink after BLINK_AFTER s.
# Mushrooms are drawn as one MultiMesh per part (a handful of draw calls for the
# whole map); lying items are a few nodes each. A new map (migration) rebuilds
# the mushrooms, lying items come along to the arrival; a restart rebuilds all.

const FX = preload("res://scripts/fx.gd")
const TUNING = preload("res://scripts/tuning.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")

## id -> [Name, tone, band text ("%d" = healed LP)]
const DEFS := {
	"heilpilz": ["Heilpilz", "action", "HEILPILZ +%d LP"],
	"zeitstarre": ["Zeitstarre", "info", "ZEITSTARRE! ALLES STEHT STILL"],
	"bildschirmbiss": ["Bildschirm-Biss", "ember", "BILDSCHIRM-BISS!"],
	"lockruf": ["Lockruf", "special", "LOCKRUF!"],
}
const ORDER := ["heilpilz", "zeitstarre", "bildschirmbiss", "lockruf"]
const ITEM_COLORS := {
	"heilpilz": Color("5fe04a"),
	"zeitstarre": Color("5cc8ff"),
	"bildschirmbiss": Color("ff7a24"),
}
## Existing UI icons shown on the HUD band (hud_loot draws band.id).
const BAND_ICONS := {"heilpilz": "regeneration", "zeitstarre": "clock", "bildschirmbiss": "jaws", "lockruf": "magnet"}
const BLINK_AFTER := 45.0
const BREAK_REACH := 1.25
const PICKUP_REACH := 1.1
const CHECK_RANGE := 16.0
const HOVER := 1.45
const POP_SECONDS := 0.45
## Seconds after popping out before an item can be taken (so it is seen).
const ARM_SECONDS := 0.5
const BAND_SECONDS := 1.6
const EMBER := Color("ff8a2a")

## Mushroom baskets: {at, alive, yaw, size}
var mushrooms: Array[Dictionary] = []
## Lying items: {id, at, age, node, pivot, column}
var items: Array[Dictionary] = []
var broken := 0
var spawned := 0
var collected := 0
var taken: Array[String] = []
var band: Dictionary = {}
var world: Node3D
var arena: Node3D
var rng := RandomNumberGenerator.new()
var _time := 0.0
var _layout: RefCounted
var _layout_known := false
var _views: Array[MultiMeshInstance3D] = []
var _cap_material: StandardMaterial3D
var _halo_material: StandardMaterial3D
var _tint_layer: CanvasLayer
var _tint: ColorRect
var _tint_material: ShaderMaterial
static var _meshes := {}

const TINT_CODE := """
shader_type canvas_item;
uniform float strength = 0.0;
uniform vec4 ice : source_color = vec4(0.55, 0.88, 1.0, 1.0);
void fragment() {
	vec2 c = (UV - 0.5) * 2.0;
	float d = length(c * vec2(0.8, 1.0));
	float mask = smoothstep(0.55, 1.25, d);
	COLOR = vec4(ice.rgb, strength * (0.06 + 0.42 * mask));
}
"""


func setup(world_node: Node3D, arena_node: Node3D) -> void:
	world = world_node
	arena = arena_node
	var seed_value := int(arena.get("world_seed")) if arena != null and arena.get("world_seed") != null else 0
	rng.seed = hash(["map_items", seed_value])
	_build_tint()
	_rebuild()


# ---------------------------------------------------------------- placement

func _rebuild() -> void:
	_layout = arena.get("layout") if arena != null else null
	_layout_known = true
	for view in _views:
		view.queue_free()
	_views.clear()
	mushrooms.clear()
	var seed_value := int(arena.get("world_seed")) if arena != null and arena.get("world_seed") != null else 0
	var place_rng := RandomNumberGenerator.new()
	place_rng.seed = hash(["glutpilz", seed_value])
	for at in _place_points(place_rng):
		mushrooms.append({"at": at, "alive": true, "yaw": place_rng.randf() * TAU, "size": place_rng.randf_range(0.92, 1.08)})
	_build_views()
	# Lying items of the old map come along to the arrival (resource rule).
	var here: Vector3 = world.swarm.position if world != null and world.get("swarm") != null else Vector3.ZERO
	for index in items.size():
		var entry: Dictionary = items[index]
		entry.at = _open_spot(here + Vector3(3.0, 0.0, 0.0).rotated(Vector3.UP, float(index) * 2.1 + 0.6))
		(entry.node as Node3D).position = entry.at


## Wanted number of mushrooms for this map (8-12 on the solo map, more on bigger maps).
func _wanted(place_rng: RandomNumberGenerator) -> int:
	var count := place_rng.randi_range(TUNING.MAP_ITEM_COUNT.x, TUNING.MAP_ITEM_COUNT.y)
	var regions := int(arena.get("map_regions")) if arena != null and arena.get("map_regions") != null else 4
	return int(round(float(count) * float(regions * regions) / 16.0))


func _place_points(place_rng: RandomNumberGenerator) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if arena == null:
		return out
	var wanted := _wanted(place_rng)
	var start: Vector3 = world.swarm.position if world != null and world.get("swarm") != null else Vector3.ZERO
	var avoid: Array[Vector3] = []
	var circles: Array[Vector4] = []
	if _layout != null:
		if _layout.get("loot_points") != null:
			for point in _layout.loot_points:
				avoid.append(Vector3(point.x, 0.0, point.z))
		if _layout.get("nodes") != null:
			for node in _layout.nodes:
				var centre: Vector3 = node.center
				circles.append(Vector4(centre.x, 0.0, centre.z, float(node.radius) + 1.5))
	var rect: Rect2 = arena.playable_rect() if arena.has_method("playable_rect") else Rect2(-150, -150, 300, 300)
	rect = rect.grow(-8.0)
	var spacing := TUNING.MAP_ITEM_SPACING * sqrt(rect.size.x / 320.0)
	for attempt in wanted * 80:
		if out.size() >= wanted:
			break
		# Relax the spacing slowly when the map is crowded.
		var gap := spacing * (1.0 if attempt < wanted * 40 else 0.6)
		var point := Vector3(place_rng.randf_range(rect.position.x, rect.end.x), 0.0, place_rng.randf_range(rect.position.y, rect.end.y))
		if not _free(point, start, gap, out, avoid, circles):
			continue
		out.append(point)
	if out.is_empty() and arena.has_method("safe_spawn"):
		# No layout (classic map, tests): a ring around the map centre.
		var centre: Vector3 = arena.map_center() if arena.has_method("map_center") else Vector3.ZERO
		for index in wanted:
			var angle := float(index) * TAU / float(maxi(1, wanted)) + 0.5
			out.append(_open_spot(centre + Vector3(cos(angle), 0.0, sin(angle)) * (26.0 + 9.0 * float(index % 3))))
	return out


func _free(point: Vector3, start: Vector3, gap: float, taken_points: Array[Vector3], avoid: Array[Vector3], circles: Array[Vector4]) -> bool:
	if Vector2(point.x - start.x, point.z - start.z).length() < TUNING.MAP_ITEM_START_GAP:
		return false
	if arena.has_method("is_open") and not arena.is_open(point, TUNING.MAP_ITEM_CLEARANCE):
		return false
	if _layout != null and _layout.has_method("water_at") and float(_layout.water_at(point.x, point.z)) < 1.0:
		return false
	for other in taken_points:
		if Vector2(other.x - point.x, other.z - point.z).length() < gap:
			return false
	for other in avoid:
		if Vector2(other.x - point.x, other.z - point.z).length() < 4.0:
			return false
	for circle in circles:
		if Vector2(circle.x - point.x, circle.z - point.z).length() < circle.w:
			return false
	return true


func _open_spot(point: Vector3) -> Vector3:
	if arena != null and arena.has_method("safe_spawn"):
		point = arena.safe_spawn(point, 0.8)
	point.y = 0.0
	return point


## Mushrooms still standing.
func count() -> int:
	var alive := 0
	for mushroom in mushrooms:
		if mushroom.alive:
			alive += 1
	return alive


# ---------------------------------------------------------------- step

func step(delta: float, centre: Vector3, unit_points: PackedVector3Array) -> void:
	_time += delta
	if arena != null and (arena.get("layout") != _layout or not _layout_known):
		_rebuild()
	# Soft glow pulse of every cap (one shared material).
	if _cap_material != null:
		_cap_material.emission_energy_multiplier = 0.8 + 0.35 * sin(_time * 2.4)
		_halo_material.albedo_color.a = 0.2 + 0.08 * sin(_time * 2.4)
	for index in mushrooms.size():
		var mushroom: Dictionary = mushrooms[index]
		if not mushroom.alive:
			continue
		var at: Vector3 = mushroom.at
		if absf(at.x - centre.x) > CHECK_RANGE or absf(at.z - centre.z) > CHECK_RANGE:
			continue
		if _touched(at, BREAK_REACH * float(mushroom.size), centre, unit_points):
			break_mushroom(index)
	for index in range(items.size() - 1, -1, -1):
		var entry: Dictionary = items[index]
		entry.age += delta
		var at: Vector3 = entry.at
		var near := absf(at.x - centre.x) < 30.0 and absf(at.z - centre.z) < 30.0
		if near:
			_animate_item(entry)
		if near and float(entry.age) >= ARM_SECONDS and _touched(at, PICKUP_REACH, centre, unit_points):
			items.remove_at(index)
			(entry.node as Node3D).queue_free()
			collect(String(entry.id))
	_step_tint()


func _touched(at: Vector3, reach: float, centre: Vector3, unit_points: PackedVector3Array) -> bool:
	if unit_points.is_empty():
		return Vector2(at.x - centre.x, at.z - centre.z).length() <= reach + 0.6
	for point in unit_points:
		if absf(point.x - at.x) < reach and absf(point.z - at.z) < reach:
			return true
	return false


## Breaks mushroom `index`: burst, sound and (with chance) an instant item.
## `id` forces the item ("" = roll, "none" = nothing). Returns the item id or "".
func break_mushroom(index: int, id: String = "") -> String:
	var mushroom: Dictionary = mushrooms[index]
	if not mushroom.alive:
		return ""
	mushroom.alive = false
	broken += 1
	_hide_instance(index)
	var at: Vector3 = mushroom.at
	FX.ring(world if world != null else self, at, Color(EMBER, 0.85), 0.3, 2.6, 0.45)
	FX.ring(world if world != null else self, at, Color(Color("ffe08a"), 0.6), 0.2, 1.6, 0.3)
	if world != null and world.has_method("_sfx"):
		world._sfx("kill", 10)
	if id == "":
		id = roll_id() if rng.randf() < TUNING.MAP_ITEM_CHANCE else "none"
	if id == "none" or not DEFS.has(id):
		# Nothing inside: a few Bernstein coins (the magnet brings them).
		if world != null and world.has_method("drop_loot"):
			world.drop_loot(at, 0.0, 0, "normal", TUNING.MAP_ITEM_EMPTY_AMBER)
		return ""
	if id == "lockruf":
		if world != null and world.has_method("drop_lure"):
			world.drop_lure(at)
		spawned += 1
		return id
	spawn_item(id, at)
	return id


## A random item id by TUNING.MAP_ITEM_WEIGHTS.
func roll_id() -> String:
	var total := 0.0
	for id in ORDER:
		total += float(TUNING.MAP_ITEM_WEIGHTS.get(id, 0.0))
	var pick := rng.randf() * total
	for id in ORDER:
		pick -= float(TUNING.MAP_ITEM_WEIGHTS.get(id, 0.0))
		if pick <= 0.0:
			return id
	return ORDER[0]


## Places item `id` (not "lockruf") at `at`. Returns the entry.
func spawn_item(id: String, at: Vector3) -> Dictionary:
	at = _open_spot(at)
	var entry := {"id": id, "at": at, "age": 0.0}
	_build_item(entry)
	items.append(entry)
	spawned += 1
	var color: Color = ITEM_COLORS.get(id, EMBER)
	FX.ring(world if world != null else self, at, Color(color, 0.85), 0.3, 2.4, 0.5)
	return entry


## Applies item `id` at once.
func collect(id: String) -> void:
	if not DEFS.has(id):
		return
	collected += 1
	if not taken.has(id):
		taken.append(id)
	var text := String(DEFS[id][2])
	var color: Color = ITEM_COLORS.get(id, EMBER)
	var at: Vector3 = world.swarm.position if world != null else Vector3.ZERO
	match id:
		"heilpilz":
			var healed := 0
			if world != null and world.has_method("_heal_leader"):
				healed = world._heal_leader(ceili(float(world.model.leader_max_hp) * TUNING.MAP_ITEM_HEAL))
			text = text % healed
		"zeitstarre":
			if world != null:
				world.freeze_left = maxf(float(world.freeze_left), TUNING.MAP_ITEM_FREEZE)
				FX.ring(world, at, Color(color, 0.7), 1.0, TUNING.MAP_ITEM_BITE_RADIUS, 0.8)
		"bildschirmbiss":
			screen_bite(at)
			FX.ring(world, at, Color(color, 0.8), 1.0, TUNING.MAP_ITEM_BITE_RADIUS, 0.6)
			FX.ring(world, at, Color(Color("ffe08a"), 0.6), 0.5, TUNING.MAP_ITEM_BITE_RADIUS * 0.6, 0.45)
			if world != null and world.has_method("_shake"):
				world._shake(0.4)
			if world != null and world.has_method("_sfx"):
				world._sfx("stomp", 80)
		"lockruf":
			if world != null:
				world.drop_lure(at)
	band = {"id": id, "text": text, "tone": String(DEFS[id][1]), "t0": _time}
	if world != null:
		FX.ring(world, at, Color(color, 0.9), 0.4, 4.5, 0.5)
		FX.ring(world, at, Color(Color.WHITE, 0.6), 0.2, 2.5, 0.35)
		if world.has_method("_sfx"):
			world._sfx("powerup_take", 50)


## Bildschirm-Biss: every enemy within MAP_ITEM_BITE_RADIUS of `at` dies (bosses
## and apex lose MAP_ITEM_BITE_BOSS of their max HP); deaths resolve in the next
## HuntWorld step through the normal death paths (crystals, stats). Returns hits.
func screen_bite(at: Vector3) -> int:
	if world == null:
		return 0
	var radius := TUNING.MAP_ITEM_BITE_RADIUS
	var hits := 0
	for group in [world.prey, world.hunters, world.skitters, world.leapers]:
		for enemy in group:
			if is_instance_valid(enemy) and _within(enemy.position, at, radius) and float(enemy.get("health")) > 0.0:
				enemy.set("health", 0.0)
				hits += 1
	for boss in [world.boss, world.apex]:
		if boss != null and is_instance_valid(boss) and _within(boss.position, at, radius) and float(boss.health) > 0.0:
			boss.take_damage(float(boss.max_health) * TUNING.MAP_ITEM_BITE_BOSS)
			hits += 1
	var brood: Variant = world.ability_brood() if world.has_method("ability_brood") else world.get("horde")
	if brood != null and is_instance_valid(brood) and brood.has_method("damage_circle"):
		hits += int(brood.damage_circle(at, radius, 1.0e9))
	return hits


static func _within(point: Vector3, at: Vector3, radius: float) -> bool:
	return Vector2(point.x - at.x, point.z - at.z).length() <= radius


# ---------------------------------------------------------------- HUD & map

## Band for hud_loot ({} when none is showing).
func band_state() -> Dictionary:
	if band.is_empty() or _time - float(band.t0) > BAND_SECONDS:
		return {}
	return {"text": band.text, "tone": band.tone, "id": String(BAND_ICONS.get(band.id, band.id)), "item": band.id, "t": (_time - float(band.t0)) / BAND_SECONDS}


## Minimap points: standing mushrooms and lying items (HuntWorld filters by discovery).
func map_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	for mushroom in mushrooms:
		if mushroom.alive:
			out.append(mushroom.at)
	for entry in items:
		out.append(entry.at)
	return out


# Ice-blue edge tint while the world is frozen (fades over the last second).
func _build_tint() -> void:
	_tint_layer = CanvasLayer.new()
	_tint_layer.name = "Freeze tint"
	_tint_layer.layer = 0
	add_child(_tint_layer)
	_tint = ColorRect.new()
	_tint.name = "Tint"
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = TINT_CODE
	_tint_material = ShaderMaterial.new()
	_tint_material.shader = shader
	_tint.material = _tint_material
	_tint.visible = false
	_tint_layer.add_child(_tint)


func _step_tint() -> void:
	if _tint == null or world == null:
		return
	var left := float(world.get("freeze_left")) if world.get("freeze_left") != null else 0.0
	var strength := clampf(left, 0.0, 1.0)
	_tint.visible = strength > 0.001
	if _tint.visible:
		_tint_material.set_shader_parameter("strength", strength)


# ---------------------------------------------------------------- look

static func _mesh(key: String) -> Mesh:
	if _meshes.has(key):
		return _meshes[key]
	var mesh: Mesh
	match key:
		"basket":
			var basket := CylinderMesh.new()
			basket.top_radius = 0.82
			basket.bottom_radius = 0.6
			basket.height = 0.6
			basket.radial_segments = 14
			basket.rings = 1
			mesh = basket
		"band":
			var band_mesh := TorusMesh.new()
			band_mesh.inner_radius = 0.74
			band_mesh.outer_radius = 0.9
			band_mesh.rings = 20
			band_mesh.ring_segments = 6
			mesh = band_mesh
		"soil":
			var soil := CylinderMesh.new()
			soil.top_radius = 0.76
			soil.bottom_radius = 0.76
			soil.height = 0.05
			soil.radial_segments = 14
			soil.rings = 1
			mesh = soil
		"halo":
			var halo := CylinderMesh.new()
			halo.top_radius = 1.0
			halo.bottom_radius = 1.0
			halo.height = 0.02
			halo.radial_segments = 24
			halo.rings = 1
			mesh = halo
		"stem":
			var stem := CylinderMesh.new()
			stem.top_radius = 0.11
			stem.bottom_radius = 0.15
			stem.height = 1.0
			stem.radial_segments = 8
			stem.rings = 1
			mesh = stem
		"cap":
			var cap := SphereMesh.new()
			cap.radius = 0.5
			cap.height = 0.5
			cap.is_hemisphere = true
			cap.radial_segments = 16
			cap.rings = 5
			mesh = cap
		"dot":
			var dot := SphereMesh.new()
			dot.radius = 0.1
			dot.height = 0.12
			dot.radial_segments = 6
			dot.rings = 3
			mesh = dot
		"ring":
			var ring := TorusMesh.new()
			ring.inner_radius = 0.92
			ring.outer_radius = 1.0
			ring.rings = 48
			ring.ring_segments = 4
			mesh = ring
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
		"shard":
			var shard := CylinderMesh.new()
			shard.top_radius = 0.0
			shard.bottom_radius = 0.26
			shard.height = 0.55
			shard.radial_segments = 6
			shard.rings = 1
			mesh = shard
		"orb":
			var orb := SphereMesh.new()
			orb.radius = 0.4
			orb.height = 0.8
			orb.radial_segments = 16
			orb.rings = 8
			mesh = orb
		"spike":
			var spike := CylinderMesh.new()
			spike.top_radius = 0.0
			spike.bottom_radius = 0.13
			spike.height = 0.34
			spike.radial_segments = 6
			spike.rings = 1
			mesh = spike
		"bar":
			var bar := BoxMesh.new()
			bar.size = Vector3(0.44, 0.13, 0.13)
			mesh = bar
	_meshes[key] = mesh
	return mesh


static func _material(color: Color, glow: float = 0.0, unshaded := false, transparent := false, additive := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.55
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
	return material


# Parts of one basket: [mesh, material key, local transform].
func _template() -> Array:
	var parts: Array = []
	var flat := Basis.from_scale(Vector3(1.0, 1.0, 1.0))
	parts.append(["halo", "halo", Transform3D(Basis.from_scale(Vector3(1.45, 1.0, 1.45)), Vector3(0, 0.03, 0))])
	parts.append(["ring", "halo_rim", Transform3D(Basis.from_scale(Vector3(1.45, 0.3, 1.45)), Vector3(0, 0.05, 0))])
	parts.append(["basket", "basket", Transform3D(flat, Vector3(0, 0.3, 0))])
	parts.append(["band", "rim", Transform3D(Basis.from_scale(Vector3(1.0, 0.9, 1.0)), Vector3(0, 0.6, 0))])
	parts.append(["band", "weave", Transform3D(Basis.from_scale(Vector3(0.84, 0.6, 0.84)), Vector3(0, 0.26, 0))])
	parts.append(["soil", "soil", Transform3D(flat, Vector3(0, 0.56, 0))])
	# Three glowing mushrooms leaning out like a bouquet: [angle, stem height, cap scale].
	var shrooms := [[0.3, 0.95, 1.0], [2.4, 0.7, 0.82], [4.3, 0.8, 0.9]]
	for s in shrooms:
		var angle := float(s[0])
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var tilt := Basis(Vector3.UP.cross(out).normalized(), 0.42)
		var foot := out * 0.22 + Vector3(0, 0.55, 0)
		var height := float(s[1])
		parts.append(["stem", "stem", Transform3D(tilt * Basis.from_scale(Vector3(1.0, height, 1.0)), foot + tilt * Vector3(0, height * 0.5, 0))])
		var top := foot + tilt * Vector3(0, height, 0)
		var k := float(s[2])
		# Dark gill rim under the glowing cap keeps the three caps apart.
		parts.append(["cap", "gill", Transform3D(tilt * Basis.from_scale(Vector3(k * 1.08, k * 0.5, k * 1.08)), top - tilt * Vector3(0, 0.07, 0))])
		parts.append(["cap", "cap", Transform3D(tilt * Basis.from_scale(Vector3(k, k * 0.78, k)), top - tilt * Vector3(0, 0.03, 0))])
		for i in 4:
			var spot_angle := TAU * float(i) / 4.0 + angle
			var spot := top + tilt * Vector3(cos(spot_angle) * 0.27 * k, 0.24 * k, sin(spot_angle) * 0.27 * k)
			parts.append(["dot", "spot", Transform3D(Basis.from_scale(Vector3.ONE * k), spot)])
		parts.append(["dot", "spot", Transform3D(Basis.from_scale(Vector3.ONE * k * 1.3), top + tilt * Vector3(0, 0.37 * k, 0))])
	return parts


func _build_views() -> void:
	_cap_material = _material(EMBER, 0.8)
	_halo_material = _material(Color(Color("ff8a2a"), 0.22), 0.0, true, true)
	var materials := {
		"halo": _halo_material,
		"halo_rim": _material(Color(Color("ffb050"), 0.7), 0.0, true, true),
		"gill": _material(Color("a8320c")),
		"basket": _material(Color("9a6334")),
		"rim": _material(Color("d59a55")),
		"weave": _material(Color("6e4221")),
		"soil": _material(Color("3e2616")),
		"stem": _material(Color("f6e7c6"), 0.15),
		"cap": _cap_material,
		"spot": _material(Color("fff0b0"), 0.0, true),
	}
	# One MultiMesh per (mesh, material) pair; instance = mushroom x part.
	var groups := {}
	for part in _template():
		var key := "%s|%s" % [part[0], part[1]]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(part[2])
	for key in groups.keys():
		var pair: PackedStringArray = String(key).split("|")
		var locals: Array = groups[key]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = _mesh(pair[0])
		multimesh.instance_count = mushrooms.size() * locals.size()
		for index in mushrooms.size():
			var mushroom: Dictionary = mushrooms[index]
			var scale := TUNING.MAP_ITEM_SIZE * float(mushroom.size)
			var root := Transform3D(Basis(Vector3.UP, float(mushroom.yaw)) * Basis.from_scale(Vector3.ONE * scale), mushroom.at)
			for slot in locals.size():
				multimesh.set_instance_transform(index * locals.size() + slot, root * (locals[slot] as Transform3D))
		var view := MultiMeshInstance3D.new()
		view.name = "Glutpilze %s" % key
		view.multimesh = multimesh
		view.material_override = materials[pair[1]]
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		view.set_meta("parts", locals.size())
		add_child(view)
		_views.append(view)


func _hide_instance(index: int) -> void:
	var gone := Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3(0, -50, 0))
	for view in _views:
		var parts := int(view.get_meta("parts", 1))
		for slot in parts:
			view.multimesh.set_instance_transform(index * parts + slot, gone)


static func _piece(parent: Node3D, mesh: Mesh, material: Material, at: Vector3, basis := Basis.IDENTITY) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.transform = Transform3D(basis, at)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part


# Floating item: symbol shape in the item colour, a ground ring and a light column.
func _build_item(entry: Dictionary) -> void:
	var id: String = entry.id
	var color: Color = ITEM_COLORS.get(id, EMBER)
	var root := Node3D.new()
	root.name = "Item %s" % id
	root.position = entry.at
	add_child(root)
	_piece(root, _mesh("ring"), _material(Color(color.lightened(0.2), 0.8), 0.0, true, true), Vector3(0, 0.05, 0), Basis.from_scale(Vector3(1.05, 0.3, 1.05)))
	_piece(root, _mesh("halo"), _material(Color(color, 0.25), 0.0, true, true), Vector3(0, 0.03, 0), Basis.from_scale(Vector3(1.0, 1.0, 1.0)))
	var column := _piece(root, _mesh("column"), _material(Color(color.lightened(0.2), 0.3), 0.0, true, false, true), Vector3(0, 2.4, 0), Basis.from_scale(Vector3(1.0, 4.8, 1.0)))
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	pivot.position = Vector3(0, HOVER, 0)
	root.add_child(pivot)
	match id:
		"heilpilz":
			# Green mushroom with a white cross on the cap.
			_piece(pivot, _mesh("stem"), _material(Color("f6e7c6"), 0.2), Vector3(0, -0.28, 0), Basis.from_scale(Vector3(1.6, 0.5, 1.6)))
			_piece(pivot, _mesh("cap"), _material(color, 0.6), Vector3(0, -0.05, 0), Basis.from_scale(Vector3(1.55, 1.2, 1.55)))
			var white := _material(Color.WHITE, 0.0, true)
			_piece(pivot, _mesh("bar"), white, Vector3(0, 0.56, 0), Basis.from_scale(Vector3(1.1, 1.0, 1.25)))
			_piece(pivot, _mesh("bar"), white, Vector3(0, 0.56, 0), Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(1.1, 1.0, 1.25)))
		"zeitstarre":
			# Ice crystal cluster: a tall double shard and two small ones.
			var ice := _material(color, 0.9)
			var light := _material(Color("e8fbff"), 0.6)
			_piece(pivot, _mesh("shard"), ice, Vector3(0, 0.3, 0), Basis.from_scale(Vector3(1.8, 2.0, 1.8)))
			_piece(pivot, _mesh("shard"), ice, Vector3(0, -0.24, 0), Basis(Vector3.RIGHT, PI) * Basis.from_scale(Vector3(1.8, 1.0, 1.8)))
			_piece(pivot, _mesh("shard"), light, Vector3(0.5, 0.02, 0.05), Basis(Vector3.BACK, -0.7) * Basis.from_scale(Vector3(1.1, 1.3, 1.1)))
			_piece(pivot, _mesh("shard"), light, Vector3(-0.48, -0.02, 0.02), Basis(Vector3.BACK, 0.75) * Basis.from_scale(Vector3(1.0, 1.2, 1.0)))
		"bildschirmbiss":
			# Ember orb with a crown of teeth.
			_piece(pivot, _mesh("orb"), _material(color, 0.8), Vector3.ZERO, Basis.from_scale(Vector3.ONE * 1.3))
			var tooth := _material(Color("fff0c0"), 0.5)
			for i in 8:
				var angle := TAU * float(i) / 8.0
				var out := Vector3(cos(angle), 0.0, sin(angle))
				var basis := Basis(out.cross(Vector3.UP).normalized(), -PI * 0.5) * Basis.from_scale(Vector3.ONE * 1.5)
				_piece(pivot, _mesh("spike"), tooth, out * 0.6, basis)
			_piece(pivot, _mesh("spike"), tooth, Vector3(0, 0.6, 0), Basis.from_scale(Vector3.ONE * 1.5))
	pivot.scale = Vector3.ONE * 0.01
	entry["node"] = root
	entry["pivot"] = pivot
	entry["column"] = column


func _animate_item(entry: Dictionary) -> void:
	var pivot: Node3D = entry.pivot
	var age := float(entry.age)
	var phase := float(entry.at.x) * 0.7
	# Pops out of the basket (overshoot), then hovers and turns slowly.
	var t := clampf(age / POP_SECONDS, 0.0, 1.0)
	var pop := 1.0 + 2.2 * pow(t - 1.0, 3.0) + 1.2 * pow(t - 1.0, 2.0)
	pivot.scale = Vector3.ONE * TUNING.MAP_ITEM_ICON_SIZE * maxf(0.01, pop)
	pivot.rotation = Vector3(-0.35, _time * 1.3 + phase, 0.0)
	pivot.position.y = lerpf(0.6, HOVER, t) + 0.14 * sin(_time * 2.6 + phase)
	var shown := true
	if age >= BLINK_AFTER:
		shown = fmod(_time * 3.0, 1.0) < 0.62
	pivot.visible = shown
	(entry.column as MeshInstance3D).visible = shown
