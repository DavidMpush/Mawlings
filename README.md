# MAWLINGS — Godot-Neustart

Eigenständiges Projekt mit Godot **4.7.2**. Projektordner: `C:\Users\vrxby\Documents\Codex\Godot\Mawlings`. Das frühere Unity-Projekt wird nicht verwendet oder verändert.

## Starten

In Godot diesen Ordner als Projekt importieren und **F6** für die Hauptszene oder **F5** für das Projekt drücken. Alternativ:

```powershell
& 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64.exe' --path 'C:\Users\vrxby\Documents\Codex\Godot\Mawlings'
```

Der aktuelle Stand enthält eine endlos nachladende, offene 3D-Arena und 25 Mawlings zum Start. **WASD/Pfeiltasten** bewegen den Schwarm, **Leertaste** hält Rally. Für Touch liegen Bewegung rechts und Rally links. Breite sandige Laufwege und wenige Steinformationen geben Orientierung. Die Steine begrenzen die Bewegung des Schwarms, der Beute und der Jäger; zwischen ihnen bleibt viel freier Raum. Flache Wasserstellen und Blätter sind begehbare Dekoration. Die Arena wiederholt keine feste Karte: Ihre Abschnitte entstehen an festen Koordinaten und werden in der Nähe des Spielers sichtbar gehalten.

Die drei türkisfarbenen Nibbler fliehen vor dem Schwarm. In Nähe greift er automatisch an; Rally verstärkt den Angriff und verdichtet die Formation. Besiegte Beute hinterlässt einen goldenen Kadaver mit 12 Biomasse. In Kadavernähe wird Biomasse nach und nach geerntet; je 2 Biomasse entsteht ein Mawling. Weggehen pausiert die Ernte, der Rest bleibt an Ort und Stelle. Bei 250 Population bleibt übrige Biomasse ebenfalls liegen. Bis zu 120 Mawlings werden als einzelne Modelle dargestellt; die Population ist davon getrennt. Das vom Nutzer bereitgestellte `assets/source/mawling/Mawling.glb` ist als farblich vereinfachtes `assets/gameplay/characters/Mawling_game.glb` im Schwarm eingebunden. Nach einer Jagd erscheinen wieder Nibbler.

Nach 18 Sekunden kommt der erste violette **Jäger**. Ein blauer Ring kündigt sein Erscheinen an. Sein roter Angriffsring bleibt während der 1,25 Sekunden langen Warnung fest an der markierten Position: rechtzeitig herauslaufen. Treffer kosten Mawlings und erzeugen eine Verlustanzeige. Rally erhöht den Bissschaden; ein besiegter Jäger hinterlässt 26 Biomasse. Bei höherem Druck werden Jäger schneller und markieren Flächen vor der aktuellen Laufrichtung. Richtungswechsel bleiben möglich, da sie die Warnfläche anschließend nicht nachführen.

Ab etwa 45 Sekunden kommt der blau-pinke **Skitter** hinzu. Er markiert eine gerade, gelbe Sprintbahn für eine Sekunde und schießt danach entlang dieser festen Spur. Seitlich ausweichen; Steine stoppen die Sprintbahn und können Deckung bieten. Skitter hinterlassen 18 Biomasse und geben 15 DNA. Im HUD stehen aktive Jäger und Skitter.

Nach etwa **90 Sekunden** erscheint der große **Bog King**. Seine eigene Lebensleiste steht unter der oberen HUD-Zeile. Bei Nähe markiert er einen roten Kreis an seiner Position und stampft nach 1,8 Sekunden; aus dem Kreis herauslaufen, danach während seiner Erholung angreifen. Ein besiegter Bog King gibt 50 DNA und hinterlässt 110 dauerhafte Biomasse. Nach 180 weiteren Spielsekunden kann der nächste erscheinen. Die Spielversion des vom Nutzer gelieferten Modells hat 8.000 statt 50.000 Dreiecke und liegt getrennt vom Original unter `assets/gameplay/characters/`. Das Original und seine Texturdateien liegen unter `assets/source/bog_king/`; die Ordnerstruktur steht in [assets/README.md](assets/README.md).

**Bewegung und Rückmeldung (Etappe 01):** Jedes Mawling dreht sich in seine eigene Laufrichtung, hüpft und watschelt abhängig vom Tempo, atmet im Stand und folgt der Formation mit eigener Trägheit, sodass sich der Schwarm beim Laufen streckt. Weiche Schatten (eine MultiMesh) und ein korallfarbener Bodenhalo zeigen, wo der Schwarm steht; Rally verdichtet ihn sichtbar mit hellerem Ring. Beim Angriff drängen die Tiere zur Beute und beißen, beim Ernten picken sie am Kadaver. Neue Mawlings schlüpfen aus der Mitte; bei Treffern werden verlorene Tiere weggeschleudert, Überlebende weggestoßen, der Schwarm blitzt und die Kamera wackelt. Der Bog King hat eine helle, zustandsabhängige Randkontur (lila jagend, orange warnend, gold erschöpft), taucht aus dem Boden auf, stapft mit Schrittstaub, bäumt sich während der Warnung auf und stampft mit Schockwelle. Sein Warnkreis füllt sich von innen bis zum Rand und zeigt so die Restzeit. Danach ist er erschöpft („JETZT ANGREIFEN“). Außerhalb des Bildes zeigt ein Kronenpfeil am Rand zu ihm. Die Kamera zoomt bei großem Schwarm und nahem Boss etwas heraus. Alle Effekte sind rein visuell; Trefferbereiche, Zeiten und Schaden sind unverändert.

Der Zeitdruck verdoppelt sich alle 90 Spielsekunden und erhöht Angriffsleistung, neue Gegnergesundheit und Spawnrate. Maximal zwölf Jäger, drei Skitter und fünf Nibbler sind gleichzeitig aktiv. **Nur Aussterben beendet den Run**; es gibt kein Zeitlimit. Die Ergebnisanzeige zeigt Überlebenszeit, höchste Population, Kills und geerntete Biomasse. Mit **NEUER RUN**, **R** oder **Enter** neu starten. **P / Escape** oder der Pause-Button pausiert; bei Fokusverlust pausiert das Spiel ebenfalls. Die Kadaver bleiben innerhalb des aktiven Runs erhalten; Neustart setzt den gesamten Run zurück.

Das ist ein spielbarer **Survival-Mechanik-Prototyp** mit vorläufigen Werten und Gegner-/Weltformen. Das Mawling- und Bog-King-Modell sowie das HUD haben einen ersten Design-Pass. Angriff, Ernte und Flächentreffer verwenden vorerst die Entfernung zum Schwarmzentrum; individuelle Mawlings haben keine eigene Kampf-KI. Endgültige Animationen und Grafik fehlen noch. Zentrale Survival-Werte stehen in `scripts/tuning.gd`.

Der Designstand, die Asset-Aufbereitung und die nächsten Stil-Schritte stehen im [Art- und UI-Plan](ART_UI_PLAN.md).

## Evolution im Run

Nibbler geben 10 DNA, Skitter 15 DNA, Jäger 20 DNA. Ab 20 DNA öffnet sich eine Auswahl aus bis zu drei verschiedenen Mutationen. Antippen oder **1 / 2 / 3** wählt eine Verbesserung; währenddessen stehen Kampf, Ernte, Spawns und Run-Zeit still. Jede weitere Auswahl kostet 10 DNA mehr. Überschüsse bleiben erhalten. Es gibt sechs Mutationen mit jeweils maximal drei Rängen:

| Mutation | Effekt je Rang |
|---|---|
| Reißzähne | +25 % Angriffsschaden |
| Schnelle Brut | +30 % Erntetempo |
| Vielfraß | +25 % Biomasse aus zukünftigen Kills |
| Rudelinstinkt | +20 % Schaden während Rally |
| Fluchtreflex | −10 Prozentpunkte Verluste ohne Rally |
| Knochenpanzer | −10 Prozentpunkte Verluste |

Ränge derselben Mutation addieren sich. Die zwei Angriffsboni multiplizieren sich; Schutz addiert sich bis maximal 60 %, Treffer kosten mindestens ein Tier. Alte Kadaver ändern ihren Biomassewert nicht. Pause und Ergebnis zeigen den gewählten Build. Neustart setzt DNA und Mutationen zurück. Nach allen 18 Rängen läuft der Survival-Run weiter.

Prüfung dieser Etappe: [Evolution](EVOLUTION_VERIFICATION.md).

## Arbeitsweise ab dem Neustart

Wir arbeiten ausdrücklich in **größeren, zusammenhängenden Etappen**. Eine Etappe umfasst den spielbaren Ablauf, notwendiges HUD und Bedienung, Fehlerkorrekturen sowie Funktions- und Sichtprüfung. Keine Übergabe nach jeder kleinen Funktion und keine wiederholten Freigaben für bereits vereinbarte Arbeit. Diese Vorgabe ist auch in `AGENTS.md` für die weitere Zusammenarbeit festgehalten. Die [Spielregeln](DESIGN_BRIEF.md) bleiben stabil.

Alle automatisierten Prüfungen auf einmal (kompakte Ausgabe, Exit-Code ≠ 0 bei Fehlern) und alle Prüfbilder aus der echten Kamera:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/capture.ps1
```

Einzelne Prüfungen mit der installierten Godot-Konsole (zusätzlich `tests/motion.gd` für Etappe 01):

```powershell
& 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\Users\vrxby\Documents\Codex\Godot\Mawlings' --script 'res://tests/smoke.gd'
& 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\Users\vrxby\Documents\Codex\Godot\Mawlings' --script 'res://tests/run_model.gd'
& 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\Users\vrxby\Documents\Codex\Godot\Mawlings' --script 'res://tests/hunt_flow.gd'
& 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\Users\vrxby\Documents\Codex\Godot\Mawlings' --script 'res://tests/survival.gd'
& 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\Users\vrxby\Documents\Codex\Godot\Mawlings' --script 'res://tests/evolution.gd'
& 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\Users\vrxby\Documents\Codex\Godot\Mawlings' --script 'res://tests/arena.gd'
& 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\Users\vrxby\Documents\Codex\Godot\Mawlings' --script 'res://tests/skitter.gd'
& 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\Users\vrxby\Documents\Codex\Godot\Mawlings' --script 'res://tests/model_budget.gd'
& 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\Users\vrxby\Documents\Codex\Godot\Mawlings' --script 'res://tests/boss.gd'
& 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --fixed-fps 60 --path 'C:\Users\vrxby\Documents\Codex\Godot\Mawlings' --script 'res://tests/endless_playthrough.gd'
```

Prüfstand und Grenzen: [Survival-Prüfung](SURVIVAL_VERIFICATION.md), [Evolution](EVOLUTION_VERIFICATION.md), [Arena](ARENA_VERIFICATION.md) , [Skitter](SKITTER_VERIFICATION.md) und [Etappe 01 – Bewegung und Lesbarkeit](stages/01_motion_readability.md). Der Arbeitsablauf mit Claude Code steht in [stages/README.md](stages/README.md).

Projektdateien liegen unter `scenes/` und `scripts/`; `.godot/` wird nicht versioniert. Das Projekt besitzt ein eigenes Git-Repository, damit Dateien außerhalb dieses Ordners nicht dazugehören.
