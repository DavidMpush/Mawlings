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

## Bewegungs- und Feedback-Pass (Etappe 01)

Beide gelieferten Modelle nutzen jetzt `shaders/creature.gdshader`: Scheitelpunktfarbe mit Helligkeit/Sättigung, weiches Formlicht, farbige Randkontur gegen den grünen Boden und Treffer-Blitz. Mawlings bewegen sich prozedural (Blickrichtung, Hüpfgang, Atmen, Beißen, Picken, Schlüpfen, Wegschleudern), der Bog King mit schwerem Gang, Aufbäumen, Stampfen und Erschöpfungspose. Warnflächen zeigen die Restzeit durch eine wachsende Füllscheibe. Prüfbilder: `tests/capture_motion.gd`, `tests/capture_boss.gd`. Das Bog-King-GLB blickt lokal nach +Z, das Mawling-GLB nach +X; der Boss wird deshalb im Code um −90° gedreht. Neue Modelle sollten einheitlich nach +Z blicken (siehe `assets/README.md`).

## Nächste Schritte im Stil

1. **Weltmaterial:** ruhiger, leicht strukturierter Sand-/Moosboden und seltene klare Landmarken. Die bestehenden Laufwege und Steine bleiben offen; keine Randwände aus Laub.
2. **Weitere Figuren:** Nibbler, Jäger und Skitter in derselben vereinfachten Formensprache modellieren oder vorhandene passende Assets aufbereiten. Ihre Warnflächen müssen in der Spielansicht stärker auffallen als Oberflächendetails.
3. **Bewegung und Treffer:** prozeduraler Erst-Pass erledigt (Etappe 01). Offen: echte Skelettanimationen, falls Modelle mit Rig geliefert werden; Sicht aus steiler Kamera macht Aufbäumen des Bosses nur mäßig sichtbar.
4. **Referenz Swarm:** Beobachtungen zu Farbregeln, Gefahrenformen, Trefferzahlen, Belohnungsmomenten und HUD in `stages/REFERENCE_SWARM.md`; die Übertragung ist als Etappe 14 im Backlog geplant.
5. **Geräteprüfung:** Touchabstände und Leistung auf dem Samsung S25 prüfen. Bei hohen Populationen zuerst Modellanzahl, Material-/Draw-Calls und Deckung durch Dekoration messen und anpassen.


## Icon-Standard (Supercell-Stil)

Stand 27.09.2026. Gilt für alle Icons in `UiIcons` (`scripts/ui/ui_icons.gd`). Richtung: Brawl Stars / Clash Royale – kräftig, bunt, dicke dunkle Kontur, Glanzlicht. Umsetzung heute: `assets/ui/v4/build_icons_v4.py` erzeugt `assets/ui/v4/icons/<id>.png` aus den Projektkopien (V2, V3, gemalte SVGs); die Originale des Nutzers bleiben unberührt. Prüfblätter: `tests/capture_ui_icons.gd` → `preview_ui_icons.png` (nachher), `preview_ui_icons_before.png`, `preview_ui_icons_compare.png`.

**Zwei Arten von Icons**

- **Gemalt** (Inhalt, trägt eigene Farbe): Anlagen, Angriffsformen, Evolutionen, Gegner, Bosse, Biome, Schwierigkeiten, Währungen (DNA, Biomasse, Essenz, Königszahn), Belohnungen (Krone, Pokal, Alpha-Kern), Objekte (Nest, Totem). Aufrufer zeichnen sie mit weißem Tint; Währungen ignorieren fremde Farbtints (`FIXED_COLOUR`).
- **Glyphe** (Bedienung, einfarbig): Pause, Weiter/Play, Uhr, Schloss, Neu würfeln, Neustart, Verbannen, Überspringen. Weiße Fläche mit leichtem kühlem Schatten im unteren Drittel, dicke dunkle Kontur, kleine Unterkante. Der Aufrufer färbt sie per Tint (Gold, Cyan …); die Kontur bleibt dunkel.

**Maße und Beschnitt**

- Textur 256 × 256 px, transparent. Motiv inklusive Kontur füllt die längere Seite zu 89 % (≈ 14 px Rand je Seite) und ist auf die Bounding-Box zentriert. Keine eigenen Kreise, Karten oder Glows ums Motiv – die **Hintergrundplakette liefert das UI-Fundament** (`ui_frames.gd`/Brawl-Kit).
- Zielgrößen im Spiel: 96 px (Karten, Ergebnis), 56–64 px (HUD, Menü), **40 px Mindestgröße**; alles muss bei 40 px auf dunklem Panel und auf hellem Moos erkennbar sein.

**Licht, Kontur, Farbe**

- Licht von oben links: helle Kante/Glanzlicht oben links, dunklere Fläche unten rechts.
- Kontur: warmes Fast-Schwarz `#180e0c`, gemalt ≈ 5 px zusätzlich zur gemalten Linie, Glyphen ≈ 11 px bei 256 px; darunter 5–7 px Unterkante in derselben Farbe (Supercell-„Sockel“).
- 3–4 breite Farbflächen, keine feinen Texturen, keine Partikelwolken.
- Kategoriefarbe (Hauptfläche des Motivs): **Angriff = Orange/Rot**, **Wachstum/Brut = Türkis**, **Schutz = Grün**, **Spezial/Evolution = Violett**, **Beute/Währung = Gold/Bernstein**. Gegner behalten ihre Weltfarbe (Beute Türkis, Jäger Violett, Skitter Blau/Magenta).

**Unterscheidbarkeitsregel**

- Zwei Icons derselben Ansicht dürfen nicht dasselbe Grundmotiv in derselben Farbe haben. Jedes Icon braucht **ein eigenes Silhouettenmerkmal** (Form, nicht nur Farbe), das bei 40 px als schwarze Silhouette noch unterscheidbar ist.
- Zahn-Motive: nur **Reißzähne** zeigt das offene Maul frontal. Andere Zahn-Icons brauchen ein zweites dominantes Element (Pfeil, Welle, Beute, Mehrfach-Rudel) und eine andere Kategoriefarbe. Soforthilfe in V4: Vielfraß Gold, Rudelinstinkt Karmesin, Meute Violett, Knochenpanzer-Sockel Grün.
- Kreisläufe: **Neu würfeln** = zwei jagende Pfeile, **Neustart** = ein Pfeil oben offen.

Bewertung aller Icons und Nachlieferliste mit Generator-Prompts: `stages/ICON_REQUESTS.md`.
