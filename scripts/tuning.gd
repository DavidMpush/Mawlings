extends RefCounted

# Shared prototype balance, expressed in seconds and world units.
#
# Balance (Etappe 05): gemessen mit tests/balance_sim.gd / tools/balance.ps1 (Bot mit
# 0,45 s Reaktionszeit, übersieht 12 % der Warnungen; 3 Stämme x 3 Seeds x 2 Strategien).
# Ziel-Kurve (Median-Tod): Wild 6-12 min, Brutal 4-7 min, Apex 2,5-5 min; Wild nie < 2 min.
# Stand nach Treffer-pro-Tier: Wild ~9:07, Brutal ~4:53, Apex ~3:26 (alle im Ziel).
# Druck = 2^(Zeit / pressure_doubling) bleibt exponentiell; die Schwierigkeit setzt nur
# pressure_doubling sowie Gegner-HP/-Schaden-Multiplikatoren (scripts/meta/meta_data.gd).
# Tod entsteht praktisch immer, sobald ein übersehener Treffer (Basis x Druck) die
# Population übersteigt – daher bestimmt pressure_doubling die Lauflänge am stärksten.
# Formen-Zahlen (Schaden/Cooldowns) stehen in scripts/attack_forms.gd.
#
# Etappe 08 (höhere Grundschwierigkeit + "Die Flut"): neue Ziel-Kurve Wild 6:30-8:30
# (Median-Population bei 2:00 <= 160), Brutal 5:00-6:30, Apex 3:30-4:30. Matrix mit
# 6 Seeds (108 Läufe): Wild 409 s / Pop 2:00 149, Brutal 340 s, Apex 263 s (vorher 517 /
# 250 / 287 / 200 s). Begründung der Hebel:
# - Wachstum: alle Kadaver-Biomassen ~ -40 % (Beute 12 -> 6, Jäger 26 -> 8, Nest 44 -> 18,
#   Boss 110 -> 60). Mehr Jäger heißt mehr Futter; ohne den Schnitt erreichte der Bot auf
#   Wild bei 2:00 immer die 250.
# - Druck: Jäger ab 14 s, Budget 1 + t/25 (vorher 1 + t/35), Abstand 9/sqrt(Druck);
#   Skitter ab 35 s, Leaper ab 50 s; Jägerschaden 6 -> 8, HP 22 -> 26; alle Gegner mit
#   kürzerer Erholung/Lauerzeit, die mit dem Druck weiter schrumpft (recovery()).
# - Wild-Verdopplung 90 -> 80 s; längere Läufe endet die Flut (ab 5:00), nicht der Druck.
# - DIFFICULTY_RAMP_SECONDS: Brutal/Apex-Multiplikatoren wirken erst nach 75 s voll,
#   sonst war der Start bimodal (Tod nach 35 s oder normaler Lauf).
#
# Etappe 09 (Einzelstart mit Anführer, alle Gegner inkl. Nibbler greifen an): Ziel-Kurve
# Wachstum (Wild, Median) 1:00 -> 6-14, 2:00 -> 25-55, Flutbeginn -> 80-160; Tod wie
# Etappe 08. Matrix 3 Stämme x 2 Strategien x 6 Seeds (Brutal 8): Wild 398 s (Pop 12 /
# 32,5 / 145,5, 6 % unter 2:00), Brutal 320 s, Apex 226 s. Begründung der Hebel:
# - Wachstum: 1 -> 62 Tiere in der ersten Minute ohne Eingriff. Biomasse je Mawling
#   2,0 -> 3,5; Angriffsformen x P/25 (min. 0,1); Nest erst nach 60 s mit 12 (+3 je Nest);
#   Beute 6 -> 5 alle 10 s (vorher 9 s); Jäger 8 -> 5, Skitter 9 -> 6, Leaper 10 -> 7,
#   Boss 60 -> 40. Rückeroberung 1,0 je Gefallenem hält die Mitte (sonst Flut-Pop ~70).
# - Fairer Start: jeder übersehene Ring löscht einen kleinen Schwarm fast ganz aus und
#   kostet 1 LP. Jäger erst bei >= 4 Tieren oder ab 50 s (Tor gilt weiter, bis es offen
#   bleibt), höchstens 1 + P/8 gleichzeitig, Spawnabstand bei kleinem Schwarm bis x3;
#   Skitter ab 50 s und P >= 12, Leaper ab 65 s und P >= 15, erster Boss ab 120 s bei
#   P >= 40 (spätestens 240 s); kleiner Schwarm beißt +1,5/s. Nibbler: erster Schnapp
#   nach 4 s, Warnung 0,6 -> 0,8 s, nur ein Kreis gleichzeitig + 3 s Pause, nie das letzte LP.
# - DIFFICULTY_RAMP 75 -> 120 s, Brutal-HP 1,4 -> 1,3, Brutal-Schaden 1,2 -> 1,1
#   (meta_data): der Einzelstart wuchs auf Brutal/Apex sonst kaum über 20 Tiere.
#
# Etappe 10 Teil 2 (Regeneration begrenzt, Wild-Wachstum auf Etappe-09-Kurve): Matrix
# 3 Stämme x greedy/attack_first x 6 Seeds, mit Apex/Migration: Wild 400 s (Pop 11 / 36 /
# 132, keiner unter 2:00, längster 478 s), Brutal 307 s, Apex 219 s (vorher 398 / 290 /
# 217 s, Wild-Pop 1:00 16,5). Strategie form:regeneration (4 Seeds): Median 331/266/202 s,
# Ausreißer höchstens +40 % (vorher bis 777 s). Begründung der Hebel:
# - Regeneration (evolution.gd): Moorbrut zählt nur REGEN_HORDE_WEIGHT 0,15 Kill, höchstens
#   1 LP je REGEN_GAP 30/25/20 s, kein Ansparen in der Pause; Flut-Kills heilten sonst
#   jede Sekunde ein LP und hielten den Anführer ewig am Leben.
# - Beute-Kadaver CORPSE_BIOMASS 5 -> 4: Beute ist in der ersten Minute die Hauptnahrung
#   (Pop 1:00 16,5 -> 11), später zählt sie kaum.
# - Wild-Verdopplung 80 -> 85 s (meta_data + Standard hier): gleicht die kleinere erste
#   Minute aus (Wild-Median sonst 384 s); Brutal-Schaden 1,1 -> 1,05 (Median 290 -> 307 s).
const PRESSURE_DOUBLING_SECONDS := 85.0
# Etappe 09 (Einzelstart, Anführer): jeder Run beginnt mit START_POPULATION Tier(en);
# units[0] ist der Anführer mit LEADER_HP Lebenspunkten (Config-Feld leader_hp
# überschreibt). Etappe 17c: echte LP - Flächen-/Biss-Treffer auf ihn kosten
# LEADER_HIT[Angreifer] × Druck^LEADER_HIT_PRESSURE × Schwierigkeit LP statt Tod, danach
# LEADER_INVULNERABLE_SECONDS Unverwundbarkeit. LP 0: er stirbt, das nächste Tier
# übernimmt mit LEADER_SUCCESSOR_SHARE des alten Maximums, voll geheilt.
# +LEADER_HEAL_AMOUNT LP (bis Max) bei jedem erstmals erreichten Vielfachen von
# LEADER_HEAL_STEP. Meilensteine (Banner/Sound) je Run einmal.
const START_POPULATION := 1
# Biomasse je neuem Mawling (vorher 2,0 in run_model.gd).
const BIOMASS_PER_MAWLING := 3.5
# Angriffsformen skalieren mit der Schwarmgröße: x clamp(P / FORM_FULL_POPULATION,
# FORM_MIN_SHARE, 1) – ein einzelner Mawling spuckt/sport nicht wie ein Rudel.
const FORM_FULL_POPULATION := 25.0
const FORM_MIN_SHARE := 0.1
# Etappe 21 (Nutzerwunsch „Power soll linear unendlich skalieren“): über
# FORM_FULL_POPULATION wachsen die Formen ohne Deckel weiter, abgeschwächt mit
# (P / 25)^FORM_GROWTH_EXPONENT: 100 Tiere x2, 250 x3,2, 500 x4,5, 1000 x6,3. Der
# Nahkampf (1 + 0,12 x P) bleibt linear; die Flut (2^k) bleibt das Gegengewicht.
const FORM_GROWTH_EXPONENT := 0.5


## Faktor der Angriffsformen (und der Stammes-Fähigkeit) für `population` Tiere.
static func form_population_scale(population: int) -> float:
	var share := float(population) / FORM_FULL_POPULATION
	if share <= 1.0:
		return maxf(FORM_MIN_SHARE, share)
	return pow(share, FORM_GROWTH_EXPONENT)
const LEADER_HP := 100
const LEADER_INVULNERABLE_SECONDS := 1.2
const LEADER_HEAL_STEP := 25
const LEADER_HEAL_AMOUNT := 15
const LEADER_SUCCESSOR_SHARE := 0.8
## LP je Treffer auf den Anführer nach Angreifer (× Druck^LEADER_HIT_PRESSURE × Schwierigkeit).
const LEADER_HIT_PRESSURE := 0.35
const LEADER_HIT := {"prey": 10, "hunter": 20, "elite": 28, "skitter": 16, "leaper": 22, "boss": 35,
	"eruption": 15, "apex": 30, "apex_puddle": 10, "horde": 4, "default": 20}
## Etappe 17b: kein Populationslimit mehr; Meilensteine bis 10.000.
const MILESTONES := [5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000]
# Rückeroberung: jeder gefallene Mawling lässt so viel Biomasse liegen (gebündelt in
# nahe Kadaver wie Horde-Kills, Ressourcenregel); 1,0 von 3,5 = ~30 % zurückholbar.
const FALLEN_BIOMASS := 1.0
const FALLEN_BUNDLE_REACH := 3.0
# Erster Jäger frühestens ab FIRST_HUNTER_SECONDS UND (Population >= FIRST_HUNTER_POPULATION
# ODER Zeit >= FIRST_HUNTER_LATEST): der einzelne Anführer bekommt eine faire Anlaufphase.
const FIRST_HUNTER_POPULATION := 4
const FIRST_HUNTER_LATEST := 50.0
const FIRST_HUNTER_GRACE := 3.0
# Gleichzeitige Jäger höchstens 1 + P / HUNTER_POPULATION_STEP (bindet nur früh; später
# begrenzt das Zeitbudget). Ohne das jagen zwei Jäger einen auf 1-3 Tiere
# geschrumpften Schwarm, der sie kaum noch töten kann (Todesspirale in 25 % der Läufe).
const HUNTER_POPULATION_STEP := 8
# Nahkampf-Bonus kleiner Schwärme (größere Einzeltiere): + SMALL_SWARM_BITE Schaden/s
# bei 1 Tier, linear 0 bei 25 Tieren (Formel dort unverändert 1 + 0,12 x P).
const SMALL_SWARM_BITE := 1.5
# Abstand zwischen Jäger-Spawns x (1 + HUNTER_SMALL_SWARM_DELAY x (1 - P/25)): ein
# kleiner Schwarm bekommt Luft, jeder übersehene Ring kostet ihn fast alles.
const HUNTER_SMALL_SWARM_DELAY := 2.0
# Skitter/Leaper gleichzeitig höchstens P / STEP (unter einem Schritt keiner): kleine
# Schwärme sehen erst Jäger, Seitenbedrohungen kommen mit dem Wachstum dazu.
const SKITTER_POPULATION_STEP := 12
const LEAPER_POPULATION_STEP := 15
# Gegner-HP/-Schaden der Schwierigkeit wachsen in den ersten so vielen Sekunden von x1 auf
# den vollen Wert (Etappe 08: sonst löscht der erste Jäger auf Brutal/Apex den Startschwarm).
const DIFFICULTY_RAMP_SECONDS := 120.0
const FIRST_HUNTER_SECONDS := 14.0
const HUNTER_HEALTH := 26.0
const HUNTER_DAMAGE := 8.0
const HUNTER_SPEED := 2.4
const HUNTER_WARNING_SECONDS := 1.25
const HUNTER_RECOVERY_SECONDS := 1.1      # Etappe 08: 1,7 -> 1,1 (alle greifen an)
const HUNTER_ARRIVE_SECONDS := 0.5
const HUNTER_ATTACK_RADIUS := 2.3
const HUNTER_BIOMASS := 5.0
const MAX_HUNTERS := 12
# Spawn-Direktor (Etappe 08 als Konstanten): Budget = BASE + Zeit / BUDGET_SECONDS,
# Abstand = max(MIN, SPAWN_SECONDS / sqrt(Druck)).
const HUNTER_BUDGET_BASE := 1
const HUNTER_BUDGET_SECONDS := 25.0
const HUNTER_SPAWN_SECONDS := 9.0
const HUNTER_SPAWN_MIN := 2.2
const MAX_PREY := 5
const PREY_RESPAWN_SECONDS := 10.0
const CORPSE_BIOMASS := 4.0         # Etappe 10 Teil 2: 5 -> 4 (Beute-Biomasse, als Kristalle)

const FIRST_SKITTER_SECONDS := 50.0
const SKITTER_HEALTH := 15.0
const SKITTER_DAMAGE := 4.0
const SKITTER_SPEED := 3.2
const SKITTER_WARNING_SECONDS := 1.0
const SKITTER_DASH_SECONDS := 0.4
const SKITTER_RECOVERY_SECONDS := 1.3     # Etappe 08: 2,0 -> 1,3
const SKITTER_ARRIVE_SECONDS := 0.4
const SKITTER_RANGE := 7.0
const SKITTER_WIDTH := 1.15
const SKITTER_BIOMASS := 6.0
const MAX_SKITTERS := 3
const SKITTER_BUDGET_SECONDS := 90.0
const SKITTER_SPAWN_SECONDS := 26.0
const SKITTER_SPAWN_MIN := 6.0

const FIRST_BOSS_SECONDS := 120.0
const BOSS_RESPAWN_SECONDS := 180.0
# Etappe 09: der erste Bog King kommt ab FIRST_BOSS_SECONDS erst bei >= BOSS_MIN_POPULATION
# Tieren, spätestens nach BOSS_LATEST_SECONDS (vorher löschte er kleine Schwärme aus).
const BOSS_MIN_POPULATION := 40
const BOSS_LATEST_SECONDS := 240.0
const BOSS_HEALTH := 1900.0   # Etappe 21: 230 -> 1900 (Kontaktzeit ~4 s -> Wild 16 s / Brutal 29 s)
const BOSS_SPEED := 1.6
const BOSS_WARNING_SECONDS := 1.8
const BOSS_RECOVERY_SECONDS := 2.5
const BOSS_ATTACK_RADIUS := 3.6
const BOSS_DAMAGE := 14.0
const BOSS_BIOMASS := 40.0

# Mire Leaper: ambush jumper that lands on a locked, announced zone.
const FIRST_LEAPER_SECONDS := 65.0
const LEAPER_HEALTH := 18.0
const LEAPER_DAMAGE := 4.0
const LEAPER_SPEED := 2.2
const LEAPER_RANGE := 9.0
const LEAPER_ZONE_RADIUS := 2.6
const LEAPER_LURK_SECONDS := 1.5         # Etappe 08: 2,5 -> 1,5
const LEAPER_ARRIVE_SECONDS := 0.5
const LEAPER_WARNING_SECONDS := 1.1
const LEAPER_FLIGHT_SECONDS := 0.55
const LEAPER_EXHAUST_SECONDS := 1.8
# Etappe 09 (Nutzerwunsch "alle Feinde laufen auf mich zu"): no retreat after
# the landing any more; the leaper chases on and locks its next jump after this
# short breath, and walks in until it touches the swarm's edge.
const LEAPER_CHASE_LURK_SECONDS := 0.8
const LEAPER_CONTACT_DISTANCE := 1.8
const LEAPER_BIOMASS := 7.0
const LEAPER_DNA := 15
const MAX_LEAPERS := 3
const LEAPER_BUDGET_SECONDS := 80.0
const LEAPER_SPAWN_SECONDS := 28.0
const LEAPER_SPAWN_MIN := 7.0

# Run-Ziele (Etappe 06). Brutnest: Kreiszone, die der Schwarm durch Anwesenheit
# füllt; bei voll bleibt ein Gelege als normale Kadaver-Biomasse liegen.
# Füllrate/s = Anteil der Tiere in der Zone / NEST_FILL_SECONDS x Populationsfaktor
# (1,0 bei 25 Tieren, +1 je NEST_POPULATION_STEP weitere Tiere, max. NEST_MAX_SPEED).
const NEST_FIRST_SECONDS := 60.0
const NEST_RESPAWN_SECONDS := 30.0
const NEST_RADIUS := 4.0
const NEST_FILL_SECONDS := 8.0
const NEST_POPULATION_STEP := 125.0
const NEST_MAX_SPEED := 2.6
const NEST_BIOMASS := 12.0          # erstes Nest; jedes weitere + NEST_BIOMASS_GROWTH
const NEST_BIOMASS_GROWTH := 3.0
const NEST_CLUTCH := 3              # Biomasse verteilt auf so viele Eier-Kadaver
const NEST_DNA := 25
const OBJECTIVE_MIN_DISTANCE := 14.0
const OBJECTIVE_MAX_DISTANCE := 22.0
const OBJECTIVE_START_CLEARANCE := 12.0   # Abstand zum Startpunkt (0,0)

# Fluch-Totem: erscheint vor einem Boss (wenn keiner lebt); 1,5 s im Radius halten
# nimmt den Fluch an: nächster Boss +50 % HP/Schaden, bis zu dessen Tod doppelte
# Biomasse/DNA. Nicht angenommene Totems zerfallen, sobald der Boss erscheint.
const TOTEM_RADIUS := 1.8
const TOTEM_HOLD_SECONDS := 1.5
const TOTEM_LEAD_SECONDS := 50.0    # erscheint, wenn der Boss in <= so vielen s kommt
const TOTEM_MIN_LEAD_SECONDS := 15.0
const TOTEM_CHANCE := 0.75          # ab dem zweiten Boss-Zyklus; der erste hat immer eins
const CURSE_BOSS_MULTIPLIER := 1.5
const CURSE_REWARD_MULTIPLIER := 2.0

# Elite-Jäger: größer, gekrönt, mehr HP, garantierter Alpha-Kern.
const ELITE_FIRST_SECONDS := 180.0
const ELITE_INTERVAL_SECONDS := 180.0
const ELITE_HEALTH_MULTIPLIER := 4.0
const ELITE_SCALE := 1.45
const ELITE_BIOMASS := 26.0
const ELITE_DNA := 40

# Die Flut (Etappe 08): ab FLOOD_START (je Schwierigkeit in meta_data.DIFFICULTIES,
# ohne Config Wild) strömt Moorbrut (scripts/horde.gd) in Ringen um den Schwarm an.
# Flutstufe k = Sekunden seit Flutbeginn / FLOOD_DOUBLING_SECONDS; HP, Biss und
# Wellengröße wachsen mit 2^k, das Tempo auch, aber gedeckelt unter dem Schwarmtempo
# (FLOOD_SPEED_SHARE), damit man der Brut immer noch davonlaufen kann.
const FLOOD_START_SECONDS := 300.0
const FLOOD_WARNING_SECONDS := 10.0
# Etappe 27 (Nutzerentscheidung c): in Welt n beginnt die Flut bei Weltzeit
# flood_start x FLOOD_WORLD_FACTOR^(n-1), frühestens FLOOD_WORLD_MIN.
const FLOOD_WORLD_FACTOR := 0.42   # Etappe 32: 0.6 -> 0.42 (Wild 330 -> 139 -> 60 s; later worlds end runs again)
const FLOOD_WORLD_MIN := 60.0
# ... und startet dort FLOOD_WORLD_STAGE Stufen höher je Welt.
const FLOOD_WORLD_STAGE := 1.95   # Etappe 32: 1.5 -> 1.95 (world 2 x3.9, world 3 x15)
const FLOOD_DOUBLING_SECONDS := 24.0     # Etappe 21: 40 -> 24 (Waffen wachsen jetzt ohne Deckel, stages/21_balance.md)
const FLOOD_WAVE_SECONDS := 3.0
const FLOOD_WAVE_COUNT := 8          # Brut pro Welle bei Stufe 0; x 2^k bis FLOOD_WAVE_MAX
const FLOOD_WAVE_MAX := 40
const FLOOD_MAX_ACTIVE := 160         # gleichzeitig lebende Brut (Leistungsdeckel)
const FLOOD_HP := 1.2
const FLOOD_BITE := 0.4               # Biss-Multiplikator: Verlust je gebissenem sichtbarem Tier x 2^k
const FLOOD_BITE_COOLDOWN := 0.8
const FLOOD_SPEED := 3.4
# Etappe 21: 6,0 -> 8,5. Mit dem alten festen Deckel lief ein schneller Build
# (Flinkzahn + Sprinter, > 7,3 m/s) der Brut dauerhaft davon (ein Wild-Lauf > 15 min);
# jetzt gilt bis 8,5 m/s wieder der Anteil FLOOD_SPEED_SHARE am Schwarmtempo.
const FLOOD_SPEED_CAP := 8.5
const FLOOD_SPEED_SHARE := 0.82       # nie schneller als 82 % des Schwarmtempos
const FLOOD_RING_RADIUS := 23.0       # außerhalb des Hochformat-Bildes
const FLOOD_RING_SHIFT := 7.0         # Ringmitte nach "oben" (-Z): oben sieht die Kamera weiter
const FLOOD_BUNDLE_SECONDS := 0.35    # Brut-Kills werden so lange je Zelle gesammelt (Etappe 16: 1,0 -> 0,35, Kristalle)
const FLOOD_BUNDLE_CELL := 3.0
const FLOOD_KILL_BIOMASS := 0.3       # Etappe 16: 1,5 -> 0,3 (der Magnet holt jetzt fast jede Brut-Beute)
const FLOOD_KILL_DNA := 1

# Nibbler wehren sich (Etappe 08): gebissen oder umzingelt schnappen sie nach einer
# Warnung in einen kleinen Kreis; nur Tiere darin fallen (Treffer pro Tier).
const NIBBLER_SNAP_RADIUS := 1.2
const NIBBLER_SNAP_WARNING := 0.8
const NIBBLER_SNAP_COOLDOWN := 4.0       # Etappe 09: 3,0 -> 4,0; schrumpft mit dem Druck (recovery)
const NIBBLER_SNAP_COOLDOWN_MIN := 2.0
const NIBBLER_SNAP_FIRST := 4.0          # nach dem Erscheinen erst so spät der erste Schnapp
# Etappe 09 – alle greifen an: Nibbler laufen auf den Schwarm zu (langsamer als er) und
# bleiben in Schnappweite; nach NIBBLER_SNAP_GLOBAL_GAP s darf erst der nächste Nibbler
# ankündigen (nie zwei Schnapp-Kreise gleichzeitig), damit ein einzelner Anführer nicht
# überrannt wird. Ein Nibbler-Schnapp nimmt dem Anführer nie das letzte LP.
const NIBBLER_APPROACH_SPEED := 1.7
const NIBBLER_APPROACH_SPEED_MAX := 3.4
const NIBBLER_HOLD_DISTANCE := 1.3
const NIBBLER_SNAP_GLOBAL_GAP := 3.0
const NIBBLER_SNAP_RANGE := 2.2       # Schwarm so nah = umzingelt
const NIBBLER_SNAP_REACH := 0.5       # Kreismitte so weit vor dem Nibbler (Richtung Schwarm)
const NIBBLER_SNAP_DAMAGE := 1.5      # Basisverlust bei vollem Treffer; x Druck^0,6
const NIBBLER_PROVOKED_SECONDS := 1.5

# Etappe 08: Erholung/Lauern schrumpfen mit dem Druck (Faktor 1 / (1 + CUT x log2 Druck)),
# nie unter `minimum` – bei hohem Druck greifen alle Gegner fast pausenlos an.
const RECOVERY_PRESSURE_CUT := 0.2


static func recovery(base: float, pressure: float, minimum: float) -> float:
	return maxf(minimum, base / (1.0 + RECOVERY_PRESSURE_CUT * log(maxf(1.0, pressure)) / log(2.0)))


# Etappe 10 – Apex-Boss „Moosschlund“ (scripts/apex_boss.gd) im Run. Er erscheint vor
# der Flut, einmal je Run: APEX_SPAWN_SECONDS je Schwierigkeit (Wild/Brutal/Apex), sobald
# die Population >= APEX_MIN_POPULATION ist, spätestens APEX_LATEST_EXTRA s danach; ein
# lebender Bog King schiebt ihn auf (höchstens bis Flutbeginn - APEX_FLOOD_MARGIN).
# APEX_WARNING_SECONDS vorher bebt der Boden an der Auftauchstelle (Ankündigung, nichts
# trifft). Solange der Apex lebt, kommt kein neuer Bog King.
const APEX_SPAWN_SECONDS := [235.0, 210.0, 180.0]   # Etappe 32: 225/165/135 -> 235/210/180 (floods now 330/300/270 s)
const APEX_MIN_POPULATION := 45   # Etappe 32: 30 -> 45 (population gate: the endboss meets a real swarm)
const APEX_LATEST_EXTRA := 45.0   # Etappe 32: 30 -> 45
const APEX_FLOOD_MARGIN := 40.0   # Etappe 32: 15 -> 40 (a living Bog King no longer pushes the endboss into the flood)
const APEX_WARNING_SECONDS := 3.0
const APEX_SPAWN_DISTANCE := 12.0
# HP = APEX_HEALTH x APEX_HEALTH_DIFFICULTY (Wild/Brutal/Apex; Brutal/Apex bringen ihn
# früher gegen einen kleineren Schwarm), nicht mit dem Druck skaliert, damit der Kampf
# in der Zeit bis zur Flut zu schaffen ist.
# Etappe 10 Teil 3: Angriffsformen und Nahkampf messen jetzt zum Körperrand
# (body_distance) statt zur Mitte – Formen wie Sporenwolke, Stachelrücken und Erdbeben
# treffen den großen Körper viel öfter. Mit 650 LP dauerte der Kampf im Bot-Median nur
# noch ~13 s (9–15 s bei starken Builds); 1400 LP geben auf Wild ~28 s (Median der
# gewonnenen Kämpfe, Zielkorridor 25–35 s).
const APEX_HEALTH := 3500.0   # Etappe 26: 1700 -> 3500 (Endgegner, Kampf 45-70 s; tests/apex_duration.gd)
const APEX_HEALTH_DIFFICULTY := [1.0, 0.73, 0.66]   # Etappe 21: Brutal 0,75 -> 0,73, Apex 0,6 -> 0,66 (Kämpfe 25-35 s)
const APEX_BIOMASS := 70.0
const APEX_DNA := 120
const APEX_ALPHA_CORES := 2
# Nach dem Tod sinkt der Körper so lange ein, dann öffnet sich der Migrationsschlund
# APEX_PORTAL_OFFSET m hinter dem Kadaver (vom Schwarm aus), damit Fressen nicht migriert.
const APEX_SINK_SECONDS := 2.6
const APEX_PORTAL_DELAY := 1.8
const APEX_PORTAL_OFFSET := 12.0
# Angriffsmuster (Phase 1 / Phase 2); Basisverlust x Druck. Bisher in apex_boss.gd.
const APEX_BODY_RADIUS := 3.4
const APEX_MELEE_RANGE := 5.2
const APEX_SPEED := [1.3, 1.7]
const APEX_ARRIVE_SECONDS := 2.2
const APEX_PHASE_TWO_SHARE := 0.5
const APEX_PHASE_SHIFT_SECONDS := 1.8
const APEX_ATTACK_RANGE := 14.0
const APEX_KEEP_DISTANCE := 6.0
const APEX_COOLDOWN := [2.2, 1.4]
const APEX_EXHAUSTED_SECONDS := [5.0, 4.0]   # Etappe 32: 4/3 -> 5/4 s recovery window
const APEX_EXHAUSTED_VULNERABILITY := 1.5
const APEX_ROOT_WINDUP := [1.5, 1.25]
const APEX_ROOT_DAMAGE := 7.0
const APEX_SPORE_WINDUP := [1.8, 1.5]
const APEX_SPORE_DAMAGE := 6.0
const APEX_QUAKE_WINDUP := [2.2, 1.9]
const APEX_QUAKE_DAMAGE := 11.0
# Apex-Verluste wachsen nur mit Druck^APEX_PRESSURE_EXPONENT: seine Flächen decken fast
# immer den ganzen Schwarm ab (kein Teiltreffer wie beim Jäger-Ring), und auf Brutal/Apex
# trifft er kleinere Schwärme (~50 statt ~150 auf Wild) bei ähnlichem Druck.
const APEX_PRESSURE_EXPONENT := 0.6

# Migration (Etappe 10): der Migrationsschlund (scripts/migration_maw.gd) bleibt offen,
# bis der Schwarm ihn betritt (Anteil sichtbarer Tiere >= MIGRATION_SHARE für
# MIGRATION_HOLD_SECONDS; beim Verlassen sinkt der Fortschritt doppelt so schnell).
# Übergang MIGRATION_TRANSITION_SECONDS (Wirbel zu, Biomwechsel bei MIGRATION_SWITCH_AT,
# Wirbel auf); die Welt steht in der Zeit still. Ankunft: keine Eruption im Umkreis
# MIGRATION_SAFE_RADIUS, Anführer MIGRATION_ARRIVAL_GRACE s unverwundbar.
const MIGRATION_RADIUS := 4.0
const MIGRATION_SHARE := 0.6
const MIGRATION_HOLD_SECONDS := 1.0
const MIGRATION_TRANSITION_SECONDS := 1.1
const MIGRATION_SWITCH_AT := 0.5
const MIGRATION_SAFE_RADIUS := 12.0
const MIGRATION_ARRIVAL_GRACE := 2.0

# Etappe 10 (Teil 3) – zweiter Apex „Aschenkröte“ (scripts/apex_toad.gd, Muster und
# Formen dort) und Biom-Kreislauf. Ein Apex je Biom-Besuch: der Apex des Startbioms
# kommt nach APEX_SPAWN_SECONDS, nach jeder Migration erscheint der Apex des neuen
# Bioms APEX_ARRIVAL_DELAY s nach der Ankunft (Glutsumpf = Aschenkröte, Verdant Maw =
# Moosschlund), sobald die Population die Schwelle erreicht (spätestens
# APEX_LATEST_EXTRA s danach). Die Kröte braucht einen größeren Schwarm als der
# Moosschlund: nach Moosschlund und Migration hat ein normaler Lauf 50-90 Tiere.
const APEX_ARRIVAL_DELAY := 100.0
const APEX_TOAD_MIN_POPULATION := 40
# LP: überschreibt apex_toad.HEALTH (1500, dort nur für den Einzeltest mit fester DPS).
# Im Run ist der Schwarm bei der Kröte (~100 s nach der Ankunft, meist in der Flut)
# viel stärker als der Einzeltest annimmt, und Formen treffen den Rand: Bot-Läufe
# ohne Flut (balance_sim noflood, Obergrenze der Schwarm-DPS) brauchten mit 1500 LP
# ~11 s, mit 3000 LP ~18 s (≈ 4 s Immun-/Ausweichzeit + LP / ~210 DPS). In der Flut
# ist der Schwarm etwa halb so stark; 3600 LP zielen dort auf ~35–45 s.
const APEX_TOAD_HEALTH := 4100.0   # Etappe 26: 2000 -> 4100 (Kampf 45-70 s)
const APEX_TOAD_BIOMASS := 80.0
const APEX_TOAD_DNA := 150
const APEX_TOAD_ALPHA_CORES := 2
# Jeder weitere Durchlauf durch den Kreislauf (Moosschlund und Kröte kehren zurück):
# LP x APEX_LOOP_HEALTH^Durchlauf, Verluste x APEX_LOOP_DAMAGE^Durchlauf (zusätzlich
# zum Druck, der ohnehin exponentiell steigt).
const APEX_LOOP_HEALTH := 1.6
const APEX_LOOP_DAMAGE := 1.25
# Etappe 26: der Apex ist der Endgegner des Bioms - Verluste x APEX_DAMAGE_MULTIPLIER,
# in Phase 2 zusätzlich x APEX_PHASE_TWO_DAMAGE.
const APEX_DAMAGE_MULTIPLIER := 0.85   # Etappe 32: 1.2 -> 0.85 (fewer deaths at the first endboss)
const APEX_PHASE_TWO_DAMAGE := 1.1   # Etappe 32: 1.3 -> 1.1
# Etappe 26 (Nutzerentscheidung): jede Migration startet Druck, Flut und Spawn-Direktor
# neu (Weltzeit 0); jede erreichte Welt nach der ersten macht Gegner, Flut und Bosse
# um WORLD_BONUS stärker (HP, Anführer-Treffer, Apex-LP und -Verluste).
const WORLD_BONUS := 0.32   # Etappe 32: 0.25 -> 0.32
# Etappe 27 (S25-Feedback): der Direktor startet in Welt n mit Vorsprung, damit der
# Grunddruck nach einer Migration zur erreichten Welt passt (Weltzeit läuft trotzdem neu).
const WORLD_HUNTER_HEADSTART := 2     # Jäger-Budget +2 je erreichter Welt
const WORLD_HUNTER_CAP := 3           # Jäger-Deckel +3 je Welt (bis HUNTER_CAP_MAX)
const HUNTER_CAP_MAX := 21
const WORLD_SIDE_CAP := 1             # Skitter-/Leaper-Budget und -Deckel +1 je Welt
const SIDE_CAP_MAX := 6
const WORLD_SIDE_DELAY := 15.0        # Skitter/Leaper ab Weltzeit 15 s statt 50/65 s

# Etappe 27 – Hordenwellen: außerhalb der Flut kommt regelmäßig eine angekündigte
# Moorbrut-Welle aus EINER Richtung. Welt 1 ab SURGE_FIRST_SECONDS (Einzelstart
# bleibt fair), spätere Welten ab SURGE_FIRST_LATER; Abstand SURGE_INTERVAL, je
# erreichter Welt SURGE_INTERVAL_WORLD kürzer (min. SURGE_INTERVAL_MIN). Keine Welle
# während Flut-Ankündigung, Flut, Apex-Kampf und Migration.
const SURGE_FIRST_SECONDS := 100.0
const SURGE_FIRST_LATER := 35.0
const SURGE_INTERVAL := 50.0
const SURGE_INTERVAL_WORLD := 7.5   # Etappe 32: 6 -> 7.5
const SURGE_INTERVAL_MIN := 32.0
const SURGE_WARNING_SECONDS := 3.0
const SURGE_MIN_POPULATION := 12      # Welt 1: erst ab so vielen Tieren
# Anzahl = SURGE_COUNT x SURGE_COUNT_GROWTH^Welle x (1 + SURGE_COUNT_WORLD x Welten)
# x sqrt(P / SURGE_POP_REF) (ab SURGE_POP_REF), höchstens SURGE_MAX (und nie über
# FLOOD_MAX_ACTIVE lebende Brut zusammen mit der Flut: S25-Leistung).
const SURGE_COUNT := 14
const SURGE_COUNT_GROWTH := 1.2
const SURGE_COUNT_WORLD := 0.45   # Etappe 32: 0.35 -> 0.45
const SURGE_POP_REF := 40.0
const SURGE_MAX := 70
# Stärke wie Flutstufe k: Biss und Tempo mit k = SURGE_LEVEL_WORLD x Welten +
# SURGE_LEVEL_STEP x Welle (Bissverluste skalieren ohnehin mit P); die LP zusätzlich
# mit SURGE_HP_POP x log2(P/25), damit ein großer Schwarm sie nicht nur streift.
const SURGE_LEVEL_WORLD := 0.65   # Etappe 32: 0.5 -> 0.65
const SURGE_LEVEL_STEP := 0.15
const SURGE_HP_POP := 0.8
const SURGE_LEVEL_MAX := 6.0
const SURGE_DISTANCE := 22.0          # Mitte der Welle vor dem Schwarm (außerhalb des Bildes)
const SURGE_RADIUS := 6.0
const SURGE_APEX_GAP := 25.0         # keine Welle so kurz vor dem fälligen Apex (Brut lebte sonst im Bosskampf)


# Etappe 16 – Beute-Kristalle und Magnet (scripts/loot.gd) ersetzen die Kadaver-Ernte.
# Jeder Tod platzt in 1–LOOT_MAX_PER_KILL Kristalle auf (Biomasse je LOOT_BIO_CHUNK ein
# Kristall, DNA je LOOT_DNA_CHUNK; gedeckelt je Rang), die LOOT_HOP_SECONDS im Bogen
# herausspringen und liegen bleiben, bis der Schwarm sie holt (kein Verfall).
# Liegen in einer Rasterzelle (2,5 m) schon LOOT_CELL_CROWD Kristalle derselben Sorte,
# geht ein landender im größten davon auf (ab LOOT_SOFT_CAP liegenden immer, auch in
# den Nachbarzellen), damit die Karte nicht zuwächst.
const LOOT_BIO_CHUNK := 2.5
const LOOT_DNA_CHUNK := 25.0
const LOOT_MAX_PER_KILL := 6
const LOOT_HOP_SECONDS := [0.3, 0.5]
const LOOT_HOP_HEIGHT := 1.1
const LOOT_CELL_CROWD := 4
const LOOT_SOFT_CAP := 500
# Flood (handtest): bundle from 2 alike per cell, always from 150 lying crystals.
const LOOT_FLOOD_CROWD := 2
const LOOT_FLOOD_SOFT_CAP := 150
# Magnet: Kristalle im Radius um die Schwarmmitte fliegen zu einem Tier (Start mit
# LOOT_FLY_KICK m/s rückwärts, dann LOOT_FLY_ACCEL m/s² bis LOOT_FLY_MAX_SPEED).
# Radius = (MAGNET_BASE + MAGNET_PER_ROOT × √Population) × Witterung (Meta) × Lockduft
# (Anlage) × MAGNET_RALLY bei gehaltener Rally. 1 Tier 3,3 m, 25 Tiere 4,5 m, 100 → 6 m,
# 250 → 7,7 m (Schwarmradius dort ~3,8 m).
const MAGNET_BASE := 3.0
const MAGNET_PER_ROOT := 0.3
const MAGNET_RALLY := 1.35
## Etappe 17b: über 250 Tiere wächst der Radius je Verdopplung nur noch um so viel (m).
const MAGNET_PER_DOUBLING := 0.8
const LOOT_FLY_KICK := 2.5
const LOOT_FLY_ACCEL := 45.0
const LOOT_FLY_MAX_SPEED := 26.0
# Lockruf: garantiert bei Elite-Jäger, Bog King, Apex und zu jeder neuen Flutstufe
# (FLOOD_DOUBLING_SECONDS), sonst LURE_CHANCE je Jäger-/Skitter-/Leaper-Kill, sobald
# mindestens LURE_MIN_LYING Kristalle liegen. Einsammeln: alle Kristalle der Karte
# fliegen als Kette heran (Verzögerung bis LOOT_VACUUM_SPREAD s nach Entfernung,
# Flugzeit höchstens ~LOOT_VACUUM_FLIGHT s).
const LURE_PICKUP_RADIUS := 1.8
const LURE_CHANCE := 0.03
const LURE_MIN_LYING := 30
const LURE_FLOOD_DISTANCE := 9.0
const LOOT_VACUUM_SPREAD := 1.2
const LOOT_VACUUM_FLIGHT := 0.8
# Kadaver sind nur noch Deko (corpse_visuals.gd): sie liegen CORPSE_LIFE Sekunden je
# Rang und versinken in den letzten CORPSE_SINK_SECONDS; höchstens CORPSE_MAX
# gleichzeitig (die ältesten gehen zuerst).
# Nutzer 27.09.2026: „zu viel liegt herum“ -> deutlich kürzer, weniger gleichzeitig.
const CORPSE_LIFE := {"normal": 8.0, "mini": 14.0, "boss": 30.0, "special": 8.0}
const CORPSE_HORDE_LIFE := 4.0
const CORPSE_SINK_SECONDS := 1.5
const CORPSE_MAX := 20

# Etappe 17 Welle 2 - Bernstein (In-Run-Währung, nur für Kokons; verfällt am Run-Ende).
# Jede Tötung wirft Bernstein-Münzen nach Art ab (AMBER_CHUNK Bernstein je Münze,
# gedeckelt je Rang), Bernsteinknollen je Stufe AMBER_NODE (dazu DNA, keine
# Biomasse). Biomasse (nur aus Kills) lässt den Schwarm wachsen, DNA gibt Erfahrung.
const AMBER_CHUNK := 5.0
const AMBER_KILL := {"prey": 1, "hunter": 2, "skitter": 1, "leaper": 2, "elite": 12, "boss": 25, "apex": 40, "apex_toad": 40, "apex_sandworm": 40, "horde": 0}
## Moorbrut-Bündel: je getöteter Moorbrut so viel Bernstein (abgerundet je Bündel).
const AMBER_HORDE := 0.25
const AMBER_NODE := [3, 6, 12]
## Bernstein-Schatz in den Hain-Plätzen (poi_slots("grove")): je Knolle.
const AMBER_GROVE := 6

# Etappe 19 Phase 2 - Dürrschlund (Wüste). Eigener Block, nur Wüstenwerte.
# Sandwurm (scripts/apex_sandworm.gd): Etappe 20 im Run gemessen
# (tests/apex_duration.gd, ausweichender Bot, Mindestpopulation, Build wie nach
# ~3 min): 1.075 LP ergeben 33 s auf Brutal und 26 s auf Apex (Ziel 25–35 s).
const APEX_SANDWORM_HEALTH := 2200.0   # Etappe 26: 1075 -> 2200 (Kampf 45-70 s)
const APEX_SANDWORM_MIN_POPULATION := 35
const APEX_SANDWORM_BIOMASS := 75.0
const APEX_SANDWORM_DNA := 130
const APEX_SANDWORM_ALPHA_CORES := 2
# Sandmaden (scripts/sandgrub.gd): aus dem Wurm (Phase 2, Durchbruch) und als
# kleiner, seltener Hinterhalt in der Wüste (ab SANDGRUB_FIRST_SECONDS, dann alle
# SANDGRUB_AMBUSH_SECONDS / sqrt(Druck), höchstens SANDGRUB_AMBUSH_MAX Tiere je Gruppe).
const SANDGRUB_HP := 8.0
const SANDGRUB_SPEED := 5.6
const SANDGRUB_BITE := 1.0
const SANDGRUB_BITE_COOLDOWN := 0.9
const SANDGRUB_BIOMASS := 0.6
const SANDGRUB_DNA := 1
const SANDGRUB_FIRST_SECONDS := 50.0
const SANDGRUB_AMBUSH_SECONDS := 38.0
const SANDGRUB_AMBUSH_MIN := 3
const SANDGRUB_AMBUSH_MAX := 6
const SANDGRUB_AMBUSH_DISTANCE := 9.0
const SANDGRUB_MIN_POPULATION := 8
# Maden-LP und -Biss wachsen mit dem Druck (wie die Moorbrut, aber gedämpft).
const SANDGRUB_PRESSURE_EXPONENT := 0.5
# Treibsand: bremst alles, was ihn durchquert (Schwarm und Gegner), nie tödlich.
const QUICKSAND_SLOW := 0.5
const QUICKSAND_RIM := 1.2
# Sandsturm: kurze Wellen, angekündigt, heller Schleier nur am Bildrand;
# Gegner in der Zeit etwas schneller.
const SANDSTORM_FIRST_SECONDS := 45.0
const SANDSTORM_INTERVAL := Vector2(60.0, 90.0)
const SANDSTORM_WARNING := 4.0
const SANDSTORM_SECONDS := 12.0
const SANDSTORM_FADE := 2.0
const SANDSTORM_ENEMY_HASTE := 1.18
# Etappe 29: Seen und Moore mit Flachufer. Das Uferband (SHALLOW_WIDTH m auf der
# Wasserseite) ist begehbar und bremst alle Figuren auf SHALLOW_SLOW (über
# SHALLOW_RIM m eingeblendet); die tiefe Mitte blockiert wie eine Wand.
const SHALLOW_SLOW := 0.6
const SHALLOW_WIDTH := 2.5
const SHALLOW_RIM := 0.8

# Etappe 30: das versiegelte Tor steht so weit (m) neben der Boss-Arena der Welt.
const GATE_OFFSET := 13.0
# Etappe 30 (Nutzerwunsch): Endboss-LP mindestens dieses Vielfache der LP eines Bog King zum selben
# Zeitpunkt (Bog King wächst mit sqrt(Druck)); Kampf damit ~3x so lang wie der Bog King (15-30 s -> 45-90 s).
const APEX_KING_RATIO := 3.0

# Etappe 31 D: Glutpilze (scripts/map_items.gd). Leuchtende Pilzkörbe ohne Kollision,
# MAP_ITEM_COUNT je 4 x 4-Karte (größere Karten anteilig mehr); ein Biss bricht sie,
# mit MAP_ITEM_CHANCE erscheint ein Sofort-Item (Gewichte), sonst ein paar Münzen.
const MAP_ITEM_COUNT := Vector2i(8, 12)
const MAP_ITEM_CHANCE := 0.6
const MAP_ITEM_WEIGHTS := {"heilpilz": 1.0, "zeitstarre": 0.8, "bildschirmbiss": 0.8, "lockruf": 0.7}
const MAP_ITEM_EMPTY_AMBER := 4
# Heilpilz: Anteil der max. Anführer-LP.
const MAP_ITEM_HEAL := 0.3
# Zeitstarre: Sekunden, in denen alle Gegner, Bosse und die Brut stillstehen.
const MAP_ITEM_FREEZE := 5.0
# Bildschirm-Biss: Radius (m, etwa das sichtbare Bild) und Boss-Anteil der max. LP.
const MAP_ITEM_BITE_RADIUS := 18.0
const MAP_ITEM_BITE_BOSS := 0.1
# Platzierung: Mindestabstand zueinander (m, 4 x 4-Karte), zum Start, freie Fläche.
const MAP_ITEM_SPACING := 30.0
const MAP_ITEM_START_GAP := 16.0
const MAP_ITEM_CLEARANCE := 2.2
# Darstellung: Korbgröße (x ~1,6 m Breite) und Item-Symbol.
const MAP_ITEM_SIZE := 1.25
const MAP_ITEM_ICON_SIZE := 1.5

# Etappe 33: Mutationskerne (scripts/progression/cores.gd). Die Wirkungen stehen im
# Katalog; hier nur die Hooks in HuntWorld/AttackForms.
# Giftblut: Grundchance je Treffer (plus Krit-Chance), dass ein Treffer als Kritbiss
# eine Giftwolke hinterlässt (ohne Grundchance wäre der Kern ohne Kritbiss wirkungslos).
const CORE_POISON_BASE_CHANCE := 0.08
# Höchstens eine Wolke je so viele Sekunden (Waffen-Treffer bzw. Nahkampf-Takt).
const CORE_POISON_COOLDOWN := 0.4
const CORE_POISON_MELEE_SECONDS := 0.5
# Giftwolke: Schaden je Sekunde (× Druck-Skala der Waffen), Radius (m), Dauer steht in PUFF_SECONDS (2 s).
const CORE_POISON_DPS := 10.0
const CORE_POISON_RADIUS := 1.8
# Flutfresser: die Flut beginnt höchstens so früh (Weltzeit in s).
const CORE_FLOOD_MIN_START := 30.0
