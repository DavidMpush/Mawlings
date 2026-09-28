extends Node3D

const EVOLUTION = preload("res://scripts/evolution.gd")
const RUN_MODEL = preload("res://scripts/run_model.gd")
const PREY = preload("res://scripts/prey.gd")
const HUNTER = preload("res://scripts/hunter.gd")
const SKITTER = preload("res://scripts/skitter.gd")
const BOG_KING = preload("res://scripts/bog_king.gd")
const MIRE_LEAPER = preload("res://scripts/mire_leaper.gd")
const TUNING = preload("res://scripts/tuning.gd")
const META_DATA = preload("res://scripts/meta/meta_data.gd")
const FX = preload("res://scripts/fx.gd")
const FX_BATCH = preload("res://scripts/fx_batch.gd")
const QUALITY = preload("res://scripts/quality.gd")
const CORPSE_VISUALS = preload("res://scripts/corpse_visuals.gd")
const LOOT = preload("res://scripts/loot.gd")
const LOOT_NODES = preload("res://scripts/loot_nodes.gd")
# Etappe 17 Welle 2: Kokons, Power-ups und Schreine (je ein Knoten unter HuntWorld).
const CHESTS = preload("res://scripts/chests.gd")
const POWERUPS = preload("res://scripts/powerups.gd")
const SHRINES = preload("res://scripts/shrines.gd")
const HUD_LOOT_PATH := "res://scripts/ui/hud_loot.gd"
const ERUPTIONS = preload("res://scripts/eruptions.gd")
const APEX_BOSS = preload("res://scripts/apex_boss.gd")
const APEX_TOAD = preload("res://scripts/apex_toad.gd")
# Etappe 19: Sandwurm (Dürrschlund-Apex) und der Wüstenteil des Runs (Sandmaden, Sandsturm).
const APEX_SANDWORM = preload("res://scripts/apex_sandworm.gd")
const DESERT_RUN = preload("res://scripts/desert_run.gd")
const MIGRATION_MAW = preload("res://scripts/migration_maw.gd")
const BIOMES = preload("res://scripts/biomes.gd")
const BROOD_NEST = preload("res://scripts/objectives/brood_nest.gd")
const CURSE_TOTEM = preload("res://scripts/objectives/curse_totem.gd")
const ALPHA_CORE_VISUAL = preload("res://scripts/objectives/alpha_core_visual.gd")
const HUD_OBJECTIVES_PATH := "res://scripts/ui/hud_objectives.gd"
const NEST_COLOR := Color("3fe6d8")
const CURSE_COLOR := Color("ff4a8a")
const CORPSE_BIOMASS := TUNING.CORPSE_BIOMASS
# Etappe 16: DNA per kill kind (now dropped as crystals).
const KILL_DNA := {"prey": 10, "hunter": 20, "skitter": 15, "leaper": TUNING.LEAPER_DNA, "boss": 50, "apex": TUNING.APEX_DNA}
# Loot spread / remains life by rank.
const KIND_RANK := {"prey": "normal", "hunter": "normal", "skitter": "normal", "horde": "normal", "elite": "mini", "leaper": "mini", "boss": "boss", "apex": "boss", "apex_toad": "boss", "apex_sandworm": "boss", "nest": "boss", "mawling": "special"}
# Written by parallel modules; loaded at runtime so a missing file never breaks a run.
const ATTACK_FORMS_PATH := "res://scripts/attack_forms.gd"
const SESSION_PATH := "res://scripts/meta/session.gd"
const ALPHA_AMBER := Color("ffb347")
const ALPHA_VIOLET := Color("a86bff")
const ALPHA_PICKUP_RADIUS := 1.7
# Melee per animal: an animal bites when it stands within MELEE_REACH of the
# target's body edge. Damage = full swarm damage x clamp(share / FULL_SHARE, 0, 1),
# share = biting animals / visible animals. A target inside the swarm (centre
# within the old contact range) always takes at least MIN_ENGAGE.
const MELEE_REACH := 1.2
const MELEE_FULL_SHARE := 0.6
const MELEE_MIN_ENGAGE := 0.5
const BODY_RADIUS := {"prey": 0.45, "hunter": 0.72, "elite": 1.05, "skitter": 0.55, "leaper": 0.7, "boss": 2.3, "apex": TUNING.APEX_BODY_RADIUS, "apex_toad": APEX_TOAD.BODY_RADIUS, "apex_sandworm": APEX_SANDWORM.BODY_RADIUS}
const POPUP_SECONDS := 0.9
const POPUP_MAX := 3
# Etappe 16 (S5): collected crystals add up into ONE growing number at the swarm
# while they keep arriving within POPUP_MERGE_SECONDS.
const POPUP_MERGE_SECONDS := 0.45
# Collect sound chain: semitone steps (pentatonic) while crystals keep arriving
# within COLLECT_CHAIN_SECONDS; at most one collect sound per COLLECT_SOUND_MS.
const COLLECT_STEPS := [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24]
const COLLECT_CHAIN_SECONDS := 0.45
const COLLECT_SOUND_MS := 70
# Die Flut (stage 08): the Moorbrut horde is written by a parallel module and
# loaded at runtime; without it the flood still announces and counts, but spawns nothing.
const HORDE_PATH := "res://scripts/horde.gd"
const HUD_FLOOD_PATH := "res://scripts/ui/hud_flood.gd"
const META_DATA_PATH := "res://scripts/meta/meta_data.gd"

@onready var swarm = get_parent().get_node("Swarm")
@onready var hud = get_parent().get_node("HUD/Controls")
var evolution = EVOLUTION.new()
var model = RUN_MODEL.new()
# RunConfig from the menu; empty keeps the unconfigured prototype defaults.
var config: Dictionary = {}
var enemy_hp := 1.0
var enemy_damage := 1.0
var attack_forms: Node3D
# Alpha-Kern pickups stay on the ground until touched (resource rule).
var alpha_pickups: Array[Node3D] = []
var drop_rng := RandomNumberGenerator.new()
var result_stored := false
var evolve_flash := 0.0
var evolve_name := ""
var alpha_clock := 0.0
# Audio bookkeeping only: last seen enemy state per instance, melee bite cadence.
var enemy_states: Dictionary = {}
var bite_clock := 0.0
var melee_contact := false
var prey: Array[Node3D] = []
var hunters: Array[Node3D] = []
var skitters: Array[Node3D] = []
var leapers: Array[Node3D] = []
var boss: Node3D
# Corpse display (Etappe 09): one design per animal and rank, batched per design
# (scripts/corpse_visuals.gd). Etappe 16: empty decoration that sinks after
# TUNING.CORPSE_LIFE; the biomass lies in the loot crystals (scripts/loot.gd).
var corpse_view: Node3D
var loot: Node3D
# Stage 18c: breakable amber nodes of the exploration map (scripts/loot_nodes.gd).
var loot_nodes: Node3D
var chests: Node3D
var powerups: Node3D
var shrines: Node3D
## True once this biome cycle's Bog King left its golden boss cocoon.
var king_cocoon_taken := false
# Remains bookkeeping: id -> {"age", "life"}; remains_order oldest first.
var remains := {}
var remains_order: Array[int] = []
var next_remains_id := 1
# Etappe 16 statistics and feel state.
var crystals_collected := 0
var lures_collected := 0
var flood_lure_stage := 0
var collect_chain := 0
var collect_chain_at := -INF
var collect_sound_ms := 0
var lure_flash := 0.0
# Seconds the collect hint stays after the last arrival (no flicker between frames).
var collect_hint := 0.0
var _map_loot_count := -1
# Glutsumpf lava eruptions (scripts/eruptions.gd); quiet in other biomes.
var eruptions: Node3D
# Shared look of the Alpha-Kern and the curse aura (built once).
static var _alpha_parts := {}
var spawn_clock := 0.0
var hunter_clock := TUNING.FIRST_HUNTER_SECONDS
var skitter_clock := TUNING.FIRST_SKITTER_SECONDS
var leaper_clock := TUNING.FIRST_LEAPER_SECONDS
var boss_clock := TUNING.FIRST_BOSS_SECONDS
var spawn_number := 0
var paused := false
var hit_feedback := 0.0
var last_loss := 0
# Visual-only: where the swarm leans in (attack target or corpse being eaten).
var focus_point := Vector3.ZERO
var focus_mode := 0
var focus_distance := INF
# Visible unit world positions, rebuilt lazily once per step and after each hit.
var unit_points := PackedVector3Array()
var unit_points_valid := false
# Floating rewards: {"at": Vector3, "dna": int, "biomass": int, "age": float,
# "sum": float, "last": float}. Etappe 16: one growing number at the swarm per
# collection burst (see _add_collect_popup).
var kill_popups: Array[Dictionary] = []
# Flood DNA waiting for a whole crystal (flush_flood_bundles).
var flood_dna_pending := 0
var flood_amber_pending := 0.0
# Counts Bog King kills this run; HUD and Main react to changes (Königsmoment).
var king_moments := 0
var last_hit_share := 1.0
# Run-Ziele (stage 06): one Brutnest at a time, an optional Fluch-Totem before a
# boss, elite hunters on a timer. Placement uses objective_rng seeded from the
# run seed, so a seed always yields the same first nest.
var nest: Node3D
var totem: Node3D
var objective_rng := RandomNumberGenerator.new()
# Stage 18b: last clearing slot used per objective kind (the next one moves on).
var _last_objective: Dictionary = {}
var nest_clock := TUNING.NEST_FIRST_SECONDS
var elite_clock := TUNING.ELITE_FIRST_SECONDS
# True once this boss cycle had its totem roll; boss_cycles counts boss spawns.
var totem_offered := false
var boss_cycles := 0
# 0 = no curse, 1 = accepted and waiting for the next boss, 2 = cursed boss alive.
var curse_state := 0
var nests_completed := 0
var totems_taken := 0
# Die Flut: 0 = not yet, 1 = announced (countdown), 2 = running. flood_start comes
# from the difficulty (meta_data.DIFFICULTIES[n].flood_start; Wild without config).
var horde: Node3D
var flood_start := TUNING.FLOOD_START_SECONDS
var flood_state := 0
var flood_wave_clock := 0.0
var flood_reached := false
var horde_kills := 0
var flood_waves := 0
var flood_beep := -1
# Horde kills waiting to burst into crystals per cell: key -> {sum, n, biomass, dna}.
var flood_bundles: Dictionary = {}
var flood_bundle_clock := 0.0
# Soft, rate-limited swarm flash for horde bites (see _flood_bites).
const HORDE_FLASH := 0.5
const HORDE_FLASH_SECONDS := 0.6
var horde_flash_at := 0.0
# Etappe 09 - Anfuehrer: HUD/feel state (rules live in RunModel.apply_hit()).
const MILESTONE_SHOW_SECONDS := 2.5
var last_loss_fraction := 0.0
# Audio: one "threat" per pressure doubling (see _audio_threat).
var threat_doublings := 0
var milestone_value := 0
var milestone_timer := 0.0
var leader_state_key := Vector3i(-1, -1, -1)
# The first hunter waits for FIRST_HUNTER_POPULATION or FIRST_HUNTER_LATEST.
var hunters_unlocked := false
var hunters_unlocked_at := 0.0
# Shared gap after a Nibbler snap (only one snap circle at a time).
var snap_gap := 0.0
# Corpse kind per corpse id (prey, hunter, elite, skitter, leaper, boss, horde,
# mawling, nest) for scripts/corpse_visuals.gd; entries leave with the corpse.
var corpse_kinds: Dictionary = {}
# Etappe 10 - Apex and migration. apex_state: 0 waiting, 1 ground warning
# (announced, nothing hits), 2 alive, 3 defeated (Migrationsschlund open or
# opening), 4 disabled (balance bot / tests). One apex per biome visit: the
# start biome's apex comes on the difficulty schedule, after every migration
# the new biome's apex comes APEX_ARRIVAL_DELAY s after the arrival (state
# back to 0). Verdant Maw = Moosschlund, Glutsumpf = Aschenkröte.
var apex: Node3D
var apex_state := 0
# Run time the next apex is due (< 0 = difficulty schedule of the start biome).
var apex_due := -1.0
# Apexes spawned this run; apex_loop() = completed loops through the biome
# circle (strength step on a return).
var apex_spawned := 0
# Kind of the apex that rises / lives / fell last ("apex" or "apex_toad").
var apex_kind := "apex"
var toad_kills := 0
var worm_kills := 0
## Etappe 19: Wüstenteil des Runs (scripts/desert_run.gd), neben der Horde erzeugt.
var desert: Node3D
var apex_clock := 0.0
var apex_spot := Vector3.ZERO
var apex_pulse := 0.0
var apex_kills := 0
# Victory banner counter for hud_objectives (like king_moments for the Bog King).
var apex_victories := 0
# The defeated body sinks for APEX_SINK_SECONDS before it is freed.
var apex_dying: Node3D
var apex_dying_clock := 0.0
var portal: Node3D
var portal_clock := -1.0
var portal_point := Vector3.ZERO
# 0 none, 1 transition running (the world holds still), 2 done.
var migration_state := 0
var migration_timer := 0.0
var migration_switched := false
var migration_to := ""
var migrations := 0
# Active biome (scripts/biomes.gd) and the run's biome record.
var biome_id: String = BIOMES.DEFAULT
var biomes_visited: Array[String] = []
var biome_seconds: Dictionary = {}
var arrivals := 0
# Minimap stage: exploration (chunks the swarm had within EXPLORE_RADIUS, with
# the biome they were last seen in), named regions and the HUD map data
# (published at MAP_HZ as the HUD meta "map"; centre/heading every frame).
const EXPLORE_RADIUS := 24.0
const MAP_HZ := 12.0
const MAP_CELL := 28.0
var explored: Dictionary = {}
var explored_version := 0
var regions_seen: Dictionary = {}
var region_key := Vector2i.ZERO
var region_name := ""
var region_phrase := ""
var region_entries := 0
var _region_tag := Vector3i(1 << 30, 0, 0)
var _explore_at := Vector3.INF
var _explore_biome := ""
var _map_clock := 0.0
var _map_heading := Vector2(0.0, -1.0)
var _map_corpses := PackedFloat32Array()
var _map_corpse_count := -1
var _map_corpse_clock := 0.0


func _ready() -> void:
	drop_rng.randomize()
	_seed_objectives()
	_ensure_objective_hud()
	_ensure_flood_hud()
	_ensure_loot_hud()
	# Etappe 17: also the config-less first run (F5, tests) gets its start weapon.
	_configure_run()
	_create_attack_forms()
	_create_horde()
	_create_world_views()
	_reset_flood()
	_reset_apex()
	_set_world_biome(_start_biome(), false)
	_starting_prey()
	_reset_map()
	_update_hud("")


# Stores a RunConfig and restarts the run with it.
func apply_config(value: Dictionary) -> void:
	config = value.duplicate(true)
	if swarm.has_method("apply_config"):
		swarm.apply_config(config)
	reset_run()


func _starting_prey() -> void:
	# Stage 18c: around the start (random on the exploration map), on open ground.
	var home := Vector3(swarm.position.x, 0.0, swarm.position.z)
	var arena: Node = get_parent().get_node_or_null("Arena") if get_parent() != null else null
	for offset in [Vector3(-3.0, 0.0, -4.0), Vector3(4.0, 0.0, -2.0), Vector3(-2.0, 0.0, 5.0)]:
		var spot: Vector3 = home + offset
		if arena != null and arena.has_method("safe_spawn"):
			spot = arena.safe_spawn(spot, 0.6)
		_spawn_prey(spot)


func reset_run() -> void:
	if attack_forms != null and attack_forms.has_method("clear"):
		attack_forms.clear()
	if horde != null and is_instance_valid(horde) and horde.has_method("clear"):
		horde.clear()
	horde = null
	_portal_hum(false)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	prey.clear()
	hunters.clear()
	skitters.clear()
	leapers.clear()
	alpha_pickups.clear()
	enemy_states.clear()
	boss = null
	corpse_view = null
	loot = null
	loot_nodes = null
	chests = null
	powerups = null
	shrines = null
	king_cocoon_taken = false
	eruptions = null
	corpse_kinds.clear()
	remains.clear()
	remains_order.clear()
	crystals_collected = 0
	lures_collected = 0
	collect_chain = 0
	collect_chain_at = -INF
	lure_flash = 0.0
	_reset_apex()
	evolution = EVOLUTION.new()
	model = RUN_MODEL.new()
	_configure_run()
	_seed_objectives()
	spawn_clock = 0.0
	hunter_clock = TUNING.FIRST_HUNTER_SECONDS
	skitter_clock = TUNING.FIRST_SKITTER_SECONDS
	leaper_clock = TUNING.FIRST_LEAPER_SECONDS
	boss_clock = TUNING.FIRST_BOSS_SECONDS
	spawn_number = 0
	paused = false
	hit_feedback = 0.0
	last_loss = 0
	last_loss_fraction = 0.0
	threat_doublings = 0
	milestone_value = 0
	milestone_timer = 0.0
	leader_state_key = Vector3i(-1, -1, -1)
	hunters_unlocked = false
	hunters_unlocked_at = 0.0
	snap_gap = 0.0
	kill_popups.clear()
	flood_dna_pending = 0
	flood_amber_pending = 0.0
	melee_dealt = 0.0
	_forms_dealt_seen = 0.0
	_heal_pool = 0.0
	leader_heal_shown = 0
	leader_heal_at = -INF
	unit_points_valid = false
	result_stored = false
	evolve_flash = 0.0
	evolve_name = ""
	swarm.position = _start_point()
	swarm.set_population(model.population, false)
	_sync_leader()
	swarm.clear_focus()
	swarm.set_controls(Vector2.ZERO, false)
	hud.clear_pointers()
	_create_attack_forms()
	_create_horde()
	_create_world_views()
	_reset_flood()
	# Stage 10: a migrated run starts again in its configured biome.
	_set_world_biome(_start_biome(), false)
	_starting_prey()
	_reset_map()
	_update_hud("")


func _configure_run() -> void:
	enemy_hp = 1.0
	enemy_damage = 1.0
	flood_start = _difficulty_flood_start()
	if config.is_empty():
		# Etappe 17: Waffen gibt es nur noch als Startwaffe und über Kokons. Ohne
		# RunConfig (F5, Tests) trägt der Schwarm deshalb die Startwaffe des
		# Standardstamms, wie jeder Run aus dem Menü (vorher kam sie per Level).
		evolution.configure({"signature_attack": String(META_DATA.STRAINS[META_DATA.STRAIN_ORDER[0]].signature)})
		return
	model.configure(int(config.get("start_population", model.population)), float(config.get("pressure_doubling", TUNING.PRESSURE_DOUBLING_SECONDS)), int(config.get("leader_hp", TUNING.LEADER_HP)))
	evolution.configure(config)
	enemy_hp = maxf(0.1, float(config.get("enemy_hp", 1.0)))
	enemy_damage = maxf(0.1, float(config.get("enemy_damage", 1.0)))


func _create_attack_forms() -> void:
	attack_forms = null
	if not ResourceLoader.exists(ATTACK_FORMS_PATH):
		return
	var script: Script = load(ATTACK_FORMS_PATH)
	if script == null or not script.can_instantiate():
		return
	attack_forms = script.new()
	attack_forms.name = "AttackForms"
	add_child(attack_forms)
	if attack_forms.has_method("setup"):
		attack_forms.setup(self, swarm)
	_sync_attack_forms()


# Etappe 17: Werte und Arsenal -> Waffen-Ränge, Waffen-Modifikatoren und die
# Anführer-LP-Zulage (Anführerherz/Blutmond). Läuft erneut, sobald
# evolution.revision steigt (Level-Wahl, Kokon, debug_grant).
var progression_revision := -1
var progression_hp := 0
var _progression_model: RefCounted = null


func _sync_attack_forms() -> void:
	progression_revision = evolution.revision
	if attack_forms != null and attack_forms.has_method("set_ranks"):
		attack_forms.set_ranks(evolution.attack_ranks())
		if attack_forms.has_method("set_modifiers"):
			attack_forms.set_modifiers(evolution.form_modifiers())
	if _progression_model != model:
		_progression_model = model
		progression_hp = 0
	var bonus: int = evolution.leader_hp_bonus(int(config.get("leader_hp", TUNING.LEADER_HP)))
	if bonus != progression_hp and not model.extinct:
		var change := bonus - progression_hp
		progression_hp = bonus
		model.leader_max_hp = maxi(1, model.leader_max_hp + change)
		model.leader_hp = clampi(model.leader_hp + maxi(0, change), 1, model.leader_max_hp)
		_sync_leader()


# ---------------------------------------------------------------- Die Flut

# Adds the Moorbrut horde (scripts/horde.gd, contract in stages/08) when present.
func _create_horde() -> void:
	horde = null
	if not ResourceLoader.exists(HORDE_PATH):
		return
	var script: Script = load(HORDE_PATH)
	if script == null or not script.can_instantiate():
		return
	horde = script.new()
	horde.name = "Horde"
	add_child(horde)
	if horde.has_method("setup"):
		horde.setup(self, swarm, get_parent().get_node_or_null("Arena"))
	if attack_forms != null and attack_forms.has_method("set_horde"):
		attack_forms.set_horde(horde)
	_create_desert()


# Etappe 19: Sandmaden, Sandsturm und ein gemeinsamer Brut-Stellvertreter
# (Moorbrut + Sandmaden) für die Angriffsformen.
func _create_desert() -> void:
	desert = DESERT_RUN.new()
	desert.name = "Desert"
	add_child(desert)
	desert.setup(self, swarm, get_parent().get_node_or_null("Arena"))
	if attack_forms != null and attack_forms.has_method("set_horde"):
		attack_forms.set_horde(desert.brood)


func _ensure_flood_hud() -> void:
	if hud == null or hud.get_node_or_null("hud_flood") != null or not ResourceLoader.exists(HUD_FLOOD_PATH):
		return
	var component: Control = load(HUD_FLOOD_PATH).new()
	component.name = "hud_flood"
	hud.add_child(component)


func _reset_flood() -> void:
	flood_state = 0
	flood_wave_clock = 0.0
	flood_reached = false
	horde_kills = 0
	flood_waves = 0
	flood_beep = -1
	flood_bundles.clear()
	flood_bundle_clock = 0.0
	horde_flash_at = 0.0
	flood_lure_stage = 0


# Difficulty multipliers (enemy HP/damage) ramp in over the first
# DIFFICULTY_RAMP_SECONDS: a fresh 20-25 swarm is not wiped by the first hunter.
func difficulty_scale(multiplier: float) -> float:
	return lerpf(minf(1.0, multiplier), multiplier, clampf(model.elapsed / TUNING.DIFFICULTY_RAMP_SECONDS, 0.0, 1.0))


# Flood start of the configured difficulty; Wild (TUNING) without a config.
func _difficulty_flood_start() -> float:
	if config.is_empty() or not config.has("difficulty") or not ResourceLoader.exists(META_DATA_PATH):
		return TUNING.FLOOD_START_SECONDS
	var table: Array = load(META_DATA_PATH).DIFFICULTIES
	var index := clampi(int(config.get("difficulty", 0)), 0, table.size() - 1)
	return float(table[index].get("flood_start", TUNING.FLOOD_START_SECONDS))


# Seconds since the flood started (0 before).
func flood_seconds() -> float:
	return maxf(0.0, model.elapsed - flood_start) if flood_state == 2 else 0.0


# Flood stage k: strength doubles every FLOOD_DOUBLING_SECONDS.
func flood_level() -> float:
	return flood_seconds() / TUNING.FLOOD_DOUBLING_SECONDS


# Stats of newly spawned Moorbrut at the current stage (horde contract):
# HP and bite x 2^k, speed x 2^k but capped below the swarm's own speed.
func flood_stats() -> Dictionary:
	var growth := pow(2.0, minf(flood_level(), 30.0))
	var speed_cap := minf(TUNING.FLOOD_SPEED_CAP, swarm.move_speed() * TUNING.FLOOD_SPEED_SHARE)
	return {
		"hp": TUNING.FLOOD_HP * growth * enemy_hp,
		"speed": minf(TUNING.FLOOD_SPEED * growth, speed_cap),
		"bite": TUNING.FLOOD_BITE * growth,
		"bite_cooldown": TUNING.FLOOD_BITE_COOLDOWN,
		"biomass": TUNING.FLOOD_KILL_BIOMASS,
		"dna": TUNING.FLOOD_KILL_DNA,
	}


# Moorbrut per wave: x 2^k up to the wave cap, never above the active cap.
func flood_wave_count() -> int:
	var wanted := mini(TUNING.FLOOD_WAVE_MAX, int(round(float(TUNING.FLOOD_WAVE_COUNT) * pow(2.0, minf(flood_level(), 30.0)))))
	var living := int(horde.count()) if horde != null and horde.has_method("count") else 0
	return clampi(wanted, 0, maxi(0, TUNING.FLOOD_MAX_ACTIVE - living))


# Announcement, waves, bites and kills. Returns true when step() must stop
# (extinction or a mutation offer).
func _step_flood(delta: float, damage: float) -> bool:
	if flood_state == 0 and model.elapsed >= flood_start - TUNING.FLOOD_WARNING_SECONDS:
		flood_state = 1
		flood_beep = -1
		_sfx("flood_warn", 150)
	if flood_state == 1:
		var countdown := ceili(flood_start - model.elapsed)
		# Short beeps over the last three seconds (the sfx rules rate-limit them).
		if countdown <= 3 and countdown != flood_beep and countdown > 0:
			flood_beep = countdown
			_sfx("warn", 40)
		if model.elapsed >= flood_start:
			flood_state = 2
			flood_reached = true
			flood_wave_clock = 0.0
			_sfx("stomp", 220)
			_sfx("threat")
			_music_cue("flood")
			_shake(0.45)
	if flood_state != 2:
		return false
	flood_wave_clock -= delta
	if flood_wave_clock <= 0.0:
		flood_wave_clock = TUNING.FLOOD_WAVE_SECONDS
		_spawn_flood_wave()
	# Etappe 16: every new flood stage drops a Lockruf ahead of the swarm.
	var stage := int(floor(flood_level()))
	if stage > flood_lure_stage:
		flood_lure_stage = stage
		drop_lure(swarm.position + Vector3(0.0, 0.0, -TUNING.LURE_FLOOD_DISTANCE))
	if horde == null:
		return false
	var points := _unit_points()
	if horde.has_method("melee") and horde.count() > 0 and not points.is_empty():
		horde.melee(points, MELEE_REACH, damage, delta)
	var result: Dictionary = horde.step(delta, points) if horde.has_method("step") else {}
	if _flood_kills(delta):
		return true
	return _flood_bites(result, points)


func _spawn_flood_wave() -> void:
	var count := flood_wave_count()
	if count <= 0 or horde == null or not horde.has_method("spawn_ring"):
		return
	var center: Vector3 = swarm.position + Vector3(0.0, 0.0, -TUNING.FLOOD_RING_SHIFT)
	center.y = 0.0
	horde.spawn_ring(center, count, TUNING.FLOOD_RING_RADIUS, flood_stats())
	flood_waves += 1


# Bitten animals fall first (prefer_removal); the loss is scaled to the logical
# population like an area hit and resolved through _apply_hit().
func _flood_bites(result: Dictionary, points: PackedVector3Array) -> bool:
	var bitten: PackedInt32Array = result.get("bitten_indices", PackedInt32Array())
	var loss := 0
	var impact: Vector3 = swarm.position
	var leader_struck := false
	if points.is_empty():
		loss = int(result.get("losses", 0))
	elif not bitten.is_empty():
		var sum := Vector3.ZERO
		var valid := PackedInt32Array()
		var followers := PackedInt32Array()
		for index in bitten:
			if index >= 0 and index < points.size():
				valid.append(index)
				sum += points[index]
				if index == 0:
					leader_struck = true
				else:
					followers.append(index)
		if valid.is_empty():
			return false
		impact = sum / float(valid.size())
		# "losses" = summed bite strength of this step in visible animals (the
		# horde carries fractions); each visible animal stands for P / visible.
		# Stage 09: the leader's share becomes 1 LP instead of a death.
		var units := float(result.get("losses", valid.size())) * float(followers.size()) / float(valid.size())
		loss = ceili(units * float(model.population) / float(points.size()) - 0.0001) if not followers.is_empty() else 0
		last_hit_share = float(valid.size()) / float(points.size())
		if swarm.has_method("prefer_removal") and not followers.is_empty():
			swarm.prefer_removal(followers)
	if loss <= 0 and not leader_struck:
		return false
	# Etappe 08 Teil 2: bites come in series; a full hit flash on every bite kept the
	# whole swarm washed out in pale pink. Horde bites flash softly and at most every
	# HORDE_FLASH_SECONDS (the loss, shove and ghosts stay unchanged).
	var flash_before: float = float(swarm.get("flash")) if "flash" in swarm else 0.0
	# No attacker: Stachelrücken answers the Moorbrut through the horde hook.
	var ended := _apply_hit(maxi(0, loss), impact, 0.08, null, leader_struck, false, "horde")
	if not ended and "flash" in swarm:
		var soft := flash_before
		if model.elapsed >= horde_flash_at:
			horde_flash_at = model.elapsed + HORDE_FLASH_SECONDS
			soft = maxf(flash_before, HORDE_FLASH)
		swarm.set("flash", soft)
		var material: Variant = swarm.get("game_material")
		if material is ShaderMaterial:
			(material as ShaderMaterial).set_shader_parameter("flash", soft * soft)
	return ended


# Collects horde kills into per-cell bundles; every FLOOD_BUNDLE_SECONDS each
# bundle bursts into crystals (resource rule) and leaves small remains.
func _flood_kills(delta: float) -> bool:
	if horde != null and horde.has_method("take_kills"):
		for kill in horde.take_kills():
			var at: Vector3 = kill.get("position", swarm.position)
			var key := Vector2i(floori(at.x / TUNING.FLOOD_BUNDLE_CELL), floori(at.z / TUNING.FLOOD_BUNDLE_CELL))
			var bundle: Dictionary = flood_bundles.get(key, {"sum": Vector3.ZERO, "n": 0, "biomass": 0.0, "dna": 0})
			# The horde already merges close kills; "count" says how many.
			var count := maxi(1, int(kill.get("count", 1)))
			bundle.sum += Vector3(at.x, 0.0, at.z) * float(count)
			bundle.n += count
			bundle.biomass += float(kill.get("biomass", TUNING.FLOOD_KILL_BIOMASS * count))
			bundle.dna += int(kill.get("dna", TUNING.FLOOD_KILL_DNA * count))
			flood_bundles[key] = bundle
			horde_kills += count
			for index in count:
				model.record_kill("horde")
			_note_kills(count, EVOLUTION.REGEN_HORDE_WEIGHT)
	flood_bundle_clock += delta
	if flood_bundle_clock < TUNING.FLOOD_BUNDLE_SECONDS or flood_bundles.is_empty():
		return false
	flood_bundle_clock = 0.0
	return flush_flood_bundles()


# Turns every pending horde bundle into crystals + remains now. Kept as a bool
# for callers (DNA arrives later as crystals, so no offer opens here).
func flush_flood_bundles() -> bool:
	if flood_bundles.is_empty():
		return false
	for key in flood_bundles:
		var bundle: Dictionary = flood_bundles[key]
		var location: Vector3 = get_parent().get_node("Arena").safe_spawn(bundle.sum / float(bundle.n), 0.4)
		location.y = 0.0
		var amount: float = float(bundle.biomass) * evolution.biomass_multiplier() * reward_multiplier()
		_add_remains(location, "horde")
		# The horde draws its own death effect; the crystals show the reward.
		# One crystal per bundle: its DNA is saved up and drops as one DNA
		# crystal once a whole LOOT_DNA_CHUNK has come together (value kept).
		flood_dna_pending += _reward_dna(int(bundle.dna))
		var dna := 0
		if flood_dna_pending >= int(TUNING.LOOT_DNA_CHUNK):
			dna = flood_dna_pending
			flood_dna_pending = 0
		# Bernstein of the Moorbrut adds up the same way (AMBER_HORDE per animal).
		flood_amber_pending += TUNING.AMBER_HORDE * float(bundle.n)
		var coins := int(floor(flood_amber_pending))
		flood_amber_pending -= float(coins)
		if loot != null:
			loot.burst(location, amount, dna, "horde", coins)
	flood_bundles.clear()
	_sfx("kill", 10)
	return choosing()


func _flood_message(message: String) -> String:
	if flood_state == 1:
		return "DIE FLUT KOMMT IN %d s!" % maxi(1, ceili(flood_start - model.elapsed))
	if flood_state == 2 and (message.begins_with("Jage") or message.begins_with("Mawlings greifen") or message.begins_with("Biomasse") or message.begins_with("Kristalle") or message.begins_with("Schwarm voll")):
		return "DIE FLUT · in Bewegung bleiben, Brut zerbeißen"
	return message


# Flood state for hud_flood.gd.
func _flood_hud() -> Dictionary:
	return {
		"state": flood_state,
		"countdown": maxf(0.0, flood_start - model.elapsed),
		"stage": int(floor(flood_level())) + 1,
		"level": flood_level(),
		"seconds": flood_seconds(),
		"count": int(horde.count()) if horde != null and horde.has_method("count") else 0,
	}


func toggle_pause() -> void:
	if model.extinct:
		return
	paused = not paused
	# The portal hum has no pause of its own: stop it while paused, resume after.
	_portal_hum(not paused and portal != null and migration_state != 1)
	hud.clear_pointers()
	swarm.set_controls(Vector2.ZERO, false)
	_update_hud("")


func _process(delta: float) -> void:
	# A stalled frame must not consume the whole player reaction window.
	step(minf(delta, 0.05))


func step(delta: float) -> void:
	if paused or model.extinct or choosing():
		swarm.clear_focus()
		return
	# Stage 10: while the migration swirl runs the world holds still (no time,
	# no enemy step); pause and reset freeze or drop it like everything else.
	if migration_state == 1:
		_step_migration(delta)
		return
	model.advance(delta)
	biome_seconds[biome_id] = float(biome_seconds.get(biome_id, 0.0)) + delta
	_track_exploration()
	_map_clock -= delta
	_map_corpse_clock -= delta
	unit_points_valid = false
	_age_popups(delta)
	lure_flash = maxf(0.0, lure_flash - delta)
	collect_hint = maxf(0.0, collect_hint - delta)
	hit_feedback = maxf(0.0, hit_feedback - delta)
	evolve_flash = maxf(0.0, evolve_flash - delta)
	milestone_timer = maxf(0.0, milestone_timer - delta)
	if milestone_timer <= 0.0:
		milestone_value = 0
	snap_gap = maxf(0.0, snap_gap - delta)
	_sync_leader()
	_music_step()
	if swarm.rally_pressed:
		model.used_rally = true
	# Etappe 17: Werte/Arsenal geändert (Level, Kokon) -> Waffen und LP nachziehen;
	# Tempo aus Stamm, Sprinter, Relikten und Rally (Rudelhorn).
	if evolution.revision != progression_revision:
		_sync_attack_forms()
		_try_evolve()
	swarm.speed_multiplier = evolution.speed_multiplier(swarm.rally_pressed)
	var message := "Jage Beute · Kristalle fliegen zu dir"
	var pressure: float = model.pressure()
	var attack_range := 1.15 if swarm.rally_pressed else 1.5
	# Stage 09: a small swarm's bigger animals bite harder (bonus fades out at 25).
	var small_bonus := TUNING.SMALL_SWARM_BITE * clampf(1.0 - float(model.population - 1) / 24.0, 0.0, 1.0)
	# Etappe 17b: melee power grows linearly with the population (the old cap of
	# 32 at ~260 animals is gone; the flood is the exponential counterweight).
	var damage := (1.0 + float(model.population) * 0.12 + small_bonus) * (1.55 if swarm.rally_pressed else 1.0)
	damage *= evolution.damage_multiplier(swarm.rally_pressed)
	focus_mode = 0
	focus_distance = INF
	melee_contact = false
	var population_before: int = model.population
	# Attack forms only reduce health; every death below is resolved exactly once,
	# whatever dealt the damage.
	if attack_forms != null and attack_forms.has_method("step"):
		attack_forms.step(delta, _living_targets(), swarm.rally_pressed, sqrt(pressure) * evolution.damage_multiplier(false) * form_population_scale())
	for target in prey.duplicate():
		if target.get("health") <= 0.0:
			_kill_prey(target)
			if choosing():
				return
			continue
		# Living prey may be recycled at a distance; corpses never expire.
		if target.position.distance_to(swarm.position) > 40.0:
			prey.erase(target)
			target.queue_free()
			continue
		# Stage 09: one snap circle at a time, then a shared gap (fair lone start).
		var was_snapping := int(target.get("snap_state")) == 1
		if "snap_blocked" in target:
			target.set("snap_blocked", snap_gap > 0.0 or _nibbler_snapping(target))
		target.call("step", delta, swarm.position, pressure)
		if was_snapping and int(target.get("snap_state")) == 0:
			snap_gap = TUNING.recovery(TUNING.NIBBLER_SNAP_GLOBAL_GAP, pressure, 0.6)
		# Nibbler snap (stage 08): announced small circle, per-animal hit.
		if _resolve_area_hit(target, target.get("snap_center"), 0.12):
			return
		if int(target.get("snap_state")) == 1 and not message.begins_with("RAUS"):
			message = "Nibbler schnappt · kurz ausweichen"
		_consider_focus(target.position, 3.2)
		var bite := melee_factor(target.position, "prey", attack_range)
		if bite > 0.0:
			melee_dealt += damage * bite * delta
			var health: float = target.get("health") - damage * bite * delta
			target.set("health", health)
			melee_contact = true
			message = "Mawlings greifen automatisch an"
			if health <= 0.0:
				_kill_prey(target)
				if choosing():
					return
	for hunter in hunters.duplicate():
		if _resolve_death(hunter, "hunter"):
			if choosing():
				return
			continue
		_consider_focus(hunter.position, 3.4)
		var hunter_bite := 0.0 if hunter.get("state") == HUNTER.State.ARRIVING else melee_factor(hunter.position, "elite" if hunter.elite else "hunter", attack_range)
		if hunter_bite > 0.0:
			hunter.call("take_damage", damage * hunter_bite * delta)
			melee_dealt += damage * hunter_bite * delta
			melee_contact = true
			message = "Jäger angreifen · vor dem Ring ausweichen"
			if _resolve_death(hunter, "hunter"):
				if choosing():
					return
				continue
		var velocity: Vector3 = Vector3(swarm.movement_vector.x, 0.0, swarm.movement_vector.y) * swarm.move_speed()
		hunter.call("step", delta, swarm.position, pressure, velocity)
		if _resolve_area_hit(hunter, hunter.attack_center, 0.35):
			return
		if hunter.get("state") == HUNTER.State.WARNING:
			message = "RAUS AUS DEM ROTEN RING!"
	for skitter in skitters.duplicate():
		if _resolve_death(skitter, "skitter"):
			if choosing():
				return
			continue
		_consider_focus(skitter.position, 3.4)
		var skitter_bite := 0.0 if skitter.get("state") == SKITTER.State.ARRIVING else melee_factor(skitter.position, "skitter", attack_range)
		if skitter_bite > 0.0:
			skitter.take_damage(damage * skitter_bite * delta)
			melee_dealt += damage * skitter_bite * delta
			melee_contact = true
			message = "Skitter angreifen · seitlich ausweichen"
			if _resolve_death(skitter, "skitter"):
				if choosing():
					return
				continue
		skitter.step(delta, swarm.position, pressure)
		if _resolve_area_hit(skitter, skitter.position, 0.3):
			return
		if skitter.state in [SKITTER.State.WARNING, SKITTER.State.DASH]:
			message = "SPRINT! SEITLICH AUSWEICHEN"
	for leaper in leapers.duplicate():
		if _resolve_death(leaper, "leaper"):
			if choosing():
				return
			continue
		if leaper.can_be_hit():
			_consider_focus(leaper.position, 3.4)
			var leaper_bite := melee_factor(leaper.position, "leaper", attack_range)
			if leaper_bite > 0.0:
				leaper.take_damage(damage * leaper_bite * delta)
				melee_dealt += damage * leaper_bite * delta
				melee_contact = true
				if leaper.state == MIRE_LEAPER.State.EXHAUSTED:
					message = "Leaper erschöpft · jetzt angreifen!"
				elif not message.begins_with("RAUS"):
					message = "Mire Leaper angreifen"
				if _resolve_death(leaper, "leaper"):
					if choosing():
						return
					continue
		leaper.step(delta, swarm.position, pressure)
		if _resolve_area_hit(leaper, leaper.landing_center, 0.35):
			return
		if leaper.state in [MIRE_LEAPER.State.WARNING, MIRE_LEAPER.State.LEAP]:
			message = "RAUS AUS DER SPRUNGZONE!"
		elif leaper.state == MIRE_LEAPER.State.EXHAUSTED and not message.begins_with("RAUS") and not message.begins_with("SPRINT"):
			message = "Leaper erschöpft · jetzt angreifen!"
	if boss != null and _resolve_death(boss, "boss") and choosing():
		return
	if boss != null:
		if boss.state != BOG_KING.State.ARRIVING:
			_consider_focus(boss.position, 6.0)
		var boss_bite := 0.0 if boss.state == BOG_KING.State.ARRIVING else melee_factor(boss.position, "boss", 3.5)
		if boss_bite > 0.0:
			boss.take_damage(damage * boss_bite * delta)
			melee_dealt += damage * boss_bite * delta
			melee_contact = true
			message = "BOG KING · RALLY ZUM ANGRIFF"
			if _resolve_death(boss, "boss") and choosing():
				return
		if boss != null:
			boss.step(delta, swarm.position, pressure)
			if _resolve_area_hit(boss, boss.attack_center, 0.45):
				return
			if boss.state == BOG_KING.State.WARNING:
				message = "BOG KING STAMPFT · RAUS AUS DEM KREIS!"
			elif boss.state == BOG_KING.State.RECOVERY and not message.begins_with("RAUS"):
				message = "BOG KING ERSCHÖPFT · JETZT ANGREIFEN!"
			elif boss.state == BOG_KING.State.ARRIVING:
				message = "DER BOG KING TAUCHT AUF!"
	# Stage 10: apex (Moosschlund / Aschenkröte) - melee, attack forms and its locked areas.
	var apex_result := _step_apex(delta, damage, pressure, message)
	if apex_result.ended:
		return
	message = apex_result.message
	# Glutsumpf lava eruptions: announced ground rings, then one area hit each
	# (same per-animal path and leader-LP rule as the enemy areas).
	if eruptions != null:
		var impacts: Array[Dictionary] = eruptions.step(delta, swarm.position, pressure)
		if not impacts.is_empty():
			_sfx("stomp", 60)
			if _resolve_area_hit(eruptions, impacts[0].center, 0.3):
				return
		if not eruptions.pending.is_empty() and not message.begins_with("RAUS") and not message.begins_with("BOG KING STAMPFT"):
			message = "LAVA BRICHT AUS!"
	if _step_flood(delta, damage):
		return
	if desert != null:
		var desert_result: Dictionary = desert.step(delta, damage, message)
		if desert_result.ended:
			return
		message = desert_result.message
	_audio_threat()
	message = _step_loot(delta, message)
	_step_leader_heal(delta)
	if _step_arsenal_world(delta):
		return
	_step_remains(delta)
	_step_alpha_pickups(delta)
	if attack_forms != null and attack_forms.has_method("contact_fx"):
		attack_forms.contact_fx(melee_contact)  # VFX V1: gedrosselte Biss-Sprites
	_audio_step(delta, population_before)
	if focus_mode == 0:
		swarm.clear_focus()
	else:
		swarm.set_focus(focus_point, focus_mode)
	spawn_clock += delta
	if spawn_clock >= TUNING.PREY_RESPAWN_SECONDS and prey.size() < TUNING.MAX_PREY:
		spawn_clock = 0.0
		_spawn_prey(_spawn_position(7.0))
	if not hunters_unlocked and model.elapsed >= TUNING.FIRST_HUNTER_SECONDS and (model.population >= TUNING.FIRST_HUNTER_POPULATION or model.elapsed >= TUNING.FIRST_HUNTER_LATEST):
		hunters_unlocked = true
		hunters_unlocked_at = model.elapsed
		hunter_clock = maxf(hunter_clock, TUNING.FIRST_HUNTER_GRACE)
	hunter_clock -= delta
	# Stage 09: the budget grows from the moment hunters unlocked (lone start).
	var hunter_budget := mini(TUNING.MAX_HUNTERS, TUNING.HUNTER_BUDGET_BASE + int(maxf(0.0, model.elapsed - hunters_unlocked_at) / TUNING.HUNTER_BUDGET_SECONDS))
	# ... and never more hunters than the swarm can take (1 + P / HUNTER_POPULATION_STEP).
	hunter_budget = mini(hunter_budget, 1 + model.population / TUNING.HUNTER_POPULATION_STEP)
	# The early gate holds for new hunters as long as it applies (a wiped swarm
	# regrows to FIRST_HUNTER_POPULATION before the next one comes).
	var gate_open: bool = model.population >= TUNING.FIRST_HUNTER_POPULATION or model.elapsed >= TUNING.FIRST_HUNTER_LATEST
	if hunters_unlocked and gate_open and hunter_clock <= 0.0 and hunters.size() < hunter_budget:
		_spawn_hunter(_spawn_position(8.0))
		# Stage 09: a small swarm gets more breathing room between hunters.
		var small := clampf(1.0 - float(model.population) / 25.0, 0.0, 1.0)
		hunter_clock = maxf(TUNING.HUNTER_SPAWN_MIN, TUNING.HUNTER_SPAWN_SECONDS / sqrt(pressure)) * (1.0 + TUNING.HUNTER_SMALL_SWARM_DELAY * small)
	skitter_clock -= delta
	var skitter_budget := mini(TUNING.MAX_SKITTERS, 1 + int(model.elapsed / TUNING.SKITTER_BUDGET_SECONDS))
	# Stage 09: side threats join as the swarm grows (none below one step).
	skitter_budget = mini(skitter_budget, model.population / TUNING.SKITTER_POPULATION_STEP)
	if model.elapsed >= TUNING.FIRST_SKITTER_SECONDS and skitter_clock <= 0.0 and skitters.size() < skitter_budget:
		_spawn_skitter(_spawn_position(9.0))
		skitter_clock = maxf(TUNING.SKITTER_SPAWN_MIN, TUNING.SKITTER_SPAWN_SECONDS / sqrt(pressure))
	leaper_clock -= delta
	var leaper_budget := mini(TUNING.MAX_LEAPERS, 1 + int(maxf(0.0, model.elapsed - TUNING.FIRST_LEAPER_SECONDS) / TUNING.LEAPER_BUDGET_SECONDS))
	leaper_budget = mini(leaper_budget, model.population / TUNING.LEAPER_POPULATION_STEP)
	if model.elapsed >= TUNING.FIRST_LEAPER_SECONDS and leaper_clock <= 0.0 and leapers.size() < leaper_budget:
		_spawn_leaper(_spawn_position(10.0))
		leaper_clock = maxf(TUNING.LEAPER_SPAWN_MIN, TUNING.LEAPER_SPAWN_SECONDS / sqrt(pressure))
	# Stage 10: no new Bog King while the Moosschlund rises or lives.
	if boss == null and apex_state != 1 and apex_state != 2:
		boss_clock -= delta
		# Stage 09: the first Bog King waits for a real swarm (or BOSS_LATEST).
		var boss_ready: bool = boss_cycles > 0 or model.population >= TUNING.BOSS_MIN_POPULATION or model.elapsed >= TUNING.BOSS_LATEST_SECONDS
		if boss_clock <= 0.0 and boss_ready:
			_spawn_boss(_spawn_position(11.0))
	message = _step_objectives(delta, message)
	message = _flood_message(message)
	message = _apex_schedule(delta, message)
	_update_hud(message)


# Stage 09: attack forms grow with the swarm (a lone Mawling is no pack).
func form_population_scale() -> float:
	return clampf(float(model.population) / TUNING.FORM_FULL_POPULATION, TUNING.FORM_MIN_SHARE, 1.0)


# Living, hittable creatures for the attack forms (same rules as melee).
func _living_targets() -> Array:
	var result: Array = []
	for target in prey:
		if target.get("health") > 0.0:
			result.append(target)
	for target in hunters:
		if target.health > 0.0 and target.state != HUNTER.State.ARRIVING:
			result.append(target)
	for target in skitters:
		if target.health > 0.0 and target.state != SKITTER.State.ARRIVING:
			result.append(target)
	for target in leapers:
		if target.health > 0.0 and target.can_be_hit():
			result.append(target)
	if boss != null and boss.health > 0.0 and boss.state != BOG_KING.State.ARRIVING:
		result.append(boss)
	if apex != null and apex.health > 0.0 and apex.can_be_hit():
		result.append(apex)
	return result


# Kills an enemy whose health is gone, whatever dealt the damage. It leaves its
# list first, so biomass, DNA, drops and statistics are granted exactly once.
func _resolve_death(enemy: Node3D, kind: String) -> bool:
	if enemy == null or enemy.health > 0.0:
		return false
	var location: Vector3 = enemy.position
	match kind:
		"hunter":
			if not hunters.has(enemy):
				return false
			hunters.erase(enemy)
			if enemy.elite:
				_kill_burst(location, Color("f5c86a"), 4.0, 0.35)
				_drop_rewards(location, "elite", TUNING.ELITE_BIOMASS, TUNING.ELITE_DNA)
				_drop_alpha_core(location)
				_drop_cocoon("elite", location)
				drop_lure(location)
			else:
				_kill_burst(location, Color("c58be0"), 2.6, 0.25)
				_drop_rewards(location, "hunter", TUNING.HUNTER_BIOMASS, KILL_DNA.hunter)
				if model.pressure() >= 2.0 and drop_rng.randf() < 0.10:
					_drop_alpha_core(location)
				_maybe_lure(location)
		"skitter":
			if not skitters.has(enemy):
				return false
			skitters.erase(enemy)
			_kill_burst(location, Color("7fb4ff"), 2.4, 0.2)
			_drop_rewards(location, "skitter", TUNING.SKITTER_BIOMASS, KILL_DNA.skitter)
			_maybe_lure(location)
			enemy.cleanup()
		"leaper":
			if not leapers.has(enemy):
				return false
			leapers.erase(enemy)
			_kill_burst(location, Color("5fe0c8"), 2.4, 0.2)
			_drop_rewards(location, "leaper", TUNING.LEAPER_BIOMASS, KILL_DNA.leaper)
			if drop_rng.randf() < 0.25:
				_drop_alpha_core(location)
			_maybe_lure(location)
			enemy.cleanup()
		"boss":
			if enemy != boss:
				return false
			boss = null
			_kill_burst(location, Color("ffe07a"), 7.5, 0.7)
			_kill_burst(location, Color("d8b8ff"), 5.0, 0.0)
			# The curse (and its double reward) ends with the cursed boss; its own
			# crystals are still doubled.
			_drop_rewards(location, "boss", TUNING.BOSS_BIOMASS, KILL_DNA.boss)
			boss_clock = TUNING.BOSS_RESPAWN_SECONDS
			_drop_alpha_core(location)
			# Etappe 17 Welle 2 (gegen den Schneeball): only the first Bog King of a
			# biome cycle leaves the golden boss cocoon, later ones a small one.
			_drop_cocoon("elite" if king_cocoon_taken else "boss", location)
			king_cocoon_taken = true
			drop_lure(location)
		"apex":
			if enemy != apex:
				return false
			apex = null
			var toad: bool = str(enemy.get("corpse_kind")) == "apex_toad"
			var worm: bool = str(enemy.get("corpse_kind")) == "apex_sandworm"
			if toad:
				_kill_burst(location, Color("ffb45a"), 9.0, 0.8)
				_kill_burst(location, Color("ff6a2a"), 6.5, 0.0)
				_drop_rewards(location, "apex_toad", TUNING.APEX_TOAD_BIOMASS, TUNING.APEX_TOAD_DNA)
			elif worm:
				_kill_burst(location, Color("ffe2a0"), 9.0, 0.8)
				_kill_burst(location, Color("7fe7ff"), 6.5, 0.0)
				_drop_rewards(location, "apex_sandworm", TUNING.APEX_SANDWORM_BIOMASS, TUNING.APEX_SANDWORM_DNA)
				worm_kills += 1
			else:
				_kill_burst(location, Color("e8f59a"), 9.0, 0.8)
				_kill_burst(location, Color("c8a0ff"), 6.5, 0.0)
				_drop_rewards(location, "apex", TUNING.APEX_BIOMASS, KILL_DNA.apex)
			for index in (TUNING.APEX_TOAD_ALPHA_CORES if toad else (TUNING.APEX_SANDWORM_ALPHA_CORES if worm else TUNING.APEX_ALPHA_CORES)):
				_drop_alpha_core(location)
			_drop_cocoon("boss", location)
			drop_lure(location)
		_:
			return false
	model.record_kill(kind)
	_note_kills(1, 1.0, location)
	if powerups != null:
		powerups.on_kill(kind, location, kind == "hunter" and bool(enemy.get("elite")), model.elapsed)
	if kind == "apex":
		# The body sinks into the ground (apex_boss DEAD pose) before it is freed.
		apex_dying = enemy
		apex_dying_clock = TUNING.APEX_SINK_SECONDS
	else:
		enemy.queue_free()
	if kind == "apex":
		_apex_defeated(location, str(enemy.get("corpse_kind")) == "apex_toad")
	if kind == "boss":
		_king_moment(location)
		if curse_state == 2:
			curse_state = 0
	return true


func _spawn_position(radius: float) -> Vector3:
	spawn_number += 1
	var angle := float(spawn_number) * 2.39996323
	var arena: Node3D = get_parent().get_node("Arena")
	var point: Vector3 = swarm.position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	# Stage 18b: on the path map an open, reachable spot near that ring point
	# (never behind a thick wall).
	if arena.has_method("spawn_point_near") and arena.has_layout():
		var near: Vector3 = arena.spawn_point_near(swarm.position, radius, angle, 0.9)
		if near.is_finite():
			return arena.safe_spawn(near, 0.9)
	# Stage 18: a ring point beyond the map edge is mirrored to the inner side.
	if arena.has_method("fold_inside"):
		point = arena.fold_inside(point, 1.5)
	return arena.safe_spawn(point, 0.9)


# Stage 18: the swarm starts in the middle of the bounded map (solo: the origin).
func _start_point() -> Vector3:
	var arena: Node3D = get_parent().get_node_or_null("Arena") if get_parent() != null else null
	if arena == null or not arena.has_method("spawn_points"):
		return Vector3.ZERO
	var points: Array = arena.spawn_points(1)
	return Vector3(points[0].x, 0.0, points[0].z)


func _spawn_prey(location: Vector3) -> void:
	var target: Node3D = PREY.new()
	target.name = "Nibbler"
	target.position = location
	add_child(target)
	prey.append(target)
	_tint_enemy(target, "prey")


func _spawn_hunter(location: Vector3) -> Node3D:
	var target = HUNTER.new()
	target.name = "Hunter"
	target.position = location
	target.health = TUNING.HUNTER_HEALTH * sqrt(model.pressure()) * difficulty_scale(enemy_hp)
	target.max_health = target.health
	add_child(target)
	hunters.append(target)
	_tint_enemy(target, "hunter")
	return target


func _spawn_skitter(location: Vector3) -> Node3D:
	var target = SKITTER.new()
	target.name = "Skitter"
	target.position = location
	target.health = TUNING.SKITTER_HEALTH * sqrt(model.pressure()) * difficulty_scale(enemy_hp)
	target.max_health = target.health
	add_child(target)
	skitters.append(target)
	_tint_enemy(target, "skitter")
	return target


func _spawn_leaper(location: Vector3) -> Node3D:
	var target = MIRE_LEAPER.new()
	target.name = "Mire Leaper"
	target.position = location
	target.health = TUNING.LEAPER_HEALTH * sqrt(model.pressure()) * difficulty_scale(enemy_hp)
	target.max_health = target.health
	add_child(target)
	leapers.append(target)
	_tint_enemy(target, "leaper")
	return target


func _spawn_boss(location: Vector3) -> Node3D:
	var target = BOG_KING.new()
	target.name = "Bog King"
	target.position = get_parent().get_node("Arena").safe_spawn(location, 2.5)
	target.health = TUNING.BOSS_HEALTH * sqrt(model.pressure()) * difficulty_scale(enemy_hp)
	target.max_health = target.health
	add_child(target)
	boss = target
	_tint_enemy(target, "bog_king")
	_on_boss_spawned(target)
	_music_cue("boss")
	_sfx("boss_roar", 120)
	return target


func _kill_prey(target: Node3D) -> void:
	if not prey.has(target):
		return
	prey.erase(target)
	_kill_burst(target.position, Color("7de6d2"), 1.8, 0.0)
	_drop_rewards(target.position, "prey", CORPSE_BIOMASS, KILL_DNA.prey)
	model.record_kill("prey")
	_note_kills(1, 1.0, target.position)
	if powerups != null:
		powerups.on_kill("prey", target.position, false, model.elapsed)
	target.queue_free()


# Etappe 16: a death leaves empty remains (decoration) and bursts into loot
# crystals: biomass x biomass_multiplier (future kills) x curse, DNA x curse.
# Returns the DNA dropped.
func _drop_rewards(location: Vector3, kind: String, biomass: float, dna: int) -> int:
	var at := Vector3(location.x, 0.0, location.z)
	_add_remains(at, kind)
	var amount := biomass * evolution.biomass_multiplier() * reward_multiplier()
	var reward := _reward_dna(dna)
	# Etappe 17 Welle 2: every kill also drops Bernstein by kind (x curse).
	var amber := int(round(float(TUNING.AMBER_KILL.get(kind, 0)) * reward_multiplier()))
	drop_loot(at, amount, reward, String(KIND_RANK.get(kind, "normal")), amber)
	return reward


## Bursts `biomass` and `dna` into crystals at `location` (public for tests,
## captures and the perf bench). Values are final (no multipliers applied).
func drop_loot(location: Vector3, biomass: float, dna: int = 0, rank: String = "normal", amber: int = 0) -> void:
	if loot == null or model.extinct:
		return
	loot.burst(Vector3(location.x, 0.0, location.z), biomass, dna, rank, amber)


# Empty remains of `kind` (corpse_visuals design); they sink after their life.
# Returns the remains id (-1 without a corpse view).
func _add_remains(location: Vector3, kind: String) -> int:
	if corpse_view == null:
		return -1
	var id := next_remains_id
	next_remains_id += 1
	var rank := String(KIND_RANK.get(kind, "normal"))
	var life: float = TUNING.CORPSE_HORDE_LIFE if kind == "horde" else float(TUNING.CORPSE_LIFE.get(rank, 25.0))
	corpse_kinds[id] = kind
	remains[id] = {"age": 0.0, "life": life, "at": location}
	remains_order.append(id)
	corpse_view.add(id, kind, location, 1.0)
	# The oldest remains go first when too many lie around.
	while remains_order.size() > TUNING.CORPSE_MAX:
		_remove_remains(remains_order[0])
	return id


func _remove_remains(id: int) -> void:
	remains.erase(id)
	remains_order.erase(id)
	corpse_kinds.erase(id)
	if corpse_view != null:
		corpse_view.remove(id)


## Position of remains `id` (INF when gone).
func remains_position(id: int) -> Vector3:
	return remains[id].at if remains.has(id) else Vector3.INF


# Remains age; in their last CORPSE_SINK_SECONDS they sink, then they vanish.
func _step_remains(delta: float) -> void:
	if remains_order.is_empty():
		return
	for id in remains_order.duplicate():
		var entry: Dictionary = remains[id]
		entry.age += delta
		var left: float = float(entry.life) - float(entry.age)
		if left <= 0.0:
			_remove_remains(id)
		elif left < TUNING.CORPSE_SINK_SECONDS and corpse_view != null:
			corpse_view.set_decay(id, 1.0 - left / TUNING.CORPSE_SINK_SECONDS)


# Corpse designs and lava eruptions live under HuntWorld, so reset_run() frees
# them with the other children and they come back empty.
func _create_world_views() -> void:
	corpse_view = CORPSE_VISUALS.new()
	corpse_view.name = "CorpseView"
	corpse_view.empty = true
	add_child(corpse_view)
	loot = LOOT.new()
	loot.name = "Loot"
	add_child(loot)
	loot.setup(get_parent().get_node_or_null("Arena") as Node3D)
	loot_nodes = LOOT_NODES.new()
	loot_nodes.name = "LootNodes"
	add_child(loot_nodes)
	loot_nodes.setup(self, get_parent().get_node_or_null("Arena") as Node3D)
	_create_arsenal_world()
	eruptions = ERUPTIONS.new()
	eruptions.name = "Eruptions"
	eruptions.arena = get_parent().get_node_or_null("Arena") as Node3D
	add_child(eruptions)


func _piece(parent: Node3D, mesh: Mesh, material: Material, location: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = location
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part


# ---------------------------------------------------------------- Anführer-LP (Etappe 17c)

## Melee damage the swarm dealt this step (Lebensraub counts it with the forms).
var melee_dealt := 0.0
var _forms_dealt_seen := 0.0
var _heal_pool := 0.0
## Last visible heal ("+N" over the leader) and when it happened.
var leader_heal_shown := 0
var leader_heal_at := -INF


## LP a hit on the leader costs: TUNING.LEADER_HIT by attacker x
## pressure^LEADER_HIT_PRESSURE x difficulty (grows gentler than the animal damage).
func leader_damage(attacker: Node3D, source: String = "") -> int:
	var key := source
	if key == "":
		if attacker == null:
			key = "default"
		elif attacker == eruptions:
			key = "eruption"
		elif attacker is PREY:
			key = "prey"
		elif attacker is HUNTER:
			key = "elite" if bool(attacker.get("elite")) else "hunter"
		elif attacker is SKITTER:
			key = "skitter"
		elif attacker is MIRE_LEAPER:
			key = "leaper"
		elif attacker is BOG_KING:
			key = "boss"
		elif attacker == apex:
			key = "apex"
		else:
			key = "apex_puddle"
	var base := float(TUNING.LEADER_HIT.get(key, TUNING.LEADER_HIT["default"]))
	return maxi(1, int(round(base * pow(model.pressure(), TUNING.LEADER_HIT_PRESSURE) * difficulty_scale(enemy_damage))))


# Heals the leader (Lebensraub, Regeneration, Königszahnkette) and remembers the
# amount for the small green "+N" over the leader. Returns LP gained.
func _heal_leader(amount: int) -> int:
	var gained: int = model.heal_leader(amount)
	if gained > 0:
		if model.elapsed - leader_heal_at > 0.8:
			leader_heal_shown = 0
		leader_heal_shown += gained
		leader_heal_at = model.elapsed
		_sync_leader()
	return gained


# Lebensraub: a share of all damage the swarm dealt (melee + attack forms) heals
# the leader; Regeneration heals LP per second. Fractions are pooled.
func _step_leader_heal(delta: float) -> void:
	var forms_total := 0.0
	if attack_forms != null and "damage_dealt" in attack_forms:
		for value in (attack_forms.damage_dealt as Dictionary).values():
			forms_total += float(value)
	var forms_now := maxf(0.0, forms_total - _forms_dealt_seen)
	_forms_dealt_seen = forms_total
	var dealt := melee_dealt + forms_now
	melee_dealt = 0.0
	if model.extinct or model.leader_hp >= model.leader_max_hp:
		_heal_pool = 0.0
		return
	_heal_pool += dealt * evolution.lifesteal() + evolution.regen_rate() * delta
	if _heal_pool >= 1.0:
		var whole := int(floor(_heal_pool))
		_heal_pool -= float(whole)
		_heal_leader(whole)


# ---------------------------------------------------------------- Kokons, Power-ups, Schreine (Etappe 17 Welle 2)

func _create_arsenal_world() -> void:
	var arena := get_parent().get_node_or_null("Arena") as Node3D
	chests = CHESTS.new()
	chests.name = "Chests"
	add_child(chests)
	chests.setup(self, arena)
	powerups = POWERUPS.new()
	powerups.name = "Powerups"
	add_child(powerups)
	powerups.setup(self, arena)
	shrines = SHRINES.new()
	shrines.name = "Shrines"
	add_child(shrines)
	shrines.setup(self, arena)



# Holds/opens cocoons, picks up boosters, charges shrines. True when a choice
# (boss cocoon, shrine) opened and step() must stop.
func _step_arsenal_world(delta: float) -> bool:
	if model.extinct:
		return false
	var centre: Vector3 = swarm.position
	if chests != null:
		chests.step(delta, centre)
	if powerups != null:
		powerups.step(delta, centre, _unit_points())
	if shrines != null:
		shrines.step(delta, centre)
	if choosing():
		hud.clear_pointers()
		swarm.set_controls(Vector2.ZERO, false)
		_update_hud("")
		return true
	return false


## Drops a free cocoon ("elite" / "boss") at a death spot.
func _drop_cocoon(kind: String, location: Vector3) -> void:
	if chests != null and not model.extinct:
		chests.drop(kind, location)


func _ensure_loot_hud() -> void:
	if hud == null or hud.get_node_or_null("hud_loot") != null or not ResourceLoader.exists(HUD_LOOT_PATH):
		return
	var component: Control = load(HUD_LOOT_PATH).new()
	component.name = "hud_loot"
	hud.add_child(component)


func _arsenal_hud() -> Dictionary:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var state := {"tags": [], "card": {}, "active": [], "band": {}, "shrines": []}
	if chests != null:
		state.merge(chests.hud_state(camera, swarm.position), true)
	if powerups != null:
		state.merge(powerups.hud_state(), true)
	if shrines != null:
		state["shrines"] = shrines.hud_state(camera, swarm.position)
	return state


# Minimap marks of one module, only where the fog is lifted (dropped cocoons always).
func _arsenal_marks(source: Node3D) -> Array:
	if source == null:
		return []
	var arena := _map_arena()
	var out: Array = []
	for mark in source.map_marks():
		var seen := true
		if not bool(mark.get("dropped", false)) and arena != null:
			if arena.has_method("is_discovered"):
				seen = arena.is_discovered(mark.at)
			elif arena.has_method("is_explored"):
				seen = arena.is_explored(mark.at)
		if seen:
			out.append(mark)
	return out


# ---------------------------------------------------------------- Alpha-Kern

# Etappe 17: der Alpha-Kern entfällt als Ressource (Evolutionen kommen aus dem
# Boss-Kokon, Welle 2 ersetzt die Drops durch Elite-/Boss-Kokons). Nur Tests und
# Aufnahmen schalten das alte Objekt noch ein.
var alpha_cores_enabled := false


# Drops a glowing amber-violet core beside the corpse; it stays until touched.
func _drop_alpha_core(location: Vector3) -> Node3D:
	if not alpha_cores_enabled:
		return null
	var offset := Vector3(1.3, 0.0, 0.0).rotated(Vector3.UP, drop_rng.randf() * TAU)
	var pickup := Node3D.new()
	pickup.name = "Alpha core"
	pickup.position = get_parent().get_node("Arena").safe_spawn(location + offset, 0.5)
	add_child(pickup)
	var parts := _alpha_core_parts()
	var shell: Material = FX_BATCH.shared_material(Color(ALPHA_VIOLET, 0.55), true, true)
	var halo: Material = FX_BATCH.shared_material(Color(ALPHA_AMBER, 0.75), true, true, 1.0, true)
	var float_root := Node3D.new()
	float_root.name = "Float"
	pickup.add_child(float_root)
	# User model (assets/gameplay/props/AlphaCore_game.glb) instead of gem + shell.
	ALPHA_CORE_VISUAL.attach(float_root)
	var ground := _piece(pickup, parts.ring, halo, Vector3(0.0, 0.08, 0.0))
	ground.scale = Vector3(1.0, 0.2, 1.0)
	_piece(pickup, parts.beam, shell, Vector3(0.0, 2.0, 0.0))
	alpha_pickups.append(pickup)
	FX.ring(self, pickup.position, Color(ALPHA_VIOLET, 0.45), 0.3, 1.6, 0.45)
	return pickup


# Meshes of the Alpha-Kern and the curse aura, built once and shared.
static func _alpha_core_parts() -> Dictionary:
	if not _alpha_parts.is_empty():
		return _alpha_parts
	var gem := SphereMesh.new()
	gem.radius = 0.36
	gem.height = 0.84
	gem.radial_segments = 6
	gem.rings = 3
	var outer := SphereMesh.new()
	outer.radius = 0.62
	outer.height = 1.24
	outer.radial_segments = 8
	outer.rings = 4
	var ring := TorusMesh.new()
	ring.inner_radius = 0.85
	ring.outer_radius = 1.1
	ring.rings = 32
	ring.ring_segments = 4
	var beam := CylinderMesh.new()
	beam.top_radius = 0.04
	beam.bottom_radius = 0.2
	beam.height = 4.0
	beam.radial_segments = 16
	beam.rings = 1
	var aura := TorusMesh.new()
	aura.inner_radius = 2.4
	aura.outer_radius = 2.95
	aura.rings = 48
	aura.ring_segments = 4
	_alpha_parts = {"gem": gem, "outer": outer, "ring": ring, "beam": beam, "aura": aura}
	return _alpha_parts


# Animates stored-on-ground cores and collects touched ones.
func _step_alpha_pickups(delta: float) -> void:
	alpha_clock += delta
	for pickup in alpha_pickups.duplicate():
		var float_root: Node3D = pickup.get_node("Float")
		float_root.position.y = 0.12 * sin(alpha_clock * 2.6 + pickup.position.x)
		float_root.rotation.y += delta * 1.6
		var flat := Vector2(pickup.position.x - swarm.position.x, pickup.position.z - swarm.position.z)
		if flat.length() > ALPHA_PICKUP_RADIUS:
			continue
		alpha_pickups.erase(pickup)
		FX.ring(self, pickup.position, Color(ALPHA_AMBER, 0.9), 0.3, 2.0, 0.4)
		pickup.queue_free()
		collect_alpha_core()


# Stores one Alpha-Kern and evolves at once when a rule is satisfied.
func collect_alpha_core() -> void:
	_sfx("alpha_core", 25)
	evolution.add_alpha_core()
	if not _try_evolve():
		evolve_name = ""
		_update_hud("Alpha-Kern gelagert · " + (evolution.evolution_hint() if evolution.evolution_hint() != "" else "wartet auf eine Evolution"))


func _try_evolve() -> bool:
	var evolved: String = evolution.try_evolve()
	if evolved == "":
		return false
	_sync_attack_forms()
	evolve_name = evolution.info(evolved)[1]
	evolve_flash = 3.0
	_sfx("evolve", 80)
	_kill_burst(swarm.position, ALPHA_AMBER, 6.0, 0.35)
	_kill_burst(swarm.position, ALPHA_VIOLET, 4.2, 0.0)
	_update_hud("EVOLUTION · %s!" % evolve_name.to_upper())
	return true


# ---------------------------------------------------------------- Apex & Migration (stage 10)

func _reset_apex() -> void:
	apex = null
	apex_state = 0
	apex_clock = 0.0
	apex_spot = Vector3.ZERO
	apex_pulse = 0.0
	apex_kills = 0
	apex_due = -1.0
	apex_spawned = 0
	apex_kind = "apex"
	toad_kills = 0
	worm_kills = 0
	apex_victories = 0
	apex_dying = null
	apex_dying_clock = 0.0
	portal = null
	portal_clock = -1.0
	portal_point = Vector3.ZERO
	migration_state = 0
	migration_timer = 0.0
	migration_switched = false
	migration_to = ""
	migrations = 0
	arrivals = 0
	biomes_visited.clear()
	biome_seconds.clear()


# Biome of the RunConfig (menu choice); Verdant Maw without one.
func _start_biome() -> String:
	var id := str(config.get("biome_id", BIOMES.DEFAULT))
	return id if BIOMES.has(id) else BIOMES.DEFAULT


# Switches arena look, sun light and enemy tints to `id` (layout and every run
# value stay). staggered = migration inside a running game (arena.set_biome).
func _set_world_biome(id: String, staggered: bool) -> void:
	biome_id = id if BIOMES.has(id) else BIOMES.DEFAULT
	if not biomes_visited.has(biome_id):
		biomes_visited.append(biome_id)
	var arena: Node3D = get_parent().get_node_or_null("Arena") if get_parent() != null else null
	if arena != null and String(arena.get("biome_id")) != biome_id:
		arena.set_biome(biome_id, staggered)
	var main := get_parent()
	if main != null and main.has_method("apply_biome_light"):
		main.apply_biome_light(biome_id)
	_tint_living_enemies()


# Time the start biome's apex is due on the configured difficulty (Wild without config).
func apex_spawn_seconds() -> float:
	var table: Array = TUNING.APEX_SPAWN_SECONDS
	return float(table[clampi(int(config.get("difficulty", 0)), 0, table.size() - 1)])


# Apex health share of the configured difficulty (Brutal/Apex meet it earlier
# with a smaller swarm).
func apex_health_scale() -> float:
	var table: Array = TUNING.APEX_HEALTH_DIFFICULTY
	return float(table[clampi(int(config.get("difficulty", 0)), 0, table.size() - 1)])


# Run time the next apex is due: difficulty schedule in the start biome,
# APEX_ARRIVAL_DELAY after the arrival in every later biome.
func apex_due_seconds() -> float:
	return apex_due if apex_due >= 0.0 else apex_spawn_seconds()


# Apex of a biome: the Glutsumpf has the Aschenkröte, the Dürrschlund the
# Sandwurm (biomes.gd "apex_kind"), every other the Moosschlund.
static func apex_kind_for(id: String) -> String:
	if id == "glutsumpf":
		return "apex_toad"
	return String(BIOMES.get_data(id).get("apex_kind", "apex")) if BIOMES.has(id) else "apex"


static func apex_display_name(kind: String) -> String:
	if kind == "apex_sandworm":
		return APEX_SANDWORM.DISPLAY_NAME
	return APEX_TOAD.DISPLAY_NAME if kind == "apex_toad" else "Moosschlund"


# Etappe 19: rise radius of an apex kind (warning ring, spawn clearance).
static func apex_body_radius(kind: String) -> float:
	if kind == "apex_sandworm":
		return APEX_SANDWORM.BODY_RADIUS
	return APEX_TOAD.BODY_RADIUS if kind == "apex_toad" else TUNING.APEX_BODY_RADIUS


# Completed loops through the biome circle before the next apex (0 for the first
# Moosschlund and the first Aschenkröte, 1 for their return, ...).
func apex_loop() -> int:
	return apex_spawned / BIOMES.ORDER.size()


# Calm hints may be replaced by apex / migration hints; warnings never are.
func _is_calm(message: String) -> bool:
	for prefix in ["Jage", "Mawlings greifen", "Biomasse", "Kristalle", "Schwarm voll", "DIE FLUT ·", "Fluch aktiv", "Brutnest füllen", "Alpha-Kern", "Mutation", "Neue Auswahl"]:
		if message.begins_with(prefix):
			return true
	return message == ""


# Waiting -> ground warning -> spawn. Called at the end of step().
func _apex_schedule(delta: float, message: String) -> String:
	if apex_state == 0:
		var due := apex_due_seconds()
		if model.elapsed < due:
			return message
		var next_kind := apex_kind_for(biome_id)
		var needed: int = TUNING.APEX_TOAD_MIN_POPULATION if next_kind == "apex_toad" else (TUNING.APEX_SANDWORM_MIN_POPULATION if next_kind == "apex_sandworm" else TUNING.APEX_MIN_POPULATION)
		var swarm_ready: bool = model.population >= needed or model.elapsed >= due + TUNING.APEX_LATEST_EXTRA
		var king_clear: bool = boss == null or model.elapsed >= flood_start - TUNING.APEX_FLOOD_MARGIN
		if swarm_ready and king_clear:
			begin_apex_warning()
	if apex_state == 1:
		apex_clock -= delta
		apex_pulse -= delta
		var toad := apex_kind == "apex_toad"
		var worm := apex_kind == "apex_sandworm"
		if apex_pulse <= 0.0:
			apex_pulse = 0.5
			var radius: float = apex_body_radius(apex_kind)
			var outer := Color(1.0, 0.55, 0.18, 0.85) if toad else (Color(0.98, 0.86, 0.6, 0.85) if worm else Color(0.62, 0.82, 0.32, 0.85))
			var inner := Color(0.4, 0.36, 0.36, 0.7) if toad else (Color(0.55, 0.42, 0.26, 0.7) if worm else Color(0.3, 0.22, 0.12, 0.7))
			FX.ring(self, apex_spot, outer, 1.0, radius + 3.5, 0.7)
			FX.ring(self, apex_spot, inner, 0.5, radius + 1.0, 0.9)
			_shake(0.14)
		if apex_clock <= 0.0:
			spawn_apex(apex_spot)
			return "DIE ASCHENKRÖTE ERWACHT!" if toad else ("DER SANDWURM ERWACHT!" if worm else "DER MOOSSCHLUND ERWACHT!")
		if _is_calm(message):
			return "DER BODEN BEBT · DIE ASCHENKRÖTE ERWACHT" if toad else ("DER SAND BEBT · DER SANDWURM ERWACHT" if worm else "DER BODEN BEBT · DER MOOSSCHLUND ERWACHT")
	return message


## Announces the apex: the ground shakes at the (visible) spot ahead of the swarm.
func begin_apex_warning() -> void:
	if apex_state != 0:
		return
	apex_state = 1
	apex_clock = TUNING.APEX_WARNING_SECONDS
	apex_pulse = 0.0
	apex_kind = apex_kind_for(biome_id)
	var radius: float = apex_body_radius(apex_kind)
	var arena: Node3D = get_parent().get_node("Arena")
	# Stage 18: in front of the swarm, mirrored inwards at the map edge, with room
	# for the fight between the apex and the wall.
	var ahead: Vector3 = swarm.position + Vector3(0.0, 0.0, -TUNING.APEX_SPAWN_DISTANCE)
	if arena.has_method("fold_inside"):
		ahead = arena.fold_inside(ahead, radius + 6.0)
	# Stage 18b: on the path map the apex rises in the boss arena (the nearest
	# one) and comes along the paths; standing in the arena already, the swarm
	# gets it on the far side.
	var arenas: Array = arena.poi_slots("boss") if arena.has_method("poi_slots") else []
	if not arenas.is_empty():
		ahead = arenas[0]
		for spot in arenas:
			if swarm.position.distance_to(spot) < swarm.position.distance_to(ahead):
				ahead = spot
		var off: Vector3 = ahead - swarm.position
		off.y = 0.0
		if off.length() < TUNING.APEX_SPAWN_DISTANCE:
			ahead = swarm.position + (off.normalized() if off.length() > 0.5 else Vector3(0.0, 0.0, -1.0)) * TUNING.APEX_SPAWN_DISTANCE
	apex_spot = arena.safe_spawn(ahead, radius + 0.5)
	apex_spot.y = 0.0
	_sfx("quake", 160)
	_shake(0.3)


## Spawns the apex of the current biome now (public for tests and captures);
## `kind` "apex" (Moosschlund) or "apex_toad" (Aschenkröte) overrides the biome.
func spawn_apex(location: Vector3, kind: String = "") -> Node3D:
	if apex != null:
		return apex
	apex_kind = kind if kind != "" else apex_kind_for(biome_id)
	var toad := apex_kind == "apex_toad"
	var worm := apex_kind == "apex_sandworm"
	var arena: Node3D = get_parent().get_node("Arena")
	var target = APEX_TOAD.new() if toad else (APEX_SANDWORM.new() if worm else APEX_BOSS.new())
	target.name = apex_display_name(apex_kind)
	target.arena = arena
	target.position = arena.safe_spawn(Vector3(location.x, 0.0, location.z), float(target.body_radius) + 0.5)
	var facing: Vector3 = swarm.position - target.position
	target.rotation.y = atan2(facing.x, facing.z) + PI * 0.5
	# The difficulty already brings it earlier against a smaller swarm; only a
	# return in a later loop through the biome circle is stronger.
	var loop := apex_loop()
	target.health = (TUNING.APEX_TOAD_HEALTH if toad else (TUNING.APEX_SANDWORM_HEALTH if worm else TUNING.APEX_HEALTH)) * apex_health_scale() * pow(TUNING.APEX_LOOP_HEALTH, loop)
	target.max_health = target.health
	target.set_meta("damage_scale", pow(TUNING.APEX_LOOP_DAMAGE, loop))
	target.set_meta("loop", loop)
	add_child(target)
	apex = target
	apex_state = 2
	apex_spawned += 1
	_music_cue("boss")
	_sfx("stomp", 220)
	_sfx("boss_roar")
	return target


# Melee, attack-form deaths, the locked attack areas and the portal. Returns
# {"ended": step() must stop, "message": hint}.
func _step_apex(delta: float, damage: float, pressure: float, message: String) -> Dictionary:
	var result := {"ended": false, "message": message}
	if apex_dying != null:
		apex_dying.step(delta, swarm.position, pressure)
		apex_dying_clock -= delta
		if apex_dying_clock <= 0.0:
			apex_dying.queue_free()
			apex_dying = null
	if apex_state == 3:
		_step_portal(delta, result)
		if result.ended:
			return result
	if apex == null:
		return result
	if _resolve_death(apex, "apex"):
		result.ended = choosing()
		return result
	var hittable: bool = apex.can_be_hit()
	if hittable:
		_consider_focus(apex.position, float(apex.melee_range) + 2.0)
	var bite := melee_factor(apex.position, apex_kind, apex.melee_range, apex) if hittable else 0.0
	if bite > 0.0:
		apex.take_damage(damage * bite * delta)
		melee_dealt += damage * bite * delta
		melee_contact = true
		if _resolve_death(apex, "apex"):
			result.ended = choosing()
			return result
	var apex_pressure: float = pow(pressure, TUNING.APEX_PRESSURE_EXPONENT) * float(apex.get_meta("damage_scale", 1.0))
	apex.step(delta, swarm.position, apex_pressure)
	if _resolve_area_hit(apex, apex.attack_center, 0.5):
		result.ended = true
		return result
	# Aschenkröte: the lingering Glutpfützen tick like an announced enemy area.
	var puddles: Variant = apex.get("puddles")
	if puddles != null and is_instance_valid(puddles) and _resolve_area_hit(puddles, puddles.last_center, 0.2):
		result.ended = true
		return result
	var text: String = apex.hud_message()
	if apex.state == APEX_BOSS.State.WINDUP or apex.state == APEX_BOSS.State.PHASE_SHIFT:
		result.message = text
	elif text != "" and not String(result.message).begins_with("RAUS") and not String(result.message).begins_with("SPRINT"):
		result.message = text
	elif bite > 0.0 and _is_calm(result.message):
		result.message = "%s · RALLY ZUM ANGRIFF" % apex_display_name(apex_kind).to_upper()
	return result


# Victory: Königsmoment (slow motion + zoom in Main, stinger), banner counter
# for hud_objectives, and the Migrationsschlund behind the corpse.
func _apex_defeated(location: Vector3, toad: bool = false) -> void:
	apex_kills += 1
	if toad:
		toad_kills += 1
	apex_victories += 1
	apex_state = 3
	var away: Vector3 = location - swarm.position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3(0.0, 0.0, -1.0)
	var arena: Node3D = get_parent().get_node("Arena")
	var behind := location + away.normalized() * TUNING.APEX_PORTAL_OFFSET
	if arena.has_method("fold_inside"):
		behind = arena.fold_inside(behind, TUNING.MIGRATION_RADIUS + 3.0)
	# Stage 18b: on the path map the Migrationsschlund opens in its own clearing
	# near the map edge (away from the boss arena): the way there is the last
	# stretch of the biome. Only a kill right at that spot keeps the old rule.
	var maws: Array = arena.poi_slots("maw") if arena.has_method("poi_slots") else []
	if not maws.is_empty():
		var maw_spot: Vector3 = maws[0]
		if maw_spot.distance_to(location) > TUNING.MIGRATION_RADIUS + 8.0:
			behind = maw_spot
	portal_point = arena.safe_spawn(behind, TUNING.MIGRATION_RADIUS + 0.5)
	portal_point.y = 0.0
	portal_clock = TUNING.APEX_PORTAL_DELAY
	if apex_dying != null:
		apex_dying.set("migration_point", portal_point)
	# A real fanfare instead of evolve + the music stinger "king".
	_sfx("fanfare", 160)
	var main := get_parent()
	if main != null and main.has_method("king_moment"):
		main.king_moment(location)


## Opens the Migrationsschlund now (public for tests and captures).
func open_portal(location: Vector3) -> Node3D:
	if portal != null:
		return portal
	portal = MIGRATION_MAW.new()
	portal.name = "Migration maw"
	portal.setup(BIOMES.next_biome(biome_id), biome_id)
	portal.position = Vector3(location.x, 0.0, location.z)
	add_child(portal)
	portal_point = portal.position
	portal_clock = -1.0
	apex_state = maxi(apex_state, 3)
	FX.ring(self, portal.position, Color(1.0, 0.8, 0.5, 0.9), 0.6, TUNING.MIGRATION_RADIUS + 3.0, 0.9)
	FX.ring(self, portal.position, Color(0.7, 0.3, 0.55, 0.8), 0.4, TUNING.MIGRATION_RADIUS + 1.0, 1.2)
	_sfx("portal_open", 60)
	_portal_hum(true)
	return portal


func _step_portal(delta: float, result: Dictionary) -> void:
	if portal == null:
		if portal_clock < 0.0:
			return
		portal_clock -= delta
		if _is_calm(String(result.message)):
			result.message = "DER MIGRATIONSSCHLUND ÖFFNET SICH"
		if portal_clock <= 0.0:
			open_portal(portal_point)
		return
	var points := _unit_points()
	var share: float = portal.hit_fraction(points) if not points.is_empty() else (1.0 if portal.contains(swarm.position) else 0.0)
	if portal.step(delta, share):
		_begin_migration()
		result.ended = true
		return
	if not _is_calm(String(result.message)):
		return
	if share >= TUNING.MIGRATION_SHARE or portal.hold > 0.0:
		result.message = "MIGRATION · %d Prozent" % int(portal.hold * 100.0)
	elif share > 0.0:
		result.message = "MIGRATIONSSCHLUND · ganz hinein!"
	else:
		result.message = "MIGRATIONSSCHLUND · hinein = %s (freiwillig)" % BIOMES.display_name(portal.target_biome).to_upper()


func migrating() -> bool:
	return migration_state == 1


# Entered: the swirl closes, the biome switches behind it, the swirl opens.
func _begin_migration() -> void:
	migration_state = 1
	migration_timer = 0.0
	migration_switched = false
	migration_to = portal.target_biome if portal != null else BIOMES.next_biome(biome_id)
	swarm.clear_focus()
	swarm.set_controls(Vector2.ZERO, false)
	_portal_hum(false)
	_sfx("migration_whoosh", 120)
	_shake(0.35)
	_update_hud("MIGRATION · %s" % BIOMES.display_name(migration_to).to_upper())


func _step_migration(delta: float) -> void:
	migration_timer += delta
	if portal != null:
		var centre := Vector3(portal.position.x, swarm.position.y, portal.position.z)
		swarm.position = swarm.position.lerp(centre, minf(1.0, delta * 5.0))
		portal.step(delta, 1.0)
	if not migration_switched and migration_timer >= TUNING.MIGRATION_SWITCH_AT:
		_arrive()
	if migration_timer >= TUNING.MIGRATION_TRANSITION_SECONDS:
		migration_state = 2
	_update_hud("MIGRATION · %s" % BIOMES.display_name(migration_to).to_upper())


# The new biome: arena restyle (staggered), light, tints, eruptions active but
# never at the arrival spot, a short leader grace; swarm, build, pressure and
# flood carry on unchanged.
func _arrive() -> void:
	migration_switched = true
	var at: Vector3 = portal.position if portal != null else swarm.position
	# Stage 18: the next biome is a new map of the same size; the arrival point
	# stays a clearing inside it.
	var map: Node3D = get_parent().get_node_or_null("Arena") if get_parent() != null else null
	if map != null and map.has_method("prepare_arrival"):
		at = map.prepare_arrival(at)
	_set_world_biome(migration_to, true)
	if map != null and map.has_method("safe_spawn"):
		var landing: Vector3 = map.safe_spawn(Vector3(swarm.position.x, 0.0, swarm.position.z), 1.5)
		swarm.position = Vector3(landing.x, swarm.position.y, landing.z)
	# Stage 18b: the new map has other walls - an objective left on its old spot
	# moves to the nearest open ground (enemies are pushed out as they move).
	if map != null and map.has_method("has_layout") and map.has_layout():
		for objective in [nest, totem]:
			if objective != null and is_instance_valid(objective):
				objective.position = map.safe_spawn(objective.position, 3.0)
	migrations += 1
	arrivals += 1
	# Etappe 17 Welle 2: a new biome cycle guarantees the next ready evolution again.
	evolution.evolution_guarantee = true
	king_cocoon_taken = false
	# One apex per biome visit: the new biome's apex rises APEX_ARRIVAL_DELAY s
	# after the arrival (a disabled apex, state 4, stays disabled).
	if apex_state != 4:
		apex_state = 0
		apex_due = model.elapsed + TUNING.APEX_ARRIVAL_DELAY
	if eruptions != null:
		eruptions.safe_zones.append(Vector4(at.x, 0.0, at.z, TUNING.MIGRATION_SAFE_RADIUS))
		eruptions.clear()
	model.leader_invulnerable = maxf(model.leader_invulnerable, TUNING.MIGRATION_ARRIVAL_GRACE)
	_sync_leader()
	if portal != null:
		portal.queue_free()
		portal = null
	_portal_hum(false)
	_shake(0.25)


# ------------------------------------------------------------ biome tints

# Biome tint (biomes.gd enemy_tints) on the materials an enemy already has:
# creature shaders get their body_tint uniform, shared StandardMaterials are
# swapped for the shared tinted variant (fx_batch cache, one per colour).
func _tint_enemy(enemy: Node, kind: String) -> void:
	if enemy == null:
		return
	var tint: Color = BIOMES.enemy_tint(biome_id, kind)
	for node in enemy.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var material := mesh.material_override
		if material is ShaderMaterial:
			var shader: Shader = (material as ShaderMaterial).shader
			if shader != null and shader.resource_path.contains("creature"):
				(material as ShaderMaterial).set_shader_parameter("body_tint", tint)
			continue
		var base: Variant = mesh.get_meta("base_material") if mesh.has_meta("base_material") else material
		if not (base is StandardMaterial3D):
			continue
		var standard := base as StandardMaterial3D
		if standard.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
			continue
		mesh.set_meta("base_material", standard)
		if tint.a <= 0.0:
			mesh.material_override = standard
			continue
		var color := standard.albedo_color
		var shade := clampf(color.get_luminance() * 2.4, 0.0, 1.4)
		var target := Color(tint.r * shade, tint.g * shade, tint.b * shade, color.a)
		mesh.material_override = FX_BATCH.shared_material(color.lerp(target, tint.a), false, standard.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED, standard.roughness)


func _tint_living_enemies() -> void:
	for target in prey:
		_tint_enemy(target, "prey")
	for target in hunters:
		_tint_enemy(target, "hunter")
	for target in skitters:
		_tint_enemy(target, "skitter")
	for target in leapers:
		_tint_enemy(target, "leaper")
	if boss != null:
		_tint_enemy(boss, "bog_king")


# ---------------------------------------------------------------- Run-Ziele

# Resets every objective and seeds placement from the run seed (0 without config).
func _seed_objectives() -> void:
	objective_rng.seed = hash("mawlings-objectives:%d" % int(config.get("seed", 0)))
	# Swarm divisions draw from their own RNG, seeded per run (deterministic bot runs).
	var herd: Variant = get_node_or_null("../Swarm")
	if herd != null and herd.get("rng") is RandomNumberGenerator:
		(herd.rng as RandomNumberGenerator).seed = hash("mawlings-swarm:%d" % int(config.get("seed", 0)))
	nest = null
	totem = null
	nest_clock = TUNING.NEST_FIRST_SECONDS
	elite_clock = TUNING.ELITE_FIRST_SECONDS
	totem_offered = false
	boss_cycles = 0
	curse_state = 0
	nests_completed = 0
	totems_taken = 0


# Adds the objective HUD component (pointers, totem status) once.
func _ensure_objective_hud() -> void:
	if hud == null or hud.get_node_or_null("hud_objectives") != null or not ResourceLoader.exists(HUD_OBJECTIVES_PATH):
		return
	var component: Control = load(HUD_OBJECTIVES_PATH).new()
	component.name = "hud_objectives"
	hud.add_child(component)


# Doubles biomass and DNA while a Fluch-Totem curse is accepted (until the boss dies).
func reward_multiplier() -> float:
	return TUNING.CURSE_REWARD_MULTIPLIER if curse_state > 0 else 1.0


func _reward_dna(amount: int) -> int:
	return int(round(float(amount) * reward_multiplier()))


# Runs nest, totem and elite schedules inside step(); returns the hint to show.
func _step_objectives(delta: float, message: String) -> String:
	var calm := message.begins_with("Jage") or message.begins_with("Mawlings greifen") or message.begins_with("Biomasse") or message.begins_with("Kristalle") or message.begins_with("Schwarm voll")
	# Brutnest: one at a time; a new one after the previous one hatched.
	if nest == null:
		nest_clock -= delta
		if nest_clock <= 0.0:
			spawn_nest(_objective_position(TUNING.NEST_RADIUS, [totem], "nest"))
	if nest != null:
		var share := 0.0
		var points := _unit_points()
		if points.is_empty():
			share = 1.0 if nest.contains(swarm.position) else 0.0
		else:
			share = nest.hit_fraction(points)
		var full: bool = nest.fill(delta, share, model.population)
		nest.animate(delta, share > 0.0)
		if full:
			_complete_nest()
			return "BRUTNEST GESCHLÜPFT · KRISTALLE SAMMELN!"
		if share > 0.0 and calm:
			message = "Brutnest füllen · %d Prozent" % int(nest.progress * 100.0)
	# Fluch-Totem: rolled once per boss cycle while no boss is alive.
	if boss == null and totem == null and curse_state == 0 and not totem_offered and boss_clock <= TUNING.TOTEM_LEAD_SECONDS and boss_clock >= TUNING.TOTEM_MIN_LEAD_SECONDS:
		totem_offered = true
		if boss_cycles == 0 or objective_rng.randf() < TUNING.TOTEM_CHANCE:
			spawn_totem(_objective_position(TUNING.TOTEM_RADIUS + 0.6, [nest], "totem"))
	if totem != null:
		if totem.hold_step(delta, swarm.position):
			_accept_curse()
			return "FLUCH ANGENOMMEN · BEUTE ×2 BIS ZUM BOSS-TOD"
		if totem.inside and calm:
			message = "Fluch-Totem halten: Boss stärker · Beute ×2"
	# Elite hunter: crowned, tougher, guaranteed Alpha-Kern.
	elite_clock -= delta
	if elite_clock <= 0.0:
		elite_clock = TUNING.ELITE_INTERVAL_SECONDS
		spawn_elite(_spawn_position(9.0))
	if curse_state > 0 and message.begins_with("Jage"):
		message = "Fluch aktiv · Beute ×2"
	return message


func spawn_nest(location: Vector3) -> Node3D:
	if nest != null:
		nest.queue_free()
	nest = BROOD_NEST.new()
	nest.name = "Brood nest"
	nest.position = Vector3(location.x, 0.0, location.z)
	add_child(nest)
	FX.ring(self, nest.position, Color(NEST_COLOR, 0.9), 0.5, TUNING.NEST_RADIUS + 1.0, 0.7)
	return nest


func spawn_totem(location: Vector3) -> Node3D:
	if totem != null:
		totem.queue_free()
	totem = CURSE_TOTEM.new()
	totem.name = "Curse totem"
	totem.position = Vector3(location.x, 0.0, location.z)
	add_child(totem)
	FX.ring(self, totem.position, Color(CURSE_COLOR, 0.85), 0.3, 3.0, 0.6)
	return totem


func spawn_elite(location: Vector3) -> Node3D:
	var target := _spawn_hunter(location)
	target.name = "Elite hunter"
	target.make_elite(TUNING.ELITE_HEALTH_MULTIPLIER)
	FX.ring(self, target.position, Color("f5c86a"), 0.4, 3.2, 0.6)
	return target


# Full nest: bursts into crystals (they stay until collected) plus DNA crystals.
func _complete_nest() -> void:
	var location: Vector3 = nest.position
	nest.queue_free()
	nest = null
	nest_clock = TUNING.NEST_RESPAWN_SECONDS
	var total: float = (TUNING.NEST_BIOMASS + TUNING.NEST_BIOMASS_GROWTH * float(nests_completed)) * evolution.biomass_multiplier() * reward_multiplier()
	nests_completed += 1
	_add_remains(location, "nest")
	drop_loot(location, total, _reward_dna(TUNING.NEST_DNA), "boss")
	FX.ring(self, location, Color(NEST_COLOR, 0.95), 0.6, TUNING.NEST_RADIUS + 3.0, 0.8)
	FX.ring(self, location, Color("f5c86a", 0.8), 0.3, TUNING.NEST_RADIUS, 0.55)
	_shake(0.2)
	_sfx("grow")
	_sfx("evolve", 60)


func _accept_curse() -> void:
	var location: Vector3 = totem.position
	totem.queue_free()
	totem = null
	curse_state = 1
	totems_taken += 1
	FX.ring(self, location, Color(CURSE_COLOR, 0.95), 0.4, 5.0, 0.7)
	FX.ring(self, location, Color("b07ae8", 0.8), 0.2, 3.0, 0.5)
	_shake(0.15)
	_sfx("mutate", 50)


# A boss spawn closes the totem window; an accepted curse empowers this boss.
func _on_boss_spawned(target: Node3D) -> void:
	boss_cycles += 1
	totem_offered = false
	if totem != null:
		FX.ring(self, totem.position, Color("b07ae8", 0.6), 1.0, 2.5, 0.5)
		totem.queue_free()
		totem = null
	if curse_state != 1:
		return
	curse_state = 2
	target.set_meta("cursed", true)
	target.health *= TUNING.CURSE_BOSS_MULTIPLIER
	target.max_health = target.health
	var aura_material: Material = FX_BATCH.shared_material(Color(CURSE_COLOR, 0.75), true, true)
	var ring := _piece(target, _alpha_core_parts().aura, aura_material, Vector3(0.0, 0.12, 0.0))
	ring.name = "Curse aura"
	ring.scale = Vector3(1.0, 0.3, 1.0)


# Seeded point 14-22 m from the swarm on open ground, away from the start and
# from the other objective. `clearance` is the radius that must stay open.
# Stage 18b: on the path map a nest / totem sits in a clearing of its type -
# the nearest slot at least OBJECTIVE_MIN_DISTANCE away, never the last one.
func _objective_position(clearance: float, avoid: Array, kind: String = "") -> Vector3:
	var arena: Node3D = get_parent().get_node("Arena")
	var slots: Array = arena.poi_slots(kind) if kind != "" and arena.has_method("poi_slots") else []
	var pick := Vector3.INF
	for spot in slots:
		var flat := Vector3(spot.x, 0.0, spot.z)
		if flat.distance_to(Vector3(swarm.position.x, 0.0, swarm.position.z)) < TUNING.OBJECTIVE_MIN_DISTANCE:
			continue
		if _last_objective.get(kind, Vector3.INF) == flat and slots.size() > 1:
			continue
		var blocked := false
		for other in avoid:
			if other != null and is_instance_valid(other) and other.position.distance_to(flat) < 9.0:
				blocked = true
		if not blocked and (not pick.is_finite() or swarm.position.distance_to(flat) < swarm.position.distance_to(pick)):
			pick = flat
	if pick.is_finite():
		_last_objective[kind] = pick
		return arena.safe_spawn(pick, clearance)
	var fallback := Vector3.ZERO
	for attempt in 40:
		var angle := objective_rng.randf() * TAU
		var distance := objective_rng.randf_range(TUNING.OBJECTIVE_MIN_DISTANCE, TUNING.OBJECTIVE_MAX_DISTANCE)
		var candidate: Vector3 = swarm.position + Vector3(cos(angle), 0.0, sin(angle)) * distance
		candidate.y = 0.0
		if attempt == 0:
			fallback = candidate
		if Vector2(candidate.x, candidate.z).length() < TUNING.OBJECTIVE_START_CLEARANCE:
			continue
		var blocked := false
		for other in avoid:
			if other != null and is_instance_valid(other) and other.position.distance_to(candidate) < 9.0:
				blocked = true
		if blocked or not _zone_open(arena, candidate, clearance):
			continue
		return candidate
	return arena.safe_spawn(fallback, clearance)


func _zone_open(arena: Node3D, center: Vector3, clearance: float) -> bool:
	if not arena.is_open(center, minf(clearance, 1.8)):
		return false
	for index in 8:
		var angle := TAU * float(index) / 8.0
		if not arena.is_open(center + Vector3(cos(angle), 0.0, sin(angle)) * clearance * 0.85, 0.3):
			return false
	return true


# Objective state for hud_objectives.gd (screen pointers are INF when on screen).
func _objective_hud() -> Dictionary:
	return {
		"nest_active": nest != null,
		"nest_progress": nest.progress if nest != null else 0.0,
		"nest_inside": nest != null and nest.inside_share > 0.0,
		"nest_pointer": _edge_pointer(nest.position + Vector3.UP * 1.0) if nest != null and _found(nest.position) else Vector2.INF,
		"totem_active": totem != null,
		"totem_hold": totem.hold if totem != null else 0.0,
		"totem_pointer": _edge_pointer(totem.position + Vector3.UP * 1.5) if totem != null and _found(totem.position) else Vector2.INF,
		"totem_screen": _screen_point(totem.position + Vector3.UP * 1.2) if totem != null else Vector2.INF,
		"curse": curse_state,
		"reward_multiplier": reward_multiplier(),
		"nests": nests_completed,
		# Stage 10: apex bar/pointer, migration pointer, swirl and banners.
		"apex_state": apex_state,
		"apex_warning": apex_clock / TUNING.APEX_WARNING_SECONDS if apex_state == 1 else 0.0,
		"apex_health": apex.health if apex != null else 0.0,
		"apex_max_health": apex.max_health if apex != null else 0.0,
		"apex_phase": int(apex.phase) if apex != null else 1,
		"apex_vulnerable": apex != null and apex.state == APEX_BOSS.State.EXHAUSTED,
		"apex_pointer": _edge_pointer(apex.position + Vector3.UP * 3.0) if apex != null else Vector2.INF,
		"apex_victories": apex_victories,
		# Second apex: the HUD can name the living / risen / defeated apex.
		"apex_kind": apex_kind,
		"apex_name": apex_display_name(apex_kind).to_upper(),
		"portal_active": portal != null,
		"portal_hold": portal.hold if portal != null else 0.0,
		"portal_target": BIOMES.display_name(portal.target_biome).to_upper() if portal != null else "",
		"portal_pointer": _edge_pointer(portal.position + Vector3.UP * 1.5) if portal != null else Vector2.INF,
		"migration": clampf(migration_timer / TUNING.MIGRATION_TRANSITION_SECONDS, 0.0, 1.0) if migration_state == 1 else -1.0,
		"migration_screen": _screen_point(portal.position) if portal != null else Vector2.INF,
		"migration_switch": TUNING.MIGRATION_SWITCH_AT / TUNING.MIGRATION_TRANSITION_SECONDS,
		"migration_to": migration_to,
		"arrivals": arrivals,
		"biome_title": String(BIOMES.get_data(biome_id).get("title", "")),
		"biome_id": biome_id,
	}


# ---------------------------------------------------------------- HUD

func _update_hud(message: String) -> void:
	hud.evolution = evolution
	hud.population = model.population
	hud.biomass_bank = model.biomass_bank
	hud.corpse_count = loot.count() if loot != null else 0
	hud.kills = model.kills
	hud.hunters = hunters.size()
	hud.skitters = skitters.size()
	if "leapers" in hud:
		hud.set("leapers", leapers.size())
	if "alpha_cores" in hud:
		hud.set("alpha_cores", evolution.alpha_cores)
		hud.set("evolve_flash", evolve_flash)
		hud.set("evolve_name", evolve_name)
		hud.set("run_stats", run_stats() if model.extinct else {})
	hud.boss_health = boss.health if boss != null else 0.0
	hud.boss_max_health = boss.max_health if boss != null else 0.0
	hud.boss_pointer = _boss_pointer()
	hud.boss_vulnerable = boss != null and boss.state == BOG_KING.State.RECOVERY
	hud.elapsed = model.elapsed
	hud.pressure = model.pressure()
	hud.extinct = model.extinct
	hud.paused = paused
	hud.peak_population = model.peak_population
	hud.consumed_biomass = model.consumed_biomass
	hud.hit_feedback = hit_feedback
	hud.last_loss = last_loss
	# Stage 09 leader HUD (drawn by hud_top/hud_overlays).
	_set_hud_value("leader_hp", model.leader_hp)
	_set_hud_value("leader_max_hp", model.leader_max_hp)
	_set_hud_value("leader_invulnerable", model.leader_invulnerable > 0.0)
	_set_hud_value("milestone", milestone_value)
	_set_hud_value("amber", model.amber)
	hud.set_meta("leader_heal", {"amount": leader_heal_shown, "age": model.elapsed - leader_heal_at})
	_set_hud_value("strain_id", String(config.get("strain_id", META_DATA.STRAIN_ORDER[0])))
	_set_hud_value("last_loss_fraction", last_loss_fraction)
	hud.hint = message
	_update_map_hud()
	hud.set_meta("kill_popups", _popup_screen())
	hud.set_meta("king_moments", king_moments)
	hud.set_meta("flood", _flood_hud())
	var objectives := _objective_hud()
	hud.set_meta("objectives", objectives)
	if "objectives" in hud:
		hud.set("objectives", objectives)
	hud.set_meta("lure_flash", lure_flash)
	hud.set_meta("magnet_radius", magnet_radius())
	hud.set_meta("arsenal_world", _arsenal_hud())


# Edge-of-screen position pointing at an off-screen Bog King, or INF when visible.
func _boss_pointer() -> Vector2:
	if boss == null:
		return Vector2.INF
	return _edge_pointer(boss.position + Vector3.UP * 2.0)


# Screen position of a world point, or INF when behind the camera.
func _screen_point(point: Vector3) -> Vector2:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null or camera.is_position_behind(point):
		return Vector2.INF
	return camera.unproject_position(point)


# Edge-of-screen marker position for a world point, or INF when it is on screen.
# Stage 18c: a place only gets an edge pointer once the swarm discovered it
# (exploration map); the classic map and announced bosses always point.
func _found(point: Vector3) -> bool:
	var arena: Node = get_parent().get_node_or_null("Arena") if get_parent() != null else null
	if arena == null or not arena.has_method("has_layout") or not arena.has_layout():
		return true
	return arena.is_discovered(point)


func _edge_pointer(point: Vector3) -> Vector2:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return Vector2.INF
	var view: Vector2 = hud.size
	var screen := camera.unproject_position(point)
	var behind := camera.is_position_behind(point)
	if not behind and Rect2(Vector2(20, 20), view - Vector2(40, 40)).has_point(screen):
		return Vector2.INF
	var center := view * 0.5
	var direction := screen - center
	if behind:
		direction = -direction
	if direction.length_squared() < 1.0:
		return Vector2.INF
	# Keep the marker clear of the top panels and the thumb controls.
	var area := Rect2(Vector2(56, 330), view - Vector2(112, 700))
	var half := area.size * 0.5
	var reach := minf(half.x / maxf(0.001, absf(direction.x)), half.y / maxf(0.001, absf(direction.y)))
	return area.get_center() + direction * reach


# ---------------------------------------------------------------- per-animal combat

# Visible Mawlings in world space; the share of them stands for the whole
# logical population when it exceeds the visual limit.
func _unit_points() -> PackedVector3Array:
	if not unit_points_valid:
		unit_points = swarm.unit_world_points()
		unit_points_valid = true
	return unit_points


# Share of the swarm's bite that reaches a target (0 = out of reach, 1 = full).
# A big `target` with body_distance(point) (Moosschlund, Aschenkröte) is measured
# to its body rim: an animal bites within MELEE_REACH of the rim.
func melee_factor(location: Vector3, kind: String, contact_range: float, target: Node3D = null) -> float:
	var centre_distance := Vector2(location.x - swarm.position.x, location.z - swarm.position.z).length()
	var points := _unit_points()
	if points.is_empty():
		return 1.0 if centre_distance < contact_range else 0.0
	var rim: bool = target != null and target.has_method("body_distance")
	var reach: float = MELEE_REACH + float(BODY_RADIUS.get(kind, 0.5))
	var reach_squared := reach * reach
	var biting := 0
	for point in points:
		if rim:
			if float(target.body_distance(point)) <= MELEE_REACH:
				biting += 1
			continue
		var dx := point.x - location.x
		var dz := point.z - location.z
		if dx * dx + dz * dz <= reach_squared:
			biting += 1
	var factor := clampf(float(biting) / float(points.size()) / MELEE_FULL_SHARE, 0.0, 1.0)
	if centre_distance < contact_range:
		factor = maxf(factor, MELEE_MIN_ENGAGE)
	return factor


# Scales an enemy's resolved area attack by the share of visible animals inside
# its locked area; only those animals fall. True when the run ended.
func _resolve_area_hit(enemy: Node3D, fallback_impact: Vector3, shake_amount: float) -> bool:
	var power: int = enemy.get("resolved_power")
	if power <= 0:
		return false
	if attack_forms != null and (enemy == boss or enemy == apex) and attack_forms.has_method("impact_fx"):
		attack_forms.impact_fx(fallback_impact, TUNING.BOSS_ATTACK_RADIUS if enemy == boss else float(enemy.get("body_radius")) * 1.5 if "body_radius" in enemy else 4.5)  # VFX V1: Schockwelle
	if enemy == boss and enemy.has_meta("cursed"):
		power = ceili(float(power) * TUNING.CURSE_BOSS_MULTIPLIER)
	var points := _unit_points()
	var inside := PackedInt32Array()
	var impact := Vector3.ZERO
	var share := 0.0
	# Stage 09: the leader (index 0) inside loses 1 LP instead of dying; the loss of
	# the others is scaled by the followers inside only.
	var leader_struck := false
	var follower_share := 0.0
	if points.is_empty():
		share = 1.0 if enemy.contains(swarm.position) else 0.0
		leader_struck = share > 0.0
		follower_share = share * float(model.population - 1) / float(maxi(1, model.population))
		impact = fallback_impact
	else:
		for index in points.size():
			if enemy.contains(points[index]):
				impact += points[index]
				if index == 0:
					leader_struck = true
				else:
					inside.append(index)
		var total_inside := inside.size() + (1 if leader_struck else 0)
		share = float(total_inside) / float(points.size())
		follower_share = float(inside.size()) / float(points.size())
		impact = impact / float(total_inside) if total_inside > 0 else fallback_impact
	last_hit_share = share
	var loss := ceili(float(power) * follower_share - 0.0001)
	if loss <= 0 and not leader_struck:
		return false
	if swarm.has_method("prefer_removal") and not inside.is_empty():
		swarm.prefer_removal(inside)
	# A Nibbler snap never takes the leader's last LP (fair lone start).
	return _apply_hit(maxi(0, loss), impact, shake_amount, enemy, leader_struck, enemy is PREY)


# ---------------------------------------------------------------- collect popups

# Etappe 16 (S5): collected biomass/DNA add up into ONE number at the swarm
# ("+36") while crystals keep arriving within POPUP_MERGE_SECONDS; every new
# crystal restarts the little pop (hop) of the number. Afterwards it rises and fades.
func _add_collect_popup(biomass: float, dna: int, amber: int = 0) -> void:
	if biomass <= 0.0 and dna <= 0 and amber <= 0:
		return
	var now: float = model.elapsed
	if not kill_popups.is_empty():
		var last: Dictionary = kill_popups[-1]
		if now - float(last.get("last", -INF)) <= POPUP_MERGE_SECONDS:
			last.sum = float(last.sum) + biomass
			last.biomass = int(round(float(last.sum)))
			last.dna = int(last.dna) + dna
			last.amber = int(last.get("amber", 0)) + amber
			last.last = now
			last.age = minf(float(last.age), 0.03)
			last.at = _popup_anchor()
			return
	kill_popups.append({"at": _popup_anchor(), "dna": dna, "biomass": int(round(biomass)), "amber": amber, "sum": biomass, "age": 0.0, "last": now})
	while kill_popups.size() > POPUP_MAX:
		kill_popups.pop_front()


# Just above the swarm (screen-up is -Z), so the number never hides the animals.
func _popup_anchor() -> Vector3:
	var reach: float = 1.6 + 0.35 * sqrt(float(model.population))
	return swarm.position + Vector3(0.0, 0.0, -minf(reach, 4.5))


func _age_popups(delta: float) -> void:
	var now: float = model.elapsed
	for index in range(kill_popups.size() - 1, -1, -1):
		var popup: Dictionary = kill_popups[index]
		popup.age += delta
		# A growing number follows the swarm; a finished one floats away.
		if now - float(popup.get("last", -INF)) <= POPUP_MERGE_SECONDS:
			popup.at = _popup_anchor()
		if popup.age >= POPUP_SECONDS:
			kill_popups.remove_at(index)


# Screen positions for the HUD (same projection as the boss pointer).
func _popup_screen() -> Array:
	var result: Array = []
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return result
	for popup in kill_popups:
		var point: Vector3 = popup.at + Vector3.UP * 1.4
		if camera.is_position_behind(point):
			continue
		result.append({"screen": camera.unproject_position(point), "dna": popup.dna, "biomass": popup.biomass, "amber": int(popup.get("amber", 0)), "t": popup.age / POPUP_SECONDS})
	return result


# ---------------------------------------------------------------- loot & magnet (Etappe 16)

## Magnet radius around the swarm centre: grows with the swarm, x Witterung
## (meta) x Lockduft (trait), x MAGNET_RALLY while Rally is held.
func magnet_radius() -> float:
	# Etappe 17b: beyond 250 animals the radius only grows logarithmically.
	var pop := float(maxi(1, model.population))
	var base := TUNING.MAGNET_BASE + TUNING.MAGNET_PER_ROOT * sqrt(minf(pop, 250.0)) + TUNING.MAGNET_PER_DOUBLING * log(maxf(1.0, pop / 250.0)) / log(2.0)
	var radius := base * evolution.magnet_multiplier()
	if swarm != null and swarm.rally_pressed:
		radius *= TUNING.MAGNET_RALLY
	return radius


# Magnet, flights and arrivals: biomass grows the swarm (x harvest_multiplier:
# Schnelle Brut / Verdauung), DNA feeds the mutation offer. A full swarm leaves
# biomass lying. Returns the hint to show.
func _step_loot(delta: float, message: String) -> String:
	if loot == null:
		return message
	loot.flood = flood_state == 2
	# Stage 18c: a Mawling touching an amber node breaks it into crystals.
	if loot_nodes != null and not model.extinct:
		loot_nodes.step(swarm.position, _unit_points())
	var room: bool = model.biomass_capacity() > 0.0
	var got: Dictionary = loot.step(delta, swarm.position, magnet_radius(), _unit_points(), room)
	if loot.lures_taken > 0:
		for index in loot.lures_taken:
			_lure_moment()
		message = "LOCKRUF · ALLE KRISTALLE KOMMEN!"
	if int(got.crystals) > 0:
		_credit_loot(got)
		collect_hint = 1.0
	if not room and loot.lying_count() > 0 and _is_calm(message):
		return "Schwarm voll — Biomasse bleibt liegen"
	if collect_hint > 0.0 and message.begins_with("Jage"):
		return "Kristalle sammeln · Rally vergrößert den Sog"
	return message


## Credits every crystal on the map at once (tests and captures; a full swarm
## keeps its biomass lying).
func collect_loot_now() -> void:
	if loot == null:
		return
	var got: Dictionary = loot.take_all(model.biomass_capacity() > 0.0)
	if int(got.crystals) > 0:
		_credit_loot(got)
	_update_hud("")


# Arrived crystals: biomass grows the swarm (x harvest_multiplier), a rest
# beyond the cap lies down again at the swarm, DNA feeds the mutation offer;
# one growing popup and the rising collect sound.
func _credit_loot(got: Dictionary) -> void:
	crystals_collected += int(got.crystals)
	var biomass: float = float(got.biomass) * evolution.harvest_multiplier()
	var taken := 0.0
	if biomass > 0.0:
		var grown_from: int = model.population
		taken = model.absorb(biomass)
		if model.population != grown_from:
			swarm.set_population(model.population)
			if model.population > grown_from:
				_on_growth(model.population - grown_from)
		# Arrived while the swarm filled up: the rest lies down again at the swarm.
		if biomass - taken > 0.01:
			loot.drop(LOOT.Kind.BIOMASS, biomass - taken, swarm.position, swarm.position + Vector3(drop_rng.randf_range(-1.0, 1.0), 0.0, drop_rng.randf_range(-1.0, 1.0)) * 1.5)
	var dna: int = got.dna
	var amber := int(got.get("amber", 0))
	if amber > 0:
		model.amber += amber
		model.amber_collected += amber
	_add_collect_popup(taken, dna, amber)
	_collect_sound(int(got.bio_crystals) + int(got.get("coins", 0)), int(got.dna_crystals))
	if attack_forms != null and attack_forms.has_method("pickup_fx"):
		attack_forms.pickup_fx(int(got.bio_crystals), int(got.dna_crystals))  # VFX V1
	if dna > 0:
		_award_dna(dna)


# Rising collect chain: every sound in quick succession one pentatonic step
# higher (at most one per COLLECT_SOUND_MS; biomass and DNA alternate).
func _collect_sound(bio_crystals: int, dna_crystals: int) -> void:
	var now_ms := Time.get_ticks_msec()
	if now_ms - collect_sound_ms < COLLECT_SOUND_MS:
		return
	collect_sound_ms = now_ms
	if model.elapsed - collect_chain_at <= COLLECT_CHAIN_SECONDS:
		collect_chain = mini(collect_chain + 1, COLLECT_STEPS.size() - 1)
	else:
		collect_chain = 0
	collect_chain_at = model.elapsed
	var pitch := pow(2.0, float(COLLECT_STEPS[collect_chain]) / 12.0)
	var player := _sfx_node()
	if player == null:
		return
	var id := "collect_dna" if dna_crystals > 0 and (bio_crystals == 0 or collect_chain % 2 == 1) else "collect_bio"
	player.play(id, 0.0, 0.02, pitch)


## Drops a Lockruf beside `location` (guaranteed: elite, Bog King, apex, each
## new flood stage). Returns the lure node.
func drop_lure(location: Vector3) -> Node3D:
	if loot == null or model.extinct:
		return null
	var offset := Vector3(-1.6, 0.0, 0.0).rotated(Vector3.UP, drop_rng.randf() * TAU)
	var node: Node3D = loot.add_lure(location + offset)
	FX.ring(self, node.position, Color(LOOT.LURE_COLOR, 0.85), 0.3, 3.0, 0.7)
	return node


# Rare Lockruf from ordinary hunters/skitters/leapers once enough crystals lie around.
func _maybe_lure(location: Vector3) -> void:
	# Etappe 17: Magnetkern (Relikt) macht Lockrufe häufiger.
	if loot != null and loot.lying_count() >= TUNING.LURE_MIN_LYING and drop_rng.randf() < TUNING.LURE_CHANCE * evolution.lure_multiplier():
		drop_lure(location)


# Lockruf collected: every crystal on the map flies in as a chain.
func _lure_moment() -> void:
	lures_collected += 1
	lure_flash = 1.0
	var called: int = loot.vacuum(swarm.position, _unit_points(), model.biomass_capacity() > 0.0)
	# A short glow: one ring runs out over the map, one gold pulse at the swarm.
	FX.ring(self, swarm.position, Color(LOOT.LURE_COLOR, 0.55), 1.0, 11.0, 0.7)
	FX.ring(self, swarm.position, Color(LOOT.BIO_GLOW, 0.7), 0.3, 5.0, 0.5)
	_shake(0.25)
	_sfx("lure", 90)
	if called > 0:
		# The chain starts one step up: it is already a celebration.
		collect_chain = 2
		collect_chain_at = model.elapsed


# Bog King eaten: big HUD moment, sound and vibration; Main adds slow motion and zoom.
func _king_moment(location: Vector3) -> void:
	king_moments += 1
	# A real fanfare instead of evolve + the music stinger "king".
	_sfx("fanfare", 120)
	var main := get_parent()
	if main != null and main.has_method("king_moment"):
		main.king_moment(location)


# Resolves one announced hit. Returns true when the run ended by extinction.
# `loss` counts followers only (never the leader); `leader_struck` costs the
# leader 1 LP under the rules in RunModel.apply_hit() (stage 09); a `nonlethal`
# source never takes its last LP.
func _apply_hit(loss: int, impact: Vector3, shake_amount: float, attacker: Node3D = null, leader_struck: bool = false, nonlethal: bool = false, source: String = "") -> bool:
	# Etappe 17 Welle 2 - Chitinschild: the leader cannot be struck while it lasts.
	if leader_struck and bool(evolution.boosts.get("leader_immune", false)):
		leader_struck = false
	var damage_scale := difficulty_scale(enemy_damage)
	if loss > 0 and damage_scale != 1.0:
		loss = maxi(1, ceili(float(loss) * damage_scale))
	var before: int = model.population
	var outcome: Dictionary = model.apply_hit(evolution.loss_after_armor(loss, swarm.rally_pressed), leader_struck, nonlethal, leader_damage(attacker, source))
	var leader_state: String = outcome.leader
	var leader_lost_hp: bool = leader_state in ["hit", "swap", "extinct"]
	if int(outcome.lost) <= 0 and not leader_lost_hp:
		# Invulnerable leader and nobody else inside: nothing happens.
		return false
	unit_points_valid = false
	last_loss = int(outcome.lost)
	last_loss_fraction = float(last_loss) / float(maxi(1, before))
	if leader_state == "swap" and swarm.has_method("promote_leader"):
		swarm.promote_leader()
	swarm.set_population(model.population)
	swarm.react_to_hit(last_loss, impact)
	_sync_leader()
	if leader_lost_hp:
		if swarm.has_method("leader_hit"):
			swarm.leader_hit(impact)
		_sfx("leader_hit", 45)
	if leader_state == "swap":
		_sfx("leader_swap", 80)
	if last_loss > 0:
		# Death squeal, louder when the loss is a big share of the swarm.
		_sfx("death", 0, lerpf(-6.0, 0.0, clampf(last_loss_fraction * 3.0, 0.0, 1.0)))
		# Painful share of the swarm: extra "loss" hit (sfx rule gap 700 ms).
		if last_loss_fraction >= 0.1:
			_sfx("loss")
		# Rückeroberung: the fallen leave a little biomass where they fell.
		_drop_fallen_biomass(impact, last_loss)
	# The heartbeat loop for the last animal is started/stopped by swarm.gd.
	var main := get_parent()
	if main != null and main.has_method("hitstop"):
		main.hitstop(clampf(maxf(last_loss_fraction, 0.35 if leader_lost_hp else 0.0), 0.0, 1.0))
	hit_feedback = 1.2
	_shake(shake_amount)
	_sfx("hit", 30)
	if attack_forms != null and attack_forms.has_method("on_swarm_hit") and not model.extinct:
		attack_forms.on_swarm_hit(attacker, last_loss)
	# Etappe 10 (INHALT) - Dornenhaut: the attacker (and brood close by) takes thorn damage.
	if attack_forms != null and attack_forms.has_method("reflect_thorns") and evolution.has_method("thorn_damage") and not model.extinct:
		attack_forms.reflect_thorns(attacker, evolution.thorn_damage(last_loss, leader_struck), impact)
	if model.extinct:
		swarm.clear_focus()
		swarm.set_controls(Vector2.ZERO, false)
		hud.clear_pointers()
		if attack_forms != null and attack_forms.has_method("clear"):
			attack_forms.clear()
		_store_result()
		_sfx("extinct", 120)
		var player := _sfx_node()
		if player != null and player.has_method("stop_ambience"):
			player.stop_ambience()
		_portal_hum(false)
		var music := _music_node()
		if music != null:
			music.stop()
		_update_hud("Ausgestorben")
		return true
	return false


# ---------------------------------------------------------------- leader (stage 09)

# Pushes leader LP / max / invulnerability to the swarm when it changed.
func _sync_leader() -> void:
	var key := Vector3i(model.leader_hp, model.leader_max_hp, 1 if model.leader_invulnerable > 0.0 else 0)
	if key == leader_state_key:
		return
	leader_state_key = key
	if swarm.has_method("set_leader_state"):
		swarm.set_leader_state(key.x, key.y, key.z == 1)


# Etappe 10 (INHALT) - Regeneration: every kill counts towards leader LP
# (evolution.note_kills); healing is capped at leader_max_hp.
# Etappe 10 Teil 2: Moorbrut zählt nur `weight` Kill, höchstens 1 LP je REGEN_GAP s.
# Etappe 17: der Kill-Hook bündelt auch Königszahnkette (in note_kills) sowie
# Sporenherz/Pilzreich (Sporenwolke an `at`, attack_forms.on_kill).
func _note_kills(count: int, weight: float = 1.0, at: Vector3 = Vector3.INF) -> void:
	if count <= 0 or model.extinct or not evolution.has_method("note_kills"):
		return
	if at != Vector3.INF and attack_forms != null and attack_forms.has_method("on_kill"):
		attack_forms.on_kill(at, evolution.roll_kill_burst())
	var healed: int = evolution.note_kills(count, weight, model.elapsed)
	if healed <= 0:
		return
	if _heal_leader(healed) > 0:
		FX.ring(self, swarm.position, Color(0.6, 1.0, 0.55, 0.85), 0.4, 2.6, 0.5)
		_sfx("regen", 15)


# New Mawlings grew from biomass: cell division, milestones (+1 LP per 25).
func _on_growth(count: int) -> void:
	# Etappe 17 – Zellteilungs-Hook (Zwillingsbrut): jede N-te Teilung ergibt ein
	# zweites Tier (ohne Biomasse-Kosten, bis zum Limit).
	var twins: int = evolution.note_divisions(count) if evolution.has_method("note_divisions") else 0
	if twins > 0:
		var before: int = model.population
		model.absorb(float(twins) * TUNING.BIOMASS_PER_MAWLING)
		if model.population > before:
			count += model.population - before
			swarm.set_population(model.population)
	if swarm.has_method("split_new_units"):
		# The plop plays in swarm.gd at the moment each cell pinches off (throttled).
		swarm.split_new_units(count)
	var reached := model.take_milestone()
	if reached > 0:
		milestone_value = reached
		milestone_timer = MILESTONE_SHOW_SECONDS
		_sfx("milestone", 60)
	_sync_leader()


# Rückeroberung: fallen Mawlings leave FALLEN_BIOMASS each as one crystal where
# they fell (it joins crowded crystals close by like any other).
func _drop_fallen_biomass(location: Vector3, count: int) -> void:
	if count <= 0 or model.extinct or loot == null:
		return
	var amount := TUNING.FALLEN_BIOMASS * float(count)
	var arena: Node3D = get_parent().get_node_or_null("Arena")
	var spot := location
	if arena != null and arena.has_method("safe_spawn"):
		spot = arena.safe_spawn(location, 0.4)
	spot.y = 0.0
	loot.drop(LOOT.Kind.BIOMASS, amount, spot, spot + Vector3(drop_rng.randf_range(-0.8, 0.8), 0.0, drop_rng.randf_range(-0.8, 0.8)))


# True when a Nibbler other than `except` is announcing a snap.
func _nibbler_snapping(except: Node3D) -> bool:
	for other in prey:
		if other != except and int(other.get("snap_state")) == 1:
			return true
	return false


func _set_hud_value(key: String, value: Variant) -> void:
	if key in hud:
		hud.set(key, value)
	else:
		hud.set_meta(key, value)


# RunStats for the meta layer (contract in stages/03_progression.md).
func run_stats() -> Dictionary:
	var mutations := {}
	for id in evolution.ranks:
		if evolution.ranks[id] > 0:
			mutations[id] = evolution.ranks[id]
	return {
		"strain_id": str(config.get("strain_id", "")),
		"biome_id": str(config.get("biome_id", "")),
		"difficulty": int(config.get("difficulty", 0)),
		"seconds": model.elapsed,
		"peak_population": model.peak_population,
		"final_population": model.population,
		"kills": model.kills,
		"kills_by_type": model.kills_by_type.duplicate(),
		"biomass": model.consumed_biomass,
		"lost": model.lost_population,
		"bosses": model.bosses,
		"evolutions": Array(evolution.evolutions),
		"mutations": mutations,
		"used_rally": model.used_rally,
		"nests": nests_completed,
		"totems": totems_taken,
		"flood_reached": flood_reached,
		"flood_seconds": flood_seconds(),
		"horde_kills": horde_kills,
		"leader_swaps": model.leader_swaps,
		# Etappe 16: loot crystals collected, Lockrufe taken.
		"crystals": crystals_collected,
		# Etappe 17 Welle 2: Bernstein collected this run (it expires with the run).
		"amber": model.amber_collected,
		"lures": lures_collected,
		# Stage 10: apex and migration.
		"apex_kills": apex_kills,
		"toad_kills": toad_kills,
		"worm_kills": worm_kills,
		"biomes_visited": biomes_visited.size(),
		"biome_list": Array(biomes_visited),
		"migrations": migrations,
		"biome_seconds": biome_seconds.duplicate(),
		# Minimap stage: named regions entered (per biome) and explored chunks.
		"regions_visited": regions_seen.size(),
		"chunks_explored": explored.size(),
		"seed": int(config.get("seed", 0)),
		"daily": bool(config.get("daily", false)),
		"daily_date": str(config.get("daily_date", "")),
	}


# Hands the finished run to the menu exactly once.
func _store_result() -> void:
	if result_stored:
		return
	result_stored = true
	if not ResourceLoader.exists(SESSION_PATH):
		return
	var session: Script = load(SESSION_PATH)
	if session != null:
		session.set("last_result", run_stats())


# The nearest living threat or prey within reach pulls the swarm visually.
func _consider_focus(location: Vector3, reach: float) -> void:
	var distance := location.distance_to(swarm.position)
	if distance < reach and distance < focus_distance:
		focus_distance = distance
		focus_point = location
		focus_mode = 1


# Adaptive music (scripts/music.gd, node "Music" under Main; absent in tests).
func _music_node() -> Node:
	return get_parent().get_node_or_null("Music") if get_parent() != null else null


func _music_step() -> void:
	var music := _music_node()
	if music != null:
		music.set_intensity(model.pressure(), flood_state == 2, boss != null or apex != null)


func _music_cue(id: String) -> void:
	var music := _music_node()
	if music != null:
		music.stinger(id)


func _sfx_node() -> Node:
	return get_parent().get_node_or_null("Sfx") if get_parent() != null else null


func _sfx(id: String, vibrate_ms: int = 0, volume_db: float = 0.0) -> void:
	var player := _sfx_node()
	if player == null:
		return
	player.play(id, volume_db)
	if vibrate_ms > 0:
		player.vibrate(vibrate_ms)


# "threat" once per pressure doubling (the flood start adds its own).
func _audio_threat() -> void:
	var doublings := floori(model.elapsed / maxf(1.0, model.pressure_doubling))
	if doublings > threat_doublings:
		threat_doublings = doublings
		_sfx("threat")


# Loop "portal_hum" while the Migrationsschlund is open (Sfx start_loop/stop_loop).
func _portal_hum(on: bool) -> void:
	var player := _sfx_node()
	if player == null or not player.has_method("start_loop"):
		return
	if on:
		player.start_loop("portal_hum")
	else:
		player.stop_loop("portal_hum")


# Sound cues from state changes, so enemy scripts stay free of audio code.
func _audio_step(delta: float, population_before: int) -> void:
	# Stage 09: with cell division _on_growth() plays "split" instead.
	if model.population > population_before and not swarm.has_method("split_new_units"):
		_sfx("grow")
	bite_clock = maxf(0.0, bite_clock - delta)
	if melee_contact and bite_clock <= 0.0:
		bite_clock = 0.22
		_sfx("bite")
	var enemies: Array = []
	enemies.append_array(hunters)
	enemies.append_array(skitters)
	enemies.append_array(leapers)
	if boss != null:
		enemies.append(boss)
	if apex != null:
		enemies.append(apex)
	for enemy in enemies:
		var key: int = enemy.get_instance_id()
		var state: int = enemy.get("state")
		var before: int = enemy_states.get(key, -1)
		if state == before:
			continue
		enemy_states[key] = state
		if enemy == apex:
			# WINDUP (2) warns through the shared branch below; the strike stomps.
			if state == APEX_BOSS.State.WINDUP:
				var heavy: bool = enemy.current_pattern == (APEX_TOAD.Pattern.LEAP if apex_kind == "apex_toad" else (APEX_SANDWORM.Pattern.BREACH if apex_kind == "apex_sandworm" else APEX_BOSS.Pattern.QUAKE))
				_sfx("quake" if heavy else "warn")
			elif state == APEX_BOSS.State.STRIKE:
				_sfx("stomp", 80)
			elif state == APEX_BOSS.State.PHASE_SHIFT:
				_sfx("stomp", 120)
		elif enemy == boss:
			if state == BOG_KING.State.WARNING:
				_sfx("warn")
			elif before == BOG_KING.State.WARNING and state == BOG_KING.State.RECOVERY:
				_sfx("stomp", 60)
		elif enemy is MIRE_LEAPER:
			if state == MIRE_LEAPER.State.WARNING:
				_sfx("leaper_windup")
			elif before == MIRE_LEAPER.State.LEAP:
				_sfx("stomp", 40)
		elif state == 2 and before != -1:
			# Hunter and Skitter both use index 2 for their WARNING state.
			_sfx("warn")


func _kill_burst(location: Vector3, tint: Color, size: float, shake_amount: float) -> void:
	# Polish (Etappe 16): the loot crystals show the reward, so the death ring of
	# normal and mini kills is only a short, faint puff; bosses keep their shockwave.
	if size < 5.0:
		FX.ring(self, location, Color(tint, 0.32), 0.3, size * 0.55, 0.3)
	else:
		FX.ring(self, location, Color(tint, 0.75), 0.4, size, 0.5)
	_shake(shake_amount)
	_sfx("kill", 15)


func _shake(amount: float) -> void:
	if amount > 0.0 and get_parent().has_method("add_shake"):
		get_parent().add_shake(amount)


# Etappe 17: auch eine offene Boss-Kokon-Wahl (evolution.chest_offers) hält die Welt an.
func choosing() -> bool:
	return not evolution.offers.is_empty() or not evolution.chest_offers.is_empty()


func _award_dna(amount: int) -> void:
	evolution.earn(amount)
	if choosing():
		hud.clear_pointers()
		swarm.set_controls(Vector2.ZERO, false)
	_update_hud("")


func choose_mutation(slot: int) -> void:
	# Etappe 17: während der Boss-Kokon-Wahl wählt dieselbe Karte die Beute.
	if not evolution.chest_offers.is_empty():
		if paused or model.extinct:
			return
		var picked: Dictionary = evolution.choose_chest(slot)
		if picked.is_empty():
			return
		# An evolution has its own moment (EVOLUTION banner); other loot shows its card.
		if chests != null and String(picked.get("type", "")) != "evolution":
			chests.show_card(picked)
		_after_offer_change("Beute aktiv · weiter jagen!")
		_sfx("mutate")
		_try_evolve()
		return
	if paused or model.extinct or not evolution.choose(slot):
		return
	_after_offer_change("Mutation aktiv · weiter jagen!")
	_sfx("mutate")
	# A stored Alpha-Kern evolves as soon as the rules are met.
	_try_evolve()


func reroll_mutations() -> void:
	if paused or model.extinct or not evolution.reroll():
		return
	_after_offer_change("Neue Auswahl")


func banish_mutation(slot: int) -> void:
	if paused or model.extinct or not evolution.banish(slot):
		return
	_after_offer_change("Mutation verbannt")


func skip_mutation() -> void:
	if paused or model.extinct or not evolution.skip():
		return
	_after_offer_change("Mutation übersprungen")


func _after_offer_change(message: String) -> void:
	_sync_attack_forms()
	hud.clear_pointers()
	swarm.set_controls(Vector2.ZERO, false)
	_update_hud(message)


# ---------------------------------------------------------------- map (minimap stage)

func _map_arena() -> Node:
	return get_parent().get_node_or_null("Arena") if get_parent() != null else null


func _reset_map() -> void:
	explored.clear()
	explored_version += 1
	regions_seen.clear()
	region_entries = 0
	region_name = ""
	region_phrase = ""
	_region_tag = Vector3i(1 << 30, 0, 0)
	_explore_at = Vector3.INF
	_map_clock = 0.0
	_map_heading = Vector2(0.0, -1.0)
	_map_corpse_count = -1
	_map_loot_count = -1
	_track_exploration()


## Marks the chunks within EXPLORE_RADIUS as explored (in the current biome) and
## follows the named region the swarm stands in. The chunk scan runs only after
## the swarm moved 3 m; the region check is two floors per frame.
func _track_exploration() -> void:
	var arena := _map_arena()
	if arena == null or not arena.has_method("region_at"):
		return
	var at: Vector3 = swarm.position
	if not _explore_at.is_finite() or at.distance_squared_to(_explore_at) >= 9.0 or _explore_biome != biome_id:
		_explore_at = at
		_explore_biome = biome_id
		var cell: Vector2i = arena.chunk_at(at)
		var reach := ceili(EXPLORE_RADIUS / MAP_CELL)
		var changed := false
		for x in range(cell.x - reach, cell.x + reach + 1):
			for z in range(cell.y - reach, cell.y + reach + 1):
				var key := Vector2i(x, z)
				if String(explored.get(key, "")) == biome_id:
					continue
				var near := Vector2(clampf(at.x, x * MAP_CELL, (x + 1) * MAP_CELL) - at.x, clampf(at.z, z * MAP_CELL, (z + 1) * MAP_CELL) - at.z)
				if near.length_squared() <= EXPLORE_RADIUS * EXPLORE_RADIUS:
					explored[key] = biome_id
					changed = true
		if changed:
			explored_version += 1
	var region: Vector2i = arena.region_at(at)
	var tag := Vector3i(region.x, region.y, BIOMES.ORDER.find(biome_id))
	if tag == _region_tag:
		return
	_region_tag = tag
	region_key = region
	region_name = arena.region_name(region)
	region_phrase = arena.region_phrase(region)
	if not regions_seen.has(tag):
		regions_seen[tag] = true
		# The start region is not announced; every later new region is.
		if regions_seen.size() > 1:
			region_entries += 1


# Centre and heading every frame (smooth minimap), the rest at MAP_HZ.
func _update_map_hud() -> void:
	var moving: Vector2 = swarm.movement_vector if "movement_vector" in swarm else Vector2.ZERO
	if moving.length_squared() > 0.01:
		_map_heading = moving.normalized()
	hud.set_meta("map_center", swarm.position)
	hud.set_meta("map_heading", _map_heading)
	if _map_clock > 0.0 and hud.has_meta("map"):
		return
	_map_clock = 1.0 / MAP_HZ
	hud.set_meta("map", _map_state())


# Minimap data: enemies as (x, z, kind) triples (0 prey, 1 hunter, 2 elite,
# 3 skitter, 4 leaper), horde points, corpses as (x, z, size) triples (size 0
# small, 1 elite/nest/horde, 2 boss/apex), POIs as positions (INF = none).
func _map_state() -> Dictionary:
	var enemies := PackedFloat32Array()
	for target in prey:
		if is_instance_valid(target):
			enemies.append(target.position.x)
			enemies.append(target.position.z)
			enemies.append(0.0)
	for hunter in hunters:
		if is_instance_valid(hunter):
			enemies.append(hunter.position.x)
			enemies.append(hunter.position.z)
			enemies.append(2.0 if bool(hunter.get("elite")) else 1.0)
	for group in [[skitters, 3.0], [leapers, 4.0]]:
		for enemy in group[0]:
			if is_instance_valid(enemy):
				enemies.append(enemy.position.x)
				enemies.append(enemy.position.z)
				enemies.append(group[1])
	# Etappe 16: the "corpses" layer marks where loot crystals lie (coarse cells,
	# size by value) and the Lockruf drops; refreshed at 1 Hz or on a new count.
	var loot_count: int = loot.lying_count() + loot.lures.size() if loot != null else 0
	if loot_count != _map_loot_count or _map_corpse_clock <= 0.0:
		_map_loot_count = loot_count
		_map_corpse_clock = 1.0
		_map_corpses = loot.map_marks() if loot != null else PackedFloat32Array()
	var cores := PackedVector3Array()
	for pickup in alpha_pickups:
		if is_instance_valid(pickup):
			cores.append(pickup.position)
	var horde_points := PackedVector3Array()
	if horde != null and is_instance_valid(horde) and horde.has_method("positions"):
		horde_points = horde.positions()
	return {
		"arena": _map_arena(),
		"center": swarm.position,
		"biome_id": biome_id,
		"enemies": enemies,
		"horde": horde_points,
		"corpses": _map_corpses,
		"alpha": cores,
		"boss": boss.position if boss != null and is_instance_valid(boss) else Vector3.INF,
		"apex": apex.position if apex != null and is_instance_valid(apex) else Vector3.INF,
		"nest": nest.position if nest != null and is_instance_valid(nest) else Vector3.INF,
		"totem": totem.position if totem != null and is_instance_valid(totem) else Vector3.INF,
		"portal": portal.position if portal != null and is_instance_valid(portal) else Vector3.INF,
		"explored": explored,
		"explored_version": explored_version,
		"region": region_name,
		"region_phrase": region_phrase,
		"region_key": region_key,
		"region_entries": region_entries,
		"regions": regions_seen.size(),
		"arrivals": arrivals,
		# Etappe 17 Welle 2: only discovered ones (see _arsenal_marks()).
		"chests": _arsenal_marks(chests),
		"powerups": _arsenal_marks(powerups),
		"shrines": _arsenal_marks(shrines),
	}
