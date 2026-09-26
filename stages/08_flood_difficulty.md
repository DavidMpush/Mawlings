# Etappe 08 – „Die Flut“ und höhere Schwierigkeit

Nutzerfeedback: „Aktuell ist die Schwierigkeit noch sehr sehr leicht“; gewünscht ist eine Megabonk-artige Endwelle, die exponentiell schwerer wird, damit Runs nicht ewig gehen; alle Gegner sollen angreifen, keine freie Beute. Regeln in `DESIGN_BRIEF.md` ergänzt.

## Abnahmekriterien
1. **Horde (HORDE):** neuer Massen-Gegner „Moorbrut“ (kleine, schnelle Kiefer-Kreaturen, gedeckelt z. B. 160 aktiv), als ein MultiMesh gezeichnet (Leistung!), jagt den Schwarm, **Kontakt-Biss** tötet Mawlings, die sie berühren (Anteil wie Treffer pro Tier, pro Tier Abklingzeit), wenig HP → Nahkampf und Flächenformen räumen auf; Tod gibt kleine Biomasse (über normale Kadaver, gebündelt, Ressourcenregel) und DNA-Krümel. Attack-Forms treffen Horde (Aura, Projektile, Landungen, Pfützen, Stacheln).
2. **Flut (FLOOD):** Startzeit je Schwierigkeit (Wild 5:00, Brutal 4:00, Apex 3:00), klare Ankündigung 10 s vorher (Banner „DIE FLUT KOMMT“, Countdown, Sound), dann Wellen aus Ringen um den Schwarm; Stärke (HP, Schaden, Tempo, Spawnrate bis Deckel) verdoppelt sich ~alle 40 s; reguläre Gegner und Bosse laufen weiter. HUD zeigt Flutstufe/Zeit seit Flut.
3. **Alle greifen an:** Jäger/Skitter/Leaper ohne Leerlaufphasen (sofort Verfolgung, kürzere Erholung), Nibbler wehren sich mit kurzem, angekündigtem Schnapp-Biss (kleiner Kreis, kleine Verluste) und fliehen nicht nur.
4. **Schwierigkeit/Balance:** Bot (0,45 s Reaktion, 12 % übersehen) Median-Tod: Wild 6:30–8:30 (max < 11 min), Brutal 5:00–6:30, Apex 3:30–4:30; vor der Flut spürbarer Druck (Wild: Median-Population bei 2:00 ≤ 160, nicht dauernd 250). Kein Build/Stamm dominiert (Spreizung ≤ ~40 %).
5. **Leistung:** Worst Case mit voller Flut auf Desktop ≤ 5 ms (`tools/perf.ps1`, neue Szene `flood`).
6. Alle Tests grün, neue Tests `horde`, `flood`; Captures der Flut.

## Dateibesitz
- HORDE: neu `scripts/horde.gd` (API siehe unten), `scripts/attack_forms.gd` (nur Treffer-Hook für die Horde), `tests/horde.gd`, `tests/capture_horde.gd`
- FLOOD: `scripts/hunt_world.gd`, `scripts/tuning.gd`, `scripts/hunter.gd`, `scripts/skitter.gd`, `scripts/mire_leaper.gd`, `scripts/prey.gd`, `scripts/meta/meta_data.gd` (Schwierigkeitszahlen, Flut-Startzeiten), neu `scripts/ui/hud_flood.gd`, `tests/flood.gd`, `tests/balance_sim.gd`, `tests/endless_playthrough.gd`, `tools/balance.ps1`, `tests/perf_bench.gd` (Szene `flood`), bestehende Tests anpassen, falls Verhalten absichtlich geändert
- Orchestrator: `tools/test.ps1`, Doku

## Horde-API (Vertrag)
```gdscript
# scripts/horde.gd – Node3D, Kind von HuntWorld
func setup(world: Node3D, swarm: Node3D, arena: Node3D) -> void
func spawn_ring(center: Vector3, count: int, radius: float, stats: Dictionary) -> int   # stats: {hp, speed, bite, bite_cooldown}
func step(delta: float, swarm_points: PackedVector3Array) -> Dictionary               # {bitten_indices: PackedInt32Array, losses: int} – welche Mawlings (Indizes in swarm_points) gebissen wurden
func damage_circle(center: Vector3, radius: float, amount: float) -> int               # Flächenschaden, gibt Kills zurück
func damage_nearest(point: Vector3, max_range: float, amount: float) -> Vector3        # für Projektile; Vector3.INF wenn keiner
func melee(swarm_points: PackedVector3Array, reach: float, dps: float, delta: float) -> int
func take_kills() -> Array                                                            # [{position, biomass, dna}] seit letztem Aufruf
func count() -> int
func nearest(point: Vector3) -> Vector3
func clear() -> void
```

## Ergebnis (27.09.2026, Teil 1)

- **Horde „Moorbrut“:** `horde.gd`, ein MultiMesh (+4 Draw Calls), max. 160, fast schwarz-oliv mit giftgelbem Rand (auch bei Deuteranopie/Protanopie vom Schwarm getrennt), Kontaktbiss 0,55 m mit Abklingzeit, alle Angriffsformen treffen sie.
- **Die Flut:** Start Wild 300 s / Brutal 240 s / Apex 180 s, 10 s Ankündigung (Banner, Countdown, Sound, Vibration), Stärke ×2 alle 40 s (Tempo gedeckelt auf 82 % des Schwarms), Wellen alle 3 s bis 40 Tiere, Deckel 160; HUD-Chip „FLUT · STUFE n“.
- **Alle greifen an:** kürzere Erholungen, schneller Anflug; Nibbler schnappen angekündigt zurück (1,2 m, 0,6 s Warnung).
- **Schwierigkeit:** Wild-Druck ×2 alle 80 s, Jägerschaden 8, Biomasse je Kadaver −40–70 %, Brutal/Apex mit Einlauframpe 75 s. Bot-Median: Wild 409 s (Pop bei 2:00: 149), Brutal 334 s, Apex 254 s – alle im Ziel.
- **Tests:** 25/25 grün (neu: horde, flood). Playthrough: 109 Tiere nach 120 s, 82 Verluste (vorher 250/50).

Offen (Teil 2): Leistung – Worst Case ohne Flut 6,8 ms (vorher 3,97), volle Flut 9,9 ms, `horde.step` ~1,9 ms; blassrosa Biss-Effekte verdecken den Schwarm; Nibbler-Schnappkreis teils verdeckt; Früh-Tode auf Brutal/Apex beim greedy-Bot.
