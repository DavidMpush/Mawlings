# Backlog – nächste Etappen

Reihenfolge = Priorität. Jede Etappe wird nach `stages/README.md` abgearbeitet (Etappendatei mit Kriterien, parallele Agenten mit getrenntem Dateibesitz, Tests, Bildprüfung, Commit, Bericht). Blockierte Punkte wandern nach „Wartet auf Nutzer“; die Schleife überspringt sie.

## Roadmap (Reihenfolge = Priorität, Stand 28.09.2026)

Erledigt seit dem letzten Aufräumen: 15 UI-Supercell, 16 Kristalle/Magnet, 17 duale Progression (Werte, Arsenal, Kokons, Power-ups, Schreine, Bernstein), 17b Schwarm ohne Limit, 17c Anführer-LP + Lebensraub, 17d Stammes-Fähigkeiten, 18/18c Erkundungskarte, 19 Wüste + Sandwurm, 20 Gefahren-Lesbarkeit, 22/22b Leistung, 23 Audio, 24 Einstieg, Kodex. Details in den Etappendateien.

### Offene Todos

**Neues S25-Nutzerfeedback (28.09.2026):** [Playtest-Protokoll](../playtests/2026-09-28_s25_feedback.md) – nach drei Migrationen/über 15 Minuten zu wenig Gegner zwischen Fluten, Wunsch nach Hordenwellen; außerdem dynamischer rechter Joystick, verdeckte XP-Anzeige, Gebietsnamen-Overlay entfernen und Sprungfähigkeiten über schmale Hindernisse. Noch nicht umgesetzt; vor weiterer Content-Ausweitung als nächsten Geräte- und Survival-Pass priorisieren.
0. **Stand 28.09.2026 abends (Commit „World reset + stronger apex“):** Umgesetzt, aber **ohne abschließenden Balance-Kontrolllauf**:
   - Apex-Bosse deutlich stärker als der Bog King (Ziel ≥ 3× LP, Kampf 45–70 s).
   - Migration setzt Druck und Flut zurück (Schwarm, Build, Level, Relikte und Bernstein bleiben), Welt-Bonus je Welt, Welt-Anzeige im HUD.
   - Lautstärkeregler im Pause-Menü.
   - **Nächster Schritt:** Kurzer Balance-Lauf (6 Stämme × 3 Seeds, max. 30 min), `apex_duration` prüfen, Zielkurven für Welt 1 und „erreichte Welten“ (Ziel: guter Run erreicht Welt 2–3) dokumentieren, komplette `tools/test.ps1` inkl. `balance_regress` laufen lassen.
1. **Seltenheitsfarben (Nutzerwunsch):** Karte farbig nach Seltenheit: gewöhnlich grau, **außergewöhnlich grün (neue Stufe)**, selten blau, episch violett, legendär gold, überall gleich (Level-Karten, Kokon-Beute/-Strahl, Boss-Kokon, Kodex, Schrein); Kategorie nur als kleines Label. Stand siehe `stages/21_balance.md`.
2. **Balance-Rest (Etappe 21):** Zielkurven über alle 6 Stämme schließen (siehe `stages/21_balance.md`), Nachtmaul; Waffen-Skalierung über 25 Tiere prüfen; `balance_regress`-Toleranz wieder anheben. Messläufe künftig zeitlich begrenzen (max. ~30 min pro Runde).
3. **Dramaturgie (Etappe 25):** Rest laut `stages/25_drama.md` (Sprechblasen, Boss-Auftritt/-Sieg).
4. **Handtest am Gerät:** APK bauen (Java-Pfad im Editor auf `G:/Users/David/Java` stellen), Leistung und Tastgefühl auf dem S25, Audio-Pegel nach Gehör.
5. **Assets vom Nutzer:** `stages/UI_ASSET_REQUESTS.md` (Icons, Porträts, Glyphen), `stages/ASSET_REQUESTS.md` (Ruinen-Mauern/Säulen, Dschungelbaum, Oasen-Palme, Kokon/Schrein/Pilzknolle-Modelle, Wüsten-Biomkarte, Sandwurm-Porträt).
6. **Kleinere Punkte:** Glutsumpf-Übersicht kontrastarm; Sumpfwasser zeigt Raster; Ruinen-Quader schlicht (bis Modelle da sind); Kaktus/Schädel von oben klumpig; Sandmaden im Getümmel klein; erschöpfter Sandwurm formlos; eigene Glutsumpf-Musik; Kartenbau beim Run-Start (~0,3 s) noch im Ladeframe; Bot ignoriert die Entdeckung.
7. **Später:** Multiplayer (unten), Monetarisierung und Marke (Free-to-play mit Werbung, Skins, ggf. Währungen; Name/Markenprüfung).

### Multiplayer-Modus (Roadmap, Nutzerwunsch 27.09.2026)
- **Modi:** Solo, Duo, Trio, Quad. Mehrere Spieler mit je einem eigenen Schwarm auf **derselben Map**; sie konkurrieren darum, wer am längsten überlebt (letzter Schwarm gewinnt, Platzierung nach Todeszeit).
- **Nach dem Aussterben:** zuschauen mit Wechsel zwischen den verbleibenden Spielern (Kamera folgt deren Schwarm, Wischen/Tippen zum Wechseln) oder das Spiel verlassen (Ergebnis wird verbucht).
- **Skalierung:** Gegnerzahl, Flut-Stärke, Boss-LP, Kristalle, Kokons und Ressourcen skalieren mit der Spielerzahl (Startwerte je Spieler, z. B. Gegner ×(1 + 0,7·(n−1)), Kokons ×n, Map-Größe/Regionen größer).
- **Lobby und Matchmaking:**
  - Solo startet direkt.
  - Duo, Trio und Quad haben eine Lobby: Freunde einladen (Code/Freundesliste) oder allein zufällig suchen.
  - Später eine Rangliste (MMR) für faires Matchmaking. Die Meta-Upgrades werden in Ranglistenspielen gedeckelt oder angeglichen.
- **Vorschlag PvP (vom Nutzer noch zu bestätigen), Battle-Royale-Bogen:**
  1. Start in eigenen Regionen, 80–100 m auseinander, die Karte wächst mit der Spielerzahl, zuerst reines PvE.
  2. Indirekter Wettbewerb: Beute wegschnappen, Kokons zuerst öffnen, Gegner und Bosse zu anderen locken.
  3. Die **gemeinsame Flut** drängt die Spieler zusammen (schrumpfende Zone). Erst ab der Flut schaden sich Schwärme bei Kontakt.
  4. Gegen Schneeball: kleine Schwärme machen Bonusschaden gegen große; wer einen gegnerischen Anführer tötet, bekommt einen Kokon.
  - PvP ist als Schalter abschaltbar; erste Version ggf. rein kompetitiv ohne direkten Schaden.
- **Beute nach Beteiligung (Nutzerwunsch, Fairness-Vorschlag):**
  - **Gegner:** gehört dem Spieler mit dem meisten Schaden (nicht dem letzten Treffer). Die Kristalle erscheinen in der Besitzerfarbe und sind 6 s geschützt, danach für alle.
  - **Bosse:** Jeder Spieler mit mindestens 20 % Schadensanteil erhält einen eigenen Boss-Kokon, der Spieler mit dem meisten Schaden zusätzlich einen Seltenheitsbonus.
  - **POIs (Nest/Totem):** gehören dem Spieler mit der längsten Haltezeit.
  - **Kokons:** öffnet, wer zahlt.
- **Gemeinsame Flut** für alle Spieler (Nutzerentscheidung).
- **Technik (vor Umsetzung zu klären):**
  - **Netzwerk:** Server-autoritativ (dedizierter Server oder Relay mit Host), Godot High-Level Multiplayer/ENet bzw. WebSocket. Echte Kosten entstehen durch Server-Hosting, Matchmaking-Backend und Konten.
  - **Synchronisation:** Nur Schwarm-Zentren, Eingaben und Gegner-Zustände übertragen, nicht einzelne Tiere; die Tiere der Schwärme berechnet jeder Client selbst.
  - **Architektur, die wir schon jetzt nicht verbauen sollten:**
    - HuntWorld muss mehrere Schwärme verwalten können: `swarm` zu `swarms[]`, Gegner wählen das nächste Ziel, Treffer pro Schwarm.
    - Eingabe (`touch_controls`) wird vom Schwarm entkoppelt (Eingabe-Befehle statt direkter Zugriffe).
    - Die Simulation bleibt deterministisch mit Seed (dafür ist die lastunabhängige Balance-Simulation aus 15/16 ein Anfang).
    - Die Meta-Progression wird serverseitig geprüft, falls gewertet wird.
  - **Aufwand:** großer eigener Block (mehrere Etappen). Sinnvoll erst, wenn das Einzelspieler-Spiel steht und auf dem Gerät getestet ist.

### Erledigt (Kurzliste)
07 Leistung · 10 Apex & Migration · 12 Aschenkröte · 13 UI-Stil (ersetzt durch 15) · Teilen-Karte · Typografie (in 15)

## Wartet auf Nutzer

- **Schriftwahl:** 8 OFL-Kandidaten liegen unter `assets/ui/fonts/candidates/` (Vergleich `tests/capture_fonts.gd`). Empfehlung: Baloo 2 ExtraBold (Titel) + Figtree (Text).
- **Gefahrenfarbe:** Magenta statt Rot für Gegnerflächen (eigene Farbe bleibt Glut-Rot)?
- **Reihenfolge:** Etappe 14 (Swarm-Lesbarkeit) als Nächstes?
- **Android-Test auf dem Gerät:** APK baut (`tools/export_android.ps1`); Handy mit USB-Debugging anschließen.
- **Modelle (Hunyuan3D):** Skitter, Moorbrut, Moosschlund, Aschenkröte, Brutnest, Stamm-Anführer, Glutsumpf-Requisiten (Prompts in `stages/ASSET_REQUESTS.md`).
- **Später:** Name/Markenprüfung, Monetarisierung (Free-to-play mit Werbung und Skins).
- **Handtest:** 5–10 Minuten Spielgefühl.

## Erledigt
- 01 Bewegung & Lesbarkeit · 02 Welt & Assets · 03 Progression · 04 UI-Komponenten · 05 Spielgefühl, Balance, Lesbarkeit · 06 Ziele, Einstieg, UI-Politur, Leistungsmessung · 07 Leistung · 08 Die Flut & Schwierigkeit · 09 Einzelstart & Anführer · 10 Apex, Migration, Build-Vielfalt, Nutzer-Sounds/Drops/Icons · Minimap · V2-Stil · Aschenkröte · Asset-Paket V3 · Android-Export · 16 Beute-Kristalle & Magnet · 18 Begrenzte Karte (`stages/18_bounded_map.md`)
