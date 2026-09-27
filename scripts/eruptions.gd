extends Node3D

# Glutsumpf lava eruptions (stage 09 prep, not wired into HuntWorld yet).
#
# Every loss is announced: an eruption first shows its own ground telegraph
# (shaders/eruption.gdshader: rings contracting towards a growing hot core,
# the shared dark-bright-dark contour) for WARNING_SECONDS, then bursts once
# with RADIUS metres. Sources are lava pools and glow channels of the arena
# (arena.eruption_sites), close to the swarm but never inside the start zone.
# Frequency rises with pressure; everything is deterministic from the arena
# seed hash and the eruption counter, so a seed replays the same sequence for
# the same swarm path.
#
# API (like the enemy areas):
#   step(delta, swarm_position, pressure) -> Array of impacts resolved in this
#       step: {"center": Vector3, "radius": float, "power": int}
#   contains(point)          – inside any impact resolved in the last step
#   impact_contains(impact, point) (static) – one impact
#   resolved_power           – largest power resolved in the last step (0 = none)
#   clear()                  – drops pending warnings and effects
# HuntWorld hook (stage 09): `for impact in eruptions.step(...)` ->
#   `_resolve_area_hit(eruptions, impact.center, 0.3)` (uses resolved_power and
#   contains(), exactly like a hunter or the bog king).

const UI_STYLE = preload("res://scripts/ui/ui_style.gd")
const FX = preload("res://scripts/fx.gd")
const SHADER = preload("res://shaders/eruption.gdshader")

const WARNING_SECONDS := 1.6
const RADIUS := 2.5
# Base loss of a full hit, multiplied by pressure (hunter 8, bog king 14).
const BASE_DAMAGE := 6.0
# Seconds between eruption events at pressure 1; divided by sqrt(pressure).
const BASE_INTERVAL := 10.0
const MIN_INTERVAL := 3.0
# Quiet time after entering an erupting biome (or after clear()).
const FIRST_DELAY := 6.0
# Retry delay when no source is in reach.
const RETRY_SECONDS := 1.5
const MAX_PENDING := 3
# Sources are picked between these distances from the swarm centre.
const REACH_MIN := 2.0
const REACH_MAX := 13.0
# Share of events that pick a lava pool when one is in reach.
const POOL_SHARE := 0.65
# The pick is made among this many nearest sources of the chosen kind.
const NEAREST_PICK := 3
# Pending eruptions keep at least this distance from each other.
const SPACING := 5.5
# Nothing erupts within this distance of the world origin (start zone, like arena.START_CLEARANCE).
const START_CLEARANCE := 22.0
const BURST_SECONDS := 1.1
const TELEGRAPH_HEIGHT := 0.12
# Palette per mode: fill (dark smoke), pattern (rings/core), edge (contour).
const PALETTE := {"fill": Color("2b0d06"), "pattern": Color("ffcf4a"), "edge": Color("fff3cf"), "fill_alpha": 0.45}
const PALETTE_COLORBLIND := {"fill": UI_STYLE.CB_BLACK, "pattern": UI_STYLE.CB_YELLOW, "edge": UI_STYLE.CB_WHITE, "fill_alpha": 0.5}
const DARK := Color("0f0a0c")
const LAVA := {"core": Color("ffe27a"), "mid": Color("ff9a2e"), "crust": Color("5a2014")}

# The arena providing sources, seed hash and biome (sibling "Arena" if unset).
var arena: Node3D
# Pending warnings: {"center", "remaining", "power", "node"}.
var pending: Array[Dictionary] = []
# Bursts fading out (visual only): {"node", "column", "age"}.
var bursts: Array[Dictionary] = []
var resolved_power := 0
var last_impacts: Array[Dictionary] = []
# Extra no-eruption zones as Vector4(x, 0, z, radius), e.g. a migration arrival point.
var safe_zones: Array[Vector4] = []
# -1 follows the global colour-blind switch, 0 off, 1 on.
var colorblind := -1
var clock := FIRST_DELAY
# Eruptions scheduled so far: the deterministic roll counter.
var count := 0
var _was_active := false

static var _plane: PlaneMesh
static var _column_mesh: CylinderMesh
static var _column_material: StandardMaterial3D


func _ready() -> void:
	if arena == null and get_parent() != null:
		arena = get_parent().get_node_or_null("Arena") as Node3D
	if _plane == null:
		_plane = PlaneMesh.new()
		_plane.size = Vector2(RADIUS * 2.0, RADIUS * 2.0)
		_column_mesh = CylinderMesh.new()
		_column_mesh.top_radius = 0.35
		_column_mesh.bottom_radius = 0.95
		_column_mesh.height = 1.0
		_column_mesh.radial_segments = 12
		_column_mesh.rings = 1
		_column_material = StandardMaterial3D.new()
		_column_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_column_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_column_material.albedo_color = Color(LAVA.mid.lerp(LAVA.core, 0.35), 0.9)
		_column_material.cull_mode = BaseMaterial3D.CULL_DISABLED


## True while the arena's biome erupts (biomes.gd "eruptions").
func active() -> bool:
	return arena != null and bool(arena.get("biome").get("eruptions", false))


## Seconds between eruption events at this pressure (before the seeded jitter).
static func interval(pressure: float) -> float:
	return clampf(BASE_INTERVAL / sqrt(maxf(pressure, 1.0)), MIN_INTERVAL, BASE_INTERVAL)


## Sources per event: a second one from pressure 8, a third from pressure 32.
static func sources_per_event(pressure: float) -> int:
	return 1 + (1 if pressure >= 8.0 else 0) + (1 if pressure >= 32.0 else 0)


static func damage(pressure: float) -> int:
	return int(ceil(minf(1000000.0, BASE_DAMAGE * maxf(pressure, 1.0))))


func step(delta: float, swarm_position: Vector3, pressure: float) -> Array[Dictionary]:
	resolved_power = 0
	last_impacts = []
	if delta <= 0.0:
		return last_impacts
	_age_bursts(delta)
	var erupting := active()
	if not erupting:
		if _was_active:
			clear()
		_was_active = false
		return last_impacts
	if not _was_active:
		_was_active = true
		clock = FIRST_DELAY
	clock -= delta
	if clock <= 0.0:
		var added := 0
		for index in sources_per_event(pressure):
			if pending.size() >= MAX_PENDING:
				break
			if _schedule(swarm_position, pressure):
				added += 1
		if added == 0:
			clock = RETRY_SECONDS
		else:
			# Seeded jitter 0.8..1.2 so events do not tick like a metronome.
			clock = interval(pressure) * (0.8 + 0.4 * _roll(count, 4711))
	for eruption in pending.duplicate():
		eruption.remaining -= delta
		var warning: MeshInstance3D = eruption.node
		var progress := clampf(1.0 - eruption.remaining / WARNING_SECONDS, 0.0, 1.0)
		(warning.material_override as ShaderMaterial).set_shader_parameter("progress", progress)
		if eruption.remaining <= 0.0:
			pending.erase(eruption)
			var impact := {"center": eruption.center, "radius": RADIUS, "power": int(eruption.power)}
			last_impacts.append(impact)
			resolved_power = maxi(resolved_power, int(eruption.power))
			_burst(warning, eruption.center)
	return last_impacts


## Inside any impact resolved during the last step().
func contains(point: Vector3) -> bool:
	for impact in last_impacts:
		if impact_contains(impact, point):
			return true
	return false


static func impact_contains(impact: Dictionary, point: Vector3) -> bool:
	var center: Vector3 = impact.center
	return Vector2(point.x - center.x, point.z - center.z).length() <= float(impact.radius)


## Share of the given world points inside the last step's impacts (0..1).
func hit_fraction(points: PackedVector3Array) -> float:
	if points.is_empty():
		return 0.0
	var inside := 0
	for point in points:
		if contains(point):
			inside += 1
	return float(inside) / float(points.size())


## Removes pending warnings and running bursts; the quiet start delay restarts.
func clear() -> void:
	for eruption in pending:
		(eruption.node as Node).queue_free()
	for burst in bursts:
		(burst.node as Node).queue_free()
		(burst.column as Node).queue_free()
	pending.clear()
	bursts.clear()
	last_impacts = []
	resolved_power = 0
	clock = FIRST_DELAY


## Starts the next event on the following step (captures, scripted moments).
func erupt_soon() -> void:
	_was_active = active()
	clock = 0.0


## Sources the next event may pick as Vector4(x, 0, z, kind) (kind 0 = lava
## pool, 1 = glow channel), nearest first; deterministic order.
func candidates(swarm_position: Vector3) -> Array[Vector4]:
	var result: Array[Vector4] = []
	if arena == null:
		return result
	var cell: float = arena.CELL
	var middle := Vector2i(floori(swarm_position.x / cell), floori(swarm_position.z / cell))
	for x in range(middle.x - 1, middle.x + 2):
		for z in range(middle.y - 1, middle.y + 2):
			for site in arena.eruption_sites(Vector2i(x, z)):
				var point := Vector3(site.x, 0.0, site.z)
				var distance := Vector2(point.x - swarm_position.x, point.z - swarm_position.z).length()
				if distance < REACH_MIN or distance > REACH_MAX:
					continue
				if not _is_safe(point):
					continue
				var free := true
				for eruption in pending:
					if (eruption.center as Vector3).distance_to(point) < SPACING:
						free = false
						break
				if free:
					result.append(site)
	result.sort_custom(func(a: Vector4, b: Vector4) -> bool:
		var da := Vector2(a.x - swarm_position.x, a.z - swarm_position.z).length_squared()
		var db := Vector2(b.x - swarm_position.x, b.z - swarm_position.z).length_squared()
		return da < db if not is_equal_approx(da, db) else (a.x < b.x if not is_equal_approx(a.x, b.x) else a.z < b.z))
	return result


func _is_safe(point: Vector3) -> bool:
	if Vector2(point.x, point.z).length() - RADIUS < START_CLEARANCE:
		return false
	for zone in safe_zones:
		if Vector2(point.x - zone.x, point.z - zone.z).length() - RADIUS < zone.w:
			return false
	return true


func _schedule(swarm_position: Vector3, pressure: float) -> bool:
	var found := candidates(swarm_position)
	if found.is_empty():
		return false
	# Lava pools are the main source (POOL_SHARE of the events when one is in
	# reach); otherwise a point of a glow channel. Seeded pick among the nearest.
	var pools: Array[Vector4] = []
	var channels: Array[Vector4] = []
	for site in found:
		if site.w == 0.0:
			pools.append(site)
		else:
			channels.append(site)
	var options := pools if not pools.is_empty() and (channels.is_empty() or _roll(count, 4705) < POOL_SHARE) else channels
	var reach := mini(NEAREST_PICK, options.size())
	var pick := int(_roll(count, 4700) * float(reach)) % reach
	var center := Vector3(options[pick].x, 0.0, options[pick].z)
	count += 1
	var warning := MeshInstance3D.new()
	warning.name = "Eruption warning"
	warning.mesh = _plane
	warning.material_override = _material()
	warning.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(warning)
	warning.top_level = true
	warning.global_position = Vector3(center.x, TELEGRAPH_HEIGHT, center.z)
	pending.append({"center": Vector3(center.x, 0.0, center.z), "remaining": WARNING_SECONDS, "power": damage(pressure), "node": warning})
	return true


# Deterministic 0..1 value from the arena seed hash.
func _roll(index: int, salt: int) -> float:
	if arena == null:
		return 0.5
	return float(int(arena.call("_hash", index, 0, salt)) % 1000) / 1000.0


func _material() -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = SHADER
	result.set_shader_parameter("mode", 0)
	result.set_shader_parameter("progress", 0.0)
	restyle(result, UI_STYLE.colorblind if colorblind < 0 else colorblind > 0)
	result.set_shader_parameter("dark_color", DARK)
	result.set_shader_parameter("lava_core", LAVA.core)
	result.set_shader_parameter("lava_mid", LAVA.mid)
	result.set_shader_parameter("lava_crust", LAVA.crust)
	return result


static func restyle(target: ShaderMaterial, colorblind_palette: bool) -> void:
	var colors: Dictionary = PALETTE_COLORBLIND if colorblind_palette else PALETTE
	target.set_shader_parameter("fill_color", colors.fill)
	target.set_shader_parameter("pattern_color", colors.pattern)
	target.set_shader_parameter("edge_color", colors.edge)
	target.set_shader_parameter("fill_alpha", colors.fill_alpha)


# The warning plane turns into the lava splash; a short column shoots up.
func _burst(warning: MeshInstance3D, center: Vector3) -> void:
	var material := warning.material_override as ShaderMaterial
	material.set_shader_parameter("mode", 1)
	material.set_shader_parameter("age", 0.0)
	warning.name = "Eruption burst"
	var column := MeshInstance3D.new()
	column.name = "Eruption column"
	column.mesh = _column_mesh
	column.material_override = _column_material
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(column)
	column.top_level = true
	column.global_position = Vector3(center.x, 0.0, center.z)
	column.scale = Vector3(1.0, 0.01, 1.0)
	bursts.append({"node": warning, "column": column, "age": 0.0})
	FX.ring(self, center, Color(1.0, 0.72, 0.3, 0.9), 0.6, RADIUS + 0.7, 0.55)
	FX.ring(self, center, Color(0.25, 0.1, 0.06, 0.8), 0.4, RADIUS + 1.4, 0.9)


func _age_bursts(delta: float) -> void:
	for burst in bursts.duplicate():
		burst.age += delta
		var share: float = burst.age / BURST_SECONDS
		var plane := burst.node as MeshInstance3D
		var column := burst.column as MeshInstance3D
		if share >= 1.0:
			plane.queue_free()
			column.queue_free()
			bursts.erase(burst)
			continue
		(plane.material_override as ShaderMaterial).set_shader_parameter("age", share)
		# Column: shoots up in 0.1 s, then sinks back and narrows.
		var rise := clampf(float(burst.age) / 0.1, 0.0, 1.0)
		var sink := clampf((float(burst.age) - 0.1) / 0.45, 0.0, 1.0)
		var height := 3.2 * rise * (1.0 - sink)
		column.visible = height > 0.02
		column.scale = Vector3(1.0 - 0.5 * sink, maxf(height, 0.01), 1.0 - 0.5 * sink)
		column.global_position.y = height * 0.5
