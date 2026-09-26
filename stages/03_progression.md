# Etappe 03 – Progression (Run + Account), Ton, Landmarken

Grundlage: Konzept „Mawlings Progression und Marke“ (https://claude.ai/artifact/9xm1akxkxRjRErjbeZX1QN). Der Nutzer hat „weiter wie besprochen“ gesagt; die Empfehlungen aus dem Konzept gelten als Arbeitsentscheidungen: Run bleibt endlos (Migration folgt in einer späteren Etappe), Meta = Trophäen (Breite) + Essenz-Upgrades (Tiefe) + Königszähne, 2 Start-Stämme, 250 Limit, F2P-fair (Monetarisierung noch nicht bauen). Feste Regeln aus `DESIGN_BRIEF.md` gelten weiter.

## Abnahmekriterien

1. **Slots:** Mutationen in zwei Arten – *Angriffsformen* (Start 2 Slots) und *Anlagen* (die sechs bisherigen Mutationen, Start 3 Slots). Angebote respektieren freie Slots; Meta kann Slots erhöhen.
2. **Angriffsformen (4):** `rudelbiss` (Rally löst periodischen Sprungangriff aus), `sporenwolke` (Aura: Schaden über Zeit + Verlangsamung), `saeurespucker` (Fernkampf-Projektile auf nächsten Gegner), `stachelruecken` (Treffer auf den Schwarm schaden dem Angreifer). Je 3 Ränge, sichtbar dargestellt.
3. **Evolutionen (2) mit Alpha-Kern:** `saeurespucker` Rang 3 + `glutton` (Vielfraß) ≥1 → `aetzflut`; `rudelbiss` Rang 3 + `pack` (Rudelinstinkt) ≥1 → `meute`. Alpha-Kern droppt vom Bog King (immer), Leaper (25 %), Jäger ab Druck ≥2 (10 %); Aufheben durch Berühren; löst die Evolution aus, wenn Bedingungen erfüllt sind, sonst wird er gelagert.
4. **Run-Konfiguration** (Stamm, Biom, Schwierigkeit, Meta-Boni) wirkt im Spiel; ohne Konfiguration startet `main.tscn` wie bisher (Tests!).
5. **Run-Statistik** am Ende an die Meta; Ergebnisbildschirm mit „NEUER RUN“ und „BRUTSTÄTTE“.
6. **Meta:** Speicherstand (`user://mawlings_profile.json`), Essenz, 8 Brutkammer-Upgrades mit steigenden Kosten, Urinstinkt-Endlosstufen, ≥30 Trophäen-Quests, Königszähne, 6 Stämme (2 frei, 4 per Quest + Kauf), Biome (Verdant Maw frei, Glutsumpf als „bald“ gesperrt), 3 Schwierigkeiten.
7. **Brutstätte (Hauptmenü):** Startbildschirm im Hochformat mit SPIELEN, Stamm-Wahl, Schwierigkeit, Brutkammer (Upgrades kaufen), Trophäen-Liste, Belohnungsanzeige nach einem Run. Projekt startet im Menü.
8. **Ton & Haptik:** prozedural erzeugte SFX (Biss, Kill-Knacken, Wachstum-Plopp, Treffer, Warnung, Stampfen, Mutation, Aussterben), gepoolte Wiedergabe mit Lautstärke-Limit, Vibration auf Mobilgeräten.
9. **Landmarken & Modelle:** Mire-Reaper-Modell für den Leaper; `root arch`, `fallen log`, `pond seeds`, `flower` als Landmarken/Deko nach Konzept V3; Karte bleibt überwiegend offen, Kollision nur wo sinnvoll und umgehbar.
10. **Technik:** alle Tests grün, neue Tests für Meta, Angriffsformen, Menüfluss; Playthrough ohne Aussterben.

## Verträge (verbindlich für parallele Arbeit)

### `scripts/meta/session.gd` (Agent META) – Übergabe zwischen Szenen
```gdscript
extends RefCounted
static var pending_config: Dictionary = {}   # vom Menü gesetzt, von Main beim Start gelesen und geleert
static var last_result: Dictionary = {}      # von Main am Run-Ende gesetzt, vom Menü gelesen und geleert
```

### RunConfig (Dictionary, Menü → Spiel; von `Profile.build_run_config` erzeugt)
```
{ strain_id: String, biome_id: String, difficulty: int (0 Wild, 1 Brutal, 2 Apex),
  start_population: int, tint: Color,
  signature_attack: String,               # Angriffsform, die mit Rang 1 startet
  mods: { damage: float, armor: float (0..0.6 Anteil), speed: float, harvest: float, dna: float, growth: float },  # Multiplikatoren (1.0 = neutral), armor additiv
  enemy_hp: float, enemy_damage: float, pressure_doubling: float,   # aus Schwierigkeit
  slots: { attack: int, trait: int }, rerolls: int, banishes: int, skips: int,
  pool: Array[String] }                    # freigeschaltete Mutations-IDs (Angriffsformen + Anlagen)
```

### RunStats (Dictionary, Spiel → Meta, in `Session.last_result`)
```
{ strain_id, biome_id, difficulty, seconds: float, peak_population: int, final_population: int,
  kills: int, kills_by_type: { prey, hunter, skitter, leaper, boss }, biomass: float, lost: int,
  bosses: int, evolutions: Array[String], mutations: Dictionary (id -> rank), used_rally: bool }
```

### `scripts/meta/profile.gd` (Agent META)
```gdscript
extends RefCounted
static func load_or_create(path := "user://mawlings_profile.json") -> RefCounted
func save() -> void
var essence: int; var crowns: int; var upgrades: Dictionary; var instinct_level: int
var unlocked_strains: Array; var owned_strains: Array; var completed_quests: Array; var records: Dictionary
func build_run_config(strain_id: String, biome_id: String, difficulty: int) -> Dictionary
func record_run(stats: Dictionary) -> Dictionary   # {essence, crowns, new_quests: Array[id], unlocked: Array[String]}
func upgrade_cost(id: String) -> int ; func buy_upgrade(id: String) -> bool
func strain_cost(id: String) -> int ; func buy_strain(id: String) -> bool
func quest_progress(id: String) -> Vector2        # (aktuell, Ziel)
```
Daten in `scripts/meta/meta_data.gd` (`STRAINS`, `BIOMES`, `DIFFICULTIES`, `UPGRADES`, `QUESTS`), alles deutsch beschriftet.

### `scripts/attack_forms.gd` (Agent FORMS) – Node3D, Kind von HuntWorld
```gdscript
func setup(world: Node3D, swarm: Node3D) -> void
func set_ranks(ranks: Dictionary) -> void          # id -> Rang (0..3); evolvierte IDs 'aetzflut','meute' als Rang 1
func step(delta: float, targets: Array, rally: bool, enemy_scale: float) -> void
    # targets: lebende Gegner/Beute (Node3D mit 'health' und optional take_damage()); reduziert NUR Gesundheit,
    # gibt nie Knoten frei; Tod behandelt HuntWorld.
func on_swarm_hit(attacker: Node3D, loss: int) -> void   # für stachelruecken
func clear() -> void                                # Projektile/Effekte bei Reset/Aussterben entfernen
const FORMS := { id: [Name, Beschreibung je Rang] }  # für UI
```
Darstellung friert ein, wenn `step` nicht gerufen wird (Pause).

### `scripts/sfx.gd` (Agent AUDIO) – Node, von Main als Kind "Sfx" angelegt
```gdscript
func play(id: String, volume_db := 0.0, pitch_jitter := 0.08) -> void   # ids: bite, kill, grow, hit, warn, stomp, mutate, evolve, extinct, pickup, ui
func vibrate(ms: int) -> void
```

## Dateibesitz dieser Etappe
- META: `scripts/meta/*`, `tests/meta.gd`
- FORMS: `scripts/attack_forms.gd`, `tests/attack_forms.gd`, `tests/capture_forms.gd`
- RUN: `scripts/evolution.gd`, `scripts/hunt_world.gd`, `scripts/swarm.gd`, `scripts/main.gd`, `scripts/tuning.gd`, `scripts/touch_controls.gd`, `scripts/run_model.gd`, bestehende Tests anpassen, `tests/run_config.gd`
- MENU: `scenes/menu.tscn`, `scripts/menu/*`, `project.godot` (nur `run/main_scene`), `tests/menu.gd`, `tests/capture_menu.gd`
- AUDIO: `tools/gen_sfx.py`, `assets/audio/*`, `scripts/sfx.gd`, `tests/sfx.gd`
- ASSETS: `tools/optimize_characters.py`, `assets/gameplay/*`, `scripts/arena.gd`, `scripts/mire_leaper.gd`, `tests/capture_landmarks.gd`
- Orchestrator: `tools/test.ps1`, SFX-Aufrufe in HuntWorld nach Abschluss von RUN, Dokumentation, Zusammenführung

## Ergebnis (26.09.2026)

Sieben parallele Agenten (META, FORMS, RUN, MENU, AUDIO, ASSETS, SEED) plus Zusammenführung durch den Orchestrator.

- **Kriterien 1–5 (Run):** Slots Angriff 2 / Anlagen 3, vier Angriffsformen, Evolutionen Ätzflut und Meute über Alpha-Kern (bleibt liegen bis aufgesammelt), Kills aus jeder Schadensquelle genau einmal, RunConfig wirkt, RunStats in `Session.last_result`, Ergebnis mit NEUER RUN / BRUTSTÄTTE.
- **Kriterien 6–7 (Meta, Menü):** Profil `user://mawlings_profile.json`, 35 Trophäen, 8 Upgrades + Urinstinkt, Königszähne, 6 Stämme (Glutmaw, Sporling frei), 3 Schwierigkeiten, Brutstätte als Startszene mit Belohnungs-Overlay.
- **Kriterium 8 (Ton):** 35 prozedurale WAVs + Dschungel-Loop, gepoolte Wiedergabe mit Ratenlimit, Vibration auf Mobilgeräten; Auslöser über Zustandswechsel in HuntWorld.
- **Kriterium 9 (Landmarken):** Mire-Reaper-Modell für den Leaper, Wurzelbogen (Durchgang frei), Baumstamm, Schilfteich, Blumenwiese.
- **Zusatz auf Nutzerwunsch – Seed-Karten:** Jeder Run aus dem Menü erhält einen Seed; Wege (Richtung, Schwung, Breite), Steingruppen, Landmarken, Deko und Bodenfarbe variieren je Region. Garantien per Test: freie Startzone 22 m, kein Hindernis auf Wegen, Durchgänge ≥ 3 m, Kollisionsanteil ≤ 12 %. Seed 0 = klassische Karte (Tests). `Profile.daily_seed()` für eine spätere Tages-Challenge.
- **Stammfarben:** `body_tint` im Shader färbt den Körper um (Glutmaw bleibt rot).
- **Tests:** 17 von 17 grün (neu: meta, attack_forms, run_config, menu, sfx; arena erweitert). Playthrough `population=215 peak=218 kills=29 lost=45` – mit Angriffsformen deutlich leichter als in Etappe 02 (54/93).

Offen: Balance (Angriffsformen zu stark für Wild), Lesbarkeit Sporling auf Grün und Flinkzahn vs. Nibbler, Blumenfarbe ähnlich Mawlings, Wegkreuzungen erzeugen teils Doppelwege, Seed-/Tages-Anzeige im Menü, kein Handtest und keine Gerätemessung.
