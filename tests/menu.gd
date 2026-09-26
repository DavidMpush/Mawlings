extends SceneTree
## Brutstätte flow: loads without a profile, strain switching, purchases with and
## without enough currency, SPIELEN fills Session.pending_config, reward overlay.

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
	menu.queue_free()
	await process_frame
	# Reward overlay after a run.
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
	menu.queue_free()
	_delete_test_profile()
	print("PASS: menu loads, strain switch/swipe/buy, difficulty/biome locks, upgrades, instinct, trophies, SPIELEN config, reward overlay")
	quit(0)


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
