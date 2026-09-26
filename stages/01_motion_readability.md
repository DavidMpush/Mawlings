# Etappe 01 – Bewegung und Lesbarkeit von Schwarm und Bog King

Stand vorher (Commit `3bdb0a3`, Bilder `preview_boss*.png`, `preview_survival.png`): Bog King dunkelviolett auf Grün, Silhouette verschwimmt, völlig starr; Warnkreis zeigt keine Restzeit und wird vom Modell verdeckt; zweite Lebensleiste über dem Kopf doppelt die HUD-Leiste. Mawlings blicken alle gleich, schweben ohne Bodenkontakt, verschwinden bei Treffern kommentarlos; Rally ist in der Welt nicht sichtbar.

## Abnahmekriterien

1. **Schwarm lebt:** individuelle Blickrichtung aus eigener Bewegung, Hüpf-/Watschelgang abhängig von Geschwindigkeit, leichtes Atmen im Stand, Nachziehen/Strecken beim Laufen (unterschiedliche Folgegeschwindigkeit je Tier).
2. **Bodenkontakt:** weiche Schatten unter jedem sichtbaren Mawling (eine MultiMesh, 1 Draw-Call) und unter dem Bog King.
3. **Angriff/Ernte sichtbar:** Tiere drängen zur angegriffenen Beute bzw. zum Kadaver und zeigen Biss-/Pickbewegungen.
4. **Treffer sichtbar:** verlorene Tiere werden weggeschleudert und verblassen, Überlebende werden vom Einschlagpunkt weggestoßen, der Schwarm blitzt kurz; Kamera wackelt proportional.
5. **Wachstum sichtbar:** neue Mawlings „schlüpfen“ mit Skalierung aus der Schwarmmitte.
6. **Rally in der Welt:** korallfarbener Bodenhalo des Schwarms, bei Rally hellerer, enger werdender Ring.
7. **Bog King lesbar:** helle Randkontur (Rim) gegen den Boden, Rim-Farbe je Zustand (Jagd lila, Warnung orange-rot, Erschöpfung gold). Keine Lebensleiste mehr über dem Kopf (HUD hat sie).
8. **Bog King bewegt sich:** schwerer Schaukelgang mit Schrittstaub/leichtem Beben, Auftauchen aus dem Boden beim Erscheinen, Aufbäumen während der Warnung, Stampfen mit Schockwelle und Kamerawackeln, erschöpfte Pose in der Erholung (HUD-Hinweis „JETZT ANGREIFEN“).
9. **Warnung mit Zeitverlauf:** fester Außenring (dicker), Füllscheibe wächst während der Warnzeit von innen bis zum Rand; Puls wird schneller.
10. **Boss-Richtungszeiger:** Ist der Bog King außerhalb des Bildes, zeigt ein Pfeil am Bildrand mit „BOG KING“ zu ihm.
11. **Kamera:** zoomt bei großem Schwarm und nahem Boss etwas heraus, damit beide ins Hochformat passen.
12. **Regeln/Technik:** Spielmechanik (Trefferbereiche, Timing, Schaden) unverändert; alle bestehenden Tests grün; Effekte verändern keinen Spielzustand; Pause friert Spielfiguren ein.

## Schnittstellen (verbindlich für parallele Arbeit)

Gemeinsam: `res://shaders/creature.gdshader` (Uniforms `brightness`, `saturation`, `shape_light`, `rim_color`, `rim_strength`, `rim_power`, `flash_color`, `flash`), `res://scripts/fx.gd` mit `FX.ring(parent, location, tint, start_radius, end_radius, seconds)`.

`scripts/swarm.gd` (Agent Schwarm):
- `set_population(value: int, animate: bool = true)` – bei `animate` schlüpfen neue Tiere, entfernte Tiere werden weggeschleudert; `animate=false` sofort (Neustart).
- `set_focus(world_position: Vector3, mode: int)` – pro Frame von HuntWorld gesetzt; `mode` 0 = nichts, 1 = Angriff, 2 = Ernte. `clear_focus()` = mode 0.
- `react_to_hit(loss: int, impact: Vector3)` – Wegstoßen, Blitz, ggf. zusätzliche Fall-Geister wenn mehr Tiere verloren als sichtbar entfernt.
- Bestehend bleibt: `units`, `population`, `VISUAL_LIMIT`, `MOVE_SPEED`, `movement_vector`, `rally_pressed`, `set_controls`, Kindknoten `"Game model"` direkt unter jeder Einheit.

`scripts/bog_king.gd` (Agent Boss):
- Bestehend bleibt: `State`, `state`, `remaining`, `health`, `max_health`, `attack_center`, `attack_power`, `model` (Skalierung ≥ 7), `warning`, `take_damage()`, `step(delta, swarm_position, pressure) -> int` mit **identischer** Spiellogik.
- Neu: `emerge` (0..1), `body` (animierter Pivot), `skin` (ShaderMaterial). Kamerawackeln über `_shake(amount)`, das `get_parent().get_parent().add_shake(amount)` aufruft, falls vorhanden.

`scripts/main.gd` / `hunt_world.gd` / `touch_controls.gd` (Orchestrator):
- `main.add_shake(amount: float)`; Zoom nach Population und Bossnähe.
- HuntWorld setzt Fokus, ruft `react_to_hit` mit `attack_center`, erzeugt Schockwellen bei Kills, übergibt `hud.boss_pointer` (Vector2 oder `Vector2.INF`) und Erholungs-Hinweis.

## Ergebnis (26.09.2026)

Umsetzung parallel durch zwei Implementierungs-Agenten (Schwarm, Bog King) und die Hauptsitzung (Integration, HUD, Kamera, Tests); Prüfung durch Testlauf, Bildsichtung und einen Regel-/Fehlerprüfer.

| Kriterium | Status |
|---|---|
| 1 Schwarm lebt | erfüllt – Blickrichtung, Hüpfgang, Atmen, individuelles Nachziehen (`preview_motion_run.png`) |
| 2 Bodenkontakt | erfüllt – MultiMesh-Schatten, Boss-Schatten; bei 250 Tieren und unter dem Boss nur schwach sichtbar |
| 3 Angriff/Ernte | erfüllt – Tiere umschließen die Beute (`preview_motion_attack.png`) |
| 4 Treffer | erfüllt – Geister, Wegstoßen, Blitz, Kamerawackeln (`preview_motion_hit.png`) |
| 5 Wachstum | erfüllt – Schlüpfen aus der Mitte |
| 6 Rally | erfüllt – Halo + Ring (`preview_motion_rally.png`) |
| 7 Bog King lesbar | erfüllt – hellere Darstellung, Rim je Zustand, keine Überkopfleiste |
| 8 Bog King bewegt sich | erfüllt – Gang, Auftauchen, Aufbäumen, Stampfen, Erschöpfung; aus der steilen Kamera nur mäßig sichtbar |
| 9 Warnung mit Zeitverlauf | erfüllt – wachsende Füllscheibe (`preview_boss_warning_late.png`) |
| 10 Boss-Zeiger | erfüllt – Kronenpfeil am Rand (`preview_motion_pointer.png`) |
| 11 Kamera | erfüllt – Zoom nach Population und Bossnähe |
| 12 Regeln/Technik | erfüllt – alle 11 Prüfungen grün, Playthrough-Werte identisch zur Vorversion (103/127/16) |

Während der Prüfung gefundene und behobene Fehler: gestreckte Mawlings im ersten Frame/Standbild (`breath = 1.0` beim Erzeugen), Schwarm bewegte sich und biss in Pause/Mutationsmenü weiter, Boss-Zeiger nutzte das Spieler-Symbol, pro Effekt neu erzeugtes Torus-Mesh.

Bewusste Ausnahme vom Modellbudget: Nach einem Treffer bei voller Anzeige (120 Tiere) erscheinen bis zu 12 zusätzliche fallende Modelle für etwa eine Sekunde (insgesamt höchstens 28 Geister).

Offen: kein Handtest des Spielgefühls, keine Messung auf dem Samsung S25; Geister werden nicht gepoolt (kurze Instanziierungsspitze bei großen Treffern); Aufbäumen/Vorneigen des Bosses aus der Draufsicht schwach; Mawlings in Rally-Verdichtung überlappen stark.
