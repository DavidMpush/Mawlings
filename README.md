# MAWLINGS — Godot-Neustart

Eigenständiges Projekt mit Godot **4.7.2**. Projektordner: `C:\Users\vrxby\Documents\Codex\Godot\Mawlings`. Das frühere Unity-Projekt wird nicht verwendet oder verändert.

## Starten

In Godot diesen Ordner als Projekt importieren und **F6** für die Hauptszene oder **F5** für das Projekt drücken. Alternativ:

```powershell
& 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64.exe' --path 'C:\Users\vrxby\Documents\Codex\Godot\Mawlings'
```

Der erste Stand enthält nur eine offene 3D-Testfläche und 25 Mawlings. **WASD/Pfeiltasten** bewegen den Schwarm, **Leertaste** hält Rally. Für Touch liegen Bewegung rechts und Rally links. Die Inseln sind Orientierungspunkte ohne Kollision. Gegner, Ressourcen, Mutationen und Laufende sind noch nicht implementiert.

## Arbeitsweise ab dem Neustart

Jeder Schritt endet mit einer in Godot startbaren, klar begrenzten Änderung und einer kurzen Prüfung im echten Spielbild. Wir beurteilen zuerst Bewegung und Rally, dann Jagd/Fressen, dann Druck und Entscheidungen. Gameplay-Inhalte und Grafik werden erst ausgebaut, wenn die jeweilige Grundlage überzeugt. Die [Spielregeln](DESIGN_BRIEF.md) bleiben währenddessen stabil.

Projektdateien liegen unter `scenes/` und `scripts/`; `.godot/` wird nicht versioniert. Das Projekt besitzt ein eigenes Git-Repository, damit Dateien außerhalb dieses Ordners nicht dazugehören.
