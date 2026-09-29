extends Control

# Etappe 17 Welle 2 · Beute-HUD. HuntWorld adds this component to HUD/Controls
# and publishes the HUD meta "arsenal_world" (HuntWorld._arsenal_hud()):
#   tags     price pills over cocoons near the swarm [{screen, kind, price,
#            afford, hold (0..1), denied, near}]
#   card     loot card of the last opened cocoon {item, t (0..1 over 2 s)}
#   band     short band when a power-up is taken {text, tone, id, t (0..1)}
#   shrines  charge pills over shrines near the swarm [{screen, charge, inside}]
# (the active power-up row is drawn by hud_top.gd under the swarm pill).
# Drawn with ui_kit_brawl.gd only; repaints only while something is shown.

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const UiIcons := preload("res://scripts/ui/ui_icons.gd")
const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")
const STATS := preload("res://scripts/progression/stats.gd")
const PILL_H := 46.0
const CARD_W := 560.0
const CARD_H := 150.0
const CARD_Y := 0.25
# Etappe 31: below the swarm (between swarm and hint line) - at 0.32 it covered
# the speech bubbles on the left and the loss popups.
const BAND_Y := 0.64
const BAND_H := 66.0

var _time := 0.0
var _drawn := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_time += delta
	var state := _state()
	var busy := not (state.get("tags", []) as Array).is_empty() or not (state.get("card", {}) as Dictionary).is_empty() \
		or not (state.get("band", {}) as Dictionary).is_empty() or not (state.get("shrines", []) as Array).is_empty()
	if busy or _drawn:
		queue_redraw()
	_drawn = busy


func _state() -> Dictionary:
	var hud := get_parent()
	if hud == null or not hud.has_meta("arsenal_world"):
		return {}
	if bool(hud.get("extinct")) or bool(hud.get("paused")):
		return {}
	var value: Variant = hud.get_meta("arsenal_world")
	return value if value is Dictionary else {}


func _choosing() -> bool:
	var hud := get_parent()
	var evo: Variant = hud.get("evolution") if hud != null else null
	if evo == null:
		return false
	return not (evo.offers as Array).is_empty() or not (evo.chest_offers as Array).is_empty()


func _draw() -> void:
	var state := _state()
	if state.is_empty() or _choosing():
		return
	for shrine: Dictionary in state.get("shrines", []):
		_draw_shrine(shrine)
	for tag: Dictionary in state.get("tags", []):
		_draw_tag(tag)
	var band: Dictionary = state.get("band", {})
	if not band.is_empty():
		_draw_band(band)
	var card: Dictionary = state.get("card", {})
	if not card.is_empty():
		_draw_card(card)


# ---------------------------------------------------------------- price pill

# Kit pill over a cocoon: biomass plate + price (red when the swarm cannot pay),
# free ones say GRATIS / BOSS-KOKON; while held a fill bar runs under it.
func _draw_tag(tag: Dictionary) -> void:
	var at: Vector2 = tag.screen
	var kind := String(tag.kind)
	var price := int(tag.price)
	var afford := bool(tag.afford)
	var denied := bool(tag.denied)
	var text := Kit.format_int(price) if price > 0 else ("BOSS-KOKON" if kind == "boss" else "GRATIS")
	var tone: Variant = "dark"
	if price > 0 and not afford:
		tone = "danger"
	elif price <= 0:
		tone = "loot" if kind in ["gold", "boss"] else "action"
	var size_text := UiStyle.T_BODY if price > 0 else UiStyle.T_LABEL
	var width := UiStyle.number_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_text).x
	var plate := PILL_H + 6.0
	var w := width + plate + 30.0
	if denied:
		at.x += sin(_time * 60.0) * 5.0
	var rect := Rect2(at - Vector2(w * 0.5, PILL_H), Vector2(w, PILL_H))
	if bool(tag.near) and afford:
		_halo(rect, 12.0, "loot" if price <= 0 else "action", 0.35)
	Kit.pill(self, rect, tone, UiStyle.STROKE_S)
	var pc := Vector2(rect.position.x + plate * 0.5 - 4.0, rect.get_center().y)
	Kit.icon_plate(self, pc, plate, "loot" if price > 0 else ("special" if kind == "elite" else "loot"))
	var icon := "crown_tooth" if price > 0 else "cocoon"
	if UiIcons.has(icon):
		var ic := Kit.plate_center(pc, plate)
		UiIcons.draw(self, icon, Rect2(ic - Vector2(16, 16), Vector2(32, 32)), Color.WHITE)
	var color: Color = Color.WHITE if afford else UiStyle.brawl_tone("danger")["light"].lerp(Color.WHITE, 0.35)
	Kit.number(self, Vector2(pc.x + plate * 0.5 + 6.0, rect.get_center().y), text, size_text, color, Kit.LEFT | Kit.MIDDLE)
	var hold := clampf(float(tag.hold), 0.0, 1.0)
	if hold > 0.0 and not denied:
		Kit.bar(self, Rect2(rect.position.x + 14.0, rect.end.y + 6.0, rect.size.x - 28.0, 14.0), hold, "action")
	elif denied:
		var warn := Rect2(rect.get_center().x - 70.0, rect.end.y + 4.0, 140.0, 28.0)
		Kit.chip(self, warn, "danger")
		Kit.text_outlined(self, warn.get_center(), "ZU TEUER", UiStyle.T_LABEL - 4, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)


# Soft rounded halo around a rect (stacked translucent rounded rects).
func _halo(rect: Rect2, reach: float, tone: String, alpha: float) -> void:
	var light: Color = UiStyle.brawl_tone(tone)["light"]
	for i in 4:
		var grow := reach * float(4 - i) / 4.0
		var r := minf(rect.size.x, rect.size.y) * 0.5 + grow
		Kit.rrect(self, rect.grow(grow), minf(r, 40.0 + grow), Color(light, alpha * 0.28))


# ---------------------------------------------------------------- shrine

func _draw_shrine(shrine: Dictionary) -> void:
	var at: Vector2 = shrine.screen
	var charge := clampf(float(shrine.charge), 0.0, 1.0)
	var text := "SCHREIN" if charge <= 0.0 else "%d %%" % int(round(charge * 100.0))
	var width := UiStyle.display_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.T_LABEL).x
	var plate := 44.0
	var w := maxf(width + plate + 30.0, 150.0)
	var rect := Rect2(at - Vector2(w * 0.5, 40.0), Vector2(w, 40.0))
	if bool(shrine.inside):
		_halo(rect, 10.0, "special", 0.4)
	Kit.veil_pill(self, rect, "special", 0.75)
	var pc := Vector2(rect.position.x + plate * 0.5 - 4.0, rect.get_center().y)
	Kit.icon_plate(self, pc, plate, "special")
	if UiIcons.has("shrine"):
		UiIcons.draw(self, "shrine", Rect2(Kit.plate_center(pc, plate) - Vector2(14, 14), Vector2(28, 28)), Color.WHITE)
	Kit.text_outlined(self, Vector2(pc.x + plate * 0.5 + 6.0, rect.get_center().y), text, UiStyle.T_LABEL, Color.WHITE, -1, -1, null, Kit.LEFT | Kit.MIDDLE)
	if charge > 0.0:
		Kit.bar(self, Rect2(rect.position.x + 12.0, rect.end.y + 5.0, rect.size.x - 24.0, 12.0), charge, "special")


# ---------------------------------------------------------------- loot card

# Kit card with the rarity border: square icon plate, name, what changed and a
# rarity chip. Pops in (back ease), holds, fades; epic/legendary glow.
func _draw_card(card: Dictionary) -> void:
	var t := clampf(float(card.t), 0.0, 1.0)
	var item: Dictionary = card.item
	var rarity := String(item.get("rarity", "common"))
	# Stage 28: central rarity tone (a rarity id is a valid kit tone).
	var tone := rarity if UiStyle.RARITY_TONES.has(rarity) else "common"
	var appear := clampf(t / 0.1, 0.0, 1.0)
	var fade := clampf((1.0 - t) / 0.12, 0.0, 1.0)
	var pop := 1.0 + 0.12 * sin(PI * appear) * (1.0 - appear * 0.5)
	# Pops in (back ease) and shrinks away at the end.
	var scale_value := lerpf(0.6, 1.0, _back(appear)) * pop * (1.0 - pow(1.0 - fade, 2.0))
	# Kit text sets its own canvas transform, so the pop scales the rect only
	# and the text joins once the card has (almost) landed.
	var centre := Vector2(size.x * 0.5, size.y * CARD_Y)
	var rect := Rect2(centre - Vector2(CARD_W, CARD_H) * 0.5 * scale_value, Vector2(CARD_W, CARD_H) * scale_value)
	var texts := scale_value > 0.92
	var alpha := fade
	if rarity in ["epic", "legendary"]:
		_halo(rect, 30.0, tone, 0.5 * alpha)
	Kit.card(self, rect, tone, "normal")
	if not texts:
		return
	var inner := Kit.card_inner(rect)
	var plate := inner.size.y - 4.0
	var pc := Vector2(inner.position.x + plate * 0.5 + 2.0, inner.get_center().y)
	Kit.icon_plate(self, pc, plate, tone, "square")
	var id := String(item.get("id", ""))
	var icon := _icon_id(id)
	if UiIcons.has(icon):
		UiIcons.draw(self, icon, Rect2(Kit.plate_center(pc, plate) - Vector2(plate, plate) * 0.34, Vector2(plate, plate) * 0.68), Color.WHITE)
	else:
		Kit.text_outlined(self, Kit.plate_center(pc, plate), id.left(1).to_upper(), UiStyle.T_HEAD, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
	var x := pc.x + plate * 0.5 + 16.0
	var right := inner.end.x
	var chip_text := UiStyle.rarity_name(rarity)
	var chip_w := UiStyle.display_font().get_string_size(chip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.T_LABEL - 4).x + 24.0
	var chip := Rect2(right - chip_w, inner.position.y + 2.0, chip_w, 28.0)
	Kit.chip(self, chip, tone)
	Kit.text_outlined(self, chip.get_center(), chip_text, UiStyle.T_LABEL - 4, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
	Kit.text_outlined(self, Vector2(x, inner.position.y + 18.0), String(item.get("name", id)).to_upper(), UiStyle.T_HEAD, Color.WHITE, -1, -1, null, Kit.LEFT | Kit.MIDDLE, chip.position.x - x - 8.0)
	var light: Color = UiStyle.brawl_tone(tone)["light"]
	Kit.text_outlined(self, Vector2(x, inner.position.y + 60.0), _change_text(item), UiStyle.T_BODY, light.lerp(Color.WHITE, 0.4), -1, -1, null, Kit.LEFT | Kit.MIDDLE, right - x)
	Kit.paragraph(self, Vector2(x, inner.position.y + 100.0), String(item.get("desc", "")), right - x, UiStyle.T_LABEL - 2, UiStyle.BRAWL_TEXT_DIM, false, Kit.LEFT, 1)


static func _change_text(item: Dictionary) -> String:
	match String(item.get("type", "")):
		"weapon":
			var from := int(item.get("from", 0))
			var to := int(item.get("to", 1))
			return "NEUE WAFFE · RANG %d" % to if from <= 0 else "WAFFE · RANG %d → %d" % [from, to]
		"relic":
			var stacks := int(item.get("to", 1))
			return "RELIKT" if stacks <= 1 else "RELIKT · ×%d" % stacks
		"evolution":
			return "EVOLUTION!"
	return ""


func _icon_id(id: String) -> String:
	var hud := get_parent()
	var evo: Variant = hud.get("evolution") if hud != null else null
	if evo != null and evo.has_method("icon_id"):
		return String(evo.icon_id(id))
	return id


static func _back(t: float) -> float:
	var c := 1.70158
	var u := t - 1.0
	return 1.0 + (c + 1.0) * u * u * u + c * u * u


# ---------------------------------------------------------------- power-up band

func _draw_band(band: Dictionary) -> void:
	var t := clampf(float(band.t), 0.0, 1.0)
	var text := String(band.text)
	var tone := String(band.tone)
	var appear := clampf(t / 0.12, 0.0, 1.0)
	var out := clampf((1.0 - t) / 0.18, 0.0, 1.0)
	var width := UiStyle.display_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.T_BODY).x + BAND_H + 48.0
	var centre := Vector2(size.x * 0.5, size.y * BAND_Y)
	var s := lerpf(0.5, 1.0, _back(appear)) * lerpf(0.85, 1.0, out)
	var rect := Rect2(centre - Vector2(width * s, BAND_H * s * out) * 0.5, Vector2(width * s, maxf(4.0, BAND_H * s * out)))
	Kit.ribbon(self, rect, tone)
	if s < 0.92 or out < 0.6:
		return
	var pc := Vector2(rect.position.x + BAND_H * 0.5 + 2.0, centre.y)
	Kit.icon_plate(self, pc, BAND_H + 8.0, tone)
	var icon := _band_icon(String(band.get("id", "")))
	if UiIcons.has(icon):
		UiIcons.draw(self, icon, Rect2(Kit.plate_center(pc, BAND_H + 8.0) - Vector2(22, 22), Vector2(44, 44)), Color.WHITE)
	Kit.text_outlined(self, Vector2(pc.x + BAND_H * 0.5 + 14.0, centre.y - 2.0), text, UiStyle.T_BODY, Color.WHITE, -1, -1, null, Kit.LEFT | Kit.MIDDLE)


static func _band_icon(id: String) -> String:
	match id:
		"rausch":
			return "pu_rausch"
		"blutrausch":
			return "pu_blutrausch"
		"magnetsturm":
			return "pu_magnetsturm"
		"chitinschild":
			return "pu_chitinschild"
		"raserei":
			return "pu_raserei"
		"brutwelle":
			return "pu_brutwelle"
	return id
