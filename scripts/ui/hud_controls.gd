extends Control

# Stage 04 component "CONTROLS": Rally button (left), movement joystick (right)
# and the hint banner above them. Replaces `legacy.controls` in touch_controls.gd.
# Input stays in the parent; this node only draws at the parent's centres
# (_rally_center(), _movement_center()) so the touch areas are unchanged.

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const ICONS_PATH := "res://scripts/ui/ui_icons.gd"
const FRAMES_PATH := "res://scripts/ui/ui_frames.gd"
const DIR := "res://assets/ui/controls/"

# Visual radii in base-viewport pixels. The touch radius in the parent is 125.
const FRAME_R := 126.0
const RALLY_R := 106.0
const JOY_R := 104.0
const KNOB_R := 50.0
const KNOB_TRAVEL := 52.0
const BANNER_GAP := 52.0  # space between banner and the top claws

var _icons: Script = null
var _icons_checked := false
var _frames: Script = null
var _frames_checked := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	var hud := _hud()
	if hud != null and size != hud.size:
		position = Vector2.ZERO
		size = hud.size
	queue_redraw()


func _hud() -> Control:
	return get_parent() as Control


func _visible_now(hud: Control) -> bool:
	if hud == null or hud.extinct or hud.paused:
		return false
	return not (hud.has_method("_choosing") and hud._choosing())


func _draw() -> void:
	var hud := _hud()
	if not _visible_now(hud):
		return
	var rally_c: Vector2 = hud._rally_center()
	var move_c: Vector2 = hud._movement_center()
	if hud.hint != "":
		_draw_hint(hud.hint, minf(rally_c.y, move_c.y) - FRAME_R - 30.0 - BANNER_GAP)
	_draw_rally(rally_c, hud.rally_pressed)
	_draw_joystick(move_c, hud.movement_vector)


# ---------------------------------------------------------------- helpers

func _t() -> float:
	return Time.get_ticks_msec() * 0.001


func _pulse(speed: float) -> float:
	return 0.5 + 0.5 * sin(_t() * speed)


func _tex_at(name: String, center: Vector2, tex_size: Vector2, tint: Color = Color.WHITE, angle: float = 0.0) -> bool:
	var texture := UiStyle.tex(DIR + name)
	if texture == null:
		return false
	draw_set_transform(center, angle, Vector2.ONE)
	draw_texture_rect(texture, Rect2(-tex_size * 0.5, tex_size), false, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


func _glow(center: Vector2, radius: float, color: Color) -> void:
	if not _tex_at("glow.svg", center, Vector2.ONE * radius * 2.0, color):
		for i in 4:
			draw_circle(center, radius * (1.0 - i * 0.2), Color(color, color.a * 0.25))


# Bone claws gripping the frame like talons: each one sits on the rim and
# curls along it (tangential), as in the active-HUD concept. `side` mirrors
# the set for the right-hand joystick.
const CLAWS := [
	# [angle from up in degrees, length, lean in degrees, hooks inward]
	# Top cluster grips over the rim toward the button, bottom pair hangs out.
	[-64.0, 58.0, 52.0, true], [-44.0, 66.0, 50.0, true], [-24.0, 60.0, 48.0, true], [-6.0, 50.0, 46.0, true],
	[142.0, 62.0, -40.0, false], [164.0, 70.0, -34.0, false],
]


func _claws(c: Vector2, side: float, alpha: float) -> void:
	var texture := UiStyle.tex(DIR + "claw.svg")
	if texture == null:
		return
	for claw in CLAWS:
		var deg: float = float(claw[0]) * side
		var length: float = claw[1]
		var lean: float = float(claw[2]) * side
		var inward: bool = claw[3]
		var dir := Vector2.UP.rotated(deg_to_rad(deg))
		var base: Vector2
		var angle: float
		if inward:
			# Rooted outside the frame, the tip hooks back over the rim.
			base = c + dir * (FRAME_R + 16.0)
			angle = deg_to_rad(deg + 180.0 + lean)
		else:
			base = c + dir * (FRAME_R - 14.0)
			angle = deg_to_rad(deg + lean)
		# Texture: base at the bottom, tip at the top curling toward +x.
		var flip := side if inward else -side
		draw_set_transform(base, angle, Vector2(flip, 1.0))
		draw_texture_rect(texture, Rect2(Vector2(-length * 0.24, -length), Vector2(length * 0.5, length)), false, Color(UiStyle.BONE, alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _frame_ring(c: Vector2, alpha: float, spin: float) -> void:
	if not _tex_at("frame_ring.svg", c, Vector2.ONE * FRAME_R * 2.0, Color(1, 1, 1, alpha), spin):
		draw_circle(c, FRAME_R, Color(UiStyle.PANEL, alpha))
		draw_arc(c, FRAME_R - 2.0, 0.0, TAU, 64, Color(UiStyle.PANEL_EDGE, alpha), 3.0, true)


# ---------------------------------------------------------------- rally

func _draw_rally(c: Vector2, pressed: bool) -> void:
	var breathe := _pulse(2.4)
	var glow_color := Color(UiStyle.EMBER, 0.5 + 0.22 * breathe)
	var glow_r := FRAME_R + 26.0 + 6.0 * breathe
	if pressed:
		glow_color = Color(UiStyle.EMBER_GLOW, 0.7)
		glow_r = FRAME_R + 40.0
	_glow(c, glow_r, glow_color)
	_frame_ring(c, 0.96, 0.0)
	_claws(c, 1.0, 1.0)
	# Core disc with its ember ring; the whole disc sinks a little when held.
	var core_r := RALLY_R - (5.0 if pressed else 0.0)
	if not _tex_at("rally_core.svg", c, Vector2.ONE * core_r * 2.0):
		draw_circle(c, core_r, Color("5e200c"))
		draw_arc(c, core_r - 5.0, 0.0, TAU, 64, UiStyle.EMBER, 8.0, true)
	# Warm rim light breathes at rest; held, the core flares up.
	draw_arc(c, core_r - 5.0, 0.0, TAU, 72, Color(UiStyle.EMBER_GLOW, 0.35 + 0.45 * breathe), 4.0, true)
	if pressed:
		draw_circle(c, core_r - 9.0, Color(UiStyle.EMBER, 0.92))
		_glow(c + Vector2(0, -8), core_r * 0.95, Color(UiStyle.EMBER_GLOW, 1.0))
		_glow(c + Vector2(0, -12), 52.0, Color(UiStyle.TEXT, 0.95))
	else:
		_glow(c + Vector2(0, -14), 58.0, Color(UiStyle.EMBER, 0.18 + 0.14 * breathe))
	var heads_size := Vector2(180, 155)
	# Held: the heads turn into dark silhouettes against the flaring core.
	var heads_tint := Color(0.42, 0.16, 0.07) if pressed else Color.WHITE
	if not _tex_at("rally_heads.svg", c + Vector2(-6, -30), heads_size, heads_tint):
		draw_circle(c + Vector2(0, -24), 34, UiStyle.EMBER)
	# Held: bright rings contract from the rim toward the heads (the swarm pulls in).
	if pressed:
		for i in 3:
			var phase := fposmod(_t() * 1.4 + i / 3.0, 1.0)
			var r := lerpf(core_r + 18.0, core_r - 34.0, phase)
			var fade := sin(phase * PI)
			draw_arc(c, r, 0.0, TAU, 72, Color(UiStyle.TEXT, 0.9 * fade), lerpf(9.0, 3.0, phase), true)
	UiStyle.text(self, "RALLY", c + Vector2(0, 58), UiStyle.SIZE_HEAD, UiStyle.TEXT, true, 7)
	var sub := "AKTIV" if pressed else "HALTEN"
	var sub_color: Color = UiStyle.EMBER_GLOW.lerp(Color.WHITE, 0.55) if pressed else UiStyle.TEXT_DIM.lerp(UiStyle.EMBER_GLOW, 0.35)
	UiStyle.text(self, sub, c + Vector2(0, 84), UiStyle.SIZE_LABEL, sub_color, true, 5)


# ---------------------------------------------------------------- joystick

func _draw_joystick(c: Vector2, move: Vector2) -> void:
	var strength := clampf(move.length(), 0.0, 1.0)
	# Bark crescent on the outer (screen-edge) side carries the claws.
	draw_arc(c, JOY_R + 10.0, -PI * 0.62, PI * 0.62, 48, Color(UiStyle.PANEL, 0.92), 20.0, true)
	draw_arc(c, JOY_R + 19.0, -PI * 0.6, PI * 0.6, 48, Color(UiStyle.PANEL_EDGE, 0.8), 2.5, true)
	draw_arc(c, JOY_R + 3.0, 0.0, TAU, 72, Color(UiStyle.OUTLINE, 0.55), 5.0, true)
	_claws(c, -1.0, 0.95)
	if not _tex_at("joy_base.svg", c, Vector2.ONE * JOY_R * 2.0):
		draw_circle(c, JOY_R, Color("0c1d1a88"))
		draw_arc(c, JOY_R - 3.0, 0.0, TAU, 64, Color(1, 1, 1, 0.42), 3.0, true)
	# Direction wedge glow under the knob.
	if strength > 0.05:
		_glow(c + move.normalized() * 58.0, 64.0, Color(UiStyle.EMBER_GLOW, 0.3 * strength))
	for i in 4:
		var dir := Vector2.RIGHT.rotated(i * PI * 0.5)
		var lit := clampf(move.dot(dir), 0.0, 1.0)
		var tip := c + dir * 80.0
		if lit > 0.15:
			_glow(tip, 30.0 + 10.0 * lit, Color(UiStyle.EMBER_GLOW, 0.55 * lit))
		var tint := Color(1, 1, 1, 0.42).lerp(Color(UiStyle.EMBER_GLOW, 1.0), lit)
		if not _tex_at("arrow.svg", tip, Vector2(38, 38) * (1.0 + 0.3 * lit), tint, dir.angle()):
			var side := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([tip + dir * 8, tip - dir * 8 + side * 11, tip - dir * 8 - side * 11]), tint)
	var knob := c + move.limit_length(1.0) * KNOB_TRAVEL
	if not _tex_at("joy_knob.svg", knob + Vector2(0, 4), Vector2.ONE * KNOB_R * 2.46):
		draw_circle(knob, KNOB_R, Color("d8e6e0f0"))


# ---------------------------------------------------------------- hint banner

func _is_warning(text: String) -> bool:
	var upper := text.to_upper()
	return upper.begins_with("RAUS") or upper.begins_with("SPRINT")


func _draw_hint(text: String, top: float) -> void:
	var warn := _is_warning(text)
	var font := UiStyle.display_font()
	var font_size := UiStyle.SIZE_HEAD - 4 if warn else UiStyle.SIZE_BODY
	var icon_space := 46.0 if warn else 0.0
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var max_w := size.x - 72.0
	var width := clampf(text_w + icon_space + 88.0, 380.0, max_w)
	if text_w + icon_space + 88.0 > max_w:
		font_size = maxi(UiStyle.SIZE_LABEL, int(font_size * (max_w - icon_space - 88.0) / text_w))
		text_w = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var height := 66.0 if warn else 60.0
	var rect := Rect2(Vector2(size.x * 0.5 - width * 0.5, top), Vector2(width, height))
	var beat := _pulse(9.0) if warn else 0.0
	var accent: Color = UiStyle.DANGER if warn else UiStyle.TOXIC.lerp(UiStyle.BONE, 0.35)
	var frames := _frames_script()
	if frames != null and ResourceLoader.exists("res://assets/ui/frames/panel_body.svg"):
		# Shared organic panel from the frame kit; warnings add a pulsing red fill and halo.
		if warn:
			for k in 2:
				var halo := _banner_points(rect.grow(4.0 + 5.0 * k + 3.0 * beat), 18.0)
				draw_polyline(_closed(halo), Color(UiStyle.DANGER, (0.85 - 0.4 * k) * (0.45 + 0.55 * beat)), 5.0 - k, true)
		frames.panel(self, rect, accent.lerp(Color.WHITE, 0.25 * beat), true)
		if warn:
			var inner_rect: Rect2 = frames.panel_inner(rect)
			draw_colored_polygon(_banner_points(inner_rect, 8.0), Color(UiStyle.DANGER, 0.42 + 0.22 * beat))
	else:
		_draw_banner_fallback(rect, warn, accent, beat)
	var content_w := text_w + icon_space
	var x := rect.get_center().x - content_w * 0.5
	var baseline := rect.position.y + height * 0.5 + font_size * 0.36
	if warn:
		_warn_icon(Vector2(x + 18.0, rect.get_center().y), 19.0 + 2.0 * beat, UiStyle.DANGER.lerp(UiStyle.GOLD, 0.35 * beat))
	var text_color: Color = Color.WHITE.lerp(Color("ffd9c8"), beat) if warn else UiStyle.TEXT
	UiStyle.text(self, text, Vector2(x + icon_space, baseline), font_size, text_color, false, 7)


func _draw_banner_fallback(rect: Rect2, warn: bool, accent: Color, beat: float) -> void:
	var height := rect.size.y
	var outer := _banner_points(rect, 16.0)
	var inner := _banner_points(rect.grow(-5.0), 12.0)
	draw_colored_polygon(_offset(outer, Vector2(0, 5)), UiStyle.SHADOW)
	draw_colored_polygon(outer, Color("2a0c08f0") if warn else UiStyle.PANEL)
	draw_colored_polygon(inner, Color(UiStyle.DANGER, 0.16 + 0.18 * beat) if warn else Color(UiStyle.PANEL_SOFT, 0.9))
	_veins(rect, Color(accent, 0.22))
	var edge := accent.lerp(Color.WHITE, 0.25 * beat)
	draw_polyline(_closed(outer), edge, 3.0 if not warn else 4.0, true)
	draw_polyline(_closed(inner), Color(edge, 0.3), 1.5, true)
	# Bone teeth on both ends of the banner.
	for s: float in [-1.0, 1.0]:
		var base_x := rect.get_center().x + s * (rect.size.x * 0.5 - 2.0)
		for k in 2:
			var y := rect.position.y + height * (0.32 + 0.36 * k)
			var tip := Vector2(base_x + s * 16.0, y)
			draw_colored_polygon(PackedVector2Array([Vector2(base_x - s * 4.0, y - 8), tip, Vector2(base_x - s * 4.0, y + 8)]), UiStyle.BONE)
			draw_polyline(PackedVector2Array([Vector2(base_x - s * 4.0, y - 8), tip, Vector2(base_x - s * 4.0, y + 8)]), UiStyle.OUTLINE, 1.5, true)


func _frames_script() -> Script:
	if not _frames_checked:
		_frames_checked = true
		if ResourceLoader.exists(FRAMES_PATH):
			_frames = load(FRAMES_PATH)
	return _frames


func _warn_icon(center: Vector2, radius: float, color: Color) -> void:
	var icons := _icons_script()
	if icons != null and icons.has("skull"):
		icons.draw(self, "skull", Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), color)
		return
	var pts := PackedVector2Array([center + Vector2(0, -radius), center + Vector2(radius * 1.05, radius * 0.8), center + Vector2(-radius * 1.05, radius * 0.8)])
	draw_colored_polygon(pts, color)
	draw_polyline(_closed(pts), UiStyle.OUTLINE, 2.0, true)
	draw_rect(Rect2(center + Vector2(-2.5, -radius * 0.45), Vector2(5, radius * 0.7)), UiStyle.OUTLINE)
	draw_circle(center + Vector2(0, radius * 0.5), 3.0, UiStyle.OUTLINE)


func _icons_script() -> Script:
	if not _icons_checked:
		_icons_checked = true
		if ResourceLoader.exists(ICONS_PATH):
			_icons = load(ICONS_PATH)
	return _icons


# Chamfered banner with two small notches on the long edges.
func _banner_points(rect: Rect2, cut: float) -> PackedVector2Array:
	var p := rect.position
	var e := rect.end
	var mid := rect.get_center().x
	var notch := 6.0
	return PackedVector2Array([
		Vector2(p.x + cut, p.y), Vector2(mid - 70, p.y), Vector2(mid - 60, p.y + notch), Vector2(mid + 60, p.y + notch), Vector2(mid + 70, p.y),
		Vector2(e.x - cut, p.y), Vector2(e.x, p.y + cut), Vector2(e.x, e.y - cut), Vector2(e.x - cut, e.y),
		Vector2(mid + 40, e.y), Vector2(mid + 32, e.y - notch), Vector2(mid - 32, e.y - notch), Vector2(mid - 40, e.y),
		Vector2(p.x + cut, e.y), Vector2(p.x, e.y - cut), Vector2(p.x, p.y + cut),
	])


func _veins(rect: Rect2, color: Color) -> void:
	var seed_points := [0.12, 0.27, 0.73, 0.88]
	for f in seed_points:
		var x: float = rect.position.x + rect.size.x * f
		var pts := PackedVector2Array()
		for k in 5:
			var t := k / 4.0
			pts.append(Vector2(x + sin(t * 5.0 + f * 20.0) * 10.0, rect.position.y + 8.0 + (rect.size.y - 16.0) * t))
		draw_polyline(pts, color, 1.5, true)


func _offset(points: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in points:
		out.append(point + by)
	return out


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := points.duplicate()
	out.append(points[0])
	return out
