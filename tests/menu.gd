extends SceneTree
## Brutstätte flow: loads without a profile, strain switching, purchases with and
## without enough currency, SPIELEN fills Session.pending_config, reward overlay,
## fresh seed per start, TAGES-BRUT config and daily record, settings, pressed state.

const TEST_PROFILE := "user://test_menu_profile.json"
const TEST_CHRONICLE := "user://test_menu_chronicle.json"
const TEST_SHARES := "user://test_menu_shares/"
const CONFIG_KEYS := ["strain_id", "biome_id", "difficulty", "start_population", "tint", "signature_attack", "mods", "enemy_hp", "enemy_damage", "pressure_doubling", "slots", "rerolls", "banishes", "skips", "pool", "sealed", "cores_unlocked"]
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
	# Etappe 19: the Dürrschlund opens once the Moosschlund was defeated.
	menu.profile.records.total_moss = 1
	menu.tap(menu.biome_rect(1).get_center())
	if menu.biome_id != "duerrschlund":
		_fail("Dürrschlund must unlock after a Moosschlund victory")
		return
	menu.profile.records.total_moss = 0
	menu.select_biome("verdant_maw")
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
	menu.tap(menu.tab_rect(menu.TABS.find("instinct")).get_center())
	var essence_before: int = menu.profile.essence
	menu.tap(menu.instinct_buy_rect().get_center())
	if menu.profile.instinct_level != 1 or menu.profile.essence >= essence_before:
		_fail("Urinstinkt purchase failed")
		return
	# Trophies tab scrolls.
	menu.tap(menu.tab_rect(menu.TABS.find("trophies")).get_center())
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
	# Stage 15: no map code in the menu; every SPIELEN rolls a fresh random seed.
	var first_seed := int(config.get("seed", 0))
	if first_seed <= 0 or config.get("daily", false):
		_fail("SPIELEN must carry a random seed and no daily flag: %s" % config.get("seed"))
		return
	var seeds := [first_seed]
	for attempt in 3:
		session.pending_config = {}
		menu.tap(menu.play_rect().get_center())
		var again := int(session.pending_config.get("seed", 0))
		if again <= 0 or again in seeds:
			_fail("Every start needs a new seed: %s after %s" % [again, seeds])
			return
		seeds.append(again)
	if not (config.get("settings") is Dictionary) or float(config.settings.get("volume_master", 1.0)) != 0.0 or not is_equal_approx(float(config.settings.get("volume_music", 1.0)), 0.5):
		_fail("RunConfig must carry the saved settings (master 0, music 50 %%): %s" % config.get("settings"))
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
	if not await _check_share(menu):
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
	if not _check_chronicle(menu, today):
		return
	if not _check_codex(menu):
		return
	if not _check_seals(menu):
		return
	menu.queue_free()
	_delete_test_profile()
	print("PASS: menu loads, strain switch/swipe/buy, difficulty/biome locks, upgrades, instinct, trophies, SPIELEN config, reward overlay, fresh seed per start, TAGES-BRUT + daily record, settings, pressed state, layout incl. sheets/settings, UI style, chronicle booking/sheet, share card, strain ability, KODEX, SIEGEL")
	quit(0)


## Main-view hit areas must not overlap and must stay on screen; arrows are slim.
func _check_layout(menu: Control) -> bool:
	var rects := {"prev": menu.strain_prev_rect(), "next": menu.strain_next_rect(), "play": menu.play_rect(),
		"daily": menu.daily_rect(), "gear": menu.settings_button_rect(),
		"biome0": menu.biome_rect(0), "biome1": menu.biome_rect(1), "biome2": menu.biome_rect(2), "diff0": menu.difficulty_rect(0),
		"diff1": menu.difficulty_rect(1), "diff2": menu.difficulty_rect(2), "tab0": menu.tab_rect(0),
		"tab3": menu.tab_rect(3), "records": menu.records_rect()}
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
	if menu.has_method("seed_reroll_rect") or menu.has_method("next_seed_code"):
		_fail("The map code / reroll must be gone from the menu")
		return false
	if menu.strain_prev_rect().size.x > 110.0 or not screen.encloses(menu.reward_button_rect()):
		_fail("Arrow or reward button rect out of spec")
		return false
	# Stage 15: every main-view button is a full touch target; SPIELEN is the big one.
	for key in ["prev", "next", "gear", "daily", "tab0", "tab3"]:
		if rects[key].size.x < 96.0 or rects[key].size.y < 96.0:
			_fail("%s is smaller than the 96 px touch target: %s" % [key, rects[key]])
			return false
	if menu.play_rect().size.y < 120.0:
		_fail("SPIELEN below the touch target size")
		return false
	if not _check_sheet_layout(menu, screen):
		return false
	# Stage 10: share button beside WEITER, four tabs, chronicle segments are big enough to hit.
	if menu.share_button_rect().intersects(menu.reward_button_rect()) or not screen.encloses(menu.share_button_rect()) or menu.share_button_rect().size.y < 96.0:
		_fail("Share button overlaps WEITER or is too small")
		return false
	if not screen.encloses(menu.tab_rect(menu.TABS.size() - 1)) or menu.tab_rect(0).size.x < 96.0:
		_fail("All tabs must fit the dock")
		return false
	for i in menu.CHRONICLE_VIEWS.size():
		if menu.chronicle_segment_rect(i).size.y < 96.0 or menu.chronicle_segment_rect(i).size.x < 96.0:
			_fail("Chronicle segment %d is smaller than 96 px" % i)
			return false
	if menu.records_rect().size.y < 48.0:
		_fail("Record line hit area too small: %s" % menu.records_rect())
		return false
	return true


## Etappe 17d strain ability on the card and the KODEX sheet (open from TROPHÄEN,
## five category segments, silhouettes for unseen entries, run discovery saved).
func _check_codex(menu: Control) -> bool:
	if menu.codex == null:
		_fail("KODEX script missing")
		return false
	for id in menu.strain_ids:
		var a: Dictionary = menu.codex.strain_ability(id)
		if a.is_empty() or String(a.name) == "" or String(a.text) == "" or float(a.cooldown) <= 0.0:
			_fail("Strain %s has no ability for the card: %s" % [id, a])
			return false
	# The last run (mutations jaws, one Bog King) is already in the codex.
	for key in ["stat:bite", "boss:bog_king"]:
		if not menu.profile.codex_seen.has(key):
			_fail("Run discovery missing %s: %s" % [key, menu.profile.codex_seen])
			return false
	menu.open_tab("trophies")
	var button: Rect2 = menu.codex_button_rect()
	if button.size.x < 96.0 or button.size.y < 96.0 or button.intersects(menu.trophy_summary_rect()) or not menu.sheet_rect().encloses(button):
		_fail("KODEX button out of spec: %s" % button)
		return false
	menu.tap(button.get_center())
	if menu.tab != "codex":
		_fail("KODEX button did not open the codex (tab %s)" % menu.tab)
		return false
	var sheet: Rect2 = menu.sheet_rect()
	var cats: Array = menu.codex.CATEGORIES
	if cats.size() != 6 or not cats.has("cores"):
		_fail("KODEX needs six categories incl. KERNE: %s" % [cats])
		return false
	for i in cats.size():
		var seg: Rect2 = menu.codex_segment_rect(i)
		if seg.size.x < 96.0 or seg.size.y < 96.0 or not sheet.encloses(seg):
			_fail("KODEX segment %d out of spec: %s" % [i, seg])
			return false
		menu.tap(seg.get_center())
		if menu.codex_view != cats[i]:
			_fail("Segment %d did not select %s" % [i, cats[i]])
			return false
		var entries: Array = menu.codex_entries()
		if entries.is_empty():
			_fail("KODEX category %s is empty" % cats[i])
			return false
		var unseen := 0
		for e in entries:
			if String(e.name) == "" or String(e.icon) == "" or String(e.text) == "":
				_fail("KODEX entry incomplete: %s" % e)
				return false
			if not e.seen:
				unseen += 1
		if unseen == 0:
			_fail("KODEX %s must show silhouettes for unseen entries" % cats[i])
			return false
		if cats[i] == "stats" and not entries.filter(func(e: Dictionary) -> bool: return e.id == "bite")[0].seen:
			_fail("Biss must be discovered after the run")
			return false
	menu.select_codex_view("weapons")
	if menu._trophy_scroll_max() <= 0.0:
		_fail("KODEX weapon list must scroll (16 entries)")
		return false
	if menu.codex_list_rect().position.y < menu.codex_summary_rect().end.y or menu.codex_list_rect().end.y > sheet.end.y:
		_fail("KODEX list outside the sheet")
		return false
	# The dock's TROPHÄEN tab leads back; the close button closes.
	menu.tap(menu.tab_rect(menu.TABS.find("trophies")).get_center())
	if menu.tab != "trophies":
		_fail("TROPHÄEN tab must lead back from the codex")
		return false
	menu.open_codex("relics")
	menu.tap(menu.sheet_close_rect().get_center())
	if menu.tab != "":
		_fail("Close did not close the codex")
		return false
	# Relics / power-ups / evolutions from RunStats, saved with the profile.
	var fresh: Array = menu.profile.record_codex({"relics": {"blutzahn": 1}, "powerups_taken": ["rausch"], "evolutions": ["meute"], "worm_kills": 1, "apex_kills": 1})
	for key in ["relic:blutzahn", "powerup:rausch", "weapon:meute", "boss:sandwurm"]:
		if not fresh.has(key):
			_fail("record_codex missed %s: %s" % [key, fresh])
			return false
	if fresh.has("boss:moosschlund") or not menu.profile.record_codex({"relics": {"blutzahn": 2}}).is_empty():
		_fail("record_codex must count the worm as Sandwurm and not repeat entries")
		return false
	menu.profile.save()
	var reread: Variant = load("res://scripts/meta/profile.gd").load_or_create(TEST_PROFILE)
	if not reread.codex_seen.has("relic:blutzahn") or not reread.codex_seen.has("stat:bite"):
		_fail("codex_seen was not saved")
		return false
	return true


## Stage 31 B: SIEGEL sheet - tab, grouped grid of stats/weapons/relics, tap
## seals and unseals, limit 2 + Siegelring, start weapon and undiscovered
## entries refused, saved in the profile and carried in the RunConfig.
func _check_seals(menu: Control) -> bool:
	var profile_script: Variant = load("res://scripts/meta/profile.gd")
	var stats_script: Variant = load("res://scripts/progression/stats.gd")
	var arsenal: Variant = load("res://scripts/progression/arsenal.gd")
	menu.profile.sealed.clear()
	var tab_i: int = menu.TABS.find("seals")
	if tab_i != 1:
		_fail("SIEGEL tab must sit next to BRUTKAMMER: %s" % [menu.TABS])
		return false
	menu.tap(menu.tab_rect(tab_i).get_center())
	if menu.tab != "seals":
		_fail("SIEGEL tab did not open (tab %s)" % menu.tab)
		return false
	var entries: Array = menu.seal_entries()
	var counts := {"stats": 0, "weapons": 0, "relics": 0, "cores": 0}
	for e in entries:
		counts[e.group] += 1
		if arsenal.is_evolved(String(e.id)):
			_fail("Evolutions must not be sealable: %s" % e.id)
			return false
	if counts.stats != stats_script.STATS.size() or counts.weapons != arsenal.WEAPONS.size() or counts.relics != arsenal.RELICS.size() or counts.cores != menu.codex.CORES.ORDER.size():
		_fail("SIEGEL must list every stat, weapon, relic and core: %s" % counts)
		return false
	var area: Rect2 = menu.seal_list_rect()
	var sheet: Rect2 = menu.sheet_rect()
	if not sheet.encloses(area) or area.position.y < menu.seal_summary_rect().end.y or menu._trophy_scroll_max() <= 0.0:
		_fail("SIEGEL list must sit in the sheet and scroll: %s" % area)
		return false
	var tiles: Array = menu.seal_tile_rects()
	for i in tiles.size():
		var r: Rect2 = tiles[i]
		if r.size.x < 96.0 or r.size.y < 96.0:
			_fail("Seal tile %d below the touch target: %s" % [i, r])
			return false
		for k in range(i + 1, tiles.size()):
			if r.intersects(tiles[k]):
				_fail("Seal tiles %d and %d overlap" % [i, k])
				return false
	var bite: int = entries.map(func(e: Dictionary) -> String: return e.id).find("bite")
	var luck: int = entries.map(func(e: Dictionary) -> String: return e.id).find("luck")
	if bite < 0 or not entries[bite].seen or not area.encloses(tiles[bite]):
		_fail("Biss must be discovered and visible at the top of the grid")
		return false
	# Undiscovered: refused.
	menu.profile.codex_seen.erase("stat:luck")
	if luck < 0 or menu.toggle_seal("luck") or menu.profile.is_sealed("luck"):
		_fail("Undiscovered entries must not be sealable")
		return false
	# Tap seals and unseals; saved at once.
	menu.tap(tiles[bite].get_center())
	if not menu.profile.is_sealed("bite") or not profile_script.load_or_create(TEST_PROFILE).sealed.has("bite"):
		_fail("Tapping Biss must seal it and save")
		return false
	menu.tap(tiles[bite].get_center())
	if menu.profile.is_sealed("bite"):
		_fail("Tapping a sealed entry must unseal it")
		return false
	# Start weapon of the current strain: tagged and refused.
	var signature := String(menu.meta.STRAINS[menu.current_strain()].signature)
	var start: Array = entries.filter(func(e: Dictionary) -> bool: return e.start)
	if start.size() != 1 or start[0].id != signature:
		_fail("Exactly the start weapon %s must carry the START tag: %s" % [signature, start])
		return false
	menu.profile.codex_seen.append("weapon:" + signature)
	if menu.toggle_seal(signature) or menu.profile.is_sealed(signature):
		_fail("The start weapon must not be sealable")
		return false
	# Limit: 2 seals, then the Siegelring adds one per rank.
	for key in ["stat:crit", "relic:blutzahn", "stat:speed"]:
		if not menu.profile.codex_seen.has(key):
			menu.profile.codex_seen.append(key)
	if menu.profile.seal_limit() != 2 or not menu.toggle_seal("crit") or not menu.toggle_seal("blutzahn"):
		_fail("Two seals must be free at the start")
		return false
	if menu.toggle_seal("speed") or menu.profile.sealed.size() != 2:
		_fail("A third seal must be refused without the Siegelring")
		return false
	menu.profile.essence = 100000
	if not menu.profile.buy_upgrade("seal_ring") or menu.profile.seal_limit() != 3 or not menu.toggle_seal("speed"):
		_fail("Siegelring rank 1 must allow a third seal")
		return false
	# RunConfig: sealed ids, never the start weapon (even if stored), clamped.
	menu.profile.sealed.append(signature)
	var config: Dictionary = menu.profile.build_run_config(menu.current_strain(), "verdant_maw", 0)
	var sealed: Array = config.get("sealed", [])
	if sealed.has(signature) or not sealed.has("crit") or not sealed.has("blutzahn") or not sealed.has("speed"):
		_fail("RunConfig sealed wrong: %s" % [sealed])
		return false
	menu.profile.sealed.erase(signature)
	# Stage 33: group KERNE - unlocked cores are seen and sealable, locked ones refused.
	var cores: Array = menu.seal_entries().filter(func(e: Dictionary) -> bool: return e.group == "cores")
	var seen_cores: Array = cores.filter(func(e: Dictionary) -> bool: return e.seen)
	if seen_cores.size() != menu.profile.cores_unlocked.size() or seen_cores.size() == cores.size():
		_fail("KERNE: exactly the unlocked cores must be seen: %d of %d" % [seen_cores.size(), cores.size()])
		return false
	menu.toggle_seal("speed")
	var locked := String(cores.filter(func(e: Dictionary) -> bool: return not e.seen)[0].id)
	if menu.toggle_seal(locked) or menu.profile.is_sealed(locked):
		_fail("A locked core must not be sealable: %s" % locked)
		return false
	if not menu.toggle_seal(String(seen_cores[0].id)) or not menu.profile.build_run_config(menu.current_strain(), "verdant_maw", 0).sealed.has(String(seen_cores[0].id)):
		_fail("An unlocked core must be sealable and reach the RunConfig")
		return false
	menu.toggle_seal(String(seen_cores[0].id))
	menu.tap(menu.sheet_close_rect().get_center())
	if menu.tab != "":
		_fail("Close did not close the SIEGEL sheet")
		return false
	return true


## KARTE TEILEN in the reward overlay renders the card into the test folder.
func _check_share(menu: Control) -> bool:
	if menu.reward_entry.is_empty() or not menu.reward.has("chronicle"):
		_fail("Reward run was not booked into the chronicle")
		return false
	menu.last_share_path = ""
	menu.tap(menu.share_button_rect().get_center())
	for i in 120:
		await process_frame
		if not menu.is_sharing():
			break
	var path: String = menu.last_share_path
	if path == "" or not path.begins_with(TEST_SHARES) or not FileAccess.file_exists(path):
		_fail("Share card file missing: '%s'" % path)
		return false
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.get_size() != Vector2i(1080, 1920):
		_fail("Share card must be 1080 x 1920")
		return false
	if menu.reward.is_empty() or not menu.toast.begins_with("Gespeichert"):
		_fail("Sharing must keep the overlay open and toast the file: %s" % menu.toast)
		return false
	return true


## Stage 15 sheets: between header and tab dock, lists fit or scroll, buttons
## and settings rows are full touch targets.
func _check_sheet_layout(menu: Control, screen: Rect2) -> bool:
	var sheet: Rect2 = menu.sheet_rect()
	if sheet.intersects(menu.settings_button_rect()) or sheet.end.y > menu.tab_rect(0).position.y - 14.0:
		_fail("Sheet must sit between the header and the tab dock: %s" % sheet)
		return false
	for tab_i in menu.TABS.size():
		if sheet.intersects(menu.tab_rect(tab_i)):
			_fail("Sheet covers tab %d" % tab_i)
			return false
	var list: Rect2 = menu.upgrade_list_rect()
	for i in menu.meta.UPGRADE_ORDER.size():
		var buy: Rect2 = menu.upgrade_buy_rect(i)
		if buy.size.x < 96.0 or buy.size.y < 96.0 or not menu.upgrade_row_rect(i).encloses(buy):
			_fail("Upgrade buy button %d out of spec: %s" % [i, buy])
			return false
	var last: Rect2 = menu.upgrade_row_rect(menu.meta.UPGRADE_ORDER.size() - 1)
	var old_tab: String = menu.tab
	menu.tab = "upgrades"
	var scrolls: bool = menu._trophy_scroll_max() > 0.0
	menu.tab = old_tab
	if last.end.y > list.end.y and not scrolls:
		_fail("Brutkammer rows run past the list without scrolling")
		return false
	if menu.sheet_close_rect().size.x < 96.0 or menu.sheet_close_rect().size.y < 96.0:
		_fail("Sheet close button too small")
		return false
	var panel: Rect2 = menu.settings_panel_rect()
	if not screen.encloses(panel) or panel.intersects(menu.tab_rect(0)) or panel.intersects(menu.settings_button_rect()):
		_fail("Settings modal out of spec: %s" % panel)
		return false
	for k in menu.VOLUMES.size():
		var slider_row: Rect2 = menu.settings_volume_rect(k)
		if slider_row.size.y < 96.0 or not panel.encloses(slider_row) or not slider_row.encloses(menu.settings_slider_rect(k)) or slider_row.intersects(menu.settings_row_rect(0)):
			_fail("Volume row %d out of spec: %s" % [k, slider_row])
			return false
	for i in menu.SETTINGS.size():
		var row: Rect2 = menu.settings_row_rect(i)
		if row.size.y < 96.0 or not panel.encloses(row):
			_fail("Settings row %d out of spec: %s" % [i, row])
			return false
	for k in menu.UI_SKINS.size():
		var seg: Rect2 = menu.settings_skin_rect(k)
		if seg.size.y < 96.0 or seg.size.x < 96.0 or not panel.encloses(seg):
			_fail("UI style button %d out of spec: %s" % [k, seg])
			return false
	return true


## Map seeds: SPIELEN never repeats the previous seed; the code only stays as info.
func _check_seed(menu: Control) -> bool:
	var last := 0
	for i in 5:
		var value: int = menu.fresh_seed()
		if value <= 0 or value == last:
			_fail("fresh_seed repeated or invalid: %d" % value)
			return false
		last = value
	if menu.seed_code(2147483647) != "ZIK0ZJ":
		_fail("Seed code conversion is wrong: %s" % menu.seed_code(2147483647))
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
	# Volume sliders: a tap sets the value under the finger (5 % steps), a drag follows it.
	var audio: Script = load("res://scripts/audio_settings.gd")
	for k in menu.VOLUMES.size():
		if menu.volume(menu.VOLUMES[k][0]) != 1.0:
			_fail("Volume %s must default to 100 %%" % menu.VOLUMES[k][0])
			return false
	var track: Rect2 = menu.settings_slider_rect(0)
	menu.tap(Vector2(track.position.x - 20.0, menu.settings_volume_rect(0).get_center().y))
	track = menu.settings_slider_rect(2)
	menu.tap(Vector2(track.position.x + track.size.x * 0.76, track.get_center().y))
	track = menu.settings_slider_rect(1)
	_drag(menu, Vector2(track.end.x, track.get_center().y), Vector2(-track.size.x * 0.52, 0.0))
	if menu.volume("volume_master") != 0.0 or not is_equal_approx(menu.volume("volume_music"), 0.5) or not is_equal_approx(menu.volume("volume_sfx"), 0.75) or menu.setting("sound"):
		_fail("Volume sliders wrong: %s" % menu.profile.settings)
		return false
	if not audio.bus_muted("Master") or audio.bus_muted("Music") or not is_equal_approx(audio.bus_db("Music"), audio.to_db(0.5)) or not is_equal_approx(audio.bus_db("SFX"), audio.to_db(0.75)):
		_fail("Bus levels wrong: master muted %s, music %.1f dB, sfx %.1f dB" % [audio.bus_muted("Master"), audio.bus_db("Music"), audio.bus_db("SFX")])
		return false
	if not menu.settings_open:
		_fail("Slider taps must keep the settings open")
		return false
	# A tap on a switch row toggles.
	for i in menu.SETTINGS.size():
		menu.tap(menu.settings_row_rect(i).get_center())
	menu.tap(menu.settings_row_rect(0).get_center())
	if menu.setting("sound") or not menu.setting("vibration") or not menu.setting("colorblind"):
		_fail("Setting rows did not toggle")
		return false
	var reloaded: Variant = load("res://scripts/meta/profile.gd").load_or_create(TEST_PROFILE)
	if reloaded.get_setting("sound") or not reloaded.get_setting("vibration") or not reloaded.get_setting("colorblind") or not is_equal_approx(reloaded.get_volume("volume_music"), 0.5) or not is_equal_approx(reloaded.get_volume("volume_sfx"), 0.75):
		_fail("Settings were not saved: %s" % reloaded.settings)
		return false
	var strain_before: String = menu.current_strain()
	# The tall settings panel covers the main view; the tab dock lies outside it.
	if menu.settings_panel_rect().intersects(menu.tab_rect(0)):
		_fail("The tab dock must lie outside the settings panel for this check")
		return false
	menu.tap(menu.tab_rect(0).get_center())
	if menu.settings_open or menu.tab != "" or not session.pending_config.is_empty() or menu.current_strain() != strain_before:
		_fail("A tap outside the settings panel must only close it")
		return false
	menu.tap(menu.settings_button_rect().get_center())
	menu.tap(menu.settings_close_rect().get_center())
	if menu.settings_open:
		_fail("Settings close button failed")
		return false
	# Stage 15: UI style row switches the skin at once and saves it in the profile.
	var style: Script = load("res://scripts/ui/ui_style.gd")
	menu.tap(menu.settings_button_rect().get_center())
	menu.tap(menu.settings_skin_rect(1).get_center())
	var saved: Variant = load("res://scripts/meta/profile.gd").load_or_create(TEST_PROFILE)
	if menu.ui_skin() != "calm" or style.get("skin") != "calm" or not saved.get_setting("skin_calm") or not menu.settings_open:
		_fail("UI style RUHIG was not applied/saved: %s / %s" % [menu.ui_skin(), style.get("skin")])
		return false
	menu.tap(menu.settings_skin_rect(0).get_center())
	saved = load("res://scripts/meta/profile.gd").load_or_create(TEST_PROFILE)
	if menu.ui_skin() != "brawl" or style.get("skin") != "brawl" or saved.get_setting("skin_calm") or saved.get_setting("skin_organic"):
		_fail("UI style BRAWL was not restored")
		return false
	menu.close_settings()
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


## CHRONIK: both runs of this test were booked from Session.last_result; record
## line and fourth tab open the sheet, segments switch, a run row renders its card.
func _check_chronicle(menu: Control, today: String) -> bool:
	var chron: Variant = load("res://scripts/meta/chronicle.gd").load_or_create(TEST_CHRONICLE)
	if chron.runs.size() != 2 or chron.runs[1].get("daily") != true or chron.runs[0].get("daily") != false:
		_fail("Chronicle must hold the daily and the normal run: %s" % [chron.runs.size()])
		return false
	if chron.daily_board(today).size() != 1 or int(chron.runs[1].daily_rank) != 1 or chron.best(menu.current_strain(), 0).is_empty():
		_fail("Daily board / best not booked from last_result")
		return false
	menu.tap(menu.records_rect().get_center())
	if menu.tab != "chronicle" or menu.chronicle_view != "best":
		_fail("Tapping the record line must open CHRONIK / BESTWERTE")
		return false
	if menu.chronicle_rows().size() < 2 or menu.chronicle_rows()[0].kind != "total":
		_fail("Best view must show the total row and one strain")
		return false
	menu.tap(menu.chronicle_segment_rect(1).get_center())
	var rows: Array = menu.chronicle_rows()
	if menu.chronicle_view != "daily" or rows.size() < 2 or rows[1].kind != "rank":
		_fail("Daily segment must list today's rank")
		return false
	menu.tap(menu.sheet_close_rect().get_center())
	menu.tap(menu.tab_rect(menu.TABS.find("chronicle")).get_center())
	if menu.tab != "chronicle":
		_fail("CHRONIK tab did not open")
		return false
	menu.tap(menu.chronicle_segment_rect(0).get_center())
	rows = menu.chronicle_rows()
	if menu.chronicle_view != "runs" or rows.size() != 2 or rows[0].kind != "run" or float(rows[0].h) < 96.0:
		_fail("Runs segment must list both runs in rows >= 96 px")
		return false
	if menu._trophy_scroll_max() != 0.0:
		_fail("Two runs must not scroll")
		return false
	menu.last_share_path = ""
	menu.tap(menu.chronicle_row_rect(0).get_center())
	if menu.last_share_path == "" and not menu.is_sharing():
		_fail("Tapping a run row must render its share card")
		return false
	return true


func _spawn() -> Control:
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	menu.profile_path = TEST_PROFILE
	menu.chronicle_path = TEST_CHRONICLE
	menu.share_dir = TEST_SHARES
	menu.open_shares = false
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
	for p in [TEST_PROFILE, TEST_CHRONICLE]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var dir := DirAccess.open(TEST_SHARES)
	if dir != null:
		for f in dir.get_files():
			dir.remove(f)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SHARES))


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
