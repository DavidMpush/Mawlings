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

## Objekt-Modelle (Etappe Asset V3)

- `CurseTotem.glb`, `alphacore.glb`, `migration pit.glb` und `Hunter Beetle.glb` liegen als Nutzer-Originale direkt in `assets/` (unverändert, vom Android-Export ausgeschlossen). Die Spielversionen in `gameplay/props/` (`CurseTotem_game`, `AlphaCore_game`, `MigrationPit_game`) und `gameplay/characters/HunterBeetle_game` entstehen mit `PYTHONPATH=.tools python tools/optimize_characters.py totem|alpha_core|migration_pit|hunter_beetle`.
- Verwendung: `scripts/objectives/curse_totem.gd` (Totem mit leuchtenden violetten Adern), `scripts/objectives/alpha_core_visual.gd` (Alpha-Kern, von `hunt_world.gd` aufzurufen), `scripts/migration_maw.gd` (Krater wird beim Laden abgeflacht, damit der Wirbel sichtbar bleibt).

## 2D-Erweiterung (UI-Kit V2, `assets/ui/v3/`)

Kleine Kopien der Grafiken aus `Swarm/Design/UI_Assets_V2` (EXPANSION_ASSETS.md): Menü-Hintergrund, Logo, Biom-Karten, Stamm- und Bog-King-Porträt, Angriffs-/Zweig-/Anlagen-/Währungs-Icons (256 px) und Android-Launcher-Icons. Neu erzeugen mit `python assets/ui/v3/build_v3.py`; Hintergrund, Biome und Porträts werden verlustbehaftet (WebP) importiert. Sporling, Knochenkiefer und Nachtmaul sind auf ihre Stammfarbe umgefärbt.
