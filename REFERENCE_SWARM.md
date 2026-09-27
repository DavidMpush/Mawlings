# Referenzanalyse: League of Legends „Swarm“

Quelle: YouTube-Video „SOLO Jinx destroys Extreme Aatrox with 700% Damage | Swarm League of Legends“ (https://www.youtube.com/watch?v=Zzu2Y27fIlY, ca. 19 min, 1080p). Ausgewertet am 2026-09-27 über rund 45 Standbilder, Nahaufnahmen und kurze Bildfolgen (0,1–0,25 s Abstand). **Nicht beurteilt:** Ton, flüssige Bewegung, Kamerawackeln und Treffer-Stopps (nur indirekt vermutet).

Zweck: Herausarbeiten, **warum** das Spiel hochwertig wirkt, und was sich auf MAWLINGS übertragen lässt. Es ist eine Inspiration und keine Vorlage. Swarm ist ein PC-Spiel im Querformat mit Studio-Budget; MAWLINGS bleibt mobiles Hochformat mit vereinfachter Fantasy-Optik (siehe `DESIGN_BRIEF.md`, `ART_UI_PLAN.md`).

## Beobachtungen

### Farbe und Lesbarkeit
- **Ruhiger Boden, laute Effekte.** Der Boden ist fast unbunt: grauer Beton mit Rissen, dezente gelbe Linien, Wasser als Akzent. Gesättigte, helle Farben gibt es nur für spielrelevante Dinge. Deshalb bleiben auch Hunderte Effekte lesbar.
- **Farben mit fester Bedeutung.** Eigene Aktionen sind Cyan/Blau (Geschosse, Schadenszahlen, Erfahrung). Gefahr ist Rot/Pink. Beute ist Gold. Gegner sind dunkel-violett, heben sich als Masse vom Boden ab und konkurrieren nicht mit den Effekten.
- **Die Spielfigur bleibt auffindbar.** Sie hat einen hellen Ring am Boden und eine kleine Lebensleiste mit Namen und Level direkt darüber. Sie ist auch dann sichtbar, wenn der ganze Bildschirm voller Geschosse ist. Die Figur ist nur etwa 3–4 % der Bildhöhe groß; die Kamera zeigt viel Umgebung.

### Treffer und Gefahr
- **Schadenszahlen mit Rangordnung.** Normale Treffer sind klein und cyan. Kritische Treffer sind groß mit Zacken-Symbol, bis zu dreifacher Größe. Zahlen von Begleitern/Fahrzeugen sind weiß. Viele Zahlen stapeln sich leicht versetzt: Man erfasst „viel Schaden“, ohne zu lesen.
- **Treffer am Spieler** zeigen sich als orange Zahl an der Figur plus kurzer roter Blitz und rote Bodenscheibe (etwa 0,2 s). Man sieht den Treffer ohne Blick auf den Lebensbalken.
- **Drei Formen für Gefahr:**
  - dünne rote Kreislinie = „kommt gleich“ (Explosionsradius von Bomben-Gegnern, schon vor der Detonation),
  - pinke, wabernde Bodenfläche = „liegt da“ (anhaltende Schadenszone),
  - großer Ring aus Pink und Violett um eine Zone = „Ereignis läuft“.
- Die angekündigten Angriffe haben kräftige rote Kreise mit Zacken als eigene Warnsprache.

### Wachstum und Belohnung
- **Die Stärke ist sichtbar.** Am Anfang gibt es nur einen einzelnen Schuss, später Fächer und Ringe aus Geschossen, Lichtsäulen, Minen und Flächen. Das Wachstum zeigt sich auf dem Bildschirm, nicht nur als Zahl.
- **Einsammeln:** drei klar unterscheidbare Sorten (blau = Erfahrung, gold = Münzen, violett = Besonderes), dazu große drehende Kristalle und Karten als seltene Beute. Münzen fliegen als Kette in einer Bahn zur Figur. **„+9 +3 +3“ wird binnen etwa 0,25 s zu einer Zahl „+36“ zusammengezählt**: Viel Beute fühlt sich gut an, ohne das Bild zu überladen.
- **Moment beim Aufleveln:** Das Bild wird violett eingefärbt und entsättigt, eine Lichtsäule schießt auf die Figur, danach erscheinen die Karten.
- **Kartenauswahl:** drei große Karten mit Leuchtrand, Symbol, Titel, Kurztext und „NEW“-Markierung. Zwei Kartenarten sind farblich getrennt (violett = Werte-Bonus, türkis mit Bild = neue Waffe). Es gibt eine Neuwürfeln-Taste mit Zähler und einen **Countdown**, sodass die Spannung auch in der Pause bleibt. Der Hintergrund ist abgedunkelt.
- **Info-Box** beim Überfahren einer Waffe: Beschreibung, Verkaufspreis und **welche Kombination zur Weiterentwicklung führt**. Das macht die Build-Planung sichtbar.
- **Fahrzeug-Moment:** Zeitweise sitzt die Figur in einem Panzer, ein kurzer „jetzt bin ich stark“-Höhepunkt.

### Welt und Ablauf
- **Kartenzonen:** Stadtbeton mit Wasserbecken, Wiese mit Erdwegen, Felsen und Palmen, Industriebereich mit Mauern und Leuchten. Die Übergänge sind weich, die Minikarte zeigt die Zonen farbig. Große Objekte stehen nur am Rand der Zonen, die Kampfflächen bleiben frei. Der Run fühlt sich wie eine Reise an.
- **Nebenaufgaben mit Timer** mitten im Kampf (z. B. einem Punkt hinterherlaufen, eine Zone halten).
- **Figuren kommentieren:** Porträt mit Sprechblase, immer am linken Rand und nie in der Mitte. Auch der Boss spricht vor seinem Auftritt. Oben links laufen dezente, halbtransparente Systemmeldungen.
- **Gegnerwellen mit Form:** erst verstreut, dann Schwärme, dann Bomben-Käfer mit rotem Leuchten, gepanzerte Gruppen und Elite-Gegner.

### HUD
- Eine einzige Leiste unten in der Mitte: Porträt mit Level, Waffen-Symbole mit Stufe, Lebens- und Erfahrungsbalken. Die Werte-Boni stehen als kleine Symbole mit Zahl darüber.
- Oben stehen nur der Timer in einem Rahmen und die Ressourcen oben rechts; die Minikarte sitzt unten rechts. Die Bildmitte bleibt frei. Alle Elemente haben den gleichen Rahmenstil.

### Boss und Run-Ende
- **Boss-Dramaturgie:** Erst spricht der Boss, dann erscheint oben ein großer Lebensbalken mit Porträt und exakten Zahlen. Beim Sieg leuchtet das ganze Bild, danach folgt ein schlichtes „VICTORY“ auf dunklem Grund. Die Abfolge ist Höhepunkt, Ruhe, Auswertung.
- **Abschlussbildschirm:** Statistiken (Gesamtschaden, pro Minute, Gold) und der gewählte Build als Symbole. Dazu kommen **Aufgaben mit Fortschrittsbalken und Belohnung** (z. B. „Boss mit jeder Figur besiegen 2/9“), direkt über „Nochmal spielen“. Man hat beim Verlassen schon einen Grund für den nächsten Run.

## Übertragung auf MAWLINGS

Priorisiert nach Wirkung pro Aufwand. Die Nummern dienen nur der Referenz; die Etappe steht in `stages/BACKLOG.md`.

| # | Idee | Umsetzung in MAWLINGS | Bezug |
|---|---|---|---|
| S1 | Farben mit fester Bedeutung | Palette festlegen und in `ART_UI_PLAN.md` verankern: eigen = Grün/Türkis, Gefahr = Rot/Pink, Beute = Gold. Den Boden von Verdant Maw eher zurücknehmen. | `scripts/arena.gd`, `ART_UI_PLAN.md` |
| S2 | Anführer immer auffindbar | Heller Bodenring plus kleine Lebensleiste über dem Anführer, auch im dichtesten Schwarm. | Anführer-Darstellung |
| S3 | Drei Formen für Gefahr | Linie = kommt gleich (Bog King, Lava-Ausbruch), Fläche = liegt da (Glutsumpf), Ring = Ereignis (Flut, Migration). Gezackter roter Rand für angekündigte Angriffe. | Warnflächen, `scripts/arena.gd` |
| S4 | Treffer am Anführer sichtbar | Kurzer roter Bodenblitz und Zahl an der Figur, zusätzlich zum HUD. | Treffer-Rückmeldung |
| S5 | Einsammel-Zahlen zusammenzählen | „+3 +3 +3“ bei Biomasse innerhalb von ~0,25 s zu einer Zahl zusammenfassen; Drops fliegen als Kette zum Schwarm. | Drop-/Biomasse-System |
| S6 | Moment beim Aufleveln | Bei Alpha-Kern/Evolution das Bild kurz entsättigen und einfärben, Lichtsäule auf den Anführer, dann die Auswahl. | Evolution, HUD |
| S7 | Karten-Auswahl | Große Karten mit Bild, Rahmenfarbe je Art (Werte-Bonus / neue Angriffsform), „NEU“-Markierung, abgedunkelter Hintergrund. | `scripts/ui/` |
| S8 | Weiterentwicklung sichtbar | In der Info zu Angriffsformen zeigen, welche Evolution mit welcher Kombination möglich ist. | Evolution, UI |
| S9 | Kompaktes HUD im Hochformat | Oben Timer und Biomasse, unten eine schmale Leiste; die Mitte bleibt frei. | `scripts/ui/hud_top.gd` |
| S10 | Boss-Dramaturgie | Moosschlund: kurzer Kommentar, großer Balken oben, Abdunklung, nach Sieg Höhepunkt, Ruhe, dann Weiter. | `apex_boss.gd` |
| S11 | Kartenzonen | Eigene Bodenfarben/Deko je Zone in der seed-generierten Arena, passend eingefärbte Minikarte. | `scripts/arena.gd` |
| S12 | Kommentare von Figuren | Porträt mit Sprechblase am Rand bei Flut-Beginn, Bog King oder Apex. | HUD |
| S13 | Aufgaben am Run-Ende | Drei offene Ziele mit Fortschrittsbalken und Belohnung auf dem Game-Over-Bildschirm, direkt über „Nochmal“. Verknüpft mit Trophäen und Upgrades. | `scripts/meta/` |

**Nicht übernehmen:** Querformat-Layout, Maus-Info-Boxen (auf dem Touchscreen durch Antippen oder die Auswahlkarte ersetzen), Detailgrad der Modelle, Countdown bei der Kartenauswahl (widerspricht eventuell dem ruhigen mobilen Spiel; erst nach Handtest entscheiden).
