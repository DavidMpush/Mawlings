# Evolution – Prüfstand 26.09.2026

Godot 4.7.2, Windows. Zusammenhängende Etappe: Jagd → DNA → pausierte Auswahl → sechs Mutationen mit drei Rängen → weitere Jagd → Aussterben/Neustart.

## Automatisierte Prüfung

- `tests/smoke.gd`: Szene, Bewegung, Rally und gleichzeitige Touch-Eingaben bestanden.
- `tests/run_model.gd`: persistente Kadaver, Wachstum, Verbrauch und Kapazität bestanden.
- `tests/hunt_flow.gd`: Jagd, Weggehen, Zurückkehren, Ernte und Wachstum bestanden.
- `tests/survival.gd`: Druck, Warnung, Ausweichen, Treffer, Jäger-Kill, Aussterben, Pause, Neustart und Spawn-Budgets bestanden.
- `tests/evolution.gd`: DNA-Schwellen, eindeutige Angebote, ungültige Auswahl, alle 18 Ränge ohne Sackgasse, sämtliche Effektformeln, echte Kampf-/Ernteintegration, pausierte Simulationszeit und Spawns, Touch-/Tastaturauswahl, Fokus-/Pause-Zustand, zukünftige Biomasse ohne Änderung alter Kadaver, Reset und Jägerbelohnung bestanden. Fokusverlust selbst ist über den bestehenden Pausepfad angebunden; kein Hardware-Fokustest.
- `tests/endless_playthrough.gd -- --long` mit `--headless --fixed-fps 60`: 360 Spielsekunden, 250 Population, 63 Kills, 30 Verluste, 44 liegende Kadaver, 7 lebende Jäger, Evolution 13. Build: Reißzähne 3, Schnelle Brut 3, Vielfraß 2, Rudelinstinkt 3, Fluchtreflex 1, Knochenpanzer 1. Bot wählt Angebot 1, nutzt dieselbe Steuerung und weicht Warnringen aus. Angebots-RNG im Test mit Seed 19; normale Runs verwenden Zufall.

## Sichtprüfung

`tests/capture_evolution.gd` rendert echte Godot-Ansichten mit OpenGL auf RTX 5070 bei 540 × 960. Auswahl, fortgesetztes Spiel und volle Build-Übersicht geöffnet und geprüft: Beschriftungen vollständig, Karten getrennt, rechte Bewegung und linkes Rally erhalten. Lokale Bilder: `preview_evolution.png`, `preview_evolution_play.png`, `preview_evolution_summary.png` (ignorierte Prüfartefakte).

## Grenzen

Kein Samsung-S25-Test und kein manuelles Langzeit-Balancing. Formen sind weiterhin Platzhalter. Simulation nutzt das Schwarmzentrum. Die automatisierte Überlebensdauer belegt Funktionsfähigkeit, keine finale Schwierigkeit. Run-Ende weiterhin ausschließlich Aussterben; keine Zeitgrenze. Ressourcen bleiben bis zum vollständigen Verbrauch oder Neustart liegen.
