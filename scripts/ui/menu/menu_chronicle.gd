extends "res://scripts/ui/menu/menu_sheets.gd"
## Menü-Komponente CHRONIK (Etappe 10 „Teilen“): Inhalt des vierten Blatts.
##
## Kind des Menü-Controls (nach menu_sheets.gd, damit es über dem Blattrahmen
## liegt). menu_sheets zeichnet Rahmen, Titel und Schließen-Knopf; diese
## Komponente zeichnet die drei Segmente (LETZTE RUNS · TAGES-BRUT · BESTWERTE)
## und – in einem zweiten Exemplar (role "chronicle_list", clip_contents) – die
## scrollbare Liste. Alle Trefferflächen und Zeilen kommen aus menu.gd
## (chronicle_segment_rect, chronicle_list_rect, chronicle_rows,
## chronicle_row_rect); Eingabe bleibt vollständig in menu.gd.
##
## Neu gezeichnet wird nur bei Änderung (Schlüssel aus Ansicht, Scroll, gedrücktem
## Knopf und chronicle.revision) – wie menu_sheets, siehe ui_layer.gd.

const PROFILE_SCRIPT := "res://scripts/meta/profile.gd"
const SEGMENT_ACCENT := {"runs": S.EMBER, "daily": S.GOLD, "best": S.VIOLET}
const MEDAL := [Color("f5c86a"), Color("d6dde2"), Color("d08a4e")]

var _rows_list: Control = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if menu == null:
		menu = get_parent()
	_icons = load(ICONS_PATH) if ResourceLoader.exists(ICONS_PATH) else null
	_frames = load(FRAMES_PATH) if ResourceLoader.exists(FRAMES_PATH) else null
	if role == "sheets":
		role = "chronicle"
	if role == "chronicle":
		set_anchors_preset(Control.PRESET_FULL_RECT)
		_rows_list = get_script().new()
		_rows_list.role = "chronicle_list"
		_rows_list.menu = menu
		_rows_list.clip_contents = true
		_rows_list.visible = false
		add_child(_rows_list)


func _open() -> bool:
	return menu != null and menu.profile != null and menu.tab == "chronicle" and menu.reward.is_empty() and not menu.settings_open


func _process(_delta: float) -> void:
	if role != "chronicle" or menu == null:
		return
	position = Vector2.ZERO
	size = menu.size
	var open := _open()
	visible = open
	_rows_list.visible = open
	if not open:
		_last_key = null
		return
	var area: Rect2 = menu.chronicle_list_rect()
	_rows_list.position = area.position
	_rows_list.size = area.size
	var revision: int = menu.chronicle.revision if menu.chronicle != null else -1
	_rows_list._repaint([menu.trophy_scroll, area.size, menu.chronicle_view, revision, menu.pressed_rect(), S.colorblind])
	_repaint([size, menu.chronicle_view, menu.pressed_rect(), menu.trophy_scroll, revision])


func _draw() -> void:
	if menu == null or menu.profile == null:
		return
	if role == "chronicle_list":
		_draw_rows()
		return
	_draw_segments()
	_draw_list_scrollbar()

# ================================================================ segments

func _draw_segments() -> void:
	for i in menu.CHRONICLE_VIEWS.size():
		var id: String = menu.CHRONICLE_VIEWS[i]
		var rect: Rect2 = menu.chronicle_segment_rect(i)
		var active: bool = menu.chronicle_view == id
		var down: bool = menu.is_pressed(rect)
		var accent: Color = S.tone(SEGMENT_ACCENT.get(id, S.VIOLET))
		var shape := _rounded_points(rect, 24, 5)
		draw_colored_polygon(_rounded_points(Rect2(rect.position + Vector2(0, 5), rect.size), 24, 5), Color(0, 0, 0, 0.35))
		_gradient_fill(shape, rect, Color(accent, 0.30) if active else S.tone(Color("10231c")), Color(accent, 0.08) if active else S.tone(Color("07120e")))
		if down:
			draw_colored_polygon(shape, Color(1, 1, 1, 0.06))
		_outline(shape, accent if active else Color(accent, 0.35), 3.0 if active else 1.5)
		var po := _press_offset(down)
		var ic := Vector2(rect.position.x + 42, rect.get_center().y) + po
		_segment_glyph(id, ic, accent if active else Color(accent, 0.6))
		var label: String = menu.CHRONICLE_VIEW_NAMES[id]
		var fitted := _fit(label, rect.size.x - 86, [26, 24, 22])
		_txt(fitted[0], Vector2(rect.position.x + 74, rect.get_center().y + 9) + po, fitted[1], S.color("text") if active else S.color("text_dim"), 0, 5)
		if active:
			draw_line(Vector2(rect.position.x + 26, rect.end.y - 8), Vector2(rect.end.x - 26, rect.end.y - 8), accent, 3.0, true)


func _segment_glyph(id: String, c: Vector2, color: Color) -> void:
	match id:
		"runs":
			if not _icon(["clock"], Rect2(c - Vector2(20, 20), Vector2(40, 40)), color.lightened(0.3)):
				draw_arc(c, 15, 0, TAU, 24, color, 4.0, true)
				draw_line(c, c + Vector2(0, -9), color, 3.0, true)
				draw_line(c, c + Vector2(7, 3), color, 3.0, true)
		"daily":
			_sun_glyph(c, 12, color)
		_:
			if not _icon(["trophy"], Rect2(c - Vector2(20, 20), Vector2(40, 40)), color.lightened(0.3)):
				_crown(c, 16, color)


func _sun_glyph(c: Vector2, r: float, color: Color) -> void:
	for i in 8:
		var a := TAU * i / 8.0
		var d := Vector2(cos(a), sin(a))
		draw_colored_polygon(PackedVector2Array([c + d * r * 1.0 + d.orthogonal() * r * 0.28, c + d * r * 1.7, c + d * r * 1.0 - d.orthogonal() * r * 0.28]), color)
	draw_circle(c, r * 0.9, color)
	draw_circle(c + Vector2(-r * 0.25, -r * 0.3), r * 0.28, Color(1, 1, 1, 0.45))


func _draw_list_scrollbar() -> void:
	var max_scroll: float = menu._trophy_scroll_max()
	var area: Rect2 = menu.chronicle_list_rect()
	# Fade the list edges into the panel.
	for e in [[area.position.y, 1.0], [area.end.y, -1.0]]:
		var y0: float = e[0]
		var dir: float = e[1]
		var band := Rect2(area.position.x, y0 if dir > 0 else y0 - 16, area.size.x, 16)
		_gradient_fill(PackedVector2Array([band.position, Vector2(band.end.x, band.position.y), band.end, Vector2(band.position.x, band.end.y)]), band,
			S.tone(Color("0b1a15", 0.85 if dir > 0 else 0.0)), S.tone(Color("0b1a15", 0.0 if dir > 0 else 0.85)))
	if max_scroll <= 0.0:
		return
	var track := Rect2(area.end.x + 4, area.position.y + 6, 6, area.size.y - 12)
	draw_colored_polygon(_rounded_points(track, 2.5, 3), Color(1, 1, 1, 0.06))
	var h := track.size.y * track.size.y / (track.size.y + max_scroll)
	var thumb := Rect2(track.position.x, track.position.y + (track.size.y - h) * menu.trophy_scroll / max_scroll, 6, h)
	draw_colored_polygon(_rounded_points(thumb, 2.5, 3), S.color("violet"))

# ================================================================ rows

func _draw_rows() -> void:
	var rows: Array = menu.chronicle_rows()
	var origin: Vector2 = menu.chronicle_list_rect().position
	var y: float = -menu.trophy_scroll
	for i in rows.size():
		# Same stacking as menu.chronicle_row_rect(i), without rebuilding the rows.
		var local := Rect2(0, y, size.x, float(rows[i].h))
		y += float(rows[i].h) + menu.CHRONICLE_ROW_GAP
		var r := Rect2(local.position + origin, local.size)
		if local.end.y < -8 or local.position.y > size.y + 8:
			continue
		local.size.x -= 12
		var row: Dictionary = rows[i]
		match String(row.kind):
			"run":
				_run_row(local, row.data, menu.is_pressed(r))
			"header":
				_header_row(local, row.data)
			"rank":
				_rank_row(local, row.data, int(row.rank))
			"day":
				_day_row(local, row.data, String(row.date), int(row.count))
			"total":
				_total_row(local, row.data)
			"best":
				_best_row(local, String(row.data.strain_id))
			_:
				_empty_row(local, row.data)


func _time(seconds: float) -> String:
	var s := int(seconds)
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%02d:%02d" % [s / 60, s % 60]


func _short_date(date: String) -> String:
	if date.length() != 10:
		return date
	return "%s.%s." % [date.substr(8, 2), date.substr(5, 2)]


func _strain_color(id: String) -> Color:
	return Color(String(menu.meta.STRAINS.get(id, {}).get("tint", "#d9401f")))


## Strain colour that stays readable on the dark rows (Nachtmaul is almost black).
func _readable(tint: Color) -> Color:
	return tint if tint.get_luminance() > 0.25 else tint.lightened(0.45)


func _strain_badge(c: Vector2, id: String, r: float = 34.0) -> void:
	var tint := _strain_color(id)
	_medallion(c, r, _readable(tint), 0.6)
	_mawling_head(c + Vector2(0, 2), r * 0.66, tint.lightened(0.1) if tint.get_luminance() > 0.1 else tint.lightened(0.35))


## Small pill (flood, daily, difficulty) right-aligned at `right`; returns its left edge.
func _tag(right: float, y: float, text: String, color: Color, glyph: String = "") -> float:
	var w := _w(text, 22) + 28 + (26.0 if glyph != "" else 0.0)
	var rect := Rect2(right - w, y, w, 34)
	var pts := _rounded_points(rect, 17, 4)
	draw_colored_polygon(pts, Color(color, 0.16))
	_outline(pts, Color(color, 0.7), 1.5)
	var x := rect.position.x + 14
	if glyph == "sun":
		_sun_glyph(Vector2(x + 9, rect.get_center().y), 6, color)
		x += 26
	elif glyph == "flood":
		_wave_glyph(Vector2(x + 9, rect.get_center().y), color)
		x += 26
	_txt(text, Vector2(x, rect.position.y + 26), 22, color.lightened(0.3), 0, 4)
	return rect.position.x


func _wave_glyph(c: Vector2, color: Color) -> void:
	for k in 2:
		var pts := PackedVector2Array()
		for i in 9:
			var t := float(i) / 8.0
			pts.append(c + Vector2(-10 + t * 20, -4 + k * 8 + sin(t * TAU) * 3))
		draw_polyline(pts, color, 2.5, true)


func _run_row(rect: Rect2, run: Dictionary, down: bool) -> void:
	var id := String(run.get("strain_id", ""))
	var tint := _readable(_strain_color(id))
	var shape := _rounded_points(rect, 20, 5)
	_gradient_fill(shape, rect, S.tone(Color("10251d")), S.tone(Color("08140f")))
	if down:
		draw_colored_polygon(shape, Color(1, 1, 1, 0.06))
	_outline(shape, Color(tint, 0.45), 1.5)
	var stripe := Rect2(rect.position + Vector2(0, 16), Vector2(6, rect.size.y - 32))
	draw_colored_polygon(_rounded_points(stripe, 3, 2), tint)
	_strain_badge(rect.position + Vector2(62, rect.size.y * 0.5), id)
	var x := rect.position.x + 116
	_txt(_time(float(run.get("seconds", 0.0))), Vector2(x, rect.position.y + 54), 44, S.color("text"), 0, 6)
	var line := "Peak %d  ·  %d Kills" % [int(run.get("peak_population", 0)), int(run.get("kills", 0))]
	_body(line, Vector2(x, rect.position.y + 92), 22, Color(S.color("text_dim"), 0.95))
	# Right side: share glyph, date, tags.
	var right := rect.end.x - 20
	_share_glyph(Vector2(right - 22, rect.get_center().y), 15, Color(S.color("cyan"), 0.8))
	right -= 60
	# Local date and clock time of the run (the stored date is the UTC day key).
	var when := _short_date(String(run.get("date", "")))
	var t := int(run.get("time", 0))
	if t > 0:
		var local := Time.get_datetime_dict_from_unix_time(t + _utc_offset())
		when = "%02d.%02d.  %02d:%02d" % [int(local.day), int(local.month), int(local.hour), int(local.minute)]
	_body(when, Vector2(right, rect.position.y + 42), 22, Color(S.color("text_dim"), 0.9), 2)
	var tag_right := right
	var diff := int(run.get("difficulty", 0))
	var diff_name := String(menu.meta.DIFFICULTIES[clampi(diff, 0, menu.meta.DIFFICULTIES.size() - 1)].name).to_upper()
	tag_right = _tag(tag_right, rect.position.y + 60, diff_name, [S.color("toxic"), S.color("amber"), S.color("danger")][clampi(diff, 0, 2)]) - 8
	if int(run.get("flood_stage", 0)) > 0:
		tag_right = _tag(tag_right, rect.position.y + 60, "FLUT %d" % int(run.flood_stage), S.color("violet"), "flood") - 8
	if bool(run.get("daily", false)):
		var label := "#%d" % int(run.get("daily_rank", 0)) if int(run.get("daily_rank", 0)) > 0 else "TAG"
		_tag(tag_right, rect.position.y + 60, label, S.color("gold"), "sun")


## Local clock offset for the row times (dates are stored in UTC like the daily key).
func _utc_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


func _header_row(rect: Rect2, data: Dictionary) -> void:
	var text := String(data.get("text", ""))
	var y := rect.position.y + 40
	var w := _txt(text, Vector2(rect.position.x + 8, y), 26, S.color("gold"), 0, 5)
	var date := String(data.get("date", ""))
	var right := rect.end.x - 8
	if date != "":
		var profile_script: Variant = load(PROFILE_SCRIPT)
		var code := "KARTE %s" % menu.seed_code(profile_script.daily_seed())
		right -= _body(code, Vector2(right, y), 22, Color(S.color("text_dim"), 0.95), 2) + 18
		_body(_short_date(date), Vector2(rect.position.x + 24 + w, y), 22, Color(S.color("gold"), 0.8))
	draw_line(Vector2(rect.position.x + 8, rect.end.y - 8), Vector2(rect.end.x - 8, rect.end.y - 8), Color(S.color("gold"), 0.3), 2.0, true)


func _rank_row(rect: Rect2, item: Dictionary, rank: int) -> void:
	var color: Color = S.tone(MEDAL[rank - 1]) if rank <= 3 else S.color("text_dim")
	var shape := _rounded_points(rect, 20, 5)
	_gradient_fill(shape, rect, Color(color, 0.14) if rank == 1 else S.tone(Color("10251d")), S.tone(Color("08140f")))
	_outline(shape, Color(color, 0.6 if rank <= 3 else 0.3), 2.0 if rank == 1 else 1.5)
	var mc := rect.position + Vector2(52, rect.size.y * 0.5)
	if rank <= 3:
		draw_circle(mc, 30, S.color("outline"))
		draw_circle(mc, 27, color)
		draw_circle(mc, 20, color.darkened(0.25))
		_txt(str(rank), mc + Vector2(0, 12), 34, S.color("outline"), 1, 0)
	else:
		_txt(str(rank), mc + Vector2(0, 12), 34, S.color("text_dim"), 1, 5)
	var id := String(item.get("strain_id", ""))
	_strain_badge(rect.position + Vector2(134, rect.size.y * 0.5), id, 28)
	var x := rect.position.x + 180
	_txt(_time(float(item.get("seconds", 0.0))), Vector2(x, rect.position.y + 52), 42, S.color("text") if rank > 1 else S.color("gold").lightened(0.3), 0, 6)
	var strain_name := String(menu.meta.STRAINS.get(id, {}).get("name", id))
	_body("Peak %d  ·  %s" % [int(item.get("peak", 0)), strain_name], Vector2(x, rect.position.y + 86), 22, Color(S.color("text_dim"), 0.95))
	if int(item.get("flood_stage", 0)) > 0:
		_tag(rect.end.x - 20, rect.position.y + 33, "FLUT %d" % int(item.flood_stage), S.color("violet"), "flood")


func _day_row(rect: Rect2, item: Dictionary, date: String, count: int) -> void:
	var shape := _rounded_points(rect, 20, 5)
	_gradient_fill(shape, rect, S.tone(Color("10251d")), S.tone(Color("08140f")))
	_outline(shape, Color(S.color("gold"), 0.3), 1.5)
	_sun_glyph(rect.position + Vector2(48, rect.size.y * 0.5), 13, Color(S.color("gold"), 0.8))
	_txt(_short_date(date), Vector2(rect.position.x + 88, rect.position.y + 60), 34, S.color("text"), 0, 5)
	var x := rect.position.x + 250
	_txt(_time(float(item.get("seconds", 0.0))), Vector2(x, rect.position.y + 52), 38, S.color("gold").lightened(0.25), 0, 6)
	_body("Peak %d" % int(item.get("peak", 0)), Vector2(x, rect.position.y + 84), 22, Color(S.color("text_dim"), 0.95))
	_body("%d %s" % [count, "Versuch" if count == 1 else "Versuche"], Vector2(rect.end.x - 24, rect.position.y + 60), 22, Color(S.color("text_dim"), 0.9), 2)


func _total_row(rect: Rect2, best: Dictionary) -> void:
	var shape := _rounded_points(rect, 22, 5)
	_gradient_fill(shape, rect, Color(S.color("violet"), 0.16), S.tone(Color("08140f")))
	_outline(shape, Color(S.color("violet"), 0.7), 2.0)
	_outline(_rounded_points(rect.grow(-6), 17, 5), Color(S.color("violet"), 0.18), 1.5)
	var cells := [
		["RUNS", str(int(best.get("runs", 0))), S.color("toxic")],
		["BESTZEIT", _time(float(best.get("seconds", 0.0))), S.color("cyan")],
		["MAX. SCHWARM", str(int(best.get("peak", 0))), S.color("ember")],
		["HÖCHSTE FLUT", str(int(best.get("flood_stage", 0))) if int(best.get("flood_stage", 0)) > 0 else "–", S.color("violet")],
	]
	var inner := rect.grow(-24)
	var w := inner.size.x / cells.size()
	for i in cells.size():
		var cx := inner.position.x + w * (i + 0.5)
		var col: Color = cells[i][2]
		var value := _fit(String(cells[i][1]), w - 12, [48, 44, 38])
		_txt(value[0], Vector2(cx, rect.position.y + 78), value[1], col.lightened(0.3), 1, 6)
		var label := _fit(String(cells[i][0]), w - 8, [22], S.body_font())
		_body(label[0], Vector2(cx, rect.position.y + 114), label[1], Color(S.color("text_dim"), 0.95), 1)
		if i > 0:
			draw_line(Vector2(inner.position.x + w * i, rect.position.y + 36), Vector2(inner.position.x + w * i, rect.end.y - 36), Color(S.color("violet"), 0.25), 2.0)


func _best_row(rect: Rect2, id: String) -> void:
	var tint := _readable(_strain_color(id))
	var shape := _rounded_points(rect, 22, 5)
	_gradient_fill(shape, rect, Color(tint, 0.10), S.tone(Color("08140f")))
	_outline(shape, Color(tint, 0.5), 1.5)
	var col_w := 196.0
	_strain_badge(rect.position + Vector2(col_w * 0.5 + 6, 60), id, 32)
	var name := String(menu.meta.STRAINS.get(id, {}).get("name", id)).to_upper()
	var fitted := _fit(name, col_w - 24, [26, 24, 22])
	_txt(fitted[0], Vector2(rect.position.x + col_w * 0.5 + 6, rect.position.y + 126), fitted[1], tint.lightened(0.2), 1, 5)
	var left := rect.position.x + col_w
	var n: int = menu.meta.DIFFICULTIES.size()
	var w := (rect.end.x - 16 - left) / n
	for d in n:
		var cell := Rect2(left + d * w + 4, rect.position.y + 14, w - 8, rect.size.y - 28)
		var col: Color = [S.color("toxic"), S.color("amber"), S.color("danger")][clampi(d, 0, 2)]
		var b: Dictionary = menu.chronicle.best(id, d)
		var pts := _rounded_points(cell, 16, 4)
		draw_colored_polygon(pts, S.tone(Color("050c09", 0.7)))
		_outline(pts, Color(col, 0.45 if not b.is_empty() else 0.15), 1.5)
		var cx := cell.get_center().x
		_body(String(menu.meta.DIFFICULTIES[d].name).to_upper(), Vector2(cx, cell.position.y + 30), 22, Color(col, 0.95), 1)
		if b.is_empty():
			_txt("–", Vector2(cx, cell.position.y + 80), 38, Color(S.color("text_dim"), 0.5), 1, 4)
			continue
		_txt(_time(float(b.get("seconds", 0.0))), Vector2(cx, cell.position.y + 76), 36, S.color("text"), 1, 5)
		_body("Peak %d" % int(b.get("peak", 0)), Vector2(cx, cell.position.y + 106), 22, Color(S.color("text_dim"), 0.95), 1)


func _empty_row(rect: Rect2, data: Dictionary) -> void:
	var shape := _rounded_points(rect, 22, 5)
	draw_colored_polygon(shape, S.tone(Color("050c09", 0.5)))
	_outline(shape, Color(S.color("panel_edge"), 0.9), 1.5)
	var c := rect.get_center()
	_txt(String(data.get("text", "")), Vector2(c.x, c.y - 6), 30, S.color("text_dim"), 1, 5)
	var hint := _fit(String(data.get("hint", "")), rect.size.x - 60, [22], S.body_font())
	_body(hint[0], Vector2(c.x, c.y + 34), hint[1], Color(S.color("text_dim"), 0.8), 1)
