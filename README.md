# MAWLINGS — Godot-Neustart

Eigenständiges Projekt mit Godot **4.7.2**. Projektordner: `C:\Users\vrxby\Documents\Codex\Godot\Mawlings`. Das frühere Unity-Projekt wird nicht verwendet oder verändert.

## Starten

In Godot diesen Ordner als Projekt importieren und **F6** für die Hauptszene oder **F5** für das Projekt drücken. Alternativ:

```powershell
& 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64.exe' --path 'C:\Users\vrxby\Documents\Codex\Godot\Mawlings'
```

Der aktuelle Stand enthält eine offene 3D-Testfläche und 25 Mawlings zum Start. **WASD/Pfeiltasten** bewegen den Schwarm, **Leertaste** hält Rally. Für Touch liegen Bewegung rechts und Rally links. Die Inseln sind Orientierungspunkte ohne Kollision.

Die drei türkisfarbenen Nibbler fliehen vor dem Schwarm. In Nähe greift er automatisch an; Rally verstärkt den Angriff und verdichtet die Formation. Besiegte Beute hinterlässt einen goldenen Kadaver mit 12 Biomasse. In Kadavernähe wird Biomasse nach und nach geerntet; je 2 Biomasse entsteht ein Mawling. Weggehen pausiert die Ernte, der Rest bleibt an Ort und Stelle. Bei 250 Population bleibt übrige Biomasse ebenfalls liegen. Bis zu 120 Mawlings werden als einzelne Modelle dargestellt; die Population ist davon getrennt. Nach einer Jagd erscheinen wieder Nibbler.

Nach 18 Sekunden kommt der erste violette **Jäger**. Ein blauer Ring kündigt sein Erscheinen an. Sein roter Angriffsring bleibt während der 1,25 Sekunden langen Warnung fest an der markierten Position: rechtzeitig herauslaufen. Treffer kosten Mawlings und erzeugen eine Verlustanzeige. Rally erhöht den Bissschaden; ein besiegter Jäger hinterlässt 26 Biomasse. Bei höherem Druck werden Jäger schneller und markieren Flächen vor der aktuellen Laufrichtung. Richtungswechsel bleiben möglich, da sie die Warnfläche anschließend nicht nachführen.

Der Zeitdruck verdoppelt sich alle 90 Spielsekunden und erhöht Angriffsleistung, neue Jägergesundheit und Spawnrate. Maximal zwölf Jäger und fünf Nibbler sind gleichzeitig aktiv. **Nur Aussterben beendet den Run**; es gibt kein Zeitlimit. Die Ergebnisanzeige zeigt Überlebenszeit, höchste Population, Kills und geerntete Biomasse. Mit **NEUER RUN**, **R** oder **Enter** neu starten. **P / Escape** oder der Pause-Button pausiert; bei Fokusverlust pausiert das Spiel ebenfalls. Die Kadaver bleiben innerhalb des aktiven Runs erhalten; Neustart setzt den gesamten Run zurück.

Das ist ein spielbarer **Survival-Mechanik-Prototyp** mit vorläufigen Werten und Formen. Angriff, Ernte und Flächentreffer verwenden vorerst die Entfernung zum Schwarmzentrum; individuelle Mawlings haben keine eigene Kampf-KI. Mutationen, Bosse und endgültige Grafik sind noch nicht enthalten. Zentrale Survival-Werte stehen in `scripts/tuning.gd`.

## Arbeitsweise ab dem Neustart

Wir arbeiten ausdrücklich in **größeren, zusammenhängenden Etappen**. Eine Etappe umfasst den spielbaren Ablauf, notwendiges HUD und Bedienung, Fehlerkorrekturen sowie Funktions- und Sichtprüfung. Keine Übergabe nach jeder kleinen Funktion und keine wiederholten Freigaben für bereits vereinbarte Arbeit. Diese Vorgabe ist auch in `AGENTS.md` für die weitere Zusammenarbeit festgehalten. Die [Spielregeln](DESIGN_BRIEF.md) bleiben stabil.

Automatisierte Prüfungen mit der installierten Godot-Konsole:

```powershell
& 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\Users\vrxby\Documents\Codex\Godot\Mawlings' --script 'res://tests/smoke.gd'
& 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\Users\vrxby\Documents\Codex\Godot\Mawlings' --script 'res://tests/run_model.gd'
& 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\Users\vrxby\Documents\Codex\Godot\Mawlings' --script 'res://tests/hunt_flow.gd'
& 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\Users\vrxby\Documents\Codex\Godot\Mawlings' --script 'res://tests/survival.gd'
& 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --fixed-fps 60 --path 'C:\Users\vrxby\Documents\Codex\Godot\Mawlings' --script 'res://tests/endless_playthrough.gd'
```

Prüfstand und Grenzen: [Survival-Prüfung](SURVIVAL_VERIFICATION.md).

Projektdateien liegen unter `scenes/` und `scripts/`; `.godot/` wird nicht versioniert. Das Projekt besitzt ein eigenes Git-Repository, damit Dateien außerhalb dieses Ordners nicht dazugehören.
