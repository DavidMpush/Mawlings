# Etappe 23 – Audio-Durchgang für die neuen Systeme

**Ziel:** Kokons, Münzen, Power-ups, Schreine, Stammesfähigkeiten, Anführer-Treffer und die Wüste (Sandwurm, Sandmaden, Sandsturm, Treibsand) bekommen eigene, gut dosierte Klänge statt geliehener IDs. Dazu kommen eine Wüsten-Ambience und eine Wüsten-Variante der adaptiven Musik mit eigener Sandwurm-Kampfmusik.

## Abnahmekriterien
- Inventur: Ereignis → Sound, Lücken, Dopplungen, unpassende Klänge.
- Neue Sounds über den bestehenden Weg (`tools/gen_sfx.py`, `tools/gen_music.py`), Lizenzen in `assets/audio/LICENSES.md`.
- Pegel über `Sfx.RULES` (gap/voices/db), nichts nervt, mobile Lautstärke im Blick.
- Anbindung nur in den freigegebenen Dateien; nötige `hunt_world.gd`-Hooks als Liste bzw. Patch.
- Tests `sfx`, `sfx_hooks` und `music` erweitert und grün, alle Läufe mit `--audio-driver Dummy`.

## Inventur (vorher → nachher)

| Ereignis | vorher | nachher | Ort |
|---|---|---|---|
| Kokon öffnet (Seide reißt) | `split` (Zellteilung) | `cocoon_open` | `chests.gd` |
| Kokon gewöhnlich / selten / episch / legendär | `pickup` / `mutate` / `alpha_core` / `evolve` (+`fanfare`) | `cocoon_common` / `_rare` / `_epic` / `_legendary` (+`fanfare`), steigend feierlich | `chests.gd` |
| Kokon zu teuer | `warn` (Gegner-Telegraph!) | `cocoon_denied` (dumpfes Doppelklopfen) | `chests.gd` |
| Power-up aufnehmen | `alpha_core` bzw. `lure` | `powerup_take` | `powerups.gd` |
| Power-up läuft aus | – | `powerup_end` (leise, fallend) | `powerups.gd` |
| Schrein lädt | – | `shrine_tick`, 8 Stufen pentatonisch steigend (Tonhöhe über `play(..., pitch)`) | `shrines.gd` |
| Schrein voll | `milestone` (wie Schwarm-Meilenstein) | `shrine_done` (Chor-Akkord + Glocke) | `shrines.gd` |
| Fähigkeit bereit | – | `ability_ready` (kleines Glut-Glöckchen) | `abilities.gd` |
| Fähigkeiten (Glutsprung, Sporenbombe, Panzerstoß, Hetzjagd, Säureschwall, Schattenschleier) | `leaper_windup`+`stomp`, `mutate`, `quake`, `rally`, `split`, `migration_whoosh` | `ability_<id>` (+`ability_land`) | **Hook** `hunt_world.gd` (`ABILITY_SFX`) |
| Bernstein-Münze einsammeln | `collect_bio` (zählt als Kristall) | `collect_coin` in derselben steigenden Tonkette | **Hook** `hunt_world.gd` (`_collect_sound`) |
| Anführer-Treffer | `leader_hit` (immer gleich) | `leader_hit` / `leader_hit_heavy` ab 2 LP | **Hook** `hunt_world.gd` |
| Lebensraub-/Regeneration-Heilung | `regen` −9,5 dB, Abstand 400 ms | `regen` −12,5 dB, 900 ms (dezent) | `sfx.gd` |
| Anführer kritisch (1 LP) | – (`heartbeat` gilt nur für das letzte Tier, `swarm.gd`) | Loop `leader_critical` (Herzschlag-Dateien, leiser) | **Hook** `hunt_world.gd` |
| Sandwurm gräbt | – | Loop `sandworm_dig`, solange er vergraben ist | `desert_run.gd` |
| Sandwurm Durchbruch / Schwanzfeger | nur generisch `quake`/`warn` (Anlauf) + `stomp` | zusätzlich `sandworm_breach` / `sandworm_sweep` beim Schlag | `desert_run.gd` |
| Sandmaden brechen aus | – | `sandgrub_burst` | `desert_run.gd` |
| Sandsturm | – | Loop `sandstorm`, Lautstärke = Sturmstärke | `desert_run.gd` |
| Treibsand | – | Loop `quicksand` unter dem Schwarm | `desert_run.gd` |
| Wüsten-Ambience | Dschungel-Loop | `ambience_desert`, Überblendung 1,5 s (`Sfx.set_ambience`) | `sfx.gd`, `desert_run.gd` |
| Musik Wüste / Sandwurm | klassische Stems | eigener Stem-Satz `desert_*` (D-Hidschas), `desert_boss` = Sandwurm-Kampf (`Music.set_biome`) | `music.gd`, `desert_run.gd` |

Weitere Dopplungen, die bleiben: `mutate` für Mutations- und Kokon-Beutewahl (passt: Auswahl bestätigt), `kill` beim Zerbrechen der Bernstein-Hügel, `split` für die Zellteilung. Glutsumpf und Lava-Ausbrüche haben noch keine eigene Ambience bzw. keinen eigenen Klang.

## Umsetzung
- **`tools/gen_sfx.py`**: 23 neue Einmal-Sounds (2–3 Varianten) und 4 Loops (`SOUNDS_23`). Neu ist der Schalter `--only=a,b` (erzeugt nur diese IDs). Die Nahtprüfung für Rausch-Loops vergleicht jetzt mit dem typischen Nachbarschritt, wie in `gen_music.py`. Bestehende Dateien bleiben bitgleich.
- **Pegel**: gemessen als lautestes 300-ms-Fenster und an die Nachbarn angeglichen (Dateipegel + `db`):
  - Sammelketten ~−27 dB (Münze wie Kristall)
  - Kokon-Momente −22 bis −17 dB, steigend mit der Seltenheit
  - Fähigkeiten ~−19 dB
  - Wüsten-Schläge −15 bis −17 dB
  - Loops −20 bis −26 dB, der Sturm wird zusätzlich mit seiner Stärke skaliert
  - Kokon- und Fähigkeitsklänge haben 250–300 ms Abstand und 1 Stimme, `ability_ready` 800 ms, `shrine_tick` 180 ms.
- **`sfx.gd`**: neue RULES und LOOP_RULES. Neu sind `AMBIENCES`, `set_ambience(id)` (Überblendung in `_process`), `ambience_id()` und `ambience_gain()`. `SOURCES.leader_critical = heartbeat`.
- **`music.gd`**: `set_biome("verdant"|"desert")` blendet den Stem-Satz über FADE_SECONDS; `desert_ids()`, `desert_target()`, `desert_gain()`, `biome()`. Im Stil „v1“ gibt es keine Wüsten-Variante, die Nutzer-Loops laufen dort weiter.
- **`tools/gen_music.py`**: `desert_base` / `desert_tension` / `desert_flood` / `desert_boss`, 96 BPM, 8 Takte (20 s), gleiches Raster wie die klassischen Stems.
  - Tonart D-Hidschas (phrygisch-dominant).
  - Instrumente: Rahmentrommel (Doum/Tek, Maqsum-Muster), Oud-Zupfer, Bordun, Ney.
  - Flut: Warnmotiv D–Es–Fis–Es.
  - Boss: Taiko, tiefes Blech und Ney-Klage auf der übermäßigen Sekunde.
  - Schalter `--only=`.
- **`desert_run.gd`**: Audio-Teil.
  - Setzt jeden Schritt Ambience und Musik-Biom.
  - Steuert die Loops Sturm, Graben und Treibsand; spielt die Worm-Schläge beim STRIKE-Wechsel und den Maden-Ausbruch.
  - Wächter in `_process`: Macht die Welt in einem Frame keinen Schritt (Pause, Wahl, Migration, Aussterben), verstummen die Loops. Das gilt auch für `clear()` und beim Verlassen der Wüste.
- **`chests.gd`, `powerups.gd`, `shrines.gd`, `abilities.gd`**: nur Sound-Zeilen, keine Werte.

## Hooks in `hunt_world.gd` (tabu während der Balance-Runde)
Fertiger Patch gegen den aktuellen Stand: `hunt_world_etappe23.patch`. Er liegt im Scratchpad und ist parse-geprüft. Inhalt:
1. `ABILITY_SFX` auf `ability_glutsprung` (+`ability_land` 0,33 s später), `ability_sporenbombe`, `ability_panzerstoss`, `ability_hetzjagd`, `ability_saeureschwall`, `ability_schattenschleier`.
2. `_collect_sound(bio, dna, coins)`: Münzen spielen `collect_coin` in derselben Kette. Der Aufruf übergibt `got.coins` getrennt.
3. `_apply_hit`: ab `leader_loss >= 2` spielt `leader_hit_heavy` (70 ms Vibration), sonst `leader_hit`.
4. `_leader_critical(on)` und `_leader_in_danger()`: Der Loop `leader_critical` läuft bei 1 LP (max. > 1). An bei jedem `_audio_step`, aus bei Pause, Reset und Aussterben.

Bis der Patch eingespielt ist, klingen die Fähigkeiten weiter geliehen und Münzen wie Kristalle. Die Klänge sind vorhanden, die Tests prüfen Dateien und Regeln.

## Tests
- `tests/sfx.gd`: prüft die neuen IDs, jeweils eigene Dateien (nicht über SOURCES geliehen), mindestens 2 Varianten, Pegel im Rahmen, Münze leiser als die Kokons, die neuen Loops und die Ambience-Überblendung Dschungel → Wüste → Dschungel.
- `tests/sfx_hooks.gd`: prüft, dass jedes neue Ereignis seinen Klang auslöst:
  - Kokon zu teuer, öffnen und alle vier Seltenheiten (legendär mit Fanfare)
  - Power-up nehmen und auslaufen
  - Schrein-Ticks und Schrein voll
  - Fähigkeit bereit
  - Wüstenstart mit Maden, Sturm- und Grab-Loop sowie Durchbruch
  - Loops still, wenn die Welt ruht
  - Wüsten-Ambience und -Musik, zurück zum Dschungel
- `tests/music.gd`: prüft den Wüsten-Satz (gleiche Länge), Hin- und Rückblende, Sandwurm-Kampf (boss + tension), unbekanntes Biom und Stil v1 ohne Wüste.

## Offen
- Hooks aus `hunt_world.gd` einspielen (siehe oben).
- Hörprobe am Gerät (S25) und Pegel-Feinschliff nach Gehör. Die Werte hier sind gemessen, nicht gehört.
- ~~Glutsumpf-Ambience und Lava-Ausbruch-Klang~~ (erledigt in Etappe 24). Der Musikstil „v1“ hat keine Wüsten-Variante.
- Größe: +5,5 MB SFX-WAV und +3,4 MB Musik-WAV im Projekt; der Export komprimiert sie.
