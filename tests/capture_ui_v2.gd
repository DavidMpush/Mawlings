extends SceneTree

# UI kit V2 review for the style decision (run WITHOUT --headless):
#   preview_ui_v2_mutation.png  mutation choice   organic | calm
#   preview_ui_v2_hud.png       HUD in the game   organic | calm
#   preview_ui_v2_menu.png      Brutstaette menu  organic | calm
#   preview_ui_v2_icons.png     six trait icons: painted V2 PNG vs SVG at
#                               160 / 56 / 40 px on dark panel and moss green
# The skin is switched with UiStyle.set_skin(); components are not touched.
# Uses a scratch profile; the real player profile is never touched.

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const UiIcons := preload("res://scripts/ui/ui_icons.gd")
const TEST_PROFILE := "user://capture_ui_v2_profile.json"
const TRAITS := ["jaws", "brood", "glutton", "pack", "scatter", "armor"]
const MOSS := Color("7f9b5a")
const GAP := 12


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	UiStyle.set_skin("organic")
	await _icons_sheet()

	# --- game: HUD, then the mutation choice
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var world: Variant = scene.get_node("HuntWorld")
	var controls: Variant = scene.get_node("HUD/Controls")
	# Background capture windows lose focus; the auto-pause must not end up in the frames.
	controls.pause_requested.disconnect(world.toggle_pause)
	await create_timer(1.2).timeout
	# Freeze the hunt (no kills, no popups) so both halves show the same state.
	for target in world.prey:
		target.queue_free()
	world.prey.clear()
	world.model.population = 42
	world._award_dna(6)
	world._update_hud("")
	await create_timer(0.6).timeout
	world.set_process(false)
	await _pair("preview_ui_v2_hud.png")

	var evo: Variant = world.evolution
	evo.ranks = {"jaws": 1, "rudelbiss": 1}
	evo.rerolls = 1
	evo.banishes = 1
	evo.skips = 1
	evo.dna = maxi(evo.dna, evo.threshold() * 3)
	var offers: Array = []
	for id in ["jaws", "brood", "armor"]:
		offers.append(evo.info(id))
	evo.offers = offers
	world._update_hud("")
	await create_timer(1.0).timeout
	await _pair("preview_ui_v2_mutation.png")
	scene.queue_free()
	await process_frame

	# --- menu
	var session: Variant = load("res://scripts/meta/session.gd")
	if FileAccess.file_exists(TEST_PROFILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))
	var profile: Variant = load("res://scripts/meta/profile.gd").load_or_create(TEST_PROFILE)
	profile.essence = 1240
	profile.crowns = 4
	profile.records.best_seconds = 262.0
	profile.save()
	session.last_result = {}
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	menu.profile_path = TEST_PROFILE
	menu.change_scene_on_play = false
	root.add_child(menu)
	await create_timer(1.0).timeout
	await _pair("preview_ui_v2_menu.png")
	menu.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))
	UiStyle.set_skin("organic")
	print("Saved UI V2 review frames (organic | calm)")
	quit()


# Same frame in both skins, side by side (organic left, calm right).
func _pair(file_name: String) -> void:
	UiStyle.set_skin("organic")
	await _settle()
	var organic := await _grab()
	UiStyle.set_skin("calm")
	await _settle()
	var calm := await _grab()
	UiStyle.set_skin("organic")
	var sheet := Image.create(organic.get_width() * 2 + GAP, organic.get_height(), false, organic.get_format())
	sheet.fill(Color("050b08"))
	sheet.blit_rect(organic, Rect2i(Vector2i.ZERO, organic.get_size()), Vector2i.ZERO)
	sheet.blit_rect(calm, Rect2i(Vector2i.ZERO, calm.get_size()), Vector2i(organic.get_width() + GAP, 0))
	sheet.save_png("res://previews/" + file_name)


func _settle() -> void:
	# Long enough for cached UiLayers to go live and bake again.
	await create_timer(0.45).timeout


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


# Painted V2 PNG (top of each pair) vs the SVG fallback (below).
func _icons_sheet() -> void:
	var size := Vector2i(1180, 700)
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sheet := Control.new()
	sheet.size = Vector2(size)
	viewport.add_child(sheet)
	# Two images: painted first, then SVG fallback, drawn into one sheet.
	var images := []
	for painted in [true, false]:
		UiIcons.set_painted(painted)
		for connection in sheet.draw.get_connections():
			sheet.draw.disconnect(connection.callable)
		sheet.draw.connect(_draw_icons.bind(sheet, painted))
		sheet.queue_redraw()
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		images.append(viewport.get_texture().get_image())
	UiIcons.set_painted(true)
	var out := Image.create(size.x, size.y * 2 + GAP, false, images[0].get_format())
	out.fill(Color("050b08"))
	out.blit_rect(images[0], Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	out.blit_rect(images[1], Rect2i(Vector2i.ZERO, size), Vector2i(0, size.y + GAP))
	out.save_png("res://previews/preview_ui_v2_icons.png")
	viewport.queue_free()


func _draw_icons(c: Control, painted: bool) -> void:
	var font := ThemeDB.fallback_font
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color("050b08"))
	c.draw_string(font, Vector2(16, 30), "V2 painted PNG" if painted else "SVG fallback", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UiStyle.TEXT)
	c.draw_rect(Rect2(10, 44, c.size.x - 20, 200), UiStyle.PANEL)
	for i in TRAITS.size():
		UiIcons.draw(c, TRAITS[i], Rect2(24 + i * 190, 54, 160, 160))
		c.draw_string(font, Vector2(24 + i * 190, 236), TRAITS[i], HORIZONTAL_ALIGNMENT_CENTER, 160, 16, UiStyle.TEXT_DIM)
	var y := 256.0
	for band in [UiStyle.PANEL, MOSS]:
		c.draw_rect(Rect2(10, y, c.size.x - 20, 200), band)
		for i in TRAITS.size():
			UiIcons.draw(c, TRAITS[i], Rect2(24 + i * 96, y + 14, 56, 56))
			UiIcons.draw(c, TRAITS[i], Rect2(24 + i * 96, y + 100, 40, 40))
			# In a mutation-card medallion (dark disc) as used in the game.
			var medal := Vector2(640 + i * 88, y + 60)
			c.draw_circle(medal, 36, Color("0a1612"))
			UiIcons.draw(c, TRAITS[i], Rect2(medal - Vector2(28, 28), Vector2(56, 56)))
		y += 216
