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
#   boss    – radial spokes around a solid hub
#
# Usage: `TELEGRAPH.build(kind, extent)` returns a ready MeshInstance3D (a flat
# PlaneMesh, subdivide 0) whose material animates on its own; drive it with
# `set_progress()` and `set_armed()`. Node scale is honoured in metres.
const UI_STYLE = preload("res://scripts/ui/ui_style.gd")
const SHADER = preload("res://shaders/telegraph.gdshader")
const KINDS := ["hunter", "skitter", "leaper", "boss"]
const PATTERN := {"hunter": 0, "skitter": 1, "leaper": 2, "boss": 3}

# fill (translucent base), pattern (marks), edge (bright contour), fill_alpha.
const PALETTE := {
	"hunter": {"fill": Color("ff5a3c"), "pattern": Color("ffe6c4"), "edge": Color("fff1e0"), "fill_alpha": 0.2},
	"skitter": {"fill": Color("ffb347"), "pattern": Color("fff0c4"), "edge": Color("fff8e6"), "fill_alpha": 0.24},
	"leaper": {"fill": Color("9e3cf0"), "pattern": Color("ff5ad9"), "edge": Color("ffe3fa"), "fill_alpha": 0.22},
	# Dark wine with pale gold spokes: the ember-red swarm must stay readable inside.
	"boss": {"fill": Color("6e0f22"), "pattern": Color("ffe07a"), "edge": Color("fff1c8"), "fill_alpha": 0.34},
}
const PALETTE_COLORBLIND := {
	"hunter": {"fill": UI_STYLE.CB_ORANGE, "pattern": UI_STYLE.CB_ORANGE, "edge": UI_STYLE.CB_WHITE, "fill_alpha": 0.22},
	"skitter": {"fill": UI_STYLE.CB_YELLOW, "pattern": UI_STYLE.CB_WHITE, "edge": UI_STYLE.CB_WHITE, "fill_alpha": 0.26},
	"leaper": {"fill": UI_STYLE.CB_BLUE, "pattern": Color("bfe6ff"), "edge": UI_STYLE.CB_WHITE, "fill_alpha": 0.3},
	"boss": {"fill": UI_STYLE.CB_BLACK, "pattern": UI_STYLE.CB_WHITE, "edge": UI_STYLE.CB_YELLOW, "fill_alpha": 0.34},
}
const DARK := Color("0f0a0c")


# New unshaded, transparent ShaderMaterial for one telegraph kind. Uniforms:
# `progress` 0..1 (wind-up share), `armed` 0/1, `time` (<0 = global TIME), `opacity`.
static func material(kind: String, colorblind := false) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = SHADER
	result.set_shader_parameter("pattern", int(PATTERN.get(kind, 0)))
	result.set_shader_parameter("dark_color", DARK)
	restyle(result, kind, colorblind)
	return result


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


# Flat 1 m long lane of `width` metres along local Z; scale Z by the lane length.
static func lane_mesh(width: float) -> PlaneMesh:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(width, 1.0)
	return mesh


# Ready telegraph node. `extent` is the radius for round kinds and the full lane
# width for "skitter". colorblind: -1 follows the global switch, 0 off, 1 on.
static func build(kind: String, extent: float, colorblind: int = -1) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = "Telegraph %s" % kind
	part.mesh = lane_mesh(extent) if kind == "skitter" else circle_mesh(extent)
	part.material_override = material(kind, UI_STYLE.colorblind if colorblind < 0 else colorblind > 0)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
