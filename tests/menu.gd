extends SceneTree
## Brutstätte flow: loads without a profile, strain switching, purchases with and
## without enough currency, SPIELEN fills Session.pending_config, reward overlay,
## seed code + reroll, TAGES-BRUT config and daily record, settings, pressed state.

const TEST_PROFILE := "user://test_menu_profile.json"
const CONFIG_KEYS := ["strain_id", "biome_id", "difficulty", "start_population", "tint", "signature_attack", "mods", "enemy_hp", "enemy_damage", "pressure_doubling", "slots", "rerolls", "banishes", "skips", "pool"]
const MOD_KEYS := ["damage", "armor", "speed", "harvest", "dna", "growth"]

var session: Variant


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(60.0).timeout.connect(func() -> void: _fail("Menu test timed out"))
	for path in ["res://scripts/meta/profile.gd", "res://scripts/meta/session.gd", "res://scripts/meta/meta_data.gd"]:
		if not ResourceLoader.exists(path):
			_fail("Meta script missing: %s" % path)
			return
	session = load("res://scripts/meta/session.gd")
	_delete_test_profile()
	session.last_result = {}
	session.pending_config = {}
	var menu := _spawn()
	await process_frame
	await process_frame
	if menu.profile == null:
		_fail("Menu did not create a profile: %s" % menu.load_error)
		return
	if not menu.reward.is_empty():
		_fail("Reward overlay must stay hidden without last_result")
		return
	# Fresh profile: first owned strain is selected and playable.
	if not menu.can_play():
		_fail("Fresh profile must be able to play")
		return
	var first: String = menu.current_strain()
	menu.tap(menu.strain_next_rect().get_center())
	if menu.current_strain() == first:
		_fail("Next arrow did not switch strain")
		return
	menu.tap(menu.strain_prev_rect().get_center())
	if menu.current_strain() != first:
		_fail("Prev arrow did not switch back")
		return
	# Swipe on the strain card switches too.
	_drag(menu, menu.strain_card_rect().get_center(), Vector2(-180, 0))
	if menu.current_strain() == first:
		_fail("Swipe did not switch strain")
		return
	menu.select_strain(-1)
	# A locked strain blocks SPIELEN.
	var locked_index: int = menu.strain_ids.find("knochenkiefer")
	menu.strain_index = locked_index
	if menu.can_play() or not menu.play().is_empty():
		_fail("Locked strain must not start a run")
		return
	# Unlocked but not owned: buy with crowns.
	menu.profile.unlocked_strains.append("knochenkiefer")
	menu.profile.crowns = 1
	menu.tap(menu.strain_buy_rect().get_center())
	if menu.profile.owned_strains.has("knochenkiefer"):
		_fail("Strain purchase must fail without enough crowns")
		return
	menu.profile.crowns = 10
	menu.tap(menu.strain_buy_rect().get_center())
	if not menu.profile.owned_strains.has("knochenkiefer") or menu.profile.crowns != 7:
		_fail("Strain purchase with crowns failed")
		return
	menu.strain_index = menu.strain_ids.find(first)
	# Difficulty: locked Brutal is refused, Wild stays.
	menu.tap(menu.difficulty_rect(1).get_center())
	if menu.difficulty != 0:
		_fail("Locked difficulty must not be selectable")
		return
	# Locked biome is refused.
	menu.tap(menu.biome_rect(1).get_center())
	if menu.biome_id != "verdant_maw":
		_fail("Locked biome must not be selectable")
		return
	# Upgrades tab: buying without essence fails, with essence succeeds and saves.
	menu.tap(menu.tab_rect(0).get_center())
	if menu.tab != "upgrades":
		_fail("Brutkammer tab did not open")
		return
	menu.profile.essence = 0
	menu.tap(menu.upgrade_buy_rect(1).get_center())
	if int(menu.profile.upgrades.get("rending", 0)) != 0:
		_fail("Upgrade purchase must fail without essence")
		return
	menu.profile.essence = 1000
	var cost: int = menu.profile.upgrade_cost("rending")
	menu.tap(menu.upgrade_buy_rect(1).get_center())
	if int(menu.profile.upgrades.get("rending", 0)) != 1 or menu.profile.essence != 1000 - cost:
		_fail("Upgrade purchase with essence failed")
		return
	var reloaded: Variant = load("res://scripts/meta/profile.gd").load_or_create(TEST_PROFILE)
	if int(reloaded.upgrades.get("rending", 0)) != 1:
		_fail("Purchase was not saved")
		return
	# Instinct tab.
	menu.tap(menu.tab_rect(2).get_center())
	var essence_before: int = menu.profile.essence
	menu.tap(menu.instinct_buy_rect().get_center())
	if menu.profile.instinct_level != 1 or menu.profile.essence >= essence_before:
		_fail("Urinstinkt purchase failed")
		return
	# Trophies tab scrolls.
	menu.tap(menu.tab_rect(1).get_center())
	if menu.tab != "trophies":
		_fail("Trophy tab did not open")
		return
	_drag(menu, menu.sheet_rect().get_center(), Vector2(0, -400))
	if menu.trophy_scroll <= 0.0:
		_fail("Trophy list did not scroll")
		return
	menu.tap(menu.sheet_close_rect().get_center())
	if menu.tab != "":
		_fail("Sheet close button failed")
		return
	if not _check_layout(menu):
		return
	if not _check_seed(menu):
		return
	if not _check_settings(menu):
		return
	if not _check_pressed(menu):
		return
	# SPIELEN: pending_config with all RunConfig fields.
	menu.change_scene_on_play = false
	menu.tap(menu.play_rect().get_center())
	var config: Dictionary = session.pending_config
	for key in CONFIG_KEYS:
		if not config.has(key):
			_fail("RunConfig is missing '%s'" % key)
			return
	for key in MOD_KEYS:
		if not config.mods.has(key):
			_fail("RunConfig.mods is missing '%s'" % key)
			return
	if config.strain_id != first or config.difficulty != 0 or config.biome_id != "verdant_maw":
		_fail("RunConfig does not match the menu selection")
		return
	if not is_equal_approx(float(config.mods.damage), 1.05 * 1.01 * float(load("res://scripts/meta/meta_data.gd").STRAINS[first].mods.damage)):
		_fail("RunConfig does not include meta upgrades: %s" % config.mods)
		return
	if int(config.get("seed", 0)) != int(menu.profile.next_seed) or config.get("daily", false):
		_fail("SPIELEN must use the shown next_seed and no daily flag: %s" % config.get("seed"))
		return
	if not (config.get("settings") is Dictionary) or config.settings.get("sound", true):
		_fail("RunConfig must carry the saved settings (sound off): %s" % config.get("settings"))
		return
	# TAGES-BRUT: daily seed, fixed Wild and first biome, selected strain; even with Brutal chosen.
	menu.profile.unlocked_difficulties.append(1)
	menu.select_difficulty(1)
	session.pending_config = {}
	menu.tap(menu.daily_rect().get_center())
	var daily: Dictionary = session.pending_config
	var profile_script: Variant = load("res://scripts/meta/profile.gd")
	if daily.is_empty() or not daily.get("daily", false):
		_fail("TAGES-BRUT did not fill a daily RunConfig")
		return
	if int(daily.seed) != int(profile_script.daily_seed()) or int(daily.difficulty) != 0 or daily.strain_id != first or daily.biome_id != "verdant_maw":
		_fail("Daily config wrong: seed %s difficulty %s strain %s" % [daily.seed, daily.difficulty, daily.strain_id])
		return
	if menu.difficulty != 1:
		_fail("TAGES-BRUT must not change the chosen difficulty")
		return
	var seed_before_daily: int = menu.profile.next_seed
	menu.select_difficulty(0)
	menu.queue_free()
	await process_frame
	# Reward overlay after the daily run: rewards booked, daily record saved, own next map kept.
	session.pending_config = {}
	session.last_result = {"strain_id": first, "biome_id": "verdant_maw", "difficulty": 0, "seconds": 45.0,
		"peak_population": 180, "final_population": 0, "kills": 40, "kills_by_type": {"prey": 40},
		"biomass": 80.0, "lost": 60, "bosses": 0, "evolutions": [], "mutations": {}, "used_rally": true}
	menu = _spawn()
	await process_frame
	var today: String = profile_script.today_key()
	if not menu.reward.has("daily") or not menu.reward.daily.get("new_best", false):
		_fail("Daily run was not recognised in the reward: %s" % [menu.reward.keys()])
		return
	var day: Dictionary = menu.daily_today()
	if day.is_empty() or not is_equal_approx(float(day.seconds), 45.0) or int(day.peak) != 180 or int(day.runs) != 1:
		_fail("Daily record wrong: %s" % day)
		return
	if menu.profile.next_seed != seed_before_daily:
		_fail("A daily run must not reroll the own next map")
		return
	var reread: Variant = profile_script.load_or_create(TEST_PROFILE)
	if int(reread.daily_record(today).get("peak", 0)) != 180 or int(reread.records.runs) < 1:
		_fail("Daily record / run was not saved")
		return
	# A weaker daily run keeps the record and is not a new best.
	if reread.record_daily(today, 30.0, 50) or not is_equal_approx(float(reread.daily_record(today).seconds), 45.0):
		_fail("Weaker daily run must not replace the record")
		return
	menu.close_reward()
	menu.queue_free()
	await process_frame
	# Reward overlay after a normal run.
	session.pending_config = {}
	session.last_result = {"strain_id": first, "biome_id": "verdant_maw", "difficulty": 0, "seconds": 200.0,
		"peak_population": 64, "final_population": 0, "kills": 120,
		"kills_by_type": {"prey": 90, "hunter": 20, "skitter": 6, "leaper": 3, "boss": 1}, "biomass": 300.0,
		"lost": 80, "bosses": 1, "evolutions": [], "mutations": {"jaws": 2}, "used_rally": true}
	var essence_start: int = load("res://scripts/meta/profile.gd").load_or_create(TEST_PROFILE).essence
	menu = _spawn()
	await process_frame
	if menu.reward.is_empty():
		_fail("Reward overlay did not appear")
		return
	if not session.last_result.is_empty():
		_fail("last_result was not cleared")
		return
	if int(menu.reward.essence) <= 0 or menu.profile.essence != essence_start + int(menu.reward.essence):
		_fail("Run rewards were not credited")
		return
	if not menu.reward.new_quests.has("survive_1") or not menu.reward.new_quests.has("boss_1"):
		_fail("Expected new trophies survive_1 and boss_1, got %s" % [menu.reward.new_quests])
		return
	# Taps elsewhere must not leak through the overlay.
	menu.tap(menu.play_rect().get_center())
	if not session.pending_config.is_empty():
		_fail("Overlay must block SPIELEN")
		return
	menu.tap(menu.reward_button_rect().get_center())
	if not menu.reward.is_empty():
		_fail("WEITER did not close the overlay")
		return
	var saved: Variant = load("res://scripts/meta/profile.gd").load_or_create(TEST_PROFILE)
	if not saved.completed_quests.has("boss_1"):
		_fail("Run result was not saved")
		return
	if menu.reward.has("daily") or int(saved.daily_record(today).get("runs", 0)) != 1:
		_fail("A normal run must not count as a daily run")
		return
	menu.queue_free()
	_delete_test_profile()
	print("PASS: menu loads, strain switch/swipe/buy, difficulty/biome locks, upgrades, instinct, trophies, SPIELEN config, reward overlay, seed code/reroll, TAGES-BRUT + daily record, settings, pressed state, layout")
	quit(0)


## Main-view hit areas must not overlap and must stay on screen; arrows are slim.
func _check_layout(menu: Control) -> bool:
	var rects := {"prev": menu.strain_prev_rect(), "next": menu.strain_next_rect(), "play": menu.play_rect(),
		"seed_card": menu.seed_card_rect(), "daily": menu.daily_rect(), "gear": menu.settings_button_rect(),
		"biome0": menu.biome_rect(0), "biome1": menu.biome_rect(1), "diff0": menu.difficulty_rect(0),
		"diff1": menu.difficulty_rect(1), "diff2": menu.difficulty_rect(2), "tab0": menu.tab_rect(0)}
	var screen := Rect2(Vector2.ZERO, menu.size)
	var names := rects.keys()
	for i in names.size():
		if not screen.encloses(rects[names[i]]):
			_fail("%s leaves the screen: %s" % [names[i], rects[names[i]]])
			return false
		for k in range(i + 1, names.size()):
			if rects[names[i]].intersects(rects[names[k]]):
				_fail("%s overlaps %s" % [names[i], names[k]])
				return false
	if not menu.seed_card_rect().encloses(menu.seed_reroll_rect()):
		_fail("Reroll button must sit inside the seed card")
		return false
	if menu.strain_prev_rect().size.x > 90.0 or not screen.encloses(menu.reward_button_rect()):
		_fail("Arrow or reward button rect out of spec")
		return false
	return true


## Seed code: 6 readable characters, round-trips to next_seed, reroll changes and saves it.
func _check_seed(menu: Control) -> bool:
	var code: String = menu.next_seed_code()
	if code.length() != 6 or menu.seed_from_code(code) != int(menu.profile.next_seed):
		_fail("Seed code %s does not match next_seed %d" % [code, menu.profile.next_seed])
		return false
	if menu.seed_code(2147483647) != "ZIK0ZJ" or menu.seed_from_code("zik0zj") != 2147483647 or menu.seed_from_code("??") != 0:
		_fail("Seed code conversion is wrong: %s" % menu.seed_code(2147483647))
		return false
	var before: int = menu.profile.next_seed
	for attempt in 3:
		menu.tap(menu.seed_reroll_rect().get_center())
		if menu.profile.next_seed != before:
			break
	if menu.profile.next_seed == before or menu.next_seed_code() == menu.seed_code(before):
		_fail("NEU WÜRFELN did not change the map seed")
		return false
	var reloaded: Variant = load("res://scripts/meta/profile.gd").load_or_create(TEST_PROFILE)
	if reloaded.next_seed != menu.profile.next_seed:
		_fail("Rerolled seed was not saved")
		return false
	return true


## Gear opens the panel, rows toggle and save, taps outside close it; nothing leaks through.
func _check_settings(menu: Control) -> bool:
	if not menu.setting("sound") or not menu.setting("vibration") or menu.setting("colorblind"):
		_fail("Default settings must be sound on, vibration on, colorblind off")
		return false
	menu.tap(menu.settings_button_rect().get_center())
	if not menu.settings_open:
		_fail("Gear did not open the settings")
		return false
	# A tap on a row area toggles; the strain arrow lies outside the panel and closes it.
	for i in menu.SETTINGS.size():
		menu.tap(menu.settings_row_rect(i).get_center())
	menu.tap(menu.settings_row_rect(1).get_center())
	if menu.setting("sound") or not menu.setting("vibration") or not menu.setting("colorblind"):
		_fail("Setting rows did not toggle")
		return false
	var reloaded: Variant = load("res://scripts/meta/profile.gd").load_or_create(TEST_PROFILE)
	if reloaded.get_setting("sound") or not reloaded.get_setting("vibration") or not reloaded.get_setting("colorblind"):
		_fail("Settings were not saved: %s" % reloaded.settings)
		return false
	if not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")):
		_fail("Sound off must mute the master bus")
		return false
	var strain_before: String = menu.current_strain()
	menu.tap(menu.play_rect().get_center())
	if menu.settings_open or not session.pending_config.is_empty() or menu.current_strain() != strain_before:
		_fail("A tap outside the settings panel must only close it")
		return false
	menu.tap(menu.settings_button_rect().get_center())
	menu.tap(menu.settings_close_rect().get_center())
	if menu.settings_open:
		_fail("Settings close button failed")
		return false
	# Colorblind back off for the rest of the test; sound stays off (checked in the RunConfig).
	menu.toggle_setting("colorblind")
	return true


## Holding a button reports it as pressed; a drag cancels it.
func _check_pressed(menu: Control) -> bool:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = menu.daily_rect().get_center()
	menu._gui_input(press)
	if not menu.is_pressed(menu.daily_rect()) or menu.pressed_rect() != menu.daily_rect() or menu.is_pressed(menu.play_rect()):
		_fail("Pressed state for TAGES-BRUT not reported")
		return false
	var motion := InputEventMouseMotion.new()
	motion.position = press.position + Vector2(0, -120)
	menu._gui_input(motion)
	if menu.pressed_rect() != Rect2():
		_fail("Dragging must cancel the pressed state")
		return false
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = motion.position
	menu._gui_input(release)
	if not session.pending_config.is_empty():
		_fail("A cancelled press must not start a run")
		return false
	return true


func _spawn() -> Control:
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	menu.profile_path = TEST_PROFILE
	root.add_child(menu)
	return menu


func _drag(menu: Control, from: Vector2, delta: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	menu._gui_input(press)
	for i in 8:
		var motion := InputEventMouseMotion.new()
		motion.position = from + delta * float(i + 1) / 8.0
		menu._gui_input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = from + delta
	menu._gui_input(release)


func _delete_test_profile() -> void:
	if FileAccess.file_exists(TEST_PROFILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
