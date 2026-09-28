# Etappe 29 – Wasser: Seen und Moore mit Flachufer

Quelle: Nutzerfeedback 28.09.2026: „Das Wasser sind immer nur aneinandergereihte blaue Pfützen, das sieht schrecklich aus.“ Nutzerentscheidungen: **Flachufer + tiefe Mitte** und **wenige große Seen/Moore**.

## Befund

- `map_explore.gd` erzeugt Sumpf aus Rauschen und Schwellwerten (`_build_mask` ~443, `KIND_WATER`), und das ergibt schmale, zerfranste Bänder.
- `arena_border.gd` `_cell_walls` (~943-950) legt pro 2-m-Zelle eine Uferscheibe und eine Wasserscheibe (`CylinderMesh`, 24 Segmente). Scheiben am Rand sind kleiner (0,95), deshalb entstehen Perlenketten.
- Es gibt keinen Shader, keine Tiefe, keinen Uferverlauf. Wasser blockiert komplett (Zellen im SDF).
- Die Oase in der Wüste nutzt dieselben Scheiben. Der Glutsumpf zeichnet in denselben Zellen Kruste und Lava.

## Ziele und Abnahmekriterien

### A. Formen (Generator)
1. Jede Sumpf-Region bekommt **1–2 große Becken** (buchtig-rund, Durchmesser ca. 14–30 m) und dazu 0–3 kleine Tümpel (4–8 m). Es entstehen keine schmalen Bänder mehr. Die Oase in der Wüste wird ein einzelner großer Teich.
2. Die Regeln aus 18c gelten weiter: 25–35 % der Fläche blockiert, alles offene Gelände verbunden, mehrere Routen, POIs erreichbar, Start- und Ankunftslichtung frei.
3. Der Rest der Sumpf-Region ist offenes Moorland mit Schilf- und Grasbüscheln als Deko. Die Blockade-Quote kann durch Dickicht- oder Wurzelinseln ergänzt werden.

### B. Spielrolle: Flachufer + tiefe Mitte
1. Das **Flachwasser** (Uferband ca. 2,5 m breit auf der Wasserseite) ist begehbar, bremst aber alle Figuren auf `TUNING.SHALLOW_SLOW` (Start 0,6). Das gilt für den Schwarm, alle Gegner und die Moorbrut. Umgesetzt wird es wie Treibsand über `resolve_motion`.
2. Das **Tiefwasser** (Rest des Beckens) blockiert wie bisher über das SDF. Kollision entspricht der Optik: Die Tiefwasserkante liegt dort, wo die Farbe von Hell- zu Dunkeltürkis wechselt (± 0,3 m).
3. Flowfield, Bot-Routen und Spawns berücksichtigen, dass Flachwasser offen ist. Kokons, Schreine und Nester liegen nie im Wasser.

### C. Optik
1. **Eine durchgehende Wasserfläche pro Chunk.** Sie wird aus einem Mask/SDF-Bild in einem Draw-Call mit eigenem `shaders/water.gdshader` gezeichnet (GL Compatibility, unshaded oder einfach beleuchtet). Scheiben-Ketten gibt es nicht mehr.
2. Farbverlauf: Ufer mit schmalem Schlamm- oder Sandsaum, dann Flachwasser hell-türkis und leicht durchscheinend, zur Tiefe dunkler. Dazu eine feine helle Schaumlinie am Ufer, sanfte animierte Lichtflecken und leichte Wellen in Weltkoordinaten, ohne sichtbare Nähte an Chunk-Grenzen.
3. Deko ohne Kollision: Schilf am Ufer, Seerosen im Flachwasser, selten ein Stein im Tiefwasser (Deko, keine Kollision).
4. Biome:
   - **Glutsumpf:** dieselbe Form als Lava. Der Rand ist Kruste und begehbar mit Bremse; die Mitte ist Lava, blockiert, und nutzt die Optik des bestehenden `lava.gdshader`.
   - **Wüste:** die Oase als Wasser mit Sandufer.
5. Der Rand der Karte (`arena_border.gd` Wasser-Segmente) nutzt dieselbe Optik oder zumindest zusammenhängende Flächen ohne Perlenketten.
6. Leistung: höchstens 1–2 zusätzliche Draw-Calls pro Chunk. Chunk-Bau innerhalb des bisherigen Budgets (`chunk_build_ms_max` messen). Die Bench-Szenen aus `tests/perf_bench.gd` dürfen nicht spürbar langsamer werden.

## Nachweis
- Tests: `map_layout`, `map_bounds`, `arena`, `desert_run` grün, und ein neuer Test `tests/water.gd`. Er prüft:
  - Becken-Größen und Anzahl je Sumpf-Region
  - Flachwasser bremst, Tiefwasser blockiert
  - Kollision entspricht der Optik
  - Verbindungen, POIs nicht im Wasser
- Prüfbilder: Sumpf aus der Spielkamera, Übersicht, Oase, Glutsumpf, Kartenrand-Wasser, jeweils vorher und nachher.

## Ergebnis (28.09.2026)

- **Formen:**
  - Je Sumpf-Region gibt es 1–2 große Becken (16–25 m, Vereinigung aus 3–5 Scheiben plus leichtem Wackeln) und 0–3 kleine Tümpel (3–6 m).
  - Die Oase ist ein einzelner großer Teich.
  - Der Rest des Sumpfs ist offenes Moor; Inseln sind auf 16 % gedeckelt.
  - Um jedes Ufer bleiben 5 m frei.
  - Die Felder `water` und `water_deep` (vorzeichenbehafteter Abstand zur Uferlinie bzw. Tiefkante) liegen in `map_explore.gd`.
- **Spiel:**
  - Flachufer 2,5 m breit, bremst auf 0,6 (`SHALLOW_*` in `tuning.gd`, `arena.shallow_factor`, dieselbe Bremse in `horde.gd`).
  - Tiefwasser blockiert über `sdf = min(Wände, water_deep)`.
  - Die gezeichnete Tiefkante liegt höchstens 0,26 m neben der Kollision.
- **Optik:**
  - `shaders/water.gdshader`: eine Fläche pro Chunk mit Uferrand, hellem Flachwasser, Kante zur dunklen Tiefe, Schaumlinie, Glitzern und Seerosen.
  - Glutsumpf: Krustenring plus Lava aus Platten und Adern.
  - Wüste: Oasenfarben.
  - Kartenrand: durchgehendes Seeband.
  - Scheibenketten gibt es keine mehr.
- **Leistung** (Desktop-Bench): Frame-Zeiten unverändert (worst 7,7 ms, calm 3,9 ms), Draw-Calls ±10. Chunk-Bau höchstens ~7,4 ms statt 6,1 ms (Rand-Chunks), Kartenerzeugung +20–35 ms.
- **Tests:** `tests/water.gd` neu; arena (Fingerabdruck neu gesetzt), map_layout, map_bounds, desert_run, horde und flood grün. Prüfbilder `preview_water_*`, Vorher-Bilder `previews/before_*`.
- **Offen:**
  - Lava wirkt in der Spielkamera noch eher braun als glühend; die Farben nachschärfen.
  - Die alte Graph-Karte (18b, nur in Tests) nutzt noch Scheiben.
  - Schilf steht nur im Tiefwasser (Regel: kein Kleinzeug auf begehbarem Boden).
  - Am Gerät prüfen.