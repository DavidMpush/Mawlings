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
const PRESSURE_DOUBLING_SECONDS := 80.0
# Gegner-HP/-Schaden der Schwierigkeit wachsen in den ersten so vielen Sekunden von x1 auf
# den vollen Wert (Etappe 08: sonst löscht der erste Jäger auf Brutal/Apex den Startschwarm).
const DIFFICULTY_RAMP_SECONDS := 75.0
const FIRST_HUNTER_SECONDS := 14.0
const HUNTER_HEALTH := 26.0
const HUNTER_DAMAGE := 8.0
const HUNTER_SPEED := 2.4
const HUNTER_WARNING_SECONDS := 1.25
const HUNTER_RECOVERY_SECONDS := 1.1      # Etappe 08: 1,7 -> 1,1 (alle greifen an)
const HUNTER_ARRIVE_SECONDS := 0.5
const HUNTER_ATTACK_RADIUS := 2.3
const HUNTER_BIOMASS := 8.0
const MAX_HUNTERS := 12
# Spawn-Direktor (Etappe 08 als Konstanten): Budget = BASE + Zeit / BUDGET_SECONDS,
# Abstand = max(MIN, SPAWN_SECONDS / sqrt(Druck)).
const HUNTER_BUDGET_BASE := 1
const HUNTER_BUDGET_SECONDS := 25.0
const HUNTER_SPAWN_SECONDS := 9.0
const HUNTER_SPAWN_MIN := 2.2
const MAX_PREY := 5
const PREY_RESPAWN_SECONDS := 9.0
const CORPSE_BIOMASS := 6.0
const HARVEST_RATE := 4.0
const HARVEST_RADIUS := 1.55

const FIRST_SKITTER_SECONDS := 35.0
const SKITTER_HEALTH := 15.0
const SKITTER_DAMAGE := 4.0
const SKITTER_SPEED := 3.2
const SKITTER_WARNING_SECONDS := 1.0
const SKITTER_DASH_SECONDS := 0.4
const SKITTER_RECOVERY_SECONDS := 1.3     # Etappe 08: 2,0 -> 1,3
const SKITTER_ARRIVE_SECONDS := 0.4
const SKITTER_RANGE := 7.0
const SKITTER_WIDTH := 1.15
const SKITTER_BIOMASS := 9.0
const MAX_SKITTERS := 3
const SKITTER_BUDGET_SECONDS := 90.0
const SKITTER_SPAWN_SECONDS := 26.0
const SKITTER_SPAWN_MIN := 6.0

const FIRST_BOSS_SECONDS := 90.0
const BOSS_RESPAWN_SECONDS := 180.0
const BOSS_HEALTH := 230.0
const BOSS_SPEED := 1.6
const BOSS_WARNING_SECONDS := 1.8
const BOSS_RECOVERY_SECONDS := 2.5
const BOSS_ATTACK_RADIUS := 3.6
const BOSS_DAMAGE := 14.0
const BOSS_BIOMASS := 60.0

# Mire Leaper: ambush jumper that lands on a locked, announced zone.
const FIRST_LEAPER_SECONDS := 50.0
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
const LEAPER_RETREAT_SECONDS := 0.7
const LEAPER_RETREAT_DISTANCE := 5.0
const LEAPER_BIOMASS := 10.0
const LEAPER_DNA := 15
const MAX_LEAPERS := 3
const LEAPER_BUDGET_SECONDS := 80.0
const LEAPER_SPAWN_SECONDS := 28.0
const LEAPER_SPAWN_MIN := 7.0

# Run-Ziele (Etappe 06). Brutnest: Kreiszone, die der Schwarm durch Anwesenheit
# füllt; bei voll bleibt ein Gelege als normale Kadaver-Biomasse liegen.
# Füllrate/s = Anteil der Tiere in der Zone / NEST_FILL_SECONDS x Populationsfaktor
# (1,0 bei 25 Tieren, +1 je NEST_POPULATION_STEP weitere Tiere, max. NEST_MAX_SPEED).
const NEST_FIRST_SECONDS := 20.0
const NEST_RESPAWN_SECONDS := 30.0
const NEST_RADIUS := 4.0
const NEST_FILL_SECONDS := 8.0
const NEST_POPULATION_STEP := 125.0
const NEST_MAX_SPEED := 2.6
const NEST_BIOMASS := 18.0          # erstes Nest; jedes weitere + NEST_BIOMASS_GROWTH
const NEST_BIOMASS_GROWTH := 5.0
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
const FLOOD_DOUBLING_SECONDS := 40.0
const FLOOD_WAVE_SECONDS := 3.0
const FLOOD_WAVE_COUNT := 8          # Brut pro Welle bei Stufe 0; x 2^k bis FLOOD_WAVE_MAX
const FLOOD_WAVE_MAX := 40
const FLOOD_MAX_ACTIVE := 160         # gleichzeitig lebende Brut (Leistungsdeckel)
const FLOOD_HP := 1.2
const FLOOD_BITE := 0.4               # Biss-Multiplikator: Verlust je gebissenem sichtbarem Tier x 2^k
const FLOOD_BITE_COOLDOWN := 0.8
const FLOOD_SPEED := 3.4
const FLOOD_SPEED_CAP := 6.0
const FLOOD_SPEED_SHARE := 0.82       # nie schneller als 82 % des Schwarmtempos
const FLOOD_RING_RADIUS := 23.0       # außerhalb des Hochformat-Bildes
const FLOOD_RING_SHIFT := 7.0         # Ringmitte nach "oben" (-Z): oben sieht die Kamera weiter
const FLOOD_BUNDLE_SECONDS := 1.0     # Brut-Kadaver werden so lange je Zelle gesammelt
const FLOOD_BUNDLE_CELL := 3.0
const FLOOD_KILL_BIOMASS := 1.5       # Fallback, falls die Horde keine Biomasse meldet
const FLOOD_KILL_DNA := 1

# Nibbler wehren sich (Etappe 08): gebissen oder umzingelt schnappen sie nach einer
# Warnung in einen kleinen Kreis; nur Tiere darin fallen (Treffer pro Tier).
const NIBBLER_SNAP_RADIUS := 1.2
const NIBBLER_SNAP_WARNING := 0.6
const NIBBLER_SNAP_COOLDOWN := 3.0
const NIBBLER_SNAP_RANGE := 2.2       # Schwarm so nah = umzingelt
const NIBBLER_SNAP_REACH := 0.5       # Kreismitte so weit vor dem Nibbler (Richtung Schwarm)
const NIBBLER_SNAP_DAMAGE := 1.5      # Basisverlust bei vollem Treffer; x Druck^0,6
const NIBBLER_PROVOKED_SECONDS := 1.5

# Etappe 08: Erholung/Lauern schrumpfen mit dem Druck (Faktor 1 / (1 + CUT x log2 Druck)),
# nie unter `minimum` – bei hohem Druck greifen alle Gegner fast pausenlos an.
const RECOVERY_PRESSURE_CUT := 0.2


static func recovery(base: float, pressure: float, minimum: float) -> float:
	return maxf(minimum, base / (1.0 + RECOVERY_PRESSURE_CUT * log(maxf(1.0, pressure)) / log(2.0)))
