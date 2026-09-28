# Etappe 30 – Karte, Tor und Endboss (Nutzerfeedback 28.09.2026)

## Umgesetzt
- **Karten-Nebel ohne Pixel** (`shaders/map_fog.gdshader`, `hud_minimap.gd`):
  - Die 28 × 28-Erkundungsmaske wird weich hochgerechnet (B-Spline im Shader) und mit ziehendem Wolkenrauschen weich ausgeschnitten.
  - Dazu kommen ein dunklerer Kern, Wolkenstruktur und eine dezente helle Kante.
  - Minimap und große Karte haben je eine eigene Nebel-Ebene (ein Draw-Call).
- **Keine falschen POI-Symbole:** Lichtungen sind nur mögliche Plätze, die meisten bleiben leer. Die Karte zeichnet dort keine Typ-Symbole mehr. Es erscheinen nur noch echte Objekte (Nester, Totems, Kokons, Schreine, Power-ups, Bosse, Tor), der Start- und Ankunftspunkt sowie die entdeckte Endboss-Arena der Welt.
- **Tor an der Endboss-Arena:**
  - Je Welt gibt es eine Endboss-Arena: den Boss-Platz, der am weitesten vom Start bzw. von der Ankunft entfernt ist.
  - 13 m daneben steht von Anfang an ein **versiegeltes Tor** (`migration_maw.gd` `seal/unseal`, Steinsiegel). Solange es versiegelt ist, kann man es nicht betreten; auf der Karte erscheint es, sobald es entdeckt ist.
  - Der Endboss steigt immer in dieser Arena auf. Nach dem Sieg bricht das Siegel und das Tor öffnet sich.
  - Nach der Migration hat die neue Welt ihre eigene Arena mit Tor.
  - Auf der Klassik-Karte (Seed 0, ohne Boss-Plätze) öffnet sich der Schlund wie bisher hinter dem Kadaver.
  - Test: `tests/gate.gd`.
- **Goldene Hain-Knollen entfernt** (`powerups.gd` `GROVE_TREASURE := false`). Das waren die kleinen goldenen Kugeln, die nur Bernstein gaben. Die Legende zeigt jetzt „Power-up“ statt „Pilzknolle“.
- **Endboss stärker als der Bog King:**
  - Der Bog King wächst mit √Druck; Moosschlund, Sandwurm und Aschenkröte hatten feste LP (Sandwurm auf Apex nur ~1450 gegenüber 1900+ beim Bog King).
  - Neu: Endboss-LP = max(bisheriger Wert, `APEX_KING_RATIO` 3,0 × LP eines Bog King zum selben Zeitpunkt), in Welt 1 also etwa 10.000–14.000 LP.
  - Die Kämpfe werden etwa 3× so lang wie gegen den Bog King.

## Offen
- Die erste-Apex-Klippe verschärft sich dadurch (siehe Backlog 0a): Balance-Runde mit gezielt wählendem Bot und neuen Zielkurven.
- Endboss-Kampfdauer am Gerät prüfen (Ziel 45–90 s).