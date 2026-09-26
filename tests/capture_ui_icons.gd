extends SceneTree
## Icon sheet for visual review: every UiIcons id at 160 px on the dark panel
## green, at 56 px on dark and light moss, as flat silhouettes, and tinted.
## Run WITHOUT --headless. Output: res://preview_ui_icons.png

const UiIcons := preload("res://scripts/ui/ui_icons.gd")
const UiStyle := preload("res://scripts/ui/ui_style.gd")
const SIZE := Vector2i(1380, 2420)
const MOSS := Color("7f9b5a")


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sheet := Control.new()
	sheet.size = Vector2(SIZE)
	sheet.draw.connect(_draw_sheet.bind(sheet))
	viewport.add_child(sheet)
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://preview_ui_icons.png")
	print("Saved preview_ui_icons.png (%d icons)" % UiIcons.IDS.size())
	quit()


func _draw_sheet(c: Control) -> void:
	var font := ThemeDB.fallback_font
	c.draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE)), Color("050b08"))
	# 160 px on the dark card body.
	var rows := ceili(UiIcons.IDS.size() / 8.0)
	var top := Rect2(10, 10, SIZE.x - 20, rows * 196 + 10)
	c.draw_rect(top, UiStyle.PANEL.lerp(Color.BLACK, 0.0))
	for i in UiIcons.IDS.size():
		var id: String = UiIcons.IDS[i]
		var cell := Vector2(20 + (i % 8) * 170, 18 + (i / 8) * 196)
		UiIcons.draw(c, id, Rect2(cell + Vector2(5, 0), Vector2(160, 160)))
		c.draw_string(font, cell + Vector2(0, 182), id, HORIZONTAL_ALIGNMENT_CENTER, 170, 15, UiStyle.TEXT_DIM)
	# 56 px rows: dark panel, light moss, black silhouettes on moss, tinted head.
	var y := top.end.y + 10
	var bands := [[UiStyle.PANEL, Color.WHITE], [MOSS, Color.WHITE], [MOSS, Color(0.06, 0.08, 0.06)]]
	for band in bands:
		c.draw_rect(Rect2(10, y, SIZE.x - 20, 4 * 70 + 12), band[0])
		for i in UiIcons.IDS.size():
			var pos := Vector2(24 + (i % 16) * 84, y + 8 + (i / 16) * 70)
			UiIcons.draw(c, UiIcons.IDS[i], Rect2(pos, Vector2(56, 56)), band[1])
		y += 4 * 70 + 22
	# Tint check for the neutral head + missing-id placeholder + 40 px.
	c.draw_rect(Rect2(10, y, SIZE.x - 20, 70), UiStyle.PANEL)
	var tints := [Color.WHITE, UiStyle.EMBER, UiStyle.CYAN, UiStyle.VIOLET, UiStyle.TOXIC, UiStyle.GOLD]
	for i in tints.size():
		UiIcons.draw(c, "mawling_head", Rect2(24 + i * 70, y + 7, 56, 56), tints[i])
	UiIcons.draw(c, "does_not_exist", Rect2(24 + 6 * 70, y + 7, 56, 56))
	UiIcons.draw(c, "prey", Rect2(24 + 7 * 70, y + 7, 56, 56))
	var small := ["pack", "meute", "rudelbiss", "hunter", "skitter", "leaper", "nibbler", "bog_king", "biomass", "essence", "up_gene", "dna", "restart", "reroll", "hub", "instinct"]
	for i in small.size():
		UiIcons.draw(c, small[i], Rect2(580 + i * 48, y + 15, 40, 40))
