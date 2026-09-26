# Design- und Modell-Pass – Prüfung 26.09.2026

Das vom Nutzer gelieferte `assets/Mawling.glb` wurde importiert und aus der echten Godot-Spielkamera angesehen. Die Rohdatei enthält 50.000 Dreiecke, drei 4096er Texturen und keine Animation. Die erzeugte Spielvariante `assets/Mawling_game.glb` hat 3.000 Dreiecke und Scheitelpunktfarben, Dateigröße 136.464 Byte. `tests/model_budget.gd` bestätigt ein Mesh pro sichtbarem Mawling, 3.000 Dreiecke und 120 sichtbare Instanzen bei 250 logischer Population.

`tests/capture_design.gd` renderte vier Hochformat-Frames bei 540 × 960 mit Godot/OpenGL: Start mit 25 Tieren, 250 logische Population, drei lange Mutationskarten und Run-Ende. Zusätzlich wurden `tests/capture_survival.gd` und `tests/capture_evolution.gd` gerendert und betrachtet. HUD, Statuswerte, Touchziele, Karten, Warnring und Ressource blieben lesbar. Die Vorschauen `preview_design_*.png` sind lokale, ignorierte Prüfartefakte.

Die bestehenden Smoke-, Jagd-, Survival-, Evolution-, Skitter- und Arena-Tests bestanden nach der Integration. Der automatisierte Sechs-Minuten-Run mit `--fixed-fps 60` lief mit 250 Population, 84 Kills, 66 Verlusten und 68 noch liegenden Kadavern durch. Das belegt die Funktionsfähigkeit, aber keine Bildrate auf dem Samsung S25 und kein finales Design-Balancing.
