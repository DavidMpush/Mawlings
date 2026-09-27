extends Control

# Stage 08 · "Die Flut" HUD. HuntWorld adds this component to HUD/Controls and
# publishes its state as the HUD meta "flood" (see HuntWorld._flood_hud):
#   state     0 = not yet, 1 = announced (countdown), 2 = running
#   countdown seconds until the flood starts (state 1)
#   stage     1-based flood stage (doubles every TUNING.FLOOD_DOUBLING_SECONDS)
#   seconds   time since the flood started
#   count     living Moorbrut
# Announcement: a large banner "DIE FLUT KOMMT" with a big countdown; the first
# seconds of the flood show "DIE FLUT BRICHT LOS"; afterwards a compact chip
# "FLUT · STUFE n · mm:ss" in the right column pulses in the danger colour
# (faster with each stage). Drawing goes through UiLayer (stage 07): a layer
# only repaints when its key changes; with no flood nothing is drawn.

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const UiLayer := preload("res://scripts/ui/ui_layer.gd")
const UiIcons := preload("res://scripts/ui/ui_icons.gd")
const FLOOD := Color("ff3b5c")           # danger, a touch pinker than DANGER
const FLOOD_DEEP := Color("5a0d1f")
const CALM_FLOOD := Color("e3665c")      # calm skin: coral between the kit's danger and red
const CHIP_Y := 392.0                    # right column, level with the curse chip (left)
const BANNER_Y := 470.0                  # below the top panels, above the swarm
const BURST_SECONDS := 2.6               # "bricht los" banner after the start
# Skin brawl (stage 15, package H): no banner in the middle of the screen any
# more (the short flood-start band belongs to hud_overlays.gd). One compact
# danger pill sits in the row hud_top reserves under the header and the boss
# bars (hud_top.flood_slot()): skull plate, "DIE FLUT KOMMT" + countdown while
# announced, "FLUT · STUFE n" + mm:ss while running. The flood start and every
# new stage pop the pill and flash its ring (layer scale, no repaint).
const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")
const POP_SECONDS := 1.2
## Hand-over flag read by hud_overlays.gd: the short flood-start band
## ("DIE FLUT BRICHT LOS") is drawn there in the skin brawl, not here.
var banners_in_overlays := true

var _time := 0.0
var _banner: Control
var _chip: Control
var _pill_rect := Rect2()
var _pill_compact := false
var _last_mode := 0
var _last_stage := 0
var _pop_t := -1.0                       # seconds since the flood start / last new stage


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner = UiLayer.make(self, "FloodBanner", _paint_banner)
	_chip = UiLayer.make(self, "FloodChip", _paint_chip)


func _process(delta: float) -> void:
	_time += delta
	var state := _state()
	var hidden := _hidden()
	var mode := int(state.get("state", 0))
	var slot := _brawl_slot()
	if slot.size.y > 0.0:
		_process_pill(state, hidden, mode, slot, delta)
		return
	_pill_rect = Rect2()
	_chip.scale = Vector2.ONE
	var banner_key: Array = [size]
	var chip_key: Array = [size]
	if not hidden and mode == 1:
		banner_key = [size, 1, ceili(float(state.get("countdown", 0.0))), int(_time * 30.0)]
	elif not hidden and mode == 2 and float(state.get("seconds", 0.0)) < BURST_SECONDS:
		banner_key = [size, 2, int(_time * 30.0)]
	if not hidden and mode == 2:
		var stage := int(state.get("stage", 1))
		# Pulse rate grows with the stage (capped), 20 Hz repaint is plenty.
		chip_key = [size, stage, int(float(state.get("seconds", 0.0))), int(_time * 20.0)]
	_banner.refresh(banner_key)
	_chip.refresh(chip_key)


func _state() -> Dictionary:
	var hud := get_parent()
	if hud == null or not hud.has_meta("flood"):
		return {}
	return hud.get_meta("flood")


func _hidden() -> bool:
	var hud := get_parent()
	if hud == null:
		return true
	if bool(hud.get("paused")) or bool(hud.get("extinct")):
		return true
	return hud.has_method("_choosing") and hud._choosing()


# mm:ss of the time since the flood started.
static func clock_text(seconds: float) -> String:
	var whole := maxi(0, int(seconds))
	return "%02d:%02d" % [whole / 60, whole % 60]


# Text of the compact chip (tests read it).
static func chip_text(stage: int, seconds: float) -> String:
	return "FLUT · STUFE %d · %s" % [maxi(1, stage), clock_text(seconds)]


# ------------------------------------------------------------------ banner

func _paint_banner(canvas: CanvasItem) -> void:
	var state := _state()
	if state.is_empty() or _hidden():
		return
	var mode := int(state.get("state", 0))
	if mode == 1:
		_draw_banner(canvas, "DIE FLUT KOMMT", str(maxi(1, ceili(float(state.get("countdown", 0.0))))), 1.0)
	elif mode == 2 and float(state.get("seconds", 0.0)) < BURST_SECONDS:
		var t := float(state.get("seconds", 0.0)) / BURST_SECONDS
		_draw_banner(canvas, "DIE FLUT BRICHT LOS", "", 1.0 - maxf(0.0, t - 0.7) / 0.3)


func _draw_banner(canvas: CanvasItem, title: String, count: String, alpha: float) -> void:
	if UiStyle.is_calm():
		_draw_banner_calm(canvas, title, count, alpha)
		return
	var center_x := size.x * 0.5
	var pulse := 0.5 + 0.5 * sin(_time * 7.0)
	var width := minf(size.x - 60.0, 700.0)
	var height := 176.0 if count != "" else 118.0
	var rect := Rect2(center_x - width * 0.5, BANNER_Y, width, height)
	var body := _plate(rect, 28.0)
	# Glow halo, shadow, dark wine plate, pulsing danger outline.
	canvas.draw_colored_polygon(_plate(rect.grow(10.0 + 6.0 * pulse), 36.0), Color(FLOOD, (0.14 + 0.12 * pulse) * alpha))
	canvas.draw_colored_polygon(_offset(body, Vector2(0, 6)), Color(UiStyle.color("shadow"), UiStyle.color("shadow").a * alpha))
	canvas.draw_colored_polygon(body, Color(FLOOD_DEEP.lerp(UiStyle.color("panel"), 0.35), 0.94 * alpha))
	var outline := body.duplicate()
	outline.append(body[0])
	canvas.draw_polyline(outline, Color(FLOOD.lerp(Color.WHITE, 0.25 * pulse), alpha), 5.0, true)
	# Skull teeth on both ends.
	for side in [-1.0, 1.0]:
		var at := Vector2(center_x + side * (width * 0.5 - 58.0), rect.position.y + 58.0)
		canvas.draw_circle(at, 34.0, Color(FLOOD, (0.2 + 0.15 * pulse) * alpha))
		UiIcons.draw(canvas, "skull", Rect2(at - Vector2(30, 30), Vector2(60, 60)), Color(UiStyle.tone(Color("ffd3dc")), alpha))
	UiStyle.text(canvas, title, Vector2(center_x, rect.position.y + 74.0), UiStyle.SIZE_TITLE, Color(UiStyle.tone(Color("ffe3e8")), alpha), true, 8)
	if count != "":
		var pop := 1.0 + 0.18 * maxf(0.0, 1.0 - fmod(_time, 1.0) * 3.0)
		UiStyle.text_px(canvas, count, Vector2(center_x, rect.position.y + 150.0), UiStyle.SIZE_HERO * pop * 0.8, Color(FLOOD.lerp(Color.WHITE, 0.35), alpha), true, 8)


# Calm skin (V2): chamfered petrol plate, coral top band and one broad stroke,
# threat glyphs instead of skulls; only the stroke brightness pulses.
func _draw_banner_calm(canvas: CanvasItem, title: String, count: String, alpha: float) -> void:
	var center_x := size.x * 0.5
	var pulse := 0.5 + 0.5 * sin(_time * 7.0)
	var width := minf(size.x - 60.0, 700.0)
	var height := 176.0 if count != "" else 118.0
	var rect := Rect2(center_x - width * 0.5, BANNER_Y, width, height)
	var body := _chamfer(rect, 22.0)
	canvas.draw_colored_polygon(_offset(body, Vector2(0, 6)), Color(UiStyle.color("shadow"), UiStyle.color("shadow").a * alpha))
	canvas.draw_colored_polygon(body, Color(UiStyle.CALM_BG, 0.95 * alpha))
	canvas.draw_colored_polygon(_chamfer(Rect2(rect.position + Vector2(4, 4), Vector2(rect.size.x - 8, 50)), 18.0), Color(CALM_FLOOD, 0.16 * alpha))
	var outline := body.duplicate()
	outline.append(body[0])
	canvas.draw_polyline(outline, Color(CALM_FLOOD.lerp(Color.WHITE, 0.2 * pulse), alpha), 5.0, true)
	for side in [-1.0, 1.0]:
		var at := Vector2(center_x + side * (width * 0.5 - 58.0), rect.position.y + 58.0)
		UiIcons.draw(canvas, "v2_threat", Rect2(at - Vector2(30, 30), Vector2(60, 60)), Color(1, 1, 1, alpha))
	UiStyle.text(canvas, title, Vector2(center_x, rect.position.y + 74.0), UiStyle.SIZE_TITLE, Color(UiStyle.CALM_TEXT, alpha), true, 7)
	if count != "":
		var pop := 1.0 + 0.18 * maxf(0.0, 1.0 - fmod(_time, 1.0) * 3.0)
		UiStyle.text_px(canvas, count, Vector2(center_x, rect.position.y + 150.0), UiStyle.SIZE_HERO * pop * 0.8, Color(CALM_FLOOD.lerp(Color.WHITE, 0.3), alpha), true, 7)


func _chamfer(rect: Rect2, cut: float) -> PackedVector2Array:
	var p := rect.position
	var e := rect.end
	return PackedVector2Array([Vector2(p.x + cut, p.y), Vector2(e.x - cut, p.y), Vector2(e.x, p.y + cut), Vector2(e.x, e.y - cut),
		Vector2(e.x - cut, e.y), Vector2(p.x + cut, e.y), Vector2(p.x, e.y - cut), Vector2(p.x, p.y + cut)])


# ------------------------------------------------------------------ chip

func _paint_chip(canvas: CanvasItem) -> void:
	if _pill_rect.size.x > 0.0:
		_draw_pill(canvas)
		return
	var state := _state()
	if state.is_empty() or _hidden() or int(state.get("state", 0)) != 2:
		return
	var stage := int(state.get("stage", 1))
	var text := chip_text(stage, float(state.get("seconds", 0.0)))
	var font := UiStyle.body_font()
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.SIZE_LABEL + 2).x + 70.0
	var rect := Rect2(size.x - 16.0 - w, CHIP_Y, w, 48.0)
	var rate := minf(3.0 + float(stage) * 1.2, 10.0)
	var pulse := 0.5 + 0.5 * sin(_time * rate)
	if UiStyle.is_calm():
		var chip := _chamfer(rect, 12.0)
		canvas.draw_colored_polygon(chip, Color(UiStyle.CALM_BG, 0.95))
		chip.append(chip[0])
		canvas.draw_polyline(chip, CALM_FLOOD.lerp(Color.WHITE, 0.25 * pulse), 3.0, true)
		UiIcons.draw(canvas, "v2_threat", Rect2(rect.position + Vector2(8, 5), Vector2(38, 38)), Color.WHITE)
		UiStyle.text(canvas, text, rect.position + Vector2(50, 33), UiStyle.SIZE_LABEL + 2, UiStyle.CALM_TEXT, false, 4, font)
		return
	var points := _pill(rect)
	canvas.draw_colored_polygon(_pill(rect.grow(4.0 + 4.0 * pulse)), Color(FLOOD, 0.10 + 0.14 * pulse))
	canvas.draw_colored_polygon(points, Color(UiStyle.color("panel").darkened(0.2), 0.95).lerp(FLOOD_DEEP, 0.35 + 0.25 * pulse))
	points.append(points[0])
	canvas.draw_polyline(points, FLOOD.lerp(Color.WHITE, 0.3 * pulse), 3.0, true)
	var icon_c := rect.position + Vector2(27, 24)
	canvas.draw_circle(icon_c, 19, Color(FLOOD, 0.25 + 0.2 * pulse))
	UiIcons.draw(canvas, "skull", Rect2(icon_c - Vector2(17, 17), Vector2(34, 34)), UiStyle.tone(Color("ffd3dc")))
	UiStyle.text(canvas, text, rect.position + Vector2(50, 33), UiStyle.SIZE_LABEL + 2, UiStyle.tone(Color("ffe3e8")), false, 5, font)


# ------------------------------------------------------------------ brawl pill

## Row hud_top reserves for the pill (empty outside the skin brawl).
func _brawl_slot() -> Rect2:
	if not UiStyle.is_brawl() or get_parent() == null:
		return Rect2()
	var top := get_parent().get_node_or_null("hud_top")
	if top == null or not top.has_method("flood_slot"):
		return Rect2()
	return top.flood_slot()


## Rect of the pill shown this frame (empty = none); tests read it.
func pill_rect() -> Rect2:
	return _pill_rect


func _process_pill(state: Dictionary, hidden: bool, mode: int, slot: Rect2, delta: float) -> void:
	var stage := int(state.get("stage", 1))
	# Flood start and every new stage: the pill pops.
	if mode == 2 and (_last_mode != 2 or stage > _last_stage):
		_pop_t = 0.0
	_last_mode = mode
	_last_stage = stage if mode == 2 else 0
	if _pop_t >= 0.0:
		_pop_t += delta
		if _pop_t > POP_SECONDS:
			_pop_t = -1.0
	_banner.refresh([size])
	_pill_rect = Rect2() if hidden else _pill_layout(slot, state, mode)
	if _pill_rect.size.x <= 0.0:
		_chip.refresh([size])
		return
	var countdown := ceili(float(state.get("countdown", 0.0)))
	var urgent := mode == 1 or _pop_t >= 0.0
	_chip.refresh([_pill_rect, mode, stage, countdown, int(float(state.get("seconds", 0.0))), int(_time * (30.0 if urgent else 15.0))])
	var s := 1.0
	if _pop_t >= 0.0:
		# Quick swell to 1.25, elastic settle.
		var k := clampf(_pop_t / 0.45, 0.0, 1.0)
		s = 1.0 + 0.25 * (1.0 - k) * cos(k * PI * 1.5)
	_chip.pivot_offset = _pill_rect.get_center()
	_chip.scale = Vector2(s, s)


func _pill_title(state: Dictionary, mode: int) -> String:
	return "DIE FLUT KOMMT" if mode == 1 else "FLUT · STUFE %d" % maxi(1, int(state.get("stage", 1)))


func _pill_value(state: Dictionary, mode: int) -> String:
	if mode == 1:
		return str(maxi(1, ceili(float(state.get("countdown", 0.0)))))
	return clock_text(float(state.get("seconds", 0.0)))


func _pill_layout(slot: Rect2, state: Dictionary, mode: int) -> Rect2:
	if mode != 1 and mode != 2:
		return Rect2()
	_pill_compact = slot.size.y < 52.0
	var h := slot.size.y
	var plate := h + 8.0
	var title_size := UiStyle.T_LABEL if _pill_compact else UiStyle.T_BODY
	var title_w := UiStyle.display_font().get_string_size(_pill_title(state, mode), HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
	var w := plate - 6.0 + 10.0 + title_w + 14.0 + _well_width(state, mode) + 8.0
	w = minf(w, size.x - 32.0)
	return Rect2(roundf(slot.get_center().x - w * 0.5), slot.position.y, roundf(w), h)


func _value_size(mode: int) -> int:
	return UiStyle.T_HEAD if mode == 1 and not _pill_compact else UiStyle.T_BODY


func _well_width(state: Dictionary, mode: int) -> float:
	var value_w := UiStyle.number_font().get_string_size(_pill_value(state, mode) if mode == 2 else "00", HORIZONTAL_ALIGNMENT_LEFT, -1, _value_size(mode)).x
	return value_w + 28.0


func _draw_pill(canvas: CanvasItem) -> void:
	var state := _state()
	var mode := int(state.get("state", 0))
	if mode != 1 and mode != 2:
		return
	var rect := _pill_rect
	var h := rect.size.y
	var danger: Dictionary = UiStyle.brawl_tone("danger")
	var stage := int(state.get("stage", 1))
	var rate := 9.0 if mode == 1 else minf(3.0 + float(stage) * 1.2, 10.0)
	var pulse := 0.5 + 0.5 * sin(_time * rate)
	var glow := (0.3 + 0.45 * pulse) if mode == 1 else (0.12 + 0.28 * pulse)
	if _pop_t >= 0.0:
		glow = maxf(glow, 1.0 - _pop_t / POP_SECONDS)
	Kit.ring(canvas, rect.grow(5.0 + 3.0 * pulse), h * 0.5 + 5.0 + 3.0 * pulse, 5.0, Color(danger["light"], glow))
	Kit.pill(canvas, rect, "danger")
	var plate := h + 8.0
	var plate_c := Vector2(rect.position.x + plate * 0.5 - 6.0, rect.get_center().y)
	Kit.icon_plate(canvas, plate_c, plate, "dark")
	var icon := roundf(plate * 0.66)
	UiIcons.draw(canvas, "skull", Rect2(Kit.plate_center(plate_c, plate) - Vector2(icon, icon) * 0.5, Vector2(icon, icon)), Color.WHITE)
	var cy := rect.get_center().y - 2.0
	var well_w := _well_width(state, mode)
	var well := Rect2(rect.end.x - 8.0 - well_w, rect.position.y + 8.0, well_w, h - 18.0)
	var x := plate_c.x + plate * 0.5 + 10.0
	var title_size := UiStyle.T_LABEL if _pill_compact else UiStyle.T_BODY
	Kit.text_outlined(canvas, Vector2(x, cy), _pill_title(state, mode), title_size, Color.WHITE, -1, -1, null, Kit.LEFT | Kit.MIDDLE, well.position.x - 12.0 - x)
	Kit.well(canvas, well, well.size.y * 0.5)
	var value_color := Color.WHITE
	if mode == 1:
		# The countdown digit flashes on every second.
		var tick := 1.0 - fmod(float(state.get("countdown", 0.0)), 1.0)
		value_color = Color.WHITE.lerp(danger["light"], clampf(1.0 - tick * 3.0, 0.0, 1.0))
	Kit.number(canvas, well.get_center() + Vector2(0, 1), _pill_value(state, mode), _value_size(mode), value_color, Kit.CENTER | Kit.MIDDLE, well.size.x - 12.0)


# ------------------------------------------------------------------ shapes

# Rounded plate with slightly clipped corners (reads as a warning sign).
func _plate(rect: Rect2, r: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var corners := [
		[Vector2(rect.end.x - r, rect.position.y + r), -PI * 0.5],
		[Vector2(rect.end.x - r, rect.end.y - r), 0.0],
		[Vector2(rect.position.x + r, rect.end.y - r), PI * 0.5],
		[Vector2(rect.position.x + r, rect.position.y + r), PI],
	]
	for corner in corners:
		for index in 7:
			var angle: float = corner[1] + PI * 0.5 * float(index) / 6.0
			points.append(corner[0] + Vector2(cos(angle), sin(angle)) * r)
	return points


func _pill(rect: Rect2) -> PackedVector2Array:
	var points := PackedVector2Array()
	var r := rect.size.y * 0.5
	for index in 13:
		var angle := PI * 0.5 + PI * float(index) / 12.0
		points.append(Vector2(rect.position.x + r, rect.position.y + r) + Vector2(cos(angle), sin(angle)) * r)
	for index in 13:
		var angle := -PI * 0.5 + PI * float(index) / 12.0
		points.append(Vector2(rect.end.x - r, rect.position.y + r) + Vector2(cos(angle), sin(angle)) * r)
	return points


func _offset(points: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		result.append(point + by)
	return result
