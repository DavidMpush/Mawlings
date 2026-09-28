extends "res://scripts/menu/ui_kit.gd"
## Brutstätte: portrait main menu. Strain choice, biome, difficulty, SPIELEN,
## plus sheets for Brutkammer (upgrades), Trophäen and Urinstinkt, and the
## reward overlay after a run. Everything is drawn in `_draw()`; hit areas are
## exposed as `*_rect()` functions so tests can tap them.
##
## Meta scripts are loaded at runtime (see stages/03_progression.md contracts).

signal play_requested(config: Dictionary)

const PROFILE_PATH := "res://scripts/meta/profile.gd"
const SESSION_PATH := "res://scripts/meta/session.gd"
const META_DATA_PATH := "res://scripts/meta/meta_data.gd"
const CHRONICLE_PATH := "res://scripts/meta/chronicle.gd"
const SHARE_CARD_PATH := "res://scripts/ui/share_card.gd"
## KODEX (Sammlung): Blatt "codex", erreichbar über den KODEX-Knopf im TROPHÄEN-Blatt.
const CODEX_PATH := "res://scripts/meta/codex.gd"
## Chronik-Ansichten (Segmente oben im CHRONIK-Blatt).
const CHRONICLE_VIEWS := ["runs", "daily", "best"]
const CHRONICLE_VIEW_NAMES := {"runs": "LETZTE RUNS", "daily": "TAGES-BRUT", "best": "BESTWERTE"}
const GAME_SCENE := "res://scenes/main.tscn"

const TABS := ["upgrades", "trophies", "instinct", "chronicle"]
const TAB_NAMES := {"upgrades": "BRUTKAMMER", "trophies": "TROPHÄEN", "instinct": "URINSTINKT", "chronicle": "CHRONIK"}
const DIFFICULTY_COLORS := [Color("8fd46a"), Color("f2a04a"), Color("ff5a44")]
const UPGRADE_COLORS := {"brood_size": Color("68d8c7"), "rending": Color("f58a4d"), "chitin": Color("b8d879"), "sprinter": Color("7cc3f0"), "digestion": Color("f6cc70"), "witterung": Color("7fe6ff"), "geneflow": Color("6ee4d4"), "attack_slot": Color("ff8a3d"), "trait_slot": Color("b798ec")}
const UI_STYLE_PATH := "res://scripts/ui/ui_style.gd"
## Einstellungen im Panel: [Profil-Schlüssel, Titel, Erklärung].
const SETTINGS := [
	["sound", "TON", "Geräusche und Musik"],
	["vibration", "VIBRATION", "Kurzes Rütteln bei Treffern"],
	["colorblind", "FARBENBLIND-MODUS", "Warnflächen mit Mustern und Kontur"],
	["music_v1", "MUSIK: KLASSIK V1", "Aus: adaptive Musik · An: Musikpaket V1"],
	# Etappe 25: speech bubbles of the leader and the bosses.
	["speech", "SPRÜCHE", "Kommentare von Anführer und Bossen"],
]
## Seed-Code: 6 Zeichen Base36 decken 1..2^31-1 eindeutig ab (36^6 > 2^31).
## UI-Stil in den Einstellungen (Etappe 15): gespeichert als zwei Schalter im
## Profil (skin_calm, skin_organic); beide aus = brawl (Standard).
const UI_SKINS := ["brawl", "calm", "organic"]
const UI_SKIN_NAMES := {"brawl": "BRAWL", "calm": "RUHIG", "organic": "ORGANISCH"}
const SEED_ALPHABET := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const SEED_CODE_LENGTH := 6
const TAP_SLOP := 26.0
const SWIPE_DISTANCE := 90.0

## Remembered between menu visits within one process.
static var last_choice: Dictionary = {}
## Die zuletzt gestartete TAGES-BRUT ({date, seed, strain}); wird beim Auswerten des
## Run-Ergebnisses verbraucht, damit der Tagesrekord gebucht wird.
static var daily_pending: Dictionary = {}

## Tests may point this at a scratch file before the node enters the tree.
var profile_path := "user://mawlings_profile.json"
## Chronik-Datei (Tests setzen eine eigene) und Zielordner der Teilen-Karten.
const DEFAULT_PROFILE := "user://mawlings_profile.json"
const DEFAULT_CHRONICLE := "user://mawlings_chronicle.json"
var chronicle_path := DEFAULT_CHRONICLE
var share_dir := "user://shares/"
## Öffnet eine gespeicherte Karte auf dem Desktop im Bildbetrachter (nie headless,
## nie mobil, nie wenn change_scene_on_play aus ist wie in Tests).
var open_shares := true
## Tests set this to false so SPIELEN does not leave the menu scene.
var change_scene_on_play := true
## Erststart (Profil ohne Runs und ohne gesehene Tipps) überspringt das Menü.
var skip_menu_on_first_start := true

var profile: Variant = null
var meta: Variant = null
var session: Variant = null
var load_error := ""

var strain_ids: Array = []
var strain_index := 0
var biome_id := "verdant_maw"
var difficulty := 0
var tab := ""
var reward: Dictionary = {}
var reward_stats: Dictionary = {}
var trophy_scroll := 0.0
var toast := ""
var toast_time := 0.0
var settings_open := false
var chronicle: Variant = null
var chronicle_view := "runs"
## KODEX: Katalog-Skript (scripts/meta/codex.gd) und gewählte Kategorie.
var codex: Variant = null
var codex_view := "weapons"
## Chronik-Eintrag des gerade gezeigten Belohnungs-Runs (Grundlage der Teilen-Karte).
var reward_entry: Dictionary = {}
var last_share_path := ""
var _sharing := false

var _press_pos := Vector2.INF
var _drag_mode := ""
var _last_drag := Vector2.ZERO
var _slide := 0.0
var _decor: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_ensure_font()
	_build_decor()
	_load_meta()
	_consume_last_result()
	_add_components()
	_start_music()
	_start_sfx()
	queue_redraw()
	if skip_menu_on_first_start and change_scene_on_play:
		try_first_start()


# Stage 04 components draw the hub; this script keeps state and input.
const COMPONENTS := [
	["res://scripts/ui/menu/menu_main.gd", ["background", "logo", "resources", "strain", "biomes", "difficulties", "play", "tabs"]],
	["res://scripts/ui/menu/menu_sheets.gd", ["sheet", "reward", "toast", "settings"]],
	["res://scripts/ui/menu/menu_chronicle.gd", []],
	["res://scripts/ui/menu/menu_codex.gd", []],
]


func _add_components() -> void:
	for entry in COMPONENTS:
		if not ResourceLoader.exists(entry[0]):
			continue
		var component: Control = load(entry[0]).new()
		component.name = String(entry[0]).get_file().get_basename()
		add_child(component)
		for key in entry[1]:
			legacy[key] = false


func _process(delta: float) -> void:
	if toast_time > 0.0:
		toast_time = maxf(0.0, toast_time - delta)
	_slide = move_toward(_slide, 0.0, delta * maxf(900.0, absf(_slide) * 9.0))
	# Stage 07: the scripts/ui/menu components repaint themselves on change;
	# this node only draws per frame while a legacy block is still on.
	if legacy.values().has(true):
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

# ---------------------------------------------------------------- meta access

func _load_meta() -> void:
	if not ResourceLoader.exists(PROFILE_PATH) or not ResourceLoader.exists(META_DATA_PATH) or not ResourceLoader.exists(SESSION_PATH):
		load_error = "Meta-Daten fehlen"
		return
	meta = load(META_DATA_PATH)
	session = load(SESSION_PATH)
	var profile_script: Variant = load(PROFILE_PATH)
	profile = profile_script.load_or_create(profile_path)
	if profile == null:
		load_error = "Profil konnte nicht geladen werden"
		return
	strain_ids = Array(meta.STRAIN_ORDER)
	var wanted: String = last_choice.get("strain", "")
	strain_index = maxi(0, strain_ids.find(wanted))
	if wanted == "" or not _strain_owned(strain_ids[strain_index]):
		for i in strain_ids.size():
			if _strain_owned(strain_ids[i]):
				strain_index = i
				break
	biome_id = last_choice.get("biome", "verdant_maw")
	if not biome_unlocked(biome_id):
		biome_id = meta.BIOME_ORDER[0]
	difficulty = int(last_choice.get("difficulty", 0))
	if not _difficulty_unlocked(difficulty):
		difficulty = 0
	if ResourceLoader.exists(CHRONICLE_PATH):
		# A test/capture profile gets its own chronicle next to it, so automated
		# runs never write into the player's real chronicle.
		if chronicle_path == DEFAULT_CHRONICLE and profile_path != DEFAULT_PROFILE:
			chronicle_path = profile_path.get_basename() + "_chronicle.json"
		chronicle = load(CHRONICLE_PATH).load_or_create(chronicle_path)
	if ResourceLoader.exists(CODEX_PATH):
		codex = load(CODEX_PATH)
	_apply_settings()


func _consume_last_result() -> void:
	if profile == null or session == null:
		return
	var result: Dictionary = session.last_result
	if result.is_empty():
		return
	reward_stats = result.duplicate(true)
	var daily := _result_is_daily(reward_stats)
	reward = profile.record_run(reward_stats)
	if reward == null:
		reward = {}
	_book_chronicle(daily)
	if daily:
		var date: String = daily_pending.get("date", load(PROFILE_PATH).today_key())
		var seconds := float(reward_stats.get("seconds", 0.0))
		var peak := int(reward_stats.get("peak_population", 0))
		var best: bool = profile.record_daily(date, seconds, peak)
		reward["daily"] = {"date": date, "new_best": best, "record": profile.daily_record(date).duplicate()}
	daily_pending = {}
	reward["_shown"] = true
	session.last_result = {}
	profile.save()


## Bucht reward_stats zusätzlich in die Chronik (eigene Datei) und merkt sich den
## Eintrag für die Teilen-Karte.
func _book_chronicle(daily: bool) -> void:
	reward_entry = {}
	if chronicle == null:
		return
	var context := {"daily": daily, "date": load(PROFILE_PATH).today_key()}
	if daily:
		context["daily_date"] = String(daily_pending.get("date", reward_stats.get("daily_date", context.date)))
		if int(reward_stats.get("seed", 0)) <= 0 and int(daily_pending.get("seed", 0)) > 0:
			context["seed"] = int(daily_pending.seed)
	var booked: Dictionary = chronicle.record(reward_stats, context)
	chronicle.save()
	reward_entry = booked.entry
	reward["chronicle"] = {"new_best": booked.new_best, "daily_rank": booked.daily_rank}


## A result belongs to the daily brood when it says so, or when it matches the
## daily run the menu started last (Main/HuntWorld do not pass the flag on).
func _result_is_daily(result: Dictionary) -> bool:
	if result.has("daily"):
		return bool(result.daily)
	if daily_pending.is_empty():
		return false
	return String(result.get("strain_id", "")) == String(daily_pending.get("strain", "")) and int(result.get("difficulty", 0)) == 0


func current_strain() -> String:
	return "" if strain_ids.is_empty() else strain_ids[strain_index]


func _strain(id: String) -> Dictionary:
	return meta.STRAINS.get(id, {}) if meta != null else {}


func _strain_owned(id: String) -> bool:
	return profile != null and id in profile.owned_strains


func _strain_unlocked(id: String) -> bool:
	return profile != null and (id in profile.unlocked_strains or id in profile.owned_strains)


## Etappe 19: Biome können über einen Rekord freigeschaltet werden (Dürrschlund nach dem Moosschlund).
func biome_unlocked(id: String) -> bool:
	if not meta.BIOMES.has(id):
		return false
	if profile != null and profile.has_method("is_biome_unlocked"):
		return profile.is_biome_unlocked(id)
	return not bool(meta.BIOMES[id].get("locked", false))


func _difficulty_unlocked(index: int) -> bool:
	if profile == null or meta == null or index < 0 or index >= meta.DIFFICULTIES.size():
		return false
	if index == 0:
		return true
	if profile.has_method("is_difficulty_unlocked"):
		return profile.is_difficulty_unlocked(index)
	if "unlocked_difficulties" in profile:
		return index in profile.unlocked_difficulties
	var quest: String = meta.DIFFICULTIES[index].get("unlock_quest", "")
	return quest == "" or quest in profile.completed_quests


func _upgrade_available(id: String) -> bool:
	if profile.has_method("upgrade_available"):
		return profile.upgrade_available(id)
	var requires: String = meta.UPGRADES[id].get("requires", "")
	return requires == "" or requires in profile.completed_quests


func _upgrade_rank(id: String) -> int:
	return int(profile.upgrades.get(id, 0))


func _instinct_level() -> int:
	return int(profile.instinct_level)


func _instinct_cost() -> int:
	if profile.has_method("instinct_cost"):
		return profile.instinct_cost()
	return profile.upgrade_cost(meta.INSTINCT_ID)


func _quest_label(id: String) -> String:
	var quest: Dictionary = meta.quest(id)
	if quest.is_empty():
		return id
	return "%s: %s" % [quest.name, quest.description]


func _reward_text(quest: Dictionary) -> String:
	var parts: Array = []
	var r: Dictionary = quest.get("reward", {})
	if r.get("essence", 0) > 0:
		parts.append("+%d Essenz" % r.essence)
	if r.get("crowns", 0) > 0:
		parts.append("+%d %s" % [r.crowns, "Zahn" if r.crowns == 1 else "Zähne"])
	for token in r.get("unlock", []):
		parts.append(meta.unlock_label(token))
	return " · ".join(parts)

# ---------------------------------------------------------------- actions

func select_strain(offset: int) -> void:
	if strain_ids.is_empty():
		return
	strain_index = wrapi(strain_index + offset, 0, strain_ids.size())
	_slide = -signf(offset) * 260.0
	_remember()
	queue_redraw()


func select_difficulty(index: int) -> bool:
	if not _difficulty_unlocked(index):
		var quest: String = meta.DIFFICULTIES[index].get("unlock_quest", "")
		_toast("Gesperrt · %s" % _quest_label(quest))
		return false
	difficulty = index
	_remember()
	return true


func select_biome(id: String) -> bool:
	var biome: Dictionary = meta.BIOMES.get(id, {})
	if biome.is_empty() or not biome_unlocked(id):
		var hint := String(biome.get("unlock_hint", biome.get("status", "")))
		_toast("%s · %s" % [biome.get("name", id), hint if hint != "" else "kommt bald"])
		return false
	biome_id = id
	_remember()
	return true


func buy_current_strain() -> bool:
	var id := current_strain()
	if _strain_owned(id) or not _strain_unlocked(id):
		return false
	if profile.buy_strain(id):
		profile.save()
		_toast("%s gehört jetzt zur Brut" % _strain(id).get("name", id))
		return true
	_toast("Nicht genug Königszähne")
	return false


func buy_upgrade(id: String) -> bool:
	if id != meta.INSTINCT_ID and not _upgrade_available(id):
		_toast("Noch gesperrt")
		return false
	var ok: bool = profile.buy_upgrade(id)
	if ok:
		profile.save()
		_toast("Gekauft")
	else:
		_toast("Nicht genug Essenz" if id == meta.INSTINCT_ID or _upgrade_rank(id) < int(meta.UPGRADES[id].max) else "Maximal ausgebaut")
	return ok


func buy_instinct() -> bool:
	if profile.has_method("buy_instinct"):
		var ok: bool = profile.buy_instinct()
		if ok:
			profile.save()
			_toast("Urinstinkt gestärkt")
		else:
			_toast("Nicht genug Essenz")
		return ok
	return buy_upgrade(meta.INSTINCT_ID)


func can_play() -> bool:
	return profile != null and _strain_owned(current_strain()) and _difficulty_unlocked(difficulty)


func play() -> Dictionary:
	if not can_play():
		_toast("Diesen Stamm besitzt du noch nicht")
		return {}
	var config: Dictionary = profile.build_run_config(current_strain(), biome_id, difficulty, fresh_seed())
	daily_pending = {}
	_remember()
	return _start(config)


## Stage 15: no map code in the menu any more. Every SPIELEN rolls a new random
## map seed, never the one of the previous start. The seed still travels in the
## RunConfig and ends up in the chronicle and on the share card.
static var last_run_seed := 0


func fresh_seed() -> int:
	var profile_script: Variant = load(PROFILE_PATH)
	var value: int = profile_script.random_seed()
	while value == last_run_seed:
		value = profile_script.random_seed()
	last_run_seed = value
	return value


## TAGES-BRUT: same map for everyone today (Profile.daily_seed), always Wild,
## first biome, the selected strain. Rewards are booked like any run.
func can_play_daily() -> bool:
	return profile != null and _strain_owned(current_strain())


func play_daily() -> Dictionary:
	if not can_play_daily():
		_toast("Diesen Stamm besitzt du noch nicht")
		return {}
	var profile_script: Variant = load(PROFILE_PATH)
	var day_seed: int = profile_script.daily_seed()
	var config: Dictionary = profile.build_run_config(current_strain(), meta.BIOME_ORDER[0], 0, day_seed)
	config["daily"] = true
	config["daily_date"] = profile_script.today_key()
	daily_pending = {"date": config.daily_date, "seed": day_seed, "strain": config.strain_id}
	_remember()
	return _start(config)


## Erststart-Weiche: ohne gebuchten Run und ohne gesehenen Tipp geht es direkt in
## einen Run (Glutmaw, erstes Biom, Wild, Profil-Seed) – wie SPIELEN. Sonst {}.
func try_first_start() -> Dictionary:
	if profile == null or meta == null or not profile.has_method("is_first_start") or not profile.is_first_start():
		return {}
	var config: Dictionary = profile.build_run_config("glutmaw", meta.BIOME_ORDER[0], 0)
	config["first_start"] = true
	daily_pending = {}
	visible = false
	return _start(config)


func _start(config: Dictionary) -> Dictionary:
	config["settings"] = profile.settings.duplicate()
	# Main creates the onboarding (tips) only for runs that carry a profile path.
	config["profile_path"] = profile_path
	session.pending_config = config
	play_requested.emit(config)
	if change_scene_on_play and is_inside_tree():
		get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
	return config


## Today's daily record {seconds, peak, runs} or {}.
func daily_today() -> Dictionary:
	if profile == null:
		return {}
	return profile.daily_record(load(PROFILE_PATH).today_key())

# ---------------------------------------------------------------- map seed

## Base36 code of a seed (6 characters). Only shown as information (chronicle
## daily header, share card); the menu has no code input any more.
static func seed_code(value: int) -> String:
	var n := maxi(0, value)
	var code := ""
	for i in SEED_CODE_LENGTH:
		code = SEED_ALPHABET[n % 36] + code
		n = floori(n / 36.0)
	return code

# ---------------------------------------------------------------- settings

func open_settings() -> void:
	settings_open = true
	queue_redraw()


func close_settings() -> void:
	settings_open = false
	queue_redraw()


func setting(key: String) -> bool:
	return profile != null and profile.get_setting(key)


func toggle_setting(key: String) -> void:
	if profile == null:
		return
	profile.set_setting(key, not profile.get_setting(key))
	profile.save()
	_apply_settings()
	queue_redraw()


## Etappe 24: every tip of the run shows again once (profile.seen_tips cleared).
func reset_tips() -> void:
	if profile == null or not profile.has_method("reset_tips"):
		return
	profile.reset_tips()
	_toast("Tipps werden wieder gezeigt")
	queue_redraw()


## Saved UI style: "brawl" (default), "calm" or "organic".
func ui_skin() -> String:
	if profile == null:
		return "brawl"
	if profile.get_setting("skin_organic"):
		return "organic"
	if profile.get_setting("skin_calm"):
		return "calm"
	return "brawl"


func set_ui_skin(id: String) -> void:
	if profile == null or not id in UI_SKINS:
		return
	profile.set_setting("skin_calm", id == "calm")
	profile.set_setting("skin_organic", id == "organic")
	profile.save()
	_apply_settings()
	if ResourceLoader.exists(UI_STYLE_PATH):
		var style: Script = load(UI_STYLE_PATH)
		if style.has_method("set_skin"):
			style.call("set_skin", id)
	queue_redraw()


## Pushes the stored settings to engine-wide places: master bus mute and
## UiStyle.colorblind (when the style script has that flag). The game's Sfx
## node and HUD read the same profile values.
func _apply_settings() -> void:
	if profile == null:
		return
	var music := get_node_or_null("Music")
	if music != null:
		music.set_enabled(profile.get_setting("sound"))
		if music.has_method("set_style"):
			music.set_style("v1" if profile.get_setting("music_v1") else "classic")
	var sfx := get_node_or_null("Sfx")
	if sfx != null:
		sfx.set("sfx_enabled", profile.get_setting("sound"))
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_mute(bus, not profile.get_setting("sound"))
	if ResourceLoader.exists(UI_STYLE_PATH):
		var style: Script = load(UI_STYLE_PATH)
		if style.get("colorblind") != null:
			style.set("colorblind", profile.get_setting("colorblind"))
		# Only a saved non-default style is pushed on load, so tools that pick a
		# skin before opening the menu keep theirs; choosing BRAWL applies directly.
		var saved := ui_skin()
		if saved != "brawl" and style.has_method("set_skin"):
			style.call("set_skin", saved)


## The big button plays an owned strain, buys an unlocked one, or explains the lock.
func _press_main_button() -> void:
	var id := current_strain()
	if _strain_owned(id):
		play()
	elif _strain_unlocked(id):
		buy_current_strain()
	else:
		_toast("Gesperrt · %s" % _quest_label(_strain(id).get("unlock_quest", "")))


func open_tab(id: String) -> void:
	tab = "" if tab == id else id
	trophy_scroll = 0.0
	queue_redraw()


func close_reward() -> void:
	reward = {}
	reward_stats = {}
	reward_entry = {}
	queue_redraw()


func open_chronicle(view: String = "runs") -> void:
	tab = "chronicle"
	chronicle_view = view if view in CHRONICLE_VIEWS else "runs"
	trophy_scroll = 0.0
	queue_redraw()


## KODEX-Blatt öffnen (vom TROPHÄEN-Blatt aus); `view` = Kategorie.
func open_codex(view: String = "") -> void:
	if codex == null:
		return
	tab = "codex"
	if view in codex.CATEGORIES:
		codex_view = view
	trophy_scroll = 0.0
	queue_redraw()


func select_codex_view(view: String) -> void:
	if codex != null and view in codex.CATEGORIES and view != codex_view:
		codex_view = view
		trophy_scroll = 0.0
		queue_redraw()


func select_chronicle_view(view: String) -> void:
	if view in CHRONICLE_VIEWS and view != chronicle_view:
		chronicle_view = view
		trophy_scroll = 0.0
		queue_redraw()

# ---------------------------------------------------------------- share card

## Rendert die Teilen-Karte des Belohnungs-Runs; Pfad oder "".
func share_reward() -> String:
	if reward_stats.is_empty() and reward_entry.is_empty():
		return ""
	var source: Dictionary = reward_entry if not reward_entry.is_empty() else reward_stats
	return await share_run(source)


## Rendert die Teilen-Karte eines Runs (RunStats oder Chronik-Eintrag).
func share_run(stats: Dictionary) -> String:
	if _sharing or stats.is_empty() or not ResourceLoader.exists(SHARE_CARD_PATH):
		return ""
	_sharing = true
	_toast("Karte wird gezeichnet …")
	var card: Node = load(SHARE_CARD_PATH).new()
	card.name = "ShareCard"
	add_child(card)
	var path: String = await card.render(stats, share_dir)
	card.queue_free()
	_sharing = false
	if path == "":
		_toast("Karte konnte nicht gespeichert werden")
		return ""
	last_share_path = path
	# Echtes System-Teilen kommt mit dem Android-Export (Share-Intent-Plugin);
	# bis dahin: Datei speichern und auf dem Desktop im Bildbetrachter öffnen.
	_toast("Gespeichert: %s" % path.get_file())
	if open_shares and change_scene_on_play and DisplayServer.get_name() != "headless" and not OS.has_feature("mobile"):
		OS.shell_open(ProjectSettings.globalize_path(path))
	return path


func is_sharing() -> bool:
	return _sharing


func _remember() -> void:
	last_choice = {"strain": current_strain(), "biome": biome_id, "difficulty": difficulty}


func _toast(text: String) -> void:
	toast = text
	toast_time = 1.8
	queue_redraw()

# ---------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press_pos = event.position
				_last_drag = event.position
				_drag_mode = ""
			else:
				if _press_pos.is_finite() and _drag_mode == "":
					tap(event.position)
				_press_pos = Vector2.INF
				_drag_mode = ""
			accept_event()
		elif event.pressed and tab in SCROLL_TABS and not settings_open and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_scroll_trophies(90.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -90.0)
			accept_event()
	elif event is InputEventMouseMotion and _press_pos.is_finite():
		var moved: Vector2 = event.position - _press_pos
		if _drag_mode == "" and moved.length() > TAP_SLOP:
			if tab in SCROLL_TABS and reward.is_empty() and not settings_open and absf(moved.y) > absf(moved.x):
				_drag_mode = "scroll"
			elif tab == "" and reward.is_empty() and not settings_open and strain_card_rect().has_point(_press_pos) and absf(moved.x) > absf(moved.y):
				_drag_mode = "swipe"
			else:
				_drag_mode = "none"
		if _drag_mode == "scroll":
			_scroll_trophies(event.position.y - _last_drag.y)
		elif _drag_mode == "swipe" and absf(moved.x) > SWIPE_DISTANCE:
			select_strain(-1 if moved.x > 0 else 1)
			_drag_mode = "none"
		_last_drag = event.position
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if not reward.is_empty():
		if event.keycode in [KEY_ENTER, KEY_SPACE, KEY_ESCAPE]:
			close_reward()
		return
	if settings_open:
		if event.keycode in [KEY_ESCAPE, KEY_ENTER]:
			close_settings()
		return
	if event.keycode == KEY_ESCAPE and tab != "":
		open_tab(tab)
	elif tab == "" and event.keycode in [KEY_LEFT, KEY_A]:
		select_strain(-1)
	elif tab == "" and event.keycode in [KEY_RIGHT, KEY_D]:
		select_strain(1)
	elif tab == "" and event.keycode in [KEY_ENTER, KEY_SPACE]:
		play()


## Sheets with a swipe-scrolled list (all share trophy_scroll).
const SCROLL_TABS := ["upgrades", "trophies", "chronicle", "codex"]


func _scroll_trophies(amount: float) -> void:
	trophy_scroll = clampf(trophy_scroll - amount, 0.0, _trophy_scroll_max())
	queue_redraw()


## Dispatches a tap at `location` (canvas coordinates). Public for tests.
func tap(location: Vector2) -> void:
	if profile == null:
		return
	_tap_sound(location)
	if not reward.is_empty():
		if reward_button_rect().has_point(location):
			close_reward()
		elif share_button_rect().has_point(location):
			share_reward()
		return
	if settings_open:
		_tap_settings(location)
		return
	if settings_button_rect().has_point(location):
		open_settings()
		return
	for i in TABS.size():
		if tab_rect(i).has_point(location):
			open_tab(TABS[i])
			return
	if tab != "":
		_tap_sheet(location)
		return
	if strain_prev_rect().has_point(location):
		select_strain(-1)
	elif strain_next_rect().has_point(location):
		select_strain(1)
	elif play_rect().has_point(location):
		_press_main_button()
	elif daily_rect().has_point(location):
		play_daily()
	elif records_rect().has_point(location):
		open_chronicle("best")
	else:
		for i in meta.BIOME_ORDER.size():
			if biome_rect(i).has_point(location):
				select_biome(meta.BIOME_ORDER[i])
				return
		for i in meta.DIFFICULTIES.size():
			if difficulty_rect(i).has_point(location):
				select_difficulty(i)
				return


func _tap_settings(location: Vector2) -> void:
	if settings_close_rect().has_point(location) or not settings_panel_rect().has_point(location):
		close_settings()
		return
	for i in SETTINGS.size():
		if settings_row_rect(i).has_point(location):
			toggle_setting(SETTINGS[i][0])
			return
	for k in UI_SKINS.size():
		if settings_skin_rect(k).has_point(location):
			set_ui_skin(UI_SKINS[k])
			return
	if settings_tips_rect().has_point(location):
		reset_tips()


## True while a finger/mouse is held on `rect` without dragging (buttons draw
## their pressed state from this).
func is_pressed(rect: Rect2) -> bool:
	return _press_pos.is_finite() and _drag_mode == "" and rect.has_point(_press_pos)


## The tappable rectangle currently held down, or an empty Rect2.
func pressed_rect() -> Rect2:
	if not _press_pos.is_finite() or _drag_mode != "":
		return Rect2()
	for rect in _button_rects():
		if rect.has_point(_press_pos):
			return rect
	return Rect2()


func _button_rects() -> Array:
	if not reward.is_empty():
		return [reward_button_rect(), share_button_rect()]
	var rects: Array = []
	if settings_open:
		rects.append(settings_close_rect())
		for i in SETTINGS.size():
			rects.append(settings_row_rect(i))
		for k in UI_SKINS.size():
			rects.append(settings_skin_rect(k))
		rects.append(settings_tips_rect())
		return rects
	rects.append(settings_button_rect())
	for i in TABS.size():
		rects.append(tab_rect(i))
	if tab == "upgrades" and meta != null:
		for i in meta.UPGRADE_ORDER.size():
			rects.append(upgrade_buy_rect(i))
	elif tab == "instinct":
		rects.append(instinct_buy_rect())
	elif tab == "chronicle":
		for i in CHRONICLE_VIEWS.size():
			rects.append(chronicle_segment_rect(i))
	elif tab == "trophies" and codex != null:
		rects.append(codex_button_rect())
	elif tab == "codex" and codex != null:
		for i in codex.CATEGORIES.size():
			rects.append(codex_segment_rect(i))
	if tab != "":
		rects.append(sheet_close_rect())
	else:
		rects.append_array([strain_prev_rect(), strain_next_rect(), play_rect(), daily_rect(), records_rect()])
	return rects


func _tap_sheet(location: Vector2) -> void:
	if sheet_close_rect().has_point(location):
		open_tab(tab)
		return
	if tab == "upgrades":
		if not upgrade_list_rect().has_point(location):
			return
		for i in meta.UPGRADE_ORDER.size():
			if upgrade_buy_rect(i).has_point(location):
				buy_upgrade(meta.UPGRADE_ORDER[i])
				return
	elif tab == "instinct":
		if instinct_buy_rect().has_point(location):
			buy_instinct()
	elif tab == "trophies":
		if codex != null and codex_button_rect().has_point(location):
			open_codex()
	elif tab == "codex":
		for i in codex.CATEGORIES.size():
			if codex_segment_rect(i).has_point(location):
				select_codex_view(codex.CATEGORIES[i])
				return
	elif tab == "chronicle":
		for i in CHRONICLE_VIEWS.size():
			if chronicle_segment_rect(i).has_point(location):
				select_chronicle_view(CHRONICLE_VIEWS[i])
				return
		# A run row renders that run's share card.
		if chronicle_view == "runs" and chronicle_list_rect().has_point(location):
			var rows := chronicle_rows()
			for i in rows.size():
				if rows[i].kind == "run" and chronicle_row_rect(i).has_point(location):
					share_run(rows[i].data)
					return

# ---------------------------------------------------------------- layout

func _cx() -> float:
	return size.x * 0.5


func strain_card_rect() -> Rect2:
	return Rect2(40, 226, size.x - 80, 574)


## Stage 15: round arrow buttons overlapping the card edges (hit area >= 96).
func strain_prev_rect() -> Rect2:
	return Rect2(2, 382, 98, 120)


func strain_next_rect() -> Rect2:
	return Rect2(size.x - 100, 382, 98, 120)


## Round gear at the top right, opens the settings panel.
func settings_button_rect() -> Rect2:
	return Rect2(size.x - 118, 12, 100, 100)


## Buying a strain uses the main button (it turns into KAUFEN).
func strain_buy_rect() -> Rect2:
	return play_rect()


func biome_rect(i: int) -> Rect2:
	var count := maxi(2, meta.BIOME_ORDER.size() if meta != null else 3)
	var w := (size.x - 80 - 16 * (count - 1)) / float(count)
	return Rect2(40 + i * (w + 16), 822, w, 116)


func difficulty_rect(i: int) -> Rect2:
	var w := (size.x - 80 - 28) / 3.0
	return Rect2(40 + i * (w + 14), 954, w, 120)


func play_rect() -> Rect2:
	return Rect2(_cx() - 340, 1094, 680, 132)


## TAGES-BRUT: wide loot button below SPIELEN (the map code card is gone).
func daily_rect() -> Rect2:
	return Rect2(40, 1246, size.x - 80, 112)


## Stage 15: centred modal (ribbon on top, four switch rows and the UI style
## row). TAGES-BRUT stays outside it; a tap outside closes it.
func settings_panel_rect() -> Rect2:
	var h := 96.0 + SETTINGS.size() * SETTINGS_ROW_STEP + 186.0 + 64.0 + SETTINGS_TIPS_STEP
	return Rect2(40, 250, size.x - 80, h)


# Etappe 25: five switch rows - a little tighter (was 128 / 114) so TAGES-BRUT
# stays outside the modal.
const SETTINGS_ROW_STEP := 112.0
## Etappe 24: row with the "TIPPS ZURÜCKSETZEN" button under the UI style.
const SETTINGS_TIPS_STEP := 116.0


func settings_close_rect() -> Rect2:
	var p := settings_panel_rect()
	return Rect2(p.end.x - 96, p.position.y - 44, 100, 100)


func settings_row_rect(i: int) -> Rect2:
	var p := settings_panel_rect()
	return Rect2(p.position.x + 28, p.position.y + 84 + i * SETTINGS_ROW_STEP, p.size.x - 56, 100)


## UI style row below the switches: one well with three segment buttons.
func settings_skin_row_rect() -> Rect2:
	var last := settings_row_rect(SETTINGS.size() - 1)
	return Rect2(last.position.x, last.end.y + 14, last.size.x, 172)


func settings_tips_rect() -> Rect2:
	var row := settings_skin_row_rect()
	return Rect2(row.position.x, row.end.y + 18, row.size.x, 96)


func settings_skin_rect(k: int) -> Rect2:
	var row := settings_skin_row_rect()
	var n := UI_SKINS.size()
	var w := (row.size.x - 32 - 12 * (n - 1)) / float(n)
	return Rect2(row.position.x + 16 + k * (w + 12), row.position.y + 60, w, 100)


func tab_rect(i: int) -> Rect2:
	var n := TABS.size()
	var w := (size.x - 32 - 10 * (n - 1)) / float(n)
	return Rect2(16 + i * (w + 10), size.y - 138, w, 124)


## Rekordzeile zwischen TAGES-BRUT und Tab-Leiste: antippen öffnet die Chronik.
func records_rect() -> Rect2:
	var top := daily_rect().end.y + 14.0
	var bottom := tab_rect(0).position.y - 20.0
	return Rect2(40, top, size.x - 80, bottom - top)


## Stage 15: the sheet sits between the resource header and the tab dock, so
## the tabs stay visible and tappable while it is open.
func sheet_rect() -> Rect2:
	var bottom := tab_rect(0).position.y - 14.0 - 16.0
	return Rect2(16, 118, size.x - 32, bottom - 118)


## Height of the coloured title strip of a sheet (Kit.card header).
const SHEET_HEADER := 88.0


## Round close button in the title strip (hit area 100 x 100).
func sheet_close_rect() -> Rect2:
	var s := sheet_rect()
	var cy := s.position.y + (12.0 + SHEET_HEADER) * 0.5
	return Rect2(s.end.x - 116, cy - 50, 100, 100)


func _sheet_body_top() -> float:
	return sheet_rect().position.y + 12.0 + SHEET_HEADER + 14.0


## Scrolling list area of the Brutkammer (also the frame of the trophy view).
func upgrade_list_rect() -> Rect2:
	var s := sheet_rect()
	var top := _sheet_body_top()
	return Rect2(s.position.x + 24, top, s.size.x - 48, s.end.y - 22 - top)


const UPGRADE_ROW_H := 116.0
const UPGRADE_ROW_GAP := 12.0


func upgrade_row_rect(i: int) -> Rect2:
	var area := upgrade_list_rect()
	var scroll := trophy_scroll if tab == "upgrades" else 0.0
	return Rect2(area.position.x, area.position.y + i * (UPGRADE_ROW_H + UPGRADE_ROW_GAP) - scroll, area.size.x, UPGRADE_ROW_H)


func upgrade_buy_rect(i: int) -> Rect2:
	var row := upgrade_row_rect(i)
	return Rect2(row.end.x - 8 - 196, row.position.y + 8, 196, 100)


## Trophy summary strip above the list, and the list itself. The KODEX
## button sits right of the strip (full 96 px touch target).
func trophy_summary_rect() -> Rect2:
	var area := upgrade_list_rect()
	var w := area.size.x - (CODEX_BUTTON_W + 14.0 if codex != null else 0.0)
	return Rect2(area.position.x, area.position.y, w, 100)


const CODEX_BUTTON_W := 236.0


func codex_button_rect() -> Rect2:
	var area := upgrade_list_rect()
	return Rect2(area.end.x - CODEX_BUTTON_W, area.position.y, CODEX_BUTTON_W, 100)


func trophy_list_rect() -> Rect2:
	var area := upgrade_list_rect()
	var top := trophy_summary_rect().end.y + 14
	return Rect2(area.position.x, top, area.size.x, area.end.y - top)


func instinct_buy_rect() -> Rect2:
	var s := sheet_rect()
	return Rect2(_cx() - 270, s.position.y + 876, 540, 128)


func reward_button_rect() -> Rect2:
	var share := share_button_rect()
	return Rect2(share.end.x + 20, share.position.y, size.x - 64 - share.end.x - 20, 120)


## KARTE TEILEN links neben WEITER im Belohnungs-Overlay.
func share_button_rect() -> Rect2:
	return Rect2(64, size.y * 0.5 + 540, 340, 120)

# ---------------------------------------------------------------- codex layout

## Kategorie-Segmente oben im KODEX-Blatt (je ≥ 96 px).
func codex_segment_rect(i: int) -> Rect2:
	var s := sheet_rect()
	var n: int = codex.CATEGORIES.size() if codex != null else 5
	var w := (s.size.x - 48 - 10 * (n - 1)) / float(n)
	return Rect2(s.position.x + 24 + i * (w + 10), _sheet_body_top(), w, 104)


## Zähler-Leiste unter den Segmenten (nicht antippbar).
func codex_summary_rect() -> Rect2:
	var s := sheet_rect()
	return Rect2(s.position.x + 24, codex_segment_rect(0).end.y + 14, s.size.x - 48, 64)


func codex_list_rect() -> Rect2:
	var s := sheet_rect()
	var top := codex_summary_rect().end.y + 14
	return Rect2(s.position.x + 24, top, s.size.x - 48, s.end.y - 22 - top)


## Einträge der gewählten Kategorie mit "seen" (entdeckt) je Eintrag.
func codex_entries() -> Array:
	if codex == null or profile == null:
		return []
	var out: Array = codex.entries(codex_view)
	for e in out:
		e["seen"] = profile.codex_seen.has(e.key)
	return out


const CODEX_ROW_H := 124.0
const CODEX_ROW_GAP := 12.0


## Zeile i in Menü-Koordinaten (berücksichtigt den Scroll).
func codex_row_rect(i: int) -> Rect2:
	var area := codex_list_rect()
	return Rect2(area.position.x, area.position.y + i * (CODEX_ROW_H + CODEX_ROW_GAP) - trophy_scroll, area.size.x, CODEX_ROW_H)

# ---------------------------------------------------------------- chronicle layout

func chronicle_segment_rect(i: int) -> Rect2:
	var s := sheet_rect()
	var n := CHRONICLE_VIEWS.size()
	var w := (s.size.x - 48 - 12 * (n - 1)) / float(n)
	return Rect2(s.position.x + 24 + i * (w + 12), _sheet_body_top(), w, 100)


## Scrollbarer Listenbereich unter den Segmenten.
func chronicle_list_rect() -> Rect2:
	var s := sheet_rect()
	var top := chronicle_segment_rect(0).end.y + 18
	return Rect2(s.position.x + 24, top, s.size.x - 48, s.end.y - 22 - top)


## Zeilen der aktuellen Chronik-Ansicht: [{kind, h, data, …}] mit kind run,
## header, rank, day, total, best oder empty. Antippbare Zeilen sind ≥ 96 hoch.
func chronicle_rows() -> Array:
	var rows: Array = []
	if chronicle == null or meta == null:
		return [{"kind": "empty", "h": 150.0, "data": {"text": "Chronik nicht verfügbar", "hint": ""}}]
	match chronicle_view:
		"runs":
			for run in chronicle.runs:
				rows.append({"kind": "run", "h": 112.0, "data": run})
			if rows.is_empty():
				rows.append({"kind": "empty", "h": 150.0, "data": {"text": "Noch keine Jagd verzeichnet.", "hint": "Jeder Run landet hier – auch der kürzeste."}})
		"daily":
			var today: String = load(PROFILE_PATH).today_key()
			rows.append({"kind": "header", "h": 56.0, "data": {"text": "HEUTE", "date": today}})
			var board: Array = chronicle.daily_board(today)
			for i in board.size():
				rows.append({"kind": "rank", "h": 100.0, "data": board[i], "rank": i + 1})
			if board.is_empty():
				rows.append({"kind": "empty", "h": 150.0, "data": {"text": "Heute noch keine TAGES-BRUT.", "hint": "Gleiche Karte für alle – deine besten 10 Versuche stehen hier."}})
			var earlier: Array = []
			for date in chronicle.daily_dates():
				if date != today and not chronicle.daily_board(date).is_empty():
					earlier.append(date)
			if not earlier.is_empty():
				rows.append({"kind": "header", "h": 56.0, "data": {"text": "FRÜHERE TAGE", "date": ""}})
				for date in earlier:
					var list: Array = chronicle.daily_board(date)
					rows.append({"kind": "day", "h": 100.0, "data": list[0], "date": date, "count": list.size()})
		"best":
			rows.append({"kind": "total", "h": 150.0, "data": chronicle.overall_best()})
			for id in strain_ids:
				for d in meta.DIFFICULTIES.size():
					if not chronicle.best(id, d).is_empty():
						rows.append({"kind": "best", "h": 150.0, "data": {"strain_id": id}})
						break
			if rows.size() == 1:
				rows.append({"kind": "empty", "h": 150.0, "data": {"text": "Noch keine Bestwerte.", "hint": "Bestwerte je Stamm und Schwierigkeit erscheinen nach dem ersten Run."}})
	return rows


## Zeile i in Menü-Koordinaten (berücksichtigt den Scroll).
func chronicle_row_rect(i: int) -> Rect2:
	var rows := chronicle_rows()
	var area := chronicle_list_rect()
	var y := area.position.y - trophy_scroll
	for k in mini(i, rows.size()):
		y += float(rows[k].h) + CHRONICLE_ROW_GAP
	var h: float = float(rows[i].h) if i < rows.size() else 0.0
	return Rect2(area.position.x, y, area.size.x, h)


const CHRONICLE_ROW_GAP := 10.0


func _chronicle_content_height() -> float:
	var total := 0.0
	for row in chronicle_rows():
		total += float(row.h) + CHRONICLE_ROW_GAP
	return total


## Row pitch of the trophy list (row plus 12 px gap).
func _trophy_row_height() -> float:
	return 150.0


func _trophy_scroll_max() -> float:
	if meta == null:
		return 0.0
	if tab == "chronicle":
		return maxf(0.0, _chronicle_content_height() - chronicle_list_rect().size.y)
	if tab == "codex":
		var n: int = codex.entries(codex_view).size() if codex != null else 0
		return maxf(0.0, n * (CODEX_ROW_H + CODEX_ROW_GAP) - CODEX_ROW_GAP - codex_list_rect().size.y)
	if tab == "upgrades":
		var rows: int = meta.UPGRADE_ORDER.size()
		return maxf(0.0, rows * (UPGRADE_ROW_H + UPGRADE_ROW_GAP) - UPGRADE_ROW_GAP - upgrade_list_rect().size.y)
	return maxf(0.0, meta.QUESTS.size() * _trophy_row_height() - 12.0 - trophy_list_rect().size.y)

# ---------------------------------------------------------------- drawing

# UI pass (stage 04): legacy blocks can be replaced by components in scripts/ui/menu/.
var legacy := {"background": true, "logo": true, "resources": true, "strain": true, "biomes": true, "difficulties": true, "play": true, "sheet": true, "tabs": true, "reward": true, "toast": true, "settings": true}


func _draw() -> void:
	_ensure_font()
	if legacy.background:
		_draw_background()
	if profile == null:
		if legacy.logo:
			_draw_logo()
		_text(load_error if load_error != "" else "Lade …", Vector2(_cx(), size.y * 0.5), 32, BONE, true, 5)
		return
	if legacy.resources:
		_draw_resources()
	if tab == "":
		if legacy.logo:
			_draw_logo()
		if legacy.strain:
			_draw_strain()
		if legacy.biomes:
			_draw_biomes()
		if legacy.difficulties:
			_draw_difficulties()
		if legacy.play:
			_draw_play()
	elif legacy.sheet:
		_draw_sheet()
	if legacy.tabs:
		_draw_tabs()
	if legacy.reward and not reward.is_empty():
		_draw_reward()
	if legacy.toast and toast_time > 0.0 and toast != "":
		_draw_toast()


func _build_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7331
	for i in 26:
		var left := i % 2 == 0
		var y := rng.randf_range(-40, 1640)
		var x := rng.randf_range(-60, 70) if left else rng.randf_range(830, 960)
		var angle := (rng.randf_range(-0.9, 0.9)) + (0.0 if left else PI)
		_decor.append({"kind": "leaf", "pos": Vector2(x, y), "len": rng.randf_range(110, 230), "w": rng.randf_range(26, 52), "angle": angle, "shade": rng.randf_range(0.0, 1.0), "phase": rng.randf() * TAU})
	for i in 34:
		_decor.append({"kind": "spore", "pos": Vector2(rng.randf_range(0, 900), rng.randf_range(0, 1600)), "r": rng.randf_range(2.0, 5.5), "speed": rng.randf_range(8, 22), "phase": rng.randf() * TAU})


func _draw_background() -> void:
	var top := Color("0a1c17")
	var mid := Color("123326")
	var low := Color("0b1f18")
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, size.y * 0.45), Vector2(0, size.y * 0.45)]), PackedColorArray([top, top, mid, mid]))
	draw_polygon(PackedVector2Array([Vector2(0, size.y * 0.45), Vector2(size.x, size.y * 0.45), Vector2(size.x, size.y), Vector2(0, size.y)]), PackedColorArray([mid, mid, low, low]))
	# Soft glow behind the strain emblem in the strain colour.
	var tint := _strain_color(current_strain()) if profile != null else WARM
	for i in 6:
		draw_circle(Vector2(_cx(), 470), 330 - i * 48, Color(tint, 0.028 + i * 0.006))
	var t := Time.get_ticks_msec() * 0.001
	for d in _decor:
		if d.kind == "spore":
			var p: Vector2 = d.pos + Vector2(sin(t * 0.4 + d.phase) * 18.0, -fmod(t * d.speed, 1700.0))
			p.y = fposmod(p.y, 1700.0) - 50.0
			draw_circle(p, d.r * 2.2, Color(CYAN, 0.05))
			draw_circle(p, d.r, Color(Color("b9f3d8"), 0.35 + 0.25 * sin(t * 2.0 + d.phase)))
	for d in _decor:
		if d.kind == "leaf":
			var shade: float = d.shade
			var color := Color("0e2a1f").lerp(Color("1d4a2f"), shade)
			_leaf(d.pos, d.len, d.w, d.angle + sin(t * 0.7 + d.phase) * 0.04, color)
	# Vignette: darken the top and bottom bands for the HUD panels.
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, 120), Vector2(0, 120)]), PackedColorArray([Color(0, 0, 0, 0.45), Color(0, 0, 0, 0.45), Color(0, 0, 0, 0), Color(0, 0, 0, 0)]))
	draw_polygon(PackedVector2Array([Vector2(0, size.y - 220), Vector2(size.x, size.y - 220), Vector2(size.x, size.y), Vector2(0, size.y)]), PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.55)]))


func _draw_logo() -> void:
	var cx := _cx()
	var title := "MAWLINGS"
	var font_size := 112
	var w := _text_width(title, font_size)
	var baseline := 228.0
	# Jaw: an upper gum line with fangs hanging over the word and a lower one pushing up.
	var gum_top := baseline - 104.0
	var gum_low := baseline + 18.0
	var left := cx - w * 0.5 - 30
	var right := cx + w * 0.5 + 30
	draw_colored_polygon(_rounded_points(Rect2(left, gum_top - 14, right - left, 16), 8, 3), Color("7a2618"))
	draw_colored_polygon(_rounded_points(Rect2(left + 40, gum_low, right - left - 80, 14), 7, 3), Color("7a2618"))
	var tooth := Color("fff1d0")
	var count := 9
	for i in count:
		var x := lerpf(left + 26, right - 26, float(i) / (count - 1))
		var long := 30.0 if i % 4 == 0 else 18.0
		draw_colored_polygon(PackedVector2Array([Vector2(x - 11, gum_top), Vector2(x + 11, gum_top), Vector2(x + 2, gum_top + long)]), tooth)
	for i in count - 2:
		var x := lerpf(left + 70, right - 70, float(i) / (count - 3))
		var long := 24.0 if i % 3 == 1 else 14.0
		draw_colored_polygon(PackedVector2Array([Vector2(x - 9, gum_low + 2), Vector2(x + 9, gum_low + 2), Vector2(x - 2, gum_low + 2 - long)]), tooth)
	_claw(Vector2(left - 6, gum_top - 6), Vector2(-0.6, -1), 34, 9, CLAW, 0.5)
	_claw(Vector2(right + 6, gum_top - 6), Vector2(0.6, -1), 34, 9, CLAW, -0.5)
	_text(title, Vector2(cx, baseline + 4), font_size, Color("2a0d06"), true)
	_text(title, Vector2(cx, baseline), font_size, Color("ffb35c"), true, 10)
	# Highlight: a thin brighter pass slightly above for a carved look.
	_text(title, Vector2(cx, baseline - 3), font_size, Color(Color("ffe2a8"), 0.35), true)
	var sub := "BRUTSTÄTTE"
	_text(sub, Vector2(cx, baseline + 64), 26, Color("9ed5b3"), true)
	var half := _text_width(sub, 26) * 0.5
	for s in [-1.0, 1.0]:
		draw_line(Vector2(cx + s * (half + 16), baseline + 55), Vector2(cx + s * (half + 150), baseline + 55), Color("4f7a5c"), 2, true)
		_diamond(Vector2(cx + s * (half + 158), baseline + 55), 6, LEAF)


func _draw_resources() -> void:
	var essence_rect := Rect2(16, 18, 270, 76)
	_frame(essence_rect, PANEL, CYAN, 0)
	_essence_drop(Vector2(56, 60), 19, CYAN)
	_text("ESSENZ", Vector2(92, 46), 16, Color("bfeee6"))
	_text("%d" % profile.essence, Vector2(92, 82), 34, Color.WHITE, false, 5)
	var crown_rect := Rect2(size.x - 286, 18, 270, 76)
	_frame(crown_rect, PANEL, GOLD, 0)
	_fang(Vector2(crown_rect.position.x + 42, 58), 22, Color("ffe7a8"))
	_text("KÖNIGSZÄHNE", Vector2(crown_rect.position.x + 78, 46), 16, Color("f4dca0"))
	_text("%d" % profile.crowns, Vector2(crown_rect.position.x + 78, 82), 34, Color.WHITE, false, 5)


func _strain_color(id: String) -> Color:
	var s := _strain(id)
	return Color(s.get("tint", "#d9401f"))


func _draw_strain() -> void:
	var id := current_strain()
	var s := _strain(id)
	var owned := _strain_owned(id)
	var unlocked := _strain_unlocked(id)
	var tint := _strain_color(id)
	var accent := tint.lightened(0.35) if unlocked else Color("6f7d74")
	var card := strain_card_rect()
	_frame(card, Color("0e211cf0"), Color(accent, 0.9), 1 | 2, 4.0)
	var ox := _slide
	var cx := _cx() + ox
	# Emblem: pack of three heads in the strain colour (dark silhouette when locked).
	var head_color := tint if unlocked else Color("1c2a25")
	var ec := Vector2(cx, 428)
	draw_circle(ec, 116, Color(tint, 0.16) if unlocked else Color(0, 0, 0, 0.25))
	draw_arc(ec, 116, 0, TAU, 64, Color(accent, 0.65), 3, true)
	draw_arc(ec, 104, 0, TAU, 64, Color(accent, 0.2), 2, true)
	_mawling_head(ec + Vector2(-64, -34), 46, head_color.darkened(0.3))
	_mawling_head(ec + Vector2(62, -42), 43, head_color.darkened(0.18))
	_mawling_head(ec + Vector2(0, 16), 68, head_color)
	if not unlocked:
		draw_circle(ec, 50, Color("0a1a17e0"))
		_lock(ec, 36, Color("c9d1c4"))
	# Ownership badge, top left inside the card.
	var badge_text := "IM BESITZ"
	var badge_color := Color("8fd46a")
	if not unlocked:
		badge_text = "GESPERRT"
		badge_color = Color("ff9a7a")
	elif not owned:
		badge_text = "KAUFBAR"
		badge_color = GOLD
	var bw := _text_width(badge_text, 18) + 44
	var badge := Rect2(card.position.x + 22, card.position.y + 20, bw, 36)
	_pill(badge, Color(badge_color, 0.16))
	_diamond(badge.position + Vector2(20, 18), 7, badge_color)
	_text(badge_text, badge.position + Vector2(34, 25), 18, badge_color)
	# Name + description (or the unlock quest when locked).
	_text(String(s.get("name", id)).to_upper(), Vector2(cx, 606), 56, accent if unlocked else Color("aab5ab"), true, 7)
	if unlocked:
		_paragraph(s.get("description", ""), Vector2(cx, 650), card.size.x - 150, 23, Color("e6dcc0"), true, 2)
	else:
		_paragraph("Trophäe · " + _quest_label(s.get("unlock_quest", "")), Vector2(cx, 650), card.size.x - 150, 23, Color("ffd2bd"), true, 2)
	_draw_strain_stats(s, Vector2(card.position.x + 30 + ox, 690), card.size.x - 60, accent)
	# Arrows and page dots.
	for rect in [strain_prev_rect(), strain_next_rect()]:
		var dir := -1.0 if rect == strain_prev_rect() else 1.0
		_frame(rect, Color("0a1a16ee"), Color(BONE, 0.7), 0, 3.0)
		_arrow(rect.get_center(), 30, dir, BONE)
	for i in strain_ids.size():
		var dot := Vector2(_cx() + (i - (strain_ids.size() - 1) * 0.5) * 30, card.end.y + 26)
		var other := strain_ids[i] as String
		var dc := _strain_color(other) if _strain_unlocked(other) else Color("47554d")
		if i == strain_index:
			_diamond(dot, 12, dc.lightened(0.3))
		else:
			_diamond(dot, 7, Color(dc, 0.7))


func _draw_strain_stats(s: Dictionary, origin: Vector2, width: float, accent: Color) -> void:
	var mods: Dictionary = s.get("mods", {})
	var sig: String = s.get("signature", "")
	var sig_name: String = meta.MUTATION_NAMES.get(sig, sig)
	var items := [
		["START", "%d" % int(s.get("start_population", 25)), Color("f4c48c")],
		["SIGNATUR", sig_name, CYAN],
	]
	var pairs := [["damage", "SCHADEN"], ["armor", "PANZER"], ["speed", "TEMPO"], ["growth", "WACHSTUM"], ["dna", "DNA"]]
	for pair in pairs:
		var v: float = float(mods.get(pair[0], 0.0 if pair[0] == "armor" else 1.0))
		var delta := v * 100.0 if pair[0] == "armor" else (v - 1.0) * 100.0
		if absf(delta) >= 0.5:
			items.append([pair[1], "%+d %%" % roundi(delta), Color("9fe07a") if delta > 0 else Color("ff8a6a")])
	if s.has("rally_damage"):
		items.append(["RALLY", "%+d %%" % roundi((float(s.rally_damage) - 1.0) * 100.0), Color("9fe07a")])
	# Chips in one or two centred rows.
	var chips: Array = []
	for item in items:
		var text := "%s  %s" % [item[0], item[1]]
		chips.append([text, _text_width(text, 21) + 46, item[2]])
	var rows: Array = [[]]
	var row_w := 0.0
	for chip in chips:
		if row_w + chip[1] > width and not rows[-1].is_empty():
			rows.append([])
			row_w = 0.0
		rows[-1].append(chip)
		row_w += chip[1] + 10
	for r in rows.size():
		var total := 0.0
		for chip in rows[r]:
			total += chip[1] + 10
		var x := origin.x + (width - total + 10) * 0.5
		var y := origin.y + r * 48
		for chip in rows[r]:
			_pill(Rect2(x, y, chip[1], 40), Color("0a1a16"))
			_diamond(Vector2(x + 19, y + 20), 8, chip[2])
			_text(chip[0], Vector2(x + 33, y + 28), 21, Color("efe4c6"))
			x += chip[1] + 10


func _section_label(text: String, y: float) -> void:
	_text(text, Vector2(34, y), 20, Color("9ed5b3"))
	var w := _text_width(text, 20)
	draw_line(Vector2(46 + w, y - 7), Vector2(size.x - 34, y - 7), Color("2f5242"), 2, true)


func _draw_biomes() -> void:
	_section_label("BIOM", 858)
	for i in meta.BIOME_ORDER.size():
		var id: String = meta.BIOME_ORDER[i]
		var b: Dictionary = meta.BIOMES[id]
		var rect := biome_rect(i)
		var locked: bool = b.get("locked", false)
		var selected := id == biome_id
		var accent := Color("8fd46a") if id == "verdant_maw" else Color("ff8a3d")
		if locked:
			accent = Color("6f7d74")
		_frame(rect, Color("163a2a") if selected else Color("0c1c17e8"), accent if selected else Color(accent, 0.5), 1 if selected else 0, 4.0 if selected else 2.0)
		# Tiny biome vignette on the left.
		var ic := rect.position + Vector2(54, 56)
		draw_circle(ic, 36, Color("0a1a16"))
		if id == "verdant_maw":
			_leaf(ic + Vector2(-20, 18), 44, 14, -1.1, Color("5fae52"))
			_leaf(ic + Vector2(-4, 22), 40, 12, -0.4, Color("8fd46a"))
			_leaf(ic + Vector2(-26, 10), 34, 10, -1.8, Color("3f8a45"))
		else:
			_ellipse(ic + Vector2(0, 10), 26, 12, Color("7a2a14"))
			draw_circle(ic + Vector2(-8, 4), 7, Color("ff8a3d"))
			draw_circle(ic + Vector2(10, -4), 5, Color("ffc15c"))
			draw_circle(ic + Vector2(2, -16), 4, Color(Color("ffc15c"), 0.6))
		_text(String(b.name).to_upper(), Vector2(rect.position.x + 104, rect.position.y + 50), 26, Color.WHITE if not locked else Color("9aa69c"), false, 4)
		if locked:
			var status := String(b.get("status", "")).to_upper()
			_pill(Rect2(rect.position.x + 104, rect.position.y + 64, _text_width(status, 18) + 30, 32), Color("5a2a14"))
			_text(status, Vector2(rect.position.x + 119, rect.position.y + 86), 18, Color("ffc79a"))
		else:
			_text("GEWÄHLT" if selected else "ANTIPPEN", Vector2(rect.position.x + 104, rect.position.y + 86), 18, Color("a6d99a") if selected else MUTED)


func _draw_difficulties() -> void:
	_section_label("SCHWIERIGKEIT", 1032)
	for i in meta.DIFFICULTIES.size():
		var d: Dictionary = meta.DIFFICULTIES[i]
		var rect := difficulty_rect(i)
		var unlocked := _difficulty_unlocked(i)
		var selected: bool = i == difficulty
		var accent: Color = DIFFICULTY_COLORS[i] if unlocked else Color("6f7d74")
		_frame(rect, Color(accent, 0.22) if selected else Color("0c1c17e8"), accent if selected else Color(accent, 0.45), 0, 4.0 if selected else 2.0)
		var c := rect.get_center()
		var name := String(d.name).to_upper()
		if unlocked:
			for k in i + 1:
				_skull(Vector2(c.x - i * 16 + k * 32, rect.position.y + 28), 14, accent)
			_text(name, Vector2(c.x, rect.position.y + 74), 30, Color.WHITE if selected else Color("e6dcc0"), true, 4)
			_text("×%.1f ESSENZ" % float(d.get("reward", 1.0)), Vector2(c.x, rect.position.y + 100), 18, Color(accent, 0.95), true)
		else:
			var w := _text_width(name, 26)
			var x0 := c.x - (w + 38) * 0.5
			_lock(Vector2(x0 + 12, rect.position.y + 38), 15, Color("9aa69c"))
			_text(name, Vector2(x0 + 38, rect.position.y + 50), 26, Color("9aa69c"))
			var q: Dictionary = meta.quest(d.get("unlock_quest", ""))
			_text(String(q.get("name", "")), Vector2(c.x, rect.position.y + 88), 18, Color("d8c79a"), true)


func _draw_play() -> void:
	var rect := play_rect()
	var id := current_strain()
	var owned := _strain_owned(id)
	var unlocked := _strain_unlocked(id)
	var c := rect.get_center()
	if owned:
		var ok := can_play()
		var color := WARM if ok else Color("5d665f")
		_frame(rect.grow(10), Color(color, 0.12 + 0.12 * _pulse(2.2)), Color(color, 0.0), 0)
		_frame(rect, Color("a4401a"), color.lightened(0.2), 1 | 2 | 4 | 8, 5.0)
		draw_colored_polygon(_rounded_points(Rect2(rect.position + Vector2(10, 8), Vector2(rect.size.x - 20, rect.size.y * 0.42)), 18, 4), Color(1, 1, 1, 0.08))
		var w := _text_width("SPIELEN", 62)
		_text("SPIELEN", c + Vector2(28, 22), 62, Color.WHITE, true, 8)
		_mawling_head(c + Vector2(-w * 0.5 - 22, 0), 36, Color("ffcf8a"))
	elif unlocked:
		var price := int(profile.strain_cost(id))
		var affordable: bool = profile.crowns >= price
		var color := GOLD if affordable else Color("8a8466")
		_frame(rect.grow(10), Color(color, 0.1 + 0.1 * _pulse(2.2) if affordable else 0.0), Color(color, 0.0), 0)
		_frame(rect, Color("6a4c16") if affordable else Color("2a2a22"), color, 1 | 2 | 4 | 8, 5.0)
		var label := "KAUFEN · %d" % price
		var w := _text_width(label, 50)
		_text(label, c + Vector2(-22, 10), 50, Color.WHITE if affordable else Color("b5ae90"), true, 7)
		_fang(c + Vector2(w * 0.5 + 8, -6), 24, Color("ffe7a8"))
		_text("KÖNIGSZÄHNE" if affordable else "ZU WENIGE KÖNIGSZÄHNE", c + Vector2(0, 46), 18, Color("f4dca0"), true)
	else:
		_frame(rect, Color("1e2823"), Color("5d665f"), 1 | 2 | 4 | 8, 4.0)
		var w := _text_width("GESPERRT", 46)
		_lock(c + Vector2(-w * 0.5 - 14, -8), 20, Color("aab5ab"))
		_text("GESPERRT", c + Vector2(20, 8), 46, Color("aab5ab"), true, 6)
		var q: Dictionary = meta.quest(_strain(id).get("unlock_quest", ""))
		_text("Trophäe: " + String(q.get("name", "")), c + Vector2(0, 46), 19, Color("d8c79a"), true)
	# Record line and the closest open trophy below the button.
	var best := float(profile.records.get("best_seconds", 0.0))
	var peak := int(profile.records.get("best_peak", 0))
	var line := "REKORD  %02d:%02d   ·   MAX. SCHWARM  %d" % [int(best) / 60, int(best) % 60, peak]
	_text(line, Vector2(_cx(), rect.end.y + 36), 20, Color("b6d0bc"), true)
	_draw_next_trophy(Rect2(28, rect.end.y + 52, size.x - 56, 84))


func _next_quest() -> Dictionary:
	var best: Dictionary = {}
	var best_fraction := -1.0
	for q in meta.QUESTS:
		if q.id in profile.completed_quests:
			continue
		var progress: Vector2 = profile.quest_progress(q.id)
		var fraction := progress.x / maxf(1.0, progress.y)
		if fraction > best_fraction:
			best_fraction = fraction
			best = q
	return best


func _draw_next_trophy(rect: Rect2) -> void:
	var q := _next_quest()
	if q.is_empty():
		return
	var accent := Color("b798ec")
	_frame(rect, Color("0c1c17e0"), Color(accent, 0.5), 0, 2.0)
	var ic := rect.position + Vector2(44, rect.size.y * 0.5)
	draw_circle(ic, 28, INK)
	draw_arc(ic, 28, 0, TAU, 32, accent, 3, true)
	_skull(ic + Vector2(0, 2), 13, accent)
	_text("NÄCHSTE TROPHÄE", rect.position + Vector2(86, 32), 16, Color("c9bfe3"))
	_text(q.name, rect.position + Vector2(86, 66), 26, Color.WHITE, false, 3)
	var progress: Vector2 = profile.quest_progress(q.id)
	var bar := Rect2(rect.end.x - 250, rect.position.y + 50, 220, 14)
	_bar(bar, clampf(progress.x / maxf(1.0, progress.y), 0.0, 1.0), accent)
	_text_right(_progress_text(q, progress), Vector2(bar.end.x, rect.position.y + 38), 18, Color("c9bfe3"))


func _draw_tabs() -> void:
	for i in TABS.size():
		var id: String = TABS[i]
		var rect := tab_rect(i)
		var active := tab == id
		var accent: Color = [GOLD, Color("b798ec"), CYAN, Color("b798ec")][i]
		_frame(rect, Color("1a3a2c") if active else Color("0c1c17f0"), accent if active else Color(accent, 0.55), 1 | 2 if active else 0, 4.0 if active else 2.0)
		var ic := Vector2(rect.get_center().x, rect.position.y + 40)
		if id == "upgrades":
			_ellipse(ic + Vector2(-12, 4), 11, 15, accent)
			_ellipse(ic + Vector2(12, 4), 11, 15, accent.darkened(0.15))
			_ellipse(ic + Vector2(0, -8), 11, 15, accent.lightened(0.1))
		elif id == "trophies":
			_skull(ic + Vector2(0, 2), 16, accent)
			_crown(ic + Vector2(0, -20), 10, GOLD)
		else:
			_mawling_head(ic, 20, accent)
		_text(TAB_NAMES[id], Vector2(rect.get_center().x, rect.position.y + 94), 22, Color.WHITE if active else Color("d8ceb2"), true)
		if id == "upgrades" and _affordable_upgrades() > 0 and not active:
			var badge := Vector2(rect.end.x - 24, rect.position.y + 22)
			draw_circle(badge, 15, WARM)
			_text("%d" % _affordable_upgrades(), badge + Vector2(0, 7), 19, Color.WHITE, true)


func _affordable_upgrades() -> int:
	var n := 0
	for id in meta.UPGRADE_ORDER:
		if _upgrade_available(id) and _upgrade_rank(id) < int(meta.UPGRADES[id].max) and profile.essence >= profile.upgrade_cost(id):
			n += 1
	return n


func _draw_sheet() -> void:
	var s := sheet_rect()
	var accent: Color = {"upgrades": GOLD, "trophies": Color("b798ec"), "instinct": CYAN}[tab]
	_frame(s, Color("0b1d18f6"), accent, 1 | 2, 4.0)
	_text(TAB_NAMES[tab], Vector2(s.position.x + 36, s.position.y + 80), 48, Color("f5e6ba"), false, 7)
	var subtitle := ""
	if tab == "upgrades":
		subtitle = "Dauerhafte Stärken für jede Brut"
	elif tab == "trophies":
		subtitle = "%d / %d erledigt" % [profile.completed_quests.size(), meta.QUESTS.size()]
	else:
		subtitle = "Endlose Stufen für Schaden und Biomasse"
	_text(subtitle, Vector2(s.position.x + 38, s.position.y + 122), 21, Color("9ed5b3"))
	var close := sheet_close_rect()
	_frame(close, Color("0a1a16"), Color(BONE, 0.7), 0)
	var cc := close.get_center()
	draw_line(cc + Vector2(-18, -18), cc + Vector2(18, 18), BONE, 6, true)
	draw_line(cc + Vector2(18, -18), cc + Vector2(-18, 18), BONE, 6, true)
	draw_line(Vector2(s.position.x + 24, s.position.y + 146), Vector2(s.end.x - 24, s.position.y + 146), Color(accent, 0.35), 2)
	if tab == "upgrades":
		_draw_upgrades()
	elif tab == "trophies":
		_draw_trophies()
	else:
		_draw_instinct()


func _draw_cost_button(rect: Rect2, cost: int, affordable: bool, label: String, currency: String) -> void:
	var color := WARM if affordable else Color("596158")
	_frame(rect, Color("8a3a18") if affordable else Color("1e2823"), color, 0, 3.0)
	_text(label, Vector2(rect.get_center().x, rect.position.y + 38), 22, Color.WHITE if affordable else Color("a3aa9f"), true)
	var cost_text := "%d" % cost
	var w := _text_width(cost_text, 28)
	var x := rect.get_center().x - (w + 30) * 0.5
	if currency == "essence":
		_essence_drop(Vector2(x + 10, rect.position.y + 70), 10, CYAN if affordable else Color("7d8e89"))
	else:
		_fang(Vector2(x + 10, rect.position.y + 70), 12, Color("ffe7a8"))
	_text(cost_text, Vector2(x + 30, rect.position.y + 82), 28, Color.WHITE if affordable else Color("a3aa9f"))


func _draw_upgrades() -> void:
	for i in meta.UPGRADE_ORDER.size():
		var id: String = meta.UPGRADE_ORDER[i]
		var u: Dictionary = meta.UPGRADES[id]
		var row := upgrade_row_rect(i)
		var rank := _upgrade_rank(id)
		var max_rank := int(u.max)
		var available := _upgrade_available(id)
		var accent: Color = UPGRADE_COLORS.get(id, GOLD) if available else Color("6f7d74")
		_frame(row, Color("10261fee"), Color(accent, 0.55), 0, 2.0)
		var ic := row.position + Vector2(56, row.size.y * 0.5)
		draw_circle(ic, 38, INK)
		draw_arc(ic, 38, 0, TAU, 40, accent, 3, true)
		_upgrade_icon(id, ic, 24, accent)
		var x := row.position.x + 112
		_text(String(u.name).to_upper(), Vector2(x, row.position.y + 42), 27, Color.WHITE if available else Color("aab5ab"), false, 4)
		_text(u.description, Vector2(x, row.position.y + 74), 19, Color("d9ceb0"))
		if available:
			if max_rank <= 10:
				_pips(Vector2(x + 8, row.position.y + 102), rank, max_rank, accent, 8.0, 21.0)
			_text("%d / %d" % [rank, max_rank], Vector2(x + 8 + max_rank * 21 + 6, row.position.y + 109), 18, Color("b8d0bc"))
		else:
			_lock(Vector2(x + 10, row.position.y + 100), 10, Color("c4b89a"))
			_text("Trophäe: %s" % meta.quest(u.get("requires", "")).get("name", ""), Vector2(x + 28, row.position.y + 108), 18, Color("c4b89a"))
		var buy := upgrade_buy_rect(i)
		if rank >= max_rank:
			_frame(buy, Color("1b3a2a"), Color("8fd46a"), 0, 3.0)
			_check(buy.get_center() + Vector2(-44, -2), 16, Color("8fd46a"))
			_text("MAX", buy.get_center() + Vector2(14, 12), 32, Color("c9f0b0"), true)
		elif not available:
			_frame(buy, Color("161f1b"), Color("4a554e"), 0, 2.0)
			_lock(buy.get_center() + Vector2(0, -4), 18, Color("6f7d74"))
		else:
			var cost := int(profile.upgrade_cost(id))
			_draw_cost_button(buy, cost, profile.essence >= cost, "KAUFEN", "essence")


func _upgrade_icon(id: String, c: Vector2, r: float, color: Color) -> void:
	match id:
		"brood_size":
			for o in [Vector2(-0.45, 0.25), Vector2(0.45, 0.25), Vector2(0, -0.3)]:
				_ellipse(c + o * r, 0.36 * r, 0.48 * r, color)
		"rending":
			for k in 3:
				_claw(c + Vector2(-0.6 + k * 0.5, 0.7) * r, Vector2(0.35, -1), 1.5 * r, 0.22 * r, color, 0.3)
		"chitin":
			var shield := PackedVector2Array([c + Vector2(0, -0.95) * r, c + Vector2(0.8, -0.55) * r, c + Vector2(0.65, 0.45) * r, c + Vector2(0, 1.0) * r, c + Vector2(-0.65, 0.45) * r, c + Vector2(-0.8, -0.55) * r])
			draw_colored_polygon(shield, color)
			draw_line(c + Vector2(-0.6, 0) * r, c + Vector2(0.6, 0) * r, INK, 3)
		"sprinter":
			for k in 3:
				var y := (-0.5 + k * 0.5) * r
				draw_line(c + Vector2(-0.9 + k * 0.2, y), c + Vector2(0.2, y), color, 4, true)
			_arrow(c + Vector2(0.45, 0) * r, 0.8 * r, 1.0, color)
		"digestion":
			_essence_drop(c + Vector2(0, 0.15 * r), 0.7 * r, color)
		"witterung":
			# Collect radius: a crystal with two pulling rings around it.
			for k in 2:
				draw_arc(c, (0.55 + 0.35 * k) * r, 0.0, TAU, 28, Color(color, 0.9 - 0.35 * k), 3.5, true)
			_diamond(c, 0.34 * r, color)
		"geneflow":
			var a := PackedVector2Array()
			var b := PackedVector2Array()
			for i in 13:
				var t := float(i) / 12.0
				var y := c.y - r + 2.0 * r * t
				a.append(Vector2(c.x + sin(t * TAU * 1.2) * 0.5 * r, y))
				b.append(Vector2(c.x + sin(t * TAU * 1.2 + PI) * 0.5 * r, y))
			draw_polyline(a, color, 4, true)
			draw_polyline(b, color.darkened(0.25), 4, true)
		"attack_slot":
			_mawling_head(c, 0.8 * r, color)
		"trait_slot":
			for k in 3:
				_diamond(c + Vector2(-0.6 + k * 0.6, 0), 0.35 * r, color)
		_:
			_diamond(c, 0.6 * r, color)


func _draw_trophies() -> void:
	var s := sheet_rect()
	var top := _sheet_body_top()
	var bottom := s.end.y - 20
	var row_h := _trophy_row_height()
	var first := int(trophy_scroll / row_h)
	for i in range(first, mini(meta.QUESTS.size(), first + int((bottom - top) / row_h) + 2)):
		var q: Dictionary = meta.QUESTS[i]
		var y := top + i * row_h - trophy_scroll
		var row := Rect2(s.position.x + 18, y, s.size.x - 36, row_h - 12)
		if row.end.y < top - row_h or row.position.y > bottom:
			continue
		# Clip rows that leave the list area by fading them out at the edges.
		var alpha := clampf(minf((row.end.y - top) / 60.0 + 0.2, (bottom - row.position.y) / 60.0 + 0.2), 0.0, 1.0)
		if row.position.y < top - 4 or row.end.y > bottom + 4:
			alpha = minf(alpha, 0.35)
		var done: bool = q.id in profile.completed_quests
		var progress: Vector2 = profile.quest_progress(q.id)
		var accent := Color("8fd46a") if done else Color("b798ec")
		_frame(row, Color(Color("123024") if done else Color("10231e"), 0.95 * alpha), Color(accent, 0.5 * alpha), 0, 2.0)
		var ic := row.position + Vector2(50, row.size.y * 0.5)
		draw_circle(ic, 32, Color(INK, alpha))
		draw_arc(ic, 32, 0, TAU, 32, Color(accent, alpha), 3, true)
		if done:
			_check(ic, 20, Color(accent, alpha))
		else:
			_skull(ic + Vector2(0, 2), 15, Color(accent, 0.8 * alpha))
		var x := row.position.x + 100
		_text(q.name, Vector2(x, row.position.y + 38), 25, Color(Color.WHITE if not done else Color("cfe8c0"), alpha), false, 3)
		_text(q.description, Vector2(x, row.position.y + 66), 18, Color(Color("d9ceb0"), alpha))
		var reward_text := _reward_text(q)
		var bar := Rect2(x, row.position.y + 80, 250, 14)
		if done:
			_text("ERLEDIGT", Vector2(x, row.position.y + 99), 17, Color(accent, alpha))
		else:
			_bar(bar, clampf(progress.x / maxf(1.0, progress.y), 0.0, 1.0), Color(accent, alpha))
			_text(_progress_text(q, progress), Vector2(bar.end.x + 12, row.position.y + 94), 17, Color(Color("c9bfe3"), alpha))
		_paragraph(reward_text, Vector2(row.end.x - 200, row.position.y + 44), 186, 17, Color(Color("f6cc70") if not done else Color("8fa597"), alpha), false, 3)
	# Scroll indicator.
	var max_scroll := _trophy_scroll_max()
	if max_scroll > 0.0:
		var track := Rect2(s.end.x - 12, top, 5, bottom - top)
		draw_rect(track, Color(1, 1, 1, 0.06))
		var h := track.size.y * track.size.y / (track.size.y + max_scroll)
		draw_rect(Rect2(track.position.x, track.position.y + (track.size.y - h) * trophy_scroll / max_scroll, 5, h), Color("b798ec"))


func _progress_text(q: Dictionary, progress: Vector2) -> String:
	var stat: String = q.get("stat", "")
	if stat.ends_with("seconds") or stat.begins_with("diff_time") or stat.begins_with("strain_time"):
		return "%d:%02d / %d:%02d" % [int(progress.x) / 60, int(progress.x) % 60, int(progress.y) / 60, int(progress.y) % 60]
	return "%d / %d" % [int(progress.x), int(progress.y)]


func _draw_instinct() -> void:
	var s := sheet_rect()
	var level := _instinct_level()
	var info: Dictionary = meta.INSTINCT
	var c := Vector2(_cx(), s.position.y + 420)
	for i in 5:
		draw_circle(c, 210 - i * 26, Color(CYAN, 0.03 + i * 0.012))
	draw_arc(c, 170, 0, TAU, 80, Color(CYAN, 0.5), 3, true)
	# Level ring: ten segments fill up, then start again.
	var filled := level % 10
	for i in 10:
		var a0 := -PI * 0.5 + i * TAU / 10.0 + 0.04
		_ring_sector(c, 180, 204, a0, a0 + TAU / 10.0 - 0.08, CYAN if i < filled else Color("1f3a36"))
	_mawling_head(c + Vector2(-8, -30), 70, Color("ff9a4a"))
	_text("STUFE", c + Vector2(0, 74), 22, Color("bfeee6"), true)
	_text("%d" % level, c + Vector2(0, 140), 72, Color.WHITE, true, 8)
	var bonus := float(info.get("bonus", 0.01)) * level * 100.0
	_text("+%d %% SCHADEN  ·  +%d %% BIOMASSE" % [roundi(bonus), roundi(bonus)], Vector2(_cx(), s.position.y + 700), 30, Color("c9f5ec"), true, 5)
	_text(info.get("description", ""), Vector2(_cx(), s.position.y + 746), 21, Color("d9ceb0"), true)
	var cost := _instinct_cost()
	var buy := instinct_buy_rect()
	var affordable: bool = profile.essence >= cost
	_frame(buy.grow(8), Color(WARM, 0.12 * _pulse(2.0) if affordable else 0.0), Color(WARM, 0.0), 0)
	_frame(buy, Color("8a3a18") if affordable else Color("1e2823"), WARM if affordable else Color("596158"), 1 | 2, 4.0)
	_text("STÄRKEN", Vector2(buy.get_center().x, buy.position.y + 50), 36, Color.WHITE if affordable else Color("a3aa9f"), true, 5)
	var cost_text := "%d" % cost
	var w := _text_width(cost_text, 30)
	_essence_drop(Vector2(buy.get_center().x - w * 0.5 - 12, buy.position.y + 90), 11, CYAN if affordable else Color("7d8e89"))
	_text(cost_text, Vector2(buy.get_center().x - w * 0.5 + 10, buy.position.y + 104), 30, Color.WHITE if affordable else Color("a3aa9f"))
	_paragraph("Jede Stufe kostet mehr. Urinstinkt hat keine Obergrenze und lohnt sich, wenn die Brutkammer ausgebaut ist.", Vector2(_cx(), buy.end.y + 70), s.size.x - 140, 20, Color("9fb6a6"), true, 3)


func _draw_reward() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("06120ef2"))
	var center := Vector2(_cx(), size.y * 0.5)
	var panel := Rect2(center.x - 390, center.y - 640, 780, 1300)
	_frame(panel, Color("10231ef8"), GOLD, 1 | 2 | 4 | 8, 4.0)
	_skull(center + Vector2(0, -560), 34, Color("f07a4f"))
	_text("RUN BEENDET", center + Vector2(0, -470), 58, Color("f5e6ba"), true, 8)
	var strain_name: String = _strain(reward_stats.get("strain_id", "")).get("name", "")
	var diff_index := int(reward_stats.get("difficulty", 0))
	var diff_name: String = meta.DIFFICULTIES[clampi(diff_index, 0, meta.DIFFICULTIES.size() - 1)].name
	_text("%s  ·  %s" % [strain_name.to_upper(), diff_name.to_upper()], center + Vector2(0, -426), 22, Color("9ed5b3"), true)
	var seconds := float(reward_stats.get("seconds", 0.0))
	_text("ÜBERLEBT", center + Vector2(0, -370), 20, Color("b6d0bc"), true)
	_text("%02d:%02d" % [int(seconds) / 60, int(seconds) % 60], center + Vector2(0, -312), 64, Color.WHITE, true, 7)
	var stats := [["MAX. SCHWARM", "%d" % int(reward_stats.get("peak_population", 0)), WARM], ["KILLS", "%d" % int(reward_stats.get("kills", 0)), CYAN], ["BOSSE", "%d" % int(reward_stats.get("bosses", 0)), Color("ffe07a")]]
	for i in stats.size():
		var tile := Rect2(center.x - 340 + i * 232, center.y - 270, 212, 104)
		_frame(tile, Color("0a1a16"), Color(stats[i][2], 0.7), 0)
		_text(stats[i][0], Vector2(tile.get_center().x, tile.position.y + 34), 17, Color("b6d0bc"), true)
		_text(stats[i][1], Vector2(tile.get_center().x, tile.position.y + 84), 40, stats[i][2], true, 4)
	# Earned currencies, big.
	_text("BEUTE FÜR DIE BRUT", center + Vector2(0, -110), 22, Color("f4c48c"), true)
	var earned := [[CYAN, "+%d" % int(reward.get("essence", 0)), "ESSENZ", "essence"], [GOLD, "+%d" % int(reward.get("crowns", 0)), "KÖNIGSZÄHNE", "crowns"]]
	for i in earned.size():
		var tile := Rect2(center.x - 340 + i * 350, center.y - 84, 330, 136)
		_frame(tile, Color(earned[i][0], 0.1), Color(earned[i][0], 0.8), 1 if i == 0 else 2, 3.0)
		var ic := tile.position + Vector2(62, 68)
		if earned[i][3] == "essence":
			_essence_drop(ic, 26, CYAN)
		else:
			_fang(ic, 30, Color("ffe7a8"))
		_text(earned[i][1], Vector2(tile.position.x + 116, tile.position.y + 80), 52, Color.WHITE, false, 6)
		_text(earned[i][2], Vector2(tile.position.x + 118, tile.position.y + 114), 18, earned[i][0])
	# New trophies; their rewards (incl. unlocks) are listed on each row.
	var y := center.y + 108
	var new_quests: Array = reward.get("new_quests", [])
	var unlocked: Array = reward.get("unlocked", [])
	if new_quests.is_empty():
		_text("Keine neuen Trophäen – die nächste Jagd wartet.", Vector2(center.x, y + 30), 21, Color("8fa597"), true)
	else:
		_text("NEUE TROPHÄEN  %d" % new_quests.size(), Vector2(center.x - 340, y), 20, Color("c9bfe3"))
		if not unlocked.is_empty():
			_text_right("%d FREIGESCHALTET" % unlocked.size(), Vector2(center.x + 340, y), 20, GOLD)
		y += 14
		var room := int((reward_button_rect().position.y - 24 - y) / 66.0)
		var visible := mini(new_quests.size(), room if new_quests.size() <= room else room - 1)
		for k in visible:
			var q: Dictionary = meta.quest(new_quests[k])
			var has_unlock: bool = not q.get("reward", {}).get("unlock", []).is_empty()
			var row := Rect2(center.x - 340, y, 680, 58)
			_frame(row, Color("2a2412") if has_unlock else Color("15291f"), Color(GOLD, 0.7) if has_unlock else Color("8fd46a", 0.6), 0, 2.0)
			_check(row.position + Vector2(30, 29), 13, GOLD if has_unlock else Color("8fd46a"))
			_text(String(q.get("name", new_quests[k])), row.position + Vector2(58, 38), 24, Color.WHITE)
			var text := _reward_text(q)
			var size_px := 18 if _text_width(text, 18) < 400 else 16
			_text_right(text, row.position + Vector2(row.size.x - 18, 37), size_px, Color("ffe7a8") if has_unlock else Color("f6cc70"))
			y += 66
		if visible < new_quests.size():
			_text("+ %d weitere in TROPHÄEN" % (new_quests.size() - visible), Vector2(center.x, y + 26), 20, Color("c9bfe3"), true)
	var button := reward_button_rect()
	_frame(button.grow(8), Color(WARM, 0.12 + 0.08 * _pulse(2.5)), Color(WARM, 0.0), 0)
	_frame(button, Color("8a3a18"), WARM, 0, 4.0)
	_text("WEITER", button.get_center() + Vector2(0, 14), 40, Color.WHITE, true, 6)


func _draw_toast() -> void:
	var w := _text_width(toast, 24) + 60
	var alpha := clampf(toast_time / 0.3, 0.0, 1.0)
	var rect := Rect2(_cx() - w * 0.5, size.y - 230, w, 64)
	_frame(rect, Color(Color("1b120c"), 0.94 * alpha), Color(WARM, alpha), 0, 3.0)
	_text(toast, Vector2(_cx(), rect.position.y + 41), 24, Color(Color("ffe2c5"), alpha), true)


const MUSIC_PATH := "res://scripts/music.gd"


# Menu theme; the run scene starts its own music.
func _start_music() -> void:
	if has_node("Music") or not ResourceLoader.exists(MUSIC_PATH):
		return
	var music: Node = load(MUSIC_PATH).new()
	music.name = "Music"
	add_child(music)
	if profile != null:
		music.set_enabled(profile.get_setting("sound"))
	music.play_menu()


const SFX_PATH := "res://scripts/sfx.gd"


# Own Sfx node for the audio pack V1 "ui" tap (no ambience in the menu).
func _start_sfx() -> void:
	if has_node("Sfx") or not ResourceLoader.exists(SFX_PATH):
		return
	var sfx: Node = load(SFX_PATH).new()
	sfx.name = "Sfx"
	add_child(sfx)
	if profile != null:
		sfx.set("sfx_enabled", profile.get_setting("sound"))


# "ui" only for taps that land on a button (not on empty space or a drag).
func _tap_sound(location: Vector2) -> void:
	var sfx := get_node_or_null("Sfx")
	if sfx == null:
		return
	for rect in _button_rects():
		if (rect as Rect2).has_point(location):
			sfx.play("ui")
			return
