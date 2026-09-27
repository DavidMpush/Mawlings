# Übergabe an Claude Code

Stand: 26.09.2026, letzter spielbarer Commit vor dieser Übergabe: `8226181` (`Add Bog King boss encounter and organize character assets`). Dieses Dokument beschreibt den **Ist-Zustand**; `DESIGN_BRIEF.md` enthält die vom Nutzer bestätigten Produktregeln. Das aktive Projekt ist `C:\Users\vrxby\Documents\Codex\Godot\Mawlings`, nicht das alte Unity-Projekt.

## Was bereits funktioniert

- Mobiles Hochformat mit Bewegungsjoystick rechts, Rally links, Tastatursteuerung für Editor-Tests.
- Open-End-Run mit exponentiellem Druck und Ende nur bei Aussterben; offene, prozedural nachladende Arena mit breiten Wegen und wenigen Kollisionssteinen.
- Beutejagd, automatischer Angriff, Kadaver mit bis zum Verbrauch bleibender Biomasse, Schwarmwachstum bis 250 logisch / 120 sichtbar.
- Jäger mit fest markiertem Flächenangriff, Skitter mit angekündigter Sprintbahn, großer Bog King mit Stampfkreis, Bossleiste, DNA- und Biomassebelohnung.
- Sechs Mutationen mit drei Rängen, Auswahl bei DNA-Schwellen; Pause und Neustart.
- Optimierte `Mawling_game.glb` (3.000 Dreiecke) und `BogKing_game.glb` (8.000 Dreiecke), Originale unter `assets/source/`.

Der letzte automatisierte Zwei-Minuten-Run mit Boss-Spawn endete bei 103 Mawlings, Peak 127, 16 Kills, Evolution Stufe 5 und ohne Aussterben. Die Tests in `CLAUDE.md` bestanden. Das ersetzt **keinen** Handtest auf dem Samsung S25. Das Bossbild lässt sich mit `tests/capture_boss.gd` neu erzeugen.

## Offene Punkte mit hohem Nutzen

1. **Spielgefühl und Lesbarkeit:** Bosssilhouette, Warnflächen, Trefferreaktion, Bewegungsanimationen und Dichte im Hochformat gemeinsam betrachten. Die Modelle sind derzeit statisch; Gegner außer Mawling und Bog King bestehen teils aus einfachen Formen.
2. **Gerätetest:** Android-Export, Touch-Ziele, Bildrate und Speicher auf dem Samsung S25 prüfen, sobald das Gerät bereitsteht. Desktop-Editorwerte nicht als Android-Leistung ausgeben.
3. **Lange Runs:** Die Godot-Kadaverliste wird für Ernte und HUD linear durchsucht; bei vielen dauerhaften Ressourcen einen räumlichen Index und begrenzte Darstellung einführen, ohne sie spielmechanisch verschwinden zu lassen.
4. **Balance:** Bog King und Skalierung nach mehreren Minuten manuell spielen. Die aktuelle Bot-Prüfung kann einen Run durchlaufen, bewertet aber Spaß und Verständlichkeit nicht.

Für den **ersten größeren Schritt** eignet sich ein zusammenhängender Art-/Feedback-Pass im laufenden Spiel: Boss und Schwarm durch sparsame prozedurale Bewegung und klare Trefferreaktionen lebendiger machen, Warnflächen und Größenverhältnis im Hochformat prüfen, danach den vollständigen Testlauf und Bildvergleich durchführen. Vor weiterer Content-Ausweitung zunächst die vorhandene Schleife stärken. Wenn eine andere Etappe beim Code- und Spieltest klar mehr Nutzen bringt, diese begründet wählen und komplett abschließen.

## Sofort verwendbarer Startprompt

> Lies `CLAUDE.md`, `DESIGN_BRIEF.md`, `README.md`, `ART_UI_PLAN.md` und `CLAUDE_HANDOFF.md`. Prüfe den Git-Status und starte das Godot-Projekt sowie die relevanten Tests. Arbeite dann selbstständig an einer größeren, zusammenhängenden Etappe, die den spielbaren Eindruck sichtbar verbessert. Priorisiere Lesbarkeit und Bewegung von Schwarm und Bog King im Hochformat; halte Ressourcen, Open-End-Regeln und die offene Karte ein. Prüfe die echte gerenderte Ansicht, behebe gefundene Fehler, aktualisiere die Dokumentation und berichte mir die Ergebnisse und verbleibenden Grenzen. Bitte nicht nach jedem kleinen Schritt auf meine Rückmeldung warten.

## Claude Code starten

In Claude Code Desktop eine **lokale** Code-Sitzung mit dem Projektordner `C:\Users\vrxby\Documents\Codex\Godot\Mawlings` öffnen. In der CLI im Projektordner `claude --model claude-opus-5-5` starten oder in einer laufenden Sitzung `/model claude-opus-5-5` wählen. Laut offizieller Claude-Code-Dokumentation erfordert Opus 5.5 mindestens Version 2.1.280; Zugriff hängt zusätzlich vom eigenen Konto ab. Der Modellname ist bewusst nicht in Projektdateien festgelegt. Der `claude`-Befehl war beim Schreiben dieser Übergabe auf diesem Rechner **nicht im PATH**; falls die CLI noch nicht installiert ist, kann stattdessen die Desktop-App genutzt werden oder die offizielle Claude-Code-Installation erfolgen.
