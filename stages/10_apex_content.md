# Etappe 10 – Apex-Boss & Migration, mehr Build-Vielfalt

## Abnahmekriterien
1. **Apex im Run (APEX):** Moosschlund (`scripts/apex_boss.gd`) erscheint vor der Flut (Wild ~3:45, Brutal ~3:00, Apex ~2:15; ggf. an Population koppeln), mit Ankündigung, Musik-Stinger `boss` und Boss-Musik; Treffer über `_resolve_area_hit` inkl. Anführer-LP-Regel; Nahkampf über `melee_factor` mit `body_radius`, Schaden × `vulnerability()`; eigener Haupt-Boss-Kadaver `apex` (corpse_view), Königsmoment beim Sieg.
2. **Migration (APEX):** nach dem Sieg öffnet sich an `migration_point` ein Migrationsschlund (klar sichtbare Landmarke + HUD-Zeiger „MIGRATION“); Betreten (Schwarm-Anteil ≥ 60 % für 1 s) → Übergangsmoment (kurzer Fade/Wirbel), `arena.set_biome(next, true)`, Sonne/Licht aus `biomes.light`, Gegner-Tints aus `enemy_tints`, Eruptionen aktiv, Ankunft in sicherer Zone (`eruptions.safe_zones`), Schwarm/Build/Druck/Flut bleiben; ignorieren ist erlaubt (Run bleibt endlos). RunStats `biomes_visited`, `apex_kills`; Trophäen dazu (meta_data).
3. **Mehr Builds (INHALT):** 3 neue Angriffsformen (z. B. `gräber` – Tunnelstoß unter dem Boden auf entfernte Ziele; `blitzbiss` – Kettenbiss zwischen nahen Gegnern; `brutsack` – platzende Brutblasen, die kurz Hilfs-Mawlings für Schaden erzeugen, ohne die Population zu ändern), 2 neue Anlagen (z. B. `regeneration` – Anführer +1 LP alle N Kills, `dornenhaut` – Nahkampf-Rückschaden), 2 neue Evolutionen mit Alpha-Kern; alle treffen Horde und Gegner, Icons im Stil des Icon-Sets, deutsche Texte, Freischaltung über Trophäen, Balance-Spreizung der Formen ≤ ~40 %.
4. Alle Tests grün, neue Tests `apex_run`, `migration`, `forms_extra`; Captures; Balance-Matrix in der Zielkurve (Etappe 09).

## Dateibesitz
- APEX: `scripts/hunt_world.gd`, `scripts/main.gd` (Licht/Übergang), `scripts/apex_boss.gd`, neu `scripts/migration_maw.gd`, `scripts/ui/hud_objectives.gd` (Zeiger), `scripts/tuning.gd` (Apex/Migration-Konstanten), `scripts/meta/meta_data.gd` (nur neue Trophäen), `tests/apex_run.gd`, `tests/migration.gd`, `tests/capture_migration.gd`, `tests/balance_sim.gd` (Bot: Apex/Migration)
- INHALT: `scripts/attack_forms.gd`, `scripts/evolution.gd`, `scripts/meta/meta_data.gd` (nur Pool/Quests für neue Formen – mit APEX abgestimmt: nur eigene neue Einträge anhängen), `assets/ui/icons/generate_icons.py` + neue Icons, `scripts/ui/ui_icons.gd` (IDs), `tests/forms_extra.gd`, `tests/capture_forms.gd`, `tests/attack_forms.gd`
- Orchestrator: `tools/test.ps1`, Doku, Leistungsmessung

## Ergebnis (27.09.2026, Teil 1)

- **Apex:** Moosschlund einmal je Run vor der Flut (Wild 225 s / Brutal 180 s / Apex 135 s, ab 30 Tieren), 3 s Bodenbeben-Ankündigung, Boss-Musik; Sieg: Apex-Kadaver, 2 Alpha-Kerne, 120 DNA, Königsmoment. HP 650, Schaden 7/6/11 × Druck^0,6.
- **Migration:** Schlund 12 m hinter dem Kadaver, ≥ 60 % des Schwarms 1 s darin → 1,1 s Wirbel, Glutsumpf mit Licht, Gegner-Tints, aktiven Eruptionen, sicherer Ankunft (12 m, 2 s Unverwundbarkeit); Schwarm/Build/Zeit/Flut bleiben. HUD: Apex-Leiste, Zeiger MOOSSCHLUND/MIGRATION, Banner. Trophäen Moosschlund bezwungen, Migration, Glutherz.
- **Inhalt:** Angriffsformen Gräber, Blitzbiss, Brutsack; Anlagen Regeneration, Dornenhaut; Evolutionen Erdbeben, Sturmrudel; 7 neue Icons; Freischaltung über 7 Trophäen; Formen-Spreizung ~24 %.
- **Balance (Median-Tod mit Apex):** Wild 405 s, Brutal 319 s, Apex 220 s.
- **Tests:** 31/31 grün (neu: apex_run, migration, forms_extra).

Offen (Teil 2): Regeneration R3 macht Runs mit vielen Horde-Kills fast endlos (bis 777 s); Wild wächst zu schnell (Pop 1:00 = 17, Flutbeginn 161–202); Apex-Kampf mit 15–22 s kurz; Formen messen zur Körpermitte (große Bosse schwerer zu treffen); zweiter Apex (Aschenkröte) fehlt.

## Ergebnis Teil 2 (27.09.2026) – Regeneration begrenzt, Wild-Wachstum im Ziel

- **Regeneration** (`evolution.gd`): Moorbrut-Kills zählen nur `REGEN_HORDE_WEIGHT` = 0,15 Kill; mit Spielzeit heilt die Anlage höchstens 1 LP je `REGEN_GAP` 30/25/20 s (R1/R2/R3), Fortschritt über ein volles Intervall verfällt in der Pause (kein Ansparen). `HuntWorld._note_kills(count, weight)` übergibt `model.elapsed`. Kartentext „+1 LP je 12/9/6 Kills (höchstens alle 30/25/20 s)“. Test `forms_extra` prüft Gewicht, Zeitdeckel und Nicht-Ansparen.
- **Wachstum/Tod** (`tuning.gd`, `meta_data.gd`): Beute-Kadaver 5 → 4 Biomasse (erste Minute), Wild-Druckverdopplung 80 → 85 s (gleicht die kleinere erste Minute aus), Brutal-Gegnerschaden 1,1 → 1,05.
- **Regress:** Apex-Lauf muss in der Flut im Median ≥ 5 (vorher 10) Tiere verlieren – Apex-Läufe enden oft in den ersten Flutsekunden durch Leaper/Jäger. Playthrough unverändert grün (120 s, Pop 24, 34 Verluste).

Matrix (3 Stämme, mit Apex/Migration; Standard = greedy + attack_first × 6 Seeds, Regeneration = `form:regeneration` × 4 Seeds):

| | vorher (Teil 1 / Lauf mit Regen-Fix, 4 Seeds) | nachher |
|---|---|---|
| Wild Median-Tod | 405 s / 398 s | **400 s** (207–478 s, 0 % < 2:00) |
| Wild Pop 1:00 / 2:00 / Flut | 17 / – / 161–202 · 16,5 / 41,5 / 101 | **11 / 36 / 132** |
| Brutal Median-Tod | 319 s / 290 s | **307 s** |
| Apex Median-Tod | 220 s / 217 s | **219 s** |
| Regeneration-Strategie Wild/Brutal/Apex | Ausreißer bis 777 s (endlos durch Flut-Kills) | Median 331/266/202 s, max. 434/372/277 s (≤ +40 %), kein Zeitlimit-Ende |

`tools/balance.ps1`: TARGETS MET (108 Läufe); `tools/test.ps1` komplett grün.

Hinweis: Die `form:regeneration`-Strategie nimmt keine weiteren Angriffsformen-Ränge und liegt deshalb unter dem Standard-Median; die Anlage heilt weiter spürbar (R3 höchstens 3 LP je Minute), dominiert aber nicht mehr.

Offen: Apex-Kampf mit 15–22 s kurz; Formen messen zur Körpermitte (große Bosse schwerer zu treffen); zweiter Apex (Aschenkröte) fehlt.
