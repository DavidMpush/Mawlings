extends "res://scripts/menu/ui_kit.gd"
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

const S = preload("res://scripts/ui/ui_style.gd")
const MAWLING_PATH := "res://assets/gameplay/characters/Mawling_game.glb"
const SHADER_PATH := "res://shaders/creature_anim.gdshader"
const ICONS_PATH := "res://scripts/ui/ui_icons.gd"
const FRAMES_PATH := "res://scripts/ui/ui_frames.gd"

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

var menu = null
var _icons = null
var _frames = null
var _soft: Texture2D
var _viewport: SubViewport
var _camera: Camera3D
var _material: ShaderMaterial
var _pack: Array = []
var _tinted_for := "?"
var _time := 0.0
var _spores: Array = []
var _leaves: Array = []


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
	if use_3d:
		_build_stage()


func _process(delta: float) -> void:
	_time += delta
	_update_stage()
	queue_redraw()

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
		"rim_color": S.EMBER_GLOW, "rim_strength": 0.55, "rim_power": 2.2,
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
			_material.set_shader_parameter("rim_color", S.EMBER_GLOW.lerp(tint.lightened(0.4), 0.6))
			_material.set_shader_parameter("rim_strength", 0.55)
		else:
			# Locked: a dark silhouette with a cold rim, the pack is only hinted.
			_material.set_shader_parameter("body_tint", Color(S.PANEL_EDGE.r, S.PANEL_EDGE.g, S.PANEL_EDGE.b, 1.0))
			_material.set_shader_parameter("brightness", 0.32)
			_material.set_shader_parameter("saturation", 0.2)
			_material.set_shader_parameter("rim_color", S.TEXT_DIM)
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
	draw_texture_rect(_soft, Rect2(center - radius, radius * 2.0), false, color)


func _txt(value: String, at: Vector2, font_size: int, color: Color = S.TEXT, centered: bool = false, outline: int = 6, body: bool = false) -> float:
	return S.text(self, value, at, font_size, color, centered, outline, S.body_font() if body else null)


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
			_icons.draw(self, id, rect, tint)
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
	draw_polygon(points, colors)


## Organic card: shadow, accent glow, gradient body, veins, cell holes, rim, bone claws.
## claws: bitmask 1 top-left, 2 top-right, 4 bottom-right, 8 bottom-left.
func _panel(rect: Rect2, accent: Color, fill: Color = S.PANEL, glow: float = 0.0, cut: float = 20.0, notch: float = 0.0, claws: int = 0, rim: float = 3.0, cells: bool = false) -> void:
	var shape := _shape(rect, cut, notch)
	draw_colored_polygon(_shape(Rect2(rect.position + Vector2(0, 8), rect.size), cut, notch), S.SHADOW)
	if glow > 0.0:
		draw_colored_polygon(_shape(rect.grow(13), cut + 9, notch), Color(accent, 0.06 * glow))
		draw_colored_polygon(_shape(rect.grow(6), cut + 4, notch), Color(accent, 0.16 * glow))
	_fill_gradient(shape, Color(fill.lightened(0.09), fill.a), Color(fill.darkened(0.25), fill.a))
	_veins(rect, accent)
	if cells:
		_cells(Vector2(rect.end.x - 54, rect.position.y + 34), accent)
	draw_polyline(_closed(_shape(rect.grow(-7), maxf(4.0, cut - 5), notch * 0.7)), Color(accent, 0.2), 1.5, true)
	var loop := _closed(shape)
	draw_polyline(loop, S.OUTLINE, rim + 3.0, true)
	draw_polyline(loop, accent, rim, true)
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	var outward := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for i in 4:
		if claws & (1 << i):
			var dir: Vector2 = (outward[i] as Vector2).normalized()
			var base: Vector2 = corners[i] - dir * cut * 0.2
			_claw(base + Vector2(0, 2), dir, 28, 8, S.OUTLINE, 0.45 if i % 2 == 0 else -0.45)
			_claw(base, dir, 26, 7, S.BONE, 0.45 if i % 2 == 0 else -0.45)


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
		draw_polyline(points, Color(S.PANEL_EDGE, 0.55), 2.0, true)
		var mid := points[2]
		draw_line(mid, mid + dir.rotated(0.9 if from_left else -0.9) * length * 0.3, Color(S.PANEL_EDGE, 0.4), 1.5, true)
		draw_circle(points[5], 2.5, Color(accent, 0.12))


## Cluster of pores like the concept cards.
func _cells(at: Vector2, accent: Color) -> void:
	for o in [Vector2(0, 0), Vector2(20, -4), Vector2(12, 15), Vector2(30, 13)]:
		var r := 7.0 if o == Vector2.ZERO else 5.5
		draw_circle(at + o, r + 2.0, Color(accent, 0.18))
		draw_circle(at + o, r, S.OUTLINE)


func _socket(c: Vector2, r: float, accent: Color, glow: float = 1.0) -> void:
	if glow > 0.0:
		_glow(c, Vector2(r, r) * 1.9, Color(accent, 0.22 * glow))
	draw_circle(c, r + 3.0, S.OUTLINE)
	draw_circle(c, r, S.PANEL.darkened(0.35))
	draw_arc(c, r, 0, TAU, 40, accent, 3.0, true)
	draw_arc(c, r - 6.0, 0, TAU, 40, Color(accent, 0.2), 1.5, true)


func _gem(c: Vector2, r: float, color: Color) -> void:
	_diamond(c, r + 2.5, S.OUTLINE)
	_diamond(c, r, color)
	_diamond(c + Vector2(-r * 0.2, -r * 0.3), r * 0.35, Color(1, 1, 1, 0.45))

# ---------------------------------------------------------------- background

func _build_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90417
	for i in 44:
		_spores.append({"pos": Vector2(rng.randf_range(0, 900), rng.randf_range(0, 1600)), "r": rng.randf_range(1.6, 4.2), "speed": rng.randf_range(10, 28), "phase": rng.randf() * TAU, "cyan": rng.randf() < 0.45})
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


func _draw_background() -> void:
	var w := size.x
	var h := size.y
	var stops := [[0.0, S.OUTLINE], [0.3, S.PANEL_SOFT.lightened(0.04)], [0.62, Color(S.PANEL, 1.0)], [1.0, S.OUTLINE]]
	for i in stops.size() - 1:
		var a: float = stops[i][0] * h
		var b: float = stops[i + 1][0] * h
		var ca := Color(stops[i][1], 1.0)
		var cb := Color(stops[i + 1][1], 1.0)
		draw_polygon(PackedVector2Array([Vector2(0, a), Vector2(w, a), Vector2(w, b), Vector2(0, b)]), PackedColorArray([ca, ca, cb, cb]))
	var tint: Color = S.EMBER
	if menu != null and menu.profile != null:
		tint = menu._strain_color(menu.current_strain()) if menu._strain_unlocked(menu.current_strain()) else S.TEXT_DIM
	# Warm pool of light where the pack stands, cool haze lower down.
	_glow(Vector2(w * 0.5, 520), Vector2(620, 520), Color(tint, 0.2))
	_glow(Vector2(w * 0.5, 1180), Vector2(700, 380), Color(S.CYAN, 0.05))
	# God rays from the canopy.
	var ray_color := S.TOXIC.lerp(S.TEXT, 0.55)
	for i in 5:
		var x := 60.0 + i * 150.0 + sin(_time * 0.13 + i * 1.3) * 26.0
		var top_w := 30.0 + i * 8.0
		var alpha := 0.045 + 0.02 * sin(_time * 0.4 + i * 2.1)
		var top_c := Color(ray_color, alpha)
		var low_c := Color(ray_color, 0.0)
		draw_polygon(PackedVector2Array([Vector2(x, -10), Vector2(x + top_w, -10), Vector2(x + top_w + 520, 1250), Vector2(x + 300, 1250)]), PackedColorArray([top_c, top_c, low_c, low_c]))
	# Far leaves (hazy), drifting fog, spores, near leaves (dark).
	for d in _leaves:
		if d.layer == 0:
			_leaf(d.pos, d.len, d.w, d.angle + sin(_time * 0.5 + d.phase) * 0.03, Color(S.PANEL_EDGE.lerp(S.PANEL_SOFT, 0.5 + 0.3 * d.shade), 0.8))
	for i in 3:
		var fy: float = [760.0, 1010.0, 1240.0][i]
		var fx := fposmod(_time * (14.0 + i * 5.0) + i * 300.0, 1500.0) - 300.0
		_glow(Vector2(fx, fy), Vector2(460, 90), Color(S.TEXT_DIM, 0.05))
		_glow(Vector2(fx - 750.0, fy + 40.0), Vector2(460, 90), Color(S.TEXT_DIM, 0.04))
	for s in _spores:
		var p: Vector2 = s.pos + Vector2(sin(_time * 0.5 + s.phase) * 16.0, -_time * s.speed)
		p.y = fposmod(p.y + 60.0, 1720.0) - 60.0
		var c: Color = S.CYAN if s.cyan else S.TOXIC
		var flicker := 0.55 + 0.45 * sin(_time * 2.2 + s.phase)
		_glow(p, Vector2.ONE * s.r * 4.5, Color(c, 0.22 * flicker))
		draw_circle(p, s.r * 0.7, Color(c.lightened(0.5), 0.75 * flicker))
	for d in _leaves:
		if d.layer == 1:
			var col := S.OUTLINE.lerp(S.PANEL_EDGE, 0.25 + 0.4 * d.shade)
			_leaf(d.pos, d.len, d.w, d.angle + sin(_time * 0.7 + d.phase) * 0.04, col)
	# Vignette: sides and the bands behind the resource bar and tab dock.
	var dark := Color(S.OUTLINE, 0.6)
	var clear := Color(S.OUTLINE, 0.0)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(90, 0), Vector2(90, h), Vector2(0, h)]), PackedColorArray([dark, clear, clear, dark]))
	draw_polygon(PackedVector2Array([Vector2(w - 90, 0), Vector2(w, 0), Vector2(w, h), Vector2(w - 90, h)]), PackedColorArray([clear, dark, dark, clear]))
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, 130), Vector2(0, 130)]), PackedColorArray([dark, dark, clear, clear]))
	draw_polygon(PackedVector2Array([Vector2(0, h - 260), Vector2(w, h - 260), Vector2(w, h), Vector2(0, h)]), PackedColorArray([clear, clear, dark, dark]))

# ---------------------------------------------------------------- draw

func _draw() -> void:
	if menu == null:
		return
	_draw_background()
	if menu.profile == null:
		return
	_draw_resources()
	if menu.tab == "":
		_draw_logo()
		_draw_strain()
		_draw_section("BIOM", 858)
		_draw_biomes()
		_draw_section("SCHWIERIGKEIT", 1032)
		_draw_difficulties()
		_draw_play()
	_draw_tabs()


func _draw_resources() -> void:
	_resource_pill(Rect2(16, 18, 270, 76), S.VIOLET, "ESSENZ", int(menu.profile.essence), true)
	_resource_pill(Rect2(size.x - 286, 18, 270, 76), S.GOLD, "KÖNIGSZÄHNE", int(menu.profile.crowns), false)


func _resource_pill(rect: Rect2, accent: Color, label: String, value: int, essence: bool) -> void:
	var body := Rect2(rect.position + Vector2(26, 6), rect.size - Vector2(26, 12))
	draw_colored_polygon(_rounded_points(Rect2(body.position + Vector2(0, 6), body.size), body.size.y * 0.5, 5), S.SHADOW)
	_fill_gradient(_rounded_points(body, body.size.y * 0.5, 5), Color(S.PANEL_SOFT.lightened(0.08), 0.96), Color(S.PANEL.darkened(0.2), 0.96))
	var loop := _closed(_rounded_points(body, body.size.y * 0.5, 5))
	draw_polyline(loop, S.OUTLINE, 5.0, true)
	draw_polyline(loop, Color(accent, 0.85), 2.5, true)
	var ic := rect.position + Vector2(36, rect.size.y * 0.5)
	_socket(ic, 32, accent, 0.8 + 0.2 * _pulse(1.6))
	if not _icon(["essence"] if essence else ["crown_tooth"], Rect2(ic - Vector2(27, 27), Vector2(54, 54))):
		if essence:
			_essence_drop(ic + Vector2(0, 3), 15, accent)
		else:
			_fang(ic + Vector2(-2, 2), 20, S.BONE)
	_txt(label, Vector2(rect.position.x + 80, rect.position.y + 36), S.SIZE_LABEL - 1, accent.lightened(0.35), false, 4)
	_txt("%d" % value, Vector2(rect.position.x + 80, rect.position.y + 70), S.SIZE_HEAD, S.TEXT, false, 6)


func _draw_logo() -> void:
	var cx := size.x * 0.5
	var title := "MAWLINGS"
	var fs := 104
	var baseline := 218.0
	var w := _tw(title, fs)
	var face := S.display_font()
	_glow(Vector2(cx, baseline - 36), Vector2(w * 0.72, 120), Color(S.EMBER, 0.22 + 0.05 * _pulse(1.2)))
	var left := cx - w * 0.5 - 34.0
	var right := cx + w * 0.5 + 34.0
	var gum := S.DANGER.darkened(0.45)
	var upper_y := baseline - 100.0
	var lower_y := baseline + 16.0
	# Word: shadow, extrusion, bevel highlight, face with a travelling glint.
	var origin := Vector2(cx - w * 0.5, baseline)
	draw_string_outline(face, origin + Vector2(0, 9), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 16, Color(S.OUTLINE, 0.7))
	draw_string_outline(face, origin + Vector2(0, 5), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 12, S.OUTLINE)
	draw_string(face, origin + Vector2(0, 5), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, S.EMBER.darkened(0.5))
	draw_string(face, origin + Vector2(0, -3), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, S.GOLD.lightened(0.35))
	var sweep := fposmod(_time * 0.45, 2.2) - 0.35
	var x := origin.x
	for i in title.length():
		var ch := title[i]
		var cw := face.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var k := clampf(1.0 - absf((x + cw * 0.5 - origin.x) / w - sweep) * 5.0, 0.0, 1.0)
		var face_color := S.EMBER_GLOW.lerp(S.EMBER, 0.35).lerp(S.TEXT, k * 0.75)
		draw_string(face, Vector2(x, baseline), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, face_color)
		x += face.get_string_size(title.substr(0, i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x - (x - origin.x)
	# Jaws over the word: the fangs bite into the letters.
	_jaw(Vector2(left, upper_y + 26), Vector2(cx, upper_y - 20), Vector2(right, upper_y + 26), 20.0, gum, 1.0, [0.06, 0.15, 0.27, 0.39, 0.5, 0.61, 0.73, 0.85, 0.94], [44.0, 30.0, 18.0, 14.0, 12.0, 14.0, 18.0, 30.0, 44.0])
	_jaw(Vector2(left + 40, lower_y - 2), Vector2(cx, lower_y + 34), Vector2(right - 40, lower_y - 2), 16.0, gum, -1.0, [0.1, 0.24, 0.38, 0.5, 0.62, 0.76, 0.9], [30.0, 18.0, 13.0, 11.0, 13.0, 18.0, 30.0])
	# Subtitle plate.
	var sub := "BRUTSTÄTTE"
	var sub_y := baseline + 64.0
	var half := _tw(sub, S.SIZE_LABEL + 3) * 0.5
	for side in [-1.0, 1.0]:
		var a := Vector2(cx + side * (half + 14), sub_y - 9)
		var b := Vector2(cx + side * (half + 150), sub_y - 9)
		draw_line(a, b, Color(S.TOXIC, 0.45), 2.0, true)
		_gem(b + Vector2(side * 8, 0), 6, S.TOXIC)
		_gem(a + Vector2(side * 36, 0), 3.5, Color(S.TOXIC, 0.8))
	_txt(sub, Vector2(cx, sub_y), S.SIZE_LABEL + 3, S.TOXIC.lerp(S.TEXT, 0.45), true, 5)


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
		draw_colored_polygon(PackedVector2Array([edge + Vector2(-half - 2, -dir * 2), edge + Vector2(half + 2, -dir * 2), tip + Vector2(0, dir * 3)]), S.OUTLINE)
		draw_colored_polygon(PackedVector2Array([edge + Vector2(-half, 0), edge + Vector2(half, 0), tip]), S.BONE)
		draw_colored_polygon(PackedVector2Array([edge + Vector2(half * 0.1, 0), edge + Vector2(half, 0), tip]), S.BONE.darkened(0.22))
	var band := top.duplicate()
	for i in range(low.size() - 1, -1, -1):
		band.append(low[i])
	draw_colored_polygon(band, S.OUTLINE)
	var inner := PackedVector2Array()
	for i in top.size():
		inner.append(top[i].lerp(low[i], 0.2))
	for i in range(low.size() - 1, -1, -1):
		inner.append(low[i].lerp(top[i], 0.2))
	_fill_gradient(inner, gum.lightened(0.35), gum)
	draw_polyline(top, Color(S.BONE, 0.35), 2.0, true)
	# Bone knobs at the hinge.
	for p in [a, b]:
		draw_circle(p, thick * 0.75, S.OUTLINE)
		draw_circle(p, thick * 0.55, S.BONE.darkened(0.15))


func _draw_section(label: String, y: float) -> void:
	_gem(Vector2(40, y - 8), 6, S.TOXIC)
	var w := _txt(label, Vector2(54, y), S.SIZE_LABEL, S.TOXIC.lerp(S.TEXT, 0.4), false, 4)
	var a := Vector2(66 + w, y - 8)
	var b := Vector2(size.x - 40, y - 8)
	draw_polygon(PackedVector2Array([a + Vector2(0, -1), b + Vector2(0, -1), b + Vector2(0, 1), a + Vector2(0, 1)]), PackedColorArray([Color(S.TOXIC, 0.5), Color(S.TOXIC, 0.0), Color(S.TOXIC, 0.0), Color(S.TOXIC, 0.5)]))

# ---------------------------------------------------------------- strain card

func _draw_strain() -> void:
	var id: String = menu.current_strain()
	var s: Dictionary = menu._strain(id)
	var owned: bool = menu._strain_owned(id)
	var unlocked: bool = menu._strain_unlocked(id)
	var tint: Color = menu._strain_color(id)
	var accent: Color = tint.lightened(0.35) if unlocked else S.TEXT_DIM.darkened(0.25)
	if id == "nachtmaul" and unlocked:
		accent = S.VIOLET
	var card: Rect2 = menu.strain_card_rect()
	var ox: float = menu._slide
	var cx := size.x * 0.5 + ox
	if _frames != null:
		_frames.card(self, card, accent, "selected" if owned else ("normal" if unlocked else "disabled"))
	else:
		_panel(card, accent, S.PANEL, 1.0 if unlocked else 0.4, 30.0, 12.0, 1 | 2, 3.5, true)
	# Stage: glowing ground disc under the pack (projected from the 3D camera).
	var ground := STAGE_GROUND
	var radius := Vector2(262, 52)
	if _camera != null and _viewport.size.x > 0:
		var front := _stage_point(Vector3(0, 0, 1.45))
		var back := _stage_point(Vector3(0, 0, -1.75))
		ground = Vector2(_stage_point(Vector3.ZERO).x, (front.y + back.y) * 0.5)
		radius = Vector2(_stage_point(Vector3(2.5, 0, -0.15)).x - ground.x, (front.y - back.y) * 0.5)
	ground.x += ox
	_glow(ground + Vector2(0, -radius.y * 2.0), Vector2(radius.x * 1.25, radius.x * 0.85), Color(tint if unlocked else S.TEXT_DIM, 0.3 if unlocked else 0.08))
	_ellipse(ground + Vector2(0, 5), radius.x + 8, radius.y + 6, Color(S.OUTLINE, 0.75))
	_ellipse(ground, radius.x, radius.y, Color(S.PANEL_SOFT.lightened(0.05), 0.95))
	_glow(ground, radius * 0.9, Color(tint if unlocked else S.TEXT_DIM, 0.22))
	var ring := PackedVector2Array()
	for i in 49:
		var a := TAU * i / 48.0
		ring.append(ground + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	draw_polyline(ring, Color(accent, 0.55), 2.5, true)
	for i in 14:
		var a := TAU * i / 14.0 + _time * 0.15
		var p := ground + Vector2(cos(a), sin(a)) * (radius - Vector2(20, 7))
		_diamond(p, 4.0, Color(accent, 0.3 + 0.4 * maxf(0.0, sin(a))))
	if use_3d and _viewport != null:
		for u in _pack:
			var node: Node3D = u.node
			var foot := _stage_point(Vector3(node.position.x, 0.0, node.position.z)) + Vector2(ox, 0)
			_glow(foot, Vector2(64, 16) * node.scale.x, Color(S.OUTLINE, 0.85))
		draw_texture_rect(_viewport.get_texture(), Rect2(STAGE_RECT.position + Vector2(ox, 0), STAGE_RECT.size), false)
	else:
		var head := tint if unlocked else S.PANEL_EDGE
		var ec := Vector2(cx, 470)
		_mawling_head(ec + Vector2(-80, -20), 56, head.darkened(0.3))
		_mawling_head(ec + Vector2(78, -28), 52, head.darkened(0.18))
		_mawling_head(ec + Vector2(0, 30), 84, head)
	if not unlocked:
		var lc := Vector2(cx, 470)
		_socket(lc, 46, S.TEXT_DIM, 0.6)
		if not _icon(["lock"], Rect2(lc - Vector2(30, 30), Vector2(60, 60))):
			_lock(lc + Vector2(0, -2), 32, S.TEXT)
	_status_badge(card, id, owned, unlocked)
	# Name, then description + stat chips, or the unlock trophy with progress.
	var name := String(s.get("name", id)).to_upper()
	_txt(name, Vector2(cx, 674), 60, tint.lightened(0.3) if unlocked else S.TEXT_DIM, true, 9)
	if unlocked:
		var lines := _wrap(String(s.get("description", "")), card.size.x - 100, 23)
		var y := 708.0 if lines.size() == 1 else 700.0
		for i in mini(2, lines.size()):
			_txt(lines[i], Vector2(cx, y + i * 27), 23, S.TEXT.darkened(0.08), true, 4, true)
		_draw_chips(s, Rect2(card.position.x + 36 + ox, 740 if lines.size() == 1 else 746, card.size.x - 72, 42))
	else:
		_draw_unlock_quest(String(s.get("unlock_quest", "")), cx, card)
	_draw_arrows(accent)
	_draw_page_dots(card)


func _status_badge(card: Rect2, id: String, owned: bool, unlocked: bool) -> void:
	var text := "IM BESITZ"
	var color := S.TOXIC
	if not unlocked:
		text = "GESPERRT"
		color = S.DANGER.lerp(S.TEXT, 0.35)
	elif not owned:
		text = "KAUFBAR · %d" % int(menu.profile.strain_cost(id))
		color = S.GOLD
	var w := _tw(text, S.SIZE_LABEL) + 58 + (26 if unlocked and not owned else 0)
	var badge := Rect2(card.position.x + 26, card.position.y + 22, w, 40)
	var shape := _rounded_points(badge, 20, 4)
	draw_colored_polygon(shape, Color(S.OUTLINE, 0.9))
	draw_colored_polygon(_rounded_points(badge.grow(-3), 17, 4), Color(color, 0.16))
	draw_polyline(_closed(shape), Color(color, 0.7), 2.0, true)
	var ic := badge.position + Vector2(22, 20)
	if not unlocked:
		_lock(ic + Vector2(0, -1), 12, color)
	elif owned:
		_check(ic, 11, color)
	else:
		_gem(ic, 7, color)
	_txt(text, badge.position + Vector2(42, 28), S.SIZE_LABEL, color, false, 4)
	if unlocked and not owned:
		var fc := badge.position + Vector2(badge.size.x - 24, 20)
		if not _icon(["crown_tooth"], Rect2(fc - Vector2(15, 15), Vector2(30, 30))):
			_fang(fc, 12, S.BONE)


func _draw_unlock_quest(quest_id: String, cx: float, card: Rect2) -> void:
	var q: Dictionary = menu.meta.quest(quest_id)
	var title := "TROPHÄE · %s" % String(q.get("name", quest_id)).to_upper()
	var tw := _tw(title, 24)
	_skull(Vector2(cx - tw * 0.5 - 20, 704), 12, S.GOLD)
	_txt(title, Vector2(cx + 14, 714), 24, S.GOLD, true, 5)
	_txt(String(q.get("description", "")), Vector2(cx, 744), S.SIZE_LABEL + 1, S.TEXT.darkened(0.1), true, 4, true)
	var progress: Vector2 = menu.profile.quest_progress(quest_id)
	var bar := Rect2(cx - 220, 762, 330, 18)
	_progress_bar(bar, clampf(progress.x / maxf(1.0, progress.y), 0.0, 1.0), S.GOLD)
	_txt(menu._progress_text(q, progress), Vector2(bar.end.x + 16, bar.position.y + 17), S.SIZE_LABEL, S.GOLD.lerp(S.TEXT, 0.4), false, 4)


func _progress_bar(rect: Rect2, fraction: float, color: Color) -> void:
	var back := _rounded_points(rect, rect.size.y * 0.5, 4)
	draw_colored_polygon(_rounded_points(rect.grow(3), rect.size.y * 0.5 + 3, 4), S.OUTLINE)
	draw_colored_polygon(back, S.PANEL_EDGE.darkened(0.3))
	if fraction > 0.0:
		var fill := Rect2(rect.position, Vector2(maxf(rect.size.y, rect.size.x * minf(fraction, 1.0)), rect.size.y))
		_fill_gradient(_rounded_points(fill, rect.size.y * 0.5, 4), color.lightened(0.3), color.darkened(0.2))
		draw_line(fill.position + Vector2(rect.size.y * 0.5, 4), Vector2(fill.end.x - rect.size.y * 0.5, fill.position.y + 4), Color(1, 1, 1, 0.35), 2.0)


func _draw_chips(s: Dictionary, area: Rect2) -> void:
	var mods: Dictionary = s.get("mods", {})
	var sig: String = s.get("signature", "")
	var chips: Array = []
	chips.append({"kind": "start", "icon": "mawling_head_color", "text": "%d" % int(s.get("start_population", 25)), "color": S.EMBER_GLOW})
	chips.append({"kind": "sig", "icon": sig, "text": String(menu.meta.MUTATION_NAMES.get(sig, sig)), "color": S.VIOLET})
	for pair in [["damage", "SCHADEN"], ["armor", "PANZER"], ["speed", "TEMPO"], ["growth", "WACHSTUM"], ["dna", "DNA"]]:
		var v := float(mods.get(pair[0], 0.0 if pair[0] == "armor" else 1.0))
		var delta := v * 100.0 if pair[0] == "armor" else (v - 1.0) * 100.0
		if absf(delta) >= 0.5:
			chips.append({"kind": "up" if delta > 0 else "down", "icon": "", "text": "%s %+d %%" % [pair[1], roundi(delta)], "color": S.TOXIC if delta > 0 else S.DANGER.lerp(S.TEXT, 0.2)})
	if s.has("rally_damage"):
		chips.append({"kind": "up", "icon": "", "text": "RALLY %+d %%" % roundi((float(s.rally_damage) - 1.0) * 100.0), "color": S.TOXIC})
	var fs := S.SIZE_LABEL + 1
	var gap := 10.0
	var total := -gap
	for c in chips:
		c["w"] = _tw(c.text, fs) + 58.0
		total += c.w + gap
	if total > area.size.x:
		fs = S.SIZE_LABEL
		total = -gap
		for c in chips:
			c["w"] = _tw(c.text, fs) + 50.0
			total += c.w + gap
	var x := area.position.x + maxf(0.0, (area.size.x - total) * 0.5)
	for c in chips:
		var r := Rect2(x, area.position.y, c.w, area.size.y)
		var shape := _rounded_points(r, 12, 3)
		draw_colored_polygon(_rounded_points(Rect2(r.position + Vector2(0, 4), r.size), 12, 3), S.SHADOW)
		_fill_gradient(shape, S.PANEL_SOFT.lightened(0.06), S.PANEL.darkened(0.3))
		draw_polyline(_closed(shape), Color(c.color, 0.55), 2.0, true)
		var ic := r.position + Vector2(22, r.size.y * 0.5)
		if c.icon != "" and _icon([c.icon], Rect2(ic - Vector2(17, 17), Vector2(34, 34))):
			pass
		else:
			_chip_glyph(c.kind, ic, c.color)
		_txt(c.text, Vector2(r.position.x + 42, r.position.y + r.size.y * 0.5 + fs * 0.36), fs, S.TEXT, false, 4)
		x += c.w + gap


func _chip_glyph(kind: String, ic: Vector2, color: Color) -> void:
	match kind:
		"start":
			_mawling_head(ic + Vector2(-1, 2), 13, color)
		"sig":
			_claw(ic + Vector2(-6, 9), Vector2(0.35, -1), 20, 5, color, 0.35)
			_claw(ic + Vector2(2, 9), Vector2(0.35, -1), 20, 5, color, 0.35)
		"up":
			draw_colored_polygon(PackedVector2Array([ic + Vector2(0, -9), ic + Vector2(8, 5), ic + Vector2(-8, 5)]), color)
		"down":
			draw_colored_polygon(PackedVector2Array([ic + Vector2(0, 9), ic + Vector2(8, -5), ic + Vector2(-8, -5)]), color)


func _draw_arrows(accent: Color) -> void:
	for i in 2:
		var rect: Rect2 = menu.strain_prev_rect() if i == 0 else menu.strain_next_rect()
		var dir := -1.0 if i == 0 else 1.0
		var tab := rect.grow_individual(-18, -6, -18, -6)
		var c := tab.get_center()
		if _frames != null:
			_frames.button(self, tab, "secondary")
		else:
			_panel(tab, Color(S.BONE, 0.75), S.PANEL.darkened(0.2), 0.0, 16.0, 0.0, 0, 2.5)
		_glow(c, Vector2(44, 60), Color(accent, 0.18))
		_arrow(c + Vector2(dir * 3, 2), 30, dir, S.OUTLINE)
		_arrow(c + Vector2(dir * 3, 0), 28, dir, S.BONE)


func _draw_page_dots(card: Rect2) -> void:
	var n: int = menu.strain_ids.size()
	for i in n:
		var p := Vector2(size.x * 0.5 + (i - (n - 1) * 0.5) * 34.0, card.end.y + 26.0)
		var other: String = menu.strain_ids[i]
		var open: bool = menu._strain_unlocked(other)
		var color: Color = menu._strain_color(other).lightened(0.3) if open else S.PANEL_EDGE.lightened(0.15)
		if i == menu.strain_index:
			_glow(p, Vector2(26, 26), Color(color, 0.5))
			_gem(p, 11, color)
		else:
			_gem(p, 6.5, Color(color, 0.8))

# ---------------------------------------------------------------- biomes

func _draw_biomes() -> void:
	for i in menu.meta.BIOME_ORDER.size():
		var id: String = menu.meta.BIOME_ORDER[i]
		var b: Dictionary = menu.meta.BIOMES[id]
		var rect: Rect2 = menu.biome_rect(i)
		var locked: bool = b.get("locked", false)
		var selected: bool = id == menu.biome_id
		var accent: Color = S.TOXIC if id == "verdant_maw" else S.EMBER
		var edge: Color = accent if selected else Color(accent, 0.45)
		if locked:
			edge = Color(S.TEXT_DIM, 0.35)
		_panel(rect, edge, S.PANEL, 0.9 if selected else 0.0, 18.0, 0.0, 0, 3.5 if selected else 2.0)
		_paint_biome(id, rect.grow(-5))
		# Readability scrim behind the text on the left.
		var scrim := Rect2(rect.position + Vector2(5, 5), Vector2(rect.size.x * 0.62, rect.size.y - 10))
		var dark := Color(S.OUTLINE, 0.85)
		var clear := Color(S.OUTLINE, 0.0)
		draw_polygon(PackedVector2Array([scrim.position + Vector2(8, 0), Vector2(scrim.end.x, scrim.position.y), scrim.end, Vector2(scrim.position.x + 8, scrim.end.y)]), PackedColorArray([dark, clear, clear, dark]))
		if locked:
			draw_colored_polygon(_shape(rect.grow(-5), 13.0), Color(S.OUTLINE, 0.5))
		# Redraw the rim over the painting.
		draw_polyline(_closed(_shape(rect, 18.0)), edge, 3.5 if selected else 2.0, true)
		var tx := rect.position.x + 24
		_txt(String(b.name).to_upper(), Vector2(tx, rect.position.y + 50), 29, S.TEXT if not locked else S.TEXT_DIM, false, 6)
		if locked:
			var status := String(b.get("status", "")).to_upper()
			var pill := Rect2(tx, rect.position.y + 64, _tw(status, S.SIZE_LABEL) + 52, 34)
			draw_colored_polygon(_rounded_points(pill, 17, 4), Color(S.EMBER.darkened(0.55), 0.95))
			draw_polyline(_closed(_rounded_points(pill, 17, 4)), Color(S.EMBER, 0.6), 2.0, true)
			_lock(pill.position + Vector2(20, 16), 10, S.EMBER_GLOW)
			_txt(status, pill.position + Vector2(36, 25), S.SIZE_LABEL, S.EMBER_GLOW, false, 3)
		elif selected:
			_check(Vector2(tx + 10, rect.position.y + 80), 10, accent)
			_txt("GEWÄHLT", Vector2(tx + 28, rect.position.y + 88), S.SIZE_LABEL, accent.lerp(S.TEXT, 0.3), false, 4)
		else:
			_txt("ANTIPPEN", Vector2(tx, rect.position.y + 88), S.SIZE_LABEL, S.TEXT_DIM, false, 4)


## Small painted landscape inside a biome tile (stays inside `r`).
func _paint_biome(id: String, r: Rect2) -> void:
	var cut := 13.0
	var verdant := id == "verdant_maw"
	var sky_top: Color = S.CYAN.darkened(0.55) if verdant else S.DANGER.darkened(0.7)
	var sky_low: Color = S.TOXIC.darkened(0.45) if verdant else S.EMBER.darkened(0.45)
	_fill_gradient(_shape(r, cut), sky_top, sky_low)
	var far: Color = S.TOXIC.darkened(0.55) if verdant else S.OUTLINE.lerp(S.DANGER, 0.25)
	var near: Color = S.TOXIC.darkened(0.35) if verdant else S.OUTLINE
	_hill(r, cut, 0.45, 0.10, 2.3, 0.7, far)
	_hill(r, cut, 0.66, 0.08, 3.1, 2.1, near)
	var ox := r.position.x
	var oy := r.position.y
	if verdant:
		_glow(Vector2(r.end.x - 70, oy + 26), Vector2(70, 40), Color(S.TEXT, 0.18))
		_ellipse(Vector2(r.end.x - 110, r.end.y - 22), 42, 9, S.CYAN.darkened(0.2))
		_ellipse(Vector2(r.end.x - 116, r.end.y - 24), 22, 4, Color(S.TEXT, 0.4))
		_leaf(Vector2(r.end.x - 20, r.end.y - 4), 56, 16, -2.2, S.TOXIC.darkened(0.1))
		_leaf(Vector2(r.end.x - 10, r.end.y - 20), 50, 14, -2.8, S.TOXIC.darkened(0.3))
		_leaf(Vector2(r.end.x - 170, r.end.y - 2), 44, 12, -1.2, S.TOXIC.darkened(0.2))
		for k in 3:
			var p := Vector2(r.end.x - 190 + k * 26, r.end.y - 36 - (k % 2) * 6)
			_mawling_head(p, 9, S.EMBER)
	else:
		for k in 4:
			var p := Vector2(r.end.x - 60 - k * 46, r.end.y - 18 - (k % 2) * 8)
			var pulse := 0.5 + 0.5 * sin(_time * 2.0 + k)
			_glow(p, Vector2(40, 16), Color(S.EMBER, 0.35 + 0.2 * pulse))
			_ellipse(p, 20, 5, S.EMBER_GLOW)
			draw_circle(p + Vector2(4, -10 - 10 * pulse), 3.0, Color(S.EMBER_GLOW, 0.8))
		for k in 2:
			var base := Vector2(r.end.x - 70 - k * 110, r.end.y - 20)
			draw_line(base, base + Vector2(6, -58), S.OUTLINE, 5.0, true)
			draw_line(base + Vector2(4, -36), base + Vector2(22, -50), S.OUTLINE, 3.0, true)
			draw_line(base + Vector2(5, -44), base + Vector2(-12, -58), S.OUTLINE, 3.0, true)


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
	draw_colored_polygon(points, color)

# ---------------------------------------------------------------- difficulty

func _draw_difficulties() -> void:
	for i in menu.meta.DIFFICULTIES.size():
		var d: Dictionary = menu.meta.DIFFICULTIES[i]
		var rect: Rect2 = menu.difficulty_rect(i)
		var unlocked: bool = menu._difficulty_unlocked(i)
		var selected: bool = i == menu.difficulty
		var accent: Color = menu.DIFFICULTY_COLORS[i] if unlocked else S.TEXT_DIM.darkened(0.2)
		var fill := S.PANEL.lerp(accent, 0.16) if selected else S.PANEL
		_panel(rect, accent if selected else Color(accent, 0.45), fill, 0.9 if selected else 0.0, 16.0, 0.0, 0, 3.5 if selected else 2.0)
		var c := rect.get_center()
		var name := String(d.name).to_upper()
		if unlocked:
			var n: int = i + 1
			if selected:
				_glow(Vector2(c.x, rect.position.y + 32), Vector2(30 + n * 20, 30), Color(accent, 0.45))
			if not _icon([["diff_wild", "diff_brutal", "diff_apex"][i]], Rect2(c.x - 30, rect.position.y + 2, 60, 60)):
				for k in n:
					var p := Vector2(c.x + (k - (n - 1) * 0.5) * 34.0, rect.position.y + 32)
					_skull(p + Vector2(0, 2), 15, S.OUTLINE)
					_skull(p, 14, accent.lerp(S.BONE, 0.25))
			_txt(name, Vector2(c.x, rect.position.y + 78), 30, S.TEXT if selected else S.TEXT.darkened(0.15), true, 6)
			var reward := "×%.1f ESSENZ" % float(d.get("reward", 1.0))
			var rw := _tw(reward, S.SIZE_LABEL - 1) + 26.0
			var ec := Vector2(c.x - rw * 0.5 + 10, rect.position.y + 94)
			if not _icon(["essence"], Rect2(ec - Vector2(12, 12), Vector2(24, 24))):
				_essence_drop(ec, 8, S.VIOLET)
			_txt(reward, Vector2(c.x - rw * 0.5 + 26, rect.position.y + 101), S.SIZE_LABEL - 1, S.VIOLET.lerp(S.TEXT, 0.45), false, 4)
		else:
			draw_colored_polygon(_shape(rect.grow(-4), 12.0), Color(S.OUTLINE, 0.35))
			_lock(Vector2(c.x, rect.position.y + 30), 15, S.TEXT_DIM)
			_txt(name, Vector2(c.x, rect.position.y + 76), 28, S.TEXT_DIM, true, 5)
			var q: Dictionary = menu.meta.quest(d.get("unlock_quest", ""))
			_txt(String(q.get("name", "")), Vector2(c.x, rect.position.y + 101), S.SIZE_LABEL - 1, S.GOLD.darkened(0.1), true, 4)

# ---------------------------------------------------------------- main button

func _draw_play() -> void:
	var rect: Rect2 = menu.play_rect()
	var id: String = menu.current_strain()
	var owned: bool = menu._strain_owned(id)
	var unlocked: bool = menu._strain_unlocked(id)
	var c := rect.get_center()
	if owned:
		var ok: bool = menu.can_play()
		_button(rect, S.EMBER if ok else S.TEXT_DIM.darkened(0.3), ok)
		var label := "SPIELEN"
		var fs := 74
		var w := _tw(label, fs)
		var head_c := c + Vector2(-w * 0.5 - 20, -2)
		if not _icon(["mawling_head"], Rect2(head_c - Vector2(40, 40), Vector2(80, 80))):
			_mawling_head(head_c + Vector2(0, 3), 34, S.OUTLINE)
			_mawling_head(head_c, 33, S.BONE)
		_txt(label, c + Vector2(22, 26), fs, S.TEXT, true, 10)
	elif unlocked:
		var price := int(menu.profile.strain_cost(id))
		var affordable: bool = int(menu.profile.crowns) >= price
		_button(rect, S.AMBER.darkened(0.2) if affordable else S.TEXT_DIM.darkened(0.35), affordable, S.GOLD if affordable else Color(0, 0, 0, 0))
		var label := "KAUFEN  %d" % price
		var fs := 60
		var w := _tw(label, fs)
		_txt(label, c + Vector2(-24, 12), fs, S.TEXT if affordable else S.TEXT_DIM, true, 9)
		var fc := c + Vector2(w * 0.5 + 6, -8)
		if not _icon(["crown_tooth"], Rect2(fc - Vector2(30, 30), Vector2(60, 60))):
			_fang(fc, 24, S.BONE)
		_txt("KÖNIGSZÄHNE" if affordable else "ZU WENIGE KÖNIGSZÄHNE", c + Vector2(0, 48), S.SIZE_LABEL, S.TEXT if affordable else S.GOLD.lerp(S.TEXT_DIM, 0.4), true, 5)
	else:
		_button(rect, S.TEXT_DIM.darkened(0.4), false)
		var fs := 56
		var w := _tw("GESPERRT", fs)
		_lock(c + Vector2(-w * 0.5 - 16, -12), 22, S.TEXT_DIM)
		_txt("GESPERRT", c + Vector2(22, 8), fs, S.TEXT_DIM, true, 8)
		var q: Dictionary = menu.meta.quest(menu._strain(id).get("unlock_quest", ""))
		_txt("Trophäe: " + String(q.get("name", "")), c + Vector2(0, 46), S.SIZE_LABEL, S.GOLD, true, 5)
	# Record line and the closest open trophy.
	var best := float(menu.profile.records.get("best_seconds", 0.0))
	var peak := int(menu.profile.records.get("best_peak", 0))
	var ry := rect.end.y + 38
	var part_a := "REKORD %02d:%02d" % [int(best) / 60, int(best) % 60]
	var part_b := "MAX. SCHWARM %d" % peak
	var wa := _tw(part_a, S.SIZE_LABEL)
	var wb := _tw(part_b, S.SIZE_LABEL)
	var total := 26 + wa + 46 + 26 + wb
	var x := size.x * 0.5 - total * 0.5
	draw_arc(Vector2(x + 10, ry - 8), 10, 0, TAU, 20, S.TEXT_DIM, 2.5, true)
	draw_line(Vector2(x + 10, ry - 8), Vector2(x + 10, ry - 14), S.TEXT_DIM, 2.0)
	draw_line(Vector2(x + 10, ry - 8), Vector2(x + 15, ry - 6), S.TEXT_DIM, 2.0)
	_txt(part_a, Vector2(x + 26, ry), S.SIZE_LABEL, S.TEXT.darkened(0.12), false, 4)
	_gem(Vector2(x + 26 + wa + 23, ry - 8), 4, S.TEXT_DIM)
	_mawling_head(Vector2(x + 26 + wa + 46 + 10, ry - 8), 11, S.EMBER_GLOW)
	_txt(part_b, Vector2(x + 26 + wa + 46 + 26, ry), S.SIZE_LABEL, S.TEXT.darkened(0.12), false, 4)
	_draw_next_trophy(Rect2(28, rect.end.y + 54, size.x - 56, 82))


## Dominant glowing button with fang tips, gradient body, bevel and a moving shine.
func _button(rect: Rect2, color: Color, live: bool, top: Color = Color(0, 0, 0, 0)) -> void:
	var c := rect.get_center()
	var tip := 46.0
	if live:
		_glow(c, Vector2(rect.size.x * 0.66, rect.size.y * 1.05), Color(color, 0.3 + 0.18 * _pulse(2.2)))
	var shape := _button_shape(rect, tip)
	draw_colored_polygon(_button_shape(Rect2(rect.position + Vector2(0, 10), rect.size), tip), S.SHADOW)
	draw_colored_polygon(_button_shape(rect.grow(7), tip + 4), S.OUTLINE)
	if live:
		draw_colored_polygon(_button_shape(rect.grow(4), tip + 2), color.lightened(0.45))
	# Three-stop gradient: the upper and lower halves are filled separately.
	var top_c: Color = (S.EMBER_GLOW if color == S.EMBER else color.lightened(0.35)) if live else color.lightened(0.05)
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
	draw_colored_polygon(bevel, Color(1, 1, 1, 0.13 if live else 0.05))
	if live:
		var sweep := fposmod(_time * 0.5, 2.6)
		if sweep < 1.0:
			var sx := lerpf(rect.position.x + tip + 10, rect.end.x - tip - 60, sweep)
			var y0 := rect.position.y + 6
			var y1 := rect.end.y - 6
			draw_colored_polygon(PackedVector2Array([Vector2(sx + 30, y0), Vector2(sx + 58, y0), Vector2(sx + 28, y1), Vector2(sx, y1)]), Color(1, 1, 1, 0.16 * sin(sweep * PI)))
	draw_polyline(_closed(shape), color.lightened(0.5) if live else color, 3.0, true)
	# Bone claws hooking out of both tips.
	for side in [-1.0, 1.0]:
		var base := Vector2(c.x + side * (rect.size.x * 0.5 - 4), c.y)
		_claw(base + Vector2(0, 2), Vector2(side, -0.9), 36, 9, S.OUTLINE, -0.5 * side)
		_claw(base, Vector2(side, -0.9), 34, 8, S.BONE, -0.5 * side)
		_claw(base + Vector2(0, 8), Vector2(side, 0.8), 24, 6, S.BONE.darkened(0.2), 0.4 * side)


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


func _draw_next_trophy(rect: Rect2) -> void:
	var q: Dictionary = menu._next_quest()
	if q.is_empty():
		return
	var accent := S.VIOLET
	_panel(rect, Color(accent, 0.6), S.PANEL, 0.0, 16.0, 0.0, 0, 2.0)
	var ic := rect.position + Vector2(46, rect.size.y * 0.5)
	_socket(ic, 28, accent, 0.7)
	if not _icon(["trophy"], Rect2(ic - Vector2(22, 22), Vector2(44, 44))):
		_skull(ic + Vector2(0, 4), 13, accent.lerp(S.BONE, 0.3))
		_crown(ic + Vector2(0, -14), 9, S.GOLD)
	_txt("NÄCHSTE TROPHÄE", rect.position + Vector2(90, 32), S.SIZE_LABEL - 1, accent.lerp(S.TEXT, 0.35), false, 4)
	_txt(String(q.name), rect.position + Vector2(90, 66), 28, S.TEXT, false, 5)
	var progress: Vector2 = menu.profile.quest_progress(q.id)
	var bar := Rect2(rect.end.x - 262, rect.position.y + 48, 232, 16)
	_progress_bar(bar, clampf(progress.x / maxf(1.0, progress.y), 0.0, 1.0), accent)
	var ptxt: String = menu._progress_text(q, progress)
	_txt(ptxt, Vector2(bar.end.x - _tw(ptxt, S.SIZE_LABEL), rect.position.y + 36), S.SIZE_LABEL, S.TEXT, false, 4)

# ---------------------------------------------------------------- tabs

func _draw_tabs() -> void:
	var first: Rect2 = menu.tab_rect(0)
	var dock := Rect2(0, first.position.y - 16, size.x, size.y - first.position.y + 16)
	_fill_gradient(PackedVector2Array([dock.position, Vector2(dock.end.x, dock.position.y), dock.end, Vector2(dock.position.x, dock.end.y)]), Color(S.OUTLINE, 0.55), Color(S.OUTLINE, 0.95))
	draw_line(dock.position, Vector2(dock.end.x, dock.position.y), Color(S.PANEL_EDGE, 0.9), 2.0)
	var names: Dictionary = menu.TAB_NAMES
	var accents := [S.CYAN, S.GOLD, S.EMBER]
	for i in menu.TABS.size():
		var id: String = menu.TABS[i]
		var rect: Rect2 = menu.tab_rect(i)
		var active: bool = menu.tab == id
		var accent: Color = accents[i]
		var fill := S.PANEL.lerp(accent, 0.14) if active else S.PANEL
		_panel(rect, accent if active else Color(accent, 0.45), fill, 1.0 if active else 0.0, 18.0, 0.0, (1 | 2) if active else 0, 3.0 if active else 2.0)
		var ic := Vector2(rect.get_center().x, rect.position.y + 42)
		if active:
			_glow(ic, Vector2(56, 40), Color(accent, 0.4))
		if not _icon([["brood"], ["trophy"], ["mawling_head_color"]][i], Rect2(ic - Vector2(32, 32), Vector2(64, 64))):
			_tab_icon(id, ic, accent)
		_txt(String(names[id]), Vector2(rect.get_center().x, rect.position.y + 96), S.SIZE_LABEL + 1, S.TEXT if active else S.TEXT.darkened(0.15), true, 5)
		var badge := ""
		if id == "upgrades":
			var n: int = menu._affordable_upgrades()
			badge = "%d" % n if n > 0 else ""
		elif id == "instinct" and int(menu.profile.essence) >= int(menu._instinct_cost()):
			badge = "!"
		if badge != "" and not active:
			var bc := Vector2(rect.end.x - 20, rect.position.y + 18)
			var pop := 1.0 + 0.08 * _pulse(3.0)
			draw_circle(bc, 19 * pop, S.OUTLINE)
			draw_circle(bc, 16 * pop, S.DANGER)
			draw_circle(bc + Vector2(-4, -5), 5, Color(1, 1, 1, 0.3))
			_txt(badge, bc + Vector2(0, 8), S.SIZE_LABEL, S.TEXT, true, 3)


func _tab_icon(id: String, c: Vector2, accent: Color) -> void:
	match id:
		"upgrades":
			# Three brood eggs in a nest.
			_ellipse(c + Vector2(0, 17), 30, 8, S.PANEL_EDGE.darkened(0.2))
			for e in [[Vector2(-15, 4), 0.95], [Vector2(15, 4), 0.95], [Vector2(0, -6), 1.1]]:
				var p: Vector2 = c + e[0]
				var k: float = e[1]
				_ellipse(p + Vector2(0, 2), 12 * k, 16 * k, S.OUTLINE)
				_ellipse(p, 11 * k, 15 * k, accent)
				draw_circle(p + Vector2(-3, -5) * k, 3 * k, Color(1, 1, 1, 0.45))
				draw_circle(p + Vector2(4, 4) * k, 2.2 * k, accent.darkened(0.45))
				draw_circle(p + Vector2(-4, 6) * k, 1.6 * k, accent.darkened(0.45))
		"trophies":
			_skull(c + Vector2(0, 8), 18, S.OUTLINE)
			_skull(c + Vector2(0, 6), 17, S.BONE)
			_crown(c + Vector2(0, -15), 12, accent)
		_:
			_mawling_head(c + Vector2(0, 3), 26, S.OUTLINE)
			_mawling_head(c, 25, accent)
