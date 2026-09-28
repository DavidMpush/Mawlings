# Etappe 25 – Dramaturgie (S10/S12)

**Ziel:** Figuren kommentieren den Run mit kurzen Sprüchen am Bildrand (S12). Die Bosse bekommen einen Auftritt und nach dem Sieg einen kurzen Ruhemoment (S10), ohne das Spiel anzuhalten.

## Abnahmekriterien
- Sprechblasen mit Porträt-Plakette am **linken** Bildrand, im Kit-Stil, 2–3 s, höchstens eine gleichzeitig, mit Abstand, nie Spam.
- Sprecher sind der eigene Anführer (Stammeskopf) und die vier Bosse vor ihrem Auftritt.
- Abschaltbar in den Einstellungen („SPRÜCHE“).
- Boss-Auftritt: Kommentar, Rand-Vignette 0,6 s, Kamera kurz heraus. Die Boss-Leiste fährt wie bisher ein.
- Boss-Sieg: Höhepunkt (vorhandenes Sieg-Band mit Flash), dann 1–2 s Ruhe mit leiserer Musik.
- Nichts pausiert länger als 0,3 s.
- Tests für Warteschlange, Abstand, Abschaltbarkeit und freie Bildmitte; Captures angesehen.

## Umsetzung
- **`scripts/drama.gd`** (neu, von `main.gd` für jeden Run angelegt): beobachtet HuntWorld pro Frame nur über öffentliche Felder, wie das Onboarding. Anlass → Zeile:

  | Anlass | Erkennung | Sprecher |
  |---|---|---|
  | Bog King erscheint | neue `boss`-Instanz | Bog King (+ Vignette, Zoom) |
  | Apex kündigt sich an | `apex_state` → 1 | Moosschlund / Sandwurm / Aschenkröte nach `apex_kind` |
  | Apex erscheint | neue `apex`-Instanz | Vignette und Zoom (Spruch nur, wenn keine Ankündigung lief) |
  | Sieg | `king_moments` bzw. `apex_victories` steigt | nach 0,8 s `Music.hush(1,6)`, dann Ruf des Anführers |
  | Meilenstein | `milestone_value` steigt | Anführer |
  | Level-up / erste Evolution | `evolution.level` / `evolutions` | Anführer |
  | Anführer auf 1 LP / Anführerwechsel | `model.leader_hp`, `model.leader_swaps` | Anführer |
  | Flut bricht los | `flood_state` → 2 | Anführer |

- **Regeln:**
  - eine Zeile zur Zeit, 2,6 s Anzeige, 3 s Abstand
  - Warteschlange höchstens 2 Zeilen; Boss-Zeilen stehen vorn und verdrängen Anführer-Zeilen
  - der Anführer ruft höchstens alle 22 s, außer direkt nach einem Sieg
  - Zeilen, die nach 6 s noch warten, verfallen
  - eine Zeile wiederholt sich erst, wenn alle Alternativen des Anlasses gesagt sind
  - während Pause und Auswahl läuft keine Zeit
- **Texte** (Ton „Fressen, wachsen, überleben“), je 2–3 pro Anlass. Beispiele:
  - Bog King: „Wer knabbert da in meinem Sumpf?“
  - Moosschlund: „Ihr fresst meinen Wald? Ich fresse euch.“
  - Sandwurm: „Unter euch. Immer unter euch.“
  - Aschenkröte: „Quaak! Ihr riecht nach Asche!“
  - Anführer: „Mehr Mäuler, mehr Futter!“, „Mahlzeit!“, „Nur noch ein Leben – deckt mich!“
- **`scripts/ui/hud_speech.gd`** (neue HUD-Komponente, liegt unter der Mutationswahl):
  - Aufbau: Porträt-Plakette (Stammeskopf bzw. `portrait_*` aus `ui_icons`), Kit-Blase mit Schwänzchen, Namens-Chip oben, höchstens 2 Zeilen.
  - Lage: linker Rand (x = 16), unter dem Banner-Band von `hud_overlays` und unter dem oberen HUD-Stapel, höchstens 60 % der Breite. Die Mitte (40 % × 20 % um den Schwarm) bleibt frei.
  - Die Blase ist eine gebackene UiLayer; Ein- und Ausblenden über Skalierung und Modulate, kein Neuzeichnen.
  - Beute-Popups weichen der Blase aus (HUD-Meta `speech_rect`, `hud_overlays._avoid`).
  - Rand-Vignette: eine Dreiecksliste, 0,6 s.
- **`main.gd`**: `drama_zoom(seconds)` zieht die Kamera um 12 % heraus (weicht dem Königsmoment-Zoom); `_create_drama(config)`.
- **`music.gd`**: `hush(seconds)` duckt die Loops wie unter einem Stinger (−7 dB) und blendet danach zurück; Zähler `hushes`.
- **Einstellungen:** Zeile „SPRÜCHE“ (Profil `speech`, Standard an), übergeben per RunConfig `settings.speech`. Die Schalterzeilen sind etwas enger (Abstand 112, Höhe 100), damit TAGES-BRUT außerhalb des Panels bleibt.
- **Pausen:** keine. Vignette, Zoom und Ruhe laufen in Echtzeit neben dem Spiel. Der vorhandene Königsmoment (0,6 s Zeitlupe auf 30 %) bleibt unverändert.
- `hunt_world.gd` ist unverändert.

## Tests und Bilder
- `tests/drama.gd` (neu, in `tools/test.ps1`):
  - Main legt den Knoten an, Sprüche sind standardmäßig an.
  - Warteschlange: Boss vor Anführer, eine Zeile zur Zeit, Anzeigedauer, Abstand, Anführer-Abklingzeit, Grenze von 2 Zeilen, verfallene Zeilen, keine Wiederholung.
  - Schalter aus: keine Zeile, nichts sichtbar.
  - Bog-King-Auftritt: Vignette-Zähler steigt, Kamera-Zoom läuft, der Boss spricht.
  - Sieg: Musik wird leiser, der Anführer ruft. Anführer auf 1 LP.
  - Weder Pause noch Zeitlupe.
  - Blase am linken Rand, höchstens 62 % der Breite, schneidet nie die Mitte, liegt unter dem Banner (kurz, mittel, lang).
- `previews/preview_drama_sheet.png` und `preview_drama_<name>.png` aus `tests/capture_drama.gd` (neu): vier Boss-Auftritte und drei Anführer-Rufe, angesehen.
  - Blase und Banner überdecken sich nicht, die Mitte bleibt frei, die Vignette ist sichtbar.
  - Beute-Popups weichen nach oben aus.
  - Bei einer Mutationswahl liegt die Blase unter dem Dimmer.
- `previews/preview_ui_menu_sheets_settings(_calm)(_540).png`: die neue Zeile SPRÜCHE (Brawl und Ruhig).

**Stand:** fertig und lauffähig, nichts geparkt. Vollständiger Lauf `tools/test.ps1` inklusive `drama`: **ALL PASS** (28.09.2026).

## Offen
- Handtest: Häufigkeit im echten Run und Lesbarkeit am S25.
- Eigene Stimmen- oder Grunz-Laute zu den Sprüchen (Audio) fehlen noch.
- Zeilen zum Flutbeginn spricht bisher nur der Anführer; ein Moorbrut-Sprecher wäre möglich.
