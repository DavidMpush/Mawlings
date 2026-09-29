extends "res://scripts/ui/menu/menu_sheets.gd"
## Menü-Komponente KODEX (Sammlung): Inhalt des Blatts "codex".
##
## Wie menu_chronicle.gd: menu_sheets zeichnet Rahmen, Titel und Schließen-Knopf;
## diese Komponente zeichnet die Kategorie-Segmente (Waffen, Relikte, Kerne, Werte,
## Power-ups, Bosse), die Zählerleiste und – in einem zweiten Exemplar (role
## "codex_list", clip_contents) – die scrollbare Liste. Entdeckte Einträge zeigen
## Symbol, Seltenheit bzw. Art und Text; unentdeckte eine Tinten-Silhouette mit
## „???“ und einem Fundort-Hinweis. Trefferflächen: menu.codex_segment_rect,
## codex_list_rect, codex_row_rect; Eingabe bleibt vollständig in menu.gd.
## Nur Kit-Bausteine (ui_kit_brawl.gd), in jedem Skin.

var _rows_list: Control = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if menu == null:
		menu = get_parent()
	_icons = load(ICONS_PATH) if ResourceLoader.exists(ICONS_PATH) else null
	_frames = load(FRAMES_PATH) if ResourceLoader.exists(FRAMES_PATH) else null
	if role == "sheets":
		role = "codex"
	if role == "codex":
		set_anchors_preset(Control.PRESET_FULL_RECT)
		_rows_list = get_script().new()
		_rows_list.role = "codex_list"
		_rows_list.menu = menu
		_rows_list.clip_contents = true
		_rows_list.visible = false
		add_child(_rows_list)


func _open() -> bool:
	return menu != null and menu.profile != null and menu.codex != null and menu.tab == "codex" and menu.reward.is_empty() and not menu.settings_open


func _process(_delta: float) -> void:
	if role != "codex" or menu == null:
		return
	position = Vector2.ZERO
	size = menu.size
	var open := _open()
	visible = open
	_rows_list.visible = open
	if not open:
		_last_key = null
		return
	var area: Rect2 = menu.codex_list_rect()
	_rows_list.position = area.position
	_rows_list.size = area.size
	var seen: int = menu.profile.codex_seen.size()
	_rows_list._repaint([menu.trophy_scroll, area.size, menu.codex_view, seen, S.skin])
	_repaint([size, menu.codex_view, menu.pressed_rect(), menu.trophy_scroll, seen, S.skin])


func _draw() -> void:
	if menu == null or menu.profile == null or menu.codex == null:
		return
	if role == "codex_list":
		_cx_rows()
		return
	_cx_segments()
	_cx_summary()
	_b_scrollbar(menu.codex_list_rect(), "loot")

# ---------------------------------------------------------------- segments

func _cx_segments() -> void:
	var codex = menu.codex
	for i in codex.CATEGORIES.size():
		var id: String = codex.CATEGORIES[i]
		var rect: Rect2 = menu.codex_segment_rect(i)
		var active: bool = menu.codex_view == id
		var pressed: bool = menu.is_pressed(rect)
		var tone: String = codex.CATEGORY_TONES.get(id, "info")
		var lc: Vector2
		if active:
			Kit.button(self, rect, tone, pressed, S.R_L)
			lc = Kit.button_label_center(rect, pressed)
		else:
			Kit.well(self, rect.grow_individual(0, -4, 0, 0), S.R_L)
			lc = rect.get_center() + Vector2(0, 2 + (3.0 if pressed else 0.0))
		# Icon above, label below (five segments are too narrow for a row).
		var tint := Color.WHITE if active else Color(0.72, 0.72, 0.82)
		_b_icon(String(codex.CATEGORY_ICONS.get(id, "")), lc + Vector2(0, -16), 50, tint)
		_b_text(lc + Vector2(0, 30), String(codex.CATEGORY_NAMES[id]), S.T_LABEL - 2, Color.WHITE if active else S.BRAWL_TEXT_DIM, Kit.CENTER | Kit.MIDDLE, rect.size.x - 14)


## Zählerleiste: entdeckt in dieser Kategorie (Balken) und insgesamt.
func _cx_summary() -> void:
	var codex = menu.codex
	var r: Rect2 = menu.codex_summary_rect()
	var seen: Array = menu.profile.codex_seen
	var here: Vector2i = codex.progress(seen, menu.codex_view)
	var all: Vector2i = codex.progress(seen)
	Kit.well(self, r, S.R_M)
	var cy := r.get_center().y
	var x := r.position.x + 20
	x += _b_label(Vector2(x, cy + 2), "ENTDECKT", S.BRAWL_TEXT_DIM, Kit.LEFT | Kit.MIDDLE) + 14
	x += Kit.number(self, Vector2(x, cy), "%d / %d" % [here.x, here.y], S.T_HEAD - 6, _b_light("loot"), Kit.LEFT | Kit.MIDDLE) + 18
	var total := "GESAMT %d / %d" % [all.x, all.y]
	var tw := _b_width(total, S.T_LABEL)
	_b_label(Vector2(r.end.x - 20, cy + 2), total, S.BRAWL_TEXT_DIM, Kit.RIGHT | Kit.MIDDLE)
	var bar_w := r.end.x - 20 - tw - 20 - x
	if bar_w >= 60.0:
		Kit.bar(self, Rect2(x, cy - 14, bar_w, 28), float(here.x) / maxf(1.0, here.y), "loot")

# ---------------------------------------------------------------- rows

func _cx_rows() -> void:
	var entries: Array = menu.codex_entries()
	var pitch: float = menu.CODEX_ROW_H + menu.CODEX_ROW_GAP
	var scroll: float = menu.trophy_scroll
	for i in entries.size():
		var row := Rect2(0, i * pitch - scroll, size.x - 14, menu.CODEX_ROW_H)
		if row.end.y < -10 or row.position.y > size.y + 10:
			continue
		_cx_row(entries[i], row)


func _cx_row(e: Dictionary, row: Rect2) -> void:
	var seen: bool = bool(e.get("seen", false))
	var tone: String = String(e.get("tone", "neutral"))
	if seen:
		Kit.well(self, row, S.R_M)
		Kit.top_rim(self, row, S.R_M, Color(_b_light(tone), 0.55), 3.0)
	else:
		Kit.well(self, row, S.R_M)
	var plate := 96.0
	var pc := Vector2(row.position.x + 16 + plate * 0.5, row.get_center().y)
	Kit.icon_plate(self, pc, plate, tone if seen else "dark")
	var icon := String(e.get("icon", ""))
	var ic := Kit.plate_center(pc, plate)
	if seen:
		if not _b_icon(icon, ic, plate * 0.78):
			_b_text(ic, String(e.name).left(1), S.T_TITLE, Color.WHITE, Kit.CENTER | Kit.MIDDLE)
	else:
		# Silhouette: the same icon in ink, with a faint rim so the shape reads.
		if _b_icon(icon, ic + Vector2(0, 2), plate * 0.8, Color(S.BRAWL_PANEL_RIM, 0.35)):
			_b_icon(icon, ic, plate * 0.78, Color(S.BRAWL_INK, 0.96))
		else:
			Kit.disc(self, ic, 24, S.BRAWL_INK)
		_b_text(ic + Vector2(0, 2), "?", S.T_HEAD, Color(S.BRAWL_TEXT_DIM, 0.9), Kit.CENTER | Kit.MIDDLE)
	var x := pc.x + plate * 0.5 + 18
	var right := row.end.x - 18
	var ny := row.position.y + 34
	# Rarity / kind chip at the right of the name line (unseen: only a relic's rarity).
	var chip_text := String(e.get("chip", "")) if seen or String(e.key).begins_with("relic:") else ""
	var chip_left := right
	if chip_text != "":
		var cw := _b_width(chip_text, S.T_LABEL) + 28
		var cr := Rect2(right - cw, ny - 20, cw, 40)
		Kit.chip(self, cr, tone if seen else "dark")
		_b_text(cr.get_center(), chip_text, S.T_LABEL, Color.WHITE if seen else S.BRAWL_TEXT_DIM, Kit.CENTER | Kit.MIDDLE)
		chip_left = cr.position.x - 14
	var name := String(e.name).to_upper() if seen else "???"
	_b_text(Vector2(x, ny), name, S.T_HEAD - 4, Color.WHITE if seen else S.BRAWL_TEXT_DIM, Kit.LEFT | Kit.MIDDLE, chip_left - x)
	var text_w := right - x
	if seen:
		var sub := String(e.get("sub", ""))
		var boss_line := _boss_line(e)
		if boss_line != "":
			sub = sub + ("  ·  " if sub != "" else "") + boss_line
		var lines := 1 if sub != "" else 2
		# Stage 33: a core reads "+ bonus" in green and "− price" in red.
		var core := String(e.key).begins_with("core:")
		var y := Kit.paragraph(self, Vector2(x, ny + 44), String(e.text), text_w, S.T_LABEL, CorePlaqueRef.PLUS if core else Color.WHITE, core, Kit.LEFT, lines)
		if sub != "":
			_b_label(Vector2(x, y - 2), sub, CorePlaqueRef.MINUS if core else _b_light(tone), Kit.LEFT | Kit.MIDDLE, text_w)
	else:
		Kit.paragraph(self, Vector2(x, ny + 44), String(e.get("hint", "")), text_w, S.T_LABEL, S.BRAWL_TEXT_DIM, false, Kit.LEFT, 2)


## Bosse: wie oft besiegt (Profil-Rekorde).
func _boss_line(e: Dictionary) -> String:
	var key := String(e.get("record", ""))
	if key == "":
		return ""
	var n := int(menu.profile.records.get(key, 0))
	return "%d× besiegt" % n if n > 0 else ""
