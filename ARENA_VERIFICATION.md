# Arena und Lesbarkeit – Prüfstand 26.09.2026

Die Welt lädt um den Schwarm neun sichtbare Abschnitte. Jeder Abschnitt hat breite, leicht geschwungene Sandwege, offene Grünflächen und zwei niedrige Steinformationen. Diese Steine bilden vereinzelte, gut umgehbare Engstellen. Schwarm, Nibbler und Jäger gleiten an ihrer Grundfläche entlang; neue Gegner werden außerhalb der Steine platziert. Pool und Blattflächen bleiben begehbar. Ein Abschnitt behält bei Rückkehr seine Lage und Hindernisse. Kadaver sind davon unabhängig und bleiben im aktiven Run erhalten.

Die Silhouetten wurden aus der Hochformatkamera lesbarer gemacht: Mawlings haben Kamm und Augen, Nibbler seitliche Flossen und eine Schalenzeichnung, Jäger Maske und leuchtende Augen. Es sind weiterhin einfache 3D-Platzhalter, keine finalen Figuren.

`tests/arena.gd` prüft begrenzte Abschnittszahl, feste Hindernispositionen nach weiter Reise, Kollision und Gleiten, sichere Spawnpositionen, Beutebewegung und dauerhafte Kadaver. Die bestehenden Smoke-, Jagd-, Survival- und Evolutionstests bestanden. Der automatisierte Sechs-Minuten-Lauf mit `--fixed-fps 60` bestand ebenfalls: 360 Spielsekunden, Population 250, 65 Kills, 88 Verluste, 43 liegende Kadaver, Evolutionsstufe 13. Diese Zahlen sind ein automatisierter Ablauf, kein Balancing-Urteil.

Mit `tests/capture_arena.gd` und `tests/capture_survival.gd` wurden echte Godot-Frames bei 540 × 960 auf RTX 5070 gerendert und betrachtet. Die Vorschauen `preview_arena.png` und `preview_survival.png` sind ignorierte lokale Prüfdateien. Noch offen sind manuelle Spielgefühltests und der Test auf dem Samsung S25.
