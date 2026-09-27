# Bog King – erster spielbarer Boss-Pass

Stand: 26.09.2026. Das vom Nutzer bereitgestellte `BogKing.glb` ist als großer Gegner in den Endless-Run eingebunden. Die erste Begegnung beginnt nach 90 Spielsekunden; nach einem Sieg bleibt ein Kadaver mit 110 Biomasse liegen und der nächste Boss kann nach 180 Sekunden erscheinen. Es gibt kein Run-Ende durch den Sieg. Das Modell ist auf 8.000 Dreiecke und rund 341 KB reduziert; das unveränderte Original mit 50.000 Dreiecken liegt unter `assets/source/bog_king/`.

Der Boss hat einen eigenen HUD-Balken und einen Balken über dem Modell. Sein Stampfen markiert 1,8 Sekunden lang einen festen roten Kreis. Der Boss bewegt sich beim Warnen nicht weiter; ein Ausweichen verlässt den Kreis. Nach dem Angriff folgt eine Erholungsphase. Die Trefferprüfung nutzt derzeit wie bei den anderen Gegnern das Zentrum des Schwarms.

Prüfung mit Godot 4.7.2:

- `tests/boss.gd`: Spawn, großes Modell, HUD, Warnung, Ausweichen, Einzeltreffer, DNA, permanente Biomasse, Respawn-Timer und Reset bestanden.
- `tests/smoke.gd`, `tests/survival.gd`, `tests/skitter.gd`, `tests/evolution.gd` und `tests/model_budget.gd` bestanden.
- `tests/endless_playthrough.gd` mit `--fixed-fps 60`: 120 Spielsekunden ohne Aussterben; Boss erscheint während des Runs. Ergebnis: 103 Population, 127 Peak, 16 Kills und Evolution Stufe 5.
- Sichtprüfung mit `tests/capture_boss.gd`: Hochformat bei 25 Mawlings, Boss und Stampfwarnung. Das Modell bleibt gegenüber dem Schwarm deutlich groß; Steuerung und HUD sind sichtbar.

Ein Spieltest auf dem Samsung S25 und endgültige Animationen stehen noch aus. Bosswerte und Maßstab sind ein erster spielbarer Entwurf.
