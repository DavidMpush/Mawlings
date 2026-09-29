extends "res://scripts/ui/menu/menu_sheets.gd"
## Menu component SIEGEL (stage 31 B): content of the sheet "seals".
##
## Like menu_codex.gd: menu_sheets draws frame, title and close button; this
## component draws the counter strip (SIEGEL used / limit, one-line hint) and,
## in a second instance (role "seals_list", clip_contents), the scrolling grid
## of stats, weapons and relics grouped under small headers. Discovered entries
## show their codex icon on a card in their tone; a sealed one is dimmed with a
## padlock and a violet rim; undiscovered ones are ink silhouettes "???"; the
## current strain's start weapon carries a START tag. Hit areas:
## menu.seal_summary_rect, seal_list_rect, seal_tile_rects; input stays in
## menu.gd (toggle_seal). Kit building blocks only, in every skin.

var _grid: Control = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if menu == null:
		menu = get_parent()
	_icons = load(ICONS_PATH) if ResourceLoader.exists(ICONS_PATH) else null
	_frames = load(FRAMES_PATH) if ResourceLoader.exists(FRAMES_PATH) else null
	if role == "sheets":
		role = "seals"
	if role == "seals":
		set_anchors_preset(Control.PRESET_FULL_RECT)
		_grid = get_script().new()
		_grid.role = "seals_list"
		_grid.menu = menu
		_grid.clip_contents = true
		_grid.visible = false
		add_child(_grid)


func _open() -> bool:
	return menu != null and menu.profile != null and menu.codex != null and menu.tab == "seals" and menu.reward.is_empty() and not menu.settings_open


func _process(_delta: float) -> void:
	if role != "seals" or menu == null:
		return
	position = Vector2.ZERO
	size = menu.size
	var open := _open()
	visible = open
	_grid.visible = open
	if not open:
		_last_key = null
		return
	var area: Rect2 = menu.seal_list_rect()
	_grid.position = area.position
	_grid.size = area.size
	var p = menu.profile
	var key: Array = [menu.trophy_scroll, area.size, str(p.sealed), p.codex_seen.size(), p.seal_limit(), menu.current_strain(), menu.pressed_rect(), S.skin]
	_grid._repaint(key)
	_repaint([size] + key)


func _draw() -> void:
	if menu == null or menu.profile == null or menu.codex == null:
		return
	if role == "seals_list":
		_sl_grid()
		return
	_sl_summary()
	_b_scrollbar(menu.seal_list_rect(), "special")

# ---------------------------------------------------------------- summary

## Counter strip: padlock plate, "SIEGEL 2 / 2", one pip per available seal,
## and the one-line rule below.
func _sl_summary() -> void:
	var r: Rect2 = menu.seal_summary_rect()
	var p = menu.profile
	var used: int = p.sealed.size()
	var limit: int = p.seal_limit()
	Kit.well(self, r, S.R_M)
	var pc := Vector2(r.position.x + 56, r.get_center().y)
	Kit.icon_plate(self, pc, 80, "special")
	_b_icon("lock", Kit.plate_center(pc, 80), 60)
	var x := pc.x + 56
	var y1 := r.position.y + 38
	x += _b_text(Vector2(x, y1), "SIEGEL", S.T_HEAD - 4, Color.WHITE, Kit.LEFT | Kit.MIDDLE) + 16
	x += Kit.number(self, Vector2(x, y1), "%d / %d" % [used, limit], S.T_HEAD - 4, _b_light("special") if used < limit else _b_light("loot"), Kit.LEFT | Kit.MIDDLE) + 22
	# Pips: one per seal slot of the full ring (filled = used, open = free, dark = buyable).
	var max_seals: int = int(menu.meta.BASE_SEALS) + int(menu.meta.UPGRADES.seal_ring.max)
	var pip := 30.0
	var gap := 8.0
	var px := r.end.x - 20 - max_seals * pip - (max_seals - 1) * gap
	if px > x:
		for k in max_seals:
			var c := Vector2(px + k * (pip + gap) + pip * 0.5, y1)
			if k < used:
				Kit.icon_plate(self, c, pip, "special")
				_b_icon("lock", Kit.plate_center(c, pip), pip * 0.7)
			elif k < limit:
				Kit.disc(self, c, pip * 0.5, S.BRAWL_INK)
				Kit.circle_ring(self, c, pip * 0.5 - 3, 3.0, _b_light("special"))
			else:
				Kit.disc(self, c, pip * 0.5 - 4, Color(S.BRAWL_PANEL_RIM, 0.45))
	var hint := "Versiegeltes kommt im Run nie. Nur Entdecktes ist versiegelbar."
	_b_label(Vector2(pc.x + 56, r.position.y + 82), hint, S.BRAWL_TEXT_DIM, Kit.LEFT | Kit.MIDDLE, r.end.x - 20 - (pc.x + 56))

# ---------------------------------------------------------------- grid

func _sl_grid() -> void:
	var entries: Array = menu.seal_entries()
	var scroll: float = menu.trophy_scroll
	var origin: Vector2 = menu.seal_list_rect().position
	var pressed: Rect2 = menu.pressed_rect()
	for item in menu.seal_layout():
		var r: Rect2 = item.rect
		r.position.y -= scroll
		if r.end.y < -10 or r.position.y > size.y + 10:
			continue
		if item.kind == "header":
			_sl_header(item, r, entries)
		else:
			var down := pressed.size != Vector2.ZERO and pressed.has_point(origin + r.get_center())
			_sl_tile(entries[int(item.index)], r, down)


func _sl_header(item: Dictionary, r: Rect2, entries: Array) -> void:
	var seen := 0
	var sealed := 0
	var total := 0
	for e in entries:
		if e.group != item.group:
			continue
		total += 1
		seen += 1 if bool(e.seen) else 0
		sealed += 1 if bool(e.sealed) else 0
	var cy := r.position.y + r.size.y * 0.5 + 2
	var w := _b_text(Vector2(r.position.x + 6, cy), String(item.text), S.T_HEAD - 8, Color.WHITE, Kit.LEFT | Kit.MIDDLE)
	var info := "%d / %d ENTDECKT" % [seen, total]
	if sealed > 0:
		info = "%d VERSIEGELT  ·  " % sealed + info
	var iw := _b_label(Vector2(r.end.x - 4, cy), info, S.BRAWL_TEXT_DIM, Kit.RIGHT | Kit.MIDDLE)
	var lx := r.position.x + 6 + w + 16
	var rx := r.end.x - 4 - iw - 16
	if rx - lx > 20:
		Kit.rrect(self, Rect2(lx, cy - 2, rx - lx, 4), 2.0, Color(S.BRAWL_PANEL_RIM, 0.6))


func _sl_tile(e: Dictionary, r: Rect2, down: bool) -> void:
	var seen: bool = bool(e.seen)
	var sealed: bool = bool(e.sealed)
	var start: bool = bool(e.start)
	var tone: String = String(e.get("tone", "neutral"))
	if down and seen and not start:
		r.position.y += 3
	if seen and not sealed:
		Kit.card(self, r, tone, "normal", 0.0, S.R_M)
	else:
		Kit.well(self, r, S.R_M)
	var plate := 96.0
	var pc := Vector2(r.get_center().x, r.position.y + 70)
	var ic := Kit.plate_center(pc, plate)
	var icon := String(e.get("icon", ""))
	var name_y := r.position.y + 148
	var name_w := r.size.x - 20
	if not seen:
		Kit.icon_plate(self, pc, plate, "dark")
		if _b_icon(icon, ic + Vector2(0, 2), plate * 0.8, Color(S.BRAWL_PANEL_RIM, 0.35)):
			_b_icon(icon, ic, plate * 0.78, Color(S.BRAWL_INK, 0.96))
		else:
			Kit.disc(self, ic, 24, S.BRAWL_INK)
		_b_text(ic + Vector2(0, 2), "?", S.T_HEAD, Color(S.BRAWL_TEXT_DIM, 0.9), Kit.CENTER | Kit.MIDDLE)
		_b_text(Vector2(r.get_center().x, name_y), "???", S.T_LABEL, S.BRAWL_TEXT_DIM, Kit.CENTER | Kit.MIDDLE, name_w)
		if sealed:
			_sl_padlock(r, pc)
		return
	Kit.icon_plate(self, pc, plate, tone if not sealed else "neutral")
	var tint := Color.WHITE if not sealed else Color(0.55, 0.55, 0.66)
	if not _b_icon(icon, ic, plate * 0.78, tint):
		_b_text(ic, String(e.name).left(1), S.T_TITLE, tint, Kit.CENTER | Kit.MIDDLE)
	var name := String(e.name).to_upper()
	if sealed:
		# Dimmed card: veil over plate and icon, violet rim, padlock on top.
		Kit.rrect(self, r.grow(-2), S.R_M - 2, Color(S.BRAWL_INK, 0.45))
		Kit.ring(self, r, S.R_M, 4.0, _b_light("special"))
		_sl_padlock(r, pc)
		_b_text(Vector2(r.get_center().x, name_y), name, S.T_LABEL, _b_light("special"), Kit.CENTER | Kit.MIDDLE, name_w)
		return
	_b_text(Vector2(r.get_center().x, name_y), name, S.T_LABEL, Color.WHITE, Kit.CENTER | Kit.MIDDLE, name_w)
	if start:
		# Start weapon: small tag in the top-left corner, cannot be sealed.
		var tw := _b_width("START", S.T_LABEL - 4) + 20
		var tag := Rect2(r.position.x + 8, r.position.y + 8, tw, 32)
		Kit.chip(self, tag, "loot")
		_b_text(tag.get_center(), "START", S.T_LABEL - 4, Color.WHITE, Kit.CENTER | Kit.MIDDLE)


## Padlock over the icon plate of a sealed tile.
func _sl_padlock(r: Rect2, pc: Vector2) -> void:
	var lc := pc + Vector2(34, 30)
	Kit.icon_plate(self, lc, 62, "special")
	if not _b_icon("lock", Kit.plate_center(lc, 62), 46):
		Kit.disc(self, Kit.plate_center(lc, 62), 14, Color.WHITE)
