# Etappe 31 – Limit Break, Siegel, Run-Auswertung, Kartenobjekte

Quelle: [IDEAS_VAMPIRE_SURVIVORS.md](IDEAS_VAMPIRE_SURVIVORS.md), Empfehlung Punkt 1 (Nutzer: „mach gerne weiter“). Regeln aus DESIGN_BRIEF und Etappe 28/30 gelten: jede Build-Änderung ist eine Wahl, Plätze 4 Waffen / 6 Werte / 6 Relikte.

## A. Limit Break („Überladung“)
1. Sind alle 6 Werte auf Rang 5 (`evolution.complete()`), öffnet ein Level-up statt der Heilung eine **Überladungs-Wahl 1 aus 3**: kleine Dauer-Boni ohne Platz und ohne Rang-Deckel.
   - Pool: Biss +2 %, Angriffstempo −1,5 %, Reichweite +2 %, Tempo +1 %, Magnet +3 %, Brutrate +2 %, Rüstung −1,5 % Verluste, Lebensraub +0,3 %, Anführer-LP +4 %.
   - Werte je Stufe nach Seltenheit (gleiches Farb- und Faktorsystem wie Werte).
2. Karte „ÜBERLADUNG“ mit eigenem Etikett. Die Heilung bleibt als vierte, immer vorhandene Option „Anführer heilen“, wenn der Anführer unter 60 % LP hat. Sonst gibt es nur die drei Boni.
3. Deckel: jede Überladung höchstens +50 % bzw. −30 % gesamt; Anzeige der Summe im Pause-Build-Blatt oder auf der Karte („gesamt +12 %“).
4. Tests: complete → Überladungs-Wahl, Werte addieren sich, Deckel, Reroll/Überspringen funktionieren, Balance-Bot wählt.

## B. Siegel (Pool vor dem Run kuratieren)
1. In der Brutstätte gibt es ein neues Blatt **SIEGEL** (Tab neben der Brutkammer). Es listet Werte, Waffen und Relikte (Kodex-Icons). Antippen versiegelt oder löst; versiegelte Einträge werden im Run **nie angeboten** (Level, Schrein, alle Kokons).
2. Anzahl der Siegel: Start 2, Brutkammer-Upgrade „Siegelring“ +1 je Rang (max. 6, Kosten wie andere Upgrades). Die Startwaffe des Stamms lässt sich nicht versiegeln.
3. Speichern im Profil (`sealed: Array[String]`); die RunConfig erhält `sealed`; `evolution`, `stats` und `arsenal` filtern die Pools. Nie weniger als 3 Kandidaten je Art: Reicht es nicht, werden Siegel für diesen Run ignoriert und ein Hinweis erscheint.
4. Tests: Profil speichert, Config enthält, Angebote enthalten nie versiegelte Ids, Limit, Startwaffe.

## C. Auswertung nach dem Run
1. Das Ergebnis-Overlay bekommt eine zweite Seite oder einen Bereich **„DEIN BUILD“**: je Waffe/Evolution, Nahkampf, Fähigkeit und Relikt-Effekt der verursachte Schaden (Summe und Anteil als Balken), dazu die Ränge und die Reihenfolge der Wahlen (Level/Zeit).
2. Daten aus `run_stats()` (Schaden je Quelle: `attack_forms` dealt, `melee_dealt`, Fähigkeit); Chronik speichert die Top-3-Quellen.
3. Prüfbild nach einem echten Run (Capture).

## D. Kartenobjekte mit Sofort-Effekt
1. Neues System `scripts/map_items.gd`: seltene **Glutpilze** (leuchtende, klar sichtbare Pilzkörbe) liegen auf der Karte, etwa 8–12 je Karte (kein Kleinzeug-Konflikt, Deko ohne Kollision). Ein Biss bricht sie; mit Chance erscheint ein Sofort-Item, das beim Hinlaufen wirkt (wie Power-ups: kein Magnet):
   - **Heilpilz** (grün): Anführer +30 % LP.
   - **Zeitstarre** (eisblau): alle Gegner und die Brut 5 s eingefroren (Angriffe pausiert, Warnflächen halten an).
   - **Bildschirm-Biss** (Glut): alle Gegner im Bild nehmen hohen Schaden (Bosse 10 % max. LP); Brut im Bild stirbt.
   - **Lockruf** (vorhanden): alle Kristalle.
2. Die Items bleiben liegen, bis sie aufgesammelt werden (Ressourcenregel), blinken nach 45 s und sind nach der Entdeckung auf der Minimap.
3. Tests und Prüfbild.

## E. Lava-Farbe (offen aus Etappe 29)
Lava soll glühen statt braun wirken: hellere, gesättigte Glut in den Adern, dunklere Kruste, leichtes Pulsieren.

## Schnittstellen
- RunConfig `sealed: Array[String]`; `evolution.sealed` (von `configure`), gefiltert in `stats.candidates`, `arsenal.roll_chest/_pick_relic` und Start-Kokon.
- `evolution.overdrive: Dictionary` (id → Summe); `evolution.overdrive_offers()`; die Wahl läuft über die normalen `offers` mit Karten `[id "od_<stat>", Name, Desc, rarity]`.
- `hunt_world.run_stats()["damage"] = {source_id: float}`, `["picks"] = [[t, kind, id], …]`.
- `hunt_world`: `map_items` (Node), `freeze_left` (Sekunden; Gegner-`step` pausiert bei > 0).

## Ergebnis (29.09.2026)

- **A Überladung:**
  - Sind alle 6 Werte auf Rang 5, öffnet ein Level-up (bzw. ein Schrein) eine 1-aus-3-Wahl aus 9 Dauer-Boni. Werte je Seltenheit, Deckel +50 % bzw. −30 %; die Karte zeigt „gesamt +N %“.
  - „Anführer heilen“ nimmt den dritten Platz ein, wenn der Anführer unter 60 % LP hat.
  - Sind alle Boni gedeckelt, heilt ein Level-up wieder automatisch.
  - Verbannen ist bei diesen Karten aus; der XP-Balken füllt sich weiter.
  - Ein Schrein, der während einer offenen Wahl geladen wird, wartet (`queued_shrines`).
- **B Siegel:**
  - Neues Brutstätten-Blatt SIEGEL (Werte, Waffen, Relikte; nur Entdecktes versiegelbar; Startwaffe mit START-Etikett).
  - 2 Siegel, Brutkammer-Upgrade „Siegelring“ +1 je Rang (max. 6).
  - `Profile.sealed` → `RunConfig.sealed` → `evolution/stats/arsenal` filtern Level, Schrein, alle Kokons und die Überladung.
  - Sinkt eine Art unter 3 Kandidaten, gelten ihre Siegel in diesem Run nicht (`seals_ignored`).
- **C Auswertung:**
  - Ergebnis-Knopf BUILD mit Seite „DEIN BUILD“: Schaden je Quelle (Waffen, Evolutionen, Relikt-Effekte, Nahkampf, Fähigkeit) als Rangliste mit Balken, dazu eine Zeitleiste aller Wahlen (Farbe = Seltenheit).
  - `run_stats.damage/picks`; die Chronik speichert die Top 3.
- **D Kartenobjekte:**
  - 8–12 Glutpilzkörbe je Karte, ohne Kollision. Ein Biss öffnet einen Korb; mit 60 % liegt ein Item darin:
    - Heilpilz (+30 % LP)
    - Zeitstarre (5 s alles eingefroren, Nahkampf wirkt weiter)
    - Bildschirm-Biss (18 m; Bosse −10 % max. LP)
    - Lockruf
  - Ohne Item gibt der Korb 4 Bernstein.
  - Die Items bleiben liegen (Hinlaufen, kein Magnet) und erscheinen nach der Entdeckung auf der Minimap.
- **E Lava:** dunkle Krustenplatten mit breiteren, hell glühenden Adern statt braunem Karamell.
- **Nebenbei:**
  - Das Item- und Power-up-Band sitzt unter dem Schwarm (0,64 statt 0,32), weil es die Sprechblasen verdeckte.
  - Sprechblasen höchstens 52 % breit.
  - Das Tor-Siegel hat leuchtende Runenringe (`preview_gate_sealed.png`).
- **Prüfung:** komplette Suite grün, `balance_regress` besteht. Prüfbilder `preview_ui_menu_sheets_seals*`, `preview_ui_result_build*`, `preview_map_items_*`, `preview_water_lava`.
- **Offen:** Farbe gefrorener Gegner (derzeit nur Randtönung und Hinweis); die alte (nicht-brawl) Kartenoptik für die Überladung.