extends SceneTree

const PROFILE = preload("res://scripts/meta/profile.gd")
const DATA = preload("res://scripts/meta/meta_data.gd")
const SESSION = preload("res://scripts/meta/session.gd")
const TEST_PATH := "user://mawlings_profile_test.json"
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _initialize() -> void:
	call_deferred("_run")

func _stats(overrides: Dictionary) -> Dictionary:
	var stats := {
		"strain_id": "glutmaw", "biome_id": "verdant_maw", "difficulty": 0, "seconds": 30.0,
		"peak_population": 25, "final_population": 0, "kills": 0,
		"kills_by_type": {"prey": 0, "hunter": 0, "skitter": 0, "leaper": 0, "boss": 0},
		"biomass": 0.0, "lost": 25, "bosses": 0, "evolutions": [], "mutations": {}, "used_rally": true,
	}
	stats.merge(overrides, true)
	return stats

func _clean() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))

func _run() -> void:
	_clean()
	# Datenumfang
	check(DATA.STRAINS.size() == 6 and DATA.UPGRADES.size() == 8 and DATA.DIFFICULTIES.size() == 3, "Data sizes")
	check(DATA.QUESTS.size() >= 30, "At least 30 quests")
	var ids := {}
	for q in DATA.QUESTS:
		check(not ids.has(q.id), "Unique quest id %s" % q.id)
		ids[q.id] = true
	for id in DATA.STRAINS:
		var uq := String(DATA.STRAINS[id].unlock_quest)
		check(uq == "" or ids.has(uq), "Strain unlock quest exists: %s" % id)
	check(SESSION.pending_config.is_empty() and SESSION.last_result.is_empty(), "Session empty")

	# Neues Profil
	var p = PROFILE.load_or_create(TEST_PATH)
	check(p.essence == 0 and p.crowns == 0, "Fresh currencies")
	check(p.owned_strains.size() == 2 and p.owned_strains.has("glutmaw") and p.owned_strains.has("sporling"), "Two free strains")
	check(p.is_difficulty_unlocked(0) and not p.is_difficulty_unlocked(1) and not p.is_difficulty_unlocked(2), "Only Wild unlocked")

	# Config vollständig
	var config: Dictionary = p.build_run_config("glutmaw", "verdant_maw", 0)
	for key in ["strain_id", "biome_id", "difficulty", "start_population", "tint", "signature_attack", "mods",
			"enemy_hp", "enemy_damage", "pressure_doubling", "slots", "rerolls", "banishes", "skips", "pool"]:
		check(config.has(key), "Config key %s" % key)
	for key in ["damage", "armor", "speed", "harvest", "dna", "growth"]:
		check(config.mods.has(key), "Mods key %s" % key)
	check(config.start_population == 1 and config.tint is Color and config.signature_attack == "rudelbiss", "Glutmaw base")
	check(config.slots.attack == 2 and config.slots.trait == 3, "Base slots")
	check(is_equal_approx(config.pressure_doubling, float(DATA.DIFFICULTIES[0].pressure_doubling)) and is_equal_approx(config.enemy_hp, float(DATA.DIFFICULTIES[0].enemy_hp)), "Wild difficulty")
	for id in ["jaws", "brood", "glutton", "pack", "scatter", "armor", "rudelbiss", "sporenwolke"]:
		check(config.pool.has(id), "Start pool has %s" % id)
	check(not config.pool.has("saeurespucker") and not config.pool.has("stachelruecken"), "Locked forms not in pool")
	var spore: Dictionary = p.build_run_config("sporling", "verdant_maw", 0)
	check(spore.start_population == 1 and is_equal_approx(spore.mods.growth, 1.3) and is_equal_approx(spore.mods.damage, 0.85), "Sporling mods")

	# Gesperrte Auswahl fällt zurück
	var locked: Dictionary = p.build_run_config("knochenkiefer", "glutsumpf", 2)
	check(locked.strain_id == "glutmaw" and locked.biome_id == "verdant_maw" and locked.difficulty == 0, "Locked selections fall back")

	# Upgrades
	check(p.upgrade_cost("rending") == 40 and not p.buy_upgrade("rending"), "No money no upgrade")
	p.essence = 1000
	check(p.buy_upgrade("rending") and p.essence == 960 and p.upgrade_cost("rending") == 60, "Buy rending, cost rises")
	check(p.buy_upgrade("brood_size"), "Buy brood size")
	check(not p.buy_upgrade("attack_slot"), "Attack slot needs quest")
	check(p.upgrade_cost("instinct") == 500 and p.buy_upgrade("instinct") and p.upgrade_cost("instinct") == 550, "Instinct cost")
	p.essence = 0
	check(not p.buy_upgrade("chitin"), "Money runs out")
	p.upgrades["chitin"] = 10
	check(p.upgrade_cost("chitin") == -1 and not p.buy_upgrade("chitin"), "Max rank")
	config = p.build_run_config("glutmaw", "verdant_maw", 0)
	check(config.start_population == 2, "Brood size applied (+1 per rank, stage 09)")
	p.upgrades["brood_size"] = 10
	check(p.build_run_config("glutmaw", "verdant_maw", 0).start_population == 5 and p.upgrade_cost("brood_size") == -1, "Brood size stops at 4 ranks (start 5)")
	p.upgrades["brood_size"] = 1
	check(is_equal_approx(config.mods.damage, 1.05 * 1.01), "Rending + instinct damage")
	check(is_equal_approx(config.mods.armor, 0.3), "Meta armor capped at 0.3")

	# Quest einmalig
	var result: Dictionary = p.record_run(_stats({"seconds": 70.0}))
	check(result.new_quests.has("survive_1"), "First minute quest")
	var expected := int(70.0 * 0.4)
	check(result.run_essence == expected and result.essence == expected + 50, "Essence incl. quest reward")
	result = p.record_run(_stats({"seconds": 70.0}))
	check(not result.new_quests.has("survive_1") and result.essence == 28, "Quest rewarded once")
	result = p.record_run(_stats({"seconds": 1.0}))
	check(result.essence == 5, "Minimum essence")
	check(p.quest_progress("survive_3") == Vector2(70, 180), "Quest progress")
	check(p.quest_progress("survive_1") == Vector2(60, 60), "Completed progress")

	# Boss -> Königszähne, Stamm freischalten und kaufen
	check(not p.buy_strain("knochenkiefer"), "Cannot buy locked strain")
	var before: int = p.crowns
	result = p.record_run(_stats({"seconds": 200.0, "bosses": 2, "kills": 40, "biomass": 100.0,
		"kills_by_type": {"prey": 10, "hunter": 28, "skitter": 0, "leaper": 0, "boss": 2}}))
	check(result.run_crowns == 2 and result.new_quests.has("boss_1"), "Boss crowns and quest")
	check(result.unlocked.has("strain:knochenkiefer") and p.unlocked_strains.has("knochenkiefer"), "Strain unlocked")
	check(p.crowns == before + result.crowns, "Crowns credited")
	check(result.run_essence == int(100 * 0.5 + 200 * 0.4 + 40 + 2 * 40), "Essence formula")
	p.crowns = 2
	check(not p.buy_strain("knochenkiefer"), "Strain too expensive")
	p.crowns = 5
	check(p.buy_strain("knochenkiefer") and p.crowns == 2 and p.owned_strains.has("knochenkiefer"), "Strain bought")
	check(not p.buy_strain("knochenkiefer"), "No double purchase")
	var bone: Dictionary = p.build_run_config("knochenkiefer", "verdant_maw", 0)
	check(bone.strain_id == "knochenkiefer" and bone.signature_attack == "stachelruecken" and bone.pool.has("stachelruecken"), "Owned strain config")
	check(is_equal_approx(bone.mods.armor, 0.5) and is_equal_approx(bone.mods.speed, 0.85), "Strain + meta armor")

	# Schwierigkeit per Quest, Belohnungsfaktor
	result = p.record_run(_stats({"seconds": 320.0}))
	check(result.new_quests.has("survive_5") and p.is_difficulty_unlocked(1), "Brutal unlocked")
	var brutal: Dictionary = p.build_run_config("glutmaw", "verdant_maw", 1)
	check(brutal.difficulty == 1 and is_equal_approx(brutal.enemy_hp, float(DATA.DIFFICULTIES[1].enemy_hp)) and is_equal_approx(brutal.enemy_damage, float(DATA.DIFFICULTIES[1].enemy_damage)) and is_equal_approx(brutal.pressure_doubling, float(DATA.DIFFICULTIES[1].pressure_doubling)), "Brutal config")
	result = p.record_run(_stats({"seconds": 10.0, "difficulty": 1, "bosses": 1, "kills_by_type": {"boss": 1}}))
	check(result.run_crowns == 2 and result.run_essence == int((10 * 0.4 + 40) * 2.0), "Brutal rewards")
	check(not p.is_difficulty_unlocked(2), "Apex still locked")

	# Speichern / Laden
	p.save()
	var loaded = PROFILE.load_or_create(TEST_PATH)
	check(loaded.essence == p.essence and loaded.crowns == p.crowns, "Currencies round trip")
	check(loaded.upgrades == p.upgrades and loaded.instinct_level == 1, "Upgrades round trip")
	check(loaded.owned_strains.has("knochenkiefer") and loaded.completed_quests == p.completed_quests, "Strains/quests round trip")
	check(loaded.is_difficulty_unlocked(1) and is_equal_approx(loaded.records.best_seconds, 320.0), "Records round trip")
	check(loaded.records.best_peak is int and loaded.records.best_peak == 25, "Int records stay int")
	check(loaded.build_run_config("knochenkiefer", "verdant_maw", 1) == p.build_run_config("knochenkiefer", "verdant_maw", 1), "Config identical after load")
	var raw := FileAccess.get_file_as_string(TEST_PATH)
	check(JSON.parse_string(raw).get("version") == 1, "Versioned file")

	# Kaputte Datei
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("{ kaputt ::: ")
	file.close()
	var broken = PROFILE.load_or_create(TEST_PATH)
	check(broken.essence == 0 and broken.owned_strains.size() == 2, "Broken file yields fresh profile")
	file = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("{\"version\":1,\"essence\":\"viel\",\"records\":[1,2],\"owned_strains\":[\"glutmaw\",5,\"erfunden\"]}")
	file.close()
	var partial = PROFILE.load_or_create(TEST_PATH)
	check(partial.essence == 0 and partial.owned_strains.size() == 2 and partial.records.runs == 0, "Garbage fields ignored")
	_clean()
	var missing = PROFILE.load_or_create(TEST_PATH)
	check(missing.essence == 0 and not FileAccess.file_exists(TEST_PATH), "Missing file is not an error")

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
	else:
		print("PASS meta: data, config fields, upgrades, quests once, strain unlock+buy, difficulty lock, save/load, broken file")
		quit(0)
