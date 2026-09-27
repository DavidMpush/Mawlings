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
- HUD oben zeigt Waffen-Medaillons noch mit 3 Rangpunkten, keine Relikt-Leiste (Welle 2, `hud_top.gd`).
- Kritbiss wirkt als Erwartungswert (keine sichtbaren Krit-Treffer).
- Schallbrüller schiebt nur Gegner mit `slow_factor` (Nibbler, Jäger, Skitter), nie Bosse/Leaper.
