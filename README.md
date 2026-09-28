# MAWLINGS

Mobiles Schwarm-Survival im Hochformat, gebaut mit Godot **4.7.2**. Projektordner `C:\Users\vrxby\Documents\Codex\Godot\Mawlings`, eigenes Git-Repository. Das alte Unity-Projekt ist nur noch Referenz. Verbindliche Regeln: [DESIGN_BRIEF.md](DESIGN_BRIEF.md); Stil: [ART_UI_PLAN.md](ART_UI_PLAN.md); nächste Schritte: [stages/BACKLOG.md](stages/BACKLOG.md).

Stand: spielbarer Prototyp mit Bot-Balance. Ein längerer Handtest und die Messung auf dem Zielgerät (Samsung S25) stehen noch aus.

## Starten

In Godot den Ordner als Projekt öffnen und **F5** drücken. Das Spiel startet im Menü (`scenes/menu.tscn`), der Run läuft in `scenes/main.tscn` (**F6**). Ohne Editor:

```powershell
& 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64.exe' --path 'C:\Users\vrxby\Documents\Codex\Godot\Mawlings'
```

**Steuerung:**

| Aktion | Touch | Tastatur |
|---|---|---|
| Bewegen | rechte Hand | WASD / Pfeiltasten |
| Rally (verdichten, stärker beißen, größerer Sog) | linke Hand | Leertaste |
| Pause | Pause-Knopf | P / Esc |
| Neustart nach dem Aussterben | NEUER RUN | R / Enter |
| Karte groß | Tipp auf die Minimap | – |
| Mutation wählen | Karte antippen | 1 / 2 / 3 |

## Spielablauf

- **Start:** Ein Run beginnt mit einem einzelnen **Anführer**. Neue Mawlings entstehen per Zellteilung aus Biomasse. Die Population hat **kein Limit**; bis 120 Tiere sind einzeln sichtbar, darüber steht jedes Modell für mehrere Tiere.
- **Kampf und Ende:** Der Schwarm greift in der Nähe automatisch an. Warnflächen treffen nur die Tiere, die darin stehen. Der Zeitdruck verdoppelt sich regelmäßig. Ab 4:30 / 4:00 / 3:00 (Wild / Brutal / Apex) kommt **„Die Flut“**, Horden mit exponentiell wachsender Stärke. **Nur Aussterben beendet einen Run.**
- **Anführer:** Er hat **100 LP** mit einem Balken über dem Kopf. Treffer kosten je Angriff LP, danach ist er kurz unverwundbar. Heilung gibt es über Lebensraub, Regeneration und Meilensteine. Fällt er, übernimmt ein Nachfolger mit 80 % des Maximums.
- **Meta:** Menü **Brutstätte** mit 6 Stämmen (Glutmaw, Sporling, Knochenkiefer, Flinkzahn, Ätzmaul, Nachtmaul), 3 Schwierigkeiten, Brutkammer-Upgrades, Trophäen, Chronik, Tages-Brut und Einstellungen. Die Meta-Währung ist Essenz; Bosse geben Königszähne.
- **Kodex:** Sammlung mit den Tabs Waffen, Relikte, Werte, Power-ups und Bosse; der Knopf KODEX steht im Trophäen-Blatt. Ein Eintrag gilt als entdeckt, sobald er einmal in einem Run erhalten oder besiegt wurde. Das Profil speichert ihn in `codex_seen`; unentdeckte Einträge erscheinen als Silhouette mit „???“ und Fundort. Katalog: `scripts/meta/codex.gd`.

## Welt

- **Karte:** begrenzte, seed-generierte **Erkundungskarte**. Solo 4 × 4 Regionen = 336 m, Duo 5 × 5, Trio/Quad 6 × 6.
  - Jede Region würfelt eine Landschaft: Wiese, Wald, Dickicht, Ruinen, Felsrücken, Sumpf oder Labyrinth. Der Rand ist natürlich.
  - Orte liegen zufällig: Kokons, Schreine, Nester, Totems, Hain-Schätze, Elite-Lager, Boss-Arena, Migrationsschlund.
  - Die Minimap zeigt die ganze Karte mit Nebel; Orte erscheinen erst nach der Entdeckung.
  - Seed 0 (Tests) bleibt die offene Klassik-Karte.
- **Biome im Kreis:** **Verdant Maw → Dürrschlund** (Wüste: Treibsand, Sandstürme) **→ Glutsumpf** (Lava-Ausbrüche) → wieder Verdant Maw. Jeder Durchlauf macht die Apex-Bosse stärker. Nach dem Apex öffnet sich ein Schlund; wer hineinläuft, wandert mit Build und Flut auf eine neue Karte.
- **Gegner:**
  - Nibbler (schnappen zurück), Jäger und Elite-Jäger (Ring-Angriff), Skitter (Sprintbahn), Mire Leaper (Sprungzone).
  - Bog King: Mini-Boss mit Stampf-Angriff.
  - Moorbrut: Horde der Flut.
  - Sandmaden: nur in der Wüste.
- **Apex-Bosse:** Moosschlund (Verdant Maw), Sandwurm (Dürrschlund), Aschenkröte (Glutsumpf).
- **Gefahren:** Alle Angriffe sind angekündigt. Es gibt drei Formen: Kontur (kommt gleich), Fläche (liegt da), großer Ring (läuft gerade). Gefahr ist immer Magenta/Pink.

## Drei Ressourcen

| Ressource | Farbe | Herkunft | Zweck |
|---|---|---|---|
| **Biomasse** | grün | Gegner-Kills | Wachstum, 3,5 je Mawling |
| **DNA** | blau | Kills, Bernsteinknollen | Erfahrung: violetter XP-Balken oben, Level → Werte-Wahl |
| **Bernstein** | gold | Kills, Bernsteinknollen, Hain-Schätze | Karten-Kokons, verfällt am Run-Ende |

Beute platzt in Kristalle und Münzen, die liegen bleiben, bis sie eingesammelt sind. Der **Magnet** zieht sie heran; er wächst mit dem Schwarm und bei Rally. Ein **Lockruf** holt alle Kristalle der Karte auf einmal.

## Progression im Run (zwei Spuren)

- **Werte** kommen nur über Level (DNA).
  - Jede Wahl bietet 3 Karten mit Seltenheit (gewöhnlich/selten/episch/legendär); Glück hebt die Seltenheit.
  - 15 Werte mit 5 Rängen: Biss, Kritbiss, Angriffstempo, Reichweite, Rudelinstinkt, Knochenpanzer, Fluchtreflex, Anführerherz, Regeneration, Lebensraub, Brutrate, Lockduft, Genfluss, Sprinter, Glück.
  - Neu würfeln, Verbannen und Überspringen werden über die Meta freigeschaltet.
- **Arsenal** kommt nur aus Kokons und Bossen.
  - 10 Waffen mit Rang 1–5, 4 Waffenplätze.
  - 21 stapelbare Relikte.
  - 6 Evolutionen: Waffe auf Rang 5 + passendes Relikt → Boss-Kokon.
- **Kokons:**
  - Karten-Kokons kosten Bernstein (steigend).
  - Gratis sind der Start-Kokon, goldene Kokons (mindestens episch), Elite-Kokons und Boss-Kokons (1 aus 3).
  - Zum Öffnen den Schwarm 1 s im Kokon halten.
- **Schreine:** Den Schwarm im Steinkreis halten lädt ihn auf; voll gibt es eine Werte-Wahl mit mindestens seltenen Karten.
- **Power-ups** nur von Mini-Bossen (Elite, Bog King, Apex): Rausch, Blutrausch, Magnetsturm, Chitinschild, Raserei, Brutwelle. Aufsammeln nur durch Hinlaufen.
- **Stammes-Fähigkeiten** (Etappe 17d, in Arbeit): eine aktive Fähigkeit je Stamm mit eigenem Knopf und Cooldown. Die Stammkarte im Menü zeigt Name, Kurztext und Abklingzeit.

## Code-Überblick

- `scripts/hunt_world.gd` verbindet alle Systeme; die Zahlen stehen in `scripts/tuning.gd`.
- Progression: `scripts/evolution.gd` (Fassade), `scripts/progression/`.
- Welt: `scripts/arena*.gd`, `scripts/map_explore.gd`, `scripts/flow_field.gd`.
- Beute: `scripts/loot.gd`, `scripts/loot_nodes.gd`, `scripts/chests.gd`, `scripts/powerups.gd`, `scripts/shrines.gd`.
- HUD: `scripts/ui/`, Skin **„brawl“** (Kit `scripts/ui/ui_kit_brawl.gd`). Meta: `scripts/meta/`.
- Schriften liegen unter `assets/ui/fonts/`: Display und Body als eingebundene TTF mit Lizenz.
- Assets und ihre Herkunft: [assets/README.md](assets/README.md). Die Nutzer-Originale in `assets/*.glb` importiert Godot nicht (`importer="skip"`); das Spiel nutzt die reduzierten Versionen unter `assets/gameplay/`.

## Tests und Werkzeuge

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test.ps1              # alle Tests + Durchlauf + Balance-Regression
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test.ps1 -Only smoke,menu
powershell -NoProfile -ExecutionPolicy Bypass -File tools/capture.ps1 -Only boss # Prüfbilder (mit Fenster)
powershell -NoProfile -ExecutionPolicy Bypass -File tools/perf.ps1              # Leistungsmessung
powershell -NoProfile -ExecutionPolicy Bypass -File tools/balance.ps1           # Balance-Bot
powershell -NoProfile -ExecutionPolicy Bypass -File tools/export_android.ps1    # APK
```

- Godot-Läufe starten immer mit `--audio-driver Dummy`; Fenster-Läufe mit `--screen 1`.
- Captures (`tests/capture_*.gd`) laufen ohne `--headless` und schreiben nach **`previews/`**. Der Ordner ist git-ignoriert und wird von Godot per `.gdignore` nicht importiert.
- Der Balance-Bot `tests/balance_sim.gd` misst die Zielkurven: Wild 390–510 s, Brutal 300–390 s, Apex 210–270 s.

## Etappen

- Etappen-Dateien: [stages/](stages/). Ablauf: [stages/README.md](stages/README.md).
- Aktuell:
  - [15 UI (Kit)](stages/15_ui_rework.md)
  - [16 Beute und Magnet](stages/16_loot_magnet.md)
  - [17 Duale Progression](stages/17_dual_progression.md)
  - [17b/17c Schwarm ohne Limit, Anführer-LP](stages/17bc_swarm_leader.md)
  - [17d Fähigkeiten](stages/17d_abilities.md)
  - [18 Begrenzte Karte](stages/18_bounded_map.md)
  - [18c Erkundungskarte](stages/18c_exploration_map.md)
  - [19 Wüste](stages/19_desert.md)
  - [20 Gefahren-Lesbarkeit](stages/20_danger_readability.md)
- Ältere Etappen (01–10) und archivierte Prüfnachweise stehen ebenfalls unter `stages/`.

Arbeitsweise: größere, zusammenhängende, spielbare Etappen (siehe `AGENTS.md`, `CLAUDE.md`).
