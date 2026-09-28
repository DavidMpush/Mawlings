# MAWLINGS – aktiver Art- und UI-Plan

Stand: 26.09.2026. Grundlage sind die früheren Entwürfe `Swarm/Design/MUTATION_UI_GODOT_DIRECTION.md`, `VISUAL_DIRECTION_V2.md`, `HY3D_GODOT_WORLD_PLAN.md` und `MAP_DIRECTION_OPEN_ARENA.md`. Die Konzeptbilder definieren Stimmung und Lesbarkeit, keine exakten Layouts oder zu kopierenden Figuren. Dieses Dokument beschreibt den Stand des aktiven Godot-Projekts.

## Gestalterische Regeln

- Mobiles Hochformat, leicht geneigte Kamera, offene Kampfzone. Gut drei Viertel des sichtbaren Bodens sollen ruhig und begehbar wirken; Steine bilden nur vereinzelte umgehbare Engstellen.
- Spieler zuerst: warmes Korallrot/Orange, klare Schwarmform. Gefahren haben feste, unterschiedlich geformte Warnflächen zusätzlich zur Farbe (Farbregeln und Gefahrenformen siehe unten, Etappe 20).
- 3D-Formen mit breiten Farbflächen und lesbarer Silhouette. Keine fotorealistische Dschungeldichte. Requisiten sollen Kämpfe und Kadaver nicht verdecken.
- **Hindernisse sind groß und eindeutig** (Nutzerentscheidung 28.09.2026, Etappe 18c): Blockieren dürfen nur Felsbrocken ab ~3–4 m, Baumgruppen mit sichtbarem Stamm, zusammenhängende Mauerzüge und Dickichtwände sowie Wasser- und Lavaflächen mit klarer Kante. Jede Wand hat einen dunklen Boden-Fußabdruck mit Kantenschatten. Kleinzeug auf begehbarem Boden (Kiesel, Blatthorste, Blumen, Riedgras) gibt es nicht; erlaubt sind nur flache, bodenfarbene Flecken unter 0,3 m ohne Schatten oder Kontur. **Kollision = Optik:** Die sichtbare Kante ist die Kollisionskante (± 0,3 m); keine unsichtbaren Ränder, keine sichtbaren Hindernisse ohne Kollision. Umgesetzt durch Wände je 2-m-Rasterzelle (`arena_border._cell_walls`), eine Grundflächenprüfung aller Wand- und Randprops (`_fits`) und Landmarken, deren Sockel dem Kollisionskreis entspricht.
- UI ist funktional: Population links, Zeit/Druck mittig, DNA/Evolution rechts. Pause oben rechts; Bewegung unten rechts, Rally unten links. Die Bildschirmmitte bleibt frei. Biomasse und Kadaverhinweis erscheinen kontextuell.

## Farbregeln und Gefahrenformen (Etappe 20, S1–S3)

**Farben mit fester Bedeutung** (Tokens in `scripts/ui/ui_style.gd`, `BRAWL_TONES`):
- **Eigen** = Glut/Orange (`ember`): Schwarm, eigene Angriffe, Rally, eigene Buffs (z. B. Raserei-Aura).
- **Gefahr** = Magenta/Pink (`BRAWL_DANGER_*`): alle Warnflächen (Jäger, Skitter, Nibbler, Leaper violett-magenta, Bog King, alle Apex-Angriffe, Lava-Ausbrüche), Einschlagringe, Flut-Ereignisring.
- **Beute** = Gold (`loot`): Bernstein, Kokons (Karten-Kokon Gold statt Glut), Belohnungen.
- **DNA/XP** = Blau bzw. Violett wie im HUD; **Wachstum** = Grün (Biomasse-Kristalle).
- **Freundliche Zonen** nie in Gefahrenfarbe: Kokon Gold (zu teuer: neutrales Grau-Blau statt Pink), Schrein Violett, Nest Türkis, sichere Inseln im Beben Cyan.
- Der Boden bleibt ruhig; Lava ist Umgebung (Farbe der Lava selbst), die Warnung darum ist Pink.

**Drei Gefahrenformen:**
- **Linie/Kontur = „kommt gleich“:** angekündigte Angriffe mit Warnzeit. Heller Rand in Gefahrenfarbe genau auf der Trefferkante (die Außenkante des hellen Bands IST die Kante), dunkle Kontur direkt außen, durchscheinende Füllung, die vom Ursprung her mit der Warnzeit dunkler wird (helle Vorderkante), helle Markierungen innen, Ring pulsiert zum Einschlag schneller. Normale Gegner: `telegraph.gdshader` (Muster je Art); Bosse: SVG-Kreis und -Kegel (`telegraph_boss.gdshader`) und für alles andere dieselbe Optik prozedural (`telegraph_boss_shapes.gdshader`: Bahn mit Chevrons, Ring mit Innenradius, Scheibe mit sicheren Inseln).
- **Fläche = „liegt da“:** gefüllte Fläche ohne Vorderkante und ohne Puls, weicher dunkler Rand, langsame Blasen (`TG.build_hazard`: Glutpfützen der Kröte). Treibsand ist eine ruhige, dunklere Sandfläche (Gelände, bremst nur).
- **Großer Ring = „Ereignis läuft“:** Flutwelle (heller pinker Ring, der sich zum Schwarm zusammenzieht), Migrationsschlund; Halte-Ringe von Kokon und Schrein in ihrer eigenen, freundlichen Farbe.

**Einheitliche Boss-Telegraphen** (`scripts/telegraph_style.gd`): `build("boss", r)` / `build_boss_cone(reach, angle)` (SVG), `build_boss_lane(width, length)`, `build_boss_ring(inner, outer)`, `build_boss_islands(radius, islands)`, `build_boss_disc(r)`, `build_hazard(r)`; alle mit Farbenblind-Palette (Füllung dunkel, Rand Gelb, Markierungen Weiß; Fläche Zinnoberrot). Moosschlund: Wurzeln = Bahnen, Sporen = Ring, Beben = Scheibe mit Inseln; Kröte: Sprung/Spucke = SVG-Kreis, Zunge = Bahn, Pfützen = Fläche; Sandwurm: Durchbruch = SVG-Kreis, Schwanzfeger = SVG-Kegel mit genau dem SVG-Öffnungswinkel. `tests/telegraph_shapes.gd` prüft, dass gezeichnete Kante und Trefferprüfung übereinstimmen.

**Anführer (S2):** Krone, LP-Punkte und heller Bodenring am Anführer (seit Etappe 09, `swarm.gd`) erfüllen „immer auffindbar“; in Etappe 20 unverändert.

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

## Kampf-VFX V1 (Nutzerpaket, 27.09.2026)

Sechs gemalte Effektbilder und zwei Boss-Telegraphen aus `Swarm/Design/VFX_Assets_V1`; Aufbereitung und Import siehe `assets/README.md` (Kampf-VFX V1).

**Effekt-Sprites** (`scripts/vfx_sprites.gd`, `shaders/vfx_sprite.gdshader`): je Bild eine MultiMesh (höchstens ein Draw Call je Art, unsichtbar wenn leer). Die CPU schreibt eine Instanz nur beim Erscheinen; Größe, Drehung, Ausblenden, Sog und Aufstieg rechnet der Shader aus `INSTANCE_CUSTOM` (Startzeit, Dauer, Startwinkel, Variation) und einer eigenen Uhr, die nur läuft, während der Run läuft (Pause friert ein, Reset räumt ab). Flache Quads, je nach Art 0–40° zur Kamera geneigt, **ohne Tiefentest** über Körpern gezeichnet – sonst verschwinden kurze Treffer im dichten Schwarm.

| Art | Auslöser | Dauer | Obergrenze |
|---|---|---|---|
| Biss | Kontaktbisse (gedrosselt 0,16 → 0,07 s je nach Schwarmgröße, reihum an Zielen in Beißweite; in der Flut am Schwarmrand zur Brut), Rudelbiss-/Meute-Landung, Giftbiss | 0,12–0,20 s | 40 |
| Säure | Säurespucker-/Ätzflut-Treffer, kleiner Giftspritzer beim Giftbiss | 0,25–0,40 s | 24 |
| Sporen | Sporenherz/Pilzreich-Wolke (groß), Sporen-Aura: alle 0,45 s ein kleiner Puff an einem getroffenen Ziel | 0,4–0,7 s | 12 |
| Schockwelle | Gräber/Erdbeben (1,5 × Radius), Bog-King-Stampf und Apex-Angriffe (2,2 × Radius), Schallbrüller (bis 3 getroffene Ziele, klein) | 0,25–0,45 s | 12 |
| Biomasse | Kristall-Aufnahme, höchstens alle 0,1 s ein Sprite am Schwarmrand, das in die Mitte gezogen wird | 0,45–0,6 s | 16 |
| DNA | DNA-Aufnahme, höchstens alle 0,18 s, leuchtet auf und steigt | 0,6–0,8 s | 8 |

Die Qualitätsstufe (`effect_density`) senkt die Obergrenzen (nie unter ein Drittel). Klauenwirbel bekommt bewusst kein Sprite: das Biss-Motiv passt nicht zu Klingen, die bestehenden Klingen und Ringe lesen sich besser.

**Boss-Telegraphen** (`scripts/telegraph_style.gd`, `shaders/telegraph_boss.gdshader`): `TG.build("boss", radius)` zeigt jetzt den Kreis aus dem Paket (Korallring gestrichelt, dunkle Kontur, heller gestrichelter Innenring, vier Pfeile), `TG.build("boss_cone", reichweite)` bzw. `TG.build_boss_cone(reichweite, halber_winkel)` den Kegel (Spitze am Knoten, lokal +Z = Angriffsrichtung; gut lesbar zwischen etwa 20° und 40°). Die Trefferkante der SVG (Kreis r = 210 px, Kegel ≈ 412 px) liegt exakt auf Radius bzw. Reichweite (geprüft in `tests/vfx.gd` und mit Referenzlinie in `preview_vfx_boss_exact.png`). Füllfortschritt wie bisher (von der Mitte/Kegelspitze wachsend, hier zur dunklen Kontur hin abgedunkelt, damit der korallrote Schwarm darin lesbar bleibt, mit heller Vorderkante), der Ring pulsiert zum Einschlag hin schneller. Farbenblind: Füllung dunkel, Ring Gelb, Markierungen Weiß. Die alte Speichen-Optik bleibt als `"boss_spokes"` erhalten. Bog King nutzt den Kreis automatisch. Seit Etappe 20 sind alle Boss-Angriffe in diesem Stil (Farbe Pink statt Koralle, siehe „Farbregeln und Gefahrenformen“).
