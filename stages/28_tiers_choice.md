# Etappe 28 – Seltenheitsstufen und volle Build-Kontrolle

Quelle: Nutzerwunsch 28.09.2026 („Upgrade Tiers umsetzen“, „nie eine Waffe oder ein Stat-Upgrade random – ich möchte mit meinem Build immer die Kontrolle haben“) und die geplante Seltenheitsrunde aus `stages/21_balance.md`.

## Befund

- 4 Stufen (`stats.gd` `RARITIES` common/rare/epic/legendary, Faktoren 1/1,5/2/3, Chancen 70/22/7/1 %).
- Kartenfarbe folgt der **Kategorie** (Waffe Glut, Relikt neutral, Wert je Zweig); nur Rand und Chip zeigen die Seltenheit (`mutation_screen.gd` `_card_style`). Beutekarte, Relikt-Leiste und Kodex-Relikte nutzen schon die Seltenheit, aber jeweils eigene Tabellen.
- **Zufällige Vergabe ohne Wahl:** Karten-Kokon (Bernstein), goldener Kokon, Elite-Kokon und Start-Kokon würfeln je ein Item und geben es sofort (`evolution.open_chest` → `grant`). Nur der Boss-Kokon bietet 1 aus 3. Level und Schrein bieten 1 aus 3 Werte.
- Power-ups (Mini-Boss-Drops, zeitlich begrenzt) sind kein Build-Bestandteil und bleiben Drops.

## Ziele und Abnahmekriterien

### A. Fünf Seltenheitsstufen (Logik)
1. `common` GEWÖHNLICH (grau) · `uncommon` UNGEWÖHNLICH (grün, **neu**) · `rare` SELTEN (blau) · `epic` EPISCH (violett) · `legendary` LEGENDÄR (gold).
2. Wert-Faktoren 1,0 / 1,25 / 1,5 / 2,0 / 3,0; Basischancen 55 / 25 / 13 / 6 / 1 %. Glück hebt wie bisher alles ab `uncommon` relativ an.
3. Waffen-Rangsprung je Seltenheit: gewöhnlich/ungewöhnlich/selten +1, episch +2, legendär +3 (wie bisher, neue Stufe +1).
4. Böden: Start-Kokon höchstens selten, Karten-Kokon gewöhnlich, Elite-Kokon selten, goldener Kokon episch, Boss-Kokon episch, Schrein selten. Relikte behalten ihre feste Seltenheit; einzelne bisher gewöhnliche Relikte dürfen auf `uncommon` rücken, wenn es die Verteilung braucht.
5. Profile, Kodex, Chronik und gespeicherte Stände mit alten Ids laden weiter (keine Id entfällt).

### B. Jede Build-Änderung ist eine Wahl (Logik)
1. **Alle Kokons** (Start, Karte, Elite, gold, Boss) öffnen eine **1-aus-3-Wahl** (`evolution.chest_offers`, gleiche Karten wie der Boss-Kokon). Nichts wird mehr automatisch vergeben.
2. Die drei Angebote sind verschieden und immer gültig: Bei vollen Waffenplätzen nur Rang-ups eigener Waffen und Relikte; ohne gültige Angebote (alles maximal) gibt es einen Bernstein-Ersatz statt einer Karte.
3. Start-Kokon: mit < 2 Waffen drei **neue Waffen** zur Wahl.
4. Bernstein wird beim Öffnen bezahlt (wie bisher); die Wahl pausiert die Welt wie die Level-Wahl.
5. Boss-Kokon behält seine Evolutions-Garantie.
6. Die Beutekarte (`hud_loot.gd`) zeigt nach der Wahl weiterhin kurz das gewählte Item.
7. Der Balance-Bot wählt über dieselbe Wahl (seine Strategie), `balance_regress` besteht.

### C. Farbe folgt der Seltenheit, überall gleich (UI)
1. Zentrales Token `UiStyle.RARITY_TONES` / `UiStyle.rarity_tone(id)` / `UiStyle.rarity_name(id)` mit den fünf Stufen (brawl und Fallback-Skins).
2. Karten der Mutationswahl (Level, Schrein, alle Kokons): **Kartenkörper, Rand, Kopf und Chip in Seltenheitsfarbe**; die Kategorie (WAFFE, RELIKT, WERT · ANGRIFF …, EVOLUTION) nur als kleines Label. Evolution behält zusätzlich den goldenen Glanz.
3. Gleiche Farben in Beutekarte, Kokon-Strahl und -Glühen je nach bester angebotener Seltenheit, Relikt-Leiste im HUD, Kodex (Relikte, Waffen-Ränge wo sinnvoll) und Schrein.
4. Lesbarkeit: grau und grün sind klar unterscheidbar; die Farbenblind-Einstellung behält Unterscheidbarkeit (Chip-Text trägt die Stufe).
5. Prüfbilder: Mutationswahl mit allen fünf Stufen, Kokonwahl, Beutekarte, Kodex.

## Schnittstellen

- `stats.gd`: `RARITIES := ["common", "uncommon", "rare", "epic", "legendary"]`, `RARITY_FACTOR`, `RARITY_CHANCE`, `RARITY_NAME` (UNGEWÖHNLICH), `RARITY_TONE` bleibt als Alias auf `UiStyle.rarity_tone`.
- `UiStyle.RARITY_TONES: Dictionary` id → Ton-Dictionary wie `brawl_tone()` (`face`, `light`, `dark`, …); `UiStyle.rarity_tone(id) -> Dictionary`, `UiStyle.rarity_color(id) -> Color` (Face), `UiStyle.rarity_name(id) -> String`.
- `evolution.chest_offers` für jede Kokon-Art; `evolution.chest_kind` (start/map/elite/gold/boss) für Band und Fußzeile im Wahlbildschirm.
- Karteneinträge unverändert `[id, Name, Desc, rarity, item]`; `item.kind` ∈ weapon/relic/evolution/rank liefert das Kategorie-Label.

## Ergebnis (28.09.2026)

- **Stufen:**
  - Fünf Stufen (grau, grün, blau, violett, gold), Faktoren 1/1,25/1,5/2/3, Chancen 55/25/13/6/1 %, Rangsprung +1/+1/+1/+2/+3.
  - Hungerstein, Witterungsnase und DNA-Splitter wurden auf `uncommon` gesetzt; Relikt-Verteilung 3/3/11/5/3.
  - Alte Ids laden weiter.
- **Wahl:**
  - Jeder Kokon (Start, Karte, Elite, gold, Boss) öffnet eine 1-aus-3-Wahl (`arsenal.roll_chest`, `evolution.chest_kind`). Automatisch vergeben wird nichts mehr.
  - Es gibt immer gültige, verschiedene Angebote. Bei vollen Waffenplätzen erscheinen nur Rang-ups und Relikte; der Start-Kokon bietet drei neue Waffen.
  - Ohne gültiges Angebot wird Bernstein erstattet.
  - Es ist immer nur eine Wahl gleichzeitig offen. Die Beutekarte zeigt das gewählte Item.
- **Farben:**
  - Zentral über `UiStyle.RARITY_TONES` / `rarity_tone` / `rarity_color` / `rarity_name` (mit Farbenblind-Tabelle).
  - Der Kartenkörper folgt der Seltenheit, die Kategorie steht als kleines Etikett oben links.
  - Band je Kokon-Art. Beutekarte, Kokon-Strahl, Relikt-Leiste und Kodex nutzen dieselben Töne.
- **Prüfung:** komplette Suite grün, `balance_regress` besteht (Sporling/Apex Median 240 s). Prüfbilder `preview_ui_mutations_tiers_a/_b`, `_cocoon_*`, `preview_arsenal17_open_*`, `preview_ui_codex_relics`.
- **Offen:**
  - Der Balance-Bot wählt Kokon-Karten weiter „wie gewürfelt“ (erste Karte), damit die Zielwerte vergleichbar bleiben. Mit gezielter Wahl (Seltenheit und Waffe) werden Runs deutlich stärker: 3 von 5 Sporling/Apex-Seeds überlebten bis zum Limit. Bei der nächsten Balance-Runde sollte der Bot wie ein guter Spieler wählen und die Zielkurven neu setzen, zusammen mit dem Punkt „Erster Apex als Klippe“.
  - Das Band über der Wahl ist immer gold (nicht in der besten Seltenheit).
  - Der grüne Kokon-Strahl ist auf Gras schwächer.
  - `hud_overlays.gd` hat noch alte Kategoriefarben.
## Nachtrag: Slots + Levelkurve (28.09.2026)

Nutzerentscheidungen: „Build-Plätze strikt begrenzt: 4 Waffen · 6 Werte · 6 Relikte“ und „man levelt zu schnell und zu oft von Anfang an“.

- **Plätze:** Waffen 4 (wie bisher, +Urmutter, +Meta-Waffenplatz), **Werte 6** verschiedene (`stats.SLOTS`, `evolution.DEFAULT_SLOTS.trait`, `meta_data.BASE_SLOTS`; alte Profile und RunConfigs mit `"trait": 14` laden weiter, die Werte-/Relikt-Plätze sind fest), **Relikte 6** verschiedene (`arsenal.RELIC_SLOTS`).
- **Nur noch Aufstiege, wenn voll:** Level-, Schrein-, Neu-würfeln-, Verbannen- und Überspringen-Angebote bieten bei 6 eigenen Werten nur Rang-ups eigener Werte unter Rang 5 (`stats.candidates(…, slots)`). Kokons bieten bei 6 eigenen Relikten nur weitere Stapel eigener Relikte, bei vollen Waffenplätzen nur Rang-ups (wie bisher). Gibt es weniger als drei gültige Karten, kommen weniger.
- **Relikt-Stapel:** höchstens 5 je Relikt (`RELIC_MAX_STACK`), Urmutter 1 (ein Zusatzplatz), Zwillingsbrut 3 (ab 3 Stapeln schon „jede 2. Teilung“). `debug_grant` ignoriert die Grenzen (Tests/Captures).
- **Alles belegt und maximal:** Ein Level-up (und ein Schrein) heilt den Anführer um 20 % der Max-LP (`evolution.MAX_HEAL_SHARE`, `take_max_heals()`, HuntWorld `_apply_max_heals`: grünes „+N“ und kurzer Hinweis „WERTE MAXIMAL · Anführer +N LP“); die XP-Leiste zeigt MAX. Ein Kokon erstattet Bernstein (Weg aus Etappe 28).
- **UI:** Eine Karte für ein NEUES Teil zeigt im Kategorie-Etikett den Platz, z. B. „WAFFE 3/4“, „RELIKT 5/6“, „WERT 5/6 · ANGRIFF“. `touch_controls._slot_text`: „Waffen x/4 · Werte x/6 · Relikte x/6“.
- **Levelkurve:** `threshold() = 60 + 25·L + 6·L²` (vorher `20 + 10·L + 1,5·L²`): erstes Level bei 60 DNA, Level 10 nach ~3435 DNA (alte Kurve dort ~Level 16).
- **Messung** (Bot, Glutmaw/Wild, Seeds 1–3, Limit 420 s, gleicher Stand, nur die Kurve getauscht; `lv` = Level bei 1:00/2:00/4:00):

  | Kurve | Seed 1 | Seed 2 | Seed 3 |
  |---|---|---|---|
  | alt | 420 s (überlebt), Lv 16, lv 3/6/11, pop120 41 | 355 s, Lv 15, lv 3/6/11, pop120 31 | 339 s, Lv 15, lv 3/5/11, pop120 20 |
  | neu | 390 s, Lv 10, lv 1/3/6, pop120 12 | 293 s, Lv 7, lv 1/3/6, pop120 26 | 349 s, Lv 9, lv 1/3/7, pop120 35 |

  `balance_regress` besteht mit der neuen Kurve (Glutmaw/Wild 150 s: Level 3–5, lv120 = 3–4, Peak 21–57; Sporling/Apex: Median 223 s, Level 5–7). Ziel war ~Level 2 bei 1:00 und ~4 bei 2:00: gemessen 1 bzw. 3–4; die Runs enden vor 7:00 mit Level 7–10. Wer das Ziel genauer treffen will: `45 + 20·L + 6·L²` (kumuliert 45/116/225/370/551 DNA für Level 1–5).
