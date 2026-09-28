extends SceneTree

# Preview sheets of the brawl UI kit (stage 15, wave 1). Run WITHOUT --headless:
#   Godot_console.exe --path . --screen 1 --audio-driver Dummy --script res://tests/capture_ui_kit_brawl.gd
# Writes (project root, ignored by git):
#   preview_ui_kit_brawl.png        900 x 1600, kit in context over the live game
#   preview_ui_kit_brawl_540.png    same at the 540 x 960 window (real downscale)
#   preview_ui_kit_brawl_tones.png  900 x 1600, every component in every tone
#   preview_ui_kit_brawl_tones_540.png
#   preview_ui_kit_brawl_zoom_*.png 2x crops of the tone sheet (edge quality)

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")
const UiIcons := preload("res://scripts/ui/ui_icons.gd")

const TONES := ["ember", "action", "info", "loot", "danger", "special", "neutral", "dark"]
const TONE_LABELS := {"ember": "SCHWARM", "action": "AKTION", "info": "DNA", "loot": "BEUTE",
	"danger": "GEFAHR", "special": "EVOLUTION", "neutral": "NEUTRAL", "dark": "PANEL"}

var page: Control
var mode := "context"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	UiStyle.set_skin("brawl")
	root.size = Vector2i(900, 1600)
	# Live game as background; while another agent has hunt_world.gd half
	# edited (parse error) fall back to a saved game frame or the menu art.
	var world_script: Script = load("res://scripts/hunt_world.gd")
	if world_script == null or not world_script.can_instantiate():
		_fallback_background()
	else:
		_live_background()
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	page = Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.draw.connect(_draw_page)
	layer.add_child(page)
	await create_timer(1.0).timeout
	mode = "context"
	page.queue_redraw()
	await _save("preview_ui_kit_brawl.png")
	mode = "tones"
	page.queue_redraw()
	await _save("preview_ui_kit_brawl_tones.png")
	# 2x crops ~ a bit more than the S25 pixel density (1.2 screen px per base px)
	page.scale = Vector2(2, 2)
	for crop in [["zoom_buttons", Vector2(0, -60)], ["zoom_bars", Vector2(0, -1500)], ["zoom_text", Vector2(-900, -2200)]]:
		page.position = crop[1]
		page.queue_redraw()
		await create_timer(0.15).timeout
		await _save("preview_ui_kit_brawl_%s.png" % crop[0])
	page.scale = Vector2.ONE
	page.position = Vector2.ZERO
	root.size = Vector2i(540, 960)
	await create_timer(0.3).timeout
	mode = "context"
	page.queue_redraw()
	await _save("preview_ui_kit_brawl_540.png")
	mode = "tones"
	page.queue_redraw()
	await _save("preview_ui_kit_brawl_tones_540.png")
	print("Saved brawl UI kit previews")
	quit()


func _live_background() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var controls := scene.get_node_or_null("HUD/Controls")
	var world := scene.get_node_or_null("HuntWorld")
	# Background capture windows lose focus; the auto-pause must not end up in the frames.
	if controls != null and world != null and controls.has_signal("pause_requested"):
		if controls.pause_requested.is_connected(world.toggle_pause):
			controls.pause_requested.disconnect(world.toggle_pause)
	var hud := scene.get_node_or_null("HUD")
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = false


func _fallback_background() -> void:
	print("hunt_world.gd does not load right now: using a still background")
	var tex: Texture2D = null
	for path in ["res://previews/preview_hunt.png", "res://previews/preview.png"]:
		if FileAccess.file_exists(path):
			tex = ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path(path)))
			break
	if tex == null:
		tex = load("res://assets/ui/v3/menu_background.png")
	var bg := TextureRect.new()
	bg.texture = tex
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	root.add_child(bg)


func _draw_page() -> void:
	if mode == "context":
		_draw_context(page)
	else:
		_draw_tones(page)


# ------------------------------------------------------------------ context sheet

func _draw_context(c: CanvasItem) -> void:
	# top HUD: population (ember), timer (centre), DNA (info), pause
	Kit.pill(c, Rect2(20, 28, 250, 76))
	Kit.icon_plate(c, Vector2(62, 66), 76, "ember")
	_icon(c, "mawling_head", Kit.plate_center(Vector2(62, 66), 76), 44)
	Kit.number(c, Vector2(112, 66), 184, UiStyle.T_HEAD, Color.WHITE, Kit.LEFT | Kit.MIDDLE)
	Kit.text_outlined(c, Vector2(196, 70), "/250", UiStyle.T_LABEL, UiStyle.BRAWL_TEXT_DIM, -1, -1, null, Kit.LEFT | Kit.MIDDLE)

	Kit.pill(c, Rect2(330, 24, 240, 84), "dark")
	Kit.number(c, Vector2(450, 64), "07:42", UiStyle.T_TITLE, Color.WHITE, Kit.CENTER | Kit.MIDDLE)
	Kit.bar(c, Rect2(350, 116, 200, 26), 0.72, "danger", 5)

	Kit.pill(c, Rect2(620, 28, 186, 76))
	Kit.icon_plate(c, Vector2(652, 66), 76, "info")
	_icon(c, "dna", Kit.plate_center(Vector2(652, 66), 76), 44)
	Kit.number(c, Vector2(790, 66), 1240, UiStyle.T_HEAD, Color("bff1ff"), Kit.RIGHT | Kit.MIDDLE)
	Kit.round_button(c, Vector2(850, 66), 38, "neutral")
	_icon(c, "pause", Kit.round_label_center(Vector2(850, 66), 38), 34)
	Kit.badge(c, Vector2(800, 30), "3", "danger")

	# boss bar
	Kit.panel(c, Rect2(60, 176, 780, 92), "dark", UiStyle.R_L)
	Kit.icon_plate(c, Vector2(110, 222), 96, "danger", "square")
	_icon(c, "bog_king", Kit.plate_center(Vector2(110, 222), 96), 64)
	Kit.text_outlined(c, Vector2(172, 210), "BOG KING", UiStyle.T_HEAD, Color.WHITE)
	Kit.number(c, Vector2(812, 210), "8.450 / 12.000", UiStyle.T_LABEL, Color("ffd0e8"), Kit.RIGHT)
	Kit.bar(c, Rect2(172, 222, 650, 32), 0.7, "danger")

	# level-up / mutation choice
	Kit.ribbon(c, Rect2(210, 330, 480, 84), "ember")
	Kit.text_outlined(c, Vector2(450, 372), "MUTATION!", UiStyle.T_TITLE, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
	Kit.text_outlined(c, Vector2(450, 470), "Wähle eine Verstärkung", UiStyle.T_BODY, Color("ffe9d6"), 7, 3, UiStyle.body_bold_font(), Kit.CENTER)
	var cards := [["ember", "jaws", "Rasierkiefer", "+25 % Bissschaden", "NEU"], ["info", "brood", "Schnelle Brut", "Teilung 18 % schneller", ""],
		["special", "armor", "Knochenpanzer", "−1 Schaden pro Treffer", "2"]]
	for i in cards.size():
		var r := Rect2(40 + i * 280, 510, 260, 380)
		var state := "selected" if i == 1 else "normal"
		Kit.card(c, r, cards[i][0], state, 64)
		Kit.text_outlined(c, Vector2(r.get_center().x, r.position.y + 42), String(cards[i][2]).to_upper(), 30, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE, r.size.x - 40)
		var plate := Vector2(r.get_center().x, r.position.y + 170)
		Kit.icon_plate(c, plate, 128, cards[i][0])
		_icon(c, cards[i][1], Kit.plate_center(plate, 128), 92)
		Kit.paragraph(c, Vector2(r.position.x + 24, r.position.y + 280), cards[i][3], r.size.x - 48, UiStyle.T_BODY, Color.WHITE, true, Kit.CENTER, 2)
		if cards[i][4] != "":
			Kit.badge(c, r.position + Vector2(r.size.x - 18, 10), cards[i][4], "danger" if cards[i][4] == "NEU" else "loot")
	Kit.button(c, Rect2(40, 920, 400, 104), "neutral")
	_label(c, Rect2(40, 920, 400, 104), "NEU WÜRFELN", false)
	Kit.button(c, Rect2(460, 920, 400, 104), "action")
	_label(c, Rect2(460, 920, 400, 104), "WÄHLEN", false)

	# loot toast + objective
	Kit.pill(c, Rect2(40, 1070, 300, 64), "dark")
	Kit.icon_plate(c, Vector2(74, 1102), 60, "loot")
	_icon(c, "biomass", Kit.plate_center(Vector2(74, 1102), 60), 36)
	Kit.number(c, Vector2(116, 1102), "+36", UiStyle.T_HEAD, Color("ffe07a"), Kit.LEFT | Kit.MIDDLE)
	Kit.text_outlined(c, Vector2(216, 1106), "Biomasse", UiStyle.T_LABEL, Color.WHITE, 6, 2, UiStyle.body_bold_font(), Kit.LEFT | Kit.MIDDLE)
	Kit.panel(c, Rect2(380, 1062, 480, 116), "dark", UiStyle.R_M)
	Kit.text_outlined(c, Vector2(404, 1102), "Nest zerstören", UiStyle.T_BODY, Color.WHITE, 7, 3, UiStyle.body_bold_font())
	Kit.number(c, Vector2(836, 1102), "2/3", UiStyle.T_BODY, Color("ffe07a"), Kit.RIGHT)
	Kit.bar(c, Rect2(404, 1122, 432, 30), 0.66, "loot", 3)

	# controls: Rally left, joystick right
	Kit.round_button(c, Vector2(150, 1420), 96, "ember")
	Kit.text_outlined(c, Kit.round_label_center(Vector2(150, 1420), 96), "RALLY", UiStyle.T_HEAD, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
	Kit.badge(c, Vector2(222, 1340), "2", "info", UiStyle.T_LABEL)
	Kit.disc(c, Vector2(740, 1420), 112, Color(UiStyle.BRAWL_INK, 0.35))
	Kit.circle_ring(c, Vector2(740, 1420), 112, 5.0, Color(1, 1, 1, 0.35))
	Kit.round_button(c, Vector2(760, 1400), 52, "neutral", true)


# ------------------------------------------------------------------ tone sheet

func _draw_tones(c: CanvasItem) -> void:
	c.draw_rect(Rect2(-900, -1600, 2700, 4800), Color(0.05, 0.04, 0.12, 0.62))
	Kit.text_outlined(c, Vector2(450, 44), "BRAWL KIT · TÖNE", UiStyle.T_HEAD, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
	# buttons: normal / pressed, all tones
	for i in TONES.size():
		var tone: String = TONES[i]
		var col := i % 2
		var row := i / 2
		var x := 24.0 + col * 440.0
		var y := 84.0 + row * 104.0
		var tone_value: String = "disabled" if tone == "dark" else tone
		var r := Rect2(x, y, 240, 88)
		Kit.button(c, r, tone_value)
		_label(c, r, TONE_LABELS[tone] if tone != "dark" else "GESPERRT", false, UiStyle.T_LABEL + 4)
		var rp := Rect2(x + 256, y, 160, 88)
		Kit.button(c, rp, tone_value, true)
		_label(c, rp, "GEDRÜCKT", true, UiStyle.T_LABEL)
	# round buttons + icon plates
	var y0 := 538.0
	for i in TONES.size():
		var cx := 60.0 + i * 110.0
		Kit.round_button(c, Vector2(cx, y0), 44, TONES[i], i == 7)
		Kit.icon_plate(c, Vector2(cx, y0 + 108), 72, TONES[i], "round")
		Kit.icon_plate(c, Vector2(cx, y0 + 196), 72, TONES[i], "square")
	for i in 3:
		_icon(c, ["pause", "dna", "biomass"][i], Kit.round_label_center(Vector2(60.0 + [6, 2, 3][i] * 110.0, y0), 44), 32)
	# pills, chips, badges
	var y1 := 790.0
	for i in TONES.size():
		var col := i % 4
		var row := i / 4
		var r := Rect2(24 + col * 216, y1 + row * 74, 196, 56)
		Kit.pill(c, r, TONES[i])
		Kit.text_outlined(c, r.get_center(), TONE_LABELS[TONES[i]], UiStyle.T_LABEL, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE, r.size.x - 24)
	var y2 := 950.0
	for i in 6:
		var r := Rect2(24 + i * 146, y2, 128, 40)
		Kit.chip(c, r, TONES[i])
		Kit.text_outlined(c, r.get_center(), ["STUFE 3", "NEU", "SELTEN", "+10", "ELITE", "EPISCH"][i], UiStyle.T_LABEL, Color.WHITE, 6, 2, null, Kit.CENTER | Kit.MIDDLE)
	var badges := [["3", "danger"], ["NEU", "danger"], ["12", "info"], ["!", "loot"], ["99+", "special"], ["1", "action"]]
	for i in badges.size():
		Kit.badge(c, Vector2(70 + i * 150, 1036), badges[i][0], badges[i][1])
	# bars
	var y3 := 1090.0
	var fills := [0.82, 0.55, 0.36, 0.64, 0.9, 0.18, 0.47, 0.03]
	for i in TONES.size():
		var col := i % 2
		var row := i / 2
		var tone: String = TONES[i] if TONES[i] != "dark" else "ember"
		Kit.bar(c, Rect2(24 + col * 440, y3 + row * 52, 416, 34 if row < 2 else 24), fills[i], tone, 5 if i == 4 else 0)
	# panels, well, cards
	var y4 := 1310.0
	Kit.panel(c, Rect2(24, y4, 270, 150))
	Kit.well(c, Rect2(44, y4 + 70, 230, 56))
	Kit.text_outlined(c, Vector2(44, y4 + 44), "Panel", UiStyle.T_HEAD, Color.WHITE)
	Kit.card(c, Rect2(314, y4, 170, 150), "ember", "normal", 40)
	Kit.card(c, Rect2(500, y4, 170, 150), "info", "pressed", 40)
	Kit.card(c, Rect2(686, y4, 190, 150), "special", "disabled", 40)
	# type scale (right column of the zoom crop at the bottom)
	var y5 := 1520.0
	Kit.text_outlined(c, Vector2(24, y5), "72", UiStyle.T_HERO, Color("ffd23f"))
	Kit.text_outlined(c, Vector2(130, y5), "Titel 54", UiStyle.T_TITLE, Color.WHITE)
	Kit.text_outlined(c, Vector2(380, y5), "Kopf 38", UiStyle.T_HEAD, Color("ffb24a"))
	Kit.text_outlined(c, Vector2(560, y5 - 20), "Figtree 26 – Text äöü ß", UiStyle.T_BODY, Color.WHITE, 0, 0, UiStyle.body_font())
	Kit.text_outlined(c, Vector2(560, y5 + 16), "Label 22 · 0123456789 €", UiStyle.T_LABEL, Color("b8b4e6"), 0, 0, UiStyle.body_bold_font())
	Kit.number(c, Vector2(560, y5 + 58), "11:11 / 88:88", UiStyle.T_HEAD, Color("45d4ff"))


# ------------------------------------------------------------------ helpers

func _label(c: CanvasItem, r: Rect2, value: String, pressed: bool, size: int = UiStyle.T_HEAD) -> void:
	Kit.text_outlined(c, Kit.button_label_center(r, pressed), value, size, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE, r.size.x - 28)


func _icon(c: CanvasItem, id: String, center: Vector2, size: float) -> void:
	if UiIcons.has(id):
		UiIcons.draw(c, id, Rect2(center - Vector2(size, size) * 0.5, Vector2(size, size)))


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/" + file_name)
