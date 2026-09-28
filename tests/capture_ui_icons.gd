extends SceneTree
## Icon review sheets (icon standard V4, ART_UI_PLAN.md "Icon-Standard").
## Every UiIcons id at 96 px and 40 px, on the dark panel green and on light
## moss, once with the V4 standard (after) and once without (before), plus a
## focus strip for the look-alike teeth icons, the glyphs and tints.
## Run WITHOUT --headless. Output: res://preview_ui_icons.png (after),
## res://preview_ui_icons_before.png, res://preview_ui_icons_compare.png

const UiIcons := preload("res://scripts/ui/ui_icons.gd")
const DARK := Color("0c1a14")
const MOSS := Color("7f9b5a")
const BACK := Color("050b08")
const LABEL := Color("c9d6cc")
const COLS := 4
const CELL := Vector2(320, 150)
const FOCUS := ["jaws", "pack", "glutton", "rudelbiss", "meute", "armor", "scatter",
	"dna", "biomass", "pause", "clock", "lock", "reroll", "restart", "banish", "skip"]
# Second tint row: tintable head, fixed-colour currencies, painted icons.
const PAINTED_TINT := ["mawling_head", "dna", "biomass", "skull", "crown", "nest", "essence"]
const TINTS := [Color.WHITE, Color("ffc94a"), Color("5fe0d0"), Color("ff6a4a"), Color("b58cff")]


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	UiIcons.set_v4(true)
	await _render(_draw_sheet, _sheet_size(), "res://previews/preview_ui_icons.png")
	UiIcons.set_v4(false)
	await _render(_draw_sheet, _sheet_size(), "res://previews/preview_ui_icons_before.png")
	await _render(_draw_compare, Vector2i(1400, 640), "res://previews/preview_ui_icons_compare.png")
	UiIcons.set_v4(true)
	print("Saved preview_ui_icons(.png/_before/_compare) (%d icons)" % UiIcons.IDS.size())
	quit()


func _sheet_size() -> Vector2i:
	var rows := ceili(UiIcons.IDS.size() / float(COLS))
	return Vector2i(int(COLS * CELL.x) + 20, int(rows * CELL.y) + 20)


func _render(fn: Callable, size: Vector2i, out: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sheet := Control.new()
	sheet.size = Vector2(size)
	sheet.draw.connect(fn.bind(sheet, size))
	viewport.add_child(sheet)
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(out)
	viewport.queue_free()
	await process_frame


# One cell: [dark: 96 + 40] [moss: 96 + 40] and the id below.
func _cell(c: Control, id: String, at: Vector2, tint := Color.WHITE) -> void:
	for k in 2:
		var bg := Rect2(at + Vector2(k * 152, 0), Vector2(148, 112))
		c.draw_rect(bg, DARK if k == 0 else MOSS)
		UiIcons.draw(c, id, Rect2(bg.position + Vector2(6, 8), Vector2(96, 96)), tint)
		UiIcons.draw(c, id, Rect2(bg.position + Vector2(104, 64), Vector2(40, 40)), tint)
	c.draw_string(ThemeDB.fallback_font, at + Vector2(0, 132), id, HORIZONTAL_ALIGNMENT_CENTER, 300, 16, LABEL)


func _draw_sheet(c: Control, size: Vector2i) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, Vector2(size)), BACK)
	for i in UiIcons.IDS.size():
		var at := Vector2(14 + (i % COLS) * CELL.x, 10 + (i / COLS) * CELL.y)
		_cell(c, UiIcons.IDS[i], at)


# Focus strip: before (row 1) / after (row 2) at 64 + 40 px on dark and moss,
# then the V4 glyphs and the neutral head in five tints.
func _draw_compare(c: Control, size: Vector2i) -> void:
	var font := ThemeDB.fallback_font
	c.draw_rect(Rect2(Vector2.ZERO, Vector2(size)), BACK)
	for row in 2:
		UiIcons.set_v4(row == 1)
		var y := 10.0 + row * 250.0
		c.draw_string(font, Vector2(12, y + 20), "VORHER" if row == 0 else "NACHHER (V4)", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, LABEL)
		for band in 2:
			var by := y + 30 + band * 104
			c.draw_rect(Rect2(10, by, size.x - 20, 100), DARK if band == 0 else MOSS)
			for i in FOCUS.size():
				var x := 20.0 + i * 85.0
				UiIcons.draw(c, FOCUS[i], Rect2(x, by + 4, 64, 64))
				UiIcons.draw(c, FOCUS[i], Rect2(x + 12, by + 64, 34, 34))
	UiIcons.set_v4(true)
	var ty := 530.0
	c.draw_string(font, Vector2(12, ty - 8), "Getönt: oben V4-Glyphen, unten Kopf/DNA/Biomasse/Schädel/Krone/Nest/Essenz", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, LABEL)
	c.draw_rect(Rect2(10, ty, size.x - 20, 96), DARK)
	var glyphs := ["pause", "clock", "lock", "reroll", "restart", "banish", "skip"]
	for g in glyphs.size():
		for t in TINTS.size():
			var x := 20.0 + g * 190.0 + t * 36.0
			UiIcons.draw(c, glyphs[g], Rect2(x, ty + 10, 34, 34), TINTS[t])
			UiIcons.draw(c, PAINTED_TINT[g], Rect2(x, ty + 52, 34, 34), TINTS[t])
