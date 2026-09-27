# Etappe 09 – Einzelstart, Anführer, Zellteilung

Nutzerentscheidung (27.09.2026): Start mit **einem** Mawling für alle Stämme; jedes neue Tier soll sich hart verdient und befriedigend anfühlen, jeder Verlust soll wehtun. Der erste Mawling ist ein **Anführer mit Lebensleiste**; stirbt er, übernimmt ein anderes Tier mit weniger Leben; der Run endet weiter nur durch Aussterben. Wachstum sieht aus wie **Zellteilung** (kein Ei-Schlüpfen). Die Apex-Einbindung rückt auf Etappe 10.

## Abnahmekriterien
1. **Einzelstart:** alle Stämme `start_population = 1`; Brutkammer „Brutgröße“ +1 je Rang (max. 4); Onboarding/Tests angepasst.
2. **Anführer:** `swarm.units[0]` ist immer der Anführer; Lebenspunkte `leader_max_hp` (Basis 3, Meta/Stamm-Boni möglich), Treffer auf Flächen/Horde-Bisse, die den Anführer einschließen, kosten 1 LP statt Tod + 1,2 s Unverwundbarkeit (nur Anführer); andere Tiere in der Zone sterben normal. LP 0 → Anführer stirbt; hat der Schwarm weitere Tiere, wird das nächste Anführer mit `max(1, alter_max − 1)` LP (voll geheilt), sonst Aussterben. Kein Heilen außer: +1 LP bei jedem 25er-Meilenstein (bis Max).
3. **Früher Druck, fair:** erste Bedrohung (Jäger) frühestens bei Population ≥ 4 oder nach 50 s; Nibbler-Schnapp trifft den einzelnen Anführer (LP), tötet ihn aber nicht in einem Zug. Wachstumskurve (Bot, Wild, Median): 1:00 → 6–14, 2:00 → 25–55, Flutbeginn → 80–160. Todeskurve aus Etappe 08 bleibt im Ziel (Wild 390–510 s, Brutal 300–390 s, Apex 210–270 s).
4. **Rückeroberung:** gefallene Mawlings hinterlassen kleine Biomasse (gebündelte Kadaver, Ressourcenregel), die man zurückholen kann.
5. **Gefühl beim Wachsen (GEFÜHL):** Zellteilung – ein bestehendes Tier bläht sich, schnürt sich ein, teilt sich in zwei; das neue gleitet in die Formation; Plopp-Sound je Teilung (gedrosselt), Zähler „+1“-Hüpfer; Meilensteine 5/10/25/50/100/250 mit Banner, Sound, Leuchten; bei kleinem Schwarm größere, individuellere Tiere.
6. **Gefühl beim Verlieren (GEFÜHL):** Hitstop proportional zum Verlustanteil (bei 1 von 3 deutlich, bei 1 von 200 kaum), Todesschrei (gedrosselt), roter Zähler-Puls, Anführer-Treffer mit eigener Rückmeldung (LP-Pip bricht), beim letzten Tier Herzschlag + rote Vignette; neue SFX (Teilung, Meilenstein, Todesschrei, Herzschlag, Anführer-Treffer, Anführer-Wechsel).
7. Alle Tests grün (angepasst), Balance-Harness auf neuer Kurve, Captures der neuen Momente.

## Schnittstellen (verbindlich)
`scripts/swarm.gd` (GEFÜHL implementiert, KERN nutzt):
```gdscript
const LEADER := 0                               # Anführer ist immer units[0]
func set_leader_state(hp: int, max_hp: int, invulnerable: bool) -> void   # Optik (Pips, Krone, Glühen, Blinken)
func leader_hit(impact: Vector3) -> void        # Rückmeldung Anführer-Treffer
func promote_leader() -> void                   # nach Tod des Anführers: nächstes Tier wird units[0] (Übernahme-Effekt)
func split_new_units(count: int) -> void        # statt Schlüpfen: Teilungsanimation für die zuletzt hinzugefügten Tiere
```
Bestehend bleibt: `set_population(value, animate)`, `unit_world_points()` (Index 0 = Anführer), `prefer_removal(indices)` – **darf Index 0 nie entfernen**, solange Population > 0; KERN entscheidet über Anführer-Tod und ruft `promote_leader()`.
`scripts/main.gd` (GEFÜHL): `func hitstop(strength: float) -> void` (0..1, echte Zeit ≤ 0,12 s, Tests/headless aus).
HUD-Variablen (KERN setzt über `hud.set(...)`, GEFÜHL zeichnet): `leader_hp`, `leader_max_hp`, `leader_invulnerable`, `milestone` (Zahl, 0 = keiner), `last_loss_fraction`.
Sfx-IDs (GEFÜHL erzeugt): `split`, `milestone`, `death`, `heartbeat`, `leader_hit`, `leader_swap`.

## Dateibesitz
- KERN: `scripts/hunt_world.gd`, `scripts/run_model.gd`, `scripts/tuning.gd`, `scripts/meta/meta_data.gd`, `scripts/meta/profile.gd` (nur Werte), `scripts/prey.gd`, `scripts/onboarding.gd` (Tipp „Anführer“), `tests/*` außer den GEFÜHL-Captures, `tools/balance.ps1`
- GEFÜHL: `scripts/swarm.gd`, `shaders/creature_anim.gdshader`, `scripts/main.gd`, `scripts/sfx.gd`, `tools/gen_sfx.py`, `assets/audio/*`, `scripts/ui/hud_top.gd`, `scripts/ui/hud_overlays.gd`, neu `tests/capture_lone.gd`

## Ergebnis

### Integration Kadaver-Designs, Musik, Eruptionen + offene Punkte
- `hunt_world.gd`: alter Kadaver-MultiMesh-Block ersetzt durch Knoten `corpse_view` (`corpse_visuals.gd`; `add`/`set_fill`/`remove`, Reset über Neuaufbau). Musik über Main/`Music`: `set_intensity` pro Schritt, Stinger `flood`/`boss`/`king`/`extinct` + `stop()` beim Aussterben. `Eruptions` als Kind von HuntWorld (Arena explizit gesetzt), Einschläge über `_resolve_area_hit` (Anführer-LP-Regel), Hinweis „LAVA BRICHT AUS!“ während der Warnung; nur Glutsumpf.
- Sounds an einer Stelle: `leader_hit`, `leader_swap`, `milestone`, `death` nur aus HuntWorld; Teilungs-Plopp (zur Einschnürung synchron) und Herzschlag-Loop nur aus `swarm.gd`.
- Anführer: eigener Folgefaktor (22/s), keine Nachzieh-Verschiebung, kaum Wander → steht in der Schwarmmitte. (Eine zusätzliche Verdichtung kleiner Schwärme wurde verworfen: mehr Tiere in Jägerringen, Wild-Regress fiel auf 88 s.)
- Mire Leaper: kein Rückzug mehr; nach der Erschöpfung sofort STALK mit `LEAPER_CHASE_LURK_SECONDS` 0,8 s, läuft bis `LEAPER_CONTACT_DISTANCE` 1,8 m heran (Test `leaper` angepasst).
- Menü: „Invalid polygon data“ behoben (`ui_kit._rounded_points` entfernt doppelte Punkte bei Pillen; Chronik-Pille nur bei sinnvoller Größe).
- Tests: `tools/test.ps1` komplett grün inkl. Playthrough und Balance-Regress; `eruptions` prüft zusätzlich den HuntWorld-Trefferpfad.
