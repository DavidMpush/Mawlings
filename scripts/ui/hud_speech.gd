extends Control

# Etappe 25 (S12/S10): speech bubbles and the boss-entrance vignette.
# scripts/drama.gd decides WHAT is said and publishes it as the HUD meta
#   "speech"         {} or {speaker, name, icon, text, tone, boss, age}
#   "drama_vignette" {serial, seconds}: a new serial darkens the screen edge
# This component only draws: a portrait plate at the LEFT edge (never in the
# middle; the swarm keeps the centre) with a kit bubble beside it and the name
# chip on top. The bubble is a cached UiLayer (one texture while it shows);
# pop-in and fade-out run through the layer's scale/modulate, no repaint.

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const UiLayer := preload("res://scripts/ui/ui_layer.gd")
const UiIcons := preload("res://scripts/ui/ui_icons.gd")
const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")
const PLATE := 104.0
const EDGE := 16.0
const MAX_W_SHARE := 0.6        # bubble + plate at most 60 % of the width
const MIN_GAP_TOP := 22.0       # at least this far below the top HUD stack ...
const BANNER_CLEAR := 118.0     # ... and below the moment banners (hud_overlays BANNER_Y + sub line)
const MAX_LINES := 2
const POP_SECONDS := 0.16
const FADE_SECONDS := 0.25
const SHOW_SECONDS := 2.6       # = drama.gd SHOW_SECONDS
const VIGNETTE_ALPHA := 0.55

var _layer: Control
var _line: Dictionary = {}
var _vignette_serial := 0
var _vignette_t := -1.0
var _vignette_len := 0.6


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer = UiLayer.make(self, "Speech", _paint, true)


func _process(delta: float) -> void:
	var hud := get_parent()
	if hud == null:
		return
	var line: Dictionary = hud.get_meta("speech", {}) if hud.has_meta("speech") else {}
	var extinct := bool(hud.get("extinct"))
	_line = {} if extinct else line
	var shown := not _line.is_empty() and UiStyle.is_brawl()
	_layer.visible = shown
	# Loot popups (hud_overlays) step aside from the bubble.
	hud.set_meta("speech_rect", bubble_rect() if shown else Rect2())
	if shown:
		var rect := bubble_rect()
		_layer.region = Rect2(rect.position - Vector2(12, 40), rect.size + Vector2(24, 64)).abs()
		_layer.refresh([_line.get("speaker", ""), _line.get("text", ""), rect, size])
		var age := float(_line.get("age", 0.0))
		var pop := clampf(age / POP_SECONDS, 0.0, 1.0)
		var fade := clampf((SHOW_SECONDS - age) / FADE_SECONDS, 0.0, 1.0)
		_layer.pivot_offset = Vector2(rect.position.x, rect.get_center().y)
		_layer.scale = Vector2.ONE * lerpf(0.86, 1.0, 1.0 - pow(1.0 - pop, 3.0))
		_layer.modulate = Color(1, 1, 1, minf(pop * 1.6, fade))
	# Boss entrance: the screen edge darkens for a moment.
	var vignette: Variant = hud.get_meta("drama_vignette", {}) if hud.has_meta("drama_vignette") else {}
	if vignette is Dictionary and int((vignette as Dictionary).get("serial", 0)) != _vignette_serial:
		_vignette_serial = int(vignette.serial)
		_vignette_len = maxf(0.1, float(vignette.get("seconds", 0.6)))
		_vignette_t = 0.0
	if _vignette_t >= 0.0:
		_vignette_t += delta / maxf(0.01, Engine.time_scale)
		if _vignette_t > _vignette_len:
			_vignette_t = -1.0
		queue_redraw()


## Screen rect of the whole speech element (plate + bubble); public for tests.
func bubble_rect() -> Rect2:
	var text := String(_line.get("text", ""))
	var name_text := String(_line.get("name", ""))
	# Plate + gap + text + padding stays inside MAX_W_SHARE of the width.
	var max_w := size.x * MAX_W_SHARE - EDGE - PLATE - 18.0
	var text_w := minf(max_w - 48.0, UiStyle.body_bold_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.T_BODY).x)
	text_w = maxf(text_w, UiStyle.display_font().get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.T_LABEL).x + 24.0)
	var lines := Kit.wrap_lines(text, UiStyle.body_bold_font(), UiStyle.T_BODY, text_w + 1.0).size()
	var h := maxf(PLATE - 8.0, 40.0 + 32.0 * float(mini(lines, MAX_LINES)))
	var top := maxf(_banner_bottom(), _top_stack() + MIN_GAP_TOP)
	return Rect2(EDGE, top, PLATE + 18.0 + text_w + 48.0, maxf(PLATE, h))


## The screen's middle kept free for the swarm (tests check bubble_rect against it).
func center_zone() -> Rect2:
	return Rect2(size.x * 0.3, size.y * 0.4, size.x * 0.4, size.y * 0.2)


# Lower edge of the banner band of hud_overlays (title ribbon + sub line), so a
# boss entrance banner and the boss's line never cover each other.
func _banner_bottom() -> float:
	var overlays := get_parent().get_node_or_null("hud_overlays") if get_parent() != null else null
	if overlays == null:
		return size.y * 0.28
	return (size.y - float(overlays.BASE_H)) * 0.5 + float(overlays.BANNER_Y) + BANNER_CLEAR


func _top_stack() -> float:
	var top := get_parent().get_node_or_null("hud_top") if get_parent() != null else null
	return float(top.top_stack_bottom()) if top != null and top.has_method("top_stack_bottom") else 0.0


func _paint(canvas: CanvasItem) -> void:
	if _line.is_empty():
		return
	var rect := bubble_rect()
	var tone := String(_line.get("tone", "ember"))
	var t: Dictionary = UiStyle.brawl_tone(tone)
	var plate_c := Vector2(rect.position.x + PLATE * 0.5, rect.position.y + rect.size.y * 0.5)
	# Bubble: dark kit panel right of the plate, a small tail towards the portrait.
	var bubble := Rect2(rect.position.x + PLATE + 10.0, rect.position.y + 6.0, rect.size.x - PLATE - 10.0, rect.size.y - 6.0)
	var tail := PackedVector2Array([Vector2(bubble.position.x + 2.0, plate_c.y - 12.0), Vector2(bubble.position.x - 16.0, plate_c.y + 4.0), Vector2(bubble.position.x + 2.0, plate_c.y + 14.0)])
	var shadow := PackedVector2Array()
	for p in tail:
		shadow.append(p + Vector2(0, 4))
	canvas.draw_colored_polygon(shadow, UiStyle.BRAWL_INK_SOFT)
	Kit.panel(canvas, bubble, "dark", UiStyle.R_L)
	canvas.draw_colored_polygon(tail, UiStyle.BRAWL_INK)
	var inner := PackedVector2Array([tail[0] + Vector2(4, 4), tail[1] + Vector2(8, 0), tail[2] + Vector2(4, -4)])
	canvas.draw_colored_polygon(inner, UiStyle.BRAWL_PANEL_TOP)
	# Portrait plate: strain head for the leader, the boss portrait otherwise.
	Kit.icon_plate(canvas, plate_c, PLATE, tone)
	var face := Kit.plate_center(plate_c, PLATE)
	var icon := String(_line.get("icon", ""))
	if icon == "":
		icon = _strain_head()
	var side := PLATE * (0.8 if bool(_line.get("boss", false)) else 0.7)
	if UiIcons.has(icon):
		UiIcons.draw(canvas, icon, Rect2(face - Vector2.ONE * side * 0.5, Vector2.ONE * side), Color.WHITE)
	# Name chip on the bubble's top edge, then the line.
	var name_text := String(_line.get("name", ""))
	var chip_w := UiStyle.display_font().get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.T_LABEL).x + 28.0
	var chip := Rect2(bubble.position.x + 20.0, bubble.position.y - 17.0, chip_w, 32.0)
	Kit.chip(canvas, chip, tone)
	Kit.text_outlined(canvas, chip.get_center(), name_text, UiStyle.T_LABEL, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE, chip_w - 12.0)
	var text := String(_line.get("text", ""))
	var lines := Kit.wrap_lines(text, UiStyle.body_bold_font(), UiStyle.T_BODY, bubble.size.x - 47.0)
	var n := mini(lines.size(), MAX_LINES)
	var first := bubble.get_center().y + 6.0 - (n - 1) * 16.0 + UiStyle.T_BODY * Kit.CAP_BODY * 0.5
	Kit.paragraph(canvas, Vector2(bubble.position.x + 24.0, first), text, bubble.size.x - 47.0, UiStyle.T_BODY, Color.WHITE if bool(_line.get("boss", false)) else Color(t["light"]).lerp(Color.WHITE, 0.7), true, Kit.LEFT, MAX_LINES, 0)


func _strain_head() -> String:
	var hud := get_parent()
	var strain := String(hud.get_meta("strain_id", "")) if hud != null and hud.has_meta("strain_id") else ""
	if strain == "" and hud != null and "strain_id" in hud:
		strain = String(hud.get("strain_id"))
	return UiIcons.strain_head(strain) if strain != "" else "mawling_head_color"


func _draw() -> void:
	if _vignette_t < 0.0:
		return
	# Quick in (0.12 s), hold, ease out: the edge darkens, the middle stays clear.
	var k := clampf(_vignette_t / 0.12, 0.0, 1.0) * clampf((_vignette_len - _vignette_t) / (_vignette_len * 0.6), 0.0, 1.0)
	var color := Color(UiStyle.BRAWL_INK, VIGNETTE_ALPHA * k)
	var clear := Color(color, 0.0)
	var depth := minf(size.x, size.y) * 0.22
	var e := size
	var edges := [
		[Vector2.ZERO, Vector2(e.x, 0), Vector2(e.x - depth, depth), Vector2(depth, depth)],
		[Vector2(e.x, 0), e, Vector2(e.x - depth, e.y - depth), Vector2(e.x - depth, depth)],
		[e, Vector2(0, e.y), Vector2(depth, e.y - depth), Vector2(e.x - depth, e.y - depth)],
		[Vector2(0, e.y), Vector2.ZERO, Vector2(depth, depth), Vector2(depth, e.y - depth)],
	]
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for quad in edges:
		var base := points.size()
		points.append_array(PackedVector2Array(quad))
		colors.append_array([color, color, clear, clear])
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, points, colors)
