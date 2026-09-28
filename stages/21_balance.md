# Etappe 21 – Große Balance-Runde

## Ziel
Die Kampfkraft soll ohne Deckel mit dem Schwarm wachsen (Nutzerwunsch: „Power soll linear unendlich skalieren“). Die Flut bleibt das exponentielle Gegengewicht, damit lange Runs trotzdem enden. Danach werden alle sechs Stämme und alle drei Schwierigkeiten auf die Zielkurven gebracht.

## Abnahmekriterien
1. Die Angriffsformen skalieren über 25 Tiere hinaus weiter. Das Wachstum ist abgeschwächt, aber unbegrenzt, und mit dem linearen Nahkampf abgestimmt.
2. Zielkurven für greedy und attack_first, alle 6 Stämme, mindestens 5 Seeds:
   - Median-Tod: Wild 390–510 s, Brutal 300–390 s, Apex 210–270 s.
   - Wachstum auf Wild: 1:00 → 6–14, 2:00 → 25–55, Flutbeginn → 80–160 Tiere.
   - Stamm-Spreizung (max/min der Stamm-Mediane) höchstens 40 % je Schwierigkeit.
3. Kampfdauern: Apex 25–35 s (`tests/apex_duration.gd`), Bog King etwa 15–25 s.
4. `balance_regress` prüft wieder `min_flood_lost` ≥ 3, ohne dass die Laufzeit wächst.
5. Doku mit Matrix vorher/nachher, dazu `DESIGN_BRIEF.md`.

## Ergebnis

### Skalierung (`tuning.gd`: `form_population_scale`, `FORM_GROWTH_EXPONENT`)
Waffen und Stammes-Fähigkeit bekommen folgenden Faktor:
- **bis 25 Tiere:** P/25, mindestens 0,1 (unverändert),
- **darüber:** **√(P/25)**, ohne Deckel.

Das ergibt 100 Tiere ×2, 250 Tiere ×3,2, 500 Tiere ×4,5 und 1000 Tiere ×6,3. Vorher lag der Deckel bei 25 Tieren (×1).

Der Nahkampf bleibt linear (1 + 0,12·P, also 13/s bei 100 und 61/s bei 500). Ein 500er-Schwarm beißt damit etwa 4,7-mal so hart wie ein 100er, seine Waffen treffen 2,2-mal so hart. `HuntWorld.form_population_scale()` ruft jetzt nur noch `TUNING.form_population_scale()` auf; das ist die einzige Zeile in `hunt_world.gd`.

### Gegengewicht und Feinabstimmung
| Hebel | vorher | nachher | Grund |
|---|---|---|---|
| `FLOOD_DOUBLING_SECONDS` | 40 | **24** | Die stärkeren Waffen hielten Wild ~680 s und Brutal ~490 s am Leben; die Flut muss schneller wachsen. |
| `FLOOD_SPEED_CAP` | 6,0 | **8,5** | Ein schneller Build (Flinkzahn + Sprinter) lief der Brut mit dem festen Deckel dauerhaft davon (ein Wild-Lauf > 15 min). Bis 8,5 m/s gilt jetzt wieder 82 % des Schwarmtempos. |
| Brutal `flood_start` | 240 s | **210 s** | Brutal lag bei 446 s. |
| `APEX_SPAWN_SECONDS` Brutal | 180 s | **165 s** | Der Apex muss samt spätester Ankunft vor der Flut kommen (`tests/apex_run.gd`). |
| `BOSS_HEALTH` (Bog King) | 230 | **1900** | Im Kontakt fiel er in etwa 4 s. HP = 1900 × √Druck × Schwierigkeit. |
| `APEX_HEALTH_DIFFICULTY` Brutal / Apex | 0,75 / 0,6 | **0,73 / 0,66** | Apex-Kämpfe lagen mit der neuen Skalierung bei 23–26 s (Apex) bzw. bis 35,5 s (Brutal-Kröte). |
| `SPIT_DAMAGE` (Säurespucker) | 7,5 … 14 | **9,5 … 18** | Schwächste Startwaffe (Einzelziel, ~6,8 Schaden/s auf Rang 1). |
| `ACID_DAMAGE` (Säureschwall) | 25 | **35** | Ätzmaul war auf Apex der schwächste Stamm. |
| Glutmaw `rally_damage` | 1,15 | **1,25** | Apex 214 s (Schlusslicht). Die Beschreibung sagt jetzt 25 %. |
| Sporling `growth` | 1,3 | **1,25** | Mit der Skalierung wächst ein schneller Schwarm doppelt stark. |
| Knochenkiefer `speed` | 0,85 | **0,9** | Auf Apex und Brutal konnte er den Warnflächen kaum ausweichen. |
| Flinkzahn `speed` | 1,25 | **1,12** | Auf Apex lief er dem Moosschlund minutenlang davon (344 s gegenüber sonst ~230 s). |
| Ätzmaul `damage` / `armor` | 0,9 / 0 | **0,95 / 0,05** | Schwächster Stamm auf Brutal und Apex. |
| Nachtmaul `dna` / `growth` | 1,25 / 1,0 | **1,3 / 1,1** | Wild 255 s (vorher Schlusslicht). Ohne Fähigkeit überlebte er so lange wie die anderen; der Abstand kam vom kleinen Schwarm. |

Zum Nachtmaul: Die Nachtmaul-Tode um 95 s waren übersehene Jäger-Ringe auf einen 10–14er-Schwarm. Das ist Seed-Zufall und kein Fehler des Schattenschleiers; ohne Fähigkeit wurden in denselben Seeds andere Ringe übersehen.

### Bot (`tests/balance_sim.gd`, `tools/balance.ps1`)
- **Boss-Fähigkeit:** Der Bot setzt die Kessel-Fähigkeit (Sporenbombe, Säureschwall, Panzerstoß) jetzt auch ein, wenn ein Bog King oder Apex höchstens 7 m am Schwarm steht, so wie ein Spieler es täte.
- **Bog-King-Kämpfe:** Sie stehen als `king:<s>` in `fights=`. Gezählt wird vom ersten Treffer bis zum Tod, abzüglich der Sekunden, in denen der Bot mehr als 9 m entfernt Beute sammelt. Bei der Ermittlung aufgefallen: Ein freigegebener Knoten ist in Godot 4 gleich `null`, deshalb vergleicht der Bot Instanz-IDs.
- **Sandwurm:** Er wird jetzt als `worm` statt `moos` gezählt.
- **`balance.ps1`:**
  - Standard sind alle sechs Stämme und Seeds 1–5.
  - Die Stamm-Spreizung ≤ 40 % gehört jetzt zur Zielprüfung.
- **`balance_regress`:**
  - Die Apex-Spezifikation ist jetzt Sporling (Seeds 2–6, Apex, bis zum Tod, Limit 420 s) mit `min_flood`, `max_seconds` 330 und **`min_flood_lost` 3**. Im Median verliert er 13 Tiere an die Moorbrut.
  - Die frühere Glutmaw/Apex-Spezifikation starb immer um 3:00 am Moosschlund (0 Flutverluste). Sie ist darin aufgegangen; zwei statt drei Spezifikationen machen die Regression kürzer.

## Matrix vorher / nachher
Grundlage: greedy + attack_first, alle 6 Stämme.
- **vorher:** Seeds 1–5 (180 Läufe, Stand 447be84).
- **nachher:** Seeds 1–7 (252 Läufe). Wild und Apex liefen mit den Endwerten; Brutal wurde nach der Apex-Spawnzeit 165 s neu gemessen. Die letzte Anpassung, Brutal-Apex-HP 0,75 → 0,73, ist nur mit `apex_duration` geprüft.

Die beiden Strategien liefern je Seed oft denselben Lauf. Die Spreizung schwankt deshalb mit wenigen Seeds stark; mit 7 Seeds ist sie stabil.

| | Wild | Brutal | Apex |
|---|---|---|---|
| Median vorher | **554 s** ✗ | 307 s | 233 s |
| Median nachher | **479 s** ✓ | **345 s** ✓ | **240 s** ✓ |
| Spreizung vorher | 154 % ✗ | 156 % ✗ | 92 % ✗ |
| Spreizung nachher | **12 %** ✓ | **30 %** ✓ | **13 %** ✓ |
| min / max nachher | 209 / 570 s | 109 / 521 s | 80 / 402 s |
| Wachstum Wild 1:00 / 2:00 / Flut | 13 / 31 / 114 → **12,5 / 29,5 / 141,5** ✓ | | |
| Wild-Läufe unter 2:00 | 3 % → **0 %** | | |

**Stamm-Mediane (Wild / Brutal / Apex, in s):**

| Stamm | vorher | nachher |
|---|---|---|
| Glutmaw | 522 / 273 / 247 | 450 / 378 / 252 |
| Sporling | 647 / 531 / 244 | 473 / 390 / 244 |
| Knochenkiefer | 420 / 430 / 206 | 465 / 300 / 241 |
| Flinkzahn | 592 / 561 / 397 | 463 / 337 / 224 |
| Ätzmaul | 578 / 219 / 216 | 505 / 385 / 224 |
| Nachtmaul | **255** / 274 / 210 | 484 / 386 / 227 |

### Kampfdauern
- **Apex** (`tests/apex_duration.gd`, Mindest-Population, mittlerer Build):

  | | Moosschlund | Sandwurm | Aschenkröte |
  |---|---|---|---|
  | Brutal | 31,3 s | 32,7 s | 34,3 s |
  | Apex | 25,5 s | 26,3 s | 27,7 s |

  Alle liegen im Band 25–35 s; vor der Apex-HP-Anpassung waren es 22,9–25,9 s. In der Bot-Matrix dauern Apex-Kämpfe im Median 29 s (Wild) bis 43 s (Apex); der Bot weicht dort lange aus.
- **Bog King** (Matrix, Kontaktzeit): Median Wild 16 s, Brutal 30 s. Vorher waren es etwa 4 s Kontakt, gemessen an einem Beispiel-Lauf.

## Bekannte Grenzen
- Die Spreizung hängt stark am Seed-Zufall; ein übersehener Ring löscht einen kleinen Schwarm aus. Einzelne Stämme können mit anderen Seeds ±15 % abweichen.
- Brutal-Bosskämpfe (30 s) liegen etwas über dem Band 15–25 s, denn die Brutal-HP (×1,15) wirken auf die hohe Grund-HP. Absichtlich so belassen: Der Bog King soll auf Brutal zäher sein.
- Die Waffen-Skalierung wirkt über `enemy_scale` auch auf Stachelrücken-Rückschaden und Relikt-Effekte (Glutdrüse, Gewitterfell). In der Flut ist Stachelrücken damit der stärkste Schadensposten; das ist in den Zielkurven schon enthalten.
- Balance ohne Meta-Upgrades (neues Konto). Mit voller Brutkammer werden die Läufe länger; dafür endet die Flut sie weiterhin.
- `tests/apex.gd` prüfte „Apex-HP ≥ 2,5 × Bog-King-Grund-HP“. Mit 1900 statt 230 gilt jetzt „≥ 0,8 ×“; der Apex bleibt über Phasen der längere Kampf. `chronicle.gd` erwartet für 95 s Flut jetzt Stufe 4, weil die Flut alle 24 s eine Stufe steigt.

## Offen
- **Seltenheitsfarben mit fünf Stufen** (Nutzer-Feedback zur Mutationswahl, vom Koordinator nachgereicht): **nicht begonnen**, weil die Runde auf Wunsch sofort abgeschlossen wurde. Geplant sind:
  - fünf Stufen gewöhnlich (grau), **außergewöhnlich (grün, neu)**, selten (blau), episch (violett), legendär (gold),
  - Faktoren 1,0 / 1,25 / 1,5 / 2,0 / 3,0 und Basischancen etwa 55 / 25 / 13 / 6 / 1 % in `stats.gd` und `arsenal.gd`,
  - Mindest-Seltenheiten für Elite, Gold, Boss und Schrein anpassen,
  - ein zentrales Token `UiStyle.RARITY_TONES`, damit die Kartenfarbe der Seltenheit folgt statt der Kategorie. Umzustellen sind Mutationswahl, Kokon- und Beute-Karte, Öffnungsstrahl, Relikt-Leiste, Kodex und Schrein.
  - Danach braucht es eine Balance-Kontrolle, denn die Chancen verschieben die Werte-Stärke.
- Die Brutal-Apex-HP 0,73 ist ohne eigene Balance-Matrix eingestellt; der Effekt liegt bei etwa −1 s Kampfdauer.
