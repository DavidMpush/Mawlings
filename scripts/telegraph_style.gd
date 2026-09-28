extends RefCounted

# Ground warning look for every enemy (stage 05 readability). Each kind has its
# own pattern (shaders/telegraph.gdshader) and a bright outer contour framed by
# dark hairlines, so the areas stay distinct without colour and read on moss
# and sand. The colour-blind palette swaps red/green-dependent hues for
# Okabe-Ito blue/orange/yellow/white.
#
#   hunter  – striped ring with inward teeth (disc of the attack radius)
#   skitter – lane of chevrons scrolling in dash direction (local +Z)
#   leaper  – dot field with a crosshair on the landing point
#   boss    – VFX package V1 (user art): coral dashed ring, dark contour, pale
#             dashed inner ring and four arrows (boss_telegraph_circle.svg)
#   boss_cone – forward cone from the boss (boss_telegraph_cone.svg): contour,
#             dashed arc, chevrons and an origin diamond; local +Z = attack direction
# Both boss shapes come from channel masks (tools/build_vfx.gd) drawn by
# shaders/telegraph_boss.gdshader; their hit edge sits exactly on the attack
# radius / reach. The old procedural spokes stay available as "boss_spokes".
#
# Usage: `TELEGRAPH.build(kind, extent)` returns a ready MeshInstance3D (a flat
# PlaneMesh, subdivide 0) whose material animates on its own; drive it with
# `set_progress()` and `set_armed()`. Node scale is honoured in metres.
const UI_STYLE = preload("res://scripts/ui/ui_style.gd")
const SHADER = preload("res://shaders/telegraph.gdshader")
const BOSS_SHADER = preload("res://shaders/telegraph_boss.gdshader")
const BOSS_CIRCLE_MASK = preload("res://assets/vfx/boss_telegraph_circle_mask.png")
const BOSS_CONE_MASK = preload("res://assets/vfx/boss_telegraph_cone_mask.png")
# Stage 20: procedural boss shapes in the same style (lane, ring, islands,
# hazard area) - shaders/telegraph_boss_shapes.gdshader.
const SHAPES_SHADER = preload("res://shaders/telegraph_boss_shapes.gdshader")
enum Shape { DISC, LANE, RING, ISLANDS, HAZARD }
## Contour margin around every procedural shape (the dark line lies outside the edge).
const SHAPE_MARGIN := 0.3
const KINDS := ["hunter", "skitter", "leaper", "boss", "boss_cone"]
const PATTERN := {"hunter": 0, "skitter": 1, "leaper": 2, "boss_spokes": 3}
# SVG geometry (viewBox 512): circle hit radius 210 px around the centre; cone
# origin at (75, 256), reach ~412 px along +X, edges at +-29.2 deg (tan 0.558).
const CIRCLE_HIT_PX := 210.0
const CONE_ORIGIN_PX := Vector2(75.0, 256.0)
const CONE_REACH_PX := 412.0
const CONE_TAN := 0.558
const CONE_DEFAULT_ANGLE := 0.5094

# fill (translucent base), pattern (marks), edge (bright contour), fill_alpha.
const PALETTE := {
	# Stage 20 (S1): every warning is danger magenta/pink (UI_STYLE.BRAWL_DANGER_*),
	# never the ember orange of the own swarm; the kinds differ by pattern.
	"hunter": {"fill": UI_STYLE.BRAWL_DANGER_FACE, "pattern": Color("ffb8dc"), "edge": Color("ff5aa8"), "fill_alpha": 0.24},
	"skitter": {"fill": UI_STYLE.BRAWL_DANGER_LIGHT, "pattern": Color("ffcfe6"), "edge": Color("ff5aa8"), "fill_alpha": 0.26},
	"leaper": {"fill": Color("9e3cf0"), "pattern": Color("ff5ad9"), "edge": Color("ffe3fa"), "fill_alpha": 0.22},
	# VFX V1 colours: coral fill/ring, pale marks, dark wine contour (DARK_BOSS). The
	# wind-up fill darkens towards the contour so the coral swarm stays readable.
	# Stage 20: the user's coral moved to danger magenta (same masks, same marks).
	"boss": {"fill": UI_STYLE.BRAWL_DANGER_FACE, "pattern": Color("ffe4f1"), "edge": Color("ff4fa3"), "fill_alpha": 0.2},
	"boss_cone": {"fill": UI_STYLE.BRAWL_DANGER_FACE, "pattern": Color("ffe4f1"), "edge": Color("ff4fa3"), "fill_alpha": 0.22},
	# Fläche = "liegt da" (Glutpfützen, Säure): filled, calm, no front.
	"hazard": {"fill": UI_STYLE.BRAWL_DANGER_DARK, "pattern": UI_STYLE.BRAWL_DANGER_LIGHT, "edge": UI_STYLE.BRAWL_DANGER_FACE, "fill_alpha": 0.5},
	# Stage 17d: the swarm's own areas (ability clouds, acid puddles, fire trail) -
	# ember, never danger pink.
	"own": {"fill": Color("ff6a1f"), "pattern": Color("ffd08a"), "edge": Color("ffa340"), "fill_alpha": 0.32},
	# Old procedural boss look (dark wine with pale gold spokes).
	"boss_spokes": {"fill": Color("6e0f22"), "pattern": Color("ffe07a"), "edge": Color("fff1c8"), "fill_alpha": 0.34},
}
const PALETTE_COLORBLIND := {
	"hunter": {"fill": UI_STYLE.CB_ORANGE, "pattern": UI_STYLE.CB_ORANGE, "edge": UI_STYLE.CB_WHITE, "fill_alpha": 0.22},
	"skitter": {"fill": UI_STYLE.CB_YELLOW, "pattern": UI_STYLE.CB_WHITE, "edge": UI_STYLE.CB_WHITE, "fill_alpha": 0.26},
	"leaper": {"fill": UI_STYLE.CB_BLUE, "pattern": Color("bfe6ff"), "edge": UI_STYLE.CB_WHITE, "fill_alpha": 0.3},
	"boss": {"fill": UI_STYLE.CB_BLACK, "pattern": UI_STYLE.CB_WHITE, "edge": UI_STYLE.CB_YELLOW, "fill_alpha": 0.3},
	"boss_cone": {"fill": UI_STYLE.CB_BLACK, "pattern": UI_STYLE.CB_WHITE, "edge": UI_STYLE.CB_YELLOW, "fill_alpha": 0.3},
	"boss_spokes": {"fill": UI_STYLE.CB_BLACK, "pattern": UI_STYLE.CB_WHITE, "edge": UI_STYLE.CB_YELLOW, "fill_alpha": 0.34},
	"hazard": {"fill": UI_STYLE.CB_VERMILLION, "pattern": UI_STYLE.CB_YELLOW, "edge": UI_STYLE.CB_WHITE, "fill_alpha": 0.5},
	"own": {"fill": UI_STYLE.CB_ORANGE, "pattern": UI_STYLE.CB_WHITE, "edge": UI_STYLE.CB_YELLOW, "fill_alpha": 0.32},
}
const DARK := Color("0f0a0c")
const DARK_BOSS := Color("3a0f24")
## Safe islands inside a boss area: friendly cyan, never a danger colour.
const SAFE := Color("7fe7ff")
const SAFE_COLORBLIND := Color("56b4e9")


# New unshaded, transparent ShaderMaterial for one telegraph kind. Uniforms:
# `progress` 0..1 (wind-up share), `armed` 0/1, `time` (<0 = global TIME), `opacity`.
static func material(kind: String, colorblind := false) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	if is_boss(kind):
		result.shader = BOSS_SHADER
		result.set_shader_parameter("shape", 1 if kind == "boss_cone" else 0)
		result.set_shader_parameter("mask", BOSS_CONE_MASK if kind == "boss_cone" else BOSS_CIRCLE_MASK)
		result.set_shader_parameter("dark_color", DARK_BOSS)
	else:
		result.shader = SHADER
		result.set_shader_parameter("pattern", int(PATTERN.get(kind, 0)))
		result.set_shader_parameter("dark_color", DARK)
	restyle(result, kind, colorblind)
	return result


## True for the textured boss shapes (VFX package V1).
static func is_boss(kind: String) -> bool:
	return kind == "boss" or kind == "boss_cone"


# Material using the global colour-blind switch in ui_style.gd.
static func current(kind: String) -> ShaderMaterial:
	return material(kind, UI_STYLE.colorblind)


# Swaps the palette of an existing telegraph material (e.g. when the setting changes).
static func restyle(target: ShaderMaterial, kind: String, colorblind := false) -> void:
	var table: Dictionary = PALETTE_COLORBLIND if colorblind else PALETTE
	var colors: Dictionary = table.get(kind, table["hunter"])
	target.set_shader_parameter("fill_color", colors["fill"])
	target.set_shader_parameter("pattern_color", colors["pattern"])
	target.set_shader_parameter("edge_color", colors["edge"])
	target.set_shader_parameter("fill_alpha", colors["fill_alpha"])


# Flat plane for a round telegraph of `radius` metres.
static func circle_mesh(radius: float) -> PlaneMesh:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(radius * 2.0, radius * 2.0)
	return mesh


# Plane for the boss circle: the SVG's hit ring (210 of 256 px) lands exactly on
# `radius`; arrows and contour reach a little beyond, like in the SVG.
static func boss_circle_mesh(radius: float) -> PlaneMesh:
	var mesh := PlaneMesh.new()
	var edge := radius * 512.0 / CIRCLE_HIT_PX
	mesh.size = Vector2(edge, edge)
	return mesh


# Quad for the boss cone: origin at the node, pointing along local +Z, reach
# `reach` metres, half opening `half_angle` (rad). The SVG is drawn at 29 deg; other
# angles stretch it sideways (reads well between ~20 and ~40 deg).
static func boss_cone_mesh(reach: float, half_angle: float = CONE_DEFAULT_ANGLE) -> ArrayMesh:
	var along := reach / CONE_REACH_PX
	var across := along * tan(clampf(half_angle, 0.1, 1.2)) / CONE_TAN
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	var corners := [Vector2(0, 0), Vector2(512, 0), Vector2(512, 512), Vector2(0, 512)]
	var points: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	for corner in corners:
		# Texture +u = attack direction (local +Z), texture v = local X.
		points.append(Vector3((corner.y - CONE_ORIGIN_PX.y) * across, 0.0, (corner.x - CONE_ORIGIN_PX.x) * along))
		uvs.append(corner / 512.0)
	for index in [0, 1, 2, 0, 2, 3]:
		tool.set_uv(uvs[index])
		tool.add_vertex(points[index])
	return tool.commit()


# ------------------------------------------------------------ stage 20 shapes

## Procedural boss shape material (Shape enum) in the palette `kind` ("boss",
## "hazard", or any PALETTE key). Set the size uniforms with the shape builders.
static func shape_material(shape: int, kind := "boss", colorblind := false) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = SHAPES_SHADER
	result.set_shader_parameter("shape", shape)
	# Own (ember) areas get a warm dark rim, never the wine of the danger shapes.
	result.set_shader_parameter("dark_color", Color("6e2808") if kind == "own" else DARK_BOSS)
	restyle(result, kind, colorblind)
	result.set_shader_parameter("safe_color", SAFE_COLORBLIND if colorblind else SAFE)
	return result


static func _shape_part(shape: int, kind: String, colorblind: int, size: Vector2) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = "Telegraph %s %d" % [kind, shape]
	var mesh := PlaneMesh.new()
	mesh.size = size + Vector2.ONE * SHAPE_MARGIN * 2.0
	part.mesh = mesh
	part.material_override = shape_material(shape, kind, UI_STYLE.colorblind if colorblind < 0 else colorblind > 0)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return part


## Boss disc (procedural twin of build("boss", r) without the SVG arrows).
static func build_boss_disc(radius: float, colorblind: int = -1, kind := "boss") -> MeshInstance3D:
	var part := _shape_part(Shape.DISC, kind, colorblind, Vector2.ONE * radius * 2.0)
	(part.material_override as ShaderMaterial).set_shader_parameter("outer", radius)
	return part


## Boss lane: `width` wide, `length` long, centred on the node; local +Z is the
## attack direction (the wind-up grows from the -Z end). Hit edge = the rectangle.
static func build_boss_lane(width: float, length: float, colorblind: int = -1) -> MeshInstance3D:
	var part := _shape_part(Shape.LANE, "boss", colorblind, Vector2(width, length))
	var material := part.material_override as ShaderMaterial
	material.set_shader_parameter("half_width", width * 0.5)
	material.set_shader_parameter("lane_length", length)
	return part


## Boss ring from `inner` to `outer` metres (inside and outside are safe).
static func build_boss_ring(inner: float, outer: float, colorblind: int = -1) -> MeshInstance3D:
	var part := _shape_part(Shape.RING, "boss", colorblind, Vector2.ONE * outer * 2.0)
	var material := part.material_override as ShaderMaterial
	material.set_shader_parameter("outer", outer)
	material.set_shader_parameter("inner", inner)
	return part


## Boss disc with up to 4 safe islands (Vector4 x, 0, z, radius in node-local metres).
static func build_boss_islands(radius: float, islands: Array, colorblind: int = -1) -> MeshInstance3D:
	var part := _shape_part(Shape.ISLANDS, "boss", colorblind, Vector2.ONE * radius * 2.0)
	var material := part.material_override as ShaderMaterial
	material.set_shader_parameter("outer", radius)
	var local := PackedVector4Array()
	for island in islands:
		if local.size() < 4:
			local.append(Vector4(island.x, island.z, island.w, 0.0))
	var count := local.size()
	while local.size() < 4:
		local.append(Vector4(0, 0, -1, 0))
	material.set_shader_parameter("islands", local)
	material.set_shader_parameter("island_count", count)
	return part


## Fläche ("liegt da"): a filled hazard disc without wind-up (puddles, acid).
static func build_hazard(radius: float, colorblind: int = -1, kind := "hazard") -> MeshInstance3D:
	var part := _shape_part(Shape.HAZARD, kind, colorblind, Vector2.ONE * radius * 2.0)
	(part.material_override as ShaderMaterial).set_shader_parameter("outer", radius)
	return part


# Flat 1 m long lane of `width` metres along local Z; scale Z by the lane length.
static func lane_mesh(width: float) -> PlaneMesh:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(width, 1.0)
	return mesh


# Ready telegraph node. `extent` is the radius for round kinds and the full lane
# width for "skitter". colorblind: -1 follows the global switch, 0 off, 1 on.
# "boss" = textured boss circle (extent = radius), "boss_cone" = boss cone
# (extent = reach, default opening; see build_boss_cone for other angles).
static func build(kind: String, extent: float, colorblind: int = -1) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = "Telegraph %s" % kind
	match kind:
		"skitter":
			part.mesh = lane_mesh(extent)
		"boss":
			part.mesh = boss_circle_mesh(extent)
		"boss_cone":
			part.mesh = boss_cone_mesh(extent)
		_:
			part.mesh = circle_mesh(extent)
	part.material_override = material(kind, UI_STYLE.colorblind if colorblind < 0 else colorblind > 0)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return part


## Boss cone with an explicit opening: origin at the node, rotate the node so
## local +Z points along the attack. `half_angle` in radians.
static func build_boss_cone(reach: float, half_angle: float, colorblind: int = -1) -> MeshInstance3D:
	var part := build("boss_cone", reach, colorblind)
	part.mesh = boss_cone_mesh(reach, half_angle)
	return part


static func set_progress(target: Variant, value: float) -> void:
	_apply(target, "progress", clampf(value, 0.0, 1.0))


# armed = false shows a faint contour only (e.g. a hunter still approaching).
static func set_armed(target: Variant, armed: bool) -> void:
	_apply(target, "armed", 1.0 if armed else 0.0)


static func set_opacity(target: Variant, value: float) -> void:
	_apply(target, "opacity", clampf(value, 0.0, 1.0))


# Accepts the MeshInstance3D from build() or its ShaderMaterial.
static func _apply(target: Variant, key: String, value: float) -> void:
	var shader_material: ShaderMaterial = null
	if target is ShaderMaterial:
		shader_material = target
	elif target is GeometryInstance3D:
		shader_material = (target as GeometryInstance3D).material_override as ShaderMaterial
	if shader_material != null:
		shader_material.set_shader_parameter(key, value)
