extends Control
## Shared drawing vocabulary of the MAWLINGS menus. The helpers are copied from
## `scripts/touch_controls.gd` (the in-run HUD) so both screens speak the same
## visual language: dark jungle panels, bone-coloured claws, warm/cyan accents.

const INK := Color("0a1a17")
const PANEL := Color("0f231ee6")
const BONE := Color("f5e4b7")
const CLAW := Color("d9c79a")
const WARM := Color("ff8a3d")
const CYAN := Color("6ee4d4")
const DANGER := Color("ff5a44")
const GOLD := Color("f6cc70")
const MUTED := Color("9fb6a6")
const LEAF := Color("7fa86a")

var _bold: FontVariation


func _ensure_font() -> void:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = ThemeDB.fallback_font
		_bold.variation_embolden = 0.85


func _pulse(speed: float = 3.0) -> float:
	return 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * speed)


func _font_for(font_size: int) -> Font:
	_ensure_font()
	return _bold if font_size >= 24 else ThemeDB.fallback_font


func _text_width(value: String, font_size: int) -> float:
	return _font_for(font_size).get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


func _text(value: String, point: Vector2, font_size: int, color: Color = Color.WHITE, centered: bool = false, outline: int = 0) -> void:
	var font := _font_for(font_size)
	var origin := point
	if centered:
		origin.x -= font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5
	if outline > 0:
		draw_string_outline(font, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, Color(0.02, 0.07, 0.06, 0.85))
	draw_string(font, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## Right-aligned text ending at point.x.
func _text_right(value: String, point: Vector2, font_size: int, color: Color = Color.WHITE, outline: int = 0) -> void:
	_text(value, point - Vector2(_text_width(value, font_size), 0), font_size, color, false, outline)


## Word-wrapped text; returns the y below the last line.
func _paragraph(value: String, point: Vector2, width: float, font_size: int, color: Color, centered: bool = false, max_lines: int = 4) -> float:
	var font := _font_for(font_size)
	var words := value.split(" ", false)
	var line := ""
	var y := point.y
	var lines := 0
	for word in words:
		var candidate := word if line == "" else line + " " + word
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width and line != "":
			_text(line, Vector2(point.x, y), font_size, color, centered)
			y += font_size * 1.3
			lines += 1
			line = word
			if lines >= max_lines:
				return y
		else:
			line = candidate
	if line != "":
		_text(line, Vector2(point.x, y), font_size, color, centered)
		y += font_size * 1.3
	return y


func _rounded_points(rect: Rect2, radius: float, steps: int = 6) -> PackedVector2Array:
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var centers := [Vector2(rect.end.x - r, rect.position.y + r), rect.end - Vector2(r, r), Vector2(rect.position.x + r, rect.end.y - r), rect.position + Vector2(r, r)]
	var points := PackedVector2Array()
	for i in 4:
		var start := -PI * 0.5 + i * PI * 0.5
		for s in steps + 1:
			var angle := start + PI * 0.5 * float(s) / float(steps)
			points.append(centers[i] + Vector2(cos(angle), sin(angle)) * r)
	return points


func _pill(rect: Rect2, color: Color) -> void:
	draw_colored_polygon(_rounded_points(rect, rect.size.y * 0.5, 4), color)


func _frame(rect: Rect2, fill: Color, edge: Color, claws: int = 0, width: float = 3.0) -> void:
	var radius := minf(26.0, minf(rect.size.x, rect.size.y) * 0.32)
	var points := _rounded_points(rect, radius)
	draw_colored_polygon(points, fill)
	if edge.a <= 0.0:
		return
	var inner := _rounded_points(rect.grow(-6), radius - 5)
	inner.append(inner[0])
	draw_polyline(inner, Color(edge, 0.22 * edge.a), 2.0, true)
	points.append(points[0])
	draw_polyline(points, edge, width, true)
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	var outward := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for i in 4:
		if claws & (1 << i):
			var dir: Vector2 = outward[i].normalized()
			var base: Vector2 = corners[i] - dir * radius * 0.28
			_claw(base, dir, 22, 7, CLAW, 0.45 if i % 2 == 0 else -0.45)


func _claw(base: Vector2, direction: Vector2, length: float, width: float, color: Color, bend: float = 0.35) -> void:
	var d := direction.normalized()
	var side := Vector2(-d.y, d.x)
	var points := PackedVector2Array()
	var steps := 6
	for i in steps + 1:
		var t := float(i) / steps
		points.append(base + d * length * t + side * (bend * length * t * t) + side * width * (1.0 - t))
	for i in range(steps - 1, -1, -1):
		var t := float(i) / steps
		points.append(base + d * length * t + side * (bend * length * t * t) - side * width * (1.0 - t))
	draw_colored_polygon(points, color)


func _bar(rect: Rect2, fraction: float, color: Color) -> void:
	var back := _rounded_points(rect, rect.size.y * 0.5, 4)
	draw_colored_polygon(back, Color("2a4a44"))
	if fraction > 0.0:
		var fill := Rect2(rect.position, Vector2(maxf(rect.size.y, rect.size.x * minf(fraction, 1.0)), rect.size.y))
		draw_colored_polygon(_rounded_points(fill, rect.size.y * 0.5, 4), color)


func _pips(origin: Vector2, rank: int, max_rank: int, color: Color, size_px: float = 11.0, gap: float = 26.0) -> void:
	for i in max_rank:
		var pc := origin + Vector2(i * gap, 0)
		var shape := PackedVector2Array([pc + Vector2(0, -size_px), pc + Vector2(size_px * 0.8, 0), pc + Vector2(0, size_px), pc + Vector2(-size_px * 0.8, 0)])
		if i < rank:
			draw_colored_polygon(shape, color)
		else:
			shape.append(shape[0])
			draw_polyline(shape, Color(color, 0.45), 2, true)


func _diamond(center: Vector2, r: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -r), center + Vector2(r * 0.85, 0), center + Vector2(0, r), center + Vector2(-r * 0.85, 0)]), color)


func _ellipse(c: Vector2, rx: float, ry: float, color: Color, rotation: float = 0.0) -> void:
	var points := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		points.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rotation))
	draw_colored_polygon(points, color)


func _ring_sector(c: Vector2, r_in: float, r_out: float, a0: float, a1: float, color: Color) -> void:
	var points := PackedVector2Array()
	var steps := 14
	for i in steps + 1:
		var a := lerpf(a0, a1, float(i) / steps)
		points.append(c + Vector2(cos(a), sin(a)) * r_out)
	for i in range(steps, -1, -1):
		var a := lerpf(a0, a1, float(i) / steps)
		points.append(c + Vector2(cos(a), sin(a)) * r_in)
	draw_colored_polygon(points, color)


func _mawling_head(center: Vector2, r: float, color: Color, facing: float = 1.0) -> void:
	var s := Vector2(r * facing, r)
	var outline := PackedVector2Array()
	for v in [Vector2(-0.95, 0.15), Vector2(-0.85, -0.4), Vector2(-0.5, -0.72), Vector2(-0.05, -0.82), Vector2(0.45, -0.66), Vector2(0.9, -0.42), Vector2(1.05, -0.2), Vector2(1.0, -0.08), Vector2(0.12, 0.06), Vector2(0.86, 0.3), Vector2(0.9, 0.42), Vector2(0.6, 0.6), Vector2(0.05, 0.64), Vector2(-0.5, 0.62), Vector2(-0.86, 0.45)]:
		outline.append(center + v * s)
	for spike in [[Vector2(-0.93, -0.05), Vector2(-0.8, -0.48), Vector2(-1.28, -0.5)], [Vector2(-0.72, -0.56), Vector2(-0.34, -0.78), Vector2(-0.78, -1.02)], [Vector2(-0.22, -0.8), Vector2(0.14, -0.78), Vector2(-0.2, -1.1)]]:
		draw_colored_polygon(PackedVector2Array([center + spike[0] * s, center + spike[1] * s, center + spike[2] * s]), color.darkened(0.2))
	draw_colored_polygon(outline, color)
	var tooth := Color("fff1d0")
	for t in [0.18, 0.46, 0.74]:
		var a: Vector2 = Vector2(0.95, -0.07).lerp(Vector2(0.2, 0.05), t)
		draw_colored_polygon(PackedVector2Array([center + (a + Vector2(-0.08, 0)) * s, center + (a + Vector2(0.08, 0)) * s, center + (a + Vector2(0, 0.2)) * s]), tooth)
	for t in [0.3, 0.65]:
		var b: Vector2 = Vector2(0.2, 0.1).lerp(Vector2(0.84, 0.31), t)
		draw_colored_polygon(PackedVector2Array([center + (b + Vector2(-0.07, 0.02)) * s, center + (b + Vector2(0.07, 0.02)) * s, center + (b + Vector2(0, -0.17)) * s]), tooth)
	draw_circle(center + Vector2(0.36, -0.36) * s, r * 0.13, INK)
	draw_circle(center + Vector2(0.39, -0.39) * s, r * 0.05, Color("ffe07a"))


func _skull(center: Vector2, r: float, color: Color) -> void:
	draw_circle(center + Vector2(0, -0.18 * r), 0.82 * r, color)
	draw_rect(Rect2(center + Vector2(-0.46, 0.25) * r, Vector2(0.92, 0.55) * r), color)
	for side in [-1.0, 1.0]:
		draw_circle(center + Vector2(side * 0.32, -0.16) * r, 0.23 * r, INK)
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, 0.12) * r, center + Vector2(0.1, 0.32) * r, center + Vector2(-0.1, 0.32) * r]), INK)
	for i in 3:
		var x := (-0.2 + i * 0.2) * r
		draw_line(center + Vector2(x, 0.5 * r), center + Vector2(x, 0.8 * r), INK, maxf(1.5, r * 0.08))


func _crown(c: Vector2, r: float, color: Color) -> void:
	var k := r / 20.0
	draw_colored_polygon(PackedVector2Array([c + Vector2(-20, 12) * k, c + Vector2(-22, -12) * k, c + Vector2(-10, 0) * k, c + Vector2(0, -17) * k, c + Vector2(10, 0) * k, c + Vector2(22, -12) * k, c + Vector2(20, 12) * k]), color)


## Königszahn: a curved golden fang.
func _fang(c: Vector2, r: float, color: Color) -> void:
	var tip := Vector2(0.3, 1.0)
	var points := PackedVector2Array()
	var steps := 8
	for i in steps + 1:
		var t := float(i) / steps
		points.append(c + _bezier(Vector2(0.5, -0.75), Vector2(0.55, 0.35), tip, t) * r)
	for i in range(steps - 1, -1, -1):
		var t := float(i) / steps
		points.append(c + _bezier(Vector2(-0.5, -0.75), Vector2(-0.25, 0.4), tip, t) * r)
	draw_colored_polygon(points, color)
	draw_line(c + Vector2(-0.18, -0.55) * r, c + Vector2(0.02, 0.35) * r, Color(1, 1, 1, 0.5), maxf(2.0, r * 0.12))
	draw_colored_polygon(_rounded_points(Rect2(c + Vector2(-0.62, -1.0) * r, Vector2(1.24, 0.32) * r), r * 0.12, 2), color.darkened(0.35))


func _bezier(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	return a.lerp(b, t).lerp(b.lerp(c, t), t)


## Essenz: glowing droplet with a spark.
func _essence_drop(c: Vector2, r: float, color: Color) -> void:
	draw_circle(c, r * 1.25, Color(color, 0.18))
	var points := PackedVector2Array()
	for i in 17:
		var angle := -PI * 0.2 + (PI * 1.4) * i / 16.0
		points.append(c + Vector2(cos(angle), sin(angle)) * r + Vector2(0, r * 0.25))
	points.append(c + Vector2(0, -r * 1.35))
	draw_colored_polygon(points, color)
	draw_circle(c + Vector2(-0.28, 0.1) * r, r * 0.22, Color(1, 1, 1, 0.55))


func _lock(c: Vector2, r: float, color: Color) -> void:
	draw_arc(c + Vector2(0, -0.3 * r), 0.48 * r, PI, TAU, 16, color, maxf(3.0, r * 0.18), true)
	draw_line(c + Vector2(-0.48, -0.3) * r, c + Vector2(-0.48, 0.05) * r, color, maxf(3.0, r * 0.18))
	draw_line(c + Vector2(0.48, -0.3) * r, c + Vector2(0.48, 0.05) * r, color, maxf(3.0, r * 0.18))
	draw_colored_polygon(_rounded_points(Rect2(c + Vector2(-0.75, -0.05) * r, Vector2(1.5, 1.05) * r), r * 0.2, 3), color)
	draw_circle(c + Vector2(0, 0.38) * r, r * 0.15, INK)


func _check(c: Vector2, r: float, color: Color) -> void:
	draw_polyline(PackedVector2Array([c + Vector2(-0.6, 0.0) * r, c + Vector2(-0.15, 0.45) * r, c + Vector2(0.65, -0.45) * r]), color, maxf(3.0, r * 0.22), true)


func _arrow(c: Vector2, r: float, dir: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(dir * 0.6, 0) * r, c + Vector2(-dir * 0.4, -0.75) * r, c + Vector2(-dir * 0.15, 0) * r, c + Vector2(-dir * 0.4, 0.75) * r]), color)


func _leaf(base: Vector2, length: float, width: float, angle: float, color: Color) -> void:
	var dir := Vector2.RIGHT.rotated(angle)
	var side := Vector2(-dir.y, dir.x)
	var points := PackedVector2Array()
	var steps := 8
	for i in steps + 1:
		var t := float(i) / steps
		points.append(base + dir * length * t + side * width * sin(t * PI))
	for i in range(steps - 1, 0, -1):
		var t := float(i) / steps
		points.append(base + dir * length * t - side * width * sin(t * PI) * 0.85)
	draw_colored_polygon(points, color)
	draw_line(base, base + dir * length * 0.9, color.darkened(0.3), maxf(1.5, width * 0.08), true)
