extends RefCounted
## Statische Account-Daten: Stämme, Biome, Schwierigkeiten, Brutkammer-Upgrades, Trophäen-Quests.
##
## Freischalt-Token (in Quest-Belohnungen und in Profile.record_run()["unlocked"]):
##   "strain:<id>"      Stamm wird kaufbar (Königszähne)
##   "difficulty:<n>"   Schwierigkeit n wird wählbar
##   "upgrade:<id>"     Brutkammer-Upgrade wird kaufbar (z. B. attack_slot)
##   "mutation:<id>"    Wert (Level-Spur) kommt in den Angebots-Pool
##   "weapon:<id>"      Waffe kommt in die Kokon-Beute (Etappe 17)
##   "relic:<id>"       Relikt kommt in die Kokon-Beute (Etappe 17)
##   "reroll" / "banish" / "skip"   +1 pro Run
## unlock_label(token) liefert die deutsche Anzeige. Alte Token/IDs (Anlagen der
## Etappen 03–16, z. B. "mutation:graeber", "jaws") bildet migrate_id() bzw.
## migrate_token() ab; Profile.gd migriert gespeicherte Freischaltungen damit.
##
## Einzelstart (Etappe 09): jeder Stamm beginnt mit einem Mawling (dem Anführer);
## "Brutgröße" gibt +1 je Rang (max. 4 Ränge -> 5 Tiere). Da jedes Starttier jetzt
## ein großer Vorsprung ist, kostet ein Rang 150/300/600/1200 Essenz.
##
## Rüstung: Stamm-Rüstung darf negativ sein (Flinkzahn −0.1) und verrechnet sich mit Chitin;
## das Endergebnis in RunConfig.mods.armor wird auf 0.0..0.6 gekappt (keine Zusatzverluste).
## Glutmaws Rally-Bonus steht zusätzlich als mods.rally_damage (Multiplikator, sonst 1.0).

const ARSENAL = preload("res://scripts/progression/arsenal.gd")

## Etappe 17: Start-Pools der beiden Spuren. Werte: alle außer Regeneration
## (Trophäe „Zähes Herz“). Waffen/Relikte wie Arsenal.START_WEAPONS/UNLOCK_*.
const TRAIT_IDS := ["bite", "crit", "haste", "reach", "rally", "armor", "evade", "vigor", "lifesteal", "brood", "magnet", "gene", "speed", "luck"]
const START_WEAPONS := ["rudelbiss", "sporenwolke", "klauenwirbel", "giftbiss", "schallbrueller"]
const START_RELICS := ["hungerstein", "zaehe_haut", "scharfe_zaehne", "flinke_beine", "witterungsnase", "dna_splitter",
	"sporenherz", "aetzdruese", "rudelhorn", "gewitterfell", "grabkralle", "gluecksknochen",
	"blutzahn", "koenigszahnkette", "glutdruese", "zwillingsbrut", "magnetkern"]
## Alt-Name (Etappe 03–16); gleich START_WEAPONS.
const START_ATTACKS := START_WEAPONS
## Build slots (user decision 28.09.2026): attack = weapons (arsenal), trait =
## distinct stats, relic = distinct relics. Old profiles keep loading (slots are
## rebuilt here, never read from the save).
const BASE_SLOTS := {"attack": 4, "trait": 6, "relic": 6}
const BASE_REROLLS := 1
const BASE_BANISHES := 0
const BASE_SKIPS := 0
## Anzeigenamen freischaltbarer Inhalte (Menü, Belohnungen).
const MUTATION_NAMES := {"rudelbiss": "Rudelbiss", "sporenwolke": "Sporenwolke", "saeurespucker": "Säurespucker", "stachelruecken": "Stachelrücken",
	"graeber": "Gräber", "blitzbiss": "Blitzbiss", "brutsack": "Brutsack",
	"klauenwirbel": "Klauenwirbel", "giftbiss": "Giftbiss", "schallbrueller": "Schallbrüller",
	"regen": "Regeneration", "dornenhaut": "Dornenhaut", "urmutter": "Urmutter", "blutmond": "Blutmond", "schlundherz": "Schlundherz"}
## Etappe 17d: Kurztext der Stammes-Fähigkeit auf der Stammkarte (Name, Abklingzeit
## und Stamm -> Fähigkeit stehen in abilities.gd; Codex.strain_ability() fügt zusammen).
const ABILITY_TEXT := {
	"glutsprung": "8 m Sprung, beißt alles auf der Bahn",
	"sporenbombe": "Sporenwolke bremst und vergiftet",
	"panzerstoss": "Stoßwelle, danach 2 s −60 % Verluste",
	"hetzjagd": "4 s lang +70 % Tempo",
	"saeureschwall": "Säurekegel mit brennenden Pfützen",
	"schattenschleier": "3 s verlieren Gegner die Spur",
}
## Alt-IDs der Anlagen -> neue Werte (dornenhaut bleibt als Relikt-ID gleich).
const LEGACY_IDS := {"jaws": "bite", "pack": "rally", "scatter": "evade", "glutton": "brood", "lockduft": "magnet", "regeneration": "regen"}
## Etappe 17b: kein Populationslimit mehr; nur noch Deckel der Start-Population.
const MAX_POPULATION := 250
const META_ARMOR_CAP := 0.3
const ARMOR_CAP := 0.6

## Etappe 21 (stages/21_balance.md): Stammwerte auf <= 40 % Spreizung je Schwierigkeit abgestimmt
## (Glutmaw Rally 1,25, Sporling Wachstum 1,25, Knochenkiefer Tempo 0,9, Flinkzahn Tempo 1,12,
## Ätzmaul Schaden 0,95 + Panzer 0,05, Nachtmaul DNA 1,3 + Wachstum 1,1; Brutal-Flut ab 210 s).
const STRAINS := {
	"glutmaw": {
		"name": "Glutmaw", "description": "Ausgewogener Rudeljäger. Rally-Angriffe beißen 25 % härter.",
		"unlock_quest": "", "price": 0, "tint": "#d9401f", "start_population": 1,
		"signature": "rudelbiss", "rally_damage": 1.25,
		"mods": {"damage": 1.0, "armor": 0.0, "speed": 1.0, "harvest": 1.0, "dna": 1.0, "growth": 1.0}},
	"sporling": {
		"name": "Sporling", "description": "Wächst rasant und vernebelt Gegner, beißt aber schwächer.",
		"unlock_quest": "", "price": 0, "tint": "#f06aa8", "start_population": 1,
		"signature": "sporenwolke",
		"mods": {"damage": 0.85, "armor": 0.0, "speed": 1.0, "harvest": 1.0, "dna": 1.0, "growth": 1.25}},
	"knochenkiefer": {
		"name": "Knochenkiefer", "description": "Gepanzert und stachelig, dafür schwerfällig.",
		"unlock_quest": "boss_1", "price": 3, "tint": "#e9f0f8", "start_population": 1,
		"signature": "stachelruecken",
		"mods": {"damage": 1.0, "armor": 0.2, "speed": 0.9, "harvest": 1.0, "dna": 1.0, "growth": 1.0}},
	"flinkzahn": {
		"name": "Flinkzahn", "description": "Blitzschnelles Rudel mit dünner Haut.",
		"unlock_quest": "leaper_10", "price": 3, "tint": "#3f5cf0", "start_population": 1,
		"signature": "rudelbiss",
		"mods": {"damage": 1.0, "armor": -0.1, "speed": 1.12, "harvest": 1.0, "dna": 1.0, "growth": 1.0}},
	"aetzmaul": {
		"name": "Ätzmaul", "description": "Spuckt Säure aus der Distanz, im Nahkampf etwas schwächer.",
		"unlock_quest": "evo_aetzflut", "price": 5, "tint": "#f2e02a", "start_population": 1,
		"signature": "saeurespucker",
		"mods": {"damage": 0.95, "armor": 0.05, "speed": 1.0, "harvest": 1.0, "dna": 1.0, "growth": 1.0}},
	"nachtmaul": {
		"name": "Nachtmaul", "description": "Expertenstamm: klein und zerbrechlich, mutiert aber schneller.",
		"unlock_quest": "apex_3", "price": 8, "tint": "#2c2848", "start_population": 1,
		"signature": "sporenwolke",
		"mods": {"damage": 1.0, "armor": 0.0, "speed": 1.0, "harvest": 1.0, "dna": 1.3, "growth": 1.1}},
}
const STRAIN_ORDER := ["glutmaw", "sporling", "knochenkiefer", "flinkzahn", "aetzmaul", "nachtmaul"]

const BIOMES := {
	"verdant_maw": {"name": "Verdant Maw", "description": "Offene, grüne Jagdgründe.", "locked": false, "status": ""},
	"duerrschlund": {"name": "Dürrschlund", "description": "Dünen, Knochenfelder und Treibsand.", "locked": true, "status": "Moosschlund", "unlock_hint": "Besiege den Moosschlund", "unlock_stat": "total_moss"},
	"glutsumpf": {"name": "Glutsumpf", "description": "Glühender Sumpf voller Gase.", "locked": true, "status": "bald"},
}
const BIOME_ORDER := ["verdant_maw", "duerrschlund", "glutsumpf"]

## flood_start: Sekunden bis "Die Flut" (Etappe 08); die Ankündigung kommt 10 s vorher.
const DIFFICULTIES := [
	{"name": "Wild", "description": "Der normale Kreislauf der Jagd.", "enemy_hp": 1.0, "enemy_damage": 1.0,
		"pressure_doubling": 80.0, "flood_start": 270.0, "reward": 1.0, "crowns": 1, "unlock_quest": ""},
	{"name": "Brutal", "description": "Zähere, härter zuschlagende Gegner.", "enemy_hp": 1.15, "enemy_damage": 1.05,
		"pressure_doubling": 80.0, "flood_start": 210.0, "reward": 2.0, "crowns": 2, "unlock_quest": "survive_5"},
	{"name": "Apex", "description": "Nur für die stärksten Schwärme.", "enemy_hp": 1.2, "enemy_damage": 1.15,
		"pressure_doubling": 60.0, "flood_start": 180.0, "reward": 3.5, "crowns": 3, "unlock_quest": "brutal_3"},
]

## Kosten eines Rangs r (0-basiert, also der nächste Kauf) = round(base * growth^r).
const UPGRADES := {
	"brood_size": {"name": "Brutgröße", "description": "+1 Mawling zum Start", "max": 4, "base": 150, "growth": 2.0, "requires": ""},
	"rending": {"name": "Reißkraft", "description": "+5 % Schaden", "max": 10, "base": 40, "growth": 1.5, "requires": ""},
	"chitin": {"name": "Chitin", "description": "+3 % Panzer (max. 30 %)", "max": 10, "base": 45, "growth": 1.5, "requires": ""},
	"sprinter": {"name": "Sprinter", "description": "+3 % Tempo", "max": 8, "base": 35, "growth": 1.5, "requires": ""},
	"digestion": {"name": "Verdauung", "description": "+6 % Biomasse je Kristall", "max": 10, "base": 40, "growth": 1.5, "requires": ""},
	# Etappe 16: größerer Magnetradius für Beute-Kristalle.
	"witterung": {"name": "Witterung", "description": "+8 % Sammelradius", "max": 5, "base": 60, "growth": 1.6, "requires": ""},
	"geneflow": {"name": "Genfluss", "description": "+6 % DNA", "max": 10, "base": 50, "growth": 1.5, "requires": ""},
	"attack_slot": {"name": "Waffenplatz", "description": "+1 Platz für Waffen", "max": 1, "base": 2500, "growth": 1.0, "requires": "survive_10"},
	# Etappe 17: Werte haben kein Platzlimit mehr; die ID bleibt für gespeicherte Profile
	# und gibt jetzt +1 Neu würfeln je Rang.
	"trait_slot": {"name": "Mutationswurf", "description": "+1 Neu würfeln pro Run", "max": 2, "base": 800, "growth": 2.0, "requires": ""},
}
const UPGRADE_ORDER := ["brood_size", "rending", "chitin", "sprinter", "digestion", "witterung", "geneflow", "attack_slot", "trait_slot"]
const INSTINCT_ID := "instinct"
const INSTINCT := {"name": "Urinstinkt", "description": "Endlos: je Stufe +1 % Schaden und Biomasse", "base": 500, "step": 50, "bonus": 0.01}

## Quest-Statistiken (Profile.quest_value):
##   best_seconds, best_peak, best_no_rally_seconds, runs,
##   total_kills, total_prey, total_hunters, total_skitters, total_leapers, total_bosses,
##   total_evolutions, total_biomass, evo:<id>, diff_time:<n>, strain_time:<id>
const QUESTS := [
	{"id": "survive_1", "name": "Erste Minute", "description": "Überlebe 60 Sekunden.", "stat": "best_seconds", "target": 60, "reward": {"essence": 50}},
	{"id": "survive_3", "name": "Zäher Schwarm", "description": "Überlebe 3 Minuten.", "stat": "best_seconds", "target": 180, "reward": {"essence": 100}},
	{"id": "survive_5", "name": "Fünf Minuten Hunger", "description": "Überlebe 5 Minuten.", "stat": "best_seconds", "target": 300, "reward": {"crowns": 1, "unlock": ["difficulty:1"]}},
	{"id": "survive_10", "name": "Unersättlich", "description": "Überlebe 10 Minuten.", "stat": "best_seconds", "target": 600, "reward": {"crowns": 2, "unlock": ["upgrade:attack_slot"]}},
	{"id": "survive_15", "name": "Uralter Schwarm", "description": "Überlebe 15 Minuten.", "stat": "best_seconds", "target": 900, "reward": {"crowns": 3}},
	{"id": "peak_50", "name": "Rudel", "description": "Erreiche 50 Mawlings gleichzeitig.", "stat": "best_peak", "target": 50, "reward": {"essence": 80}},
	{"id": "peak_100", "name": "Horde", "description": "Erreiche 100 Mawlings gleichzeitig.", "stat": "best_peak", "target": 100, "reward": {"unlock": ["weapon:stachelruecken"]}},
	{"id": "peak_200", "name": "Flut", "description": "Erreiche 200 Mawlings gleichzeitig.", "stat": "best_peak", "target": 200, "reward": {"crowns": 2}},
	# Etappe 17b: kein Limit mehr - "Die volle Brut" in Stufen.
	{"id": "peak_250", "name": "Die volle Brut I", "description": "Erreiche 250 Mawlings gleichzeitig.", "stat": "best_peak", "target": 250, "reward": {"crowns": 3}},
	{"id": "peak_500", "name": "Die volle Brut II", "description": "Erreiche 500 Mawlings gleichzeitig.", "stat": "best_peak", "target": 500, "reward": {"crowns": 3, "essence": 200}},
	{"id": "peak_1000", "name": "Die volle Brut III", "description": "Erreiche 1.000 Mawlings gleichzeitig.", "stat": "best_peak", "target": 1000, "reward": {"crowns": 5}},
	{"id": "kills_100", "name": "Erste Beute", "description": "Erlege insgesamt 100 Tiere.", "stat": "total_kills", "target": 100, "reward": {"essence": 100}},
	{"id": "kills_500", "name": "Jagdrausch", "description": "Erlege insgesamt 500 Tiere.", "stat": "total_kills", "target": 500, "reward": {"unlock": ["weapon:saeurespucker", "reroll"]}},
	{"id": "kills_2000", "name": "Schlächter", "description": "Erlege insgesamt 2000 Tiere.", "stat": "total_kills", "target": 2000, "reward": {"crowns": 2, "unlock": ["relic:blutmond"]}},
	{"id": "kills_5000", "name": "Plage", "description": "Erlege insgesamt 5000 Tiere.", "stat": "total_kills", "target": 5000, "reward": {"unlock": ["skip"]}},
	{"id": "prey_200", "name": "Weidegänger", "description": "Reiße insgesamt 200 Beutetiere.", "stat": "total_prey", "target": 200, "reward": {"essence": 100}},
	{"id": "hunter_100", "name": "Jäger der Jäger", "description": "Besiege insgesamt 100 Jäger.", "stat": "total_hunters", "target": 100, "reward": {"essence": 150}},
	{"id": "skitter_10", "name": "Krabbelzeug", "description": "Besiege insgesamt 10 Skitter.", "stat": "total_skitters", "target": 10, "reward": {"essence": 100}},
	{"id": "leaper_10", "name": "Sprungfalle", "description": "Besiege insgesamt 10 Mire Leaper.", "stat": "total_leapers", "target": 10, "reward": {"essence": 120, "unlock": ["strain:flinkzahn"]}},
	{"id": "boss_1", "name": "Königsmord", "description": "Besiege den Bog King.", "stat": "total_bosses", "target": 1, "reward": {"crowns": 1, "unlock": ["strain:knochenkiefer"]}},
	{"id": "boss_5", "name": "Kronensammler", "description": "Besiege den Bog King 5-mal.", "stat": "total_bosses", "target": 5, "reward": {"crowns": 3, "unlock": ["relic:urmutter"]}},
	{"id": "boss_20", "name": "Sumpfherrscher", "description": "Besiege den Bog King 20-mal.", "stat": "total_bosses", "target": 20, "reward": {"unlock": ["banish"]}},
	{"id": "evolutions_5", "name": "Formwandler", "description": "Wähle insgesamt 5 Evolutionen.", "stat": "total_evolutions", "target": 5, "reward": {"unlock": ["banish"]}},
	{"id": "evo_aetzflut", "name": "Ätzflut", "description": "Entfessle die Evolution Ätzflut.", "stat": "evo:aetzflut", "target": 1, "reward": {"essence": 200, "unlock": ["strain:aetzmaul"]}},
	{"id": "evo_meute", "name": "Meute", "description": "Entfessle die Evolution Meute.", "stat": "evo:meute", "target": 1, "reward": {"essence": 200, "crowns": 2}},
	# Etappe 10 (INHALT): Freischaltung der neuen Formen/Anlagen und Evolutions-Trophäen.
	{"id": "form_graeber", "name": "Wühlarbeit", "description": "Besiege insgesamt 40 Skitter.", "stat": "total_skitters", "target": 40, "reward": {"essence": 120, "unlock": ["weapon:graeber"]}},
	{"id": "form_blitzbiss", "name": "Kettenreaktion", "description": "Besiege insgesamt 250 Jäger.", "stat": "total_hunters", "target": 250, "reward": {"essence": 150, "unlock": ["weapon:blitzbiss"]}},
	{"id": "form_brutsack", "name": "Brutpflege", "description": "Erreiche 150 Mawlings gleichzeitig.", "stat": "best_peak", "target": 150, "reward": {"essence": 150, "unlock": ["weapon:brutsack"]}},
	{"id": "trait_regeneration", "name": "Zähes Herz", "description": "Überlebe 7 Minuten.", "stat": "best_seconds", "target": 420, "reward": {"essence": 150, "unlock": ["mutation:regen"]}},
	{"id": "trait_dornenhaut", "name": "Dornige Haut", "description": "Besiege insgesamt 30 Mire Leaper.", "stat": "total_leapers", "target": 30, "reward": {"essence": 150, "unlock": ["relic:dornenhaut"]}},
	{"id": "evo_erdbeben", "name": "Erdbeben", "description": "Entfessle die Evolution Erdbeben.", "stat": "evo:erdbeben", "target": 1, "reward": {"essence": 200, "crowns": 2}},
	{"id": "evo_sturmrudel", "name": "Sturmrudel", "description": "Entfessle die Evolution Sturmrudel.", "stat": "evo:sturmrudel", "target": 1, "reward": {"essence": 200, "crowns": 2}},
	# Etappe 17: neue Evolutionen.
	{"id": "evo_pilzreich", "name": "Pilzreich", "description": "Entfessle die Evolution Pilzreich.", "stat": "evo:pilzreich", "target": 1, "reward": {"essence": 200, "crowns": 2}},
	{"id": "evo_dornenwall", "name": "Dornenwall", "description": "Entfessle die Evolution Dornenwall.", "stat": "evo:dornenwall", "target": 1, "reward": {"essence": 200, "crowns": 2}},
	{"id": "no_rally_2", "name": "Stille Jagd", "description": "Überlebe 2 Minuten, ohne Rally zu nutzen.", "stat": "best_no_rally_seconds", "target": 120, "reward": {"essence": 150}},
	{"id": "brutal_3", "name": "Brutal", "description": "Überlebe 3 Minuten auf Brutal.", "stat": "diff_time:1", "target": 180, "reward": {"crowns": 2, "unlock": ["difficulty:2"]}},
	{"id": "apex_3", "name": "Apex", "description": "Überlebe 3 Minuten auf Apex.", "stat": "diff_time:2", "target": 180, "reward": {"crowns": 3, "unlock": ["strain:nachtmaul"]}},
	{"id": "strain_glutmaw", "name": "Glutmaw-Meister", "description": "Überlebe 3 Minuten mit Glutmaw.", "stat": "strain_time:glutmaw", "target": 180, "reward": {"essence": 150}},
	{"id": "strain_sporling", "name": "Sporling-Meister", "description": "Überlebe 3 Minuten mit Sporling.", "stat": "strain_time:sporling", "target": 180, "reward": {"essence": 150}},
	{"id": "strain_knochenkiefer", "name": "Knochenkiefer-Meister", "description": "Überlebe 3 Minuten mit Knochenkiefer.", "stat": "strain_time:knochenkiefer", "target": 180, "reward": {"crowns": 1}},
	{"id": "strain_flinkzahn", "name": "Flinkzahn-Meister", "description": "Überlebe 3 Minuten mit Flinkzahn.", "stat": "strain_time:flinkzahn", "target": 180, "reward": {"crowns": 1}},
	{"id": "strain_aetzmaul", "name": "Ätzmaul-Meister", "description": "Überlebe 3 Minuten mit Ätzmaul.", "stat": "strain_time:aetzmaul", "target": 180, "reward": {"crowns": 1}},
	{"id": "strain_nachtmaul", "name": "Nachtmaul-Meister", "description": "Überlebe 3 Minuten mit Nachtmaul.", "stat": "strain_time:nachtmaul", "target": 180, "reward": {"crowns": 2}},
	{"id": "biomass_1000", "name": "Vollgefressen", "description": "Sammle insgesamt 1000 Biomasse.", "stat": "total_biomass", "target": 1000, "reward": {"essence": 100}},
	{"id": "biomass_10000", "name": "Nimmersatt", "description": "Sammle insgesamt 10000 Biomasse.", "stat": "total_biomass", "target": 10000, "reward": {"crowns": 1}},
	{"id": "runs_10", "name": "Zehn Bruten", "description": "Spiele 10 Runs.", "stat": "runs", "target": 10, "reward": {"unlock": ["reroll"]}},
	# Etappe 10 (APEX): Moosschlund, Migration, Glutsumpf.
	{"id": "apex_moosschlund", "name": "Moosschlund bezwungen", "description": "Besiege den Moosschlund.", "stat": "total_moss", "target": 1, "reward": {"crowns": 2, "essence": 200, "unlock": ["relic:schlundherz"]}},
	{"id": "migration_1", "name": "Migration", "description": "Wandere durch den Migrationsschlund in ein neues Biom.", "stat": "total_migrations", "target": 1, "reward": {"crowns": 1, "essence": 150}},
	{"id": "glutsumpf_2", "name": "Glutherz", "description": "Überlebe 2 Minuten im Glutsumpf.", "stat": "biome_time:glutsumpf", "target": 120, "reward": {"crowns": 2}},
	{"id": "apex_sandwurm", "name": "Sandwurm bezwungen", "description": "Besiege den Sandwurm im Dürrschlund.", "stat": "total_worms", "target": 1, "reward": {"crowns": 3, "essence": 250}},
	{"id": "apex_aschenkroete", "name": "Aschenkröte bezwungen", "description": "Besiege die Aschenkröte im Glutsumpf.", "stat": "total_toads", "target": 1, "reward": {"crowns": 3, "essence": 300}},
]

static func quest(id: String) -> Dictionary:
	for q in QUESTS:
		if q.id == id:
			return q
	return {}

static func unlock_label(token: String) -> String:
	var parts := token.split(":", true, 1)
	var kind := parts[0]
	var arg := parts[1] if parts.size() > 1 else ""
	match kind:
		"strain":
			return "Stamm kaufbar: %s" % STRAINS.get(arg, {}).get("name", arg)
		"difficulty":
			var index := int(arg)
			return "Schwierigkeit: %s" % (DIFFICULTIES[index].name if index >= 0 and index < DIFFICULTIES.size() else arg)
		"upgrade":
			return "Upgrade kaufbar: %s" % UPGRADES.get(arg, {}).get("name", arg)
		"mutation":
			return "Neuer Wert: %s" % MUTATION_NAMES.get(migrate_id(arg), migrate_id(arg))
		"weapon":
			return "Neue Waffe: %s" % MUTATION_NAMES.get(arg, arg)
		"relic":
			return "Neues Relikt: %s" % MUTATION_NAMES.get(arg, arg)
		"reroll":
			return "+1 Neu würfeln pro Run"
		"banish":
			return "+1 Verbannen pro Run"
		"skip":
			return "+1 Überspringen pro Run"
	return token


## Etappe 17: alte Anlagen-ID -> neuer Wert (sonst unverändert).
static func migrate_id(id: String) -> String:
	return String(LEGACY_IDS.get(id, id))


## Etappe 17: altes Freischalt-Token -> neues ("mutation:graeber" -> "weapon:graeber",
## "mutation:dornenhaut" -> "relic:dornenhaut", "mutation:regeneration" -> "mutation:regen").
static func migrate_token(token: String) -> String:
	var parts := token.split(":", true, 1)
	if parts.size() < 2 or parts[0] != "mutation":
		return token
	var id := migrate_id(parts[1])
	if ARSENAL.is_weapon(id):
		return "weapon:" + id
	if ARSENAL.is_relic(id):
		return "relic:" + id
	return "mutation:" + id


## Etappe 17: alle IDs, die ein Run ohne Freischaltung kennt (Werte, Waffen, Relikte).
static func start_pool() -> Array:
	var ids: Array = []
	ids.append_array(TRAIT_IDS)
	ids.append_array(START_WEAPONS)
	ids.append_array(START_RELICS)
	return ids
