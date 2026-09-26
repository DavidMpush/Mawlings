# Etappe 05 – Spielgefühl, Balance, Lesbarkeit, Android-Vorbereitung

Ziel: Das größte Risiko aus der Konzeptbewertung angehen – der Spaß ist unbewiesen. Kampf soll sich wie „die Horde frisst“ anfühlen, die Schwierigkeit soll steigen statt zu langweilen, alles soll auf dem Handy lesbar sein.

## Abnahmekriterien
1. **Treffer pro Tier (KAMPF):** Flächenangriffe (Jäger-Ring, Skitter-Bahn, Leaper-Zone, Bog-King-Kreis) töten nur Mawlings, deren sichtbare Position in der Fläche liegt, anteilig auf die logische Population hochgerechnet; Schwarm-Mittelpunkt ist nicht mehr allein entscheidend. Ausweichen eines Teils des Schwarms rettet diesen Teil. Nahkampf: Schaden skaliert mit der Zahl der Tiere in Reichweite des Ziels.
2. **Rückmeldung (KAMPF):** „+DNA“ und „+Biomasse“ schweben kurz an der Kill-Stelle (gebündelt); Königs-Kill = kurze Zeitlupe (≈0,6 s), Kamera-Zoom, großer Moment („KÖNIG VERSCHLUNGEN“).
3. **Balance (BALANCE):** Simulationsharness über mehrere Seeds, Stämme, Schwierigkeiten und einfache Bot-Strategien; Ziel-Kurve Wild: Bot überlebt 2 min sicher, stirbt median zwischen 6 und 12 min; Brutal median 4–7 min; Apex median 2,5–5 min. Kein Build dominiert extrem. Werte in `tuning.gd`/Formen dokumentiert.
4. **Lesbarkeit (FARBEN):** alle 6 Stämme auf Moosgrün und Sand klar sichtbar, keine Verwechslung mit Beute (Türkis) oder Gegnern; Blumen kollidieren farblich nicht mit Mawlings; Warnflächen zusätzlich über Muster/Kontur unterscheidbar (Farbenblind-tauglich), eine Einstellung „Farbenblind-Modus“ ist vorbereitet.
5. **Menü (MENÜ):** Seed des nächsten Runs sichtbar (kurzer Code), Knopf „TAGES-BRUT“ startet mit `Profile.daily_seed()`, eigener Tagesrekord; Menü-Layoutwünsche aus Etappe 04 umgesetzt.
6. **Android (Orchestrator):** `export_presets.cfg` (Hochformat, arm64, Debug), Prüf- und Exportskript `tools/export_android.ps1`; echter Export sobald Exportvorlagen (Nutzerfreigabe) und Gerät vorhanden.
7. Alle Tests grün, neue Tests für Kriterium 1, 3 (Harness als Test mit Toleranzen), 5.

## Dateibesitz
- KAMPF: `scripts/hunt_world.gd`, `scripts/swarm.gd`, `scripts/hunter.gd`, `scripts/skitter.gd`, `scripts/mire_leaper.gd`, `scripts/bog_king.gd` (nur Treffer-Geometrie: Methode `hit_fraction(points)` o. ä.), `scripts/main.gd` (Zeitlupe/Zoom), `scripts/ui/hud_overlays.gd` (Popups/Königsmoment), `tests/per_unit_hits.gd`
- BALANCE: `scripts/tuning.gd`, `scripts/attack_forms.gd` (nur Zahlen), `scripts/evolution.gd` (nur Zahlen), `scripts/meta/meta_data.gd` (nur Schwierigkeits-/Upgrade-Zahlen), `tests/balance_sim.gd`, `tools/balance.ps1`
- FARBEN: `scripts/meta/meta_data.gd` (nur Stamm-Farben – mit BALANCE abgestimmt: nur `tint`-Felder ändern), `scripts/arena.gd` (Blumen/Deko-Farben), `shaders/*` (Kontur/Outline), `scripts/ui/ui_style.gd` (Farbenblind-Palette), Warnflächen-Darstellung in `scripts/fx.gd` oder neuem `scripts/telegraph_style.gd`
- MENÜ: `scripts/menu/menu.gd`, `scripts/ui/menu/*`, `scripts/meta/profile.gd` (Tagesrekord), `tests/menu.gd`
- Orchestrator: `export_presets.cfg`, `tools/export_android.ps1`, `tools/test.ps1`, Doku

## Ergebnis (26.09.2026)

- **Kampf:** Flächenangriffe treffen nur den Anteil sichtbarer Tiere in der Zone (`contains`/`hit_fraction` je Gegner, Verlust = ceil(Stärke × Anteil), auf logische Population hochgerechnet; fallende Tiere sind die in der Zone). Nahkampf skaliert mit beißenden Tieren (Kill-Zeiten ±5 % zur Vorversion). Popups „+DNA/+Biomasse“ gebündelt an der Kill-Stelle. Königsmoment: Zeitlupe 0,3 für 0,6 s, Kamera-Zoom, Banner „KÖNIG VERSCHLUNGEN“ (headless aus).
- **Balance:** Harness `tests/balance_sim.gd` + `tools/balance.ps1` (Bot mit 0,45 s Reaktionszeit und 12 % übersehenen Warnungen). Median-Tod Wild 547 s, Brutal 293 s, Apex 206 s – alle in der Zielkurve; Stamm-Spreizung ≤ 22 %, Angriffsformen 33 % (vorher 97 %). Apex HP ×1,8 / Schaden ×1,5 / Verdopplung 48 s, Brutal HP ×2,5; Sporenwolke stärker, Säurespucker schwächer, Stachelrücken stärker. Regressionstest in `tools/test.ps1`.
- **Lesbarkeit:** neue Stammfarben (Sporling Rosa, Knochenkiefer Knochenweiß, Flinkzahn Kobalt, Ätzmaul Säuregelb, Nachtmaul Mitternacht), dunkle Silhouettenkontur (Kontrast ≥ 4,4:1 auf Moos und Sand), Lavendel-Blumen; Warnflächen mit Mustern (Jäger Streifenring, Skitter Chevrons, Leaper Punkte + Fadenkreuz, Boss Speichen in Weinrot/Gold) und Farbenblind-Palette (Okabe-Ito).
- **Menü:** Karten-Code (6 Zeichen) mit Neu würfeln, TAGES-BRUT mit Tagesrekord, Einstellungen (Ton, Vibration, Farbenblind) im Profil und in der RunConfig, Drückzustände, luftigeres Layout.
- **Android:** `export_presets.cfg` (arm64, Debug, Vibration) und `tools/export_android.ps1` (prüft Vorlagen, SDK/JDK, exportiert, installiert, startet). Blockiert durch fehlende Exportvorlagen, falschen Java-Pfad und kein verbundenes Gerät.
- **Tests:** 19/19 grün (neu: per_unit_hits, balance_regress). Playthrough `population=244 peak=244 kills=33 lost=56`.

Offen: Handtest; Popups überlappen gelegentlich die Verlustanzeige; Wasser nah am Beute-Türkis; Sporling auf Brutal schwach; Boss-Erstauftritt je Schwierigkeit nicht getrennt.
