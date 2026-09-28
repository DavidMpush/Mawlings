# Etappe 18c – Erkundungskarte

Nutzer-Feedback (27.09.2026) zur Lichtungskarte aus 18b: „Mit dem Map Design bin ich aktuell überhaupt nicht zufrieden. Die ist mir viel zu linear und langweilig. Ich sehe von Anfang an auf der Minimap, wo welche POI sind, das wollte ich so nicht. Es soll schon mehr einen Random-Faktor wie bei Megabonk geben, wo man die aktuelle Map erforschen will und am Weg schon Ressourcen farmt, die mehr oder weniger random verteilt werden.“ Weiterhin gilt: natürliche Engpässe, mitdenken bei der Route.

18c ersetzt den Lichtungs-/Korridor-Graphen als Standard. Weiterverwendet: begrenzte 4 × 4-Karte, natürlicher Rand, Kollision über das Wandabstandsfeld, Flussfeld, Wandbausteine, Minimap-Nebel, Seed = gleiche Karte, Migration = neue Karte. Die 18b-Karte bleibt über `arena.layout_style = "graph"` baubar.

## Abnahmekriterien
1. **Gelände statt Korridore:** Jede Region würfelt einen Landschaftstyp (Wiese, lichter Wald, Dickicht, Ruinenfeld, Felsrücken, Sumpf, Felslabyrinth; Glutsumpf-Varianten). Die Übergänge sind organisch. Engpässe entstehen natürlich, es gibt immer mehrere Routen und nichts ist abgeschnitten. 25–35 % der Fläche sind blockiert. Sandwege gibt es nur als lose Trampelpfade.
2. **Nebel des Unbekannten:** Minimap und große Karte zeigen nur Gesehenes (Sichtradius ~28 m). POIs und Randzeiger erscheinen erst nach der Entdeckung (Ausnahme: angekündigter Boss, Schlund). Hohe Landmarken locken von weitem.
3. **Zufällige Orte** (Poisson-artig, mit kleiner Freifläche):
   - 10–14 Kokons, 2–3 goldene Kokons, 4–6 Schreine, Nester, Totems, Pilzknollen-Haine, 2–3 Elite-Lager;
   - eine offene Boss-Arena irgendwo, ein zufälliger offener Start; Multiplayer weit auseinander.
   - API: `poi_slots`, `discovered`, `is_discovered`, `discover_around`.
4. **Beute am Weg:** 60–90 Bernsteinknollen (dichter in Wald, Ruinen und am Rand). Ein Kontakt zerbricht sie; sie geben Kristalle, Power-up- und Relikt-Hooks und sind tiefer und gefährlicher liegend wertvoller. Sie bleiben liegen, bis sie zerbrochen sind.
5. **Aus der Bildprüfung:** Keine Verdeckung des Schwarms (Schwarm + ~6 m Ring immer sichtbar); Ruinen als Gebäudereste; Glutsumpf-Variante; Kartenaufbau ≤ 120 ms.
6. **Tests/Doku:** Tests auf 18c, `tools/test.ps1` grün, diese Datei, finale Bilder.

## Ergebnis

### Generator `scripts/map_explore.gd` (neu)
- **Landschaften:** Region-Seeds mit Domain-Warp ergeben organische Grenzen. Jede Landschaft hat eine eigene Dichtefunktion und einen eigenen Ziel-Blockieranteil:

  | Landschaft | Aufbau | Ziel blockiert |
  |---|---|---|
  | Wiese | seltene Felsgruppen | 7 % |
  | Wald | Baumgruppen um Zellrauschen | 26 % |
  | Dickicht | geschlossene Masse mit Gassen | 58 % |
  | Felsrücken | Rauschkonturen mit Durchbrüchen | 24 % |
  | Sumpf | Tümpel | 36 % |
  | Labyrinth | Felsnähte | 40 % |
  | Ruinen | Grundrisse (feste Form, siehe unten) | – |

  Alles wird gemeinsam skaliert. Ergebnis: **27–29 %** blockiert (Seeds 4242, 777, 90210).
- **Ruinen:** Hausgrundrisse auf einem schrägen 20-m-Raster. Räume 8–13 m mit 2,4 m starken Mauern, Türöffnungen in den meisten Seiten, eingestürzte Abschnitte; die Ecken stehen immer (L-Winkel). Lose Säulen stehen dort, wo sich vier Grundstücke treffen.
- **Nichts abgeschnitten:** Kleine offene Taschen werden gefüllt, größere bekommen eine gegrabene Lücke. Große Körper (Bog King, Apex) brauchen breiten Boden: Jede breite Fläche mit einem Ort oder ≥ 70 Zellen bekommt einen ~8 m breiten Korridor zum Hauptgebiet (zwei Runden, Landmarken-Steine zählen als Hindernis).
- **Orte** (solo):
  - 12 Kokons, 3 goldene Kokons (bevorzugt in Gefahrenzonen, weit vom Start), 5 Schreine, 8 Nester, 5 Totems, 7 Haine, 3 Elite-Lager;
  - eine Boss-Arena (Radius 24 m), der Schlund weit weg von ihr, ein zufälliger offener Start, 4 Landmarken;
  - jeder Ort mit einer gewellten Freifläche. Duo 5 × 5 skaliert die Anzahl nach Fläche.
- **Trampelpfade:** 6–10 schmale, per A* dem Gelände folgende Pfade zwischen wichtigen Orten (45–120 m, je Ort höchstens 2); nur Optik.
- **Bernsteinknollen:** 65–85 je Karte, Wertstufe 0–2 nach Entfernung vom Start und Gefahrenzone.
- **Wandabstandsfeld:** Ein zweiseitiger Chamfer-Durchlauf über die Maske plus Kartenrand.
- **Aufbauzeit:** Das Rauschen kommt nativ über `FastNoiseLite.get_image`.
  - Leerlauf: 112–143 ms, kurz vor den Breitkorridoren gemessen. Deren BFS ist optimiert, aber nicht erneut im Leerlauf nachgemessen.
  - Unter Last mit bis zu 20 parallelen Godot-Prozessen: 180–420 ms. Das Ziel ≤ 120 ms ist also nicht sicher erreicht.

### Navigation
- Zweites Flussfeld für große Körper (`flow_big`, nur Boden mit ≥ 3,4 m Wandabstand). Die beiden Felder rechnen im Wechsel je Frame. `steer_direction` nimmt ab einem Radius von 1,5 m das große Feld (Ausweg: das normale Feld).
- Kollisionskreise (Landmarken) sperren im Flussraster.
- Zur Aufnahme: Bog King und Apex erreichen den Schwarm von allen breiten Orten.

### Entdeckung
- `arena.discover_around(pos, r)` läuft mit dem Nebel (Sichtradius 28 m). Dazu `is_discovered(pos)` und `discovered(type)`.
- Die Minimap zeigt Unerkundetes schwarz. Ortssymbole und die Live-Marker für Nest und Totem erscheinen erst nach der Entdeckung, ebenso die Randzeiger für Nest und Totem (`hunt_world._found`).
- Boss, Apex und Schlund bleiben wie bisher sichtbar.
- Der Balance-Bot kennt weiter alle Ziele.

### Darstellung
- **Durchsicht:** Alle Props nutzen `shaders/prop_fade.gdshader`. Fragmente zwischen Kamera und Schwarm werden weggedithert (Bildschirmkreis des 6,5-m-Rings, näher an der Kamera als der Schwarm, höher als 0,45 m). `arena.sync` setzt die Schwarmposition.
- **Landmarken** (`scripts/map_beacons.gd`): Riesenbaum, Knochensäule, leuchtender Pilzturm, Steinnadel, außerhalb der Chunks gebaut.
- **Wände:** neue Charaktere Ruine (helle Mauerblöcke entlang der Mauerlinie, durchgehend), Säule (Schaft plus liegende Trommel) und Baumgruppe (Stamm mit Krone; Glutsumpf verkohlt mit Glutpilzen).
- **Knollen:** Bernstein-Material, Glühen steigt mit der Stufe.

### Hooks für Etappe 17 Welle 2
- `poi_slots("cocoon" | "cocoon_gold" | "shrine" | "grove" | "elite" | "nest" | "totem" | "boss" | "maw" | "start")`, `discovered(type)`, `is_discovered(pos)`.
- `hunt_world.loot_nodes.bonus(kind, at)` mit `kind` = `"powerup"` oder `"relic"`.
- Minimap-Symbole für `cocoon`/`cocoon_gold` (Kokon), `grove` (Pilzknolle), `elite` und `shrine`.

### Tests
- `tests/map_layout.gd` auf 18c umgebaut:
  - für 3 Seeds: ≥ 4 Landschaften, 22–38 % blockiert (Ist: 27–29 %), ≤ 1 % offene Zellen abgeschnitten, alle Ortsarten in Mindestzahl auf offenem, erreichbarem Boden, Boss-Arena breit, Schlund weit weg;
  - Wand-Läufe ohne Eindringen und ohne Durchtunneln; Jäger, Bog King und Apex erreichen den Schwarm von den weiten Orten; Bot-Route zu Boss, Schlund und Nest; Flutpunkte;
  - 60–90 Knollen, tiefer liegend besser; Landmarken; Entdeckung (am Start nur wenige Orte bekannt); Determinismus; Duo; Ankunft; die 18b-Graph-Variante baut weiter.
- `tests/arena.gd`: Seed-Teil auf zufälligen Start und Landmarken-Steine umgestellt, Fingerabdruck neu (Prop-Shader).

### Bilder
- `preview_explore_4242.png`, `preview_explore_777.png`, `preview_explore_90210.png` (Übersicht Verdant)
- `preview_explore_glut.png`, `preview_explore_glut_forest.png` (Glutsumpf)
- `preview_explore_minimap.png` (große Karte mit Nebel nach dem Start)
- `preview_explore_forest.png` (Wald mit Lücken, Durchsicht)
- `preview_explore_ruins.png`, `preview_explore_ruins_top.png` (Ruinenfeld mit Knollen, Grundrisse von oben)

Erzeugt mit `tests/capture_map_explore.gd`.

### Balance und Prüfstand (28.09.2026, parallel laufende Agenten)
- **Kartenseitig behoben:**
  - Die drei Start-Nibbler entstanden an festen Koordinaten um den Weltursprung, der 18c-Start ist aber zufällig. Jetzt entstehen sie um den Start. Ergebnis: Population nach 60 s 6–13 statt 2–3.
  - Die Boss-Arena liegt jetzt mindestens ~110 m vom Start entfernt.
  - Der Bot zerbricht Knollen in 12 m Umkreis.
- **`balance_regress` ist rot, im Kern nicht durch die Karte:** Im selben Arbeitsbaum ist auch die 18b-Graph-Karte grenzwertig bzw. zu schwach.
  - Wild: Median Peak 20, Population nach 2:00 = 15.
  - Apex: Median ~198 s, kaum Flut.
  - Ursache ist Welle 2 von Etappe 17 (`SIGNATURE_START_RANK` 4 → 1, Werte/Kokons neu).
- **18c im Vergleich:**
  - Wild: Peak 24, Population nach 2:00 = 14 (Ziel ≥ 15).
  - Sporling/Apex: Peak 24 (Ziel ≥ 25).
  - Glutmaw/Apex: Median 144 s, Peak 20, keine Flut.
  - Die Kurven gehören mit Welle 2 neu balanciert.
- **Weitere Fehler anderer Agenten:** `corpse_visuals` (Zeitlimit, `apex_sandworm` fehlt im Wörterbuch; Aschenkröte/Apex-Agent). `endless_playthrough` bestand mit Peak 17 (Seed-0-Karte, knapp).

### Offen
- Die Ruinen bestehen aus dem Felsmodell: Die Grundrisse lesen sich von oben klar, aus der Spielkamera noch steinig. Eigene Mauer- und Säulenmodelle würden stark helfen.
- Die Glutsumpf-Übersicht ist dunkel und kontrastarm; aus der Spielkamera lesen sich verkohlter Wald und Glutpilze gut.
- Die Landmarke ist im Ruinenbild noch nicht in der Ferne zu sehen.
- Knollen-Balance nur grob über `balance_regress` geprüft.
- Draw Calls: Seed 4242 hat 522 statt 383 Teile in 3 × 9 Chunks (mehr Wandcharaktere je Chunk).
- Aufbauzeit unter Last über dem Ziel (siehe oben).
- Handtest am Gerät steht aus.

## Folgerunde: große, eindeutige Hindernisse (28.09.2026)

Nutzer-Feedback: „Teilweise liegt so viel Kleinzeug herum, wo man oft nicht direkt weiß, ob man da drüberlaufen kann oder davor hängen bleibt … wirklich große visuelle Elemente, wo man direkt checkt: da muss ich ausweichen.“

**Regel** (auch in `DESIGN_BRIEF.md` und `ART_UI_PLAN.md`): Blockierend sind nur große, eindeutige Formen mit dunklem Boden-Fußabdruck; kein Kleinzeug auf begehbarem Boden; Kollision = Optik (± 0,3 m); das gilt auch für die Klassik-Karte und den Rand.

**Umsetzung**
- **Wände je Rasterzelle** (`arena_border._cell_walls`, Erkundungskarte): Jede blockierte 2-m-Zelle trägt genau ein großes Element ihres Charakters:
  - Fels: Block von 2,7 m Grundfläche, innen höher.
  - Dickicht/Wurzel: Buschmasse, innen Stämme.
  - Baumgruppe: Stamm mit Krone innen, Busch am Rand.
  - Wasser: Wasserscheiben bis zur Kante.
  - Ruine/Säule: Mauerquader je Zelle mit gebrochenen Höhen.
  - Glutsumpf: Basalt, verkohlte Stümpfe, Kruste.

  Die Wände sind damit durchgehend, ohne lose Kleinteile, und enden an der Kollisionskante. Zur Kamera hin sind sie niedrig, tief drinnen lichter.
- **Grundflächenprüfung** (`_fits`) für alle übrigen Wand- und Randprops (18b-Graphkarte, Kartenrand): Die Kantenmitten der ausgerichteten Grundfläche müssen innerhalb von 0,3 m in der Kollision liegen, die Ecken innerhalb von 0,8 m. Sonst schrumpft das Prop; unter 0,75 m entfällt es. Die Randfront wellt nur noch 0–0,3 m statt bis 2,6 m (vorher unsichtbarer Rand).
- **Boden-Fußabdruck:** Der dunkle Wandboden setzt jetzt scharf an der Kollisionskante ein (feineres Raster, 1,17 m), mit einer dunkleren Kontaktkante.
- **Generator:** Blockierte Flecken unter 4 Zellen (~3,5 m) werden zu offenem Boden. Ruinensäulen sind 3,6 m breit.
- **Kleinzeug entfernt** (auch auf Seed 0): Kiesel, Blatthorste, einzelne Blumen, Riedgras und Glutpilze an Pfützen, Blätter um Steine, Blumen der Wiesen-Landmarke, Schlackeklumpen am Lavateich. Es bleiben flache Moos- und Sandflecken. Glutsumpf-Steine sind eine große Basaltsäule statt drei schmaler.
- **Landmarken:** Die Sockel entsprechen dem Kollisionskreis (Riesenbaum-Stamm 5,2 m, Knochensäule und Steinnadel entsprechend), dazu ein dunkler Fußabdruck. Wurzelbogen am Baum und Pilzturm sind entfallen (ihre Optik ragte über die Kollision hinaus).
- **Nebeneffekt:** deutlich weniger Draw Calls (3 × 9 Chunks: Seed 0 726 → 370, Seed 4242 522 → 281).

**Prüfung**
- Spielkamera:
  - `preview_explore_forest.png` (Wald)
  - `preview_explore_ruins.png` (Ruinen)
  - `preview_explore_rocks.png` (Felsrücken)
  - `preview_explore_swamp.png` (Sumpf)
  - `preview_explore_glut_forest.png` (Glutsumpf)
- Kollision in Rot über der Optik: `preview_explore_forest_collision.png` (Spielkamera) und `preview_explore_ruins_collision.png` (Draufsicht). Die Kanten decken sich.
- Tests `map_layout`, `arena`, `map_bounds`, `minimap` grün.
- Fingerabdruck in `arena` neu gesetzt: Die Klassik-Karte verliert das Kleinzeug, Glutsumpf-Steine sind eine Säule, die Wände sind zellbasiert.

**Offen**
- Ruinen sind Quader aus dem Felsmaterial: klar lesbar, aber noch sehr hell und schlicht; eigene Mauermodelle würden helfen.
- Sumpfwasser zeigt das Scheibenraster.
- Flache Pfützen der Klassik-Karte und die Teich-Landmarke sind weiter begehbar. Sie sind jetzt ohne Aufbauten, könnten aber noch als Hindernis gelesen werden.
- Die Kronen der Riesenbäume überragen die Kollision in der Höhe (durch das Durchsichtsfenster entschärft).