# Etappe 17 – Duale Progression: Mutationen (Werte) + Arsenal (Waffen & Relikte)

## Nutzerentscheidungen (27.09.2026)
- Zwei getrennte Spuren wie LoL Swarm (Stats + Waffen) bzw. Megabonk (Stats + Items).
- **Werte** gibt es nur über Level (DNA = Erfahrung). **Waffen und Relikte** gibt es nur über Kokons auf der Karte und über Bosse.
- **Kokon-Preis:** Biomasse, steigend je geöffnetem Kokon (Abwägung Wachstum gegen Arsenal).
- **Kokon-Beute:** Karten-Kokons geben sofort ein zufälliges Teil (kein Pausieren). Boss-Kokons lassen **1 aus 3** wählen.
- **Seltenheit:** gewöhnlich / selten / episch / legendär bei Werten und Kokon-Beute, beeinflusst vom Wert **Glück**.
- **Umfang erste Stufe:**
  - 14 Werte
  - 10 Waffen mit je 5 Rängen
  - 20 Relikte
  - 5 Evolutionen
  - Kokons und Boss-Kokon
  - Seltenheit, Balance neu

## Spur 1 – Mutationen (Werte)
- Jedes Level: 3 Karten, 1 wählen. Die bestehenden Funktionen Neu würfeln, Verbannen und Überspringen bleiben.
- Jeder Wert hat 5 Ränge. Kein Slot-Limit, weil Werte nur Zahlen ändern.
- **Seltenheitswurf je Karte:**

  | Seltenheit | Faktor | Basischance | Farbe |
  |---|---|---|---|
  | gewöhnlich | × 1,0 | 70 % | neutral |
  | selten | × 1,5 | 22 % | info |
  | episch | × 2,0 | 7 % | special |
  | legendär | × 3,0 | 1 % | loot |

  Glück verschiebt die Chancen nach oben: je Punkt Glück +10 % relativ auf selten, episch und legendär.

| ID | Name | Kategorie | Basis je Rang (gewöhnlich) | ersetzt heute |
|---|---|---|---|---|
| `bite` | Biss | Angriff | +8 % Schaden | jaws |
| `crit` | Kritbiss | Angriff | +4 % Chance auf doppelten Schaden | – |
| `haste` | Angriffstempo | Angriff | −6 % Abklingzeit der Waffen | – |
| `reach` | Reichweite | Angriff | +8 % Fläche/Reichweite der Waffen | – |
| `rally` | Rudelinstinkt | Angriff | +10 % Schaden während Rally | pack |
| `armor` | Knochenpanzer | Schutz | −6 % Verluste | armor |
| `evade` | Fluchtreflex | Schutz | −6 % Verluste ohne Rally | scatter |
| `vigor` | Anführerherz | Schutz | +1 Anführer-LP (Rang 1/3/5) | – |
| `regen` | Regeneration | Schutz | Anführer +1 LP je N Kills (N 14→8) | regeneration |
| `brood` | Brutrate | Wachstum | +6 % Biomasse je Kristall | brood/glutton |
| `magnet` | Lockduft | Wachstum | +12 % Sammelradius | lockduft |
| `gene` | Genfluss | Wachstum | +8 % DNA | – |
| `speed` | Sprinter | Sonstiges | +5 % Tempo | – |
| `luck` | Glück | Sonstiges | +1 Glück (Seltenheit, Kokon-Rabatt 3 %) | – |

`dornenhaut` wird Relikt (siehe unten).

## Spur 2 – Arsenal
### Waffen (Angriffsformen), 4 Plätze, Ränge 1–5
Findet man eine Waffe, die man schon hat, steigt ihr Rang. Rang 3 und Rang 5 bringen jeweils einen sichtbaren Sprung.

| ID | Name | Rang 3 | Rang 5 | Evolution mit Relikt |
|---|---|---|---|---|
| `rudelbiss` | Rudelbiss | +1 Sprungziel | Sprünge betäuben kurz | `meute` + Rudelhorn |
| `sporenwolke` | Sporenwolke | +30 % Fläche | Verlangsamung stärker | `pilzreich` (neu) + Sporenherz |
| `saeurespucker` | Säurespucker | 2 Salven | Säure durchschlägt | `aetzflut` + Ätzdrüse |
| `stachelruecken` | Stachelrücken | Rückschaden +50 % | Stacheln fliegen als Salve | `dornenwall` (neu) + Dornenhaut |
| `graeber` | Gräber | 2 Stöße | Nachbeben | `erdbeben` + Knochenpanzer-Relikt „Grabkralle“ |
| `blitzbiss` | Blitzbiss | +2 Kettenziele | keine Abschwächung | `sturmrudel` + Gewitterfell |
| `brutsack` | Brutsack | +1 Blase | Beißer leben länger | – (später) |
| `klauenwirbel` (neu) | Klauenwirbel | Wirbel um den Schwarm, 2 Klingen | 4 Klingen | – |
| `giftbiss` (neu) | Giftbiss | Bisse vergiften (Schaden über Zeit) | Gift springt über | – |
| `schallbrüller` (neu) | Schallbrüller | Kegel-Stoß nach vorn, wirft zurück | doppelter Kegel | – |

Evolution: Waffe Rang 5 + passendes Relikt ⇒ Der nächste **Boss-Kokon** bietet garantiert die Evolution an. Der Alpha-Kern entfällt als eigene Ressource. Elite-Jäger geben stattdessen einen kleinen Kokon.

### Relikte (Items), unbegrenzt, stapelbar
Je Relikt: ID, Name, Seltenheit, Wirkung je Stapel. Startset mit 20 Relikten:
- **Gewöhnlich:**
  - `hungerstein`: +20 % Biomasse, −5 % Tempo
  - `zaehe_haut`: −4 % Verluste
  - `scharfe_zaehne`: +6 % Schaden
  - `flinke_beine`: +6 % Tempo
  - `witterungsnase`: +15 % Sammelradius
  - `dna_splitter`: +10 % DNA
- **Selten:**
  - `sporenherz`: Kills platzen mit 15 % als Sporenwolke
  - `aetzdruese`: Säurespucker +20 % Schaden
  - `rudelhorn`: Rally +15 % Tempo
  - `gewitterfell`: 10 % Chance auf Kettenblitz bei Treffern
  - `dornenhaut`: +40 % Rückschaden
  - `grabkralle`: Gräber-Stöße +1 Radius
  - `gluecksknochen`: +2 Glück
- **Episch:**
  - `koenigszahnkette`: jeder 15. Kill heilt den Anführer um 1 LP
  - `glutdruese`: Bisse setzen Brand
  - `zwillingsbrut`: jede 4. Zellteilung ergibt 2 Tiere
  - `magnetkern`: Lockrufe doppelt so oft
- **Legendär:**
  - `urmutter`: +1 Waffenplatz
  - `blutmond`: +40 % Schaden, Anführer −1 LP maximal
  - `schlundherz`: Kokons 40 % billiger

### Kokons
- **Karten-Kokons (Brutkokon):**
  - Pro Region seed-basiert 1–2 Kokons, auf der Minimap sichtbar, bleiben bis zum Öffnen liegen (Ressourcenregel).
  - Öffnen: Schwarm 1 s darin halten, dann Abbuchung der Biomasse. Preis: 25 · 1,35^n (n = bereits geöffnete Kokons), Rabatt durch Glück/Schlundherz. Ohne genug Biomasse zeigt der Kokon den Preis rot.
  - Beute sofort und zufällig (kein Pausieren):
    - 55 % Relikt, 45 % Waffe (neu oder Rang +1); bei vollen Waffenplätzen nur Rang +1 vorhandener Waffen.
    - Seltenheit gewürfelt (mit Glück).
- **Elite-Kokon:** Elite-Jäger lassen einen kleinen, kostenlosen Kokon fallen (Beute wie Karten-Kokon, Seltenheit mindestens selten).
- **Boss-Kokon (golden):**
  - Bog King, Moosschlund und Aschenkröte hinterlassen ihn, kostenlos.
  - Öffnen pausiert, **1 aus 3**, Seltenheit mindestens episch; bietet garantiert eine Evolution an, wenn eine bereitsteht.
- **Öffnungsmoment:** Der Kokon pulsiert und platzt, ein Lichtstrahl in Seltenheitsfarbe steigt auf, die Beute-Karte ploppt kurz im HUD auf (Kit-Karte mit Seltenheitsrand), dazu ein Sound je Seltenheit.

## Power-ups (Nutzerwunsch 27.09.2026, wie in Megabonk)
Kurze Booster als Aufsammel-Objekte, die das Spiel dynamischer machen. Sie werden eingesammelt wie Kristalle, laufen aber nicht über den Magneten, damit man bewusst hinlaufen muss. Nur der Lockruf bleibt Magnet-Auslöser.

| ID | Name | Wirkung | Dauer | Farbe |
|---|---|---|---|---|
| `rausch` | Rausch | +45 % Tempo | 8 s | action (grün) |
| `blutrausch` | Blutrausch | −40 % Abklingzeit aller Waffen | 8 s | ember |
| `magnetsturm` | Magnetsturm | Sammelradius ×3 | 10 s | loot |
| `chitinschild` | Chitinschild | Anführer unverwundbar, −70 % Verluste | 6 s | info |
| `raserei` | Raserei | doppelter Schaden | 7 s | danger |
| `brutwelle` | Brutwelle | sofort +Biomasse für 3 Zellteilungen | sofort | special |

- **Quellen:**
  - 1,5 % je normalem Kill (höchstens 1 Power-up alle 20 s)
  - garantiert bei Elite-Jägern
  - zerstörbare „Pilzknollen“ auf der Karte (2–3 je Region, seed-basiert, ein Biss öffnet sie)
  - ein Power-up je neuer Flutstufe
- Power-ups bleiben liegen, bis man sie einsammelt (Ressourcenregel); nach 45 s blinken sie als Hinweis, verschwinden aber nicht.
- **Stapeln:** Gleiche Power-ups verlängern die Dauer (maximal das Doppelte), verschiedene laufen parallel.
- **Darstellung in der Welt:** schwebende, rotierende Plakette mit Icon in ihrer Farbe und Lichtsäule, gut unterscheidbar von Kristallen.
- **Darstellung im HUD:** unter der Schwarm-Pill eine Reihe kleiner `icon_plate` mit Ring-Timer. Beim Einsammeln ein kurzes Band („RAUSCH!“) und ein Farbpuls am Schwarm (z. B. Speed-Linien, Schild-Kuppel).
- Die Relikte `magnetkern` und `gluecksknochen` wirken auch auf die Power-up-Chance.

## Schnittstellen (verbindlich für die Umsetzungs-Agenten)
- `scripts/progression/stats.gd` (neu): Definition der 14 Werte, Rang und Seltenheit, `mods` wie heute `evolution.mods`, dazu `roll_offers(rng, luck)`.
- `scripts/progression/arsenal.gd` (neu): Waffen-Ränge 1–5, Plätze, Relikt-Stapel, `roll_chest(rng, luck, kind)` mit kind = map/elite/boss, `evolution_ready()`.
- `scripts/evolution.gd`: bleibt die Fassade für HuntWorld und HUD (Level, DNA, Angebote, `mods`) und delegiert an beide. Bestehende Aufrufer möglichst unverändert.
- `scripts/attack_forms.gd`: Rangstufen 1–5 und neue Waffen.
- `scripts/powerups.gd` (neu): Power-ups (Drop, Aufsammeln, Timer, Wirkung über `mods`-Multiplikatoren, die Stats/Arsenal ergänzen) und Pilzknollen.
- `scripts/chests.gd` (neu): Kokons in der Welt (MultiMesh oder wenige Knoten), Seed-Platzierung je Region, Halten zum Öffnen, Preis, Öffnungsmoment.
- HUD:
  - `mutation_screen.gd`: Seltenheitsrand, Werte-Karten, Boss-Kokon-Auswahl mit denselben Karten.
  - `hud_top`: Waffen-Medaillons mit Rang 1–5 und kleiner Relikt-Leiste.
  - Kokon-Preis-Pill über dem Kokon.
  - Minimap-Symbol Kokon.
- Meta: Freischaltungen wie heute über Trophäen (`mutation:<id>`, neu `relic:<id>`, `weapon:<id>`). Die Startpools legt `meta_data.gd` fest.
- Balance: Der Bot kauft Kokons nach einer einfachen Regel (Biomasse > 2 × Preis und Pop ≥ 20); die Zielkurven aus Etappe 09 und 16 bleiben.

## Abnahme
1. Beide Spuren sind spielbar: Level geben nur Werte, Kokons und Bosse nur Waffen und Relikte.
2. Alle Inhalte aus den Tabellen sind vorhanden und im Kit-Stil dargestellt; Icons nutzen vorhandene IDs oder Platzhalter-Plaketten. Für fehlende Icons Prompts in `stages/ICON_REQUESTS.md` ergänzen.
3. Seltenheit sichtbar (Kartenrand und Strahl) und wirksam; Glück wirkt.
4. Evolution über Waffe 5 + Relikt + Boss-Kokon.
5. Tests: neue Tests `progression_stats`, `arsenal`, `chests`, `powerups`; alle bestehenden angepasst und grün; Balance-Zielkurven eingehalten.
6. Captures: Level-up mit seltener Karte, Kokon mit Preis, Öffnungsmoment je Seltenheit, Boss-Kokon-Auswahl, HUD mit 4 Waffen und Relikten.

## Ergebnis Welle 1 – Datenschicht und Level-Spur (27.09.2026)

### Umgesetzt
- **Werte** (`scripts/progression/stats.gd`): 14 Werte, 5 Ränge, Seltenheitswurf 70/22/7/1 mit Glück (+10 % relativ je Punkt), `roll_offers(rng, luck, pool, banished, exclude)`. Rang = Anzahl Wahlen, „Wert“ = Summe der Seltenheitsfaktoren (Wirkung = Basis × Wert). Alte Anlagen-IDs werden abgebildet (`jaws→bite`, `pack→rally`, `scatter→evade`, `glutton/brood→brood`, `lockduft→magnet`, `regeneration→regen`).
- **Arsenal** (`scripts/progression/arsenal.gd`): 10 Waffen, 20 Relikte (6/7/4/3), 6 Evolutionsregeln, 4 Plätze (+Urmutter, +Meta-Waffenplatz), `roll_chest(rng, luck, kind)`, `grant(item)`, `evolution_ready()`, `chest_price(luck)`. Waffen-Seltenheit = Rang-Sprung (gewöhnlich/selten +1, episch +2, legendär +3).
- **Waffen** (`scripts/attack_forms.gd`): Ränge 1–5 für die 7 Formen (Rang 1–3 wie bisher, Sprünge: Rudelbiss Folgesprung/Betäubung, Sporen +30 % Fläche/starke Lähmung, Säure Doppelsalve/Durchschlag, Stacheln +50 %/Stachelsalve, Gräber 2 Stöße/Nachbeben, Blitzbiss +2 Ziele/keine Abschwächung, Brutsack 2 Blasen/langlebige Beißer). Neu **Klauenwirbel** (kreisende Klingen mit Glutschweif), **Giftbiss** (zuschnappende Fänge, Gift als DoT mit Bodenring und Blasen, Rang 5 springt über), **Schallbrüller** (Schallbögen im Kegel, Rückstoß leichter Gegner, Rang 5 doppelter Kegel). Neue Evolutionen **Pilzreich** und **Dornenwall** sind gebaut. Alles über FX-Batches (je Effekt ein Draw-Call).
- **Relikte:** alle 20 wirken; Hooks gebündelt in `evolution.gd` (`note_kills`, `note_divisions`, `roll_kill_burst`, `form_modifiers`, Multiplikatoren) plus `attack_forms.on_kill/spore_burst`. HuntWorld ruft sie an genau einer Stelle je Hook.
- **Fassade** `scripts/evolution.gd`: Level geben nur Werte; `offers` = `[id, Name, Text, Seltenheit]`. Alpha-Kern ist Stub (`add_alpha_core` leer, Drops aus, `hunt_world.alpha_cores_enabled` nur für Tests). `debug_grant(id, rarity)`.
- **Mutation-Screen:** Seltenheitsrand (neutral/info/special/loot + Glanz), Chip, Wert vorher → nachher, 5 Rang-Punkte; Modus `chest` (Boss-Kokon) mit Waffe/Relikt/Evolution, Rang- bzw. Stapelwechsel und Evolutions-Pille.
- **Meta:** neue Pools (`TRAIT_IDS`, `START_WEAPONS`, `START_RELICS`), Token `weapon:`/`relic:`, Trophäen umgestellt, neue Relikt-Freischaltungen (Urmutter: boss_5, Blutmond: kills_2000, Schlundherz: Moosschlund), Evolutions-Trophäen Pilzreich/Dornenwall. Profile migrieren alte IDs und tragen Relikte früher erfüllter Trophäen nach. „Anlagenslot“ heißt jetzt „Mutationswurf“ (+1 Neu würfeln je Rang), „Angriffsslot“ „Waffenplatz“.

### API für Welle 2
- `evolution.open_chest(kind)` → map/elite: Beute sofort (`granted`), zählt den Preis hoch; boss: füllt `chest_offers`, die Welt hält an (`HuntWorld.choosing()`), `HuntWorld.choose_mutation(slot)` wählt die Beute (auch per Tap/1-2-3). `evolution.chest_price()`, `evolution.roll_chest(kind)`, `evolution.grant(item)`, `evolution.evolution_ready()`.
- Jede Änderung erhöht `evolution.revision`; HuntWorld synchronisiert dann Waffen, Modifikatoren, Anführer-LP und zeigt eine neue Evolution (`try_evolve()` liefert sie einmal).
- Power-ups: `evolution.boosts` (`damage`, `speed`, `magnet`, `cooldown`, `loss`, `leader_immune` – letzteres noch ohne Wirkung, Welle 2 schließt es im Treffer-Pfad an).
- Elite-/Boss-Drops: die alten `_drop_alpha_core`-Stellen in `hunt_world._resolve_death` sind die Einhängepunkte für Elite- und Boss-Kokon.

### Balance (ohne Kokons, 3 Stämme × 6 Seeds, greedy)
Ohne Waffen-Aufstieg fiel der Wild-Median auf ~230 s. Ausgleich: Startwaffe auf Rang 4 (`SIGNATURE_START_RANK`) und einige Werte über Konzept (Biss 12, Kritbiss 5, Tempo 8, Reichweite 10, Rudelinstinkt 12, Panzer/Flucht 8, Brutrate 10 %). Ergebnis: Wild 503 s (Wachstum 9,5/38,5/133 ok), Brutal 307 s ok, Apex 226 s ok. Offen: Stammspreizung (Knochenkiefer mit passivem Stachelrücken deutlich schwächer, Sporling stärker), einzelne 900-s-Läufe auf Wild. Welle 2 muss mit Kokons neu balancieren und `SIGNATURE_START_RANK` voraussichtlich auf 1 senken. Die Messungen liefen parallel zu Umbauten des Karten-Agenten und sind deshalb verrauscht.

### Tests und Bilder
- Neu: `tests/progression_stats.gd`, `tests/arsenal.gd` (in `tools/test.ps1`). Angepasst: evolution, run_config, attack_forms (+ neue Waffen/Relikte/Evolutionen), forms_extra, meta, loot_magnet, sfx, sfx_hooks, migration, toad_run, apex_run, objectives, perf_bench, Captures.
- Bilder: `preview_ui_mutations_rarity|legendary|long|levelup|flash|chest|chest_ranks[_540].png` (`tests/capture_ui_mutations.gd`), `preview_weapons17_*.png` (`tests/capture_weapons17.gd`).

### Offen
- Icons fehlen (Prompts in `stages/ICON_REQUESTS.md`); Klauenwirbel, Giftbiss, Schallbrüller und Glutdrüse zeigen eine Buchstaben-Plakette.
- ~~HUD oben zeigt Waffen-Medaillons noch mit 3 Rangpunkten, keine Relikt-Leiste~~ → Welle 2.
- Kritbiss wirkt als Erwartungswert (keine sichtbaren Krit-Treffer).
- Schallbrüller schiebt nur Gegner mit `slow_factor` (Nibbler, Jäger, Skitter), nie Bosse/Leaper.

## Ergebnis Welle 2 – Kokons, Power-ups, Schreine (27.09.2026)

### Umgesetzt
- **Kokons** (`scripts/chests.gd`, ein Knoten „Chests“ unter HuntWorld):
  - Karten-Kokons an `arena.poi_slots("cocoon")`, goldene an `poi_slots("cocoon_gold")`; ohne Plätze (Seed 0) 6 + 1 Rückfall-Plätze auf offenem Boden.
  - Öffnen: Schwarm-Mitte 1 s im Haltekreis (Verlassen lässt die Haltezeit doppelt so schnell sinken). Karten-Kokon zahlt `evolution.chest_price()` aus der Biomasse des Schwarms (erst die Bank, dann ganze Tiere, nie der Anführer). Zu teuer: bleibt zu, Pille rot mit Chip „ZU TEUER“, Warnklang.
  - Goldener Kokon: gratis, `open_chest("elite", "epic")` (sofort, mindestens episch, erhöht den Preis nicht). Auslegung der Vorgabe „selten bzw. episch“: Elite-Kokon mindestens selten, goldener mindestens episch.
  - Elite-Jäger → kleiner Gratis-Kokon (`open_chest("elite")`, mindestens selten) statt Alpha-Kern. Bog King, Moosschlund, Aschenkröte → goldener Boss-Kokon → `open_chest("boss")` → 1 aus 3 im `mutation_screen` (Modus `chest`); die Wahl zeigt danach ihre Beute-Karte.
  - Kokons bleiben liegen, bis sie geöffnet sind; eine neue Karte (Migration) bringt neue Karten-Kokons, fallen gelassene (Elite/Boss) wandern mit an den Ankunftsort.
  - Öffnungsmoment: 0,45 s Pulsieren mit Zittern → Platzen (Splitter), Lichtstrahl in der Seltenheitsfarbe (Höhe wächst mit der Seltenheit), zwei Ringe, Wackler, Klang je Seltenheit (`pickup`/`mutate`/`alpha_core`/`evolve` + `fanfare`), Beute-Karte 2 s im HUD.
  - Optik: eigenes Primitiv (Seiden-Ei mit drei Bändern auf einem Seidenhügel, glühender Schlitz zur Kamera, Boden-Halo und Haltekreis; golden bzw. mit Knochenkrone für den Boss-Kokon). Modell-Wunsch in `ASSET_REQUESTS.md`.
  - Bernsteinknollen: `loot_nodes.bonus("relic")` → `evolution.relic_find()` (ein Relikt, Seltenheit mit Glück) mit Strahl und Karte.
- **Power-ups** (`scripts/powerups.gd`): die 6 Booster des Konzepts über `evolution.boosts`; Blutrausch erhöht `evolution.revision`, damit die Waffen-Abklingzeiten neu gesetzt werden. `leader_immune` wirkt in `hunt_world._apply_hit` (Anführer wird nicht getroffen). Quellen: 1,5 % je normalem Kill (Nibbler, Jäger, Skitter, Leaper; höchstens einer je 20 s; Magnetkern ×2 je Stapel, Glück +10 % je Punkt), jeder Elite-Jäger, jede neue Flutstufe, Pilzknollen-Haine (`poi_slots("grove")`, 2–3 Knollen, ein Biss; der Booster springt knapp vor den Schwarmrand), `loot_nodes.bonus("powerup")`. Nur Hinlaufen (kein Magnet, kein Lockruf); Stapeln bis zum Doppelten; nach 45 s Blinken, nie Verschwinden. Welt: schwebende, pendelnde Plakette mit Symbol, Lichtsäule und Bodenring in der Booster-Farbe. Am Schwarm: Rausch Tempo-Linien, Chitinschild Kuppel, Raserei roter Rand, Magnetsturm der Sammelkreis, Blutrausch pulsierender Glutring; letzte 1,5 s blinken.
- **Schreine** (`scripts/shrines.gd`): Steinkreis mit 16 Ladeplatten und Kristall; Schwarm-Mitte im Ring lädt in 4 s (Verlassen pausiert) → `evolution.open_shrine()`: 1 aus 3 Werten, mindestens selten, über den Level-up-Screen (Band „SCHREIN!“ · „MINDESTENS SELTEN“), kostet keine DNA und zählt kein Level; Neu würfeln/Verbannen behalten Schrein-Karten, Überspringen kostet keine DNA. Ein voller Schrein wartet, bis eine offene Wahl geschlossen ist. Einmal je Schrein.
- **HUD:** `hud_top.gd`: Waffen-Medaillons mit 5 Rang-Punkten (Rang 5 gold), Evolution mit violettem Glanz und EVO-Chip, darunter Relikt-Leiste (2 Spalten, Plaketten in Seltenheitsfarbe, Stapel-Abzeichen, ab 8 „+N“), Power-up-Reihe mit Ring-Timern unter der Schwarm-Pille (neben der Minimap). Neu `scripts/ui/hud_loot.gd`: Preis-Pillen über Kokons in der Nähe (Haltebalken), Lade-Pillen über Schreinen, Beute-Karte (Kit-Karte mit Seltenheitsrand), Power-up-Band. HUD-Meta `arsenal_world`; Karten-Meta `map` trägt `chests` [{at, kind, dropped}], `powerups` [{at, id}], `shrines` [{at, done, charge}], gefiltert über `arena.is_discovered` (Rückfall `is_explored`).
- **Fassade:** `evolution.open_chest(kind, minimum)`, `open_shrine()`, `offer_source`, `relic_find()`; `arsenal.roll_chest(..., minimum)`, `roll_relic()`; `stats.roll_offers(..., minimum)`. `SIGNATURE_START_RANK` = 1.
- **Bot** (`tests/balance_sim.gd`): Boss-Kokon-Wahl (Evolution > Waffe aufwerten > neue Waffe > Relikt), Power-ups bis 14 m und Knollen bis 9 m auf dem Weg, Karten-Kokons nach „Biomasse > 2 × Preis und Pop ≥ 20“ bis 90 m, Gratis-Kokons bei kleinem Schwarm nur bis 25 m, Schreine ab Pop 15 ohne Gegner in 12 m. BALANCE-Zeile: `cocoons=map/gold/elite/boss boosts= shrines=`.

### Tests und Bilder
- Neu: `tests/chests.gd`, `tests/powerups.gd`, `tests/shrines.gd` (in `tools/test.ps1`).
- Bilder: `tests/capture_arsenal17.gd` (ohne `--headless`, `--screen 1 --audio-driver Dummy`, optional `-- cocoon|open|boss|powerups|shrine|hud`) → `preview_arsenal17_cocoon_price|cocoon_red|cocoon_hold|open_common|open_rare|open_epic|open_legendary|boss_choice|boss_card|powerups_world|powerup_<id>|shrine|hud_full.png`.

### Balance (3 Stämme × 4–6 Seeds, greedy; Messungen stark verrauscht, der Rechner lief parallel mit anderen Agenten)
| Variante | Wild | Brutal | Apex | Wachstum Wild 1:00 / 2:00 |
|---|---|---|---|---|
| Rang 1, Konzept-Preis (Stand jetzt) | 230 s | 227 s | 161 s | 5,5 / 12,5 |
| Rang 2 | 261 s | – | 172 s | 5,5 / 14 |
| Rang 4 (Welle-1-Wert) + Kokons | 779 s (Läufe bis 900 s) | – | 281 s | 5,5 / 22,5 |
| Rang 1 + kleiner Schwarm beißt stärker (SMALL_SWARM_BITE 3–4, FORM_MIN_SHARE 0,35–0,5) | 235 s | 249 s | 184 s | 6 / 17 |

Befund: Mit Rang 1 sterben viele Läufe bei 90–110 s am ersten Jäger-Paar, bevor der Schwarm 20 Tiere erreicht; dann kauft der Bot nach der Regel keinen Kokon. Wer überlebt, schneeballt mit Kokons stark (Rang 4: 5–7 Karten-, 3 Elite-, 5 Boss-Kokons, bis 30 Power-ups je Lauf). Die Zielkurven sind **nicht erreicht**; die Frühphasen-Stellschrauben in `tuning.gd` halfen kaum und sind deshalb nicht übernommen. Werte (`stats.gd`) bleiben auf Welle-1-Niveau (ein Zurück zum Konzept schwächt die Frühphase weiter). Stamm-Spreizung: Knochenkiefer (passiver Stachelrücken) bleibt klar am schwächsten.
Vorschläge: Rang-1-Werte der Waffen in `attack_forms.gd` anheben (Datei des VFX-Agenten) oder ein Gratis-„Start-Kokon“ nahe dem Start; gegen den Schneeball Boss-Kokons nur beim ersten Bog King je Zyklus oder `CHEST_GROWTH` 1,45–1,5.

Suite-Stand (27.09., 23:57): alle Tests grün außer `arena` („Verdant Maw chunks unchanged“, Karten-Agent) und `balance_regress` (glutmaw/Apex erreicht die Flut nicht mehr: 0 s Flut, 0 Moorbrut-Verluste – Folge von Rang 1).

### Offen
- Balance-Zielkurven und `balance_regress` (siehe oben); Entscheidung über den Ausgleich für Rang 1 nötig.
- Eigene Icons für Power-ups/Kokon/Schrein (`ICON_REQUESTS.md`), Modelle (`ASSET_REQUESTS.md`).
- Die Minimap-Symbole für `chests`/`powerups`/`shrines` zeichnet der Karten-Agent.

## Welle 2b – Orchestrator- und Nutzerentscheidungen (28.09.2026)

Diese Stände ersetzen die entsprechenden Punkte von Welle 2 oben.

### Wirtschaft: drei Ressourcen
- **Biomasse** = Wachstum, nur aus Gegner-Kills; Kristalle jetzt grün/lime (Kit-Ton action).
- **DNA** = Erfahrung; im HUD nur noch als dünner violetter XP-Balken ganz oben über die volle Breite (unter der Safe Area, ohne Zahl). Das Level steht als violettes Abzeichen an der Bernstein-Pille.
- **Bernstein** = In-Run-Währung für Kokons (`model.amber`, verfällt am Run-Ende, keine Meta-Währung):
  - Münzen (`loot.Kind.AMBER`, eigene MultiMesh, goldene, zur Kamera geneigte Scheiben) aus Kills: `TUNING.AMBER_KILL` = Nibbler 1, Jäger 2, Skitter 1, Leaper 2, Elite 12, Bog King 25, Apex 40; Moorbrut 0,25 je Tier.
  - Aus Bernsteinknollen (`AMBER_NODE` 3/6/12) und dem Hain-Schatz (`AMBER_GROVE` 6 je Knolle).
  - Magnet wie Kristalle; ein voller Schwarm nimmt Bernstein weiter.
- **Kokons kosten Bernstein** (`chest_price()` = 25 · 1,85^n), nie Tiere oder Biomasse. Die Preis-Pille zeigt Bernstein und ist rot, wenn er nicht reicht.
- HUD: Die rechte Pille ist die Bernstein-Pille (Gold-Plakette, Zahl mit Tausenderpunkt). Der Sammel-Zähler am Schwarm zeigt Bernstein gold, Biomasse grün, DNA blau. Die Schwarm-Pille zeigt den gemalten Stammkopf (`UiIcons.strain_head`) auf dunkler Plakette.
- **Offene Welt gibt nur Münzen und XP**: Bernsteinknollen geben Bernstein und DNA, keine Biomasse, keine Power-ups, keine Relikte. Das Signal `loot_nodes.bonus` wird nicht mehr gesendet; der Relikt-Wurf ist entfernt.

### Power-ups
- Nur noch von **Mini-Bossen**: Elite-Jäger, Mire Leaper, Bog King, Apex. Je Kill garantiert ein zufälliger aus den sechs.
- Entfallen: 1,5 %-Drop bei normalen Kills, Drop je Flutstufe, Pilzknollen als Quelle.
- Die Hain-Plätze tragen jetzt einen **Bernstein-Schatz** (2–3 goldene Knollen dicht beieinander, ein Biss bricht sie in Münzen).

### Balance-Maßnahmen
- **Waffen-Rang 1 moderat angehoben** (`attack_forms.gd`, Rang 2–5 steigen weiter sichtbar): z. B. Rudelbiss 12 Schaden alle 1,8 s, Sporen 8/s, Stachelrücken 44 (Knochenkiefer-Stärkung), Säure 7,5 alle 1,1 s. Die Rangtexte sind angepasst.
- **Start-Kokon**:
  - Gratis, 15–30 m um den Start auf offenem Boden, immer auf der Minimap.
  - Beute gewöhnlich/selten; eine neue Waffe, solange weniger als zwei Waffen da sind (`arsenal.roll_start`).
- **Gegen den späten Schneeball**:
  - `CHEST_GROWTH` 1,85.
  - Die garantierte Evolution gibt es nur im ersten Boss-Kokon je Biom-Zyklus (`evolution.evolution_guarantee`, zurückgesetzt bei der Ankunft im neuen Biom).
  - Nur der erste Bog King je Biom-Zyklus hinterlässt einen Boss-Kokon, weitere einen Elite-Kokon. Apex-Bosse geben immer einen.
  - Werte wieder auf Konzept (Biss 8, Kritbiss 4, Tempo 6, Reichweite 8, Rudel 10, Panzer/Flucht 6, Brutrate 6 %).
  - Level-Schwelle `20 + 10·L + 1,5·L²`: späte Level teurer, frühe fast unverändert.
- **Bot**: Er kauft Karten-Kokons, sobald der Bernstein reicht und nichts droht. Gratis-Kokons holt er bei kleinem Schwarm nur bis 25 m, den Start-Kokon immer.

### Balance-Messungen (3 Stämme × 5 Seeds, greedy; Rechner parallel ausgelastet, verrauscht)

| Stand | Wild | Brutal | Apex | Wachstum 1:00 / 2:00 | Spreizung W/B/A |
|---|---|---|---|---|---|
| Rang-1-Anhebung + Start-Kokon (Biomasse-Preis) | 809 s | 514 s | 240 s | 12 / 25 | 42/37/32 % |
| + Bernstein-Wirtschaft (Wachstum 1,5) | 900 s | 755 s | 340 s | 13 / 35 | 10/26/52 % |
| + Werte Konzept, Wachstum 1,7, weniger Bernstein/Kill, Level-Schwelle quadratisch | 580 s | 390 s | 222 s | 13 / 31 | 27/33/3 % |
| **+ Wachstum 1,85 (Stand jetzt)** | **566 s** | **366 s** ✓ | **221 s** ✓ | **13 / 31** ✓ | **9/22/3 %** ✓ |

Wild liegt noch rund 10 % über dem Ziel 390–510 s. Gute Läufe überleben die Flut lange; Wild hat den spätesten Flutstart. Brutal, Apex, Wachstum und Spreizung liegen im Ziel.

### Tests (28.09.2026, 01:40)
- `tools/test.ps1` ist grün bis auf zwei Tests in fremden Bereichen:
  - `arena` („Verdant Maw chunks unchanged“, Kartenbau des Karten-Agenten).
  - `apex_run` („HUD: MIGRATION pointer data“: das Migrationsziel ist nicht mehr GLUTSUMPF, Folge des neuen Bioms Dürrschlund in `biomes.gd` des Wüsten-Agenten).
- `balance_regress` ist grün. Die Toleranz für Moorbrut-Verluste bei Apex liegt jetzt bei 3 statt 5: Apex-Läufe enden häufiger in den ersten Flutsekunden durch Jäger oder Leaper.
- Angepasst:
  - `chests`: Bernstein-Kauf, keine Tiere, Münz-Drop und Magnet, Bernsteinknollen ohne Biomasse/Relikt/Power-up, XP-Balken ohne Zahl, Start-Kokon, Evolutionsgarantie je Zyklus.
  - `powerups`: nur Mini-Bosse, Hain-Schatz.
  - `loot_magnet`: Münzen zählen nicht zu den Kristallen.
  - `attack_forms` und `forms_extra`: Rangwerte über die Konstanten.
  - `arsenal`: Preis über `CHEST_GROWTH`.
  - `evolution`: quadratische Level-Schwelle.
  - `horde`: Stachelrücken Rang 1 = 44.
- Bilder `preview_arsenal17_*.png` sind neu erzeugt, darunter `loot` (Münzen gold, Biomasse grün, DNA blau). `hud_full` zeigt Bernstein-Pille, XP-Balken und Stammkopf; `cocoon_price` und `cocoon_red` zeigen den Bernstein-Preis.
