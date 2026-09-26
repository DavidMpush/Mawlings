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
var corpse_visuals: Dictionary = {}
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


func _ready() -> void:
	drop_rng.randomize()
	_seed_objectives()
	_ensure_objective_hud()
	_create_attack_forms()
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
	corpse_visuals.clear()
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
	kill_popups.clear()
	unit_points_valid = false
	result_stored = false
	evolve_flash = 0.0
	evolve_name = ""
	swarm.position = Vector3.ZERO
	swarm.set_population(model.population, false)
	swarm.clear_focus()
	swarm.set_controls(Vector2.ZERO, false)
	hud.clear_pointers()
	_create_attack_forms()
	_starting_prey()
	_update_hud("")


func _configure_run() -> void:
	enemy_hp = 1.0
	enemy_damage = 1.0
	if config.is_empty():
		return
	model.configure(int(config.get("start_population", model.population)), float(config.get("pressure_doubling", TUNING.PRESSURE_DOUBLING_SECONDS)))
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
	if swarm.rally_pressed:
		model.used_rally = true
	var message := "Jage die türkisfarbene Beute"
	var pressure: float = model.pressure()
	var attack_range := 1.15 if swarm.rally_pressed else 1.5
	var damage := minf(32.0, 1.0 + float(model.population) * 0.12) * (1.55 if swarm.rally_pressed else 1.0)
	damage *= evolution.damage_multiplier(swarm.rally_pressed)
	focus_mode = 0
	focus_distance = INF
	melee_contact = false
	var population_before: int = model.population
	# Attack forms only reduce health; every death below is resolved exactly once,
	# whatever dealt the damage.
	if attack_forms != null and attack_forms.has_method("step"):
		attack_forms.step(delta, _living_targets(), swarm.rally_pressed, sqrt(pressure) * evolution.damage_multiplier(false))
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
		target.call("step", delta, swarm.position)
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
	for corpse in model.corpses.duplicate():
		var id: int = corpse.id
		if corpse.position.distance_to(swarm.position) > TUNING.HARVEST_RADIUS:
			continue
		var rate := TUNING.HARVEST_RATE * (1.35 if swarm.rally_pressed else 1.0)
		var consumed: float = model.harvest(id, rate * evolution.harvest_multiplier() * delta)
		if consumed > 0.0:
			swarm.set_population(model.population)
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
	hunter_clock -= delta
	var hunter_budget := mini(TUNING.MAX_HUNTERS, 1 + int(model.elapsed / 35.0))
	if hunter_clock <= 0.0 and hunters.size() < hunter_budget:
		_spawn_hunter(_spawn_position(8.0))
		hunter_clock = maxf(2.5, 12.0 / sqrt(pressure))
	skitter_clock -= delta
	var skitter_budget := mini(TUNING.MAX_SKITTERS, 1 + int(model.elapsed / 90.0))
	if model.elapsed >= TUNING.FIRST_SKITTER_SECONDS and skitter_clock <= 0.0 and skitters.size() < skitter_budget:
		_spawn_skitter(_spawn_position(9.0))
		skitter_clock = maxf(7.0, 28.0 / sqrt(pressure))
	leaper_clock -= delta
	var leaper_budget := mini(TUNING.MAX_LEAPERS, 1 + int(maxf(0.0, model.elapsed - TUNING.FIRST_LEAPER_SECONDS) / 80.0))
	if model.elapsed >= TUNING.FIRST_LEAPER_SECONDS and leaper_clock <= 0.0 and leapers.size() < leaper_budget:
		_spawn_leaper(_spawn_position(10.0))
		leaper_clock = maxf(8.0, 30.0 / sqrt(pressure))
	if boss == null:
		boss_clock -= delta
		if boss_clock <= 0.0:
			_spawn_boss(_spawn_position(11.0))
	message = _step_objectives(delta, message)
	_update_hud(message)


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
				_create_corpse(location, TUNING.ELITE_BIOMASS * evolution.biomass_multiplier())
				_drop_alpha_core(location)
			else:
				_kill_burst(location, Color("c58be0"), 2.6, 0.25)
				_create_corpse(location, TUNING.HUNTER_BIOMASS * evolution.biomass_multiplier())
				if model.pressure() >= 2.0 and drop_rng.randf() < 0.10:
					_drop_alpha_core(location)
		"skitter":
			if not skitters.has(enemy):
				return false
			skitters.erase(enemy)
			_kill_burst(location, Color("7fb4ff"), 2.4, 0.2)
			_create_corpse(location, TUNING.SKITTER_BIOMASS * evolution.biomass_multiplier())
			enemy.cleanup()
		"leaper":
			if not leapers.has(enemy):
				return false
			leapers.erase(enemy)
			_kill_burst(location, Color("5fe0c8"), 2.4, 0.2)
			_create_corpse(location, TUNING.LEAPER_BIOMASS * evolution.biomass_multiplier())
			if drop_rng.randf() < 0.25:
				_drop_alpha_core(location)
			enemy.cleanup()
		"boss":
			if enemy != boss:
				return false
			boss = null
			_kill_burst(location, Color("ffe07a"), 7.5, 0.7)
			_kill_burst(location, Color("d8b8ff"), 5.0, 0.0)
			_create_corpse(location, TUNING.BOSS_BIOMASS * evolution.biomass_multiplier())
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
	target.health = TUNING.HUNTER_HEALTH * sqrt(model.pressure()) * enemy_hp
	target.max_health = target.health
	add_child(target)
	hunters.append(target)
	return target


func _spawn_skitter(location: Vector3) -> Node3D:
	var target = SKITTER.new()
	target.name = "Skitter"
	target.position = location
	target.health = TUNING.SKITTER_HEALTH * sqrt(model.pressure()) * enemy_hp
	target.max_health = target.health
	add_child(target)
	skitters.append(target)
	return target


func _spawn_leaper(location: Vector3) -> Node3D:
	var target = MIRE_LEAPER.new()
	target.name = "Mire Leaper"
	target.position = location
	target.health = TUNING.LEAPER_HEALTH * sqrt(model.pressure()) * enemy_hp
	target.max_health = target.health
	add_child(target)
	leapers.append(target)
	return target


func _spawn_boss(location: Vector3) -> Node3D:
	var target = BOG_KING.new()
	target.name = "Bog King"
	target.position = get_parent().get_node("Arena").safe_spawn(location, 2.5)
	target.health = TUNING.BOSS_HEALTH * sqrt(model.pressure()) * enemy_hp
	target.max_health = target.health
	add_child(target)
	boss = target
	_on_boss_spawned(target)
	return target


func _kill_prey(target: Node3D) -> void:
	if not prey.has(target):
		return
	prey.erase(target)
	_kill_burst(target.position, Color("7de6d2"), 1.8, 0.0)
	var corpses_before: int = model.corpses.size()
	_create_corpse(target.position, CORPSE_BIOMASS * evolution.biomass_multiplier())
	model.record_kill("prey")
	target.queue_free()
	var dna := _reward_dna(10)
	_add_popup(target.position, dna, model.corpses[-1].initial if model.corpses.size() > corpses_before else 0.0)
	_award_dna(dna)


func _create_corpse(location: Vector3, biomass: float) -> int:
	# Fluch-Totem: doubled biomass until the cursed boss dies.
	var id: int = model.add_corpse(location, biomass * reward_multiplier())
	if id < 0:
		return id
	var visual := Node3D.new()
	visual.name = "Persistent corpse %d" % id
	visual.position = location
	add_child(visual)
	var amber := StandardMaterial3D.new()
	amber.albedo_color = Color("efb642")
	amber.roughness = 0.8
	var ring := CylinderMesh.new()
	ring.top_radius = 0.7
	ring.bottom_radius = 0.7
	ring.height = 0.06
	_piece(visual, ring, amber, Vector3(0.0, 0.05, 0.0))
	var core := SphereMesh.new()
	core.radius = 0.25
	core.height = 0.4
	_piece(visual, core, amber, Vector3(0.0, 0.25, 0.0))
	corpse_visuals[id] = visual
	return id


func _update_corpse(id: int, initial: float) -> void:
	var visual: Node3D = corpse_visuals.get(id)
	if visual == null:
		return
	var remaining: float = model.remaining_biomass(id)
	if remaining <= 0.0:
		corpse_visuals.erase(id)
		visual.queue_free()
	else:
		visual.scale = Vector3.ONE * (0.45 + 0.55 * remaining / initial)


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
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = ALPHA_AMBER
	var shell := StandardMaterial3D.new()
	shell.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shell.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shell.albedo_color = Color(ALPHA_VIOLET, 0.55)
	var halo := StandardMaterial3D.new()
	halo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo.albedo_color = Color(ALPHA_AMBER, 0.75)
	halo.cull_mode = BaseMaterial3D.CULL_DISABLED
	var float_root := Node3D.new()
	float_root.name = "Float"
	pickup.add_child(float_root)
	var gem := SphereMesh.new()
	gem.radius = 0.36
	gem.height = 0.84
	gem.radial_segments = 6
	gem.rings = 3
	_piece(float_root, gem, glow, Vector3(0.0, 1.3, 0.0))
	var outer := SphereMesh.new()
	outer.radius = 0.62
	outer.height = 1.24
	outer.radial_segments = 8
	outer.rings = 4
	_piece(float_root, outer, shell, Vector3(0.0, 1.3, 0.0))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.85
	ring.outer_radius = 1.1
	ring.rings = 32
	ring.ring_segments = 4
	var ground := _piece(pickup, ring, halo, Vector3(0.0, 0.08, 0.0))
	ground.scale = Vector3(1.0, 0.2, 1.0)
	var beam := CylinderMesh.new()
	beam.top_radius = 0.04
	beam.bottom_radius = 0.2
	beam.height = 4.0
	_piece(pickup, beam, shell, Vector3(0.0, 2.0, 0.0))
	alpha_pickups.append(pickup)
	FX.ring(self, pickup.position, Color(ALPHA_VIOLET, 0.8), 0.3, 2.4, 0.6)
	return pickup


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
		var id := _create_corpse(location + Vector3(cos(angle), 0.0, sin(angle)) * 0.55, total / float(TUNING.NEST_CLUTCH))
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
	var aura_material := StandardMaterial3D.new()
	aura_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	aura_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	aura_material.albedo_color = Color(CURSE_COLOR, 0.75)
	var aura := TorusMesh.new()
	aura.inner_radius = 2.4
	aura.outer_radius = 2.95
	aura.rings = 48
	aura.ring_segments = 4
	var ring := _piece(target, aura, aura_material, Vector3(0.0, 0.12, 0.0))
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
	hud.hint = message
	hud.set_meta("kill_popups", _popup_screen())
	hud.set_meta("king_moments", king_moments)
	var objectives := _objective_hud()
	hud.set_meta("objectives", objectives)
	if "objectives" in hud:
		hud.set("objectives", objectives)
	hud.nearest_corpse = ""
	var nearest := INF
	for corpse in model.corpses:
		var offset: Vector3 = corpse.position - swarm.position
		var distance := offset.length()
		if distance < nearest:
			nearest = distance
			var direction := "hier"
			if distance > TUNING.HARVEST_RADIUS:
				direction = ("oben" if offset.z < 0 else "unten") if absf(offset.z) > absf(offset.x) else ("links" if offset.x < 0 else "rechts")
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
	if points.is_empty():
		share = 1.0 if enemy.contains(swarm.position) else 0.0
		impact = fallback_impact
	else:
		for index in points.size():
			if enemy.contains(points[index]):
				inside.append(index)
				impact += points[index]
		share = float(inside.size()) / float(points.size())
		impact = impact / float(inside.size()) if not inside.is_empty() else fallback_impact
	last_hit_share = share
	var loss := ceili(float(power) * share - 0.0001)
	if loss <= 0:
		return false
	if swarm.has_method("prefer_removal"):
		swarm.prefer_removal(inside)
	return _apply_hit(loss, impact, shake_amount, enemy)


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
	var main := get_parent()
	if main != null and main.has_method("king_moment"):
		main.king_moment(location)


# Resolves one announced hit. Returns true when the run ended by extinction.
func _apply_hit(loss: int, impact: Vector3, shake_amount: float, attacker: Node3D = null) -> bool:
	if enemy_damage != 1.0:
		loss = maxi(1, ceili(float(loss) * enemy_damage))
	unit_points_valid = false
	var before: int = model.population
	last_loss = model.apply_loss(evolution.loss_after_armor(loss, swarm.rally_pressed))
	swarm.set_population(model.population)
	swarm.react_to_hit(before - model.population, impact)
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
		_update_hud("Ausgestorben")
		return true
	return false


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


func _sfx_node() -> Node:
	return get_parent().get_node_or_null("Sfx") if get_parent() != null else null


func _sfx(id: String, vibrate_ms: int = 0) -> void:
	var player := _sfx_node()
	if player == null:
		return
	player.play(id)
	if vibrate_ms > 0:
		player.vibrate(vibrate_ms)


# Sound cues from state changes, so enemy scripts stay free of audio code.
func _audio_step(delta: float, population_before: int) -> void:
	if model.population > population_before:
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
