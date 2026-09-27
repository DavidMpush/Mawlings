extends Node3D

const EVOLUTION = preload("res://scripts/evolution.gd")
const RUN_MODEL = preload("res://scripts/run_model.gd")
const PREY = preload("res://scripts/prey.gd")
const HUNTER = preload("res://scripts/hunter.gd")
const SKITTER = preload("res://scripts/skitter.gd")
const BOG_KING = preload("res://scripts/bog_king.gd")
const MIRE_LEAPER = preload("res://scripts/mire_leaper.gd")
const TUNING = preload("res://scripts/tuning.gd")
const FX = preload("res://scripts/fx.gd")
const FX_BATCH = preload("res://scripts/fx_batch.gd")
const QUALITY = preload("res://scripts/quality.gd")
const CORPSE_VISUALS = preload("res://scripts/corpse_visuals.gd")
const ERUPTIONS = preload("res://scripts/eruptions.gd")
const BROOD_NEST = preload("res://scripts/objectives/brood_nest.gd")
const CURSE_TOTEM = preload("res://scripts/objectives/curse_totem.gd")
const HUD_OBJECTIVES_PATH := "res://scripts/ui/hud_objectives.gd"
const NEST_COLOR := Color("3fe6d8")
const CURSE_COLOR := Color("ff4a8a")
const CORPSE_BIOMASS := TUNING.CORPSE_BIOMASS
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
const BODY_RADIUS := {"prey": 0.45, "hunter": 0.72, "elite": 1.05, "skitter": 0.55, "leaper": 0.7, "boss": 2.3}
const POPUP_SECONDS := 0.9
const POPUP_MAX := 6
const POPUP_MERGE_SECONDS := 0.3
const POPUP_MERGE_DISTANCE := 2.5
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
# (scripts/corpse_visuals.gd). Display only; the corpses live in RunModel.
var corpse_view: Node3D
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
# Floating kill rewards: {"at": Vector3, "dna": int, "biomass": int, "age": float}.
var kill_popups: Array[Dictionary] = []
# Counts Bog King kills this run; HUD and Main react to changes (Königsmoment).
var king_moments := 0
var last_hit_share := 1.0
# Run-Ziele (stage 06): one Brutnest at a time, an optional Fluch-Totem before a
# boss, elite hunters on a timer. Placement uses objective_rng seeded from the
# run seed, so a seed always yields the same first nest.
var nest: Node3D
var totem: Node3D
var objective_rng := RandomNumberGenerator.new()
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
# Horde kills waiting to become one corpse per cell: key -> {sum, n, biomass, dna}.
var flood_bundles: Dictionary = {}
var flood_bundle_clock := 0.0
# Soft, rate-limited swarm flash for horde bites (see _flood_bites).
const HORDE_FLASH := 0.5
const HORDE_FLASH_SECONDS := 0.6
var horde_flash_at := 0.0
# Etappe 09 - Anfuehrer: HUD/feel state (rules live in RunModel.apply_hit()).
const MILESTONE_SHOW_SECONDS := 2.5
var last_loss_fraction := 0.0
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


func _ready() -> void:
	drop_rng.randomize()
	_seed_objectives()
	_ensure_objective_hud()
	_ensure_flood_hud()
	_create_attack_forms()
	_create_horde()
	_create_world_views()
	_reset_flood()
	_starting_prey()
	_update_hud("")


# Stores a RunConfig and restarts the run with it.
func apply_config(value: Dictionary) -> void:
	config = value.duplicate(true)
	if swarm.has_method("apply_config"):
		swarm.apply_config(config)
	reset_run()


func _starting_prey() -> void:
	_spawn_prey(Vector3(-3.0, 0.0, -4.0))
	_spawn_prey(Vector3(4.0, 0.0, -2.0))
	_spawn_prey(Vector3(-2.0, 0.0, 5.0))


func reset_run() -> void:
	if attack_forms != null and attack_forms.has_method("clear"):
		attack_forms.clear()
	if horde != null and is_instance_valid(horde) and horde.has_method("clear"):
		horde.clear()
	horde = null
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
	eruptions = null
	corpse_kinds.clear()
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
	milestone_value = 0
	milestone_timer = 0.0
	leader_state_key = Vector3i(-1, -1, -1)
	hunters_unlocked = false
	hunters_unlocked_at = 0.0
	snap_gap = 0.0
	kill_popups.clear()
	unit_points_valid = false
	result_stored = false
	evolve_flash = 0.0
	evolve_name = ""
	swarm.position = Vector3.ZERO
	swarm.set_population(model.population, false)
	_sync_leader()
	swarm.clear_focus()
	swarm.set_controls(Vector2.ZERO, false)
	hud.clear_pointers()
	_create_attack_forms()
	_create_horde()
	_create_world_views()
	_reset_flood()
	_starting_prey()
	_update_hud("")


func _configure_run() -> void:
	enemy_hp = 1.0
	enemy_damage = 1.0
	flood_start = _difficulty_flood_start()
	if config.is_empty():
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


func _sync_attack_forms() -> void:
	if attack_forms != null and attack_forms.has_method("set_ranks"):
		attack_forms.set_ranks(evolution.attack_ranks())


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
		_sfx("warn", 150)
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
			_music_cue("flood")
			_shake(0.45)
	if flood_state != 2:
		return false
	flood_wave_clock -= delta
	if flood_wave_clock <= 0.0:
		flood_wave_clock = TUNING.FLOOD_WAVE_SECONDS
		_spawn_flood_wave()
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
	var ended := _apply_hit(maxi(0, loss), impact, 0.08, null, leader_struck)
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
# bundle becomes one persistent corpse (resource rule) with one popup.
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
	flood_bundle_clock += delta
	if flood_bundle_clock < TUNING.FLOOD_BUNDLE_SECONDS or flood_bundles.is_empty():
		return false
	flood_bundle_clock = 0.0
	return flush_flood_bundles()


# Turns every pending horde bundle into a corpse + DNA now. True when a
# mutation offer opened (step() must stop).
func flush_flood_bundles() -> bool:
	if flood_bundles.is_empty():
		return false
	var dna_total := 0
	for key in flood_bundles:
		var bundle: Dictionary = flood_bundles[key]
		var location: Vector3 = get_parent().get_node("Arena").safe_spawn(bundle.sum / float(bundle.n), 0.4)
		location.y = 0.0
		var amount: float = float(bundle.biomass) * evolution.biomass_multiplier() * reward_multiplier()
		# A long flood kills hundreds: feed an uneaten corpse close by instead of
		# adding one more (keeps the corpse list short; the biomass stays).
		var id := _grow_nearby_corpse(location, amount)
		if id >= 0:
			model.kills += int(bundle.n)
			location = _corpse_position(id)
		else:
			id = _create_corpse(location, float(bundle.biomass) * evolution.biomass_multiplier(), "horde")
			if id >= 0:
				# add_corpse counted one kill; the bundle holds bundle.n of them.
				model.kills += int(bundle.n) - 1
		var dna := _reward_dna(int(bundle.dna))
		dna_total += dna
		# The horde draws its own death effect; the popup shows the reward.
		_add_popup(location, dna, model.remaining_biomass(id) if id >= 0 else 0.0)
	flood_bundles.clear()
	if dna_total > 0:
		_sfx("kill", 10)
		_award_dna(dna_total)
	return choosing()


# Adds biomass to the corpse within FLOOD_BUNDLE_CELL of `location`; -1 when none.
func _grow_nearby_corpse(location: Vector3, amount: float, distance: float = TUNING.FLOOD_BUNDLE_CELL) -> int:
	if amount <= 0.0 or model.extinct:
		return -1
	var reach := distance * distance
	for index in model.corpses.size():
		var corpse: Dictionary = model.corpses[index]
		var offset: Vector3 = corpse.position - location
		if offset.x * offset.x + offset.z * offset.z > reach:
			continue
		corpse.remaining += amount
		corpse.initial += amount
		_update_corpse(int(corpse.id), float(corpse.initial))
		return int(corpse.id)
	return -1


func _corpse_position(id: int) -> Vector3:
	for corpse in model.corpses:
		if corpse.id == id:
			return corpse.position
	return swarm.position


func _flood_message(message: String) -> String:
	if flood_state == 1:
		return "DIE FLUT KOMMT IN %d s!" % maxi(1, ceili(flood_start - model.elapsed))
	if flood_state == 2 and (message.begins_with("Jage") or message.begins_with("Mawlings greifen") or message.begins_with("Biomasse") or message.begins_with("Schwarm voll")):
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
	model.advance(delta)
	unit_points_valid = false
	_age_popups(delta)
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
	var message := "Jage die türkisfarbene Beute"
	var pressure: float = model.pressure()
	var attack_range := 1.15 if swarm.rally_pressed else 1.5
	# Stage 09: a small swarm's bigger animals bite harder (bonus fades out at 25).
	var small_bonus := TUNING.SMALL_SWARM_BITE * clampf(1.0 - float(model.population - 1) / 24.0, 0.0, 1.0)
	var damage := minf(32.0, 1.0 + float(model.population) * 0.12 + small_bonus) * (1.55 if swarm.rally_pressed else 1.0)
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
	for corpse in model.corpses.duplicate():
		var id: int = corpse.id
		if corpse.position.distance_to(swarm.position) > TUNING.HARVEST_RADIUS:
			continue
		var rate := TUNING.HARVEST_RATE * (1.35 if swarm.rally_pressed else 1.0)
		var grown_from: int = model.population
		var consumed: float = model.harvest(id, rate * evolution.harvest_multiplier() * delta)
		if consumed > 0.0:
			swarm.set_population(model.population)
			if model.population > grown_from:
				_on_growth(model.population - grown_from)
			if focus_mode == 0:
				focus_mode = 2
				focus_point = corpse.position
			if not message.begins_with("RAUS"):
				message = "Biomasse ernten · Rally beschleunigt"
			_update_corpse(id, corpse.initial)
		elif model.population >= RUN_MODEL.MAX_POPULATION:
			message = "Schwarm voll — Biomasse bleibt liegen"
	_step_alpha_pickups(delta)
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
	if boss == null:
		boss_clock -= delta
		# Stage 09: the first Bog King waits for a real swarm (or BOSS_LATEST).
		var boss_ready: bool = boss_cycles > 0 or model.population >= TUNING.BOSS_MIN_POPULATION or model.elapsed >= TUNING.BOSS_LATEST_SECONDS
		if boss_clock <= 0.0 and boss_ready:
			_spawn_boss(_spawn_position(11.0))
	message = _step_objectives(delta, message)
	message = _flood_message(message)
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
	return result


# Kills an enemy whose health is gone, whatever dealt the damage. It leaves its
# list first, so biomass, DNA, drops and statistics are granted exactly once.
func _resolve_death(enemy: Node3D, kind: String) -> bool:
	if enemy == null or enemy.health > 0.0:
		return false
	var location: Vector3 = enemy.position
	var corpses_before: int = model.corpses.size()
	match kind:
		"hunter":
			if not hunters.has(enemy):
				return false
			hunters.erase(enemy)
			if enemy.elite:
				_kill_burst(location, Color("f5c86a"), 4.0, 0.35)
				_create_corpse(location, TUNING.ELITE_BIOMASS * evolution.biomass_multiplier(), "elite")
				_drop_alpha_core(location)
			else:
				_kill_burst(location, Color("c58be0"), 2.6, 0.25)
				_create_corpse(location, TUNING.HUNTER_BIOMASS * evolution.biomass_multiplier(), "hunter")
				if model.pressure() >= 2.0 and drop_rng.randf() < 0.10:
					_drop_alpha_core(location)
		"skitter":
			if not skitters.has(enemy):
				return false
			skitters.erase(enemy)
			_kill_burst(location, Color("7fb4ff"), 2.4, 0.2)
			_create_corpse(location, TUNING.SKITTER_BIOMASS * evolution.biomass_multiplier(), "skitter")
			enemy.cleanup()
		"leaper":
			if not leapers.has(enemy):
				return false
			leapers.erase(enemy)
			_kill_burst(location, Color("5fe0c8"), 2.4, 0.2)
			_create_corpse(location, TUNING.LEAPER_BIOMASS * evolution.biomass_multiplier(), "leaper")
			if drop_rng.randf() < 0.25:
				_drop_alpha_core(location)
			enemy.cleanup()
		"boss":
			if enemy != boss:
				return false
			boss = null
			_kill_burst(location, Color("ffe07a"), 7.5, 0.7)
			_kill_burst(location, Color("d8b8ff"), 5.0, 0.0)
			_create_corpse(location, TUNING.BOSS_BIOMASS * evolution.biomass_multiplier(), "boss")
			boss_clock = TUNING.BOSS_RESPAWN_SECONDS
			_drop_alpha_core(location)
		_:
			return false
	model.record_kill(kind)
	enemy.queue_free()
	var base_dna: int = {"hunter": 20, "skitter": 15, "leaper": TUNING.LEAPER_DNA, "boss": 50}[kind]
	if kind == "hunter" and enemy.elite:
		base_dna = TUNING.ELITE_DNA
	var dna := _reward_dna(base_dna)
	_add_popup(location, dna, model.corpses[-1].initial if model.corpses.size() > corpses_before else 0.0)
	if kind == "boss":
		_king_moment(location)
		# The curse (and its double reward) ends with the cursed boss; its own
		# corpse and DNA above were still doubled.
		if curse_state == 2:
			curse_state = 0
	_award_dna(dna)
	return true


func _spawn_position(radius: float) -> Vector3:
	spawn_number += 1
	var angle := float(spawn_number) * 2.39996323
	return get_parent().get_node("Arena").safe_spawn(swarm.position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius), 0.9)


func _spawn_prey(location: Vector3) -> void:
	var target: Node3D = PREY.new()
	target.name = "Nibbler"
	target.position = location
	add_child(target)
	prey.append(target)


func _spawn_hunter(location: Vector3) -> Node3D:
	var target = HUNTER.new()
	target.name = "Hunter"
	target.position = location
	target.health = TUNING.HUNTER_HEALTH * sqrt(model.pressure()) * difficulty_scale(enemy_hp)
	target.max_health = target.health
	add_child(target)
	hunters.append(target)
	return target


func _spawn_skitter(location: Vector3) -> Node3D:
	var target = SKITTER.new()
	target.name = "Skitter"
	target.position = location
	target.health = TUNING.SKITTER_HEALTH * sqrt(model.pressure()) * difficulty_scale(enemy_hp)
	target.max_health = target.health
	add_child(target)
	skitters.append(target)
	return target


func _spawn_leaper(location: Vector3) -> Node3D:
	var target = MIRE_LEAPER.new()
	target.name = "Mire Leaper"
	target.position = location
	target.health = TUNING.LEAPER_HEALTH * sqrt(model.pressure()) * difficulty_scale(enemy_hp)
	target.max_health = target.health
	add_child(target)
	leapers.append(target)
	return target


func _spawn_boss(location: Vector3) -> Node3D:
	var target = BOG_KING.new()
	target.name = "Bog King"
	target.position = get_parent().get_node("Arena").safe_spawn(location, 2.5)
	target.health = TUNING.BOSS_HEALTH * sqrt(model.pressure()) * difficulty_scale(enemy_hp)
	target.max_health = target.health
	add_child(target)
	boss = target
	_on_boss_spawned(target)
	_music_cue("boss")
	return target


func _kill_prey(target: Node3D) -> void:
	if not prey.has(target):
		return
	prey.erase(target)
	_kill_burst(target.position, Color("7de6d2"), 1.8, 0.0)
	var corpses_before: int = model.corpses.size()
	_create_corpse(target.position, CORPSE_BIOMASS * evolution.biomass_multiplier(), "prey")
	model.record_kill("prey")
	target.queue_free()
	var dna := _reward_dna(10)
	_add_popup(target.position, dna, model.corpses[-1].initial if model.corpses.size() > corpses_before else 0.0)
	_award_dna(dna)


# `kind` names the corpse design (corpse_kinds); `rewarded` applies the curse bonus.
func _create_corpse(location: Vector3, biomass: float, kind: String = "prey", rewarded: bool = true) -> int:
	# Fluch-Totem: doubled biomass until the cursed boss dies.
	var id: int = model.add_corpse(location, biomass * (reward_multiplier() if rewarded else 1.0))
	if id < 0:
		return id
	corpse_kinds[id] = kind
	if corpse_view != null:
		corpse_view.add(id, kind, location, float(model.corpses[-1].initial))
	return id


func _update_corpse(id: int, initial: float) -> void:
	if corpse_view == null:
		return
	var remaining: float = model.remaining_biomass(id)
	if remaining <= 0.0:
		corpse_view.remove(id)
		corpse_kinds.erase(id)
	else:
		corpse_view.set_fill(id, remaining / maxf(initial, 0.001))


# Corpse designs and lava eruptions live under HuntWorld, so reset_run() frees
# them with the other children and they come back empty.
func _create_world_views() -> void:
	corpse_view = CORPSE_VISUALS.new()
	corpse_view.name = "CorpseView"
	add_child(corpse_view)
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


# ---------------------------------------------------------------- Alpha-Kern

# Drops a glowing amber-violet core beside the corpse; it stays until touched.
func _drop_alpha_core(location: Vector3) -> Node3D:
	var offset := Vector3(1.3, 0.0, 0.0).rotated(Vector3.UP, drop_rng.randf() * TAU)
	var pickup := Node3D.new()
	pickup.name = "Alpha core"
	pickup.position = get_parent().get_node("Arena").safe_spawn(location + offset, 0.5)
	add_child(pickup)
	var parts := _alpha_core_parts()
	var glow: Material = FX_BATCH.shared_material(ALPHA_AMBER, true)
	var shell: Material = FX_BATCH.shared_material(Color(ALPHA_VIOLET, 0.55), true, true)
	var halo: Material = FX_BATCH.shared_material(Color(ALPHA_AMBER, 0.75), true, true, 1.0, true)
	var float_root := Node3D.new()
	float_root.name = "Float"
	pickup.add_child(float_root)
	_piece(float_root, parts.gem, glow, Vector3(0.0, 1.3, 0.0))
	_piece(float_root, parts.outer, shell, Vector3(0.0, 1.3, 0.0))
	var ground := _piece(pickup, parts.ring, halo, Vector3(0.0, 0.08, 0.0))
	ground.scale = Vector3(1.0, 0.2, 1.0)
	_piece(pickup, parts.beam, shell, Vector3(0.0, 2.0, 0.0))
	alpha_pickups.append(pickup)
	FX.ring(self, pickup.position, Color(ALPHA_VIOLET, 0.8), 0.3, 2.4, 0.6)
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
	_sfx("pickup", 25)
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


# ---------------------------------------------------------------- Run-Ziele

# Resets every objective and seeds placement from the run seed (0 without config).
func _seed_objectives() -> void:
	objective_rng.seed = hash("mawlings-objectives:%d" % int(config.get("seed", 0)))
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
	var calm := message.begins_with("Jage") or message.begins_with("Mawlings greifen") or message.begins_with("Biomasse") or message.begins_with("Schwarm voll")
	# Brutnest: one at a time; a new one after the previous one hatched.
	if nest == null:
		nest_clock -= delta
		if nest_clock <= 0.0:
			spawn_nest(_objective_position(TUNING.NEST_RADIUS, [totem]))
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
			return "BRUTNEST GESCHLÜPFT · BIOMASSE FRESSEN!"
		if share > 0.0 and calm:
			message = "Brutnest füllen · %d Prozent" % int(nest.progress * 100.0)
	# Fluch-Totem: rolled once per boss cycle while no boss is alive.
	if boss == null and totem == null and curse_state == 0 and not totem_offered and boss_clock <= TUNING.TOTEM_LEAD_SECONDS and boss_clock >= TUNING.TOTEM_MIN_LEAD_SECONDS:
		totem_offered = true
		if boss_cycles == 0 or objective_rng.randf() < TUNING.TOTEM_CHANCE:
			spawn_totem(_objective_position(TUNING.TOTEM_RADIUS + 0.6, [nest]))
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


# Full nest: a clutch of ordinary corpses (they stay until eaten) plus DNA.
func _complete_nest() -> void:
	var location: Vector3 = nest.position
	nest.queue_free()
	nest = null
	nest_clock = TUNING.NEST_RESPAWN_SECONDS
	var total: float = (TUNING.NEST_BIOMASS + TUNING.NEST_BIOMASS_GROWTH * float(nests_completed)) * evolution.biomass_multiplier()
	nests_completed += 1
	var created := 0.0
	for index in TUNING.NEST_CLUTCH:
		var angle := TAU * float(index) / float(TUNING.NEST_CLUTCH) + 0.4
		var id := _create_corpse(location + Vector3(cos(angle), 0.0, sin(angle)) * 0.55, total / float(TUNING.NEST_CLUTCH), "nest")
		if id >= 0:
			# A hatched nest is not a kill.
			model.kills -= 1
			created += model.remaining_biomass(id)
	var dna := _reward_dna(TUNING.NEST_DNA)
	FX.ring(self, location, Color(NEST_COLOR, 0.95), 0.6, TUNING.NEST_RADIUS + 3.0, 0.8)
	FX.ring(self, location, Color("f5c86a", 0.8), 0.3, TUNING.NEST_RADIUS, 0.55)
	_shake(0.2)
	_sfx("grow")
	_sfx("evolve", 60)
	_add_popup(location, dna, created)
	_award_dna(dna)


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
func _objective_position(clearance: float, avoid: Array) -> Vector3:
	var arena: Node3D = get_parent().get_node("Arena")
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
		"nest_pointer": _edge_pointer(nest.position + Vector3.UP * 1.0) if nest != null else Vector2.INF,
		"totem_active": totem != null,
		"totem_hold": totem.hold if totem != null else 0.0,
		"totem_pointer": _edge_pointer(totem.position + Vector3.UP * 1.5) if totem != null else Vector2.INF,
		"totem_screen": _screen_point(totem.position + Vector3.UP * 1.2) if totem != null else Vector2.INF,
		"curse": curse_state,
		"reward_multiplier": reward_multiplier(),
		"nests": nests_completed,
	}


# ---------------------------------------------------------------- HUD

func _update_hud(message: String) -> void:
	hud.evolution = evolution
	hud.population = model.population
	hud.biomass_bank = model.biomass_bank
	hud.corpse_count = model.corpses.size()
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
	_set_hud_value("last_loss_fraction", last_loss_fraction)
	hud.hint = message
	hud.set_meta("kill_popups", _popup_screen())
	hud.set_meta("king_moments", king_moments)
	hud.set_meta("flood", _flood_hud())
	var objectives := _objective_hud()
	hud.set_meta("objectives", objectives)
	if "objectives" in hud:
		hud.set("objectives", objectives)
	hud.nearest_corpse = ""
	# Etappe 07: squared distances in the loop, the label is formatted once.
	var nearest := INF
	var nearest_offset := Vector3.ZERO
	for corpse in model.corpses:
		var offset: Vector3 = corpse.position - swarm.position
		var distance_squared := offset.length_squared()
		if distance_squared < nearest:
			nearest = distance_squared
			nearest_offset = offset
	if nearest < INF:
		var distance := sqrt(nearest)
		var direction := "hier"
		if distance > TUNING.HARVEST_RADIUS:
			direction = ("oben" if nearest_offset.z < 0 else "unten") if absf(nearest_offset.z) > absf(nearest_offset.x) else ("links" if nearest_offset.x < 0 else "rechts")
		hud.nearest_corpse = "Kadaver: %dm · %s" % [int(distance), direction]
	hud.queue_redraw()


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
func melee_factor(location: Vector3, kind: String, contact_range: float) -> float:
	var centre_distance := Vector2(location.x - swarm.position.x, location.z - swarm.position.z).length()
	var points := _unit_points()
	if points.is_empty():
		return 1.0 if centre_distance < contact_range else 0.0
	var reach: float = MELEE_REACH + float(BODY_RADIUS.get(kind, 0.5))
	var reach_squared := reach * reach
	var biting := 0
	for point in points:
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


# ---------------------------------------------------------------- kill popups

# Bundles DNA and biomass of one kill into a floating reward at the kill spot;
# kills close in time and space merge into one popup.
func _add_popup(location: Vector3, dna: int, biomass: float) -> void:
	var amount := int(round(biomass))
	for popup in kill_popups:
		if popup.age < POPUP_MERGE_SECONDS and Vector2(popup.at.x - location.x, popup.at.z - location.z).length() < POPUP_MERGE_DISTANCE:
			popup.dna += dna
			popup.biomass += amount
			popup.age = 0.0
			popup.at = (popup.at + location) * 0.5
			return
	kill_popups.append({"at": location, "dna": dna, "biomass": amount, "age": 0.0})
	while kill_popups.size() > POPUP_MAX:
		kill_popups.pop_front()


func _age_popups(delta: float) -> void:
	for index in range(kill_popups.size() - 1, -1, -1):
		kill_popups[index].age += delta
		if kill_popups[index].age >= POPUP_SECONDS:
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
		result.append({"screen": camera.unproject_position(point), "dna": popup.dna, "biomass": popup.biomass, "t": popup.age / POPUP_SECONDS})
	return result


# Bog King eaten: big HUD moment, sound and vibration; Main adds slow motion and zoom.
func _king_moment(location: Vector3) -> void:
	king_moments += 1
	_sfx("evolve", 120)
	_music_cue("king")
	var main := get_parent()
	if main != null and main.has_method("king_moment"):
		main.king_moment(location)


# Resolves one announced hit. Returns true when the run ended by extinction.
# `loss` counts followers only (never the leader); `leader_struck` costs the
# leader 1 LP under the rules in RunModel.apply_hit() (stage 09); a `nonlethal`
# source never takes its last LP.
func _apply_hit(loss: int, impact: Vector3, shake_amount: float, attacker: Node3D = null, leader_struck: bool = false, nonlethal: bool = false) -> bool:
	var damage_scale := difficulty_scale(enemy_damage)
	if loss > 0 and damage_scale != 1.0:
		loss = maxi(1, ceili(float(loss) * damage_scale))
	var before: int = model.population
	var outcome: Dictionary = model.apply_hit(evolution.loss_after_armor(loss, swarm.rally_pressed), leader_struck, nonlethal)
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
		var music := _music_node()
		if music != null:
			music.stinger("extinct")
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


# New Mawlings grew from biomass: cell division, milestones (+1 LP per 25).
func _on_growth(count: int) -> void:
	if swarm.has_method("split_new_units"):
		# The plop plays in swarm.gd at the moment each cell pinches off (throttled).
		swarm.split_new_units(count)
	var reached := model.take_milestone()
	if reached > 0:
		milestone_value = reached
		milestone_timer = MILESTONE_SHOW_SECONDS
		_sfx("milestone", 60)
	_sync_leader()


# Rückeroberung: fallen Mawlings leave FALLEN_BIOMASS each, bundled into a corpse
# close by (like horde kills) so the list stays short; a new one otherwise.
func _drop_fallen_biomass(location: Vector3, count: int) -> void:
	if count <= 0 or model.extinct:
		return
	var amount := TUNING.FALLEN_BIOMASS * float(count)
	var arena: Node3D = get_parent().get_node_or_null("Arena")
	var spot := location
	if arena != null and arena.has_method("safe_spawn"):
		spot = arena.safe_spawn(location, 0.4)
	spot.y = 0.0
	if _grow_nearby_corpse(spot, amount, TUNING.FALLEN_BUNDLE_REACH) >= 0:
		return
	if _create_corpse(spot, amount, "mawling", false) >= 0:
		# Fallen Mawlings are no kills.
		model.kills -= 1


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
		music.set_intensity(model.pressure(), flood_state == 2, boss != null)


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
	for enemy in enemies:
		var key: int = enemy.get_instance_id()
		var state: int = enemy.get("state")
		var before: int = enemy_states.get(key, -1)
		if state == before:
			continue
		enemy_states[key] = state
		if enemy == boss:
			if state == BOG_KING.State.WARNING:
				_sfx("warn")
			elif before == BOG_KING.State.WARNING and state == BOG_KING.State.RECOVERY:
				_sfx("stomp", 60)
		elif enemy is MIRE_LEAPER:
			if state == MIRE_LEAPER.State.WARNING:
				_sfx("warn")
			elif before == MIRE_LEAPER.State.LEAP:
				_sfx("stomp", 40)
		elif state == 2 and before != -1:
			# Hunter and Skitter both use index 2 for their WARNING state.
			_sfx("warn")


func _kill_burst(location: Vector3, tint: Color, size: float, shake_amount: float) -> void:
	FX.ring(self, location, tint, 0.4, size, 0.5)
	_shake(shake_amount)
	_sfx("kill", 15)


func _shake(amount: float) -> void:
	if amount > 0.0 and get_parent().has_method("add_shake"):
		get_parent().add_shake(amount)


func choosing() -> bool:
	return not evolution.offers.is_empty()


func _award_dna(amount: int) -> void:
	evolution.earn(amount)
	if choosing():
		hud.clear_pointers()
		swarm.set_controls(Vector2.ZERO, false)
	_update_hud("")


func choose_mutation(slot: int) -> void:
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
