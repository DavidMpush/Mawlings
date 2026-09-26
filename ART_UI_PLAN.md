# MAWLINGS – aktiver Art- und UI-Plan

Stand: 26.09.2026. Grundlage sind die früheren Entwürfe `Swarm/Design/MUTATION_UI_GODOT_DIRECTION.md`, `VISUAL_DIRECTION_V2.md`, `HY3D_GODOT_WORLD_PLAN.md` und `MAP_DIRECTION_OPEN_ARENA.md`. Die Konzeptbilder definieren Stimmung und Lesbarkeit, keine exakten Layouts oder zu kopierenden Figuren. Dieses Dokument beschreibt den Stand des aktiven Godot-Projekts.

## Gestalterische Regeln

- Mobiles Hochformat, leicht geneigte Kamera, offene Kampfzone. Gut drei Viertel des sichtbaren Bodens sollen ruhig und begehbar wirken; Steine bilden nur vereinzelte umgehbare Engstellen.
- Spieler zuerst: warmes Korallrot/Orange, klare Schwarmform. Beute Türkis, Jäger Violett, Skitter Blau/Magenta, Biomasse Bernstein. Gefahren haben feste, unterschiedlich geformte Warnflächen zusätzlich zur Farbe.
- 3D-Formen mit breiten Farbflächen und lesbarer Silhouette. Keine fotorealistische Dschungeldichte. Requisiten sollen Kämpfe und Kadaver nicht verdecken.
- UI ist funktional: Population links, Zeit/Druck mittig, DNA/Evolution rechts. Pause oben rechts; Bewegung unten rechts, Rally unten links. Die Bildschirmmitte bleibt frei. Biomasse und Kadaverhinweis erscheinen kontextuell.

## Umgesetzter erster Pass

Das HUD verwendet drei kompakte obere Felder mit eigenen abgeschrägten Konturen, gedecktem Dunkelgrün und je einer funktionalen Akzentfarbe. Rally und Joystick haben große Touchziele. Bei Mutationsauswahl dunkelt die Welt ab, die obere Statuszeile bleibt lesbar und die Steuerung tritt zurück. Drei große Karten besitzen sechs eigenständige Code-Icons, Rang und den numerischen Effekt vor/nach der Wahl. Pause und Run-Ende zeigen den Build. Hochformatansichten mit 25 und 250 Population, langen Kartentexten und Ergebnisanzeige wurden gerendert und geprüft.

Das vom Nutzer gelieferte `assets/source/mawling/Mawling.glb` bleibt als Roh-Asset erhalten. Es enthält 50.000 Dreiecke, drei 4096er Texturen und keine Animation. Für den laufenden Schwarm wurde daraus `assets/gameplay/characters/Mawling_game.glb` mit 3.000 Dreiecken und gemittelten Scheitelpunktfarben erzeugt (136 KB statt 32 MB). Die sichtbaren Tiere nutzen dieses Modell; maximal 120 Instanzen stehen für bis zu 250 logische Mawlings. Größe und Abstand verändern sich mit der Population. `tools/optimize_characters.py` erzeugt die Spielversion reproduzierbar mit Python, NumPy, Pillow und `fast-simplification`.

Der Bog King nutzt dieselbe Formensprache und sein eigenes geliefertes Modell. Die 8.000-Dreieck-Spielversion ist siebenfach skaliert und erscheint nach 90 Sekunden mit eigenem Lebensbalken und großem, angekündigtem Stampfkreis. Damit bleibt er im Hochformat gegenüber dem Schwarm klar erkennbar. Die Originaldatei liegt unter `assets/source/bog_king/`, die Spielversion unter `assets/gameplay/characters/`.

## Nächste Schritte im Stil

1. **Weltmaterial:** ruhiger, leicht strukturierter Sand-/Moosboden und seltene klare Landmarken. Die bestehenden Laufwege und Steine bleiben offen; keine Randwände aus Laub.
2. **Weitere Figuren:** Nibbler, Jäger und Skitter in derselben vereinfachten Formensprache modellieren oder vorhandene passende Assets aufbereiten. Ihre Warnflächen müssen in der Spielansicht stärker auffallen als Oberflächendetails.
3. **Bewegung und Treffer:** kurze Dreh-, Lauf- und Reaktionsbewegungen am Mawling-Modell; gebündelte statt dutzender Schadenszahlen. Das Roh-Asset hat kein Skelett/keine Animation, daher zunächst sparsame prozedurale Bewegung.
4. **Geräteprüfung:** Touchabstände und Leistung auf dem Samsung S25 prüfen. Bei hohen Populationen zuerst Modellanzahl, Material-/Draw-Calls und Deckung durch Dekoration messen und anpassen.

