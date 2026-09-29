extends RefCounted
## KODEX (Sammlung, wie in Megabonk / LoL Swarm) und die Stammes-Fähigkeit fürs Menü.
##
## Fünf Kategorien: Waffen (inkl. Evolutionen), Relikte, Werte, Power-ups, Bosse.
## Ein Eintrag gilt als entdeckt, sobald er einmal in einem Run erhalten bzw.
## besiegt wurde. Das Profil speichert Schlüssel "<art>:<id>" in `codex_seen`
## (weapon:, relic:, stat:, powerup:, boss:); keys_from_result() liest sie aus
## einem RunStats-Dictionary (stages/03_progression.md):
##   mutations {id: Rang}   Werte und Waffen (evolution.ranks)
##   evolutions [id]        Evolutionen
##   relics {id: Stapel}    Relikte            (optional, Hook in HuntWorld.run_stats)
##   powerups_taken [id]    Power-ups          (optional, Hook, Powerups.taken)
##   bosses / apex_kills / worm_kills / toad_kills   besiegte Bosse
## Die Katalogdaten kommen aus den Spieltabellen (Arsenal, Stats, Powerups,
## Evolution-Symbole, Abilities); nichts ist doppelt gepflegt außer den Kurztexten.

const ARSENAL = preload("res://scripts/progression/arsenal.gd")
const STATS = preload("res://scripts/progression/stats.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const DATA = preload("res://scripts/meta/meta_data.gd")
## Stage 33: Mutationskerne catalogue (ORDER, CORES, DEFAULT_UNLOCKED).
const CORES = preload("res://scripts/progression/cores.gd")
const POWERUPS_PATH := "res://scripts/powerups.gd"
const ABILITIES_PATH := "res://scripts/abilities.gd"
const EVOLUTION_PATH := "res://scripts/evolution.gd"

## Stage 33: "cores" (Mutationskerne); a core counts as discovered once it is
## unlocked (Profile.cores_unlocked keeps codex_seen in sync) or taken in a run.
## Core icons are "core:<id>" (drawn procedurally by ui/core_plaque.gd).
const CATEGORIES := ["weapons", "relics", "cores", "stats", "powerups", "bosses"]
const CATEGORY_NAMES := {"weapons": "WAFFEN", "relics": "RELIKTE", "cores": "KERNE", "stats": "WERTE", "powerups": "POWER-UPS", "bosses": "BOSSE"}
## Symbol und Kit-Ton je Kategorie (Segmente im KODEX-Blatt).
const CATEGORY_ICONS := {"weapons": "rudelbiss", "relics": "crown", "cores": "core:", "stats": "jaws", "powerups": "pu_raserei", "bosses": "bog_king"}
const CATEGORY_TONES := {"weapons": "ember", "relics": "loot", "cores": "special", "stats": "info", "powerups": "action", "bosses": "danger"}
## Wo man Unentdecktes findet (Text unter „???“).
const CATEGORY_HINTS := {
	"weapons": "Steckt in Kokons.",
	"evolved": "Entsteht aus Waffe Rang 5 + passendem Relikt.",
	"relics": "Steckt in Kokons und Boss-Kokons.",
	"cores": "Wird über eine Trophäe freigeschaltet.",
	"stats": "Kommt mit der Werte-Wahl beim Level-Aufstieg.",
	"powerups": "Lassen Mini-Bosse fallen.",
	"bosses": "Wartet im Biom %s.",
}
const STAT_CATEGORY := {"attack": ["ANGRIFF", "ember"], "protect": ["SCHUTZ", "info"], "growth": ["WACHSTUM", "action"], "special": ["SPEZIAL", "special"]}
## Power-up-Wirkung in einem Satz (Name/Dauer/Symbol kommen aus Powerups.DEFS).
const POWERUP_TEXT := {
	"rausch": "Der Schwarm läuft 45 % schneller.",
	"blutrausch": "Waffen laden 40 % schneller nach.",
	"magnetsturm": "Dreifacher Sammelradius für Kristalle und Münzen.",
	"chitinschild": "Kaum Verluste, der Anführer ist unverwundbar.",
	"raserei": "Doppelter Schaden für den ganzen Schwarm.",
	"brutwelle": "Sofort drei Zellteilungen: +3 Tiere.",
}
## Bosse: id, Name, Art, Biom, Text, Symbol, Rekord-Zähler im Profil.
const BOSSES := [
	["bog_king", "Bog King", "MINI-BOSS", "Verdant Maw", "Stampft Schockwellen durch den Sumpf.", "portrait_bog_king", "total_bosses"],
	["moosschlund", "Moosschlund", "APEX", "Verdant Maw", "Uralter Schlund aus Moos, Tor zur Wüste.", "portrait_apex", "total_moss"],
	["sandwurm", "Sandwurm", "APEX", "Dürrschlund", "Taucht ab und bricht unter dir hervor.", "portrait_apex_sandworm", "total_worms"],
	["aschenkroete", "Aschenkröte", "APEX", "Glutsumpf", "Speit Glut, der Boden brennt.", "portrait_apex_toad", "total_toads"],
]

static var _powerups: Script = null
static var _abilities: Script = null
static var _evolution: Script = null


static func _script(path: String) -> Script:
	return load(path) if ResourceLoader.exists(path) else null


static func powerup_defs() -> Dictionary:
	if _powerups == null:
		_powerups = _script(POWERUPS_PATH)
	return _powerups.DEFS if _powerups != null else {}


static func powerup_order() -> Array:
	if _powerups == null:
		_powerups = _script(POWERUPS_PATH)
	return Array(_powerups.ORDER) if _powerups != null else []


## Symbol-ID eines Waffen-/Relikt-/Wert-Eintrags (Evolution.ICON_IDS, sonst die ID).
static func icon_for(id: String) -> String:
	if _evolution == null:
		_evolution = _script(EVOLUTION_PATH)
	if _evolution != null:
		return String(_evolution.ICON_IDS.get(id, id))
	return id

# ---------------------------------------------------------------- Stammes-Fähigkeit

## {id, name, text, cooldown, icon} der aktiven Fähigkeit eines Stammes (Etappe 17d);
## leer, wenn abilities.gd fehlt oder den Stamm nicht kennt.
static func strain_ability(strain: String) -> Dictionary:
	if _abilities == null:
		_abilities = _script(ABILITIES_PATH)
	if _abilities == null:
		return {}
	var id := String(_abilities.STRAIN_ABILITY.get(strain, ""))
	var def: Dictionary = _abilities.DEFS.get(id, {})
	if def.is_empty():
		return {}
	return {"id": id, "name": String(def.get("name", id)), "text": String(DATA.ABILITY_TEXT.get(id, "")),
		"cooldown": float(def.get("cooldown", 0.0)), "icon": String(def.get("icon", ""))}

# ---------------------------------------------------------------- Katalog

## Einträge einer Kategorie: [{key, id, name, text, sub, chip, tone, icon, hint}].
## `chip`/`tone` = Seltenheit bzw. Art; `sub` = Zusatzzeile (Rezept, Biom).
static func entries(category: String) -> Array:
	var out: Array = []
	match category:
		"weapons":
			for row in ARSENAL.WEAPONS:
				out.append(_entry("weapon", row[0], row[1], row[2], "WAFFE", "ember", icon_for(row[0]), ""))
			for row in ARSENAL.EVOLVED:
				var rule: Dictionary = ARSENAL.rule_for(row[0])
				var sub := ""
				if not rule.is_empty():
					sub = "%s Rang 5 + %s" % [String(ARSENAL.info(rule.base)[1]), String(ARSENAL.info(rule.partner)[1])]
				out.append(_entry("weapon", row[0], row[1], row[2], "EVOLUTION", "special", icon_for(row[0]), sub))
		"relics":
			for row in ARSENAL.RELICS:
				var rarity := String(row[3])
				# Stage 28: chip and tone from the central rarity token (rarity id = kit tone).
				out.append(_entry("relic", row[0], row[1], row[2], UiStyle.rarity_name(rarity), rarity if UiStyle.RARITY_TONES.has(rarity) else "common", icon_for(row[0]), ""))
		"cores":
			# Stage 33: "+ bonus" as text, "− price" as the coloured sub line.
			for id in CORES.ORDER:
				var d: Dictionary = CORES.definition(id)
				out.append(_entry("core", id, String(d.get("name", id)), "+ " + String(d.get("plus", "")), "KERN", "legendary", "core:" + String(id), "− " + String(d.get("minus", ""))))
		"stats":
			for d in STATS.STATS:
				var cat: Array = STAT_CATEGORY.get(String(d.cat), ["WERT", "info"])
				out.append(_entry("stat", d.id, d.name, STATS.describe_step(d.id), cat[0], cat[1], icon_for(d.id), ""))
		"powerups":
			var defs := powerup_defs()
			for id in powerup_order():
				var def: Array = defs.get(id, [])
				if def.is_empty():
					continue
				var seconds := float(def[1])
				var chip := "SOFORT" if seconds <= 0.0 else "%d SEK" % roundi(seconds)
				out.append(_entry("powerup", id, def[0], String(POWERUP_TEXT.get(id, "")), chip, String(def[2]), String(def[3]), ""))
		"bosses":
			for row in BOSSES:
				var e := _entry("boss", row[0], row[1], row[4], row[2], "danger" if row[2] == "APEX" else "ember", row[5], "Biom: %s" % row[3])
				e["record"] = row[6]
				out.append(e)
	for e in out:
		var hint := String(CATEGORY_HINTS.get(category, ""))
		if e.chip == "EVOLUTION":
			hint = CATEGORY_HINTS.evolved
		elif category == "bosses":
			hint = hint % String(e.sub).trim_prefix("Biom: ")
		elif category == "cores":
			var q := core_quest(String(e.id))
			if not q.is_empty():
				hint = "Trophäe „%s“: %s" % [String(q.name), String(q.description)]
		e["hint"] = hint
	return out


## Stage 33: the trophy (DATA.QUESTS row) whose reward unlocks core `id`; {} for
## a core that is unlocked from the start.
static func core_quest(id: String) -> Dictionary:
	for q in DATA.QUESTS:
		if (q.reward.get("unlock", []) as Array).has("core:" + id):
			return q
	return {}


## Stage 33: core ids unlocked in a fresh profile (first DEFAULT_UNLOCKED).
static func default_cores() -> Array[String]:
	return CORES.default_unlocked()


static func _entry(kind: String, id: String, name: String, text: String, chip: String, tone: String, icon: String, sub: String) -> Dictionary:
	return {"key": "%s:%s" % [kind, id], "id": id, "name": name, "text": text, "sub": sub, "chip": chip, "tone": tone, "icon": icon}


## Alle Schlüssel des Katalogs (für Zähler und Tests).
static func all_keys(category: String = "") -> Array:
	var out: Array = []
	for cat in CATEGORIES:
		if category != "" and cat != category:
			continue
		for e in entries(cat):
			out.append(e.key)
	return out


## [entdeckt, gesamt] einer Kategorie ("" = alle) für eine Liste von Schlüsseln.
static func progress(seen: Array, category: String = "") -> Vector2i:
	var keys := all_keys(category)
	var found := 0
	for key in keys:
		if seen.has(key):
			found += 1
	return Vector2i(found, keys.size())

# ---------------------------------------------------------------- Entdecken

## Schlüssel aller Einträge, die ein Run (RunStats) erhalten oder besiegt hat.
static func keys_from_result(stats: Dictionary) -> Array:
	var out: Array = []
	var mutations: Variant = stats.get("mutations", {})
	if mutations is Dictionary:
		for raw in mutations:
			if int(mutations[raw]) <= 0:
				continue
			_add(out, _key_for(String(raw)))
	for id in _ids(stats.get("evolutions", [])):
		_add(out, _key_for(id))
	for id in _ids(stats.get("relics", {})):
		if ARSENAL.is_relic(id):
			_add(out, "relic:" + id)
	var defs := powerup_defs()
	for id in _ids(stats.get("powerups_taken", [])):
		if defs.has(id):
			_add(out, "powerup:" + id)
	# Stage 33: cores taken in the run.
	for id in _ids(stats.get("cores", [])):
		if CORES.has(id):
			_add(out, "core:" + id)
	for id in _ids(stats.get("bosses_seen", [])):
		_add(out, "boss:" + id)
	var worms := int(stats.get("worm_kills", 0))
	var toads := int(stats.get("toad_kills", 0))
	if int(stats.get("bosses", 0)) > 0:
		_add(out, "boss:bog_king")
	if int(stats.get("apex_kills", 0)) - worms - toads > 0:
		_add(out, "boss:moosschlund")
	if worms > 0:
		_add(out, "boss:sandwurm")
	if toads > 0:
		_add(out, "boss:aschenkroete")
	return out


## Schlüssel aus den Gesamtrekorden eines Profils (ältere Profile ohne codex_seen).
static func keys_from_records(records: Dictionary) -> Array:
	var out: Array = []
	for id in _ids(records.get("evolutions_seen", [])):
		_add(out, _key_for(id))
	for row in BOSSES:
		if int(records.get(String(row[6]), 0)) > 0:
			_add(out, "boss:" + String(row[0]))
	return out


## "weapon:<id>" / "stat:<id>" / "relic:<id>" für eine Spiel-ID (alte IDs migriert); "" = unbekannt.
static func _key_for(raw: String) -> String:
	if ARSENAL.is_weapon(raw) or ARSENAL.is_evolved(raw):
		return "weapon:" + raw
	if ARSENAL.is_relic(raw):
		return "relic:" + raw
	var id := STATS.migrate(raw)
	if STATS.has(id):
		return "stat:" + id
	return ""


static func _ids(value: Variant) -> Array:
	var out: Array = []
	if value is Dictionary:
		for k in value:
			if not (value[k] is int or value[k] is float) or float(value[k]) > 0.0:
				out.append(String(k))
	elif value is Array or value is PackedStringArray:
		for k in value:
			out.append(String(k))
	return out


static func _add(out: Array, key: String) -> void:
	if key != "" and not out.has(key):
		out.append(key)
