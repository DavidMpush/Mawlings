# Icon-Nachlieferung und Bewertung (Stand 27.09.2026)

Grundlage: „Icon-Standard (Supercell-Stil)“ in `ART_UI_PLAN.md`. Prüfbilder: `preview_ui_icons_before.png` (vorher), `preview_ui_icons.png` (nachher, V4), `preview_ui_icons_compare.png` (Zahn-Gruppe, Glyphen, Tints), erzeugt mit `tests/capture_ui_icons.gd` (ohne `--headless`).

Noten: **A** bleibt · **B** bleibt, nachbearbeitet (V4: Beschnitt, Zentrierung, einheitliche Kontur, ggf. Kategoriefarbe) · **C** ersetzen. „intern“ = durch V4 bereits ersetzt, keine Lieferung nötig.

## Bewertung

Zusammenfassung: 66 IDs – **23 A**, **19 B**, **16 C** (davon 10 intern ersetzt: 8 Glyphen + DNA/Biomasse als gemalte Währung; **6 brauchen neue Bilder**), 8 ohne Verwendung (`up_*`). Dazu 2 fehlende Boss-Porträts.

| ID | Quelle heute | verwendet in (Auszug) | Art | Note | Begründung / Maßnahme |
|---|---|---|---|---|---|
| jaws | V2 PNG | Mutationen, Brutkammer „Reißkraft“ | gemalt | B | Gutes Motiv, bleibt als *das* Zahn-Icon; V4-Kontur. |
| brood | V2 PNG | Mutationen, Minimap/Nest-Fallback, Brutkammer | gemalt | A | Türkise Eier, eindeutig. |
| glutton | V2 PNG | Mutationen, Brutkammer „Verdauung“ | gemalt | B | Fast gleich wie Reißzähne; V4: Kiefer in Beute-Gold, Zunge/Kugel bleiben. |
| pack | V2 PNG | Mutationen, Tipp „Rally“, Brutkammer „Anlagenslot“ | gemalt | **C** | Drei rote Kiefer = Reißzähne ×3, bei 40 px Brei. V4-Notlösung Karmesin. |
| scatter | V2 PNG | Mutationen, Brutkammer „Sprinter“ | gemalt | **C** | Motiv (türkiser Stachel-Flügel) sagt nicht „Fluchtreflex“, dünn bei 40 px, falsche Kategoriefarbe. |
| armor | V2 PNG | Mutationen, Brutkammer „Chitin“ | gemalt | B | Knochenplatten gut; V4: violetter Sockel → Schutz-Grün. |
| rudelbiss | V3 leap | Mutationen, Brutkammer „Angriffsslot“ | gemalt | B | Kiefer + Pfeil, lesbar; V4-Kontur. |
| sporenwolke | V3 spore_burst | Mutationen | gemalt | A | Eigenständige Pilzform. |
| saeurespucker | V3 acid_spit | Mutationen | gemalt | B | Dunkler Kopf auf Grün kontrastarm; V4-Kontur hilft. |
| stachelruecken | SVG | Mutationen | gemalt | **C** | Violette Kuppel mit Stacheln wirkt wie Igel/Muffin, amateurhaft, falsche Kategoriefarbe. |
| aetzflut | SVG | Mutationen | gemalt | B | Säurewelle erkennbar; V4-Kontur. |
| meute | V3 swarm_wave | Mutationen | gemalt | B | Zu nah an Rudelbiss/Reißzähnen; V4: Kiefer Violett (Evolution), Welle bleibt Cyan. |
| graeber | V3 slam | Mutationen | gemalt | B | Bei 40 px unruhig; V4-Kontur. |
| blitzbiss | V3 sickle_slash | Mutationen | gemalt | A | Klar, dynamisch. |
| brutsack | SVG | Mutationen | gemalt | **C** | Pinke Kugel mit Mini-Köpfen, flach, liest sich nicht als Brutsack. |
| erdbeben | SVG | Mutationen | gemalt | B | Eigener Goldring wirkt wie Plakette; später ohne Ring. |
| sturmrudel | SVG | Mutationen | gemalt | **C** | Blaue Haie im Ring, bei 40 px blauer Fleck; Angriff sollte Orange/Rot sein. |
| regeneration | SVG | Mutationen | gemalt | A | Herz + Plus, sofort klar. |
| dornenhaut | SVG | Mutationen | gemalt | B | Lesbar, aber sehr nah an Stachelrücken-Bedeutung; V4-Kontur. |
| essence | SVG | Menü-Ressourcen, Belohnung | gemalt | A | Violetter Tropfen, klar. |
| crown_tooth | SVG | Menü (Königszähne) | gemalt | B | Heller Zahn wenig Kontrast; V4-Kontur. |
| dna | SVG → **V3 dna** | HUD, Popups, Menü | gemalt | C (intern) | Flache Glyphe ersetzt durch gemalte Währung; fremde Tints werden ignoriert. |
| skull | SVG | Bedrohung, Flut, Totem-Fallback, Trophäen | gemalt | B | Solide; V4-Kontur. |
| mawling_head | SVG | HUD/Menü (wird eingefärbt) | gemalt | B | Neutraler Kopf zum Tönen, bleibt. |
| mawling_head_color | SVG | HUD, Menü, Tipp, Teilen-Karte | gemalt | A | Spielerfarbe, klar. |
| crown | SVG | Boss, Trophäen, Objectives | gemalt | A | |
| alpha_core | SVG | HUD, Overlays, Trophäen | gemalt | A | |
| pause | SVG | HUD, Pause-Overlay | Glyphe | C (intern) | V4-Glyphe. |
| play | – (fehlte) | Weiterspielen-Knopf | Glyphe | C (intern) | Neu als V4-Glyphe. |
| lock | SVG | Menü (gesperrt) | Glyphe | C (intern) | V4-Glyphe. |
| trophy | SVG | Menü, Chronik, Trophäen | gemalt | A | |
| biome_verdant | SVG | Biom-Banner | gemalt | B | Kleine Blätter, dunkel bei 40 px. |
| biome_glutsumpf | SVG | Biom-Banner | gemalt | B | wie oben. |
| diff_wild | SVG | Menü Schwierigkeit | gemalt | A | |
| diff_brutal | SVG | Menü Schwierigkeit | gemalt | B | Dünne Krallenstriche; V4-Kontur macht sie lesbar. |
| diff_apex | SVG | Menü Schwierigkeit | gemalt | A | |
| clock | SVG | Pause/Ergebnis, Chronik, Trophäen | Glyphe | C (intern) | V4-Glyphe (Stoppuhr). |
| reroll | SVG | Mutationsauswahl, Menü | Glyphe | C (intern) | V4-Glyphe (zwei Pfeile). |
| banish | SVG | Mutationsauswahl | Glyphe | C (intern) | V4-Glyphe. |
| skip | SVG | Mutationsauswahl | Glyphe | C (intern) | V4-Glyphe. |
| biomass | SVG → **V3 biomass** | Popups, Ergebnis, Tipp | gemalt | C (intern) | Umriss-Tropfen ersetzt durch gemalte Währung. |
| hunter | SVG | Ergebnis/Overlays | gemalt | **C** | Violetter Haikopf = Mawling-Kopf in Violett; passt nicht zum neuen Jäger-Käfer. |
| skitter | SVG | Ergebnis/Overlays | gemalt | A | |
| leaper | SVG | Ergebnis/Overlays | gemalt | B | Lesbar, Proportionen etwas steif. |
| nibbler (prey) | SVG | Tipp, Overlays | gemalt | A | |
| bog_king (boss) | SVG | Tipp, Boss-Anzeigen | gemalt | A | |
| up_brood_size … up_trait_slot (8) | SVG | **nicht verwendet** (Brutkammer nutzt Anlagen-Icons) | – | – | Keine Arbeit nötig; bei Bedarf später löschen. |
| instinct | SVG | Menü Urinstinkt | gemalt | A | |
| restart | SVG | Ergebnis-Knopf | Glyphe | C (intern) | V4-Glyphe (ein Pfeil, oben offen). |
| hub | SVG | Ergebnis-Knopf „Brutstätte“ | gemalt | B | Bogen mit Ei, schlicht; V4-Kontur. |
| nest | V3 brood_nest | Objectives, Minimap | gemalt | A | |
| totem | V3 curse_totem | Objectives, Minimap | gemalt | B | Dunkel auf Dunkel; V4-Kontur. |
| currency_dna / currency_biomass | V3 | (Quelle für dna/biomass) | gemalt | A | |
| branch_growth / _attack / _protect / _special | V3 | nur branch_special in Trophäen | gemalt | A | |
| portrait_bog_king | V3 bog_king | Boss-Leiste, Ergebnis | gemalt | A | Unverändert (Büste, Beschnitt unten gewollt). |

## Nachlieferung

**So liefern:** je Bild ein PNG 1024 × 1024 mit transparentem Hintergrund, Dateiname wie in der Tabelle, z. B. nach `Swarm/Design/UI_Assets_V2/Icons/V4/`. Einbau: Quelle in `PAINTED` von `assets/ui/v4/build_icons_v4.py` eintragen, Skript laufen lassen, Godot-Import. Beschnitt und Kontur vereinheitlicht das Skript – der Generator muss nur Motiv, Stil und Rand treffen. Bitte je Motiv 3–4 Varianten erzeugen und die mit der klarsten Silhouette bei kleiner Ansicht wählen.

### Gemeinsamer Stil-Block (Icons, an jeden Motivzusatz anhängen)

```
One original premium 2D game UI icon for the mobile swarm survival game Mawlings, in the art style of Supercell games (Brawl Stars, Clash Royale). One bold emblem with a chunky, instantly readable silhouette. Thick even near-black outline around the whole shape, clean cel shading with only 3-4 broad saturated color areas, light from the top left with one crisp cream-white highlight, darker shade toward the lower right. Centered, filling about 85 percent of a square canvas, even margins, transparent background. Must stay readable at 40 pixels. No card, frame, circle, badge, glow, particles, text, letters or scenery. 1024x1024 PNG.
```

### Stil-Block Boss-Porträt

```
One original boss portrait for the mobile game Mawlings in the art style of Supercell games (Brawl Stars, Clash Royale). Head-and-shoulders bust of the creature in three-quarter view facing left, menacing expression, thick even near-black outline, bold cel shading with 3-4 broad color areas, light from the top left with a crisp highlight. The bust is cut off flat at the bottom edge and fills about 90 percent of a square canvas, transparent background. Readable at 56 pixels. No frame, circle, glow, text or scenery. 1024x1024 PNG.
```

### Motive

| Datei | Wofür (deutsch) | Motivzusatz (englisch, an Stil-Block hängen) |
|---|---|---|
| `pack.png` | **Rudelinstinkt** (Anlage, Angriff): mehr Schaden bei Rally. Soll „Rudel sammelt sich zum Angriff“ zeigen, nicht noch ein Maul. | `Motif: a tight wedge of three small ember-orange predator creature heads charging toward the viewer, the front head largest with an open snarl, the two behind smaller, a bold golden rally chevron arrow pointing forward behind them. Main colors ember orange and red, gold accent.` |
| `scatter.png` | **Fluchtreflex** (Anlage, Spezial): weniger Verluste ohne Rally. „Auseinanderstieben“. | `Motif: three small violet creature silhouettes bursting apart from one center point in three directions, each with a short white speed streak behind it, a small cyan dodge flash in the middle. Main color violet, cyan accent.` |
| `stachelruecken.png` | **Stachelrücken** (Angriffsform, Schutz): wer den Schwarm trifft, erleidet Schaden. Anders als Dornenhaut (grüne Kugel): Rückenplatte + zurückschreckende Kralle. | `Motif: a moss-green armored back plate seen from the side with a fan of five tall bone-white spikes, an orange enemy claw recoiling from the spikes with a small red impact spark. Main color moss green, bone white spikes.` |
| `brutsack.png` | **Brutsack** (Angriffsform, Wachstum): platzende Brutblasen setzen Hilfs-Beißer frei. | `Motif: a swollen translucent turquoise egg sac with three small curled creature embryos visible inside, the top bursting open as one tiny creature with a snapping jaw leaps out, two droplets flying. Main color turquoise, small ember-orange creature.` |
| `sturmrudel.png` | **Sturmrudel** (Evolution aus Blitzbiss, Angriff): Kettenbiss über sechs Ziele. | `Motif: a jagged ember-orange lightning bolt that zigzags through three small snapping jaws in a row, each jaw lit by a white spark where the bolt hits it. Main colors ember orange and red, white sparks.` |
| `hunter.png` | **Jäger** (Gegner): muss zum neuen Käfer-Modell passen und sich klar vom Mawling-Kopf unterscheiden. | `Motif: the head of a purple-magenta predator beetle-lizard seen from the front-left, narrow blade-like armored head, two curved horns, glowing orange eyes, short shoulder spines. Main color purple-magenta, orange eyes.` |
| `portrait_moosschlund.png` | **Moosschlund** (Apex-Boss 1), für Boss-Leiste und Ergebnis. Stil-Block Boss-Porträt. | `Motif: a colossal moss-covered swamp beast with a huge wide maw of wooden-looking teeth, two tangled root antlers, moss and small glowing green spore bulbs on its back. Main colors moss green and bark brown, glowing green bulbs.` |
| `portrait_aschenkroete.png` | **Aschenkröte** (Apex-Boss 2, Glutsumpf). Stil-Block Boss-Porträt. | `Motif: a giant lava toad with cracked charcoal-black skin and glowing orange magma seams, a very wide mouth, three bubbling ember blisters on its back. Main colors charcoal black and glowing orange.` |

**Optional (B-Icons später veredeln, gleicher Stil-Block):** `erdbeben.png` ohne Goldring (`Motif: three bone-white stone spikes erupting from cracked brown earth with flying rock chunks, orange shock lines.`), `biome_verdant.png`/`biome_glutsumpf.png` als kräftigere Mini-Landschaftsembleme, `flood.png` für „Die Flut“ (heute Schädel: `Motif: a dark olive wave made of many tiny snarling swamp creatures with toxic yellow eyes, crashing forward.`).
