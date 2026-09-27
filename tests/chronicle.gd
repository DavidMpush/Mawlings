extends SceneTree
## Chronik (Etappe 10): speichern/laden, 30er-Deckel, Bestwerte je Stamm und
## Schwierigkeit, Tages-Bestenliste (Top 10), kaputte/fremde Datei, Flutstufe,
## Seed-Code, Teilen-Karte schreibt ein 1080 x 1920-PNG in einen Testordner.

const TEST_PATH := "user://test_chronicle.json"
const SHARE_DIR := "user://test_shares/"

var Chronicle: Variant


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(60.0).timeout.connect(func() -> void: _fail("Chronicle test timed out"))
	if not ResourceLoader.exists("res://scripts/meta/chronicle.gd"):
		_fail("chronicle.gd missing")
		return
	Chronicle = load("res://scripts/meta/chronicle.gd")
	_clean()
	# Fresh chronicle: empty, not recovered.
	var c: Variant = Chronicle.load_or_create(TEST_PATH)
	if not c.runs.is_empty() or c.recovered or c.total_runs != 0:
		_fail("Fresh chronicle must be empty")
		return
	# Booking + reload keeps every field.
	var booked: Dictionary = c.record(_stats("glutmaw", 0, 200.0, 64, {"seed": 1234567, "flood_reached": true, "flood_seconds": 95.0, "mutations": {"jaws": 2, "pack": 1}}), {"date": "2026-09-20", "time": 1790000000})
	if not booked.new_best or booked.daily_rank != 0:
		_fail("First run must be a new best and no daily rank: %s" % booked)
		return
	var e: Dictionary = booked.entry
	if e.seed_code != "00QGLJ" or e.flood_stage != 3 or e.date != "2026-09-20" or int(e.mutations.jaws) != 2:
		_fail("Entry fields wrong: code %s flood %s date %s" % [e.seed_code, e.flood_stage, e.date])
		return
	if Chronicle.seed_code(1234567) != load("res://scripts/menu/menu.gd").seed_code(1234567):
		_fail("Chronicle seed code must match the menu seed code")
		return
	if not c.save():
		_fail("Chronicle did not save")
		return
	var r: Variant = Chronicle.load_or_create(TEST_PATH)
	if r.runs.size() != 1 or not is_equal_approx(float(r.runs[0].seconds), 200.0) or int(r.runs[0].peak_population) != 64 or r.runs[0].seed_code != "00QGLJ" or int(r.runs[0].flood_stage) != 3:
		_fail("Reloaded run differs: %s" % [r.runs])
		return
	if r.recovered:
		_fail("A valid file must not count as recovered")
		return
	# Cap: only the newest 30 runs stay, newest first; total keeps counting.
	for i in 40:
		r.record(_stats("sporling", 0, 10.0 + i, 20 + i), {"date": "2026-09-21", "time": 1790100000 + i})
	if r.runs.size() != Chronicle.KEEP_RUNS or not is_equal_approx(float(r.runs[0].seconds), 49.0) or r.total_runs != 41:
		_fail("Run cap/order wrong: %d runs, first %s, total %d" % [r.runs.size(), r.runs[0].seconds, r.total_runs])
		return
	r.save()
	var r2: Variant = Chronicle.load_or_create(TEST_PATH)
	if r2.runs.size() != 30 or r2.total_runs != 41:
		_fail("Cap not kept after reload")
		return
	# Bests per strain + difficulty.
	var b: Dictionary = r2.best("glutmaw", 0)
	if b.is_empty() or not is_equal_approx(float(b.seconds), 200.0) or int(b.peak) != 64 or int(b.runs) != 1 or int(b.flood_stage) != 3:
		_fail("Glutmaw/Wild best wrong: %s" % b)
		return
	var weaker: Dictionary = r2.record(_stats("glutmaw", 0, 150.0, 90), {"date": "2026-09-22"})
	b = r2.best("glutmaw", 0)
	if weaker.new_best or not is_equal_approx(float(b.seconds), 200.0) or int(b.peak) != 90 or int(b.runs) != 2:
		_fail("Weaker run must keep best time but raise peak: %s" % b)
		return
	var brutal: Dictionary = r2.record(_stats("glutmaw", 1, 100.0, 40), {"date": "2026-09-22"})
	if not brutal.new_best or r2.best("glutmaw", 1).is_empty() or not is_equal_approx(float(r2.best("glutmaw", 0).seconds), 200.0):
		_fail("Difficulties must keep separate bests")
		return
	var overall: Dictionary = r2.overall_best()
	if not is_equal_approx(float(overall.seconds), 200.0) or int(overall.peak) != 90 or int(overall.flood_stage) != 3:
		_fail("Overall best wrong: %s" % overall)
		return
	# Daily board: top 10 by time, then peak; rank reported; other days separate.
	var day := "2026-09-27"
	var ranks: Array = []
	for i in 12:
		var res: Dictionary = r2.record(_stats("glutmaw", 0, 30.0 + i * 5.0, 50 + i, {"daily": true}), {"daily": true, "daily_date": day, "date": day, "time": 1790500000 + i})
		ranks.append(res.daily_rank)
	var board: Array = r2.daily_board(day)
	if board.size() != Chronicle.DAILY_TOP or not is_equal_approx(float(board[0].seconds), 85.0) or not is_equal_approx(float(board[9].seconds), 40.0):
		_fail("Daily board wrong: %d entries, top %s" % [board.size(), board[0].seconds if not board.is_empty() else -1])
		return
	if int(ranks[-1]) != 1 or int(ranks[0]) != 1:
		_fail("Daily ranks wrong: %s" % [ranks])
		return
	var slow: Dictionary = r2.record(_stats("glutmaw", 0, 5.0, 10, {"daily": true}), {"daily": true, "daily_date": day, "date": day})
	if slow.daily_rank != 0 or r2.daily_board(day).size() != 10:
		_fail("A run outside the top 10 must get rank 0")
		return
	var tie: Dictionary = r2.record(_stats("sporling", 0, 85.0, 70, {"daily": true}), {"daily": true, "daily_date": day, "date": day, "time": 1790600000})
	if tie.daily_rank != 1 or String(r2.daily_board(day)[0].strain_id) != "sporling":
		_fail("Equal time with bigger peak must rank first: %s" % tie)
		return
	r2.record(_stats("glutmaw", 0, 60.0, 30, {"daily": true}), {"daily": true, "daily_date": "2026-09-26", "date": "2026-09-26"})
	if r2.daily_board("2026-09-26").size() != 1 or r2.daily_dates()[0] != day:
		_fail("Other days must keep their own board, newest first")
		return
	if not r2.daily_board("2026-09-20").is_empty():
		_fail("Normal runs must not enter a daily board")
		return
	# Only DAILY_DAYS dates are kept.
	for d in 35:
		var date := "2025-01-%02d" % (d % 28 + 1) if d < 28 else "2025-02-%02d" % (d - 27)
		r2.record(_stats("glutmaw", 0, 20.0, 5, {"daily": true}), {"daily": true, "daily_date": date, "date": date})
	if r2.daily.size() > Chronicle.DAILY_DAYS or r2.daily_board(day).is_empty():
		_fail("Daily days must be trimmed to %d, oldest first (%d)" % [Chronicle.DAILY_DAYS, r2.daily.size()])
		return
	r2.save()
	var r3: Variant = Chronicle.load_or_create(TEST_PATH)
	if r3.daily_board(day).size() != 10 or String(r3.daily_board(day)[0].strain_id) != "sporling":
		_fail("Daily board not kept after reload")
		return
	# Broken file: fresh chronicle, broken copy kept, no crash; foreign version too.
	for garbage in ["{not json", "[1, 2, 3]", "{\"version\": 99, \"runs\": []}", "{\"version\": 1, \"runs\": 5}"]:
		var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
		f.store_string(garbage)
		f.close()
		var broken: Variant = Chronicle.load_or_create(TEST_PATH)
		if not broken.recovered or not broken.runs.is_empty():
			_fail("Broken file '%s' must give an empty, recovered chronicle" % garbage)
			return
		if not FileAccess.file_exists(TEST_PATH + ".broken"):
			_fail("Broken file must be kept as .broken")
			return
		broken.record(_stats("glutmaw", 0, 12.0, 8))
		if not broken.save() or Chronicle.load_or_create(TEST_PATH).runs.size() != 1:
			_fail("Recovered chronicle must save again")
			return
	# Damaged single entries are skipped, the rest survives.
	var mixed := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	mixed.store_string(JSON.stringify({"version": 1, "runs": [{"seconds": 33.0, "strain_id": "glutmaw", "peak_population": "12"}, "junk", {"no_seconds": 1}], "bests": {"glutmaw|0": {"seconds": "x"}}, "daily": {"nope": [], "2026-09-27": [{"seconds": 9.0}, 7]}}))
	mixed.close()
	var m: Variant = Chronicle.load_or_create(TEST_PATH)
	if m.recovered or m.runs.size() != 1 or int(m.runs[0].peak_population) != 12 or m.daily_board("2026-09-27").size() != 1 or m.daily.has("nope"):
		_fail("Partly damaged file must keep the valid entries")
		return
	# Share card: renders (headless: CPU fallback) and writes a 1080 x 1920 PNG.
	var card: Node = load("res://scripts/ui/share_card.gd").new()
	root.add_child(card)
	var path: String = await card.render(r3.runs[0], SHARE_DIR, "test_card.png")
	if path == "" or not FileAccess.file_exists(path):
		_fail("Share card was not written")
		return
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.get_width() != 1080 or image.get_height() != 1920:
		_fail("Share card must be 1080 x 1920")
		return
	var data: Dictionary = card.last_data
	if data.code != r3.runs[0].seed_code or int(data.peak) != int(r3.runs[0].peak_population):
		_fail("Share card data wrong: %s" % data)
		return
	card.queue_free()
	_clean()
	print("PASS: chronicle save/load, 30-run cap, bests per strain/difficulty, daily top 10 + ranks + day trim, broken/foreign files, share card PNG")
	quit(0)


func _stats(strain: String, difficulty: int, seconds: float, peak: int, extra: Dictionary = {}) -> Dictionary:
	var s := {"strain_id": strain, "biome_id": "verdant_maw", "difficulty": difficulty, "seconds": seconds,
		"peak_population": peak, "final_population": 0, "kills": int(seconds), "kills_by_type": {"prey": int(seconds)},
		"biomass": seconds * 2.0, "lost": peak, "bosses": 0, "evolutions": [], "mutations": {}, "used_rally": true,
		"flood_reached": false, "flood_seconds": 0.0, "seed": 42}
	for k in extra:
		s[k] = extra[k]
	return s


func _clean() -> void:
	for p in [TEST_PATH, TEST_PATH + ".broken"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var dir := DirAccess.open(SHARE_DIR)
	if dir != null:
		for f in dir.get_files():
			dir.remove(f)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SHARE_DIR))


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
