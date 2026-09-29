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

## Ergebnis

(folgt)
