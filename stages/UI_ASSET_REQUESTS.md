# UI-Asset-Wunschliste und Bild-Inventur (Stand 28.09.2026)

**Lieferstand 28.09.2026:** A1 (15), A2 (8), A3 (5), B1 (13), B2 (7), B3 (5) und B4 (3) sind als 56 transparente PNGs geliefert. Quellen und Prompt-Satz: `C:/Users/vrxby/Documents/Codex/Swarm/Design/UI_Assets_V2/V5_DELIVERY.md`; Kopien im Projekt: `assets/ui/v5/`. Die 35 gemalten Icons sind in V4 und die vier Porträts in V3 verarbeitet; die Bedien-Glyphen werden direkt geladen. Die vier Seltenheits-Plaketten sind vorbereitet, aber noch nicht auf Karten verdrahtet. Je Motiv liegt eine ausgewählte Fassung vor. `tribe_sandling` bleibt optional, die C-Gruppe ist für eine spätere Runde offen.

Gilt ab jetzt für **alle 2D-UI-Bilder** (Icons, Porträts, Hintergründe, Menü-Elemente). Ersetzt die Nachlieferlisten in `stages/ICON_REQUESTS.md` (dort bleibt die Bewertung von 27.09. als Verlauf) und den Abschnitt „B – 2D-Grafiken“ in `stages/ASSET_REQUESTS.md`. 3D-Modelle bleiben in `ASSET_REQUESTS.md`.

Priorität: **A** = ersetzt heute einen sichtbaren Platzhalter, ein Monogramm oder ein doppelt genutztes Motiv an zentraler Stelle · **B** = hebt Menü/Marke deutlich · **C** = später/Feinschliff.

Prüfbilder dieser Inventur (alle neu gerendert am 28.09.): `preview_ui_hud_top_*.png`, `preview_ui_controls_*.png`, `preview_ui_mutations_*.png`, `preview_ui_result*.png`, `preview_ui_pause.png`, `preview_ui_banner_*.png`, `preview_ui_boss_*.png`, `preview_ui_menu_main*.png`, `preview_ui_menu_sheets_*.png`, `preview_share_*.png`, `preview_arsenal17_*.png`, `preview_minimap_*.png`, `preview_ui_icons*.png`.

## So liefern

- Icons und Porträts: PNG **1024 × 1024**, transparent, Dateiname wie in den Tabellen, z. B. nach `Swarm/Design/UI_Assets_V2/Icons/V5/` bzw. `…/Portraits/`. Je Motiv 3–4 Varianten erzeugen und die mit der klarsten Silhouette bei 40 px wählen.
- Hintergründe: PNG/JPG in der angegebenen Größe, ohne Transparenz.
- Einbau: Icons über `PAINTED` in `assets/ui/v4/build_icons_v4.py` (Beschnitt, Kontur und Unterkante macht das Skript; `python assets/ui/v4/build_icons_v4.py <id>` baut nur diese IDs), danach Godot-Import. Porträts/Hintergründe über `assets/ui/v3/build_v3.py`.

## Gemeinsamer Stil-Block Icons (an jeden Motivzusatz anhängen)

```
One original premium 2D game UI icon for the mobile swarm survival game Mawlings, in the art style of Supercell games (Brawl Stars, Clash Royale). Hand-painted look with one bold emblem and a chunky, instantly readable silhouette. Thick even near-black outline around the whole shape, clean cel shading with only 3-4 broad saturated color areas, light from the top left with one crisp cream-white highlight, darker shade toward the lower right. Centered, filling about 85 percent of a square canvas, even margins, transparent background. Must stay readable at 40 pixels on a dark blue-violet panel and on light green grass. No card, frame, circle, badge, glow, particles, text, letters or scenery. 1024x1024 PNG.
```

Kategoriefarben (Hauptfläche des Motivs): **Angriff** Glut-Orange/Rot · **Wachstum/Brut** Türkis-Blau · **Schutz** Grün · **Spezial/Evolution** Violett · **Beute/Währung** Gold/Bernstein · **Gefahr** Magenta/Pink. Gegner in ihrer Weltfarbe. Relikte in ihrer Materialfarbe (die Karte trägt die Seltenheit am Rand).

## Stil-Block Glyphen (Bedienung, einfarbig)

```
One original 2D mobile game UI control glyph in the style of Supercell games (Brawl Stars, Clash Royale). A single simple bold symbol filled pure white with a soft cool grey shade on the lower third, thick even near-black outline and a small dark offset at the bottom like a raised sticker. Centered, filling about 85 percent of a square canvas, transparent background, readable at 32 pixels. No color other than white, grey and the outline, no frame, circle, glow or text. 1024x1024 PNG.
```

## Stil-Block Porträt (Stämme, Bosse)

```
One original character portrait for the mobile game Mawlings in the art style of Supercell games (Brawl Stars, Clash Royale). Head-and-shoulders bust of the creature in three-quarter view facing left, expressive face, thick even near-black outline, bold cel shading with 3-4 broad color areas, light from the top left with a crisp highlight. The bust is cut off flat at the bottom edge and fills about 90 percent of a square canvas, transparent background. Readable at 56 pixels. No frame, circle, glow, text or scenery. 1024x1024 PNG.
```

## Stil-Block Hintergrund/Illustration

```
Stylized hand-painted mobile fantasy game art in the style of Supercell games, colorful alien jungle, broad painterly shapes, soft depth, strong but calm composition with a darker vignette at the edges and a clean readable center for UI panels, no creatures unless requested, no text, no UI.
```

---

## A – sofort sichtbar

### A1 Waffen, Evolutionen, Werte (Mutations-/Beute-Karten, HUD-Waffenreihe)

| Datei (ID) | Wofür / Stelle | heute | Motivzusatz (englisch) |
|---|---|---|---|
| `schallbrueller.png` | **Schallbrüller** (Waffe, Angriff); HUD-Waffenreihe, Karten | **Monogramm „S“** | `Motif: a roaring ember-orange creature head in profile with a wide open mouth, three bold pale-blue sound wave arcs fanning out forward from the mouth. Main colors ember orange head, pale blue waves.` |
| `glutdruese.png` | **Glutdrüse** (Relikt, episch); HUD-Relikte, Kokon-Karte | **Monogramm „G“** | `Motif: a glowing ember-orange gland shaped like a small cracked egg with little yellow flames licking out of the cracks. Main colors ember orange and yellow flame.` |
| `pilzreich.png` | **Pilzreich** (Evolution aus Sporenwolke) | `sporenwolke` (doppelt) | `Motif: a ring of three fat magenta-capped mushrooms releasing a big lime-green spore cloud upward. Main colors magenta caps, lime green spores, violet accent.` |
| `dornenwall.png` | **Dornenwall** (Evolution aus Stachelrücken) | `dornenhaut` (doppelt mit Relikt) | `Motif: a closed ring of crimson thorns standing upright like a fence, seen slightly from above, one big bone-white spike in front. Main colors crimson and bone white, violet shadow.` |
| `sturmrudel.png` | **Sturmrudel** (Evolution aus Blitzbiss) | gezeichnetes SVG (blaue Haie im Ring) | `Motif: a jagged ember-orange lightning bolt that zigzags through three small snapping jaws in a row, each jaw lit by a white spark where the bolt hits it. Main colors ember orange and red, white sparks.` |
| `crit.png` | **Kritbiss** (Wert, Angriff) | `crown_tooth` (Währung, doppelt) | `Motif: a single sharp fang cracking a small stone with a bright yellow star-shaped impact burst. Main colors bone white and ember orange, yellow burst.` |
| `haste.png` | **Angriffstempo** (Wert, Angriff) | `clock` (Bedien-Glyphe!) | `Motif: a small bone stopwatch with a bold ember-orange claw slash across its face and two speed lines. Main colors ember orange, cream.` |
| `reach.png` | **Reichweite** (Wert, Angriff) | `branch_attack` = dasselbe Bild wie Klauenwirbel | `Motif: a claw mark with three concentric ember-orange range rings expanding outward from it. Main colors ember orange and red.` |
| `vigor.png` | **Anführerherz** (Wert, Schutz) | `crown` | `Motif: a small golden crown sitting on top of a plump green heart with a white plus sign. Main colors green heart, gold crown.` |
| `gene.png` | **Genfluss** (Wert, Wachstum) | `dna` (Währung, doppelt) | `Motif: a turquoise DNA double helix with a small upward arrow and two sparkles. Main colors turquoise and white.` |
| `speed.png` | **Sprinter** (Wert, Spezial) | `instinct` (auch Menü-Tab) | `Motif: a violet creature paw with three bold motion streaks behind it. Main colors violet and white.` |
| `luck.png` | **Glück** (Wert, Spezial) | `essence` (Währung, doppelt) | `Motif: a violet four-leaf clover made of small creature claws with a golden sparkle. Main colors violet and gold.` |
| `magnet.png` | **Lockduft/Witterung** (Wert Sammelradius, Brutkammer „Witterung“) | `branch_growth` (goldene Eier) | `Motif: a creature snout sniffing with two turquoise scent swirls pulling small gold crystals toward it. Main colors turquoise swirls, gold crystals, ember snout.` |
| `pack.png` | **Rudelinstinkt** (Wert Rally-Schaden, Tipp „Rally“, Mutationswurf) | V2 drei rote Kiefer, Karmesin umgefärbt | `Motif: a tight wedge of three small ember-orange predator creature heads charging toward the viewer, the front head largest with an open snarl, a bold golden rally chevron arrow behind them. Main colors ember orange and red, gold accent.` |
| `scatter.png` | **Fluchtreflex** (Wert, Schutz) | V2 türkiser Stachel-Flügel (sagt nichts) | `Motif: three small green creature silhouettes bursting apart from one center point in three directions, each with a short white speed streak, a small cyan dodge flash in the middle. Main color green, cyan accent.` |

### A2 Power-ups, Kokon, Schrein (HUD-Ringe, Welt-Plakette, Minimap, Banner)

Heute zeigen alle sechs Power-ups **Stellvertreter, die anderswo schon etwas anderes bedeuten** (Rausch = Urinstinkt-Tab, Blutrausch = Uhr-Glyphe, Chitinschild = Knochenpanzer …).

| Datei | Wofür | heute | Motivzusatz |
|---|---|---|---|
| `pu_rausch.png` | Rausch (+45 % Tempo, grün) | `instinct` | `Motif: a lime-green creature paw mid-leap with three bold white speed streaks behind it. Main colors lime green and white.` |
| `pu_blutrausch.png` | Blutrausch (Waffen schneller, Glut) | `clock` | `Motif: a small bone stopwatch whose hand is a red claw, cracked glass with ember sparks flying out. Main colors ember orange, blood red, cream.` |
| `pu_magnetsturm.png` | Magnetsturm (Sog ×3, Gold) | `branch_growth` | `Motif: a bone horseshoe magnet pulling a swirl of small gold crystals into its arc. Main colors gold and bone white.` |
| `pu_chitinschild.png` | Chitinschild (unverwundbar, Blau) | `armor` | `Motif: a round domed chitin shield plate with segmented edges and a bright cyan shine, a tiny crown shape embossed in the middle. Main colors sky blue and white.` |
| `pu_raserei.png` | Raserei (doppelter Schaden, Magenta) | `jaws` | `Motif: an open snarling jaw with glowing magenta eyes and two small red anger marks. Main colors magenta and blood red.` |
| `pu_brutwelle.png` | Brutwelle (+3 Tiere, Violett) | `brood` | `Motif: three small violet eggs bursting on a rising wave, tiny creature heads popping out. Main colors violet and turquoise.` |
| `cocoon.png` | Kokon (Preis-Pille, Minimap, Beute) | `nest` | `Motif: an upright silk cocoon wrapped in cream threads with a glowing ember slit on the front, sitting on a small silk mound. Main colors cream and ember orange.` |
| `shrine.png` | Schrein (Lade-Pille, Minimap) | `essence` | `Motif: a small ring of four standing stones around a floating violet crystal. Main colors stone grey and violet.` |

### A3 Währungen, Gefahr, Bosse (auf fast jedem Bildschirm)

| Datei | Wofür / Stelle | heute | Motivzusatz |
|---|---|---|---|
| `essence.png` | **Essenz** (Menü-Leiste oben, Ergebnis, Preise) | gezeichnetes SVG-Tröpfchen (flach) | `Motif: a plump violet essence droplet made of glowing liquid with a small swirl inside and a bright rim light, like a premium gem currency. Main colors violet and magenta, cream highlight.` |
| `crown_tooth.png` | **Königszahn** (Menü-Leiste, HUD-Pille, Kokon-Preis) | gezeichnetes SVG (heller Zahn, kontrastarm) | `Motif: a big golden fang with a tiny crown of three points at its root and a red gem, polished like a trophy coin. Main colors gold and ivory, small red gem.` |
| `flood.png` | **Die Flut** (Banner, Flut-Pille, Druck) | `skull` – derselbe Schädel steht auch bei „Apex erscheint“ und „Druck“ | `Motif: a dark olive wave made of many tiny snarling swamp creatures with toxic yellow eyes, crashing forward. Main colors dark olive and toxic yellow, magenta foam.` |
| `pressure.png` | **Druck** (HUD-Pille unter der Uhr) | `skull` | `Motif: a magenta skull-shaped pressure gauge with the needle in the red zone and two small cracks. Main colors magenta and bone white.` |
| `portrait_apex_sandworm.png` | **Sandwurm** (Apex Dürrschlund), Boss-Leiste und Ergebnis | fehlt → `diff_apex` | Porträt-Stil-Block + `Motif: a colossal sand worm bursting upward with a round mouth ringed by three rows of bone teeth, segmented pale ochre armor plates, small cool blue-grey shadows. Main colors pale ochre and bone white, dark maw.` |

## B – Menü und Marke hochwertiger

### B1 Bedien-Glyphen (heute lokal im Code gezeichnet)

Alle mit dem Glyphen-Stil-Block. Die acht V4-Glyphen (Pause, Play, Uhr, Schloss, Neu würfeln, Neustart, Verbannen, Überspringen) sind brauchbar und bleiben.

| Datei | Stelle heute (Code) | Motivzusatz |
|---|---|---|
| `g_settings.png` | Zahnrad oben rechts im Menü (`menu_main._b_gear_glyph`) | `Symbol: a chunky six-tooth cog wheel with a round hole.` |
| `g_close.png` | X-Knopf aller Sheets und der großen Karte | `Symbol: a bold rounded X.` |
| `g_share.png` | Teilen in Chronik, Ergebnis, Belohnung (`menu_sheets._share_glyph`) | `Symbol: three connected dots forming a share sign.` |
| `g_check.png` | „IM BESITZ“, Biom/Schwierigkeit gewählt, UI-Stil | `Symbol: a bold check mark.` |
| `g_arrow_left.png` / `g_arrow_right.png` | Stamm-Karussell, „NOCH OFFEN ▸“ | `Symbol: a bold rounded triangle arrow pointing right.` (links gespiegelt im Code) |
| `g_map.png` | Minimap antippen / große Karte | `Symbol: a folded paper map with a small pin.` |
| `g_sound.png`, `g_vibration.png`, `g_eye.png`, `g_music.png` | Einstellungen (`menu_sheets._setting_glyph`) | `Symbol: a loudspeaker with two sound arcs.` / `a smartphone with two shake lines.` / `an eye with a round pupil.` / `a double music note.` |
| `g_warning.png` | Warnhinweise, Gefahren-Pfeil (`Kit.warn_glyph`) | `Symbol: a rounded warning triangle with an exclamation mark.` |
| `g_daily.png` | Tages-Brut-Sonne (`_b_sun_glyph`, Chronik-Tab) | `Symbol: a sun with eight short rounded rays and a small egg in the center.` |

### B2 Menü-Tabs und Belohnungen (gemalt, farbig)

| Datei | Stelle | heute | Motivzusatz |
|---|---|---|---|
| `tab_brutkammer.png` | Tab Brutkammer | `brood` (Eier) – ok, aber gleich wie Anlage „Brutrate“ | `Motif: a round organic brood chamber of roots with three turquoise eggs glowing inside. Main colors turquoise and bark brown.` |
| `trophy.png` | Tab Trophäen, Aufgaben, Chronik | gezeichnetes SVG | `Motif: a chunky golden trophy cup with two bone handles and a small fang emblem. Main colors gold and bone white.` |
| `tab_instinct.png` | Tab Urinstinkt | `instinct` (SVG, auch Power-up) | `Motif: a glowing orange creature eye with a slit pupil inside a violet flame. Main colors ember orange and violet.` |
| `tab_chronicle.png` | Tab Chronik | `clock` (Bedien-Glyphe) | `Motif: an old scroll of leathery hide with a small clawed paw print and a bookmark tooth. Main colors cream parchment and ember orange.` |
| `hub.png` | Knopf „Brutstätte“ (Ergebnis, Pause) | gezeichnetes SVG (Bogen mit Ei) | `Motif: a small cave den entrance made of roots and bone with a warm ember glow and one egg inside. Main colors bark brown and ember orange.` |
| `alpha_core.png` | Alpha-Kern (HUD-Pille, Overlays, Trophäen) | gezeichnetes SVG | `Motif: a floating amber core crystal cradled inside a violet bony claw shell, warm glowing center. Main colors amber and violet.` |
| `crown.png` | Boss besiegt, Anführer, Trophäen | gezeichnetes SVG | `Motif: a crooked golden crown made of bone spikes with one amber gem. Main colors gold and amber.` |

### B3 Seltenheit und Karten

| Datei | Wofür | heute | Motivzusatz |
|---|---|---|---|
| `rarity_common.png`, `rarity_rare.png`, `rarity_epic.png`, `rarity_legendary.png` (je 512 × 256) | Seltenheits-Plakette oben rechts auf Mutations-/Kokon-Karten | Kit-Chip mit Text | Icon-Stil-Block, aber `A small horizontal gem banner: a cut gemstone in the middle with two short bone wings. Common: grey stone gem. Rare: sky-blue gem. Epic: violet gem. Legendary: gold gem with a tiny crown and sparkles.` |
| `evo_badge.png` | „EVO“-Kennzeichen an Waffen-Medaillen | Kit-Chip mit Text | `Motif: a small violet DNA strand twisting into an upward arrow. Main colors violet and cyan.` |

### B4 Porträts (Stämme)

Drei der sechs Stamm-Porträts sind **umgefärbte** Fremdmotive (Sporling = harvester in Pink, Knochenkiefer = bulk, Nachtmaul = ripper in Violett). Alle Stämme werden außerdem als Kopf-Ausschnitt für die Schwarm-Pille (`mawling_head_<stamm>`) genutzt; eigene Porträts machen beides besser.

| Datei | Stamm | Motivzusatz (Porträt-Stil-Block) |
|---|---|---|
| `tribe_sporling.png` | Sporling | `Motif: a small pastel-pink predator creature with round spore sacs on its back and a softer rounder jaw with ivory teeth, curious look, tiny glowing spores.` |
| `tribe_knochenkiefer.png` | Knochenkiefer | `Motif: a sturdy small predator creature with bone-white armor plates on head and back and a heavy wedge jaw, stubborn look.` |
| `tribe_nachtmaul.png` | Nachtmaul | `Motif: a slim midnight violet-black predator creature with faint cyan glowing eyes and spots, long curved fangs, sly look.` |
| `tribe_sandling.png` (falls ein Wüstenstamm kommt) | Wüstenstamm | `Motif: a small pale ochre predator creature with a flat shovel-like jaw, sand-colored plates and blue-grey shadows.` |

## C – später

| Datei | Wofür | heute | Motivzusatz / Größe |
|---|---|---|---|
| `bg_result.png` (1080 × 1920) | Ergebnis-/Aussterben-Bildschirm | Spielwelt abgedunkelt | Hintergrund-Stil-Block + `Vertical portrait: an abandoned creature den in a jungle at dusk, a ring of broken bones and eggshells, warm ember light from below, deep violet sky.` |
| `bg_sheet.png` (1080 × 1920, kachelbar oben/unten) | Hintergrund der Menü-Sheets | Kit-Verlauf | `Seamless dark blue-violet organic texture of subtle leaves and roots, very low contrast, for UI panels.` |
| `bg_loading.png` (1080 × 1920) | Ladebildschirm/Splash | – (keiner) | `Vertical portrait: the MAWLINGS swarm pouring out of a giant root cave toward the viewer, ember-red creatures, dramatic light, empty top third for the logo.` |
| `biome_duerrschlund.png` (1536 × 1024) | Biomkarte Dürrschlund im Menü | fehlt | Hintergrund-Stil-Block + `Pale ochre desert dunes with bleached giant rib bones, a turquoise oasis with green rim, pink cactus flowers, cool blue-grey shadows, a sand worm fin in the distance.` |
| `biome_verdant.png`, `biome_glutsumpf.png`, `biome_duerrschlund_icon.png` | Biom-Banner, Wahl-Chips | gezeichnete SVG (kleine Blätter, dunkel bei 40 px) | Icon-Stil-Block + `Motif: a tiny landscape emblem: a moss hill with a big fern leaf` / `a black lava rock with a glowing magma crack` / `a sand dune with a bone rib arch`. |
| `hunter.png` | Jäger (Ergebnis, Overlays) | SVG violetter Haikopf, passt nicht zum Käfer-Modell | `Motif: the head of a purple-magenta predator beetle-lizard from the front-left, narrow blade-like armored head, two curved horns, glowing orange eyes.` |
| `sandgrub.png` | Sandgrub (Wüstengegner) | fehlt | `Motif: a fat pale larva-like sand grub with a round toothy mouth rearing up, ochre segments. Main colors pale ochre and pink mouth.` |
| `leaper.png` | Mire Leaper | SVG, steif | `Motif: a crouching green frog-like leaper creature about to jump, long hind legs, wide jaw. Main colors swamp green and yellow belly.` |
| `erdbeben.png` | Erdbeben (Evolution) | SVG mit eigenem Goldring | `Motif: three bone-white stone spikes erupting from cracked brown earth with flying rock chunks, orange shock lines.` |
| `diff_brutal.png` | Schwierigkeit Brutal | SVG dünne Krallenstriche | `Motif: three deep red claw slashes torn through a dark stone plate.` |
| Relikte (19) | Kokon-Karten, HUD-Relikt-Kacheln | Stellvertreter aus anderen Icons (siehe `ICON_REQUESTS.md`, Abschnitt Etappe 17, Tabelle „Priorität B“) | Motivzusätze unverändert aus `ICON_REQUESTS.md` übernehmen: `hungerstein`, `zaehe_haut`, `scharfe_zaehne`, `flinke_beine`, `witterungsnase`, `dna_splitter`, `sporenherz`, `aetzdruese`, `rudelhorn`, `gewitterfell`, `grabkralle`, `gluecksknochen`, `koenigszahnkette`, `zwillingsbrut`, `magnetkern`, `urmutter`, `blutmond`, `schlundherz`. |
| `klauenwirbel.png`, `giftbiss.png` | Klauenwirbel/Giftbiss (Waffen) | seit 28.09. Soforthilfe aus Nutzer-Bildern (siehe unten) | Eigenes Motiv nur, wenn die Soforthilfe im Spiel stört: `three curved bone claw blades spinning as a pinwheel with ember motion streaks` / `a snapping jaw with two long fangs dripping bright toxic green venom`. |

---

## Soforthilfe am 28.09. (aus vorhandenen Nutzer-Bildern, ohne Lieferung)

| ID | vorher | jetzt | Quelle |
|---|---|---|---|
| `mawling_head_color` | gezeichnetes SVG (oranger Comic-Kopf) | Kopf-Ausschnitt aus dem Glutmaw-Porträt, V4-Kontur | `UI_Assets_V2/Portraits/Tribes/base_mawling.png` → `assets/ui/v3/heads/glutmaw.png` → V4 |
| `mawling_head` (zum Einfärben) | weißes SVG | derselbe Kopf als helles Knochenweiß mit gemalter Schattierung | wie oben, `bone_white()` im V4-Skript |
| `mawling_head_<stamm>` (neu, 6) | – | Kopf-Ausschnitte aller Stamm-Porträts (inkl. Umfärbung) | `assets/ui/v3/heads/<stamm>.png`; Abfrage `UiIcons.strain_head(stamm)` |
| `klauenwirbel` | Monogramm „K“ | drei gebogene Knochenklingen (V3 `razor_offense`) | `Icons/Evolutions/razor_offense.png` |
| `giftbiss` | Monogramm „G“ | Nutzer-Icon `bite` (offenes Maul), Kiefer giftgrün umgefärbt | `Icons/Attacks/bite.png` (bisher ungenutzt) |

Nicht genutzt, weil das Motiv nicht passt: `crownfang`, `spine_mother` (Boss-Porträts ohne Spielboss), `carapace_survival` als Chitinschild (violetter Rand = Spezial, nicht Schutz/Blau), `hunger_mass` als Lockduft (goldene Eier lesen sich als Brut).

---

## Inventur aller sichtbaren Bild-Elemente (28.09.)

Herkunft: **(a)** gemaltes Nutzer-Asset (V2/V3-Paket, auch als V4 nachbearbeitet) · **(b)** von uns gezeichneter Vektor/SVG-Platzhalter · **(c)** lokal im Code gezeichnete Glyphe oder Kit-Form (inkl. der 8 V4-Glyphen aus dem Build-Skript) · **(d)** Buchstaben-Monogramm/Fallback.

| Bildschirm | Element | Herkunft | Bewertung |
|---|---|---|---|
| HUD oben | Schwarm-Pille Kopf | a (neu) | ok; grau-weiß auf Orange liest sich, farbiger Stammkopf auf dunkler Plakette wäre besser (siehe Anbindung) |
| HUD oben | Uhr, Druck-Segmente | c | ok |
| HUD oben | Königszahn-Pille | b | flach, kontrastarm → A3 |
| HUD oben | Pause | c (V4) | ok |
| HUD oben | Druck-Pille Schädel | b | doppelt mit Flut/Apex → A3 |
| HUD oben | Alpha-Kern-Pille | b | ok, B2 |
| HUD rechts | Waffen-Medaillen | a (Rudelbiss, Sporen, Säure, Gräber, Blitz, Stachel, Brutsack, Klauenwirbel, Giftbiss), b (Ätzflut, Erdbeben, Sturmrudel), **d** (Schallbrüller) | Schallbrüller Monogramm → A1 |
| HUD rechts | Relikt-Kacheln | a/b Stellvertreter, **d** (Glutdrüse) | fast alle doppelt → A1/C |
| HUD links | Power-up-Ringe | a/b Stellvertreter | alle doppelt belegt → A2 |
| HUD | Rank-Punkte, EVO-Chip, Level-Badge | c | ok |
| Minimap | Rahmen, N-Kompass, Spielerpfeil, Punkte | c | ok; Nest/Totem-Marker a |
| Große Karte | Legende (Punkte), Schließen-X | c | X → B1 |
| Steuerung | Rally-Knopf, Joystick mit Pfeildreiecken | c | Kit, stimmig; kein Bedarf |
| Tipps | Tipp-Icon (Rudelinstinkt), Chevron | a / c | `pack` sieht aus wie Reißzähne ×3 → A1 |
| Warnungen | Warn-Dreieck | c | B1 |
| Mutation/Kokon/Schrein | Karten-Icons | a (Anlagen, Waffen), b (Evolutionen-SVG), Stellvertreter für Werte, **d** (Schallbrüller, Glutdrüse) | Angriffstempo = Uhr-Glyphe, Reichweite = Klauenwirbel-Bild → A1 |
| Mutation | Neu würfeln, Überspringen, Verbannen | c (V4) | ok |
| Mutation | Seltenheits-Chip, NEU-Badge | c | B3 |
| Boss-Leiste | Bog King, Moosschlund, Aschenkröte | a | gut; Sandwurm fehlt → A3 |
| Banner | Flut/Apex (Schädel), Anführer/Meilenstein (Kopf), Boss (Krone), Evolution, Sieg (Pokal) | b / a | Schädel doppelt → A3 |
| Ergebnis | Uhr, Peak (Kopf), Kills, Biomasse, Bosse, Build, Essenz, Königszahn, Aufgaben-Pokal, Nochmal/Brutstätte | c, a, a, a, b, a, b, b, b, c/b | „TEILEN“ ohne Icon; Pokal/Essenz/Zahn flach |
| Pause | Uhr, Kopf, DNA, Build, Weiter/Neustart/Brutstätte | c, a, a, a, c/c/b | ok |
| Menü Hauptseite | Logo, Stamm-Porträt, Biomkarten | a | stark |
| Menü Hauptseite | Essenz, Königszahn (Leiste) | b | schwächste Stelle ganz oben → A3 |
| Menü Hauptseite | Zahnrad, Karussell-Pfeile, Punkte, Häkchen, Schloss, Sonne (Tages-Brut), ▲-Chips | c | Zahnrad/Sonne/Pfeile wirken hausgemacht → B1 |
| Menü Hauptseite | Schwierigkeit Wild/Brutal/Apex | b | Brutal dünn → C |
| Menü Hauptseite | SPIELEN-Kopf, Rekord-Zeile | a (neu), c | gut |
| Menü-Tabs | Brutkammer, Trophäen, Urinstinkt, Chronik | a, b, b, c | uneinheitlich → B2 |
| Sheet Brutkammer | Upgrade-Icons | a (V4) | gut |
| Sheet Trophäen | Pokal, gesperrte Silhouetten | b, c | ok |
| Sheet Einstellungen | Lautsprecher, Handy, Auge, Note | c | amateurhaft neben den gemalten Icons → B1 |
| Sheet Chronik | Stammköpfe in den Zeilen, Tabs (Uhr, Sonne, Pokal), Teilen | a, c/c/b, c | Teilen-Glyphe → B1 |
| Sheet Urinstinkt | Instinkt, Play-Pfeil | b, c | → B2 |
| Belohnung | Essenz, Königszahn, Trophäen-Liste | b | → A3/B2 |
| Teilen-Karte | Logo, Porträt, Uhr, Kopf/Kills/Biomasse, Build, Fuß-Kopf | a, a, c, a, a, a | gut; Hintergrund = Menü-Hintergrund (C `bg_result`) |

**Zählung der Elementarten** (ca., jede Art einmal je Bildschirmgruppe): **(a) ≈ 34**, **(b) ≈ 17**, **(c) ≈ 29**, **(d) 2** (Schallbrüller, Glutdrüse; dazu jede künftige ID ohne Icon). Doppelt belegte Motive: 25 Werte/Relikte/Power-ups zeigen ein Icon, das an anderer Stelle etwas anderes bedeutet.

**Die schlimmsten Stellen:** (1) Währungsleiste oben im Menü (Essenz-Tropfen und Königszahn sind flache SVGs direkt neben dem gemalten Logo); (2) Power-up-Ringe und Relikt-Kacheln im HUD – alles Stellvertreter, u. a. die Uhr-Glyphe als „Blutrausch“; (3) Einstellungen-Sheet mit vier Code-Glyphen; (4) Schallbrüller/Glutdrüse als Buchstaben; (5) ein Schädel für Flut, Druck und „Apex erscheint“.

## Etappe 17d – Stammesfähigkeiten (neu angefragt)
- **Sechs Fähigkeits-Icons** für den runden Knopf über Rally (bisher Stammesköpfe): Glutsprung (Sprungbogen mit Glutspur), Sporenbombe (Sporenwolke), Panzerstoß (Schockwelle am Knochenschild), Hetzjagd (Pfeilreihe/Laufspur), Säureschwall (Säurekegel), Schattenschleier (Schleier/Auge). Stil wie V4, Grundfarbe Glut, bei 64 px lesbar.
- **Vier Relikt-Icons**: Glutkern (Stundenglas mit Glutkern; bisher „haste“), Feuerspur (brennende Spur; bisher „glutdruese“), Sporenhall (Echo-Wolke; bisher „sporenwolke“), Weiter Schlund (weites Maul; bisher „reach“).
