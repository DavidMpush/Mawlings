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
const PRESSURE_DOUBLING_SECONDS := 90.0
const FIRST_HUNTER_SECONDS := 18.0
const HUNTER_HEALTH := 22.0
const HUNTER_DAMAGE := 6.0
const HUNTER_SPEED := 2.4
const HUNTER_WARNING_SECONDS := 1.25
const HUNTER_RECOVERY_SECONDS := 1.7
const HUNTER_ATTACK_RADIUS := 2.3
const HUNTER_BIOMASS := 26.0
const MAX_HUNTERS := 12
const MAX_PREY := 5
const PREY_RESPAWN_SECONDS := 9.0
const CORPSE_BIOMASS := 12.0
const HARVEST_RATE := 4.0
const HARVEST_RADIUS := 1.55

const FIRST_SKITTER_SECONDS := 45.0
const SKITTER_HEALTH := 15.0
const SKITTER_DAMAGE := 4.0
const SKITTER_SPEED := 3.2
const SKITTER_WARNING_SECONDS := 1.0
const SKITTER_DASH_SECONDS := 0.4
const SKITTER_RECOVERY_SECONDS := 2.0
const SKITTER_RANGE := 7.0
const SKITTER_WIDTH := 1.15
const SKITTER_BIOMASS := 18.0
const MAX_SKITTERS := 3

const FIRST_BOSS_SECONDS := 90.0
const BOSS_RESPAWN_SECONDS := 180.0
const BOSS_HEALTH := 230.0
const BOSS_SPEED := 1.6
const BOSS_WARNING_SECONDS := 1.8
const BOSS_RECOVERY_SECONDS := 2.5
const BOSS_ATTACK_RADIUS := 3.6
const BOSS_DAMAGE := 12.0
const BOSS_BIOMASS := 110.0

# Mire Leaper: ambush jumper that lands on a locked, announced zone.
const FIRST_LEAPER_SECONDS := 60.0
const LEAPER_HEALTH := 18.0
const LEAPER_DAMAGE := 4.0
const LEAPER_SPEED := 2.2
const LEAPER_RANGE := 9.0
const LEAPER_ZONE_RADIUS := 2.6
const LEAPER_LURK_SECONDS := 2.5
const LEAPER_WARNING_SECONDS := 1.1
const LEAPER_FLIGHT_SECONDS := 0.55
const LEAPER_EXHAUST_SECONDS := 2.0
const LEAPER_RETREAT_SECONDS := 0.7
const LEAPER_RETREAT_DISTANCE := 5.0
const LEAPER_BIOMASS := 20.0
const LEAPER_DNA := 15
const MAX_LEAPERS := 3

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
const NEST_BIOMASS := 44.0          # erstes Nest; jedes weitere + NEST_BIOMASS_GROWTH
const NEST_BIOMASS_GROWTH := 12.0
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
const ELITE_BIOMASS := 44.0
const ELITE_DNA := 40
