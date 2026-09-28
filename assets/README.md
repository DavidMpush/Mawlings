# Charakter-Assets

## UI-Nachlieferung V5 (28.09.2026)

Die 56 transparenten Quelldateien aus der priorisierten [UI-Wunschliste](../stages/UI_ASSET_REQUESTS.md) liegen unter `assets/ui/v5/`: 48 Icons und Glyphen, vier Seltenheits-Plaketten, drei Stammporträts und ein Sandwurm-Porträt. `assets/ui/v4/build_icons_v4.py` erzeugt die 256-px-Spielversionen von 35 gemalten Icons; `assets/ui/v3/build_v3.py` verarbeitet die Porträts. Die 13 weißen Glyphen lädt `UiIcons` direkt. Die Plaketten sind als Quelldateien vorhanden, in den Mutationskarten aber noch nicht verwendet. Die Bildquellen und der Prompt-Satz stehen in `C:/Users/vrxby/Documents/Codex/Swarm/Design/UI_Assets_V2/V5_DELIVERY.md`.

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
- Lieferung 27.09.2026 (Nachmittag): `Skitter.glb`, `moorbrut.glb`, `moosschlund.glb`, `Bog King new.glb`, `Elite Crown.glb`, `nest.glb` liegen als Originale in `assets/` (vom Export ausgeschlossen). Spielversionen: `gameplay/characters/Skitter_game`, `Moorbrut_game`, `Moosschlund_game`, `BogKingNew_game`, `gameplay/props/EliteCrown_game`, `BroodNest_game` über `PYTHONPATH=.tools python tools/optimize_characters.py skitter|moorbrut|moosschlund|bog_king_new|elite_crown|nest`.
- Lieferung 27.09.2026 (Abend): `Ash Toad.glb` (Aschenkröte, Apex des Glutsumpfs) liegt als Original in `assets/` (vom Export ausgeschlossen). Spielversion `gameplay/characters/AshToad_game` (8.000 Dreiecke, verschweißt) über `PYTHONPATH=.tools python tools/optimize_characters.py ash_toad`. Verwendung: `scripts/apex_toad.gd` (echte Modellfarben, die orangen Glutadern leuchten per Shader-Zusatz auf `creature_anim`, stärker vor der Glutspucke und in Phase 2) und der Kadaver `apex_toad` in `scripts/corpse_visuals.gd` (auf dem Rücken). Prüfbilder: `tests/capture_ash_toad_model.gd` (Seitenansicht mit +Z-Marker und Animationszustände). `gameplay/characters/BogKing_game.glb` (alter Bog King, von keinem Skript mehr geladen) wurde am 28.09.2026 gelöscht.
- Lieferung 27.09.2026 (Wüstenwelt „Dürrschlund“, Etappe 19): `sandwurm.glb`, `sandgrub.glb`, `sandportal.glb`, `ribbones.glb`, `rockarch.glb`, `sandstone.glb`, `cactus.glb`, `skull.glb` liegen als Originale in `assets/` (vom Export ausgeschlossen, alle verschweißt reduziert). Spielversionen über `PYTHONPATH=.tools python tools/optimize_characters.py <id>`:
  - `gameplay/characters/Sandwurm_game` (8.000 Dreiecke, Kopf +Z, Rundmaul vorn, Schwanz im Sandhügel) – `scripts/apex_sandworm.gd` (Grab-Spur, Durchbruch senkrecht, Segment-Wellen und Maulweitung im Shader-Zusatz zu `creature_anim`), Kadaver `apex_sandworm` in `scripts/corpse_visuals.gd`.
  - `gameplay/characters/Sandgrub_game` (1.200) – `scripts/sandgrub.gd` (MultiMesh, Glieder-/Kieferrahmen vermessen), Kadaver `sandgrub`.
  - `gameplay/props/SandPortal_game` (3.000, Durchbruch-Maul laut Referenzbild 02 → Migrationsschlund der Wüste), `RibBones_game` (2.500, Rippenreihe, Wand/Engpass), `RockArch_game` (2.500, Felsbogen, Landmarke), `SandstoneCliff_game` (2.000; sehr flache Platte, 0,17 : 1,1 – als Wand in Y strecken), `Cactus_game` (1.500, Deko), `GiantSkull_game` (3.000, Landmarke). Rollen und Farben im Biom-Eintrag `duerrschlund` in `scripts/biomes.gd`.
  - Prüfbilder: `tests/capture_sandworm.gd` (`preview_sandworm_*.png`). Fehlt noch: Oasen-Palme.

## Kampf-VFX V1 (`assets/vfx/`)

Quelle: `Swarm/Design/VFX_Assets_V1` (Nutzerpaket 27.09.2026, bleibt unverändert). `tools/build_vfx.gd` erzeugt alles reproduzierbar mit Godot selbst (`Godot_console.exe --headless --audio-driver Dummy --path . --script res://tools/build_vfx.gd [-- src=<ordner>]`, danach einmal `--editor --import`):
- Sechs Effektbilder (`bite_hit`, `acid_splash`, `spore_cloud`, `slam_shockwave`, `harvest_particles`, `dna_pickup`): auf das sichtbare Motiv beschnitten, quadratisch, Alpha-Ränder aufgefüllt, Lanczos auf 256 px (Schockwelle 384, Sporen 320). Import: VRAM-komprimiert (S3TC/ETC2), Mipmaps. Zusammen ≈ 0,6 MB PNG.
- Boss-Telegraphen `boss_telegraph_circle_mask.png` / `boss_telegraph_cone_mask.png` (512 px): die SVGs, Ebene für Ebene als **Kanalmaske** gerastert (R Füllung, G dunkle Kontur, B Korallring, A helle Markierungen). So bleibt die Form exakt, und `scripts/telegraph_style.gd` färbt sie (normal und Farbenblind-Palette). Import verlustfrei mit Mipmaps, ohne Alpha-Randkorrektur (sonst würden die Kanäle verfälscht).
Verwendung: `scripts/vfx_sprites.gd` (gepoolte MultiMeshes, `shaders/vfx_sprite.gdshader`) und `shaders/telegraph_boss.gdshader`. Prüfbilder: `tests/capture_vfx.gd`.
