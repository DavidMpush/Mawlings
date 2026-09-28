# Etappe 20 – Lesbarkeit der Gefahren und einheitliche Boss-Telegraphen

Grundlage: `stages/REFERENCE_SWARM.md` S1 (Farben mit fester Bedeutung), S2 (Anführer auffindbar), S3 (drei Formen für Gefahr). Parallel arbeitet ein Agent an 17b/17c (`hunt_world.gd`, `swarm.gd`, HUD, `tuning.gd` außer dem Wüsten-Block u. a.); diese Dateien sind unberührt.

## Abnahmekriterien
1. Moosschlund, Aschenkröte und Sandwurm zeigen ihre Angriffe im Boss-Stil aus `telegraph_style.gd` (SVG-Kreis/-Kegel wo die Form passt, sonst gleichwertige Varianten: Bahn, Ring mit Innenradius, Scheibe mit Inseln), mit Farbenblind-Palette. Die gezeichnete Trefferkante entspricht exakt der Trefferprüfung.
2. Drei Gefahrenformen überall: Kontur = kommt gleich, Fläche = liegt da, großer Ring = Ereignis läuft. Normale Gegner und Ausbrüche geprüft.
3. Farbregeln: eigen Glut/Orange, Gefahr Magenta/Pink, Beute Gold, DNA/XP Blau/Violett, Wachstum Grün; freundliche Zonen nie in Gefahrenfarbe. Boden ruhig.
4. Apex-Kampfdauer auf Brutal/Apex gemessen (Ziel 25–35 s); nur Boss-LP bzw. Wüsten-Block angepasst.
5. Tests grün (einzeln), Captures jeder Gefahrenform und jedes Boss-Angriffs selbst angesehen. Doku in `ART_UI_PLAN.md`.

## Ergebnis (28.09.2026)

### Einheitliche Boss-Telegraphen
- Neu `shaders/telegraph_boss_shapes.gdshader`: dieselbe Optik wie die SVG-Masken, prozedural. Heller Gefahrenrand, dessen Außenkante die Trefferkante ist, dunkle Kontur direkt außen, Füllung, die vom Ursprung mit der Warnzeit dunkler wird (helle Vorderkante), gestrichelter Innenring, Chevrons auf Bahnen, sichere Inseln hell mit cyanfarbenem Rand. Formen: Scheibe, Bahn, Ring, Scheibe mit Inseln, **Fläche** (gefüllt, ohne Vorderkante und Puls, langsame Blasen).
- `telegraph_style.gd`: `build_boss_disc`, `build_boss_lane`, `build_boss_ring`, `build_boss_islands`, `build_hazard`, `shape_material`, Palette `hazard`, `SAFE`-Farben, `SHAPE_MARGIN`.
- **Moosschlund:** Wurzeln = Bahnen, Sporen = Ring, Beben = Scheibe mit Inseln (eigener Muster-Shader entfernt).
- **Aschenkröte:** Sprung und Spucke = SVG-Boss-Kreis, Zunge = Boss-Bahn, Glutpfützen = Fläche (eigener Shader entfernt).
- **Sandwurm:** war schon SVG-Kreis/-Kegel. Für exakte Kanten: Öffnungswinkel des Schwanzfegers = SVG-Winkel (29,2° statt 31,5°, sonst dehnt sich der Bogen seitlich), Treffer beginnt an der gezeichneten Spitze (`SWEEP_INNER` 0; dort liegt ohnehin der Wurmkörper).
- `tests/telegraph_shapes.gd` (neu, in `tools/test.ps1`): baut für jeden Angriff die vorzeichenbehaftete Kantendistanz des Shaders aus Knoten, Mesh und Uniforms nach und vergleicht sie auf einem dichten Raster mit `contains()` (Moosschlund 3, Kröte 3 + Pfützen, Sandwurm 2, Bog King) – 0 Abweichungen. Dazu Palettenregeln und Farbenblind.

### Gefahrenformen und Farben
- Warnflächen normaler Gegner jetzt Magenta/Pink: Jäger und Nibbler (`BRAWL_DANGER_FACE`, Rand #ff5aa8), Skitter (`BRAWL_DANGER_LIGHT`), Leaper blieb Violett-Magenta. Vorher Rot-Orange bzw. Bernstein (Farbe des eigenen Schwarms).
- Boss-Palette von Koralle auf Pink (gleiche Masken und Markierungen), dunkle Kontur weinrot.
- Lava-Ausbruch: Kontur und Ringe pink, nur der wachsende Kern bleibt Lava (`eruption.gdshader`).
- Einschlagringe (Beben, Sprung, Spucke, Stampf, Toben) pink statt orange.
- Großer Ring: jede Flutwelle zeigt einen hellen pinken Ring, der sich vom Spawnring zum Schwarm zusammenzieht (`horde.gd`).
- Freundlich: Karten-Kokon Gold statt Glut, „zu teuer“ grau-blau statt Pink (`chests.gd`); Raserei-Aura und Power-up in Glut statt Gefahr (`powerups.gd`). Nest Türkis, Schrein Violett, Inseln Cyan unverändert.
- S2: Krone, LP-Punkte und Bodenring am Anführer gibt es schon; unverändert (`swarm.gd` gesperrt).

### Apex-Kampfdauer (`tests/apex_duration.gd`, neu)
Echter Run (HuntWorld), ausweichender Bot (verlässt Warnflächen auf kürzestem Weg, sonst Rally am Rand), Mindestpopulation des Apex, Build wie nach ~3 min (Startwaffe + Sporenwolke, Biss 2, Kritbiss, Angriffstempo).

| Apex | Brutal | Apex |
|---|---|---|
| Moosschlund (1.400 LP) | 25,3 s | 20,4 s |
| Sandwurm (vorher 2.500 LP) | 65,0 s | 52,2 s |
| **Sandwurm (jetzt 1.075 LP)** | **33,0 s** | **26,4 s** |
| Aschenkröte (3.600 LP) | 59,9 s | 46,8 s |

- `APEX_SANDWORM_HEALTH` im Wüsten-Block: 2.500 → **1.075**.
- **Empfehlung (nicht umgesetzt, Werte liegen im allgemeinen Teil von `tuning.gd`):** `APEX_TOAD_HEALTH` 3.600 → ~2.000 (≈ 33/26 s), `APEX_HEALTH` (Moosschlund) 1.400 → ~1.700 (Apex-Stufe sonst unter 25 s). Die `HEALTH`-Konstanten in den Boss-Dateien gelten nur ohne HuntWorld.

### Tests (einzeln, weil 17b/17c die Suite zeitweise rot macht)
Grün: `telegraph_shapes`, `apex`, `apex_toad`, `apex_sandworm`, `toad_run`, `desert_run`, `boss`, `per_unit_hits`, `flood`, `horde`, `chests`, `powerups`, `shrines`, `vfx`, `motion`.
Rot, nicht durch diese Etappe: `apex_run` („Leader … 100 -> 42“), `eruptions` („hp 100 -> 85“), `survival`/`skitter`/`leaper` („biomass crystals … at cap“) – Anführer-LP und Biomasse-Obergrenze kommen aus dem laufenden 17b/17c-Umbau (`run_model`/`swarm`/`hunt_world`); diese Etappe ändert nur Farben/Formen und die Sandwurm-LP.
Angepasst: `apex_toad` (Nachbarformen unterscheiden sich in der Form statt Farbe), `apex_sandworm` (Kegel beginnt an der Spitze).

### Bilder (`tests/capture_dangers.gd`)
`preview_danger_enemies`, `_bog_king`, `_moss_roots`, `_moss_spores`, `_moss_quake` (+ `_cb`), `_toad_leap`, `_toad_spit`, `_toad_tongue`, `_toad_puddles`, `_worm_breach`, `_worm_sweep`, `_exact` (cyan Referenzring liegt auf der Kante), `_eruption`, `_flood`, `_friendly`, `_sheet`.

Iterationen: (1) Gegner-Warnflächen wirkten weißlich (heller Rand, blasses Muster), Ausbruch fehlte im Bild (keine Quelle in Reichweite), Referenzlinie unsichtbar. (2) Rand und Muster der Gegner kräftiger pink, Ausbruch an einer Lavastelle, Referenz als Ring.

**Ehrliche Bewertung:** Alle Angriffe lesen sich jetzt als eine Familie: pinker Rand = Treffer, dunkle Kontur, helle Markierungen; Kröten- und Moosschlund-Angriffe sind deutlich klarer als die alten Muster-Shader, die sicheren Inseln stechen als einzige kühle Farbe heraus. Die Pfützen als gefüllte, ruhige Fläche unterscheiden sich gut von den pulsierenden Konturen. Schwächen: Die Flutwelle als Ring ist hell und kurz und wirkt auf Verdant eher dezent; die Moosschlund-Bahnen sind sehr lang und dominieren das Bild; Leaper bleibt Violett (eigene Farbe der Art) statt reinem Pink. Kein Handtest.
