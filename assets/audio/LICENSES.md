# Audio-Herkunft und Lizenzen

Alle Dateien in `assets/audio/` sind entweder **prozedural** erzeugt (`tools/gen_sfx.py`, eigene Synthese, keine Fremdrechte) oder aus **vom Nutzer gelieferten Aufnahmen** abgeleitet (`tools/import_user_sfx.py`). Die Originale liegen unverändert in `C:\Users\vrxby\Documents\Codex\Swarm\Design\Sounds\` und werden **nicht** ins Repository oder den Export kopiert; im Spiel liegen nur gekürzte, gefilterte, in Mono umgewandelte Varianten.

## Mixkit-Dateien (Mixkit Sound Effects Free License)

Quelle: https://mixkit.co/free-sound-effects/ – Mixkit-Lizenz: kostenlos in kommerziellen und nicht-kommerziellen Projekten (auch Spielen) nutzbar, ohne Namensnennung; **nicht** als eigenständige Sound-Dateien oder in einer Sound-Bibliothek weitergeben oder verkaufen. Im Spiel eingebettet (Export komprimiert QOA) ist erlaubt; die Dateien in diesem Repo daher nicht separat veröffentlichen.

| Quelldatei | Spiel-IDs |
|---|---|
| `mixkit-aggressive-beast-roar-13.wav` | `boss_roar_1..2` |
| `mixkit-alien-technology-hum-2134.wav` | `portal_open_1..2` |
| `mixkit-completion-of-a-level-2063.wav` | `milestone_1..2` |
| `mixkit-epic-orchestra-transition-2290.wav` | `migration_whoosh_1` |
| `mixkit-game-blood-pop-slide-2363.wav` | `kill_1..4`, `death_1..3` |
| `mixkit-mechanical-crate-pick-up-3154.wav` | `alpha_core_1..2` |
| `mixkit-mystwrious-bass-pulse-2298.wav` | `quake_1..2` |
| `mixkit-ominous-drums-227.wav` | `flood_warn_1..2` |
| `mixkit-sci-fi-positive-notification-266.wav` | `mutate_1..3` |
| `mixkit-sword-magic-drag-3009.wav` | `evolve_1..2` |
| `mixkit-technological-futuristic-hum-2133.wav` | `portal_hum_1` (Loop) |
| `mixkit-trumpet-fanfare-2293.wav` | `fanfare_1` |
| `mixkit-video-game-health-recharge-2837.wav` | `regen_1..2` |
| `mixkit-retro-game-emergency-alarm-1000.wav` | nicht verwendet (sehr schrill, Energie um 17 kHz) |

## Weitere Stock-Sounds (vom Nutzer bestätigt am 27.09.2026)

Der Nutzer hat bestätigt, dass alle gelieferten Sounds lizenzfreie Stock-Sounds sind. Bei einer Veröffentlichung die genaue Quelle je Datei nachtragen.

| Quelldatei | Spiel-IDs | Status |
|---|---|---|
| `soft-quick-sound-of-slime-sk5tldnt.wav` | `split_1..4` | Stock, lizenzfrei (Nutzerangabe) |
| `merge-3-mobile-game-short-7ir6tzte.wav` | `grow_1..3` | Stock, lizenzfrei (Nutzerangabe) |
| `sling-streching-sfx-for-m-vpiblugt.wav` | `leaper_windup_1..2` | Stock, lizenzfrei (Nutzerangabe) |

## Prozedural (eigene Synthese)

`bite`, `hit`, `warn`, `stomp`, `extinct`, `pickup`, `ui`, `leader_hit`, `leader_swap`, `heartbeat`, `ambience_jungle` sowie die Musik unter `assets/music/` (`tools/gen_music.py`).
