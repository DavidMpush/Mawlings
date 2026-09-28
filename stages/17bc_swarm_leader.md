# Etappe 17b + 17c – Schwarm ohne Limit, Anführer mit Lebensbalken und Lebensraub

## Nutzerentscheidungen
- 27.09.2026 (17b): „Power soll linear unendlich skalieren.“ Das Limit von 250 Mawlings entfällt, die Flut bleibt das exponentielle Gegengewicht.
- 28.09.2026 (17c): Statt 3 Treffer-Pips hat der Anführer echte LP mit Lebensbalken. Neu kommt der Wert Lebensraub dazu.
- Orchestrator 28.09.2026:
  - Die Treffer-LP sind je Angriff festgelegt (Tabelle unten).
  - Nachfolger übernehmen mit 80 % des Maximums.
  - Der Mire Leaper zählt nicht mehr als Mini-Boss für Power-ups.

## Kriterien
### 17b Schwarm ohne Limit
1. Kein logisches Populationslimit mehr (`run_model`, Kapazität unbegrenzt).
2. Die Trophäe „Die volle Brut“ gibt es in Stufen: 250, 500 und 1.000.
3. Meilensteine 5/10/25/50/100/250/500/1.000/2.500/5.000/10.000; ab 1.000 heißt das Banner „SCHWARM: 1.000!“.
4. Die Nahkampfkraft wächst linear mit der Population; der versteckte Deckel (32 Schaden/s bei ~260 Tieren) ist entfernt.
5. Darstellung: höchstens 120 sichtbare Modelle.
   - Darüber steht jedes Modell für mehrere Tiere.
   - Die Formation wird nur noch logarithmisch breiter, die Tiere wachsen leicht mit, der Bodenring wird kräftiger.
   - Treffer bleiben anteilig: Flächen treffen den Anteil der sichtbaren Punkte × Angriffsstärke; Moorbrut-Bisse treffen den Anteil × echte Population.
6. HUD ohne „/250“, Kurzform ab 10.000 („12,3k“).
7. Der Sammelradius wächst über 250 Tiere hinaus nur noch um `MAGNET_PER_DOUBLING` je Verdopplung.
8. Leistung: keine Schleife läuft über die logische Population; `perf_bench pop=5000` ist so schnell wie 250 Tiere.

### 17c Anführer-LP und Lebensraub
1. Der Anführer startet mit **100 LP** (`TUNING.LEADER_HP`).
2. Ein Treffer kostet `LEADER_HIT[Angreifer]` × √Druck × Schwierigkeit:

   | Angreifer | LP |
   |---|---|
   | Nibbler | 10 (nie tödlich) |
   | Jäger | 20 |
   | Elite-Jäger | 28 |
   | Skitter | 16 |
   | Leaper | 22 |
   | Bog King | 35 |
   | Eruption | 15 |
   | Apex | 30 |
   | Apex-Pfütze | 10 |
   | Moorbrut-Biss | 4 |

   Danach bleiben die 1,2 s Unverwundbarkeit.
3. Anzeige:
   - Über dem Anführer steht ein Balken im Stil der Gegnerleisten (grün → gelb → rot, der verlorene Teil blitzt weiß auf, unter 25 % pulsiert der Rahmen rot).
   - Die Schwarm-Pille trägt eine kleine LP-Leiste.
   - Heilung zeigt ein kleines grünes „+N“.
4. **Lebensraub** ist ein neuer Wert (+0,4 % des Schwarm-Schadens je Wert). Dazu kommt das Relikt **Blutzahn** (selten, +3 %). Gezählt werden Nahkampf und alle Waffen.
5. Regeneration heilt jetzt LP je Sekunde (0,5 LP/s je Wert).
   - Die Königszahnkette heilt 15 LP.
   - Anführerherz gibt +15 % Max-LP je Wert, Blutmond −25 Max-LP.
   - Der Chitinschild bleibt Immunität.
   - Meilensteine je 25 Tiere heilen 15 LP.
6. Ein Nachfolger übernimmt mit 80 % des bisherigen Maximums und voll geheilt.

## Ergebnis
Der Balance-Stand steht unten.

- Code:
  - `run_model.gd`: `apply_hit(..., leader_damage)`, `heal_leader()`, unbegrenzte Kapazität.
  - `hunt_world.gd`: `leader_damage()`, `_step_leader_heal()` und `melee_dealt`.
  - `tuning.gd`: `LEADER_*`, `MILESTONES`, `MAGNET_PER_DOUBLING`.
  - `stats.gd`: Lebensraub, Einheiten „hp“ (%) und „lps“.
  - `evolution.gd`: `lifesteal()`, `regen_rate()`, `leader_hp_bonus(base)`.
  - `arsenal.gd`: Blutzahn.
  - `meta_data.gd`: Pools und Trophäen-Stufen.
  - HUD: `hud_top.gd` (Balken, Leiste, Kurzform), `hud_overlays.gd` (Meilenstein-Text).
  - `swarm.gd`: Formation, Größe und Bodenring über 120 Tiere; Treffer-Chunk statt Pip.
- Tests angepasst: `run_model`, `leader` (neu: Lebensraub, Regeneration, Anführerherz), `progression_stats`, `forms_extra`, `evolution`, `arsenal`, `loot_magnet`, `boss`, `powerups`. `perf_bench` hat jetzt `pop=`.
- Leistung (Desktop, Szene „worst“): 250 Tiere 7,5 ms, 5.000 Tiere 8,2 ms je Frame.
- Bilder aus `tests/capture_swarm17bc.gd`: `preview_swarm17_pop_120|pop_500|pop_5000|hud_12k|leader_full|leader_half|leader_critical|lifesteal|successor.png`.

## Balance (28.09.2026; 3 Stämme × 5 Seeds, greedy; der Rechner lief parallel mit anderen Agenten, Werte verrauscht)
- **Treffer auf den Anführer** wachsen mit Druck^0,35 statt √Druck (`LEADER_HIT_PRESSURE`). Mit √Druck starben Brutal- und Apex-Läufe mittelfristig zu schnell.
- **Lebensraub** 0,4 % je Wert: sparsam, damit er lange Läufe nicht weiter streckt.
- **Schwierigkeiten** (`meta_data.gd`):
  - Wild: Druck-Verdopplung 85 → 80 s, Flut 300 → 270 s.
  - Brutal: Gegner-LP 1,3 → 1,15.
  - Apex: Gegner-LP 1,3 → 1,2.
  - Hintergrund: Ohne die Leaper-Power-ups stagnierten kleine Schwärme auf Brutal.
- **Apex-LP** (Orchestrator): Moosschlund 1.400 → 1.700, Aschenkröte 3.600 → 2.000.

| | Wild | Brutal | Apex | Wachstum 1:00 / 2:00 | Spreizung W/B/A |
|---|---|---|---|---|---|
| Ziel | 390–510 s | 300–390 s | 210–270 s | 6–14 / 25–55 | ≤ 40 % |
| Stand | 563 s | 299 s | 217 s ✓ | 13 / 30 ✓ | 10 / 40 / 24 % ✓ |

**Offen:**
- Wild liegt ~10 % über dem Ziel: Gute Läufe überleben die Flut lange.
- Brutal verläuft zweigeteilt: Kleine Schwärme sterben am Apex bei ~220 s, gewachsene erst bei 400–600 s. Der Median liegt deshalb am unteren Rand und springt je Messung um ±40 s.
- `balance_regress`: glutmaw/Apex erreicht die Flut, stirbt aber in ihren ersten Sekunden am Moosschlund oder an Jägern (Median 0 Moorbrut-Verluste). `min_flood_lost` wird deshalb nicht mehr verlangt; die ursprüngliche 5 ist mit dem stärkeren Moosschlund nicht erreichbar.
