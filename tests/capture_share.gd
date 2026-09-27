extends SceneTree
## Stage 10 review frames: three share cards (short run, long run with flood and
## evolution, daily brood) at 1080 x 1920 and the CHRONIK sheet (runs, daily,
## bests). Run WITHOUT --headless:
##   Godot --screen 1 --audio-driver Dummy --path . --script res://tests/capture_share.gd

const TEST_PROFILE := "user://capture_share_profile.json"
const TEST_CHRONICLE := "user://capture_share_chronicle.json"

const RUNS := {
	"short": {"strain_id": "glutmaw", "biome_id": "verdant_maw", "difficulty": 0, "seconds": 47.0,
		"peak_population": 38, "kills": 52, "bosses": 0, "biomass": 96.0, "mutations": {"jaws": 1},
		"evolutions": [], "flood_reached": false, "flood_seconds": 0.0, "seed": 1234567},
	"long": {"strain_id": "knochenkiefer", "biome_id": "verdant_maw", "difficulty": 1, "seconds": 872.0,
		"peak_population": 250, "kills": 3120, "bosses": 4, "biomass": 5400.0,
		"mutations": {"jaws": 3, "pack": 3, "armor": 2, "stachelruecken": 3, "brood": 1}, "evolutions": ["meute"],
		"flood_reached": true, "flood_seconds": 505.0, "seed": 987654321},
	"daily": {"strain_id": "sporling", "biome_id": "verdant_maw", "difficulty": 0, "seconds": 401.0,
		"peak_population": 196, "kills": 1260, "bosses": 2, "biomass": 2300.0,
		"mutations": {"sporenwolke": 3, "brood": 3, "glutton": 2}, "evolutions": [],
		"flood_reached": true, "flood_seconds": 101.0, "seed": 55443322, "daily": true, "daily_rank": 2},
}


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	var chronicle_script: Variant = load("res://scripts/meta/chronicle.gd")
	var profile_script: Variant = load("res://scripts/meta/profile.gd")
	# Share cards straight from RunStats-like dictionaries.
	for key in RUNS:
		var card: Node = load("res://scripts/ui/share_card.gd").new()
		root.add_child(card)
		var stats: Dictionary = RUNS[key].duplicate(true)
		stats["date"] = profile_script.today_key()
		stats["daily_date"] = profile_script.today_key() if stats.get("daily", false) else ""
		var path: String = await card.render(stats, "res://", "preview_share_%s.png" % key)
		print("Saved ", path)
		card.queue_free()
		await process_frame
	# CHRONIK with a filled history.
	for p in [TEST_PROFILE, TEST_CHRONICLE]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var profile: Variant = profile_script.load_or_create(TEST_PROFILE)
	profile.essence = 640
	profile.crowns = 3
	profile.records.runs = 14
	profile.records.best_seconds = 872.0
	profile.records.best_peak = 250
	profile.unlocked_strains.append("knochenkiefer")
	profile.owned_strains.append("knochenkiefer")
	profile.seen_tips = ["move"]
	profile.save()
	var chron: Variant = chronicle_script.load_or_create(TEST_CHRONICLE)
	var today: String = profile_script.today_key()
	var now := int(Time.get_unix_time_from_system())
	var strains := ["glutmaw", "sporling", "knochenkiefer"]
	for i in 12:
		var s: Dictionary = RUNS.short.duplicate(true)
		s.strain_id = strains[i % 3]
		s.difficulty = 1 if i % 5 == 2 else 0
		s.seconds = 60.0 + float((i * 97) % 600)
		s.peak_population = 30 + (i * 37) % 200
		s.kills = int(s.seconds * 2.4)
		s.flood_reached = s.seconds > 300.0
		s.flood_seconds = maxf(0.0, s.seconds - 300.0)
		var daily := i % 4 == 1
		chron.record(s, {"date": today, "time": now - (12 - i) * 1800, "daily": daily, "daily_date": today if daily else ""})
	chron.record(RUNS.long, {"date": today, "time": now - 900})
	chron.record(RUNS.daily, {"date": today, "time": now - 300, "daily": true, "daily_date": today})
	chron.record(RUNS.short, {"date": "2026-09-25", "time": now - 200000, "daily": true, "daily_date": "2026-09-25"})
	chron.save()
	load("res://scripts/meta/session.gd").last_result = {}
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	menu.profile_path = TEST_PROFILE
	menu.chronicle_path = TEST_CHRONICLE
	menu.change_scene_on_play = false
	menu.skip_menu_on_first_start = false
	menu.open_shares = false
	root.add_child(menu)
	await _shot("res://preview_menu_chronicle_main.png")
	menu.open_chronicle("runs")
	await _shot("res://preview_menu_chronicle.png")
	menu.select_chronicle_view("daily")
	await _shot("res://preview_menu_chronicle_daily.png")
	menu.select_chronicle_view("best")
	await _shot("res://preview_menu_chronicle_best.png")
	menu.queue_free()
	await process_frame
	# Reward overlay with the KARTE TEILEN button.
	load("res://scripts/meta/session.gd").last_result = RUNS.long.duplicate(true)
	menu = load("res://scenes/menu.tscn").instantiate()
	menu.profile_path = TEST_PROFILE
	menu.chronicle_path = TEST_CHRONICLE
	menu.change_scene_on_play = false
	menu.open_shares = false
	root.add_child(menu)
	await _shot("res://preview_menu_reward_share.png")
	menu.queue_free()
	await process_frame
	for p in [TEST_PROFILE, TEST_CHRONICLE]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("Saved share + chronicle review frames")
	quit()


func _shot(path: String) -> void:
	await process_frame
	await create_timer(2.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
