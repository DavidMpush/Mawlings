extends RefCounted
## Stage 33 (Mutationskerne): procedural core plaques, no image assets.
##
## A core is drawn as a round plaque: gold outer rim (cores are always
## legendary), a violet inner ring (the core accent), a dark orb that glows in
## the core's own tint and a white vector glyph on top. Used by the choice
## screen (mode "core"), the HUD core strip, the result BUILD page, the SIEGEL
## sheet and the KODEX tab KERNE (menu icon ids "core:<id>").
##
## Catalogue data (name, plus, minus) comes from scripts/progression/cores.gd
## (CORES := {id: {name, plus, minus, effects}}), loaded lazily so the UI keeps
## working without it. Glyph and tint are pure presentation and live here,
## matched by keywords in the id or the name so new ids still get a motif.

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")
const CORES_PATH := "res://scripts/progression/cores.gd"

## Violet accent of every core (rim ring, strip frame, text on dark).
const ACCENT := Color("b27cff")
const ACCENT_DARK := Color("4a1f99")
## Plus / minus line colours on cards and pages.
const PLUS := Color("8ff5a0")
const MINUS := Color("ff7c8e")

## keyword (lowercase, in id or name) -> [glyph, orb tint]; first match wins.
const MOTIFS := [
	["hung", "cell", Color("5fd36a")],
	["rudel", "fangs", Color("ff7a3a")],
	["arsenal", "spear", Color("4fc3ff")],
	["gift", "drop", Color("a4e03a")],
	["magnet", "magnet", Color("ff5a7a")],
	["könig", "crown", Color("ffcf3a")],
	["koenig", "crown", Color("ffcf3a")],
	["wander", "chevrons", Color("3fe0c0")],
	["panzer", "shield", Color("8fb0ee")],
	["flut", "wave", Color("4d86ff")],
	["bernstein", "gem", Color("ffa726")],
	["gedächt", "eye", Color("c08cff")],
	["gedaecht", "eye", Color("c08cff")],
	["letzt", "heart", Color("ff4d6d")],
]
const FALLBACK_TINTS := [Color("ff8a5c"), Color("5fd3c8"), Color("d77cff"), Color("ffd35c"), Color("7cb8ff"), Color("9ae05a")]

static var _cores_script: Script = null
static var _tried := false


static func _script() -> Script:
	if not _tried:
		_tried = true
		if ResourceLoader.exists(CORES_PATH):
			_cores_script = load(CORES_PATH)
	return _cores_script


## Catalogue {id: {name, plus, minus, ...}} or {} without cores.gd.
static func catalogue() -> Dictionary:
	var s := _script()
	if s == null:
		return {}
	var map: Variant = s.get_script_constant_map().get("CORES")
	return map if map is Dictionary else {}


## Core ids in catalogue order (ORDER constant when present, else CORES order).
static func ids() -> Array:
	var s := _script()
	if s == null:
		return []
	var order: Variant = s.get_script_constant_map().get("ORDER")
	if order is Array and not (order as Array).is_empty():
		return Array(order).map(func(v): return String(v))
	return catalogue().keys().map(func(v): return String(v))


## {id, name, plus, minus, glyph, tint} for a core id; unknown ids get a name
## from the id and a fallback motif. `desc` (card entry[2]) fills plus/minus
## when the catalogue has none ("+ …\n− …" or "… / …").
static func info(id: String, desc: String = "") -> Dictionary:
	var row: Dictionary = catalogue().get(id, {})
	var name := String(row.get("name", id.capitalize()))
	var plus := String(row.get("plus", ""))
	var minus := String(row.get("minus", ""))
	if (plus == "" or minus == "") and desc != "":
		var parts := desc.split("\n", false) if desc.contains("\n") else desc.split(" / ", false)
		if parts.size() >= 2:
			plus = parts[0] if plus == "" else plus
			minus = parts[1] if minus == "" else minus
		elif plus == "":
			plus = desc
	plus = _strip_sign(plus)
	minus = _strip_sign(minus)
	var motif := motif(id, name)
	return {"id": id, "name": name, "plus": plus, "minus": minus, "glyph": motif[0], "tint": motif[1]}


static func _strip_sign(text: String) -> String:
	var t := text.strip_edges()
	for sign in ["+ ", "− ", "- "]:
		if t.begins_with(sign):
			return t.substr(sign.length()).strip_edges()
	return t


## [glyph, tint] by keyword in the id or the name.
static func motif(id: String, name: String = "") -> Array:
	var hay := (id + " " + name).to_lower()
	for m in MOTIFS:
		if hay.contains(String(m[0])):
			return [m[1], m[2]]
	var h := absi(hash(id))
	return ["letter", FALLBACK_TINTS[h % FALLBACK_TINTS.size()]]

# ---------------------------------------------------------------- plaque

## Full round core plaque of diameter `size` at `center`. `dim` greys it out
## (locked / sealed); `glow` adds the soft violet-gold halo (cards, pages).
static func draw_plaque(c: CanvasItem, center: Vector2, size: float, id: String, dim: bool = false, glow: bool = false, name: String = "") -> void:
	var r := size * 0.5
	if r < 6.0:
		return
	var m := motif(id, name if name != "" else String(catalogue().get(id, {}).get("name", "")))
	var tint: Color = m[1]
	var gold: Dictionary = UiStyle.rarity_tone("legendary")
	if dim:
		tint = Color(0.42, 0.42, 0.52)
	if glow and not dim:
		Kit.glow(c, center, r * 1.55, ACCENT, 0.55)
		Kit.glow(c, center, r * 1.2, gold["light"], 0.35)
	var stroke := maxf(2.0, roundf(size * 0.045))
	var batch := Kit.TriBatch.new()
	batch.disc(center + Vector2(0, maxf(2.0, size * 0.05)), r, UiStyle.BRAWL_INK_SOFT)
	batch.disc(center, r, UiStyle.BRAWL_INK)
	# Gold rim (legendary), lit from the top.
	var rim_face: Color = gold["face"] if not dim else Color(0.5, 0.5, 0.58)
	var rim_dark: Color = gold["dark"] if not dim else Color(0.3, 0.3, 0.38)
	batch.disc(center, r - stroke + 0.5, rim_dark)
	batch.disc(center - Vector2(0, size * 0.02), r - stroke - size * 0.02, rim_face)
	Kit._fade_disc_into(batch, center - Vector2(0, size * 0.02), r - stroke - size * 0.02, Color(gold["light"] if not dim else Color(0.7, 0.7, 0.78), 1.0), 0.0, 0.6)
	# Violet accent ring.
	# Violet accent ring (thinner on small HUD plaques so the orb stays big).
	var small := size < 64.0
	var r_violet := r * (0.8 if small else 0.78)
	batch.disc(center, r_violet, UiStyle.BRAWL_INK)
	batch.disc(center, r_violet - stroke * 0.8, ACCENT_DARK if not dim else Color(0.25, 0.25, 0.32))
	batch.ring(center, r_violet - stroke * 0.8, maxf(1.5, size * 0.035), ACCENT if not dim else Color(0.5, 0.5, 0.6))
	# Orb: dark core in the tint, glowing towards the middle.
	var r_orb := r * (0.7 if small else 0.64)
	batch.disc(center, r_orb, tint.darkened(0.62))
	batch.flush(c)
	Kit.glow(c, center + Vector2(0, size * 0.02), r_orb * 0.98, tint, 0.95 if not dim else 0.4)
	# Glass highlight (top-left).
	c.draw_set_transform(center + Vector2(-r_orb * 0.3, -r_orb * 0.46), -0.5, Vector2(1.0, 0.55))
	Kit.disc(c, Vector2.ZERO, r_orb * 0.34, Color(1, 1, 1, 0.28 if not dim else 0.12))
	c.draw_set_transform(Vector2.ZERO)
	# Gold studs at the four diagonals of the rim.
	if size >= 64.0:
		for k in 4:
			var a := PI * 0.25 + k * PI * 0.5
			var p := center + Vector2(cos(a), sin(a)) * (r - stroke - (r - stroke - r_violet) * 0.5)
			Kit.disc(c, p, size * 0.035, UiStyle.BRAWL_INK)
			Kit.disc(c, p, size * 0.022, Color.WHITE if not dim else Color(0.7, 0.7, 0.75))
	var glyph_col := Color.WHITE if not dim else Color(0.72, 0.72, 0.8)
	draw_glyph(c, String(m[0]), center, r_orb * (1.7 if small else 1.5), glyph_col, id)


## Glyph only (white shape with ink outline) of side `side` at `center`.
## `glyph` is a motif name (see MOTIFS) or "letter" (first letter of `id`).
static func draw_glyph(c: CanvasItem, glyph: String, center: Vector2, side: float, color: Color, id: String = "") -> void:
	var s := side * 0.5
	var ink := Color(UiStyle.BRAWL_INK, color.a)
	var w := maxf(2.0, side * 0.075)
	match glyph:
		"cell":
			for p in [Vector2(-0.32, 0.04), Vector2(0.32, -0.04)]:
				Kit.disc(c, center + p * s, s * 0.5 + w, ink)
			for p in [Vector2(-0.32, 0.04), Vector2(0.32, -0.04)]:
				Kit.disc(c, center + p * s, s * 0.5, color)
			# Division seam and one small daughter bud: a cell splitting in two.
			c.draw_line(center + Vector2(0.02, -0.4) * s, center + Vector2(-0.02, 0.4) * s, ink, maxf(2.0, w * 1.1), true)
			Kit.disc(c, center + Vector2(0.62, -0.62) * s, s * 0.2 + w, ink)
			Kit.disc(c, center + Vector2(0.62, -0.62) * s, s * 0.2, color)
		"fangs":
			for k in 3:
				var x := (k - 1) * 0.52
				var h := 0.95 if k == 1 else 0.7
				_poly(c, center, s, [Vector2(x - 0.26, -0.55), Vector2(x + 0.26, -0.55), Vector2(x, -0.55 + h * 1.2)], color, ink, w)
		"spear":
			_poly(c, center, s, [Vector2(0, -0.95), Vector2(0.34, -0.3), Vector2(0.12, -0.34), Vector2(0.12, 0.9), Vector2(-0.12, 0.9), Vector2(-0.12, -0.34), Vector2(-0.34, -0.3)], color, ink, w)
			_poly(c, center, s, [Vector2(-0.46, 0.18), Vector2(0.46, 0.18), Vector2(0.46, 0.36), Vector2(-0.46, 0.36)], color, ink, w)
		"drop":
			var pts: Array = [Vector2(0, -0.95)]
			for k in 13:
				var a := -0.15 * PI + k * (1.3 * PI / 12.0)
				pts.append(Vector2(cos(a) * 0.58, 0.28 + sin(a) * 0.58))
			_poly(c, center, s, pts, color, ink, w)
		"magnet":
			var arc_c := center + Vector2(0, 0.05) * s
			c.draw_arc(arc_c, s * 0.5, 0.0, PI, 20, ink, s * 0.36 + w * 2.0, true)
			for x: float in [-0.5, 0.5]:
				c.draw_line(arc_c + Vector2(x, 0.02) * s, arc_c + Vector2(x, -0.72) * s, ink, s * 0.36 + w * 2.0)
			c.draw_arc(arc_c, s * 0.5, 0.0, PI, 20, color, s * 0.36, true)
			for x: float in [-0.5, 0.5]:
				c.draw_line(arc_c + Vector2(x, 0.02) * s, arc_c + Vector2(x, -0.46) * s, color, s * 0.36)
				c.draw_line(arc_c + Vector2(x, -0.46) * s, arc_c + Vector2(x, -0.72) * s, Color("ff5a7a") if color.s < 0.1 and color.v > 0.9 else color.darkened(0.2), s * 0.36)
		"crown":
			_poly(c, center, s, [Vector2(-0.8, 0.55), Vector2(-0.85, -0.45), Vector2(-0.42, -0.02), Vector2(0, -0.75), Vector2(0.42, -0.02), Vector2(0.85, -0.45), Vector2(0.8, 0.55)], color, ink, w)
			Kit.disc(c, center + Vector2(0, 0.22) * s, s * 0.13, ink)
		"chevrons":
			for x: float in [-0.3, 0.3]:
				var pts := PackedVector2Array([center + Vector2(x - 0.3, -0.62) * s, center + Vector2(x + 0.3, 0) * s, center + Vector2(x - 0.3, 0.62) * s])
				c.draw_polyline(pts, ink, s * 0.3 + w * 2.0, true)
				c.draw_polyline(pts, color, s * 0.3, true)
		"shield":
			_poly(c, center, s, [Vector2(0, -0.9), Vector2(0.72, -0.6), Vector2(0.66, 0.1), Vector2(0, 0.92), Vector2(-0.66, 0.1), Vector2(-0.72, -0.6)], color, ink, w)
			_poly(c, center, s, [Vector2(0, -0.55), Vector2(0.36, -0.38), Vector2(0.32, 0.06), Vector2(0, 0.5)], Color(ink, 0.35 * color.a), Color(0, 0, 0, 0), 0.0)
		"wave":
			for row: float in [-0.3, 0.32]:
				var pts := PackedVector2Array()
				for k in 17:
					var t := k / 16.0
					pts.append(center + Vector2(-0.82 + 1.64 * t, row + sin(t * TAU * 1.25) * 0.2) * s)
				c.draw_polyline(pts, ink, s * 0.26 + w * 2.0, true)
				c.draw_polyline(pts, color, s * 0.26, true)
		"gem":
			_poly(c, center, s, [Vector2(-0.4, -0.66), Vector2(0.4, -0.66), Vector2(0.8, -0.2), Vector2(0, 0.9), Vector2(-0.8, -0.2)], color, ink, w)
			_poly(c, center, s, [Vector2(-0.8, -0.2), Vector2(0.8, -0.2), Vector2(0, 0.9)], Color(ink, 0.22 * color.a), Color(0, 0, 0, 0), 0.0)
		"eye":
			var pts: Array = []
			for k in 13:
				var t := k / 12.0
				pts.append(Vector2(-0.9 + 1.8 * t, -sin(t * PI) * 0.55))
			for k in range(1, 12):
				var t := 1.0 - k / 12.0
				pts.append(Vector2(-0.9 + 1.8 * t, sin(t * PI) * 0.55))
			_poly(c, center, s, pts, color, ink, w)
			Kit.disc(c, center, s * 0.34, ink)
			Kit.disc(c, center + Vector2(-0.1, -0.1) * s, s * 0.1, color)
		"heart":
			var pts: Array = []
			for k in 25:
				var t := -PI + k * TAU / 24.0
				var x := 16.0 * pow(sin(t), 3)
				var y := -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
				pts.append(Vector2(x, y + 2.0) / 19.0)
			_poly(c, center, s, pts, color, ink, w)
			# Crack: the last bite.
			var crack := PackedVector2Array([center + Vector2(0.05, -0.5) * s, center + Vector2(-0.12, -0.12) * s, center + Vector2(0.12, 0.1) * s, center + Vector2(-0.02, 0.45) * s])
			c.draw_polyline(crack, ink, maxf(2.0, s * 0.13), true)
		"spark":
			# Generic core: glowing orb with a four-point star (KODEX segment).
			Kit.disc(c, center, s * 0.62 + w, ink)
			Kit.disc(c, center, s * 0.62, Color(ACCENT, color.a))
			Kit.circle_ring(c, center, s * 0.62, maxf(2.0, w * 0.8), Color(UiStyle.rarity_tone("legendary")["face"], color.a))
			_poly(c, center, s, [Vector2(0, -0.5), Vector2(0.12, -0.12), Vector2(0.5, 0), Vector2(0.12, 0.12), Vector2(0, 0.5), Vector2(-0.12, 0.12), Vector2(-0.5, 0), Vector2(-0.12, -0.12)], color, ink, w * 0.6)
		_:
			var letter :=id.left(1).to_upper() if id != "" else "?"
			Kit.text_outlined(c, center + Vector2(0, 1), letter, _text_size(side), color, -1, -1, null, Kit.CENTER | Kit.MIDDLE)


static func _text_size(side: float) -> int:
	for step in [UiStyle.T_HERO, UiStyle.T_TITLE, UiStyle.T_HEAD, UiStyle.T_BODY]:
		if side >= float(step) * 1.1:
			return step
	return UiStyle.T_LABEL


# Filled polygon in unit coordinates (× s around center) with an ink outline.
static func _poly(c: CanvasItem, center: Vector2, s: float, unit: Array, fill: Color, ink: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for p: Vector2 in unit:
		pts.append(center + p * s)
	if w > 0.0 and ink.a > 0.0:
		var closed := pts.duplicate()
		closed.append(pts[0])
		c.draw_polyline(closed, ink, w * 2.0, true)
	c.draw_colored_polygon(pts, fill)
