# Backlog – nächste Etappen

Reihenfolge = Priorität. Jede Etappe wird nach `stages/README.md` abgearbeitet (Etappendatei mit Kriterien, parallele Agenten mit getrenntem Dateibesitz, Tests, Bildprüfung, Commit, Bericht). Blockierte Punkte wandern nach „Wartet auf Nutzer“; die Schleife überspringt sie.

## Offen

1. **06 Run-Inhalt: Brutnester & Schreine** – Brutnest (Zone mit dem Schwarm halten → Wachstumsschub), Fluch-Totem (stärkerer nächster Boss, doppelte Beute), Elite-Jäger mit Alpha-Kern-Garantie; seed-deterministisch platziert, bleiben bis zum Verbrauch (Ressourcenregel). Kriterium: Bot-Balance bleibt in der Zielkurve.
2. **07 Apex-Boss & Migration** – eigener Apex-Boss für Verdant Maw (~8 min), Migrationsschlund nach Sieg, Wechsel ins nächste Biom mit Schwarm und Build, Run bleibt endlos. Glutsumpf als zweites Biom mit eigener Boden-/Farbwelt (Lava-Warnflächen) – Modelle soweit vorhanden, sonst Platzhalter.
3. **08 Einstieg & Onboarding** – erste 60 s ohne Text: 10 s erster Kill, 30 s erstes Wachstum, 60 s erste Mutation; kontextuelle Hinweise nur beim ersten Auftreten (im Profil gemerkt); Menü-Erststart direkt ins Spiel.
4. **09 Teilen** – Teilen-Karte am Run-Ende (Zeit, Peak, Build, Seed-Code), lokale Bestenliste je Tages-Brut, Vorbereitung Clip-Export (letzte 15 s, 9:16) soweit ohne Plattform-SDK möglich.
5. **10 Leistung & Qualitätsstufen** – Profiling-Szene (250 Tiere, Boss, alle Effekte), Qualitätsstufen (Schatten, Effektdichte, SubViewport im Menü, Deko-Dichte), Ziel 60 fps auf Mittelklasse; Messwerte dokumentieren.
6. **11 UI-Politur 2** – Kartenkörper mit Zellstruktur, Verbannen-Knöpfe, Popups vs. Verlustlabel, kleine Texte ≥ 22 px, Menü-Einstellungen leichter; sobald Schrift da ist: vollständiger Typografie-Pass.

## Wartet auf Nutzer

- **Schriften:** Freigabe zum Laden zweier OFL-Schriften aus dem offiziellen Google-Fonts-Repository (Titel: Anton / Bebas Neue / Lilita One; Text: Nunito / Figtree) → `assets/ui/fonts/display.ttf`, `body.ttf`.
- **Android-Test:** Godot-Exportvorlagen 4.7.2 installieren (Editor → Exportvorlagen verwalten, ~1 GB) oder Download freigeben; Java-Pfad in den Editoreinstellungen auf `G:\Users\David\Java` korrigieren; Handy mit USB-Debugging anschließen → `tools/export_android.ps1`.
- **Modelle (Hunyuan3D):** Jäger (`08_hunter.png`), Skitter, Biomasse-Knoten (`05_biomass_node.png`), Pilz (`04_fungus.png`), je ein Modell pro Stamm oder Freigabe, Stämme nur farblich zu unterscheiden; Apex-Boss-Entwurf.
- **Entscheidungen:** Name/Markenprüfung (Überschneidung „Mawling“ in Hollow Knight: Silksong), Monetarisierungsmodell, Package-Name für Android (Platzhalter `com.jaysolution.mawlings`).
- **Handtest:** 5–10 Minuten Spielgefühl (Treffer pro Tier, Königsmoment, Balance Wild/Brutal, Lesbarkeit der Farben).

## Erledigt
- 01 Bewegung & Lesbarkeit · 02 Welt & Assets · 03 Progression · 04 UI-Komponenten · 05 Spielgefühl, Balance, Lesbarkeit
