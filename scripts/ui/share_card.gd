extends Node
## Teilen-Karte (Etappe 10): rendert aus RunStats ein 1080 x 1920-Bild (9:16,
## Story-Format) im Markenstil und speichert es als PNG.
##
##   var card := ShareCard.new()
##   add_child(card)                      # braucht den SceneTree zum Rendern
##   var path: String = await card.render(stats)   # "user://shares/…png" oder ""
##   card.queue_free()
##
## Gerendert wird einmal in eine SubViewport (UPDATE_ONCE) und das Bild danach
## freigegeben. Ohne Grafik (--headless) gibt es keine Pixel: dann entsteht ein
## schlichtes Ersatzbild per CPU, damit Speicherpfad und Ablauf testbar bleiben.
##
## Sichere Zone: oben ~260 px und unten ~300 px verdecken TikTok/Instagram-Story
## ihre Bedienelemente – dort liegen nur Kiefer-Deko und das Maul-Motiv; alles
## Wichtige (Zeit, Schwarm, Build, Code) steht dazwischen.

const S := preload("res://scripts/ui/ui_style.gd")
const UiIcons := preload("res://scripts/ui/ui_icons.gd")
const CHRONICLE_PATH := "res://scripts/meta/chronicle.gd"
const META_DATA_PATH := "res://scripts/meta/meta_data.gd"

const SIZE := Vector2i(1080, 1920)
const DEFAULT_DIR := "user://shares/"
## Ältere Karten im Ordner werden über diese Zahl hinaus gelöscht.
const KEEP_FILES := 20

## Letzte gerenderte Daten (für Tests und Capture).
var last_data: Dictionary = {}
var last_path := ""


## Rendert und speichert die Karte; gibt den Pfad (user://…) oder "" zurück.
func render(stats: Dictionary, out_dir: String = DEFAULT_DIR, file_name: String = "") -> String:
	last_data = card_data(stats)
	var image: Image = null
	if DisplayServer.get_name() != "headless" and is_inside_tree():
		image = await _render_viewport(last_data)
	if image == null or image.is_empty():
		image = _fallback_image(last_data)
	if not out_dir.ends_with("/"):
		out_dir += "/"
	if not DirAccess.dir_exists_absolute(out_dir):
		DirAccess.make_dir_recursive_absolute(out_dir)
	if file_name == "":
		file_name = "mawlings_%s_%s.png" % [Time.get_datetime_string_from_system(false, false).replace(":", "").replace("-", "").replace("T", "_"), String(last_data.code) if last_data.code != "" else "run"]
	var path := out_dir + file_name
	if image.save_png(path) != OK:
		push_warning("Teilen-Karte konnte nicht gespeichert werden: %s" % path)
		return ""
	_prune(out_dir)
	last_path = path
	return path


## Alles, was die Karte zeigt, aus RunStats (oder einem Chronik-Eintrag).
static func card_data(stats: Dictionary) -> Dictionary:
	var chronicle: Variant = load(CHRONICLE_PATH) if ResourceLoader.exists(CHRONICLE_PATH) else null
	var meta: Variant = load(META_DATA_PATH) if ResourceLoader.exists(META_DATA_PATH) else null
	var strain_id := String(stats.get("strain_id", ""))
	var strain: Dictionary = meta.STRAINS.get(strain_id, {}) if meta != null else {}
	var diff := int(stats.get("difficulty", 0))
	var diff_name := "Wild"
	if meta != null and diff >= 0 and diff < meta.DIFFICULTIES.size():
		diff_name = String(meta.DIFFICULTIES[diff].name)
	var run_seed := int(stats.get("seed", 0))
	var code := String(stats.get("seed_code", ""))
	if code == "" and run_seed > 0 and chronicle != null:
		code = chronicle.seed_code(run_seed)
	var flood := int(stats.get("flood_stage", -1))
	if flood < 0:
		flood = chronicle.flood_stage(stats) if chronicle != null else 0
	# Build: attack forms and traits by rank (highest first), evolutions on top.
	var build: Array = []
	var evolutions: Array = stats.get("evolutions", []) if stats.get("evolutions", []) is Array else []
	for e in evolutions:
		build.append({"id": String(e), "rank": 3, "evolved": true})
	var mutations: Dictionary = stats.get("mutations", {}) if stats.get("mutations", {}) is Dictionary else {}
	var ids := mutations.keys()
	ids.sort_custom(func(a, b) -> bool: return int(mutations[a]) > int(mutations[b]) or (int(mutations[a]) == int(mutations[b]) and String(a) < String(b)))
	for id in ids:
		if int(mutations[id]) > 0 and not evolutions.has(id):
			build.append({"id": String(id), "rank": int(mutations[id]), "evolved": false})
	var date := String(stats.get("daily_date", ""))
	if date == "":
		date = String(stats.get("date", ""))
	return {
		"strain_id": strain_id, "strain_name": String(strain.get("name", strain_id if strain_id != "" else "Mawlings")),
		"tint": Color(String(strain.get("tint", "#d9401f"))),
		"difficulty": diff, "difficulty_name": diff_name,
		"seconds": maxf(0.0, float(stats.get("seconds", 0.0))),
		"peak": int(stats.get("peak_population", stats.get("peak", 0))),
		"start": int(stats.get("start_population", 0)),
		"kills": int(stats.get("kills", 0)), "bosses": int(stats.get("bosses", 0)),
		"biomass": int(float(stats.get("biomass", 0.0))),
		"flood_stage": flood, "build": build.slice(0, 6), "build_total": build.size(),
		"code": code, "daily": bool(stats.get("daily", false)), "date": date,
		"daily_rank": int(stats.get("daily_rank", 0)),
	}


static func time_text(seconds: float) -> String:
	var s := int(seconds)
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%02d:%02d" % [s / 60, s % 60]


func _render_viewport(data: Dictionary) -> Image:
	var viewport := SubViewport.new()
	viewport.name = "ShareCardViewport"
	viewport.size = SIZE
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.gui_disable_input = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var painter := Painter.new()
	painter.data = data
	painter.size = Vector2(SIZE)
	viewport.add_child(painter)
	add_child(viewport)
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	viewport.queue_free()
	return image


## CPU-Ersatzbild für Läufe ohne Grafik: Markenfarben, Stammfarbe, Balken.
static func _fallback_image(data: Dictionary) -> Image:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGB8)
	var top := Color("0a1c17")
	var low := Color("081611")
	for y in range(0, SIZE.y, 16):
		image.fill_rect(Rect2i(0, y, SIZE.x, 16), top.lerp(Color("123326"), sin(float(y) / SIZE.y * PI)).lerp(low, float(y) / SIZE.y * 0.3))
	var tint: Color = data.get("tint", S.EMBER)
	image.fill_rect(Rect2i(140, 820, 800, 140), tint.darkened(0.2))
	image.fill_rect(Rect2i(140, 1480, 800, 120), Color("0c1d17"))
	return image


func _prune(out_dir: String) -> void:
	var dir := DirAccess.open(out_dir)
	if dir == null:
		return
	var files: Array = []
	for f in dir.get_files():
		if f.begins_with("mawlings_") and f.ends_with(".png"):
			files.append(f)
	files.sort()
	while files.size() > KEEP_FILES:
		dir.remove(files.pop_front())


# ====================================================================== painter

class Painter extends "res://scripts/ui/menu/menu_canvas.gd":
	var data: Dictionary = {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ensure_font()

	func _draw() -> void:
		var w := size.x
		var tint: Color = data.get("tint", S.EMBER)
		# Readable accent: very dark strains (Nachtmaul) get lifted for text and glows.
		var accent := tint if tint.get_luminance() > 0.25 else tint.lightened(0.45)
		_background(tint)
		_maw_frame()
		_logo(Vector2(w * 0.5, 356))
		_strain_banner(Vector2(w * 0.5, 540), accent)
		_hero_time(Vector2(w * 0.5, 900), accent)
		_swarm_line(Vector2(w * 0.5, 1030), accent)
		_tiles(1086)
		_build_row(1290)
		_code_panel(Rect2(90, 1466, w - 180, 176), accent)
		_maw_motif(Vector2(w * 0.5, 1770), accent)

	# ------------------------------------------------------------ background

	func _grad(rect: Rect2, top: Color, bottom: Color) -> void:
		draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]),
			PackedColorArray([top, top, bottom, bottom]))

	static var _soft: Texture2D = null

	## Smooth radial glow (one textured quad, no visible rings).
	func _glow(c: Vector2, r: float, color: Color, _rings: int = 0) -> void:
		if _soft == null:
			var g := Gradient.new()
			g.set_color(0, Color(1, 1, 1, 1))
			g.set_color(1, Color(1, 1, 1, 0))
			g.add_point(0.45, Color(1, 1, 1, 0.42))
			var tex := GradientTexture2D.new()
			tex.gradient = g
			tex.fill = GradientTexture2D.FILL_RADIAL
			tex.fill_from = Vector2(0.5, 0.5)
			tex.fill_to = Vector2(1.0, 0.5)
			tex.width = 256
			tex.height = 256
			_soft = tex
		draw_texture_rect(_soft, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false, color)

	func _background(tint: Color) -> void:
		var w := size.x
		var h := size.y
		_grad(Rect2(0, 0, w, h * 0.45), Color("07150f"), Color("123326"))
		_grad(Rect2(0, h * 0.45, w, h * 0.55), Color("123326"), Color("06120d"))
		# Strain-coloured heat behind the time, soft cyan mist low.
		_glow(Vector2(w * 0.5, 860), 820, Color(tint, 0.5))
		_glow(Vector2(w * 0.5, 1560), 560, Color(S.CYAN, 0.12))
		# Light rays from the top centre.
		var ray_origin := Vector2(w * 0.5, 120)
		for i in 7:
			var a := (i - 3) * 0.22
			var far_l := ray_origin + Vector2(sin(a - 0.05), cos(a - 0.05)) * 1500.0
			var far_r := ray_origin + Vector2(sin(a + 0.05), cos(a + 0.05)) * 1500.0
			draw_colored_polygon(PackedVector2Array([ray_origin, far_l, far_r]), Color(S.GOLD, 0.025))
		# Jungle leaves along both edges.
		var rng := RandomNumberGenerator.new()
		rng.seed = 90210
		for i in 30:
			var left := i % 2 == 0
			var y := rng.randf_range(120, h - 120)
			var x := rng.randf_range(-80, 60) if left else rng.randf_range(w - 60, w + 80)
			var angle := rng.randf_range(-0.9, 0.9) + (0.0 if left else PI)
			var shade := rng.randf()
			_leaf(Vector2(x, y), rng.randf_range(140, 280), rng.randf_range(30, 62), angle, Color("0d2a1e").lerp(Color("1e4d31"), shade))
		for i in 46:
			var p := Vector2(rng.randf_range(40, w - 40), rng.randf_range(160, h - 160))
			var r := rng.randf_range(2.0, 6.0)
			draw_circle(p, r * 2.6, Color(S.CYAN, 0.05))
			draw_circle(p, r, Color(Color("b9f3d8"), rng.randf_range(0.25, 0.6)))
		# Vignette.
		_grad(Rect2(0, 0, w, 300), Color(0, 0, 0, 0.55), Color(0, 0, 0, 0))
		_grad(Rect2(0, h - 360, w, 360), Color(0, 0, 0, 0), Color(0, 0, 0, 0.6))

	## The whole card sits inside a maw: upper teeth hang from the top edge,
	## lower teeth rise from the bottom (story UI covers these bands anyway).
	func _maw_frame() -> void:
		var w := size.x
		var h := size.y
		var gum := S.DANGER.darkened(0.5)
		_jaw_band(Vector2(-20, 36), Vector2(w * 0.5, 96), Vector2(w + 20, 36), 34.0, gum, 1.0, 13, 86.0)
		_jaw_band(Vector2(-20, h - 36), Vector2(w * 0.5, h - 96), Vector2(w + 20, h - 36), 34.0, gum, -1.0, 11, 70.0)

	func _jaw_band(a: Vector2, ctrl: Vector2, b: Vector2, thick: float, gum: Color, dir: float, teeth: int, longest: float) -> void:
		var top := PackedVector2Array()
		var low := PackedVector2Array()
		for i in 25:
			var t := float(i) / 24.0
			var p := _bezier(a, ctrl, b, t)
			top.append(p - Vector2(0, thick * 0.5))
			low.append(p + Vector2(0, thick * 0.5))
		for i in teeth:
			var t := (i + 0.5) / teeth
			var p := _bezier(a, ctrl, b, t)
			var edge := p + Vector2(0, dir * thick * 0.4)
			var edge_factor := absf(t - 0.5) * 2.0
			var length := lerpf(longest * 0.45, longest, edge_factor) if i % 2 == 0 else lerpf(longest * 0.3, longest * 0.6, edge_factor)
			var half := 14.0 + length * 0.14
			var tip := edge + Vector2((0.5 - t) * 18.0, dir * length)
			draw_colored_polygon(PackedVector2Array([edge + Vector2(-half - 3, 0), edge + Vector2(half + 3, 0), tip + Vector2(0, dir * 4)]), S.OUTLINE)
			draw_colored_polygon(PackedVector2Array([edge + Vector2(-half, 0), edge + Vector2(half, 0), tip]), S.BONE)
			draw_colored_polygon(PackedVector2Array([edge + Vector2(half * 0.1, 0), edge + Vector2(half, 0), tip]), S.BONE.darkened(0.22))
		var band := top.duplicate()
		for i in range(low.size() - 1, -1, -1):
			band.append(low[i])
		draw_colored_polygon(band, S.OUTLINE)
		var inner := PackedVector2Array()
		var colors := PackedColorArray()
		for i in top.size():
			inner.append(top[i].lerp(low[i], 0.18))
			colors.append(gum.lightened(0.35))
		for i in range(low.size() - 1, -1, -1):
			inner.append(low[i].lerp(top[i], 0.18))
			colors.append(gum)
		draw_polygon(inner, colors)

	# ------------------------------------------------------------ logo + banner

	func _logo(c: Vector2) -> void:
		var title := "MAWLINGS"
		var fs := 150
		var face := S.display_font()
		var tw := face.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var origin := Vector2(c.x - tw * 0.5, c.y)
		_glow(Vector2(c.x, c.y - 50), 460, Color(S.EMBER, 0.3))
		draw_string_outline(face, origin + Vector2(0, 12), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 22, Color(S.OUTLINE, 0.75))
		draw_string_outline(face, origin + Vector2(0, 7), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 16, S.OUTLINE)
		draw_string(face, origin + Vector2(0, 7), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, S.EMBER.darkened(0.5))
		draw_string(face, origin + Vector2(0, -4), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, S.GOLD.lightened(0.35))
		draw_string(face, origin, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, S.EMBER_GLOW.lerp(S.EMBER, 0.35))
		# Fangs bite into the word from above and below.
		var left := c.x - tw * 0.5 - 40
		var right := c.x + tw * 0.5 + 40
		_logo_jaw(Vector2(left, c.y - 138), Vector2(c.x, c.y - 196), Vector2(right, c.y - 138), 24.0, 1.0, [0.06, 0.16, 0.28, 0.4, 0.5, 0.6, 0.72, 0.84, 0.94], [56.0, 38.0, 22.0, 17.0, 15.0, 17.0, 22.0, 38.0, 56.0])
		_logo_jaw(Vector2(left + 56, c.y + 26), Vector2(c.x, c.y + 64), Vector2(right - 56, c.y + 26), 20.0, -1.0, [0.1, 0.24, 0.38, 0.5, 0.62, 0.76, 0.9], [38.0, 22.0, 16.0, 14.0, 16.0, 22.0, 38.0])
		var sub := "DIE HORDE BIST DU"
		var sw := S.body_font().get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x * 0.5
		for sgn in [-1.0, 1.0]:
			draw_line(Vector2(c.x + sgn * (sw + 16), c.y + 106), Vector2(c.x + sgn * (sw + 130), c.y + 106), Color(S.TOXIC, 0.5), 2.0, true)
			_diamond(Vector2(c.x + sgn * (sw + 138), c.y + 106), 6, S.TOXIC)
		S.text(self, sub, Vector2(c.x, c.y + 116), 30, S.TOXIC.lerp(S.TEXT, 0.4), true, 6, S.body_font())

	func _logo_jaw(a: Vector2, ctrl: Vector2, b: Vector2, thick: float, dir: float, spots: Array, lengths: Array) -> void:
		var gum := S.DANGER.darkened(0.45)
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
			var tip := edge + Vector2((0.5 - t) * 10.0, dir * float(lengths[i]))
			var half := 8.0 + float(lengths[i]) * 0.16
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
		draw_colored_polygon(inner, gum)
		for p in [a, b]:
			draw_circle(p, thick * 0.75, S.OUTLINE)
			draw_circle(p, thick * 0.55, S.BONE.darkened(0.15))

	func _strain_banner(c: Vector2, accent: Color) -> void:
		var label := "%s  ·  %s" % [String(data.strain_name).to_upper(), String(data.difficulty_name).to_upper()]
		var fs := 40
		var tw := S.display_font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var daily: bool = data.daily
		var extra := 0.0
		var daily_label := ""
		if daily:
			daily_label = "TAGES-BRUT"
			if int(data.daily_rank) > 0:
				daily_label += "  #%d" % int(data.daily_rank)
			extra = S.display_font().get_string_size(daily_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x + 96
		var total := tw + 104 + extra
		var rect := Rect2(c.x - total * 0.5, c.y - 40, total, 80)
		draw_colored_polygon(_rounded_points(rect.grow(4), 44, 6), S.OUTLINE)
		draw_colored_polygon(_rounded_points(rect, 40, 6), Color("0c1d17"))
		draw_colored_polygon(_rounded_points(Rect2(rect.position, Vector2(tw + 104, rect.size.y)), 40, 6), Color(accent, 0.22))
		var pts := _rounded_points(rect, 40, 6)
		pts.append(pts[0])
		draw_polyline(pts, Color(accent, 0.85), 3.0, true)
		_mawling_head(rect.position + Vector2(50, 40), 26, accent)
		S.text(self, label, rect.position + Vector2(88, 54), fs, S.TEXT, false, 7)
		if daily:
			var x := rect.position.x + tw + 104
			draw_line(Vector2(x, rect.position.y + 14), Vector2(x, rect.end.y - 14), Color(S.GOLD, 0.5), 2.0)
			_sun(Vector2(x + 44, c.y), 18, S.GOLD)
			S.text(self, daily_label, Vector2(x + 76, c.y + 12), 34, S.GOLD, false, 6)

	func _sun(c: Vector2, r: float, color: Color) -> void:
		for i in 10:
			var a := TAU * i / 10.0
			var d := Vector2(cos(a), sin(a))
			draw_colored_polygon(PackedVector2Array([c + d * r * 0.95 + d.orthogonal() * r * 0.2, c + d * r * 1.6, c + d * r * 0.95 - d.orthogonal() * r * 0.2]), color.darkened(0.1))
		draw_circle(c, r * 0.85, color)
		draw_circle(c + Vector2(-r * 0.25, -r * 0.25), r * 0.3, Color(1, 1, 1, 0.4))

	# ------------------------------------------------------------ hero

	func _hero_time(c: Vector2, accent: Color) -> void:
		S.text(self, "ÜBERLEBT", Vector2(c.x, c.y - 250), 46, Color(S.TEXT_DIM, 0.95), true, 6, S.body_font())
		var value: String = _time_text(float(data.seconds))
		var fs := 300 if value.length() <= 5 else 220
		var face := S.display_font()
		var tw := face.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if tw > size.x - 120:
			fs = int(fs * (size.x - 120) / tw)
			tw = face.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var origin := Vector2(c.x - tw * 0.5, c.y)
		_glow(Vector2(c.x, c.y - fs * 0.36), tw * 0.66, Color(accent, 0.45))
		draw_string_outline(face, origin + Vector2(0, 16), value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 34, Color(S.OUTLINE, 0.8))
		draw_string_outline(face, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 44, Color(accent, 0.35))
		draw_string_outline(face, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 22, S.OUTLINE)
		draw_string(face, origin + Vector2(0, 8), value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, accent.darkened(0.45))
		draw_string(face, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		# Divider with diamonds under the number.
		var y := c.y + 40
		draw_line(Vector2(c.x - 300, y), Vector2(c.x - 40, y), Color(accent, 0.5), 3.0, true)
		draw_line(Vector2(c.x + 40, y), Vector2(c.x + 300, y), Color(accent, 0.5), 3.0, true)
		_diamond(Vector2(c.x, y), 12, accent)
		_diamond(Vector2(c.x - 310, y), 6, Color(accent, 0.8))
		_diamond(Vector2(c.x + 310, y), 6, Color(accent, 0.8))

	func _time_text(seconds: float) -> String:
		var s := int(seconds)
		if s >= 3600:
			return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
		return "%d:%02d" % [s / 60, s % 60]

	## "25 → 196 MAWLINGS" (start only when the stats carry it).
	func _swarm_line(c: Vector2, accent: Color) -> void:
		var peak := int(data.peak)
		var start := int(data.start)
		var face := S.display_font()
		var parts: Array = []
		if start > 0 and start < peak:
			parts.append([str(start), 72, Color(S.TEXT_DIM, 0.9)])
			parts.append(["→", 72, Color(S.TEXT_DIM, 0.7)])
		parts.append([str(peak), 96, S.EMBER_GLOW.lerp(accent, 0.25)])
		parts.append(["MAWLINGS", 52, S.TEXT])
		var total := 0.0
		for p in parts:
			total += face.get_string_size(p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, p[1]).x + 22
		var head := 58.0
		total += head + 10
		var x := c.x - total * 0.5
		_mawling_head(Vector2(x + head * 0.5, c.y - 30), 30, S.EMBER)
		x += head + 10
		for p in parts:
			x += S.text(self, p[0], Vector2(x, c.y), p[1], p[2], false, 9) + 22
		S.text(self, "HÖCHSTER SCHWARM", Vector2(c.x, c.y + 44), 30, Color(S.TEXT_DIM, 0.95), true, 5, S.body_font())

	# ------------------------------------------------------------ tiles + build

	func _tiles(y: float) -> void:
		# Only numbers worth showing: zero bosses / no flood give way to biomass.
		var tiles: Array = [["KILLS", str(int(data.kills)), S.CYAN]]
		if int(data.bosses) > 0:
			tiles.append(["BOSSE", str(int(data.bosses)), S.GOLD])
		if int(data.flood_stage) > 0:
			tiles.append(["FLUTSTUFE", str(int(data.flood_stage)), S.VIOLET])
		if tiles.size() < 3:
			tiles.append(["BIOMASSE", str(int(data.biomass)), S.AMBER])
		var margin := 90.0
		var gap := 24.0
		var tw := (size.x - margin * 2 - gap * 2) / 3.0
		var x0 := (size.x - tiles.size() * tw - (tiles.size() - 1) * gap) * 0.5
		for i in tiles.size():
			var rect := Rect2(x0 + i * (tw + gap), y, tw, 164)
			var col: Color = tiles[i][2]
			draw_colored_polygon(_rounded_points(Rect2(rect.position + Vector2(0, 8), rect.size), 28, 6), Color(0, 0, 0, 0.4))
			draw_colored_polygon(_rounded_points(rect, 28, 6), Color("0c1d17f0"))
			var inner := rect.grow(-4)
			draw_polygon(_rounded_points(inner, 25, 6), _vertical_colors(_rounded_points(inner, 25, 6), inner, Color(col, 0.2), Color(col, 0.02)))
			var pts := _rounded_points(rect, 28, 6)
			pts.append(pts[0])
			draw_polyline(pts, Color(col, 0.8), 3.0, true)
			S.text(self, tiles[i][1], Vector2(rect.get_center().x, rect.position.y + 98), 76, col.lightened(0.3), true, 8)
			S.text(self, tiles[i][0], Vector2(rect.get_center().x, rect.position.y + 140), 28, Color(S.TEXT_DIM, 0.95), true, 5, S.body_font())

	func _vertical_colors(points: PackedVector2Array, rect: Rect2, top: Color, bottom: Color) -> PackedColorArray:
		var colors := PackedColorArray()
		for p in points:
			colors.append(top.lerp(bottom, clampf((p.y - rect.position.y) / maxf(1.0, rect.size.y), 0.0, 1.0)))
		return colors

	func _build_row(y: float) -> void:
		var build: Array = data.build
		var c := size.x * 0.5
		S.text(self, "BUILD", Vector2(c, y), 30, S.VIOLET.lerp(S.TEXT, 0.35), true, 5)
		var hw := S.display_font().get_string_size("BUILD", HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x * 0.5
		for sgn in [-1.0, 1.0]:
			draw_line(Vector2(c + sgn * (hw + 18), y - 10), Vector2(c + sgn * (hw + 200), y - 10), Color(S.VIOLET, 0.45), 2.0, true)
			_diamond(Vector2(c + sgn * (hw + 208), y - 10), 6, S.VIOLET)
		if build.is_empty():
			S.text(self, "Reiner Schwarm – keine Mutation", Vector2(c, y + 84), 34, Color(S.TEXT_DIM, 0.9), true, 5, S.body_font())
			return
		var slot := 132.0
		var n := build.size()
		var x0 := c - (n * slot - 20) * 0.5
		for i in n:
			var b: Dictionary = build[i]
			var ic := Vector2(x0 + i * slot + (slot - 20) * 0.5, y + 82)
			var col: Color = S.GOLD if b.evolved else S.VIOLET
			for k in 4:
				draw_circle(ic, 58 + k * 5, Color(col, 0.04))
			draw_circle(ic, 54, Color("040b08"))
			draw_arc(ic, 54, 0, TAU, 48, col, 4.0, true)
			if UiIcons.has(String(b.id)):
				UiIcons.draw(self, String(b.id), Rect2(ic - Vector2(40, 40), Vector2(80, 80)))
			else:
				_diamond(ic, 26, col)
			# Rank pips under the medallion.
			for k in 3:
				var p := ic + Vector2((k - 1) * 22, 74)
				var filled := k < int(b.rank)
				_diamond(p, 8, col if filled else Color(col, 0.2))
		if int(data.build_total) > n:
			S.text(self, "+%d" % (int(data.build_total) - n), Vector2(x0 + n * slot + 8, y + 96), 36, S.VIOLET, false, 5)

	# ------------------------------------------------------------ code + motif

	func _code_panel(rect: Rect2, accent: Color) -> void:
		var code := String(data.code)
		draw_colored_polygon(_rounded_points(Rect2(rect.position + Vector2(0, 8), rect.size), 34, 6), Color(0, 0, 0, 0.45))
		draw_colored_polygon(_rounded_points(rect, 34, 6), Color("0a1a14f2"))
		var pts := _rounded_points(rect, 34, 6)
		pts.append(pts[0])
		draw_polyline(pts, Color(S.CYAN, 0.75), 3.0, true)
		var inner := _rounded_points(rect.grow(-8), 28, 6)
		inner.append(inner[0])
		draw_polyline(inner, Color(S.CYAN, 0.18), 2.0, true)
		var c := rect.get_center().x
		var challenge := "SCHLÄGST DU %s?" % _time_text(float(data.seconds))
		if code == "":
			S.text(self, challenge, Vector2(c, rect.position.y + 78), 52, S.GOLD, true, 8)
			S.text(self, "Die Horde wartet.", Vector2(c, rect.position.y + 130), 32, Color(S.TEXT_DIM, 0.95), true, 5, S.body_font())
			return
		S.text(self, challenge, Vector2(c, rect.position.y + 62), 44, S.GOLD, true, 7)
		var label := "KARTE"
		var lw := S.display_font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		var spaced := " ".join(code.split(""))
		var cw := S.display_font().get_string_size(spaced, HORIZONTAL_ALIGNMENT_LEFT, -1, 58).x
		var x := c - (lw + 20 + cw) * 0.5
		S.text(self, label, Vector2(x, rect.position.y + 118), 30, S.CYAN.lerp(S.TEXT, 0.3), false, 5)
		S.text(self, spaced, Vector2(x + lw + 20, rect.position.y + 122), 58, S.TEXT, false, 8)
		S.text(self, "Gleicher Code = gleiche Karte", Vector2(c, rect.position.y + 158), 28, Color(S.TEXT_DIM, 0.95), true, 5, S.body_font())

	## Small open maw between the lower teeth: the brand mark.
	func _maw_motif(c: Vector2, accent: Color) -> void:
		_glow(c, 130, Color(S.EMBER, 0.4))
		if UiIcons.has("mawling_head_color"):
			UiIcons.draw(self, "mawling_head_color", Rect2(c - Vector2(62, 62), Vector2(124, 124)))
		else:
			_mawling_head(c, 52, S.EMBER)
