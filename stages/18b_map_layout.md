# Etappe 18b – Karte aus Lichtungen, Wegen und Engpässen

Nutzer-Feedback (27.09.2026) zur Etappe 18: „Die Map mit den Wegen wirkt noch sehr willkürlich. Ich hätte schon gerne, dass Wege auch wo hin führen und nicht alles random ist. Wege sollen auch gewissermaßen Engpässe sein, wo eben Wände und Props im Weg liegen. Man soll schon auch mitdenken, wo man gerade hin oder entlang pathed …“

## Abnahmekriterien
1. **Graph statt Streuung:** Jede Karte mit Seed besteht aus Lichtungen (Knoten) und Wegen (Kanten), dazwischen undurchdringliches Gelände. Solo 8–12 Lichtungen (30–50 m) plus eine große zentrale Lichtung. Typen: Start, Nest, Kokon, Pilzknollen-Hain, Totem, Boss-Arena (50–60 m), Migrationsschlund (am Rand gegenüber), Landmarke. API `arena.poi_slots(type)`, `arena.clearings()`, `arena.paths()`.
2. **Wege:** Jeder Weg verbindet zwei Lichtungen; 8–14 m (Engpass) bis 20 m (Hauptweg); Sandweg mit Rändern aus Props. Wichtige Lichtungen: kurz und eng gegen lang und offen. Graph zusammenhängend, keine Sackgassen, mindestens zwei Schleifen durch die Mitte.
3. **Wände:** Aus vorhandenen Modellen (Fels, Blätter, Stämme, Wurzelbogen, Riedgras, Wasser; Glutsumpf Basalt, verkohlte Stümpfe, Lavakruste), dicht und ohne Lücken, dunkler Boden darunter; Kollision über Zellraster in `resolve_motion`/`is_open`, Gleiten an Wänden, kein Tier quetscht sich durch; Wände zwischen Kamera und Schwarm niedrig.
4. **Navigation:** Gemeinsames Flussfeld (`arena.flow_direction`), `steer_direction` nutzt es; ≤ 0,3 ms je Frame; die Flut kommt über die Wege.
5. **Platzierung:** Nester, Totems, Apex, Schlund und Start auf passenden Lichtungen; Ausbrüche auf Wegen/Lichtungen; Drops in Wänden auf freien Boden; `spawn_points(n)` auf Start-Lichtungen.
6. **Minimap:** Wände dunkel, Wege hell, Lichtungen mit POI-Symbolen, Nebel wie gehabt.
7. **Balance:** Bot navigiert über die Wege, hängt nicht an Wänden; Zielkurven prüfen.
8. **Designregel** in `DESIGN_BRIEF.md` und `CLAUDE.md` aktualisiert.
9. **Tests:** `tests/map_layout.gd` (neu, in `tools/test.ps1`), bestehende Tests angepasst und grün (isoliert geprüft).
10. **Bildprüfung:** Übersicht für drei Seeds je Biom, Spielkamera an Engpass mit Horde, Nest-Lichtung, Boss-Arena, zwei Routen; mindestens drei Iterationen.

## Ergebnis (27.09.2026)

### Aufbau
- **`scripts/map_layout.gd` (neu, reine Daten):** Seed → Lichtungen → Typen → Graph → Wegformen → Ausstattung → Wandabstandsfeld.
  - Lichtungen: Start-/Ankunftspunkte als feste Knoten (Solo: Hub 30–33 m Radius in der Mitte), Boss-Arena (Radius 26–29 m) weit weg vom Start, Schlund (18–21 m) nahe am Rand möglichst weit von der Boss-Arena, danach Best-Candidate-Würfe mit ≥ 30 m Wand zwischen den Rändern und 14 m Wand zum Kartenrand. Solo: 11 Lichtungen (Hub + 10), Duo 17.
  - Typen: der erste jeder Art in Startnähe, weitere möglichst weit gestreut (Nest ×3, Kokon ×2, Totem, Hain, Landmarke …); bei zu wenigen Lichtungen teilen sich Typen eine Lichtung (zweiter Platz auf halbem Radius).
  - Graph: Delaunay-Kandidaten (ohne Wege, die eine dritte Lichtung streifen) → Minimalbaum als breite Hauptwege → schmale Zusatzwege, bis jede Lichtung ≥ 2 Ausgänge hat, der Hub ≥ 3, **keine Brücke** (kein Weg, dessen Wegfall die Karte teilt) und ~5 Schleifen. Wegmündungen liegen ≥ 34° auseinander.
  - Wege: leicht gebogene Mittellinien (quadratische Bézierkurve), Hauptweg 14–18 m (±8 % Wellung), enger Weg 9,6–12 m mit einer Engstelle von 8,8 m. Boss-Arena und Nester bekommen einen kurzen engen und einen langen breiten Zugang. Konflikte (Wege zu nah aneinander oder an einer fremden Lichtung) werden erst begradigt, dann wird der Zusatzweg gestrichen.
  - Ausstattung: POI-Plätze je Typ (Hain 5, Kokon 2, sonst 1), Landmarke (Wurzelbogen, Stamm, Teich, Wiese) in Landmarken-Lichtungen, 0–2 Deckungsfelsen je Lichtung, 3 Säulen in der Boss-Arena, keine am Start.
  - Wandabstandsfeld: 2-m-Raster, Lichtungen als gewellte Kreise, Wege als Kapselketten, Kartenrand als Wand; bilinear abgefragt (`sample`, `gradient`). Aufbau 63–74 ms je Karte (Start, Migration).
- **`scripts/flow_field.gd` (neu):** Dijkstra (Kosten 2/3, keine Diagonale um Wandecken) auf dem 2-m-Raster mit Vier-Eimer-Warteschlange, doppelt gepuffert. `arena.sync` rechnet je Frame 320 Zellen (~0,3 ms); ein ganzes Feld (~6 200 offene Zellen) ist nach ~20 Frames (~0,35 s) fertig und wird neu begonnen, sobald der Schwarm sich 2 m bewegt hat. Richtung = gewichtetes Gefälle der vier nächsten Zellen (glatt über Zellgrenzen). Nebenbei sammelt es die Zellen in 24–44 m Laufweite (Flut-Spawns).
- **`scripts/arena.gd`:** baut Layout und Flussfeld je Seed/Biom/Kartengröße; Kollision `is_open`/`resolve_motion`/`safe_spawn` über das Wandabstandsfeld (Herausschieben entlang des Gefälles = Gleiten; tief in der Wand → nächster freier Punkt). `steer_direction`: gerade bei freier Sicht bis 14 m, sonst Flussfeld, sonst an der Wand entlang; Felsen werden seitlich umgangen. Neu: `has_layout`, `wall_distance`, `push_walls`, `poi_slots`, `clearings`, `paths`, `clearing_at`, `flow_direction`, `flow_distance`, `finish_flow`, `spawn_point_near`, `flood_point`, `nav_direction` (A* über `AStarGrid2D` auf dem Flussraster, für den Bot), `open_direction`. Wege als Sandbänder (42 % der Laufbreite) von Lichtung zu Lichtung mit runden Enden, Platz nur in Start-/Ankunftslichtungen; Glutsumpf als Glutkanal mit runden Enden. `map_features` liefert Wandproben für die Minimap, `map_overview` Lichtungen und Wege. **Seed 0 bleibt die offene Klassik-Karte** (Tests/F5).
- **`scripts/arena_border.gd`:** `build_walls` – Wandprops je Chunk als MultiMesh (Raster 2,33 m, Charakter je Voronoi-Fleck: Dickicht 46 %, Fels 26 %, Wurzelwall 16 %, Sumpfwasser 12 %; Glutsumpf: verkohltes Holz, Basalt, verkohlte Wurzeln, Lavakruste mit wenigen Glutpfützen, Glutpilze als leuchtende Wandkante). Vorn niedrig und dicht, dahinter groß, tief drinnen lichter und dunkler. Wände mit offenem Boden im Norden (zwischen Kamera und Schwarm) beginnen 0,4 m hinter der Wandlinie und sind in der Höhe gedeckelt (0,5 m + 0,95 m je Meter Tiefe). Darunter dunkler Waldboden (Glutsumpf fast schwarz).
- **`scripts/horde.gd`:** Flut-Brut entsteht an `flood_point` (Wegmündungen in 24–44 m Laufweite, ≥ 18 m Luftlinie), folgt ab 7 m vom Schwarm dem Flussfeld (je Brut alle 5 Logikrunden aufgefrischt), prallt an Wänden ab (Vorfilter über die nächste Rasterzelle).
- **`scripts/swarm.gd`:** Jedes Tier hält 0,3 m Abstand zu Wänden (nur nahe einer Wand aktiv).
- **`scripts/hunt_world.gd` (nur Platzierung):** Gegner-Spawns über `spawn_point_near` (offen, nicht hinter einer dicken Wand); Nest/Totem im nächsten Platz ihres Typs (≥ 14 m entfernt, nie derselbe wie zuletzt); Apex steigt in der nächsten Boss-Arena auf; Schlund öffnet in seiner Lichtung; nach einer Migration werden Nest/Totem auf freien Boden gesetzt. Klassik-Karte unverändert.
- **`scripts/ui/hud_minimap.gd`:** Wände dunkel (12 × 12 Proben je Chunk, bilinear), Wege hell, Lichtungen als Symbol (Boss, Schlund, Nest, Totem, Kokon, Hain; Start als Punkt), unter Nebel gedimmt.
- **Bot (`tests/balance_sim.gd`):** Ziele über `nav_direction`, Ausweichen über `open_direction`, ein weit entfernter Schlund wird zielstrebig angelaufen.

### API für Etappe 17 Welle 2
- `arena.poi_slots("cocoon")` → 4 Plätze (2 Kokon-Lichtungen × 2), `arena.poi_slots("grove")` → 5 Plätze (Pilzknollen-Hain), auf Seed 0 leer (dann eigene Platzwahl nötig).
- `arena.clearings()` / `arena.paths()` für Anzeige und Logik, `arena.clearing_at(point)`, `arena.is_open(point, r)`, `arena.safe_spawn(point, r)`.
- Minimap-Marker `CHEST`/`POWERUP` erscheinen zusätzlich als Lichtungssymbole.

### Tests
- `tests/map_layout.gd` (neu): 3 Seeds – 11 Lichtungen, 15 Wege (4–5 eng), 5 Schleifen, 0 Brücken, Hub-Grad 4–5, jeder Weg verbindet zwei Lichtungen, Breiten 8,8–20 m, Mittellinie offen; alle POI-Typen in Lichtungen auf freiem Boden; Boss-Arena ≥ 25 m Radius mit engem und breitem Zugang; alle Lichtungen per Flussfeld erreichbar; 60 Wand-Läufe je Seed (Radien 0,3–2,5 m): tiefstes Eindringen 0,000 m, 0 Durchtunnelungen; Punkte in der Wand nie offen; Tiere werden immer herausgeschoben; Jäger/Bog King/Apex erreichen den Schwarm aus jeder Lichtung (langsamster 65 s bei 3 m/s); Bot-Route erreicht Boss-Arena, Schlund und Nest; Flutpunkte offen in 24–44 m Laufweite; gleicher Seed = gleiche Karte (auch in neuer Arena); Duo 5 × 5 (17 Lichtungen, 24 Wege, 8 Schleifen, Starts ≥ 100 m, verbunden); Ankunftslichtung nach Migration.
- Angepasst: `tests/arena.gd` (Seed-Teil beschreibt das neue Layout, Fingerabdruck neu, Klassik-Karte unverändert), `tests/map_bounds.gd` (Randläufe/Eckspawns auf Seed 0, neue Pfadkarten-Spawns, Startlichtungen je Spielerzahl, Migration am Schlund), `tests/eruptions.gd` (Quellen auf Wegen).
- **Isoliert geprüft** (Kopie aus HEAD + Karten-Dateien, `hunt_world.gd` nur mit den Karten-Hunks, ohne Etappe 17): alle Tests grün, `balance_regress` im Median innerhalb der Toleranz.
- **Arbeitsbaum mit Etappe 17 Welle 1:** `tools/test.ps1` komplett grün einschließlich `endless_playthrough` und `balance_regress` (glutmaw/Wild Pop 2:00 Median 32, Brutal/Apex im Toleranzband).

### Nachtrag: `endless_playthrough` und Etappe 17
- Ursache für „Wild must survive 120 s“ war **nicht** die Karte: Der Lauf nutzt Seed 0 (offene Klassik-Karte), dort greift kein 18b-Code; mit der Arena von Etappe 18 ergab er dieselben Werte (Peak 13–16, teils fast ausgestorben).
- Ursache war Etappe 17: (1) Ein Run ohne RunConfig (F5, Tests) bekam keine Startwaffe mehr, weil Waffen nicht mehr über Level kommen. Jetzt trägt auch der Lauf ohne Config die Startwaffe des Standardstamms (`hunt_world._configure_run` auch in `_ready`). (2) Die Glutmaw-Startwaffe Rudelbiss springt nur bei gehaltener Rally; der einfache Test-Bot rallyte nur bei Kontakt. Er rallyt jetzt wie Spieler und Balance-Bot, sobald ein Gegner in 4 m ist. Schwellen des Tests unverändert. Ergebnis deterministisch: 120 s, Peak 44, 12 Verluste, Anführer 4/4.
- `tests/evolution.gd`: „Restart clears all evolution“ erwartet nach dem Neustart nur noch die Startwaffe.
- `tools/test.ps1`: `balance_regress` braucht auf der Wege-Karte ~190 s (3 × 5 Läufe) und bekommt das Dreifache des Einzel-Zeitlimits (der Test selbst ist unverändert).
- `tests/arena.gd`: Fingerabdruck neu gesetzt (Seed 4242 ist jetzt eine Wege-Karte; niedrige Wandfronten zur Kamera); die Klassik-Karte (Seed 0) ist unverändert.

### Leistung (Desktop)
- Flussfeld: 320 Zellen je Frame, Schritt 0,36–0,54 ms im Test (unter Last, headless), ganzes Feld 6–9 ms verteilt auf ~20 Frames.
- Kartenaufbau 63–74 ms (Layout) + ~5 ms (Flussraster); Chunkbau mit Wänden ~3,7 ms im Mittel (Randchunks vorher 2,6–3,0 ms), Rückkehr aus dem Wand-Cache günstiger.

### Bilder
- Übersicht: `preview_layout_verdant_{4242,777,90210}.png`, `preview_layout_glut_{4242,777,90210}.png`.
- Spielkamera: `preview_layout_choke.png`, `preview_layout_southwall.png`, `preview_layout_nest.png`, `preview_layout_boss.png`, `preview_layout_routes.png`, `preview_layout_glut_path.png` (`tests/capture_map_layout.gd`), Minimap `preview_minimap_*.png`.

### Iterationen der Bildprüfung
1. Graph lesbar, aber 16–20 m breite Sandstraßen kreuzten jede Lichtung, Wandcharakter wechselte in sichtbaren Quadraten, Stämme wirkten wie verstreute Stöckchen, Glutsumpf ohne Kontrast.
2. Sand schmaler und endet in den Lichtungen (Lichtungen wirken als Orte), Voronoi-Flecken, weniger Stämme, Glutpilze als Wandkante, dunkler Glutboden, runde Kanal-Enden.
3. Südwände: vordere Reihe weiter zurück und niedriger (Schwarm an der Wand bleibt sichtbar); Minimap-Symbole größer; Fehler behoben, durch den die Klassik-Karte im Glutsumpf zusätzliche Verdant-Wege bekam.

### Offen / ehrliche Bewertung
- Die Karte wirkt jetzt wie ein Level (Hub, Ring, Schleifen, Ziele an festen Orten). Die Wege sind aber recht gerade und ähnlich lang; von oben wirken die Wandflächen noch unruhig (viele kleine Props statt großer Formen). Eigene Wand-/Klippenmodelle würden stark helfen.
- An einer Wand südlich des Schwarms bleibt der Schwarm sichtbar, die vorderen Blätter überdecken aber die unterste Tierreihe leicht; eine echte Durchsicht (Transparenz bei Verdeckung) fehlt noch.
- Glutsumpf: Wand und Boden unterscheiden sich von oben noch zu wenig; in der Spielkamera tragen Glutpilze und Stümpfe die Kante.
- Kristalle, die nach einer Migration in einer Wand liegen, sind nur über Magnet/Lockruf erreichbar.
- Bog King spawnt weiter im Ring um den Schwarm (nicht in der Boss-Arena), damit der Takt der Mini-Bosse bleibt.
- Seed 0 (F5 ohne Menü) bleibt offen; echte Runs aus dem Menü haben immer einen Seed.
- Handtest am Gerät steht aus.
