extends SceneTree
## Etappe 17d + KODEX: renders the strain card of every strain with its ability
## strip (all owned, plus one locked), the TROPHÄEN sheet with the KODEX button
## and the KODEX sheet for each of its five categories (some entries discovered,
## the rest as silhouettes). 900 x 1600, the strain cards also at 540 x 960.
## Run WITHOUT --headless (frame_post_draw needs a window), with
## --audio-driver Dummy --screen 1. Uses a scratch profile. Writes
## previews/preview_ui_codex_<state>[_540].png.

const TEST_PROFILE := "user://capture_ui_codex_profile.json"
const SEEN := ["weapon:rudelbiss", "weapon:sporenwolke", "weapon:giftbiss", "weapon:meute",
	"relic:blutzahn", "relic:scharfe_zaehne", "relic:urmutter", "relic:glutdruese",
	"stat:bite", "stat:crit", "stat:armor", "stat:lifesteal", "stat:luck",
	"powerup:rausch", "powerup:raserei", "boss:bog_king", "boss:moosschlund"]


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var menu := await _spawn(Vector2i(900, 1600))
	for id in menu.strain_ids:
		menu.strain_index = menu.strain_ids.find(id)
		await _settle(10)
		await _shot("res://previews/preview_ui_codex_strain_%s.png" % id)
	# A locked strain shows its ability too (below the trophy quest).
	menu.profile.owned_strains.erase("nachtmaul")
	menu.profile.unlocked_strains.erase("nachtmaul")
	menu.strain_index = menu.strain_ids.find("nachtmaul")
	await _settle(10)
	await _shot("res://previews/preview_ui_codex_strain_locked.png")
	menu.open_tab("trophies")
	await _settle(10)
	await _shot("res://previews/preview_ui_codex_trophies.png")
	menu.open_codex("weapons")
	for cat in menu.codex.CATEGORIES:
		menu.select_codex_view(cat)
		await _settle(10)
		await _shot("res://previews/preview_ui_codex_%s.png" % cat)
	menu.select_codex_view("weapons")
	menu.trophy_scroll = menu._trophy_scroll_max()
	await _settle(10)
	await _shot("res://previews/preview_ui_codex_weapons_end.png")
	menu.queue_free()
	await process_frame
	# Phone-size check of the strain card (longest ability texts).
	menu = await _spawn(Vector2i(540, 960))
	for id in ["knochenkiefer", "aetzmaul", "nachtmaul"]:
		menu.strain_index = menu.strain_ids.find(id)
		await _settle(10)
		await _shot("res://previews/preview_ui_codex_strain_%s_540.png" % id)
	menu.open_codex("relics")
	await _settle(10)
	await _shot("res://previews/preview_ui_codex_relics_540.png")
	menu.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))
	print("Saved KODEX review frames")
	quit()


func _spawn(window: Vector2i) -> Control:
	root.size = window
	DisplayServer.window_set_size(window)
	var session: Variant = load("res://scripts/meta/session.gd")
	if FileAccess.file_exists(TEST_PROFILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))
	var profile_script: Variant = load("res://scripts/meta/profile.gd")
	var profile: Variant = profile_script.load_or_create(TEST_PROFILE)
	profile.essence = 12480
	profile.crowns = 4
	for id in ["knochenkiefer", "flinkzahn", "aetzmaul", "nachtmaul"]:
		profile.unlocked_strains.append(id)
		profile.owned_strains.append(id)
	profile.completed_quests.append_array(["survive_1", "survive_3", "peak_50", "kills_100", "boss_1"])
	profile.records.total_bosses = 3
	profile.records.total_moss = 1
	profile.codex_seen.append_array(SEEN)
	profile.save()
	session.last_result = {}
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	menu.profile_path = TEST_PROFILE
	menu.change_scene_on_play = false
	menu.skip_menu_on_first_start = false
	root.add_child(menu)
	await _settle(24)
	return menu


func _settle(frames: int) -> void:
	for i in frames:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(path)
	print("Saved ", path)
