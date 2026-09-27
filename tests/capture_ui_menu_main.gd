extends SceneTree
## Stage 15 / MENU_MAIN (brawl skin): renders the Brutstätte main view with the
## menu's own components at 900 x 1600 and 540 x 960 for the review states:
## standard (Glutmaw), another owned strain (Sporling), a locked strain, a
## buyable strain, the longest description (Ätzmaul), TAGES-BRUT played today + held down, and an open tab.
## Run WITHOUT --headless (frame_post_draw needs a window), with
## --audio-driver Dummy --screen 1. Uses a scratch profile; the real player
## profile is never touched. Writes preview_ui_menu_main_<state>[_540].png.

const TEST_PROFILE := "user://capture_ui_menu_main_profile.json"
const SIZES := [[Vector2i(900, 1600), ""], [Vector2i(540, 960), "_540"]]


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	for entry in SIZES:
		await _capture_size(entry[0], entry[1])
	print("Saved MENU_MAIN review frames")
	quit()


func _capture_size(window: Vector2i, suffix: String) -> void:
	root.size = window
	DisplayServer.window_set_size(window)
	var session: Variant = load("res://scripts/meta/session.gd")
	if FileAccess.file_exists(TEST_PROFILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))
	var profile_script: Variant = load("res://scripts/meta/profile.gd")
	var profile: Variant = profile_script.load_or_create(TEST_PROFILE)
	profile.essence = 12480
	profile.crowns = 4
	profile.upgrades["brood_size"] = 3
	profile.upgrades["rending"] = 2
	profile.instinct_level = 3
	profile.completed_quests.append_array(["survive_1", "survive_3", "peak_50", "kills_100"])
	profile.records.best_seconds = 262.0
	profile.records.best_peak = 250
	profile.records.total_kills = 340
	profile.records.total_leapers = 6
	profile.records.total_bosses = 0
	profile.save()
	session.last_result = {}
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	menu.profile_path = TEST_PROFILE
	menu.change_scene_on_play = false
	menu.skip_menu_on_first_start = false
	root.add_child(menu)
	await _settle(24)
	await _shot("res://preview_ui_menu_main%s.png" % suffix)
	menu.strain_index = menu.strain_ids.find("sporling")
	await _settle(12)
	await _shot("res://preview_ui_menu_main_other%s.png" % suffix)
	menu.strain_index = menu.strain_ids.find("knochenkiefer")
	await _settle(12)
	await _shot("res://preview_ui_menu_main_locked%s.png" % suffix)
	menu.profile.unlocked_strains.append("knochenkiefer")
	await _settle(12)
	await _shot("res://preview_ui_menu_main_buy%s.png" % suffix)
	# Longest description (Ätzmaul) as an owned strain: two lines + chips must fit.
	menu.profile.unlocked_strains.append("aetzmaul")
	menu.profile.owned_strains.append("aetzmaul")
	menu.strain_index = menu.strain_ids.find("aetzmaul")
	await _settle(12)
	await _shot("res://preview_ui_menu_main_long%s.png" % suffix)
	# TAGES-BRUT: today's record is booked and the button is held down.
	menu.strain_index = menu.strain_ids.find("glutmaw")
	menu.profile.daily_records[profile_script.today_key()] = {"seconds": 261.0, "peak": 180, "runs": 2}
	menu.set("_press_pos", menu.daily_rect().get_center())
	await _settle(12)
	await _shot("res://preview_ui_menu_main_daily%s.png" % suffix)
	menu.set("_press_pos", Vector2.INF)
	menu.open_tab("upgrades")
	await _settle(12)
	await _shot("res://preview_ui_menu_main_tab%s.png" % suffix)
	menu.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))


func _settle(frames: int) -> void:
	for i in frames:
		await process_frame


func _shot(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
