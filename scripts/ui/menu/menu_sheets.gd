extends "res://scripts/menu/ui_kit.gd"
## Menü-Komponente (Etappe 04, Agent MENU_SHEETS): Brutkammer, Trophäen,
## Urinstinkt, Belohnungs-Overlay nach dem Run und Toast.
##
## Kind des Menü-Controls (`scripts/menu/menu.gd`), voller Anker, ignoriert die
## Maus. Liest alle Daten aus dem Menü (profile, meta, tab, reward, reward_stats,
## trophy_scroll, toast, toast_time) und zeichnet an dessen `*_rect()`-Flächen,
## damit Trefferflächen stimmen. Eingabe bleibt vollständig in menu.gd.
## Einschalten: `menu.legacy.sheet = false`, `menu.legacy.reward = false`.
##
## Die Trophäenliste zeichnet ein zweites Exemplar dieses Skripts (role
## "trophy_list") mit clip_contents, damit Zeilen beim Scrollen sauber
## abgeschnitten werden. Die Sortierung (offene zuerst, erledigte hinten) ist
## reine Darstellung; Scrollhöhe und Zeilenhöhe bleiben die von menu.gd.

const S := preload("res://scripts/ui/ui_style.gd")
const UiStyleRef := preload("res://scripts/ui/ui_style.gd")
const UiFramesRef := preload("res://scripts/ui/ui_frames.gd")
const ICONS_PATH := "res://scripts/ui/ui_icons.gd"
const FRAMES_PATH := "res://scripts/ui/ui_frames.gd"

const TAB_TITLE := {"upgrades": "BRUTKAMMER", "trophies": "TROPHÄEN", "instinct": "URINSTINKT", "chronicle": "CHRONIK", "codex": "KODEX"}
const TAB_ACCENT := {"upgrades": S.GOLD, "trophies": S.VIOLET, "instinct": S.CYAN, "chronicle": S.VIOLET, "codex": S.GOLD}
## Kategorie-Farbe je Brutkammer-Upgrade (Angriff Ember, Wachstum Cyan, Spezial Violett, Schutz Toxic).
const UPGRADE_ACCENT := {"brood_size": S.CYAN, "rending": S.EMBER, "chitin": S.TOXIC, "sprinter": S.CYAN,
	"digestion": S.AMBER, "geneflow": S.CYAN, "attack_slot": S.EMBER, "trait_slot": S.VIOLET}
## Icon-Wunschliste je Upgrade für UiIcons (erste vorhandene ID gewinnt), sonst eigene Zeichnung.
const UPGRADE_ICONS := {"brood_size": ["brood", "trait_brood"], "rending": ["jaws", "trait_jaws"],
	"chitin": ["armor", "trait_armor"], "sprinter": ["scatter", "trait_scatter"],
	"digestion": ["glutton", "trait_glutton"], "geneflow": ["dna", "dna_helix"],
	"attack_slot": ["rudelbiss", "attack_rudelbiss"], "trait_slot": ["pack", "trait_pack"]}

var role := "sheets"
var menu = null

var _list: Control = null
var _icons: Variant = null
var _frames: Variant = null
var _reward_open := false
var _reward_t0 := 0.0
var _last_tab := ""
var _tab_t0 := 0.0
var _last_key: Variant = null
var _toast_node: Control = null
var _toast_shown := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if menu == null:
		menu = get_parent()
	_icons = load(ICONS_PATH) if ResourceLoader.exists(ICONS_PATH) else null
	_frames = load(FRAMES_PATH) if ResourceLoader.exists(FRAMES_PATH) else null
	if role == "sheets":
		set_anchors_preset(Control.PRESET_FULL_RECT)
		_list = get_script().new()
		_list.role = "trophy_list"
		_list.menu = menu
		_list.clip_contents = true
		_list.visible = false
		add_child(_list)
		# Toast on its own child above every sheet list (also the chronicle's).
		_toast_node = get_script().new()
		_toast_node.role = "toast"
		_toast_node.menu = menu
		_toast_node.z_index = 5
		_toast_node.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_toast_node)


func _now() -> float:
	return Time.get_ticks_msec() * 0.001


func _process(_delta: float) -> void:
	if role != "sheets" or menu == null:
		return
	position = Vector2.ZERO
	size = menu.size
	var open: bool = menu.profile != null and not menu.reward.is_empty()
	if open and not _reward_open:
		_reward_t0 = _now()
	_reward_open = open
	if menu.tab != _last_tab:
		_last_tab = menu.tab
		_tab_t0 = _now()
	# The list child sits above this node's drawing, so it hides under the
	# settings modal. Brawl also scrolls the Brutkammer inside it.
	var list_tabs := ["trophies", "upgrades"] if S.is_brawl() else ["trophies"]
	var show_list: bool = menu.profile != null and menu.tab in list_tabs and not open and not menu.legacy.get("sheet", true) and not bool(menu.get("settings_open"))
	_list.visible = show_list
	if show_list:
		var area := _list_area()
		_list.position = area.position
		_list.size = area.size
		var p = menu.profile
		var list_key: Array = [menu.tab, menu.trophy_scroll, area.size, p.completed_quests.size(), str(p.records), S.colorblind, S.skin]
		if menu.tab == "upgrades":
			list_key.append_array([p.essence, str(p.upgrades), menu.pressed_rect()])
		_list._repaint(list_key)
	_repaint(_state_key(open))
	var toast_on: bool = menu.toast_time > 0.0 and menu.toast != "" and not menu.legacy.get("reward", true)
	_toast_node.size = size
	if toast_on or _toast_shown:
		_toast_node.queue_redraw()
	_toast_shown = toast_on


# Stage 07 (performance): repaint only on change. Nothing open = nothing drawn
# and no repaint at all; the reward intro and the toast animate per frame,
# pulsing buttons and the instinct ring at 30 Hz, settings only on change.
func _repaint(key: Variant) -> void:
	if key == null or typeof(key) != typeof(_last_key) or key != _last_key:
		queue_redraw()
	_last_key = key


func _state_key(reward_open: bool) -> Variant:
	var sheet: bool = menu.profile != null and menu.tab != ""
	var settings: bool = menu.profile != null and bool(menu.get("settings_open"))
	if not reward_open and not sheet and not settings:
		return ["idle", size]
	if reward_open and _now() - _reward_t0 < 5.0:
		return null
	var p = menu.profile
	var key: Array = [size, menu.tab, reward_open, settings, menu.pressed_rect(), menu.trophy_scroll, S.colorblind,
		p.essence, p.crowns, str(p.upgrades), p.instinct_level, p.completed_quests.size(), str(p.settings), S.skin]
	# Brawl sheets are static; only the organic glows and the reward shine move.
	if S.is_brawl():
		return key
	# Buy-button glows, the instinct ring and the reward shine keep moving.
	if reward_open or menu.tab in ["upgrades", "instinct"]:
		key.append(int(_now() * 30.0))
	return key


func _list_area() -> Rect2:
	if S.is_brawl():
		return menu.upgrade_list_rect() if menu.tab == "upgrades" else menu.trophy_list_rect()
	var s: Rect2 = menu.sheet_rect()
	var top: float = menu._sheet_body_top()
	return Rect2(s.position.x + 8, top - 4, s.size.x - 30, s.end.y - 20 - top + 8)


func _draw() -> void:
	if menu == null or menu.profile == null:
		return
	if role == "toast":
		if menu.toast_time > 0.0 and menu.toast != "" and not menu.legacy.get("reward", true):
			if S.is_brawl():
				_b_toast()
			else:
				_draw_toast()
		return
	if role == "trophy_list":
		if S.is_brawl():
			_b_draw_list()
		else:
			_draw_trophy_rows()
		return
	if S.is_brawl():
		_b_draw()
		return
	if menu.tab != "" and not menu.legacy.get("sheet", true):
		_draw_sheet()
	if menu.get("settings_open") and not menu.legacy.get("settings", true) and menu.reward.is_empty():
		_draw_settings()
	if not menu.legacy.get("reward", true):
		if not menu.reward.is_empty():
			_draw_reward()
		pass

# ================================================================ text + shapes

func _w(value: String, px: int, font: Font = null) -> float:
	var face: Font = font if font != null else S.display_font()
	return face.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x


## align: 0 left, 1 centre, 2 right. Returns the drawn width.
func _txt(value: String, at: Vector2, px: int, color: Color = S.TEXT, align: int = 0, outline: int = 6, font: Font = null) -> float:
	var face: Font = font if font != null else S.display_font()
	var width := face.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var origin := at
	if align == 1:
		origin.x -= width * 0.5
	elif align == 2:
		origin.x -= width
	if outline > 0:
		draw_string_outline(face, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, px, outline, Color(S.color("outline"), 0.9 * color.a))
	draw_string(face, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, px, S.tone(color))
	return width


func _body(value: String, at: Vector2, px: int, color: Color = S.TEXT_DIM, align: int = 0) -> float:
	return _txt(value, at, px, color, align, 4, S.body_font())


## Largest size from `sizes` whose text fits `max_w`; clips with … otherwise.
func _fit(value: String, max_w: float, sizes: Array, font: Font = null) -> Array:
	for px in sizes:
		if _w(value, px, font) <= max_w:
			return [value, px]
	var px: int = sizes[-1]
	var cut := value
	while cut.length() > 3 and _w(cut + "…", px, font) > max_w:
		cut = cut.substr(0, cut.length() - 1)
	return [cut.strip_edges() + "…", px]


## Organic chamfered outline: large cut top-left / bottom-right, small cut on the others.
func _shape(rect: Rect2, cut: float) -> PackedVector2Array:
	var c := minf(cut, minf(rect.size.x, rect.size.y) * 0.4)
	var k := c * 0.45
	var x0 := rect.position.x
	var y0 := rect.position.y
	var x1 := rect.end.x
	var y1 := rect.end.y
	return PackedVector2Array([
		Vector2(x0 + c, y0), Vector2(x1 - k, y0), Vector2(x1, y0 + k), Vector2(x1, y1 - c),
		Vector2(x1 - c, y1), Vector2(x0 + k, y1), Vector2(x0, y1 - k), Vector2(x0, y0 + c)])


func _gradient_fill(points: PackedVector2Array, rect: Rect2, top: Color, bottom: Color) -> void:
	var colors := PackedColorArray()
	for p in points:
		colors.append(top.lerp(bottom, clampf((p.y - rect.position.y) / maxf(1.0, rect.size.y), 0.0, 1.0)))
	draw_polygon(points, colors)


func _outline(points: PackedVector2Array, color: Color, width: float, color_b: Color = Color(0, 0, 0, 0)) -> void:
	var closed := points.duplicate()
	closed.append(points[0])
	if color_b.a <= 0.0:
		draw_polyline(closed, color, width, true)
		return
	var colors := PackedColorArray()
	var x0 := INF
	var x1 := -INF
	for p in closed:
		x0 = minf(x0, p.x)
		x1 = maxf(x1, p.x)
	for p in closed:
		colors.append(color.lerp(color_b, (p.x - x0) / maxf(1.0, x1 - x0)))
	draw_polyline_colors(closed, colors, width, true)


## Card from the organic frame kit: shadow, soft glow in the category colour,
## dark green gradient body with cell pores, two-tone rim and bone claws.
## state: "normal", "active" (stronger glow), "dim" (locked / muted), "gold".
func _card(rect: Rect2, accent: Color, state: String = "normal", cut: float = 22.0, claws: bool = true) -> void:
	if _frames != null:
		var mapped: String = {"dim": "disabled", "active": "selected", "gold": "selected"}.get(state, "normal")
		_frames.card(self, rect, accent, mapped)
		return
	var glow := {"normal": 0.55, "active": 1.0, "dim": 0.0, "gold": 0.8}.get(state, 0.5) as float
	var edge := accent if state != "dim" else S.tone(Color("4a574f"))
	draw_colored_polygon(_shape(Rect2(rect.position + Vector2(0, 6), rect.size), cut), Color(S.color("shadow"), 0.55))
	if glow > 0.0:
		for i in 3:
			_outline(_shape(rect.grow(3 + i * 4), cut + 2 + i * 2), Color(edge, glow * (0.16 - i * 0.045)), 5.0)
	var shape := _shape(rect, cut)
	var top := S.tone(Color("15302a")).lerp(accent, 0.07 if state != "dim" else 0.0)
	_gradient_fill(shape, rect, top, S.tone(Color("07130f")))
	# Soft inner light along the top edge.
	var sheen := Rect2(rect.position + Vector2(cut, 3), Vector2(rect.size.x - cut * 1.6, 3))
	draw_rect(sheen, Color(edge, 0.10))
	# Cell pores in the upper right, like the concept frames.
	var pore := Vector2(rect.end.x - 44, rect.position.y + 22)
	for o in [Vector2(0, 0), Vector2(15, 4), Vector2(6, 15), Vector2(21, 17)]:
		var pc: Vector2 = pore + o
		draw_circle(pc, 5.0, S.tone(Color("030806")))
		draw_arc(pc, 5.0, 0, TAU, 12, Color(edge, 0.25), 1.2, true)
	var inner := _shape(rect.grow(-6), cut - 4)
	_outline(inner, Color(edge, 0.16), 1.5)
	_outline(shape, edge.lightened(0.1), 3.0, edge.lerp(S.color("violet") if accent != S.color("violet") else S.color("cyan"), 0.35) if state != "dim" else Color(0, 0, 0, 0))
	if claws and state != "dim":
		_claw(Vector2(rect.end.x - 10, rect.position.y + 10), Vector2(0.55, -1), 20, 6, S.color("bone"), 0.45)
		_claw(Vector2(rect.position.x + 10, rect.end.y - 10), Vector2(-0.55, 1), 20, 6, S.color("bone"), 0.45)


## Round medallion behind icons: glow, dark well, bright rim.
func _medallion(c: Vector2, r: float, accent: Color, glow: float = 1.0) -> void:
	if S.is_calm():
		# V2: octagonal petrol plate with one accent stroke, no glow.
		var plate := UiFramesRef.chamfer_points(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), r * 0.42)
		draw_colored_polygon(plate, Color(S.CALM_BG, 0.97))
		_outline(plate, S.tone(accent), 3.0)
		return
	for i in 4:
		draw_circle(c, r + 4 + i * 5, Color(accent, 0.05 * glow))
	draw_circle(c, r, S.tone(Color("040b08")))
	draw_circle(c + Vector2(0, -r * 0.18), r * 0.8, Color(accent, 0.10 * maxf(glow, 0.3)))
	draw_arc(c, r, 0, TAU, 48, accent, 3.0, true)
	draw_arc(c, r - 6, 0, TAU, 48, Color(accent, 0.25), 1.5, true)


## kind: "ember" (primary), "gold", "cyan", "off", "max". `pressed` sinks the
## button (labels use _press_offset with the same flag).
func _button(rect: Rect2, kind: String, glow: float = 0.0, pressed: bool = false) -> void:
	if pressed:
		glow *= 0.4
	if _frames != null:
		if kind == "ember":
			if glow > 0.0 and not S.is_calm():
				for i in 3:
					draw_colored_polygon(_shape(rect.grow(6 + i * 6), 20 + i * 3), Color(S.color("ember_glow"), glow * (0.10 - i * 0.03)))
			_frames.button(self, rect, "primary", pressed)
		else:
			_frames.button(self, rect, "secondary", pressed)
			if kind == "max" or kind == "gold" or kind == "cyan":
				var tint: Color = {"max": S.color("toxic"), "gold": S.color("gold"), "cyan": S.color("cyan")}[kind]
				var inner := rect.grow(-7)
				_gradient_fill(_rounded_points(inner, 14, 5), inner, Color(tint, 0.26), Color(tint, 0.06))
		return
	if pressed:
		rect = Rect2(rect.position + Vector2(0, 3), rect.size).grow(-2)
	var base: Color = {"ember": S.tone(Color("c4521f")), "gold": S.tone(Color("a8791f")), "cyan": S.tone(Color("1d8a80")), "off": S.tone(Color("1c2621")), "max": S.tone(Color("2c5a2c"))}.get(kind, S.tone(Color("1c2621")))
	var edge: Color = {"ember": S.color("ember_glow"), "gold": S.color("gold"), "cyan": S.color("cyan"), "off": S.tone(Color("46524a")), "max": S.color("toxic")}.get(kind, S.tone(Color("46524a")))
	if glow > 0.0:
		for i in 4:
			draw_colored_polygon(_shape(rect.grow(4 + i * 5), 18 + i * 3), Color(edge, glow * (0.12 - i * 0.025)))
	var shape := _shape(rect, 16)
	draw_colored_polygon(_shape(Rect2(rect.position + Vector2(0, 5), rect.size), 16), Color(0, 0, 0, 0.45))
	_gradient_fill(shape, rect, base.lightened(0.18), base.darkened(0.45))
	if kind != "off":
		var gloss := Rect2(rect.position + Vector2(8, 5), Vector2(rect.size.x - 16, rect.size.y * 0.38))
		_gradient_fill(_shape(gloss, 10), gloss, Color(1, 1, 1, 0.20), Color(1, 1, 1, 0.02))
	_outline(shape, edge, 3.0)
	_outline(_shape(rect.grow(-5), 12), Color(edge, 0.2), 1.5)


## Label shift that goes with a pressed button.
func _press_offset(pressed: bool) -> Vector2:
	return Vector2(0, 3) if pressed else Vector2.ZERO


func _bar_fill(rect: Rect2, fraction: float, color: Color) -> void:
	if _frames != null:
		_frames.bar(self, rect, fraction, color)
		return
	draw_colored_polygon(_rounded_points(rect, rect.size.y * 0.5 - 0.5, 4), S.tone(Color("050c09")))
	_outline(_rounded_points(rect, rect.size.y * 0.5 - 0.5, 4), Color(color, 0.35), 1.5)
	if fraction > 0.0:
		var fill := Rect2(rect.position + Vector2(2, 2), Vector2(maxf(rect.size.y - 4, (rect.size.x - 4) * minf(fraction, 1.0)), rect.size.y - 4))
		var pts := _rounded_points(fill, fill.size.y * 0.5 - 0.5, 4)
		_gradient_fill(pts, fill, color.lightened(0.3), color.darkened(0.2))
		draw_circle(Vector2(fill.end.x - fill.size.y * 0.5, fill.get_center().y), fill.size.y * 0.9, Color(color, 0.25))


func _rank_diamond(c: Vector2, r: float, color: Color, filled: bool) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.8, 0), c + Vector2(0, r), c + Vector2(-r * 0.8, 0)])
	if filled:
		if S.is_calm():
			draw_colored_polygon(pts, S.tone(color))
			return
		draw_circle(c, r * 1.3, Color(color, 0.18))
		draw_colored_polygon(pts, color)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.6), c + Vector2(r * 0.35, 0), c + Vector2(0, -r * 0.1)]), Color(1, 1, 1, 0.45))
	else:
		draw_colored_polygon(pts, S.tone(Color("050c09")))
		_outline(pts, Color(color, 0.4), 1.5)


## Essence colour follows the painted icon (violet drop) when the icon set exists.
func _ess() -> Color:
	return S.color("violet") if _icons != null and _icons.has("essence") else S.color("cyan")


func _essence_icon(c: Vector2, r: float, enabled: bool = true) -> void:
	if _icon(["essence"], Rect2(c - Vector2(r, r) * 1.3, Vector2(r, r) * 2.6), Color.WHITE if enabled else Color(0.6, 0.65, 0.63)):
		return
	_essence_drop(c, r, S.color("cyan") if enabled else S.tone(Color("6d807b")))


func _crown_icon(c: Vector2, r: float) -> void:
	if _icon(["king_tooth", "crown_tooth", "tooth", "koenigszahn"], Rect2(c - Vector2(r, r) * 1.3, Vector2(r, r) * 2.6), Color.WHITE):
		return
	_fang(c, r, S.tone(Color("ffe7a8")))


## Draws the first UiIcons id that exists; false when none (caller falls back).
func _icon(ids: Array, rect: Rect2, tint: Color = Color.WHITE) -> bool:
	if _icons == null:
		return false
	for id in ids:
		if _icons.has(id):
			_icons.draw(self, id, rect, tint)
			return true
	return false


func _sweep(poly: PackedVector2Array, bounds: Rect2, phase: float, alpha: float) -> void:
	if phase <= 0.0 or phase >= 1.0:
		return
	var x := lerpf(bounds.position.x - 160, bounds.end.x + 60, phase)
	var band := PackedVector2Array([Vector2(x, bounds.end.y + 4), Vector2(x + 70, bounds.end.y + 4), Vector2(x + 170, bounds.position.y - 4), Vector2(x + 100, bounds.position.y - 4)])
	for part in Geometry2D.intersect_polygons(band, poly):
		draw_colored_polygon(part, Color(1, 1, 1, alpha * sin(phase * PI)))

# ================================================================ sheet frame

func _draw_sheet() -> void:
	var tab: String = menu.tab
	var s: Rect2 = menu.sheet_rect()
	var accent: Color = S.tone(TAB_ACCENT.get(tab, S.GOLD))
	# Dim the menu behind and lay the big organic panel.
	draw_rect(Rect2(Vector2.ZERO, size), Color(S.color("dim"), 0.35))
	if _frames != null:
		_frames.panel(self, s, accent, true)
	else:
		_card(s, accent, "normal", 36, true)
	var top := s.position.y
	# Stage 15 layout: the list starts 114 px below the sheet top, so the
	# title strip is tighter than before (no subtitle line any more).
	_txt(TAB_TITLE.get(tab, ""), Vector2(s.position.x + 40, top + 72), 48, S.color("text"), 0, 8)
	# Close button (hit area from menu.gd).
	var close: Rect2 = menu.sheet_close_rect()
	var close_down: bool = menu.is_pressed(close)
	_button(close.grow(-6), "off", 0.0, close_down)
	var cc := close.get_center() + _press_offset(close_down)
	for d in [Vector2(1, 1), Vector2(1, -1)]:
		draw_line(cc - d * 17, cc + d * 17, S.color("outline"), 11, true)
		draw_line(cc - d * 17, cc + d * 17, S.color("bone"), 6, true)
	# Divider with a centre diamond.
	var y := top + 102
	draw_line(Vector2(s.position.x + 30, y), Vector2(s.end.x - 30, y), Color(accent, 0.35), 2, true)
	_rank_diamond(Vector2(s.get_center().x, y), 8, accent, true)
	if tab == "upgrades":
		_essence_pill(Vector2(close.position.x - 16, top + 66))
		_draw_upgrades()
	elif tab == "trophies":
		_draw_trophy_header(s, accent)
		_draw_trophy_scrollbar(s, accent)
		_b_codex_button()
	elif tab == "instinct":
		_essence_pill(Vector2(close.position.x - 16, top + 66))
		_draw_instinct()


## Essence balance pill, right-aligned at `right_mid` (right edge, vertical centre).
func _essence_pill(right_mid: Vector2) -> void:
	var value := "%d" % int(menu.profile.essence)
	var w := _w(value, 30) + 76
	var rect := Rect2(right_mid.x - w, right_mid.y - 28, w, 56)
	draw_colored_polygon(_rounded_points(rect, 26, 5), S.tone(Color("050c09e0")))
	_outline(_rounded_points(rect, 26, 5), Color(_ess(), 0.6), 2.0)
	_essence_icon(rect.position + Vector2(32, 30), 14)
	_txt(value, rect.position + Vector2(56, 39), 30, S.color("text"), 0, 5)

# ================================================================ Brutkammer

func _upgrade_effect(id: String, rank: int) -> String:
	match id:
		"brood_size":
			return "+%d Start-Mawlings" % (2 * rank)
		"rending":
			return "+%d %% Schaden" % (5 * rank)
		"chitin":
			return "+%d %% Panzer" % mini(30, 3 * rank)
		"sprinter":
			return "+%d %% Tempo" % (3 * rank)
		"digestion":
			return "+%d %% Biomasse" % (6 * rank)
		"geneflow":
			return "+%d %% DNA" % (6 * rank)
		"witterung":
			return "+%d %% Sammelradius" % (8 * rank)
		"attack_slot":
			return "%d Waffenplätze" % (int(menu.meta.BASE_SLOTS.attack) + rank)
		"trait_slot":
			# Etappe 17: ehemals Anlagenslot, jetzt +1 Neu würfeln je Rang.
			return "+%d Neu würfeln" % rank
	return "Rang %d" % rank


## Only the number part of the next rank, e.g. "+12 %" or "4".
func _upgrade_next_short(id: String, rank: int) -> String:
	var full := _upgrade_effect(id, rank)
	var parts := full.split(" ")
	if parts.size() >= 2 and parts[1] == "%":
		return parts[0] + " %"
	return parts[0]


func _draw_upgrades() -> void:
	var meta = menu.meta
	var profile = menu.profile
	var now := _now()
	for i in meta.UPGRADE_ORDER.size():
		var id: String = meta.UPGRADE_ORDER[i]
		var u: Dictionary = meta.UPGRADES[id]
		var row: Rect2 = menu.upgrade_row_rect(i)
		var buy: Rect2 = menu.upgrade_buy_rect(i)
		var rank := int(profile.upgrade_rank(id))
		var max_rank := int(u.max)
		var available: bool = profile.upgrade_available(id)
		var maxed := rank >= max_rank
		var cost := int(profile.upgrade_cost(id))
		var affordable: bool = available and not maxed and profile.essence >= cost
		var accent: Color = S.tone(UPGRADE_ACCENT.get(id, S.GOLD))
		var state := "dim" if not available else "normal"
		_card(row, accent if available else S.tone(Color("5b675f")), state, 22, false)
		# Icon medallion.
		var ic := row.position + Vector2(62, row.size.y * 0.5)
		_medallion(ic, 44, accent if available else S.tone(Color("56625a")), 1.0 if available else 0.0)
		var icon_rect := Rect2(ic - Vector2(32, 32), Vector2(64, 64))
		if not _icon(UPGRADE_ICONS.get(id, []), icon_rect, Color.WHITE if available else Color(0.55, 0.6, 0.57)):
			_upgrade_glyph(id, ic, 27, accent.lightened(0.15) if available else S.tone(Color("6f7d74")))
		if not available:
			draw_circle(ic + Vector2(28, 28), 17, S.tone(Color("050c09")))
			_lock(ic + Vector2(28, 27), 13, S.color("bone"))
		# Name with rank diamonds, divider, effect now -> next rank.
		var x := row.position.x + 124
		var right := buy.position.x - 18
		var name_color: Color = accent.lightened(0.3) if available else S.tone(Color("9aa69c"))
		var nw := _txt(String(u.name).to_upper(), Vector2(x, row.position.y + 50), 31, name_color, 0, 6)
		draw_line(Vector2(x, row.position.y + 62), Vector2(right, row.position.y + 62), Color(accent if available else S.tone(Color("56625a")), 0.3), 2, true)
		if available:
			var gap := 17.0 if max_rank > 4 else 24.0
			var dx := x + nw + 22
			for k in max_rank:
				_rank_diamond(Vector2(dx + k * gap, row.position.y + 39), 7.0, accent, k < rank)
			_body("%d/%d" % [rank, max_rank], Vector2(dx + max_rank * gap + 2, row.position.y + 47), 22, Color(S.color("text_dim"), 0.9))
		if not available:
			var q: Dictionary = meta.quest(String(u.get("requires", "")))
			var line := _fit("Trophäe: %s – %s" % [String(q.get("name", "")), String(q.get("description", ""))], right - x - 30, [22], S.body_font())
			_lock(Vector2(x + 11, row.position.y + 88), 11, S.color("gold"))
			_body(line[0], Vector2(x + 30, row.position.y + 96), line[1], S.color("gold"))
		else:
			var wx := _body(_upgrade_effect(id, rank), Vector2(x, row.position.y + 96), 24, S.color("text"))
			if maxed:
				_body("  ·  maximal", Vector2(x + wx, row.position.y + 96), 22, Color(S.color("toxic"), 0.9))
			else:
				var ax := x + wx + 12
				_arrow(Vector2(ax + 8, row.position.y + 88), 12, 1.0, accent)
				_txt(_upgrade_next_short(id, rank + 1), Vector2(ax + 24, row.position.y + 97), 26, accent.lightened(0.35), 0, 5)
		# Buy button.
		if maxed:
			_button(buy, "max")
			_crown(buy.get_center() + Vector2(0, -24), 16, S.color("gold"))
			_txt("MAX", buy.get_center() + Vector2(0, 30), 40, S.tone(Color("e4ffc8")), 1, 6)
		elif not available:
			_button(buy, "off")
			_lock(buy.get_center() + Vector2(0, -14), 17, S.tone(Color("7d8a80")))
			_txt("GESPERRT", buy.get_center() + Vector2(0, 34), 22, S.tone(Color("8d998f")), 1, 4)
		else:
			var pulse := 0.6 + 0.4 * sin(now * 3.0 + i * 0.7)
			var down: bool = menu.is_pressed(buy)
			var po := _press_offset(down)
			_button(buy, "ember" if affordable else "off", pulse if affordable else 0.0, down)
			var label_color := S.color("text") if affordable else S.tone(Color("9aa39c"))
			_txt("KAUFEN", Vector2(buy.get_center().x, buy.position.y + 38) + po, 24, label_color, 1, 5)
			var cost_text := "%d" % cost
			var cw := _w(cost_text, 34)
			var cx := buy.get_center().x - (cw + 34) * 0.5
			_essence_icon(Vector2(cx + 11, buy.position.y + 70) + po, 12, affordable)
			_txt(cost_text, Vector2(cx + 32, buy.position.y + 83) + po, 34, Color.WHITE if affordable else S.tone(Color("8d998f")), 0, 6)


func _upgrade_glyph(id: String, c: Vector2, r: float, color: Color) -> void:
	match id:
		"brood_size":
			for o in [Vector2(-0.48, 0.28), Vector2(0.48, 0.28), Vector2(0, -0.32)]:
				_ellipse(c + o * r, 0.4 * r, 0.52 * r, color)
				draw_circle(c + o * r + Vector2(-0.12, -0.16) * r, 0.1 * r, Color(1, 1, 1, 0.5))
		"rending":
			for k in 3:
				_claw(c + Vector2(-0.7 + k * 0.55, 0.75) * r, Vector2(0.35, -1), 1.5 * r, 0.22 * r, color, 0.3)
		"chitin":
			var shield := PackedVector2Array([c + Vector2(0, -0.95) * r, c + Vector2(0.8, -0.55) * r, c + Vector2(0.65, 0.45) * r, c + Vector2(0, 1.0) * r, c + Vector2(-0.65, 0.45) * r, c + Vector2(-0.8, -0.55) * r])
			draw_colored_polygon(shield, color)
			draw_line(c + Vector2(-0.55, -0.05) * r, c + Vector2(0.55, -0.05) * r, S.color("outline"), 3)
			draw_line(c + Vector2(0, -0.8) * r, c + Vector2(0, 0.85) * r, S.color("outline"), 3)
		"sprinter":
			for k in 3:
				var y := (-0.5 + k * 0.5) * r
				draw_line(c + Vector2(-1.0 + k * 0.2, y), c + Vector2(0.1, y), color, 5, true)
			_arrow(c + Vector2(0.4, 0) * r, 0.9 * r, 1.0, color)
		"digestion":
			_essence_drop(c + Vector2(0, 0.15 * r), 0.7 * r, color)
		"geneflow":
			var a := PackedVector2Array()
			var b := PackedVector2Array()
			for k in 13:
				var t := float(k) / 12.0
				var y := c.y - r + 2.0 * r * t
				a.append(Vector2(c.x + sin(t * TAU * 1.2) * 0.5 * r, y))
				b.append(Vector2(c.x + sin(t * TAU * 1.2 + PI) * 0.5 * r, y))
			for k in range(1, 12, 2):
				draw_line(a[k], b[k], Color(color, 0.6), 2, true)
			draw_polyline(a, color, 5, true)
			draw_polyline(b, color.darkened(0.25), 5, true)
		"attack_slot":
			_mawling_head(c, 0.85 * r, color)
		"trait_slot":
			for k in 3:
				_diamond(c + Vector2(-0.62 + k * 0.62, 0), 0.38 * r, color if k < 2 else Color(color, 0.45))
		_:
			_diamond(c, 0.6 * r, color)

# ================================================================ Trophäen

func _trophy_order() -> Array:
	var open: Array = []
	var done: Array = []
	for q in menu.meta.QUESTS:
		if q.id in menu.profile.completed_quests:
			done.append(q)
		else:
			open.append(q)
	return open + done


func _draw_trophy_header(s: Rect2, accent: Color) -> void:
	var done: int = menu.profile.completed_quests.size()
	var total: int = menu.meta.QUESTS.size()
	var right: float = menu.sheet_close_rect().position.x - 16
	var y := s.position.y + 60
	var label := "%d / %d" % [done, total]
	var lw := _w(label, 34)
	_icon_trophy(Vector2(right - lw - 40, y - 12), 20)
	_txt(label, Vector2(right, y), 34, S.color("gold"), 2, 6)
	_body("erledigt", Vector2(right, y + 30), 22, Color(S.color("gold"), 0.8), 2)
	_bar_fill(Rect2(right - 170, y + 44, 170, 14), float(done) / maxf(1.0, total), S.color("gold"))


func _icon_trophy(c: Vector2, r: float) -> void:
	if _icon(["trophy"], Rect2(c - Vector2(r, r) * 1.2, Vector2(r, r) * 2.4)):
		return
	# Cup with handles and a small crown.
	draw_colored_polygon(PackedVector2Array([c + Vector2(-0.75, -0.7) * r, c + Vector2(0.75, -0.7) * r, c + Vector2(0.5, 0.15) * r, c + Vector2(0.15, 0.35) * r, c + Vector2(-0.15, 0.35) * r, c + Vector2(-0.5, 0.15) * r]), S.color("gold"))
	draw_arc(c + Vector2(-0.75, -0.35) * r, 0.3 * r, PI * 0.5, PI * 1.5, 10, S.color("gold"), 3, true)
	draw_arc(c + Vector2(0.75, -0.35) * r, 0.3 * r, -PI * 0.5, PI * 0.5, 10, S.color("gold"), 3, true)
	draw_rect(Rect2(c + Vector2(-0.12, 0.3) * r, Vector2(0.24, 0.4) * r), S.color("gold"))
	draw_rect(Rect2(c + Vector2(-0.5, 0.7) * r, Vector2(1.0, 0.25) * r), S.color("gold").darkened(0.2))
	draw_line(c + Vector2(-0.4, -0.55) * r, c + Vector2(-0.25, 0.05) * r, Color(1, 1, 1, 0.5), 2, true)


func _quest_category(stat: String) -> String:
	if stat.ends_with("seconds") or stat.begins_with("diff_time") or stat.begins_with("strain_time"):
		return "time"
	if stat == "best_peak":
		return "swarm"
	if stat == "total_bosses":
		return "boss"
	if stat.begins_with("evo") or stat == "total_evolutions":
		return "evolution"
	if stat == "total_biomass":
		return "biomass"
	if stat == "runs":
		return "runs"
	return "hunt"


const CATEGORY_COLOR := {"time": S.CYAN, "swarm": S.EMBER, "boss": S.GOLD, "evolution": S.VIOLET, "biomass": S.AMBER, "runs": S.TOXIC, "hunt": S.DANGER}
const CATEGORY_ICONS := {"time": ["clock"], "swarm": ["mawling_head", "mawling"], "boss": ["crown"], "evolution": ["branch_special", "dna", "dna_helix"], "biomass": ["alpha_core", "biomass"], "runs": ["trophy"], "hunt": ["skull"]}


func _category_glyph(cat: String, c: Vector2, r: float, color: Color) -> void:
	var ids: Array = CATEGORY_ICONS.get(cat, [])
	# Painted V2 icons (evolution branch) keep their own colours.
	if _icons != null and not ids.is_empty() and _icons.has(ids[0]) and _icons.is_painted(ids[0]):
		_icons.draw(self, ids[0], Rect2(c - Vector2(r, r) * 1.3, Vector2(r, r) * 2.6), Color.WHITE)
		return
	if _icon(ids, Rect2(c - Vector2(r, r) * 1.25, Vector2(r, r) * 2.5), color.lightened(0.4)):
		return
	match cat:
		"time":
			draw_circle(c, r, color)
			draw_circle(c, r * 0.78, S.tone(Color("06110d")))
			draw_line(c, c + Vector2(0, -0.6) * r, color, 3, true)
			draw_line(c, c + Vector2(0.45, 0.1) * r, color, 3, true)
			draw_circle(c, r * 0.12, color)
		"swarm":
			_mawling_head(c + Vector2(-0.1, 0.1) * r, r * 1.05, color)
		"boss":
			_crown(c + Vector2(0, 0.15) * r, r * 1.1, color)
		"evolution":
			_upgrade_glyph("geneflow", c, r, color)
		"biomass":
			_ellipse(c, r * 0.72, r * 0.95, color)
			for o in [Vector2(-0.25, -0.3), Vector2(0.28, 0.0), Vector2(-0.1, 0.4)]:
				draw_circle(c + o * r, r * 0.16, color.darkened(0.45))
		"runs":
			_icon_trophy(c, r * 0.95)
		_:
			_skull(c + Vector2(0, 0.05) * r, r * 0.95, color)


func _draw_trophy_rows() -> void:
	var row_h: float = menu._trophy_row_height()
	var scroll: float = menu.trophy_scroll
	var order := _trophy_order()
	var first := int(scroll / row_h)
	var profile = menu.profile
	for k in range(maxi(0, first - 1), mini(order.size(), first + int(size.y / row_h) + 2)):
		var q: Dictionary = order[k]
		var row := Rect2(10, 4 + k * row_h - scroll, size.x - 16, row_h - 12)
		if row.end.y < -10 or row.position.y > size.y + 10:
			continue
		var done: bool = q.id in profile.completed_quests
		var cat := _quest_category(String(q.stat))
		var cat_color: Color = S.tone(CATEGORY_COLOR.get(cat, S.VIOLET))
		var accent: Color = S.color("gold") if done else cat_color
		_card(row, accent, "gold" if done else "normal", 20, false)
		var ic := row.position + Vector2(56, row.size.y * 0.5)
		_medallion(ic, 38, accent, 0.9 if done else 0.6)
		_category_glyph(cat, ic, 20, cat_color if not done else S.color("gold"))
		if done:
			draw_circle(ic + Vector2(27, 26), 15, S.color("gold"))
			draw_circle(ic + Vector2(27, 26), 12, S.tone(Color("3a2a08")))
			_check(ic + Vector2(27, 26), 10, S.color("gold"))
		var x := row.position.x + 110
		_txt(String(q.name), Vector2(x, row.position.y + 38), 29, S.color("gold").lightened(0.25) if done else S.color("text"), 0, 6)
		_body(String(q.description), Vector2(x, row.position.y + 66), 22, Color(S.color("text_dim"), 0.95))
		var progress: Vector2 = profile.quest_progress(q.id)
		# Currency rewards right-aligned on the name line (clear of the frame pores).
		_draw_reward_chips(q, Vector2(row.end.x - 70, row.position.y + 40), done)
		var used_right := x
		if done:
			used_right += _txt("ERLEDIGT", Vector2(x, row.position.y + 95), 22, S.color("gold"), 0, 4)
		else:
			var bar := Rect2(x, row.position.y + 78, 210, 16)
			_bar_fill(bar, clampf(progress.x / maxf(1.0, progress.y), 0.0, 1.0), cat_color)
			used_right = bar.end.x + 12 + _body(menu._progress_text(q, progress), Vector2(bar.end.x + 12, row.position.y + 94), 22, S.color("text"))
		var unlocks: Array = q.get("reward", {}).get("unlock", [])
		if not unlocks.is_empty():
			var label := String(menu.meta.unlock_label(unlocks[0]))
			if unlocks.size() > 1:
				label += " +%d" % (unlocks.size() - 1)
			var room := row.end.x - 26 - used_right - 18 - 34
			var fitted := _fit(label, room, [22], S.body_font())
			var tw := _w(fitted[0], fitted[1], S.body_font()) + 34
			var tag := Rect2(row.end.x - 26 - tw, row.position.y + 70, tw, 32)
			draw_colored_polygon(_rounded_points(tag, 15, 4), S.tone(Color("050c09", 0.85)))
			draw_colored_polygon(_rounded_points(tag, 15, 4), Color(S.color("gold"), 0.10 if done else 0.2))
			_outline(_rounded_points(tag, 15, 4), Color(S.color("gold"), 0.45 if done else 0.85), 1.5)
			_rank_diamond(tag.position + Vector2(16, 16), 6, S.color("gold"), true)
			_body(fitted[0], tag.position + Vector2(27, 23), fitted[1], Color(S.color("gold"), 0.7) if done else S.color("gold").lightened(0.35))


func _draw_reward_chips(q: Dictionary, right_base: Vector2, done: bool) -> void:
	var r: Dictionary = q.get("reward", {})
	var x := right_base.x
	var alpha := 0.6 if done else 1.0
	if int(r.get("crowns", 0)) > 0:
		var t := "+%d" % int(r.crowns)
		x -= _txt(t, Vector2(x, right_base.y), 27, Color(S.color("gold").lightened(0.3), alpha), 2, 5)
		_crown_icon(Vector2(x - 16, right_base.y - 10), 13)
		x -= 44
	if int(r.get("essence", 0)) > 0:
		var t := "+%d" % int(r.essence)
		x -= _txt(t, Vector2(x, right_base.y), 27, Color(_ess().lightened(0.3), alpha), 2, 5)
		_essence_icon(Vector2(x - 16, right_base.y - 10), 11, not done)


func _draw_trophy_scrollbar(s: Rect2, accent: Color) -> void:
	var max_scroll: float = menu._trophy_scroll_max()
	if max_scroll <= 0.0:
		return
	var area := _list_area()
	var track := Rect2(s.end.x - 20, area.position.y + 6, 6, area.size.y - 12)
	draw_colored_polygon(_rounded_points(track, 2.5, 3), Color(1, 1, 1, 0.06))
	var h := track.size.y * track.size.y / (track.size.y + max_scroll)
	var thumb := Rect2(track.position.x, track.position.y + (track.size.y - h) * menu.trophy_scroll / max_scroll, 6, h)
	draw_colored_polygon(_rounded_points(thumb, 2.5, 3), accent)
	# Fade the list edges into the panel.
	for e in [[area.position.y, 1.0], [area.end.y, -1.0]]:
		var y0: float = e[0]
		var dir: float = e[1]
		var band := Rect2(area.position.x, y0 if dir > 0 else y0 - 18, area.size.x, 18)
		var top_c := S.tone(Color("0b1a15", 0.9 if dir > 0 else 0.0))
		var bot_c := S.tone(Color("0b1a15", 0.0 if dir > 0 else 0.9))
		_gradient_fill(PackedVector2Array([band.position, Vector2(band.end.x, band.position.y), band.end, Vector2(band.position.x, band.end.y)]), band, top_c, bot_c)

# ================================================================ Urinstinkt

func _draw_instinct() -> void:
	var s: Rect2 = menu.sheet_rect()
	var level := int(menu.profile.instinct_level)
	var info: Dictionary = menu.meta.INSTINCT
	var bonus := float(info.get("bonus", 0.01)) * 100.0
	var now := _now()
	var c := Vector2(s.get_center().x, s.position.y + 404)
	var breathe := 0.5 + 0.5 * sin(now * 1.8)
	# The ring is drawn at 92 % so it fits between header and tiles.
	var ring_scale := 0.92
	draw_set_transform(c - c * ring_scale, 0.0, Vector2(ring_scale, ring_scale))
	# Glow halo.
	for i in 8:
		draw_circle(c, 290 - i * 18, Color(S.color("cyan"), 0.018 + i * 0.004 + breathe * 0.006))
	# Rotating rune ticks.
	for i in 36:
		var a := now * 0.15 + i * TAU / 36.0
		var p := c + Vector2(cos(a), sin(a)) * 252
		draw_circle(p, 3.0 if i % 3 == 0 else 1.6, Color(S.color("cyan"), 0.35 if i % 3 == 0 else 0.18))
	draw_arc(c, 238, 0, TAU, 96, Color(S.color("cyan"), 0.3), 2, true)
	# Level ring: ten segments per circle.
	var filled := level % 10
	var circle_index := level / 10
	for i in 10:
		var a0 := -PI * 0.5 + i * TAU / 10.0 + 0.035
		var a1 := a0 + TAU / 10.0 - 0.07
		if i < filled:
			_ring_sector(c, 186, 232, a0, a1, Color(S.color("cyan"), 0.2))
			_ring_sector(c, 192, 226, a0, a1, S.color("cyan").darkened(0.1))
			_ring_sector(c, 212, 224, a0, a1, S.color("cyan").lightened(0.45))
		elif i == filled:
			_ring_sector(c, 192, 226, a0, a1, Color(S.color("cyan"), 0.18 + 0.2 * breathe))
		else:
			_ring_sector(c, 192, 226, a0, a1, S.tone(Color("10261f")))
	# Inner well.
	draw_circle(c, 176, S.tone(Color("040b08")))
	for i in 5:
		draw_circle(c + Vector2(0, -20), 160 - i * 26, Color(S.color("cyan"), 0.035))
	draw_arc(c, 176, 0, TAU, 96, S.color("cyan"), 3, true)
	draw_arc(c, 166, 0, TAU, 96, Color(S.color("cyan"), 0.25), 1.5, true)
	if not _icon(["mawling_head", "mawling"], Rect2(c + Vector2(-58, -150), Vector2(116, 116)), S.color("ember_glow")):
		_mawling_head(c + Vector2(-6, -86), 58, S.color("ember"))
	_txt("STUFE", c + Vector2(0, 2), 26, Color(S.color("cyan").lightened(0.4), 0.95), 1, 5)
	_txt("%d" % level, c + Vector2(0, 108), 110, Color.WHITE, 1, 10)
	if circle_index > 0:
		_body("Kreis %d" % (circle_index + 1), c + Vector2(0, 148), 23, Color(S.color("cyan"), 0.8), 1)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Current bonus and next level tiles.
	var tiles_y := s.position.y + 668
	var tw := (s.size.x - 100) * 0.5
	var cur := Rect2(s.position.x + 40, tiles_y, tw, 136)
	var nxt := Rect2(cur.end.x + 20, tiles_y, tw, 136)
	_card(cur, S.color("cyan"), "normal", 18, false)
	_card(nxt, S.color("ember"), "normal", 18, false)
	_body("AKTUELL", cur.position + Vector2(32, 48), 22, Color(S.color("cyan"), 0.9))
	_txt("+%d %% Schaden" % roundi(bonus * level), cur.position + Vector2(32, 86), 28, S.color("text"), 0, 5)
	_txt("+%d %% Biomasse" % roundi(bonus * level), cur.position + Vector2(32, 118), 28, S.color("text"), 0, 5)
	_body("STUFE %d" % (level + 1), nxt.position + Vector2(32, 48), 22, Color(S.color("ember_glow"), 0.95))
	_txt("+%d %% Schaden" % roundi(bonus * (level + 1)), nxt.position + Vector2(32, 86), 28, S.color("ember_glow").lightened(0.3), 0, 5)
	_txt("+%d %% Biomasse" % roundi(bonus * (level + 1)), nxt.position + Vector2(32, 118), 28, S.color("ember_glow").lightened(0.3), 0, 5)
	_arrow(Vector2(cur.end.x + 10, tiles_y + 68), 16, 1.0, S.color("ember_glow"))
	# STÄRKEN button on the menu rectangle.
	var cost := int(menu._instinct_cost())
	var buy: Rect2 = menu.instinct_buy_rect()
	var affordable: bool = menu.profile.essence >= cost
	var down: bool = menu.is_pressed(buy)
	var po := _press_offset(down)
	_button(buy, "ember" if affordable else "off", (0.6 + 0.4 * breathe) if affordable else 0.0, down)
	var col := Color.WHITE if affordable else S.tone(Color("9aa39c"))
	_txt("STÄRKEN", Vector2(buy.get_center().x, buy.position.y + 58) + po, 46, col, 1, 7)
	var cost_text := "%d" % cost
	var cw := _w(cost_text, 32)
	var cx := buy.get_center().x - (cw + 34) * 0.5
	_essence_icon(Vector2(cx + 11, buy.position.y + 90) + po, 12, affordable)
	_txt(cost_text, Vector2(cx + 32, buy.position.y + 103) + po, 32, col, 0, 5)
	if not affordable:
		_body("Noch %d Essenz" % (cost - int(menu.profile.essence)), Vector2(buy.get_center().x, buy.end.y + 40), 22, S.color("danger").lightened(0.3), 1)
	var note_y := buy.end.y + (84 if not affordable else 56)
	_paragraph_body("Urinstinkt hat keine Obergrenze. Jede Stufe kostet %d Essenz mehr – lohnt sich, wenn die Brutkammer ausgebaut ist." % int(info.get("step", 50)), Vector2(s.get_center().x, note_y), s.size.x - 140, 22, Color(S.color("text_dim"), 0.85))


func _paragraph_body(value: String, at: Vector2, width: float, px: int, color: Color) -> void:
	var font := S.body_font()
	var line := ""
	var y := at.y
	for word in value.split(" ", false):
		var candidate := word if line == "" else line + " " + word
		if _w(candidate, px, font) > width and line != "":
			_body(line, Vector2(at.x, y), px, color, 1)
			y += px * 1.35
			line = word
		else:
			line = candidate
	if line != "":
		_body(line, Vector2(at.x, y), px, color, 1)

# ================================================================ Belohnung

func _ease(t0: float, duration: float) -> float:
	var t := clampf((_now() - _reward_t0 - t0) / duration, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)


func _draw_reward() -> void:
	var reward: Dictionary = menu.reward
	var stats: Dictionary = menu.reward_stats
	var meta = menu.meta
	var cx := size.x * 0.5
	var appear := _ease(0.0, 0.35)
	draw_rect(Rect2(Vector2.ZERO, size), S.tone(Color("040b08", 0.9 * appear)))
	var button: Rect2 = menu.reward_button_rect()
	var panel := Rect2(34, 66, size.x - 68, button.end.y + 44 - 66)
	var pivot := panel.get_center()
	var scale := lerpf(0.94, 1.0, appear)
	draw_set_transform(pivot - pivot * scale, 0.0, Vector2(scale, scale))
	_card(panel, S.color("gold"), "gold", 40, true)
	# Rays behind the emblem.
	var em := Vector2(cx, 150)
	var t := _now() - _reward_t0
	for i in 12:
		var a := t * 0.25 + i * TAU / 12.0
		var tip := em + Vector2(cos(a), sin(a)) * 120
		var l := em + Vector2(cos(a - 0.08), sin(a - 0.08)) * 50
		var r := em + Vector2(cos(a + 0.08), sin(a + 0.08)) * 50
		draw_colored_polygon(PackedVector2Array([l, tip, r]), Color(S.color("gold"), 0.07))
	_medallion(em, 54, S.color("danger"), 1.0)
	if not _icon(["skull"], Rect2(em - Vector2(36, 36), Vector2(72, 72)), S.color("bone")):
		_skull(em + Vector2(0, 4), 34, S.color("bone"))
	_txt("RUN BEENDET", Vector2(cx, 272), 66, S.color("text"), 1, 9)
	var strain: Dictionary = meta.STRAINS.get(String(stats.get("strain_id", "")), {})
	var diff_index := clampi(int(stats.get("difficulty", 0)), 0, meta.DIFFICULTIES.size() - 1)
	var sub := "%s  ·  %s" % [String(strain.get("name", "")).to_upper(), String(meta.DIFFICULTIES[diff_index].name).to_upper()]
	var daily: Dictionary = reward.get("daily", {})
	if not daily.is_empty():
		sub = "TAGES-BRUT  ·  " + sub + ("  ·  TAGESREKORD" if daily.get("new_best", false) else "")
	_txt(sub, Vector2(cx, 314), 24, Color(strain.get("tint", "#9ed5b3")).lightened(0.4), 1, 5)
	# Survival time counts up.
	var seconds := float(stats.get("seconds", 0.0)) * _ease(0.25, 1.0)
	_body("ÜBERLEBT", Vector2(cx, 364), 22, Color(S.color("text_dim"), 0.95), 1)
	_txt("%02d:%02d" % [int(seconds) / 60, int(seconds) % 60], Vector2(cx, 440), 84, Color.WHITE, 1, 9)
	# Stat tiles.
	var tiles := [["MAX. SCHWARM", float(stats.get("peak_population", 0)), S.color("ember")], ["KILLS", float(stats.get("kills", 0)), S.color("cyan")], ["BOSSE", float(stats.get("bosses", 0)), S.color("gold")]]
	var tw := (panel.size.x - 60 - 40) / 3.0
	for i in tiles.size():
		var tile := Rect2(panel.position.x + 30 + i * (tw + 20), 470, tw, 108)
		_card(tile, tiles[i][2], "normal", 16, false)
		_body(tiles[i][0], Vector2(tile.get_center().x, tile.position.y + 44), 22, Color(S.color("text_dim"), 0.95), 1)
		var v := roundi(float(tiles[i][1]) * _ease(0.45 + i * 0.1, 1.0))
		_txt("%d" % v, Vector2(tile.get_center().x, tile.position.y + 88), 44, (tiles[i][2] as Color).lightened(0.25), 1, 6)
	# Loot header.
	var ly := 628.0
	var hw := _w("BEUTE FÜR DIE BRUT", 26) * 0.5
	_txt("BEUTE FÜR DIE BRUT", Vector2(cx, ly), 26, S.color("gold"), 1, 5)
	for sgn in [-1.0, 1.0]:
		draw_line(Vector2(cx + sgn * (hw + 16), ly - 9), Vector2(cx + sgn * (hw + 150), ly - 9), Color(S.color("gold"), 0.45), 2, true)
		_rank_diamond(Vector2(cx + sgn * (hw + 158), ly - 9), 6, S.color("gold"), true)
	var loot := [
		{"color": _ess(), "value": int(reward.get("essence", 0)), "label": "ESSENZ", "icon": "essence",
			"split": [int(reward.get("run_essence", 0)), int(reward.get("quest_essence", 0))]},
		{"color": S.color("gold"), "value": int(reward.get("crowns", 0)), "label": "KÖNIGSZÄHNE", "icon": "crowns",
			"split": [int(reward.get("run_crowns", 0)), int(reward.get("quest_crowns", 0))]},
	]
	var lw := (panel.size.x - 60 - 20) * 0.5
	for i in loot.size():
		var L: Dictionary = loot[i]
		var tile := Rect2(panel.position.x + 30 + i * (lw + 20), 650, lw, 168)
		var col: Color = L.color
		var count_e := _ease(0.9 + i * 0.15, 1.2)
		var done := count_e >= 1.0
		_card(tile, col, "active" if done else "normal", 22, false)
		var ic := tile.position + Vector2(76, 80)
		var burst := 1.0 + (0.18 * (1.0 - _ease(2.1 + i * 0.15, 0.4)) if done else 0.0)
		for k in 5:
			draw_circle(ic, (46 + k * 9) * burst, Color(col, 0.05))
		if L.icon == "essence":
			_essence_icon(ic, 30 * burst)
		else:
			_crown_icon(ic, 34 * burst)
		var value := roundi(float(L.value) * count_e)
		var vt := "+%d" % value
		var fitted := _fit(vt, tile.size.x - 200, [66, 56, 48])
		_txt(fitted[0], Vector2(tile.position.x + 136, tile.position.y + 82), fitted[1], Color.WHITE, 0, 8)
		_txt(L.label, Vector2(tile.position.x + 138, tile.position.y + 112), 22, col.lightened(0.3), 0, 4)
		var split: Array = L.split
		if split[1] > 0:
			var room := tile.end.x - 34.0 - (tile.position.x + 138)
			var parts := "Run +%d · Trophäe +%d" % [split[0], split[1]]
			if _w(parts, 22, S.body_font()) > room:
				parts = "+%d Run · +%d Tr." % [split[0], split[1]]
			if _w(parts, 22, S.body_font()) > room:
				parts = "+%d · +%d" % [split[0], split[1]]
			_body(parts, Vector2(tile.position.x + 138, tile.position.y + 138), 22, Color(S.color("text_dim"), 0.9), 0)
		# Shine sweep once the count lands, then every few seconds.
		var since := _now() - _reward_t0 - (2.1 + i * 0.15)
		if since > 0.0:
			_sweep(_shape(tile, 22), tile, fmod(since, 3.6) / 0.8, 0.22)
	# New trophies + unlock cards, staggered.
	var new_quests: Array = reward.get("new_quests", [])
	var y := 866.0
	if new_quests.is_empty():
		_body("Keine neuen Trophäen – die nächste Jagd wartet.", Vector2(cx, y + 40), 22, Color(S.color("text_dim"), 0.9), 1)
		var next: Dictionary = menu._next_quest()
		if not next.is_empty():
			_body("Nächstes Ziel: %s" % next.name, Vector2(cx, y + 76), 22, S.color("violet").lightened(0.3), 1)
	else:
		var unlocked: Array = reward.get("unlocked", [])
		_txt("NEUE TROPHÄEN  %d" % new_quests.size(), Vector2(panel.position.x + 34, y), 24, S.color("violet").lightened(0.35), 0, 5)
		if not unlocked.is_empty():
			_txt("%d FREIGESCHALTET" % unlocked.size(), Vector2(panel.end.x - 34, y), 24, S.color("gold"), 2, 5)
		var with_unlock: Array = []
		var plain: Array = []
		for id in new_quests:
			var q: Dictionary = meta.quest(String(id))
			if q.is_empty():
				continue
			if q.get("reward", {}).get("unlock", []).is_empty():
				plain.append(q)
			else:
				with_unlock.append(q)
		var bottom := button.position.y - 22
		var cy := y + 18
		var shown := 0
		var total := with_unlock.size() + plain.size()
		var left := panel.position.x + 30
		var width := panel.size.x - 60
		var card_h := 66.0
		var chip_h := 52.0
		for k in with_unlock.size():
			var remaining := total - shown
			var need := card_h + (0.0 if remaining == 1 else 34.0)
			if cy + need > bottom:
				break
			_unlock_card(Rect2(left, cy, width, card_h), with_unlock[k], shown)
			cy += card_h + 8
			shown += 1
		var col := 0
		for k in plain.size():
			var remaining := total - shown
			if col == 0 and cy + chip_h + (0.0 if remaining <= 2 else 34.0) > bottom:
				break
			var cw := (width - 12) * 0.5
			_trophy_chip(Rect2(left + col * (cw + 12), cy, cw, chip_h), plain[k], shown)
			shown += 1
			col += 1
			if col == 2:
				col = 0
				cy += chip_h + 8
		if col == 1:
			cy += chip_h + 8
		if shown < total:
			var a := _ease(2.0 + shown * 0.16, 0.3)
			_body("+ %d weitere in TROPHÄEN" % (total - shown), Vector2(cx, cy + 22), 22, Color(S.color("violet").lightened(0.35), a), 1)
	# WEITER on the menu rectangle.
	var pulse := 0.5 + 0.5 * sin(_now() * 2.5)
	var down: bool = menu.is_pressed(button)
	_button(button, "ember", 0.6 + 0.4 * pulse, down)
	_txt("WEITER", button.get_center() + Vector2(0, 17) + _press_offset(down), 50, Color.WHITE, 1, 8)
	_draw_share_button()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## KARTE TEILEN (stage 10): secondary button left of WEITER; renders the share card.
func _draw_share_button() -> void:
	var rect: Rect2 = menu.share_button_rect()
	var busy: bool = menu.is_sharing()
	var down: bool = menu.is_pressed(rect) or busy
	_button(rect, "cyan", 0.0, down)
	var po := _press_offset(down)
	var ic := Vector2(rect.position.x + 58, rect.get_center().y) + po
	_share_glyph(ic, 22, S.color("cyan").lightened(0.35))
	var x := rect.position.x + 96
	_txt("KARTE", Vector2(x, rect.position.y + 54) + po, 34, S.color("text"), 0, 6)
	_txt("TEILEN" if not busy else "WIRD GEMALT", Vector2(x, rect.position.y + 92) + po, 30 if not busy else 22, S.color("cyan").lightened(0.4), 0, 5)


## Share glyph: three linked nodes.
func _share_glyph(c: Vector2, r: float, color: Color) -> void:
	if S.is_brawl() and _b_icon("g_share", c, r * 2.4, color):
		return
	var a := c + Vector2(r * 0.7, -r * 0.8)
	var b := c + Vector2(-r * 0.75, 0)
	var d := c + Vector2(r * 0.7, r * 0.8)
	for seg in [[a, b], [b, d]]:
		draw_line(seg[0], seg[1], S.color("outline"), 9.0, true)
		draw_line(seg[0], seg[1], color, 5.0, true)
	for p in [a, b, d]:
		draw_circle(p, r * 0.42, S.color("outline"))
		draw_circle(p, r * 0.32, color)


func _stagger(index: int) -> float:
	return _ease(2.0 + index * 0.16, 0.35)


func _unlock_card(rect: Rect2, q: Dictionary, index: int) -> void:
	var a := _stagger(index)
	if a <= 0.0:
		return
	var r := rect
	r.position.x += (1.0 - a) * 60.0
	var unlocks: Array = q.reward.get("unlock", [])
	var labels: Array = []
	for token in unlocks:
		labels.append(String(menu.meta.unlock_label(token)))
	_card(r, S.color("gold"), "gold" if a >= 1.0 else "normal", 18, false)
	var ic := r.position + Vector2(38, r.size.y * 0.5)
	_medallion(ic, 24, S.color("gold"), 0.8)
	_unlock_glyph(String(unlocks[0]), ic, 14)
	var tag := Rect2(r.end.x - 120, r.position.y + 18, 66, 30)
	draw_colored_polygon(_rounded_points(tag, 14, 4), Color(S.color("gold"), 0.25 + 0.15 * sin(_now() * 4.0)))
	_txt("NEU", tag.get_center() + Vector2(0, 9), 22, S.color("gold").lightened(0.4), 1, 4)
	var text := " · ".join(labels)
	var fitted := _fit(text, r.size.x - 180, [25, 23, 22])
	_txt(fitted[0], r.position + Vector2(76, 30), fitted[1], S.color("gold").lightened(0.35), 0, 5)
	var line := "%s%s" % [q.name, _currency_suffix(q)]
	var f2 := _fit(line, r.size.x - 180, [22], S.body_font())
	_body(f2[0], r.position + Vector2(76, 57), f2[1], Color(S.color("text_dim"), 0.95))


func _currency_suffix(q: Dictionary) -> String:
	var r: Dictionary = q.get("reward", {})
	var parts: Array = []
	if int(r.get("essence", 0)) > 0:
		parts.append("+%d Essenz" % int(r.essence))
	if int(r.get("crowns", 0)) > 0:
		parts.append("+%d %s" % [int(r.crowns), "Zahn" if int(r.crowns) == 1 else "Zähne"])
	return "" if parts.is_empty() else "  ·  " + " · ".join(parts)


func _unlock_glyph(token: String, c: Vector2, r: float) -> void:
	var kind := token.split(":")[0]
	var arg := token.split(":")[1] if token.contains(":") else ""
	match kind:
		"strain":
			_mawling_head(c, r * 1.05, Color(String(menu.meta.STRAINS.get(arg, {}).get("tint", "#d9401f"))).lightened(0.2))
		"difficulty":
			_skull(c, r * 0.95, S.color("danger").lightened(0.2))
		"mutation":
			_upgrade_glyph("geneflow", c, r, S.color("violet").lightened(0.3))
		"upgrade":
			_upgrade_glyph("attack_slot", c, r, S.color("ember"))
		_:
			_diamond(c, r * 0.8, S.color("gold"))


func _trophy_chip(rect: Rect2, q: Dictionary, index: int) -> void:
	var a := _stagger(index)
	if a <= 0.0:
		return
	var r := rect
	r.position.x += (1.0 - a) * 60.0
	_card(r, S.color("toxic"), "normal", 14, false)
	var ic := r.position + Vector2(28, r.size.y * 0.5)
	draw_circle(ic, 15, Color(S.color("toxic"), 0.25))
	_check(ic, 11, S.color("toxic").lightened(0.3))
	var fitted := _fit(String(q.name), r.size.x - 150, [23, 22])
	_txt(fitted[0], r.position + Vector2(52, 34), fitted[1], S.color("text"), 0, 4)
	var rw: Dictionary = q.get("reward", {})
	var right := r.end.x - 14
	if int(rw.get("crowns", 0)) > 0:
		right -= _txt("+%d" % int(rw.crowns), Vector2(right, r.position.y + 35), 23, S.color("gold").lightened(0.3), 2, 4)
		_crown_icon(Vector2(right - 12, r.position.y + 26), 10)
		right -= 30
	if int(rw.get("essence", 0)) > 0:
		right -= _txt("+%d" % int(rw.essence), Vector2(right, r.position.y + 35), 23, _ess().lightened(0.3), 2, 4)
		_essence_icon(Vector2(right - 12, r.position.y + 27), 9)

# ================================================================ Toast

# ================================================================ Einstellungen

func _draw_settings() -> void:
	var p: Rect2 = menu.settings_panel_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color(S.color("dim"), 0.8))
	if _frames != null:
		_frames.panel(self, p, S.color("bone"), true)
	else:
		_card(p, S.color("bone"), "normal", 36, true)
	_txt("EINSTELLUNGEN", Vector2(p.position.x + 40, p.position.y + 62), 44, S.color("text"), 0, 8)
	var close: Rect2 = menu.settings_close_rect()
	var close_down: bool = menu.is_pressed(close)
	_button(close.grow(-6), "off", 0.0, close_down)
	var cc := close.get_center() + _press_offset(close_down)
	for d in [Vector2(1, 1), Vector2(1, -1)]:
		draw_line(cc - d * 17, cc + d * 17, S.color("outline"), 11, true)
		draw_line(cc - d * 17, cc + d * 17, S.color("bone"), 6, true)
	var accents := [S.color("cyan"), S.color("ember"), S.color("violet")]
	for i in menu.SETTINGS.size():
		var entry: Array = menu.SETTINGS[i]
		var row: Rect2 = menu.settings_row_rect(i)
		var on: bool = menu.setting(entry[0])
		var accent: Color = accents[i % accents.size()]
		var down: bool = menu.is_pressed(row)
		var po := _press_offset(down)
		_setting_row(row, accent, on, down)
		var ic := row.position + Vector2(58, row.size.y * 0.5) + po
		_medallion(ic, 36, accent if on else S.tone(Color("56625a")), 0.7 if on else 0.0)
		_setting_glyph(String(entry[0]), ic, accent.lightened(0.2) if on else S.tone(Color("7d8a80")), on)
		_txt(String(entry[1]), row.position + Vector2(116, 50) + po, 32, S.color("text") if on else S.color("text_dim"), 0, 6)
		var desc := _fit(String(entry[2]), row.size.x - 116 - 190, [22], S.body_font())
		_body(desc[0], row.position + Vector2(116, 84) + po, desc[1], Color(S.color("text_dim"), 0.95))
		_switch(Rect2(Vector2(row.end.x - 164, row.get_center().y - 30) + po, Vector2(140, 60)), on, accent)
	# UI style row (stage 15), drawn in the old frame language too so a player
	# on calm/organic can switch back.
	var sr: Rect2 = menu.settings_skin_row_rect()
	_setting_row(sr, S.color("cyan"), true, false)
	_txt("UI-STIL", sr.position + Vector2(24, 44), 30, S.color("text"), 0, 6)
	for k in menu.UI_SKINS.size():
		var id: String = menu.UI_SKINS[k]
		var rect: Rect2 = menu.settings_skin_rect(k)
		var down: bool = menu.is_pressed(rect)
		_button(rect, "ember" if id == menu.ui_skin() else "off", 0.0, down)
		_txt(String(menu.UI_SKIN_NAMES[id]), rect.get_center() + Vector2(0, 10) + _press_offset(down), 26, S.color("text"), 1, 5)
	# Etappe 24: reset the one-time tips.
	var tips: Rect2 = menu.settings_tips_rect()
	var tips_down: bool = menu.is_pressed(tips)
	_button(tips, "off", 0.0, tips_down)
	_txt("TIPPS ZURÜCKSETZEN", tips.get_center() + Vector2(0, 10) + _press_offset(tips_down), 28, S.color("text"), 1, 5)
	var note_y: float = tips.end.y + 40
	_paragraph_body("Farbenblind: Gefahren zusätzlich mit Muster und Kontur.", Vector2(p.get_center().x, note_y), p.size.x - 110, 22, Color(S.color("text_dim"), 0.85))


## Light settings row (stage 06): flat dark strip with a thin rim and an accent
## stripe when on – no claw frame per row, the switch carries the state.
func _setting_row(row: Rect2, accent: Color, on: bool, down: bool) -> void:
	var shape := _rounded_points(row, 18, 5)
	draw_colored_polygon(shape, S.tone(Color("06110c", 0.72 if on else 0.5)))
	if on:
		_gradient_fill(_rounded_points(row.grow(-2), 16, 5), row, Color(accent, 0.10), Color(accent, 0.02))
	if down:
		draw_colored_polygon(shape, Color(1, 1, 1, 0.05))
	_outline(shape, Color(accent, 0.45) if on else Color(S.color("panel_edge"), 0.9), 1.5)
	if on:
		var stripe := Rect2(row.position + Vector2(0, 22), Vector2(5, row.size.y - 44))
		draw_colored_polygon(_rounded_points(stripe, 2.5, 2), accent)


## Toggle switch: capsule track, sliding knob, AN/AUS written inside.
func _switch(rect: Rect2, on: bool, accent: Color) -> void:
	var r := rect.size.y * 0.5
	draw_colored_polygon(_rounded_points(rect.grow(3), r + 3, 6), S.color("outline"))
	var track := _rounded_points(rect, r, 6)
	_gradient_fill(track, rect, (accent.darkened(0.05) if on else S.tone(Color("1c2621"))), (accent.darkened(0.45) if on else S.tone(Color("0c1410"))))
	_outline(track, accent.lightened(0.3) if on else S.tone(Color("5b675f")), 2.0)
	var knob := Vector2(rect.end.x - r if on else rect.position.x + r, rect.get_center().y)
	draw_circle(knob + Vector2(0, 3), r - 5, Color(0, 0, 0, 0.45))
	draw_circle(knob, r - 5, S.color("bone") if on else S.tone(Color("8d998f")))
	draw_circle(knob + Vector2(-5, -6), 6, Color(1, 1, 1, 0.4))
	var label := "AN" if on else "AUS"
	var free := rect.size.x - 2.0 * r
	var lx := rect.position.x + free * 0.5 + (0.0 if on else 2.0 * r)
	_txt(label, Vector2(lx, rect.get_center().y + 9), 24, S.color("outline") if on else S.color("text_dim"), 1, 0 if on else 4)


func _setting_glyph(key: String, c: Vector2, color: Color, on: bool) -> void:
	if S.is_brawl():
		var glyph_id: String = {"sound": "g_sound", "vibration": "g_vibration", "music_v1": "g_music", "speech": "mawling_head_color"}.get(key, "g_eye")
		if _b_icon(glyph_id, c, 50.0, color if on else Color(0.5, 0.55, 0.6)):
			return
	match key:
		"sound":
			# Speaker with sound waves (crossed out when off).
			draw_colored_polygon(PackedVector2Array([c + Vector2(-18, -8), c + Vector2(-8, -8), c + Vector2(4, -19), c + Vector2(4, 19), c + Vector2(-8, 8), c + Vector2(-18, 8)]), color)
			if on:
				draw_arc(c + Vector2(6, 0), 10, -0.9, 0.9, 12, color, 3.5, true)
				draw_arc(c + Vector2(6, 0), 18, -0.9, 0.9, 16, color, 3.5, true)
			else:
				draw_line(c + Vector2(10, -9), c + Vector2(24, 9), color, 4, true)
				draw_line(c + Vector2(24, -9), c + Vector2(10, 9), color, 4, true)
		"vibration":
			# Phone with shake marks.
			var body := Rect2(c + Vector2(-10, -18), Vector2(20, 36))
			draw_colored_polygon(_rounded_points(body, 5, 3), color)
			draw_rect(Rect2(body.position + Vector2(4, 5), Vector2(12, 22)), S.color("outline"))
			if on:
				for sgn in [-1.0, 1.0]:
					draw_line(c + Vector2(sgn * 17, -10), c + Vector2(sgn * 21, -4), color, 3, true)
					draw_line(c + Vector2(sgn * 21, -4), c + Vector2(sgn * 17, 2), color, 3, true)
					draw_line(c + Vector2(sgn * 17, 2), c + Vector2(sgn * 21, 8), color, 3, true)
		"speech":
			# Etappe 25: speech bubble with a tail (three dots while on).
			var bubble := PackedVector2Array()
			for i in 24:
				var a := TAU * float(i) / 24.0
				bubble.append(c + Vector2(cos(a) * 22.0, sin(a) * 15.0 - 3.0))
			draw_colored_polygon(bubble, color)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-12, 8), c + Vector2(-4, 10), c + Vector2(-16, 20)]), color)
			if on:
				for x in [-9.0, 0.0, 9.0]:
					draw_circle(c + Vector2(x, -3), 3, S.color("outline"))
		"music_v1":
			# Two beamed notes; a third, small one when the V1 pack is on.
			for x in [-12.0, 10.0]:
				draw_circle(c + Vector2(x - 5, 12), 7, color)
				draw_line(c + Vector2(x + 1, 12), c + Vector2(x + 1, -16), color, 4, true)
			draw_line(c + Vector2(-11, -16), c + Vector2(11, -12), color, 6, true)
			if on:
				draw_circle(c + Vector2(22, -2), 4, color)
				draw_line(c + Vector2(25, -2), c + Vector2(25, -18), color, 3, true)
		_:
			# Eye with a striped iris (pattern, not only colour).
			var pts := PackedVector2Array()
			for i in 17:
				var t := float(i) / 16.0
				pts.append(c + Vector2(lerpf(-22, 22, t), -sin(t * PI) * 13))
			for i in range(15, 0, -1):
				var t := float(i) / 16.0
				pts.append(c + Vector2(lerpf(-22, 22, t), sin(t * PI) * 13))
			draw_colored_polygon(pts, color)
			draw_circle(c, 9, S.color("outline"))
			for k in 3:
				draw_line(c + Vector2(-6 + k * 5, -7), c + Vector2(-9 + k * 5, 7), color, 2, true)


func _draw_toast() -> void:
	var text: String = menu.toast
	var remaining: float = menu.toast_time
	var fade_out := clampf(remaining / 0.3, 0.0, 1.0)
	var fade_in := clampf((1.8 - remaining) / 0.15, 0.0, 1.0)
	var a := minf(fade_out, fade_in)
	var fitted := _fit(text, size.x - 140, [24, 22], S.body_font())
	var w := _w(fitted[0], fitted[1], S.body_font()) + 84
	var rect := Rect2(size.x * 0.5 - w * 0.5, 30 - (1.0 - fade_in) * 16, w, 56)
	var accent := S.color("danger") if text.begins_with("Nicht") or text.begins_with("Gesperrt") or text.begins_with("Noch") else S.color("toxic")
	var pts := _rounded_points(rect, 26, 6)
	draw_colored_polygon(_rounded_points(Rect2(rect.position + Vector2(0, 4), rect.size), 26, 6), Color(0, 0, 0, 0.4 * a))
	draw_colored_polygon(pts, S.tone(Color("08140f", 0.94 * a)))
	_outline(pts, Color(accent, 0.7 * a), 2.0)
	_rank_diamond(rect.position + Vector2(30, 28), 8, Color(accent, a), true)
	_body(fitted[0], rect.position + Vector2(50, 36), fitted[1], Color(S.color("text"), a))


# Calm skin (V2 kit): rounded chips and capsules become chamfered, bone claws
# disappear. The organic skin keeps the ui_kit.gd shapes unchanged.
func _rounded_points(rect: Rect2, radius: float, steps: int = 6) -> PackedVector2Array:
	if UiStyleRef.is_calm():
		return UiFramesRef.chamfer_points(rect, minf(radius, minf(rect.size.x, rect.size.y) * 0.5) * 0.62)
	return super(rect, radius, steps)


func _claw(base: Vector2, direction: Vector2, length: float, width: float, color: Color, bend: float = 0.35) -> void:
	if UiStyleRef.is_calm():
		return
	super(base, direction, length, width, color, bend)


# ================================================================ brawl skin (stage 15)
# Supercell-style sheets drawn only with ui_kit_brawl.gd and UiStyle tokens:
# the sheet is a Kit.card with a coloured title strip between the resource
# header and the tab dock (both stay visible), rows are Kit.well strips with an
# icon plate, and every button is a Kit 3D button. Settings and the reward are
# centred modals with a Kit.ribbon title. Organic/calm keep the code above.

const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")
const UiArtRef := preload("res://scripts/ui/ui_art.gd")
const B_TAB_TONE := {"upgrades": "info", "trophies": "loot", "instinct": "ember", "chronicle": "special", "codex": "loot"}
const B_TAB_ICON := {"upgrades": "tab_brutkammer", "trophies": "trophy", "instinct": "tab_instinct", "chronicle": "tab_chronicle", "codex": "evo_badge"}
## Plate tone per Brutkammer upgrade (own swarm ember, growth/DNA info, loot, evolution special).
const B_UPGRADE_TONE := {"brood_size": "ember", "rending": "ember", "chitin": "action", "sprinter": "info",
	"digestion": "loot", "witterung": "info", "geneflow": "info", "attack_slot": "special", "trait_slot": "special"}
const B_UPGRADE_ICON := {"brood_size": "brood", "rending": "jaws", "chitin": "armor", "sprinter": "scatter",
	"digestion": "glutton", "witterung": "branch_growth", "geneflow": "dna", "attack_slot": "rudelbiss", "trait_slot": "pack"}
const B_CATEGORY_TONE := {"time": "info", "swarm": "ember", "boss": "danger", "evolution": "special", "biomass": "loot", "runs": "action", "hunt": "ember"}
const B_CATEGORY_ICON := {"time": "clock", "swarm": "mawling_head_color", "boss": "crown", "evolution": "branch_special", "biomass": "biomass", "runs": "trophy", "hunt": "skull"}
const B_SETTING_TONE := {"sound": "info", "vibration": "ember", "colorblind": "special", "music_v1": "loot", "speech": "action"}
const B_DIFF_TONE := ["action", "ember", "danger"]


func _b_text(pos: Vector2, value: String, font_size: int, color: Color = Color.WHITE, align: int = Kit.LEFT, max_w: float = 0.0, font: Font = null) -> float:
	return Kit.text_outlined(self, pos, value, font_size, color, -1, -1, font, align, max_w)


## Figtree label with a thin ink outline (secondary lines on dark wells).
func _b_label(pos: Vector2, value: String, color: Color = S.BRAWL_TEXT_DIM, align: int = Kit.LEFT, max_w: float = 0.0, bold: bool = true) -> float:
	return Kit.text_outlined(self, pos, value, S.T_LABEL, color, 4, 0, S.body_bold_font() if bold else S.body_font(), align, max_w)


func _b_width(value: String, font_size: int, font: Font = null) -> float:
	var face: Font = font if font != null else S.display_font()
	return face.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


func _b_icon(id: String, center: Vector2, side: float, tint: Color = Color.WHITE) -> bool:
	if _icons == null or id == "" or not _icons.has(id):
		return false
	_icons.draw(self, id, Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side)), tint)
	return true


func _b_light(tone: Variant) -> Color:
	return S.brawl_tone(tone)["light"]


## White X with an ink rim (close buttons).
func _b_cross(c: Vector2, r: float) -> void:
	if _b_icon("g_close", c, r * 2.0):
		return
	for pass_i in 2:
		for d in [Vector2(1, 1), Vector2(1, -1)]:
			draw_line(c - d * r, c + d * r, S.BRAWL_INK if pass_i == 0 else Color.WHITE, 15.0 if pass_i == 0 else 8.0, true)


func _b_check(c: Vector2, r: float) -> void:
	if _b_icon("g_check", c, r * 2.0):
		return
	var pts := PackedVector2Array([c + Vector2(-0.62, 0.02) * r, c + Vector2(-0.16, 0.46) * r, c + Vector2(0.66, -0.44) * r])
	draw_polyline(pts, S.BRAWL_INK, maxf(6.0, r * 0.5), true)
	draw_polyline(pts, Color.WHITE, maxf(3.0, r * 0.26), true)


func _b_arrow(c: Vector2, r: float, color: Color = Color.WHITE) -> void:
	if _b_icon("g_arrow_right", c, r * 2.0, color):
		return
	var pts := PackedVector2Array([c + Vector2(0.6, 0.0) * r, c + Vector2(-0.4, -0.72) * r, c + Vector2(-0.4, 0.72) * r])
	draw_colored_polygon(pts, color)
	pts.append(pts[0])
	draw_polyline(pts, S.BRAWL_INK, 4.0, true)


## Round close button on `rect` (hit area from menu.gd).
func _b_close(rect: Rect2) -> void:
	var pressed: bool = menu.is_pressed(rect)
	var c := rect.get_center()
	Kit.round_button(self, c, 40.0, "neutral", pressed)
	_b_cross(Kit.round_label_center(c, 40.0, pressed), 13.0)


## Essence icon + price, centred on `center` (MIDDLE); returns the width.
func _b_price(center: Vector2, cost: int, font_size: int, color: Color = Color.WHITE) -> void:
	var nw := _b_width(Kit.format_int(cost), font_size, S.number_font())
	var icon := font_size * 1.15
	var x := center.x - (icon + 6.0 + nw) * 0.5
	_b_icon("essence", Vector2(x + icon * 0.5, center.y), icon, Color.WHITE if color == Color.WHITE else Color(0.7, 0.7, 0.75))
	Kit.number(self, Vector2(x + icon + 6.0, center.y), cost, font_size, color, Kit.LEFT | Kit.MIDDLE)


## Thin scroll thumb right of a list (only when it scrolls).
func _b_scrollbar(area: Rect2, tone: String) -> void:
	var max_scroll: float = menu._trophy_scroll_max()
	if max_scroll <= 0.0:
		return
	var track := Rect2(area.end.x + 3.0, area.position.y + 8.0, 7.0, area.size.y - 16.0)
	Kit.rrect(self, track, 3.5, Color(S.BRAWL_INK, 0.55))
	var h := maxf(48.0, track.size.y * track.size.y / (track.size.y + max_scroll))
	var thumb := Rect2(track.position.x, track.position.y + (track.size.y - h) * clampf(menu.trophy_scroll / max_scroll, 0.0, 1.0), 7.0, h)
	Kit.rrect(self, thumb, 3.5, _b_light(tone))


# ---------------------------------------------------------------- dispatch

func _b_draw() -> void:
	if menu.tab != "" and not menu.legacy.get("sheet", true) and menu.reward.is_empty():
		_b_sheet()
	if menu.get("settings_open") and not menu.legacy.get("settings", true) and menu.reward.is_empty():
		_b_settings()
	if not menu.legacy.get("reward", true):
		if not menu.reward.is_empty():
			_b_reward()
		pass


## The clipped list child (role "trophy_list"): Brutkammer or trophy rows.
func _b_draw_list() -> void:
	if menu.tab == "upgrades":
		_b_upgrade_rows()
	elif menu.tab == "trophies":
		_b_trophy_rows()


# ---------------------------------------------------------------- sheet frame

func _b_sheet() -> void:
	var tab: String = menu.tab
	var s: Rect2 = menu.sheet_rect()
	var tone: String = B_TAB_TONE.get(tab, "info")
	Kit.card(self, s, tone, "normal", menu.SHEET_HEADER, S.R_XL)
	var cy: float = s.position.y + (12.0 + menu.SHEET_HEADER) * 0.5
	var pc := Vector2(s.position.x + 62, cy)
	Kit.icon_plate(self, pc, 72, "dark")
	_b_icon(B_TAB_ICON.get(tab, ""), Kit.plate_center(pc, 72), 56)
	var close: Rect2 = menu.sheet_close_rect()
	_b_text(Vector2(pc.x + 50, cy + 2), String(TAB_TITLE.get(tab, "")), S.T_TITLE, Color.WHITE, Kit.LEFT | Kit.MIDDLE, close.position.x - pc.x - 70)
	_b_close(close)
	match tab:
		"upgrades":
			_b_scrollbar(menu.upgrade_list_rect(), tone)
		"trophies":
			_b_trophy_summary()
			_b_codex_button()
			_b_scrollbar(menu.trophy_list_rect(), tone)
		"instinct":
			_b_instinct()


# ---------------------------------------------------------------- Brutkammer

func _b_upgrade_rows() -> void:
	var meta = menu.meta
	var origin: Vector2 = menu.upgrade_list_rect().position
	for i in meta.UPGRADE_ORDER.size():
		var row: Rect2 = menu.upgrade_row_rect(i)
		if row.end.y < origin.y - 8 or row.position.y > origin.y + size.y + 8:
			continue
		_b_upgrade_row(String(meta.UPGRADE_ORDER[i]), Rect2(row.position - origin, row.size), menu.upgrade_buy_rect(i), origin)


func _b_upgrade_row(id: String, row: Rect2, buy_menu: Rect2, origin: Vector2) -> void:
	var meta = menu.meta
	var profile = menu.profile
	var u: Dictionary = meta.UPGRADES[id]
	var rank := int(profile.upgrade_rank(id))
	var max_rank := int(u.max)
	var available: bool = profile.upgrade_available(id)
	var maxed := rank >= max_rank
	var cost := int(profile.upgrade_cost(id))
	var affordable: bool = available and not maxed and profile.essence >= cost
	var buy := Rect2(buy_menu.position - origin, buy_menu.size)
	Kit.well(self, row, S.R_M)
	# Icon plate (locked: neutral plate, dimmed icon, lock tag).
	var tone: String = B_UPGRADE_TONE.get(id, "info") if available else "neutral"
	var pc := Vector2(row.position.x + 60, row.get_center().y)
	Kit.icon_plate(self, pc, 88, tone)
	if not _b_icon(B_UPGRADE_ICON.get(id, ""), Kit.plate_center(pc, 88), 70, Color.WHITE if available else Color(0.55, 0.55, 0.62)):
		_upgrade_glyph(id, Kit.plate_center(pc, 88), 26, Color.WHITE)
	if not available:
		var lc := pc + Vector2(30, 30)
		Kit.icon_plate(self, lc, 40, "neutral")
		_b_icon("lock", Kit.plate_center(lc, 40), 26)
	var x := row.position.x + 122
	var right := buy.position.x - 16
	# Rank counter right-aligned on the name line.
	var rank_text := "%d/%d" % [rank, max_rank]
	var rw := 0.0
	if available:
		rw = Kit.number(self, Vector2(right, row.position.y + 34), rank_text, S.T_LABEL, S.BRAWL_TEXT_DIM, Kit.RIGHT | Kit.MIDDLE) + 12.0
	_b_text(Vector2(x, row.position.y + 34), String(u.name).to_upper(), S.T_HEAD, Color.WHITE if available else S.BRAWL_TEXT_DIM, Kit.LEFT | Kit.MIDDLE, right - x - rw)
	if not available:
		var q: Dictionary = meta.quest(String(u.get("requires", "")))
		var reason := "Trophäe: %s – %s" % [String(q.get("name", "")), String(q.get("description", ""))]
		Kit.paragraph(self, Vector2(x, row.position.y + 76), reason, right - x, S.T_LABEL, _b_light("loot"), true, Kit.LEFT, 2, 4)
	else:
		var bar := Rect2(x, row.position.y + 66, 176, 30)
		Kit.bar(self, bar, float(rank) / maxf(1.0, max_rank), "loot", max_rank if max_rank <= 10 else 0)
		var ex := bar.end.x + 14
		var room := right - ex
		var now := _upgrade_effect(id, rank)
		if maxed:
			_b_label(Vector2(ex, bar.get_center().y), now, Color.WHITE, Kit.LEFT | Kit.MIDDLE, room)
		else:
			var nxt := _upgrade_next_short(id, rank + 1)
			var nw := _b_width(nxt, S.T_LABEL)
			var used := _b_label(Vector2(ex, bar.get_center().y), now, Color.WHITE, Kit.LEFT | Kit.MIDDLE, maxf(40.0, room - nw - 38))
			_b_arrow(Vector2(ex + used + 17, bar.get_center().y), 15.0, _b_light("action"))
			_b_text(Vector2(ex + used + 32, bar.get_center().y), nxt, S.T_LABEL, _b_light("action"), Kit.LEFT | Kit.MIDDLE, maxf(30.0, right - (ex + used + 32)))
	# Buy button.
	var pressed: bool = menu.is_pressed(buy_menu)
	if maxed:
		Kit.button(self, buy, "loot", pressed, S.R_L)
		_b_text(Kit.button_label_center(buy, pressed), "MAX", S.T_HEAD, Color.WHITE, Kit.CENTER | Kit.MIDDLE)
	elif not available:
		Kit.button(self, buy, "disabled", false, S.R_L)
		var lc := Kit.button_label_center(buy, false)
		var gw := _b_width("GESPERRT", S.T_LABEL)
		_b_icon("lock", Vector2(lc.x - (gw + 36) * 0.5 + 14, lc.y), 30)
		_b_text(Vector2(lc.x - (gw + 36) * 0.5 + 36, lc.y), "GESPERRT", S.T_LABEL, S.BRAWL_TEXT_DIM, Kit.LEFT | Kit.MIDDLE)
	else:
		Kit.button(self, buy, "action" if affordable else "disabled", pressed, S.R_L)
		_b_price(Kit.button_label_center(buy, pressed), cost, S.T_HEAD, Color.WHITE if affordable else S.BRAWL_TEXT_DIM)


# ---------------------------------------------------------------- Trophäen

func _b_trophy_summary() -> void:
	var r: Rect2 = menu.trophy_summary_rect()
	var done: int = menu.profile.completed_quests.size()
	var total: int = menu.meta.QUESTS.size()
	Kit.well(self, r, S.R_M)
	var pc := Vector2(r.position.x + 48, r.get_center().y)
	Kit.icon_plate(self, pc, 64, "loot")
	_b_icon("trophy", Kit.plate_center(pc, 64), 50)
	var x := pc.x + 48
	x += Kit.number(self, Vector2(x, r.get_center().y), "%d / %d" % [done, total], S.T_HEAD, _b_light("loot"), Kit.LEFT | Kit.MIDDLE) + 12
	x += _b_label(Vector2(x, r.get_center().y + 2), "ERLEDIGT", S.BRAWL_TEXT_DIM, Kit.LEFT | Kit.MIDDLE) + 20
	# The bar takes what is left (the strip is narrower beside the KODEX button).
	var bar_w := minf(300.0, r.end.x - 24 - x)
	if bar_w >= 80.0:
		Kit.bar(self, Rect2(r.end.x - 24 - bar_w, r.get_center().y - 17, bar_w, 34), float(done) / maxf(1.0, total), "loot")


## KODEX button beside the trophy summary: opens the collection sheet.
func _b_codex_button() -> void:
	if menu.codex == null:
		return
	var rect: Rect2 = menu.codex_button_rect()
	var pressed: bool = menu.is_pressed(rect)
	Kit.button(self, rect, "special", pressed, S.R_L)
	var lc := Kit.button_label_center(rect, pressed)
	var p: Vector2i = menu.codex.progress(menu.profile.codex_seen)
	_b_icon("evo_badge", lc + Vector2(-rect.size.x * 0.5 + 44, 0), 58)
	var tx := lc.x - rect.size.x * 0.5 + 82
	_b_text(Vector2(tx, lc.y - 14), "KODEX", S.T_HEAD - 4, Color.WHITE, Kit.LEFT | Kit.MIDDLE, rect.end.x - tx - 12)
	Kit.number(self, Vector2(tx, lc.y + 22), "%d / %d" % [p.x, p.y], S.T_LABEL, Color.WHITE, Kit.LEFT | Kit.MIDDLE, rect.end.x - tx - 12)


func _b_trophy_rows() -> void:
	var pitch: float = menu._trophy_row_height()
	var scroll: float = menu.trophy_scroll
	var order := _trophy_order()
	var first := int(scroll / pitch)
	for k in range(maxi(0, first - 1), mini(order.size(), first + int(size.y / pitch) + 2)):
		var row := Rect2(0, k * pitch - scroll, size.x - 14, pitch - 12)
		if row.end.y < -10 or row.position.y > size.y + 10:
			continue
		_b_trophy_row(order[k], row)


func _b_trophy_row(q: Dictionary, row: Rect2) -> void:
	var profile = menu.profile
	var done: bool = q.id in profile.completed_quests
	var cat := _quest_category(String(q.stat))
	if done:
		Kit.card(self, row, "loot", "normal", 0.0, S.R_M)
	else:
		Kit.well(self, row, S.R_M)
	var pc := Vector2(row.position.x + 64, row.get_center().y)
	var icon: String = B_CATEGORY_ICON.get(cat, "trophy")
	if done:
		Kit.icon_plate(self, pc, 92, "loot")
		_b_icon(icon, Kit.plate_center(pc, 92), 70)
		var cc := pc + Vector2(32, 32)
		Kit.icon_plate(self, cc, 40, "action")
		_b_check(Kit.plate_center(cc, 40), 12)
	else:
		# Not reached yet: dark plate, icon as an ink silhouette.
		Kit.icon_plate(self, pc, 92, "dark")
		if not _b_icon(icon, Kit.plate_center(pc, 92), 70, Color(S.BRAWL_INK, 0.92)):
			Kit.disc(self, Kit.plate_center(pc, 92), 22, S.BRAWL_INK)
	var x := row.position.x + 128
	var inner_right := row.end.x - (22.0 if done else 16.0)
	# Currency reward chip on the name line.
	var chip_left := inner_right
	var r: Dictionary = q.get("reward", {})
	var parts: Array = []
	if int(r.get("essence", 0)) > 0:
		parts.append(["essence", "+%d" % int(r.essence)])
	if int(r.get("crowns", 0)) > 0:
		parts.append(["crown_tooth", "+%d" % int(r.crowns)])
	if not parts.is_empty():
		var cw := 16.0
		for p in parts:
			cw += 34.0 + _b_width(String(p[1]), S.T_LABEL, S.number_font()) + 10.0
		var chip := Rect2(inner_right - cw, row.position.y + (16.0 if done else 12.0), cw, 44)
		Kit.chip(self, chip, "dark")
		var cx := chip.position.x + 10
		for p in parts:
			_b_icon(String(p[0]), Vector2(cx + 16, chip.get_center().y), 34)
			cx += 34 + Kit.number(self, Vector2(cx + 34, chip.get_center().y), String(p[1]), S.T_LABEL, Color.WHITE, Kit.LEFT | Kit.MIDDLE) + 10
		chip_left = chip.position.x - 12
	var ny := row.position.y + (40.0 if done else 36.0)
	_b_text(Vector2(x, ny), String(q.name), S.T_HEAD, _b_light("loot") if done else Color.WHITE, Kit.LEFT | Kit.MIDDLE, chip_left - x)
	var desc_y := Kit.paragraph(self, Vector2(x, ny + 38), String(q.description), inner_right - x, S.T_LABEL, Color.WHITE if done else S.BRAWL_TEXT_DIM, false, Kit.LEFT, 2, 3)
	var bar := Rect2(x, desc_y - 10, 240, 30)
	var progress: Vector2 = profile.quest_progress(q.id)
	Kit.bar(self, bar, clampf(progress.x / maxf(1.0, progress.y), 0.0, 1.0), "loot")
	var used := bar.end.x + 12
	if done:
		used += _b_text(Vector2(used, bar.get_center().y), "ERLEDIGT", S.T_LABEL, _b_light("action"), Kit.LEFT | Kit.MIDDLE)
	else:
		used += Kit.number(self, Vector2(used, bar.get_center().y), menu._progress_text(q, progress), S.T_LABEL, Color.WHITE, Kit.LEFT | Kit.MIDDLE)
	var unlocks: Array = r.get("unlock", [])
	if not unlocks.is_empty():
		var label := String(menu.meta.unlock_label(unlocks[0]))
		if unlocks.size() > 1:
			label += " +%d" % (unlocks.size() - 1)
		var room := inner_right - used - 16
		var tw := minf(_b_width(label, S.T_LABEL, S.body_bold_font()) + 24, room)
		if tw > 80:
			var tag := Rect2(inner_right - tw, bar.get_center().y - 20, tw, 40)
			Kit.chip(self, tag, "special")
			_b_label(tag.get_center(), label, Color.WHITE, Kit.CENTER | Kit.MIDDLE, tw - 16)


# ---------------------------------------------------------------- Urinstinkt

func _b_instinct() -> void:
	var s: Rect2 = menu.sheet_rect()
	var level := int(menu.profile.instinct_level)
	var info: Dictionary = menu.meta.INSTINCT
	var bonus := float(info.get("bonus", 0.01)) * 100.0
	var cx := s.get_center().x
	var top: float = menu._sheet_body_top()
	# Big level plate.
	var pc := Vector2(cx, top + 196)
	Kit.icon_plate(self, pc, 320, "ember")
	var fc := Kit.plate_center(pc, 320)
	_b_text(fc + Vector2(0, -84), "STUFE", S.T_HEAD, Color.WHITE, Kit.CENTER | Kit.MIDDLE)
	Kit.number(self, fc + Vector2(0, 8), level, 110, Color.WHITE, Kit.CENTER | Kit.MIDDLE, 250)
	var circle := level / 10
	var filled := level % 10
	_b_label(fc + Vector2(0, 94), "KREIS %d" % (circle + 1), Color.WHITE, Kit.CENTER | Kit.MIDDLE)
	# Progress of the current circle (ten segments).
	var bar := Rect2(cx - 300, top + 400, 600, 42)
	Kit.bar(self, bar, filled / 10.0, "ember", 10)
	_b_label(Vector2(cx, bar.end.y + 26), "Noch %d %s bis Kreis %d" % [10 - filled, "Stufe" if 10 - filled == 1 else "Stufen", circle + 2], S.BRAWL_TEXT_DIM, Kit.CENTER | Kit.MIDDLE)
	# Current bonus -> next level.
	var ty := top + 510
	var tw := (s.size.x - 48 - 72) * 0.5
	var cur := Rect2(s.position.x + 24, ty, tw, 150)
	var nxt := Rect2(cur.end.x + 72, ty, tw, 150)
	for pair in [[cur, "AKTUELL", level, Color.WHITE], [nxt, "STUFE %d" % (level + 1), level + 1, _b_light("action")]]:
		var r: Rect2 = pair[0]
		Kit.well(self, r, S.R_M)
		_b_label(Vector2(r.get_center().x, r.position.y + 30), String(pair[1]), S.BRAWL_TEXT_DIM, Kit.CENTER | Kit.MIDDLE)
		var v := roundi(bonus * int(pair[2]))
		_b_text(Vector2(r.get_center().x, r.position.y + 76), "+%d %% Schaden" % v, 34, pair[3], Kit.CENTER | Kit.MIDDLE, r.size.x - 24)
		_b_text(Vector2(r.get_center().x, r.position.y + 118), "+%d %% Biomasse" % v, 34, pair[3], Kit.CENTER | Kit.MIDDLE, r.size.x - 24)
	var ac := Vector2(cur.end.x + 36, ty + 75)
	Kit.icon_plate(self, ac, 56, "action")
	_b_arrow(Kit.plate_center(ac, 56) + Vector2(2, 0), 22.0)
	# STÄRKEN.
	var cost := int(menu._instinct_cost())
	var buy: Rect2 = menu.instinct_buy_rect()
	var affordable: bool = menu.profile.essence >= cost
	var pressed: bool = menu.is_pressed(buy)
	Kit.button(self, buy, "action" if affordable else "disabled", pressed, S.R_XL)
	var lc := Kit.button_label_center(buy, pressed)
	var col := Color.WHITE if affordable else S.BRAWL_TEXT_DIM
	var label_w := _b_width("STÄRKEN", S.T_TITLE)
	var price_w := _b_width(Kit.format_int(cost), S.T_HEAD, S.number_font()) + 50
	var x0 := lc.x - (label_w + 28 + price_w) * 0.5
	_b_text(Vector2(x0, lc.y), "STÄRKEN", S.T_TITLE, col, Kit.LEFT | Kit.MIDDLE)
	_b_price(Vector2(x0 + label_w + 28 + price_w * 0.5, lc.y), cost, S.T_HEAD, col)
	var note_y := buy.end.y + 40
	if not affordable:
		_b_label(Vector2(cx, note_y), "Noch %s Essenz" % Kit.format_int(cost - int(menu.profile.essence)), _b_light("loot"), Kit.CENTER | Kit.MIDDLE)
		note_y += 40
	Kit.paragraph(self, Vector2(s.position.x + 60, note_y + 10), "Urinstinkt hat keine Obergrenze. Jede Stufe kostet %d Essenz mehr – lohnt sich, wenn die Brutkammer ausgebaut ist." % int(info.get("step", 50)), s.size.x - 120, S.T_BODY, S.BRAWL_TEXT_DIM, false, Kit.CENTER, 3)


# ---------------------------------------------------------------- Einstellungen

func _b_settings() -> void:
	var p: Rect2 = menu.settings_panel_rect()
	Kit.dim(self, Rect2(Vector2.ZERO, size), 0.78)
	Kit.panel(self, p, "dark", S.R_XL, S.STROKE_L)
	var rib := Rect2(p.get_center().x - 230, p.position.y - 42, 460, 88)
	Kit.ribbon(self, rib, "info")
	_b_text(rib.get_center() + Vector2(0, -2), "EINSTELLUNGEN", S.T_TITLE, Color.WHITE, Kit.CENTER | Kit.MIDDLE, rib.size.x - 40)
	_b_close(menu.settings_close_rect())
	for i in menu.SETTINGS.size():
		var entry: Array = menu.SETTINGS[i]
		var row: Rect2 = menu.settings_row_rect(i)
		var key := String(entry[0])
		var on: bool = menu.setting(key)
		var pressed: bool = menu.is_pressed(row)
		Kit.well(self, row, S.R_M)
		var pc := Vector2(row.position.x + 56, row.get_center().y)
		Kit.icon_plate(self, pc, 80, B_SETTING_TONE.get(key, "info") if on else "neutral")
		_setting_glyph(key, Kit.plate_center(pc, 80), Color.WHITE, on)
		var sw := Rect2(row.end.x - 20 - 156, row.get_center().y - 32, 156, 64)
		var x := row.position.x + 112
		_b_text(Vector2(x, row.position.y + 32), String(entry[1]), S.T_HEAD, Color.WHITE if on else S.BRAWL_TEXT_DIM, Kit.LEFT | Kit.MIDDLE, sw.position.x - x - 16)
		Kit.paragraph(self, Vector2(x, row.position.y + 70), String(entry[2]), sw.position.x - x - 16, S.T_LABEL, S.BRAWL_TEXT_DIM, false, Kit.LEFT, 2, 3)
		_b_switch(sw, on, pressed)
	# UI style: three segment buttons.
	var sr: Rect2 = menu.settings_skin_row_rect()
	Kit.well(self, sr, S.R_M)
	_b_text(Vector2(sr.position.x + 24, sr.position.y + 32), "UI-STIL", S.T_HEAD, Color.WHITE, Kit.LEFT | Kit.MIDDLE)
	_b_label(Vector2(sr.end.x - 24, sr.position.y + 34), "wirkt sofort, auch im Run", S.BRAWL_TEXT_DIM, Kit.RIGHT | Kit.MIDDLE)
	var current: String = menu.ui_skin()
	for k in menu.UI_SKINS.size():
		var id: String = menu.UI_SKINS[k]
		var rect: Rect2 = menu.settings_skin_rect(k)
		var pressed: bool = menu.is_pressed(rect)
		var active := id == current
		Kit.button(self, rect, "action" if active else "neutral", pressed, S.R_L)
		var lc := Kit.button_label_center(rect, pressed)
		if active:
			var nw := _b_width(String(menu.UI_SKIN_NAMES[id]), S.T_BODY)
			_b_check(Vector2(lc.x - (nw + 34) * 0.5 + 10, lc.y), 14)
			_b_text(Vector2(lc.x - (nw + 34) * 0.5 + 34, lc.y), String(menu.UI_SKIN_NAMES[id]), S.T_BODY, Color.WHITE, Kit.LEFT | Kit.MIDDLE, rect.size.x - 60)
		else:
			_b_text(lc, String(menu.UI_SKIN_NAMES[id]), S.T_BODY, Color.WHITE, Kit.CENTER | Kit.MIDDLE, rect.size.x - 24)
	# Etappe 24: every one-time tip shows again (profile.seen_tips cleared).
	var tips: Rect2 = menu.settings_tips_rect()
	var tips_pressed: bool = menu.is_pressed(tips)
	Kit.button(self, tips, "neutral", tips_pressed, S.R_L)
	var tc := Kit.button_label_center(tips, tips_pressed)
	var tw := _b_width("TIPPS ZURÜCKSETZEN", S.T_BODY)
	_b_text(Vector2(tc.x - (tw + 50) * 0.5 + 50, tc.y), "TIPPS ZURÜCKSETZEN", S.T_BODY, Color.WHITE, Kit.LEFT | Kit.MIDDLE, tips.size.x - 90)
	_icon(["reroll"], Rect2(Vector2(tc.x - (tw + 50) * 0.5 - 4, tc.y - 20), Vector2(40, 40)))
	Kit.paragraph(self, Vector2(p.position.x + 40, tips.end.y + 40), "Farbenblind: Gefahren zusätzlich mit Muster und Kontur.", p.size.x - 80, S.T_LABEL, S.BRAWL_TEXT_DIM, false, Kit.CENTER, 2)


## Pill toggle: on = action with the knob right, off = neutral with the knob left.
func _b_switch(rect: Rect2, on: bool, pressed: bool) -> void:
	var r := rect
	if pressed:
		r = Rect2(rect.position + Vector2(0, 3), rect.size)
	Kit.pill(self, r, "action" if on else "neutral")
	var kr := r.size.y * 0.5 - 7.0
	var kc := Vector2(r.end.x - kr - 7.0 if on else r.position.x + kr + 7.0, r.get_center().y)
	Kit.disc(self, kc + Vector2(0, 3), kr, S.BRAWL_INK_SOFT)
	Kit.disc(self, kc, kr, S.BRAWL_INK)
	Kit.disc(self, kc, kr - 3.0, Color.WHITE)
	Kit.fade_disc(self, kc, kr - 3.0, S.BRAWL_TEXT_DIM, 0.55, 1.0)
	var free_c := Vector2(r.position.x + (r.size.x - kr * 2.0 - 7.0) * 0.5 if on else r.end.x - (r.size.x - kr * 2.0 - 7.0) * 0.5, r.get_center().y)
	_b_text(free_c, "AN" if on else "AUS", S.T_LABEL, Color.WHITE, Kit.CENTER | Kit.MIDDLE)


# ---------------------------------------------------------------- Belohnung

func _b_reward() -> void:
	var reward: Dictionary = menu.reward
	var stats: Dictionary = menu.reward_stats
	var meta = menu.meta
	var cx := size.x * 0.5
	var appear := _ease(0.0, 0.35)
	Kit.dim(self, Rect2(Vector2.ZERO, size), 0.86 * appear)
	var button: Rect2 = menu.reward_button_rect()
	var share: Rect2 = menu.share_button_rect()
	var oy := (1.0 - appear) * 60.0
	var panel := Rect2(34, 176 + oy, size.x - 68, button.end.y + 28 - 176)
	Kit.panel(self, panel, "dark", S.R_XL, S.STROKE_L)
	# Title ribbon: pops in slightly larger, then settles.
	var pop := 1.0 + 0.08 * (1.0 - _ease(0.15, 0.4))
	var rw := 520.0 * pop
	var rib := Rect2(cx - rw * 0.5, panel.position.y - 50, rw, 96)
	Kit.ribbon(self, rib, "ember")
	_b_text(rib.get_center() + Vector2(0, -2), "RUN BEENDET", S.T_TITLE, Color.WHITE, Kit.CENTER | Kit.MIDDLE, rib.size.x - 40)
	var strain: Dictionary = meta.STRAINS.get(String(stats.get("strain_id", "")), {})
	var diff_index := clampi(int(stats.get("difficulty", 0)), 0, meta.DIFFICULTIES.size() - 1)
	var sub := "%s  ·  %s" % [String(strain.get("name", "")).to_upper(), String(meta.DIFFICULTIES[diff_index].name).to_upper()]
	var daily: Dictionary = reward.get("daily", {})
	if not daily.is_empty():
		sub = "TAGES-BRUT  ·  " + sub + ("  ·  TAGESREKORD" if daily.get("new_best", false) else "")
	var y := panel.position.y + 90
	_b_text(Vector2(cx, y), sub, S.T_BODY, _b_light(Color(strain.get("tint", "#ff6a1f"))), Kit.CENTER | Kit.MIDDLE, panel.size.x - 60)
	# Survival time counts up.
	var seconds := float(stats.get("seconds", 0.0)) * _ease(0.25, 1.0)
	_b_label(Vector2(cx, y + 50), "ÜBERLEBT", S.BRAWL_TEXT_DIM, Kit.CENTER | Kit.MIDDLE)
	Kit.number(self, Vector2(cx, y + 116), "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60], 96, Color.WHITE, Kit.CENTER | Kit.MIDDLE)
	# Stat wells.
	var tiles := [["MAX. SCHWARM", float(stats.get("peak_population", 0)), "ember", "mawling_head_color"],
		["KILLS", float(stats.get("kills", 0)), "info", "skull"], ["BOSSE", float(stats.get("bosses", 0)), "danger", "crown"]]
	var ty := y + 190
	var tw := (panel.size.x - 48 - 24) / 3.0
	for i in tiles.size():
		var tile := Rect2(panel.position.x + 24 + i * (tw + 12), ty, tw, 112)
		Kit.well(self, tile, S.R_M)
		var pc := Vector2(tile.position.x + 50, tile.get_center().y)
		Kit.icon_plate(self, pc, 72, tiles[i][2])
		_b_icon(String(tiles[i][3]), Kit.plate_center(pc, 72), 54)
		var v := roundi(float(tiles[i][1]) * _ease(0.45 + i * 0.1, 1.0))
		var tx := pc.x + 48
		Kit.number(self, Vector2(tx, tile.position.y + 44), v, S.T_HEAD, _b_light(tiles[i][2]), Kit.LEFT | Kit.MIDDLE, tile.end.x - tx - 12)
		_b_label(Vector2(tx, tile.position.y + 82), String(tiles[i][0]), S.BRAWL_TEXT_DIM, Kit.LEFT | Kit.MIDDLE, tile.end.x - tx - 12)
	# Loot header.
	var ly := ty + 158
	var hw := _b_text(Vector2(cx, ly), "BEUTE FÜR DIE BRUT", S.T_BODY, _b_light("loot"), Kit.CENTER | Kit.MIDDLE) * 0.5
	for sgn in [-1.0, 1.0]:
		var a := Vector2(cx + sgn * (hw + 18), ly)
		var b := Vector2(cx + sgn * (hw + 170), ly)
		draw_line(a, b, S.BRAWL_INK, 7.0, true)
		draw_line(a, b, _b_light("loot"), 3.0, true)
	var loot := [
		{"tone": "special", "value": int(reward.get("essence", 0)), "label": "ESSENZ", "icon": "essence",
			"split": [int(reward.get("run_essence", 0)), int(reward.get("quest_essence", 0))]},
		{"tone": "loot", "value": int(reward.get("crowns", 0)), "label": "KÖNIGSZÄHNE", "icon": "crown_tooth",
			"split": [int(reward.get("run_crowns", 0)), int(reward.get("quest_crowns", 0))]},
	]
	var lw := (panel.size.x - 48 - 16) * 0.5
	var loot_y := ly + 34
	for i in loot.size():
		var L: Dictionary = loot[i]
		var tile := Rect2(panel.position.x + 24 + i * (lw + 16), loot_y, lw, 170)
		var count_e := _ease(0.9 + i * 0.15, 1.2)
		var landed := count_e >= 1.0
		Kit.card(self, tile, L.tone, "selected" if landed else "normal", 0.0, S.R_L)
		var body := Kit.card_inner(tile)
		var pc := Vector2(body.position.x + 56, body.get_center().y)
		var burst := 1.0 + (0.14 * (1.0 - _ease(2.1 + i * 0.15, 0.4)) if landed else 0.0)
		Kit.icon_plate(self, pc, 96 * burst, L.tone)
		_b_icon(String(L.icon), Kit.plate_center(pc, 96 * burst), 76 * burst)
		var tx := pc.x + 64
		var value := roundi(float(L.value) * count_e)
		Kit.number(self, Vector2(tx, body.position.y + 44), "+" + Kit.format_int(value), S.T_TITLE, Color.WHITE, Kit.LEFT | Kit.MIDDLE, body.end.x - tx - 8)
		_b_text(Vector2(tx, body.position.y + 90), String(L.label), S.T_LABEL, _b_light(L.tone), Kit.LEFT | Kit.MIDDLE, body.end.x - tx - 8)
		var split: Array = L.split
		if split[1] > 0:
			var parts := "Run +%d · Trophäe +%d" % [split[0], split[1]]
			if _b_width(parts, S.T_LABEL, S.body_bold_font()) > body.end.x - tx - 8:
				parts = "+%d Run · +%d Tr." % [split[0], split[1]]
			_b_label(Vector2(tx, body.position.y + 124), parts, S.BRAWL_TEXT_DIM, Kit.LEFT | Kit.MIDDLE, body.end.x - tx - 8)
	# New trophies and unlocks, staggered.
	var list_top := loot_y + 206
	var bottom := share.position.y - 20
	var new_quests: Array = reward.get("new_quests", [])
	if new_quests.is_empty():
		Kit.paragraph(self, Vector2(panel.position.x + 40, list_top + 40), "Keine neuen Trophäen – die nächste Jagd wartet.", panel.size.x - 80, S.T_BODY, S.BRAWL_TEXT_DIM, false, Kit.CENTER, 2)
		var next: Dictionary = menu._next_quest()
		if not next.is_empty():
			_b_text(Vector2(cx, list_top + 100), "Nächstes Ziel: %s" % next.name, S.T_LABEL, _b_light("special"), Kit.CENTER | Kit.MIDDLE, panel.size.x - 80)
	else:
		var unlocked: Array = reward.get("unlocked", [])
		_b_text(Vector2(panel.position.x + 30, list_top), "NEUE TROPHÄEN  %d" % new_quests.size(), S.T_BODY, _b_light("special"), Kit.LEFT | Kit.MIDDLE)
		if not unlocked.is_empty():
			_b_text(Vector2(panel.end.x - 30, list_top), "%d FREIGESCHALTET" % unlocked.size(), S.T_BODY, _b_light("loot"), Kit.RIGHT | Kit.MIDDLE)
		var with_unlock: Array = []
		var plain: Array = []
		for id in new_quests:
			var q: Dictionary = meta.quest(String(id))
			if q.is_empty():
				continue
			if q.get("reward", {}).get("unlock", []).is_empty():
				plain.append(q)
			else:
				with_unlock.append(q)
		var cy := list_top + 30
		var shown := 0
		var total := with_unlock.size() + plain.size()
		var left := panel.position.x + 24
		var width := panel.size.x - 48
		for k in with_unlock.size():
			var need := 84.0 + (0.0 if total - shown == 1 else 40.0)
			if cy + need > bottom:
				break
			_b_unlock_row(Rect2(left, cy, width, 76), with_unlock[k], shown)
			cy += 84
			shown += 1
		var col := 0
		for k in plain.size():
			if col == 0 and cy + 64 + (0.0 if total - shown <= 2 else 40.0) > bottom:
				break
			var cw := (width - 12) * 0.5
			_b_trophy_chip(Rect2(left + col * (cw + 12), cy, cw, 60), plain[k], shown)
			shown += 1
			col += 1
			if col == 2:
				col = 0
				cy += 68
		if col == 1:
			cy += 68
		if shown < total:
			_b_label(Vector2(cx, cy + 18), "+ %d weitere in TROPHÄEN" % (total - shown), Color(_b_light("special"), _ease(2.0 + shown * 0.16, 0.3)), Kit.CENTER | Kit.MIDDLE)
	# KARTE TEILEN (info) + WEITER (action) on the menu rectangles.
	var busy: bool = menu.is_sharing()
	var sp: bool = menu.is_pressed(share) or busy
	Kit.button(self, share, "info", sp, S.R_L)
	var sl := Kit.button_label_center(share, sp)
	var ic := Vector2(share.position.x + 58, sl.y)
	Kit.icon_plate(self, ic, 64, "dark")
	_share_glyph(Kit.plate_center(ic, 64), 17, Color.WHITE)
	var tx := share.position.x + 104
	if busy:
		_b_text(Vector2(tx, sl.y), "WIRD GEMALT", S.T_LABEL, Color.WHITE, Kit.LEFT | Kit.MIDDLE, share.end.x - tx - 14)
	else:
		_b_text(Vector2(tx, sl.y - 17), "KARTE", S.T_BODY, Color.WHITE, Kit.LEFT | Kit.MIDDLE)
		_b_text(Vector2(tx, sl.y + 17), "TEILEN", S.T_BODY, Color.WHITE, Kit.LEFT | Kit.MIDDLE)
	var wp: bool = menu.is_pressed(button)
	Kit.button(self, button, "action", wp, S.R_XL)
	_b_text(Kit.button_label_center(button, wp), "WEITER", S.T_TITLE, Color.WHITE, Kit.CENTER | Kit.MIDDLE, button.size.x - 40)


func _b_unlock_row(rect: Rect2, q: Dictionary, index: int) -> void:
	var a := _stagger(index)
	if a <= 0.0:
		return
	var r := Rect2(rect.position + Vector2((1.0 - a) * 60.0, 0), rect.size)
	var unlocks: Array = q.reward.get("unlock", [])
	var labels: Array = []
	for token in unlocks:
		labels.append(String(menu.meta.unlock_label(token)))
	Kit.well(self, r, S.R_M)
	var pc := Vector2(r.position.x + 40, r.get_center().y)
	Kit.icon_plate(self, pc, 60, "loot")
	var kind := String(unlocks[0]).split(":")[0]
	var icon: String = {"strain": "mawling_head_color", "difficulty": "skull", "mutation": "dna", "upgrade": "brood"}.get(kind, "trophy")
	_b_icon(icon, Kit.plate_center(pc, 60), 46)
	Kit.badge(self, Vector2(r.end.x - 52, r.get_center().y), "NEU", "danger", S.T_LABEL)
	var x := pc.x + 44
	var room := r.end.x - 110 - x
	_b_text(Vector2(x, r.position.y + 26), " · ".join(labels), S.T_LABEL, _b_light("loot"), Kit.LEFT | Kit.MIDDLE, room)
	_b_label(Vector2(x, r.position.y + 54), "%s%s" % [q.name, _currency_suffix(q)], S.BRAWL_TEXT_DIM, Kit.LEFT | Kit.MIDDLE, room)


func _b_trophy_chip(rect: Rect2, q: Dictionary, index: int) -> void:
	var a := _stagger(index)
	if a <= 0.0:
		return
	var r := Rect2(rect.position + Vector2((1.0 - a) * 60.0, 0), rect.size)
	Kit.well(self, r, S.R_M)
	var pc := Vector2(r.position.x + 32, r.get_center().y)
	Kit.icon_plate(self, pc, 44, "action")
	_b_check(Kit.plate_center(pc, 44), 12)
	var rw: Dictionary = q.get("reward", {})
	var right := r.end.x - 12
	if int(rw.get("crowns", 0)) > 0:
		right -= Kit.number(self, Vector2(right, r.get_center().y), "+%d" % int(rw.crowns), S.T_LABEL, Color.WHITE, Kit.RIGHT | Kit.MIDDLE)
		_b_icon("crown_tooth", Vector2(right - 16, r.get_center().y), 30)
		right -= 38
	if int(rw.get("essence", 0)) > 0:
		right -= Kit.number(self, Vector2(right, r.get_center().y), "+%d" % int(rw.essence), S.T_LABEL, Color.WHITE, Kit.RIGHT | Kit.MIDDLE)
		_b_icon("essence", Vector2(right - 16, r.get_center().y), 30)
		right -= 38
	_b_text(Vector2(pc.x + 32, r.get_center().y), String(q.name), S.T_LABEL, Color.WHITE, Kit.LEFT | Kit.MIDDLE, right - pc.x - 40)


# ---------------------------------------------------------------- toast

func _b_toast() -> void:
	var text: String = menu.toast
	var remaining: float = menu.toast_time
	var fade_in := clampf((1.8 - remaining) / 0.15, 0.0, 1.0)
	var bad := text.begins_with("Nicht") or text.begins_with("Gesperrt") or text.begins_with("Noch")
	var w := minf(size.x - 60, _b_width(text, S.T_BODY, S.body_bold_font()) + 120)
	# Kit shapes are opaque, so the toast slides in and out instead of fading.
	var slide := (1.0 - fade_in) * 40.0 + (1.0 - clampf(remaining / 0.3, 0.0, 1.0)) * 40.0
	# Above the tab dock; over the reward overlay at the top edge.
	var y := 30.0 - slide if not menu.reward.is_empty() else 1398.0 + slide
	var rect := Rect2(size.x * 0.5 - w * 0.5, y, w, 72)
	Kit.pill(self, rect, "dark")
	var pc := Vector2(rect.position.x + 40, rect.get_center().y)
	Kit.icon_plate(self, pc, 52, "danger" if bad else "action")
	if bad:
		_b_text(Kit.plate_center(pc, 52), "!", S.T_HEAD, Color.WHITE, Kit.CENTER | Kit.MIDDLE)
	else:
		_b_check(Kit.plate_center(pc, 52), 14)
	_b_text(Vector2(pc.x + 42, rect.get_center().y), text, S.T_BODY, Color.WHITE, Kit.LEFT | Kit.MIDDLE, rect.end.x - pc.x - 64, S.body_bold_font())
