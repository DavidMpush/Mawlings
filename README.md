# MAWLINGS — Godot-Neustart

Eigenständiges Projekt mit Godot **4.7.2**. Projektordner: `C:\Users\vrxby\Documents\Codex\Godot\Mawlings`. Das frühere Unity-Projekt wird nicht verwendet oder verändert.

## Starten

In Godot diesen Ordner als Projekt importieren und **F6** für die Hauptszene oder **F5** für das Projekt drücken. Alternativ:

```powershell
& 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64.exe' --path 'C:\Users\vrxby\Documents\Codex\Godot\Mawlings'
```

Der aktuelle Stand enthält eine offene 3D-Testfläche und 25 Mawlings zum Start. **WASD/Pfeiltasten** bewegen den Schwarm, **Leertaste** hält Rally. Für Touch liegen Bewegung rechts und Rally links. Die Inseln sind Orientierungspunkte ohne Kollision.

Die drei türkisfarbenen Nibbler fliehen vor dem Schwarm. In Nähe greift er automatisch an; Rally verstärkt den Angriff und verdichtet die Formation. Besiegte Beute hinterlässt einen goldenen Kadaver mit 12 Biomasse. In Kadavernähe wird Biomasse nach und nach geerntet; je 2 Biomasse entsteht ein Mawling. Weggehen pausiert die Ernte, der Rest bleibt an Ort und Stelle. Bei 250 Population bleibt übrige Biomasse ebenfalls liegen. Bis zu 120 Mawlings werden als einzelne Modelle dargestellt; die Population ist davon getrennt. Nach einer Jagd erscheinen wieder Nibbler.

Das ist weiterhin ein kleiner **Mechanik-Prototyp**. Angriff und Ernte verwenden vorerst die Entfernung zum Schwarmzentrum; individuelle Mawlings haben keine eigene Kampf-KI. Ein gefährlicher Gegner, Populationsverluste, Aussterben, Mutationen und exponentieller Druck folgen später.

## Arbeitsweise ab dem Neustart

Jeder Schritt endet mit einer in Godot startbaren, klar begrenzten Änderung und einer kurzen Prüfung im echten Spielbild. Wir beurteilen zuerst Bewegung und Rally, dann Jagd/Fressen, dann Druck und Entscheidungen. Gameplay-Inhalte und Grafik werden erst ausgebaut, wenn die jeweilige Grundlage überzeugt. Die [Spielregeln](DESIGN_BRIEF.md) bleiben währenddessen stabil.

Automatisierte Prüfungen mit der installierten Godot-Konsole:

```powershell
& 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\Users\vrxby\Documents\Codex\Godot\Mawlings' --script 'res://tests/smoke.gd'
& 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\Users\vrxby\Documents\Codex\Godot\Mawlings' --script 'res://tests/run_model.gd'
& 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\Users\vrxby\Documents\Codex\Godot\Mawlings' --script 'res://tests/hunt_flow.gd'
```

Projektdateien liegen unter `scenes/` und `scripts/`; `.godot/` wird nicht versioniert. Das Projekt besitzt ein eigenes Git-Repository, damit Dateien außerhalb dieses Ordners nicht dazugehören.
