extends Node
## Teilen-Karte (Etappe 10, Stil Etappe 15 „brawl“): rendert aus RunStats ein
## 1080 x 1920-Bild (9:16, Story-Format) mit den Kit-Bausteinen und speichert es
## als PNG. Gezeichnet wird im 900 x 1600-Raster des Spiels (gleiche Typo-Stufen)
## und auf 1080 x 1920 skaliert.
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
## Sichere Zone: oben ~260 px und unten ~300 px (1920er-Raster) verdecken
## TikTok/Instagram-Story ihre Bedienelemente – dort liegen nur Hintergrund und
## das Markenzeichen; Logo, Stamm, Zeit, Werte, Build und Code stehen dazwischen.

const S := preload("res://scripts/ui/ui_style.gd")
const UiIcons := preload("res://scripts/ui/ui_icons.gd")
const UiArt := preload("res://scripts/ui/ui_art.gd")
const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")
const CHRONICLE_PATH := "res://scripts/meta/chronicle.gd"
const META_DATA_PATH := "res://scripts/meta/meta_data.gd"

const SIZE := Vector2i(1080, 1920)
const BASE := Vector2(900, 1600)
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
		"tint": Color(String(strain.get("tint", ""))) if strain.has("tint") else S.brawl_tone("ember")["face"],
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
	# The painter lays out on the 900 x 1600 base grid of the kit (same type
	# scale as the game) and is scaled up to 1080 x 1920; text is rasterised
	# at the final size.
	var k := float(SIZE.x) / BASE.x
	viewport.oversampling_override = k
	var painter := Painter.new()
	painter.data = data
	painter.size = BASE
	painter.scale = Vector2(k, k)
	viewport.add_child(painter)
	add_child(viewport)
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	viewport.queue_free()
	return image


## CPU-Ersatzbild für Läufe ohne Grafik: Panel-Farben, Stammfarbe, Balken.
static func _fallback_image(data: Dictionary) -> Image:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGB8)
	for y in range(0, SIZE.y, 16):
		image.fill_rect(Rect2i(0, y, SIZE.x, 16), S.BRAWL_PANEL_TOP.lerp(S.BRAWL_PANEL_BOTTOM, float(y) / SIZE.y))
	var tint: Color = data.get("tint", S.brawl_tone("ember")["face"])
	image.fill_rect(Rect2i(156, 432, 768, 480), tint)
	image.fill_rect(Rect2i(156, 948, 768, 180), S.brawl_tone("loot")["face"])
	image.fill_rect(Rect2i(156, 1486, 768, 132), S.BRAWL_WELL)
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

## Stage 15 (brawl kit): painted menu background, logo, strain card with the
## tribe portrait, survival time, three stat tiles, build plates and the map
## code. Safe zone: story UIs cover ~217 px at the top and ~250 px at the
## bottom of the 1600 base; everything important sits between 190 and 1350.
class Painter extends Control:
	const TOP := 190.0
	const LEFT := 130.0
	const W := 640.0
	const ROMAN := ["I", "II", "III", "IV", "V"]

	var data: Dictionary = {}
	static var _soft: Texture2D = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var tint: Color = data.get("tint", S.brawl_tone("ember")["face"])
		_background(tint)
		_logo(Vector2(size.x * 0.5, TOP))
		_strain_card(Rect2(LEFT, 356, W, 410), tint)
		_hero(Rect2(LEFT, 790, W, 150))
		_tiles(Rect2(LEFT, 960, W, 130))
		_build(Rect2(LEFT, 1110, W, 120))
		_code(Rect2(LEFT, 1250, W, 104))
		_maw_mark(Vector2(size.x * 0.5, 1476))

	# ------------------------------------------------------------ helpers

	func _txt(pos: Vector2, value: String, font_size: int, color: Color = Color.WHITE, align: int = Kit.LEFT, max_w: float = 0.0, font: Font = null) -> float:
		return Kit.text_outlined(self, pos, value, font_size, color, -1, -1, font, align, max_w)

	func _icon(id: String, center: Vector2, side: float) -> bool:
		if not UiIcons.has(id):
			return false
		UiIcons.draw(self, id, Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side)))
		return true

	## Smooth radial glow (one textured quad).
	func _glow(c: Vector2, r: Vector2, color: Color) -> void:
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
		draw_texture_rect(_soft, Rect2(c - r, r * 2.0), false, color)

	## Strain tint as a kit tone: very light or very dark tints keep a visible frame.
	func _strain_tone(tint: Color) -> Variant:
		if tint.get_luminance() < 0.12:
			return "special"
		if tint.s < 0.2 and tint.v > 0.8:
			return tint.darkened(0.35)
		return tint

	# ------------------------------------------------------------ background

	func _background(tint: Color) -> void:
		var full := Rect2(Vector2.ZERO, size)
		var quad := PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
		var painted := UiArt.menu_background()
		if painted != null:
			UiArt.draw_cover(self, painted, quad, full, Color(0.7, 0.72, 0.8))
		else:
			draw_polygon(quad, PackedColorArray([S.BRAWL_PANEL_TOP, S.BRAWL_PANEL_TOP, S.BRAWL_PANEL_BOTTOM, S.BRAWL_PANEL_BOTTOM]))
		draw_rect(full, Color(S.BRAWL_PANEL_BOTTOM, 0.34))
		_glow(Vector2(size.x * 0.5, 600), Vector2(560, 520), Color(S.brawl_tone(_strain_tone(tint))["light"], 0.3))
		_glow(Vector2(size.x * 0.5, 880), Vector2(460, 240), Color(S.brawl_tone("loot")["light"], 0.14))

	# ------------------------------------------------------------ logo

	func _logo(top_center: Vector2) -> void:
		var tex := UiArt.logo()
		if tex == null:
			_txt(top_center + Vector2(0, 70), "MAWLINGS", 96, S.brawl_tone("ember")["light"], Kit.CENTER | Kit.MIDDLE)
			return
		var lw := 600.0
		var lh := lw * float(tex.get_height()) / float(tex.get_width())
		var rect := Rect2(top_center.x - lw * 0.5, top_center.y, lw, lh)
		draw_texture_rect(tex, Rect2(rect.position + Vector2(0, S.SHADOW_Y), rect.size), false, Color(S.BRAWL_INK, 0.6))
		draw_texture_rect(tex, rect, false)

	# ------------------------------------------------------------ strain card

	func _strain_card(rect: Rect2, tint: Color) -> void:
		var tone: Variant = _strain_tone(tint)
		var header := 70.0
		Kit.card(self, rect, tone, "normal", header, S.R_XL)
		var body := Kit.card_inner(rect, header).grow(S.SPACE_S)
		var cx := rect.get_center().x
		var light: Color = S.brawl_tone(tone)["light"]
		# Portrait on a lit ground ellipse.
		var foot := Vector2(cx, body.end.y - 30.0)
		_glow(Vector2(cx, foot.y - 120.0), Vector2(260, 150), Color(light, 0.3))
		draw_colored_polygon(_ellipse(foot + Vector2(0, 4), 170, 30), Color(S.BRAWL_INK, 0.55))
		draw_colored_polygon(_ellipse(foot, 158, 25), Color(light, 0.22))
		var tex := UiArt.tribe(String(data.get("strain_id", "")))
		if tex == null:
			tex = UiArt.tribe("glutmaw")
		if tex != null:
			UiArt.draw_standing(self, tex, foot + Vector2(0, 8), 262.0)
		elif not _icon("mawling_head_color", foot + Vector2(0, -110), 180):
			pass
		_txt(Vector2(cx, rect.position.y + S.STROKE_L + (header + 7.0) * 0.5 + 2.0), String(data.strain_name).to_upper(), S.T_TITLE, Color.WHITE, Kit.CENTER | Kit.MIDDLE, rect.size.x - 80.0)
		# Difficulty chip top-left, daily chip top-right.
		var diff := int(data.get("difficulty", 0))
		var dname := String(data.difficulty_name).to_upper()
		var dw := S.display_font().get_string_size(dname, HORIZONTAL_ALIGNMENT_LEFT, -1, S.T_LABEL).x + 64.0
		var chip := Rect2(body.position.x + S.SPACE_M, body.position.y + S.SPACE_M, dw, 46.0)
		Kit.chip(self, chip, "dark")
		_icon(["diff_wild", "diff_brutal", "diff_apex"][clampi(diff, 0, 2)], Vector2(chip.position.x + 24.0, chip.get_center().y), 34.0)
		_txt(Vector2(chip.position.x + 46.0, chip.get_center().y), dname, S.T_LABEL, Color.WHITE, Kit.LEFT | Kit.MIDDLE)
		if bool(data.daily):
			var label := "TAGES-BRUT"
			if int(data.daily_rank) > 0:
				label += "  #%d" % int(data.daily_rank)
			var lw := S.display_font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, S.T_LABEL).x + 36.0
			var day := Rect2(body.end.x - S.SPACE_M - lw, body.position.y + S.SPACE_M, lw, 46.0)
			Kit.chip(self, day, "loot")
			_txt(day.get_center(), label, S.T_LABEL, Color.WHITE, Kit.CENTER | Kit.MIDDLE)

	func _time_text(seconds: float) -> String:
		var s := int(seconds)
		if s >= 3600:
			return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
		return "%d:%02d" % [s / 60, s % 60]

	func _ellipse(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 32:
			var a := TAU * i / 32.0
			pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		return pts

	# ------------------------------------------------------------ time, tiles, build

	func _hero(rect: Rect2) -> void:
		Kit.panel(self, rect, "loot", S.R_L)
		var value: String = _time_text(float(data.seconds))
		var tw := minf(S.number_font().get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 96).x, rect.size.x - 200.0)
		var x0 := rect.get_center().x - (104.0 + 24.0 + tw) * 0.5
		var pc := Vector2(x0 + 52.0, rect.get_center().y)
		Kit.icon_plate(self, pc, 104.0, "dark")
		_icon("clock", Kit.plate_center(pc, 104.0), 64.0)
		var x := x0 + 128.0
		_txt(Vector2(x + 4.0, rect.position.y + 36.0), "ÜBERLEBT", S.T_LABEL, Color.WHITE, Kit.LEFT | Kit.MIDDLE)
		Kit.text_outlined(self, Vector2(x, rect.position.y + 94.0), value, 96, Color.WHITE, 18, 7, S.number_font(), Kit.LEFT | Kit.MIDDLE, tw)

	func _tiles(area: Rect2) -> void:
		# Peak always; then the most telling of kills, bosses, flood stage, biomass.
		var tiles: Array = [["mawling_head_color", "PEAK", int(data.peak), "ember"], ["jaws", "KILLS", int(data.kills), "ember"]]
		if int(data.bosses) > 0:
			tiles.append(["bog_king", "BOSSE", int(data.bosses), "danger"])
		elif int(data.flood_stage) > 0:
			tiles.append(["skull", "FLUTSTUFE", int(data.flood_stage), "danger"])
		else:
			tiles.append(["biomass", "BIOMASSE", int(data.biomass), "loot"])
		var gap := S.SPACE_M
		var w := (area.size.x - gap * 2.0) / 3.0
		for i in tiles.size():
			var rect := Rect2(area.position.x + i * (w + gap), area.position.y, w, area.size.y)
			Kit.panel(self, rect, "dark", S.R_L)
			var pc := Vector2(rect.position.x + 46.0, rect.position.y + 50.0)
			Kit.icon_plate(self, pc, 64.0, tiles[i][3])
			_icon(tiles[i][0], Kit.plate_center(pc, 64.0), 48.0)
			Kit.number(self, Vector2(rect.position.x + 88.0, rect.position.y + 52.0), int(tiles[i][2]), S.T_TITLE, Color.WHITE, Kit.LEFT | Kit.MIDDLE, rect.end.x - 12.0 - (rect.position.x + 88.0))
			_txt(Vector2(rect.get_center().x, rect.end.y - 24.0), tiles[i][1], S.T_LABEL, S.BRAWL_TEXT_DIM, Kit.CENTER | Kit.MIDDLE, w - 16.0)

	func _build(rect: Rect2) -> void:
		Kit.panel(self, rect, "dark", S.R_L)
		var build: Array = data.build
		if build.is_empty():
			_txt(rect.get_center(), "Reiner Schwarm – keine Mutation", S.T_BODY, S.BRAWL_TEXT_DIM, Kit.CENTER | Kit.MIDDLE, rect.size.x - 40.0, S.body_bold_font())
			return
		var extra := int(data.build_total) - build.size()
		var n := build.size() + (1 if extra > 0 else 0)
		var step := minf(98.0, (rect.size.x - 40.0) / n)
		var plate := minf(78.0, step - 14.0)
		var x0 := rect.get_center().x - (n - 1) * step * 0.5
		for i in build.size():
			var b: Dictionary = build[i]
			var c := Vector2(x0 + i * step, rect.get_center().y + 4.0)
			Kit.icon_plate(self, c, plate, "special" if b.evolved else "ember")
			_icon(String(b.id), Kit.plate_center(c, plate), plate * 0.76)
			var tag: String = "EVO" if b.evolved else ROMAN[clampi(int(b.rank), 1, ROMAN.size()) - 1]
			Kit.badge(self, c + Vector2(plate * 0.38, -plate * 0.36), tag, "loot" if b.evolved else "neutral", S.T_LABEL)
		if extra > 0:
			_txt(Vector2(x0 + build.size() * step, rect.get_center().y), "+%d" % extra, S.T_HEAD, Color.WHITE, Kit.CENTER | Kit.MIDDLE)

	# ------------------------------------------------------------ code + mark

	func _code(rect: Rect2) -> void:
		Kit.panel(self, rect, "dark", S.R_L)
		var code := String(data.code)
		var challenge := "SCHLÄGST DU %s?" % _time_text(float(data.seconds))
		if code == "":
			_txt(Vector2(rect.get_center().x, rect.position.y + 38.0), challenge, S.T_HEAD, S.brawl_tone("loot")["light"], Kit.CENTER | Kit.MIDDLE, rect.size.x - 40.0)
			_txt(Vector2(rect.get_center().x, rect.end.y - 28.0), "Die Horde wartet.", S.T_BODY, S.BRAWL_TEXT_DIM, Kit.CENTER | Kit.MIDDLE, rect.size.x - 40.0, S.body_bold_font())
			return
		var x := rect.position.x + S.SPACE_XL
		_txt(Vector2(x, rect.position.y + 32.0), challenge, S.T_HEAD, S.brawl_tone("loot")["light"], Kit.LEFT | Kit.MIDDLE, rect.size.x * 0.56)
		_txt(Vector2(x, rect.end.y - 28.0), "Gleicher Code = gleiche Karte", S.T_LABEL, S.BRAWL_TEXT_DIM, Kit.LEFT | Kit.MIDDLE, rect.size.x * 0.56, S.body_bold_font())
		# The code sits in a well on the right, like the menu's KARTEN-CODE.
		var well := Rect2(rect.end.x - S.SPACE_M - 250.0, rect.position.y + S.SPACE_M, 250.0, rect.size.y - S.SPACE_M * 2.0)
		Kit.well(self, well, S.R_M)
		_txt(Vector2(well.get_center().x, well.position.y + 20.0), "KARTEN-CODE", S.T_LABEL, S.brawl_tone("info")["light"], Kit.CENTER | Kit.MIDDLE)
		Kit.number(self, Vector2(well.get_center().x, well.end.y - 28.0), code, 44, Color.WHITE, Kit.CENTER | Kit.MIDDLE, well.size.x - 20.0)

	## Brand mark below the safe zone (covered by story UI anyway).
	func _maw_mark(c: Vector2) -> void:
		Kit.icon_plate(self, c, 120.0, "ember")
		if not _icon("mawling_head_color", Kit.plate_center(c, 120.0), 96.0):
			_txt(c, "M", S.T_TITLE, Color.WHITE, Kit.CENTER | Kit.MIDDLE)
