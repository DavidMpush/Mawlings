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
	check(DATA.STRAINS.size() == 6 and DATA.UPGRADES.size() == 9 and DATA.DIFFICULTIES.size() == 3, "Data sizes")
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
	check(config.slots.attack == 4 and config.slots.trait == 6 and config.slots.relic == 6, "Base slots (4 weapons, 6 stats, 6 relics)")
	check(is_equal_approx(config.pressure_doubling, float(DATA.DIFFICULTIES[0].pressure_doubling)) and is_equal_approx(config.enemy_hp, float(DATA.DIFFICULTIES[0].enemy_hp)), "Wild difficulty")
	# Etappe 17: ein Pool mit Werten, Waffen und Relikten.
	for id in ["bite", "crit", "brood", "rally", "evade", "armor", "luck", "rudelbiss", "sporenwolke", "klauenwirbel", "giftbiss", "schallbrueller", "hungerstein", "magnetkern"]:
		check(config.pool.has(id), "Start pool has %s" % id)
	for id in ["saeurespucker", "stachelruecken", "regen", "dornenhaut", "urmutter", "blutmond", "schlundherz", "jaws"]:
		check(not config.pool.has(id), "Locked or old id not in pool: %s" % id)
	check(DATA.migrate_token("mutation:graeber") == "weapon:graeber" and DATA.migrate_token("mutation:dornenhaut") == "relic:dornenhaut" and DATA.migrate_token("mutation:regeneration") == "mutation:regen", "Old unlock tokens migrate")
	check(DATA.unlock_label("weapon:giftbiss") == "Neue Waffe: Giftbiss" and DATA.unlock_label("relic:urmutter") == "Neues Relikt: Urmutter", "Weapon/relic unlock labels")
	for q in DATA.QUESTS:
		for token in q.reward.get("unlock", []):
			check(DATA.migrate_token(String(token)) == String(token), "Quest %s uses a current token (%s)" % [q.id, token])
	var spore: Dictionary = p.build_run_config("sporling", "verdant_maw", 0)
	check(spore.start_population == 1 and is_equal_approx(spore.mods.growth, 1.25) and is_equal_approx(spore.mods.damage, 0.85), "Sporling mods")

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
	check(is_equal_approx(bone.mods.armor, 0.5) and is_equal_approx(bone.mods.speed, 0.9), "Strain + meta armor")

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

	# Apex-Trophäen: nur Moosschlund-Siege zählen für „Moosschlund bezwungen“.
	_clean()
	var apex_profile = PROFILE.load_or_create(TEST_PATH)
	result = apex_profile.record_run(_stats({"seconds": 30.0, "apex_kills": 1, "toad_kills": 1}))
	check(apex_profile.records.total_apex == 1 and apex_profile.records.total_toads == 1 and apex_profile.records.total_moss == 0, "Toad kill is no Moosschlund kill")
	check(result.new_quests.has("apex_aschenkroete") and not result.new_quests.has("apex_moosschlund"), "Only the toad trophy after a toad kill")
	result = apex_profile.record_run(_stats({"seconds": 30.0, "apex_kills": 2, "toad_kills": 1}))
	check(apex_profile.records.total_moss == 1 and result.new_quests.has("apex_moosschlund"), "Moosschlund trophy after a Moosschlund kill")
	# Altes Profil ohne total_moss: total_apex - total_toads.
	file = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("{\"version\":1,\"records\":{\"total_apex\":5,\"total_toads\":2}}")
	file.close()
	var old_profile = PROFILE.load_or_create(TEST_PATH)
	check(old_profile.records.total_moss == 3 and old_profile.quest_value("total_moss") == 3.0, "Old profile migrates total_moss = apex - toads")
	file = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("{\"version\":1,\"records\":{\"total_apex\":1,\"total_toads\":3}}")
	file.close()
	check(PROFILE.load_or_create(TEST_PATH).records.total_moss == 0, "Migration never goes negative")
	# Etappe 17: alte Freischaltungen (Anlagen-IDs) werden migriert, Relikte aus früher
	# erfüllten Trophäen nachgetragen.
	file = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("{\"version\":1,\"unlocked_mutations\":[\"rudelbiss\",\"jaws\",\"regeneration\",\"graeber\",\"dornenhaut\"],\"completed_quests\":[\"boss_5\"],\"upgrades\":{\"trait_slot\":2}}")
	file.close()
	var legacy = PROFILE.load_or_create(TEST_PATH)
	for id in ["bite", "regen", "graeber", "dornenhaut", "urmutter"]:
		check(legacy.unlocked_mutations.has(id), "Legacy profile unlocks %s" % id)
	check(not legacy.unlocked_mutations.has("jaws") and not legacy.unlocked_mutations.has("regeneration"), "Old ids are gone after migration")
	var legacy_config: Dictionary = legacy.build_run_config("glutmaw", "verdant_maw", 0)
	check(legacy_config.pool.has("regen") and legacy_config.pool.has("graeber") and legacy_config.pool.has("urmutter"), "Migrated unlocks reach the pool")
	check(legacy_config.rerolls == DATA.BASE_REROLLS + 2, "Old Anlagenslot ranks become rerolls")
	check(legacy_config.slots.trait == 6 and legacy_config.slots.relic == 6, "An old profile gets the 6 stat / 6 relic slots")
	# Lautstärke-Regler: defaults 1,0, old "sound": false -> master 0, 5 % steps, saved as numbers.
	_clean()
	var fresh = PROFILE.load_or_create(TEST_PATH)
	check(fresh.get_volume("volume_master") == 1.0 and fresh.get_volume("volume_music") == 1.0 and fresh.get_volume("volume_sfx") == 1.0 and fresh.get_setting("sound"), "Volume defaults 100 %")
	file = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("{\"version\":1,\"settings\":{\"sound\":false,\"vibration\":false,\"volume_music\":0.43}}")
	file.close()
	var old_sound = PROFILE.load_or_create(TEST_PATH)
	check(old_sound.get_volume("volume_master") == 0.0 and not old_sound.get_setting("sound") and is_equal_approx(old_sound.get_volume("volume_music"), 0.45) and old_sound.get_volume("volume_sfx") == 1.0 and not old_sound.get_setting("vibration"), "Old sound switch migrates to master 0: %s" % old_sound.settings)
	old_sound.set_volume("volume_sfx", 0.62)
	old_sound.set_setting("sound", true)
	old_sound.save()
	var reread_volume = PROFILE.load_or_create(TEST_PATH)
	check(is_equal_approx(reread_volume.get_volume("volume_sfx"), 0.6) and reread_volume.get_volume("volume_master") == 1.0 and not reread_volume.settings.has("sound"), "Volumes saved as numbers: %s" % reread_volume.settings)
	_clean()
	var missing = PROFILE.load_or_create(TEST_PATH)
	check(missing.essence == 0 and not FileAccess.file_exists(TEST_PATH), "Missing file is not an error")

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
	else:
		print("PASS meta: data, config fields, upgrades, quests once, strain unlock+buy, difficulty lock, save/load, broken file, apex trophies + total_moss migration, stage 17 pools + unlock migration, volume sliders + sound migration")
		quit(0)
