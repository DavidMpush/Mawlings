extends SceneTree
## Renders the Brutstätte states for visual review. Run WITHOUT --headless.

const TEST_PROFILE := "user://capture_menu_profile.json"
## The menu derives a separate chronicle next to a test profile (stage 10).
const TEST_CHRONICLE := "user://capture_menu_profile_chronicle.json"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	var session: Variant = load("res://scripts/meta/session.gd")
	for p in [TEST_PROFILE, TEST_CHRONICLE]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	# A mid-progress profile so the screens show mixed states.
	var profile: Variant = load("res://scripts/meta/profile.gd").load_or_create(TEST_PROFILE)
	profile.essence = 1240
	profile.crowns = 4
	profile.upgrades["brood_size"] = 3
	profile.upgrades["rending"] = 2
	profile.upgrades["chitin"] = 10
	profile.upgrades["sprinter"] = 1
	profile.instinct_level = 3
	profile.completed_quests.append_array(["survive_1", "survive_3", "peak_50", "kills_100"])
	profile.records.best_seconds = 262.0
	profile.records.best_peak = 88
	profile.records.total_kills = 340
	profile.records.total_leapers = 6
	profile.next_seed = 1234567
	profile.record_daily(profile.today_key(), 261.0, 180)
	profile.save()
	session.last_result = {}
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	menu.profile_path = TEST_PROFILE
	menu.change_scene_on_play = false
	root.add_child(menu)
	await _shot("res://previews/preview_menu_main.png")
	# TAGES-BRUT held down (pressed state) with today's record.
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = menu.daily_rect().get_center()
	menu._gui_input(press)
	await _shot("res://previews/preview_menu_daily.png")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = press.position + Vector2(0, -200)
	var drag := InputEventMouseMotion.new()
	drag.position = release.position
	menu._gui_input(drag)
	menu._gui_input(release)
	menu.open_settings()
	menu.toggle_setting("colorblind")
	menu.toggle_setting("vibration")
	await _shot("res://previews/preview_menu_settings.png")
	menu.toggle_setting("colorblind")
	menu.toggle_setting("vibration")
	menu.close_settings()
	menu.strain_index = menu.strain_ids.find("knochenkiefer")
	await _shot("res://previews/preview_menu_locked.png")
	menu.profile.unlocked_strains.append("knochenkiefer")
	await _shot("res://previews/preview_menu_buy.png")
	menu.strain_index = 0
	menu.open_tab("upgrades")
	await _shot("res://previews/preview_menu_upgrades.png")
	menu.open_tab("trophies")
	await _shot("res://previews/preview_menu_trophies.png")
	menu.open_tab("instinct")
	await _shot("res://previews/preview_menu_instinct.png")
	menu.queue_free()
	await process_frame
	session.last_result = {"strain_id": "glutmaw", "biome_id": "verdant_maw", "difficulty": 0, "seconds": 318.0,
		"peak_population": 112, "final_population": 0, "kills": 214,
		"kills_by_type": {"prey": 150, "hunter": 40, "skitter": 12, "leaper": 5, "boss": 1}, "biomass": 420.0,
		"lost": 180, "bosses": 1, "evolutions": [], "mutations": {"jaws": 2, "pack": 1}, "used_rally": true}
	menu = load("res://scenes/menu.tscn").instantiate()
	menu.profile_path = TEST_PROFILE
	root.add_child(menu)
	await _shot("res://previews/preview_menu_rewards.png")
	menu.queue_free()
	await process_frame
	# Result of a daily brood: subtitle names TAGES-BRUT and the new day record.
	load("res://scripts/menu/menu.gd").daily_pending = {"date": profile.today_key(), "seed": profile.daily_seed(), "strain": "glutmaw"}
	session.last_result = {"strain_id": "glutmaw", "biome_id": "verdant_maw", "difficulty": 0, "seconds": 402.0,
		"peak_population": 196, "final_population": 0, "kills": 260,
		"kills_by_type": {"prey": 200, "hunter": 50, "skitter": 10}, "biomass": 500.0,
		"lost": 200, "bosses": 0, "evolutions": [], "mutations": {"jaws": 3}, "used_rally": true}
	menu = load("res://scenes/menu.tscn").instantiate()
	menu.profile_path = TEST_PROFILE
	root.add_child(menu)
	await _shot("res://previews/preview_menu_daily_reward.png")
	menu.close_reward()
	await _shot("res://previews/preview_menu_after_daily.png")
	menu.queue_free()
	for p in [TEST_PROFILE, TEST_CHRONICLE]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("Saved menu review frames")
	quit()


func _shot(path: String) -> void:
	await process_frame
	# Components animate in (count-ups, fades); wait before each frame.
	await create_timer(2.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
