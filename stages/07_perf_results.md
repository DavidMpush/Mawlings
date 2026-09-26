# Etappe 07 – Leistung: Messwerte vorher/nachher

Messaufbau wie `stages/06_perf_notes.md` (Windows 11, Ryzen 5 3600, RTX 5070, OpenGL 3.3
Compatibility, Fenster 540 × 1170, Vsync aus, **Desktop-Werte, keine Android-Werte**).
Befehl: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/perf.ps1 [-Only …] [-Seconds 12]`.
Messrauschen zwischen Läufen ca. ± 0,5 ms. Die Tabelle führt PERF_WORLD; die anderen
Stränge (PERF_HUD, PERF_SWARM, APEX) tragen ihre eigenen Zeilen ein, am Ende folgt die
Gesamtmessung.

**Neu in Etappe 07:** `main.gd` wendet die Qualitätsstufe an. Am Desktop ist das HOCH
(MSAA 2×, 3D-Skalierung 1,0, 60-fps-Grenze); der Bench hebt die Grenze wieder auf und misst
dadurch mit MSAA 2×. `worst_noaa` (msaa=0) misst wie Etappe 06. Neue Varianten:
`worst_c60` (60 liegende Kadaver, langer Run), `worst_medium`, `worst_low` (Stufe erzwungen).

## Strang PERF_WORLD (Kadaver, FX-Ringe, Angriffsformen, Gegner, Ziele, Qualität)

A/B in zwei isolierten Kopien des Commits `0f1d9f9` (ohne die parallel entstehenden
Änderungen der anderen Stränge): links HEAD, rechts HEAD + nur PERF_WORLD-Dateien.
12 s je Worst Case, 6 s je Variante.

| Szene | avg ms vorher → nachher | Draw Calls | Primitive | Knoten | world-Geometrie* |
|---|---:|---:|---:|---:|---:|
| Worst Case (30 Kadaver) | 7,8 → 7,9 (jetzt mit MSAA 2×) | **525 → 440** | **485 000 → 248 000** | 915 → 744 | 165 → 57 |
| Worst Case ohne MSAA | 8,2 → 8,2 | 517 → 434 | 484 000 → 248 000 | 917 → 744 | 136 → 47 |
| Worst Case, **60 Kadaver** | 7,8 → 7,9 | **563 → 435** | **597 000 → 262 000** | 1 007 → 744 | 196 → 47 |
| Ruhiger Start | 2,4 → 2,4 | 140 → 140 | 57 000 → 57 000 | 403 → 381 | 7 → 7 |

\* `world_geo_total` = sichtbare GeometryInstance3D unter HuntWorld (Kadaver, Gegner, Ziele,
Angriffsformen, Ringe).

Teilsysteme im Worst Case (Anzahl sichtbarer Geometrie-Knoten, Draw-Call-Anteil per Schalter):

| Teil | vorher | nachher | Anmerkung |
|---|---:|---:|---|
| Kadaver (`corpse_geo`) | 66 Knoten, −59 Draw Calls, −125 000 Primitive | **1 MultiMesh**, ≈ 1 Draw Call, ~390 Dreiecke je Kadaver | wächst nicht mehr mit der Run-Länge (60 Kadaver = 30 Kadaver) |
| Angriffsform-Effekte (`attack_fx_geo`) | 18 | 7 | Ringe, Pfützen, Sporen, Stacheln, Bogenpunkte je 1 MultiMesh |
| Gegner (`enemy_geo`) | 79 | 47 | Leaper-Bogen 11 → 1, Augen/Hörner/Klingen zusammengeführt, Kugeln 64 → 10–24 Segmente |
| FX-Ringe (`fx.gd`) | 1 Knoten + 1 Material je Ring | 1 MultiMesh je Elternknoten | Material geteilt, Farbe/Alpha je Instanz |

Die Frame-Zeit ändert sich am Desktop kaum: der Worst Case ist CPU-gebunden durch HUD-
Neuzeichnen und Schwarm-Skript (siehe Etappe 06), nicht durch diese Objekte. Der Gewinn liegt
bei Draw Calls (−85, bei 60 Kadavern −128), Dreiecken (−49 % bzw. −56 %), Knoten (−171 bzw.
−263) und darin, dass lange Runs nicht mehr linear teurer werden. Auf Mobil-GPUs zählen die
eingesparten Dreiecke und Draw Calls deutlich mehr als am Desktop.

### Maßnahmen

- **Kadaver** (`hunt_world.gd`): alle liegenden Kadaver sind Instanzen EINES MultiMesh
  („Persistent corpses“); Scheibe + Kern zu einem Mesh zusammengeführt (`corpse_segments`
  aus `quality.gd`: 16/12/10 statt 64), ein geteiltes Material. Füllstand per Instanz-Transform,
  Entfernen per Swap-Remove (O(1)), Kapazität wächst in 64er-Schritten. Spielmechanik
  unverändert: die Kadaver leben weiter in `RunModel.corpses`. Culling nach Entfernung ist damit
  überflüssig (ein Draw Call für alle); die MultiMesh-AABB umfasst alle Kadaver.
- **FX-Ringe** (`fx.gd`): `FX.ring()` behält seine Signatur, legt aber je Elternknoten einen
  gepoolten Knoten „FX rings“ mit einem MultiMesh an (max. 48 Ringe, ältester fällt heraus);
  geteiltes Vertex-Colour-Material, Farbe und Alpha je Instanz. Keine Material- oder
  Knoten-Erzeugung pro Ring mehr.
- **Gemeinsame Hilfe** `scripts/fx_batch.gd` (neu): MultiMesh-Batch mit `begin/add/finish`,
  geteilte Materialien (`shared_material`, `vertex_color_material`) und `merge()` für
  zusammengeführte Primitive.
- **Angriffsformen** (`attack_forms.gd`): Ringe (dünn/dick), Pfützen (Scheibe/Rand, Scheibe
  weiter mit `render_priority −1`), Sporenpartikel, Stacheln und Sprungbogen-Punkte je als
  MultiMesh; keine Materialien mehr pro Ring/Pfütze. Projektile bleiben gepoolte Knoten.
  `effect_density` dünnt Sporenpartikel, Bogenpunkte und Spuckspur aus (Telegraphen nie).
- **Gegner** (`hunter.gd`, `skitter.gd`, `prey.gd`, `mire_leaper.gd`): Meshes und Materialien
  statisch geteilt; gleichfarbige Teile zusammengeführt (Jäger-Hörner, -Augen, Kronen-Reif +
  Zacken; Skitter-Klingen und -Augen); Kugel-/Zylindersegmente reduziert; Leaper-Bogen als
  MultiMesh, Schatten-Textur und Lebensbalken geteilt. Bog King unverändert (Einzelstück).
- **Ziele** (`objectives/*`): 12 Nest-Klauen → 1 Mesh, 9 Totem-Splitter → 1, Steinstapel →
  1, Schädel + Hörner → 1, Augen → 1; statische Materialien geteilt, Segmente reduziert.
  Animierte Materialien (Füllscheibe, Rand, Eier, Strahl) bleiben je Ziel (nur eines lebt).
- **Alpha-Kern und Fluch-Aura** (`hunt_world.gd`): Meshes und Materialien geteilt.
- **Sichtlinie nur in Reichweite** (`hunter.gd`, `skitter.gd`): `arena.clear_line()` zum
  Schwarm lief für jeden jagenden Jäger/Skitter jedes Frame, das Ergebnis zählte aber nur in
  Angriffsreichweite (3 m bzw. 5,5 m). Jetzt wird es erst dort ausgewertet (Kurzschluss, gleiches
  Ergebnis, keine Nebenwirkung). Profil im Worst Case: `clear_line` für 10 Gegner ≈ 2,1 ms,
  `steer_direction` ≈ 0,9 ms (Abtastung alle 0,25 m mit `is_open`). **world_ms 1,98 → 1,23**
  (isoliert) bzw. 1,08 (Gesamtstand). Playthrough und Balance identisch.
- **HUD-Daten** (`hunt_world._update_hud`): nächster Kadaver per quadrierter Distanz, Text nur
  einmal formatiert (gleiches Ergebnis).
- **Qualität** (`main.gd`): `_apply_quality()` beim Start – Einstellung `settings.quality`
  (low/medium/high, sonst Heuristik aus `quality.gd`) → `QUALITY.apply_viewport()` (nicht
  headless, Tests behalten ihre Taktung), Schwarm-Schatten über `swarm.shadows.visible`
  (`unit_shadows`). `main.quality_value("decor_density")` ist der abfragbare Hook für die
  Arena (APEX liest ihn später). `visible_mawlings` wird **nicht** angewendet – Nahkampf und
  Flächentreffer zählen sichtbare Tiere. Die Profil-Einstellung „quality“ existiert noch nicht
  (`profile.gd` kennt nur bool-Schalter); das Menü kann sie später setzen.

### Prüfung

- `tools/test.ps1` voll in der isolierten Kopie (HEAD + PERF_WORLD): **ALL PASS**, inkl.
  `per_unit_hits`, `motion`, `attack_forms`, `objectives`. Playthrough und `balance_regress`
  sind **identisch** mit HEAD (PLAYTEST 120 s, peak 250, kills 34, lost 50, corpses 11, nests 2;
  BALANCE glutmaw kills 41 / sporling kills 71, gleiche Verluste, Builds und Formschaden).
- Captures `combat, objectives, forms, boss, leaper, hunt`: Ringe, Sporen, Stacheln, Pfützen,
  Leaper-Bogen, Nest-Klauen, Totem, Kadaver und Jäger-Details sehen aus wie vorher.

## Gesamtmessung (alle Stränge, Arbeitsstand)

Arbeitsverzeichnis nach PERF_SWARM (Schwarm-MultiMesh) + PERF_WORLD, PERF_HUD im Zwischenstand
(headless noch `ui_layer.gd`-Fehler „Parameter t is null“ im Playthrough – PERF_HUD-Teil, nicht
PERF_WORLD). Stufe HOCH (MSAA 2×), 12 s bzw. 6 s:

| Szene | Etappe 06 | jetzt | Draw Calls | Primitive | Knoten | RAM / VRAM MB |
|---|---:|---:|---:|---:|---:|---:|
| Worst Case | 8,1–8,9 ms | **3,9 ms** (p95 5,3) | 525 → **187** | 485 000 → 66 000 | 915 → 408 | 144/65 → 62/40 |
| Worst Case, 60 Kadaver | – (7,8 ms/563 DC isoliert) | 4,3 ms | 178 | 81 000 | 408 | 62/40 |
| Ruhiger Start | 2,1–2,7 ms | 1,6 ms | 140 → 77 | 57 000 → 21 000 | 403 → 330 | 48/37 |
| Menü mit 3D-Rudel | 13,0 ms | 1,3 ms | 838 → 81 | 33 000 → 18 000 | – | 52/47 |

Weitere Varianten desselben Stands (vor dem Sichtlinien-Umbau, daher world_ms ~0,8 ms höher):
Worst Case 4,7 ms / 186 DC; ohne MSAA 4,7 ms / 179 DC; Stufe MITTEL 4,5 ms / 179 DC;
Stufe NIEDRIG 4,6 ms / 176 DC / 58 000 Primitive. Kriterium 1 (≤ 4 ms, ≤ 250 Draw Calls,
Menü ≤ 4 ms) ist damit am Desktop erreicht; die Stufen unterscheiden sich am Desktop kaum
(CPU-gebunden), ihr Nutzen liegt bei Füllrate/GPU auf Mobilgeräten.

Größter verbleibender Einzelposten der Welt: `arena.clear_line()`/`steer_direction()` (APEX-
Datei `arena.gd`) – Abtastung alle 0,25 m mit `is_open()` je Probe; `steer_direction` ruft es für
jeden jagenden Gegner jedes Frame auf (≈ 0,1 ms je Aufruf). Vorschlag für APEX/Etappe 08:
früher Ausstieg, wenn im Korridor der Strecke kein Hindernis liegt, oder gröbere Abtastung.

`tests/perf_bench.gd` ist an den MultiMesh-Schwarm angepasst: `off=units` blendet
`swarm.bodies`/`ghost_bodies` aus, `cap=N` kürzt die sichtbaren Instanzen, `mm_units`
(Schätzung aus Etappe 06) entfällt, `_geometry()` verträgt Nicht-Knoten.
