extends RefCounted
## Account-Profil: Essenz, Königszähne, Upgrades, Stämme, Trophäen, Records. JSON unter user://.

const DATA = preload("res://scripts/meta/meta_data.gd")
const SCRIPT_PATH := "res://scripts/meta/profile.gd"
const DEFAULT_PATH := "user://mawlings_profile.json"
const VERSION := 1
const SEED_MAX := 2147483647

var path := DEFAULT_PATH
var essence: int = 0
var crowns: int = 0
var upgrades: Dictionary = {}
var instinct_level: int = 0
var unlocked_strains: Array = []
var owned_strains: Array = []
var completed_quests: Array = []
var records: Dictionary = {}
var unlocked_difficulties: Array = [0]
var unlocked_upgrades: Array = []
var unlocked_mutations: Array = []
var bonus_rerolls: int = 0
var bonus_banishes: int = 0
var bonus_skips: int = 0
## Karten-Seed des nächsten Runs (≠ 0); wird gespeichert und nach jedem Run neu gewürfelt.
var next_seed: int = 1
## Tagesrekorde der TAGES-BRUT: "JJJJ-MM-TT" (UTC) -> {seconds, peak, runs}.
var daily_records: Dictionary = {}
## Einstellungen (Ton, Vibration, Farbenblind-Modus); fehlende Schlüssel = DEFAULT_SETTINGS.
var settings: Dictionary = {}
## Einstieg: IDs der bereits gezeigten Tipps (jeder Tipp einmal pro Profil).
var seen_tips: Array = []

const DEFAULT_SETTINGS := {"sound": true, "vibration": true, "colorblind": false, "music_v1": false, "skin_calm": false, "skin_organic": false}
## So viele Tage bleiben in daily_records erhalten (älteste fallen heraus).
const DAILY_KEEP := 30

func _init() -> void:
	_reset_defaults()

func _reset_defaults() -> void:
	essence = 0
	crowns = 0
	upgrades = {}
	for id in DATA.UPGRADE_ORDER:
		upgrades[id] = 0
	instinct_level = 0
	unlocked_strains = []
	owned_strains = []
	for id in DATA.STRAIN_ORDER:
		if String(DATA.STRAINS[id].unlock_quest) == "":
			unlocked_strains.append(id)
			owned_strains.append(id)
	completed_quests = []
	records = _default_records()
	unlocked_difficulties = [0]
	unlocked_upgrades = []
	unlocked_mutations = DATA.START_ATTACKS.duplicate()
	bonus_rerolls = 0
	bonus_banishes = 0
	bonus_skips = 0
	next_seed = random_seed()
	daily_records = {}
	settings = DEFAULT_SETTINGS.duplicate()
	seen_tips = []

static func _default_records() -> Dictionary:
	return {
		"runs": 0, "best_seconds": 0.0, "best_peak": 0, "best_no_rally_seconds": 0.0,
		"total_seconds": 0.0, "total_kills": 0, "total_prey": 0, "total_hunters": 0,
		"total_skitters": 0, "total_leapers": 0, "total_bosses": 0, "total_evolutions": 0,
		"total_biomass": 0.0, "total_lost": 0, "evolutions_seen": [],
		"diff_time": [0.0, 0.0, 0.0], "strain_time": {},
		# Etappe 10: Moosschlund kills, migrations, best seconds per biome in one run.
		"total_apex": 0, "total_migrations": 0, "biome_time": {},
		# Etappe 10 Teil 3: Aschenkröten-Siege (total_apex zählt beide Apex).
		"total_toads": 0,
		"total_worms": 0,
		# Moosschlund-Siege allein (Trophäe „Moosschlund bezwungen“).
		"total_moss": 0,
	}

# --- Laden / Speichern -------------------------------------------------------

static func load_or_create(profile_path := DEFAULT_PATH) -> RefCounted:
	var profile = load(SCRIPT_PATH).new()
	profile.path = profile_path
	if FileAccess.file_exists(profile_path):
		var text := FileAccess.get_file_as_string(profile_path)
		var json := JSON.new()
		if json.parse(text) == OK and json.data is Dictionary:
			profile._apply(json.data)
		else:
			push_warning("Profil beschädigt, neues Profil angelegt: %s" % profile_path)
	return profile

func save() -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Profil konnte nicht gespeichert werden: %s" % path)
		return
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()

func to_dict() -> Dictionary:
	return {
		"version": VERSION, "essence": essence, "crowns": crowns, "upgrades": upgrades,
		"instinct_level": instinct_level, "unlocked_strains": unlocked_strains,
		"owned_strains": owned_strains, "completed_quests": completed_quests, "records": records,
		"unlocked_difficulties": unlocked_difficulties, "unlocked_upgrades": unlocked_upgrades,
		"unlocked_mutations": unlocked_mutations, "bonus_rerolls": bonus_rerolls,
		"bonus_banishes": bonus_banishes, "bonus_skips": bonus_skips, "next_seed": next_seed,
		"daily_records": daily_records, "settings": settings, "seen_tips": seen_tips,
	}

func _apply(d: Dictionary) -> void:
	essence = maxi(0, _int(d.get("essence"), 0))
	crowns = maxi(0, _int(d.get("crowns"), 0))
	instinct_level = maxi(0, _int(d.get("instinct_level"), 0))
	bonus_rerolls = maxi(0, _int(d.get("bonus_rerolls"), 0))
	bonus_banishes = maxi(0, _int(d.get("bonus_banishes"), 0))
	bonus_skips = maxi(0, _int(d.get("bonus_skips"), 0))
	var saved_seed := _int(d.get("next_seed"), 0)
	if saved_seed > 0 and saved_seed <= SEED_MAX:
		next_seed = saved_seed
	var saved_settings: Variant = d.get("settings")
	if saved_settings is Dictionary:
		for key in DEFAULT_SETTINGS:
			if saved_settings.get(key) is bool:
				settings[key] = saved_settings[key]
	var saved_daily: Variant = d.get("daily_records")
	if saved_daily is Dictionary:
		for key in saved_daily:
			var entry: Variant = saved_daily[key]
			if key is String and entry is Dictionary:
				daily_records[key] = {
					"seconds": maxf(0.0, float(entry.get("seconds", 0.0)) if (entry.get("seconds") is float or entry.get("seconds") is int) else 0.0),
					"peak": maxi(0, _int(entry.get("peak"), 0)),
					"runs": maxi(0, _int(entry.get("runs"), 0)),
				}
		_trim_daily()
	var saved_upgrades: Variant = d.get("upgrades")
	if saved_upgrades is Dictionary:
		for id in DATA.UPGRADES:
			upgrades[id] = clampi(_int(saved_upgrades.get(id), 0), 0, int(DATA.UPGRADES[id].max))
	_merge_strings(unlocked_strains, d.get("unlocked_strains"), DATA.STRAINS.keys())
	_merge_strings(owned_strains, d.get("owned_strains"), DATA.STRAINS.keys())
	_merge_strings(completed_quests, d.get("completed_quests"), [])
	_merge_strings(unlocked_upgrades, d.get("unlocked_upgrades"), DATA.UPGRADES.keys())
	_merge_strings(unlocked_mutations, d.get("unlocked_mutations"), [])
	# Etappe 17: alte Anlagen-IDs (jaws, regeneration, …) auf die neuen Werte abbilden.
	var migrated: Array = []
	for id in unlocked_mutations:
		var mapped := DATA.migrate_id(String(id))
		if not migrated.has(mapped):
			migrated.append(mapped)
	unlocked_mutations = migrated
	# Neue Inhalts-Freischaltungen früher erfüllter Trophäen nachtragen (z. B. Relikte).
	for q in DATA.QUESTS:
		if not completed_quests.has(q.id):
			continue
		for token in q.reward.get("unlock", []):
			var parts := String(token).split(":", true, 1)
			if parts.size() == 2 and parts[0] in ["mutation", "weapon", "relic"]:
				var id := DATA.migrate_id(parts[1])
				if not unlocked_mutations.has(id):
					unlocked_mutations.append(id)
	_merge_strings(seen_tips, d.get("seen_tips"), [])
	var diffs: Variant = d.get("unlocked_difficulties")
	if diffs is Array:
		for value in diffs:
			var index := _int(value, -1)
			if index >= 0 and index < DATA.DIFFICULTIES.size() and not unlocked_difficulties.has(index):
				unlocked_difficulties.append(index)
	var saved_records: Variant = d.get("records")
	if saved_records is Dictionary:
		for key in records:
			if not saved_records.has(key):
				continue
			var value: Variant = saved_records[key]
			var current: Variant = records[key]
			match typeof(current):
				TYPE_INT:
					records[key] = maxi(0, _int(value, 0))
				TYPE_FLOAT:
					records[key] = maxf(0.0, float(value) if (value is float or value is int) else 0.0)
				TYPE_ARRAY:
					if value is Array:
						if key == "diff_time":
							for i in mini(3, value.size()):
								records.diff_time[i] = float(value[i]) if (value[i] is float or value[i] is int) else 0.0
						else:
							for item in value:
								if item is String and not records[key].has(item):
									records[key].append(item)
				TYPE_DICTIONARY:
					if value is Dictionary:
						for sub in value:
							if value[sub] is float or value[sub] is int:
								records[key][String(sub)] = float(value[sub])
		# Ältere Profile kennen nur total_apex (beide Apex) und total_toads.
		if not saved_records.has("total_moss"):
			records.total_moss = maxi(0, int(records.total_apex) - int(records.total_toads))

static func _int(value: Variant, fallback: int) -> int:
	if value is int or value is float:
		return int(value)
	return fallback

static func _merge_strings(target: Array, source: Variant, allowed: Array) -> void:
	if not source is Array:
		return
	for item in source:
		if item is String and (allowed.is_empty() or allowed.has(item)) and not target.has(item):
			target.append(item)

# --- Upgrades ----------------------------------------------------------------

func upgrade_rank(id: String) -> int:
	if id == DATA.INSTINCT_ID:
		return instinct_level
	return int(upgrades.get(id, 0))

func upgrade_max(id: String) -> int:
	if id == DATA.INSTINCT_ID:
		return -1
	return int(DATA.UPGRADES.get(id, {}).get("max", 0))

func upgrade_available(id: String) -> bool:
	if id == DATA.INSTINCT_ID:
		return true
	if not DATA.UPGRADES.has(id):
		return false
	var requires := String(DATA.UPGRADES[id].requires)
	return requires == "" or unlocked_upgrades.has(id) or completed_quests.has(requires)

## Kosten des nächsten Rangs; -1 bei unbekannter ID oder Maximalrang.
func upgrade_cost(id: String) -> int:
	if id == DATA.INSTINCT_ID:
		return int(DATA.INSTINCT.base) + int(DATA.INSTINCT.step) * instinct_level
	if not DATA.UPGRADES.has(id):
		return -1
	var info: Dictionary = DATA.UPGRADES[id]
	var rank := upgrade_rank(id)
	if rank >= int(info.max):
		return -1
	return int(round(float(info.base) * pow(float(info.growth), rank)))

func buy_upgrade(id: String) -> bool:
	var cost := upgrade_cost(id)
	if cost < 0 or not upgrade_available(id) or essence < cost:
		return false
	essence -= cost
	if id == DATA.INSTINCT_ID:
		instinct_level += 1
	else:
		upgrades[id] = upgrade_rank(id) + 1
	save()
	return true

# --- Stämme / Schwierigkeit / Biome --------------------------------------------

func strain_cost(id: String) -> int:
	if not DATA.STRAINS.has(id):
		return -1
	return int(DATA.STRAINS[id].price)

func buy_strain(id: String) -> bool:
	if not DATA.STRAINS.has(id) or owned_strains.has(id) or not unlocked_strains.has(id):
		return false
	var cost := strain_cost(id)
	if crowns < cost:
		return false
	crowns -= cost
	owned_strains.append(id)
	save()
	return true

func is_difficulty_unlocked(difficulty: int) -> bool:
	return unlocked_difficulties.has(difficulty)

func is_biome_unlocked(biome_id: String) -> bool:
	if not DATA.BIOMES.has(biome_id):
		return false
	var entry: Dictionary = DATA.BIOMES[biome_id]
	# Etappe 19: Biome mit unlock_stat öffnen sich über einen Rekord (Dürrschlund: Moosschlund besiegt).
	var stat := String(entry.get("unlock_stat", ""))
	if stat != "" and int(records.get(stat, 0)) > 0:
		return true
	return not bool(entry.locked)

# --- Karten-Seed ----------------------------------------------------------------

## Zufälliger Karten-Seed in 1..SEED_MAX (nie 0 = klassische Karte).
static func random_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(1, SEED_MAX)

## Seed der täglichen Herausforderung: deterministisch aus dem UTC-Datum
## (optional ein Datum {year, month, day} übergeben), nie 0.
static func daily_seed(date: Dictionary = {}) -> int:
	if date.is_empty():
		date = Time.get_date_dict_from_system(true)
	var n: int = int(date.year) * 10000 + int(date.month) * 100 + int(date.day)
	n = (n ^ 0x5DEECE66D) * 6364136223846793005
	n = n ^ (n >> 31)
	return posmod(n, SEED_MAX) + 1

func reroll_seed() -> void:
	next_seed = random_seed()

## Datumsschlüssel der Tages-Brut (UTC, wie daily_seed), z. B. "2026-09-26".
static func today_key(date: Dictionary = {}) -> String:
	if date.is_empty():
		date = Time.get_date_dict_from_system(true)
	return "%04d-%02d-%02d" % [int(date.year), int(date.month), int(date.day)]

# --- Tagesrekord / Einstellungen -------------------------------------------------

## Bucht einen Tageslauf; true, wenn Zeit oder Peak einen neuen Tagesrekord setzen.
func record_daily(date_key: String, seconds: float, peak: int) -> bool:
	var entry: Dictionary = daily_records.get(date_key, {"seconds": 0.0, "peak": 0, "runs": 0})
	var first: bool = int(entry.runs) == 0
	var better: bool = seconds > float(entry.seconds) or peak > int(entry.peak)
	entry.seconds = maxf(float(entry.seconds), maxf(0.0, seconds))
	entry.peak = maxi(int(entry.peak), maxi(0, peak))
	entry.runs = int(entry.runs) + 1
	daily_records[date_key] = entry
	_trim_daily()
	return first or better

## {seconds, peak, runs} des Tages oder {} ohne Lauf.
func daily_record(date_key: String) -> Dictionary:
	return daily_records.get(date_key, {})

func _trim_daily() -> void:
	var keys := daily_records.keys()
	keys.sort()
	while keys.size() > DAILY_KEEP:
		daily_records.erase(keys.pop_front())

func get_setting(key: String) -> bool:
	return bool(settings.get(key, DEFAULT_SETTINGS.get(key, false)))

func set_setting(key: String, value: bool) -> void:
	if DEFAULT_SETTINGS.has(key):
		settings[key] = value

# --- Einstieg (Tipps) -------------------------------------------------------------

func has_seen_tip(id: String) -> bool:
	return seen_tips.has(id)

## Merkt einen Tipp als gesehen und speichert sofort; false, wenn er schon bekannt war.
func mark_tip(id: String) -> bool:
	if id == "" or seen_tips.has(id):
		return false
	seen_tips.append(id)
	save()
	return true

## Erststart: noch kein Run gebucht und noch kein Tipp gesehen.
func is_first_start() -> bool:
	return int(records.get("runs", 0)) == 0 and seen_tips.is_empty()

# --- Run-Konfiguration ---------------------------------------------------------

## Gesperrte/unbekannte Auswahl fällt auf Glutmaw / Verdant Maw / Wild zurück.
## run_seed ≠ 0 erzwingt eine Karte (z. B. daily_seed()); sonst gilt next_seed.
func build_run_config(strain_id: String, biome_id: String, difficulty: int, run_seed: int = 0) -> Dictionary:
	if not owned_strains.has(strain_id) or not DATA.STRAINS.has(strain_id):
		strain_id = "glutmaw"
	if not is_biome_unlocked(biome_id):
		biome_id = "verdant_maw"
	if not is_difficulty_unlocked(difficulty):
		difficulty = 0
	var strain: Dictionary = DATA.STRAINS[strain_id]
	var base: Dictionary = strain.mods
	var diff: Dictionary = DATA.DIFFICULTIES[difficulty]
	var instinct := 1.0 + float(DATA.INSTINCT.bonus) * instinct_level
	var meta_armor := minf(DATA.META_ARMOR_CAP, 0.03 * upgrade_rank("chitin"))
	var mods := {
		"damage": float(base.damage) * (1.0 + 0.05 * upgrade_rank("rending")) * instinct,
		"armor": clampf(float(base.armor) + meta_armor, 0.0, DATA.ARMOR_CAP),
		"speed": float(base.speed) * (1.0 + 0.03 * upgrade_rank("sprinter")),
		"harvest": float(base.harvest) * (1.0 + 0.06 * upgrade_rank("digestion")) * instinct,
		"dna": float(base.dna) * (1.0 + 0.06 * upgrade_rank("geneflow")),
		"growth": float(base.growth),
		"rally_damage": float(strain.get("rally_damage", 1.0)),
		# Etappe 16: Witterung vergrößert den Magnetradius der Beute-Kristalle.
		"magnet": 1.0 + 0.08 * upgrade_rank("witterung"),
	}
	# Etappe 17: ein Pool mit Werten, Waffen und Relikten; evolution.gd teilt ihn auf.
	var pool: Array[String] = []
	for id in DATA.start_pool():
		pool.append(String(id))
	for id in unlocked_mutations:
		var mapped := DATA.migrate_id(String(id))
		if not pool.has(mapped):
			pool.append(mapped)
	var signature := String(strain.signature)
	if not pool.has(signature):
		pool.append(signature)
	return {
		"strain_id": strain_id, "biome_id": biome_id, "difficulty": difficulty,
		"start_population": mini(DATA.MAX_POPULATION, int(strain.start_population) + mini(upgrade_rank("brood_size"), int(DATA.UPGRADES.brood_size.max))),
		"tint": Color(String(strain.tint)),
		"signature_attack": signature,
		"mods": mods,
		"enemy_hp": float(diff.enemy_hp), "enemy_damage": float(diff.enemy_damage),
		"pressure_doubling": float(diff.pressure_doubling),
		"slots": {"attack": int(DATA.BASE_SLOTS.attack) + upgrade_rank("attack_slot"),
			"trait": int(DATA.BASE_SLOTS.trait)},
		# Etappe 17: "Mutationswurf" (ehemals Anlagenslot) = +1 Neu würfeln je Rang.
		"rerolls": DATA.BASE_REROLLS + bonus_rerolls + upgrade_rank("trait_slot"),
		"banishes": DATA.BASE_BANISHES + bonus_banishes,
		"skips": DATA.BASE_SKIPS + bonus_skips,
		"pool": pool,
		"seed": run_seed if run_seed != 0 else next_seed,
	}

# --- Run-Auswertung -------------------------------------------------------------

static func run_essence(stats: Dictionary) -> int:
	var difficulty := clampi(_int(stats.get("difficulty"), 0), 0, DATA.DIFFICULTIES.size() - 1)
	var raw := float(stats.get("biomass", 0.0)) * 0.5 + float(stats.get("seconds", 0.0)) * 0.4 \
		+ float(stats.get("kills", 0)) + float(stats.get("bosses", 0)) * 40.0
	return maxi(5, int(raw * float(DATA.DIFFICULTIES[difficulty].reward)))

static func run_crowns(stats: Dictionary) -> int:
	var difficulty := clampi(_int(stats.get("difficulty"), 0), 0, DATA.DIFFICULTIES.size() - 1)
	return maxi(0, _int(stats.get("bosses"), 0)) * int(DATA.DIFFICULTIES[difficulty].crowns)

## Rückgabe: {essence, crowns, new_quests, unlocked} (Gesamtgewinn inkl. Quest-Belohnungen)
## plus run_essence, run_crowns, quest_essence, quest_crowns zur Aufschlüsselung.
func record_run(stats: Dictionary) -> Dictionary:
	var gained_essence := run_essence(stats)
	var gained_crowns := run_crowns(stats)
	essence += gained_essence
	crowns += gained_crowns
	_update_records(stats)
	var new_quests: Array = []
	var unlocked: Array = []
	var quest_essence := 0
	var quest_crowns := 0
	for q in DATA.QUESTS:
		if completed_quests.has(q.id) or quest_value(q.stat) < float(q.target):
			continue
		completed_quests.append(q.id)
		new_quests.append(q.id)
		var reward: Dictionary = q.reward
		quest_essence += int(reward.get("essence", 0))
		quest_crowns += int(reward.get("crowns", 0))
		for token in reward.get("unlock", []):
			if _apply_unlock(String(token)):
				unlocked.append(String(token))
	essence += quest_essence
	crowns += quest_crowns
	reroll_seed()
	save()
	return {
		"essence": gained_essence + quest_essence, "crowns": gained_crowns + quest_crowns,
		"new_quests": new_quests, "unlocked": unlocked,
		"run_essence": gained_essence, "run_crowns": gained_crowns,
		"quest_essence": quest_essence, "quest_crowns": quest_crowns,
	}

func _apply_unlock(token: String) -> bool:
	var parts := token.split(":", true, 1)
	var arg := parts[1] if parts.size() > 1 else ""
	match parts[0]:
		"strain":
			if DATA.STRAINS.has(arg) and not unlocked_strains.has(arg):
				unlocked_strains.append(arg)
				return true
		"difficulty":
			var index := int(arg)
			if index >= 0 and index < DATA.DIFFICULTIES.size() and not unlocked_difficulties.has(index):
				unlocked_difficulties.append(index)
				return true
		"upgrade":
			if DATA.UPGRADES.has(arg) and not unlocked_upgrades.has(arg):
				unlocked_upgrades.append(arg)
				return true
		"mutation", "weapon", "relic":
			# Etappe 17: Werte, Waffen und Relikte teilen sich eine Freischaltliste.
			arg = DATA.migrate_id(arg)
			if arg != "" and not unlocked_mutations.has(arg):
				unlocked_mutations.append(arg)
				return true
		"reroll":
			bonus_rerolls += 1
			return true
		"banish":
			bonus_banishes += 1
			return true
		"skip":
			bonus_skips += 1
			return true
	# Known kinds that were already unlocked simply change nothing.
	if not parts[0] in ["strain", "difficulty", "upgrade", "mutation", "weapon", "relic"]:
		push_warning("Unbekannte Freischaltung: %s" % token)
	return false

func _update_records(stats: Dictionary) -> void:
	var seconds := maxf(0.0, float(stats.get("seconds", 0.0)))
	var kills_by_type: Dictionary = stats.get("kills_by_type", {}) if stats.get("kills_by_type") is Dictionary else {}
	var difficulty := clampi(_int(stats.get("difficulty"), 0), 0, DATA.DIFFICULTIES.size() - 1)
	records.runs += 1
	records.best_seconds = maxf(records.best_seconds, seconds)
	records.best_peak = maxi(records.best_peak, _int(stats.get("peak_population"), 0))
	if not bool(stats.get("used_rally", true)):
		records.best_no_rally_seconds = maxf(records.best_no_rally_seconds, seconds)
	records.total_seconds += seconds
	records.total_kills += maxi(0, _int(stats.get("kills"), 0))
	records.total_prey += maxi(0, _int(kills_by_type.get("prey"), 0))
	records.total_hunters += maxi(0, _int(kills_by_type.get("hunter"), 0))
	records.total_skitters += maxi(0, _int(kills_by_type.get("skitter"), 0))
	records.total_leapers += maxi(0, _int(kills_by_type.get("leaper"), 0))
	records.total_bosses += maxi(0, _int(stats.get("bosses"), _int(kills_by_type.get("boss"), 0)))
	records.total_biomass += maxf(0.0, float(stats.get("biomass", 0.0)))
	records.total_lost += maxi(0, _int(stats.get("lost"), 0))
	var evolutions: Variant = stats.get("evolutions", [])
	if evolutions is Array:
		records.total_evolutions += evolutions.size()
		for id in evolutions:
			if not records.evolutions_seen.has(String(id)):
				records.evolutions_seen.append(String(id))
	records.diff_time[difficulty] = maxf(float(records.diff_time[difficulty]), seconds)
	var strain_id := String(stats.get("strain_id", ""))
	if strain_id != "":
		records.strain_time[strain_id] = maxf(float(records.strain_time.get(strain_id, 0.0)), seconds)
	records.total_apex += maxi(0, _int(stats.get("apex_kills"), 0))
	var toad_kills := maxi(0, _int(stats.get("toad_kills"), 0))
	records.total_toads += toad_kills
	var worm_kills := maxi(0, _int(stats.get("worm_kills"), 0))
	records.total_worms += worm_kills
	# RunStats liefert apex_kills (beide Apex) und toad_kills; moss_kills optional.
	var moss_kills := _int(stats.get("moss_kills"), _int(stats.get("apex_kills"), 0) - toad_kills - worm_kills)
	records.total_moss += maxi(0, moss_kills)
	records.total_migrations += maxi(0, _int(stats.get("migrations"), 0))
	var biome_seconds: Variant = stats.get("biome_seconds", {})
	if biome_seconds is Dictionary:
		for id in biome_seconds:
			var value: Variant = biome_seconds[id]
			if value is float or value is int:
				records.biome_time[String(id)] = maxf(float(records.biome_time.get(String(id), 0.0)), float(value))

# --- Trophäen -------------------------------------------------------------------

func quest_value(stat: String) -> float:
	var parts := stat.split(":", true, 1)
	if parts.size() == 2:
		match parts[0]:
			"evo":
				return 1.0 if records.evolutions_seen.has(parts[1]) else 0.0
			"diff_time":
				var index := int(parts[1])
				return float(records.diff_time[index]) if index >= 0 and index < records.diff_time.size() else 0.0
			"strain_time":
				return float(records.strain_time.get(parts[1], 0.0))
			"biome_time":
				return float(records.biome_time.get(parts[1], 0.0))
		return 0.0
	return float(records.get(stat, 0))

func quest_progress(id: String) -> Vector2:
	var q: Dictionary = DATA.quest(id)
	if q.is_empty():
		return Vector2.ZERO
	var target := float(q.target)
	if completed_quests.has(id):
		return Vector2(target, target)
	return Vector2(minf(quest_value(q.stat), target), target)
