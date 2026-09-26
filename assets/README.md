# Charakter-Assets

- `source/mawling/` und `source/bog_king/`: angelieferte Original-GLBs und externe Texturen. Die Originale bleiben unverändert und dienen als Ausgangsmaterial. Die GLBs enthalten ihre Texturen bereits eingebettet; die zusätzlich gelieferten PNGs sind lokale Rohdaten und werden nicht ins Git-Repository aufgenommen.
- `gameplay/characters/`: kleine, aus den Originalen erzeugte GLBs mit Scheitelpunktfarben. Nur diese Dateien werden im laufenden Spiel instanziert.
- `*.import`: von Godot verwaltete Import-Einstellungen; `.godot/` enthält den regenerierbaren Cache.

Spielversionen neu erzeugen: `python tools/optimize_characters.py all` im Projektordner ausführen. Benötigt werden NumPy, Pillow und `fast-simplification` (hier lokal unter `.tools/` installiert; bei Bedarf `PYTHONPATH=.tools` setzen). Änderungen am Modell sollten zuerst am Original erfolgen, damit der Ableitungsschritt reproduzierbar bleibt.

## Anlieferung neuer Modelle (z. B. aus Hunyuan3D)

- **Format:** GLB mit eingebetteten Texturen, ein Objekt pro Datei, ohne Boden/Sockel. Original unter `source/<name>/` ablegen; die Spielversion entsteht mit `tools/optimize_characters.py`.
- **Ausrichtung:** Figur steht aufrecht (+Y oben), Füße auf y = 0, Blick nach **+Z**. Achtung: Das Mawling-Original blickt nach +X, der Bog King nach +Z; der Code gleicht beides aus (`swarm.gd` bzw. `model.rotation.y` in `bog_king.gd`). Neue Modelle bitte einheitlich nach +Z.
- **Pose:** neutrale Standpose mit leicht gespreizten Beinen, Maul geschlossen oder leicht offen; keine Aktionspose, da die Bewegung prozedural erfolgt.
- **Silhouette vor Detail:** klare, große Formen und kräftige Farbflächen lesen sich in der Hochformat-Draufsicht; feine Stacheln, dünne Glieder und Oberflächenrauschen gehen nach der Reduktion auf 3.000–8.000 Dreiecke und Scheitelpunktfarben verloren.
