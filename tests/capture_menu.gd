extends SceneTree
## Renders the Brutstätte states for visual review. Run WITHOUT --headless.

const TEST_PROFILE := "user://capture_menu_profile.json"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	var session: Variant = load("res://scripts/meta/session.gd")
	if FileAccess.file_exists(TEST_PROFILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))
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
	profile.save()
	session.last_result = {}
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	menu.profile_path = TEST_PROFILE
	menu.change_scene_on_play = false
	root.add_child(menu)
	await _shot("res://preview_menu_main.png")
	menu.strain_index = menu.strain_ids.find("knochenkiefer")
	await _shot("res://preview_menu_locked.png")
	menu.profile.unlocked_strains.append("knochenkiefer")
	await _shot("res://preview_menu_buy.png")
	menu.strain_index = 0
	menu.open_tab("upgrades")
	await _shot("res://preview_menu_upgrades.png")
	menu.open_tab("trophies")
	await _shot("res://preview_menu_trophies.png")
	menu.open_tab("instinct")
	await _shot("res://preview_menu_instinct.png")
	menu.queue_free()
	await process_frame
	session.last_result = {"strain_id": "glutmaw", "biome_id": "verdant_maw", "difficulty": 0, "seconds": 318.0,
		"peak_population": 112, "final_population": 0, "kills": 214,
		"kills_by_type": {"prey": 150, "hunter": 40, "skitter": 12, "leaper": 5, "boss": 1}, "biomass": 420.0,
		"lost": 180, "bosses": 1, "evolutions": [], "mutations": {"jaws": 2, "pack": 1}, "used_rally": true}
	menu = load("res://scenes/menu.tscn").instantiate()
	menu.profile_path = TEST_PROFILE
	root.add_child(menu)
	await _shot("res://preview_menu_rewards.png")
	menu.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))
	print("Saved menu review frames")
	quit()


func _shot(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
