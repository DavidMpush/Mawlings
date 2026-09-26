# MAWLINGS — Projektkontext für Claude Code

Arbeite im **Godot-Projekt dieses Verzeichnisses**. Antworte dem Nutzer auf Deutsch. Das alte Unity-Projekt unter `C:\Users\vrxby\Documents\Codex\Swarm` ist nur eine historische Referenz; ändere es nicht. Die verbindliche Spielrichtung steht in `DESIGN_BRIEF.md`, die gewünschte Arbeitsweise zusätzlich in `AGENTS.md`. Lies vor einer größeren Änderung auch `README.md`, `ART_UI_PLAN.md` und bei Bedarf `CLAUDE_HANDOFF.md`.

## Arbeitsweise

- Der Nutzer möchte **größere, zusammenhängende, spielbare Etappen**. Bei „weiter“ selbstständig eine sinnvolle Etappe mit Mechanik, Bedienung, visueller Prüfung, Fehlerkorrekturen und Dokumentation abschließen. Nicht nach jeder Kleinigkeit um Freigabe bitten.
- Erkläre Fortschritt knapp und regelmäßig. Beurteile Spielgefühl und Design ehrlich anhand der gerenderten Spielansicht, nicht nur anhand bestandener Tests.
- Halte die Arena offen und gut lesbar. Ziel ist vereinfachte, farbige Fantasy-Optik im mobilen Hochformat. Inspirationsbilder sind keine exakten Vorgaben für UI, Modelle oder Karte.
- Ressourcen bleiben innerhalb eines Runs bis zum vollständigen Verbrauch liegen. Ein Run endet ausschließlich bei Aussterben. Der Druck steigt exponentiell. Bewegung liegt rechts, Rally links.
- Bestehende Dateien und Nutzer-Assets erhalten; Änderungen im Git-Repository auf eine prüfbare Etappe begrenzen. Nach der Arbeit Tests und `git status` prüfen, `README.md` sowie relevante Prüfnachweise aktualisieren.

## Aktueller Stand

Godot 4.7.2, Hauptszene `scenes/main.tscn`. Spielstart mit 25 Mawlings, logisches Limit 250, maximal 120 sichtbare Mawling-Modelle. Endlose, offene 3D-Arena mit wenigen Stein-Engstellen. Beute, Jäger, Skitter, Bog King, persistente Kadaver, Biomasse-Wachstum, sechs Mutationen mit je drei Rängen, Pause und Neustart sind spielbar. Der Bog King erscheint erstmals nach etwa 90 Sekunden. `scripts/hunt_world.gd` verbindet die Systeme; Zahlen stehen in `scripts/tuning.gd`. `scripts/touch_controls.gd` zeichnet das Hochformat-HUD. Rohmodelle liegen in `assets/source/`, reduzierte Spielmodelle in `assets/gameplay/characters/`.

Das ist ein **Prototyp**, kein fertig ausbalanciertes Spiel. Kampf und Treffer nutzen den Schwarmmittelpunkt; einzelne Tiere haben keine eigene Kampf-KI. Es fehlen Animationen, Audio, Geräteprofiling auf dem Samsung S25 und eine längere manuelle Spielgefühl-Prüfung. Die dauerhaften Kadaver werden in Godot derzeit linear durchsucht; das ist für sehr lange Runs noch nicht optimiert. Für neuen Content erst die Lesbarkeit und bestehende Spielschleife festigen.

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

## Orientierung

- `DESIGN_BRIEF.md`: bestätigte Regeln.
- `README.md`: Spielablauf, Steuerung, Testbefehle.
- `ART_UI_PLAN.md`: aktuelle Formensprache und nächste Designschritte.
- `BOSS_VERIFICATION.md`, weitere `*_VERIFICATION.md`: Prüfstand und bekannte Grenzen.
- `assets/README.md`: Herkunft, Ordnerstruktur, Optimierung der Modelle.
- `CLAUDE_HANDOFF.md`: Übergabestand und mögliche erste Etappe.
