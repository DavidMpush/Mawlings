# Backlog – nächste Etappen

Reihenfolge = Priorität. Jede Etappe wird nach `stages/README.md` abgearbeitet (Etappendatei mit Kriterien, parallele Agenten mit getrenntem Dateibesitz, Tests, Bildprüfung, Commit, Bericht). Blockierte Punkte wandern nach „Wartet auf Nutzer“; die Schleife überspringt sie.

## Roadmap (Reihenfolge = Priorität)

1. **15/16 abschließen** – Polier-Runde erledigt (siehe `stages/16_loot_magnet.md`, Abschnitt Polier-Runde). Offen: README neu gliedern, Vorschaubilder/Import-Cache aufräumen, eigene Kristallmodelle, Handtest der Flut-Momente und Kristallgrößen auf dem S25.
2. **17 Duale Progression** – Werte über Level, Waffen und Relikte über Kokons und Bosse, Seltenheit, Evolutionen über Waffe 5 + Relikt. Konzept und Schnittstellen: `stages/17_dual_progression.md`.
3. **18 Lesbarkeit nach Swarm-Vorbild (Rest)** – S1–S4 (Farbregeln in der Welt, Anführer-Ring, drei Gefahrenformen, Treffer-Blitz am Anführer), S11 Kartenzonen, S12 Kommentare. S5–S10 und S13 sind mit 15/16 erledigt.
3b. **18b Kartenlayout** – Die begrenzte Karte (Etappe 18) braucht ein gestaltetes Wegenetz statt zufälliger Streifen und Sackgassen: Wege verbinden die Regionen, eine Mitte, klare POI-Plätze (Nest, Kokon, Boss-Arena, Migrationsschlund), Landmarken als Orientierung. Glutsumpf-Rand als echte Klippe statt Geröllfeld; eigene Baum- und Klippenmodelle anfragen (`stages/ASSET_REQUESTS.md`).
3a. **17b Schwarm ohne Limit** (Nutzerwunsch 27.09.2026: „Power soll linear unendlich skalieren“) – direkt nach Etappe 17 Welle 2:
   - Das logische Limit 250 entfällt (`run_model`, `meta_data`, `profile`), Kampfkraft skaliert linear mit der Population, die Flut bleibt das exponentielle Gegengewicht.
   - Darstellung: ab 120 sichtbaren Modellen steht jedes Modell für mehrere Tiere (dichter/breiter, leicht größere Tiere, kräftigerer Bodenring); Treffer pro Tier weiterhin anteilig.
   - HUD ohne „/250“, Kurzform ab 10.000 („12,3k“).
   - Meilensteine 500/1.000/2.500/5.000/…, Trophäen-Stufen statt „Die volle Brut 250“.
   - Balance: lange Runs enden durch die Flut; Leistung stabil bei sehr großen Zahlen.
3b. **17c Anführer mit Lebensbalken + Lebensraub** (Nutzerwunsch 28.09.2026), zusammen mit 17b umsetzen:
   - Statt 3 Treffer-Pips echte LP (Start ~100) mit Balken über dem Anführer im Stil der Gegner-Leisten (grün → rot), dazu eine kleine Leiste an der Schwarm-Pill.
   - Treffer kosten angriffsabhängig LP (Jäger ~20, Boss-Stampf ~35, Moorbrut-Biss ~4, × Druck-Skalierung); kurze Unverwundbarkeit bleibt.
   - **Lebensraub** als neuer Wert (Mutation) und in Relikten (z. B. „Blutzahn“ +3 %): ein Anteil des ausgeteilten Schwarm-Schadens heilt den Anführer.
   - Regeneration wird zu LP/s; die Königszahn-Kette heilt 15 LP; Anführerherz +15 % Max-LP; der Chitinschild schützt weiter.
   - Nachfolger übernimmt mit 80 % des bisherigen Maximums.
   - Die Balance-Zielkurven gelten weiter.
3b2. **17d Stammes-Fähigkeiten** (Nutzer bestätigt 28.09.2026), direkt nach 17b/17c:
   - Genau **eine aktive Fähigkeit pro Stamm**, eigener kleinerer runder Knopf schräg über Rally (linke Hand), Cooldown 20–40 s als Ring am Knopf, **kein Zielen** (wirkt in Laufrichtung bzw. am Schwarm).
   - Klar unterschieden von Power-ups (passiv, vom Mini-Boss).
   - Glutmaw **Glutsprung** (8 m Sprung nach vorn, beißt auf der Bahn, kurz unverwundbar, 25 s)
   - Sporling **Sporenbombe** (Wolke am Schwarm, verlangsamt + Gift 5 s, 30 s)
   - Knochenkiefer **Panzerstoß** (Schockwelle wirft zurück, 2 s −60 % Verluste, 30 s)
   - Flinkzahn **Hetzjagd** (4 s +70 % Tempo, Schwarm streckt sich zur Linie, 20 s)
   - Ätzmaul **Säureschwall** (Kegel nach vorn + Pfützen, 30 s)
   - Nachtmaul **Schattenschleier** (3 s verlieren Gegner das Ziel, Warnflächen verfehlen, 40 s)
   - Relikte verändern Fähigkeiten (z. B. −20 % Cooldown, Feuerspur beim Glutsprung).
   - Später: Varianten pro Stamm über die Meta-Progression.
   - Tastatur: Q/Shift. Bot nutzt die Fähigkeit sinnvoll (vor Warnflächen, bei Einkesselung); Balance-Zielkurven halten.
3c. **19 Wüstenwelt „Dürrschlund“ mit Sandwurm** (Nutzerwunsch 27.09.2026) – Neue Biom-Reihenfolge: **Verdant Maw → Wüste → Glutsumpf**. Der Moosschlund-Schlund führt in die Wüste; deren Endboss ist der **Sandwurm**, erst sein Schlund führt in den Glutsumpf.
   - **Biom:** Dünen, Knochenfelder (Riesenrippen als Wände/Engpässe), Felsbögen, Sandstein-Klippen, vereinzelte Kakteen/Dornbüsche, Oasen als Lichtungen; Gefahr: Treibsand-Flächen (verlangsamen) und Sandstürme (Sicht, kurze Wellen). Farbwelt warmes Ocker/Sand mit türkisen Oasen, der Schwarm bleibt klar lesbar (Sand nicht zu orange).
   - **Gegner-Tints bzw. neue Wüstengegner** später; zunächst Tints der bestehenden Gegner.
   - **Sandwurm (Apex/Endboss):**
     - gräbt sich unter dem Boden (sichtbare Sandspur, Staub);
     - **Durchbruch:** Warnring unter/vor dem Schwarm, bricht senkrecht mit Rundmaul heraus, trifft pro Tier;
     - **Schwanzfeger:** halb aufgetaucht, Bogen-Fläche;
     - verwundbar nur aufgetaucht, danach kurz erschöpft (Angriffsfenster);
     - **Phase 2:** schneller und öfter, setzt Sandmaden frei (kleine Horde);
     - eigener Kadaver, Boss-Kokon (Etappe 17), Trophäe.
   - **Voraussetzung:** Modelle vom Nutzer (Prompts in `stages/ASSET_REQUESTS.md`, Abschnitt „Wüstenwelt“).
4. **19 Balance und Inhalt** – Stammspreizung nach dem Kristall-System (Sporling zu stark, Knochenkiefer auf Apex schwach), Apex-Kampfdauer 25–35 s auf allen Stufen, Aschenkröte in der Flut messen, weitere Biome/Bosse nach Modell-Lieferungen.
5. **20 Gerät und Leistung** – Samsung S25: APK installieren, Frametime/Hitze/Akku messen, Qualitätsstufen justieren, Touch-Handtest.
6. **Später: Multiplayer (Solo/Duo/Trio/Quad)** – siehe unten.
7. **Später: Monetarisierung und Marke** – Free-to-play mit Werbung, Skins, ggf. Währungen; Name/Markenprüfung.

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
