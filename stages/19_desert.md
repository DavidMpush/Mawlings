# Etappe 19 – Wüstenwelt „Dürrschlund“ mit Sandwurm

Nutzerwunsch (27.09.2026, `BACKLOG.md` Punkt 3c): Ein drittes Biom zwischen Verdant Maw und Glutsumpf. Dünen, Knochenfelder, Felsbögen, Sandstein-Klippen, Kakteen und Oasen; Endboss ist der **Sandwurm**, erst sein Schlund führt in den Glutsumpf. Neue Reihenfolge: **Verdant Maw → Dürrschlund → Glutsumpf** (→ Verdant, Schleife).

Die Etappe ist in zwei Phasen geteilt. Phase 1 liefert Modelle, Boss, Gegner, Kadaver und Biomdaten als eigenständige, getestete Bausteine; Phase 2 baut sie in Karte und Run ein.

## Phase 1 – Abnahmekriterien
1. Alle acht Nutzer-Originale reduziert (verschweißt), importiert, vom Android-Export ausgeschlossen.
2. `scripts/apex_sandworm.gd` mit der Apex-Schnittstelle von `apex_boss.gd`/`apex_toad.gd`: Graben (nur Sandspur, unverwundbar), Durchbruch (Warnring, senkrechter Ausbruch, Treffer pro Tier), Schwanzfeger (Kegel, halb aufgetaucht), verwundbar nur aufgetaucht, danach erschöpft (×1,6), Phase 2 ab 50 % (schneller, öfter, Sandmaden), Tod → Kadaver-Design.
3. `scripts/sandgrub.gd`: kleiner, schneller Beißer, Horde-Vertrag, eigenständig lauffähig.
4. Kadaver-Designs `apex_sandworm` und `sandgrub` (liegend; leer = Asch-Material).
5. Biom-Eintrag `duerrschlund` in `scripts/biomes.gd` (nur Daten, `ORDER` unverändert).
6. Tests `apex_sandworm`, `sandgrub` in `tools/test.ps1`; Capture `tests/capture_sandworm.gd`, mindestens zwei Bild-Iterationen.

## Phase 1 – Ergebnis (27.09.2026)

### Modelle
`tools/optimize_characters.py` (alle mit WELD): `sandwurm` → `characters/Sandwurm_game.glb` (8.000 Dreiecke, 241 KB), `sandgrub` → `characters/Sandgrub_game.glb` (1.200), `sandportal` → `props/SandPortal_game.glb` (3.000), `ribbones` → `RibBones_game` (2.500), `rockarch` → `RockArch_game` (2.500), `sandstone` → `SandstoneCliff_game` (2.000), `cactus` → `Cactus_game` (1.500), `skull` → `GiantSkull_game` (3.000). Alle Originale (je ~33–44 MB) stehen in `exclude_filter` von `export_presets.cfg`.
- **Sandportal = Durchbruch-Maul** (Referenzbild `02_sandworm_breakthrough_maw.png`: runder Zahnschlund in aufgebrochener Kruste). Im Spiel wird es der **Migrationsschlund der Wüste** (Phase 2); der Durchbruch des Bosses selbst nutzt den Wurm senkrecht (von oben sieht man dasselbe Rundmaul).
- Sandwurm: Kopf +Z, Schwanz steckt im mitmodellierten Sandhügel; das Loch (Drehpunkt) liegt bei roh z = −0,3. Sandstein-Klippe ist eine sehr flache Platte (0,17 × 1,1) – als Wand in Y gestreckt (Capture: ×2,2).

### Sandwurm (`scripts/apex_sandworm.gd`)
- **Schnittstelle** wie Moosschlund/Kröte (`step`, `take_damage`, `vulnerability`, `can_be_hit`, `contains`, `hit_fraction`, `resolved_power`, `attack_center`, `body_radius`, `body_distance`, `contains_body`, `melee_range`, `hud_message`, `restyle`, `refresh_pose`, `migration_ready/point`, Signale `defeated`, `phase_changed`); `State`-Enum mit gleichen Namen und Werten wie `apex_boss.State` (EXHAUSTED = goldener „Jetzt angreifen“-Zustand des HUD). `corpse_kind = "apex_sandworm"`, `DISPLAY_NAME = "Sandwurm"`.
- **Zusätzlich für die Integration:** Signal `grubs_released(center, count)` und `take_grubs()` (Warteschlange), `is_buried()`, `dive` (Abtauchen nach jedem Auftauchen, unverwundbar).
- **Graben (CHASE):** unter dem Sand, 5,2 / 6,8 m/s, umkreist den Schwarm in 8,5 m, solange die Abklingzeit läuft. Sichtbar nur als Furche aus flachen Sandhügeln (unbeleuchtet, dunklere Rinne, heller Kamm am Kopf) mit Staubwolken; `body_distance` = ∞, `vulnerability` = 0.
- **Durchbruch:** Ring 4,2 / 4,0 m (telegraph_style „boss“) unter dem Schwarm, 0,35 s Bewegung vorgehalten (max. 2,5 m); Warnzeit 1,6 / 1,4 s, in der die Spur in den Ring läuft; Verlust 12 × Druck, nur Tiere im Ring (`contains`). Danach steht der Wurm 0,6 s senkrecht mit gespreiztem Maul im Loch (verwundbar), Felsbrocken und Staub fliegen, dann kippt er seitlich (zur Kamera hin, nie auf den Schwarm) und liegt **erschöpft** 3,6 / 2,8 s mit offenem Maul und blauem Randlicht (×1,6).
- **Schwanzfeger:** taucht halb 6 m neben dem Schwarm auf (schräg aufgerichtet, verwundbar ×1,0), holt aus und fegt einen Kegel (telegraph_style „boss_cone“, Reichweite 12 / 14 m, halber Winkel 0,55 rad) durch den Schwarm; Warnzeit 1,35 / 1,2 s, Verlust 8. Ausweichen seitlich oder hinter den Wurm. Danach Abtauchen, keine Erschöpfung.
- **Phase 2** (≤ 50 % LP): 1,8 s Toben (senkrecht, unverwundbar, bricht eine laufende Warnung ohne Verlust ab), gibt 6 Sandmaden frei; danach Doppel-Durchbruch (zweiter Ring rastet erneut auf den Schwarm ein, je 4 Sandmaden am Loch), Erschöpfung erst nach der Kette; schneller, kürzere Pausen, wächst um 8 %, Rottönung.
- **Bewegung/Optik:** Ganzkörper-Transform (Anstieg aus der Tiefe, Kippen senkrecht ↔ liegend, Gieren beim Fegen, Absacken) plus Shader-Zusatz auf `creature_anim.gdshader`: **Segment-Welle** (seitliches Gleiten und Heben der Panzerringe, zum Schwanz stärker, über `wave_time` → Pause friert sie ein) und **Maulweitung** (`maw_open`).
- **Zahlen:** Schaden analog Kröte (Durchbruch = Sprung 12, Fegen 8). Standalone-LP 1000: der Wurm ist nur etwa die Hälfte eines Zyklus treffbar, der Schwarm muss nach jedem Ausweichen zurücklaufen. Bot-Kampf (weicht allem aus): **59 s @30 / 39 s @40 / 35 s @55 DPS** (Kröte 54/42/32). Im Run setzt HuntWorld wie bei der Kröte eine Tuning-Zahl (Vorschlag `APEX_SANDWORM_HEALTH` ≈ 2.500 zwischen Moosschlund 1.400 und Kröte 3.600).

### Sandmade (`scripts/sandgrub.gd`)
Horde-Vertrag wie `horde.gd` (`setup`, `spawn_burst`, `spawn_ring`, `step(delta, points) -> {bitten_indices, losses}`, `melee`, `damage_circle`, `damage_nearest`, `take_kills`, `count`, `positions`, `nearest`, `clear`). Bricht 0,45 s aus dem Sand (beißt dann noch nicht), läuft zum nächsten Mawling (5,6 m/s, Moorbrut 4,8, Schwarm ~7; Sprint ×1,5 auf den letzten 1,8 m), beißt 1× je 0,9 s, 8 LP, 0,6 Biomasse, 1 DNA; max. 32. Eine MultiMesh (creature_anim, Beine/Kiefer/Schwanzwackeln vermessen), Schatten-MultiMesh, Staub. Körper ockerbraun getönt mit bernsteinfarbenem Rand und dunkler Kontur, damit er sich vom hellen Sand abhebt.

### Kadaver
`corpse_visuals.gd`: `apex_sandworm` (Wurm auf der Seite, flach gedrückt auf 2,8 m, drei abgebrochene Zähne, goldener Halo, großer Kristall) und `sandgrub` (auf dem Rücken, 400-Dreiecks-LOD, ein kleiner Splitter). Mit `empty = true` greift das bestehende Asch-Material. `tests/corpse_visuals.gd` um beide Arten erweitert; Stapel-Obergrenze 16 → 18 (eine Stapel-MultiMesh je Design).

### Biom `duerrschlund` (`scripts/biomes.gd`, nur Daten)
Helles Ocker/Beige (`ground` #dcc89e, Wege gepresster, graulicher Sand #bcac8a), kühle blaugraue Schatten (`desert.shadow_cool`), Oasen türkis (#35c4bd) mit grünem Rand, Kaktusblüten rosa; Licht warm-neutral. Neu: `apex_kind`, `wall_tint` (gedämpftes Rostbraun, Wände bleiben dunkler als der Sand), `bone_tint`, Block `desert` (Shader-Farben für Dünen, Rippeln, Treibsand, Oase), Block `border` (Dünenkamm/Treibsand-Rand, staubiger Dunst), `props` mit Rollen (Wand: SandstoneCliff, RibBones; Deko: Cactus; Landmarke: GiantSkull, RockArch; Portal: SandPortal; fehlt: OasisPalm), Schalter `quicksand`/`sandstorm` (noch ohne Wirkung), Gegner-Tints. `ORDER` bleibt `["verdant_maw", "glutsumpf"]`.

### Tests
- `tests/apex_sandworm.gd`: Ankunft unverwundbar, Zyklus Durchbruch–Fegen, Graben unverwundbar mit Spur/Staub und verborgenem Modell, Umkreisen, Durchbruch erst nach voller Warnzeit, Treffer pro Tier, Vorhalt bei laufendem Schwarm, Erschöpfung ×1,6 und Abtauchen, Fegen (Kegel, seitlich ausweichbar, Teiltreffer), jedes Muster in beiden Phasen aus 3/7/12 m und vier Richtungen mit 45 % Reaktionszeit ausweichbar, Phase 2 (Abbruch ohne Verlust, Maden per Signal und Warteschlange, Doppel-Durchbruch, Erschöpfung nach der Kette), Pause, `defeated` genau einmal, Kadaver-Designs (auch leer), Farbenblind-Palette für Ring und Kegel, Kapsel-/Säulenkörper, Modellposen (liegend zur +Z-Seite, senkrecht > 6 m), Bot-Kampflänge 35–50 s @40 DPS.
- `tests/sandgrub.gd`: Ausbruch ohne Biss, Lauf zum nächsten Tier, Biss-Takt, Nahkampf, Fläche, Bündelung, Obergrenze, Pause, MultiMesh, Biss ohne sichtbare Punkte.
- Grün: `apex_sandworm`, `sandgrub`, `corpse_visuals`, `apex`, `apex_toad`, `migration`, `model_budget`, `encoding`, `smoke` (volle Suite und Playthrough nicht gelaufen, da andere Agenten parallel an HuntWorld/Karte arbeiten).

### Bilder (`tests/capture_sandworm.gd`, echte Spielszene, Arena ausgeblendet, Test-Sandboden in der Biom-Palette)
`preview_sandworm_props.png`, `_arrival`, `_trail`, `_breach_warning`, `_breach`, `_exhausted`, `_sweep`, `_sweep_cb`, `_sweep_strike`, `_phase2`, `_phase2_grubs`, `_grubs_close`, `_phase2_breach`, `_corpse`.

Iterationen: (1) Spur als Kugelkette mit schwarzen Schattenseiten, der halb aufgetauchte Wurm deckte beim Fegen den Schwarm zu, Maden unsichtbar im Schwarm, Wände so hell wie der Sand. (2) Spur unbeleuchtet als flache Furche mit hellem Kamm, Fegen aus 6 m und schräg aufgerichtet, Wurm kippt zur Kamera, Maden brechen außerhalb der Wurmsäule aus und sind ockerbraun getönt, Wände per `wall_tint` rostbraun. (3) Furche etwas dunkler, HUD-Texte korrekt.

**Ehrliche Bewertung:** Der glutrote Schwarm liest sich auf dem hellen Sand sehr gut; Ring und Kegel sind klar. Der Durchbruch (Rundmaul von oben, Brocken, Staub) und das Toben wirken. Schwächen: Der liegende, erschöpfte Wurm ist eine eher formlose helle Walze – das Maul ist von oben kaum zu sehen, der Zustand liest sich vor allem über Text und Randlicht. Die Spur ist lesbar, aber zurückhaltend (bei Bewegung besser als im Standbild). Der Wurm ist sandfarben auf Sand; Kontur und Schatten tragen ihn. Kaktus und Schädel wirken von oben klein bzw. klumpig (Hörner kaum sichtbar). Die Sandmaden sind in der Nahansicht gut erkennbar, im Getümmel am Schwarmrand klein.

## Phase 2 – Plan
1. **Kartenintegration (Karten-Agent, `arena*.gd`, `map_*.gd`, `flow_field.gd`, `loot_nodes.gd`, `hud_minimap.gd`):** `BIOMES.ORDER = ["verdant_maw", "duerrschlund", "glutsumpf"]` (Tests `apex.gd`/`migration` anpassen: `next_biome("verdant_maw") == "duerrschlund"`). Boden-Shader aus dem Block `desert` (Dünen, Rippeln, kühle Schatten, Knochensplitter), Wände aus `SandstoneCliff` (in Y ~×2,2) und `RibBones`, Landmarken `GiantSkull`/`RockArch` (Bogen als Durchgang auf einem Weg), Deko `Cactus`, Oasen als Lichtungen (Palme nach Lieferung), Rand aus Dünenkämmen und Klippen (`border`), `SandPortal` als Migrationsschlund der Wüste (`migration_maw.gd` je Biom), Minimap-Farben. Treibsand (verlangsamt, begehbar, sichtbare Wirbel) und Sandsturm (angekündigte Sichtwelle) als Gefahren.
2. **Run-Integration (HuntWorld):** `apex_kind_for("duerrschlund") = "apex_sandworm"`, `apex_display_name`, `KIND_RANK`/`BODY_RADIUS` (`apex_sandworm`), Belohnungen (`APEX_SANDWORM_BIOMASS/DNA/ALPHA_CORES`), Boss-Kokon (Etappe 17), Trophäe; `take_grubs()` pro Frame → `sandgrub.spawn_burst(center, count, stats)` mit Druck-Skalierung; Sandmaden wie die Moorbrut über `_flood_bites`/`_flood_kills` auflösen (gleicher Vertrag); `is_buried()` für Fokus/Zielhilfe und Minimap (Spur statt Boss-Marker); schwerer Treffer = Durchbruch (Zeile mit `current_pattern == LEAP/QUAKE`).
3. **Spawn/Balance:** Tuning-Werte nach `tuning.gd` (`APEX_SANDWORM_*`, `SANDGRUB_*`), Apex-Spawn ab Mindestpopulation zwischen Moosschlund und Kröte, Kampfdauer 25–35 s im Run messen (Backlog Punkt 4), Sandmaden auch in normalen Wüsten-Spawns (Ring über Wege) und in der Flut prüfen; Gegner-Tints der Wüste im Spiel prüfen.
4. **Musik/SFX:** Grab-Rumpeln (Schleife, lauter mit Nähe), Durchbruch (Explosion + Sand), Fegen (Peitschen-Wusch), Toben (Brüllen), Sandmaden (Zirpen/Beißen); Wüsten-Musiklage (adaptive Musik wie Verdant/Glut).
5. **2D:** Biomkarte „Dürrschlund“ und Boss-Porträt Sandwurm (`ASSET_REQUESTS.md`), Oasen-Palme als 3D-Modell.

## Phase 2 – Ergebnis (28.09.2026)

### Reihenfolge und Run
- `biomes.ORDER = ["verdant_maw", "duerrschlund", "glutsumpf"]` (Kreis wie bisher, jeder Durchlauf stärker; `apex_loop()` zählt jetzt drei Apex je Runde). Layout-Seeds je Biom über ein festes Salz (`arena.LAYOUT_SALT`), damit die Glutsumpf-Karten durch die neue Reihenfolge gleich bleiben.
- `HuntWorld.apex_kind_for` liest `apex_kind` aus den Biomdaten: Verdant → Moosschlund, Dürrschlund → **Sandwurm** (`apex_sandworm`), Glutsumpf → Aschenkröte. Sandwurm wie die Kröte eingebunden: Warnung „DER SAND BEBT · DER SANDWURM ERWACHT“ (sandfarbene Ringe), Boss-Musik, `APEX_SANDWORM_HEALTH` 2.500 (Mindestpopulation 35), Durchbruch und Schwanzfeger über `_resolve_area_hit` (pro Tier), Durchbruch als schwerer Treffer (Sound), Kadaver `apex_sandworm`, Boss-Kokon, Königsmoment, `worm_kills` in den RunStats, Sandgold als HUD-Farbe des Boss-Balkens.
- Der Schlund der Wüste ist das **SandPortal** (`migration_maw.setup(target, source)`): das Zahnmaul, im Inneren flach gedrückt, damit der Wirbel sichtbar bleibt.
- `scripts/desert_run.gd` (Kind von HuntWorld, neben der Horde erzeugt; HuntWorld ruft nur `desert.step()`): **Sandmaden** aus `apex.take_grubs()` und als seltener Hinterhalt (ab 50 s in der Wüste, alle ~38 s / √Druck, 3–6 Tiere, erst ab 8 Mawlings); Bisse über `_flood_bites`, Kills über die Brut-Bündel (Kristalle + kleine Reste). Die Maden laufen weit weg über das Flussfeld und schlüpfen immer auf offenem Sand (`sandgrub.gd`). Ein Stellvertreter (`brood_pair.gd`) gibt den Angriffsformen Moorbrut und Maden zusammen.
- Werte als eigener Block am Ende von `tuning.gd` (Sandwurm-Belohnungen, `SANDGRUB_*`, `QUICKSAND_*`, `SANDSTORM_*`).

### Karte (`map_explore.gd`, Biom-Parameter)
- Eigene Landschaften auf denselben Slots: offene Dünen (Sandsteinfelsen), Kaktushain, Sandstein-Klippenfeld, **Knochenfeld** (Rippenkörbe 10–13 m als feste Blöcke, je ein RibBones-Modell; ein angeschnittener Korb fällt ganz weg), Felsrücken, **Oase** (türkises Wasser mit grünem Rand), Schlucht. Knochenfeld, Oase und Kaktushain kommen auf jeder Wüstenkarte vor.
- Landmarken: **Riesenschädel** (Kollisionskreis 3,5 m) und **Felsbogen** (quer zur Kamera, nur die zwei Füße blockieren, darunter begehbar).
- **Treibsand**: 7–10 runde Flächen (4–6,5 m) auf offenem Sand, fern von Orten, Start und Knollen.
- Optik: `shaders/desert_ground.gdshader` (helles Ocker, kühle Senken, Windrippeln mit Schattenkante, wenige Knochensplitter, keine hellen Bodenflecken mehr), Wände zellweise wie die grüne Karte (Sandstein in gedämpftem Rostbraun mit stehenden Platten innen, Kaktus je Zelle, Oasenwasser), Rand aus Dünen, Sandstein und Dünenmeer (`arena_border._place_desert`). Minimap in Wüstenfarben mit Treibsand.
- Messwerte (Seeds 4242/31337): 27 bzw. 25 % blockiert, 7 bzw. 13 Rippenkörbe (1 bzw. 4 wegen Orten entfernt), 8/9 Treibsandflächen, Kartenbau 0,67–0,76 s unter Last (parallele Godot-Läufe; Verdant gleich schnell).

### Gefahren
- **Treibsand** (`arena.resolve_motion` → `quicksand_factor`): bremst alles auf 50 % (1,2 m weicher Rand), nie tödlich; Hinweis „TREIBSAND · bremst, raus auf festen Sand“. Sichtbar dunkler mit langsam nach innen laufender Spirale (`shaders/quicksand.gdshader`).
- **Sandsturm** (`scripts/sandstorm.gd`): erste Welle nach 45 s in der Wüste, dann alle 60–90 s; 4 s Ankündigung („SANDSTURM ZIEHT AUF“), 12 s Sturm, 2 s Ausklang. Staubschleier nur am Bildrand (innere 70 % frei), alle Kreaturen außer dem Schwarm 18 % schneller (`arena.enemy_haste`). Außerhalb der Wüste sofort ruhig.

### Menü und Meta
- Biom-Kachel „Dürrschlund“ (drei Spalten), gesperrt mit Chip „MOOSSCHLUND“, frei nach dem ersten Moosschlund-Sieg (`unlock_stat: total_moss`, `profile.is_biome_unlocked`); Platzhalterbild aus einem Capture (`assets/ui/v3/biomes/duerrschlund.png`, Felsbogen).
- Trophäe „Sandwurm bezwungen“ (`total_worms`, 3 Kronen, 250 Essenz). Regionsnamen der Wüste (Salzrinne, Knochenmulde, …).

### Tests
- Neu `tests/desert_run.gd` (in `tools/test.ps1`): Reihenfolge Verdant → Wüste → Glutsumpf → Verdant (Wüstenkarte, Shader-Boden, Pit- bzw. SandPortal-Schlund), Sandwurm 100 s nach der Ankunft (Warnung, Name, Boss-Stinger, Populationsschwelle), Durchbruch voll/Rand/daneben und Schwanzfeger pro Tier, Maden aus Phase 2 (Warteschlange geleert, beißen, sterben, Kristalle), Hinterhalt, Tod (Kadaver, Boss-Kokon, SandPortal zum Glutsumpf, `worm_kills`), Treibsand bremst den Schwarm und tötet nie, Sandsturm (Hinweis, Tempo, Schleier, Ruhe danach), Trophäe und Freischaltung.
- Angepasst: `map_layout` (zwei Wüsten-Seeds mit allen Prüfungen plus Rippen/Treibsand/Bogen), `migration` (Glutsumpf jetzt hinter der Wüste), `toad_run` (Schleife mit Sandwurm), `apex` (Reihenfolge), `map_bounds`, `menu` (Freischaltung, drei Kacheln), `arena` (Fingerabdruck ohne Material-Instanz-IDs in den Gruppennamen; die IDs verschoben sich schon durch zusätzliche Preloads).

- Volle Suite (`tools/test.ps1`) grün inkl. `balance_regress` und `endless_playthrough`; `apex_run` erwartete noch „GLUTSUMPF“ als Schlundziel und wurde auf „DÜRRSCHLUND“ angepasst (danach grün).

### Bilder (`tests/capture_desert.gd`)
`preview_desert_4242.png`, `_31337`, `_dunes`, `_cliffs`, `_oasis`, `_cactus`, `_ribs` (+ `_top`, `_collision`), `_quicksand`, `_landmarks` (Felsbogen), `_skull`, `_sandstorm`, `_minimap`, `_worm_chase`, `_worm_breach_warning`, `_worm_breach`, `_worm_exhausted`, `_worm_sweep`, `_worm_grubs`, `_worm_dead`, `_portal`, `_card`.

Iterationen: (1) Sandstein grell orange (Platten), helle Bodenflecken wirkten wie Kiesel, Oasen als Blasenmuster, Felsbogen von der Seite nur ein Klotz, Schlund ohne sichtbaren Wirbel (Zahnmaul geschlossen), Chip der Menükachel lief über. (2) Wandtönung dunkler und entsättigt, Bodenflecken aus, größere Oasenscheiben, Bogen immer quer zur Kamera, Schlund innen geöffnet, kurzer Chip „MOOSSCHLUND“.

**Ehrliche Bewertung:** Die Wüste liest sich klar anders als Verdant und Glutsumpf; der Schwarm bleibt auf dem hellen Sand das stärkste Element. Rippenkörbe, Felsbogen, Treibsand und Oasen sind gut erkennbar, Kollision = Optik hält (Rippen-Block ~0,5 m größer als das Modell, dunkler Boden füllt es). Schwächen: Die Sandsteinwände nutzen weiter das allgemeine Felsmodell (dunkle Kerbenflecken, etwas schmutzig); Kakteen wirken von oben wie stachlige Büsche; Oasen haben noch Wellenränder aus Einzelscheiben und keine Palme (fehlt als Modell); der Schädel ist als Landmarke eher niedrig. Sandmaden sind im Getümmel klein. Kein längerer Handtest, keine Messung auf dem Gerät.

### Offen
- Oasen-Palme, echtes Biomkarten-Bild und Boss-Porträt Sandwurm (`ASSET_REQUESTS.md`); Wüsten-Icon für Banner/Objectives (bisher Verdant-Symbol).
- Wüstenmusik und eigene Sounds (Graben, Durchbruch, Fegen, Maden), Kampfdauer des Sandwurms im Run messen (Ziel 25–35 s), Maden in der Flut prüfen.

**Nachtrag Etappe 20:** `APEX_SANDWORM_HEALTH` im Run auf 1.075 gesenkt (gemessen 33 s Brutal / 26 s Apex, `tests/apex_duration.gd`); Schwanzfeger mit dem SVG-Öffnungswinkel (29,2°) und Treffer ab der Kegelspitze, damit die gezeichnete Kante exakt stimmt.
