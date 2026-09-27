extends RefCounted
## Chronik (Etappe 10 „Teilen“): lokale Lauf-Historie, getrennt vom Profil.
##
## Speichert in `user://mawlings_chronicle.json`
## - die letzten KEEP_RUNS Runs (RunStats + Datum, Uhrzeit, Seed-Code, Stamm,
##   Schwierigkeit, Tagesflag, Flutstufe), neueste zuerst,
## - Bestwerte je Stamm + Schwierigkeit ("strain|difficulty"),
## - die lokale Tages-Bestenliste je Datum (Top DAILY_TOP der eigenen Versuche,
##   nach Zeit, dann Peak), höchstens DAILY_DAYS Tage.
## Die Datei ist versioniert. Eine kaputte oder fremde Datei wird beiseite gelegt
## (`<pfad>.broken`) und durch eine leere Chronik ersetzt – nie ein Absturz.

const SCRIPT_PATH := "res://scripts/meta/chronicle.gd"
const DEFAULT_PATH := "user://mawlings_chronicle.json"
const VERSION := 1
const KEEP_RUNS := 30
const DAILY_TOP := 10
const DAILY_DAYS := 30
## Muss zu Tuning.FLOOD_DOUBLING_SECONDS passen (Flutstufe k = Sekunden / 40 + 1).
const FLOOD_DOUBLING_SECONDS := 40.0
const TUNING_PATH := "res://scripts/tuning.gd"
const SEED_ALPHABET := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"

var path := DEFAULT_PATH
var runs: Array = []            # neueste zuerst
var bests: Dictionary = {}      # "strain|difficulty" -> {seconds, peak, kills, flood_stage, runs, date}
var daily: Dictionary = {}      # "YYYY-MM-DD" -> Array[{seconds, peak, kills, strain_id, flood_stage, time}]
var total_runs := 0             # alle je gebuchten Runs (nicht gedeckelt)
## true, wenn beim Laden eine beschädigte Datei ersetzt wurde.
var recovered := false
## Zählt jede Änderung (UI-Komponenten nutzen es als Repaint-Schlüssel).
var revision := 0


static func load_or_create(file_path: String = DEFAULT_PATH) -> RefCounted:
	var chronicle: RefCounted = load(SCRIPT_PATH).new()
	chronicle.path = file_path
	if not FileAccess.file_exists(file_path):
		return chronicle
	var text := FileAccess.get_file_as_string(file_path)
	var json := JSON.new()
	var ok: bool = json.parse(text) == OK and json.data is Dictionary and chronicle._apply(json.data)
	if not ok:
		push_warning("Chronik beschädigt, neue Chronik angelegt: %s" % file_path)
		var broken := ProjectSettings.globalize_path(file_path)
		DirAccess.remove_absolute(broken + ".broken")
		DirAccess.rename_absolute(broken, broken + ".broken")
		chronicle._reset()
		chronicle.recovered = true
	return chronicle


func save() -> bool:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Chronik konnte nicht gespeichert werden: %s" % path)
		return false
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	return true


func to_dict() -> Dictionary:
	return {"version": VERSION, "total_runs": total_runs, "runs": runs, "bests": bests, "daily": daily}


func _reset() -> void:
	runs = []
	bests = {}
	daily = {}
	total_runs = 0
	revision += 1


## Übernimmt gespeicherte Daten; false, wenn die Datei nicht zur Chronik passt.
func _apply(d: Dictionary) -> bool:
	var version: Variant = d.get("version")
	if not (version is float or version is int) or int(version) < 1 or int(version) > VERSION:
		return false
	if not (d.get("runs", []) is Array) or not (d.get("bests", {}) is Dictionary) or not (d.get("daily", {}) is Dictionary):
		return false
	_reset()
	for raw in d.get("runs", []):
		if raw is Dictionary and _is_number(raw.get("seconds")):
			runs.append(entry_from_stats(raw, raw))
		if runs.size() >= KEEP_RUNS:
			break
	var saved_bests: Dictionary = d.get("bests", {})
	for key in saved_bests:
		var b: Variant = saved_bests[key]
		if b is Dictionary and String(key).contains("|"):
			bests[String(key)] = _clean_best(b)
	var saved_daily: Dictionary = d.get("daily", {})
	for date in saved_daily:
		var list: Variant = saved_daily[date]
		if not (list is Array) or not _is_date(String(date)):
			continue
		var clean: Array = []
		for item in list:
			if item is Dictionary and _is_number(item.get("seconds")):
				clean.append(_daily_item(item))
		clean.sort_custom(_better)
		daily[String(date)] = clean.slice(0, DAILY_TOP)
	_trim_daily()
	total_runs = maxi(runs.size(), _int(d.get("total_runs"), runs.size()))
	return true

# ---------------------------------------------------------------- booking

## Bucht einen Run. `context` ergänzt/überschreibt: date, time, seed, daily,
## daily_date, strain_id, difficulty. Rückgabe: {entry, new_best, daily_rank}
## (daily_rank 1..DAILY_TOP, 0 = kein Tageslauf oder nicht in den Top 10).
func record(stats: Dictionary, context: Dictionary = {}) -> Dictionary:
	var merged := stats.duplicate(true)
	for key in context:
		merged[key] = context[key]
	var entry := entry_from_stats(merged, context)
	runs.push_front(entry)
	while runs.size() > KEEP_RUNS:
		runs.pop_back()
	total_runs += 1
	# Bestwert je Stamm und Schwierigkeit.
	var key := best_key(entry.strain_id, entry.difficulty)
	var best: Dictionary = bests.get(key, {"seconds": 0.0, "peak": 0, "kills": 0, "flood_stage": 0, "runs": 0, "date": ""})
	var new_best: bool = int(best.runs) == 0 or float(entry.seconds) > float(best.seconds)
	if float(entry.seconds) > float(best.seconds):
		best.seconds = entry.seconds
		best.date = entry.date
	best.peak = maxi(int(best.peak), int(entry.peak_population))
	best.kills = maxi(int(best.kills), int(entry.kills))
	best.flood_stage = maxi(int(best.flood_stage), int(entry.flood_stage))
	best.runs = int(best.runs) + 1
	bests[key] = best
	# Tages-Bestenliste.
	var rank := 0
	if entry.daily:
		var date: String = entry.daily_date if entry.daily_date != "" else entry.date
		var list: Array = daily.get(date, [])
		var item := _daily_item(entry)
		list.append(item)
		list.sort_custom(_better)
		rank = list.find(item) + 1
		if rank > DAILY_TOP:
			rank = 0
		daily[date] = list.slice(0, DAILY_TOP)
		_trim_daily()
	entry["daily_rank"] = rank
	revision += 1
	return {"entry": entry, "new_best": new_best, "daily_rank": rank}


## Normalisierter Chronik-Eintrag aus RunStats (unbekannte Felder fallen weg).
static func entry_from_stats(stats: Dictionary, context: Dictionary = {}) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var time := _int(context.get("time", stats.get("time")), now)
	var date := String(context.get("date", stats.get("date", "")))
	if not _is_date(date):
		date = Time.get_date_string_from_unix_time(time)
	var run_seed := maxi(0, _int(stats.get("seed"), 0))
	var kills_by_type := {}
	var raw_kills: Variant = stats.get("kills_by_type", {})
	if raw_kills is Dictionary:
		for k in raw_kills:
			kills_by_type[String(k)] = maxi(0, _int(raw_kills[k], 0))
	var mutations := {}
	var raw_mut: Variant = stats.get("mutations", {})
	if raw_mut is Dictionary:
		for k in raw_mut:
			var r := _int(raw_mut[k], 0)
			if r > 0:
				mutations[String(k)] = r
	var evolutions: Array = []
	var raw_evo: Variant = stats.get("evolutions", [])
	if raw_evo is Array:
		for e in raw_evo:
			evolutions.append(String(e))
	var is_daily := bool(stats.get("daily", false))
	var daily_date := String(stats.get("daily_date", ""))
	if is_daily and not _is_date(daily_date):
		daily_date = date
	var entry := {
		"date": date, "time": time,
		"strain_id": String(stats.get("strain_id", "")), "biome_id": String(stats.get("biome_id", "")),
		"difficulty": clampi(_int(stats.get("difficulty"), 0), 0, 9),
		"seconds": maxf(0.0, _float(stats.get("seconds"), 0.0)),
		"peak_population": maxi(0, _int(stats.get("peak_population"), 0)),
		"final_population": maxi(0, _int(stats.get("final_population"), 0)),
		"kills": maxi(0, _int(stats.get("kills"), 0)),
		"kills_by_type": kills_by_type,
		"biomass": maxf(0.0, _float(stats.get("biomass"), 0.0)),
		"lost": maxi(0, _int(stats.get("lost"), 0)),
		"bosses": maxi(0, _int(stats.get("bosses"), 0)),
		"evolutions": evolutions, "mutations": mutations,
		"used_rally": bool(stats.get("used_rally", false)),
		"nests": maxi(0, _int(stats.get("nests"), 0)),
		"totems": maxi(0, _int(stats.get("totems"), 0)),
		"flood_reached": bool(stats.get("flood_reached", false)),
		"flood_seconds": maxf(0.0, _float(stats.get("flood_seconds"), 0.0)),
		"horde_kills": maxi(0, _int(stats.get("horde_kills"), 0)),
		"seed": run_seed, "seed_code": seed_code(run_seed) if run_seed > 0 else "",
		"daily": is_daily, "daily_date": daily_date if is_daily else "",
		"daily_rank": maxi(0, _int(stats.get("daily_rank"), 0)),
	}
	entry["flood_stage"] = flood_stage(entry)
	return entry


## Flutstufe wie im HUD: 0 = Flut nicht erreicht, sonst floor(Sekunden / 40) + 1.
static func flood_stage(stats: Dictionary) -> int:
	if not bool(stats.get("flood_reached", false)):
		return 0
	var doubling := FLOOD_DOUBLING_SECONDS
	if ResourceLoader.exists(TUNING_PATH):
		var tuning: Variant = load(TUNING_PATH)
		if tuning != null and tuning.get("FLOOD_DOUBLING_SECONDS") != null:
			doubling = float(tuning.FLOOD_DOUBLING_SECONDS)
	return int(floor(maxf(0.0, _float(stats.get("flood_seconds"), 0.0)) / maxf(1.0, doubling))) + 1

# ---------------------------------------------------------------- queries

static func best_key(strain_id: String, difficulty: int) -> String:
	return "%s|%d" % [strain_id, difficulty]


## {seconds, peak, kills, flood_stage, runs, date} oder {}.
func best(strain_id: String, difficulty: int) -> Dictionary:
	return bests.get(best_key(strain_id, difficulty), {})


## Bester Eintrag über alle Stämme/Schwierigkeiten: {seconds, peak, kills, flood_stage, runs}.
func overall_best() -> Dictionary:
	var out := {"seconds": 0.0, "peak": 0, "kills": 0, "flood_stage": 0, "runs": total_runs}
	for key in bests:
		var b: Dictionary = bests[key]
		out.seconds = maxf(float(out.seconds), float(b.get("seconds", 0.0)))
		out.peak = maxi(int(out.peak), int(b.get("peak", 0)))
		out.kills = maxi(int(out.kills), int(b.get("kills", 0)))
		out.flood_stage = maxi(int(out.flood_stage), int(b.get("flood_stage", 0)))
	return out


## Top-Liste eines Tages (bester zuerst) oder [].
func daily_board(date: String) -> Array:
	return daily.get(date, [])


## Alle Tage mit Einträgen, neuester zuerst.
func daily_dates() -> Array:
	var keys := daily.keys()
	keys.sort()
	keys.reverse()
	return keys

# ---------------------------------------------------------------- helpers

static func seed_code(value: int) -> String:
	var n := maxi(0, value)
	var code := ""
	for i in 6:
		code = SEED_ALPHABET[n % 36] + code
		n = floori(n / 36.0)
	return code


static func _daily_item(source: Dictionary) -> Dictionary:
	return {
		"seconds": maxf(0.0, _float(source.get("seconds"), 0.0)),
		"peak": maxi(0, _int(source.get("peak", source.get("peak_population")), 0)),
		"kills": maxi(0, _int(source.get("kills"), 0)),
		"strain_id": String(source.get("strain_id", "")),
		"flood_stage": maxi(0, _int(source.get("flood_stage"), 0)),
		"time": _int(source.get("time"), 0),
	}


static func _clean_best(b: Dictionary) -> Dictionary:
	return {
		"seconds": maxf(0.0, _float(b.get("seconds"), 0.0)), "peak": maxi(0, _int(b.get("peak"), 0)),
		"kills": maxi(0, _int(b.get("kills"), 0)), "flood_stage": maxi(0, _int(b.get("flood_stage"), 0)),
		"runs": maxi(0, _int(b.get("runs"), 0)), "date": String(b.get("date", "")),
	}


## Sortierung der Tagesliste: längere Zeit zuerst, dann größerer Peak, dann früher.
static func _better(a: Dictionary, b: Dictionary) -> bool:
	if not is_equal_approx(float(a.seconds), float(b.seconds)):
		return float(a.seconds) > float(b.seconds)
	if int(a.peak) != int(b.peak):
		return int(a.peak) > int(b.peak)
	return int(a.time) < int(b.time)


func _trim_daily() -> void:
	var keys := daily.keys()
	keys.sort()
	while keys.size() > DAILY_DAYS:
		daily.erase(keys.pop_front())


static func _is_number(value: Variant) -> bool:
	return value is float or value is int


static func _is_date(value: String) -> bool:
	return value.length() == 10 and value[4] == "-" and value[7] == "-" and value.substr(0, 4).is_valid_int()


static func _int(value: Variant, fallback: int) -> int:
	if value is int:
		return value
	if value is float:
		return int(value)
	if value is String and String(value).is_valid_int():
		return int(value)
	return fallback


static func _float(value: Variant, fallback: float) -> float:
	if value is float or value is int:
		return float(value)
	if value is String and String(value).is_valid_float():
		return float(value)
	return fallback
