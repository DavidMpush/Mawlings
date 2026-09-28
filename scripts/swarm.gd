extends Node3D

const MAWLING_SCENE = preload("res://assets/gameplay/characters/Mawling_game.glb")
const CREATURE_SHADER = preload("res://shaders/creature_anim.gdshader")
const FX = preload("res://scripts/fx.gd")

const START_POPULATION := 25
const MOVE_SPEED := 7.0
# Stage 18b: every animal keeps this distance to a wall of the path map.
const UNIT_WALL_RADIUS := 0.3
const FOLLOW_SPEED := 7.0
const GOLDEN_ANGLE := 2.39996323
const VISUAL_LIMIT := 120

# Etappe 09: the leader is always units[0]. KERN owns its hit points and death;
# this script only shows them (size, rim, ground ring, HUD crown and pips).
const LEADER := 0
const LEADER_SCALE := 1.45
const LEADER_HIT_SECONDS := 0.35
const CROWN_JUMP_SECONDS := 0.5
const INVULNERABLE_BLINK := 7.0     # blinks per second while invulnerable
# Formation: the leader takes the centre, the others spiral around it.
const LEADER_GAP := 1.5
# The leader is bound tightly to the swarm centre: own fast follow rate, no trail,
# almost no wander, only a small lean towards the focus.
const LEADER_FOLLOW_SPEED := 22.0
const LEADER_WANDER := 0.04
const LEADER_FOCUS_SHARE := 0.35
# Stage 27 E (Glutsprung): above this arc height (m) the swarm counts as in the
# air; the animals then tuck to LEAP_TUCK of their formation radius.
const LEAP_AIRBORNE := 0.05
const LEAP_TUCK := 0.2
const LEAP_TUCK_SPEED := 14.0
# Cell division (split_new_units): swell, then pinch and slide out.
const SPLIT_SWELL := 0.25
const SPLIT_SLIDE := 0.32
const SPLIT_PARALLEL := 6
const MAX_SPLITS := 60
const MILESTONES := [5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000]
const MILESTONE_GLOW_SECONDS := 0.9

# Purely visual tuning; none of this feeds back into game state.
const WANDER := 0.15
const TRAIL_SECONDS := 0.07
const HOP_HEIGHT := 0.2
const GAIT_RATE := 11.0
const HATCH_SECONDS := 0.3
const FLASH_SECONDS := 0.25
const PUSH_RADIUS := 5.0
const PUSH_SPEED := 9.0
const PUSH_DAMPING := 6.0
const MAX_GHOSTS := 28
const MAX_HIT_COPIES := 12
const GHOST_REAR := 0.14
const GHOST_FLIGHT := 0.8
const GHOST_SHRINK := 0.3
const GHOST_GRAVITY := 16.0
const GHOST_AXIS := Vector3(0.8, 0.0, 0.6)
const MAX_SPOTS := 24
const SPOT_SECONDS := 2.6
const SHADOW_Y := 0.03
const HALO_Y := 0.012
const CORAL := Color(1.0, 0.45, 0.25)
const CORAL_LIGHT := Color(1.0, 0.68, 0.48)
const DEFAULT_RIM := Color("ffb27a")
const CROWN_GOLD := Color("ffd35c")

enum Focus { NONE, ATTACK, HARVEST }

var movement_vector := Vector2.ZERO
# Run configuration: strain speed multiplier and colour accent.
var speed_multiplier := 1.0
## Stage 17d (Hetzjagd): the swarm stretches into a line behind the leader along
## `line_direction`; `leap_height` (m) lifts every animal (Glutsprung arc).
var line_formation := false
var line_direction := Vector3(0, 0, -1)
var line_blend := 0.0
var leap_height := 0.0
const LINE_SPACING := 0.55
var coral := CORAL
var coral_light := CORAL_LIGHT
var rim_tint := DEFAULT_RIM
var rim_amount := 0.45
var rally_pressed := false
# Logical Mawlings: lightweight Node3D data holders OUTSIDE the scene tree (no mesh).
# `position`/`rotation.y`/`scale` place a unit in swarm-local space, its child
# "Game model" carries the hop/roll/breath pose. All visible units are drawn by
# one MultiMeshInstance3D (`bodies`), fallen ghosts by `ghost_bodies`.
var units: Array[Node3D] = []
var population := START_POPULATION
var game_material: ShaderMaterial
var ghost_material: ShaderMaterial

# Per-unit animation state, index-aligned with `units`.
var unit_phase := PackedFloat32Array()
var unit_follow := PackedFloat32Array()
var unit_gait := PackedFloat32Array()
var unit_speed := PackedFloat32Array()
var unit_hatch := PackedFloat32Array()
var unit_push := PackedVector3Array()
var unit_bite := PackedFloat32Array()

# Falling-away ghosts of removed units; they are no longer part of `units`.
var ghosts: Array[Node3D] = []
var ghost_velocity := PackedVector3Array()
var ghost_age := PackedFloat32Array()
var ghost_spin := PackedFloat32Array()
var ghost_scale := PackedFloat32Array()
var fresh_ghost_from := 0
var removed_since_frame := 0
var pending_loss := 0
var pending_impact := Vector3.ZERO
# Units moved to the back by prefer_removal(); the next hit flings these first.
var hit_tail := 0
# Dark stains where fallen Mawlings lay (world positions, extra shadow instances).
var spot_position := PackedVector3Array()
var spot_age := PackedFloat32Array()

var focus_position := Vector3.ZERO
var focus_mode := 0
var attack_blend := 0.0
var harvest_blend := 0.0
var rally_blend := 0.0
var flash := 0.0
var clock := 0.0
var swarm_velocity := Vector3.ZERO
var display_scale := 0.91
# 1 for a handful of animals (bigger, more individual motion), 0 for the mass.
var individuality := 0.0

# Leader display state (set_leader_state / leader_hit / promote_leader).
var leader_hp := 0
var leader_max_hp := 0
var leader_invulnerable := false
var leader_hit_age := 99.0
var leader_swap_age := 99.0
var crown_from := Vector3.ZERO
# LP before the last hit (the HUD bar flashes the lost chunk) and its age.
var pip_broken := -1
var pip_break_age := 99.0
var _dead_leader: Node3D = null

# Cell division: {"child": Node3D or null, "parent": Node3D, "t": float, "side": Vector3, "popped": bool}
# t < 0 waits (stagger), 0..SPLIT_SWELL swells the parent, then the child slides out.
var splits: Array[Dictionary] = []
var _fx_shape := {}     # Node3D -> Vector4(scale xz, scale y, glow, hidden)
var _fx_offset := {}    # Node3D -> Vector3 render offset of a dividing parent (swarm-local)
var _fx_place := {}     # Node3D -> Vector3 position of a child inside/leaving its parent
var split_count := 0    # divisions shown so far (tests, HUD)
# Own seeded RNG for split parents/timing: the global RNG is randomised at start-up
# and also used by sounds, so it made seeded runs drift (balance_regress).
var rng := RandomNumberGenerator.new()

# Growth moments.
var peak_population := 0
var last_milestone := 0
var milestone_age := 99.0
var milestone_glow := 0.0
var _was_more := false
var heartbeat_on := false
## Rustle loop state (see _set_rustle); population where it is loudest.
const MAX_VISIBLE_RUSTLE := 120
var rustle_on := false
var rustle_db := 0.0

var shadows: MultiMeshInstance3D
# One draw call for all visible Mawlings; INSTANCE_CUSTOM = (walk, leg phase, bite, glow + 4 * leader).
var bodies: MultiMeshInstance3D
var ghost_bodies: MultiMeshInstance3D
var mawling_mesh: Mesh
# Transform of the glb's mesh node inside the model root (Z-up storage -> upright).
var mesh_local := Transform3D.IDENTITY
var halo: MeshInstance3D
var halo_material: StandardMaterial3D
var ring: MeshInstance3D
var ring_material: StandardMaterial3D
var leader_mark: MeshInstance3D
var leader_mark_material: StandardMaterial3D


func _ready() -> void:
	add_to_group("swarm")
	rng.seed = 90101
	game_material = _creature_material(0.0)
	ghost_material = _creature_material(0.45)
	# Fallen Mawlings darken towards a bruised red instead of washing out pale.
	ghost_material.set_shader_parameter("flash_color", Color("5c1c24"))
	_build_ground_marks()
	_build_bodies()
	set_population(START_POPULATION, false)
	for index in units.size():
		units[index].position = _formation_goal(index, units.size(), _flow_radius())
	_update_ground_marks(_flow_radius())
	_refresh_bodies()


func _notification(what: int) -> void:
	# Unit and ghost holders live outside the tree and are not freed with the swarm.
	if what == NOTIFICATION_PREDELETE:
		for unit in units:
			if is_instance_valid(unit):
				unit.free()
		units.clear()
		for ghost in ghosts:
			if is_instance_valid(ghost):
				ghost.free()
		ghosts.clear()


func set_population(value: int, animate: bool = true) -> void:
	# Without processing nothing would finish animating, so fall back to instant.
	animate = animate and is_inside_tree() and is_processing()
	var before := population
	population = maxi(0, value)
	var target := mini(population, VISUAL_LIMIT)
	var old_count := units.size()
	while units.size() < target:
		var index := units.size()
		var unit := _make_unit()
		unit.rotation.y = float(index) * GOLDEN_ANGLE
		if animate:
			unit.position = Vector3(cos(float(index)) * 0.25, 0.0, sin(float(index)) * 0.25)
		units.append(unit)
		unit_phase.append(fposmod(float(index) * 0.7548777, 1.0) * TAU)
		unit_follow.append(0.7 + 0.6 * fposmod(float(index) * 0.618034 + 0.31, 1.0))
		unit_gait.append(fposmod(float(index) * 1.3247, 1.0) * TAU)
		unit_speed.append(0.0)
		unit_hatch.append(1.0)
		unit_push.append(Vector3.ZERO)
		unit_bite.append(0.0)
		_pose_model(unit, 0.0, 0.0, 0.0, 1.0, 0.0)
		# Growth is a cell division of an older animal; without one it hatches.
		if animate and not _queue_split(unit, old_count):
			unit_hatch[index] = 0.0
			_pose_model(unit, 0.0, 0.0, 0.0, 0.0, 0.0)
	while units.size() > target:
		var unit: Node3D = units.pop_back()
		_forget_splits(unit)
		var was_dead_leader := unit == _dead_leader
		if animate:
			_launch_ghost(unit, Vector3.ZERO)
			removed_since_frame += 1
		else:
			unit.free()
		if was_dead_leader:
			_dead_leader = null
	var count := units.size()
	unit_phase.resize(count)
	unit_follow.resize(count)
	unit_gait.resize(count)
	unit_speed.resize(count)
	unit_hatch.resize(count)
	unit_push.resize(count)
	unit_bite.resize(count)
	# Above the visual limit growth shows as a division pulse of a random animal.
	if animate and population > before and count == old_count and count > 0:
		for n in mini(population - before, 3):
			_queue_split(null, count)
	if not animate:
		_clear_ghosts()
		splits.clear()
		_fx_shape.clear()
		_fx_offset.clear()
		_fx_place.clear()
		spot_position.resize(0)
		spot_age.resize(0)
		peak_population = population
		last_milestone = 0
		milestone_age = 99.0
		_was_more = false
		leader_swap_age = 99.0
		leader_hit_age = 99.0
		pip_break_age = 99.0
		_dead_leader = null
		display_scale = _scale_for(population)
	else:
		_check_milestones()
	if population > 1:
		_was_more = true
	for unit in units:
		unit.scale = Vector3.ONE * display_scale
	_refresh_bodies()


# World positions of the visible units (flat), index-aligned with `units`.
func unit_world_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	points.resize(units.size())
	var origin := global_transform if is_inside_tree() else transform
	for index in units.size():
		var point: Vector3 = origin * units[index].position
		point.y = 0.0
		points[index] = point
	return points


# Moves the given unit indices to the back of the formation, so the next
# set_population() drop removes exactly those animals (the ones inside a hit
# area) and the survivors close ranks by re-taking the freed formation slots.
# Etappe 09: the leader (index 0) is never moved back while the swarm lives;
# KERN decides about its death and calls promote_leader().
func prefer_removal(indices: PackedInt32Array) -> void:
	var count := units.size()
	if indices.is_empty() or count == 0:
		return
	var marked := {}
	for index in indices:
		if index >= 0 and index < count and (index != LEADER or population <= 0):
			marked[index] = true
	# A leader that already fell (promote_leader) stays last in line.
	var dead := units.find(_dead_leader) if _dead_leader != null else -1
	if dead > 0:
		marked.erase(dead)
	if marked.is_empty():
		return
	var order := PackedInt32Array()
	for index in count:
		if not marked.has(index) and index != dead:
			order.append(index)
	for index in count:
		if marked.has(index):
			order.append(index)
	if dead > 0:
		order.append(dead)
	_reorder(order)
	hit_tail = marked.size() + (1 if dead > 0 else 0)


# ---------------------------------------------------------------- leader API

## Leader display: hit points (Etappe 17c: a health bar in the HUD), maximum and
## the post-hit invulnerability (blink).
func set_leader_state(hp: int, max_hp: int, invulnerable: bool) -> void:
	hp = maxi(0, hp)
	max_hp = maxi(0, max_hp)
	# A lost chunk of LP flashes on the bar: pip_broken keeps the LP before the hit.
	if hp < leader_hp and max_hp == leader_max_hp:
		pip_broken = leader_hp
		pip_break_age = 0.0
	leader_hp = hp
	leader_max_hp = max_hp
	leader_invulnerable = invulnerable


## Feedback for a hit that cost the leader a hit point instead of its life.
func leader_hit(impact: Vector3) -> void:
	if units.is_empty():
		return
	leader_hit_age = 0.0
	var local := impact - _origin().origin
	local.y = 0.0
	var away := units[LEADER].position - local
	away.y = 0.0
	var direction := away.normalized() if away.length_squared() > 0.0004 else Vector3(1.0, 0.0, 0.0)
	unit_push[LEADER] += direction * PUSH_SPEED * 0.8
	if is_inside_tree():
		var at := _origin() * units[LEADER].position
		FX.ring(_fx_parent(), at, Color(1.0, 0.3, 0.2, 0.75), 0.4, 2.2, 0.35)
	# Sound: HuntWorld plays "leader_hit" (event sounds come from one place only).
	_vibrate(70)


## The leader died: the next animal becomes units[0] (crown jumps over). Call it
## BEFORE set_population() drops the population: the fallen leader is moved to
## the back, so exactly it falls with the next shrink.
func promote_leader() -> void:
	var count := units.size()
	if count < 2:
		return
	var old := units[LEADER]
	crown_from = _origin() * old.position
	# Successor: the first animal that is not still hidden inside a division.
	var successor := 1
	for index in range(1, count):
		var shape: Variant = _fx_shape.get(units[index])
		if shape == null or (shape as Vector4).w < 0.5:
			successor = index
			break
	_swap(LEADER, successor)
	# The fallen leader goes last in line (behind animals already marked by prefer_removal).
	var order := PackedInt32Array()
	for index in count:
		if index != successor:
			order.append(index)
	order.append(successor)
	_reorder(order)
	hit_tail += 1
	_dead_leader = old
	_forget_splits(old)
	leader_swap_age = 0.0
	leader_hit_age = 99.0
	pip_break_age = 99.0
	if is_inside_tree():
		var at := _origin() * units[LEADER].position
		FX.ring(_fx_parent(), at, Color(CROWN_GOLD.r, CROWN_GOLD.g, CROWN_GOLD.b, 0.8), 0.3, 2.6, 0.5)
	# Sound: HuntWorld plays "leader_swap".


## Cell division for the `count` most recently added animals (set_population()
## already divides animated growth; this only covers animals that appeared
## without one). Population never waits for the animation.
func split_new_units(count: int) -> void:
	if count <= 0 or units.is_empty() or not is_inside_tree():
		return
	var start := maxi(1, units.size() - count)
	var busy := {}
	for entry in splits:
		if entry.child != null:
			busy[entry.child] = true
	for index in range(start, units.size()):
		if not busy.has(units[index]) and unit_hatch[index] >= 1.0:
			_queue_split(units[index], start)


## Leader crown/pips for the HUD: world anchor above the leader, crown jump etc.
func leader_display() -> Dictionary:
	var visible_leader := not units.is_empty() and population > 0
	var anchor := Vector3.ZERO
	if visible_leader:
		anchor = _origin() * units[LEADER].position
		anchor.y = 1.75 * display_scale * LEADER_SCALE
	return {
		"visible": visible_leader,
		"anchor": anchor,
		"from": crown_from + Vector3(0.0, anchor.y, 0.0),
		"jump": clampf(leader_swap_age / CROWN_JUMP_SECONDS, 0.0, 1.0),
		"hp": leader_hp,
		"max_hp": leader_max_hp,
		"invulnerable": leader_invulnerable,
		"hit_age": leader_hit_age,
		"pip_broken": pip_broken,
		"pip_break_age": pip_break_age,
	}


func move_speed() -> float:
	return MOVE_SPEED * speed_multiplier


# Applies strain speed and tint from a RunConfig. creature_anim.gdshader has no
# albedo tint uniform, so the strain colour drives the rim light and the ground
# halo/Rally ring instead (a true body tint needs a shader uniform).
func apply_config(config: Dictionary) -> void:
	var mods: Dictionary = config.get("mods", {})
	speed_multiplier = clampf(float(mods.get("speed", 1.0)), 0.5, 2.0)
	var tint: Variant = config.get("tint", null)
	if tint is Color:
		coral = tint
		coral_light = (tint as Color).lightened(0.3)
		rim_tint = DEFAULT_RIM.lerp(tint, 0.8)
		rim_amount = 0.62
	else:
		coral = CORAL
		coral_light = CORAL_LIGHT
		rim_tint = DEFAULT_RIM
		rim_amount = 0.45
	# Glutmaw keeps the authored ember red; other strains recolour the body.
	var body := Color(1, 1, 1, 0)
	if tint is Color and String(config.get("strain_id", "glutmaw")) != "glutmaw":
		body = Color((tint as Color).r, (tint as Color).g, (tint as Color).b, 0.85)
	for material in [game_material, ghost_material]:
		if material != null:
			material.set_shader_parameter("body_tint", body)
			material.set_shader_parameter("rim_color", rim_tint)
			material.set_shader_parameter("rim_strength", rim_amount)
	if game_material != null:
		game_material.set_shader_parameter("leader_rim", _leader_color())
	if halo_material != null:
		halo_material.albedo_color = Color(coral.r, coral.g, coral.b, 0.1)


func set_controls(direction: Vector2, rally: bool) -> void:
	if rally and not rally_pressed and is_inside_tree() and not units.is_empty():
		var radius := _flow_radius() + 0.6
		FX.ring(self, global_position, Color(coral_light.r, coral_light.g, coral_light.b, 0.55), radius, radius * 0.42, 0.3)
		_play("rally")
	movement_vector = direction.limit_length(1.0)
	rally_pressed = rally


func set_focus(world_position: Vector3, mode: int) -> void:
	focus_mode = mode
	if mode != Focus.NONE:
		focus_position = world_position


func clear_focus() -> void:
	focus_mode = Focus.NONE


# Visual reaction to a resolved hit: flash, shove survivors, fling extra losses.
func react_to_hit(loss: int, impact: Vector3) -> void:
	if loss <= 0:
		return
	flash = 1.0
	game_material.set_shader_parameter("flash", flash)
	var local_impact := impact - global_position if is_inside_tree() else impact - position
	local_impact.y = 0.0
	for index in units.size():
		var away := units[index].position - local_impact
		away.y = 0.0
		var distance := away.length()
		if distance >= PUSH_RADIUS:
			continue
		var direction := away / distance if distance > 0.05 else Vector3(cos(unit_phase[index]), 0.0, sin(unit_phase[index]))
		unit_push[index] += direction * PUSH_SPEED * (1.0 - distance / PUSH_RADIUS)
	if is_processing():
		pending_loss += loss
		pending_impact = local_impact


# Set by Main while paused, choosing a mutation or extinct: poses hold still,
# only already-launched falling ghosts and the hit flash finish.
var frozen := false


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	if frozen:
		_update_ghosts(delta)
		if flash > 0.0:
			flash = maxf(0.0, flash - delta / FLASH_SECONDS)
			game_material.set_shader_parameter("flash", flash * flash)
		game_material.set_shader_parameter("idle_motion", 0.0)
		_set_heartbeat(false)
		_set_rustle(0.0)
		return
	game_material.set_shader_parameter("idle_motion", 1.0)
	var before := position
	var motion := Vector3(movement_vector.x, 0.0, movement_vector.y) * move_speed() * delta
	# Stage 27 E: mid-Glutsprung the ability carries the swarm (possibly over a
	# narrow obstacle); resolving it here would shove it out of that obstacle.
	if leap_height <= LEAP_AIRBORNE:
		position = get_parent().get_node("Arena").resolve_motion(position, motion, 0.75)
	swarm_velocity = (position - before) / delta if delta > 0.0 else Vector3.ZERO
	swarm_velocity.y = 0.0
	clock += delta
	leader_hit_age += delta
	leader_swap_age += delta
	pip_break_age += delta
	milestone_age += delta
	_resolve_pending_hit()
	_step_splits(delta)
	_animate_units(delta)
	_update_ghosts(delta)
	if flash > 0.0:
		flash = maxf(0.0, flash - delta / FLASH_SECONDS)
		game_material.set_shader_parameter("flash", flash * flash)
	if milestone_glow > 0.0:
		milestone_glow = maxf(0.0, milestone_glow - delta / MILESTONE_GLOW_SECONDS)
		game_material.set_shader_parameter("swarm_glow", milestone_glow * milestone_glow)
	# Last animal standing after the swarm was bigger: heartbeat loop.
	_set_heartbeat(population == 1 and _was_more)
	_set_rustle(swarm_velocity.length() / maxf(0.1, move_speed()))


# True when the straight line from the swarm centre to `point` passes a wall.
func _crosses_wall(field: Node, point: Vector3) -> bool:
	var centre := Vector3(position.x, 0.0, position.z)
	for sample in range(1, 7):
		if field.wall_distance(centre.lerp(point, float(sample) / 7.0)) < 0.0:
			return true
	return false


# The farthest open spot on the line from the swarm centre towards `spot`.
func _open_towards_centre(field: Node, spot: Vector3) -> Vector3:
	var centre := Vector3(position.x, 0.0, position.z)
	var best := centre
	for sample in range(1, 9):
		var probe := centre.lerp(spot, float(sample) / 8.0)
		if field.wall_distance(probe) < UNIT_WALL_RADIUS:
			break
		best = probe
	return best


func _animate_units(delta: float) -> void:
	var fade := 1.0 - exp(-6.0 * delta)
	rally_blend = lerpf(rally_blend, 1.0 if rally_pressed else 0.0, 1.0 - exp(-9.0 * delta))
	attack_blend = lerpf(attack_blend, 1.0 if focus_mode == Focus.ATTACK else 0.0, fade)
	harvest_blend = lerpf(harvest_blend, 1.0 if focus_mode == Focus.HARVEST else 0.0, fade)
	var wanted_scale := _scale_for(population)
	# Units only get a new scale while the size actually eases (saves 120 writes a frame).
	var rescale := absf(display_scale - wanted_scale) > 0.0005
	if rescale:
		display_scale = lerpf(display_scale, wanted_scale, 1.0 - exp(-3.0 * delta))
	individuality = _individuality(population)
	var unit_size := Vector3.ONE * display_scale
	var flow_radius := _flow_radius()
	var radius := lerpf(flow_radius, flow_radius * 0.42, rally_blend)
	var focus_local := focus_position - global_position
	focus_local.y = 0.0
	var focus_strength := attack_blend * 0.5 + harvest_blend * 0.3
	var reach := radius * 2.2 + 1.0
	var count := units.size()
	# Stage 18: near the map edge the animals stay inside the playable area
	# (fence in swarm-local metres; only active close to the edge).
	var fence := Rect2()
	var fenced := false
	var field: Node = get_parent().get_node_or_null("Arena") if get_parent() != null else null
	if field != null and field.has_method("playable_rect"):
		var play: Rect2 = field.playable_rect()
		fence = Rect2(play.position.x - position.x, play.position.y - position.z, play.size.x, play.size.y).grow(-0.3)
		fenced = not fence.grow(-(radius * 2.5 + 4.0)).has_point(Vector2.ZERO)
	# Stage 18b: close to a wall of the path map every animal is pushed out of
	# it (no Mawling stands inside the thicket or squeezes through a wall).
	var walled: bool = field != null and field.has_method("has_layout") and field.has_layout() and field.wall_distance(position) < radius * 2.5 + 4.0
	# Stage 27 E: mid-Glutsprung (the ability may carry the swarm over a narrow
	# obstacle) no animal is pushed out of walls; the push resumes on landing.
	var airborne := leap_height > LEAP_AIRBORNE
	var damping := exp(-PUSH_DAMPING * delta)
	var body_mesh := bodies.multimesh
	var shadow_mesh := shadows.multimesh
	var top_speed := move_speed()
	var speed_follow := 1.0 - exp(-8.0 * delta)
	var turn := 1.0 - exp(-10.0 * delta)
	var wander := WANDER + 0.45 * individuality
	# Jaw values only need refreshing while (or just after) attacking or harvesting.
	var bite_active := attack_blend + harvest_blend > 0.002
	var any_split := not _fx_shape.is_empty()
	var spiral := 1.0 / (float(count) + LEADER_GAP)
	line_blend = lerpf(line_blend, 1.0 if line_formation else 0.0, 1.0 - exp(-7.0 * delta))
	var line_back := Vector3(-line_direction.x, 0.0, -line_direction.z).normalized() if line_direction.length_squared() > 0.001 else Vector3(0, 0, 1)
	var line_side := Vector3(-line_back.z, 0.0, line_back.x)
	for index in count:
		var unit := units[index]
		if rescale:
			unit.scale = unit_size
		var phase := unit_phase[index]
		var follow := unit_follow[index]
		# Formation slot (same as _formation_goal): leader in the centre, spiral around.
		var goal := Vector3.ZERO
		var is_leader := index == LEADER
		var sway := LEADER_WANDER if is_leader else wander
		if not is_leader:
			var angle := float(index) * GOLDEN_ANGLE
			var reach_out := sqrt((float(index) + LEADER_GAP) * spiral) * radius
			goal = Vector3(cos(angle) * reach_out, 0.0, sin(angle) * reach_out)
			# Slower followers hang further back and stretch the swarm while moving.
			goal -= swarm_velocity * TRAIL_SECONDS * (2.3 - follow)
			if line_blend > 0.01:
				# Hetzjagd: a narrow column behind the leader (two files, slight zigzag).
				var rank := float(index) * 0.5
				var line_goal := line_back * (0.9 + rank * LINE_SPACING) + line_side * (0.35 if index % 2 == 0 else -0.35)
				goal = goal.lerp(line_goal, line_blend)
		goal.x += sway * sin(clock * 0.7 + phase)
		goal.z += sway * cos(clock * 0.53 + phase * 1.7)
		var pull := 0.0
		if focus_strength > 0.01 and not airborne:
			var to_focus := focus_local - goal
			var distance := to_focus.length()
			pull = focus_strength * clampf(1.0 - distance / reach, 0.2, 1.0)
			goal += to_focus.limit_length(2.6) * pull * (LEADER_FOCUS_SHARE if is_leader else 1.0)
		var old := unit.position
		var response := 1.0 - exp(-(LEADER_FOLLOW_SPEED if is_leader else FOLLOW_SPEED * follow) * delta)
		if airborne:
			# Glutsprung: the animals tuck into a tight ball around the swarm
			# centre, so they all land on the open landing spot (none is left
			# on the near side of a hopped obstacle) and spread out from there.
			goal *= LEAP_TUCK
			response = maxf(response, 1.0 - exp(-LEAP_TUCK_SPEED * delta))
		var next := old.lerp(Vector3(goal.x, 0.0, goal.z), response)
		var push := unit_push[index]
		if push.length_squared() > 0.0001:
			next += push * delta
			unit_push[index] = push * damping
		next.y = 0.0
		# Division shape: only animals inside a division (or the leader) take the slow path.
		var special := index == LEADER
		var shape := Vector4.ZERO
		var offset := Vector3.ZERO
		if any_split and _fx_shape.has(unit):
			special = true
			shape = _fx_shape[unit]
			offset = _fx_offset.get(unit, Vector3.ZERO)
			# A child still inside (or sliding out of) its parent is placed by the division.
			if _fx_place.has(unit):
				next = _fx_place[unit]
		if fenced:
			next.x = clampf(next.x, fence.position.x, fence.end.x)
			next.z = clampf(next.z, fence.position.y, fence.end.y)
		# In the air the animals fly over the wall with the swarm; after landing
		# the push resumes (offsets are local, so they land with the swarm).
		if walled and not airborne:
			var spot := Vector3(position.x + next.x, 0.0, position.z + next.z)
			if field.wall_distance(spot) < UNIT_WALL_RADIUS:
				var pushed: Vector3 = field.push_walls(spot, UNIT_WALL_RADIUS)
				# Stage 29: the gradient may point out on the FAR side of a small
				# obstacle (a deep-water core); then pull the animal back along its
				# line to the swarm centre instead, so no one ends up behind it.
				if _crosses_wall(field, pushed):
					pushed = _open_towards_centre(field, spot)
				next.x = pushed.x - position.x
				next.z = pushed.z - position.z
		unit.position = next
		# Own world velocity drives facing and gait.
		var velocity := (next - old) / maxf(delta, 0.001) + swarm_velocity
		velocity.y = 0.0
		var speed := velocity.length()
		var speed_share := lerpf(unit_speed[index], clampf(speed / top_speed, 0.0, 1.0), speed_follow)
		unit_speed[index] = speed_share
		if speed > 0.45:
			unit.rotation.y = lerp_angle(unit.rotation.y, atan2(velocity.x, velocity.z) + PI * 0.5, turn)
		elif pull > 0.05:
			var look := focus_local - next
			if look.length_squared() > 0.04:
				unit.rotation.y = lerp_angle(unit.rotation.y, atan2(look.x, look.z) + PI * 0.5, turn * 0.6)
		elif individuality > 0.0:
			# A handful of animals look around on their own while standing.
			unit.rotation.y += sin(clock * 0.9 + phase * 2.3) * 0.9 * individuality * delta
		# Waddling hop gait; its phase advances with speed so idle animals rest.
		var gait := unit_gait[index] + delta * GAIT_RATE * (0.85 + 0.3 * follow) * speed_share
		unit_gait[index] = fmod(gait, TAU * 8.0)
		var hop := absf(sin(gait)) * HOP_HEIGHT * speed_share + leap_height
		if individuality > 0.0:
			hop += pow(maxf(0.0, sin(clock * 1.7 + phase * 3.0)), 12.0) * 0.12 * individuality * (1.0 - speed_share)
		var roll := sin(gait) * 0.16 * speed_share
		var pitch := 0.12 * speed_share
		var jaw := 0.0
		if pull > 0.05:
			var bite := pow(maxf(0.0, sin(clock * 14.0 + phase * 3.0)), 3.0) * 0.5
			var peck := pow(0.5 + 0.5 * sin(clock * 4.5 + phase * 2.0), 2.0) * 0.55
			var weight := clampf(pull / 0.3, 0.0, 1.0)
			pitch += (bite * attack_blend + peck * harvest_blend) * weight
			jaw = clampf((bite * 2.0 * attack_blend + peck * harvest_blend) * weight, 0.0, 1.0)
		var breath := sin(clock * 2.2 + phase) * (0.035 + 0.03 * individuality) * (1.0 - speed_share)
		var hatch := unit_hatch[index]
		if hatch < 1.0:
			hatch = minf(1.0, hatch + delta / HATCH_SECONDS)
			unit_hatch[index] = hatch
		var grown := _back_out(hatch)
		var pose := _pose_model(unit, hop, roll, pitch, grown, breath)
		# Leg cycle (creature_anim.gdshader) locked to the hop: feet land as the hop ends.
		if bite_active:
			unit_bite[index] = jaw
		var shadow_size := display_scale * 1.05 * grown * maxf(0.35, 1.0 - hop * 1.4 + leap_height * 1.2)
		if not special:
			body_mesh.set_instance_transform(index, unit.transform * pose * mesh_local)
			body_mesh.set_instance_custom_data(index, Color(speed_share, fmod(gait, TAU) + PI * 0.5, unit_bite[index], 0.0))
			shadow_mesh.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3(shadow_size, 1.0, shadow_size)), Vector3(next.x, SHADOW_Y, next.z)))
			continue
		if shape.x == 0.0:
			shape = Vector4(1.0, 1.0, 0.0, 0.0)
		var glow := shape.z
		var extra := 1.0
		var leader_flag := 0.0
		if index == LEADER:
			extra = _leader_extra()
			glow = _leader_glow(glow)
			leader_flag = 4.0
		var place := unit.transform
		if shape.w > 0.5:
			place.basis = place.basis * 0.001
			shadow_size = 0.0
		else:
			place.basis = place.basis * Basis.from_scale(Vector3(shape.x, shape.y, shape.x) * extra)
			shadow_size *= extra * shape.x
		place.origin += offset
		body_mesh.set_instance_transform(index, place * pose * mesh_local)
		body_mesh.set_instance_custom_data(index, Color(speed_share, fmod(gait, TAU) + PI * 0.5, unit_bite[index], glow + leader_flag))
		shadow_mesh.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3(shadow_size, 1.0, shadow_size)), Vector3(next.x + offset.x, SHADOW_Y, next.z + offset.z)))
	body_mesh.visible_instance_count = count
	_write_spots(count)
	_update_ground_marks(radius)


# Formation slot of a unit: the leader stands in the centre, the others fill a
# golden-angle spiral around it (a gap in the middle leaves room for the leader).
func _formation_goal(index: int, count: int, radius: float) -> Vector3:
	if index == LEADER:
		return Vector3.ZERO
	var angle := float(index) * GOLDEN_ANGLE
	var fraction := sqrt((float(index) + LEADER_GAP) / (float(count) + LEADER_GAP))
	return Vector3(cos(angle) * fraction * radius, 0.0, sin(angle) * fraction * radius)


# Compatibility shim: units have no own mesh any more; the shared MultiMesh draws
# them (per-unit leg/bite values travel in INSTANCE_CUSTOM, not instance uniforms).
func _unit_mesh(_unit: Node3D) -> GeometryInstance3D:
	return bodies


func _pose_model(unit: Node3D, hop: float, roll: float, pitch: float, grown: float, breath: float) -> Transform3D:
	var model: Node3D = unit.get_child(0)
	var size := Vector3(grown * (1.0 - breath * 0.5), grown * (1.0 + breath), grown * (1.0 - breath * 0.5))
	var pose := Transform3D(Basis.from_euler(Vector3(roll, 0.0, pitch)).scaled(size), Vector3(0.0, hop, 0.0))
	model.transform = pose
	return pose


# Rewrites both MultiMeshes from the unit holders (population change, reset, or
# edits while the swarm does not process); _animate_units() does the same inline.
func _refresh_bodies() -> void:
	if bodies == null:
		return
	var body_mesh := bodies.multimesh
	var shadow_mesh := shadows.multimesh
	for index in units.size():
		var unit := units[index]
		var pose: Transform3D = (unit.get_child(0) as Node3D).transform
		var place := unit.transform
		var extra := LEADER_SCALE if index == LEADER else 1.0
		if index == LEADER:
			place.basis = place.basis * extra
		body_mesh.set_instance_transform(index, place * pose * mesh_local)
		body_mesh.set_instance_custom_data(index, Color(unit_speed[index], fmod(unit_gait[index], TAU) + PI * 0.5, unit_bite[index], 4.0 if index == LEADER else 0.0))
		var shadow_size := display_scale * 1.05 * extra * _back_out(unit_hatch[index]) * (1.0 - pose.origin.y * 1.4)
		var spot := unit.position
		shadow_mesh.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3(shadow_size, 1.0, shadow_size)), Vector3(spot.x, SHADOW_Y, spot.z)))
	body_mesh.visible_instance_count = units.size()
	_write_spots(units.size())


# Ghost holders store WORLD transforms; the ghost MultiMesh is top-level.
func _refresh_ghost_bodies() -> void:
	if ghost_bodies == null:
		return
	var ghost_mesh := ghost_bodies.multimesh
	var count := ghosts.size()
	for index in count:
		var ghost := ghosts[index]
		ghost_mesh.set_instance_transform(index, ghost.transform * (ghost.get_child(0) as Node3D).transform * mesh_local)
	ghost_mesh.visible_instance_count = count


func _update_ground_marks(radius: float) -> void:
	var visible_swarm := not units.is_empty()
	var halo_radius := radius + 0.6
	halo.visible = visible_swarm
	halo.scale = Vector3(halo_radius, 1.0, halo_radius)
	# Etappe 17b: a big swarm gets a stronger ground ring (it stands for the mass).
	var mass := clampf(_mass_level() / 5.0, 0.0, 1.0)
	halo_material.albedo_color = Color(coral.r, coral.g, coral.b, lerpf(0.10, 0.2, rally_blend) + 0.14 * mass)
	ring.visible = visible_swarm and rally_blend > 0.01
	var pulse := 1.0 + 0.04 * sin(clock * 9.0)
	ring.scale = Vector3(halo_radius * pulse, 0.3, halo_radius * pulse)
	ring_material.albedo_color = Color(coral_light.r, coral_light.g, coral_light.b, 0.6 * rally_blend)
	# Leader: a glowing ring on the ground under units[0].
	leader_mark.visible = visible_swarm and population > 0
	if leader_mark.visible:
		var leader := units[LEADER]
		var size := display_scale * _leader_extra() * 0.62 * (1.0 + 0.06 * sin(clock * 4.0))
		leader_mark.position = Vector3(leader.position.x, HALO_Y + 0.008, leader.position.z)
		leader_mark.scale = Vector3(size, 0.35, size)
		var color := _leader_color()
		var alpha := 0.75
		if leader_invulnerable:
			alpha = 0.25 if fmod(clock * INVULNERABLE_BLINK, 1.0) < 0.5 else 0.85
		if leader_hit_age < LEADER_HIT_SECONDS:
			color = color.lerp(Color(1.0, 0.25, 0.18), 1.0 - leader_hit_age / LEADER_HIT_SECONDS)
		leader_mark_material.albedo_color = Color(color.r, color.g, color.b, alpha)


# ---------------------------------------------------------------- leader look

func _leader_color() -> Color:
	return coral_light.lerp(CROWN_GOLD, 0.55).lightened(0.15)


# Size factor of the leader; a new leader grows into the role.
func _leader_extra() -> float:
	if leader_swap_age < CROWN_JUMP_SECONDS:
		var t := leader_swap_age / CROWN_JUMP_SECONDS
		return lerpf(1.0, LEADER_SCALE, _back_out(t))
	if leader_hit_age < LEADER_HIT_SECONDS:
		# Flinch: a short squeeze on the hit.
		return LEADER_SCALE * (1.0 - 0.12 * sin(PI * leader_hit_age / LEADER_HIT_SECONDS))
	return LEADER_SCALE


# Per-instance glow of the leader: red on a hit, blink while invulnerable, gold on promotion.
func _leader_glow(base: float) -> float:
	if leader_hit_age < LEADER_HIT_SECONDS:
		return -1.0 + leader_hit_age / LEADER_HIT_SECONDS
	if leader_swap_age < CROWN_JUMP_SECONDS * 1.4:
		return maxf(base, 1.0 - leader_swap_age / (CROWN_JUMP_SECONDS * 1.4))
	if leader_invulnerable:
		return maxf(base, 0.7 if fmod(clock * INVULNERABLE_BLINK, 1.0) < 0.5 else 0.0)
	return base


# ---------------------------------------------------------------- cell division

# Registers a division for `child` (null = only a pulse, above the visual limit).
# The parent is an older animal (index < parent_limit) near the child's slot.
func _queue_split(child: Node3D, parent_limit: int) -> bool:
	if parent_limit <= 0 or splits.size() >= MAX_SPLITS or units.is_empty():
		return false
	var busy := {}
	for entry in splits:
		busy[entry.parent] = true
		if entry.child != null:
			busy[entry.child] = true
	var target := Vector3.ZERO
	if child != null:
		target = _formation_goal(units.size() - 1, units.size(), _flow_radius())
	var parent: Node3D = null
	var best := INF
	for attempt in 5:
		var candidate := units[rng.randi() % parent_limit]
		if busy.has(candidate) and attempt < 4:
			continue
		if child == null:
			parent = candidate
			break
		var distance := candidate.position.distance_squared_to(target)
		if distance < best:
			best = distance
			parent = candidate
	if parent == null:
		return false
	if child != null:
		child.position = parent.position
	splits.append({"child": child, "parent": parent, "t": -rng.randf_range(0.0, 0.06), "side": Vector3.ZERO, "popped": false})
	return true


func _forget_splits(unit: Node3D) -> void:
	for index in range(splits.size() - 1, -1, -1):
		var entry: Dictionary = splits[index]
		if entry.parent == unit:
			# The child still appears, just without a parent to split from.
			if entry.child != null:
				var slot := units.find(entry.child)
				if slot >= 0:
					unit_hatch[slot] = 0.0
			splits.remove_at(index)
		elif entry.child == unit:
			splits.remove_at(index)
	_fx_shape.erase(unit)
	_fx_offset.erase(unit)
	_fx_place.erase(unit)


# Advances the divisions (at most SPLIT_PARALLEL at once, the rest waits) and
# fills _fx_shape/_fx_offset for this frame's drawing.
func _step_splits(delta: float) -> void:
	_fx_shape.clear()
	_fx_offset.clear()
	_fx_place.clear()
	if splits.is_empty():
		return
	var running := 0
	var total := SPLIT_SWELL + SPLIT_SLIDE
	# A long queue (big harvest bursts) plays faster, so no child hides for long.
	var backlog := maxi(0, splits.size() - SPLIT_PARALLEL)
	delta *= minf(4.0, 1.0 + float(backlog) / 8.0)
	var index := 0
	while index < splits.size():
		var entry: Dictionary = splits[index]
		var t: float = entry.t
		if t >= 0.0:
			running += 1
			t += delta
		elif running < SPLIT_PARALLEL:
			t += delta
			if t >= 0.0:
				running += 1
		entry.t = t
		if t >= total:
			splits.remove_at(index)
			continue
		_split_pose(entry, t)
		index += 1


func _split_pose(entry: Dictionary, t: float) -> void:
	var parent: Node3D = entry.parent
	var child: Node3D = entry.child
	var size := display_scale
	if t < SPLIT_SWELL:
		# Swell: the parent bloats and wobbles; the child waits hidden inside.
		var s := clampf(t / SPLIT_SWELL, 0.0, 1.0)
		var e := s * s * (3.0 - 2.0 * s)
		var wobble := sin(maxf(t, 0.0) * 42.0) * 0.05 * e
		_merge_shape(parent, Vector4(1.0 + 0.34 * e + wobble, 1.0 - 0.12 * e - wobble, 0.55 * e, 0.0))
		if child != null:
			_fx_shape[child] = Vector4(1.0, 1.0, 0.0, 1.0)
			_fx_place[child] = parent.position
		return
	var u := clampf((t - SPLIT_SWELL) / SPLIT_SLIDE, 0.0, 1.0)
	if not entry.popped:
		entry.popped = true
		split_count += 1
		var side := Vector3.ZERO
		if child != null:
			var slot := units.find(child)
			if slot >= 0:
				side = _formation_goal(slot, units.size(), _flow_radius()) - parent.position
		side.y = 0.0
		if side.length_squared() < 0.01:
			var angle := rng.randf() * TAU
			side = Vector3(cos(angle), 0.0, sin(angle))
		entry.side = side.normalized()
		# One plop per division, unless the growth cue already played it just now.
		var sfx := _sfx()
		if sfx != null and not (sfx.has_method("recently_played") and sfx.recently_played("split", 320)):
			_play("split", -5.0 * clampf(float(population) / 120.0, 0.0, 1.0))
		if population <= 40 and is_inside_tree():
			FX.ring(_fx_parent(), _origin() * parent.position, Color(1.0, 0.96, 0.8, 0.55), 0.15, 0.9 * size + 0.3, 0.3)
	var out := 1.0 - pow(1.0 - u, 3.0)
	var sep: Vector3 = entry.side * (0.75 * size) * out
	var shimmer := pow(1.0 - u, 1.5)
	# Pinch: the parent narrows at the moment of division, then settles with a bounce.
	var pinch := sin(PI * minf(1.0, u * 1.6)) * 0.14
	_merge_shape(parent, Vector4(1.0 + 0.34 * (1.0 - out) - pinch, 1.0 + 0.06 * sin(PI * u), shimmer, 0.0))
	_fx_offset[parent] = -sep * 0.35
	if child != null:
		_fx_shape[child] = Vector4(lerpf(0.55, 1.0, _back_out(u)) - pinch, 1.0, shimmer, 0.0)
		_fx_place[child] = parent.position + sep


func _merge_shape(unit: Node3D, shape: Vector4) -> void:
	var old: Variant = _fx_shape.get(unit)
	if old == null or shape.x > (old as Vector4).x:
		_fx_shape[unit] = shape


# ---------------------------------------------------------------- growth moments

func _check_milestones() -> void:
	if population <= peak_population:
		return
	for mark: int in MILESTONES:
		if peak_population < mark and population >= mark:
			last_milestone = mark
			milestone_age = 0.0
			milestone_glow = 1.0
			# Sound: HuntWorld plays "milestone" (RunModel.take_milestone()).
			_vibrate(40)
			if is_inside_tree():
				var radius := _flow_radius() + 0.8
				FX.ring(_fx_parent(), global_position, Color(CROWN_GOLD.r, CROWN_GOLD.g, CROWN_GOLD.b, 0.7), radius * 0.5, radius * 1.4, 0.6)
	peak_population = population


func _set_heartbeat(on: bool) -> void:
	if on == heartbeat_on:
		return
	heartbeat_on = on
	var sfx := _sfx()
	if sfx == null:
		return
	if on and sfx.has_method("start_loop"):
		sfx.start_loop("heartbeat")
	elif not on and sfx.has_method("stop_loop"):
		sfx.stop_loop("heartbeat")


## Soft rustle loop while the swarm moves: louder with size and speed, stopped
## when it stands still (with a little hysteresis) or is frozen (pause, end).
func _set_rustle(speed_share: float) -> void:
	var sfx := _sfx()
	if sfx == null or not sfx.has_method("start_loop"):
		return
	speed_share = clampf(speed_share, 0.0, 1.0)
	if speed_share < (0.08 if rustle_on else 0.2):
		if rustle_on:
			rustle_on = false
			sfx.stop_loop("rustle")
		return
	var size_share := clampf(float(population) / float(MAX_VISIBLE_RUSTLE), 0.0, 1.0)
	var volume := lerpf(-14.0, 0.0, size_share) + lerpf(-6.0, 0.0, speed_share)
	if not rustle_on:
		rustle_on = true
		rustle_db = volume
		sfx.start_loop("rustle", volume)
	elif absf(volume - rustle_db) > 0.5:
		rustle_db = volume
		sfx.set_loop_volume("rustle", volume)


# ---------------------------------------------------------------- hits and ghosts

func _resolve_pending_hit() -> void:
	if pending_loss > 0:
		# Aim this frame's fallen units away from the impact.
		for index in range(fresh_ghost_from, ghosts.size()):
			ghost_velocity[index] = _fling_velocity(ghosts[index].position - _origin().origin, pending_impact, ghost_spin[index])
		var copies := mini(pending_loss - removed_since_frame, MAX_HIT_COPIES)
		# Hit animals still in the list (population above the visual limit) are
		# at the back; their copies fly from where the hit actually landed.
		var tail := mini(hit_tail - removed_since_frame, units.size())
		for copy in copies:
			if units.is_empty() or ghosts.size() >= MAX_GHOSTS:
				break
			var source := units[units.size() - 1 - copy % tail] if tail > 0 else units[(copy * 37 + pending_loss) % units.size()]
			var ghost := _make_unit()
			ghost.transform = source.transform
			_pose_model(ghost, 0.0, 0.0, 0.0, 1.0, 0.0)
			_launch_ghost(ghost, pending_impact)
		# The death squeal is played by HuntWorld._apply_hit() (one place for events).
	pending_loss = 0
	removed_since_frame = 0
	hit_tail = 0
	fresh_ghost_from = ghosts.size()


func _launch_ghost(unit: Node3D, impact: Vector3) -> void:
	if ghosts.size() >= MAX_GHOSTS:
		unit.free()
		return
	# From here on the holder keeps its WORLD transform (drawn by ghost_bodies).
	var local := unit.position
	unit.transform = _origin() * unit.transform
	var spin := (fposmod(float(ghosts.size() + unit.get_instance_id()) * 0.618034, 1.0) - 0.5) * 16.0
	ghosts.append(unit)
	ghost_velocity.append(_fling_velocity(local, impact, spin))
	ghost_age.append(0.0)
	ghost_spin.append(spin)
	ghost_scale.append(LEADER_SCALE if unit == _dead_leader else 1.0)


func _fling_velocity(local: Vector3, impact: Vector3, spin: float) -> Vector3:
	var away := local - impact
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3(cos(spin), 0.0, sin(spin))
	return away.normalized() * 3.2 + Vector3(0.0, 5.0 + absf(spin) * 0.1, 0.0)


func _update_ghosts(delta: float) -> void:
	var index := ghosts.size() - 1
	var had_spots := not spot_age.is_empty()
	while index >= 0:
		var ghost := ghosts[index]
		var age := ghost_age[index] + delta
		if age >= GHOST_REAR + GHOST_FLIGHT + GHOST_SHRINK or not is_instance_valid(ghost):
			if is_instance_valid(ghost):
				ghost.free()
			_remove_ghost(index)
			index -= 1
			continue
		ghost_age[index] = age
		var size := display_scale * ghost_scale[index]
		if age < GHOST_REAR:
			# Rear up: head back, a little lift, then the fall.
			var r := sin(0.5 * PI * age / GHOST_REAR)
			_pose_model(ghost, 0.12 * r, 0.0, -0.75 * r, 1.0 + 0.12 * r, 0.0)
			ghost.scale = Vector3.ONE * size
			index -= 1
			continue
		var fly_age := age - GHOST_REAR
		if fly_age - delta < GHOST_FLIGHT and fly_age >= GHOST_FLIGHT:
			_add_spot(ghost.position, ghost_scale[index])
		var velocity := ghost_velocity[index]
		velocity.y -= GHOST_GRAVITY * delta
		var next := ghost.position + velocity * delta
		if next.y < 0.0:
			next.y = 0.0
			velocity = Vector3(velocity.x * 0.4, -velocity.y * 0.25, velocity.z * 0.4)
		ghost_velocity[index] = velocity
		ghost.position = next
		ghost.rotate_object_local(GHOST_AXIS, ghost_spin[index] * delta)
		var shrink := clampf((fly_age - GHOST_FLIGHT) / GHOST_SHRINK, 0.0, 1.0)
		ghost.scale = Vector3.ONE * maxf(size * (1.0 - shrink * shrink), 0.001)
		index -= 1
	_refresh_ghost_bodies()
	if had_spots:
		_age_spots(delta)


func _remove_ghost(index: int) -> void:
	ghosts.remove_at(index)
	ghost_velocity.remove_at(index)
	ghost_age.remove_at(index)
	ghost_spin.remove_at(index)
	ghost_scale.remove_at(index)
	if index < fresh_ghost_from:
		fresh_ghost_from -= 1


func _clear_ghosts() -> void:
	for ghost in ghosts:
		if is_instance_valid(ghost):
			ghost.free()
	ghosts.clear()
	ghost_velocity.resize(0)
	ghost_age.resize(0)
	ghost_spin.resize(0)
	ghost_scale.resize(0)
	fresh_ghost_from = 0
	removed_since_frame = 0
	pending_loss = 0
	hit_tail = 0
	_refresh_ghost_bodies()


# Dark stain where a fallen Mawling lay; fades after SPOT_SECONDS.
func _add_spot(world: Vector3, size: float) -> void:
	if spot_position.size() >= MAX_SPOTS:
		spot_position.remove_at(0)
		spot_age.remove_at(0)
	spot_position.append(Vector3(world.x, size, world.z))   # y carries the size
	spot_age.append(0.0)


func _age_spots(delta: float) -> void:
	for index in range(spot_age.size() - 1, -1, -1):
		spot_age[index] += delta
		if spot_age[index] >= SPOT_SECONDS:
			spot_position.remove_at(index)
			spot_age.remove_at(index)


# Stains follow the unit shadows in the same MultiMesh (instances count..).
func _write_spots(count: int) -> void:
	var shadow_mesh := shadows.multimesh
	var spots := spot_position.size()
	var inverse := _origin().affine_inverse()
	for index in spots:
		var age := spot_age[index]
		var grow := clampf(age / 0.18, 0.0, 1.0)
		var fade := 1.0 - clampf((age - SPOT_SECONDS * 0.6) / (SPOT_SECONDS * 0.4), 0.0, 1.0)
		var world := spot_position[index]
		var local := inverse * Vector3(world.x, 0.0, world.z)
		var size := display_scale * 1.1 * world.y * grow * fade
		shadow_mesh.set_instance_transform(count + index, Transform3D(Basis.from_scale(Vector3(size, 1.0, size * 0.8)), Vector3(local.x, SHADOW_Y - 0.004, local.z)))
	shadow_mesh.visible_instance_count = count + spots


# ---------------------------------------------------------------- helpers

func _reorder(order: PackedInt32Array) -> void:
	var old_units := units.duplicate()
	var old_phase := unit_phase.duplicate()
	var old_follow := unit_follow.duplicate()
	var old_gait := unit_gait.duplicate()
	var old_speed := unit_speed.duplicate()
	var old_hatch := unit_hatch.duplicate()
	var old_push := unit_push.duplicate()
	var old_bite := unit_bite.duplicate()
	for slot in order.size():
		var source := order[slot]
		units[slot] = old_units[source]
		unit_phase[slot] = old_phase[source]
		unit_follow[slot] = old_follow[source]
		unit_gait[slot] = old_gait[source]
		unit_speed[slot] = old_speed[source]
		unit_hatch[slot] = old_hatch[source]
		unit_push[slot] = old_push[source]
		unit_bite[slot] = old_bite[source]


func _swap(a: int, b: int) -> void:
	if a == b:
		return
	var unit := units[a]
	units[a] = units[b]
	units[b] = unit
	var f := unit_phase[a]
	unit_phase[a] = unit_phase[b]
	unit_phase[b] = f
	f = unit_follow[a]
	unit_follow[a] = unit_follow[b]
	unit_follow[b] = f
	f = unit_gait[a]
	unit_gait[a] = unit_gait[b]
	unit_gait[b] = f
	f = unit_speed[a]
	unit_speed[a] = unit_speed[b]
	unit_speed[b] = f
	f = unit_hatch[a]
	unit_hatch[a] = unit_hatch[b]
	unit_hatch[b] = f
	f = unit_bite[a]
	unit_bite[a] = unit_bite[b]
	unit_bite[b] = f
	var v := unit_push[a]
	unit_push[a] = unit_push[b]
	unit_push[b] = v


func _sfx() -> Node:
	if not is_inside_tree() or get_parent() == null:
		return null
	return get_parent().get_node_or_null("Sfx")


func _play(id: String, volume_db: float = 0.0) -> void:
	var sfx := _sfx()
	if sfx != null and sfx.has_method("play"):
		sfx.play(id, volume_db)


func _vibrate(ms: int) -> void:
	var sfx := _sfx()
	if sfx != null and sfx.has_method("vibrate"):
		sfx.vibrate(ms)


# Rings of the leader/division/milestone moments go to Main, so the swarm
# itself keeps its handful of geometry nodes.
func _fx_parent() -> Node:
	return get_parent() if get_parent() != null else self


func _origin() -> Transform3D:
	return global_transform if is_inside_tree() else transform


func _flow_radius() -> float:
	# Etappe 17b: beyond the visible limit every model stands for several animals;
	# the formation only widens logarithmically (dense, not sparse).
	var shown := minf(float(population), float(VISUAL_LIMIT))
	var radius := 2.65 + maxf(0.0, sqrt(shown / 25.0) - 1.0) * 0.55 + 0.45 * _mass_level()
	# A handful of animals stands closer together around the leader.
	return radius * clampf(sqrt(float(population) / 25.0), 0.55, 1.0)


# 0..1 weight of "few animals": full up to one, gone at 25.
func _individuality(value: int) -> float:
	var t := clampf(float(value - 1) / 24.0, 0.0, 1.0)
	return 1.0 - t * t * (3.0 - 2.0 * t)


# Visual size per animal: big and individual when few, smaller in the mass.
func _scale_for(value: int) -> float:
	if value <= 25:
		return lerpf(0.91, 1.22, _individuality(value))
	if value <= VISUAL_LIMIT:
		return lerpf(0.91, 0.66, clampf(float(value - 25) / float(VISUAL_LIMIT - 25), 0.0, 1.0))
	# Etappe 17b: above the visible limit the animals grow a little again with the mass.
	return minf(1.0, 0.66 + 0.065 * _mass_level_of(value))


## Doublings above the visible limit (0 up to 120 animals, ~5.4 at 5.000).
func _mass_level() -> float:
	return _mass_level_of(population)


static func _mass_level_of(value: int) -> float:
	return maxf(0.0, log(maxf(1.0, float(value) / float(VISUAL_LIMIT))) / log(2.0))


# Ease-out with a slight overshoot so hatchlings pop into place.
func _back_out(t: float) -> float:
	var s := t - 1.0
	return 1.0 + 2.70158 * s * s * s + 1.70158 * s * s


func _make_unit() -> Node3D:
	var unit := Node3D.new()
	unit.name = "Mawling"
	var model := Node3D.new()
	model.name = "Game model"
	unit.add_child(model)
	return unit


# The Mawling glb is read once: its single mesh plus the mesh node's placement
# inside the model root. Bodies and ghosts draw that mesh via MultiMesh.
func _build_bodies() -> void:
	var sample: Node3D = MAWLING_SCENE.instantiate()
	var piece: MeshInstance3D = sample.find_children("*", "MeshInstance3D", true, false)[0]
	mawling_mesh = piece.mesh
	mesh_local = Transform3D.IDENTITY
	var node: Node = piece
	while node != sample:
		mesh_local = (node as Node3D).transform * mesh_local
		node = node.get_parent()
	sample.free()
	game_material.set_shader_parameter("use_instance_custom", true)
	game_material.set_shader_parameter("leader_rim", _leader_color())
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	# GL Compatibility reads custom data as instance colour unless colours are on
	# too, so every instance carries a white colour (COLOR = vertex colour).
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = mawling_mesh
	multimesh.instance_count = VISUAL_LIMIT
	multimesh.visible_instance_count = 0
	for index in VISUAL_LIMIT:
		multimesh.set_instance_color(index, Color.WHITE)
	bodies = MultiMeshInstance3D.new()
	bodies.name = "Mawlings"
	bodies.multimesh = multimesh
	bodies.material_override = game_material
	bodies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bodies)
	var ghost_multimesh := MultiMesh.new()
	ghost_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	ghost_multimesh.mesh = mawling_mesh
	ghost_multimesh.instance_count = MAX_GHOSTS
	ghost_multimesh.visible_instance_count = 0
	ghost_bodies = MultiMeshInstance3D.new()
	ghost_bodies.name = "Fallen Mawlings"
	ghost_bodies.multimesh = ghost_multimesh
	ghost_bodies.material_override = ghost_material
	ghost_bodies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost_bodies.top_level = true
	add_child(ghost_bodies)


func _creature_material(base_flash: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CREATURE_SHADER
	material.set_shader_parameter("brightness", 1.2)
	material.set_shader_parameter("saturation", 1.15)
	material.set_shader_parameter("shape_light", 0.35)
	material.set_shader_parameter("rim_color", rim_tint)
	material.set_shader_parameter("rim_strength", rim_amount)
	material.set_shader_parameter("flash_color", Color("ffd9c9"))
	material.set_shader_parameter("flash", base_flash)
	# Limb animation frame for Mawling_game.glb, measured in raw mesh space (Z-up
	# storage): soles at z = +0.0008 (up = -Z), head/jaw towards -X, tail towards +X,
	# lateral = +Y. Feet centres (forward, lateral) from clustering the lowest 5 %
	# of vertices; the rest pose is already mid-stride (pair A spread, pair B tucked).
	material.set_shader_parameter("up_axis", Vector3(0.0, 0.0, -1.0))
	material.set_shader_parameter("forward_axis", Vector3(-1.0, 0.0, 0.0))
	material.set_shader_parameter("ground_offset", -0.0008)
	material.set_shader_parameter("foot_a_front", Vector2(0.239, -0.287))
	material.set_shader_parameter("foot_a_back", Vector2(-0.286, 0.205))
	material.set_shader_parameter("foot_b_front", Vector2(0.063, 0.239))
	material.set_shader_parameter("foot_b_back", Vector2(-0.052, -0.191))
	material.set_shader_parameter("foot_radius", 0.15)
	material.set_shader_parameter("leg_height", 0.22)
	material.set_shader_parameter("stride", 0.09)
	material.set_shader_parameter("lift", 0.09)
	material.set_shader_parameter("stride_centering", 0.5)
	# Script drives the cycle per instance (INSTANCE_CUSTOM of the body MultiMesh); ghosts stay still.
	material.set_shader_parameter("walk_speed", 0.0)
	material.set_shader_parameter("walk_amount", 0.0)
	material.set_shader_parameter("walk_scale", 1.0 if base_flash <= 0.0 else 0.0)
	material.set_shader_parameter("jaw_hinge_forward", 0.12)
	material.set_shader_parameter("jaw_hinge_height", 0.47)
	material.set_shader_parameter("jaw_floor", 0.22)
	material.set_shader_parameter("jaw_angle", 0.45)
	material.set_shader_parameter("bite_amount", 0.0)
	material.set_shader_parameter("tail_start", -0.34)
	material.set_shader_parameter("tail_length", 0.26)
	material.set_shader_parameter("tail_floor", 0.1)
	material.set_shader_parameter("tail_swing", 0.06)
	material.set_shader_parameter("tail_rate", 3.0)
	return material


func _build_ground_marks() -> void:
	var shadow_gradient := Gradient.new()
	shadow_gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	shadow_gradient.colors = PackedColorArray([Color(0, 0, 0, 1), Color(0, 0, 0, 0.6), Color(0, 0, 0, 0)])
	var shadow_material := _ground_material(_radial_texture(shadow_gradient), Color(0, 0, 0, 0.38))
	shadow_material.render_priority = 1
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = plane
	multimesh.instance_count = VISUAL_LIMIT + MAX_SPOTS
	multimesh.visible_instance_count = 0
	shadows = MultiMeshInstance3D.new()
	shadows.name = "Shadows"
	shadows.multimesh = multimesh
	shadows.material_override = shadow_material
	shadows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadows)

	var halo_gradient := Gradient.new()
	halo_gradient.offsets = PackedFloat32Array([0.0, 0.78, 1.0])
	halo_gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	halo_material = _ground_material(_radial_texture(halo_gradient), Color(CORAL.r, CORAL.g, CORAL.b, 0.1))
	var disc := PlaneMesh.new()
	disc.size = Vector2(2.0, 2.0)
	halo = MeshInstance3D.new()
	halo.name = "Swarm halo"
	halo.mesh = disc
	halo.material_override = halo_material
	halo.position.y = HALO_Y
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)

	ring_material = _ground_material(null, Color(CORAL_LIGHT.r, CORAL_LIGHT.g, CORAL_LIGHT.b, 0.0))
	var torus := TorusMesh.new()
	torus.inner_radius = 0.93
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 6
	ring = MeshInstance3D.new()
	ring.name = "Rally ring"
	ring.mesh = torus
	ring.material_override = ring_material
	ring.position.y = HALO_Y + 0.005
	ring.visible = false
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)

	# Leader ground ring (one more draw call; the swarm stays within 6 geometry nodes).
	leader_mark_material = _ground_material(null, Color(CROWN_GOLD.r, CROWN_GOLD.g, CROWN_GOLD.b, 0.75))
	leader_mark_material.render_priority = 2
	var leader_torus := TorusMesh.new()
	leader_torus.inner_radius = 0.78
	leader_torus.outer_radius = 1.0
	leader_torus.rings = 32
	leader_torus.ring_segments = 4
	leader_mark = MeshInstance3D.new()
	leader_mark.name = "Leader ring"
	leader_mark.mesh = leader_torus
	leader_mark.material_override = leader_mark_material
	leader_mark.visible = false
	leader_mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(leader_mark)


func _ground_material(texture: Texture2D, tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = tint
	material.albedo_texture = texture
	return material


func _radial_texture(gradient: Gradient) -> GradientTexture2D:
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture
