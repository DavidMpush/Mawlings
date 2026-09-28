# Etappe 22 – Leistung

Auftrag (28.09.2026): alle Spielsituationen messen (Start, Mitte, Flut, Bog King + Flut, jeder Apex, Wüste mit Sandsturm, Pop 5.000, 1.000 Kristalle, Menü), optimieren ohne Optik und Spielverhalten zu ändern, Qualitätsstufen erweitern, Android-Export prüfen. Parallel lief die große Balance-Runde (Spielwerte unberührt).

## Messaufbau
- `tests/perf_bench.gd` direkt (Fenster, 540 × 1170, Stufe HOCH = Desktop, Vsync aus), je Szene 2 Läufe à 8–15 s. Neue Szenen: `mid` (60 Tiere, 2 Jäger, 1 Skitter), `travel` (gerade Bahnen über die Karte: neue Chunks, Wände, Minimap-Backen), `apex kind=apex|apex_toad|apex_sandworm` (im eigenen Biom), `desert` (Sandsturm läuft, Sandmaden). Neue Kennzahlen: `max_ms`, `hitches` (Frames > 8 ms), `PERF_CHUNKS` (Chunk-Aufbauten, längster), Schalter `hide=<HUD-Komponente>`, `layers=<hud_controls-Ebenen>`, `spikes=1` (Ursache langsamer Frames).
- **Wichtig:** Während aller Messungen liefen auf demselben Rechner bis zu 20 weitere Godot-Prozesse (Balance-Runde). Frame-Zeiten (avg, p95, max, Hitches) sind dadurch stark verrauscht und höher als im Leerlauf; die `PERF_SPIKE`-Auswertung zeigte keine Spitze, die mit Chunk-Aufbau, HUD-Backen oder Minimap zusammenfiel. Belastbar sind Draw Calls, Dreiecke, Chunk-Aufbauzeiten und Kartenbauzeit.

## Befund
- **Das HUD erzeugt die meisten Draw Calls**, nicht die 3D-Welt: Mitte ohne HUD 58 statt 334 Draw Calls, Flut ohne HUD 121 statt 572, Render-CPU 2,5 → 0,9 ms.
- Größter Einzelposten: der **Fähigkeitsknopf** (17d) – sein Glühen pulsierte über den Cache-Schlüssel, die Ebene wurde nie gebacken und zeichnete jedes Frame ~130 Draw Calls (Kit.glow = Fächer aus ~90 Polygonen).
- **GPU-Rücklesen beim HUD-Cache:** Jede gebackene Ebene las ihre SubViewport-Textur per `get_image()` zurück (Pipeline-Stall) und baute das Renderziel neu auf.
- Chunk-Aufbau: 1,5–4 ms je Chunk; beim Betreten einer neuen Chunk-Reihe entstanden bis zu drei in einem Frame.
- Kartenbau (Migration): ~320 ms GDScript im Frame des Biomwechsels (unter Last gemessen).

## Optimierungen
- `hud_controls.gd`: Fähigkeitsknopf ohne Zeit im Schlüssel (statisches Glühen, wird gebacken); Rally-Glühen gebacken (Atmen über Modulate); Joystick in gebackene Basis (Scheibe, Ringe, ruhige Pfeile) und bewegten Teil (Lichtbogen, leuchtende Pfeile, Knauf) geteilt.
- `ui_layer.gd`: gebackene Ebenen zeigen ihr Renderziel direkt (bleibt erhalten, kein `get_image()`, kein neues Renderziel je Backen); Zähler `bake_count` für den Bench.
- `arena.gd`: neue Chunks werden auf mehrere Frames verteilt (`chunk_budget`, im Spiel 1 je Frame; der Chunk unter dem Schwarm sofort); Messwerte `chunk_builds`/`chunk_build_ms_max`.
- `arena.gd` + `hunt_world.gd`: **Kartenvorbau im Hintergrund** – öffnet sich der Migrationsschlund, baut ein Worker-Thread die nächste Karte (gleiche Eingaben, gleiches Ergebnis; geprüft in `tests/map_layout.gd`). Der Biomwechsel nimmt die fertige Karte: 319 → 49 ms (Rest: Flussfeld, Beacons, Chunks).
- Qualitätsstufen (`quality.gd`) um `wall_detail` (Wand-Innenleben und Kartenrand dünner, Wandränder bleiben: HOCH 1,0 / MITTEL 0,8 / NIEDRIG 0,55), `minimap_bake_us` (600/450/300 µs Backzeit je Frame) und `vfx_sprites` erweitert; Leser: `arena_border.gd`, `hud_minimap.gd`, `vfx_sprites.gd`.

## Messtabelle (Stufe HOCH, Mittel aus 2 Läufen; Frame-Zeiten unter Fremdlast)
| Szene | Draw Calls vorher → nachher | Dreiecke nachher | avg / p95 ms nachher | world_ms | Render-CPU / GPU ms nachher |
|---|---:|---:|---|---:|---|
| Start (calm) | 389 → **242** | 41 000 | 7,0 / 9 | 0,6 | 2,4 / 1,8 |
| Mitte (Pop 60) | 320 → **177** | 38 000 | 7,1 / 9,6 | 1,3 | 1,6 / 1,1 |
| Reise (neue Chunks) | 291 → **149** | 35 000 | 6,4 / 8,3 | 1,1 | 1,5 / 1,0 |
| Worst Case (250 Tiere, Bog King, alle Gegner) | 516 → **327** | 149 000 | 12,2 / 14,8 | 2,2 | 2,6 / 1,7 |
| Bog King + Flut | 735 → **550** | 131 000 | 21,2 / 26,8 | 4,8 | 3,9 / 3,0 |
| Moosschlund | 336 → **191** | 38 000 | 7,5 / 10 | 1,2 | 1,8 / 1,1 |
| Aschenkröte | 369 → **223** | 37 000 | 9,0 / 11,1 | 1,3 | 2,0 / 1,5 |
| Sandwurm | 345 → **205** | 46 000 | 8,3 / 10,9 | 1,4 | 1,9 / 1,3 |
| Wüste + Sandsturm | 318 → **195** | 44 000 | 8,6 / 11,9 | 1,5 | 1,9 / 1,3 |
| Pop 5.000 | 529 → **328** | 147 000 | 12,6 / 15,1 | 2,2 | 2,6 / 1,7 |
| 1.000 Kristalle | 526 → **322** | 255 000 | 12,6 / 16,8 | 2,2 | 2,6 / 1,8 |
| Menü | 13 → 13 | 1 200 | 0,8 / 1,0 | – | 0,2 / 0,1 |
| Stufe NIEDRIG: Worst / Flut / Reise | – | – | 8,7 / 13,6 / 3,6 | 1,6 / 3,1 / 0,6 | 1,9 / 2,6 / 0,9 |

- Chunk-Aufbau: längster 3,4–4,1 ms (Ziel < 8 ms); je Frame höchstens einer.
- Speicher: 72–80 MB RAM, 48–71 MB VRAM (gehaltene HUD-Renderziele kosten ein paar MB VRAM).
- **Vergleich Etappe 07 (≤ 4 ms, ≤ 250 Draw Calls):** Start, Mitte, Reise, alle Apex-Kämpfe und die Wüste liegen jetzt unter 250 Draw Calls. Worst Case, Pop 5.000, 1.000 Kristalle (~325) und besonders die Flut (~550) liegen darüber – fast ausschließlich HUD (Beute-Popups, Flut-/Boss-Anzeigen, Schwarm-Pille, Zeiger zeichnen live mit vielen Polygonen). Frame-Zeit ≤ 4 ms ist unter der Fremdlast nicht nachweisbar; `world_ms` (Spiellogik) liegt außer in der Flut bei ≤ 2,2 ms.

## Etappe 22b – HUD-Draw-Calls in Kampf und Flut
Ziel: Worst Case, Pop 5.000 und 1.000 Kristalle ≤ 250, Flut + Bog King ≤ 300 Draw Calls, ohne sichtbare Änderung. Messung wie oben (`scene=… secs=12`, Stufe HOCH, 2 Läufe); Aufschlüsselung mit den neuen Bench-Schaltern `mute=<Komponente>/<Ebene>` (Maler zeichnet nichts), `list_layers=1` und `shot=<name>` (Bild nach `previews/`).

Hebel (die 2D-Leinwand fasst in gl_compatibility fast nichts zusammen, jedes `draw_*` ist ein Draw Call):
- `ui_kit_brawl.gd`: **`TriBatch`** – Scheiben, Ringe, Verlaufsscheiben und Polygone mit schmalem Weichrand (Kantenglättung) in einer Dreiecksliste (`canvas_item_add_triangle_array`). Runde `icon_plate` 12 → 1, `disc`/`circle_ring` 2–3 → 1, `round_button` → 3, `glow` bis 96 → 1, Pfeil (`chevron`, 4 Striche mit Gelenkscheiben) 16 → 1, Balkenteiler per `draw_multiline`.
- **Text**: `text_outlined` zeichnet erst beide Umrisse, dann Schatten und Füllung (gleiches Tintenschwarz, Reihenfolge daher bildgleich) – 4 → 2 Draw Calls. Neu `Kit.texts_outlined` für mehrere Texte in zwei Durchgängen.
- **Beute-Popups** (`hud_overlays.gd`): alle Plaketten in einem Batch, dann Symbole, dann alle Zahlen gemeinsam; Verlustzahl + „MAWLINGS“ gemeinsam; Rand-Vignette 4 → 1.
- **Schwarm-Pille und Bossleiste** (`hud_top.gd`) je in drei Ebenen: hinten (Puls-/Trefferring, live nur während er leuchtet), **Standbild gebacken** (Pille, Portrait, Panel, Name, Tag-Chip; Schlüssel ohne LP/Zahl, Textlayout-Schlüssel `_boss_text_layout`), live (Zahl, LP-Streifen, rote Plakette nur bei Verlust, Balken, Phasenmarken – Marken gebündelt).
- **Warnhinweis** (`hud_controls.gd`): der pulsierende Halo ist eine eigene Live-Ebene `hint_glow`, das Banner bleibt gebacken (vorher 30 Hz Neuzeichnen).
- Gebrawl-Banner, Ergebnis und Pause (`hud_overlays`) als gecachte Ebenen.

| Szene | Draw Calls Etappe 22 → 22b | avg / p95 ms 22b |
|---|---:|---|
| Start (calm) | 242 → **~215** | 6,5 / 8,4 |
| Mitte (Pop 60) | 177 → **~144** | 7,1 / 9,3 |
| Worst Case | 327 → **~207** | 11,3 / 13,7 |
| Pop 5.000 | 328 → **~210** | – |
| 1.000 Kristalle | 322 → **~208** | 11,5 / 15,3 |
| Bog King + Flut | 550 → **~280** | 17,3 / 23,3 |
| Moosschlund | 191 → **157** | 7,4 / 9,5 |
| Wüste | 195 → **~145** | – |
| Menü | 13 → 13 | 0,9 / 1,1 |

Ziele erreicht. Die Flut schwankt je nach Hinweiswechsel (jeder neue Hinweistext backt das Banner neu) um ±10.

Tests (22b): `tools/test.ps1` – HUD-, Boss-, Smoke-, Karten- und Ability-Tests grün; rot sind `flood`, `apex`, `apex_run`, `meta`, `chronicle` (Flutstart 210 statt 240 s, Apex-Grundleben, Stamm-Modifikatoren) – Spielwerte der parallel laufenden Balance-Runde, nicht HUD.

Sichtprüfung: `previews/hud_before_{worst,flood}.png` (vor 22b) gegen `hud_after_{worst,flood}.png`; Ausschnitte oben (Pille, Uhr, Bossleisten mit Phasenmarke), Popups, Randzeiger und Steuerung vergrößert verglichen – gleiche Formen, Farben, Kanten. Bewusste Mini-Abweichungen: Weichrand der Batch-Formen ist eigene Geometrie statt Godot-Kantenglättung (subpixelig); der anfangs doppelte Schlagschatten der roten Verlust-Plakette ist behoben (die Live-Plakette zeichnet ohne eigenen Schatten, `icon_plate_into(..., shadow = false)`; Tinte über Tinte ist bildgleich).

## Android
- `tools/export_android.ps1 -NoInstall` bricht vor dem Export ab: In den Godot-Editoreinstellungen zeigt der Java-SDK-Pfad auf `G:\Users\David\Java\bin\java.exe` (erwartet: JDK-Ordner ohne `\bin\java.exe`). Diese Nutzer-Einstellung habe ich nicht geändert. `adb devices`: kein Gerät verbunden.

## Tests
`tools/test.ps1` komplett grün (ALL PASS). `map_layout` prüft zusätzlich den Kartenvorbau (gleicher Fingerabdruck) und druckt bei einem nicht offenen Platz die Ursache.

## Offen
- HUD: Randzeiger (Ziele) zeichnen noch Glühen, Ring, Bogen, Pfeil, Plakette und Text einzeln (~8 je Zeiger); Stil-Boxen (`rrect`/`ring`/Balken) sind je ein Draw Call. Weitere Bündelung möglich, derzeit nicht nötig.
- Kartenbau beim Run-Start (~0,3 s GDScript) noch im Ladeframe; könnte im Menü vorgebaut werden.
- Messung auf dem S25 und im Leerlauf des Rechners; Java-Pfad korrigieren, dann APK-Größe.
