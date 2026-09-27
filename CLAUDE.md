# MAWLINGS — Projektkontext für Claude Code

Arbeite im **Godot-Projekt dieses Verzeichnisses**. Antworte dem Nutzer auf Deutsch. Das alte Unity-Projekt unter `C:\Users\vrxby\Documents\Codex\Swarm` ist nur eine historische Referenz; ändere es nicht. Die verbindliche Spielrichtung steht in `DESIGN_BRIEF.md`, die gewünschte Arbeitsweise zusätzlich in `AGENTS.md`. Lies vor einer größeren Änderung auch `README.md`, `ART_UI_PLAN.md` und bei Bedarf `CLAUDE_HANDOFF.md`.

## Arbeitsweise

- Der Nutzer möchte **größere, zusammenhängende, spielbare Etappen**. Bei „weiter“ selbstständig eine sinnvolle Etappe mit Mechanik, Bedienung, visueller Prüfung, Fehlerkorrekturen und Dokumentation abschließen. Nicht nach jeder Kleinigkeit um Freigabe bitten.
- Erkläre Fortschritt knapp und regelmäßig. Beurteile Spielgefühl und Design ehrlich anhand der gerenderten Spielansicht, nicht nur anhand bestandener Tests.
- Halte die Arena offen und gut lesbar. Ziel ist vereinfachte, farbige Fantasy-Optik im mobilen Hochformat. Inspirationsbilder sind keine exakten Vorgaben für UI, Modelle oder Karte.
- Ressourcen bleiben innerhalb eines Runs bis zum vollständigen Verbrauch liegen. Ein Run endet ausschließlich bei Aussterben. Der Druck steigt exponentiell. Bewegung liegt rechts, Rally links.
- Bestehende Dateien und Nutzer-Assets erhalten; Änderungen im Git-Repository auf eine prüfbare Etappe begrenzen. Nach der Arbeit Tests und `git status` prüfen, `README.md` sowie relevante Prüfnachweise aktualisieren.

## Aktueller Stand

Godot 4.7.2. Startszene ist das Menü `scenes/menu.tscn` (Brutstätte: Stämme, Biome, Schwierigkeit, Upgrades, Trophäen, Chronik, Tages-Brut, Einstellungen); der Run läuft in `scenes/main.tscn`. Ein Run beginnt mit **einem Anführer** (3 LP, Nachfolger bei Tod); neue Mawlings entstehen per Zellteilung aus Biomasse, logisches Limit 250, sichtbar max. 120 (ein MultiMesh). Seed-generierte, endlose Arena (Verdant Maw; Glutsumpf mit Lava-Ausbrüchen vorbereitet). Gegner: Nibbler (schnappen zurück), Jäger/Elite-Jäger, Skitter, Mire Leaper, Bog King (ab ~2 min), ab 5/4/3 min (Wild/Brutal/Apex) „Die Flut“ mit Moorbrut-Horden und exponentiell steigender Stärke. Treffer pro Tier (nur Tiere in der Warnfläche sterben). Angriffsformen, Anlagen, Evolutionen per Alpha-Kern, Brutnester, Fluch-Totems, Meta-Progression, Sound und adaptive Musik. Apex-Boss „Moosschlund“ ist gebaut, aber noch nicht eingebunden (Backlog). Systeme: `scripts/hunt_world.gd` verbindet alles, Zahlen in `scripts/tuning.gd`, HUD-Komponenten unter `scripts/ui/`, Meta unter `scripts/meta/`. Stand und nächste Schritte: `stages/BACKLOG.md` und die Etappendateien unter `stages/`.

Das ist ein **Prototyp** mit Bot-Balance, aber ohne längeren Handtest und ohne Messung auf dem Samsung S25 (Export blockiert: Exportvorlagen/Java-Pfad/Gerät). Schriften sind noch Fallback.

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
- `BOSS_VERIFICATION.md`, weitere `*_VERIFICATION.md`: Prüfstand und bekannte Grenzen.
- `assets/README.md`: Herkunft, Ordnerstruktur, Optimierung der Modelle.
- `CLAUDE_HANDOFF.md`: Übergabestand und mögliche erste Etappe.
