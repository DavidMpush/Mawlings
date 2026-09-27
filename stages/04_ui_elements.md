# Etappe 04 – UI Element für Element

Nutzerurteil: „Beim UI sind wir noch ziemlich weit weg“ von den Konzepten. Ursache: Alles wird aus `draw_*`-Primitiven mit der Godot-Standardschrift gezeichnet. Ziel: jedes Element einzeln an die Konzepte heranführen – mit echten SVG-Grafiken (Verläufe, Glanz, organische Rahmen, gemalte Icons) und einer kräftigen Display-Schrift.

Referenzen (nur lesen): `C:\Users\vrxby\Documents\Codex\Swarm\Design\MAWLINGS_ACTIVE_HUD_CONCEPT_PORTRAIT.png`, `MAWLINGS_MUTATION_UI_CONCEPT_PORTRAIT.png`, `MUTATION_UI_GODOT_DIRECTION.md`, `MAWLINGS_VISUAL_CONCEPT_02_PORTRAIT.png`. Konzepte sind Stimmung und Qualitätsniveau, keine Pixelvorlage und keine LoL-Kopie.

## Stilregeln
- Tokens nur aus `scripts/ui/ui_style.gd` (Palette, Schriftgrößen, `display_font()`, `body_font()`, `tex()`, `nine()`, `text()`). Keine neuen Farbliterale ohne Grund.
- Organische Rahmen: dunkles Grün-Schwarz mit feiner Adern-/Zellstruktur, abgeschrägte Ecken, 2–3 Kerben, Knochenklauen/-zähne als Akzent, farbige Glühkante nach Kategorie (Angriff Ember, Wachstum Cyan, Spezial Violett, Schutz Toxic).
- Lesbarkeit auf 6-Zoll-Handy vor Dekor: Text ≥ 20 px im 900×1600-Raster, Zahlen groß, Kontur um helle Schrift. Bildmitte im Spiel frei. Bewegung rechts, Rally links (Touch-Zentren unverändert).
- Grafiken als SVG unter `assets/ui/…` (Godot importiert sie als Textur; für scharfe Darstellung in den `.import`-Einstellungen `svg/scale` passend setzen, z. B. 2.0). Weiße/graue Grafik + `modulate`, wo Farbvarianten nötig sind.

## Komponenten-Vertrag
- HUD-Komponenten: `scripts/ui/<name>.gd`, `extends Control`, als Kind von `HUD/Controls` (`touch_controls.gd`) mit vollem Anker; `mouse_filter = MOUSE_FILTER_IGNORE`; lesen alle Daten aus `get_parent()` (dieselben Variablen, die `touch_controls` hat); zeichnen in `_draw()`, `queue_redraw()` in `_process`.
- Menü-Komponenten: `scripts/ui/menu/<name>.gd`, gleiches Muster, Eltern = Menü-Control (`scripts/menu/menu.gd`).
- **Eingabe bleibt in `touch_controls.gd` bzw. `menu.gd`.** Komponenten zeichnen an den dortigen Rechtecken (`_mutation_rect(slot)`, `_action_rect()`, `_pause_rect()`, `_rally_center()`, `_movement_center()`, Menü `*_rect()`), damit Trefferflächen stimmen. Diese Dateien ändert nur der Orchestrator; gewünschte Rechteck-Änderungen im Bericht nennen.
- Alte Zeichnung abschalten über `hud.legacy["top"] = false` usw. (Schlüssel: top, badges, pointer, feedback, result, mutations, controls, banner; Menü: background, logo, resources, strain, biomes, difficulties, play, sheet, tabs, reward). Die endgültige Einbindung macht der Orchestrator.
- Gemeinsame Bausteine (entstehen parallel, danach nutzen): `scripts/ui/ui_icons.gd` (`UiIcons.draw(canvas, id, rect, tint := Color.WHITE)`, `has(id)`), `scripts/ui/ui_frames.gd` (`UiFrames.card(canvas, rect, accent, state)`, `panel(...)`, `button(canvas, rect, kind, pressed)`, `bar(canvas, rect, fraction, color)`, `pill(...)`). Bis sie existieren: eigener einfacher Fallback, danach umstellen.
- Jede Komponente hat eine Vorschau `tests/capture_ui_<name>.gd` (ohne `--headless`, 540×960 Fenster, Fokus-Pause trennen), die sie im echten Spiel bzw. Menü mit Beispieldaten zeigt, und wird **neben das Konzeptbild gelegt**. Mindestens 3 Verbesserungsrunden.

## Agenten
| Agent | Element | Dateien |
|---|---|---|
| ICONS | Icon-Set: 6 Anlagen, 4 Angriffsformen, 2 Evolutionen, Essenz, Königszahn, DNA-Helix, Schädel, Mawling-Kopf, Krone, Alpha-Kern, Pause, Schloss, Trophäe, 2 Biome, 3 Schwierigkeiten, Uhr | `assets/ui/icons/*`, `scripts/ui/ui_icons.gd`, `tests/capture_ui_icons.gd` |
| FRAMES | Rahmen-Kit: Karte, Panel, Pill, Knöpfe (primär/sekundär/rund), Leisten, Klauen/Zähne | `assets/ui/frames/*`, `scripts/ui/ui_frames.gd`, `tests/capture_ui_frames.gd` |
| HUD_TOP | Obere Leiste (Schwarm, Gefahr+Zeit, DNA/Level, Pause), Chips, Boss-Leiste, Kadaver/Biomasse, Alpha-Chip, Angriffs-Medaillons | `scripts/ui/hud_top.gd`, `tests/capture_ui_hud_top.gd` |
| CONTROLS | Rally-Knopf, Joystick, Hinweis-Banner | `scripts/ui/hud_controls.gd`, `tests/capture_ui_controls.gd` |
| MUTATIONS | Mutationswahl: Titel, 3 Karten, Reroll/Banish/Skip | `scripts/ui/mutation_screen.gd`, `tests/capture_ui_mutations.gd` |
| OVERLAYS | Ergebnis/Pause, Evolutions-Banner, Verlustanzeige, Boss-Zeiger | `scripts/ui/hud_overlays.gd` (Capture entfernt, heute `tests/capture_ui_result.gd`) |
| MENU_MAIN | Brutstätte-Hauptansicht: Hintergrund, Logo, Ressourcen, Stammkarte, Biome, Schwierigkeit, SPIELEN, Tabs | `scripts/ui/menu/menu_main.gd`, `tests/capture_ui_menu_main.gd` |
| MENU_SHEETS | Brutkammer, Trophäen, Urinstinkt, Belohnungs-Overlay, Toast | `scripts/ui/menu/menu_sheets.gd`, `tests/capture_ui_menu_sheets.gd` |

## Ergebnis (26.09.2026)

Acht UI-Agenten parallel, Einbindung und Prüfung durch den Orchestrator. Das UI besteht jetzt aus Komponenten mit echten SVG-Grafiken; `touch_controls.gd` und `menu.gd` behalten Zustand und Eingabe, ihre alten Zeichenblöcke sind über `legacy` abgeschaltet.

- **Grundlage:** 49 gemalte SVG-Icons (`assets/ui/icons`, Generator `generate_icons.py`, API `UiIcons`), Rahmen-Kit mit 20 SVGs (organische Karte mit Adern, Kerben und Hakenhörnern, Panels mit Klauen, Pill, primärer/sekundärer/runder Knopf, Segmentleisten, Ranken; `generate_frames.py`, API `UiFrames`, 9-Slice).
- **HUD:** obere Leiste mit Mawling-Kopf, Populations-Puls (+/−), Gefahren-Segmentleiste mit Schädel, DNA/Level, Chips, Boss-Leiste mit Krone, Alpha-Kern, Medaillons; Rally mit drei Köpfen und Zusammenzieh-Ringen, Glas-Joystick, Warn-Banner mit Schädel.
- **Mutationswahl:** Titel mit Ranken, drei Konzept-nahe Karten (Kategorie-Farbe, Icon-Medaillon, Effekt groß, Rang-Rauten, Evolutionshinweis, NEU-Plakette), gestaffeltes Einblenden, Aufblitzen bei Wahl; 1–2 Karten jetzt vertikal zentriert.
- **Overlays:** Ergebnis mit hochzählenden Werten, Kill-Chips und Build; Pause mit BRUTSTÄTTE (Aufgeben bucht Belohnungen); Evolutions-Banner; gebündelte Verlustanzeige; Boss-Zeiger.
- **Menü:** 3D-Rudel des Stamms (SubViewport, `body_tint`), Logo mit Kiefern, gemalte Biom-Kacheln, SPIELEN mit Zähnen, Brutkammer/Trophäen/Urinstinkt als Karten, Belohnungs-Overlay mit Zählern und Freischalt-Karten. Essenz einheitlich Violett.
- **Tests:** 17/17 grün; Captures warten jetzt auf Einblend-Animationen.

Offen: echte Display-Schrift (Freigabe zum Laden von OFL-Schriften ausstehend), Gerätetest auf S25 (SubViewport-Kosten, Lesbarkeit kleiner Texte), Rahmenkörper noch ruhiger als im Konzept, Verbannen-Knöpfe eng an der Kartenkante, Menü-Rechtecke (Pfeile schmaler, mehr Abstand) noch nicht angepasst.
