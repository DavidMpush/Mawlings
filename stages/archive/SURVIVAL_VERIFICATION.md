# Survival-Etappe — Prüfung am 25.09.2026

Godot 4.7.2, lokales Windows-Projekt. Alle fünf Prüfskripte beenden sich erfolgreich und ohne Scriptfehler.

| Prüfung | Abgedeckter Ablauf |
| --- | --- |
| `smoke.gd` | Szenenstart, Tastaturbewegung, Rally, gleichzeitige Bewegung rechts und Rally links, unabhängiges Loslassen |
| `run_model.gd` | Teilbiomasse, genaue Nachwuchskosten, vollständiger Verbrauch, Populationslimit, erhaltene Restbiomasse |
| `hunt_flow.gd` | Echte Beutejagd, Kadaver verlassen, unveränderte Restmenge, Rückkehr, Wachstum |
| `survival.gd` | Feste Warnfläche, Ausweichen, genau ein Treffer, spätere Vorhalteangriffe, Jäger durch normalen Kampf töten, Aussterben durch Angriffe, Neustart über UI, Pause, Spawn-Budgets und Ressourcenpersistenz |
| `endless_playthrough.gd` | Automatisierter Spieler steuert über die Bewegungseingabe, jagt, erntet und weicht Warnringen aus |

Der zweiminütige automatisierte Run endet mit 78 Mawlings, Höchststand 84, elf Kills, 25 verlorenen Mawlings, zwei Kadavern und vier aktiven Jägern. Der längere Lauf (`-- --long`, sechs simulierte Minuten) endet mit 250 Mawlings, 58 Kills, 57 verlorenen Mawlings, 44 verbleibenden Kadavern und sieben Jägern. Beide verwenden einen festen Simulationsschritt von 60 Hz. Diese Läufe prüfen das Zusammenspiel; sie belegen weder Spaß noch endgültiges Balancing oder Geräteperformance.

Ein beschleunigter Modelltest über 24 Stunden erhält Ressourcen und endliche Druckwerte. Ein Szenentest spielt mit vorgerückter Zeit über zwölf Minuten hinaus, ohne einen Sieg oder zeitgesteuertes Run-Ende auszulösen. Der Druckexponent ist nur gegen numerischen Überlauf begrenzt.

`tests/capture_survival.gd` rendert Warnring und tatsächliches Aussterben mit Ergebnisanzeige in 540 × 960. Beide Bilder wurden visuell auf Lesbarkeit und überlappende Bedienflächen geprüft. Die Dateien `preview_survival.png` und `preview_extinction.png` sind erzeugte, von Git ignorierte Ausgaben.

Noch offen: menschliches Spielgefühl, Balance über längere Runs und Samsung-S25-Profiling. Gegner und Map verwenden einfache Formen. Boden-Dekoration hat keine Kollision. Die Reichweiten beziehen sich vorerst auf das Schwarmzentrum. Persistenz gilt innerhalb des Runs; es gibt noch keinen Speicherstand über App-Neustarts hinweg.
