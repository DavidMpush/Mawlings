extends SceneTree
## Stage 15 / MENU_SHEETS (brawl skin): renders the menu sheets with the menu's
## own components at 900 x 1600 and 540 x 960: Brutkammer (plus a held buy
## button and a toast), Trophäen (top and scrolled), Urinstinkt, Chronik (runs,
## scrolled, Tages-Brut, Bestwerte), Einstellungen and the reward overlay
## (while counting and settled).
## Run WITHOUT --headless (frame_post_draw needs a window), with
## --audio-driver Dummy --screen 1. Uses a scratch profile and chronicle; the
## real player files are never touched. Writes preview_ui_menu_sheets_<state>[_540].png.

const TEST_PROFILE := "user://capture_ui_menu_sheets_profile.json"
const TEST_CHRONICLE := "user://capture_ui_menu_sheets_profile_chronicle.json"
const SIZES := [[Vector2i(900, 1600), ""], [Vector2i(540, 960), "_540"]]
const UiStyle := preload("res://scripts/ui/ui_style.gd")


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	UiStyle.set_skin("brawl")
	OS.low_processor_usage_mode = false
	for entry in SIZES:
		await _capture_size(entry[0], entry[1])
	_delete_files()
	print("Saved MENU_SHEETS review frames")
	quit()


func _capture_size(window: Vector2i, suffix: String) -> void:
	root.size = window
	DisplayServer.window_set_size(window)
	var session: Variant = load("res://scripts/meta/session.gd")
	_delete_files()
	var profile_script: Variant = load("res://scripts/meta/profile.gd")
	var profile: Variant = profile_script.load_or_create(TEST_PROFILE)
	profile.essence = 12480
	profile.crowns = 4
	profile.upgrades["brood_size"] = 3
	profile.upgrades["rending"] = 2
	profile.upgrades["chitin"] = 10
	profile.upgrades["sprinter"] = 1
	profile.upgrades["digestion"] = 5
	profile.instinct_level = 13
	profile.completed_quests.append_array(["survive_1", "survive_3", "peak_50", "kills_100", "biomass_1000"])
	profile.records.best_seconds = 262.0
	profile.records.best_peak = 88
	profile.records.total_kills = 340
	profile.records.total_prey = 120
	profile.records.total_hunters = 34
	profile.records.total_leapers = 6
	profile.records.total_biomass = 1400.0
	profile.records.runs = 7
	profile.save()
	_seed_chronicle(profile_script.today_key())
	session.last_result = {}
	var menu := _spawn()
	await _settle(20)
	# Brutkammer: essence for all but the last upgrade; one buy button held.
	menu.open_tab("upgrades")
	menu.profile.essence = 700
	menu.set("_press_pos", menu.upgrade_buy_rect(1).get_center())
	await _settle(8)
	await _shot("res://previews/preview_ui_menu_sheets_upgrades%s.png" % suffix)
	menu.set("_press_pos", Vector2.INF)
	menu.profile.essence = 12480
	menu._toast("Gekauft")
	await _settle(14)
	await _shot("res://previews/preview_ui_menu_sheets_upgrades_toast%s.png" % suffix)
	menu.toast_time = 0.0
	menu.open_tab("trophies")
	await _settle(8)
	await _shot("res://previews/preview_ui_menu_sheets_trophies%s.png" % suffix)
	menu._scroll_trophies(-99999.0)
	await _settle(8)
	await _shot("res://previews/preview_ui_menu_sheets_trophies_end%s.png" % suffix)
	menu.open_tab("instinct")
	await _settle(8)
	await _shot("res://previews/preview_ui_menu_sheets_instinct%s.png" % suffix)
	menu.profile.essence = 300
	await _settle(8)
	await _shot("res://previews/preview_ui_menu_sheets_instinct_poor%s.png" % suffix)
	menu.profile.essence = 12480
	menu.open_chronicle("runs")
	await _settle(8)
	await _shot("res://previews/preview_ui_menu_sheets_chronicle%s.png" % suffix)
	menu._scroll_trophies(-99999.0)
	await _settle(8)
	await _shot("res://previews/preview_ui_menu_sheets_chronicle_end%s.png" % suffix)
	menu.select_chronicle_view("daily")
	await _settle(8)
	await _shot("res://previews/preview_ui_menu_sheets_chronicle_daily%s.png" % suffix)
	menu.select_chronicle_view("best")
	await _settle(8)
	await _shot("res://previews/preview_ui_menu_sheets_chronicle_best%s.png" % suffix)
	# Settings over the main page.
	menu.open_tab("chronicle")
	menu.open_settings()
	# Volume sliders: master 100 %, music 45 %, effects off (mute cross).
	menu.set_volume("volume_music", 0.45)
	menu.set_volume("volume_sfx", 0.0)
	await _settle(8)
	await _shot("res://previews/preview_ui_menu_sheets_settings%s.png" % suffix)
	# UI style switch: RUHIG applies at once (the old frames draw the same
	# rects), then BRAWL again; the choice is saved in the profile.
	menu.tap(menu.settings_skin_rect(1).get_center())
	await _settle(8)
	await _shot("res://previews/preview_ui_menu_sheets_settings_calm%s.png" % suffix)
	menu.close_settings()
	menu.open_tab("upgrades")
	await _settle(8)
	await _shot("res://previews/preview_ui_menu_sheets_upgrades_calm%s.png" % suffix)
	menu.open_settings()
	menu.tap(menu.settings_skin_rect(0).get_center())
	await _settle(4)
	menu.queue_free()
	await process_frame
	# Reward overlay after a run with new trophies and an unlock.
	var fresh: Variant = profile_script.load_or_create(TEST_PROFILE)
	fresh.completed_quests.clear()
	fresh.records.best_seconds = 0.0
	fresh.records.best_peak = 0
	fresh.save()
	session.last_result = {"strain_id": "glutmaw", "biome_id": "verdant_maw", "difficulty": 0, "seconds": 318.0,
		"peak_population": 112, "final_population": 0, "kills": 214,
		"kills_by_type": {"prey": 150, "hunter": 40, "skitter": 12, "leaper": 5, "boss": 1}, "biomass": 420.0,
		"lost": 180, "bosses": 1, "evolutions": [], "mutations": {"jaws": 2, "pack": 1}, "used_rally": true}
	menu = _spawn()
	await _wait(0.9)
	await _shot("res://previews/preview_ui_menu_sheets_reward_count%s.png" % suffix)
	await _wait(2.8)
	await _shot("res://previews/preview_ui_menu_sheets_reward%s.png" % suffix)
	menu.queue_free()
	await process_frame


func _seed_chronicle(today: String) -> void:
	var chronicle: Variant = load("res://scripts/meta/chronicle.gd").load_or_create(TEST_CHRONICLE)
	var runs := [
		["glutmaw", 0, 184.0, 64, 120, false], ["sporling", 0, 262.0, 88, 214, false], ["glutmaw", 1, 141.0, 51, 98, false],
		["aetzmaul", 0, 96.0, 30, 44, true], ["glutmaw", 0, 305.0, 79, 260, true], ["nachtmaul", 2, 72.0, 22, 31, false],
		["glutmaw", 0, 58.0, 18, 20, false], ["sporling", 1, 199.0, 70, 150, false],
	]
	for r in runs:
		var stats := {"strain_id": r[0], "biome_id": "verdant_maw", "difficulty": r[1], "seconds": r[2],
			"peak_population": r[3], "kills": r[4], "flood_stage": 2 if r[2] > 300.0 else 0}
		chronicle.record(stats, {"daily": r[5], "date": today, "daily_date": today})
	chronicle.save()


func _spawn() -> Control:
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	menu.profile_path = TEST_PROFILE
	menu.change_scene_on_play = false
	menu.skip_menu_on_first_start = false
	root.add_child(menu)
	return menu


func _delete_files() -> void:
	for path in [TEST_PROFILE, TEST_CHRONICLE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _settle(frames: int) -> void:
	for i in frames:
		await process_frame


func _shot(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
