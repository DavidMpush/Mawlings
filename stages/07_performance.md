# Etappe 07 – Leistung umsetzen (+ Vorarbeit Apex-Boss & Glutsumpf)

Grundlage: `stages/06_perf_notes.md` (Desktop Worst Case 8,1 ms / 530 Draw Calls, Menü 13 ms; Kostentreiber HUD-Neuzeichnen, 120 Einzelmodelle, Kadaver/FX ohne geteilte Ressourcen). Messen mit `tools/perf.ps1` (ohne `--headless`).

## Abnahmekriterien
1. Desktop-Worst-Case (perf_bench) ≤ 4 ms im Mittel, Draw Calls ≤ 250; Menü ≤ 4 ms; ruhiger Start unverändert günstig. Messwerte vorher/nachher in `stages/07_perf_results.md`.
2. **Kein** Spielverhalten ändert sich: alle Tests grün inkl. `per_unit_hits`, `balance_regress`, Playthrough in der gewohnten Spanne; Bild in den Captures gleichwertig.
3. `scripts/quality.gd` eingebaut: Stufe wird beim Start gewählt (Heuristik, überschreibbar in den Einstellungen später), steuert nur Darstellung (nie Kampf: `unit_world_points()` bleibt die Kampfbasis, auch wenn weniger Tiere gezeichnet würden – sichtbare Obergrenze nicht senken).
4. Vorarbeit APEX: Apex-Boss „Verdant-Apex“ und Glutsumpf-Biomdaten als eigenständige, getestete Bausteine, Einbindung in HuntWorld in Etappe 08.

## Dateibesitz
- PERF_HUD: `scripts/ui/*` (alle HUD-/Menü-Komponenten, `ui_style.gd` Schriftgrößen-Cache, `ui_frames.gd`, `ui_icons.gd`), `scripts/touch_controls.gd`, `scripts/menu/menu.gd` (nur Redraw-Steuerung)
- PERF_SWARM: `scripts/swarm.gd`, `shaders/creature_anim.gdshader`, `shaders/creature_look.gdshaderinc`, `tests/model_budget.gd` (anpassen), `tests/motion.gd` (nur falls Strukturzugriffe brechen)
- PERF_WORLD: `scripts/hunt_world.gd` (nur Kadaver-/Popup-/FX-Darstellung), `scripts/fx.gd`, `scripts/attack_forms.gd` (nur Darstellung/Pooling), `scripts/objectives/*` (nur Darstellung), `scripts/prey.gd`, Gegner-Skripte (nur geteilte Materialien/Meshes), `scripts/quality.gd` + Einbau in `scripts/main.gd`, `tests/perf_bench.gd`, `tools/perf.ps1`, `stages/07_perf_results.md`
- APEX: neu `scripts/apex_boss.gd`, `scripts/biomes.gd` (Biom-Daten: Boden-, Weg-, Deko-, Wasser-/Lava-Farben, Gegner-Tints, Namen), `tests/apex.gd`, `tests/capture_apex.gd`; `scripts/arena.gd` (Biom-Parameter: Farben/Deko aus `biomes.gd` statt fester Konstanten, Default = Verdant Maw exakt wie heute)

## Ergebnis (26.09.2026)

Desktop (Ryzen 5 3600, RTX 5070, Fenster 540×1170, Vsync aus – **keine Android-Werte**), `tools/perf.ps1 -Quick`:

| Szene | vorher | nachher |
|---|---|---|
| Worst Case | 8,1–8,9 ms, ~530 Draw Calls, 148 MB RAM | **3,97 ms** (p95 5,2), **196** Draw Calls, 63 MB RAM |
| Ruhiger Start | 2,2 ms, 139 Draw Calls | **1,48 ms**, 78 Draw Calls |
| Menü | 13–15 ms, ~850 Draw Calls | **1,11 ms**, 81 Draw Calls |

- **Schwarm:** ein MultiMesh für 120 Tiere (`INSTANCE_CUSTOM` für Gang/Phase/Biss), Units als leichte Datenknoten; 123 → 4 Draw Calls.
- **HUD/Menü:** `ui_layer.gd` zeichnet nur bei Zustandsänderung und backt ruhige Ebenen in Texturen; Pulse über `modulate`/`scale`; feste Schriftgrößenpalette; Menü-Blätter/Sporen als MultiMesh.
- **Welt:** Kadaver als ein MultiMesh (wächst nicht mehr mit der Run-Länge), FX-Ringe, Angriffsformen, Popups mit geteilten Meshes/Materialien, Gegner-Teile zusammengeführt.
- **Qualitätsstufen:** `main.gd` wählt die Stufe per Heuristik (Schatten, Effekt-/Deko-Dichte, MSAA, 3D-Skalierung); Kampfbasis (sichtbare Tiere) bleibt unverändert.
- **Vorarbeit Etappe 08:** `apex_boss.gd` (Moosschlund: Wurzelbruch, Sporenring, Beben mit Sicherheitsinseln, Phase 2, Erschöpfung, `migration_ready`), `biomes.gd` (Verdant Maw exakt, Glutsumpf), `arena.set_biome()`, Test `apex`.
- **Tests:** 22/22 grün, Playthrough und Balance unverändert.

Offen: Android-Messung; Menü +11 MB VRAM durch eingebackene Ebenen; Einbacken liest einmal von der GPU zurück (auf dem Gerät prüfen); 2 ObjectDB-Lecks beim Beenden der Boss-Aufnahme; `arena.clear_line` ist größter Welt-Einzelposten.
