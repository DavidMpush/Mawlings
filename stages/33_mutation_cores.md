# Etappe 33 – Mutationskerne (Arcana)

Quelle: [IDEAS_VAMPIRE_SURVIVORS.md](IDEAS_VAMPIRE_SURVIVORS.md) Punkt 3. Der Nutzer hat die Entscheidungen an den Orchestrator übergeben (29.09.2026). Umsetzung nach der Balance-Runde (Etappe 32).

## Idee
Wenige, **regelverändernde** Karten, die dem Run eine Identität geben: nicht „+8 % Biss“, sondern „so spielt dein Schwarm anders“. Sie ergänzen Werte, Waffen und Relikte, ohne deren Plätze zu belegen.

## Entscheidungen
1. **Zeitpunkte:** 1 aus 3 zum **Run-Start** (vor dem ersten Schritt, statt eines leeren Moments) und nach **jedem Endboss-Sieg** (im Boss-Kokon-Moment, als eigene Wahl davor). Maximal 3 Kerne je Run (Start, nach Welt 1, nach Welt 2).
2. **Pool (Start 12 Kerne):** Jeder hat einen klaren Vorteil **und** einen spürbaren Preis:

   | Kern | Wirkung | Preis |
   |---|---|---|
   | Hungrige Brut | Zellteilung braucht 30 % weniger Biomasse | Tiere haben −25 % LP (mehr Verluste pro Treffer) |
   | Rudelgeist | Nahkampf +40 % | Waffen −20 % |
   | Arsenal-Kult | Waffen +30 % | Nahkampf −30 % |
   | Giftblut | Jeder Kritbiss hinterlässt eine Giftwolke (2 s) | Krit-Chance −5 % |
   | Magnetsturm-Herz | Magnet ×2, Lockruf alle 90 s | Tempo −8 % |
   | Königsjäger | Bosse und Elite +35 % Schaden | normale Gegner −10 % |
   | Wandernde Brut | Tempo +15 %, Glutsprung/Fähigkeit −25 % Abklingzeit | Rally-Bonus −50 % |
   | Panzerherz | Anführer +50 % LP, Treffer auf den Anführer −30 % | Heilung −50 % |
   | Flutfresser | Brut-Kills geben doppelte Kristalle | Flut beginnt 20 s früher |
   | Bernsteinblut | +50 % Bernstein, Kokons −20 % Preis | DNA −15 % |
   | Schwarmgedächtnis | Überspringen/Neu würfeln +2 | Level-Kurve +10 % |
   | Letzter Biss | Beim Tod des Anführers: Nachfolger mit 100 % statt 80 % | Anführer-Max-LP −20 % |

3. **Darstellung:** eigene Kartenform (runde „Kern“-Plakette, violett-goldener Rand, Seltenheit **immer legendär-gold**), Text in zwei Zeilen „+ …“ (grün) und „− …“ (rot). Im HUD eine kleine Kern-Leiste unter den Relikten, im Ergebnis bei „DEIN BUILD“.
4. **Siegel:** Kerne sind versiegelbar (eigene Gruppe im SIEGEL-Blatt).
5. **Meta:** Zu Beginn sind 6 Kerne freigeschaltet, die übrigen 6 über Trophäen (z. B. „Erreiche Welt 3“, „Besiege die Aschenkröte“). Kodex-Tab KERNE.
6. **Balance:** Kerne sollen sich etwa ausgleichen. Der Bot (`smart`) wählt nach Stamm und Build. Prüfung: Matrix mit jedem Start-Kern einzeln (Median-Tod ±20 % zum Lauf ohne Kern).

## Schnittstellen (Vorschlag)
- `scripts/progression/cores.gd`: Katalog `CORES := {id: {name, plus, minus, effects: {…}}}`.
- `evolution.cores: Array[String]`; `evolution.core_offers`; `evolution.choose_core(slot)`; die Wirkung läuft über die vorhandenen Multiplikatoren (`damage_multiplier`, `melee_multiplier`, `harvest_multiplier` …) und ein paar Hooks in `hunt_world` (Lockruf-Takt, Flutbeginn, Nachfolger-LP, Giftwolke).
- `mutation_screen` Modus „core“; RunConfig `sealed` enthält Kern-Ids; Profil speichert freigeschaltete Kerne.

## Ergebnis

(offen, Umsetzung nach Etappe 32)
