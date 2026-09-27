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

var _time := 0.0
var _banner: Control
var _chip: Control


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
