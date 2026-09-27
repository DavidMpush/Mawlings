# Backlog – nächste Etappen

Reihenfolge = Priorität. Jede Etappe wird nach `stages/README.md` abgearbeitet (Etappendatei mit Kriterien, parallele Agenten mit getrenntem Dateibesitz, Tests, Bildprüfung, Commit, Bericht). Blockierte Punkte wandern nach „Wartet auf Nutzer“; die Schleife überspringt sie.

## Offen

1. ~~**07 Leistung umsetzen** – Empfehlungen aus `stages/06_perf_notes.md`: HUD nur bei Änderung neu zeichnen und Schriftgrößen fixieren, Schwarm als ein MultiMesh mit `INSTANCE_CUSTOM`, Kadaver/FX mit geteilten Meshes/Materialien, Menü-Hintergrund cachen; `scripts/quality.gd` einbauen (ohne Kampfergebnis zu verändern). Ziel: Desktop-Worst-Case ≤ 4 ms, Draw Calls ≤ 250, Menü ≤ 4 ms.~~ (erledigt: 3,97 ms / 196 / Menü 1,1 ms)
2. ~~**09 Apex-Boss & Migration einbinden** (vor der Flut platzieren, z. B. Wild ~3:30; Flut läuft im neuen Biom weiter) – Bausteine aus 07 (`apex_boss.gd`, `biomes.gd`, `arena.set_biome`) in HuntWorld: Apex nach ~8 min, Migrationsschlund nach Sieg, Wechsel ins nächste Biom mit Schwarm und Build, Run bleibt endlos. Glutsumpf als zweites Biom mit eigener Boden-/Farbwelt (Lava-Warnflächen) – Modelle soweit vorhanden, sonst Platzhalter.~~ (erledigt in Etappe 10)
5. ~~**12 Zweiter Apex „Aschenkröte“**~~ (erledigt: Kröte im Glutsumpf, Biom-Kreislauf, Randtreffer). Rest: Apex-Kampf auf Brutal/Apex noch ~18–20 s statt 25–35 s; Kröten-Kampfdauer in der Flut ungemessen.
6. **13 UI-Stil** – Nutzer hat entschieden: V2-Kit (ruhig, jetzt Standard). Rest: Eigenzeichnungen (Rally, Joystick, Mutationstitel, Menü-Kacheln) auf den gewählten Skin umstellen; `shardcluster.glb` als Drop-Variante nutzen.
3. **10 Teilen** – Teilen-Karte am Run-Ende (Zeit, Peak, Build, Seed-Code), lokale Bestenliste je Tages-Brut, Vorbereitung Clip-Export (letzte 15 s, 9:16) soweit ohne Plattform-SDK möglich.
4. **11 Typografie-Pass** – sobald die Schriften freigegeben sind: Display-/Textschrift überall, Größen und Abstände neu abstimmen, Boss-Balken zeigt Fluch, Tipp-Panel schmaler.
7. **14 Lesbarkeit & Belohnung nach Swarm-Vorbild** – Ideen S1–S13 aus `REFERENCE_SWARM.md`. Vorgeschlagene Reihenfolge: (a) Farbregeln, Anführer-Ring, drei Gefahrenformen, Treffer-Blitz am Anführer (S1–S4); (b) Einsammel-Zahlen zusammenzählen, Moment beim Aufleveln, Auswahlkarten, Evolutions-Hinweis (S5–S8); (c) HUD-Leiste, Boss-Dramaturgie Moosschlund, Kartenzonen, Kommentare, Aufgaben am Run-Ende (S9–S13). Priorität gegenüber 10–13 noch mit dem Nutzer abstimmen.

## Wartet auf Nutzer

- **Schriftwahl:** 8 OFL-Kandidaten liegen unter `assets/ui/fonts/candidates/` (Vergleich `tests/capture_fonts.gd`). Empfehlung: Baloo 2 ExtraBold (Titel) + Figtree (Text).
- **Gefahrenfarbe:** Magenta statt Rot für Gegnerflächen (eigene Farbe bleibt Glut-Rot)?
- **Reihenfolge:** Etappe 14 (Swarm-Lesbarkeit) als Nächstes?
- **Android-Test auf dem Gerät:** APK baut (`tools/export_android.ps1`); Handy mit USB-Debugging anschließen.
- **Modelle (Hunyuan3D):** Skitter, Moorbrut, Moosschlund, Aschenkröte, Brutnest, Stamm-Anführer, Glutsumpf-Requisiten (Prompts in `stages/ASSET_REQUESTS.md`).
- **Später:** Name/Markenprüfung, Monetarisierung (Free-to-play mit Werbung und Skins).
- **Handtest:** 5–10 Minuten Spielgefühl.

## Erledigt
- 01 Bewegung & Lesbarkeit · 02 Welt & Assets · 03 Progression · 04 UI-Komponenten · 05 Spielgefühl, Balance, Lesbarkeit · 06 Ziele, Einstieg, UI-Politur, Leistungsmessung · 07 Leistung · 08 Die Flut & Schwierigkeit · 09 Einzelstart & Anführer · 10 Apex, Migration, Build-Vielfalt, Nutzer-Sounds/Drops/Icons · Minimap · V2-Stil · Aschenkröte · Asset-Paket V3 · Android-Export
