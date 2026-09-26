# Etappe 02 – Welt und Figuren nach Konzept, alle vorhandenen Assets eingebaut

Referenzen (nur lesen): `C:\Users\vrxby\Documents\Codex\Swarm\Design\` – `MAWLINGS_MAP_TOPDOWN_HYBRID_V3.png` (Arbeitsreferenz Karte), `MAWLINGS_VISUAL_CONCEPT_02_PORTRAIT.png`, `MAWLINGS_ACTIVE_HUD_CONCEPT_PORTRAIT.png`, `HY3D_References/*.png` (Einzelobjekt-Vorlagen). Konzeptbilder bestimmen Stimmung und Farben, keine exakten Layouts; die Arena bleibt offen (`DESIGN_BRIEF.md`).

Vorher: flacher olivgrüner Boden, graubrauner Weg, Steine aus Kugeln, Nibbler aus Kugeln.

Neue Spielmodelle (aus den Nutzer-GLBs in `assets/` mit `tools/optimize_characters.py` erzeugt, Scheitelpunktfarben, eine Mesh je Datei):
- `assets/gameplay/characters/Nibbler_game.glb` – 2.500 Dreiecke, AABB ca. 0,56 × 1,15 × 0,83 (x × y × z), Mittelpunkt nicht am Boden (y von −0,62 bis +0,53); lange Achse Z → blickt nach ±Z (im Bild prüfen).
- `assets/gameplay/props/Rock_game.glb` – 1.500 Dreiecke, AABB ca. 0,90 × 1,02 × 0,43.
- `assets/gameplay/props/Leaf_game.glb` – 1.500 Dreiecke, AABB ca. 0,93 × 0,93 × 0,57.
Alle Modelle mit `shaders/creature.gdshader` (ShaderMaterial, vertex colours) rendern; ein gemeinsames Material je Modelltyp, nie pro Instanz neu.

## Abnahmekriterien

1. **Boden wie Konzept V3:** warmes, helleres Moosgrün als Grundfläche, warmer Sandweg mit weicher Kante, vereinzelte Sand-/Erdflecken und Kiesel; ruhig genug, dass Schwarm, Kadaver und Warnflächen klar dominieren.
2. **Felsen:** Die Kollisionssteine nutzen `Rock_game.glb` (deterministische Drehung/Variation je Position), passend zur **unveränderten** Kollisionsfläche `OBSTACLE_RADIUS = 1.85`; Moos-/Blattsockel statt Kugeln.
3. **Blätter:** `Leaf_game.glb` als Blatthorste an Felsen und vereinzelt am Rand der offenen Fläche, nie mitten auf dem Weg; ohne Kollision, niedrig genug, dass sie keine Warnringe verdecken.
4. **Wasser:** Teich mit hellerem Türkis und hellem Uferrand wie im Konzept, weiterhin begehbar.
5. **Nibbler:** `Nibbler_game.glb` statt Kugelfigur, etwas größer als ein Mawling, türkis mit Rim; blickt in Laufrichtung, hüpft beim Fliehen, schaut sich im Stand um, Schatten, Blitz bei Bissen; Lebensleiste bleibt.
6. **Regeln/Technik:** Kollision, Spawn, Fluchtlogik und Trefferradien unverändert; alle Tests grün; arena-Test unverändert bestanden; Chunk-Aufbau bleibt günstig (geteilte Meshes/Materialien).

## Ergebnis (26.09.2026)

Auf Nutzerwunsch zu einer Mehrstrang-Etappe erweitert: fünf parallele Agenten mit getrennten Dateien (Karte, Nibbler, Shader-Animation, UI, Mire Leaper), Zusammenführung und Prüfung durch die Hauptsitzung.

- **Karte (`arena.gd`):** Boden `#80a04c`, Sandweg `#d4b377` mit Randstreifen, Sand-/Erdflecken, Kiesel; Felsen aus `Rock_game.glb` (~3,5 × 1,4 × 3,6 m auf Kollisionsradius 1,85), Blatthorste aus `Leaf_game.glb` nie auf dem Weg, Teich `#3fc0c4` mit Ufer. Geteilte Meshes/Materialien, Kollision unverändert. Kriterien 1–4 erfüllt; Flecken sind hartkantig.
- **Nibbler (`prey.gd`):** `Nibbler_game.glb`, 1,0 m hoch, Kopf +Z (im Bild verifiziert), Hüpfflucht, Umschauen, Schatten, Biss-Flash. Kriterium 5 erfüllt.
- **Animation (`shaders/creature_anim.gdshader`):** diagonaler Beinzyklus, Kiefer, Schwanz per Vertex-Shader mit `instance uniform` (funktioniert in GL Compatibility 4.7); Mawling und Bog King. In Nahaufnahme klar, aus der Spielkamera kaum sichtbar.
- **UI (`touch_controls.gd`):** organische Rahmen, Mawling-Kopf, Segment-Druckleiste mit Schädel, DNA-Helix, glühender Rally, Mutationskarten mit Kategorie, Rang-Rauten und Vorher/Nachher, neuer Ergebnisbildschirm, Leaper-Zähler.
- **Mire Leaper (`mire_leaper.gd`, neu):** ab 60 s, max. 3, Bogensprung auf fest markierte Landezone (2,6 m, Warnung 1,1 s), ein Treffer, danach 2 s erschöpft; 15 DNA, 20 dauerhafte Biomasse. Test `leaper.gd`.
- **Tests:** alle 12 grün. Der Playthrough-Bot weicht jetzt auch Leaper-Zonen aus: `population=54 peak=93 kills=16 lost=89 extinct=false` (vorher 103/127) – der Druck ist spürbar gestiegen.

Offen: Handtest und Balance mit Leaper, Shader-Beine aus der Spielkamera verstärken, weiche Bodenflecken, Nutzermodelle Mire Reaper, fallen log, pond seeds, root arch einbauen, DNA-Popups an der Kill-Stelle.
