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
#
# Stage 15 (skin "brawl", package C): the screen owns its geometry. Input code
# (touch_controls.gd) should hit-test with card_rect(slot), banish_rect(slot),
# reroll_rect() and skip_rect(); in the organic/calm skins these return the
# old hud rects unchanged. The level-up moment (<= 0.6 s: world desaturated
# and dimmed, light column on the leader, ribbon "MUTATION!", cards staggered
# in) can be cut short by a tap: this node eats that first tap in _input(),
# so it never picks a card the player has not seen yet.

#
# Stage 17 (dual progression): level cards are stats with a rarity (entry[3]):
# rarity rim (common neutral, rare info, epic special, legendary loot + glint),
# rarity chip in the header, value before -> after. The same cards show the
# Boss-Kokon choice (mode "chest": weapon / relic / evolution, entry[4] = item)
# whenever evolution.chest_offers is not empty; the input for that mode belongs
# to wave 2 (touch_controls / HuntWorld).
#
# Stage 28: five rarities (UiStyle.RARITY_TONES: grey, green, blue, violet,
# gold). Frame, header, plate, pips and chip take the rarity tone everywhere;
# the category (WAFFE, RELIKT, WERT · ANGRIFF, EVOLUTION) is a small tab on the
# top edge. Every cocoon kind opens this choice; the ribbon names the kind
# (evolution.chest_kind).

const UI := preload("res://scripts/ui/ui_style.gd")
const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")
const STATS := preload("res://scripts/progression/stats.gd")
const ICONS_PATH := "res://scripts/ui/ui_icons.gd"
const FRAMES_PATH := "res://scripts/ui/ui_frames.gd"
const FORMS_PATH := "res://scripts/attack_forms.gd"
const CorePlaque := preload("res://scripts/ui/core_plaque.gd")

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
	"jaws": "BISSSCHADEN", "brood": "BIOMASSE BEIM SAMMELN", "glutton": "BIOMASSE PRO KILL",
	"pack": "SCHADEN BEI RALLY", "scatter": "VERLUSTE OHNE RALLY", "armor": "VERLUSTE",
	"dornenhaut": "RÜCKSCHADEN",
}
# Traits whose effect is not a percentage: shown as rank-specific text instead.
const RANK_TEXT := {
	"regeneration": ["+1 LP JE 12 KILLS / 30 S", "+1 LP JE 9 KILLS / 25 S", "+1 LP JE 6 KILLS / 20 S"],
}
const ROMAN := ["I", "II", "III", "IV", "V"]

# ---- brawl skin (stage 15) ------------------------------------------------
# "stack": three wide cards under each other (chosen, see stage 15 notes);
# "columns": three portrait cards side by side (kit preview), kept for comparison.
const LAYOUTS := ["stack", "columns"]
# Trait branch (category label "WERT · ANGRIFF"). Stage 28: the card tone is the
# rarity; evolved forms add a gold rim + glint. Unknown new traits are guessed
# from their text.
const BRANCH_OF := {
	"jaws": "attack", "pack": "attack",
	"brood": "growth", "glutton": "growth", "lockduft": "growth",
	"armor": "protect", "regeneration": "protect", "dornenhaut": "protect",
	"scatter": "special",
}
# Stage 17: stat category -> branch (stats.gd "cat").
const STAT_BRANCH := {"attack": "attack", "protect": "protect", "growth": "growth", "special": "special"}
const CHEST_TITLE := {"start": "START-KOKON!", "map": "KOKON!", "elite": "ELITE-KOKON!", "gold": "GOLDENER KOKON!",
	"boss": "BOSS-KOKON!"}
const LEGEND_GLINT := 2.6  # seconds per sweep of the legendary shine
const BRANCH_LABEL := {"attack": "ANGRIFF", "growth": "WACHSTUM", "protect": "SCHUTZ", "special": "SPEZIAL"}
# Level-up moment timeline (seconds after the choice opens; total <= 0.6).
const LV_DIM := 0.15
const LV_BEAM_OUT := Vector2(0.3, 0.55)
const LV_RIBBON := Vector2(0.04, 0.22)     # start, duration
const LV_CARD := Vector2(0.18, 0.24)       # first start, duration
const LV_STAGGER := 0.07
const LV_TOTAL := 0.6
const LV_REDEAL := 0.2                     # card swap after reroll/banish
# Geometry (base viewport 900 x 1600).
const B_SIDE := 36.0
const B_CARD_H := 262.0
const B_GAP := 22.0
const B_COL_H := 640.0
const B_COL_GAP := 14.0
const B_HEADER := 62.0
const B_RIBBON := Vector2(470.0, 96.0)
const B_TITLE_H := 96.0 + 58.0
const B_BUTTON_H := 104.0
const B_TOP_MIN := 150.0
const B_BANISH_R := 32.0
const DESAT_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount = 0.0;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(c, vec3(g), 0.8 * amount), 1.0);
}
"""


# Draws through a callable (ribbon, pieces that animate with scale/position).
class PaintView extends Control:
	var painter: Callable
	var key: Variant = null

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func refresh(new_key: Variant) -> void:
		if typeof(new_key) != typeof(key) or new_key != key:
			key = new_key
			queue_redraw()

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)


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
var _title_font: FontVariation
var _screen_key: Variant = null
## Brawl card arrangement: "stack" (default) or "columns".
var layout := "stack"
var _desat: ColorRect
var _ribbon: PaintView
var _swarm_node: Node3D
var _leader_at := Vector2.INF
# Start of the current level-up moment (restarts when a queued level follows).
var _moment_time := -10.0
var _moment_level := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_modules()
	# Desaturates the world behind the dimmer (drawn before this node's own _draw).
	_desat = ColorRect.new()
	_desat.name = "Desaturate"
	_desat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desat.show_behind_parent = true
	_desat.visible = false
	var shader := Shader.new()
	shader.code = DESAT_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	_desat.material = material
	add_child(_desat)
	_ribbon = PaintView.new()
	_ribbon.name = "Ribbon"
	_ribbon.painter = _paint_ribbon
	_ribbon.visible = false
	add_child(_ribbon)
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


## Stage 17: "chest" while a Boss-Kokon choice is open, else "level".
## Stage 33: "core" while a Mutationskern choice is open (wins over both).
func mode() -> String:
	var evo := _evolution()
	if evo != null and "core_offers" in evo and not evo.core_offers.is_empty():
		return "core"
	if evo != null and "chest_offers" in evo and not evo.chest_offers.is_empty():
		return "chest"
	return "level"


## Stage 28: ribbon title of the open cocoon choice by evolution.chest_kind
## (every cocoon kind opens 1 of 3). Without the field only the Boss-Kokon
## offered a choice (stage 17), so that stays the fallback.
func chest_title() -> String:
	var evo := _evolution()
	if evo == null or not ("chest_kind" in evo):
		return "BOSS-KOKON!"
	return String(CHEST_TITLE.get(String(evo.chest_kind), "KOKON!"))


## True while the open stat cards come from a shrine (Etappe 17 Welle 2).
func _shrine() -> bool:
	var evo := _evolution()
	return evo != null and "offer_source" in evo and String(evo.offer_source) == "shrine"


## Cards of the current mode (chest offers win over level offers).
func entries() -> Array:
	var evo := _evolution()
	if evo == null:
		return []
	match mode():
		"core":
			return evo.core_offers
		"chest":
			return evo.chest_offers
	return evo.offers


# Reroll/skip/banish counters; none in the chest choice, no banish for
# overdrive cards (stage 31 A: evolution.offer_overdrive).
func _counter(counter: String) -> int:
	var hud := _hud()
	if hud == null or mode() != "level":
		return 0
	if counter == "banishes":
		var evo := _evolution()
		if evo != null and "offer_overdrive" in evo and bool(evo.offer_overdrive):
			return 0
	return hud._count(counter)


func _open() -> bool:
	var hud := _hud()
	var evo := _evolution()
	if hud == null or evo == null or entries().is_empty():
		return false
	return not bool(hud.get("extinct")) and not bool(hud.get("paused"))


static func _ease(t: float) -> float:
	var k := 1.0 - clampf(t, 0.0, 1.0)
	return 1.0 - k * k * k


# Overshooting ease for pops (ribbon, card landing).
static func _back(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	var c := 1.9
	var u := t - 1.0
	return 1.0 + (c + 1.0) * u * u * u + c * u * u


func _brawl() -> bool:
	return UI.is_brawl()


# ------------------------------------------------------------------ geometry API
# Hit areas for touch_controls.gd; drawing uses exactly these rects.

## Card rect of `slot` (screen coordinates of the HUD).
func card_rect(slot: int) -> Rect2:
	var hud := _hud()
	if not _brawl():
		return hud._mutation_rect(slot) if hud != null else Rect2()
	var g := _geometry()
	var n: int = g.count
	if layout == "columns":
		var cw: float = (size.x - 2.0 * 28.0 - 2.0 * B_COL_GAP) / 3.0
		var total := n * cw + (n - 1) * B_COL_GAP
		return Rect2(Vector2(size.x * 0.5 - total * 0.5 + slot * (cw + B_COL_GAP), g.cards_top), Vector2(cw, B_COL_H))
	return Rect2(Vector2(B_SIDE, g.cards_top + slot * (B_CARD_H + B_GAP)), Vector2(size.x - 2.0 * B_SIDE, B_CARD_H))


## All visible card rects (one per offer).
func card_rects() -> Array:
	var out: Array = []
	var cards := entries()
	var n: int = 3 if cards.is_empty() else mini(3, cards.size())
	for slot in n:
		out.append(card_rect(slot))
	return out


## Touch area (>= TOUCH_MIN) of the banish button on card `slot`.
func banish_rect(slot: int) -> Rect2:
	var hud := _hud()
	if not _brawl():
		return hud._banish_rect(slot) if hud != null else Rect2()
	var c := _banish_center(card_rect(slot))
	return Rect2(c - Vector2.ONE * UI.TOUCH_MIN * 0.5, Vector2.ONE * UI.TOUCH_MIN)


func reroll_rect() -> Rect2:
	var hud := _hud()
	if not _brawl():
		return hud._reroll_rect() if hud != null else Rect2()
	return _button_rect(0)


func skip_rect() -> Rect2:
	var hud := _hud()
	if not _brawl():
		return hud._skip_rect() if hud != null else Rect2()
	return _button_rect(1)


## True while the level-up moment still plays (a tap only skips it).
func intro_active() -> bool:
	return _brawl() and _open() and _now() - _moment_time < LV_TOTAL


## Jumps to the end of the level-up moment.
func skip_intro() -> void:
	var now := _now()
	_moment_time = minf(_moment_time, now - LV_TOTAL)
	_open_time = minf(_open_time, now - LV_TOTAL)
	for slot in 3:
		_slot_start[slot] = minf(_slot_start[slot], now - LV_CARD.y)
	queue_redraw()


func _banish_center(card: Rect2) -> Vector2:
	var inset := UI.STROKE_L + 7.0
	return Vector2(card.end.x - inset - B_BANISH_R - 6.0, card.position.y + inset + B_HEADER * 0.5)


# 0 = reroll, 1 = skip; a lone button is centred.
func _button_rect(which: int) -> Rect2:
	var g := _geometry()
	var hud := _hud()
	var rerolls: int = _counter("rerolls") if hud != null else 0
	var skips: int = _counter("skips") if hud != null else 0
	var y: float = g.buttons_y
	if rerolls > 0 and skips > 0:
		var w := (size.x - 2.0 * B_SIDE - UI.SPACE_XL) * 0.5
		return Rect2(Vector2(B_SIDE + which * (w + UI.SPACE_XL), y), Vector2(w, B_BUTTON_H))
	var lone := minf(440.0, size.x - 2.0 * B_SIDE)
	return Rect2(Vector2(size.x * 0.5 - lone * 0.5, y), Vector2(lone, B_BUTTON_H))


# Vertical plan: ribbon + level, cards, buttons, hint; centred, below the HUD.
func _geometry() -> Dictionary:
	var hud := _hud()
	var cards := entries()
	var n: int = 3 if cards.is_empty() else mini(3, cards.size())
	var block := B_COL_H if layout == "columns" else n * B_CARD_H + (n - 1) * B_GAP
	var has_buttons: bool = hud != null and (_counter("rerolls") > 0 or _counter("skips") > 0)
	var tail := 60.0 + (UI.SPACE_XXL + B_BUTTON_H if has_buttons else 0.0)
	var top := maxf(B_TOP_MIN, (size.y - (B_TITLE_H + block + tail)) * 0.5)
	var cards_top := top + B_TITLE_H
	var buttons_y := cards_top + block + UI.SPACE_XXL
	return {"count": n, "top": top, "cards_top": cards_top, "buttons_y": buttons_y,
		"hint_y": (buttons_y + B_BUTTON_H if has_buttons else cards_top + block) + 52.0}


# ------------------------------------------------------------------ input

# The first tap during the level-up moment only ends the moment (no blind pick).
func _input(event: InputEvent) -> void:
	if not intro_active():
		return
	var press: bool = (event is InputEventScreenTouch or event is InputEventMouseButton) and event.pressed
	if press:
		skip_intro()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ update

func _process(_delta: float) -> void:
	var now := _now()
	var open := _open()
	if open and not _was_open:
		_open_time = now
		_slot_ids = ["", "", ""]
		_start_moment(now)
	elif open and int(_evolution().level) != _moment_level:
		# Another level was queued: replay the moment (the dimmer stays down).
		_slot_ids = ["", "", ""]
		_start_moment(now)
	elif not open and _was_open:
		_close_time = now
	_was_open = open
	var hud := _hud()
	if hud != null and size != hud.size:
		position = Vector2.ZERO
		size = hud.size
	if _brawl():
		_process_brawl(now, open)
		return
	_desat.visible = false
	_ribbon.visible = false
	z_index = 0
	if _footer != null:
		_footer.visible = false
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
	if _brawl():
		_draw_brawl()
		return
	var now := _now()
	var open := _open()
	var dim :=_ease((now - _open_time) / DIM_IN) if open else 1.0 - _ease((now - _close_time) / DIM_OUT)
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
		_draw_button(hud._reroll_rect(), "reroll", "NEU WÜRFELN", rerolls, UI.color("cyan"))
	if skips > 0:
		_draw_button(hud._skip_rect(), "skip", "ÜBERSPRINGEN", skips, UI.color("bone"))
	var last: Rect2 = hud._mutation_rect(evo.offers.size() - 1)
	var hint_y := last.end.y + 58.0
	if rerolls > 0 or skips > 0:
		hint_y = (hud._reroll_rect() if rerolls > 0 else hud._skip_rect()).end.y + 50.0
	_text(self, "KARTE ANTIPPEN ZUM WÄHLEN", Vector2(size.x * 0.5, hint_y), MIN_TEXT, Color(UI.color("text_dim"), 0.85), 1, 5)


func _draw_dimmer(amount: float) -> void:
	var top := Color(UI.color("dim"), UI.color("dim").a * 0.15 * amount)
	var body := Color(UI.color("dim"), UI.color("dim").a * amount)
	var deep := Color(UI.color("dim").darkened(0.3), minf(1.0, UI.color("dim").a * 1.12) * amount)
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
	if UI.is_calm():
		_draw_title_calm(evo, cx, base_y, fs, alpha)
		return
	# Soft halo so the title reads over busy ground.
	_soft_glow(Rect2(cx - half - 120.0, base_y - fs - 24.0, half * 2.0 + 240.0, fs + 100.0), Color(UI.color("outline"), 0.55 * alpha))
	# Own tendrils: the kit divider sits too far out for this short title.
	for s in [-1.0, 1.0]:
		_vine(Vector2(cx + s * (half + 16.0), base_y - 18.0), s, alpha)
	_text(self, title, Vector2(cx, base_y + 4), fs, Color(UI.color("shadow"), 0.9 * alpha), 1, 0)
	_text(self, title, Vector2(cx, base_y), fs, Color(UI.color("bone"), alpha), 1, 10)
	# "S T U F E  n" in spaced caps between two fading rules.
	if _spaced == null:
		_spaced = FontVariation.new()
		_spaced.base_font = UI.display_font()
		_spaced.spacing_glyph = 9
	var sub := "STUFE %d" % (int(evo.level) + 1)
	var sub_y := base_y + 50.0
	var sub_w := _text(self, sub, Vector2(cx, sub_y), 28, Color(UI.color("text_dim").lerp(UI.color("bone"), 0.35), alpha), 1, 6, _spaced)
	for s in [-1.0, 1.0]:
		var inner := Vector2(cx + s * (sub_w * 0.5 + 18.0), sub_y - 10.0)
		var outer := inner + Vector2(s * 190.0, 0)
		draw_polyline_colors(PackedVector2Array([inner, outer]), PackedColorArray([Color(UI.color("toxic").darkened(0.25), 0.9 * alpha), Color(UI.color("toxic").darkened(0.25), 0.0)]), 3.0, true)
		_diamond(self, inner + Vector2(s * -2.0, 0), 6.0, Color(UI.color("toxic"), alpha))


# Calm skin (V2 kit): plain spaced heading in the light text colour, "STUFE n"
# in quiet teal-grey between two thin rules. No vines, no halo.
func _draw_title_calm(evo: RefCounted, cx: float, base_y: float, fs: int, alpha: float) -> void:
	if _spaced == null:
		_spaced = FontVariation.new()
		_spaced.base_font = UI.display_font()
		_spaced.spacing_glyph = 9
	if _title_font == null:
		_title_font = FontVariation.new()
		_title_font.base_font = UI.display_font()
		_title_font.spacing_glyph = 3
	var title := "MUTATION WÄHLEN"
	_text(self, title, Vector2(cx, base_y + 3), fs, Color(UI.color("shadow"), 0.8 * alpha), 1, 0, _title_font)
	_text(self, title, Vector2(cx, base_y), fs, Color(UI.color("text"), alpha), 1, 8, _title_font)
	var sub := "STUFE %d" % (int(evo.level) + 1)
	var sub_y := base_y + 50.0
	var sub_w := _text(self, sub, Vector2(cx, sub_y), 28, Color(UI.color("text_dim"), alpha), 1, 5, _spaced)
	if frames != null:
		frames.rule(self, Vector2(cx, sub_y - 10.0), sub_w + 36.0 + 300.0, Color(UI.CALM_EDGE.lightened(0.3), alpha), sub_w + 36.0, 1.0)


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
	var dark := Color(UI.color("toxic").darkened(0.45), alpha)
	var light := Color(UI.color("toxic").darkened(0.1), alpha)
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
	_text(self, label, Vector2(lx, rect.get_center().y + fs * 0.36), fs, UI.color("text"), 0, 6)
	_badge(self, Vector2(rect.end.x - 6, rect.position.y + 4), count, accent)


# ------------------------------------------------------------------ card

func draw_card(c: CanvasItem, slot: int, entry: Array, rank: int, flash: float) -> void:
	if _brawl():
		_brawl_card(c, slot, entry, rank, flash)
		return
	var evo := _evolution()
	var hud := _hud()
	var id := str(entry[0])
	var s: Vector2 = c.size
	var category: String = CATEGORY_OF.get(id, "special")
	# Stage 28: the accent follows the rarity in every skin (category colour
	# only for old entries without one).
	var accent: Color = UI.tone(UI.CATEGORY.get(category, UI.VIOLET)) if entry.size() <= 3 else UI.rarity_color(str(entry[3]))
	var kind: String = evo.kind_of(id) if evo != null else "trait"
	var is_form := kind in ["attack", "evolved"]
	var banish: int = hud._count("banishes")
	var banish_local: Rect2 = hud._banish_rect(slot)
	banish_local.position -= hud._mutation_rect(slot).position

	var calm := UI.is_calm() and frames != null and use_frame_kit
	if calm:
		_kit_card(c, s, category, accent)
	elif frames != null and use_frame_kit:
		frames.card(c, Rect2(Vector2.ZERO, s), accent, "selected" if flash > 0.0 else "normal")
		frames.card_cells(c, Rect2(Vector2.ZERO, s), accent)
	else:
		_card_frame(c, s, accent, slot)
	if banish <= 0 and not (frames != null and use_frame_kit):
		for pore in [Vector2(-58, 30), Vector2(-40, 22), Vector2(-42, 42), Vector2(-26, 34)]:
			_ring(c, Vector2(s.x, 0) + pore, 7.0, Color(UI.color("outline"), 0.9), Color(accent, 0.55))

	if calm:
		# V2: the painted icon sits calmly in the card's own icon column.
		var k := s.y / KIT_CARD.y
		var col := Vector2(KIT_COLUMN * 0.5 * k, s.y * 0.5 + 8.0)
		_icon(c, id, Rect2(col - Vector2(68, 68), Vector2(136, 136)), accent)
		var plate := Rect2(Vector2(14, 12), Vector2(38, 38))
		c.draw_colored_polygon(_chamfer(plate, 8.0), Color(UI.CALM_BG, 0.96))
		c.draw_polyline(_closed(_chamfer(plate, 8.0)), accent, 2.5, true)
		_text(c, str(slot + 1), plate.get_center() + Vector2(0, 8), 22, UI.color("text"), 1, 0)
		if is_form and rank == 0:
			_plaque(c, Vector2(col.x + 18.0, 30.0), "NEU", UI.color("gold"))
	else:
		_draw_medallion(c, s, id, slot, accent, flash, is_form and rank == 0)
	_draw_card_text(c, s, evo, hud, id, entry, rank, accent, is_form, banish, banish_local, calm)
	if flash > 0.0:
		if calm:
			c.draw_colored_polygon(_chamfer(Rect2(Vector2.ZERO, s).grow(-4.0), 20.0), Color(accent.lightened(0.6), 0.28 * flash))
			_kit_slice(c, "mutation_card_focus", Rect2(Vector2.ZERO, s).grow(3.0 + 6.0 * flash), Color(1, 1, 1, flash))
		else:
			var shape := _card_shape(s)
			c.draw_colored_polygon(shape, Color(accent.lightened(0.7), 0.5 * flash))
			var glow := Geometry2D.offset_polygon(shape, 14.0 * flash + 4.0)
			if not glow.is_empty():
				var ring: PackedVector2Array = glow[0]
				ring.append(ring[0])
				c.draw_polyline(ring, Color(accent.lightened(0.5), flash), 6.0, true)


# Organic medallion (concept): a bulge of the frame band around a dark well,
# strong glow in the category colour outside and a lit core behind the icon.
func _draw_medallion(c: CanvasItem, s: Vector2, id: String, slot: int, accent: Color, flash: float, fresh: bool) -> void:
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
	c.draw_circle(nb, 15.5, UI.color("outline"))
	_text(c, str(slot + 1), nb + Vector2(0, 8), 22, UI.color("text"), 1, 0)
	if fresh:
		_plaque(c, Vector2(m.x, 16), "NEU", UI.color("gold"))


# Text column, bottom row and banish tag (both skins).
func _draw_card_text(c: CanvasItem, s: Vector2, evo: RefCounted, hud: Control, id: String, entry: Array, rank: int, accent: Color, is_form: bool, banish: int, banish_local: Rect2, calm: bool) -> void:
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
	_text(c, head, Vector2(x, 40), _fit(head, UI.display_font(), MIN_TEXT, head_right - x, MIN_TEXT), Color(accent.lerp(UI.color("text_dim"), 0.35), 0.95), 0, 5)
	var name := str(entry[1]).to_upper()
	var name_size := _fit(name, UI.display_font(), 48, name_right - x, 30)
	_text(c, name, Vector2(x, 92), name_size, accent.lightened(0.15 if calm else 0.08), 0, 6 if calm else 8)
	if not calm:
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
			_text(c, lines[i], Vector2(x, 136 + i * (fs + 2)), fs, UI.color("text"), 0, 5, UI.body_font())
	else:
		var effect := _effect(id, entry, rank + 1, true)
		_text(c, effect, Vector2(x, 150), _fit(effect, UI.display_font(), 34, col_w, 24), UI.color("text"), 0, 7)

	# Bottom row: rank diamonds, change, evolution hint.
	var row_y := 198.0
	for i in 3:
		var dc := Vector2(x + 12 + i * 30, row_y - 8)
		if i < rank:
			_diamond(c, dc, 11.0, accent)
		elif i == rank:
			var pulse := 0.5 + 0.5 * sin(_now() * 5.0)
			if not calm:
				c.draw_circle(dc, 15, Color(accent, 0.18 + 0.2 * pulse))
			_diamond(c, dc, 12.0, UI.color("text"))
			_diamond(c, dc, 8.0, accent)
		else:
			_diamond(c, dc, 11.0, Color(UI.color("outline"), 0.9))
			_diamond_outline(c, dc, 11.0, Color(accent, 0.45))
	var cx := x + 104.0
	if is_form:
		if rank > 0:
			cx += _text(c, "RANG %s" % ROMAN[rank - 1], Vector2(cx, row_y), 23, UI.color("text_dim"), 0, 5) + 10.0
			_arrow(c, Vector2(cx, row_y - 8), accent)
			cx += 38.0
			cx += _text(c, ROMAN[mini(rank, ROMAN.size() - 1)], Vector2(cx, row_y + 1), 28, UI.color("text"), 0, 6)
		else:
			cx += _text(c, "RANG I", Vector2(cx, row_y + 1), 26, UI.color("text"), 0, 6)
	else:
		var before := _effect(id, entry, rank, false)
		var after := _effect(id, entry, rank + 1, false)
		cx += _text(c, before, Vector2(cx, row_y), 23, UI.color("text_dim"), 0, 5) + 10.0
		_arrow(c, Vector2(cx, row_y - 8), accent)
		cx += 38.0
		cx += _text(c, after, Vector2(cx, row_y + 1), 28, UI.color("text"), 0, 6)
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
		var tint: Color = UI.color("gold") if hint.ready else UI.color("violet")
		var pill := Rect2(hx - 36, row_y - 26, lw + 46, 34)
		if calm:
			frames.pill(c, pill, tint)
		else:
			c.draw_rect(pill, Color(UI.color("outline"), 0.75))
			c.draw_rect(pill, Color(tint, 0.6), false, 2.0)
		_icon(c, hint.id, Rect2(hx - 32, row_y - 23, 28, 28), tint)
		_text(c, label, Vector2(hx, row_y - 1), fs, tint.lightened(0.2), 0, 5)

	if banish > 0:
		_draw_banish(c, banish_local, banish)


# Compact danger tag inside the card body (hit area: hud._banish_rect(slot)).
func _draw_banish(c: CanvasItem, r: Rect2, count: int) -> void:
	var red := UI.color("danger")
	if UI.is_calm() and frames != null:
		# V2 chip: dark petrol body, thin orange-red stroke, no halo.
		frames.pill(c, r, red)
		var glyph := minf(30.0, r.size.y - 14.0)
		_icon(c, "banish", Rect2(r.position + Vector2(12, (r.size.y - glyph) * 0.5), Vector2(glyph, glyph)), red)
		var gx := r.position.x + 20.0 + glyph
		var gfs := _fit("VERBANNEN", UI.display_font(), 23, r.end.x - 10.0 - gx, MIN_TEXT)
		var gw := _width("VERBANNEN", UI.display_font(), gfs)
		_text(c, "VERBANNEN", Vector2(gx + maxf(0.0, (r.end.x - 10.0 - gx - gw) * 0.5), r.get_center().y + gfs * 0.36), gfs, UI.color("text"), 0, 4)
		_badge(c, Vector2(r.end.x - 4, r.position.y + 2), count, red)
		return
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
	_text(c, "VERBANNEN", Vector2(tx + maxf(0.0, (r.end.x - 10.0 - tx - lw) * 0.5), r.get_center().y + fs * 0.36), fs, UI.color("text"), 0, 5)
	_badge(c, Vector2(r.end.x - 4, r.position.y + 2), count, red)


# V2 mutation card (mutation_card_<category>.svg, 660 x 170 units) as a
# nine-slice scaled to the card height: the icon column (divider at 146 units)
# keeps its width, the text area stretches.
const KIT_CARD := Vector2(660, 170)
const KIT_COLUMN := 146.0
const KIT_CARD_MARGINS := Vector4(160, 48, 24, 44)
const KIT_CARD_FILE := {"attack": "mutation_card_attack", "growth": "mutation_card_growth", "protect": "mutation_card_defense", "special": "mutation_card_special", "reflex": "mutation_card_special"}
var _kit_boxes: Dictionary = {}


func _kit_card(c: CanvasItem, s: Vector2, category: String, accent: Color) -> void:
	if not _kit_slice(c, KIT_CARD_FILE.get(category, "mutation_card_special"), Rect2(Vector2.ZERO, s), Color.WHITE):
		frames.card(c, Rect2(Vector2.ZERO, s), accent, "normal")


# Draws a kit card SVG as nine-slice into rect (scale follows rect height).
func _kit_slice(c: CanvasItem, file: String, rect: Rect2, tint: Color) -> bool:
	if not _kit_boxes.has(file):
		var tex: Texture2D = UI.tex("res://assets/ui/v2/vector/%s.svg" % file)
		var box: StyleBoxTexture = null
		if tex != null:
			# texture pixels per svg unit (imported with svg/scale 2)
			var tk := tex.get_width() / KIT_CARD.x
			box = StyleBoxTexture.new()
			box.texture = tex
			box.texture_margin_left = KIT_CARD_MARGINS.x * tk
			box.texture_margin_top = KIT_CARD_MARGINS.y * tk
			box.texture_margin_right = KIT_CARD_MARGINS.z * tk
			box.texture_margin_bottom = KIT_CARD_MARGINS.w * tk
		_kit_boxes[file] = box
	var kit_box: StyleBoxTexture = _kit_boxes[file]
	if kit_box == null:
		return false
	var tk2 := kit_box.texture.get_width() / KIT_CARD.x
	var k := rect.size.y / KIT_CARD.y / tk2
	kit_box.modulate_color = tint
	c.draw_set_transform(rect.position, 0.0, Vector2(k, k))
	c.draw_style_box(kit_box, Rect2(Vector2.ZERO, rect.size / k))
	c.draw_set_transform(Vector2.ZERO)
	return true


func _chamfer(r: Rect2, cut: float) -> PackedVector2Array:
	var p := r.position
	var e := r.end
	return PackedVector2Array([Vector2(p.x + cut, p.y), Vector2(e.x - cut, p.y), Vector2(e.x, p.y + cut), Vector2(e.x, e.y - cut),
		Vector2(e.x - cut, e.y), Vector2(p.x + cut, e.y), Vector2(p.x, e.y - cut), Vector2(p.x, p.y + cut)])


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := points.duplicate()
	out.append(points[0])
	return out


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
	var deep := Color(UI.color("panel"), 1.0).darkened(0.25)
	for v in body:
		var near_icon := 1.0 - clampf(v.x / (s.x * 0.45), 0.0, 1.0)
		body_colors.append(deep.lerp(Color(UI.color("panel"), 1.0).lerp(accent, 0.1), near_icon * 0.8))
	c.draw_polygon(body, body_colors)
	# Holes through the rim, bone teeth under the lower step.
	for hole in [Vector2(5, s.y * 0.22), Vector2(5, s.y * 0.84), Vector2(s.x - 5, s.y * 0.2), Vector2(s.x - 5, s.y * 0.8)]:
		_ellipse(c, hole, 3.5, 11.0, Color(UI.color("outline"), 0.95))
	for tx in [s.x * 0.4 - 26.0, s.x * 0.4 - 50.0]:
		c.draw_colored_polygon(PackedVector2Array([Vector2(tx - 7, s.y + 5), Vector2(tx + 7, s.y + 5), Vector2(tx + 1, s.y + 19)]), UI.color("bone").darkened(0.1))
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
		c.draw_polyline(ring, Color(UI.color("panel_edge"), 0.8), 1.5, true)


func _horn(c: CanvasItem, base: Vector2, tip: Vector2, accent: Color) -> void:
	var dir := (tip - base).normalized()
	var side := Vector2(-dir.y, dir.x)
	var mid := base.lerp(tip, 0.55) + side * 6.0
	c.draw_colored_polygon(PackedVector2Array([base + side * 11.0, mid + side * 4.0, tip, mid - side * 3.0, base - side * 11.0]), accent.lightened(0.1))
	c.draw_line(base.lerp(tip, 0.2), tip, Color(UI.color("bone"), 0.5), 2.0, true)


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
	if not glow.is_empty() and not UI.is_calm():
		c.draw_colored_polygon(glow[0], Color(tint, 0.3))
	c.draw_colored_polygon(pts, tint)
	_text(c, label, Vector2(center.x, center.y + 8), 22, UI.color("outline"), 1, 0)


func _badge(c: CanvasItem, center: Vector2, count: int, tint: Color) -> void:
	c.draw_circle(center, 17, UI.color("outline"))
	c.draw_circle(center, 14.5, tint)
	_text(c, str(count), center + Vector2(0, 8), MIN_TEXT, UI.color("outline"), 1, 0)


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


# Which evolution this card feeds, and whether the pick completes its rules
# (stage 17: weapon rank 5 + partner relic; stats never feed an evolution).
func _evolution_hint(evo: RefCounted, id: String, rank: int, entry: Array = []) -> Dictionary:
	if evo == null:
		return {}
	var item: Dictionary = entry[4] if entry.size() > 4 and entry[4] is Dictionary else {}
	var max_rank: int = int(evo.MAX_RANK)
	for rule in evo.EVOLUTION_RULES:
		if evo.evolutions.has(rule.id) or (id != rule.base and id != rule.partner):
			continue
		if evo.kind_of(id) == "trait":
			continue
		var stacks: int = evo.stacks(rule.partner) if evo.has_method("stacks") else evo.rank(rule.partner)
		# A partner relic only points at evolutions whose weapon is owned.
		if id == rule.partner and evo.rank(rule.base) <= 0:
			continue
		var base_rank: int = evo.rank(rule.base)
		if id == rule.base:
			base_rank = int(item.get("to", rank + 1))
		var partner: int = stacks + (1 if id == rule.partner else 0)
		var name := str(evo.info(rule.id)[1]).to_upper()
		if base_rank >= max_rank and partner >= 1:
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
		c.draw_string_outline(face, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, step, outline, Color(UI.color("outline"), tint.a))
	c.draw_string(face, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, step, UI.tone(tint))
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



# ================================================================== brawl skin
# Stage 15, package C: level-up moment (S6), mutation cards (S7) with the
# evolution hint (S8). Drawn only with ui_kit_brawl.gd and UiStyle tokens.

var _footer: PaintView


func _start_moment(now: float) -> void:
	_moment_time = now
	var evo := _evolution()
	_moment_level = int(evo.level) if evo != null else -1
	_leader_at = _locate_leader()


func _process_brawl(now: float, open: bool) -> void:
	if _footer == null:
		_footer = PaintView.new()
		_footer.name = "Footer"
		_footer.painter = _paint_footer
		add_child(_footer)
		move_child(_footer, _ribbon.get_index() + 1)
	var t := now - _moment_time
	var dim := _ease((now - _open_time) / LV_DIM) if open else 1.0 - _ease((now - _close_time) / DIM_OUT)
	_desat.visible = dim > 0.0
	if _desat.visible:
		_desat.position = Vector2.ZERO
		_desat.size = size
		(_desat.material as ShaderMaterial).set_shader_parameter("amount", dim)
	var evo := _evolution()
	var hud := _hud()
	# While choosing, world popups and banners (later siblings) stay under the
	# cards; pause/result close the choice first, so they are never covered.
	z_index = 1 if open else 0
	_ribbon.visible = open
	_footer.visible = open
	if open:
		var g := _geometry()
		var rr := _ribbon_rect(g)
		var e := clampf((t - LV_RIBBON.x) / LV_RIBBON.y, 0.0, 1.0)
		_ribbon.position = rr.position
		_ribbon.size = rr.size
		_ribbon.pivot_offset = rr.size * 0.5
		_ribbon.scale = Vector2.ONE * lerpf(1.35, 1.0, _back(e))
		_ribbon.modulate = Color(1, 1, 1, clampf(e * 3.0, 0.0, 1.0))
		_ribbon.refresh([rr.size, int(evo.level), mode(), _shrine(), chest_title(), _cores_taken()])
		_footer.position = Vector2.ZERO
		_footer.size = size
		_footer.modulate = Color(1, 1, 1, clampf((t - 0.34) / 0.22, 0.0, 1.0))
		_footer.refresh([size, layout, _counter("rerolls"), _counter("skips"), _counter("banishes"), entries().size(), mode()])
		var offers: Array = entries()
		var fresh := t < 0.05
		var changed := 0
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
				if fresh:
					_slot_start[slot] = _moment_time + LV_CARD.x + slot * LV_STAGGER
				else:
					_slot_start[slot] = now + changed * 0.05
				changed += 1
			var rank: int = evo.rank(id)
			_snapshot.append([entry, rank])
			var rect := card_rect(slot)
			var dur := LV_CARD.y if t < LV_TOTAL else LV_REDEAL
			var k := clampf((now - _slot_start[slot]) / dur, 0.0, 1.0)
			card.visible = true
			card.entry = entry
			card.rank = rank
			card.flash = 0.0
			card.size = rect.size
			card.pivot_offset = rect.size * 0.5
			card.position = rect.position + Vector2(0.0, (1.0 - _ease(k)) * 140.0)
			card.scale = Vector2.ONE * lerpf(0.82, 1.0, _back(k))
			card.modulate = Color(1, 1, 1, clampf(k * 2.5, 0.0, 1.0))
			card.refresh(_brawl_card_key(slot, entry, rank, 0.0, rect.size))
	else:
		for card in _cards:
			card.visible = false
	var ft := (now - _flash_time) / FLASH
	_flash_card.visible = ft < 1.0 and hud != null
	if _flash_card.visible:
		var rect := card_rect(_flash_card.slot)
		var e := _ease(ft)
		_flash_card.size = rect.size
		_flash_card.pivot_offset = rect.size * 0.5
		_flash_card.position = rect.position
		_flash_card.scale = Vector2.ONE * (1.0 + 0.05 * e)
		_flash_card.flash = 1.0 - e
		_flash_card.modulate = Color(1, 1, 1, 1.0 - e * e)
		_flash_card.refresh(_brawl_card_key(_flash_card.slot, _flash_card.entry, _flash_card.rank, _flash_card.flash, rect.size))
	var key: Variant = null
	if open and t >= LV_TOTAL + 0.1 and now - _open_time >= LV_TOTAL + 0.1:
		key = ["open", size, layout, _counter("banishes"), entries().size(), mode()]
	elif not open and now - _close_time >= DIM_OUT + 0.05:
		key = ["closed", size]
	if key == null or typeof(key) != typeof(_screen_key) or key != _screen_key:
		queue_redraw()
	_screen_key = key


func _brawl_card_key(slot: int, entry: Array, rank: int, flash: float, card_size: Vector2) -> Array:
	var evo := _evolution()
	var hud := _hud()
	var key: Array = [slot, entry, rank, flash, layout, card_size, UI.colorblind, mode()]
	if hud != null:
		key.append(_counter("banishes"))
	if evo != null:
		key.append_array([str(evo.ranks), str(evo.evolutions), evo.slots_used("attack"), evo.slots_used("trait")])
		if "relics" in evo:
			key.append(str(evo.relics))
	# Legendary and evolution cards carry a moving glint (20 Hz repaint of that card only).
	var evolution := entry.size() > 4 and entry[4] is Dictionary and String(entry[4].get("type", "")) == "evolution"
	if (entry.size() > 3 and str(entry[3]) == "legendary") or evolution:
		key.append(int(_now() * 20.0))
	return key


func _ribbon_rect(g: Dictionary) -> Rect2:
	return Rect2(Vector2(size.x * 0.5 - B_RIBBON.x * 0.5, g.top), B_RIBBON)


# Screen point under the leader (for the light column), INF when unknown.
func _locate_leader() -> Vector2:
	if not is_inside_tree():
		return Vector2.INF
	if _swarm_node == null or not is_instance_valid(_swarm_node):
		_swarm_node = get_tree().get_first_node_in_group("swarm") as Node3D
	var camera := get_viewport().get_camera_3d()
	if _swarm_node == null or camera == null or not _swarm_node.has_method("leader_display"):
		return Vector2.INF
	var info: Dictionary = _swarm_node.call("leader_display")
	if not bool(info.get("visible", false)):
		return Vector2.INF
	var anchor: Vector3 = info.anchor
	var foot := Vector3(anchor.x, 0.0, anchor.z)
	if camera.is_position_behind(foot):
		return Vector2.INF
	return camera.unproject_position(foot)


# ------------------------------------------------------------------ brawl screen

func _draw_brawl() -> void:
	var now := _now()
	var open := _open()
	var t := now - _moment_time
	var dim := _ease((now - _open_time) / LV_DIM) if open else 1.0 - _ease((now - _close_time) / DIM_OUT)
	if dim <= 0.0:
		return
	# The top HUD stays half readable; below it the world sinks away.
	var band := 150.0
	Kit.dim(self, Rect2(Vector2.ZERO, size), 0.38 * dim)
	var ramp := 8
	for i in ramp:
		var y := band - 64.0 + i * 8.0
		Kit.dim(self, Rect2(0.0, y, size.x, 8.0), 0.34 * dim * float(i + 1) / (ramp + 1))
	Kit.dim(self, Rect2(0.0, band, size.x, size.y - band), 0.34 * dim)
	if not open or t >= LV_BEAM_OUT.y:
		return
	var k := _ease(t / 0.1) * (1.0 - clampf((t - LV_BEAM_OUT.x) / (LV_BEAM_OUT.y - LV_BEAM_OUT.x), 0.0, 1.0))
	_draw_beam(k)


# Light column from the top of the screen onto the leader.
func _draw_beam(k: float) -> void:
	if k <= 0.0:
		return
	var foot := _leader_at
	if foot == Vector2.INF or not Rect2(Vector2.ZERO, size).has_point(foot):
		foot = Vector2(size.x * 0.5, size.y * 0.55)
	var gold: Dictionary = UI.brawl_tone("loot")
	for layer in [[170.0, Color(gold["light"], 0.42 * k)], [54.0, Color(Color.WHITE, 0.7 * k)]]:
		var w: float = layer[0]
		var col: Color = layer[1]
		var clear := Color(col, 0.0)
		var top_col := Color(col, col.a * 0.25)
		for side: float in [-1.0, 1.0]:
			var pts := PackedVector2Array([Vector2(foot.x, 0.0), Vector2(foot.x + side * w * 0.75, 0.0), Vector2(foot.x + side * w * 0.5, foot.y), Vector2(foot.x, foot.y)])
			draw_polygon(pts, PackedColorArray([top_col, clear, clear, col]))
	# Pool of light at the leader's feet.
	draw_set_transform(foot, 0.0, Vector2(1.0, 0.42))
	Kit.disc(self, Vector2.ZERO, 150.0, Color(gold["light"], 0.2 * k))
	Kit.disc(self, Vector2.ZERO, 96.0, Color(gold["light"], 0.3 * k))
	Kit.disc(self, Vector2.ZERO, 52.0, Color(Color.WHITE, 0.55 * k))
	draw_set_transform(Vector2.ZERO)


func _paint_ribbon(c: CanvasItem) -> void:
	var evo := _evolution()
	var r := Rect2(Vector2.ZERO, B_RIBBON)
	if mode() == "core":
		# Stage 33: violet ribbon with a violet halo; which core of the run this is.
		Kit.glow(c, r.grow(-10.0), 22.0, CorePlaque.ACCENT, 0.5)
		Kit.ribbon(c, r, "special")
		Kit.text_outlined(c, Vector2(r.size.x * 0.5, r.size.y * 0.5 - 3.0), "MUTATIONSKERN", UI.T_TITLE, UI.BRAWL_TEXT, -1, -1, null, Kit.CENTER | Kit.MIDDLE, r.size.x - 44.0)
		Kit.text_outlined(c, Vector2(r.size.x * 0.5, r.end.y + 36.0), "KERN %d / 3  ·  WÄHLE 1 AUS 3" % mini(3, _cores_taken() + 1), UI.T_BODY, UI.rarity_tone("legendary")["light"], -1, -1, null, Kit.CENTER | Kit.MIDDLE)
		return
	var chest := mode() == "chest"
	# Etappe 17 Welle 2: a charged shrine opens the same stat choice (rare or better).
	var shrine := not chest and _shrine()
	Kit.ribbon(c, r, "loot" if chest else ("info" if shrine else "special"))
	Kit.text_outlined(c, Vector2(r.size.x * 0.5, r.size.y * 0.5 - 3.0), chest_title() if chest else ("SCHREIN!" if shrine else "MUTATION!"), UI.T_HERO, UI.BRAWL_TEXT, -1, -1, null, Kit.CENTER | Kit.MIDDLE, r.size.x - 44.0)
	if chest:
		Kit.text_outlined(c, Vector2(r.size.x * 0.5, r.end.y + 36.0), "WÄHLE 1 AUS 3", UI.T_BODY, UI.BRAWL_TEXT, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
	elif shrine:
		Kit.text_outlined(c, Vector2(r.size.x * 0.5, r.end.y + 36.0), "MINDESTENS SELTEN", UI.T_BODY, UI.BRAWL_TEXT, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
	elif evo != null:
		Kit.text_outlined(c, Vector2(r.size.x * 0.5, r.end.y + 36.0), "STUFE %d" % (int(evo.level) + 1), UI.T_BODY, UI.BRAWL_TEXT, -1, -1, null, Kit.CENTER | Kit.MIDDLE)


func _paint_footer(c: CanvasItem) -> void:
	var hud := _hud()
	if hud == null or _evolution() == null:
		return
	var rerolls: int = _counter("rerolls")
	var skips: int = _counter("skips")
	if rerolls > 0:
		_brawl_button(c, reroll_rect(), "reroll", "NEU WÜRFELN", rerolls)
	if skips > 0:
		_brawl_button(c, skip_rect(), "skip", "ÜBERSPRINGEN", skips)
	var g := _geometry()
	var hint := "KARTE ANTIPPEN ZUM WÄHLEN"
	match mode():
		"chest":
			hint = "BEUTE ANTIPPEN ZUM WÄHLEN"
		"core":
			hint = "EIN KERN GILT FÜR DEN GANZEN RUN"
	Kit.text_outlined(c, Vector2(size.x * 0.5, g.hint_y), hint, UI.T_LABEL, UI.BRAWL_TEXT_DIM, -1, -1, null, Kit.CENTER | Kit.MIDDLE, size.x - 2.0 * B_SIDE)


func _brawl_button(c: CanvasItem, r: Rect2, icon_id: String, label: String, count: int) -> void:
	Kit.button(c, r, "neutral")
	var mid := Kit.button_label_center(r)
	var glyph := 50.0
	var gx := r.position.x + 22.0
	_icon(c, icon_id, Rect2(Vector2(gx, mid.y - glyph * 0.5), Vector2(glyph, glyph)), Color.WHITE)
	var left := gx + glyph + 10.0
	var avail := r.end.x - 30.0 - left
	Kit.text_outlined(c, Vector2(left + avail * 0.5, mid.y), label, UI.T_HEAD, UI.BRAWL_TEXT, -1, -1, null, Kit.CENTER | Kit.MIDDLE, avail)
	Kit.badge(c, Vector2(r.end.x - 12.0, r.position.y + 4.0), str(count), "info", UI.T_LABEL)


# ------------------------------------------------------------------ brawl card

func _brawl_card(c: CanvasItem, _slot: int, entry: Array, rank: int, flash: float) -> void:
	if _is_core(entry):
		_core_card(c, entry, flash)
		return
	var evo := _evolution()
	var id := str(entry[0])
	var s: Vector2 = c.size
	var st := _card_style(evo, id, entry, rank)
	var rect := Rect2(Vector2.ZERO, s)
	_rarity_rim(c, rect, st)
	Kit.card(c, rect, st.tone, "selected" if flash > 0.0 else "normal", B_HEADER)
	var inset := UI.STROKE_L + 7.0
	var head := Rect2(Vector2(inset, inset), Vector2(s.x - 2.0 * inset, B_HEADER))
	var body := Rect2(Vector2(inset, inset + B_HEADER), Vector2(s.x - 2.0 * inset, s.y - 2.0 * inset - B_HEADER))
	var head_right := head.end.x - 12.0
	var banish: int = _counter("banishes")
	if banish > 0:
		var bc := _banish_center(rect)
		head_right = bc.x - B_BANISH_R - 14.0
	# Rarity chip at the right of the header ("SELTEN" in the rarity tone).
	head_right = _rarity_chip(c, Vector2(head_right, head.get_center().y), st) - 14.0
	if layout == "columns":
		_card_columns(c, s, head, body, head_right, evo, id, entry, rank, st)
	else:
		_card_stack(c, head, body, head_right, evo, id, entry, rank, st)
	_category_tab(c, rect, st)
	# Evolutions keep their gold glint on top of the rarity colour.
	if st.rarity == "legendary" or st.kind == "evolved":
		_legend_glint(c, rect)
	if banish > 0:
		_banish_button(c, _banish_center(rect), banish)
	if flash > 0.0:
		Kit.rrect(c, rect.grow(-UI.STROKE_L), UI.R_L - UI.STROKE_L, Color(UI.brawl_tone(st.tone)["light"], 0.25 * flash))


# Outer rim in the rarity tone (common: none); legendary with a soft gold halo.
# Evolved forms keep their gold rim.
func _rarity_rim(c: CanvasItem, rect: Rect2, st: Dictionary) -> void:
	var tone: String = "loot" if st.gold else String(st.rarity)
	if st.rarity == "common" and not st.gold:
		return
	var t: Dictionary = UI.brawl_tone(tone)
	if st.rarity == "legendary" or st.gold:
		Kit.glow(c, rect.grow(6.0), 26.0, tone, 0.55 + 0.15 * sin(_now() * 3.0))
	Kit.rrect(c, rect.grow(12.0), UI.R_L + 12.0, Color(t["light"], 0.3))
	Kit.ring(c, rect.grow(9.0), UI.R_L + 9.0, 6.0, t["face"])


# Rarity chip right-aligned at `anchor`; returns its left edge.
func _rarity_chip(c: CanvasItem, anchor: Vector2, st: Dictionary) -> float:
	var label := UI.rarity_name(st.rarity)
	var font := UI.display_font()
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.T_LABEL).x + 30.0
	var h := 42.0
	var r := Rect2(Vector2(anchor.x - w, anchor.y - h * 0.5), Vector2(w, h))
	Kit.chip(c, r, st.rarity)
	Kit.text_outlined(c, Vector2(r.get_center().x, r.get_center().y - 1.0), label, UI.T_LABEL, UI.BRAWL_TEXT, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
	return r.position.x


# Stage 28: small category tab ("WAFFE", "WERT · ANGRIFF", "EVOLUTION") on the
# card's top edge, left; a dark capsule so it never competes with the rarity.
func _category_tab(c: CanvasItem, rect: Rect2, st: Dictionary) -> void:
	var label := String(st.get("kind_label", ""))
	if label == "":
		return
	var font := UI.display_font()
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.T_LABEL).x + 32.0
	var h := 36.0
	var r := Rect2(Vector2(rect.position.x + 26.0, rect.position.y - h * 0.5 - 2.0), Vector2(w, h))
	Kit.pill(c, r, "dark", UI.STROKE_S)
	Kit.text_outlined(c, Vector2(r.get_center().x, r.get_center().y - 1.0), label, UI.T_LABEL, UI.brawl_tone(st.rarity)["light"], -1, -1, null, Kit.CENTER | Kit.MIDDLE)


# Diagonal light band sweeping over a legendary card every LEGEND_GLINT s.
func _legend_glint(c: CanvasItem, rect: Rect2) -> void:
	var inner := rect.grow(-UI.STROKE_L - 2.0)
	var t := fmod(_now(), LEGEND_GLINT) / LEGEND_GLINT
	if t > 0.55:
		return
	var k := t / 0.55
	var band := 70.0
	var skew := inner.size.y * 0.45
	var x := lerpf(inner.position.x - band - skew, inner.end.x + skew, k)
	var top := inner.position.y
	var bottom := inner.end.y
	var pts := PackedVector2Array([
		Vector2(clampf(x + skew, inner.position.x, inner.end.x), top),
		Vector2(clampf(x + skew + band, inner.position.x, inner.end.x), top),
		Vector2(clampf(x + band, inner.position.x, inner.end.x), bottom),
		Vector2(clampf(x, inner.position.x, inner.end.x), bottom)])
	if pts[1].x - pts[0].x < 1.0 and pts[2].x - pts[3].x < 1.0:
		return
	var a := 0.16 * sin(k * PI)
	c.draw_polygon(pts, PackedColorArray([Color(1, 1, 1, a), Color(1, 1, 1, a * 0.4), Color(1, 1, 1, a * 0.4), Color(1, 1, 1, a)]))


# Wide card: header with title (rarity chip right), icon plate left, value or
# text right, rank row + kind (or evolution pill) at the bottom.
func _card_stack(c: CanvasItem, head: Rect2, body: Rect2, head_right: float, evo: RefCounted, id: String, entry: Array, rank: int, st: Dictionary) -> void:
	var hy := head.get_center().y
	var title_x := head.position.x + 18.0
	Kit.text_outlined(c, Vector2(title_x, hy), str(entry[1]).to_upper(), UI.T_HEAD, UI.BRAWL_TEXT, -1, -1, null, Kit.LEFT | Kit.MIDDLE, head_right - title_x)
	var plate := 128.0
	var pc := Vector2(body.position.x + 20.0 + plate * 0.5, body.get_center().y + 2.0)
	_plate_with_icon(c, pc, plate, st, rank)
	var x0 := pc.x + plate * 0.5 + 24.0
	var right := body.end.x - 20.0
	var width := right - x0
	var row_y := body.end.y - 30.0
	if st.kind == "trait":
		var vals := _trait_values(evo, id, entry, rank)
		if vals.has("text"):
			Kit.paragraph(c, Vector2(x0, body.position.y + 38.0), vals.text, width, UI.T_BODY, UI.BRAWL_TEXT, false, Kit.LEFT, 3)
		else:
			_value_line(c, Vector2(x0, body.position.y + 44.0), vals.before, vals.after, st, width, Kit.LEFT)
			Kit.paragraph(c, Vector2(x0, body.position.y + 108.0), vals.label, width, UI.T_BODY, UI.BRAWL_TEXT, true, Kit.LEFT, 1)
	else:
		Kit.paragraph(c, Vector2(x0, body.position.y + 38.0), _item_body(id, entry, rank, st), width, UI.T_BODY, UI.BRAWL_TEXT, false, Kit.LEFT, 3)
	var x := x0
	if int(st.pips) > 0:
		x = _pips(c, Vector2(x0, row_y), rank, st, evo) + 18.0
	if st.change != "":
		x += _rank_change(c, Vector2(x, row_y), rank, st, Kit.LEFT) + 18.0
	_evo_pill(c, Vector2(right, row_y), evo, id, rank, Kit.RIGHT, right - x, entry)


# Portrait card (kit preview): header title, big plate, value, text, rank row.
func _card_columns(c: CanvasItem, s: Vector2, head: Rect2, body: Rect2, head_right: float, evo: RefCounted, id: String, entry: Array, rank: int, st: Dictionary) -> void:
	var hy := head.get_center().y
	var title_left := head.position.x + 14.0
	Kit.text_outlined(c, Vector2((title_left + head_right) * 0.5, hy), str(entry[1]).to_upper(), UI.T_HEAD, UI.BRAWL_TEXT, -1, -1, null, Kit.CENTER | Kit.MIDDLE, head_right - title_left)
	var cx := s.x * 0.5
	var plate := 128.0
	var pc := Vector2(cx, body.position.y + 24.0 + plate * 0.5)
	_plate_with_icon(c, pc, plate, st, rank)
	var width := body.size.x - 28.0
	var y := pc.y + plate * 0.5 + 84.0
	var text := ""
	if st.kind != "trait":
		if st.change != "":
			_rank_change(c, Vector2(cx, y), rank, st, Kit.CENTER)
		text = _item_body(id, entry, rank, st)
	else:
		var vals := _trait_values(evo, id, entry, rank)
		if vals.has("text"):
			text = vals.text
			y -= 30.0
		else:
			_value_line(c, Vector2(cx, y), vals.before, vals.after, st, width, Kit.CENTER)
			text = vals.label
	Kit.paragraph(c, Vector2(body.position.x + 14.0, y + 52.0), text, width, UI.T_BODY, UI.BRAWL_TEXT, st.kind == "trait", Kit.CENTER, 7)
	var row_y := body.end.y - 30.0
	if _evolution_hint(evo, id, rank, entry).is_empty():
		if int(st.pips) > 0:
			_pips(c, Vector2(cx - 80.0, row_y), rank, st, evo)
	else:
		if int(st.pips) > 0:
			_pips(c, Vector2(cx - 80.0, row_y - 58.0), rank, st, evo)
		_evo_pill(c, Vector2(cx, row_y), evo, id, rank, Kit.CENTER, width, entry)


func _plate_with_icon(c: CanvasItem, pc: Vector2, plate: float, st: Dictionary, rank: int) -> void:
	Kit.icon_plate(c, pc, plate, st.tone)
	var ic := Kit.plate_center(pc, plate)
	var side := plate * 0.8
	_icon(c, st.icon, Rect2(ic - Vector2(side, side) * 0.5, Vector2(side, side)), Color.WHITE)
	# "NEU" for something new, else the rank/stack this pick reaches.
	if st.badge == "NEU":
		Kit.badge(c, pc + Vector2(plate * 0.36, -plate * 0.44), "NEU", "loot", UI.T_LABEL)
	elif st.badge != "":
		Kit.badge(c, pc + Vector2(0.0, plate * 0.5), st.badge, "neutral", UI.T_LABEL)


# "0 % → +25 %": before dimmed, arrow in the card tone, after big.
func _value_line(c: CanvasItem, at: Vector2, before: String, after: String, st: Dictionary, width: float, align: int) -> void:
	var t: Dictionary = UI.brawl_tone(st.tone)
	var nf := UI.number_font()
	var w_before := nf.get_string_size(before, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.T_HEAD).x
	var w_arrow := nf.get_string_size("→", HORIZONTAL_ALIGNMENT_LEFT, -1, UI.T_HEAD).x
	var w_after := nf.get_string_size(after, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.T_TITLE).x
	var gap := 12.0
	var total := w_before + w_arrow + w_after + gap * 2.0
	var k := minf(1.0, width / total)
	var x := at.x - (total * k * 0.5 if align == Kit.CENTER else 0.0)
	x += Kit.number(c, Vector2(x, at.y), before, UI.T_HEAD, UI.BRAWL_TEXT_DIM, Kit.LEFT | Kit.MIDDLE, w_before * k) + gap * k
	x += Kit.text_outlined(c, Vector2(x, at.y), "→", UI.T_HEAD, t["light"], -1, -1, nf, Kit.LEFT | Kit.MIDDLE, w_arrow * k) + gap * k
	Kit.number(c, Vector2(x, at.y), after, UI.T_TITLE, UI.BRAWL_TEXT, Kit.LEFT | Kit.MIDDLE, w_after * k)


# "RANG 1 → 2" / "STAPEL 1 → 2" (or "RANG 2" for something new); returns
# the width. Digits, not roman numerals: Baloo draws "I" as a plain bar.
func _rank_change(c: CanvasItem, at: Vector2, _rank: int, st: Dictionary, align: int) -> float:
	var t: Dictionary = UI.brawl_tone(st.tone)
	var parts: Array = [[str(st.change) + " ", UI.T_LABEL, UI.BRAWL_TEXT_DIM]]
	if int(st.from) > 0:
		parts.append(["%d " % int(st.from), UI.T_HEAD, UI.BRAWL_TEXT_DIM])
		parts.append(["→ ", UI.T_HEAD, t["light"]])
	parts.append(["%d" % int(st.to), UI.T_HEAD, UI.BRAWL_TEXT])
	var nf := UI.number_font()
	var total := 0.0
	for p in parts:
		total += nf.get_string_size(p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, p[1]).x
	var x := at.x - (total * 0.5 if align == Kit.CENTER else 0.0)
	for p in parts:
		x += Kit.text_outlined(c, Vector2(x, at.y), p[0], p[1], p[2], -1, -1, nf, Kit.LEFT | Kit.MIDDLE)
	return total


# Rank pips (st.pips of them): owned ranks filled, the ranks this pick adds
# highlighted; returns the x right of the last one.
func _pips(c: CanvasItem, at: Vector2, _rank: int, st: Dictionary, _evo: RefCounted) -> float:
	var t: Dictionary = UI.brawl_tone(st.tone)
	var count: int = int(st.pips)
	var x := at.x
	for i in count:
		var pc := Vector2(x + 13.0, at.y)
		Kit.disc(c, pc + Vector2(0, 2), 14.0, UI.BRAWL_INK_SOFT)
		Kit.disc(c, pc, 14.0, UI.BRAWL_INK)
		if i < int(st.from):
			Kit.disc(c, pc, 10.5, t["face"])
			Kit.disc(c, pc - Vector2(0, 2), 6.0, Color(t["light"], 0.9))
		elif i < int(st.to):
			Kit.disc(c, pc, 10.5, Color.WHITE)
			Kit.disc(c, pc, 6.5, t["face"])
		else:
			Kit.disc(c, pc, 10.5, UI.BRAWL_WELL)
		x += 32.0
	return x - 6.0


# Small pill "→ STURMRUDEL" (special); gold when this pick makes it ready.
func _evo_pill(c: CanvasItem, anchor: Vector2, evo: RefCounted, id: String, rank: int, align: int, max_w: float, entry: Array = []) -> bool:
	var hint := _evolution_hint(evo, id, rank, entry)
	if hint.is_empty():
		return false
	var label := "→ " + str(hint.short)
	var font := UI.display_font()
	var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.T_LABEL).x
	var h := 46.0
	var icon := 34.0
	var w := minf(tw + icon + 40.0, maxf(max_w, 200.0))
	var x := anchor.x - w if align == Kit.RIGHT else (anchor.x - w * 0.5 if align == Kit.CENTER else anchor.x)
	var r := Rect2(Vector2(x, anchor.y - h * 0.5), Vector2(w, h))
	Kit.pill(c, r, "loot" if hint.ready else "special", UI.STROKE_S)
	_icon(c, hint.id, Rect2(Vector2(r.position.x + 10.0, r.get_center().y - icon * 0.5 - 1.0), Vector2(icon, icon)), Color.WHITE)
	var tx := r.position.x + icon + 18.0
	Kit.text_outlined(c, Vector2(tx, r.get_center().y - 1.0), label, UI.T_LABEL, UI.BRAWL_TEXT, -1, -1, null, Kit.LEFT | Kit.MIDDLE, r.end.x - 14.0 - tx)
	return true


func _banish_button(c: CanvasItem, center: Vector2, count: int) -> void:
	Kit.round_button(c, center, B_BANISH_R, "danger")
	var lc := Kit.round_label_center(center, B_BANISH_R)
	_icon(c, "banish", Rect2(lc - Vector2(20, 20), Vector2(40, 40)), Color.WHITE)
	Kit.badge(c, center + Vector2(B_BANISH_R * 0.8, -B_BANISH_R * 0.8), str(count), "neutral", UI.T_LABEL)


# ------------------------------------------------------------------ brawl data

# Tone, labels, rank data and icon of a card; new ids get a sensible default.
# Stage 17 keys: rarity, pips, from/to (rank or stack), change ("RANG"/"STAPEL"
# or ""), badge ("NEU", "RANG 3", "×2", "EVO").
func _card_style(evo: RefCounted, id: String, entry: Array, rank: int) -> Dictionary:
	var kind: String = evo.kind_of(id) if evo != null else ""
	if kind == "":
		kind = "attack" if _forms.has(id) else "trait"
	var item: Dictionary = entry[4] if entry.size() > 4 and entry[4] is Dictionary else {}
	var rarity := str(entry[3]) if entry.size() > 3 else "common"
	if not UI.RARITY_TONES.has(rarity):
		rarity = "common"
	# Stage 28: frame, header, plate, pips and chip all take the RARITY tone (a
	# rarity id is a valid kit tone); the category is only the small tab label.
	var st := {"kind": kind, "rarity": rarity, "tone": rarity, "is_form": kind in ["attack", "evolved"], "gold": false,
		"icon": _icon_id(evo, id), "pips": 0, "from": rank, "to": rank + 1, "change": "", "badge": ""}
	var max_rank: int = int(evo.MAX_RANK) if evo != null else 5
	if kind == "evolved":
		st.gold = true
		st.kind_label = "EVOLUTION"
		st.badge = "EVO"
	elif kind == "attack":
		st.kind_label = "WAFFE"
		st.pips = max_rank
		st.from = int(item.get("from", rank))
		st.to = int(item.get("to", mini(max_rank, rank + 1)))
		st.change = "RANG"
		st.badge = "NEU" if int(st.from) == 0 else "RANG %d" % int(st.to)
		if int(st.from) > 0:
			st.kind_label = "WAFFE · RANG +%d" % maxi(1, int(st.to) - int(st.from))
	elif kind == "overdrive":
		# Stage 31 A: Limit Break card; the running total is in its text
		# ("+3 % Schaden · gesamt +15 %"), no rank pips.
		st.kind_label = "HEILUNG" if id == "od_heal" else "ÜBERLADUNG"
	elif kind == "relic":
		st.kind_label = "RELIKT"
		var owned: int = evo.stacks(id) if evo != null and evo.has_method("stacks") else 0
		st.from = int(item.get("from", owned))
		st.to = int(item.get("to", int(st.from) + 1))
		st.change = "STAPEL" if int(st.from) > 0 else ""
		st.badge = "NEU" if int(st.from) == 0 else "×%d" % int(st.to)
	else:
		var d: Dictionary = STATS.definition(id)
		var branch: String = STAT_BRANCH.get(String(d.get("cat", "")), BRANCH_OF.get(id, _guess_branch(str(entry[2]) if entry.size() > 2 else "")))
		st.kind_label = "WERT · " + str(BRANCH_LABEL[branch])
		st.pips = max_rank
		st.badge = "NEU" if rank == 0 else "RANG %d" % (rank + 1)
	# Build slots (user decision 28.09.2026): a NEW weapon/stat/relic shows the
	# slot it takes in the category tab ("WAFFE 3/4", "WERT 5/6 · ANGRIFF").
	if kind in ["attack", "trait", "relic"] and int(st.from) == 0 and evo != null and evo.has_method("slot_limit"):
		var limit: int = int(evo.slot_limit(kind))
		if limit > 0:
			var place := "%d/%d" % [mini(int(evo.slots_used(kind)) + 1, limit), limit]
			var label := String(st.kind_label)
			var dot := label.find(" · ")
			st.kind_label = (label.substr(0, dot) + " " + place + label.substr(dot)) if dot >= 0 else label + " " + place
	var hint := _evolution_hint(evo, id, rank, entry)
	if not hint.is_empty() and hint.ready:
		st.gold = true
	return st


# Text of a weapon / relic / evolution card.
func _item_body(id: String, entry: Array, _rank: int, st: Dictionary) -> String:
	match String(st.kind):
		"attack":
			var text := _form_text(id, maxi(0, int(st.to) - 1))
			return text if text != "" else (str(entry[2]) if entry.size() > 2 else "")
		"evolved":
			var evolved := _form_text(id, 0)
			return evolved if evolved != "" else (str(entry[2]) if entry.size() > 2 else "")
	return str(entry[2]) if entry.size() > 2 else ""


static func _guess_branch(desc: String) -> String:
	var d := desc.to_lower()
	for word in ["verlust", " lp", "rückschaden", "panzer"]:
		if d.contains(word):
			return "protect"
	for word in ["biomasse", "sammel", "brut", "radius", "wachstum"]:
		if d.contains(word):
			return "growth"
	if d.contains("schaden"):
		return "attack"
	return "special"


func _icon_id(evo: RefCounted, id: String) -> String:
	if icons != null and icons.has(id):
		return id
	if evo != null:
		var map: Variant = evo.get_script().get_script_constant_map().get("ICON_IDS")
		if map is Dictionary and map.has(id):
			return str(map[id])
	return id


func _form_body(id: String, entry: Array, rank: int) -> String:
	var text := _form_text(id, rank)
	return text if text != "" else (str(entry[2]) if entry.size() > 2 else "")


# {before, after, label} for a percentage trait, {text} otherwise.
func _trait_values(evo: RefCounted, id: String, entry: Array, rank: int) -> Dictionary:
	# Stage 17: value before -> after with this card's rarity (stats.gd).
	if evo != null and evo.has_method("stat_preview") and STATS.has(id):
		var preview: Dictionary = evo.stat_preview(id, str(entry[3]) if entry.size() > 3 else "common")
		if not preview.is_empty():
			return preview
	if id == "regeneration" and evo != null and "REGEN_KILLS" in evo:
		var kills: Array = evo.REGEN_KILLS
		var gaps: Array = evo.REGEN_GAP
		var next := clampi(rank, 0, kills.size() - 1)
		return {"before": "–" if rank <= 0 else str(kills[rank - 1]), "after": str(kills[next]),
			"label": "Kills je +1 LP (höchstens alle %d s)" % int(gaps[next])}
	var desc := str(entry[2]) if entry.size() > 2 else ""
	var found := RegEx.create_from_string("^([+−-])\\s*(\\d+(?:[.,]\\d+)?)\\s*%\\s*(.*)$").search(desc)
	if found == null:
		return {"text": desc}
	var sign := found.get_string(1)
	var step := float(found.get_string(2).replace(",", "."))
	var label := found.get_string(3).replace("pro Rang", "").strip_edges()
	label = label.substr(0, 1).to_upper() + label.substr(1)
	return {"before": _percent(sign, step * rank), "after": _percent(sign, step * (rank + 1)), "label": label}


static func _percent(sign: String, value: float) -> String:
	if is_zero_approx(value):
		return "0 %"
	var digits := str(int(value)) if is_equal_approx(value, roundf(value)) else String.num(value, 1).replace(".", ",")
	return "%s%s %%" % [sign, digits]

# ------------------------------------------------------------------ core card (stage 33)

## Cores already taken this run (evolution.cores), 0 without the field.
func _cores_taken() -> int:
	var evo := _evolution()
	if evo == null or not ("cores" in evo):
		return 0
	var taken: Variant = evo.cores
	return (taken as Array).size() if taken is Array else 0


## A core card: entry[4] {kind: "core"}, or any card while the core choice is open.
func _is_core(entry: Array) -> bool:
	if entry.size() > 4 and entry[4] is Dictionary and String(entry[4].get("kind", "")) == "core":
		return true
	return mode() == "core"


# Mutationskern: gold (legendary) outer rim with a violet accent ring, violet
# card, round core plaque instead of the icon plate, "+ ..." (green) and
# "- ..." (red) as two blocks; category tab "MUTATIONSKERN", chip LEGENDÄR.
func _core_card(c: CanvasItem, entry: Array, flash: float) -> void:
	var id := str(entry[0])
	var info := CorePlaque.info(id, str(entry[2]) if entry.size() > 2 else "")
	var name := str(entry[1]) if entry.size() > 1 and str(entry[1]) != "" else String(info.name)
	var s: Vector2 = c.size
	var rect := Rect2(Vector2.ZERO, s)
	var gold: Dictionary = UI.rarity_tone("legendary")
	Kit.glow(c, rect.grow(6.0), 28.0, CorePlaque.ACCENT, 0.5 + 0.15 * sin(_now() * 3.0))
	Kit.rrect(c, rect.grow(13.0), UI.R_L + 13.0, Color(gold["light"], 0.32))
	Kit.ring(c, rect.grow(10.0), UI.R_L + 10.0, 6.0, gold["face"])
	Kit.ring(c, rect.grow(4.0), UI.R_L + 4.0, 4.0, CorePlaque.ACCENT)
	Kit.card(c, rect, "special", "selected" if flash > 0.0 else "normal", B_HEADER)
	var inset := UI.STROKE_L + 7.0
	var head := Rect2(Vector2(inset, inset), Vector2(s.x - 2.0 * inset, B_HEADER))
	var body := Rect2(Vector2(inset, inset + B_HEADER), Vector2(s.x - 2.0 * inset, s.y - 2.0 * inset - B_HEADER))
	var st := {"rarity": "legendary"}
	var head_right := _rarity_chip(c, Vector2(head.end.x - 12.0, head.get_center().y), st) - 14.0
	if layout == "columns":
		var plate := 150.0
		var cx := s.x * 0.5
		Kit.text_outlined(c, Vector2((head.position.x + 14.0 + head_right) * 0.5, head.get_center().y), name.to_upper(), UI.T_HEAD, UI.BRAWL_TEXT, -1, -1, null, Kit.CENTER | Kit.MIDDLE, head_right - head.position.x - 14.0)
		var pc := Vector2(cx, body.position.y + 24.0 + plate * 0.5)
		CorePlaque.draw_plaque(c, pc, plate, id, false, true, String(info.name))
		var y := pc.y + plate * 0.5 + 44.0
		var width := body.size.x - 28.0
		y = _core_line(c, Vector2(body.position.x + 14.0, y), "+", String(info.plus), CorePlaque.PLUS, width, 3)
		_core_line(c, Vector2(body.position.x + 14.0, y + 10.0), "−", String(info.minus), CorePlaque.MINUS, width, 3)
	else:
		var plate := minf(156.0, body.size.y - 8.0)
		var title_x := head.position.x + 18.0
		Kit.text_outlined(c, Vector2(title_x, head.get_center().y), name.to_upper(), UI.T_HEAD, UI.BRAWL_TEXT, -1, -1, null, Kit.LEFT | Kit.MIDDLE, head_right - title_x)
		var pc := Vector2(body.position.x + 16.0 + plate * 0.5, body.get_center().y + 2.0)
		CorePlaque.draw_plaque(c, pc, plate, id, false, true, String(info.name))
		var x0 := pc.x + plate * 0.5 + 22.0
		var width := body.end.x - 18.0 - x0
		# Two blocks, vertically centred in the body (2 lines each at most).
		var plus_lines := mini(2, Kit.wrap_lines(String(info.plus), UI.body_bold_font(), UI.T_BODY, width - 46.0).size())
		var minus_lines := mini(2, Kit.wrap_lines(String(info.minus), UI.body_bold_font(), UI.T_BODY, width - 46.0).size())
		var line_h := roundf(UI.T_BODY * 1.28)
		var total := (plus_lines + minus_lines) * line_h + 14.0
		var y := body.get_center().y - total * 0.5 + UI.T_BODY * 0.8
		y = _core_line(c, Vector2(x0, y), "+", String(info.plus), CorePlaque.PLUS, width, 2)
		_core_line(c, Vector2(x0, y + 14.0), "−", String(info.minus), CorePlaque.MINUS, width, 2)
	_category_tab(c, rect, {"kind_label": "KERN", "rarity": "epic"})
	_legend_glint(c, rect)
	if flash > 0.0:
		Kit.rrect(c, rect.grow(-UI.STROKE_L), UI.R_L - UI.STROKE_L, Color(gold["light"], 0.25 * flash))


# One effect block: round sign badge (+ green, - red) and the text in that
# colour, wrapped to `max_lines`; returns the baseline y below the block.
func _core_line(c: CanvasItem, at: Vector2, sign: String, text: String, tint: Color, width: float, max_lines: int) -> float:
	if text == "":
		return at.y
	var badge_c := Vector2(at.x + 17.0, at.y - UI.T_BODY * 0.36)
	Kit.disc(c, badge_c + Vector2(0, 2), 17.0, UI.BRAWL_INK_SOFT)
	Kit.disc(c, badge_c, 17.0, UI.BRAWL_INK)
	Kit.disc(c, badge_c, 13.5, tint.darkened(0.35))
	Kit.text_outlined(c, badge_c + Vector2(0, -1), sign, UI.T_BODY, Color.WHITE, -1, -1, UI.number_font(), Kit.CENTER | Kit.MIDDLE)
	return Kit.paragraph(c, Vector2(at.x + 46.0, at.y), text, width - 46.0, UI.T_BODY, tint, true, Kit.LEFT, max_lines, 6)
