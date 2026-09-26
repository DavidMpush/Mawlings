# Etappe 06 – Leistung: Messwerte und Einbau-Empfehlungen

Teil LEISTUNG (Kriterium 7). Neue Dateien: `tests/perf_bench.gd`, `tools/perf.ps1`,
`scripts/quality.gd`, diese Notiz. Keine bestehende Datei wurde geändert.

## Messaufbau

- **Rechner:** Windows 11, AMD Ryzen 5 3600 (6 Kerne/12 Threads), 32 GB RAM,
  NVIDIA GeForce RTX 5070, OpenGL 3.3 (Compatibility), Godot 4.7.2.
  **Das sind Desktop-Werte, keine Android-Werte.** Sie zeigen Verhältnisse und
  Kostentreiber, nicht die Bildrate auf dem S25 oder einem Mittelklassegerät.
- **Fenster:** 540 × 1170 (S25-Seitenverhältnis 19,5 : 9, halbe Auflösung), Vsync aus,
  `Engine.max_fps = 0`. Fokus-Pause getrennt (wie `tests/capture_motion.gd`).
- **Worst Case (`scene=worst`):** Population 250 → 120 sichtbare Modelle, Bog King +
  3 Jäger + 3 Skitter + 3 Leaper nahe am Schwarm (unverwundbar, werden bei > 14 m
  zurückgesetzt), Meute + Ätzflut (beide Evolutionen) + Sporenwolke R3 +
  Stachelrücken R3, Reißzähne/Rudelinstinkt/Vielfraß R3, 30 liegende Kadaver,
  Belohnungs-Popup alle 0,35 s, Rally 1,5 s von 3 s, Bewegung im Kreis, geseedete
  Karte (424242), volles HUD. Verluste werden jedes Frame auf 250 aufgefüllt
  (Schlüpf-/Geisteranimationen laufen dadurch ständig – eher pessimistisch).
  3 s Aufwärmen, dann 20 s Messung (Varianten 8–10 s).
- **Kennzahlen:** `avg_ms`/`p95_ms` = reale Frame-Zeit; `world_ms`/`swarm_ms` = vom
  Bench selbst gestoppte Skriptzeit von `HuntWorld.step()` bzw. `Swarm._process()`;
  `render_cpu_ms`/`gpu_ms` = RenderingServer-Messung des Haupt-Viewports;
  `draw_calls`/`objects`/`prims` = Mittel von `RENDER_TOTAL_*_IN_FRAME`;
  `process_max_ms` = `Performance.TIME_PROCESS` (Godot meldet das **Maximum der letzten
  Sekunde**, nicht den Mittelwert). Messrauschen zwischen Läufen ca. ± 0,5 ms.

Ausführen: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/perf.ps1`
(alle Varianten, ca. 6 min) oder `-Quick` (Worst Case, ruhiger Start, Menü).

## Messwerte (Desktop)

| Szene | avg ms | p95 ms | Draw Calls | Objekte | Primitive | Knoten | RAM MB | VRAM MB |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Worst Case | 8,1–8,4 | 9,9–11,3 | 530 | 820 | 488 000 | ~910 | 148 | 67 |
| Ruhiger Spielstart (25 Tiere) | 2,1 | 2,7 | 141 | 290 | 58 000 | 402 | 48 | 23 |
| Menü mit 3D-Rudel | 13,0 | 15,8 | 838 | 2 677 | 33 000 | 22 | 52 | 36 |
| Menü ohne 3D-Rudel | 13,0 | 14,1 | 864 | 2 699 | 18 500 | 5 | 49 | 27 |

Worst Case im Detail: `world_ms` 1,9 · `swarm_ms` 0,8 · `render_cpu_ms` 1,8–2,3 ·
`gpu_ms` 1,0. Der Desktop ist **CPU-gebunden** (GPU < 1,5 ms in allen Varianten).
RAM/VRAM wachsen im Worst Case in den ersten ~15 s von 100/51 MB auf 148/67 MB und
bleiben dann stehen (45-s-Lauf mit `trace=1`: kein Leck, sondern Cache-Aufbau).

### Anteile per Schalter (Worst Case minus Teilsystem)

| Schalter | Δ Frame-Zeit | Δ Draw Calls | Δ Primitive | Anmerkung |
|---|---:|---:|---:|---|
| `off=hud` (HUD unsichtbar) | **−4,1 ms** | **−237** | – | render_cpu 1,8 → 0,8 ms, GPU 1,0 → 0,2 ms, **RAM 148 → 50 MB, VRAM 67 → 25 MB** |
| `off=swarmcpu` (Schwarm-Animation aus) | **−2,5 ms** | 0 | 0 | Skript 0,8 ms + Transform-/Shader-Parameter-Weitergabe; `world_ms` sinkt dabei mit (1,9 → 0,65, ruhender Schwarm → weniger Kontakt-Logik) |
| `off=forms` (keine Angriffsformen) | −1,2 ms | −94 | −20 000 | fast nur Render-Seite; Skriptzeit der Formen klein |
| `off=units` (Mawling-Modelle unsichtbar) | −0,4…−0,9 ms | **−129** | **−188 000** | ≈ 1 560 Dreiecke × 120 Modelle |
| `off=corpses` (34 Kadaver unsichtbar) | −0,2…−0,7 ms | −60 | **−136 000** | je Kadaver eigenes Material + eigene 64-Segment-Kugel (~4 000 Dreiecke) |
| `off=enemies` | −0,4 ms | −32 | −68 000 | |
| `off=arena` (ganze Karte) | −0,7 ms | −44 | −21 000 | Deko allein (`off=decor`): −34 Draw Calls, −22 000 Primitive |
| `off=fx` (Formen-/Ring-Effekte nur unsichtbar) | −0,5 ms | −31 | −14 000 | |
| `off=popups` | −0,2 ms | −26 | – | |
| `off=shadows` | −0,4 ms | −10 | −10 000 | Schatten-MultiMesh ist bereits 1 Aufruf |
| `mm_units` (Schätzung: Modelle als MultiMesh) | ±0 ms | **−128** | −185 000 | Bench aktualisiert das MultiMesh zusätzlich per GDScript; die Knoten laufen weiter |
| `cap=60` (nur 60 Modelle sichtbar) | −0,1 ms | −69 | −96 000 | |
| `scale3d=0.7` / `msaa=2` / 720 × 1560 | ±0,2 ms | – | – | GPU hier nicht der Engpass (auf Mobil anders) |
| Menü: 3D-Rudel aus | ±0 ms | – | – | −8 MB VRAM (SubViewport mit MSAA 4×) |

### Speicherprobe Schrift

Die Schriften sind derzeit der Godot-Fallback-Font (kein `assets/ui/fonts/`), dynamisch
gerastert. Eine Probe (Scratch-Skript, nicht im Repo) zeichnete dieselbe Zeile mit
Kontur in 1/12/24 verschiedenen Größen: RAM 32 → 40,5 → 51,9 MB, VRAM 10,3 → 13,1 → 18,3 MB,
also **≈ 0,8 MB RAM und ≈ 0,3 MB VRAM je zusätzlicher Größe**. Das HUD animiert
Schriftgrößen stufenlos (`hud_overlays.gd` Popups `int(34 * pop)`, Königsmoment
`int(64 * pop)`/`int(58 * scale)`, `hud_top.gd` Populationszahl `54 + 8 * pulse`,
`hud_controls.gd` Einpassung). Das erklärt einen Teil der +98 MB RAM/+42 MB VRAM des HUD;
der Rest (Icon-Buckets in `ui_icons.gd`, Rahmen) ist nicht einzeln gemessen.

## Kostentreiber (Reihenfolge)

1. **HUD-Zeichnung (≈ 50 % der Worst-Case-Frame-Zeit, 237 Draw Calls, +98 MB RAM).**
   Alle HUD-Komponenten rufen in `_process` jedes Frame `queue_redraw()` und
   zeichnen Rahmen, Polygone, Konturschrift und Icons neu; jede Konturschrift ist ein
   eigener Durchgang und bricht das Batching. Dazu Glyphen-Caches je Schriftgröße.
2. **Schwarm als 120 Einzelmodelle (≈ 2,5 ms + 129 Draw Calls + 188 000 Dreiecke).**
   Je Tier 3 Knoten (`Mawling`/`Game model`/Mesh) mit Transform-Updates und drei
   `set_instance_shader_parameter`-Aufrufen pro Frame; Instance-Uniforms verhindern
   jedes Zusammenfassen.
3. **Wachsende Einzel-Objekte ohne Teilen von Ressourcen:** Kadaver (2 Draw Calls und
   ~4 000 Dreiecke je Kadaver, bleiben dauerhaft liegen → wächst linear mit der Run-Länge),
   Angriffsform-Effekte (94 Draw Calls, einzelne MeshInstances für Sporenpartikel,
   Bogenpunkte, Spuren) und `fx.gd`-Ringe (neues `StandardMaterial3D` je Ring).
4. **Menü:** 838 Draw Calls und 13 ms pro Frame – teurer als der Worst Case im Spiel –,
   weil `menu_main.gd`/`menu_sheets.gd` den ganzen Hub (Adern, Zellen, Verläufe) jedes
   Frame neu zeichnen. Das 3D-Rudel selbst kostet fast nichts.

Arena/Deko (44 Draw Calls im Bild, 21 000 Primitive) und das Schatten-MultiMesh sind
günstig und nicht vorrangig.

## Einbau-Empfehlungen je Datei (Gewinn geschätzt, Desktop-Maßstab)

| Priorität | Datei(en) | Maßnahme | Erwarteter Gewinn |
|---|---|---|---|
| 1 | `scripts/ui/hud_top.gd`, `hud_overlays.gd`, `hud_controls.gd`, `hud_objectives.gd`, `scripts/touch_controls.gd` | Neu zeichnen nur bei geänderten Werten oder laufender Animation (Zustands-Hash je Komponente, `hud_redraw_hz` aus `quality.gd` als Obergrenze im Ruhezustand); statische Rahmen/Paneele in eigene CanvasItems, die nur bei Größenänderung zeichnen; Rahmen als Nine-Patch-Textur statt Polygon-Tessellierung | −2…3 ms, −120…180 Draw Calls |
| 1 | dieselben + `scripts/ui/ui_style.gd` | Feste Schriftgrößen, Puls/Pop über `draw_set_transform` skalieren (`popup_font_steps`), oder eigene Display-Schrift mit MSDF-Import (eine Atlas-Textur für alle Größen) | −40…80 MB RAM, −20…35 MB VRAM (Probe: ~0,8/0,3 MB je Größe) |
| 2 | `scripts/swarm.gd`, `shaders/creature_anim.gdshader` | Mawlings als ein `MultiMeshInstance3D`; Laufzyklus/Phase/Biss/Blitz per `INSTANCE_CUSTOM` (`use_custom_data`) statt `instance uniform`; Posen in PackedArrays, keine 360 Knoten. Optional LOD-Mesh (~600 Dreiecke) ab `display_scale < 0,7` | −1,5…2 ms, −119 Draw Calls; mit LOD −110 000 Dreiecke |
| 3 | `scripts/hunt_world.gd` (`_create_corpse`) | Kadaver-Mesh und -Material einmal anlegen und teilen; Kugel mit `corpse_segments` 10–16 statt 64; mittelfristig ein MultiMesh für alle Kadaver | −60 Draw Calls, −130 000 Dreiecke bei 34 Kadavern; danach O(1) statt O(n) |
| 3 | `scripts/attack_forms.gd`, `scripts/fx.gd` | Sporenpartikel, Bogenpunkte und Spuckspuren je als MultiMesh; ein Material je Farbe; `fx.gd`-Ringe poolen und Alpha über Instance-Uniform/Vertexfarbe statt neuem Material; `effect_density` für Zierteile | −50…80 Draw Calls, ~−0,8 ms |
| 4 | `scripts/ui/menu/menu_main.gd`, `menu_sheets.gd` | Statischen Hintergrund, Karten und Adern nur bei Zustandswechsel zeichnen (eigene CanvasItems oder einmalig in eine Textur), nur Sporen/Blätter animiert neu; Rudel-SubViewport mit `menu_msaa` (2× statt 4×) bzw. `menu_3d = false` in NIEDRIG | 13 → ~3–4 ms, −600 Draw Calls; −8 MB VRAM ohne Rudel |
| 5 | `scripts/main.gd` (bzw. Startpunkt) | `Quality.apply_viewport(get_viewport(), Quality.settings())` beim Start: `scaling_3d_scale` 0,85/0,7, MSAA nur in HOCH | auf Mobil fillrate-abhängig; am Desktop ±0 |
| 6 | `scripts/arena.gd` | `decor_density` auf Moos/Sand/Kiesel/Blattbüschel/Blumen anwenden (erste n Teile, seed-stabil); Kiesel/Blätter je Chunk als MultiMesh | −20…30 Draw Calls; niedrige Priorität |
| – | `scripts/swarm.gd` `VISUAL_LIMIT` | `visible_mawlings` erst senken, wenn `HuntWorld.melee_factor`/`_resolve_area_hit` nicht mehr an den sichtbaren Modellen hängen – sonst ändert die Qualitätsstufe das Kampfergebnis | bis −69 Draw Calls/−96 000 Dreiecke bei 60 |

## Priorität für Zielgeräte

- **Samsung Galaxy S25 (Snapdragon 8 Elite, Adreno 830 → Stufe HOCH):** Die CPU liegt
  etwa auf Desktop-Niveau; 60 fps im Worst Case sind wahrscheinlich, aber die
  CPU-Last (HUD + Schwarmknoten) erzeugt Wärme und Drosselung in langen Runs.
  Reihenfolge: HUD-Neuzeichnung (1), Schwarm-MultiMesh (2), Kadaver teilen (3), Menü (4).
- **Mittelklasse (z. B. Adreno 6xx, Mali-G57/G68, 4–6 GB → Stufe NIEDRIG/MITTEL):**
  GDScript und GLES-Treiber pro Draw Call sind grob 2,5–4× langsamer; aus 8 ms
  Desktop-CPU werden geschätzt 20–30 ms (33–50 fps). Ohne Punkte 1–3 ist 60 fps
  nicht erreichbar; zusätzlich `scaling_3d_scale` 0,7–0,85 (Füllrate bei 1080 × 2400)
  und `effect_density`/`unit_shadows` aus `quality.gd`. Speicher: die +98 MB HUD-Caches
  zählen auf 4-GB-Geräten; Schriftgrößen fixieren.

## `scripts/quality.gd`

Statische API ohne Einbau: `current_tier()`, `settings(tier)`, `value(key)`,
`set_override(tier)`, `parse("mittel")`, `device_info()`, `choose_tier(info)`,
`apply_viewport(viewport, values)`, `scaled_count(full, density)`. Stufen NIEDRIG/MITTEL/HOCH
mit dokumentierten Schaltern (sichtbare Mawlings, Schatten-MultiMesh, Schwarm-MultiMesh,
Animationstakt, Effekt- und Deko-Dichte, Kadaver-Segmente, HUD-Neuzeichnung,
Popup-Schriftstufen, Menü-3D und -MSAA, MSAA, 3D-Skalierung, FPS-Grenze). Heuristik:
Desktop → HOCH; mobil Punkte aus GPU-Familie (Adreno/Mali/Immortalis/Xclipse), Kernzahl
und RAM, bei > 3,2 MP Bildschirm eine Stufe tiefer, falls nicht HOCH.
Probe: Adreno 830/11 GB → HOCH, Adreno 619/6 GB → MITTEL, Mali-G68/8 GB → MITTEL,
Mali-G57/4 GB → NIEDRIG, Immortalis-G715/8 GB → HOCH.

## Offene Punkte

- Keine Messung auf Android: S25 und ein Mittelklassegerät mit `tools/export_android.ps1`
  plus Bench (oder Godot-Remote-Profiler) messen; Heuristik danach anpassen.
- HUD-Speicher: Schriftgrößen sind belegt, Anteil von Icon-Buckets und Rahmen nicht
  einzeln gemessen.
- Der Bench ruft `HuntWorld.step()` und `Swarm._process()` selbst auf (Zeitmessung),
  hält Gegner unverwundbar und füllt die Population auf; Varianten mit < 0,5 ms
  Unterschied liegen im Rauschen.
- Messung enthält den Zwischenstand der parallel entstehenden Teile (Ziele-HUD, Tipps);
  nach der Zusammenführung einmal `tools/perf.ps1 -Quick` wiederholen.
