# MAWLINGS — Projektkontext für Claude Code

Arbeite im **Godot-Projekt dieses Verzeichnisses**. Antworte dem Nutzer auf Deutsch. Das alte Unity-Projekt unter `C:\Users\vrxby\Documents\Codex\Swarm` ist nur eine historische Referenz; ändere es nicht. Die verbindliche Spielrichtung steht in `DESIGN_BRIEF.md`, die gewünschte Arbeitsweise zusätzlich in `AGENTS.md`. Lies vor einer größeren Änderung auch `README.md`, `ART_UI_PLAN.md` und `stages/BACKLOG.md`.

## Arbeitsweise

- Der Nutzer möchte **größere, zusammenhängende, spielbare Etappen**. Bei „weiter“ selbstständig eine sinnvolle Etappe mit Mechanik, Bedienung, visueller Prüfung, Fehlerkorrekturen und Dokumentation abschließen. Nicht nach jeder Kleinigkeit um Freigabe bitten.
- Erkläre Fortschritt knapp und regelmäßig. Beurteile Spielgefühl und Design ehrlich anhand der gerenderten Spielansicht, nicht nur anhand bestandener Tests.
- Halte die Karte strukturiert mit lesbaren Wegen und Engpässen (Lichtungen, Wege, klare Wände; freie Bildmitte um den Schwarm). Ziel ist vereinfachte, farbige Fantasy-Optik im mobilen Hochformat. Inspirationsbilder sind keine exakten Vorgaben für UI, Modelle oder Karte.
- Ressourcen bleiben innerhalb eines Runs bis zum vollständigen Verbrauch liegen. Ein Run endet ausschließlich bei Aussterben. Der Druck steigt exponentiell. Bewegung liegt rechts, Rally links.
- Bestehende Dateien und Nutzer-Assets erhalten; Änderungen im Git-Repository auf eine prüfbare Etappe begrenzen. Nach der Arbeit Tests und `git status` prüfen, `README.md` sowie relevante Prüfnachweise aktualisieren.

## Aktueller Stand

Godot 4.7.2. Startszene ist das Menü `scenes/menu.tscn` (Brutstätte: Stämme, Biome, Schwierigkeit, Upgrades, Trophäen, Chronik, Tages-Brut, Einstellungen); der Run läuft in `scenes/main.tscn`. Ein Run beginnt mit **einem Anführer** (100 LP mit Lebensbalken, Treffer kosten je Angriff LP, Heilung über Lebensraub/Regeneration; Nachfolger übernimmt mit 80 % des Maximums); neue Mawlings entstehen per Zellteilung aus Biomasse, **kein Populationslimit** (Etappe 17b), sichtbar max. 120 (ein MultiMesh; darüber steht jedes Modell für mehrere Tiere). Seed-generierte, begrenzte **Erkundungskarte** (Etappe 18/18c, Regionen mit gewürfelter Landschaft, Orte erst nach Entdeckung sichtbar; Solo 4 × 4 Regionen = 336 m, Duo 5 × 5, Trio/Quad 6 × 6 über `arena.configure_map`; natürlicher Rand aus `scripts/arena_border.gd`; Migration = neue Karte je Biom; Minimap zeigt die ganze Karte mit Nebel). Biom-Kreis Verdant Maw → Dürrschlund (Wüste, Treibsand/Sandstürme) → Glutsumpf (Lava-Ausbrüche). Gegner: Nibbler (schnappen zurück), Jäger/Elite-Jäger, Skitter, Mire Leaper, Bog King (ab ~2 min), ab 4:30/3:30/3:00 (Wild/Brutal/Apex) „Die Flut“ mit Moorbrut-Horden und exponentiell steigender Stärke. Treffer pro Tier (nur Tiere in der Warnfläche sterben). Drei Ressourcen: Biomasse (Wachstum), DNA (XP → Werte-Wahl), Bernstein (Geld für Karten-Kokons). Duale Progression (Etappe 17): Werte über Level, Waffen/Relikte/Evolutionen aus Kokons und Bossen; Schreine, Power-ups von Mini-Bossen; Stammes-Fähigkeiten (17d, in Arbeit). Brutnester, Fluch-Totems, Meta-Progression, Sound und adaptive Musik. Apex-Bosse Moosschlund, Sandwurm, Aschenkröte mit Migration ins nächste Biom; UI-Skin „brawl“.

Seit Etappe 27–31 (S25-Feedback, Stand 29.09.2026):
- **Druck:** Hordenwellen zwischen den Fluten; Direktor-Vorsprung je Welt; in Welt n startet die Flut früher und stärker.
- **Steuerung und HUD:** schwebender rechter Joystick; XP-Balken über der Pillenreihe; kein Gebietsbanner.
- **Glutsprung** springt über schmale Hindernisse.
- **Wahl und Slots:** 5 Seltenheitsstufen (grau/grün/blau/violett/gold, Kartenfarbe = Seltenheit); **jeder Kokon ist eine 1-aus-3-Wahl, nichts wird zufällig vergeben**; Slots 4 Waffen / 6 Werte / 6 Relikte (voll = nur Upgrades); **Überladung**, wenn alles maximal ist; **Siegel** (Pool vor dem Run kuratieren).
- **Levelkurve** langsamer (60 + 25L + 6L²).
- **Wasser:** Seen/Moore mit bremsendem Flachufer und blockierender Tiefe (`shaders/water.gdshader`, Lava-Variante).
- **Karte:** weicher Kartennebel (`shaders/map_fog.gdshader`); keine Platzhalter-Symbole mehr.
- **Endboss und Tor:** versiegeltes Tor an der Endboss-Arena jeder Welt; Endboss ≥ 3× Bog-King-LP.
- **Glutpilz-Körbe** mit Sofort-Items (Heilpilz, Zeitstarre, Bildschirm-Biss, Lockruf).
- **Auswertung** „DEIN BUILD“ im Ergebnis.
- Hain-Knollen entfernt. Systeme: `scripts/hunt_world.gd` verbindet alles, Zahlen in `scripts/tuning.gd`, HUD-Komponenten unter `scripts/ui/`, Meta unter `scripts/meta/`. Stand und nächste Schritte: `stages/BACKLOG.md` und die Etappendateien unter `stages/`.

Das ist ein **Prototyp** mit Bot-Balance. Erster S25-Test am 28.09.2026 (`playtests/`). Die APK baut über `tools/export_android.ps1`, aber nur unter dem Windows-Konto `vrxby`: Die Claude-Sitzung läuft als `arufa` und hat keinen Zugriff auf SDK, Java und Exportvorlagen; Git braucht dort `-c safe.directory=…`. Schriften: eingebundene Display-/Body-TTF unter `assets/ui/fonts/`. Captures landen in `previews/` (git-ignoriert, `.gdignore`).

## Starten und prüfen (PowerShell unter Windows)

Godot-Editor: `C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64.exe`; Konsolenversion: `C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe`.

```powershell
$godotExe = 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe'
$projectDir = 'C:\Users\vrxby\Documents\Codex\Godot\Mawlings'
& $godotExe --headless --editor --import --path $projectDir --quit
foreach ($testName in @('smoke','run_model','hunt_flow','survival','evolution','arena','skitter','model_budget','boss')) {
  & $godotExe --headless --path $projectDir --script "res://tests/$testName.gd"
  if ($LASTEXITCODE -ne 0) { throw "Test fehlgeschlagen: $testName" }
}
& $godotExe --headless --fixed-fps 60 --path $projectDir --script 'res://tests/endless_playthrough.gd'
```

Die `tests/capture_*.gd`-Skripte erzeugen Bilder aus der echten Spielkamera. **Ohne `--headless`** ausführen, da `frame_post_draw` sonst hängen kann. Vorschauen und `.godot/` sind regenerierbare, ignorierte Dateien. Im Editor F5 starten; WASD/Pfeiltasten bewegen, Leertaste aktiviert Rally. Für das erste Bossbild kann `tests/capture_boss.gd` ausgeführt werden.

## Claude-Code-Workflow (Orchestrator + Subagenten)

- Etappen stehen in `stages/NN_name.md` mit Abnahmekriterien; Ablauf in `stages/README.md`. Die Hauptsitzung plant, verteilt unabhängige Dateien parallel an Implementierungs-Agenten und legt Schnittstellen vorher fest.
- Prüfagenten in `.claude/agents/`: `godot-tester` (Tests + Playthrough), `visual-reviewer` (rendert und bewertet Bilder), `rules-guard` (Diff gegen Regeln/Fehler). Nach jeder Umsetzungsrunde parallel starten, Mängel beheben, wiederholen.
- Schnellbefehle: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/test.ps1 [-Only boss,smoke]` und `... tools/capture.ps1 [-Only boss]`.
- Hook `tools/hooks/check_gdscript.js` parst jede geänderte `.gd`-Datei mit Godot und meldet Fehler sofort.
- Der Nutzer erlaubt Commits direkt auf `main` nach bestandener Prüfung; kein Push ohne Nachfrage.
- Automatische Godot-Läufe **ohne Ton**: immer `--audio-driver Dummy` übergeben (Captures, Bench, Sonden, Tests). Der Nutzer will beim Arbeiten keine Spielgeräusche hören.
- Godot-Läufe **mit Fenster** (Captures, Perf-Bench, Sonden) immer mit `--screen 1` starten (zweiter Monitor, Hochformat), damit der Hauptbildschirm des Nutzers frei bleibt. `tools/capture.ps1` und `tools/perf.ps1` tun das automatisch (`$env:MAWLINGS_SCREEN` überschreibt).
- Subagenten arbeiten parallel im selben Arbeitsverzeichnis: **kein** `git stash`, `git checkout -- …`, `git reset`, `git clean` oder Commit durch Subagenten. Vergleiche mit dem alten Stand nur über `git show HEAD:<pfad>` oder Kopien im Scratchpad.

## Orientierung

- `DESIGN_BRIEF.md`: bestätigte Regeln.
- `README.md`: Spielablauf, Steuerung, Testbefehle.
- `ART_UI_PLAN.md`: aktuelle Formensprache und nächste Designschritte.
- `stages/NN_*.md`: Etappen mit Kriterien, Ergebnissen und bekannten Grenzen; `stages/REFERENCE_SWARM.md`: Referenzanalyse LoL Swarm; `stages/archive/`: alte Prüfnachweise des Prototyps (Stand 25./26.09.).
- `assets/README.md`: Herkunft, Ordnerstruktur, Optimierung der Modelle.
