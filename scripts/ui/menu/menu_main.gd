extends "res://scripts/ui/menu/menu_canvas.gd"
## MENU_MAIN (stage 04): the Brutstätte main view as one component.
##
## Replaces the menu's legacy blocks background, logo, resources, strain, biomes,
## difficulties, play and tabs (see REPLACES). Child of the menu Control
## (`scripts/menu/menu.gd`); reads all state from the parent and draws at the
## parent's `*_rect()` functions, so hit areas stay where menu.gd handles input.
##
## The component draws BEHIND its parent (`show_behind_parent`): the menu's own
## sheet, reward overlay and toast – and sibling components – stay on top.
##
## The strain card shows a small idling pack of real Mawling models rendered in a
## SubViewport (5 low-poly meshes, unshaded creature shader, only updated while
## the main view is visible). Set `use_3d = false` before adding the node to fall
## back to a painted emblem.
##
## Stage 07 (performance): nothing is repainted per frame any more.
## - Background: sky, rays, fog and vignette are small live layers (rays and
##   fog move at 30 Hz); the drifting leaves and spores are four MultiMeshes
##   whose instance transforms/colours move each frame (one draw call each).
## - Foreground: the same widget code paints four phases, each its own layer:
##   UNDER (live glows under widgets), BASE (baked: panels, card, bodies),
##   LIVE (30 Hz: pulses, shine, glint, turning gems, the 3D pack texture) and
##   TOP (baked: icons, text, claws). Widgets never overlap each other, so the
##   stacking inside every widget stays the original one. BASE/TOP repaint
##   (and re-bake) only when the menu state changes.

const S = preload("res://scripts/ui/ui_style.gd")
const UiLayer := preload("res://scripts/ui/ui_layer.gd")
const MAWLING_PATH := "res://assets/gameplay/characters/Mawling_game.glb"
const SHADER_PATH := "res://shaders/creature_anim.gdshader"
const ICONS_PATH := "res://scripts/ui/ui_icons.gd"
const FRAMES_PATH := "res://scripts/ui/ui_frames.gd"
const UiArt := preload("res://scripts/ui/ui_art.gd")
const LABEL := 22   # stage 06: smallest menu text (900 grid)

## Legacy keys of menu.gd this component takes over.
const REPLACES := ["background", "logo", "resources", "strain", "biomes", "difficulties", "play", "tabs"]

## Where the 3D pack is shown inside the strain card (base 900 x 1600 space).
const STAGE_RECT := Rect2(118, 318, 664, 316)
## Fallback centre of the ground disc when no 3D stage exists.
const STAGE_GROUND := Vector2(450, 572)
const CAMERA_FROM := Vector3(0.0, 1.55, 4.3)
const CAMERA_AT := Vector3(0.0, 0.32, -0.35)
## Pack: position on the ground (x, z), scale, yaw offset (radians, 0 = facing camera).
## The glb faces -X; yaw PI/2 turns it to the camera, the offsets give 3/4 profiles.
const PACK := [
	[Vector2(0.1, 0.65), 1.25, -1.2],
	[Vector2(-1.55, 0.05), 1.05, -1.25],
	[Vector2(1.6, 0.1), 1.05, 1.2],
	[Vector2(-0.8, -1.1), 0.95, -1.3],
	[Vector2(0.9, -1.15), 0.95, 1.3],
]

var use_3d := true
## Painted strain portraits (UI kit V2 expansion) instead of the 3D pack; the
## 3D stage is only built when a portrait is missing or this is off.
var use_portraits := true

var menu = null
var _icons = null
var _frames = null
var _spaced_sub: FontVariation
var _soft: Texture2D
var _viewport: SubViewport
var _camera: Camera3D
var _material: ShaderMaterial
var _pack: Array = []
var _tinted_for := "?"
var _time := 0.0
var _spores: Array = []
var _leaves: Array = []

var _ph := ""                 # phase being painted: under, base, live, top
var _layers: Dictionary = {}
var _far_leaves: MultiMeshInstance2D
var _near_leaves: MultiMeshInstance2D
var _spore_glows: MultiMeshInstance2D
var _spore_dots: MultiMeshInstance2D


func _ready() -> void:
	menu = get_parent()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_behind_parent = true
	_ensure_font()
	if ResourceLoader.exists(ICONS_PATH):
		_icons = load(ICONS_PATH)
	if ResourceLoader.exists(FRAMES_PATH):
		_frames = load(FRAMES_PATH)
	_soft = _make_soft_texture()
	_build_decor()
	if use_portraits and UiArt.tribe("glutmaw") != null:
		use_3d = false
	if use_3d:
		_build_stage()
	_build_layers()


func _process(delta: float) -> void:
	_time += delta
	_update_stage()
	_update_background()
	_refresh_layers()


func _on(phase: String) -> bool:
	return _ph == phase


func _build_layers() -> void:
	_layers.sky = UiLayer.make(self, "Sky", func(c: CanvasItem) -> void: _with(c, _paint_sky))
	_layers.rays = UiLayer.make(self, "Rays", func(c: CanvasItem) -> void: _with(c, _paint_rays))
	_far_leaves = _multimesh("FarLeaves", _leaf_mesh(), null, _leaf_count(0))
	_layers.fog = UiLayer.make(self, "Fog", func(c: CanvasItem) -> void: _with(c, _paint_fog))
	_spore_glows = _multimesh("SporeGlows", _quad_mesh(), _soft, _spores.size())
	_spore_dots = _multimesh("SporeDots", _disc_mesh(), null, _spores.size())
	_near_leaves = _multimesh("NearLeaves", _leaf_mesh(), null, _leaf_count(1))
	_layers.vignette = UiLayer.make(self, "Vignette", func(c: CanvasItem) -> void: _with(c, _paint_vignette))
	for phase in ["under", "base", "live", "top"]:
		_layers[phase] = UiLayer.make(self, phase.capitalize(), _phase_painter(phase), phase == "base" or phase == "top")
	_update_background()


func _with(canvas: CanvasItem, paint: Callable) -> void:
	_cv = canvas
	paint.call()
	_cv = self


func _phase_painter(phase: String) -> Callable:
	return func(canvas: CanvasItem) -> void:
		_cv = canvas
		_ph = phase
		_paint_front()
		_ph = ""
		_cv = self


# Everything the baked phases show; any change repaints (and later re-bakes).
func _state_key() -> Array:
	if menu == null:
		return []
	var key: Array = [size, menu.profile == null, menu.get("load_error"), menu.tab, menu.strain_index, menu._slide,
		menu.biome_id, menu.difficulty, menu.pressed_rect(), menu.settings_open, menu.reward.is_empty(), S.colorblind, S.skin]
	var p = menu.profile
	if p != null:
		key.append_array([p.essence, p.crowns, str(p.upgrades), p.instinct_level, str(p.unlocked_strains), str(p.owned_strains),
			p.completed_quests.size(), str(p.records), str(p.unlocked_difficulties), str(p.daily_records),
			menu.can_play(), menu.can_play_daily(), menu._affordable_upgrades(), menu._instinct_cost()])
	if _viewport != null:
		key.append(_viewport.size)
	return key


func _refresh_layers() -> void:
	var key := _state_key()
	var tick := int(_time * 30.0)
	var tint: Color = S.color("ember")
	if menu != null and menu.profile != null:
		tint = menu._strain_color(menu.current_strain()) if menu._strain_unlocked(menu.current_strain()) else S.color("text_dim")
	_layers.sky.refresh([size, tint, S.skin])
	_layers.rays.refresh(tick)
	_layers.fog.refresh(tick)
	_layers.vignette.refresh([size, S.skin])
	_layers.base.refresh(key)
	_layers.top.refresh(key)
	_layers.under.refresh([key, tick])
	_layers.live.refresh([key, tick])

# ---------------------------------------------------------------- background layers

func _leaf_count(layer: int) -> int:
	var n := 0
	for d in _leaves:
		if d.layer == layer:
			n += 1
	return n


func _multimesh(node_name: String, mesh: Mesh, texture: Texture2D, count: int) -> MultiMeshInstance2D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	var node := MultiMeshInstance2D.new()
	node.name = node_name
	node.multimesh = mm
	node.texture = texture
	add_child(node)
	return node


static func _mesh(verts: PackedVector2Array, colors: PackedColorArray, uvs: PackedVector2Array = PackedVector2Array()) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	if not uvs.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## ui_kit._leaf() as a unit mesh (x = length, y = width): blade in white, the
## midrib at 0.7 so the instance colour gives colour.darkened(0.3).
static func _leaf_mesh() -> ArrayMesh:
	var outline := PackedVector2Array()
	for i in 9:
		var t := float(i) / 8.0
		outline.append(Vector2(t, sin(t * PI)))
	for i in range(7, 0, -1):
		var t := float(i) / 8.0
		outline.append(Vector2(t, -sin(t * PI) * 0.85))
	var verts := PackedVector2Array()
	var colors := PackedColorArray()
	for index in Geometry2D.triangulate_polygon(outline):
		verts.append(outline[index])
		colors.append(Color.WHITE)
	var rib := [Vector2(0, -0.04), Vector2(0.9, -0.04), Vector2(0.9, 0.04), Vector2(0, 0.04)]
	for index in [0, 1, 2, 0, 2, 3]:
		verts.append(rib[index])
		colors.append(Color(0.7, 0.7, 0.7, 1.0))
	return _mesh(verts, colors)


static func _quad_mesh() -> ArrayMesh:
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	for index in [0, 1, 2, 0, 2, 3]:
		verts.append(corners[index])
		uvs.append((corners[index] + Vector2.ONE) * 0.5)
		colors.append(Color.WHITE)
	return _mesh(verts, colors, uvs)


static func _disc_mesh() -> ArrayMesh:
	var verts := PackedVector2Array()
	var colors := PackedColorArray()
	var steps := 24
	for i in steps:
		verts.append_array([Vector2.ZERO, Vector2.from_angle(TAU * i / steps), Vector2.from_angle(TAU * (i + 1) / steps)])
		colors.append_array([Color.WHITE, Color.WHITE, Color.WHITE])
	return _mesh(verts, colors)


## Moves leaves and spores (same formulas as the stage 04 background).
func _update_background() -> void:
	if _far_leaves == null:
		return
	var far := 0
	var near := 0
	for d in _leaves:
		if d.layer == 0:
			var angle: float = d.angle + sin(_time * 0.5 + d.phase) * 0.03
			_far_leaves.multimesh.set_instance_transform_2d(far, Transform2D(angle, Vector2(d.len, d.w), 0.0, d.pos))
			_far_leaves.multimesh.set_instance_color(far, Color(S.color("panel_edge").lerp(S.color("panel_soft"), 0.5 + 0.3 * d.shade), 0.8))
			far += 1
		else:
			var angle: float = d.angle + sin(_time * 0.7 + d.phase) * 0.04
			_near_leaves.multimesh.set_instance_transform_2d(near, Transform2D(angle, Vector2(d.len, d.w), 0.0, d.pos))
			_near_leaves.multimesh.set_instance_color(near, S.color("outline").lerp(S.color("panel_edge"), 0.25 + 0.4 * d.shade))
			near += 1
	for i in _spores.size():
		var sp: Dictionary = _spores[i]
		var p: Vector2 = sp.pos + Vector2(sin(_time * 0.5 + sp.phase) * 16.0, -_time * sp.speed)
		p.y = fposmod(p.y + 60.0, 1720.0) - 60.0
		var c: Color = S.color("cyan") if sp.cyan else S.color("toxic")
		var flicker := 0.55 + 0.45 * sin(_time * 2.2 + sp.phase)
		_spore_glows.multimesh.set_instance_transform_2d(i, Transform2D(0.0, Vector2.ONE * sp.r * 4.5, 0.0, p))
		_spore_glows.multimesh.set_instance_color(i, Color(c, 0.22 * flicker))
		_spore_dots.multimesh.set_instance_transform_2d(i, Transform2D(0.0, Vector2.ONE * sp.r * 0.7, 0.0, p))
		_spore_dots.multimesh.set_instance_color(i, Color(c.lightened(0.5), 0.75 * flicker))

# ---------------------------------------------------------------- 3D pack

func _build_stage() -> void:
	if not ResourceLoader.exists(MAWLING_PATH) or not ResourceLoader.exists(SHADER_PATH):
		use_3d = false
		return
	_viewport = SubViewport.new()
	_viewport.name = "PackStage"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.size = Vector2i(STAGE_RECT.size)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.fov = 30.0
	_viewport.add_child(_camera)
	_camera.look_at_from_position(CAMERA_FROM, CAMERA_AT)
	_material = _creature_material()
	var scene: PackedScene = load(MAWLING_PATH)
	for i in PACK.size():
		var spec: Array = PACK[i]
		var unit := Node3D.new()
		var model: Node3D = scene.instantiate()
		unit.add_child(model)
		var meshes: Array = model.find_children("*", "MeshInstance3D", true, false)
		for mesh in meshes:
			mesh.material_override = _material
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ground: Vector2 = spec[0]
		unit.position = Vector3(ground.x, 0.0, ground.y)
		unit.scale = Vector3.ONE * float(spec[1])
		_viewport.add_child(unit)
		_pack.append({"node": unit, "meshes": meshes, "yaw": float(spec[2]), "phase": i * 1.7 + 0.4})


# Same limb frame as swarm.gd's game material, tuned for a calm idle.
func _creature_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADER_PATH)
	var params := {
		"brightness": 1.25, "saturation": 1.15, "shape_light": 0.4,
		"rim_color": S.color("ember_glow"), "rim_strength": 0.55, "rim_power": 2.2,
		"flash": 0.0, "up_axis": Vector3(0.0, 0.0, -1.0), "forward_axis": Vector3(-1.0, 0.0, 0.0),
		"ground_offset": -0.0008, "foot_a_front": Vector2(0.239, -0.287), "foot_a_back": Vector2(-0.286, 0.205),
		"foot_b_front": Vector2(0.063, 0.239), "foot_b_back": Vector2(-0.052, -0.191), "foot_radius": 0.15,
		"leg_height": 0.22, "stride": 0.09, "lift": 0.09, "stride_centering": 0.5,
		"walk_speed": 0.0, "walk_amount": 0.0, "walk_scale": 1.0,
		"jaw_hinge_forward": 0.12, "jaw_hinge_height": 0.47, "jaw_floor": 0.22, "jaw_angle": 0.45, "bite_amount": 0.0,
		"tail_start": -0.34, "tail_length": 0.26, "tail_floor": 0.1, "tail_swing": 0.06, "tail_rate": 2.2, "idle_motion": 1.0,
	}
	for key in params:
		m.set_shader_parameter(key, params[key])
	return m


## 3D ground point -> base-canvas position inside STAGE_RECT.
func _stage_point(world: Vector3) -> Vector2:
	return STAGE_RECT.position + _camera.unproject_position(world) / Vector2(_viewport.size) * STAGE_RECT.size


func _stage_visible() -> bool:
	return menu != null and menu.profile != null and menu.tab == "" and menu.reward.is_empty()


func _update_stage() -> void:
	if _viewport == null:
		return
	var active := _stage_visible()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if not active:
		return
	var scale := 1.0
	if get_viewport() != null:
		scale = clampf(get_viewport().get_final_transform().get_scale().x, 1.0, 2.0)
	var wanted := Vector2i((STAGE_RECT.size * scale).round())
	if _viewport.size != wanted:
		_viewport.size = wanted
	var id: String = menu.current_strain()
	var unlocked: bool = menu._strain_unlocked(id)
	var key := "%s|%s" % [id, unlocked]
	if key != _tinted_for:
		_tinted_for = key
		var tint: Color = menu._strain_color(id)
		var body := Color(1, 1, 1, 0)
		if id != "glutmaw":
			body = Color(tint.r, tint.g, tint.b, 0.85)
		if unlocked:
			_material.set_shader_parameter("body_tint", body)
			_material.set_shader_parameter("brightness", 1.25)
			_material.set_shader_parameter("saturation", 1.15)
			_material.set_shader_parameter("rim_color", S.color("ember_glow").lerp(tint.lightened(0.4), 0.6))
			_material.set_shader_parameter("rim_strength", 0.55)
		else:
			# Locked: a dark silhouette with a cold rim, the pack is only hinted.
			_material.set_shader_parameter("body_tint", Color(S.color("panel_edge").r, S.color("panel_edge").g, S.color("panel_edge").b, 1.0))
			_material.set_shader_parameter("brightness", 0.32)
			_material.set_shader_parameter("saturation", 0.2)
			_material.set_shader_parameter("rim_color", S.color("text_dim"))
			_material.set_shader_parameter("rim_strength", 0.9)
	# Idle: look around, breathe, a short trot in place now and then, snapping jaws.
	for i in _pack.size():
		var u: Dictionary = _pack[i]
		var t: float = _time + u.phase
		var trot := clampf(sin(t * 0.55) * 2.2 - 1.5, 0.0, 0.7)
		var bite := pow(maxf(0.0, sin(t * 1.1 + i * 0.9)), 14.0)
		var node: Node3D = u.node
		node.rotation.y = PI * 0.5 + u.yaw + sin(t * 0.6) * 0.18 + sin(t * 1.7) * 0.04
		node.position.y = absf(sin(t * 9.0)) * 0.05 * trot
		for mesh in u.meshes:
			mesh.set_instance_shader_parameter("instance_walk", trot)
			mesh.set_instance_shader_parameter("instance_phase", fmod(t * 9.0, TAU))
			mesh.set_instance_shader_parameter("instance_bite", bite)

# ---------------------------------------------------------------- helpers

func _make_soft_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	return texture


## Soft radial light blob, `radius` per axis.
func _glow(center: Vector2, radius: Vector2, color: Color) -> void:
	_cv.draw_texture_rect(_soft, Rect2(center - radius, radius * 2.0), false, color)


func _txt(value: String, at: Vector2, font_size: int, color: Color = S.TEXT, centered: bool = false, outline: int = 6, body: bool = false) -> float:
	return S.text(_cv, value, at, font_size, color, centered, outline, S.body_font() if body else null)


func _tw(value: String, font_size: int, body: bool = false) -> float:
	var face: Font = S.body_font() if body else S.display_font()
	return face.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


func _wrap(value: String, width: float, font_size: int, body: bool = true) -> Array:
	var lines: Array = []
	var line := ""
	for word in value.split(" ", false):
		var candidate: String = word if line == "" else line + " " + word
		if _tw(candidate, font_size, body) > width and line != "":
			lines.append(line)
			line = word
		else:
			line = candidate
	if line != "":
		lines.append(line)
	return lines


## Shared icon if the ICONS kit has it, else false (caller draws a fallback).
func _icon(ids: Array, rect: Rect2, tint: Color = Color.WHITE) -> bool:
	if _icons == null:
		return false
	for id in ids:
		if _icons.has(id):
			_icons.draw(_cv, id, rect, tint)
			return true
	return false


## Bevelled organic outline with optional side notches.
func _shape(rect: Rect2, cut: float, notch: float = 0.0) -> PackedVector2Array:
	var x0 := rect.position.x
	var y0 := rect.position.y
	var x1 := rect.end.x
	var y1 := rect.end.y
	var c := minf(cut, minf(rect.size.x, rect.size.y) * 0.32)
	var my := (y0 + y1) * 0.5
	var p := PackedVector2Array()
	p.append(Vector2(x0 + c, y0))
	p.append(Vector2(x1 - c, y0))
	p.append(Vector2(x1 - c * 0.3, y0 + c * 0.3))
	p.append(Vector2(x1, y0 + c))
	if notch > 0.0:
		p.append(Vector2(x1, my - notch * 1.8))
		p.append(Vector2(x1 - notch, my - notch * 0.5))
		p.append(Vector2(x1 - notch, my + notch * 0.5))
		p.append(Vector2(x1, my + notch * 1.8))
	p.append(Vector2(x1, y1 - c))
	p.append(Vector2(x1 - c * 0.3, y1 - c * 0.3))
	p.append(Vector2(x1 - c, y1))
	p.append(Vector2(x0 + c, y1))
	p.append(Vector2(x0 + c * 0.3, y1 - c * 0.3))
	p.append(Vector2(x0, y1 - c))
	if notch > 0.0:
		p.append(Vector2(x0, my + notch * 1.8))
		p.append(Vector2(x0 + notch, my + notch * 0.5))
		p.append(Vector2(x0 + notch, my - notch * 0.5))
		p.append(Vector2(x0, my - notch * 1.8))
	p.append(Vector2(x0, y0 + c))
	p.append(Vector2(x0 + c * 0.3, y0 + c * 0.3))
	return p


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var loop := points.duplicate()
	loop.append(points[0])
	return loop


## Vertical gradient fill for any polygon.
func _fill_gradient(points: PackedVector2Array, top_color: Color, bottom_color: Color) -> void:
	var y0 := INF
	var y1 := -INF
	for p in points:
		y0 = minf(y0, p.y)
		y1 = maxf(y1, p.y)
	var colors := PackedColorArray()
	for p in points:
		colors.append(top_color.lerp(bottom_color, clampf((p.y - y0) / maxf(1.0, y1 - y0), 0.0, 1.0)))
	_cv.draw_polygon(points, colors)


## Organic card: shadow, accent glow, gradient body, veins, cell holes, rim, bone claws.
## claws: bitmask 1 top-left, 2 top-right, 4 bottom-right, 8 bottom-left.
func _panel(rect: Rect2, accent: Color, fill: Color = S.PANEL, glow: float = 0.0, cut: float = 20.0, notch: float = 0.0, claws: int = 0, rim: float = 3.0, cells: bool = false) -> void:
	if S.is_calm():
		_panel_calm(rect, accent, fill, glow, cut, rim)
		return
	var shape := _shape(rect, cut, notch)
	_cv.draw_colored_polygon(_shape(Rect2(rect.position + Vector2(0, 8), rect.size), cut, notch), S.color("shadow"))
	if glow > 0.0:
		_cv.draw_colored_polygon(_shape(rect.grow(13), cut + 9, notch), Color(accent, 0.06 * glow))
		_cv.draw_colored_polygon(_shape(rect.grow(6), cut + 4, notch), Color(accent, 0.16 * glow))
	_fill_gradient(shape, Color(fill.lightened(0.09), fill.a), Color(fill.darkened(0.25), fill.a))
	_veins(rect, accent)
	if cells:
		_cells(Vector2(rect.end.x - 54, rect.position.y + 34), accent)
	_cv.draw_polyline(_closed(_shape(rect.grow(-7), maxf(4.0, cut - 5), notch * 0.7)), Color(accent, 0.2), 1.5, true)
	var loop := _closed(shape)
	_cv.draw_polyline(loop, S.color("outline"), rim + 3.0, true)
	_cv.draw_polyline(loop, accent, rim, true)
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	var outward := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for i in 4:
		if claws & (1 << i):
			var dir: Vector2 = (outward[i] as Vector2).normalized()
			var base: Vector2 = corners[i] - dir * cut * 0.2
			_claw(base + Vector2(0, 2), dir, 28, 8, S.color("outline"), 0.45 if i % 2 == 0 else -0.45)
			_claw(base, dir, 26, 7, S.color("bone"), 0.45 if i % 2 == 0 else -0.45)


## Calm skin (V2 kit): petrol body, a faint teal line under the top edge and
## one broad accent stroke. A selected panel gets a slightly stronger stroke,
## no glow, veins, cells or claws.
func _panel_calm(rect: Rect2, accent: Color, fill: Color, glow: float, cut: float, rim: float) -> void:
	var c := minf(cut, 18.0)
	var shape := UiFramesRef.chamfer_points(rect, c)
	_cv.draw_colored_polygon(UiFramesRef.chamfer_points(Rect2(rect.position + Vector2(0, 6), rect.size), c), S.color("shadow"))
	var body := S.tone(fill)
	_fill_gradient(shape, Color(body.lightened(0.04), maxf(body.a, 0.94)), Color(body.darkened(0.12), maxf(body.a, 0.94)))
	if rect.size.y > 60.0:
		_cv.draw_line(Vector2(rect.position.x + c + 2, rect.position.y + 12), Vector2(rect.end.x - c - 2, rect.position.y + 12), Color("76cfc066"), 2.0, true)
	var edge := S.tone(accent)
	if glow > 0.0:
		_cv.draw_polyline(_closed(UiFramesRef.chamfer_points(rect.grow(4.0), c + 2.0)), Color(edge, 0.18 * glow), 3.0, true)
	_cv.draw_polyline(_closed(shape), edge, maxf(2.0, rim), true)


## Faint branching veins, deterministic per rectangle.
func _veins(rect: Rect2, accent: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(rect.position)) ^ hash(Vector2i(rect.size))
	var count := clampi(int(rect.size.x * rect.size.y / 26000.0), 2, 9)
	for i in count:
		var from_left := rng.randf() < 0.5
		var start := Vector2(rect.position.x + 6 if from_left else rect.end.x - 6, rng.randf_range(rect.position.y + 20, rect.end.y - 20))
		var dir := Vector2(1 if from_left else -1, rng.randf_range(-0.6, 0.6)).normalized()
		var points := PackedVector2Array([start])
		var p := start
		var length := rng.randf_range(40, minf(160, rect.size.x * 0.3))
		for k in 5:
			dir = dir.rotated(rng.randf_range(-0.5, 0.5))
			p += dir * length / 5.0
			points.append(p)
		_cv.draw_polyline(points, Color(S.color("panel_edge"), 0.55), 2.0, true)
		var mid := points[2]
		_cv.draw_line(mid, mid + dir.rotated(0.9 if from_left else -0.9) * length * 0.3, Color(S.color("panel_edge"), 0.4), 1.5, true)
		_cv.draw_circle(points[5], 2.5, Color(accent, 0.12))


## Cluster of pores like the concept cards.
func _cells(at: Vector2, accent: Color) -> void:
	for o in [Vector2(0, 0), Vector2(20, -4), Vector2(12, 15), Vector2(30, 13)]:
		var r := 7.0 if o == Vector2.ZERO else 5.5
		_cv.draw_circle(at + o, r + 2.0, Color(accent, 0.18))
		_cv.draw_circle(at + o, r, S.color("outline"))


func _socket(c: Vector2, r: float, accent: Color, glow: float = 1.0, glow_phase: String = "top") -> void:
	if S.is_calm():
		# V2: octagonal petrol plate with one stroke, no glow.
		if not _on("top"):
			return
		var plate := UiFramesRef.chamfer_points(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), r * 0.42)
		_cv.draw_colored_polygon(plate, Color(S.CALM_BG, 0.97))
		_cv.draw_polyline(_closed(plate), S.tone(accent), 3.0, true)
		return
	if glow > 0.0 and _on(glow_phase):
		_glow(c, Vector2(r, r) * 1.9, Color(accent, 0.22 * glow))
	if not _on("top"):
		return
	_cv.draw_circle(c, r + 3.0, S.color("outline"))
	_cv.draw_circle(c, r, S.color("panel").darkened(0.35))
	_cv.draw_arc(c, r, 0, TAU, 40, accent, 3.0, true)
	_cv.draw_arc(c, r - 6.0, 0, TAU, 40, Color(accent, 0.2), 1.5, true)



func _gem(c: Vector2, r: float, color: Color) -> void:
	if S.is_calm():
		_diamond(c, r, S.tone(color))
		return
	_diamond(c, r + 2.5, S.color("outline"))
	_diamond(c, r, color)
	_diamond(c + Vector2(-r * 0.2, -r * 0.3), r * 0.35, Color(1, 1, 1, 0.45))

# ---------------------------------------------------------------- background

func _build_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90417
	for i in 44:
		_spores.append({"pos": Vector2(rng.randf_range(0, 900), rng.randf_range(0, 1600)), "r": rng.randf_range(1.6, 4.2), "speed": rng.randf_range(10, 28), "phase": rng.randf() * TAU, "cyan": rng.randf() < 0.45})
	# The painted background already frames the view with jungle; the drifting
	# leaves are only the fallback without it.
	if UiArt.menu_background() != null:
		return
	# Two layers of jungle leaves hugging the side edges; layer 0 is far and hazy.
	for layer in 2:
		for i in 16:
			var left := i % 2 == 0
			var y := rng.randf_range(-60, 1660)
			var x := rng.randf_range(-70, 40) if left else rng.randf_range(860, 970)
			var angle := rng.randf_range(-1.0, 0.9) + (0.0 if left else PI)
			_leaves.append({"layer": layer, "pos": Vector2(x, y), "len": rng.randf_range(150, 280) * (1.2 if layer == 0 else 1.0), "w": rng.randf_range(34, 62), "angle": angle, "shade": rng.randf(), "phase": rng.randf() * TAU})
	# Canopy fronds hanging from the top corners.
	for i in 7:
		var left := i % 2 == 0
		_leaves.append({"layer": 1, "pos": Vector2(rng.randf_range(-30, 160) if left else rng.randf_range(740, 930), rng.randf_range(-40, 10)), "len": rng.randf_range(160, 250), "w": rng.randf_range(40, 60), "angle": rng.randf_range(1.0, 1.5) if left else rng.randf_range(1.65, 2.1), "shade": rng.randf() * 0.5, "phase": rng.randf() * TAU})


func _paint_sky() -> void:
	if S.is_brawl():
		_b_paint_sky()
		return
	var w := size.x
	var h := size.y
	var painted := UiArt.menu_background()
	if painted != null:
		# V2 swamp painting (cover, centred), slightly dimmed so panels stay calm.
		var full := Rect2(Vector2.ZERO, size)
		UiArt.draw_cover(_cv, painted, PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, h), Vector2(0, h)]), full, Color(0.86, 0.9, 0.9))
		var glow_tint: Color = S.color("ember")
		if menu != null and menu.profile != null:
			glow_tint = menu._strain_color(menu.current_strain()) if menu._strain_unlocked(menu.current_strain()) else S.color("text_dim")
		_glow(Vector2(w * 0.5, 500), Vector2(560, 440), Color(glow_tint, 0.12))
		return
	var stops := [[0.0, S.color("outline")], [0.3, S.color("panel_soft").lightened(0.04)], [0.62, Color(S.color("panel"), 1.0)], [1.0, S.color("outline")]]
	for i in stops.size() - 1:
		var a: float = stops[i][0] * h
		var b: float = stops[i + 1][0] * h
		var ca := Color(stops[i][1], 1.0)
		var cb := Color(stops[i + 1][1], 1.0)
		_cv.draw_polygon(PackedVector2Array([Vector2(0, a), Vector2(w, a), Vector2(w, b), Vector2(0, b)]), PackedColorArray([ca, ca, cb, cb]))
	var tint: Color = S.color("ember")
	if menu != null and menu.profile != null:
		tint = menu._strain_color(menu.current_strain()) if menu._strain_unlocked(menu.current_strain()) else S.color("text_dim")
	# Warm pool of light where the pack stands, cool haze lower down.
	_glow(Vector2(w * 0.5, 520), Vector2(620, 520), Color(tint, 0.2))
	_glow(Vector2(w * 0.5, 1180), Vector2(700, 380), Color(S.color("cyan"), 0.05))


## God rays from the canopy.
func _paint_rays() -> void:
	if S.is_brawl():
		return
	var ray_color := S.color("toxic").lerp(S.color("text"), 0.55)
	for i in 5:
		var x := 60.0 + i * 150.0 + sin(_time * 0.13 + i * 1.3) * 26.0
		var top_w := 30.0 + i * 8.0
		var alpha := 0.045 + 0.02 * sin(_time * 0.4 + i * 2.1)
		var top_c := Color(ray_color, alpha)
		var low_c := Color(ray_color, 0.0)
		_cv.draw_polygon(PackedVector2Array([Vector2(x, -10), Vector2(x + top_w, -10), Vector2(x + top_w + 520, 1250), Vector2(x + 300, 1250)]), PackedColorArray([top_c, top_c, low_c, low_c]))


## Drifting fog between the far leaves and the spores.
func _paint_fog() -> void:
	if S.is_brawl():
		return
	for i in 3:
		var fy: float = [760.0, 1010.0, 1240.0][i]
		var fx := fposmod(_time * (14.0 + i * 5.0) + i * 300.0, 1500.0) - 300.0
		_glow(Vector2(fx, fy), Vector2(460, 90), Color(S.color("text_dim"), 0.05))
		_glow(Vector2(fx - 750.0, fy + 40.0), Vector2(460, 90), Color(S.color("text_dim"), 0.04))


## Vignette: sides and the bands behind the resource bar and tab dock.
func _paint_vignette() -> void:
	if S.is_brawl():
		_b_paint_vignette()
		return
	var w := size.x
	var h := size.y
	var dark := Color(S.color("outline"), 0.6)
	var clear := Color(S.color("outline"), 0.0)
	_cv.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(90, 0), Vector2(90, h), Vector2(0, h)]), PackedColorArray([dark, clear, clear, dark]))
	_cv.draw_polygon(PackedVector2Array([Vector2(w - 90, 0), Vector2(w, 0), Vector2(w, h), Vector2(w - 90, h)]), PackedColorArray([clear, dark, dark, clear]))
	_cv.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, 130), Vector2(0, 130)]), PackedColorArray([dark, dark, clear, clear]))
	_cv.draw_polygon(PackedVector2Array([Vector2(0, h - 260), Vector2(w, h - 260), Vector2(w, h), Vector2(0, h)]), PackedColorArray([clear, clear, dark, dark]))


# ---------------------------------------------------------------- draw

func _paint_front() -> void:
	if menu == null:
		return
	if S.is_brawl():
		_paint_brawl()
		return
	if menu.profile == null:
		# Loading / error state: only the new logo, menu.gd writes the status line.
		_draw_logo()
		return
	_draw_resources()
	if menu.tab == "":
		_draw_logo()
		_draw_strain()
		_draw_section("BIOM", menu.biome_rect(0).position.y - 16)
		_draw_biomes()
		_draw_section("SCHWIERIGKEIT", menu.difficulty_rect(0).position.y - 16)
		_draw_difficulties()
		_draw_play()
		_draw_daily()
	_draw_tabs()



func _draw_resources() -> void:
	_resource_pill(Rect2(16, 18, 270, 76), S.color("violet"), "ESSENZ", int(menu.profile.essence), true)
	_resource_pill(Rect2(size.x - 286, 18, 270, 76), S.color("gold"), "KÖNIGSZÄHNE", int(menu.profile.crowns), false)
	if _on("top"):
		_draw_gear_button()



## Settings gear beside the crown counter (hit area: menu.settings_button_rect()).
func _draw_gear_button() -> void:
	var rect: Rect2 = menu.settings_button_rect()
	var pressed: bool = menu.is_pressed(rect) or menu.settings_open
	var c := rect.get_center() + (Vector2(0, 3) if pressed else Vector2.ZERO)
	var r := minf(rect.size.x, rect.size.y) * 0.5 - 4.0
	_cv.draw_circle(c + Vector2(0, 5), r, S.color("shadow"))
	_socket(c, r, S.color("bone") if not pressed else S.color("ember_glow"), 0.5 if pressed else 0.25)
	_gear(c, r * 0.62, S.color("outline"), 1.12)
	_gear(c, r * 0.62, S.color("bone").darkened(0.08) if not pressed else S.color("ember_glow").lerp(S.color("text"), 0.4), 1.0)


## Eight-tooth gear with a hole; `k` > 1 draws a slightly larger outline pass.
func _gear(c: Vector2, r: float, color: Color, k: float) -> void:
	var points := PackedVector2Array()
	var teeth := 8
	for i in teeth * 4:
		var a := TAU * i / (teeth * 4.0) + 0.2
		var outer := i % 4 == 1 or i % 4 == 2
		points.append(c + Vector2(cos(a), sin(a)) * r * k * (1.0 if outer else 0.74))
	_cv.draw_colored_polygon(points, color)
	_cv.draw_circle(c, r * 0.3 * (2.0 - k), S.color("panel").darkened(0.35) if k <= 1.0 else color)

func _resource_pill(rect: Rect2, accent: Color, label: String, value: int, essence: bool) -> void:
	var body := Rect2(rect.position + Vector2(26, 6), rect.size - Vector2(26, 12))
	if _on("base") and S.is_calm():
		var chip := UiFramesRef.chamfer_points(body, 14.0)
		_cv.draw_colored_polygon(UiFramesRef.chamfer_points(Rect2(body.position + Vector2(0, 5), body.size), 14.0), S.color("shadow"))
		_cv.draw_colored_polygon(chip, Color(S.CALM_BG, 0.95))
		_cv.draw_line(body.position + Vector2(16, 11), Vector2(body.end.x - 16, body.position.y + 11), Color("76cfc04d"), 2.0, true)
		_cv.draw_polyline(_closed(chip), Color(S.tone(accent), 0.85), 2.5, true)
	elif _on("base"):
		_cv.draw_colored_polygon(_rounded_points(Rect2(body.position + Vector2(0, 6), body.size), body.size.y * 0.5, 5), S.color("shadow"))
		_fill_gradient(_rounded_points(body, body.size.y * 0.5, 5), Color(S.color("panel_soft").lightened(0.08), 0.96), Color(S.color("panel").darkened(0.2), 0.96))
		var loop := _closed(_rounded_points(body, body.size.y * 0.5, 5))
		_cv.draw_polyline(loop, S.color("outline"), 5.0, true)
		_cv.draw_polyline(loop, Color(accent, 0.85), 2.5, true)
	var ic := rect.position + Vector2(36, rect.size.y * 0.5)
	_socket(ic, 32, accent, 0.8 + 0.2 * _pulse(1.6), "live")
	if not _on("top"):
		return
	if not _icon(["essence"] if essence else ["crown_tooth"], Rect2(ic - Vector2(27, 27), Vector2(54, 54))):
		if essence:
			_essence_drop(ic + Vector2(0, 3), 15, accent)
		else:
			_fang(ic + Vector2(-2, 2), 20, S.color("bone"))
	_txt(label, Vector2(rect.position.x + 80, rect.position.y + 36), LABEL, accent.lightened(0.35), false, 4)
	_txt("%d" % value, Vector2(rect.position.x + 80, rect.position.y + 70), S.SIZE_HEAD, S.color("text"), false, 6)



func _draw_logo() -> void:
	var cx := size.x * 0.5
	var title := "MAWLINGS"
	var fs := 104
	var baseline := 218.0
	var w := _tw(title, fs)
	var face := S.display_font()
	if UiArt.logo() != null:
		_draw_logo_art(cx, baseline)
		return
	if S.is_calm():
		_draw_logo_calm(cx, title, fs, baseline, w, face)
		return
	if _on("under"):
		_glow(Vector2(cx, baseline - 36), Vector2(w * 0.72, 120), Color(S.color("ember"), 0.22 + 0.05 * _pulse(1.2)))
	var left := cx - w * 0.5 - 34.0
	var right := cx + w * 0.5 + 34.0
	var gum := S.color("danger").darkened(0.45)
	var upper_y := baseline - 100.0
	var lower_y := baseline + 16.0
	# Word: shadow, extrusion, bevel highlight, face with a travelling glint.
	var origin := Vector2(cx - w * 0.5, baseline)
	if _on("base"):
		_cv.draw_string_outline(face, origin + Vector2(0, 9), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 16, Color(S.color("outline"), 0.7))
		_cv.draw_string_outline(face, origin + Vector2(0, 5), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 12, S.color("outline"))
		_cv.draw_string(face, origin + Vector2(0, 5), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, S.color("ember").darkened(0.5))
		_cv.draw_string(face, origin + Vector2(0, -3), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, S.color("gold").lightened(0.35))
	if _on("live"):
		# Face with the travelling glint.
		var sweep := fposmod(_time * 0.45, 2.2) - 0.35
		var x := origin.x
		for i in title.length():
			var ch := title[i]
			var cw := face.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var k := clampf(1.0 - absf((x + cw * 0.5 - origin.x) / w - sweep) * 5.0, 0.0, 1.0)
			var face_color := S.color("ember_glow").lerp(S.color("ember"), 0.35).lerp(S.color("text"), k * 0.75)
			_cv.draw_string(face, Vector2(x, baseline), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, face_color)
			x += face.get_string_size(title.substr(0, i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x - (x - origin.x)
	if not _on("top"):
		return
	# Jaws over the word: the fangs bite into the letters.
	_jaw(Vector2(left, upper_y + 26), Vector2(cx, upper_y - 20), Vector2(right, upper_y + 26), 20.0, gum, 1.0, [0.06, 0.15, 0.27, 0.39, 0.5, 0.61, 0.73, 0.85, 0.94], [44.0, 30.0, 18.0, 14.0, 12.0, 14.0, 18.0, 30.0, 44.0])
	_jaw(Vector2(left + 40, lower_y - 2), Vector2(cx, lower_y + 34), Vector2(right - 40, lower_y - 2), 16.0, gum, -1.0, [0.1, 0.24, 0.38, 0.5, 0.62, 0.76, 0.9], [30.0, 18.0, 13.0, 11.0, 13.0, 18.0, 30.0])
	# Subtitle plate.
	var sub := "BRUTSTÄTTE"
	var sub_y := baseline + 64.0
	var half := _tw(sub, LABEL + 3) * 0.5
	for side in [-1.0, 1.0]:
		var a := Vector2(cx + side * (half + 14), sub_y - 9)
		var b := Vector2(cx + side * (half + 150), sub_y - 9)
		_cv.draw_line(a, b, Color(S.color("toxic"), 0.45), 2.0, true)
		_gem(b + Vector2(side * 8, 0), 6, S.color("toxic"))
		_gem(a + Vector2(side * 36, 0), 3.5, Color(S.color("toxic"), 0.8))
	_txt(sub, Vector2(cx, sub_y), LABEL + 3, S.color("toxic").lerp(S.color("text"), 0.45), true, 5)


## V2 logo artwork (jaw as the W) with the BRUTSTAETTE rule below.
func _draw_logo_art(cx: float, baseline: float) -> void:
	var tex := UiArt.logo()
	var lw := 610.0
	var lh := lw * float(tex.get_height()) / float(tex.get_width())
	var rect := Rect2(cx - lw * 0.5, baseline + 20.0 - lh, lw, lh)
	if _on("under") and not S.is_calm():
		_glow(rect.get_center(), Vector2(lw * 0.62, lh * 0.9), Color(S.color("ember"), 0.16 + 0.04 * _pulse(1.2)))
	if _on("base"):
		_cv.draw_texture_rect(tex, Rect2(rect.position + Vector2(0, 7), rect.size), false, Color(0, 0, 0, 0.45))
		_cv.draw_texture_rect(tex, rect, false)
	if not _on("top"):
		return
	var sub := "BRUTSTÄTTE"
	var sub_y := baseline + 64.0
	if _spaced_sub == null:
		_spaced_sub = FontVariation.new()
		_spaced_sub.base_font = S.display_font()
		_spaced_sub.spacing_glyph = 6
	var sub_w := S.text(_cv, sub, Vector2(cx, sub_y), LABEL + 3, S.color("text_dim"), true, 4, _spaced_sub)
	UiFramesRef.rule(_cv, Vector2(cx, sub_y - 9), sub_w + 36.0 + 280.0, Color(S.color("panel_edge").lightened(0.3), 1.0), sub_w + 36.0, 1.0)


## Calm logo (V2): the word in light amber with a dark petrol extrusion and a
## slow glint, no jaws or glow; BRUTSTAETTE between two thin rules.
func _draw_logo_calm(cx: float, title: String, fs: int, baseline: float, w: float, face: Font) -> void:
	var origin := Vector2(cx - w * 0.5, baseline)
	if _on("base"):
		_cv.draw_string_outline(face, origin + Vector2(0, 7), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 14, Color(S.color("outline"), 0.8))
		_cv.draw_string_outline(face, origin, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 10, S.color("outline"))
		_cv.draw_string(face, origin + Vector2(0, 6), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("5c3322"))
	if _on("live"):
		var sweep := fposmod(_time * 0.3, 2.6) - 0.3
		var x := origin.x
		for i in title.length():
			var ch := title[i]
			var cw := face.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var k := clampf(1.0 - absf((x + cw * 0.5 - origin.x) / w - sweep) * 5.0, 0.0, 1.0)
			_cv.draw_string(face, Vector2(x, baseline), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, S.CALM_ORANGE_LIGHT.lerp(S.CALM_TEXT, k * 0.5))
			x += face.get_string_size(title.substr(0, i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x - (x - origin.x)
	if not _on("top"):
		return
	var sub := "BRUTSTÄTTE"
	var sub_y := baseline + 58.0
	if _spaced_sub == null:
		_spaced_sub = FontVariation.new()
		_spaced_sub.base_font = S.display_font()
		_spaced_sub.spacing_glyph = 6
	var sub_w := S.text(_cv, sub, Vector2(cx, sub_y), LABEL + 3, S.CALM_TEXT_DIM, true, 4, _spaced_sub)
	UiFramesRef.rule(_cv, Vector2(cx, sub_y - 9), sub_w + 36.0 + 280.0, Color(S.CALM_EDGE.lightened(0.3), 1.0), sub_w + 36.0, 1.0)


## A curved jaw band with teeth hanging (dir 1) or rising (dir -1) from it.
func _jaw(a: Vector2, ctrl: Vector2, b: Vector2, thick: float, gum: Color, dir: float, spots: Array, lengths: Array) -> void:
	var top := PackedVector2Array()
	var low := PackedVector2Array()
	for i in 21:
		var t := float(i) / 20.0
		var p := _bezier(a, ctrl, b, t)
		var taper := 0.45 + 0.55 * sin(t * PI)
		top.append(p - Vector2(0, thick * 0.5 * taper))
		low.append(p + Vector2(0, thick * 0.5 * taper))
	for i in spots.size():
		var t: float = spots[i]
		var p := _bezier(a, ctrl, b, t)
		var edge := p + Vector2(0, dir * thick * 0.35)
		var tip := edge + Vector2((0.5 - t) * 8.0, dir * float(lengths[i]))
		var half := 6.0 + float(lengths[i]) * 0.16
		_cv.draw_colored_polygon(PackedVector2Array([edge + Vector2(-half - 2, -dir * 2), edge + Vector2(half + 2, -dir * 2), tip + Vector2(0, dir * 3)]), S.color("outline"))
		_cv.draw_colored_polygon(PackedVector2Array([edge + Vector2(-half, 0), edge + Vector2(half, 0), tip]), S.color("bone"))
		_cv.draw_colored_polygon(PackedVector2Array([edge + Vector2(half * 0.1, 0), edge + Vector2(half, 0), tip]), S.color("bone").darkened(0.22))
	var band := top.duplicate()
	for i in range(low.size() - 1, -1, -1):
		band.append(low[i])
	_cv.draw_colored_polygon(band, S.color("outline"))
	var inner := PackedVector2Array()
	for i in top.size():
		inner.append(top[i].lerp(low[i], 0.2))
	for i in range(low.size() - 1, -1, -1):
		inner.append(low[i].lerp(top[i], 0.2))
	_fill_gradient(inner, gum.lightened(0.35), gum)
	_cv.draw_polyline(top, Color(S.color("bone"), 0.35), 2.0, true)
	# Bone knobs at the hinge.
	for p in [a, b]:
		_cv.draw_circle(p, thick * 0.75, S.color("outline"))
		_cv.draw_circle(p, thick * 0.55, S.color("bone").darkened(0.15))


func _draw_section(label: String, y: float) -> void:
	if not _on("top"):
		return
	_gem(Vector2(40, y - 8), 6, S.color("toxic"))
	var w := _txt(label, Vector2(54, y), LABEL, S.color("toxic").lerp(S.color("text"), 0.4), false, 4)
	var a := Vector2(66 + w, y - 8)
	var b := Vector2(size.x - 40, y - 8)
	_cv.draw_polygon(PackedVector2Array([a + Vector2(0, -1), b + Vector2(0, -1), b + Vector2(0, 1), a + Vector2(0, 1)]), PackedColorArray([Color(S.color("toxic"), 0.5), Color(S.color("toxic"), 0.0), Color(S.color("toxic"), 0.0), Color(S.color("toxic"), 0.5)]))

# ---------------------------------------------------------------- strain card

func _draw_strain() -> void:
	var id: String = menu.current_strain()
	var s: Dictionary = menu._strain(id)
	var owned: bool = menu._strain_owned(id)
	var unlocked: bool = menu._strain_unlocked(id)
	var tint: Color = menu._strain_color(id)
	var accent: Color = tint.lightened(0.35) if unlocked else S.color("text_dim").darkened(0.25)
	if id == "nachtmaul" and unlocked:
		accent = S.color("violet")
	var card: Rect2 = menu.strain_card_rect()
	var ox: float = menu._slide
	var cx := size.x * 0.5 + ox
	if _on("base"):
		if _frames != null:
			_frames.card(_cv, card, accent, "selected" if owned else ("normal" if unlocked else "disabled"))
		else:
			_panel(card, accent, S.color("panel"), 1.0 if unlocked else 0.4, 30.0, 12.0, 1 | 2, 3.5, true)
	# Stage: glowing ground disc under the pack (projected from the 3D camera).
	var ground := STAGE_GROUND
	var radius := Vector2(262, 52)
	if _camera != null and _viewport.size.x > 0:
		var front := _stage_point(Vector3(0, 0, 1.45))
		var back := _stage_point(Vector3(0, 0, -1.75))
		ground = Vector2(_stage_point(Vector3.ZERO).x, (front.y + back.y) * 0.5)
		radius = Vector2(_stage_point(Vector3(2.5, 0, -0.15)).x - ground.x, (front.y - back.y) * 0.5)
	ground.x += ox
	if _on("base"):
		_glow(ground + Vector2(0, -radius.y * 2.0), Vector2(radius.x * 1.25, radius.x * 0.85), Color(tint if unlocked else S.color("text_dim"), 0.3 if unlocked else 0.08))
		_ellipse(ground + Vector2(0, 5), radius.x + 8, radius.y + 6, Color(S.color("outline"), 0.75))
		_ellipse(ground, radius.x, radius.y, Color(S.color("panel_soft").lightened(0.05), 0.95))
		_glow(ground, radius * 0.9, Color(tint if unlocked else S.color("text_dim"), 0.22))
		var ring := PackedVector2Array()
		for i in 49:
			var a := TAU * i / 48.0
			ring.append(ground + Vector2(cos(a) * radius.x, sin(a) * radius.y))
		_cv.draw_polyline(ring, Color(accent, 0.55), 2.5, true)
	if _on("live"):
		for i in 14:
			var a := TAU * i / 14.0 + _time * 0.15
			var p := ground + Vector2(cos(a), sin(a)) * (radius - Vector2(20, 7))
			_diamond(p, 4.0, Color(accent, 0.3 + 0.4 * maxf(0.0, sin(a))))
		if use_3d and _viewport != null:
			for u in _pack:
				var node: Node3D = u.node
				var foot := _stage_point(Vector3(node.position.x, 0.0, node.position.z)) + Vector2(ox, 0)
				_glow(foot, Vector2(64, 16) * node.scale.x, Color(S.color("outline"), 0.85))
			# A ViewportTexture: the pack keeps moving without a repaint.
			_cv.draw_texture_rect(_viewport.get_texture(), Rect2(STAGE_RECT.position + Vector2(ox, 0), STAGE_RECT.size), false)
		elif UiArt.tribe(id) != null:
			_draw_portrait(UiArt.tribe(id), ground, radius, unlocked)
	if not _on("top"):
		return
	if (use_3d and _viewport != null) or UiArt.tribe(id) != null:
		pass
	else:
		var head := tint if unlocked else S.color("panel_edge")
		var ec := Vector2(cx, 470)
		_mawling_head(ec + Vector2(-80, -20), 56, head.darkened(0.3))
		_mawling_head(ec + Vector2(78, -28), 52, head.darkened(0.18))
		_mawling_head(ec + Vector2(0, 30), 84, head)
	if not unlocked:
		var lc := Vector2(cx, 470)
		_socket(lc, 46, S.color("text_dim"), 0.6)
		if not _icon(["lock"], Rect2(lc - Vector2(30, 30), Vector2(60, 60))):
			_lock(lc + Vector2(0, -2), 32, S.color("text"))
	_status_badge(card, id, owned, unlocked)
	# Name, then description + stat chips, or the unlock trophy with progress.
	var name := String(s.get("name", id)).to_upper()
	_txt(name, Vector2(cx, 674), 60, tint.lightened(0.3) if unlocked else S.color("text_dim"), true, 9)
	if unlocked:
		var lines := _wrap(String(s.get("description", "")), card.size.x - 100, 23)
		var y := 708.0 if lines.size() == 1 else 700.0
		for i in mini(2, lines.size()):
			_txt(lines[i], Vector2(cx, y + i * 27), 23, S.color("text").darkened(0.08), true, 4, true)
		_draw_chips(s, Rect2(card.position.x + 36 + ox, 740 if lines.size() == 1 else 746, card.size.x - 72, 42))
	else:
		_draw_unlock_quest(String(s.get("unlock_quest", "")), cx, card)
	_draw_arrows(accent)
	_draw_page_dots(card)


## Painted strain portrait standing on the ground disc, breathing slowly (LIVE).
## Locked strains show only a dark silhouette with a cold rim.
func _draw_portrait(tex: Texture2D, ground: Vector2, radius: Vector2, unlocked: bool) -> void:
	var breathe := 1.0 + 0.014 * sin(_time * 1.7)
	var height := 272.0 * breathe
	var foot := ground + Vector2(0, radius.y * 0.3)
	_glow(ground + Vector2(0, 4), Vector2(radius.x * 0.62, radius.y * 0.7), Color(S.color("outline"), 0.9))
	if unlocked:
		UiArt.draw_standing(_cv, tex, foot, height)
	else:
		UiArt.draw_standing(_cv, tex, foot + Vector2(0, -3), height, Color(S.color("text_dim"), 0.3))
		UiArt.draw_standing(_cv, tex, foot, height, Color(0.04, 0.07, 0.08, 0.96))


func _status_badge(card: Rect2, id: String, owned: bool, unlocked: bool) -> void:
	var text := "IM BESITZ"
	var color := S.color("toxic")
	if not unlocked:
		text = "GESPERRT"
		color = S.color("danger").lerp(S.color("text"), 0.35)
	elif not owned:
		text = "KAUFBAR · %d" % int(menu.profile.strain_cost(id))
		color = S.color("gold")
	var w := _tw(text, LABEL) + 58 + (26 if unlocked and not owned else 0)
	var badge := Rect2(card.position.x + 26, card.position.y + 22, w, 40)
	var shape := _rounded_points(badge, 20, 4)
	_cv.draw_colored_polygon(shape, Color(S.color("outline"), 0.9))
	_cv.draw_colored_polygon(_rounded_points(badge.grow(-3), 17, 4), Color(color, 0.16))
	_cv.draw_polyline(_closed(shape), Color(color, 0.7), 2.0, true)
	var ic := badge.position + Vector2(22, 20)
	if not unlocked:
		_lock(ic + Vector2(0, -1), 12, color)
	elif owned:
		_check(ic, 11, color)
	else:
		_gem(ic, 7, color)
	_txt(text, badge.position + Vector2(42, 28), LABEL, color, false, 4)
	if unlocked and not owned:
		var fc := badge.position + Vector2(badge.size.x - 24, 20)
		if not _icon(["crown_tooth"], Rect2(fc - Vector2(15, 15), Vector2(30, 30))):
			_fang(fc, 12, S.color("bone"))


func _draw_unlock_quest(quest_id: String, cx: float, card: Rect2) -> void:
	var q: Dictionary = menu.meta.quest(quest_id)
	var title := "TROPHÄE · %s" % String(q.get("name", quest_id)).to_upper()
	var tw := _tw(title, 24)
	_skull(Vector2(cx - tw * 0.5 - 20, 704), 12, S.color("gold"))
	_txt(title, Vector2(cx + 14, 714), 24, S.color("gold"), true, 5)
	_txt(String(q.get("description", "")), Vector2(cx, 744), LABEL + 1, S.color("text").darkened(0.1), true, 4, true)
	var progress: Vector2 = menu.profile.quest_progress(quest_id)
	var bar := Rect2(cx - 220, 762, 330, 18)
	_progress_bar(bar, clampf(progress.x / maxf(1.0, progress.y), 0.0, 1.0), S.color("gold"))
	_txt(menu._progress_text(q, progress), Vector2(bar.end.x + 16, bar.position.y + 17), LABEL, S.color("gold").lerp(S.color("text"), 0.4), false, 4)


func _progress_bar(rect: Rect2, fraction: float, color: Color) -> void:
	if S.is_calm():
		UiFramesRef.bar(_cv, rect.grow(2.0), fraction, color)
		return
	var back := _rounded_points(rect, rect.size.y * 0.5, 4)
	_cv.draw_colored_polygon(_rounded_points(rect.grow(3), rect.size.y * 0.5 + 3, 4), S.color("outline"))
	_cv.draw_colored_polygon(back, S.color("panel_edge").darkened(0.3))
	if fraction > 0.0:
		var fill := Rect2(rect.position, Vector2(maxf(rect.size.y, rect.size.x * minf(fraction, 1.0)), rect.size.y))
		_fill_gradient(_rounded_points(fill, rect.size.y * 0.5, 4), color.lightened(0.3), color.darkened(0.2))
		_cv.draw_line(fill.position + Vector2(rect.size.y * 0.5, 4), Vector2(fill.end.x - rect.size.y * 0.5, fill.position.y + 4), Color(1, 1, 1, 0.35), 2.0)


func _draw_chips(s: Dictionary, area: Rect2) -> void:
	var mods: Dictionary = s.get("mods", {})
	var sig: String = s.get("signature", "")
	var chips: Array = []
	chips.append({"kind": "start", "icon": "mawling_head_color", "text": "%d" % int(s.get("start_population", 25)), "color": S.color("ember_glow")})
	chips.append({"kind": "sig", "icon": sig, "text": String(menu.meta.MUTATION_NAMES.get(sig, sig)), "color": S.color("violet")})
	for pair in [["damage", "SCHADEN"], ["armor", "PANZER"], ["speed", "TEMPO"], ["growth", "WACHSTUM"], ["dna", "DNA"]]:
		var v := float(mods.get(pair[0], 0.0 if pair[0] == "armor" else 1.0))
		var delta := v * 100.0 if pair[0] == "armor" else (v - 1.0) * 100.0
		if absf(delta) >= 0.5:
			chips.append({"kind": "up" if delta > 0 else "down", "icon": "", "text": "%s %+d %%" % [pair[1], roundi(delta)], "color": S.color("toxic") if delta > 0 else S.color("danger").lerp(S.color("text"), 0.2)})
	if s.has("rally_damage"):
		chips.append({"kind": "up", "icon": "", "text": "RALLY %+d %%" % roundi((float(s.rally_damage) - 1.0) * 100.0), "color": S.color("toxic")})
	var fs := LABEL + 1
	var gap := 10.0
	var total := -gap
	for c in chips:
		c["w"] = _tw(c.text, fs) + 58.0
		total += c.w + gap
	if total > area.size.x:
		fs = LABEL
		total = -gap
		for c in chips:
			c["w"] = _tw(c.text, fs) + 50.0
			total += c.w + gap
	var x := area.position.x + maxf(0.0, (area.size.x - total) * 0.5)
	for c in chips:
		var r := Rect2(x, area.position.y, c.w, area.size.y)
		var shape := _rounded_points(r, 12, 3)
		_cv.draw_colored_polygon(_rounded_points(Rect2(r.position + Vector2(0, 4), r.size), 12, 3), S.color("shadow"))
		_fill_gradient(shape, S.color("panel_soft").lightened(0.06), S.color("panel").darkened(0.3))
		_cv.draw_polyline(_closed(shape), Color(c.color, 0.55), 2.0, true)
		var ic := r.position + Vector2(22, r.size.y * 0.5)
		if c.icon != "" and _icon([c.icon], Rect2(ic - Vector2(17, 17), Vector2(34, 34))):
			pass
		else:
			_chip_glyph(c.kind, ic, c.color)
		_txt(c.text, Vector2(r.position.x + 42, r.position.y + r.size.y * 0.5 + fs * 0.36), fs, S.color("text"), false, 4)
		x += c.w + gap


func _chip_glyph(kind: String, ic: Vector2, color: Color) -> void:
	match kind:
		"start":
			_mawling_head(ic + Vector2(-1, 2), 13, color)
		"sig":
			_claw(ic + Vector2(-6, 9), Vector2(0.35, -1), 20, 5, color, 0.35)
			_claw(ic + Vector2(2, 9), Vector2(0.35, -1), 20, 5, color, 0.35)
		"up":
			_cv.draw_colored_polygon(PackedVector2Array([ic + Vector2(0, -9), ic + Vector2(8, 5), ic + Vector2(-8, 5)]), color)
		"down":
			_cv.draw_colored_polygon(PackedVector2Array([ic + Vector2(0, 9), ic + Vector2(8, -5), ic + Vector2(-8, -5)]), color)


func _draw_arrows(accent: Color) -> void:
	# Stage 06: slim round knobs on the card's side edge instead of tall tabs;
	# the whole prev/next rect stays the hit area.
	for i in 2:
		var rect: Rect2 = menu.strain_prev_rect() if i == 0 else menu.strain_next_rect()
		var dir := -1.0 if i == 0 else 1.0
		var pressed: bool = menu.is_pressed(rect)
		var c := rect.get_center() + Vector2(dir * 6.0, 0.0) + (Vector2(0, 3) if pressed else Vector2.ZERO)
		var r := 30.0 * (0.94 if pressed else 1.0)
		if S.is_calm():
			# V2 round_button_base: small chamfered plate with a light rim.
			if not UiFramesRef.kit_at(_cv, "round_button_base", c, Vector2.ONE * r * 2.2, Color(0.8, 0.84, 0.82) if pressed else Color.WHITE):
				_cv.draw_colored_polygon(UiFramesRef.chamfer_points(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), r * 0.35), S.CALM_BG)
			_arrow(c + Vector2(dir * 3, 0), 22, dir, S.CALM_TEXT)
			continue
		_glow(c, Vector2(52, 52), Color(accent, 0.22 if pressed else 0.14))
		_cv.draw_circle(c + Vector2(0, 4), r + 3.0, Color(S.color("shadow"), 0.8))
		_cv.draw_circle(c, r + 3.0, S.color("outline"))
		_cv.draw_circle(c, r, S.color("panel").darkened(0.25))
		_cv.draw_circle(c + Vector2(0, -r * 0.2), r * 0.72, Color(accent, 0.12 if not pressed else 0.2))
		_cv.draw_arc(c, r, 0, TAU, 40, Color(S.color("bone"), 0.85), 2.5, true)
		_arrow(c + Vector2(dir * 3, 2), 26, dir, S.color("outline"))
		_arrow(c + Vector2(dir * 3, 0), 24, dir, S.color("bone"))


func _draw_page_dots(card: Rect2) -> void:
	var n: int = menu.strain_ids.size()
	var step := 40.0
	var y := card.end.y + 28.0
	# Faint rail so the dots read as one pager, not as loose sparkles.
	var half := (n - 1) * step * 0.5 + 18.0
	_cv.draw_line(Vector2(size.x * 0.5 - half, y), Vector2(size.x * 0.5 + half, y), Color(S.color("panel_edge"), 0.8), 2.0, true)
	for i in n:
		var p := Vector2(size.x * 0.5 + (i - (n - 1) * 0.5) * step, y)
		var other: String = menu.strain_ids[i]
		var open: bool = menu._strain_unlocked(other)
		var color: Color = menu._strain_color(other).lightened(0.3) if open else S.color("panel_edge").lightened(0.25)
		if i == menu.strain_index:
			if not S.is_calm():
				_glow(p, Vector2(30, 30), Color(color, 0.55))
			_gem(p, 12, color)
		elif open:
			_gem(p, 8, Color(color, 0.9))
		else:
			_gem(p, 7, Color(color, 0.8))
			_lock(p + Vector2(0, 1), 5, Color(S.color("outline"), 0.9))

# ---------------------------------------------------------------- biomes

func _draw_biomes() -> void:
	for i in menu.meta.BIOME_ORDER.size():
		var id: String = menu.meta.BIOME_ORDER[i]
		var b: Dictionary = menu.meta.BIOMES[id]
		var rect: Rect2 = menu.biome_rect(i)
		var locked: bool = b.get("locked", false)
		var selected: bool = id == menu.biome_id
		var accent: Color = S.color("toxic") if id == "verdant_maw" else S.color("ember")
		var edge: Color = accent if selected else Color(accent, 0.45)
		if locked:
			edge = Color(S.color("text_dim"), 0.35)
		if _on("base"):
			_panel(rect, edge, S.color("panel"), 0.9 if selected else 0.0, 18.0, 0.0, 0, 3.5 if selected else 2.0)
		_paint_biome(id, rect.grow(-5))
		if not _on("top"):
			continue
		# Readability scrim behind the text on the left.
		var scrim := Rect2(rect.position + Vector2(5, 5), Vector2(rect.size.x * 0.62, rect.size.y - 10))
		var dark := Color(S.color("outline"), 0.85)
		var clear := Color(S.color("outline"), 0.0)
		_cv.draw_polygon(PackedVector2Array([scrim.position + Vector2(8, 0), Vector2(scrim.end.x, scrim.position.y), scrim.end, Vector2(scrim.position.x + 8, scrim.end.y)]), PackedColorArray([dark, clear, clear, dark]))
		if locked:
			_cv.draw_colored_polygon(_shape(rect.grow(-5), 13.0), Color(S.color("outline"), 0.5))
		# Redraw the rim over the painting.
		_cv.draw_polyline(_closed(_shape(rect, 18.0)), edge, 3.5 if selected else 2.0, true)
		var tx := rect.position.x + 24
		_txt(String(b.name).to_upper(), Vector2(tx, rect.position.y + 50), 29, S.color("text") if not locked else S.color("text_dim"), false, 6)
		if locked:
			var status := String(b.get("status", "")).to_upper()
			var pill := Rect2(tx, rect.position.y + 64, _tw(status, LABEL) + 52, 34)
			_cv.draw_colored_polygon(_rounded_points(pill, 17, 4), Color(S.color("ember").darkened(0.55), 0.95))
			_cv.draw_polyline(_closed(_rounded_points(pill, 17, 4)), Color(S.color("ember"), 0.6), 2.0, true)
			_lock(pill.position + Vector2(20, 16), 10, S.color("ember_glow"))
			_txt(status, pill.position + Vector2(36, 25), LABEL, S.color("ember_glow"), false, 3)
		elif selected:
			_check(Vector2(tx + 10, rect.position.y + 80), 10, accent)
			_txt("GEWÄHLT", Vector2(tx + 28, rect.position.y + 88), LABEL, accent.lerp(S.color("text"), 0.3), false, 4)
		else:
			_txt("ANTIPPEN", Vector2(tx, rect.position.y + 88), LABEL, S.color("text_dim"), false, 4)


## Small painted landscape inside a biome tile (stays inside `r`).
func _paint_biome(id: String, r: Rect2) -> void:
	var cut := 13.0
	var verdant := id == "verdant_maw"
	var card := UiArt.biome(id)
	if card != null:
		# V2 biome card, cropped to the tile band (Glutsumpf: the lava river).
		if _on("base"):
			UiArt.draw_cover(_cv, card, _shape(r, cut), r, Color.WHITE, Vector2(0.5, 0.55 if verdant else 0.62))
		return
	var sky_top: Color = S.color("cyan").darkened(0.55) if verdant else S.color("danger").darkened(0.7)
	var sky_low: Color = S.color("toxic").darkened(0.45) if verdant else S.color("ember").darkened(0.45)
	var far: Color = S.color("toxic").darkened(0.55) if verdant else S.color("outline").lerp(S.color("danger"), 0.25)
	var near: Color = S.color("toxic").darkened(0.35) if verdant else S.color("outline")
	var ox := r.position.x
	var oy := r.position.y
	if _on("base"):
		_fill_gradient(_shape(r, cut), sky_top, sky_low)
		_hill(r, cut, 0.45, 0.10, 2.3, 0.7, far)
		_hill(r, cut, 0.66, 0.08, 3.1, 2.1, near)
	# Verdant is still (BASE); the Glutsumpf lava pulses (LIVE).
	if (verdant and not _on("base")) or (not verdant and not _on("live")):
		return
	if verdant:
		_glow(Vector2(r.end.x - 70, oy + 26), Vector2(70, 40), Color(S.color("text"), 0.18))
		_ellipse(Vector2(r.end.x - 110, r.end.y - 22), 42, 9, S.color("cyan").darkened(0.2))
		_ellipse(Vector2(r.end.x - 116, r.end.y - 24), 22, 4, Color(S.color("text"), 0.4))
		_leaf(Vector2(r.end.x - 20, r.end.y - 4), 56, 16, -2.2, S.color("toxic").darkened(0.1))
		_leaf(Vector2(r.end.x - 10, r.end.y - 20), 50, 14, -2.8, S.color("toxic").darkened(0.3))
		_leaf(Vector2(r.end.x - 170, r.end.y - 2), 44, 12, -1.2, S.color("toxic").darkened(0.2))
		for k in 3:
			var p := Vector2(r.end.x - 190 + k * 26, r.end.y - 36 - (k % 2) * 6)
			_mawling_head(p, 9, S.color("ember"))
	else:
		for k in 4:
			var p := Vector2(r.end.x - 60 - k * 46, r.end.y - 18 - (k % 2) * 8)
			var pulse := 0.5 + 0.5 * sin(_time * 2.0 + k)
			_glow(p, Vector2(40, 16), Color(S.color("ember"), 0.35 + 0.2 * pulse))
			_ellipse(p, 20, 5, S.color("ember_glow"))
			_cv.draw_circle(p + Vector2(4, -10 - 10 * pulse), 3.0, Color(S.color("ember_glow"), 0.8))
		for k in 2:
			var base := Vector2(r.end.x - 70 - k * 110, r.end.y - 20)
			_cv.draw_line(base, base + Vector2(6, -58), S.color("outline"), 5.0, true)
			_cv.draw_line(base + Vector2(4, -36), base + Vector2(22, -50), S.color("outline"), 3.0, true)
			_cv.draw_line(base + Vector2(5, -44), base + Vector2(-12, -58), S.color("outline"), 3.0, true)


func _hill(r: Rect2, cut: float, level: float, amp: float, freq: float, phase: float, color: Color) -> void:
	var points := PackedVector2Array()
	var steps := 16
	for i in steps + 1:
		var t := float(i) / steps
		var x := r.position.x + r.size.x * t
		var y := r.position.y + r.size.y * (level - amp * sin(t * freq * PI + phase))
		if t == 0.0:
			y = maxf(y, r.position.y + cut)
		points.append(Vector2(x, y))
	points.append(Vector2(r.end.x, r.end.y - cut))
	points.append(Vector2(r.end.x - cut * 0.3, r.end.y - cut * 0.3))
	points.append(Vector2(r.end.x - cut, r.end.y))
	points.append(Vector2(r.position.x + cut, r.end.y))
	points.append(Vector2(r.position.x + cut * 0.3, r.end.y - cut * 0.3))
	points.append(Vector2(r.position.x, r.end.y - cut))
	_cv.draw_colored_polygon(points, color)

# ---------------------------------------------------------------- difficulty

func _draw_difficulties() -> void:
	if not _on("top"):
		return
	for i in menu.meta.DIFFICULTIES.size():
		var d: Dictionary = menu.meta.DIFFICULTIES[i]
		var rect: Rect2 = menu.difficulty_rect(i)
		var unlocked: bool = menu._difficulty_unlocked(i)
		var selected: bool = i == menu.difficulty
		var accent: Color = menu.DIFFICULTY_COLORS[i] if unlocked else S.color("text_dim").darkened(0.2)
		var fill := S.color("panel").lerp(accent, 0.16) if selected else S.color("panel")
		_panel(rect, accent if selected else Color(accent, 0.45), fill, 0.9 if selected else 0.0, 16.0, 0.0, 0, 3.5 if selected else 2.0)
		var c := rect.get_center()
		var name := String(d.name).to_upper()
		if unlocked:
			var n: int = i + 1
			if selected and not S.is_calm():
				_glow(Vector2(c.x, rect.position.y + 32), Vector2(30 + n * 20, 30), Color(accent, 0.45))
			if not _icon([["diff_wild", "diff_brutal", "diff_apex"][i]], Rect2(c.x - 29, rect.position.y + 2, 58, 58)):
				for k in n:
					var p := Vector2(c.x + (k - (n - 1) * 0.5) * 34.0, rect.position.y + 32)
					_skull(p + Vector2(0, 2), 15, S.color("outline"))
					_skull(p, 14, accent.lerp(S.color("bone"), 0.25))
			_txt(name, Vector2(c.x, rect.position.y + 75), 30, S.color("text") if selected else S.color("text").darkened(0.15), true, 6)
			var reward := "×%.1f ESSENZ" % float(d.get("reward", 1.0))
			var rw := _tw(reward, LABEL) + 26.0
			var ec := Vector2(c.x - rw * 0.5 + 10, rect.position.y + 90)
			if not _icon(["essence"], Rect2(ec - Vector2(12, 12), Vector2(24, 24))):
				_essence_drop(ec, 8, S.color("violet"))
			_txt(reward, Vector2(c.x - rw * 0.5 + 26, rect.position.y + 97), LABEL, S.color("violet").lerp(S.color("text"), 0.45), false, 4)
		else:
			_cv.draw_colored_polygon(_shape(rect.grow(-4), 12.0), Color(S.color("outline"), 0.35))
			_lock(Vector2(c.x, rect.position.y + 30), 15, S.color("text_dim"))
			_txt(name, Vector2(c.x, rect.position.y + 72), 28, S.color("text_dim"), true, 5)
			var q: Dictionary = menu.meta.quest(d.get("unlock_quest", ""))
			_txt(String(q.get("name", "")), Vector2(c.x, rect.position.y + 96), LABEL, S.color("gold").darkened(0.1), true, 4)

# ---------------------------------------------------------------- main button

func _draw_play() -> void:
	var rect: Rect2 = menu.play_rect()
	# Pressed: the button sinks a little and loses some of its glow.
	if menu.is_pressed(rect):
		rect = Rect2(rect.position + Vector2(0, 4), rect.size).grow(-3)
	var id: String = menu.current_strain()
	var owned: bool = menu._strain_owned(id)
	var unlocked: bool = menu._strain_unlocked(id)
	var c := rect.get_center()
	if owned:
		var ok: bool = menu.can_play()
		_button(rect, S.color("ember") if ok else S.color("text_dim").darkened(0.3), ok)
		var label := "SPIELEN"
		var fs := 74
		var w := _tw(label, fs)
		var head_c := c + Vector2(-w * 0.5 - 20, -2)
		if _on("top") and not _icon(["mawling_head"], Rect2(head_c - Vector2(40, 40), Vector2(80, 80))):
			_mawling_head(head_c + Vector2(0, 3), 34, S.color("outline"))
			_mawling_head(head_c, 33, S.color("bone"))
		if _on("top"):
			_txt(label, c + Vector2(22, 26), fs, S.color("text"), true, 10)
	elif unlocked:
		var price := int(menu.profile.strain_cost(id))
		var affordable: bool = int(menu.profile.crowns) >= price
		_button(rect, S.color("amber").darkened(0.2) if affordable else S.color("text_dim").darkened(0.35), affordable, S.color("gold") if affordable else Color(0, 0, 0, 0))
		var label := "KAUFEN  %d" % price
		var fs := 60
		var w := _tw(label, fs)
		if not _on("top"):
			return
		_txt(label, c + Vector2(-24, 12), fs, S.color("text") if affordable else S.color("text_dim"), true, 9)
		var fc := c + Vector2(w * 0.5 + 6, -8)
		if not _icon(["crown_tooth"], Rect2(fc - Vector2(30, 30), Vector2(60, 60))):
			_fang(fc, 24, S.color("bone"))
		_txt("KÖNIGSZÄHNE" if affordable else "ZU WENIGE KÖNIGSZÄHNE", c + Vector2(0, 48), LABEL, S.color("text") if affordable else S.color("gold").lerp(S.color("text_dim"), 0.4), true, 5)
	else:
		_button(rect, S.color("text_dim").darkened(0.4), false)
		var fs := 56
		var w := _tw("GESPERRT", fs)
		if not _on("top"):
			return
		_lock(c + Vector2(-w * 0.5 - 16, -12), 22, S.color("text_dim"))
		_txt("GESPERRT", c + Vector2(22, 8), fs, S.color("text_dim"), true, 8)
		var q: Dictionary = menu.meta.quest(menu._strain(id).get("unlock_quest", ""))
		_txt("Trophäe: " + String(q.get("name", "")), c + Vector2(0, 46), LABEL, S.color("gold"), true, 5)
	if not _on("top"):
		return
	# All-time record line under the daily row (the next trophy lives in TROPHÄEN).
	var best := float(menu.profile.records.get("best_seconds", 0.0))
	var peak := int(menu.profile.records.get("best_peak", 0))
	# Stage 10: the line is a quiet pill that opens the CHRONIK (hit area menu.records_rect()).
	var rec: Rect2 = menu.records_rect()
	var rec_down: bool = menu.is_pressed(rec)
	var pill := rec.grow_individual(0, -3, 0, -3)
	if pill.size.x < 8.0 or pill.size.y < 8.0:
		return
	if rec_down:
		pill.position.y += 2
	_cv.draw_colored_polygon(_rounded_points(pill, pill.size.y * 0.5, 5), Color(S.color("violet"), 0.16) if rec_down else Color(S.color("outline"), 0.45))
	var pill_edge := _rounded_points(pill, pill.size.y * 0.5, 5)
	pill_edge.append(pill_edge[0])
	_cv.draw_polyline(pill_edge, Color(S.color("violet"), 0.45), 1.5, true)
	var more := "CHRONIK"
	var wm := _tw(more, LABEL)
	_txt(more, Vector2(pill.end.x - 44 - wm, pill.get_center().y + 8), LABEL, S.color("violet").lerp(S.color("text"), 0.35), false, 4)
	_arrow(Vector2(pill.end.x - 26, pill.get_center().y), 11, 1.0, S.color("violet").lerp(S.color("text"), 0.35))
	var ry: float = pill.get_center().y + 8.0
	var part_a := "REKORD %02d:%02d" % [int(best) / 60, int(best) % 60]
	var part_b := "MAX. SCHWARM %d" % peak
	var wa := _tw(part_a, LABEL)
	var x := pill.position.x + 24.0
	_cv.draw_arc(Vector2(x + 10, ry - 8), 10, 0, TAU, 20, S.color("text_dim"), 2.5, true)
	_cv.draw_line(Vector2(x + 10, ry - 8), Vector2(x + 10, ry - 14), S.color("text_dim"), 2.0)
	_cv.draw_line(Vector2(x + 10, ry - 8), Vector2(x + 15, ry - 6), S.color("text_dim"), 2.0)
	_txt(part_a, Vector2(x + 26, ry), LABEL, S.color("text").darkened(0.12), false, 4)
	_gem(Vector2(x + 26 + wa + 23, ry - 8), 4, S.color("text_dim"))
	_mawling_head(Vector2(x + 26 + wa + 46 + 10, ry - 8), 11, S.color("ember_glow"))
	_txt(part_b, Vector2(x + 26 + wa + 46 + 26, ry), LABEL, S.color("text").darkened(0.12), false, 4)


## TAGES-BRUT: secondary gold button with a sun glyph and today's record.
func _draw_daily() -> void:
	var rect: Rect2 = menu.daily_rect()
	var ok: bool = menu.can_play_daily()
	var pressed: bool = ok and menu.is_pressed(rect)
	if _on("base"):
		if _frames != null:
			_frames.button(_cv, rect, "secondary", pressed)
			var inner := rect.grow(-8)
			if pressed:
				inner.position.y += 3
			_fill_gradient(_rounded_points(inner, 14, 4), Color(S.color("gold"), (0.4 if pressed else 0.22) if ok else 0.06), Color(S.color("gold"), 0.03))
		else:
			_panel(rect, S.color("gold") if ok else S.color("text_dim"), S.color("panel"), 0.4 if ok else 0.0, 16.0, 0.0, 0, 2.5)
	var off := Vector2(0, 3) if pressed else Vector2.ZERO
	var sun := rect.position + Vector2(46, rect.size.y * 0.5) + off
	var sun_c: Color = S.color("gold") if ok else S.color("text_dim")
	_draw_sun(sun, sun_c, ok)
	if not _on("top"):
		return
	var x := rect.position.x + 84

	_txt("TAGES-BRUT", Vector2(x, rect.position.y + 44) + off, 32, S.color("text") if ok else S.color("text_dim"), false, 6)
	var today: Dictionary = menu.daily_today()
	var line := "Heute noch offen · Wild"
	var color: Color = S.color("gold").lerp(S.color("text"), 0.35)
	if not today.is_empty():
		var t := float(today.get("seconds", 0.0))
		line = "Heute: %02d:%02d · Peak %d" % [int(t) / 60, int(t) % 60, int(today.get("peak", 0))]
		color = S.color("gold")
	if not today.is_empty() and _tw(line, LABEL) > rect.end.x - 12.0 - x:
		var t2 := float(today.get("seconds", 0.0))
		line = "%02d:%02d · Peak %d" % [int(t2) / 60, int(t2) % 60, int(today.get("peak", 0))]
	_txt(line, Vector2(x, rect.position.y + 76) + off, LABEL, color if ok else S.color("text_dim"), false, 4)


## Sun glyph of TAGES-BRUT: pulsing glow, turning rays (LIVE phase).
func _draw_sun(sun: Vector2, sun_c: Color, ok: bool) -> void:
	if not _on("live"):
		return
	if ok:
		_glow(sun, Vector2(40, 40), Color(S.color("gold"), 0.25 + 0.1 * _pulse(1.4)))
	for i in 10:
		var a := TAU * i / 10.0 + _time * 0.2
		var d := Vector2(cos(a), sin(a))
		var tip := sun + d * 27.0
		var side := d.orthogonal() * 4.5
		_cv.draw_colored_polygon(PackedVector2Array([sun + d * 15.0 + side, tip, sun + d * 15.0 - side]), sun_c.darkened(0.1))
	_cv.draw_circle(sun, 16, S.color("outline"))
	_cv.draw_circle(sun, 13, sun_c)
	_cv.draw_circle(sun + Vector2(-4, -4), 4, Color(1, 1, 1, 0.45))


## Dominant glowing button with fang tips, gradient body, bevel and a moving shine.
func _button(rect: Rect2, color: Color, live: bool, top: Color = Color(0, 0, 0, 0)) -> void:
	if S.is_calm():
		_button_calm(rect, color, live)
		return
	var c := rect.get_center()
	var tip := 46.0
	if live and _on("under"):
		_glow(c, Vector2(rect.size.x * 0.66, rect.size.y * 1.05), Color(color, 0.3 + 0.18 * _pulse(2.2)))
	var shape := _button_shape(rect, tip)
	if _on("base"):
		_button_body(rect, shape, tip, color, live, top)
	if live and _on("live"):
		var sweep := fposmod(_time * 0.5, 2.6)
		if sweep < 1.0:
			var sx := lerpf(rect.position.x + tip + 10, rect.end.x - tip - 60, sweep)
			var y0 := rect.position.y + 6
			var y1 := rect.end.y - 6
			_cv.draw_colored_polygon(PackedVector2Array([Vector2(sx + 30, y0), Vector2(sx + 58, y0), Vector2(sx + 28, y1), Vector2(sx, y1)]), Color(1, 1, 1, 0.16 * sin(sweep * PI)))
	if not _on("top"):
		return
	_cv.draw_polyline(_closed(shape), color.lightened(0.5) if live else color, 3.0, true)
	# Bone claws hooking out of both tips.
	for side in [-1.0, 1.0]:
		var base := Vector2(c.x + side * (rect.size.x * 0.5 - 4), c.y)
		_claw(base + Vector2(0, 2), Vector2(side, -0.9), 36, 9, S.color("outline"), -0.5 * side)
		_claw(base, Vector2(side, -0.9), 34, 8, S.color("bone"), -0.5 * side)
		_claw(base + Vector2(0, 8), Vector2(side, 0.8), 24, 6, S.color("bone").darkened(0.2), 0.4 * side)


## Calm SPIELEN (V2 button_primary): chamfered burnt-orange body, light amber
## stroke, one highlight line; a slow soft shine is the only motion.
func _button_calm(rect: Rect2, color: Color, live: bool) -> void:
	var shape := UiFramesRef.chamfer_points(rect, 26.0)
	var hot := color.is_equal_approx(S.color("ember"))
	var body: Color = Color("b9653b") if hot else S.tone(color).darkened(0.1)
	var edge: Color = S.CALM_ORANGE_LIGHT if hot else (S.tone(color).lightened(0.35) if live else S.tone(color).lightened(0.1))
	if _on("base"):
		_cv.draw_colored_polygon(UiFramesRef.chamfer_points(Rect2(rect.position + Vector2(0, 8), rect.size), 26.0), S.color("shadow"))
		_fill_gradient(shape, body.lightened(0.12), body.darkened(0.18))
		_cv.draw_line(Vector2(rect.position.x + 28, rect.position.y + 14), Vector2(rect.end.x - 28, rect.position.y + 14), Color("ffe3b880") if live else Color(1, 1, 1, 0.12), 2.5, true)
		_cv.draw_line(Vector2(rect.position.x + 28, rect.end.y - 12), Vector2(rect.end.x - 28, rect.end.y - 12), Color("6e321c73"), 2.5, true)
	if live and _on("live"):
		var sweep := fposmod(_time * 0.4, 3.0)
		if sweep < 1.0:
			var sx := lerpf(rect.position.x + 40, rect.end.x - 100, sweep)
			var y0 := rect.position.y + 6
			var y1 := rect.end.y - 6
			_cv.draw_colored_polygon(PackedVector2Array([Vector2(sx + 30, y0), Vector2(sx + 52, y0), Vector2(sx + 22, y1), Vector2(sx, y1)]), Color(1, 1, 1, 0.1 * sin(sweep * PI)))
	if _on("top"):
		_cv.draw_polyline(_closed(shape), edge, 3.5, true)


func _button_body(rect: Rect2, shape: PackedVector2Array, tip: float, color: Color, live: bool, top: Color) -> void:
	_cv.draw_colored_polygon(_button_shape(Rect2(rect.position + Vector2(0, 10), rect.size), tip), S.color("shadow"))
	_cv.draw_colored_polygon(_button_shape(rect.grow(7), tip + 4), S.color("outline"))
	if live:
		_cv.draw_colored_polygon(_button_shape(rect.grow(4), tip + 2), color.lightened(0.45))
	# Three-stop gradient: the upper and lower halves are filled separately.
	var top_c: Color = (S.color("ember_glow") if color == S.color("ember") else color.lightened(0.35)) if live else color.lightened(0.05)
	if top.a > 0.0:
		top_c = top
	var n := shape.size() / 2
	var upper := shape.slice(0, n + 1)
	var lower := shape.slice(n, shape.size())
	lower.append(shape[0])
	_fill_gradient(upper, top_c, color)
	_fill_gradient(lower, color, color.darkened(0.55))
	# Bevel: soft light over the upper half, dark lip at the bottom.
	var bevel := _button_shape(Rect2(rect.position + Vector2(18, 8), Vector2(rect.size.x - 36, rect.size.y * 0.42)), tip * 0.55)
	_cv.draw_colored_polygon(bevel, Color(1, 1, 1, 0.13 if live else 0.05))


func _button_shape(rect: Rect2, tip: float) -> PackedVector2Array:
	var cy := rect.get_center().y
	var p := PackedVector2Array()
	p.append(Vector2(rect.position.x, cy))
	for i in 9:
		p.append(Vector2(lerpf(rect.position.x + tip, rect.end.x - tip, i / 8.0), rect.position.y))
	p.append(Vector2(rect.end.x, cy))
	for i in 9:
		p.append(Vector2(lerpf(rect.end.x - tip, rect.position.x + tip, i / 8.0), rect.end.y))
	return p


# ---------------------------------------------------------------- tabs

func _draw_tabs() -> void:
	var first: Rect2 = menu.tab_rect(0)
	var dock := Rect2(0, first.position.y - 8, size.x, size.y - first.position.y + 8)
	if _on("base"):
		_fill_gradient(PackedVector2Array([dock.position, Vector2(dock.end.x, dock.position.y), dock.end, Vector2(dock.position.x, dock.end.y)]), Color(S.color("outline"), 0.55), Color(S.color("outline"), 0.95))
		_cv.draw_line(dock.position, Vector2(dock.end.x, dock.position.y), Color(S.color("panel_edge"), 0.9), 2.0)
	var names: Dictionary = menu.TAB_NAMES
	var accents := [S.color("cyan"), S.color("gold"), S.color("ember"), S.color("violet")]
	for i in menu.TABS.size():
		var id: String = menu.TABS[i]
		var rect: Rect2 = menu.tab_rect(i)
		var active: bool = menu.tab == id
		var accent: Color = accents[i]
		var fill := S.color("panel").lerp(accent, 0.14) if active else S.color("panel")
		var ic := Vector2(rect.get_center().x, rect.position.y + 42)
		if _on("base"):
			_panel(rect, accent if active else Color(accent, 0.45), fill, 1.0 if active else 0.0, 18.0, 0.0, (1 | 2) if active else 0, 3.0 if active else 2.0)
			if active and not S.is_calm():
				_glow(ic, Vector2(56, 40), Color(accent, 0.4))
		if _on("top"):
			if not _icon([["brood"], ["trophy"], ["mawling_head_color"], ["clock"]][i], Rect2(ic - Vector2(32, 32), Vector2(64, 64))):
				_tab_icon(id, ic, accent)
			_txt(String(names[id]), Vector2(rect.get_center().x, rect.position.y + 96), LABEL + 1, S.color("text") if active else S.color("text").darkened(0.15), true, 5)
		var badge := ""
		if id == "upgrades":
			var n: int = menu._affordable_upgrades()
			badge = "%d" % n if n > 0 else ""
		elif id == "instinct" and int(menu.profile.essence) >= int(menu._instinct_cost()):
			badge = "!"
		if badge != "" and not active and _on("live"):
			var bc := Vector2(rect.end.x - 20, rect.position.y + 18)
			var pop := 1.0 + 0.08 * _pulse(3.0)
			_cv.draw_circle(bc, 19 * pop, S.color("outline"))
			_cv.draw_circle(bc, 16 * pop, S.color("danger"))
			_cv.draw_circle(bc + Vector2(-4, -5), 5, Color(1, 1, 1, 0.3))
			_txt(badge, bc + Vector2(0, 8), LABEL, S.color("text"), true, 3)


func _tab_icon(id: String, c: Vector2, accent: Color) -> void:
	match id:
		"upgrades":
			# Three brood eggs in a nest.
			_ellipse(c + Vector2(0, 17), 30, 8, S.color("panel_edge").darkened(0.2))
			for e in [[Vector2(-15, 4), 0.95], [Vector2(15, 4), 0.95], [Vector2(0, -6), 1.1]]:
				var p: Vector2 = c + e[0]
				var k: float = e[1]
				_ellipse(p + Vector2(0, 2), 12 * k, 16 * k, S.color("outline"))
				_ellipse(p, 11 * k, 15 * k, accent)
				_cv.draw_circle(p + Vector2(-3, -5) * k, 3 * k, Color(1, 1, 1, 0.45))
				_cv.draw_circle(p + Vector2(4, 4) * k, 2.2 * k, accent.darkened(0.45))
				_cv.draw_circle(p + Vector2(-4, 6) * k, 1.6 * k, accent.darkened(0.45))
		"trophies":
			_skull(c + Vector2(0, 8), 18, S.color("outline"))
			_skull(c + Vector2(0, 6), 17, S.color("bone"))
			_crown(c + Vector2(0, -15), 12, accent)
		_:
			_mawling_head(c + Vector2(0, 3), 26, S.color("outline"))
			_mawling_head(c, 25, accent)


# ================================================================ brawl skin (stage 15)
# Supercell-style main view drawn only with ui_kit_brawl.gd and UiStyle tokens.
# Same phases as above: BASE (cached frames), LIVE (portrait breathing, glows),
# TOP (cached plates, icons, text). The organic/calm drawing stays untouched.

const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")
const TAB_TONES := ["info", "loot", "ember", "special"]
const TAB_ICONS := ["brood", "trophy", "instinct", "clock"]
const STRAIN_HEADER := 74.0
const PORTRAIT_H := 288.0


func _paint_brawl() -> void:
	if menu.profile == null:
		_b_logo(560.0)
		return
	_b_header()
	if menu.tab == "":
		_b_logo(104.0)
		_b_strain()
		_b_biomes()
		_b_difficulties()
		_b_play()
		_b_daily()
		_b_records()
	_b_tabs()


# ---------------------------------------------------------------- small helpers

func _b_text(pos: Vector2, value: String, font_size: int, color: Color = Color.WHITE, align: int = Kit.LEFT, max_w: float = 0.0, font: Font = null) -> float:
	return Kit.text_outlined(_cv, pos, value, font_size, color, -1, -1, font, align, max_w)


func _b_icon(id: String, center: Vector2, side: float, tint: Color = Color.WHITE) -> bool:
	if _icons == null or not _icons.has(id):
		return false
	_icons.draw(_cv, id, Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side)), tint)
	return true


func _b_light(tone: Variant) -> Color:
	return Kit.DISABLED["light"] if (tone is String and tone == "disabled") else S.brawl_tone(tone)["light"]


func _b_dark(tone: Variant) -> Color:
	return Kit.DISABLED["dark"] if (tone is String and tone == "disabled") else S.brawl_tone(tone)["dark"]


## Dark body inside a Kit.card (frame band excluded).
func _b_body(rect: Rect2, header: float = 0.0) -> Rect2:
	var inset := S.STROKE_L + 7.0
	return Rect2(rect.position + Vector2(inset, inset + header), rect.size - Vector2(inset * 2.0, inset * 2.0 + header))


func _b_body_radius(radius: float) -> float:
	return maxf(radius - S.STROKE_L - 7.0, 4.0)


func _b_ellipse_points(c: Vector2, rx: float, ry: float, n: int = 40) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _b_check(c: Vector2, r: float) -> void:
	var pts := PackedVector2Array([c + Vector2(-0.62, 0.02) * r, c + Vector2(-0.16, 0.46) * r, c + Vector2(0.66, -0.44) * r])
	_cv.draw_polyline(pts, S.BRAWL_INK, maxf(6.0, r * 0.5), true)
	_cv.draw_polyline(pts, Color.WHITE, maxf(3.0, r * 0.26), true)


## Solid white arrow head with an ink rim (dir -1 left, 1 right).
func _b_arrow(c: Vector2, r: float, dir: float) -> void:
	var pts := PackedVector2Array([c + Vector2(dir * 0.6, 0.0) * r, c + Vector2(-dir * 0.4, -0.72) * r, c + Vector2(-dir * 0.4, 0.72) * r])
	_cv.draw_colored_polygon(pts, Color.WHITE)
	pts.append(pts[0])
	_cv.draw_polyline(pts, S.BRAWL_INK, 5.0, true)


func _b_gear_glyph(c: Vector2, r: float) -> void:
	for pass_i in 2:
		var k := 1.16 if pass_i == 0 else 1.0
		var pts := PackedVector2Array()
		for i in 32:
			var a := TAU * i / 32.0 + 0.2
			var outer := i % 4 == 1 or i % 4 == 2
			pts.append(c + Vector2(cos(a), sin(a)) * r * (1.0 if outer else 0.74) * k)
		_cv.draw_colored_polygon(pts, S.BRAWL_INK if pass_i == 0 else Color.WHITE)
	Kit.disc(_cv, c, r * 0.3, S.BRAWL_INK)


func _b_sun_glyph(c: Vector2, r: float) -> void:
	for pass_i in 2:
		for i in 8:
			var a := TAU * i / 8.0 + PI / 8.0
			var d := Vector2(cos(a), sin(a))
			var side := d.orthogonal() * r * (0.24 if pass_i == 0 else 0.15)
			var tip := c + d * r * (1.08 if pass_i == 0 else 1.0)
			_cv.draw_colored_polygon(PackedVector2Array([c + d * r * 0.5 + side, tip, c + d * r * 0.5 - side]), S.BRAWL_INK if pass_i == 0 else Color.WHITE)
	Kit.disc(_cv, c, r * 0.58, S.BRAWL_INK)
	Kit.disc(_cv, c, r * 0.58 - 3.0, S.brawl_tone("loot")["light"])
	Kit.fade_disc(_cv, c, r * 0.58 - 3.0, Color.WHITE, 0.0, 0.5)


# ---------------------------------------------------------------- background

func _b_paint_sky() -> void:
	var full := Rect2(Vector2.ZERO, size)
	var quad := PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	var painted := UiArt.menu_background()
	if painted != null:
		UiArt.draw_cover(_cv, painted, quad, full, Color(0.72, 0.74, 0.8))
	else:
		_fill_gradient(quad, S.BRAWL_PANEL_TOP, S.BRAWL_PANEL_BOTTOM)
	# Blue-violet veil so the saturated widgets carry.
	_cv.draw_rect(full, Color(S.BRAWL_PANEL_BOTTOM, 0.28))
	var tint: Color = S.brawl_tone("ember")["face"]
	if menu != null and menu.profile != null:
		tint = menu._strain_color(menu.current_strain()) if menu._strain_unlocked(menu.current_strain()) else S.BRAWL_TEXT_DIM
	_glow(Vector2(size.x * 0.5, 470), Vector2(520, 360), Color(tint, 0.2))


func _b_paint_vignette() -> void:
	var w := size.x
	var h := size.y
	var dark := Color(S.BRAWL_INK, 0.7)
	var clear := Color(S.BRAWL_INK, 0.0)
	var side := Color(S.BRAWL_INK, 0.28)
	_cv.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, 150), Vector2(0, 150)]), PackedColorArray([dark, dark, clear, clear]))
	_cv.draw_polygon(PackedVector2Array([Vector2(0, h - 420), Vector2(w, h - 420), Vector2(w, h), Vector2(0, h)]), PackedColorArray([clear, clear, dark, dark]))
	_cv.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(70, 0), Vector2(70, h), Vector2(0, h)]), PackedColorArray([side, clear, clear, side]))
	_cv.draw_polygon(PackedVector2Array([Vector2(w - 70, 0), Vector2(w, 0), Vector2(w, h), Vector2(w - 70, h)]), PackedColorArray([clear, side, side, clear]))


# ---------------------------------------------------------------- header

func _b_header() -> void:
	_b_resource(Rect2(20, 26, 276, 76), "special", "essence", int(menu.profile.essence))
	_b_resource(Rect2(316, 26, 236, 76), "loot", "crown_tooth", int(menu.profile.crowns))
	_b_gear()


## Resource counter: icon plate overlapping the left end of a dark pill.
func _b_resource(rect: Rect2, tone: String, icon: String, value: int) -> void:
	var plate := rect.size.y + 6.0
	var pc := Vector2(rect.position.x + plate * 0.5, rect.get_center().y)
	var pill := Rect2(rect.position.x + plate * 0.5, rect.position.y + 9.0, rect.size.x - plate * 0.5, rect.size.y - 18.0)
	if _on("base"):
		Kit.pill(_cv, pill, "dark")
	if not _on("top"):
		return
	Kit.icon_plate(_cv, pc, plate, tone)
	_b_icon(icon, Kit.plate_center(pc, plate), plate * 0.72)
	var x := pc.x + plate * 0.5 + S.SPACE_M
	Kit.number(_cv, Vector2(x, pill.get_center().y), value, S.T_HEAD, Color.WHITE, Kit.LEFT | Kit.MIDDLE, pill.end.x - x - S.SPACE_L)


func _b_gear() -> void:
	if not _on("top"):
		return
	var rect: Rect2 = menu.settings_button_rect()
	var pressed: bool = menu.is_pressed(rect) or menu.settings_open
	var c := rect.get_center()
	var r := 44.0
	Kit.round_button(_cv, c, r, "neutral", pressed)
	_b_gear_glyph(Kit.round_label_center(c, r, pressed), r * 0.5)


func _b_logo(top: float) -> void:
	var cx := size.x * 0.5
	var tex := UiArt.logo()
	if tex == null:
		if _on("top"):
			_b_text(Vector2(cx, top + 50), "MAWLINGS", S.T_HERO, S.brawl_tone("ember")["light"], Kit.CENTER | Kit.MIDDLE)
		return
	if not _on("base"):
		return
	var lw := 500.0
	var lh := lw * float(tex.get_height()) / float(tex.get_width())
	var rect := Rect2(cx - lw * 0.5, top, lw, lh)
	_cv.draw_texture_rect(tex, Rect2(rect.position + Vector2(0, S.SHADOW_Y), rect.size), false, Color(S.BRAWL_INK, 0.6))
	_cv.draw_texture_rect(tex, rect, false)


# ---------------------------------------------------------------- strain card

func _b_strain_tone(id: String, unlocked: bool) -> Variant:
	if not unlocked:
		return "disabled"
	if id == "nachtmaul":
		return "special"
	var tint: Color = menu._strain_color(id)
	if tint.s < 0.2 and tint.v > 0.8:
		return tint.darkened(0.35)   # bone-white Knochenkiefer: keep the frame visible
	return tint


func _b_strain() -> void:
	var id: String = menu.current_strain()
	var s: Dictionary = menu._strain(id)
	var owned: bool = menu._strain_owned(id)
	var unlocked: bool = menu._strain_unlocked(id)
	var tone: Variant = _b_strain_tone(id, unlocked)
	var base_rect: Rect2 = menu.strain_card_rect()
	var card := Rect2(base_rect.position + Vector2(menu._slide, 0.0), base_rect.size)
	var body := _b_body(card, STRAIN_HEADER)
	var cx := card.get_center().x
	var foot := Vector2(cx, body.position.y + 306.0)
	if _on("base"):
		Kit.card(_cv, card, tone, "normal" if unlocked else "disabled", STRAIN_HEADER, S.R_XL)
		var light := _b_light(tone)
		_glow(Vector2(cx, foot.y - 120.0), Vector2(300, 170), Color(light, 0.28 if unlocked else 0.1))
		_cv.draw_colored_polygon(_b_ellipse_points(foot + Vector2(0, 4), 190, 34), Color(S.BRAWL_INK, 0.55))
		_cv.draw_colored_polygon(_b_ellipse_points(foot, 176, 28), Color(light, 0.22 if unlocked else 0.1))
		var rim := _b_ellipse_points(foot, 176, 28)
		rim.append(rim[0])
		_cv.draw_polyline(rim, Color(light, 0.6 if unlocked else 0.25), 3.0, true)
	if _on("live"):
		var tex := UiArt.tribe(id)
		if tex != null:
			var h := PORTRAIT_H * (1.0 + 0.014 * sin(_time * 1.7))
			if unlocked:
				UiArt.draw_standing(_cv, tex, foot + Vector2(0, 10), h)
			else:
				UiArt.draw_standing(_cv, tex, foot + Vector2(0, 6), h, Color(S.BRAWL_PANEL_RIM, 0.55))
				UiArt.draw_standing(_cv, tex, foot + Vector2(0, 10), h, Color(S.BRAWL_INK, 0.97))
	if not _on("top"):
		return
	if UiArt.tribe(id) == null:
		_mawling_head(foot + Vector2(0, -110), 90, _b_light(tone))
	# Name in the coloured header band.
	var name := String(s.get("name", id)).to_upper()
	_b_text(Vector2(cx, card.position.y + S.STROKE_L + (STRAIN_HEADER + 7.0) * 0.5 + 2.0), name, S.T_TITLE, Color.WHITE if unlocked else S.BRAWL_TEXT_DIM, Kit.CENTER | Kit.MIDDLE, card.size.x - 120.0)
	_b_status(body, id, owned, unlocked)
	if not unlocked:
		var lc := foot + Vector2(0, -130)
		Kit.icon_plate(_cv, lc, 104, "neutral")
		_b_icon("lock", Kit.plate_center(lc, 104), 66)
	var text_top := foot.y + 44.0
	if unlocked:
		var desc := String(s.get("description", ""))
		var one_line := Kit.wrap_lines(desc, S.body_font(), S.T_BODY, body.size.x - 72).size() <= 1
		Kit.paragraph(_cv, Vector2(body.position.x + 36, text_top + (16.0 if one_line else 0.0)), desc, body.size.x - 72, S.T_BODY, Color.WHITE, false, Kit.CENTER, 2)
		_b_chips(s, Rect2(body.position.x + 20, body.end.y - 66, body.size.x - 40, 52))
	else:
		_b_unlock_quest(String(s.get("unlock_quest", "")), Rect2(body.position.x + 36, text_top - 30, body.size.x - 72, body.end.y - 50 - (text_top - 30)))
	_b_arrows()
	_b_page_dots(Vector2(body.end.x - S.SPACE_L - 12.0, body.position.y + S.SPACE_L + 23.0))


## Status plaque in the top-left of the card body.
func _b_status(body: Rect2, id: String, owned: bool, unlocked: bool) -> void:
	var text := "IM BESITZ"
	var tone := "action"
	if not unlocked:
		text = "GESPERRT"
		tone = "neutral"
	elif not owned:
		text = "KAUFBAR"
		tone = "loot"
	var price := int(menu.profile.strain_cost(id)) if unlocked and not owned else -1
	var tw := S.display_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, S.T_LABEL).x
	var extra := 0.0
	if price >= 0:
		extra = S.number_font().get_string_size(str(price), HORIZONTAL_ALIGNMENT_LEFT, -1, S.T_LABEL).x + 12.0
	var rect := Rect2(body.position + Vector2(S.SPACE_L, S.SPACE_L), Vector2(52.0 + tw + extra + S.SPACE_L, 46))
	Kit.chip(_cv, rect, tone)
	var ic := Vector2(rect.position.x + 24, rect.get_center().y)
	if not unlocked:
		_b_icon("lock", ic, 30)
	elif owned:
		_b_check(ic, 14)
	else:
		_b_icon("crown_tooth", ic, 34)
	var x := rect.position.x + 46
	x += _b_text(Vector2(x, rect.get_center().y), text, S.T_LABEL, Color.WHITE, Kit.LEFT | Kit.MIDDLE)
	if price >= 0:
		Kit.number(_cv, Vector2(x + 12, rect.get_center().y), price, S.T_LABEL, Color.WHITE, Kit.LEFT | Kit.MIDDLE)


func _b_unlock_quest(quest_id: String, area: Rect2) -> void:
	var q: Dictionary = menu.meta.quest(quest_id)
	var cx := area.get_center().x
	var y := area.position.y + 24
	var title := "TROPHÄE: %s" % String(q.get("name", quest_id)).to_upper()
	var tw := _b_text(Vector2(cx + 22, y), title, S.T_HEAD, S.brawl_tone("loot")["light"], Kit.CENTER | Kit.MIDDLE, area.size.x - 60)
	_b_icon("trophy", Vector2(cx + 22 - tw * 0.5 - 28, y - 2), 44)
	Kit.paragraph(_cv, Vector2(area.position.x, y + 48), String(q.get("description", "")), area.size.x, S.T_BODY, S.BRAWL_TEXT_DIM, false, Kit.CENTER, 1)
	var progress: Vector2 = menu.profile.quest_progress(quest_id)
	var bar := Rect2(cx - 250, y + 76, 380, 34)
	Kit.bar(_cv, bar, clampf(progress.x / maxf(1.0, progress.y), 0.0, 1.0), "loot")
	_b_text(Vector2(bar.end.x + 16, bar.get_center().y), menu._progress_text(q, progress), S.T_LABEL, Color.WHITE, Kit.LEFT | Kit.MIDDLE, area.end.x - bar.end.x - 16)


## Stat chips: start pack, signature form, stat modifiers.
func _b_chips(s: Dictionary, area: Rect2) -> void:
	var mods: Dictionary = s.get("mods", {})
	var sig: String = s.get("signature", "")
	var chips: Array = []
	if int(s.get("start_population", 1)) > 1:
		chips.append({"icon": "mawling_head_color", "text": "%d" % int(s.get("start_population", 1)), "tone": "ember", "glyph": ""})
	chips.append({"icon": sig, "text": String(menu.meta.MUTATION_NAMES.get(sig, sig)), "tone": "special", "glyph": ""})
	for pair in [["damage", "SCHADEN"], ["armor", "PANZER"], ["speed", "TEMPO"], ["growth", "WACHSTUM"], ["dna", "DNA"]]:
		var v := float(mods.get(pair[0], 0.0 if pair[0] == "armor" else 1.0))
		var delta := v * 100.0 if pair[0] == "armor" else (v - 1.0) * 100.0
		if absf(delta) >= 0.5:
			chips.append({"icon": "", "text": "%s %+d %%" % [pair[1], roundi(delta)], "tone": "action" if delta > 0 else "danger", "glyph": "▲" if delta > 0 else "▼"})
	if s.has("rally_damage"):
		chips.append({"icon": "", "text": "RALLY %+d %%" % roundi((float(s.rally_damage) - 1.0) * 100.0), "tone": "action", "glyph": "▲"})
	var font := S.display_font()
	var gap := S.SPACE_M
	var plate := 40.0
	var pad := 8.0 + plate + 8.0 + S.SPACE_M
	var fixed := 0.0
	var text_w := 0.0
	for c in chips:
		c["tw"] = font.get_string_size(c.text, HORIZONTAL_ALIGNMENT_LEFT, -1, S.T_LABEL).x
		text_w += c.tw
		fixed += pad
	fixed += gap * (chips.size() - 1)
	# Shrink the labels a little if needed (never below ~18 px), else drop chips from the end.
	var k := clampf((area.size.x - fixed) / maxf(1.0, text_w), 0.0, 1.0)
	while k < 0.82 and chips.size() > 2:
		var last: Dictionary = chips.pop_back()
		text_w -= last.tw
		fixed -= pad + gap
		k = clampf((area.size.x - fixed) / maxf(1.0, text_w), 0.0, 1.0)
	var total := fixed + text_w * k
	var x := area.position.x + maxf(0.0, (area.size.x - total) * 0.5)
	for c in chips:
		var w: float = pad + c.tw * k
		var r := Rect2(x, area.position.y, w, area.size.y)
		Kit.chip(_cv, r, "dark")
		var pc := Vector2(r.position.x + 8.0 + plate * 0.5, r.get_center().y)
		Kit.icon_plate(_cv, pc, plate, c.tone)
		if c.icon != "" and _b_icon(c.icon, Kit.plate_center(pc, plate), plate * 0.82):
			pass
		elif c.glyph != "":
			_b_text(Kit.plate_center(pc, plate) + Vector2(0, 1), c.glyph, S.T_LABEL, Color.WHITE, Kit.CENTER | Kit.MIDDLE)
		_b_text(Vector2(pc.x + plate * 0.5 + 8.0, r.get_center().y), c.text, S.T_LABEL, Color.WHITE, Kit.LEFT | Kit.MIDDLE, c.tw * k + 0.5)
		x += w + gap


func _b_arrows() -> void:
	for i in 2:
		var rect: Rect2 = menu.strain_prev_rect() if i == 0 else menu.strain_next_rect()
		var dir := -1.0 if i == 0 else 1.0
		var pressed: bool = menu.is_pressed(rect)
		var c := rect.get_center()
		var r := 42.0
		Kit.round_button(_cv, c, r, "neutral", pressed)
		_b_arrow(Kit.round_label_center(c, r, pressed) + Vector2(dir * 2.0, 0), 30.0, dir)


## Pager in the top-right corner of the card body; `right` is the last dot.
func _b_page_dots(right: Vector2) -> void:
	var n: int = menu.strain_ids.size()
	var step := 28.0
	for i in n:
		var p := right + Vector2((i - (n - 1)) * step, 0)
		var other: String = menu.strain_ids[i]
		var open: bool = menu._strain_unlocked(other)
		if i == menu.strain_index:
			Kit.disc(_cv, p, 11, S.BRAWL_INK)
			Kit.disc(_cv, p, 8, Color.WHITE)
		else:
			Kit.disc(_cv, p, 8, S.BRAWL_INK)
			Kit.disc(_cv, p, 5.5, _b_light(_b_strain_tone(other, open)) if open else Kit.DISABLED["face"])


# ---------------------------------------------------------------- biome and difficulty tiles

func _b_biomes() -> void:
	for i in menu.meta.BIOME_ORDER.size():
		var id: String = menu.meta.BIOME_ORDER[i]
		var b: Dictionary = menu.meta.BIOMES[id]
		var rect: Rect2 = menu.biome_rect(i)
		var locked: bool = b.get("locked", false)
		var selected: bool = id == menu.biome_id
		var tone := "disabled" if locked else ("info" if selected else "neutral")
		var state := "disabled" if locked else ("selected" if selected else "normal")
		var body := _b_body(rect)
		var rb := _b_body_radius(S.R_L)
		if _on("base"):
			Kit.card(_cv, rect, tone, state, 0.0, S.R_L)
			var art := UiArt.biome(id)
			var shape := Kit.round_rect_points(body, Vector4(rb, rb, rb, rb))
			if art != null:
				UiArt.draw_cover(_cv, art, shape, body, Color(0.5, 0.5, 0.56) if locked else Color.WHITE, Vector2(0.5, 0.55 if id == "verdant_maw" else 0.62))
			_fill_gradient(shape, Color(S.BRAWL_INK, 0.0), Color(S.BRAWL_INK, 0.8))
			Kit.ring(_cv, body.grow(1.5), rb + 1.5, 3.0, Color(_b_dark(tone), 0.95))
		if not _on("top"):
			continue
		var x := body.position.x + S.SPACE_L
		_b_text(Vector2(x, body.end.y - 26), String(b.name).to_upper(), S.T_HEAD, Color.WHITE if not locked else S.BRAWL_TEXT_DIM, Kit.LEFT | Kit.MIDDLE, body.size.x - 90)
		var corner := Vector2(rect.end.x - 34, rect.position.y + 34)
		if locked:
			Kit.icon_plate(_cv, corner, 52, "neutral")
			_b_icon("lock", Kit.plate_center(corner, 52), 34)
			var status := String(b.get("status", "")).to_upper()
			if status != "":
				var sw := S.display_font().get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, S.T_LABEL).x + 28.0
				var chip := Rect2(body.position.x + S.SPACE_M, body.position.y + S.SPACE_M, sw, 36)
				Kit.chip(_cv, chip, "neutral")
				_b_text(chip.get_center(), status, S.T_LABEL, Color.WHITE, Kit.CENTER | Kit.MIDDLE)
		elif selected:
			Kit.icon_plate(_cv, corner, 52, "action")
			_b_check(Kit.plate_center(corner, 52), 15)


func _b_difficulties() -> void:
	for i in menu.meta.DIFFICULTIES.size():
		var d: Dictionary = menu.meta.DIFFICULTIES[i]
		var rect: Rect2 = menu.difficulty_rect(i)
		var unlocked: bool = menu._difficulty_unlocked(i)
		var selected: bool = i == menu.difficulty
		var tone := "disabled" if not unlocked else ("info" if selected else "neutral")
		var state := "disabled" if not unlocked else ("selected" if selected else "normal")
		var body := _b_body(rect)
		if _on("base"):
			Kit.card(_cv, rect, tone, state, 0.0, S.R_L)
		if not _on("top"):
			continue
		var cx := body.get_center().x
		var name := String(d.name).to_upper()
		var row1 := body.position.y + 36.0
		var row2 := body.end.y - 22.0
		var font := S.display_font()
		var nw := minf(font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, S.T_HEAD).x, body.size.x - 66.0)
		var icon_x := cx - (nw + 52.0) * 0.5 + 22.0
		if unlocked:
			if not _b_icon(["diff_wild", "diff_brutal", "diff_apex"][i], Vector2(icon_x, row1), 52):
				_skull(Vector2(icon_x, row1), 16, Color.WHITE)
			_b_text(Vector2(icon_x + 30, row1), name, S.T_HEAD, Color.WHITE, Kit.LEFT | Kit.MIDDLE, body.size.x - 66.0)
			var reward := "×%s ESSENZ" % String.num(float(d.get("reward", 1.0)), 1).replace(".", ",")
			var rw := font.get_string_size(reward, HORIZONTAL_ALIGNMENT_LEFT, -1, S.T_LABEL).x + 32.0
			var ex := cx - rw * 0.5
			_b_icon("essence", Vector2(ex + 12, row2), 30)
			_b_text(Vector2(ex + 32, row2), reward, S.T_LABEL, S.brawl_tone("special")["light"], Kit.LEFT | Kit.MIDDLE, body.size.x - 40)
		else:
			_b_icon("lock", Vector2(icon_x, row1), 40)
			_b_text(Vector2(icon_x + 30, row1), name, S.T_HEAD, S.BRAWL_TEXT_DIM, Kit.LEFT | Kit.MIDDLE, body.size.x - 66.0)
			var q: Dictionary = menu.meta.quest(d.get("unlock_quest", ""))
			_b_text(Vector2(cx, row2), String(q.get("name", "")), S.T_LABEL, S.brawl_tone("loot")["light"], Kit.CENTER | Kit.MIDDLE, body.size.x - 12, S.body_bold_font())


# ---------------------------------------------------------------- SPIELEN, daily, records

func _b_play() -> void:
	var rect: Rect2 = menu.play_rect()
	var pressed: bool = menu.is_pressed(rect)
	var id: String = menu.current_strain()
	var owned: bool = menu._strain_owned(id)
	var unlocked: bool = menu._strain_unlocked(id)
	var price := int(menu.profile.strain_cost(id))
	var affordable: bool = int(menu.profile.crowns) >= price
	var tone := "disabled"
	if owned:
		tone = "action" if menu.can_play() else "disabled"
	elif unlocked:
		tone = "loot" if affordable else "disabled"
	if _on("under") and tone != "disabled" and not pressed:
		_glow(rect.get_center() + Vector2(0, 6), Vector2(rect.size.x * 0.62, rect.size.y * 0.95), Color(S.brawl_tone(tone)["light"], 0.16 + 0.1 * _pulse(2.2)))
	if _on("base"):
		Kit.button(_cv, rect, tone, pressed, S.R_XL)
	if not _on("top"):
		return
	var lc := Kit.button_label_center(rect, pressed)
	var font := S.display_font()
	if owned:
		var label := "SPIELEN"
		var fs := 64
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var icon := 92.0
		var x0 := lc.x - (w + icon + 16.0) * 0.5
		if not _b_icon("mawling_head_color", Vector2(x0 + icon * 0.5, lc.y), icon):
			_mawling_head(Vector2(x0 + icon * 0.5, lc.y), 38, Color.WHITE)
		_b_text(Vector2(x0 + icon + 16.0, lc.y), label, fs, Color.WHITE, Kit.LEFT | Kit.MIDDLE)
	elif unlocked:
		var label := "KAUFEN"
		var fs := S.T_TITLE
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pw := S.number_font().get_string_size(str(price), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var total := w + 20.0 + pw + 8.0 + 60.0
		var y := lc.y - (0.0 if affordable else 14.0)
		var x := lc.x - total * 0.5
		var col := Color.WHITE if affordable else S.BRAWL_TEXT_DIM
		x += _b_text(Vector2(x, y), label, fs, col, Kit.LEFT | Kit.MIDDLE) + 20.0
		x += Kit.number(_cv, Vector2(x, y), price, fs, col, Kit.LEFT | Kit.MIDDLE) + 8.0
		_b_icon("crown_tooth", Vector2(x + 30, y), 60)
		if not affordable:
			_b_text(Vector2(lc.x, lc.y + 36), "ZU WENIGE KÖNIGSZÄHNE", S.T_LABEL, S.brawl_tone("loot")["light"], Kit.CENTER | Kit.MIDDLE, rect.size.x - 60)
	else:
		var fs := S.T_TITLE
		var w := font.get_string_size("GESPERRT", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var y := lc.y - 14.0
		var x0 := lc.x - (w + 56.0) * 0.5
		_b_icon("lock", Vector2(x0 + 22, y), 48)
		_b_text(Vector2(x0 + 56, y), "GESPERRT", fs, S.BRAWL_TEXT_DIM, Kit.LEFT | Kit.MIDDLE)
		var q: Dictionary = menu.meta.quest(menu._strain(id).get("unlock_quest", ""))
		_b_text(Vector2(lc.x, lc.y + 36), "Trophäe: " + String(q.get("name", "")), S.T_LABEL, S.brawl_tone("loot")["light"], Kit.CENTER | Kit.MIDDLE, rect.size.x - 60)


## TAGES-BRUT as a wide loot button (stage 15: the map code card is gone):
## sun plate, title and rule line, today's best in a dark pill on the right.
func _b_daily() -> void:
	var rect: Rect2 = menu.daily_rect()
	var ok: bool = menu.can_play_daily()
	var pressed: bool = ok and menu.is_pressed(rect)
	if _on("base"):
		Kit.button(_cv, rect, "loot" if ok else "disabled", pressed, S.R_L)
	if not _on("top"):
		return
	var lc := Kit.button_label_center(rect, pressed)
	var pc := Vector2(rect.position.x + 60, lc.y)
	Kit.icon_plate(_cv, pc, 80, "ember" if ok else "neutral")
	_b_sun_glyph(Kit.plate_center(pc, 80), 28)
	var today: Dictionary = menu.daily_today()
	var pill := Rect2(rect.end.x - 20 - 300, lc.y - 31, 300, 62)
	Kit.pill(_cv, pill, "dark", S.STROKE_S)
	var cy := pill.get_center().y
	if today.is_empty():
		_b_text(Vector2(pill.get_center().x - 14, cy), "NOCH OFFEN", S.T_BODY, Color.WHITE if ok else S.BRAWL_TEXT_DIM, Kit.CENTER | Kit.MIDDLE, pill.size.x - 70)
		_b_arrow(Vector2(pill.end.x - 30, cy), 20.0, 1.0)
	else:
		var t := float(today.get("seconds", 0.0))
		var x := pill.position.x + 18
		_b_icon("clock", Vector2(x + 16, cy), 34)
		x += 40
		x += Kit.number(_cv, Vector2(x, cy), "%02d:%02d" % [int(t) / 60, int(t) % 60], S.T_HEAD, Color.WHITE, Kit.LEFT | Kit.MIDDLE) + 14
		_b_icon("mawling_head_color", Vector2(x + 16, cy), 36)
		Kit.number(_cv, Vector2(x + 38, cy), int(today.get("peak", 0)), S.T_BODY, Color.WHITE, Kit.LEFT | Kit.MIDDLE, pill.end.x - x - 56)
	var x := rect.position.x + 118
	var max_w := pill.position.x - x - S.SPACE_L
	_b_text(Vector2(x, lc.y - 16), "TAGES-BRUT", S.T_HEAD, Color.WHITE if ok else S.BRAWL_TEXT_DIM, Kit.LEFT | Kit.MIDDLE, max_w)
	var runs := int(today.get("runs", 0))
	var line := "Gleiche Karte für alle · Wild"
	if runs > 0:
		line = "Heute %d %s · gleiche Karte für alle" % [runs, "Versuch" if runs == 1 else "Versuche"]
	_b_text(Vector2(x, lc.y + 22), line, S.T_LABEL, Color.WHITE if ok else S.BRAWL_TEXT_DIM, Kit.LEFT | Kit.MIDDLE, max_w, S.body_bold_font())


## All-time record line; tapping it opens the CHRONIK (hit area menu.records_rect()).
func _b_records() -> void:
	var rec: Rect2 = menu.records_rect()
	var pressed: bool = menu.is_pressed(rec)
	var pill := Rect2(rec.position.x, rec.get_center().y - 29 + (3.0 if pressed else 0.0), rec.size.x, 58)
	if _on("base"):
		Kit.pill(_cv, pill, "dark", S.STROKE_S)
	if not _on("top"):
		return
	var best := float(menu.profile.records.get("best_seconds", 0.0))
	var peak := int(menu.profile.records.get("best_peak", 0))
	var cy := pill.get_center().y
	var more := "CHRONIK →"
	var mw := S.display_font().get_string_size(more, HORIZONTAL_ALIGNMENT_LEFT, -1, S.T_LABEL).x
	_b_text(Vector2(pill.end.x - 26 - mw, cy), more, S.T_LABEL, S.brawl_tone("info")["light"], Kit.LEFT | Kit.MIDDLE)
	var x := pill.position.x + 22
	var limit := pill.end.x - 26 - mw - 16
	_b_icon("clock", Vector2(x + 16, cy), 36)
	x += 40
	x += _b_text(Vector2(x, cy), "REKORD %02d:%02d" % [int(best) / 60, int(best) % 60], S.T_LABEL, Color.WHITE, Kit.LEFT | Kit.MIDDLE, limit - x) + 22
	if x + 60 < limit:
		_b_icon("mawling_head_color", Vector2(x + 16, cy), 38)
		x += 40
		_b_text(Vector2(x, cy), "MAX. SCHWARM %s" % Kit.format_int(peak), S.T_LABEL, Color.WHITE, Kit.LEFT | Kit.MIDDLE, limit - x)


# ---------------------------------------------------------------- tab dock

func _b_tabs() -> void:
	var first: Rect2 = menu.tab_rect(0)
	var dock := Rect2(-S.STROKE_L - 20.0, first.position.y - 14.0, size.x + 2.0 * (S.STROKE_L + 20.0), size.y - first.position.y + 60.0)
	if _on("base"):
		Kit.panel(_cv, dock, "dark", S.R_XL, S.STROKE_L, true)
	var names: Dictionary = menu.TAB_NAMES
	for i in menu.TABS.size():
		var id: String = menu.TABS[i]
		var rect: Rect2 = menu.tab_rect(i)
		var active: bool = menu.tab == id
		var tone: String = TAB_TONES[i]
		var pressed: bool = menu.is_pressed(rect)
		if _on("base"):
			if active:
				Kit.button(_cv, rect, tone, false, S.R_L)
			elif pressed:
				Kit.well(_cv, rect, S.R_L)
		if not _on("top"):
			continue
		var plate := 68.0
		var pc := Vector2(rect.get_center().x, rect.position.y + 44.0 + (3.0 if pressed and not active else 0.0))
		Kit.icon_plate(_cv, pc, plate, "dark" if active else tone)
		if not _b_icon(TAB_ICONS[i], Kit.plate_center(pc, plate), plate * 0.78):
			_tab_icon(id, Kit.plate_center(pc, plate), Color.WHITE)
		_b_text(Vector2(rect.get_center().x, rect.position.y + 100.0), String(names[id]), S.T_LABEL, Color.WHITE, Kit.CENTER | Kit.MIDDLE, rect.size.x - 16.0)
		var badge := ""
		if id == "upgrades":
			var n: int = menu._affordable_upgrades()
			badge = "%d" % n if n > 0 else ""
		elif id == "instinct" and int(menu.profile.essence) >= int(menu._instinct_cost()):
			badge = "!"
		if badge != "" and not active:
			Kit.badge(_cv, Vector2(pc.x + plate * 0.5 + 8.0, rect.position.y + 14.0), badge, "danger", S.T_LABEL)
