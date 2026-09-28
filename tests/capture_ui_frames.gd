extends SceneTree

# Pattern sheet of the frame kit over a dimmed live game (stage 04, FRAMES).
# Run without --headless:
#   Godot_console.exe --path . --script res://tests/capture_ui_frames.gd
# Writes preview_ui_frames.png (540 x 960 window) and preview_ui_frames_zoom_*.png.

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const UiFrames := preload("res://scripts/ui/ui_frames.gd")

var page: Control


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var controls := scene.get_node_or_null("HUD/Controls")
	var world := scene.get_node_or_null("HuntWorld")
	# Background capture windows lose focus; the auto-pause must not end up in the frames.
	if controls != null and world != null and controls.has_signal("pause_requested"):
		if controls.pause_requested.is_connected(world.toggle_pause):
			controls.pause_requested.disconnect(world.toggle_pause)
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	page = Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.draw.connect(_draw_page)
	layer.add_child(page)
	await create_timer(0.8).timeout
	await _save("preview_ui_frames.png")
	# 2x crops ~ Galaxy S25 pixel density (1.2 screen px per layout px)
	page.scale = Vector2(2, 2)
	page.position = Vector2(0, -360)
	await create_timer(0.2).timeout
	await _save("preview_ui_frames_zoom_left.png")
	page.position = Vector2(-900, -360)
	await create_timer(0.2).timeout
	await _save("preview_ui_frames_zoom_right.png")
	page.position = Vector2(0, -2400)
	await create_timer(0.2).timeout
	await _save("preview_ui_frames_zoom_bottom.png")
	print("Saved UI frame previews")
	quit()


func _draw_page() -> void:
	var c := page
	c.draw_rect(Rect2(-900, -1600, 2700, 4800), UiStyle.DIM)

	# Heading
	UiFrames.divider(c, Vector2(450, 96), 880, UiStyle.TOXIC, 540)
	UiStyle.text(c, "MUTATION WÄHLEN", Vector2(450, 112), UiStyle.SIZE_TITLE, UiStyle.BONE, true)
	UiFrames.divider(c, Vector2(450, 150), 520, UiStyle.TEXT_DIM, 200, 0.6)
	UiStyle.text(c, "STUFE 4", Vector2(450, 160), UiStyle.SIZE_LABEL, UiStyle.TEXT_DIM, true)

	# Mutation cards
	var cards := [[UiStyle.EMBER, "RAZOR JAWS", "normal"], [UiStyle.CYAN, "RAPID BROOD", "selected"], [UiStyle.VIOLET, "BONE PLATE", "normal"]]
	for i in cards.size():
		var r := Rect2(24, 196 + i * 232, 852, 212)
		UiFrames.card(c, r, cards[i][0], cards[i][2])
		var inner := UiFrames.card_inner(r)
		UiStyle.text(c, cards[i][1], inner.position + Vector2(200, 60), UiStyle.SIZE_HEAD, cards[i][0])
		c.draw_line(inner.position + Vector2(200, 82), inner.position + Vector2(inner.size.x - 40, 82), _a(cards[i][0], 0.35), 2)
		UiStyle.text(c, "+25 % BISSSCHADEN", inner.position + Vector2(200, 128), UiStyle.SIZE_BODY, UiStyle.TEXT)
	# small cards: pressed / disabled / tiny
	UiFrames.card(c, Rect2(24, 900, 330, 170), UiStyle.TOXIC, "pressed")
	UiFrames.card(c, Rect2(372, 900, 300, 170), UiStyle.GOLD, "disabled")
	UiFrames.card(c, Rect2(690, 910, 186, 120), UiStyle.EMBER)
	UiStyle.text(c, "pressed", Vector2(60, 1000), UiStyle.SIZE_LABEL, UiStyle.TEXT_DIM)
	UiStyle.text(c, "disabled", Vector2(410, 1000), UiStyle.SIZE_LABEL, UiStyle.TEXT_DIM)

	# Panels + pills
	UiFrames.panel(c, Rect2(24, 1100, 260, 96))
	UiStyle.text(c, "250", Vector2(110, 1164), UiStyle.SIZE_HEAD, UiStyle.TEXT)
	UiFrames.panel(c, Rect2(304, 1100, 292, 96), UiStyle.CYAN)
	UiStyle.text(c, "LV 4", Vector2(330, 1164), UiStyle.SIZE_HEAD, UiStyle.CYAN)
	UiFrames.panel_plain(c, Rect2(616, 1100, 260, 96), UiStyle.DANGER)
	UiFrames.bar(c, Rect2(420, 1170, 150, 14), 0.62, UiStyle.CYAN)
	UiFrames.bar(c, Rect2(636, 1150, 220, 24), 0.55, UiStyle.DANGER, 7)

	UiFrames.pill(c, Rect2(24, 1216, 180, 48), UiStyle.EMBER)
	UiStyle.text(c, "+10 DNA", Vector2(114, 1250), UiStyle.SIZE_LABEL, UiStyle.CYAN, true)
	UiFrames.pill(c, Rect2(220, 1222, 130, 36), UiStyle.GOLD)
	UiFrames.pill(c, Rect2(366, 1216, 110, 48), UiStyle.VIOLET)
	UiFrames.bar(c, Rect2(500, 1226, 376, 28), 0.37, UiStyle.EMBER)

	# Buttons
	UiFrames.button(c, Rect2(24, 1290, 300, 88), "primary")
	UiStyle.text(c, "SPIELEN", UiFrames.button_label_center(Rect2(24, 1290, 300, 88)) + Vector2(0, 14), UiStyle.SIZE_HEAD, UiStyle.TEXT, true)
	UiFrames.button(c, Rect2(340, 1290, 220, 88), "primary", true)
	UiFrames.button(c, Rect2(576, 1290, 300, 72), "secondary")
	UiStyle.text(c, "NEU WÜRFELN", Vector2(726, 1336), UiStyle.SIZE_LABEL, UiStyle.BONE, true)
	UiFrames.button(c, Rect2(576, 1372, 180, 56), "secondary", true)

	UiFrames.button(c, Rect2(24, 1394, 190, 190), "round")
	UiStyle.text(c, "RALLY", Vector2(119, 1500), UiStyle.SIZE_BODY, UiStyle.TEXT, true)
	UiFrames.button(c, Rect2(240, 1420, 150, 150), "round", true, UiStyle.CYAN)
	UiFrames.button(c, Rect2(410, 1444, 110, 110), "round", false, UiStyle.TOXIC)

	# Ornaments
	UiFrames.claw(c, Vector2(560, 1580), -0.5, 0.8)
	UiFrames.claw(c, Vector2(620, 1580), 0.0, 1.0)
	UiFrames.claw(c, Vector2(700, 1580), 0.5, -0.8)
	for i in 5:
		UiFrames.tooth(c, Vector2(770 + i * 22, 1450), 0.0, 0.5 + i * 0.1)
	UiFrames.divider(c, Vector2(820, 1540), 100, UiStyle.CYAN, 0, 0.5)


func _a(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/" + file_name)
