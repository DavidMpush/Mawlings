extends SceneTree

# Font candidates in the real game (run WITHOUT --headless, e.g.
#   --screen 1 --audio-driver Dummy --script res://tests/capture_fonts.gd).
# For each title x text combination the UiStyle font cache is filled at runtime
# (no file changes) before the game and the menu are loaded, then HUD, mutation
# choice and menu are rendered at 900 x 1600 and cropped 1:1 into one sheet:
#   preview_fonts_<combo>.png   one 900 x 1600 sheet per combination (calm skin)
#   preview_fonts_overview.png  all faces side by side, light on #09191C
# Digit widths and tnum support are printed to the console.

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const DIR := "res://assets/ui/fonts/candidates/"
const TEST_PROFILE := "user://capture_fonts_profile.json"
const SIZE := Vector2i(900, 1600)
const BG := Color("09191c")

# key: [label, file, {axis: value}]
const FACES := {
	"lilita": ["Lilita One", "lilitaone/LilitaOne-Regular.ttf", {}],
	"titan": ["Titan One", "titanone/TitanOne-Regular.ttf", {}],
	"fredoka": ["Fredoka SemiBold 600", "fredoka/Fredoka.ttf", {"wght": 600, "wdth": 100}],
	"baloo": ["Baloo 2 ExtraBold 800", "baloo2/Baloo2.ttf", {"wght": 800}],
	"bebas": ["Bebas Neue", "bebasneue/BebasNeue-Regular.ttf", {}],
	"anton": ["Anton", "anton/Anton-Regular.ttf", {}],
	"nunito": ["Nunito Bold 700", "nunito/Nunito.ttf", {"wght": 700}],
	"figtree": ["Figtree Bold 700", "figtree/Figtree.ttf", {"wght": 700}],
}
const TITLES := ["lilita", "titan", "fredoka", "baloo", "bebas", "anton"]
const BODIES := ["nunito", "figtree"]
const COMBOS := [["lilita", "nunito"], ["titan", "nunito"], ["fredoka", "figtree"],
	["baloo", "figtree"], ["bebas", "nunito"], ["anton", "figtree"]]

# Crops (x, y, w, h in 900 x 1600 frame pixels) and where they go on the sheet.
const CROP_HUD := Rect2i(0, 0, 900, 190)
const CROP_MUT := Rect2i(0, 320, 900, 1000)
const CROP_MENU := Rect2i(0, 100, 900, 200)
const CROP_PLAY := Rect2i(0, 1180, 900, 180)

var _fonts := {}


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = SIZE
	UiStyle.set_skin("calm")
	for key in FACES:
		_fonts[key] = _make_font(key)
	_report_digits()
	var only := _only_combo()
	for combo in COMBOS:
		if only != "" and only != "%s_%s" % combo:
			continue
		await _combo(combo[0], combo[1])
	await _overview()
	if FileAccess.file_exists(TEST_PROFILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))
	UiStyle._fonts.clear()
	print("Saved font previews")
	quit()


## Optional "-- combo=lilita_nunito" to render a single combination.
func _only_combo() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("combo="):
			return arg.substr(6)
	return ""


func _make_font(key: String) -> Font:
	var face: Array = FACES[key]
	var file: FontFile = load(DIR + face[1])
	var axes: Dictionary = face[2]
	if axes.is_empty():
		return file
	var ts := TextServerManager.get_primary_interface()
	var coords := {}
	for axis in axes:
		coords[ts.name_to_tag(axis)] = axes[axis]
	var variation := FontVariation.new()
	variation.base_font = file
	variation.variation_opentype = coords
	return variation


func _report_digits() -> void:
	var ts := TextServerManager.get_primary_interface()
	for key in FACES:
		var font: Font = _fonts[key]
		var base: FontFile = font if font is FontFile else (font as FontVariation).base_font
		var widths := []
		for d in 10:
			widths.append(snappedf(font.get_string_size(str(d), HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x, 0.1))
		var features: Dictionary = base.get_supported_feature_list()
		var tnum := features.has(ts.name_to_tag("tnum"))
		var bytes := FileAccess.get_file_as_bytes(DIR + FACES[key][1]).size()
		print("%-22s digits@100px min %.1f max %.1f  tnum=%s  file=%d KB  glyphs %s" % [FACES[key][0],
			widths.min(), widths.max(), tnum, bytes / 1024, widths])


func _combo(title: String, body: String) -> void:
	UiStyle._fonts["display"] = _fonts[title]
	UiStyle._fonts["body"] = _fonts[body]
	var frames := {}

	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var world: Variant = scene.get_node("HuntWorld")
	var controls: Variant = scene.get_node("HUD/Controls")
	# Background capture windows lose focus; the auto-pause must not end up in the frames.
	controls.pause_requested.disconnect(world.toggle_pause)
	await create_timer(1.2).timeout
	for target in world.prey:
		target.queue_free()
	world.prey.clear()
	world.set_process(false)
	var evo: Variant = world.evolution
	evo.offers = []
	evo.level = 3
	evo.dna = 7
	world.model.population = 128
	world.model.elapsed = 277.0
	world._update_hud("")
	await create_timer(1.4).timeout
	frames.hud = await _grab()

	evo.ranks = {"evade": 1, "rudelbiss": 1}
	evo.rerolls = 1
	evo.banishes = 1
	evo.skips = 1
	evo.dna = maxi(evo.dna, evo.threshold() * 3)
	evo.offers = [evo.info("evade") + ["rare"], evo.info("reach") + ["common"], evo.info("brood") + ["epic"]]
	world._update_hud("")
	await create_timer(1.2).timeout
	frames.mut = await _grab()
	scene.queue_free()
	await process_frame

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
	await create_timer(1.4).timeout
	frames.menu = await _grab()
	menu.queue_free()
	await process_frame

	if OS.get_cmdline_user_args().has("raw"):
		for k in frames:
			frames[k].save_png("res://preview_fonts_raw_%s_%s.png" % [title, k])
	await _sheet(title, body, frames)


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


# One 900 x 1600 sheet from 1:1 crops of the three frames plus a caption.
func _sheet(title: String, body: String, frames: Dictionary) -> void:
	# Textures must outlive the draw call, so they are built up front.
	var parts := [
		[ImageTexture.create_from_image(frames.hud), CROP_HUD],
		[ImageTexture.create_from_image(frames.mut), CROP_MUT],
		[ImageTexture.create_from_image(frames.menu), CROP_MENU],
		[ImageTexture.create_from_image(frames.menu), CROP_PLAY],
	]
	var canvas := Control.new()
	canvas.size = Vector2(SIZE)
	canvas.draw.connect(func() -> void:
		canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), Color("050b0a"))
		var y := 0.0
		for part in parts:
			var src: Rect2i = part[1]
			canvas.draw_texture_rect_region(part[0], Rect2(Vector2(0, y), Vector2(src.size)), Rect2(src))
			y += src.size.y
		var caption := "%s  +  %s" % [FACES[title][0], FACES[body][0]]
		canvas.draw_rect(Rect2(0, SIZE.y - 30, SIZE.x, 30), Color("000000c0"))
		canvas.draw_string(ThemeDB.fallback_font, Vector2(12, SIZE.y - 9), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	)
	root.add_child(canvas)
	for i in 3:
		await process_frame
	var image := await _grab()
	image.save_png("res://preview_fonts_%s_%s.png" % [title, body])
	canvas.queue_free()
	await process_frame


func _overview() -> void:
	var cols := 2
	var cell := Vector2(900, 380)
	var keys: Array = TITLES + BODIES
	var rows := int(ceil(keys.size() / float(cols)))
	var sheet_size := Vector2i(int(cell.x) * cols, int(cell.y) * rows)
	var viewport := SubViewport.new()
	viewport.size = sheet_size
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var canvas := Control.new()
	canvas.size = Vector2(sheet_size)
	canvas.draw.connect(func() -> void:
		canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), BG)
		for i in keys.size():
			var key: String = keys[i]
			var font: Font = _fonts[key]
			var o := Vector2((i % cols) * cell.x, (i / cols) * cell.y)
			canvas.draw_rect(Rect2(o + Vector2(6, 6), cell - Vector2(12, 12)), Color("37645e"), false, 2.0)
			var kind := "TITEL" if TITLES.has(key) else "TEXT"
			var kb := FileAccess.get_file_as_bytes(DIR + FACES[key][1]).size() / 1024
			canvas.draw_string(ThemeDB.fallback_font, o + Vector2(22, 34), "%s · %s · %d KB" % [kind, FACES[key][0], kb], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("4cdacb"))
			var ink := Color("eaf0d9")
			canvas.draw_string(font, o + Vector2(22, 118), "MAWLINGS 128", HORIZONTAL_ALIGNMENT_LEFT, cell.x - 40, 72, ink)
			canvas.draw_string(font, o + Vector2(22, 180), "0123456789 ÄÖÜß 04:37", HORIZONTAL_ALIGNMENT_LEFT, cell.x - 40, 48, ink)
			canvas.draw_string(font, o + Vector2(22, 226), "Rally: alle 2,2 s Sprungangriff auf den nächsten Gegner", HORIZONTAL_ALIGNMENT_LEFT, cell.x - 40, 26, ink)
			canvas.draw_string(font, o + Vector2(22, 262), "−10 % VERLUSTE OHNE RALLY · Größe Übermaß", HORIZONTAL_ALIGNMENT_LEFT, cell.x - 40, 22, ink)
			# Digit jitter: counters 111 / 888 at 48 px, right-aligned with a guide.
			var right := o.x + cell.x - 40
			for j in 3:
				var value: String = ["111", "888", "250"][j]
				var w := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 48).x
				canvas.draw_string(font, Vector2(o.x + 22 + j * 170, o.y + 350), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 48, ink)
				canvas.draw_line(Vector2(o.x + 22 + j * 170, o.y + 358), Vector2(o.x + 22 + j * 170 + w, o.y + 358), Color("d9aa5b"), 3.0)
			var widths := []
			for d in 10:
				widths.append(font.get_string_size(str(d), HORIZONTAL_ALIGNMENT_LEFT, -1, 48).x)
			canvas.draw_string(ThemeDB.fallback_font, Vector2(o.x + 540, o.y + 350), "Ziffern 48px: %.0f–%.0f px" % [widths.min(), widths.max()], HORIZONTAL_ALIGNMENT_LEFT, right - o.x - 540, 18, Color("d9aa5b"))
	)
	viewport.add_child(canvas)
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://preview_fonts_overview.png")
	viewport.queue_free()
	await process_frame
