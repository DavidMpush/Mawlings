# Etappen-Protokoll

Jede größere Etappe hat eine Datei `stages/NN_name.md` mit Ziel, Abnahmekriterien und Ergebnisprotokoll. Die Hauptsitzung von Claude Code steuert die Etappe als Orchestrator:

1. **Planen:** Stage-Datei mit messbaren Abnahmekriterien anlegen (Mechanik, Lesbarkeit im Hochformat, Regeln aus `DESIGN_BRIEF.md`, Tests).
2. **Umsetzen:** unabhängige Teile parallel an Subagenten mit klar getrennten Dateien vergeben; Schnittstellen vorher in der Stage-Datei festlegen. Der Hook `tools/hooks/check_gdscript.js` prüft jede geänderte `.gd`-Datei sofort auf Parse-Fehler.
3. **Prüfen (parallel):** `godot-tester` (Tests + Playthrough), `visual-reviewer` (gerenderte Bilder gegen Kriterien), `rules-guard` (Diff gegen Regeln und Fehler).
4. **Korrigieren und wiederholen**, bis alle Kriterien erfüllt sind (höchstens etwa fünf Runden, danach offene Punkte dokumentieren).
5. **Abschließen:** README/Prüfnachweise aktualisieren, Ergebnis in die Stage-Datei schreiben, auf `main` committen.

Befehle:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test.ps1            # alle Tests + Playthrough
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test.ps1 -Only boss # einzelne Tests
powershell -NoProfile -ExecutionPolicy Bypass -File tools/capture.ps1         # alle Prüfbilder (mit Fenster)
```

Grenze: Standbilder und Bot-Runs ersetzen keinen kurzen Handtest des Spielgefühls durch den Nutzer am Ende jeder Etappe.
