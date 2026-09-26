# Etappe 06 – Run-Ziele, Einstieg, UI-Politur, Leistung

Aus `stages/BACKLOG.md`: Punkte 1 (Brutnester & Schreine), 3 (Einstieg), 5 (Leistung, Messung + Qualitätsstufen-API) und 6 (UI-Politur ohne Schrift) parallel.

## Abnahmekriterien
1. **Brutnest:** erscheint seed-deterministisch in der Welt (Marker am Rand, HUD-Zeiger wenn außerhalb), Kreiszone ≈4 m; Schwarm-Anteil in der Zone lädt einen Balken (≈8 s bei vollem Schwarm, schneller mit mehr Tieren drin), bei voll: großer Wachstumsschub als **liegenbleibende Biomasse** (Ressourcenregel: normale Kadaver-Mechanik) + DNA; Fortschritt bleibt beim Verlassen erhalten. 1 Nest aktiv, neues nach Abschluss mit Abstand/Zeit.
2. **Fluch-Totem:** gelegentlich; Berühren = Wahl annehmen (kurz halten, keine Menüunterbrechung): nächster Boss +50 % HP/Schaden, dafür doppelte Beute/DNA bis zu dessen Tod; klar sichtbar markiert, ignorierbar.
3. **Elite-Jäger:** ab ~3 min alle ~3 min ein größerer, gekrönter Jäger mit mehr HP und garantiertem Alpha-Kern.
4. **Balance:** `tools/test.ps1` grün inkl. `balance_regress`; Bot nutzt Nester (einfach: hingehen, wenn kein Gegner warnt); Median-Kurve bleibt in den Zielbereichen aus Etappe 05 (Nester dürfen leicht verlängern).
5. **Einstieg:** Erster Start (Profil ohne Runs) geht direkt in einen Run (Menü wird übersprungen); kontextuelle Tipps nur beim ersten Auftreten je Thema (Bewegen, erster Kill/Fressen, Rally, erste Warnfläche, Mutation, Alpha-Kern, Brutnest, Boss), gespeichert im Profil (`seen_tips`); nie mehr als ein Tipp gleichzeitig, verschwindet selbständig; Tipps über dem Hinweisbanner, Bildmitte frei.
6. **UI-Politur:** Mutationskarten-Körper mit Zell-/Adernstruktur; Verbannen-Knöpfe nicht mehr an der Kartenkante; Popups kollidieren nicht mit der Verlustanzeige; Menü-Einstellungszeilen leichter; alle Texte ≥ 22 px im 900er-Raster, wo bisher kleiner.
7. **Leistung:** Mess-Szene (250 Tiere/120 sichtbar, Boss + 3 Jäger + 3 Skitter + 3 Leaper, alle Angriffsformen, Popups, volles HUD) mit Frame-Zeit, Draw Calls, Objekte, Speicher – Desktop-Werte dokumentiert; `scripts/quality.gd` mit Stufen (niedrig/mittel/hoch) und dokumentierten Schaltern (Schatten-Multimesh, Effektdichte, Deko-Dichte, Menü-3D), noch ohne Einbau in fremde Dateien.

## Dateibesitz
- ZIELE: neu `scripts/objectives/*`, `scripts/hunt_world.gd`, `scripts/hunter.gd` (Elite-Variante), `scripts/tuning.gd` (neue Konstanten), `tests/objectives.gd`, `tests/capture_objectives.gd`, `tests/balance_sim.gd` + `tests/endless_playthrough.gd` (nur Bot: Nester nutzen)
- EINSTIEG: neu `scripts/onboarding.gd` (Node, wird von Main als Kind von HuntWorld/Main angelegt – Einbau-Zeile macht EINSTIEG in `scripts/main.gd`), `scripts/ui/hud_controls.gd` (Tipp-Darstellung), `scripts/menu/menu.gd` (nur Erststart-Weiche), `scripts/meta/profile.gd` (nur `seen_tips`, `runs`-Zähler lesen), `tests/onboarding.gd`, `tests/capture_onboarding.gd`
- POLITUR: `scripts/ui/mutation_screen.gd`, `scripts/ui/hud_overlays.gd`, `scripts/ui/hud_top.gd`, `scripts/ui/menu/menu_sheets.gd`, `scripts/ui/menu/menu_main.gd`, `scripts/ui/ui_frames.gd` + `assets/ui/frames/*`
- LEISTUNG: neu `scripts/quality.gd`, `tests/perf_bench.gd`, `tools/perf.ps1`, `stages/06_perf_notes.md`
- Orchestrator: `tools/test.ps1`, Doku, Zusammenführung

## Ergebnis (26.09.2026)

- **Ziele:** Brutnest (4 m, Füllen nach Schwarmanteil, Fortschritt bleibt, Belohnung 3 liegenbleibende Kadaver mit 44+ Biomasse + 25 DNA), Fluch-Totem vor Bossen (1,5 s halten: Boss +50 %, Beute/DNA ×2 bis zu dessen Tod), Elite-Jäger ab 3:00 (Krone, HP ×4, garantierter Alpha-Kern). Seed-deterministisch, HUD-Zeiger über `hud_objectives.gd`. Balance-Matrix weiter im Ziel: Wild 517 s, Brutal 287 s, Apex 200 s.
- **Einstieg:** Erststart direkt in einen Run; 9 einmalige Tipps (Bewegen, Warnfläche, Boss, Rally, Beute, Kadaver, Alpha-Kern, Mutation, Brutnest) mit Zeigern zu den Knöpfen, gespeichert in `seen_tips`; ohne Profil (Tests/F5) inaktiv.
- **Politur:** Zell-/Adernstruktur im Kartenkörper, leuchtende Icon-Medaillons, Verbannen-Knopf in der Namenszeile, Popups ohne Überlappung mit der Verlustanzeige, leichte Einstellungszeilen, alle Texte ≥ 22 px.
- **Leistung:** `tests/perf_bench.gd` + `tools/perf.ps1`, Messwerte und Empfehlungen in [06_perf_notes.md](06_perf_notes.md) (Desktop: Worst Case 8,1 ms, 530 Draw Calls; Menü 13 ms). Kostentreiber: HUD-Neuzeichnen jedes Frame (~4 ms), 120 Einzelmodelle im Schwarm (~2,5 ms), Kadaver/Effekte ohne geteilte Ressourcen. `scripts/quality.gd` mit 3 Stufen, noch nicht eingebaut.
- **Werkzeug:** `tools/test.ps1` mit Zeitlimit pro Godot-Prozess (hängende Tests werden gezielt beendet).
- **Tests:** 21/21 grün (neu: objectives, onboarding).

Offen: Leistungsoptimierung (Backlog 07), Android-Messung, Boss-Balken zeigt Fluch nicht, Tipp-Panel etwas breit.
