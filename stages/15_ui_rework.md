# Etappe 15 – UI-Neuaufbau im Supercell-Stil

## Nutzerentscheidungen (27.09.2026, verbindlich)

- Das bisherige UI (organic/calm) wirkt amateurhaft und wird ersetzt.
- **Richtung Supercell** (Brawl Stars/Clash Royale): kräftige, bunte Flächen, dicke fast schwarze Konturen, runde 3D-Buttons mit dunklerer Unterkante und Glanzlicht, große freundliche Schrift mit dunkler Kontur und Schlagschatten, klare Hierarchie, wenige starke Formen.
- **Schriften:** Baloo 2 ExtraBold für Titel und Zahlen, Figtree für Text.
- **HUD im Run stark reduziert** (Welle 2); die Bildmitte bleibt frei, Bewegung rechts, Rally links.
- **Farbbedeutung:** Glut-Orange/Rot = eigener Schwarm, Grün = Aktion/Bestätigen, Türkis-Blau = Info/DNA, Gold = Beute, Magenta/Pink = Gefahr. **Die Gefahrenfarbe ist noch nicht bestätigt** und deshalb nur ein Token (`UiStyle.BRAWL_DANGER_*`).
- Die Skins „calm“ und „organic“ bleiben als Option erhalten.

## Welle 1 – Fundament (erledigt)

### Schriften
- `assets/ui/fonts/display.ttf` (Baloo 2, variabel wght 400–800, 73 KB) und `body.ttf` (Figtree, wght 300–900, 36 KB). Beide sind Latein-Subsets (Basic Latin, Latin-1 inkl. Umlaute/ß/×/·/±, „“‚‘ – — … • € ™, Pfeile ←↑→↓, − ≈ ≠ ≤ ≥ ∞ ▲▼). Die Layout-Features `kern tnum pnum lnum case frac locl ccmp liga` bleiben erhalten. Lizenzen liegen in `OFL_display.txt` und `OFL_body.txt`.
- Die Subsets erzeugt `PYTHONPATH=.tools python tools/subset_fonts.py` (fontTools in `.tools/`). Baloo erhält dabei enge vertikale Metriken (Ascent 900/Descent 300 statt 1078/524 für Devanagari), damit Labels und die vertikale Zentrierung stimmen. In Figtree fehlen ≈ ∞ ▲ ▼ ‰; diese kommen über die Fallback-Schrift Baloo.
- Die Gewichte legen FontVariation-Ressourcen fest: `display.tres` (800), `display_numbers.tres` (800 + `tnum`), `body.tres` (500) und `body_bold.tres` (700).
- **Global:** `project.godot` setzt `gui/theme/custom_font = body.tres`. Dadurch verwenden alle Controls und `ThemeDB.fallback_font` Figtree, also auch die Altstellen in `touch_controls.gd` und `scripts/menu/ui_kit.gd`. `UiStyle.display_font()`, `number_font()`, `body_font()` und `body_bold_font()` laden die `.tres`. Die Kandidaten unter `fonts/candidates/` sind vom Android-Export ausgeschlossen.

### Skin „brawl“ (Standard) – `scripts/ui/ui_style.gd`
- `UiStyle.skin = "brawl"`; `SKINS = ["organic", "calm", "brawl"]`, `set_skin()` wie bisher.
- `is_calm()` bedeutet jetzt **„ruhiger Skin“ (calm oder brawl)**: Krallen, Zähne, Ranken und große Glows entfallen. `is_brawl()` wählt das Kit. **Für calm-spezifische Assets** (V2-Texturen, V2-Glyphen) muss `UiStyle.skin == "calm"` geprüft werden, wie es `ui_icons.gd` bereits tut. Heute hängen 81 Stellen an `is_calm()`, vor allem in hud_top, hud_overlays, hud_minimap, hud_controls, hud_objectives, hud_flood und menu_canvas. Welle 2 ersetzt diese Zweige je Bildschirm durch das Kit.
- `UiStyle.color(token)` und `tone(c)` bilden die alten Akzente auf die Brawl-Palette ab (Textfarben auf dunklem Grund). Dunkles Moosgrün wird tiefes Blau-Violett. `UiStyle.text()`/`text_px()` zeichnen im Skin brawl automatisch einen harten Schlagschatten.
- `UiFrames.card/panel/pill/button/bar/panel_inner/button_label_center` leiten im Skin brawl auf das Kit um (`UiFrames.brawl_tone(accent)` → Tonname). Damit sehen Altbildschirme sofort brawl-ähnlich aus. Neue Bildschirme rufen das Kit **direkt** auf.

**Töne** (`UiStyle.BRAWL_TONES`, jeweils `light` / `face` / `dark`; Farbfehlsicht-Modus über `brawl_tone()`):

| Ton | Bedeutung | face |
|---|---|---|
| `ember` | eigener Schwarm, Angriff, Rally | `#ff6a1f` |
| `action` | Bestätigen, Spielen, Kaufen | `#4fc92c` |
| `info` | DNA, Wachstum, Info | `#22a9ef` |
| `loot` | Biomasse, Belohnung, Währung | `#ffbe1f` |
| `danger` | Gefahr, Druck, Boss (unbestätigt) | `#f2358f` |
| `special` | Evolution, Mutation, Alpha-Kern | `#925aff` |
| `neutral` | Zweit-Button, inaktive Tabs | `#5a64a0` |
| `dark` | Panels, Karten | `#242050` |
| `disabled` | gesperrt (nur Kit) | `#5b5875` |

- **Flächen:** Kontur `BRAWL_INK #0e0b1f`, Schatten `BRAWL_INK_SOFT` (60 %). Panel-Verlauf von `BRAWL_PANEL_TOP #2f2a63` nach `BRAWL_PANEL_BOTTOM #1b1840`, Innenkante oben `BRAWL_PANEL_RIM #5a54a8`, Mulde `BRAWL_WELL #120f2b`. Text `#ffffff`, gedämpfter Text `#b8b4e6`.
- **Radien:** `R_S 10`, `R_M 16`, `R_L 24`, `R_XL 34`. **Konturen:** `STROKE_S 3`, `STROKE_M 4`, `STROKE_L 5`. **3D-Unterkante:** `LIP 8`, `LIP_S 5` (11 % der Höhe). **Schatten:** `SHADOW_Y 6`. **Abstände:** `SPACE_XS 4`, `S 8`, `M 12`, `L 16`, `XL 24`, `XXL 32`. **Touch:** `TOUCH_MIN 96`.
- **Typo** (Basis-Viewport **900 × 1600**, nicht 540 × 960; auf dem S25 etwa × 1,2):

| Stufe | px | Schrift | Kontur/Schatten | Einsatz |
|---|---|---|---|---|
| `T_HERO` | 72 | Baloo 800 | 14 / 6 | Ergebnis-Titel, Level-up |
| `T_TITLE` | 54 | Baloo 800 | 12 / 5 | Bildschirmtitel, große Zahlen |
| `T_HEAD` | 38 | Baloo 800 | 10 / 4 | Kartentitel, Button-Label, HUD-Werte |
| `T_BODY` | 26 | Figtree 500/700 | 7 / 3 (optional) | Beschreibungen |
| `T_LABEL` | 22 | Baloo 800 oder Figtree 700 | 6 / 3 | Beschriftungen, Chips |

Alle Stufen sind `SIZE_STEPS`. Nichts Lesbares liegt unter 22; `max_width` darf Text bis etwa 18 herunterskalieren. Die Vorlage des Nutzers (72/48/34/26/20/16 bei 1080 Breite) wurde bewusst etwas größer übertragen, weil der Mindestwert 22 im Projekt gilt.

### Bausteine – `scripts/ui/ui_kit_brawl.gd` (`const Kit := preload(...)`)
Alle Funktionen sind statisch und zeichnen auf `canvas` (in `_draw()` oder einem UiLayer-Painter). `rect` ist die ganze sichtbare Fläche inklusive Kontur und Unterkante; nur der Schatten reicht darunter. `tone` ist ein Tonname oder eine beliebige Color.

```gdscript
Kit.panel(canvas, rect, tone := "dark", radius := R_L, stroke := STROKE_M, shadow := true)
Kit.panel_inner(rect, stroke := STROKE_M) -> Rect2
Kit.well(canvas, rect, radius := R_S)                       # Mulde: Slots, Zeilen
Kit.card(canvas, rect, tone := "info", state := "normal", header := 0.0, radius := R_L)  # normal|pressed|selected|disabled
Kit.card_inner(rect, header := 0.0) -> Rect2
Kit.button(canvas, rect, tone := "action", pressed := false, radius := R_M)   # tone "disabled" = gesperrt
Kit.button_label_center(rect, pressed := false) -> Vector2  # mit MIDDLE verwenden
Kit.lip_for(height) -> float
Kit.round_button(canvas, center, radius, tone := "ember", pressed := false)
Kit.round_label_center(center, radius, pressed := false) -> Vector2
Kit.pill(canvas, rect, tone := "dark", stroke := STROKE_M)  # Kapsel
Kit.chip(canvas, rect, tone := "neutral")                   # kleines Tag
Kit.badge(canvas, center, text, tone := "danger", size := T_BODY)   # "3", "NEU", "99+"
Kit.icon_plate(canvas, center, size, tone := "dark", shape := "round")   # "round" | "square"
Kit.plate_center(center, size) -> Vector2                  # Icon-Mitte (Fläche ist angehoben)
Kit.bar(canvas, rect, fraction, tone := "info", segments := 0)
Kit.ribbon(canvas, rect, tone := "ember")                  # Titelband mit Schwalbenschwanz
Kit.dim(canvas, rect, alpha := 0.72)
Kit.text_outlined(canvas, pos, text, size, color := WHITE, outline := -1, shadow := -1, font := null, align := LEFT, max_width := 0.0) -> float
Kit.number(canvas, pos, value, size, color := WHITE, align := LEFT, max_width := 0.0) -> float   # tnum, int -> "12.345"
Kit.paragraph(canvas, pos, text, width, size := T_BODY, color := WHITE, bold := false, align := LEFT, max_lines := 4, outline := 0) -> float  # y unter der letzten Zeile
Kit.wrap_lines(text, font, size, width) -> PackedStringArray
Kit.format_int(n) -> String
# align: Kit.LEFT | CENTER | RIGHT, optional | Kit.MIDDLE (pos.y = Mitte der Großbuchstaben)
# Primitive: rrect, ring, top_rim, fade_rrect, disc, circle_ring, fade_disc, round_rect_points
```

Technik: Flächen und Konturen sind geglättete `StyleBoxFlat`- bzw. `draw_circle`-Aufrufe. Verläufe sind Vertex-Farb-Polygone, die vor ungedeckten Kanten ausblenden, und der Kontur-Ring wird zuletzt gezeichnet. Dadurch sind alle sichtbaren Kanten auch bei 540 × 960 geglättet. Es gibt keine Texturen und keine neuen Glyph-Caches außerhalb von `SIZE_STEPS`.

### Vorschau
`tests/capture_ui_kit_brawl.gd` (ohne `--headless`, mit `--screen 1 --audio-driver Dummy`) erzeugt:
- `preview_ui_kit_brawl.png` (900 × 1600): Kit im Kontext über dem laufenden Spiel (HUD oben, Boss-Leiste, Mutationswahl mit Band und drei Karten, Buttons, Beute-Toast, Aufgabe, Rally/Joystick),
- `preview_ui_kit_brawl_tones.png`: jeder Baustein in jedem Ton, jeweils normal und gedrückt,
- `…_540.png`-Varianten mit echter Verkleinerung sowie Zoom-Ausschnitte `…_zoom_buttons|bars|text.png` in doppelter Größe.

Die Vorschau entstand in drei Runden. (1) Die harte Glanz-Kapsel wirkte wie eine Plastikschiene; sie wurde durch weichen Glanz, eine Lichtkante und einen kleinen Glanzpunkt ersetzt. Gedrückt heißt jetzt: dunkler, ohne Glanz, mit Innenschatten. (2) Der runde Glanz ist jetzt ein Bogen statt einer Kapsel, die Kartentitel sind größer, die Unterkante beträgt 11 % der Höhe, und die Verläufe werden am echten Umriss abgeschnitten, was einen Triangulationsfehler bei Leisten behob. (3) Größere Abzeichen, die Mulde hat eine Lichtkante unten, gesperrte Buttons bleiben ohne Glanz.

## Welle 2 – Bildschirme (Plan)

Jeder Agent besitzt nur die genannten Dateien, zeichnet ausschließlich mit `ui_kit_brawl.gd` und `UiStyle.T_*`/Tönen und entfernt in seinen Dateien die `is_calm()`-Zweige für brawl. Die Zweige organic/calm dürfen bleiben. Das Kit selbst ändert nur der Orchestrator. Braucht ein Agent einen neuen Baustein, meldet er ihn, statt ihn lokal nachzubauen. Icons liefern `ui_icons.gd` und `assets/ui/v4/icons/` des Icon-Agenten, immer auf `Kit.icon_plate`.

| Paket | Dateien (Besitz) | Inhalt |
|---|---|---|
| **A · HUD oben** | `scripts/ui/hud_top.gd`, `scripts/ui/hud_minimap.gd` (nur Rahmen/Label), `tests/capture_ui_hud_top.gd` | Stark reduziert: links Schwarm-Pill (Plakette + Zahl), Mitte Zeit (`number`, T_TITLE) mit Druck-Leiste (danger, Segmente), rechts DNA-Pill mit Level-Leiste und runder Pause-Taste. Kontext-Chips höchstens eine Zeile und nur bei Bedarf. Minimap kleiner oder einklappbar. |
| **B · Steuerung** | `scripts/ui/hud_controls.gd`, `scripts/touch_controls.gd` (nur Zeichnen/Fonts, keine Eingabelogik) | Rally als `round_button` ember links (Ladung als Abzeichen/Ring), Joystick rechts: Basis-Scheibe + neutraler Knopf (gedrückt). Hinweisbanner als Pill. `ThemeDB.fallback_font`-Stellen durch `UiStyle`-Fonts ersetzen. |
| **C · Mutationskarten + Level-up** | `scripts/ui/mutation_screen.gd`, `tests/capture_ui_mutations.gd` | S6/S7: kurzer Level-up-Moment (Abdunkeln, Lichtsäule, `ribbon` „MUTATION!“), drei `card` mit Kopfleiste im Kategorie-Ton, `icon_plate` 128, Abzeichen „NEU“/Rang, Werte vorher → nachher als `number`; Buttons Neu würfeln (neutral) / Verbannen / Überspringen. |
| **D · Ergebnis** | `scripts/ui/hud_overlays.gd` (Result + Pause), `scripts/ui/share_card.gd` | Ergebnis nach S13: `T_HERO`-Titel, Werte in Pills, Build als Plaketten, **Aufgaben mit Fortschrittsleiste und Belohnung** über „NOCHMAL“ (action) / „MENÜ“ (neutral). Pause als Panel mit Build. |
| **E · Menü Hauptseite** | `scripts/ui/menu/menu_main.gd`, `scripts/ui/menu/menu_canvas.gd`, `tests/capture_ui_menu_main.gd` | Kopf mit Ressourcen-Pills, Stamm-Karte (`card` ember), Biom/Schwierigkeit als Kacheln mit `selected`, großer **SPIELEN**-Button (action, ≥ 120 px hoch), untere Tab-Leiste mit Plaketten + Abzeichen. |
| **F · Menü Sheets** | `scripts/ui/menu/menu_sheets.gd`, `scripts/ui/menu/menu_chronicle.gd`, `scripts/menu/ui_kit.gd`, `scripts/menu/menu.gd` (nur Zeichnen), `tests/capture_ui_menu_sheets.gd` | Brutkammer, Trophäen, Urinstinkt, Chronik, Einstellungen und Belohnungs-Overlay als `panel` + `well`-Zeilen. Kaufen = action, gesperrt = disabled, Fortschritt als `bar` loot. Optional: Skin-Auswahl (brawl/calm/organic) in den Einstellungen; heute wird der Skin nirgends gespeichert. |
| **G · Welt-Popups** | Popup-Zeichnung in `scripts/hunt_world.gd`/Popup-Knoten (mit dem Gameplay-Besitzer abstimmen), `scripts/ui/hud_objectives.gd` | S5: Biomasse-Zahlen innerhalb von 0,25 s zu einer Zahl zusammenfassen (`number` loot, Kontur + Schatten). Schadenszahlen nach Rang, Zeiger (Nest/Totem) als Plakette mit Pfeil. |
| **H · Boss-Leiste + Banner** | Boss-Teil von `scripts/ui/hud_top.gd` (mit A abstimmen: A gibt die Funktion `_draw_boss_bar` ab), `scripts/ui/hud_flood.gd`, Banner in `hud_overlays.gd` (mit D abstimmen) | S10: große Leiste oben mit Porträt-Plakette (square, danger), Name T_HEAD, exakte Zahlen, Segmente je Phase. Banner als `ribbon` (Flut = danger, Migration = info, Sieg = loot). |

Reihenfolge: A, B, C und E parallel; danach D, F, G und H. A und H teilen `hud_top.gd`, deshalb läuft H nach A oder A übergibt die Boss-Funktion.

### Abnahmekriterien Welle 2
1. Jeder Bildschirm nutzt nur Kit-Bausteine und Token. Keine Hex-Farben und keine `ThemeDB.fallback_font` in den besessenen Dateien.
2. **Lesbarkeit bei 540 × 960:** kein Text unter T_LABEL (22). Kein Text läuft über oder wird abgeschnitten, auch bei langen deutschen Texten (Test mit dem längsten Kartentext, 250 Population und 5-stelliger DNA). Wo nötig `max_width`/`paragraph`.
3. Touch-Ziele ≥ `TOUCH_MIN` (96 px); Rally links, Bewegung rechts; die Bildmitte (mittleres Drittel) bleibt im Run frei.
4. **HUD im Run:** höchstens drei feste Elemente oben plus Pause; alles andere erscheint kontextuell und verschwindet wieder.
5. Farbbedeutung eingehalten (Töne-Tabelle). Die Gefahrenfarbe kommt nur aus `BRAWL_DANGER_*`, damit ein Tausch nach der Nutzerentscheidung eine Zeile ist.
6. Gedrückter Zustand an jedem Button sichtbar; gesperrt ist deutlich von aktiv unterscheidbar.
7. Pro Paket eine Aufnahme (900 × 1600 und 540 × 960), vom `visual-reviewer` gegen den Stil der Kit-Vorschau geprüft.
8. Tests grün: `smoke`, `menu`, `onboarding`, `minimap`, `objectives`, `run_config`, `chronicle` sowie die Playthrough-Prüfung. Die UiLayer-Caches bleiben erhalten (Performance-Etappe 07); keine neuen Schriftgrößen außerhalb von `SIZE_STEPS`.

## Beobachtungen aus Welle 1 für Welle 2
- Altbildschirme laufen mit Baloo/Figtree ohne Absturz. `menu` (inkl. Layout-Prüfung) und `smoke` sind grün. Die Aufnahmen von HUD, Mutation, Menü und Overlays zeigen keine sichtbaren Überläufe. Baloo ist aber **breiter** als der alte gestauchte Fallback. Enge Stellen, die Welle 2 prüfen muss: HUD-Chips („ALPHA-KERN ×1“, „DRUCK ×6.2“), Mutationskarten-Zeile „Rally: alle 2,2 s Sprungangriff …“ (Figtree, drei Zeilen), Menü-Tabs „BRUTKAMMER“/„URINSTINKT“, Schwierigkeits-Untertitel „Fünf Minuten Hunger“.
- Der Titel „MUTATION WÄHLEN“ in `mutation_screen.gd` wirkt dünn, weil dort offenbar die Theme-Schrift (Figtree 500) in Titelgröße gezeichnet wird. Paket C muss ihn auf `display_font` umstellen.
- Die Mischoptik (eigene chamfer-Rahmen aus dem calm-Zweig neben den Kit-Bausteinen) ist ein Zwischenstand und wird Paket für Paket ersetzt.
