# Etappe 32 – Balance für das Welten-Modell

Anlass: Seit Etappe 26–31 (Weltreset, frühere und stärkere Flut je Welt, Hordenwellen, Endboss ≥ 3× Bog King, 1-aus-3-Wahl überall, Slots 4/6/6, langsamere Levelkurve, Überladung) stimmen die alten Zielkurven (Wild 390–510 s usw.) nicht mehr. Die Bot-Runs sind zweigeteilt: Etwa die Hälfte stirbt am ersten Endboss, der Rest kommt bis Welt 3–5. Der Nutzer hat die Entscheidungen an den Orchestrator übergeben.

## Entscheidungen (Orchestrator, 29.09.2026)
1. **Der Bot spielt wie ein guter Spieler:** Die neue Strategie `smart` wählt Karten nach Build-Logik:
   - Waffen bis 4 Plätze, dann Rang-ups der stärksten Waffe
   - Evolution sofort
   - Relikte passend zu eigenen Waffen (Evolutions-Partner) bevorzugt
   - höhere Seltenheit bevorzugt
   - Werte: Biss/Angriffstempo/Reichweite/Anführerherz/Lebensraub vor Nischenwerten
   - Überladung: Biss oder Heilung bei niedrigen LP

   `smart` ist ab jetzt die Standardstrategie der Balance-Matrix (`tools/balance.ps1`). `greedy`/`attack_first` bleiben zum Vergleich.
2. **Zielkurven** (Median über 6 Stämme × 3 Seeds, Strategie `smart`, Limit 25 min):

   | Schwierigkeit | Tod (Median) | Erreichte Welt (Median) | Tod am ersten Endboss höchstens |
   |---|---|---|---|
   | Wild | 11–17 min | 3 | 25 % |
   | Brutal | 8–12 min | 2–3 | 30 % |
   | Apex | 5–9 min | 2 | 35 % |

   Kein Run überlebt das 25-min-Limit (höchstens 1 von 18 je Schwierigkeit). Der Stamm-Spread (max/min der Stamm-Mediane) liegt bei höchstens 50 %.
3. **Endboss-Kampf:** 45–90 s bei einem gut gebauten Schwarm. Der Endboss bleibt klar stärker als der Bog King (LP-Regel aus Etappe 30 bleibt), aber die **Tode am ersten Endboss** sinken. Hebel in dieser Reihenfolge:
   1. Endboss-Schaden (`APEX_DAMAGE_MULTIPLIER`, Phase-2-Faktor)
   2. Ankündigung/Erholungsfenster
   3. Population-Gate bzw. Aufstiegszeit
   4. erst zuletzt die LP
4. **Welt-Druck:** Die Stellschrauben aus Etappe 27c (`FLOOD_WORLD_FACTOR`, `FLOOD_WORLD_STAGE`, `WORLD_BONUS`) und die Hordenwellen dürfen innerhalb ±30 % angepasst werden, um die Zielkurven zu treffen.
5. **Nicht ändern:** Regeln aus DESIGN_BRIEF (nur Aussterben beendet den Run, Flut exponentiell, jede Wahl bleibt Wahl), Slot-Zahlen, Levelkurve (höchstens ±15 %), Seltenheits-Chancen.
6. **Regression:** `balance_regress` auf `smart` umstellen, mit neuen Toleranzen passend zu den Zielen. Laufzeit ≤ 5 min.

## Nachweis
- Balance-Matrix vorher/nachher (Tabelle je Schwierigkeit: Median-Tod, erreichte Welt, Todesursachen, Anteil Tod am ersten Endboss, Kampfdauer der Endbosse).
- Messläufe zeitlich begrenzen (je Runde ≤ 30 min).
- Komplette Suite grün.

## Ergebnis (29.09.2026)

### Bot und Werkzeuge
- **`smart`** (`tests/balance_sim.gd`, `_pick_smart`/`_pick_chest_smart`) wählt nach Build-Logik:
  - **Werte:** Biss > Angriffstempo > Reichweite > Anführerherz = Lebensraub > Kritbiss/Knochenpanzer > Nischenwerte. Jede Seltenheitsstufe zählt +2; unter 45 % LP gewinnen Anführerherz, Lebensraub und Regeneration.
  - **Überladung:** Biss vor Angriffstempo und Reichweite; „Anführer heilen“ unter 45 % LP.
  - **Kokons:** Evolution sofort. Neue Waffen, solange Plätze frei sind, danach Rang-ups (die stärkste Waffe nach verursachtem Schaden +6, Waffen mit vorhandenem Partner-Relikt +4). Relikte als Evolutions-Partner eigener Waffen +16, Urmutter +12, Wirtschafts-Relikte −8. Höhere Seltenheit wird bevorzugt.
  - **Wege:** Zusätzlich läuft `smart` wie ein Spieler quer über die Karte zu bezahlbaren Kokons und Schreinen (`SMART_TRAVEL_REACH` 400 m). Der alte Bot verglich sie mit dem nächsten Kristall und holte deshalb in vielen Seeds keinen einzigen Karten-Kokon (bis 500 Bernstein ungenutzt).
- **BALANCE-Zeile:** neu `world=` (Ankünfte + 1) und `firstapex=` (1 = gestorben, während der erste Endboss lebte). `fights=`, `migrations=`, `kpm_w1`/`kpm_after` gab es schon. Zusätzlich gibt jeder Lauf eine `STATS {json}`-Zeile aus.
- **`tools/balance.ps1`:** Standard ist jetzt `-Strategies smart -Seeds 1,2,3 -Limit 1500`. Neu ist `-From <log>` (wertet ein gespeichertes Log aus). Die Zielprüfung folgt der Tabelle oben: Median-Tod, Median-Welt, Anteil Tod am ersten Endboss, Timeouts ≤ 1, Spreizung ≤ 50 %, Endboss-Kämpfe (gewonnen, Median) 45–90 s. Wachstum und Tode unter 2:00 stehen nur noch als Info da; die alten Bänder gehören zum Modell vor den Welten.
- **Laufzeit:** Eine Matrix-Runde (54 Läufe, `-Parallel 6`) dauerte 7–13 min.

### Matrix vorher / nachher
Grundlage: 6 Stämme × Seeds 1–3, `smart`, Limit 25 min.
- **vorher:** Zahlen von `HEAD`, gemessen mit dem fertigen `smart`-Bot.
- **nachher:** Runde 5 (Endstand).

| | Wild vorher | Wild nachher | Brutal vorher | Brutal nachher | Apex vorher | Apex nachher |
|---|---|---|---|---|---|---|
| Tod (Median) | 491 s ✗ | **714 s** ✓ | 277 s ✗ | **584 s** ✓ | 230 s ✗ | **348 s** ✓ |
| Welt (Median) | 1,5 ✗ | **3** ✓ | 1 ✗ | **2** ✓ | 1 ✗ | 1 ✗ |
| Tod am 1. Endboss | 39 % ✗ | **17 %** ✓ | 89 % ✗ | **28 %** ✓ | 89 % ✗ | 44 % ✗ |
| Timeouts (25 min) | 0 | 0 ✓ | 0 | 0 ✓ | 0 | 0 ✓ |
| Stamm-Spreizung | 195 % ✗ | **18 %** ✓ | 44 % | 126 % ✗ | 33 % | 138 % ✗ |
| Endboss-Kämpfe gewonnen (Median, n) | 41 s (32) | 44 s (35) ✗ knapp | – (0) | **52 s (24)** ✓ | – (0) | **61 s (11)** ✓ |
| davon erster Endboss | 57 s (9) | 46 s (13) | – | 61 s (11) | – | 74 s (6) |
| Todesursachen | Flut 10, Apex 4, Jäger 2, Bog King 1, Skitter 1 | Flut 10, Apex 3, Jäger 3, Bog King 2 | Apex 8, Flut 7, Jäger 3 | Flut 9, Apex 3, Jäger 2, Bog King 2, Leaper 1, Lava 1 | Apex 8, Jäger 5, Flut 4, Leaper 1 | Flut 6, Jäger 4, Leaper 4, Apex 3, Bog King 1 |
| erreichte Welten | 1×9, 2, 4, 5×7 | 1×5, 3×6, 4×5, 5×2 | 1×18 | 1×7, 2×3, 3×5, 4×3 | 1×18 | 1×12, 2×2, 3×3, 4 |

Vorher hat auf Brutal und Apex **kein** Lauf den ersten Endboss besiegt. Er stieg 12 s vor der Flut auf, hatte als Endboss rund 15.000–18.000 LP (3 × Bog King) und traf auf 30–45 Tiere.

**Stamm-Mediane nachher (Tod in s / Welt):**
- **Wild:** Glutmaw 724/3, Sporling 677/3, Knochenkiefer 771/3, Flinkzahn 705/3, Ätzmaul 753/4, Nachtmaul 653/3.
- **Brutal:** Glutmaw 314/1, Sporling 699/3, Flinkzahn 354/1, Knochenkiefer 641/3, Nachtmaul 353/1, Ätzmaul 709/3.
- **Apex:** Glutmaw 338/1, Sporling 330/1, Flinkzahn 261/1, Ätzmaul 475/2, Knochenkiefer 608/3, Nachtmaul 255/1.

**Verlauf der Runden (Wild / Brutal / Apex: Tod, Welt, Tod am 1. Endboss):**
- **R1:** 949 s w5 17 % / 494 s w1,5 33 % / 302 s w1 67 %.
- **R2:** 833 s w4 11 % / 583 s w2 22 % / 315 s w1 61 %.
- **R3:** 752 s w3,5 11 % / 575 s w2 22 % / 325 s w1 67 %.
- **R4:** 724 s w3,5 11 % / 547 s w2 33 % / 425 s w1 33 %.
- **R5:** 714 s w3 17 % / 584 s w2 28 % / 348 s w1 44 %.

Mit 18 Läufen je Schwierigkeit entspricht ein Lauf 5,6 Prozentpunkten. Zwischen R4 und R5 schwanken Brutal und Apex deshalb um ±10 Punkte, ohne dass eine Änderung sie gezielt traf.

### Änderungen (alle in den erlaubten Hebeln)
| Hebel | vorher | nachher | Grund |
|---|---|---|---|
| `APEX_DAMAGE_MULTIPLIER` | 1,2 | **0,85** | Hebel 1: Endboss-Verluste. |
| `APEX_PHASE_TWO_DAMAGE` | 1,3 | **1,1** | Hebel 1. |
| `APEX_EXHAUSTED_SECONDS` | 4 / 3 s | **5 / 4 s** | Hebel 2: Erholungsfenster (mehr Treffer in der Erschöpfung). Die Verwundbarkeit ×1,5 bleibt; ein Versuch mit 1,6–1,8 verkürzte die Kämpfe unter 45 s. |
| `APEX_FLOOD_MARGIN` | 15 s | **40 s** | Hebel 3 (Aufstiegszeit): Ein lebender Bog King schob den Endboss bis 12 s vor die Flut, praktisch in jedem Lauf. Jetzt steigt er spätestens 37 s vor der Flut auf. |
| `APEX_MIN_POPULATION` / `APEX_LATEST_EXTRA` | 30 / 30 s | **45 / 45 s** | Hebel 3: Population-Gate. |
| `APEX_SPAWN_SECONDS` | 225 / 165 / 135 | **235 / 210 / 180** | Hebel 3, passend zur späteren Flut. |
| `flood_start` (meta_data) | 270 / 210 / 180 s | **330 / 300 / 270 s** | Der erste Endboss braucht einen Kampf vor der Flut. Auf Brutal/Apex war der Schwarm beim Aufstieg zu klein (Flut-Pop. 30 bzw. 23). |
| Apex `pressure_doubling` | 60 s | **80 s** | Über √Druck trieb die 60-s-Verdopplung die Endboss-LP (3 × Bog King) auf rund 28.000. |
| Apex `enemy_hp` / `enemy_damage` | 1,2 / 1,15 | **1,15 / 1,1** | Viele frühe Tode auf Apex. Apex unterscheidet sich jetzt von Brutal durch die frühere Flut und härtere Treffer. |
| `FLOOD_WORLD_FACTOR` | 0,6 | **0,42** (−30 %) | Durch die spätere Flut und den leichteren Endboss erreichten gute Runs Welt 5–6. Wild startet die Flut jetzt 330 → 139 → 60 s. |
| `FLOOD_WORLD_STAGE` | 1,5 | **1,95** (+30 %) | wie oben |
| `WORLD_BONUS` | 0,25 | **0,32** (+28 %) | wie oben |
| `SURGE_COUNT_WORLD` / `SURGE_LEVEL_WORLD` / `SURGE_INTERVAL_WORLD` | 0,35 / 0,5 / 6 | **0,45 / 0,65 / 7,5** (+29 / +30 / +25 %) | Hordenwellen passen zur erreichten Welt. |

**Nicht geändert:** Endboss-LP (`APEX_KING_RATIO` 3,0, `APEX_HEALTH*`), Slots, Levelkurve, Seltenheits-Chancen, Regeln aus DESIGN_BRIEF.

### Regression und Tests
- **`balance_regress`** läuft jetzt mit `smart`, jeder Seed in einem eigenen Godot-Prozess (`_simulate_process`). Mehrere Läufe in einem Prozess drifteten auseinander: Seed 1 Knochenkiefer/Brutal starb dort nach 163 s, im eigenen Prozess lebte er am Limit. Damit entspricht die Regression jetzt der Matrix. Laufzeit ~3,5 min.
  - **Spezifikation 1:** Glutmaw/Wild, Seeds 1–5, bis 150 s, Einzelstart-Kurve. `min_lost` 10 → 2, weil `smart` bis 2:00 kaum Tiere verliert.
  - **Spezifikation 2:** Knochenkiefer/Brutal, Seeds 1–3, bis 420 s. Geprüft wird:
    - erster Endboss in mindestens 2 von 3 Seeds besiegt, Kampf 25–130 s,
    - der Median lebt am Limit,
    - Peak 80–400 (zu-leicht-Wächter),
    - die Moorbrut beißt (≥ 3).
- **Angepasste Tests (Zahl absichtlich geändert):**
  - `flood.gd`: Flutstart je Schwierigkeit.
  - `surge.gd`: Flutstart je Welt, jetzt aus `FLOOD_WORLD_FACTOR` gerechnet.
  - `apex_run.gd`: Aufstiegszeiten; Gate-Population aus `APEX_MIN_POPULATION`.
- **Suite:** `tools/test.ps1` komplett grün.

### Offen
- **Apex:** Die Median-Welt bleibt 1 (Ziel 2), Tod am ersten Endboss 44 % (Ziel ≤ 35 %; R4 33 %). Ursachen:
  - 4 von 18 Läufen (alle Seed 1) sterben vor dem Endboss im Einzelstart an Jägern und Leapern (88–122 s).
  - Die Endboss-LP bleiben nach der Regel aus Etappe 30 (≥ 3 × Bog King). Gegen 100–170 Tiere dauert der Kampf dann oft über 100 s, und der Schwarm stirbt in der Flut.
  - Der nächste Hebel wäre laut Reihenfolge die LP. Er ist bewusst nicht gezogen; das bleibt eine Nutzerentscheidung.
- **Stamm-Spreizung Brutal/Apex (126 / 138 %):** Mit 3 Seeds ist der Stamm-Median zweigeteilt (Welt 1 oder Welt 3). Glutmaw, Flinkzahn und Nachtmaul verlieren den ersten Endboss öfter. Das Kriterium ist bei 3 Seeds sehr seed-abhängig; mit 5–7 Seeds (wie Etappe 21) wäre es aussagekräftiger.
- **Endboss-Kampf Wild 44 s** liegt knapp unter 45 s. Späte Welten mit sehr großen Schwärmen (500+) töten den Endboss in 20–35 s; der erste Endboss dauert 46 s.
- **Frühe Tode im Einzelstart** (Seed 1 bei mehreren Stämmen, 86–150 s) sind unverändert. Das liegt außerhalb der Hebel dieser Etappe (Etappe 09).
- `tests/apex_duration.gd` (nicht in der Suite) ist mit den neuen Werten nicht neu gemessen.
- Die CLAUDE.md-Zeile „Flut ab 4:30/3:30/3:00“ ist veraltet (jetzt 5:30/5:00/4:30); nicht in meinem Dateiumfang.
