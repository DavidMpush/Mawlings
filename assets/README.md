# Charakter-Assets

- `source/mawling/` und `source/bog_king/`: angelieferte Original-GLBs und externe Texturen. Die Originale bleiben unverändert und dienen als Ausgangsmaterial. Die GLBs enthalten ihre Texturen bereits eingebettet; die zusätzlich gelieferten PNGs sind lokale Rohdaten und werden nicht ins Git-Repository aufgenommen.
- `gameplay/characters/`: kleine, aus den Originalen erzeugte GLBs mit Scheitelpunktfarben. Nur diese Dateien werden im laufenden Spiel instanziert.
- `*.import`: von Godot verwaltete Import-Einstellungen; `.godot/` enthält den regenerierbaren Cache.

Spielversionen neu erzeugen: `python tools/optimize_characters.py all` im Projektordner ausführen. Benötigt werden NumPy, Pillow und `fast-simplification` (hier lokal unter `.tools/` installiert; bei Bedarf `PYTHONPATH=.tools` setzen). Änderungen am Modell sollten zuerst am Original erfolgen, damit der Ableitungsschritt reproduzierbar bleibt.
