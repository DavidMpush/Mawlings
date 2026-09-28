# Etappe 24 – Einstieg für die neuen Systeme

**Ziel:** Kokons, Bernstein, Power-ups, Schreine, XP-Balken, Anführer-LP, Erkundung und die Wüste erklären sich beim ersten Auftreten mit einem kurzen Tipp im Kit-Stil. Dazu kommen Glutsumpf-Ambience und ein Klang für die Lava-Ausbrüche.

## Abnahmekriterien
- Einmalige Tipps zum richtigen Moment, gespeichert im Profil (`seen_tips`).
- Nie mehr als ein Tipp gleichzeitig, mit Mindestabstand; die Bildmitte bleibt frei.
- Tipps lassen sich in den Einstellungen zurücksetzen.
- Zustände nur über vorhandene öffentliche Felder lesen; `hunt_world.gd` und die Balance-Dateien bleiben unberührt.
- Glutsumpf-Ambience als Loop, Lava-Ausbruch mit Warnung und Einschlag.
- Tests `onboarding`, `sfx` und `sfx_hooks` grün; Captures angesehen.

## Tipps (`scripts/onboarding.gd`)

| ID | Moment (Auslöser) | Text | Verschwindet |
|---|---|---|---|
| `amber` | erste Bernstein-Münze eingesammelt (`model.amber_collected > 0`) | „Bernstein! Mit den Münzen kaufst du Kokons“ | nach 6 s |
| `cocoon` | geschlossener Kokon (Karte, Gold, Elite, Start) ≤ 16 m | „Kokon! Bleib im Kreis, bis er aufgeht – der Preis in Bernstein steht darüber“ | Kokon öffnet oder Schwarm entfernt sich |
| `boss_cocoon` | Boss-Kokon ≤ 16 m | „Boss-Kokon! Gratis öffnen – du wählst 1 aus 3 Beuten“ | wie oben |
| `powerup` | liegendes Power-up ≤ 12 m | „Power-up! Lauf hinein – es wirkt ein paar Sekunden“ | aufgenommen (`powerups.collected`) |
| `shrine` | unfertiger Schrein ≤ 16 m | „Schrein! Bleib darin, bis er voll ist – er schenkt einen seltenen Wert“ | Ladung > 30 % |
| `ability` | gibt es seit 17d (bereit, nach 20 s, Gegner nah) | unverändert | Fähigkeit benutzt; **neu:** der Tipp zeigt mit Pfeil und Ring auf den Knopf |
| `xp` | erste DNA vor dem ersten Level (`evolution.dna > 0`, `level == 0`) | „Der Balken oben füllt sich mit DNA – voll heißt neue Mutation“ | Level 1 erreicht |
| `leader_low` | Anführer auf 1 LP (max. > 1) | „Anführer auf 1 LP! Lebensraub heilt beim Beißen – weich Treffern aus“ | LP > 1 |
| `explore` | nach 25 s eine Landmarke ≤ 20 m (`arena.landmark` der 3 × 3 Chunks) | „Erkunde! Der Nebel verbirgt Kokons, Schreine und Bosse“ | neue Region betreten (`regions_seen`) |
| `quicksand` | Schwarm im Treibsand (`arena.quicksand_factor < 0.95`) | „Treibsand bremst – raus auf festen Sand“ | raus aus dem Sand |
| `sandstorm` | Sandsturm kündigt sich an oder weht (nur im Dürrschlund) | „Sandsturm zieht auf – Gegner werden schneller, bleib in Bewegung“ | Sturm vorbei |

- **Reihenfolge (Priorität):** Gefahr zuerst: `move`, `warning`, `leader`, `leader_low`, `boss`, `rally`, `ability`, `sandstorm`, `quicksand`. Danach Ressourcen und Orte: `prey`, `corpse`, `amber`, `boss_cocoon`, `cocoon`, `powerup`, `shrine`, `alpha`, `xp`, `mutation`, `nest`, `explore`, `map`.
- **Regeln** bleiben wie in Etappe 06:
  - ein Tipp zur Zeit, mindestens 4 s Abstand, 6 s Anzeige, frühestens nach 1,6 s ausgeblendet, wenn erfüllt
  - jeder Tipp einmal pro Profil, beim Zeigen gespeichert
  - das Tipp-Panel sitzt über den Bedienelementen, die Bildmitte bleibt frei
- **Symbole und Farben** (`hud_controls.gd` `TIP_ICONS` und `_tip_plate_tone`):

  | Tipp | Symbol | Farbe |
  |---|---|---|
  | Bernstein | Königszahn | Gold |
  | Kokons | Kokon | Gold |
  | Power-up | Rausch-Symbol | Grün |
  | Schrein | Schrein | Violett |
  | XP | Evo-Abzeichen | Violett |
  | Anführer schwach | Regeneration | Rot |
  | Erkunden | Karte | Blau |
  | Treibsand | Tempo | Rot |
  | Sandsturm | Hast | Rot |
- **Einstellungen:** Knopf „TIPPS ZURÜCKSETZEN“ unter dem UI-Stil (Brawl und Ruhig). Er leert `profile.seen_tips` (neu: `profile.reset_tips()`) und bestätigt mit einer Toast-Meldung. Das Panel ist 116 px höher; TAGES-BRUT liegt weiter außerhalb.
- **Hooks in `hunt_world.gd`:** keine nötig. Alle Auslöser lesen vorhandene öffentliche Felder:
  - aus der Welt: `model`, `chests`, `powerups`, `shrines`, `evolution`, `regions_seen`, `desert.storm`
  - die Arena über `Main/Arena`
- **Grenze:** Der Boss-Kokon-Tipp erscheint, wenn der Kokon in Sicht liegt. Während der 1-aus-3-Wahl selbst ruht die Welt, dort zeigt das Onboarding (wie bei allen Tipps) nichts Neues an.

## Glutsumpf-Audio
- `tools/gen_sfx.py` `SOUNDS_24`:
  - `ambience_glutsumpf`: 10-s-Loop mit tiefem Lava-Grollen, Blubbern, Dampfzischen und leisem Knistern.
  - `lava_warn`: 1,6 s wie der Bodenring; steigendes Grollen mit immer schnellerem Blubbern.
  - `lava_burst`: Knall, heißer Aufwind, spritzende Lava, Zischen.
- Pegel (lautestes 300-ms-Fenster + `db`):
  - `lava_warn` ≈ −21 dB, wie `warn`
  - `lava_burst` ≈ −15 dB, über dem geliehenen `stomp`, den HuntWorld zusätzlich spielt
  - Ambience wie die anderen Betten
- **Anbindung:**
  - `eruptions.gd`: nur Sound-Zeilen; `lava_warn` beim Ankündigen, `lava_burst` beim Ausbruch.
  - `sfx.gd`: `AMBIENCES.ambience_glutsumpf`.
  - `desert_run.gd`: wählt das Bett je Biom (Dschungel, Wüste, Glutsumpf).
- **Musik:** Im Glutsumpf läuft weiter die klassische Musik. Ein eigener Stem-Satz wäre ohne Hörprobe nicht sicher gut genug gewesen.
- **Optionaler Hook** (nach der Balance-Runde): in `hunt_world.gd` beim Ausbruch `_sfx("stomp", 60)` streichen oder leiser machen, da `lava_burst` jetzt den Einschlag trägt. Die Vibration kann bleiben.

## Tests und Bilder
- `tests/onboarding.gd` prüft für jeden neuen Tipp: Definition, Reihenfolge und ein vorhandenes Symbol. Dazu, mit frischem Profil, dass der Tipp:
  - vorher nicht erscheint
  - im Moment erscheint, mit Text und Symbol am HUD
  - danach verschwindet und nur einmal gezeigt wird

  Weiter prüft er: bei zwei fälligen Tipps kommt der höhere zuerst, der zweite nach dem Abstand; kein Sandsturm-Tipp außerhalb der Wüste. Der Reset-Knopf liegt im Panel, ist ≥ 96 px, leert das Profil und zeigt einen Toast.
- `tests/sfx.gd`: `lava_warn`/`lava_burst` in den Regeln mit eigenen Dateien, Glutsumpf-Bett und Überblendung.
- `tests/sfx_hooks.gd`: Run im Glutsumpf → Bett `ambience_glutsumpf`, Ausbruch → `lava_warn`, danach `lava_burst`.
- Captures, angesehen:
  - `previews/preview_tips_sheet.png` und `preview_tip_<id>.png`, neu per `tests/capture_onboarding_tips.gd`. Alle zehn Tipps sind lesbar und höchstens zweizeilig; der Fähigkeits-Tipp zeigt auf den Knopf.
  - `preview_ui_menu_sheets_settings(_calm)(_540).png` mit dem neuen Knopf.

Vollständiger Lauf `tools/test.ps1`: **ALL PASS** (28.09.2026, nach der Balance-Runde).

## Offen
- Hörprobe der Glutsumpf-Klänge am Gerät.
- Eigene Glutsumpf-Musik, falls gewünscht.
- Tipps während der Kokon-Wahl selbst, falls gewünscht; das wäre ein Hook im Auswahlbildschirm.
