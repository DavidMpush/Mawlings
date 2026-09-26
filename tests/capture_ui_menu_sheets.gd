extends SceneTree
## Vorschau der Menü-Komponente MENU_SHEETS (Brutkammer, Trophäen, Urinstinkt,
## Belohnungs-Overlay, Toast) im echten Menü mit Beispielprofil.
## OHNE --headless ausführen:
##   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/capture_ui_menu_sheets.gd
## Nutzt ein eigenes Testprofil; das echte Profil bleibt unberührt.

const TEST_PROFILE := "user://capture_ui_menu_sheets_profile.json"
const COMPONENT := "res://scripts/ui/menu/menu_sheets.gd"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	# Keep rendering even when the window loses focus.
	OS.low_processor_usage_mode = false
	var session: Variant = load("res://scripts/meta/session.gd")
	_delete_profile()
	var profile: Variant = load("res://scripts/meta/profile.gd").load_or_create(TEST_PROFILE)
	profile.essence = 1240
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
	session.last_result = {}
	var menu := _spawn()
	await _wait(0.3)
	menu.open_tab("upgrades")
	menu._toast("Gekauft")
	await _wait(0.4)
	await _shot("res://preview_ui_menu_sheets_upgrades.png")
	menu.open_tab("trophies")
	await _wait(0.2)
	await _shot("res://preview_ui_menu_sheets_trophies.png")
	menu._scroll_trophies(-99999.0)
	await _wait(0.2)
	await _shot("res://preview_ui_menu_sheets_trophies_end.png")
	menu.open_tab("instinct")
	await _wait(0.2)
	await _shot("res://preview_ui_menu_sheets_instinct.png")
	menu.queue_free()
	await process_frame
	session.last_result = {"strain_id": "glutmaw", "biome_id": "verdant_maw", "difficulty": 0, "seconds": 318.0,
		"peak_population": 112, "final_population": 0, "kills": 214,
		"kills_by_type": {"prey": 150, "hunter": 40, "skitter": 12, "leaper": 5, "boss": 1}, "biomass": 420.0,
		"lost": 180, "bosses": 1, "evolutions": [], "mutations": {"jaws": 2, "pack": 1}, "used_rally": true}
	menu = _spawn()
	await _wait(0.9)
	await _shot("res://preview_ui_menu_sheets_reward_count.png")
	await _wait(2.6)
	await _shot("res://preview_ui_menu_sheets_reward.png")
	menu.queue_free()
	_delete_profile()
	print("Saved menu sheet previews")
	quit()


func _spawn() -> Control:
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	menu.profile_path = TEST_PROFILE
	menu.change_scene_on_play = false
	menu.legacy["sheet"] = false
	menu.legacy["reward"] = false
	var sheets: Control = load(COMPONENT).new()
	sheets.name = "MenuSheets"
	menu.add_child(sheets)
	root.add_child(menu)
	return menu


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _delete_profile() -> void:
	if FileAccess.file_exists(TEST_PROFILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))


func _shot(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
