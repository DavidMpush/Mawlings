extends Control

# Mutation choice overlay (stage 04). Replaces touch_controls legacy["mutations"].
# Draw-only: input stays in touch_controls.gd. Every card sits exactly on
# hud._mutation_rect(slot), banish/reroll/skip on the matching hud rects, so the
# hit areas never drift from what the player sees. All data comes from the parent.
#
# Cards are child Controls (CardView) so the intro and the pick flash can use
# position/scale/modulate without touching the drawing code.
#
# Stage 07 (performance): the screen repaints only while it fades or when its
# values change, a card only when its content changes (the pulsing rank
# diamond: 20 Hz). Shrink-to-fit text is scaled from one rasterised size
# instead of trying every integer size.

const UI := preload("res://scripts/ui/ui_style.gd")
const ICONS_PATH := "res://scripts/ui/ui_icons.gd"
const FRAMES_PATH := "res://scripts/ui/ui_frames.gd"
const FORMS_PATH := "res://scripts/attack_forms.gd"

const DIM_IN := 0.2
const DIM_OUT := 0.3
const INTRO := 0.34
const STAGGER := 0.085
const FLASH := 0.45
const TOP_CLEAR := 124.0   # the status bar stays readable above the dimmer
const MIN_TEXT := 22        # stage 06: nothing on this screen below 22 px (900 grid)

# Category drives frame and name colour (stage 04 rules).
const CATEGORY_OF := {
	"jaws": "attack", "pack": "attack", "rudelbiss": "attack", "saeurespucker": "attack",
	"brood": "growth", "glutton": "growth",
	"scatter": "special", "sporenwolke": "special", "aetzflut": "special", "meute": "special",
	"armor": "protect", "stachelruecken": "protect",
	"graeber": "attack", "blitzbiss": "attack", "erdbeben": "attack", "sturmrudel": "attack",
	"brutsack": "growth", "regeneration": "protect", "dornenhaut": "protect",
}
# Short effect wording per trait; the numbers are parsed from evolution.gd.
const EFFECT_LABEL := {
	"jaws": "BISSSCHADEN", "brood": "ERNTETEMPO", "glutton": "BIOMASSE PRO KILL",
	"pack": "SCHADEN BEI RALLY", "scatter": "VERLUSTE OHNE RALLY", "armor": "VERLUSTE",
	"dornenhaut": "RÜCKSCHADEN",
}
# Traits whose effect is not a percentage: shown as rank-specific text instead.
const RANK_TEXT := {
	"regeneration": ["+1 LP JE 12 KILLS / 30 S", "+1 LP JE 9 KILLS / 25 S", "+1 LP JE 6 KILLS / 20 S"],
}
const ROMAN := ["I", "II", "III", "IV", "V"]


class CardView extends Control:
	var screen: Control
	var slot := 0
	var entry: Array = []
	var rank := 0
	var flash := 0.0
	var key: Variant = null

	# Repaints when `new_key` differs from the last painted one.
	func refresh(new_key: Variant) -> void:
		if typeof(new_key) != typeof(key) or new_key != key:
			key = new_key
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if screen != null and not entry.is_empty():
			screen.draw_card(self, slot, entry, rank, flash)


var icons: Script
var frames: Script
# Shared SVG frame kit (ui_frames.gd) when present; false = own polygon frames.
var use_frame_kit := true
var _forms: Dictionary = {}
var _cards: Array = []
var _flash_card: CardView
var _slot_ids: Array = ["", "", ""]
var _slot_start: Array = [0.0, 0.0, 0.0]
var _snapshot: Array = []
var _was_open := false
var _open_time := -10.0
var _close_time := -10.0
var _flash_time := -10.0
var _spaced: FontVariation
var _screen_key: Variant = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_modules()
	for slot in 3:
		var card := CardView.new()
		card.screen = self
		card.slot = slot
		card.visible = false
		add_child(card)
		_cards.append(card)
	_flash_card = CardView.new()
	_flash_card.screen = self
	_flash_card.visible = false
	add_child(_flash_card)
	var hud := get_parent()
	if hud != null and hud.has_signal("mutation_chosen"):
		hud.connect("mutation_chosen", _on_chosen)


func _load_modules() -> void:
	if icons == null and ResourceLoader.exists(ICONS_PATH):
		icons = load(ICONS_PATH)
	if frames == null and ResourceLoader.exists(FRAMES_PATH):
		frames = load(FRAMES_PATH)
	if _forms.is_empty() and ResourceLoader.exists(FORMS_PATH):
		var script: Script = load(FORMS_PATH)
		if script != null:
			var map: Variant = script.get_script_constant_map().get("FORMS")
			if map is Dictionary:
				_forms = map


func _now() -> float:
	return Time.get_ticks_msec() * 0.001


func _hud() -> Control:
	return get_parent() as Control


func _evolution() -> RefCounted:
	var hud := _hud()
	return hud.get("evolution") if hud != null else null


func _open() -> bool:
	var hud := _hud()
	var evo := _evolution()
	if hud == null or evo == null or evo.offers.is_empty():
		return false
	return not bool(hud.get("extinct")) and not bool(hud.get("paused"))


static func _ease(t: float) -> float:
	var k := 1.0 - clampf(t, 0.0, 1.0)
	return 1.0 - k * k * k


# ------------------------------------------------------------------ update

func _process(_delta: float) -> void:
	var now := _now()
	var open := _open()
	if open and not _was_open:
		_open_time = now
		_slot_ids = ["", "", ""]
	elif not open and _was_open:
		_close_time = now
	_was_open = open
	var hud := _hud()
	if hud != null and size != hud.size:
		position = Vector2.ZERO
		size = hud.size
	if open:
		var evo := _evolution()
		var offers: Array = evo.offers
		var changed := 0
		var fresh := now - _open_time < 0.05
		_snapshot = []
		for slot in 3:
			var card: CardView = _cards[slot]
			if slot >= offers.size():
				_slot_ids[slot] = ""
				card.visible = false
				continue
			var entry: Array = offers[slot]
			var id := str(entry[0])
			if id != _slot_ids[slot]:
				_slot_ids[slot] = id
				_slot_start[slot] = now + (0.08 if fresh else 0.0) + changed * STAGGER
				changed += 1
			var rank: int = evo.rank(id)
			_snapshot.append([entry, rank])
			var rect: Rect2 = hud._mutation_rect(slot)
			var e := _ease((now - _slot_start[slot]) / INTRO)
			card.visible = true
			card.entry = entry
			card.rank = rank
			card.flash = 0.0
			card.size = rect.size
			card.pivot_offset = rect.size * 0.5
			card.position = rect.position + Vector2((1.0 - e) * 64.0, (1.0 - e) * 14.0)
			card.scale = Vector2.ONE * lerpf(0.96, 1.0, e)
			card.modulate = Color(1, 1, 1, e)
			card.refresh(_card_key(hud, evo, slot, entry, rank, 0.0))
	else:
		for card in _cards:
			card.visible = false
	var ft := (now - _flash_time) / FLASH
	_flash_card.visible = ft < 1.0 and hud != null
	if _flash_card.visible:
		var rect: Rect2 = hud._mutation_rect(_flash_card.slot)
		var e := _ease(ft)
		_flash_card.size = rect.size
		_flash_card.pivot_offset = rect.size * 0.5
		_flash_card.position = rect.position
		_flash_card.scale = Vector2.ONE * (1.0 + 0.06 * e)
		_flash_card.flash = 1.0 - e
		_flash_card.modulate = Color(1, 1, 1, 1.0 - e * e)
		_flash_card.refresh(_card_key(hud, _evolution(), _flash_card.slot, _flash_card.entry, _flash_card.rank, _flash_card.flash))
	var key: Variant = _screen_state(now, open)
	if key == null or typeof(key) != typeof(_screen_key) or key != _screen_key:
		queue_redraw()
	_screen_key = key


# Everything a card shows; the offered rank's diamond pulses (20 Hz).
func _card_key(hud: Control, evo: RefCounted, slot: int, entry: Array, rank: int, flash: float) -> Array:
	var key: Array = [slot, entry, rank, flash, use_frame_kit, int(_now() * 20.0) if rank < 3 else 0]
	if hud != null:
		key.append_array([hud._count("banishes"), hud._banish_rect(slot), hud._mutation_rect(slot).size])
	if evo != null:
		key.append_array([evo.slots_used("attack"), evo.slots_used("trait"), evo.slot_limit("attack"), evo.slot_limit("trait"), str(evo.ranks), str(evo.evolutions)])
	return key


# null while the dimmer/title animate, else the values the screen shows.
func _screen_state(now: float, open: bool) -> Variant:
	if open and now - _open_time < maxf(DIM_IN, 0.3) + 0.05:
		return null
	if not open and now - _close_time < DIM_OUT + 0.05:
		return null
	if not open:
		return ["closed", size]
	var hud := _hud()
	var evo := _evolution()
	return ["open", size, hud._count("rerolls"), hud._count("skips"), int(evo.level), evo.offers.size()]


func _on_chosen(slot: int) -> void:
	if slot < 0 or slot >= _snapshot.size():
		return
	_flash_card.slot = slot
	_flash_card.entry = _snapshot[slot][0]
	_flash_card.rank = _snapshot[slot][1]
	_flash_time = _now()
	# The picked card must not replay its intro under the flash.
	_cards[slot].visible = false


# ------------------------------------------------------------------ screen

func _draw() -> void:
	var now := _now()
	var open := _open()
	var dim := _ease((now - _open_time) / DIM_IN) if open else 1.0 - _ease((now - _close_time) / DIM_OUT)
	if dim <= 0.0:
		return
	_draw_dimmer(dim)
	if not open:
		return
	var hud := _hud()
	var evo := _evolution()
	_draw_title(evo, _ease((now - _open_time) / 0.3))
	var rerolls: int = hud._count("rerolls")
	var skips: int = hud._count("skips")
	if rerolls > 0:
		_draw_button(hud._reroll_rect(), "reroll", "NEU WÜRFELN", rerolls, UI.CYAN)
	if skips > 0:
		_draw_button(hud._skip_rect(), "skip", "ÜBERSPRINGEN", skips, UI.BONE)
	var last: Rect2 = hud._mutation_rect(evo.offers.size() - 1)
	var hint_y := last.end.y + 58.0
	if rerolls > 0 or skips > 0:
		hint_y = (hud._reroll_rect() if rerolls > 0 else hud._skip_rect()).end.y + 50.0
	_text(self, "KARTE ANTIPPEN ZUM WÄHLEN", Vector2(size.x * 0.5, hint_y), MIN_TEXT, Color(UI.TEXT_DIM, 0.85), 1, 5)


func _draw_dimmer(amount: float) -> void:
	var top := Color(UI.DIM, UI.DIM.a * 0.15 * amount)
	var body := Color(UI.DIM, UI.DIM.a * amount)
	var deep := Color(UI.DIM.darkened(0.3), minf(1.0, UI.DIM.a * 1.12) * amount)
	var w := size.x
	var h := size.y
	draw_rect(Rect2(0, 0, w, TOP_CLEAR), top)
	_vgrad(Rect2(0, TOP_CLEAR, w, 60), top, body)
	_vgrad(Rect2(0, TOP_CLEAR + 60, w, h * 0.5 - TOP_CLEAR - 60), body, deep)
	_vgrad(Rect2(0, h * 0.5, w, h * 0.5), deep, body)


func _vgrad(r: Rect2, a: Color, b: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), PackedColorArray([a, a, b, b]))


func _draw_title(evo: RefCounted, appear: float) -> void:
	var cx := size.x * 0.5
	var first: Rect2 = _hud()._mutation_rect(0)
	var base_y := first.position.y - 92.0 - (1.0 - appear) * 16.0
	var title := "MUTATION WÄHLEN"
	var font := UI.display_font()
	var fs := 62
	var half := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5
	var alpha := appear
	# Soft halo so the title reads over busy ground.
	_soft_glow(Rect2(cx - half - 120.0, base_y - fs - 24.0, half * 2.0 + 240.0, fs + 100.0), Color(UI.OUTLINE, 0.55 * alpha))
	# Own tendrils: the kit divider sits too far out for this short title.
	for s in [-1.0, 1.0]:
		_vine(Vector2(cx + s * (half + 16.0), base_y - 18.0), s, alpha)
	_text(self, title, Vector2(cx, base_y + 4), fs, Color(UI.SHADOW, 0.9 * alpha), 1, 0)
	_text(self, title, Vector2(cx, base_y), fs, Color(UI.BONE, alpha), 1, 10)
	# "S T U F E  n" in spaced caps between two fading rules.
	if _spaced == null:
		_spaced = FontVariation.new()
		_spaced.base_font = UI.display_font()
		_spaced.spacing_glyph = 9
	var sub := "STUFE %d" % (int(evo.level) + 1)
	var sub_y := base_y + 50.0
	var sub_w := _text(self, sub, Vector2(cx, sub_y), 28, Color(UI.TEXT_DIM.lerp(UI.BONE, 0.35), alpha), 1, 6, _spaced)
	for s in [-1.0, 1.0]:
		var inner := Vector2(cx + s * (sub_w * 0.5 + 18.0), sub_y - 10.0)
		var outer := inner + Vector2(s * 190.0, 0)
		draw_polyline_colors(PackedVector2Array([inner, outer]), PackedColorArray([Color(UI.TOXIC.darkened(0.25), 0.9 * alpha), Color(UI.TOXIC.darkened(0.25), 0.0)]), 3.0, true)
		_diamond(self, inner + Vector2(s * -2.0, 0), 6.0, Color(UI.TOXIC, alpha))


# Soft blob: opaque centre fading to all four edges (no hard rectangle).
func _soft_glow(r: Rect2, tint: Color) -> void:
	var clear := Color(tint, 0.0)
	var mid := r.get_center()
	var xs := [r.position.x, mid.x, r.end.x]
	var ys := [r.position.y, mid.y, r.end.y]
	for gx in 2:
		for gy in 2:
			var pts := PackedVector2Array([Vector2(xs[gx], ys[gy]), Vector2(xs[gx + 1], ys[gy]), Vector2(xs[gx + 1], ys[gy + 1]), Vector2(xs[gx], ys[gy + 1])])
			var cols := PackedColorArray()
			for v in pts:
				cols.append(tint if v == mid else clear)
			draw_polygon(pts, cols)


# Thorny tendril curling outward and up from the title ends.
func _vine(start: Vector2, side: float, alpha: float) -> void:
	var dark := Color(UI.TOXIC.darkened(0.45), alpha)
	var light := Color(UI.TOXIC.darkened(0.1), alpha)
	var p0 := start
	var p1 := start + Vector2(side * 70.0, 26.0)
	var p2 := start + Vector2(side * 120.0, -40.0)
	var p3 := start + Vector2(side * 92.0, -70.0)
	var pts := PackedVector2Array()
	var steps := 18
	for i in steps + 1:
		var t := float(i) / steps
		var u := 1.0 - t
		pts.append(u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3)
	for i in steps:
		var t := float(i) / steps
		draw_line(pts[i], pts[i + 1], dark, lerpf(9.0, 2.0, t), true)
	for i in steps:
		var t := float(i) / steps
		draw_line(pts[i] + Vector2(0, -1.5), pts[i + 1] + Vector2(0, -1.5), light, lerpf(3.5, 1.0, t), true)
	# Thorns on the outer side, a leaf at the root, a curl at the tip.
	for i: int in [4, 8, 12]:
		var a := pts[i]
		var dir := (pts[i + 1] - pts[i]).normalized()
		var nrm := Vector2(-dir.y, dir.x) * (1.0 if side > 0 else -1.0)
		var tip := a + nrm * -(14.0 - i * 0.5) + dir * 6.0
		draw_colored_polygon(PackedVector2Array([a - dir * 5.0, a + dir * 5.0, tip]), light)
	var leaf_c := start + Vector2(side * 34.0, 22.0)
	var leaf := PackedVector2Array()
	for i in 12:
		var a := TAU * i / 12.0
		leaf.append(leaf_c + Vector2(cos(a) * 16.0 * side, sin(a) * 6.0).rotated(0.35 * side))
	draw_colored_polygon(leaf, dark)
	draw_arc(p3 + Vector2(side * -8.0, 2.0), 8.0, 0.0, TAU * 0.75, 12, dark, 2.5, true)


func _draw_button(rect: Rect2, icon_id: String, label: String, count: int, accent: Color) -> void:
	if frames != null and use_frame_kit:
		frames.button(self, rect, "secondary", false, accent)
	else:
		_plate(self, rect, accent, 12.0)
	var icon_rect := Rect2(rect.position + Vector2(18, rect.size.y * 0.5 - 22), Vector2(44, 44))
	_icon(self, icon_id, icon_rect, accent)
	var font := UI.display_font()
	var fs := _fit(label, font, 26, rect.size.x - 100.0, MIN_TEXT)
	var lw := _width(label, font, fs)
	var lx := icon_rect.end.x + (rect.end.x - 24.0 - icon_rect.end.x - lw) * 0.5
	_text(self, label, Vector2(lx, rect.get_center().y + fs * 0.36), fs, UI.TEXT, 0, 6)
	_badge(self, Vector2(rect.end.x - 6, rect.position.y + 4), count, accent)


# ------------------------------------------------------------------ card

func draw_card(c: CanvasItem, slot: int, entry: Array, rank: int, flash: float) -> void:
	var evo := _evolution()
	var hud := _hud()
	var id := str(entry[0])
	var s: Vector2 = c.size
	var category: String = CATEGORY_OF.get(id, "special")
	var accent: Color = UI.CATEGORY.get(category, UI.VIOLET)
	var kind: String = evo.kind_of(id) if evo != null else "trait"
	var is_form := kind in ["attack", "evolved"]
	var banish: int = hud._count("banishes")
	var banish_local: Rect2 = hud._banish_rect(slot)
	banish_local.position -= hud._mutation_rect(slot).position

	if frames != null and use_frame_kit:
		frames.card(c, Rect2(Vector2.ZERO, s), accent, "selected" if flash > 0.0 else "normal")
		frames.card_cells(c, Rect2(Vector2.ZERO, s), accent)
	else:
		_card_frame(c, s, accent, slot)
	if banish <= 0 and not (frames != null and use_frame_kit):
		for pore in [Vector2(-58, 30), Vector2(-40, 22), Vector2(-42, 42), Vector2(-26, 34)]:
			_ring(c, Vector2(s.x, 0) + pore, 7.0, Color(UI.OUTLINE, 0.9), Color(accent, 0.55))

	# Medallion (concept): a bulge of the frame band around a dark well, strong
	# glow in the category colour outside and a lit core behind the icon.
	var m := Vector2(120, s.y * 0.5)
	_halo(c, m, 168.0, Color(accent, 0.62 + 0.4 * flash))
	c.draw_circle(m, 92, Color("0c1d14"))
	c.draw_circle(m, 88, Color("17321f"))
	for i in 7:
		var a := TAU * i / 7.0 + 0.3
		c.draw_circle(m + Vector2(cos(a), sin(a)) * 88.0, 3.2, Color("020604"))
	for i in 3:
		c.draw_arc(m, 96.0 + i * 6.0, 0, TAU, 72, Color(accent, 0.34 - i * 0.1), 7.0, true)
	c.draw_arc(m, 92, 0, TAU, 72, Color(accent, 0.9), 3.0, true)
	c.draw_circle(m, 80, Color("020604"))
	_halo(c, m + Vector2(0, 10), 78.0, Color(accent, 0.3))
	# Inner rim light: the well glows at its edge, the centre stays dark.
	for i in 3:
		c.draw_arc(m, 75.0 - i * 6.0, 0, TAU, 64, Color(accent, 0.4 - i * 0.13), 6.0, true)
	c.draw_arc(m, 80, 0, TAU, 64, accent.lightened(0.15), 4.0, true)
	c.draw_arc(m, 80, PI * 1.1, PI * 1.9, 24, Color(accent.lightened(0.6), 0.7), 2.0, true)
	_icon(c, id, Rect2(m - Vector2(64, 64), Vector2(128, 128)), accent)
	# Number badge (keys 1/2/3), bottom left of the medallion.
	var nb := m + Vector2(-62, 58)
	c.draw_circle(nb, 19, Color(accent, 0.95))
	c.draw_circle(nb, 15.5, UI.OUTLINE)
	_text(c, str(slot + 1), nb + Vector2(0, 8), 22, UI.TEXT, 1, 0)
	if is_form and rank == 0:
		_plaque(c, Vector2(m.x, 16), "NEU", UI.GOLD)

	# Text column.
	var x := 236.0
	var right := s.x - 34.0
	var col_w := right - x
	var kind_label := "ANGRIFFSFORM" if is_form else "ANLAGE"
	var slot_kind := "attack" if is_form else "trait"
	var used: int = evo.slots_used(slot_kind)
	var limit: int = evo.slot_limit(slot_kind)
	var slot_text := "SLOT %d/%d" % [mini(used + (1 if rank == 0 else 0), limit), limit]
	# The banish tag may share the header or the name line; text yields to it.
	var banish_head := banish > 0 and banish_local.position.y < 42.0
	var banish_name := banish > 0 and banish_local.end.y > 52.0 and banish_local.position.y < 96.0
	var head_right := (banish_local.position.x - 16.0) if banish_head else right - 80.0
	var name_right := (banish_local.position.x - 14.0) if banish_name else right
	var head := "%s  ·  %s" % [kind_label, slot_text]
	_text(c, head, Vector2(x, 40), _fit(head, UI.display_font(), MIN_TEXT, head_right - x, MIN_TEXT), Color(accent.lerp(UI.TEXT_DIM, 0.35), 0.95), 0, 5)
	var name := str(entry[1]).to_upper()
	var name_size := _fit(name, UI.display_font(), 48, name_right - x, 30)
	_text(c, name, Vector2(x, 92), name_size, accent.lightened(0.08), 0, 8)
	c.draw_polyline_colors(PackedVector2Array([Vector2(x, 106), Vector2(right, 106)]), PackedColorArray([Color(accent, 0.75), Color(accent, 0.0)]), 2.5, true)

	if is_form:
		var body := _form_text(id, rank)
		if body == "":
			body = str(entry[2])
		var fs := 24
		var lines := _wrap(body, UI.body_font(), fs, col_w)
		while lines.size() > 2 and fs > MIN_TEXT:
			fs -= 1
			lines = _wrap(body, UI.body_font(), fs, col_w)
		if lines.size() > 2:
			lines = lines.slice(0, 2)
			lines[1] = lines[1].rstrip(" .,") + "…"
		for i in lines.size():
			_text(c, lines[i], Vector2(x, 136 + i * (fs + 2)), fs, UI.TEXT, 0, 5, UI.body_font())
	else:
		var effect := _effect(id, entry, rank + 1, true)
		_text(c, effect, Vector2(x, 150), _fit(effect, UI.display_font(), 34, col_w, 24), UI.TEXT, 0, 7)

	# Bottom row: rank diamonds, change, evolution hint.
	var row_y := 198.0
	for i in 3:
		var dc := Vector2(x + 12 + i * 30, row_y - 8)
		if i < rank:
			_diamond(c, dc, 11.0, accent)
		elif i == rank:
			var pulse := 0.5 + 0.5 * sin(_now() * 5.0)
			c.draw_circle(dc, 15, Color(accent, 0.18 + 0.2 * pulse))
			_diamond(c, dc, 12.0, UI.TEXT)
			_diamond(c, dc, 8.0, accent)
		else:
			_diamond(c, dc, 11.0, Color(UI.OUTLINE, 0.9))
			_diamond_outline(c, dc, 11.0, Color(accent, 0.45))
	var cx := x + 104.0
	if is_form:
		if rank > 0:
			cx += _text(c, "RANG %s" % ROMAN[rank - 1], Vector2(cx, row_y), 23, UI.TEXT_DIM, 0, 5) + 10.0
			_arrow(c, Vector2(cx, row_y - 8), accent)
			cx += 38.0
			cx += _text(c, ROMAN[mini(rank, ROMAN.size() - 1)], Vector2(cx, row_y + 1), 28, UI.TEXT, 0, 6)
		else:
			cx += _text(c, "RANG I", Vector2(cx, row_y + 1), 26, UI.TEXT, 0, 6)
	else:
		var before := _effect(id, entry, rank, false)
		var after := _effect(id, entry, rank + 1, false)
		cx += _text(c, before, Vector2(cx, row_y), 23, UI.TEXT_DIM, 0, 5) + 10.0
		_arrow(c, Vector2(cx, row_y - 8), accent)
		cx += 38.0
		cx += _text(c, after, Vector2(cx, row_y + 1), 28, UI.TEXT, 0, 6)
	var hint := _evolution_hint(evo, id, rank)
	if not hint.is_empty():
		var hint_font := UI.display_font()
		var label: String = hint.text
		var avail := right - cx - 30.0
		if hint_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, MIN_TEXT).x > avail:
			label = hint.short
		var fs := _fit(label, hint_font, MIN_TEXT, avail, MIN_TEXT)
		var lw := _width(label, hint_font, fs)
		var hx := right - lw
		var tint: Color = UI.GOLD if hint.ready else UI.VIOLET
		var pill := Rect2(hx - 36, row_y - 26, lw + 46, 34)
		c.draw_rect(pill, Color(UI.OUTLINE, 0.75))
		c.draw_rect(pill, Color(tint, 0.6), false, 2.0)
		_icon(c, hint.id, Rect2(hx - 32, row_y - 23, 28, 28), tint)
		_text(c, label, Vector2(hx, row_y - 1), fs, tint.lightened(0.2), 0, 5)

	if banish > 0:
		_draw_banish(c, banish_local, banish)
	if flash > 0.0:
		var shape := _card_shape(s)
		c.draw_colored_polygon(shape, Color(accent.lightened(0.7), 0.5 * flash))
		var glow := Geometry2D.offset_polygon(shape, 14.0 * flash + 4.0)
		if not glow.is_empty():
			var ring: PackedVector2Array = glow[0]
			ring.append(ring[0])
			c.draw_polyline(ring, Color(accent.lightened(0.5), flash), 6.0, true)


# Compact danger tag inside the card body (hit area: hud._banish_rect(slot)).
func _draw_banish(c: CanvasItem, r: Rect2, count: int) -> void:
	var red := UI.DANGER
	var shape := _rounded(r, 14.0)
	_halo(c, r.get_center(), r.size.x * 0.62, Color(red, 0.16))
	c.draw_colored_polygon(_rounded(Rect2(r.position + Vector2(0, 3), r.size), 14.0), Color(0, 0, 0, 0.45))
	c.draw_colored_polygon(shape, Color("1c0a08").lerp(Color("0c1d14"), 0.3))
	c.draw_colored_polygon(_rounded(Rect2(r.position + Vector2(4, 4), Vector2(r.size.x - 8, r.size.y * 0.42)), 10.0), Color(red, 0.12))
	var ring := shape.duplicate()
	ring.append(ring[0])
	c.draw_polyline(ring, Color(red, 0.85), 2.5, true)
	var icon_size := minf(32.0, r.size.y - 12.0)
	_icon(c, "banish", Rect2(r.position + Vector2(10, (r.size.y - icon_size) * 0.5), Vector2(icon_size, icon_size)), red.lightened(0.2))
	var tx := r.position.x + 16.0 + icon_size
	var fs := _fit("VERBANNEN", UI.display_font(), 23, r.end.x - 10.0 - tx, MIN_TEXT)
	var lw := _width("VERBANNEN", UI.display_font(), fs)
	_text(c, "VERBANNEN", Vector2(tx + maxf(0.0, (r.end.x - 10.0 - tx - lw) * 0.5), r.get_center().y + fs * 0.36), fs, UI.TEXT, 0, 5)
	_badge(c, Vector2(r.end.x - 4, r.position.y + 2), count, red)


func _rounded(r: Rect2, radius: float) -> PackedVector2Array:
	var rad := minf(radius, minf(r.size.x, r.size.y) * 0.5)
	var pts := PackedVector2Array()
	var corners := [Vector2(r.end.x - rad, r.position.y + rad), Vector2(r.end.x - rad, r.end.y - rad), Vector2(r.position.x + rad, r.end.y - rad), Vector2(r.position.x + rad, r.position.y + rad)]
	for k in 4:
		for i in 5:
			var a := -PI * 0.5 + PI * 0.5 * k + PI * 0.5 * i / 4.0
			pts.append(corners[k] + Vector2(cos(a), sin(a)) * rad)
	return pts


# Organic card: chamfered corners, a stepped top edge, side notches, horns.
func _card_shape(s: Vector2) -> PackedVector2Array:
	var w := s.x
	var h := s.y
	var ch := 30.0
	var p := PackedVector2Array()
	p.append(Vector2(ch, 0))
	p.append(Vector2(w * 0.6, 0))
	p.append(Vector2(w * 0.6 + 14, -8))
	p.append(Vector2(w - ch - 6, -8))
	p.append(Vector2(w, ch - 8))
	_notch(p, Vector2(w, h * 0.36), Vector2(w, h * 0.64), -1.0, 13.0)
	p.append(Vector2(w, h - ch))
	p.append(Vector2(w - ch, h))
	p.append(Vector2(w * 0.4 + 14, h))
	p.append(Vector2(w * 0.4, h + 7))
	p.append(Vector2(ch + 6, h + 7))
	p.append(Vector2(0, h - ch + 7))
	_notch(p, Vector2(0, h * 0.7), Vector2(0, h * 0.34), 1.0, 13.0)
	p.append(Vector2(0, ch))
	return p


func _notch(p: PackedVector2Array, a: Vector2, b: Vector2, inward: float, depth: float) -> void:
	for i in 9:
		var t := float(i) / 8.0
		p.append(a.lerp(b, t) + Vector2(inward * depth * sin(t * PI), 0))


func _card_frame(c: CanvasItem, s: Vector2, accent: Color, seed_slot: int) -> void:
	var shape := _card_shape(s)
	for layer in [[22.0, 0.05], [14.0, 0.09], [8.0, 0.15], [3.0, 0.3]]:
		var glow := Geometry2D.offset_polygon(shape, layer[0])
		if not glow.is_empty():
			c.draw_colored_polygon(glow[0], Color(accent, layer[1]))
	_horn(c, Vector2(10, 12), Vector2(-20, -22), accent)
	_horn(c, Vector2(s.x - 26, -2), Vector2(s.x + 14, -30), accent)
	_horn(c, Vector2(s.x - 10, s.y - 14), Vector2(s.x + 18, s.y + 20), accent)
	# Rim with a light-to-dark vertical gradient.
	var rim_colors := PackedColorArray()
	for v in shape:
		rim_colors.append(accent.lightened(0.28).lerp(accent.darkened(0.35), clampf(v.y / s.y, 0.0, 1.0)))
	c.draw_polygon(shape, rim_colors)
	var inner := Geometry2D.offset_polygon(shape, -11.0)
	if inner.is_empty():
		return
	var body: PackedVector2Array = inner[0]
	var body_colors := PackedColorArray()
	var deep := Color(UI.PANEL, 1.0).darkened(0.25)
	for v in body:
		var near_icon := 1.0 - clampf(v.x / (s.x * 0.45), 0.0, 1.0)
		body_colors.append(deep.lerp(Color(UI.PANEL, 1.0).lerp(accent, 0.1), near_icon * 0.8))
	c.draw_polygon(body, body_colors)
	# Holes through the rim, bone teeth under the lower step.
	for hole in [Vector2(5, s.y * 0.22), Vector2(5, s.y * 0.84), Vector2(s.x - 5, s.y * 0.2), Vector2(s.x - 5, s.y * 0.8)]:
		_ellipse(c, hole, 3.5, 11.0, Color(UI.OUTLINE, 0.95))
	for tx in [s.x * 0.4 - 26.0, s.x * 0.4 - 50.0]:
		c.draw_colored_polygon(PackedVector2Array([Vector2(tx - 7, s.y + 5), Vector2(tx + 7, s.y + 5), Vector2(tx + 1, s.y + 19)]), UI.BONE.darkened(0.1))
	# Vein and cell texture, deterministic per slot.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 + seed_slot * 31
	var vein := Color(accent, 0.07)
	for n in 7:
		var pt := Vector2(rng.randf_range(250, s.x - 40), rng.randf_range(24, s.y - 24))
		var line := PackedVector2Array([pt])
		for k in 5:
			pt += Vector2(rng.randf_range(-40, 60), rng.randf_range(-22, 22))
			pt = pt.clamp(Vector2(24, 20), s - Vector2(24, 20))
			line.append(pt)
		c.draw_polyline(line, vein, 2.0, true)
	for n in 14:
		var cc := Vector2(rng.randf_range(230, s.x - 30), rng.randf_range(20, s.y - 20))
		c.draw_arc(cc, rng.randf_range(4, 11), 0, TAU, 12, Color(accent, 0.06), 1.5, true)
	var edge := Geometry2D.offset_polygon(shape, -17.0)
	if not edge.is_empty():
		var ring: PackedVector2Array = edge[0]
		ring.append(ring[0])
		c.draw_polyline(ring, Color(UI.PANEL_EDGE, 0.8), 1.5, true)


func _horn(c: CanvasItem, base: Vector2, tip: Vector2, accent: Color) -> void:
	var dir := (tip - base).normalized()
	var side := Vector2(-dir.y, dir.x)
	var mid := base.lerp(tip, 0.55) + side * 6.0
	c.draw_colored_polygon(PackedVector2Array([base + side * 11.0, mid + side * 4.0, tip, mid - side * 3.0, base - side * 11.0]), accent.lightened(0.1))
	c.draw_line(base.lerp(tip, 0.2), tip, Color(UI.BONE, 0.5), 2.0, true)


func _plate(c: CanvasItem, r: Rect2, accent: Color, ch: float, fill: Color = Color(UI.PANEL, 0.96)) -> void:
	var pts := PackedVector2Array([
		r.position + Vector2(ch, 0), Vector2(r.end.x - ch, r.position.y), Vector2(r.end.x, r.position.y + ch),
		Vector2(r.end.x, r.end.y - ch), Vector2(r.end.x - ch, r.end.y), Vector2(r.position.x + ch, r.end.y),
		Vector2(r.position.x, r.end.y - ch), r.position + Vector2(0, ch)])
	var glow := Geometry2D.offset_polygon(pts, 6.0)
	if not glow.is_empty():
		c.draw_colored_polygon(glow[0], Color(accent, 0.14))
	c.draw_colored_polygon(pts, fill)
	var ring := pts.duplicate()
	ring.append(ring[0])
	c.draw_polyline(ring, accent, 2.5, true)


func _plaque(c: CanvasItem, center: Vector2, label: String, tint: Color) -> void:
	var font := UI.display_font()
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 30.0
	var r := Rect2(center - Vector2(w * 0.5, 15), Vector2(w, 30))
	var pts := PackedVector2Array([r.position + Vector2(10, 0), Vector2(r.end.x - 10, r.position.y), Vector2(r.end.x, r.get_center().y), Vector2(r.end.x - 10, r.end.y), Vector2(r.position.x + 10, r.end.y), Vector2(r.position.x, r.get_center().y)])
	var glow := Geometry2D.offset_polygon(pts, 5.0)
	if not glow.is_empty():
		c.draw_colored_polygon(glow[0], Color(tint, 0.3))
	c.draw_colored_polygon(pts, tint)
	_text(c, label, Vector2(center.x, center.y + 8), 22, UI.OUTLINE, 1, 0)


func _badge(c: CanvasItem, center: Vector2, count: int, tint: Color) -> void:
	c.draw_circle(center, 17, UI.OUTLINE)
	c.draw_circle(center, 14.5, tint)
	_text(c, str(count), center + Vector2(0, 8), MIN_TEXT, UI.OUTLINE, 1, 0)


func _arrow(c: CanvasItem, at: Vector2, tint: Color) -> void:
	c.draw_line(at, at + Vector2(20, 0), tint, 4.0, true)
	c.draw_colored_polygon(PackedVector2Array([at + Vector2(28, 0), at + Vector2(17, -8), at + Vector2(17, 8)]), tint)


func _diamond(c: CanvasItem, center: Vector2, r: float, tint: Color) -> void:
	c.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -r), center + Vector2(r * 0.8, 0), center + Vector2(0, r), center + Vector2(-r * 0.8, 0)]), tint)


func _diamond_outline(c: CanvasItem, center: Vector2, r: float, tint: Color) -> void:
	c.draw_polyline(PackedVector2Array([center + Vector2(0, -r), center + Vector2(r * 0.8, 0), center + Vector2(0, r), center + Vector2(-r * 0.8, 0), center + Vector2(0, -r)]), tint, 2.0, true)


func _ring(c: CanvasItem, center: Vector2, r: float, fill: Color, edge: Color) -> void:
	c.draw_circle(center, r, fill)
	c.draw_arc(center, r, 0, TAU, 14, edge, 1.5, true)


func _ellipse(c: CanvasItem, center: Vector2, rx: float, ry: float, tint: Color) -> void:
	var pts := PackedVector2Array()
	for i in 14:
		var a := TAU * i / 14.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	c.draw_colored_polygon(pts, tint)


func _halo(c: CanvasItem, center: Vector2, radius: float, tint: Color) -> void:
	if frames != null and use_frame_kit:
		frames.halo(c, center, radius, tint)
		return
	for i in 4:
		c.draw_circle(center, radius * (0.4 + i * 0.18), Color(tint, tint.a * 0.12))


# Icon from UiIcons when available, else a simple monogram medal.
func _icon(c: CanvasItem, id: String, r: Rect2, tint: Color) -> void:
	if icons != null and icons.has(id):
		# Painted icons carry their own colours; only fade them, never recolour.
		icons.draw(c, id, r, Color(1.0, 1.0, 1.0, tint.a))
		return
	var center := r.get_center()
	var rad := r.size.x * 0.5
	match id:
		"reroll":
			c.draw_arc(center, rad * 0.62, 0.4, TAU - 0.9, 20, tint, rad * 0.16, true)
			var tip := center + Vector2(cos(0.4), sin(0.4)) * rad * 0.62
			c.draw_colored_polygon(PackedVector2Array([tip + Vector2(-rad * 0.35, 0), tip + Vector2(rad * 0.3, 0), tip + Vector2(0, -rad * 0.4)]), tint)
		"skip":
			for k in 2:
				var o := center + Vector2((k - 0.6) * rad * 0.55, 0)
				c.draw_colored_polygon(PackedVector2Array([o + Vector2(-rad * 0.3, -rad * 0.5), o + Vector2(rad * 0.35, 0), o + Vector2(-rad * 0.3, rad * 0.5)]), tint)
		"banish":
			c.draw_arc(center, rad * 0.7, 0, TAU, 20, tint, rad * 0.14, true)
			c.draw_line(center + Vector2(-rad, rad) * 0.45, center + Vector2(rad, -rad) * 0.45, tint, rad * 0.16, true)
		_:
			c.draw_arc(center, rad * 0.78, 0, TAU, 32, Color(tint, 0.5), 3.0, true)
			var info: Array = _evolution().info(id) if _evolution() != null else []
			var letter := str(info[1]).substr(0, 1).to_upper() if info.size() > 1 else "?"
			_text(c, letter, center + Vector2(0, rad * 0.36), int(rad), tint, 1, 6)


# ------------------------------------------------------------------ data

# "+25 % BISSSCHADEN" (with label) or "+25 %" for a given total rank.
func _effect(id: String, entry: Array, total_rank: int, with_label: bool) -> String:
	if RANK_TEXT.has(id):
		var texts: Array = RANK_TEXT[id]
		if total_rank <= 0:
			return "—"
		return str(texts[clampi(total_rank - 1, 0, texts.size() - 1)])
	var desc := str(entry[2])
	var regex := RegEx.create_from_string("^([+−-])\\s*(\\d+)")
	var found := regex.search(desc)
	var sign := "+"
	var step := 0
	if found != null:
		sign = found.get_string(1)
		step = int(found.get_string(2))
	var value := "0 %" if total_rank <= 0 else "%s%d %%" % [sign, step * total_rank]
	if with_label:
		var per_rank := "%s%d %%" % [sign, step]
		var label: String = EFFECT_LABEL.get(id, desc.substr(desc.find("%") + 1).replace("pro Rang", "").strip_edges().to_upper())
		return "%s %s" % [per_rank, label]
	return value


func _form_text(id: String, owned_rank: int) -> String:
	var form: Variant = _forms.get(id)
	if not form is Dictionary:
		return ""
	var ranks: Array = form.get("ranks", [])
	if ranks.is_empty():
		return ""
	return str(ranks[clampi(owned_rank, 0, ranks.size() - 1)])


# Which evolution this card feeds, and whether the pick completes its rules.
func _evolution_hint(evo: RefCounted, id: String, rank: int) -> Dictionary:
	if evo == null:
		return {}
	for rule in evo.EVOLUTION_RULES:
		if evo.evolutions.has(rule.id) or (id != rule.base and id != rule.partner):
			continue
		var base_rank: int = evo.rank(rule.base) + (1 if id == rule.base else 0)
		var partner_rank: int = evo.rank(rule.partner) + (1 if id == rule.partner else 0)
		var name := str(evo.info(rule.id)[1]).to_upper()
		var ready: bool = base_rank >= evo.MAX_RANK and partner_rank >= 1
		if ready:
			return {"id": rule.id, "ready": true, "text": "BEREIT: %s" % name, "short": name}
		return {"id": rule.id, "ready": false, "text": "EVOLUTION %s" % name, "short": name}
	return {}


# ------------------------------------------------------------------ text

# Outlined text. align: 0 left, 1 centre, 2 right. Returns the drawn width.
# Whole sizes draw exactly; fractional (fitted) sizes are drawn from a palette
# size and scaled (UiStyle.size_step), so fitting adds no glyph caches.
func _text(c: CanvasItem, value: String, at: Vector2, font_size: float, tint: Color, align: int = 0, outline: int = 6, font: Font = null) -> float:
	var face: Font = font if font != null else UI.display_font()
	var whole := absf(font_size - roundf(font_size)) < 0.01
	var step := int(roundf(font_size)) if whole else UI.size_step(font_size)
	var k := 1.0 if whole else font_size / step
	var w := face.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, step).x * k
	var origin := at
	if align == 1:
		origin.x -= w * 0.5
	elif align == 2:
		origin.x -= w
	if not whole:
		c.draw_set_transform(origin, 0.0, Vector2(k, k))
		origin = Vector2.ZERO
	if outline > 0:
		c.draw_string_outline(face, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, step, outline, Color(UI.OUTLINE, tint.a))
	c.draw_string(face, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, step, tint)
	if not whole:
		c.draw_set_transform(Vector2.ZERO)
	return w


func _width(value: String, font: Font, font_size: float) -> float:
	if absf(font_size - roundf(font_size)) < 0.01:
		return font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, int(roundf(font_size))).x
	return UI.width_px(value, font_size, font)


# Size that fits `width`: `wanted` when it fits, else shrunk (not below minimum).
func _fit(value: String, font: Font, wanted: int, width: float, minimum: int) -> float:
	var w := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, wanted).x
	if w <= width or wanted <= minimum:
		return float(wanted)
	var fitted := maxf(float(minimum), floorf(wanted * width / w * 4.0) / 4.0)
	# A whole size would get its own glyph cache; stay fractional (scaled).
	if fitted > minimum and absf(fitted - roundf(fitted)) < 0.01:
		fitted -= 0.05
	return fitted


func _wrap(value: String, font: Font, font_size: int, width: float) -> Array:
	var lines: Array = []
	var line := ""
	for word in value.split(" ", false):
		var probe := word if line == "" else line + " " + word
		if line != "" and font.get_string_size(probe, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
			lines.append(line)
			line = word
		else:
			line = probe
	if line != "":
		lines.append(line)
	return lines
