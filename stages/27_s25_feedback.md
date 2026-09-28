# Etappe 27 – S25-Feedback: Survival-Druck, Joystick, XP, Gebiets-Overlay, Sprung

Quelle: [Playtest-Protokoll 28.09.2026](../playtests/2026-09-28_s25_feedback.md) (Debug-APK auf dem Samsung S25, Stand `5186d6e`, über drei Migrationen, Welt 4 bei 16:17 mit 425 Mawlings).

## Befund (Code-Analyse)

- **Ruhephasen:** Jäger/Skitter/Leaper haben feste Obergrenzen (12/3/3), ihr Budget wächst mit der **Weltzeit**, die jede Migration auf 0 setzt (`hunters_unlocked_at = elapsed` → wieder 1 Jäger). Moorbrut-Horden gibt es nur in der Flut. Ein Schwarm mit 400 Tieren tötet einzelne Jäger sofort, also passiert zwischen den Fluten fast nichts.
- **XP-Balken:** 10 px hoch am oberen Rand. `_xp_top()` rechnet den Display-Safe-Area-Rand (Bildschirmpixel) in das 900 × 1600-Bild um, obwohl das Spiel mit `aspect = keep` letterboxed läuft. Auf dem S25 rutscht der Balken dadurch auf etwa y ≈ 70, mitten hinter die obere Pillenreihe (y 28–108), und wird überdeckt.
- **Gebietsbanner:** `hud_minimap.gd` blendet beim Betreten einer Region Namen und Spruch ein.
- **Glutsprung:** `_start_leap()` läuft die Linie in 1-m-Schritten mit `resolve_motion` ab und endet am ersten Hindernis.

## Ziele und Abnahmekriterien

### A. Survival-Druck (höchste Priorität)
1. **Hordenwellen** (neu, `hunt_world.gd`): Außerhalb der Flut kommen regelmäßig angekündigte Moorbrut-Wellen **aus einer Richtung**. Welt 1 ab 100 s, spätere Welten ab 35 s, Abstand 50 s (je weiterer Welt kürzer, min. 32 s). Vorwarnung 3 s mit Kontextzeile „HORDE NAHT!“, Hinweiszeile unten, Warnsound und Gefahrenring. Während der Flut-Ankündigung, der Flut, 25 s vor einem fälligen Apex, im Apex-Kampf und während der Migration kommen keine Wellen.
2. Die Stärke passt zu Welt, Welle und Schwarm: Anzahl und LP wachsen mit der Population (LP über log2(P/25)); Biss und Tempo wachsen nur mit Welt und Wellennummer, denn Bissverluste skalieren ohnehin mit P. Deckel: `SURGE_MAX` je Welle und gemeinsam mit der Flut `FLOOD_MAX_ACTIVE` (160, S25-Leistung).
3. **Grundpräsenz nach Migration:** Der Direktor startet in Welt n mit Vorsprung: Jäger-Budget und -Deckel +2/+3 je Welt, Skitter/Leaper +1 je Welt (Deckel 6).
4. Welt 1 bleibt in den ersten ~100 s wie bisher (Einzelstart fair). `balance_regress` besteht, `endless_playthrough` stirbt nicht früh aus.
5. Nachweis: Test `tests/surge.gd` (Zeitplan, Richtung, Vorwarnung, keine Wellen während der Flut, Skalierung, Pause, Migration, Reset) und ein Bot-Lauf über mindestens eine Migration mit „Gegner-Aktivität zwischen Fluten“ (Kills/min nach der Migration nicht unter Welt 1).

### B. Schwebender Joystick rechts (`touch_controls.gd`, `hud_controls.gd`)
1. Eine Berührung in der rechten Bewegungszone (rechte Hälfte, unterhalb des Top-HUD, nicht auf Pause/Minimap/Karte/Fähigkeit) setzt den Joystick-Ursprung an die Daumenposition. Die Bewegung ergibt sich aus der Verschiebung relativ dazu (Radius 66 px wie bisher).
2. Loslassen setzt die Eingabe auf 0; der Joystick kehrt in die Ruheposition zurück (gedimmt).
3. Der Ursprung wird so geklemmt, dass der gezeichnete Joystick ganz im Bild bleibt.
4. Rally links, die Fähigkeit, Pause, Minimap und Karte bleiben eindeutig bedienbar, auch mit zwei Daumen gleichzeitig.
5. Test: `smoke.gd`/eigener Test prüft Ursprung = Aufsetzpunkt, Richtung relativ, Reset beim Loslassen, gleichzeitiges Rally, keine Übernahme von Pause/Minimap.

### C. XP-Anzeige sichtbar (`hud_top.gd`)
1. Kein Umrechnen der Display-Safe-Area bei letterboxed Viewport. Der Balken liegt oberhalb der Pillenreihe und wird von keinem Panel überdeckt.
2. Deutlich sichtbarer: höher (16 px), heller Rahmen, Leuchten bei Level-up. Die Ruhe-Optik bleibt dezent (dünne violette Leiste, ohne Zahlen).
3. Sichtprüfung mit Capture: normal, mit Bossleiste, mit Flut.

### D. Gebietsnamen-Einblendung entfernt (`hud_minimap.gd`)
1. Beim Betreten einer Region erscheint kein Banner mehr. Namen auf der großen Karte, Minimap und Landmarken bleiben.
2. `minimap.gd` prüft, dass kein Banner erscheint.

### E. Glutsprung über schmale Hindernisse (`abilities.gd`, `swarm.gd`)
1. Der Sprung prüft die Linie in 0,25-m-Schritten: Blockierte Abschnitte bis `LEAP_HOP_MAX` (5,5 m blockiert entlang der Linie inkl. 2 × 0,75 m Schwarmradius, also ca. 4 m echte Dicke) werden übersprungen, breitere Wände und der Kartenrand nicht.
2. Landepunkt: der fernste freie Punkt auf der Linie (`arena.is_open(p, 0.75)`), hinter dem nur schmale Abschnitte liegen. Gibt es keinen, gilt das alte Verhalten (Stopp vor der Wand).
3. Der Landepunkt liegt immer in der Karte und auf freiem Boden. Die Tiere hängen nach der Landung nicht hinter der Wand: Während der Flugkurve werden sie nicht an Wände gedrückt, danach rücken sie zum Schwarm auf.
4. Der Spieler kann nachvollziehen, was passiert: Die Bogenhöhe wächst etwas mit der Sprungweite, Start- und Landering bleiben.
5. Test in `abilities.gd`: schmaler Stein → Landung dahinter, breite Wand → Stopp davor, Kartenrand → nie außerhalb.

## Schnittstellen

- `hunt_world`: neue Felder `surge_state` (0 ruhig, 1 Vorwarnung, 2 läuft), `surge_index` (Wellen in dieser Welt), `surge_total`, `surge_clock`, `surge_heading: Vector3`; `surge_stats()`, `surge_count()`. HUD-Wert `surge` = `surge_total` (hud_top zeigt bei Änderung die Kontextzeile).
- `horde.spawn_ring(center, amount, radius, stats, heading := Vector3.ZERO)`: Mit `heading` wählt der Kartenpfad Punkte in diesem Sektor (`arena.flood_point(salt, heading)`).
- `touch_controls`: `_movement_center()` liefert den aktiven Ursprung (sonst die Ruheposition), dazu `movement_rest_center()`, `movement_active()`.
- `abilities`: `LEAP_HOP_MAX`, `_leap_landing(from, dir, distance) -> Vector3`.

## Ergebnis (28.09.2026)

**Umgesetzt:**
- **A:** Hordenwellen (`hunt_world.gd` `_step_surges`, Zahlen in `tuning.gd` `SURGE_*`), Horde läuft auch außerhalb der Flut (`_step_horde`), Richtung über `arena.flood_point(salt, heading)`, Warnung per Hinweis, Kontextzeile „HORDE NAHT!“, Warnringe Richtung Welle und Sound. Direktor: Jäger +2 Budget/+3 Deckel je Welt, Skitter/Leaper +1 je Welt ab Weltzeit 15 s. Keine Welle 25 s vor dem fälligen Apex (`SURGE_APEX_GAP`): Sonst lebte die Brut im Bosskampf, und die Apex-Verluste im Bot stiegen von ~25 auf ~80.
- **B:** schwebender Joystick (`touch_controls.gd`: Zone rechte Hälfte ab 30 % Höhe, Ursprung geklemmt; `hud_controls.gd`: Ruhe-Joystick gedimmt), Test `tests/joystick.gd`.
- **C:** XP-Balken 16 px über der Pillenreihe; die Safe-Area wird relativ zur letterboxed Viewport-Kante gerechnet (`hud_top.gd` `_xp_top`). Der „WELT n“-Chip rutscht darunter.
- **D:** Gebietsbanner aus (`hud_minimap.gd` `REGION_BANNER := false`).
- **E:** Glutsprung springt über bis zu 5,5 m blockierte Linie (`abilities.gd` `_leap_landing`). Die Tiere ziehen sich in der Luft zusammen und landen gemeinsam (`swarm.gd` `LEAP_TUCK`); Tests für schmal/breit/Kartenrand und 2000 Sprünge auf einer echten Karte.

**Prüfung:** `tools/test.ps1` komplett grün (neu: `joystick`, `surge`; `balance_regress` besteht, Apex-Median 265 s). Prüfbilder `tests/capture_surge.gd` (Warnung, Welle), `preview_joystick_*`.

**Balance-Kontrolllauf** (6 Stämme × 3 Schwierigkeiten × Seeds 1–3, `attack_first`, Limit 20 min, 54 Runs):
- **Zweigeteilt:** 27 Runs sterben am ersten Apex oder vorher (Wild ~285–400 s, Brutal ~210–300 s, Apex ~80–315 s), 27 Runs besiegen ihn, migrieren 3–6 Mal, wachsen auf 760–1590 Tiere und erreichen das 20-min-Limit. Keiner dieser Runs stirbt in Welt 2+.
- **Aktivität nach der Migration:** Kills/min in Welt 2+ ≈ 57–80, in Welt 1 im Mittel ≈ 30–120, also nicht niedriger (Kriterium A5 erfüllt). Pro 20-min-Run gibt es 7–16 Hordenwellen.
- **Ursache (seit Etappe 26, Weltreset):** Nach der Ankunft kommt der Apex nach 100 s. Der Bot (und ein Spieler) migriert danach, bevor die Flut der neuen Welt (Wild 270 s Weltzeit) je beginnt. Das exponentielle Gegengewicht greift also nie; die Welt-Boni (+25 % je Welt) und die Hordenwellen reichen gegen einen Schwarm mit über 1000 Tieren nicht. Schon der Regress-Lauf auf `5186d6e` zeigte zwei Sporling/Apex-Seeds, die nach einer Migration bis zum Limit überlebten.
- Die Zielbänder der Schwierigkeiten (Wild 390–510 s usw.) passen nicht mehr zum Weltreset-Modell. Neue Ziele (z. B. „guter Run erreicht Welt 2–3 und stirbt dort“) braucht eine Nutzerentscheidung, siehe Backlog.

**Nachtrag – Late-Game-Druck, Nutzerentscheidung Variante (c):** In Welt n beginnt die Flut bei Weltzeit `flood_start × 0,6^(n−1)`, frühestens nach 60 s (Wild 270 → 162 → 97 → 60 s), und zwar gleich FLOOD_WORLD_STAGE = 1,5 Stufen höher je Welt (×2,8 / ×8 / ×22). Nur der frühere Start reichte nicht: Im Lauf blieben 27 von 54 Runs bis 20 min am Leben. Mit der Stufe stirbt jeder Run. Die guten Runs erreichen Welt 3–5 und enden meist in der Flut: Wild nach 14–19 min (3–4 Migrationen), Brutal nach 8–14 min (1–3), Apex nach 10–13 min (1–3). Offen bleibt die Zweiteilung am ersten Apex: Etwa die Hälfte der Runs stirbt dort nach 3–6 min, das ist die Apex-Stärke aus `5186d6e`. Das wird ein eigener Balance-Punkt.

**Offen:** S25-Vergleichsrun (Leistung mit Wellen und 160 Brut, Joystick, XP-Sichtbarkeit am Gerät); Entscheidung zum Late-Game-Druck ab Welt 2.