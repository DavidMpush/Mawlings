# Etappe 17d – Stammes-Fähigkeiten

Konzept und Werte: `stages/BACKLOG.md` Punkt 3b2 (Nutzer bestätigt 28.09.2026). Genau eine aktive Fähigkeit pro Stamm, eigener runder Knopf schräg über Rally, Cooldown 20–40 s als Ring, kein Zielen (Laufrichtung, stehend die letzte). Klar getrennt von Power-ups (passiv, vom Mini-Boss).

## Abnahmekriterien
1. `scripts/abilities.gd`: sechs Fähigkeiten, Cooldowns, Wirkung über eine kleine Host-Schnittstelle (Welt, Schwarm, Gegner), Relikt-Hooks.
2. Knopf mit Cooldown-Ring in `scripts/ui/hud_controls.gd`, Eingabe in `scripts/touch_controls.gd` (schräg über Rally, Touch ≥ 96 px, Q/Shift).
3. Eigene Farben Glut/Orange, nie Gefahren-Pink; Effekte über `vfx_sprites.gd` und den Telegraph-/Kit-Stil.
4. `tests/abilities.gd` in `tools/test.ps1`; Captures jeder Fähigkeit und des Knopfs, selbst angesehen.
5. Anbindung an HuntWorld, Schwarm, Bot und Balance erst nach Freigabe (17b/17c läuft).

## Ergebnis Schicht 1 (eigene Dateien, 28.09.2026)

### Fähigkeiten (`scripts/abilities.gd`)
| Stamm | Fähigkeit | Wirkung | Cooldown |
|---|---|---|---|
| Glutmaw | Glutsprung | 8 m in 0,35 s nach vorn (Wände beenden den Sprung), beißt alles in 2,2 m um die Bahn (30 × Skalierung) und die Brut, unverwundbar im Sprung + 0,4 s | 25 s |
| Sporling | Sporenbombe | Wolke 6,5 m am Schwarm, 5 s: Gegner ×0,45 Tempo, Gift 12/s, Brut mit | 30 s |
| Knochenkiefer | Panzerstoß | Schockwelle 7 m: 15 Schaden, leichte Gegner fliegen bis 4 m zurück (Bosse stehen), 2 s Verluste ×0,4 | 30 s |
| Flinkzahn | Hetzjagd | 4 s Tempo ×1,7, Schwarm als Linie | 20 s |
| Ätzmaul | Säureschwall | Kegel 9 m / ±29° nach vorn 25 Schaden, drei Pfützen (1,8 m, 10/s, 5 s) auf der Achse | 30 s |
| Nachtmaul | Schattenschleier | 3 s: Warnflächen verfehlen, Gegner laufen zu einem Köder 6 m hinter dem Schwarm | 40 s |

- **Host-Schnittstelle** (alle optional): `ability_swarm_position`, `ability_set_swarm_position`, `ability_targets`, `ability_brood`, `ability_arena`, `ability_damage_scale`.
- **Was der Run beachten muss** (Abfragen für die Anbindung): `damage_taken_multiplier()`, `invulnerable()`, `speed_multiplier()`, `line_formation()`, `warnings_miss()`, `decoy_position()`. Aufrufreihenfolge: nach `attack_forms.step()` (setzt `slow_factor` zurück), vor den Gegnern.
- **Zeit:** `step(delta, bewegung)` zählt Cooldown und Effekte; ohne Schritt (Pause, Auswahl, Migration) steht alles.
- **Relikt-Hooks:** `apply_relic(id)` bzw. `set_modifier(key, value)` mit `cooldown`, `duration`, `radius`, `power`, `fire_trail`. Vorbereitete Einträge: `glutkern` (−20 % Cooldown), `feuerspur` (Glutsprung hinterlässt 3 s brennenden Boden), `sporenhall` (+40 % Dauer), `weiter_schlund` (+25 % Radius). Die Relikte selbst trägt die Anbindungsrunde in `arsenal.gd` ein.
- **Optik:** eigene Flächen (Wolke, Pfützen, Feuerspur) als Fläche im neuen Palettenstil `own` (Glut, warmer dunkler Rand; `telegraph_style.build_hazard(r, -1, "own")`), Ringe in Glut, Sprites aus `vfx_sprites.gd` (shock, bite, spore, acid).

### Knopf und Eingabe
- `touch_controls.gd`: `ability_state` (von `abilities.sync_hud(hud)`), Signal `ability_requested`, Zähler `ability_requests`, `_ability_center()` = Rally + (178, −62), Touch-Radius 70 px (140 px), Tasten **Q/Shift**. Der Knopf hat Vorrang vor Rally in seinem Kreis; ohne Zustand gibt es keinen Knopf.
- `hud_controls.gd`: runder Kit-Knopf (58 px), bereit in Glut mit sanftem Glühen und Stammeskopf-Icon, im Cooldown neutral mit Sekunden und sich füllendem Glut-Ring, aktiver Effekt als heller Ring, Name darunter.

### Tests
`tests/abilities.gd` (in `tools/test.ps1`) grün: Stamm → Fähigkeit, Cooldown 20–40 s, Ring-Anteil, Pause friert (kein Schritt), Relikt-Hooks, jede Wirkung (Sprung: Bahnbiss, Unverwundbarkeit, Wand, Feuerspur in Glut; Wolke: Verlangsamung und Gift nur innen, 5 s; Stoß: Rückstoß, Bosse fest, −60 %; Hetzjagd ×1,7 und Linie, 4 s; Säure: Kegel nur vorn, Pfützen brennen; Schleier: Köder, Warnflächen verfehlen, 3 s), Knopf-Treffer, Rally bleibt Rally, Q/Shift.

### Bilder (`tests/capture_abilities.gd`)
`preview_ability_<id>.png` (sechs), `preview_ability_button_ready.png`, `_button_cooldown.png`, `preview_ability_sheet.png`.
Iterationen: (1) Sporenwolke mit weinrotem Rand (Gefahrenkontur) und ohne Sporen nach dem Start. (2) Eigener, warmer Rand für Glut-Flächen, die Wolke puffert fortlaufend.

**Ehrliche Bewertung:** Panzerstoß und Sprung lesen sich stark, der Knopf ist klar (Kopf-Icon bereit, Sekunden im Cooldown). Die Sporen- und Säure-Sprites sind die gelieferten Violett-/Grün-Bilder – sie weichen von „eigen = Glut“ ab; das Wolken-/Pfützen-Feld ist Glut. Hetzjagd zeigt ohne Schwarm-Anbindung nur Ringe (die Linienformation kommt mit `swarm.gd`). Der Knopf ist mit 58 px eher klein neben Rally; im Handtest prüfen.

### Offen für die Anbindungsrunde
HuntWorld: Host-Methoden, `step()` im Lauf, `ability_requested`/Q, Verlustfaktor, Unverwundbarkeit, Köder und `warnings_miss` in `_resolve_area_hit`, Tempo in `swarm.speed_multiplier`, Linienformation in `swarm.gd`, Relikt-Einträge, Bot-Nutzung (vor Warnflächen, bei Einkesselung), Balance, Sounds.

## Ergebnis Anbindung (28.09.2026, nach 17b/17c)

### HuntWorld (`scripts/hunt_world.gd`)
- `abilities` wird mit der Horde erzeugt (`_create_abilities`, Stamm aus `config.strain_id`), bei Reset neu. HuntWorld ist der Host (`ability_*`-Methoden; Ziele ohne Beute, Brut = Moorbrut + Sandmaden, Schaden-Skalierung wie die Angriffsformen).
- `_step_abilities()` läuft direkt nach `attack_forms.step()`: Relikte → Modifikatoren, Knopf/Q/Shift (`request_ability`, wirkt im nächsten Schritt in Laufrichtung), Schritt, Tempo ×1,7, Linienformation, Sprunghöhe, HUD-Zustand.
- `_apply_hit`: Glutsprung = keine Verluste (auch keine Anführer-LP); Panzerstoß = Tier-Verluste und Anführer-LP ×0,4.
- `_resolve_area_hit`: unter dem Schattenschleier verfehlen alle angekündigten Flächen (Gegner, Bog King, Apex, Ausbrüche). Jäger, Skitter, Leaper, Bog King und Apex zielen dann auf den Köder (`_aim_point`).
- Pause/Auswahl/Migration: kein Schritt → Cooldown steht. Migration beendet laufende Effekte (Cooldown bleibt), Reset baut die Fähigkeit neu.
- Sounds aus vorhandenen IDs: Glutsprung `leaper_windup` + `stomp` bei der Landung, Sporenbombe `mutate`, Panzerstoß `quake`, Hetzjagd `rally`, Säureschwall `split`, Schattenschleier `migration_whoosh`.
- Nebenbei (Kodex): `run_stats()` liefert `relics` und `powerups_taken`.

### Schwarm (`scripts/swarm.gd`)
- `speed_multiplier` wie bisher (HuntWorld multipliziert die Hetzjagd hinein).
- `line_formation`/`line_direction`: die Tiere ordnen sich weich (Blend) in einer Doppelreihe hinter dem Anführer.
- `leap_height`: alle Tiere heben im Sprungbogen ab (bis 1,6 m), der Schatten bleibt am Boden.

### Relikte (`progression/arsenal.gd`)
Glutkern (selten, −20 % Abklingzeit), Feuerspur (selten, 3 s brennender Boden; beim Glutsprung als Spur, sonst am Schwarm), Sporenhall (selten, +40 % Dauer), Weiter Schlund (episch, +25 % Reichweite). Icons vorerst `haste`/`glutdruese`/`sporenwolke`/`reach`; eigene Icons (auch sechs Fähigkeits-Icons) in `stages/UI_ASSET_REQUESTS.md` angefragt.

### Onboarding
Tipp „Stammesfähigkeit bereit! …“ ab 20 s, wenn eine Bedrohung nah ist und die Fähigkeit noch nie benutzt wurde; Zeiger auf den Knopf (`onboarding.gd`, `hud_controls.gd`).

### Bot (`tests/balance_sim.gd`)
Vor Warnflächen: Glutsprung, Hetzjagd, Panzerstoß, Schattenschleier. Eingekesselt (≥ 3 Gegner in 6 m oder Moorbrut-Ring): Sporenbombe, Säureschwall, Panzerstoß. `BALANCE_NOABILITY=1` schaltet das für A/B-Läufe ab; die BALANCE-Zeile nennt `ability=<id>:<Einsätze>`.

### Balance (3 Stämme × 5 Seeds, greedy, `tools/balance.ps1`)
| | Wild | Brutal | Apex | Spreizung W/B/A |
|---|---|---|---|---|
| ohne Fähigkeit (Stand 6a51e87) | 566 s | 406 s | 212 s | 1/68/32 % |
| mit Fähigkeit | 603 s | 440 s | 244 s | 19/112/20 % |

- Die Fähigkeit verlängert die Läufe um etwa 7–15 %. Wild und Brutal liegen **schon ohne** Fähigkeit über dem Ziel (390–510 / 300–390 s); Apex bleibt im Ziel. Die Streuung (vor allem Brutal) ist mit 5 Seeds stark vom Zufall getrieben (z. B. Knochenkiefer 253 → 578 s, Glutmaw 424 → 273 s).
- Fähigkeitswerte habe ich nicht verändert: die Abweichung stammt aus dem Grundstand, die große Balance-Runde (Waffen-Skalierung) folgt. Matrix über alle sechs Stämme (3 Seeds): Nachtmaul klar am schwächsten (Wild 200 s), Sporling/Ätzmaul am stärksten – Stammeswerte, nicht die Fähigkeit.

### Tests
- `tests/abilities.gd` (Schicht) und neu `tests/ability_run.gd` (echter Run: Stamm, Knopf, Q, Cooldown, Sprung ohne Verluste, Panzerstoß −60 % Tiere und LP, Hetzjagd ×1,7 + Linie, Schleier verfehlt und Köder, Pause/Reset/Migration, Relikt) in `tools/test.ps1`.

### Bilder
`tests/capture_ability_run.gd` → `preview_ability_run_<id>.png` und `_sheet.png` (echter Run, Jäger in der Nähe). Der Sprung zeigt den abgehobenen Schwarm mit Schatten, die Hetzjagd die gestreckte Doppelreihe, der Panzerstoß die große Glut-Schockwelle, Wolke und Pfützen liegen als Glut-Flächen.
- **Volle Suite `tools/test.ps1`: ALL PASS** (51 Einträge inkl. `balance_regress` und `endless_playthrough`).
- Angepasst: `arsenal` (25 Relikte, Seltenheiten 6/11/5/3).
- Nebenfund behoben: In der Wüste (Seed 31337) konnte ein Gold-Kokon-Platz als kleine, abgeschnittene Tasche zugeschüttet werden (`_join_open` füllte Taschen < 40 Zellen). Taschen mit einem Ort werden jetzt immer angebunden statt gefüllt (`map_explore.gd`); `map_layout` druckt bei einem nicht offenen Platz Wandabstand und Hindernisse.
- Fehler behoben: `abilities.gd` hielt verlangsamte, inzwischen freigegebene Gegner typisiert fest (Skriptfehler im Balance-Lauf).

## Politur (28.09.2026, nach Etappe 22b)
- **Eigene Effekte in Glut:** Die Fähigkeiten haben ihren eigenen Sprite-Pool (`"Ability VFX"`, `VFX_SPRITES.ABILITY_POOL`). Dort bekommen Säure und Sporen den Shader-Parameter `ember = 1` (`shaders/vfx_sprite.gdshader`): Hell/Dunkel des Nutzer-Sprites wird auf die Glut-Rampe des Schwarms gelegt (Dunkelrot → Orange → warmes Weiß), keine neuen Texturen. Sporenbombe, Säureschwall und die Sporenwolken des Schattenschleiers lesen sich so als eigene Kraft statt als Gegnergift. Die Waffen (Säurespucker, Sporenwolke) behalten Violett/Grün; die Schockwelle bleibt ungetönt. Prüfung in `tests/vfx.gd` (`_test_ember_pool`).
- **Fähigkeitsknopf größer:** Radius 58 → 68 px, Touch-Radius 70 → 80 px, Versatz zur Rally (178, −62) → (190, −68) (`touch_controls.gd`, `hud_controls.gd`). Abstand zum Rally-Knopf ~17 px inklusive Cooldown-Ring. Das Hinweisbanner (und damit das Tipp-Panel darüber) rückt bei sichtbarer Fähigkeit über den Knopf (`_banner_top`), vorher berührte es den Ring oben rechts.
- Bilder: `previews/preview_ability_run_sheet.png` und `preview_ability_run_<id>.png`. Tests `abilities`, `ability_run`, `vfx`, `smoke`, `hunt_flow`, `survival`, `boss` grün.
