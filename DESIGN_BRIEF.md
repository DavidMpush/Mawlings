# MAWLINGS — bestätigte Richtung für den Godot-Neustart

- Mobiles Hochformat. Bewegungsjoystick rechts, Rally links.
- Der Spieler steuert einen **Schwarm**, keinen Einzelhelden. Die logische Population ist der Spielzustand; sichtbare Tiere können später begrenzt und unabhängig dargestellt werden.
- Jagd und Fressen erzeugen Wachstum. Nicht vollständig verbrauchte Ressourcen bleiben während des aktiven Runs an ihrer Stelle liegen und können später geerntet werden.
- **Beute-Kristalle und Magnet** (Nutzerentscheidung 27.09.2026, Etappe 16): Getötete Gegner platzen in wenige Kristalle auf (Biomasse Bernstein/Gold, DNA Türkis). Kristalle im Magnetradius des Schwarms fliegen von selbst heran und werden beim Ankommen gutgeschrieben; der Radius wächst mit dem Schwarm, über „Witterung“ (Brutkammer), „Lockduft“ (Anlage) und bei gehaltener Rally. Ein seltener **Lockruf** holt alle Kristalle der Karte auf einmal. Das ersetzt die Kadaver-Ernte; Kadaver sind nur noch Deko und verblassen. Die Ressourcenregel gilt weiter: Kristalle verfallen nicht, sondern bleiben liegen, bis sie eingesammelt sind (ein voller Schwarm lässt Biomasse liegen).
- Ein Run endet nur durch Aussterben. Bosse oder eine Prototyp-Zeitmarke beenden ihn nicht. Der Druck steigt mit der Zeit exponentiell, ohne unbegrenzte Gegnerzahlen vorauszusetzen.
- **Endphase „Die Flut“** (Nutzerentscheidung 26.09.2026, angelehnt an Megabonks Final Swarm): Ab einem festen Zeitpunkt je Schwierigkeit strömen Horden an, deren Stärke exponentiell wächst, sodass lange Runs eine echte Herausforderung sind und praktisch jeder Run einige Minuten danach endet. Gegnerzahlen bleiben gedeckelt; Lebenspunkte, Schaden und Tempo wachsen.
- **Alle Gegner greifen an** – auch Beute wehrt sich; es gibt keine völlig ungefährlichen Ziele. Die Grundschwierigkeit ist deutlich höher als im frühen Prototyp.
- Die Arena bleibt überwiegend **offen und gut lesbar**. Wenige breite, umgehbare Engstellen sind möglich; es entsteht kein enger Dauerkorridor.
- Zielstil: farbige, vereinfachte, klar lesbare Fantasy-Formen statt realistischer oder überladener Dschungelgrafik. Inspirationsbilder sind keine Vorlage für exakte Figuren, Karten oder UI.
- Zunächst nur der kleinste spielbare Kern. Neue Gegner, Mutationen, Bosse und aufwendige Art folgen nach Spieltests.

Die alte Unity-Spezifikation enthält zusätzlich engine-spezifische Architektur und einen deutlich größeren Inhaltskatalog. Sie ist eine Referenz für Produktideen, keine technische Vorgabe für dieses Godot-Projekt.
