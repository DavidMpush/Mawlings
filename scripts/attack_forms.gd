extends Node3D

# Angriffsformen (Etappe 03): vier aktive Mutationen plus zwei Evolutionen.
# Vertrag: stages/03_progression.md. Dieses Modul reduziert ausschließlich die
# Gesundheit der übergebenen Ziele (take_damage() oder 'health'), gibt nie
# Knoten frei und bewegt keine Mawlings. Alle Animationen laufen nur in step(),
# damit die Pause alles einfriert. Effekte und Projektile sind gepoolt.

const FORMS := {
	"rudelbiss": {
		"name": "Rudelbiss",
		"icon_hint": "jaws_leap",
		"ranks": [
			"Rally: alle 2,2 s Sprungangriff auf den nächsten Gegner (4 m), 8 Flächenschaden.",
			"Rally: alle 1,8 s Sprungangriff, 12 Flächenschaden.",
			"Rally: alle 1,4 s Sprungangriff, 16 Flächenschaden.",
		],
	},
	"sporenwolke": {
		"name": "Sporenwolke",
		"icon_hint": "spore_cloud",
		"ranks": [
			"Sporen-Aura (3 m): 3,5 Schaden/s, Gegner werden verlangsamt.",
			"Sporen-Aura (3,6 m): 6 Schaden/s, Gegner werden verlangsamt.",
			"Sporen-Aura (4,2 m): 9 Schaden/s, Gegner werden verlangsamt.",
		],
	},
	"saeurespucker": {
		"name": "Säurespucker",
		"icon_hint": "acid_drop",
		"ranks": [
			"Alle 1,3 s ein Säureschuss auf den nächsten Gegner (9 m), 5 Schaden.",
			"Alle 1,1 s ein Säureschuss, 7,5 Schaden.",
			"Alle 0,9 s ein Säureschuss, 10 Schaden.",
		],
	},
	"stachelruecken": {
		"name": "Stachelrücken",
		"icon_hint": "spikes",
		"ranks": [
			"Wer den Schwarm trifft, erleidet 20 Schaden + 3 je verlorenem Mawling.",
			"Rückstoß-Stacheln: 34 Schaden + 3 je verlorenem Mawling.",
			"Rückstoß-Stacheln: 48 Schaden + 3 je verlorenem Mawling.",
		],
	},
	"meute": {
		"name": "Meute",
		"icon_hint": "pack_leap",
		"evolved": true,
		"base": "rudelbiss",
		"requires": "pack",
		"ranks": [
			"Evolution von Rudelbiss: springt auch ohne Rally alle 1,2 s, Radius 2,4 m, 16 Schaden – doppelt bei Rally.",
		],
	},
	"aetzflut": {
		"name": "Ätzflut",
		"icon_hint": "acid_pool",
		"evolved": true,
		"base": "saeurespucker",
		"requires": "glutton",
		"ranks": [
			"Evolution von Säurespucker: jeder Treffer hinterlässt 2 s eine Säurepfütze (1,2 m, 4 Schaden/s).",
		],
	},
}

const RUDELBISS_INTERVAL := [2.2, 1.8, 1.4]
const RUDELBISS_DAMAGE := [8.0, 12.0, 16.0]
const RUDELBISS_RADIUS := 1.6
const RUDELBISS_REACH := 4.0
const LEAP_SECONDS := 0.24
const MEUTE_INTERVAL := 1.2
const MEUTE_RADIUS := 2.4
const MEUTE_RALLY_MULTIPLIER := 2.0

const SPORE_RADIUS := [3.0, 3.6, 4.2]
# Etappe 05 Balance: Aura war mit Abstand die schwächste Form (Brutal-Median −45 % ggü. Säure).
const SPORE_DPS := [3.5, 6.0, 9.0]
const SPORE_SLOW := 0.6

# Etappe 05 Balance: Säure dominierte (9 m Reichweite, 17 Schaden/s auf Rang 3) – leicht gedämpft.
const SPIT_INTERVAL := [1.3, 1.1, 0.9]
const SPIT_REACH := 9.0
const SPIT_SPEED := 14.0
const SPIT_DAMAGE := [5.0, 7.5, 10.0]
const SPIT_MAX_FLIGHT := 1.2
const SPIT_HEIGHT := 0.75

const PUDDLE_SECONDS := 2.0
const PUDDLE_RADIUS := 1.2
const PUDDLE_DPS := 4.0

# Etappe 05 Balance: Rückstoß greift nur bei Treffern und blieb zu schwach.
const SPINE_DAMAGE := [20.0, 34.0, 48.0]
const SPINE_PER_LOSS := 3.0
const SPINE_SECONDS := 0.42
const SPINE_COUNT := 12

const MAX_RINGS := 24
const MAX_PROJECTILES := 16
const MAX_PUDDLES := 10
const ARC_DOTS := 7
const SPORE_MOTES := 10

const FX_BATCH = preload("res://scripts/fx_batch.gd")
const QUALITY = preload("res://scripts/quality.gd")

const BITE_COLOR := Color(1.0, 0.62, 0.18)
const LEAP_CORE := Color(1.0, 0.93, 0.55)
const SPORE_COLOR := Color(0.8, 0.95, 0.32)
const ACID_COLOR := Color(0.45, 1.0, 0.3)
const SPINE_COLOR := Color(0.98, 0.9, 0.72)

var world: Node3D
var swarm: Node3D
var ranks := {}
# Summe des verursachten Schadens je Form (für Statistik/Tests).
var damage_dealt := {}

var _enemy_scale := 1.0
var _clock := 0.0
var _bite_timer := 0.0
var _spit_timer := 0.0
var _slowed := {}
var _built := false
var _current: Array = []
# Etappe 08: optionale Moorbrut-Horde (scripts/horde.gd). Ohne Horde verhält sich
# jede Form exakt wie vorher. Echte Ziele haben Vorrang; nur ohne sie zielen
# Rudelbiss und Säure auf die nächste Brut. Flächen treffen immer beide.
var horde: Node3D = null
var _leap_brood := false
var _spine_horde_cd := 0.0
const SPINE_HORDE_COOLDOWN := 0.5
const BROOD_TRACK := 1.6

var _leap_active := false
var _leap_age := 0.0
var _leap_from := Vector3.ZERO
var _leap_to := Vector3.ZERO
var _leap_target: Node3D
var _leap_damage := 0.0
var _leap_radius := RUDELBISS_RADIUS
var _arc_root: Node3D
var _leap_marker: MeshInstance3D
var _leap_marker_material: StandardMaterial3D
# Etappe 07: arc dots, spore motes, spines, rings and puddles are fx_batch.gd
# MultiMeshes (one draw call each, colour per instance, shared materials).
var _arc_batch: MultiMeshInstance3D
var _arc_count := ARC_DOTS

var _spore_root: Node3D
var _spore_edge: MeshInstance3D
var _spore_pulse: MeshInstance3D
var _spore_edge_material: StandardMaterial3D
var _spore_pulse_material: StandardMaterial3D
var _mote_batch: MultiMeshInstance3D
var _mote_count := SPORE_MOTES
var _spore_visual_radius := 0.0

var _spine_root: Node3D
var _spine_batch: MultiMeshInstance3D
var _spine_age := SPINE_SECONDS
var _spine_origin := Vector3.ZERO

var _rings: Array = []
var _ring_batch: MultiMeshInstance3D
var _thick_ring_batch: MultiMeshInstance3D
var _puddle_batch: MultiMeshInstance3D
var _puddle_rim_batch: MultiMeshInstance3D
var _trail_count := 2
var _projectiles: Array = []
var _puddles: Array = []

var _torus: TorusMesh
var _thick_torus: TorusMesh
var _dot_mesh: SphereMesh
var _mote_mesh: SphereMesh
var _bolt_mesh: SphereMesh
var _bolt_halo_mesh: SphereMesh
var _bolt_material: StandardMaterial3D
var _bolt_halo_material: StandardMaterial3D
var _bolt_trail_material: StandardMaterial3D
var _puddle_mesh: CylinderMesh


func setup(world_node: Node3D, swarm_node: Node3D) -> void:
	world = world_node
	swarm = swarm_node
	_build()


# id -> Rang (0..3); evolvierte IDs 'aetzflut' und 'meute' zählen als Rang 1.
func set_ranks(new_ranks: Dictionary) -> void:
	ranks = {}
	for id in new_ranks:
		var limit := 1 if FORMS.has(id) and FORMS[id].get("evolved", false) else 3
		ranks[id] = clampi(int(new_ranks[id]), 0, limit)


func set_horde(h: Node3D) -> void:
	horde = h


func rank(id: String) -> int:
	return int(ranks.get(id, 0))


func step(delta: float, targets: Array, rally: bool, enemy_scale: float) -> void:
	_build()
	_enemy_scale = maxf(0.0, enemy_scale)
	_clock += delta
	var origin := _swarm_position()
	var living := _living(targets)
	_current = living
	_spine_horde_cd = maxf(0.0, _spine_horde_cd - delta)
	_step_bite(delta, origin, living, rally)
	_step_spores(delta, origin, living)
	_step_spit(delta, origin, living)
	_step_projectiles(delta, living)
	_step_puddles(delta, living)
	_step_spines(delta)
	_step_rings(delta)


# Rückstoß für stachelruecken: sofortiger Schaden am Angreifer, Effekt läuft in step().
func on_swarm_hit(attacker: Node3D, loss: int) -> void:
	var level := rank("stachelruecken")
	if level <= 0:
		return
	_build()
	_spine_origin = _swarm_position()
	_spine_age = 0.0
	_ring(_spine_origin, SPINE_COLOR, 1.0, 3.2, SPINE_SECONDS)
	var amount: float = (SPINE_DAMAGE[level - 1] + float(maxi(0, loss)) * SPINE_PER_LOSS) * _enemy_scale
	# Stacheln treffen auch Brut am Schwarmrand (gedrosselt: Bisse kommen in Serie).
	if _has_horde() and _spine_horde_cd <= 0.0:
		_spine_horde_cd = SPINE_HORDE_COOLDOWN
		horde.damage_circle(_spine_origin, _spine_reach(), amount)
		_note_horde("stachelruecken", amount)
	if not _valid_target(attacker):
		return
	_hurt(attacker, amount, "stachelruecken")


func clear() -> void:
	_release_slow({})
	_leap_active = false
	_leap_target = null
	_current = []
	_bite_timer = 0.0
	_spit_timer = 0.0
	_spine_age = SPINE_SECONDS
	_leap_brood = false
	_spine_horde_cd = 0.0
	if not _built:
		return
	_arc_root.visible = false
	_leap_marker.visible = false
	_spine_root.visible = false
	_spore_root.visible = false
	for entry in _rings:
		entry.active = false
	for entry in _projectiles:
		entry.active = false
		entry.target = null
		entry.node.visible = false
	for entry in _puddles:
		entry.active = false
	_draw_rings()
	_draw_puddles()


func active_projectiles() -> int:
	var count := 0
	for entry in _projectiles:
		if entry.active:
			count += 1
	return count


func active_puddles() -> int:
	var count := 0
	for entry in _puddles:
		if entry.active:
			count += 1
	return count


func active_effects() -> int:
	var count := active_projectiles() + active_puddles()
	for entry in _rings:
		if entry.active:
			count += 1
	if _leap_active:
		count += 1
	if _spine_age < SPINE_SECONDS:
		count += 1
	return count


# --- Rudelbiss / Meute ---------------------------------------------------

func _step_bite(delta: float, origin: Vector3, living: Array, rally: bool) -> void:
	var level := rank("rudelbiss")
	var pack := rank("meute") > 0
	if level <= 0 and not pack:
		_leap_active = false
		_arc_root.visible = false
		_leap_marker.visible = false
		return
	_bite_timer = maxf(0.0, _bite_timer - delta)
	if _leap_active:
		_advance_leap(delta)
	if _leap_active or _bite_timer > 0.0 or (not rally and not pack):
		return
	var target := _nearest(living, origin, RUDELBISS_REACH)
	var brood := Vector3.INF
	if target == null:
		brood = _brood_near(origin, RUDELBISS_REACH)
		if brood == Vector3.INF:
			return
	var base: float = RUDELBISS_DAMAGE[maxi(level, 3 if pack else 1) - 1]
	if pack:
		_bite_timer = MEUTE_INTERVAL
		_leap_radius = MEUTE_RADIUS
		_leap_damage = base * (MEUTE_RALLY_MULTIPLIER if rally else 1.0)
	else:
		_bite_timer = RUDELBISS_INTERVAL[level - 1]
		_leap_radius = RUDELBISS_RADIUS
		_leap_damage = base
	_leap_damage *= _enemy_scale
	_leap_active = true
	_leap_age = 0.0
	_leap_from = origin
	_leap_target = target
	_leap_brood = target == null
	_leap_to = _flat(target.global_position) if target != null else brood
	_arc_root.visible = true
	_leap_marker.visible = true
	_pose_arc()


func _advance_leap(delta: float) -> void:
	_leap_age += delta
	if _valid_target(_leap_target):
		_leap_to = _flat(_leap_target.global_position)
	elif _leap_brood:
		_leap_to = _track_brood(_leap_to)
	if _leap_age < LEAP_SECONDS:
		_pose_arc()
		return
	_leap_active = false
	_leap_target = null
	_arc_root.visible = false
	_leap_marker.visible = false
	var tint := BITE_COLOR if rank("meute") <= 0 else Color(1.0, 0.42, 0.16)
	_ring(_leap_to, Color(tint.r, tint.g, tint.b, 0.95), _leap_radius * 0.6, _leap_radius * 1.1, 0.4, true)
	_ring(_leap_to, Color(LEAP_CORE.r, LEAP_CORE.g, LEAP_CORE.b, 0.9), 0.2, _leap_radius * 0.55, 0.26, true)
	var source := "meute" if rank("meute") > 0 else "rudelbiss"
	for target in _targets_near(_leap_to, _leap_radius):
		_hurt(target, _leap_damage, source)
	if _has_horde():
		horde.damage_circle(_leap_to, _leap_radius, _leap_damage)
		_note_horde(source, _leap_damage)
	_leap_brood = false


func _pose_arc() -> void:
	var progress := clampf(_leap_age / LEAP_SECONDS, 0.0, 1.0)
	var distance := _leap_from.distance_to(_leap_to)
	var height := 0.9 + distance * 0.25
	_arc_batch.begin()
	for index in _arc_count:
		# Die Punkte bilden einen kurzen Bogenabschnitt, der zum Ziel wandert.
		var t := clampf(progress - float(index) * 0.06, 0.0, 1.0)
		var point := _leap_from.lerp(_leap_to, t)
		point.y = 0.25 + sin(t * PI) * height
		var size := 1.0 - float(index) / float(ARC_DOTS)
		var tint := LEAP_CORE if index < 3 else Color(BITE_COLOR.r, BITE_COLOR.g, BITE_COLOR.b, 0.8)
		_arc_batch.add(Transform3D(Basis.from_scale(Vector3.ONE * maxf(0.25, size)), point), tint)
	_arc_batch.finish(false)
	# Landemarke: schrumpft während des Sprungs auf den Wirkradius zu.
	_leap_marker.global_position = Vector3(_leap_to.x, 0.15, _leap_to.z)
	var mark := lerpf(_leap_radius * 1.15, _leap_radius, progress)
	_leap_marker.scale = Vector3(mark, 0.4, mark)
	_leap_marker_material.albedo_color = Color(BITE_COLOR.r, BITE_COLOR.g, BITE_COLOR.b, 0.25 + 0.45 * progress)


# --- Sporenwolke ---------------------------------------------------------

func _step_spores(delta: float, origin: Vector3, living: Array) -> void:
	var level := rank("sporenwolke")
	if level <= 0:
		_spore_root.visible = false
		_release_slow({})
		return
	var radius: float = SPORE_RADIUS[level - 1]
	var dps: float = SPORE_DPS[level - 1] * _enemy_scale
	var inside := {}
	for target in living:
		if _flat_distance(target.global_position, origin) > radius:
			continue
		_hurt(target, dps * delta, "sporenwolke")
		if "slow_factor" in target:
			target.set("slow_factor", SPORE_SLOW)
			inside[target.get_instance_id()] = target
	_release_slow(inside)
	_slowed = inside
	if _has_horde():
		horde.damage_circle(origin, radius, dps * delta)
		_note_horde("sporenwolke", dps * delta)
	_pose_spores(origin, radius)


func _pose_spores(origin: Vector3, radius: float) -> void:
	_spore_root.visible = true
	_spore_root.global_position = Vector3(origin.x, 0.0, origin.z)
	_spore_visual_radius = lerpf(_spore_visual_radius, radius, 0.2) if _spore_visual_radius > 0.0 else radius
	var r := _spore_visual_radius
	_spore_edge.scale = Vector3(r, 0.3, r)
	_spore_edge_material.albedo_color = Color(SPORE_COLOR.r, SPORE_COLOR.g, SPORE_COLOR.b, 0.32 + 0.08 * sin(_clock * 3.0))
	# Ein Innenring läuft langsam nach außen und verblasst – zeigt die Aura-Wirkung.
	var wave := fmod(_clock * 0.55, 1.0)
	var inner := lerpf(r * 0.35, r, wave)
	_spore_pulse.scale = Vector3(inner, 0.3, inner)
	_spore_pulse_material.albedo_color = Color(SPORE_COLOR.r, SPORE_COLOR.g, SPORE_COLOR.b, 0.3 * (1.0 - wave))
	var mote_tint := Color(SPORE_COLOR.r, SPORE_COLOR.g, SPORE_COLOR.b, 0.42)
	_mote_batch.begin()
	for index in _mote_count:
		var phase := float(index) / float(_mote_count)
		var angle := phase * TAU + _clock * (0.35 + 0.1 * float(index % 3))
		var reach := r * (0.45 + 0.5 * fmod(phase * 3.7 + _clock * 0.08, 1.0))
		var lift := 0.35 + 0.35 * (0.5 + 0.5 * sin(_clock * 1.7 + phase * 11.0))
		var size := 0.8 + 0.35 * sin(_clock * 2.3 + phase * 7.0)
		_mote_batch.add(Transform3D(Basis.from_scale(Vector3.ONE * size), Vector3(cos(angle) * reach, lift, sin(angle) * reach)), mote_tint)
	_mote_batch.finish()


func _release_slow(keep: Dictionary) -> void:
	for id in _slowed:
		if keep.has(id):
			continue
		var target = _slowed[id]
		if is_instance_valid(target) and "slow_factor" in target:
			target.set("slow_factor", 1.0)
	_slowed = keep.duplicate()


# --- Säurespucker / Ätzflut ----------------------------------------------

func _step_spit(delta: float, origin: Vector3, living: Array) -> void:
	var level := rank("saeurespucker")
	if rank("aetzflut") > 0:
		level = 3
	if level <= 0:
		return
	_spit_timer = maxf(0.0, _spit_timer - delta)
	if _spit_timer > 0.0:
		return
	var target := _nearest(living, origin, SPIT_REACH)
	var brood := Vector3.INF
	if target == null:
		brood = _brood_near(origin, SPIT_REACH)
		if brood == Vector3.INF:
			return
	_spit_timer = SPIT_INTERVAL[level - 1]
	var entry: Dictionary = _take(_projectiles, MAX_PROJECTILES, _make_projectile)
	entry.active = true
	entry.age = 0.0
	entry.target = target
	entry.brood = target == null
	entry.aim = _flat(target.global_position) if target != null else brood
	entry.damage = SPIT_DAMAGE[level - 1] * _enemy_scale
	entry.node.visible = true
	entry.node.global_position = Vector3(origin.x, SPIT_HEIGHT, origin.z)
	for index in entry.trail.size():
		entry.trail[index].position = Vector3.ZERO
		entry.trail[index].visible = index < _trail_count


func _step_projectiles(delta: float, living: Array) -> void:
	for entry in _projectiles:
		if not entry.active:
			continue
		entry.age += delta
		var tracking: bool = _valid_target(entry.target)
		if tracking:
			entry.aim = _flat(entry.target.global_position)
		elif entry.brood:
			entry.aim = _track_brood(entry.aim)
		var node: Node3D = entry.node
		var goal: Vector3 = entry.aim + Vector3(0, 0.45, 0)
		var offset: Vector3 = goal - node.global_position
		var travel := SPIT_SPEED * delta
		node.scale = Vector3.ONE * (1.0 + 0.15 * sin(entry.age * 40.0))
		if offset.length() > travel and entry.age < SPIT_MAX_FLIGHT:
			var heading := offset.normalized()
			node.global_position += heading * travel
			for index in entry.trail.size():
				entry.trail[index].global_position = node.global_position - heading * 0.32 * float(index + 1)
			continue
		node.global_position = goal
		entry.active = false
		node.visible = false
		var hit_point: Vector3 = entry.aim
		if tracking:
			_hurt(entry.target, entry.damage, "saeurespucker")
			_ring(hit_point, Color(ACID_COLOR.r, ACID_COLOR.g, ACID_COLOR.b, 0.85), 0.15, 0.9, 0.25)
			if rank("aetzflut") > 0:
				_spawn_puddle(hit_point)
		elif entry.brood and _has_horde():
			var struck: Vector3 = horde.damage_nearest(hit_point, 1.0, entry.damage)
			if struck != Vector3.INF:
				_note_horde("saeurespucker", entry.damage)
				_ring(struck, Color(ACID_COLOR.r, ACID_COLOR.g, ACID_COLOR.b, 0.85), 0.15, 0.9, 0.25)
				if rank("aetzflut") > 0:
					_spawn_puddle(struck)
		entry.target = null
		entry.brood = false


func _spawn_puddle(location: Vector3) -> void:
	var entry: Dictionary = _take(_puddles, MAX_PUDDLES, _make_puddle)
	entry.active = true
	entry.age = 0.0
	entry.center = _flat(location)
	_draw_puddles()


func _step_puddles(delta: float, living: Array) -> void:
	for entry in _puddles:
		if not entry.active:
			continue
		entry.age += delta
		if entry.age >= PUDDLE_SECONDS:
			entry.active = false
			continue
		for target in living:
			if _flat_distance(target.global_position, entry.center) <= PUDDLE_RADIUS:
				_hurt(target, PUDDLE_DPS * _enemy_scale * delta, "aetzflut")
		if _has_horde():
			horde.damage_circle(entry.center, PUDDLE_RADIUS, PUDDLE_DPS * _enemy_scale * delta)
			_note_horde("aetzflut", PUDDLE_DPS * _enemy_scale * delta)
	_draw_puddles()


# Pfuetzen: Scheibe (vor anderen Transparenzen) plus Rand, je eine MultiMesh.
func _draw_puddles() -> void:
	if not _built:
		return
	_puddle_batch.begin()
	_puddle_rim_batch.begin()
	for entry in _puddles:
		if not entry.active:
			continue
		var t: float = entry.age / PUDDLE_SECONDS
		var grow := minf(1.0, t * 8.0)
		var radius := PUDDLE_RADIUS * (0.4 + 0.6 * grow)
		var fade := 1.0 - smoothstep(0.7, 1.0, t)
		var bubble := 0.06 * sin(_clock * 9.0 + entry.center.x)
		var at := Vector3(entry.center.x, 0.05, entry.center.z)
		_puddle_batch.add(Transform3D(Basis.from_scale(Vector3(radius, 1.0, radius)), at), Color(0.62, 0.9, 0.18, (0.3 + bubble) * fade))
		# Rand wie frueher: Kind der Scheibe mit Skalierung (1, 0.25, 1) und 4 cm Hoehe.
		_puddle_rim_batch.add(Transform3D(Basis.from_scale(Vector3(radius, 0.25, radius)), at + Vector3(0.0, 0.04, 0.0)), Color(0.82, 1.0, 0.4, 0.75 * fade))
	_puddle_batch.finish()
	_puddle_rim_batch.finish()


# --- Stachelrücken -------------------------------------------------------

func _step_spines(delta: float) -> void:
	if _spine_age >= SPINE_SECONDS:
		_spine_root.visible = false
		return
	_spine_age += delta
	var t := clampf(_spine_age / SPINE_SECONDS, 0.0, 1.0)
	_spine_root.visible = t < 1.0
	var origin := _swarm_position()
	_spine_root.global_position = Vector3(origin.x, 0.0, origin.z)
	var out := 1.0 - pow(1.0 - minf(1.0, t * 2.2), 3.0)
	var shrink := 1.0 - smoothstep(0.55, 1.0, t)
	var tint := Color(SPINE_COLOR.r, SPINE_COLOR.g, SPINE_COLOR.b, shrink)
	_spine_batch.begin()
	for index in SPINE_COUNT:
		var angle := TAU * float(index) / float(SPINE_COUNT)
		var reach := 1.1 + out * 1.3
		var spine_basis := Basis.from_euler(Vector3(0, -angle, -PI * 0.5 + 0.35)).scaled_local(Vector3.ONE * maxf(0.01, shrink))
		_spine_batch.add(Transform3D(spine_basis, Vector3(cos(angle) * reach, 0.45, sin(angle) * reach)), tint)
	_spine_batch.finish(false)


# --- Ringe (gepoolt) -----------------------------------------------------

func _ring(location: Vector3, tint: Color, from_radius: float, to_radius: float, seconds: float, thick := false) -> void:
	if not _built:
		return
	var entry: Dictionary = _take(_rings, MAX_RINGS, _make_ring)
	entry.thick = thick
	entry.active = true
	entry.age = 0.0
	entry.duration = seconds
	entry.from_radius = from_radius
	entry.to_radius = to_radius
	entry.color = tint
	entry.at = Vector3(location.x, 0.16, location.z)
	_draw_rings()


func _step_rings(delta: float) -> void:
	for entry in _rings:
		if not entry.active:
			continue
		entry.age += delta
		if entry.age >= entry.duration:
			entry.active = false
	_draw_rings()


# Alle aktiven Ringe in zwei MultiMeshes (duenn/dick), Farbe und Alpha je Instanz.
func _draw_rings() -> void:
	if not _built:
		return
	_ring_batch.begin()
	_thick_ring_batch.begin()
	for entry in _rings:
		if not entry.active:
			continue
		var progress: float = clampf(entry.age / entry.duration, 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - progress, 3.0)
		var radius: float = lerpf(entry.from_radius, entry.to_radius, eased)
		var tint: Color = entry.color
		var batch: MultiMeshInstance3D = _thick_ring_batch if entry.thick else _ring_batch
		batch.add(Transform3D(Basis.from_scale(Vector3(radius, 0.4, radius)), entry.at), Color(tint.r, tint.g, tint.b, tint.a * (1.0 - progress * progress)))
	_ring_batch.finish()
	_thick_ring_batch.finish()


# --- Schaden und Zielwahl ------------------------------------------------

func _hurt(target, amount: float, source: String) -> void:
	if amount <= 0.0 or not is_instance_valid(target):
		return
	if target.has_method("take_damage"):
		target.call("take_damage", amount)
	elif "health" in target:
		target.set("health", float(target.get("health")) - amount)
	else:
		return
	damage_dealt[source] = float(damage_dealt.get(source, 0.0)) + amount


func _valid_target(target) -> bool:
	if target == null or not is_instance_valid(target) or not (target is Node3D):
		return false
	if not (target as Node3D).is_inside_tree() or target.is_queued_for_deletion():
		return false
	if "health" in target and float(target.get("health")) <= 0.0:
		return false
	if target.has_method("can_be_hit") and not bool(target.call("can_be_hit")):
		return false
	return true


func _living(targets: Array) -> Array:
	var result: Array = []
	for target in targets:
		if _valid_target(target):
			result.append(target)
	return result


func _nearest(living: Array, origin: Vector3, reach: float) -> Node3D:
	var best: Node3D = null
	var best_distance := reach
	for target in living:
		var distance := _flat_distance(target.global_position, origin)
		if distance <= best_distance:
			best = target
			best_distance = distance
	return best


func _targets_near(center: Vector3, radius: float) -> Array:
	# _current wurde in diesem step() gefiltert; Schaden davor kann Ziele töten.
	var result: Array = []
	for target in _current:
		if _valid_target(target) and _flat_distance(target.global_position, center) <= radius:
			result.append(target)
	return result


# --- Moorbrut (optional) --------------------------------------------------

func _has_horde() -> bool:
	return horde != null and is_instance_valid(horde) and int(horde.call("count")) > 0


# Nächste Brut innerhalb `reach` (flach) oder Vector3.INF.
func _brood_near(origin: Vector3, reach: float) -> Vector3:
	if not _has_horde():
		return Vector3.INF
	var brood: Vector3 = horde.call("nearest", origin)
	if brood == Vector3.INF or _flat_distance(brood, origin) > reach:
		return Vector3.INF
	return _flat(brood)


# Folgt der Brut, die dem bisherigen Zielpunkt am nächsten ist (sie läuft weiter).
func _track_brood(aim: Vector3) -> Vector3:
	if not _has_horde():
		return aim
	var brood: Vector3 = horde.call("nearest", aim)
	if brood == Vector3.INF or _flat_distance(brood, aim) > BROOD_TRACK:
		return aim
	return _flat(brood)


func _note_horde(source: String, amount: float) -> void:
	var hits := int(horde.get("last_hit_count")) if horde != null and is_instance_valid(horde) else 0
	if hits > 0 and amount > 0.0:
		damage_dealt[source] = float(damage_dealt.get(source, 0.0)) + amount * float(hits)


func _spine_reach() -> float:
	var population := 25
	if swarm != null and is_instance_valid(swarm) and "population" in swarm:
		population = int(swarm.get("population"))
	# Schwarmradius wie swarm.gd (_flow_radius) plus Stachelreichweite.
	return 2.65 + maxf(0.0, sqrt(float(population) / 25.0) - 1.0) * 0.55 + 1.2


func _swarm_position() -> Vector3:
	if swarm != null and is_instance_valid(swarm) and swarm.is_inside_tree():
		return swarm.global_position
	return Vector3.ZERO


func _flat(location: Vector3) -> Vector3:
	return Vector3(location.x, 0.0, location.z)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- Aufbau und Pools ----------------------------------------------------

func _take(pool: Array, limit: int, factory: Callable) -> Dictionary:
	for entry in pool:
		if not entry.active:
			return entry
	if pool.size() < limit:
		var created: Dictionary = factory.call()
		pool.append(created)
		return created
	# Pool voll: den ältesten Eintrag wiederverwenden.
	var oldest: Dictionary = pool[0]
	for entry in pool:
		if entry.age > oldest.age:
			oldest = entry
	return oldest


func _make_ring() -> Dictionary:
	return {"active": false, "age": 0.0, "duration": 1.0, "thick": false, "at": Vector3.ZERO,
		"from_radius": 0.0, "to_radius": 1.0, "color": Color.WHITE}


func _make_projectile() -> Dictionary:
	var node := _mesh(self, _bolt_mesh, _bolt_material)
	node.top_level = true
	node.visible = false
	_mesh(node, _bolt_halo_mesh, _bolt_halo_material)
	var trail: Array = []
	for index in 2:
		var ghost := _mesh(node, _bolt_halo_mesh, _bolt_trail_material)
		ghost.scale = Vector3.ONE * (0.7 - 0.2 * float(index))
		trail.append(ghost)
	return {"trail": trail, "node": node, "active": false, "age": 0.0, "target": null, "aim": Vector3.ZERO, "damage": 0.0, "brood": false}


func _make_puddle() -> Dictionary:
	return {"active": false, "age": 0.0, "center": Vector3.ZERO}


# MultiMesh unter `parent`; top = Welt-Koordinaten (top-level am Ursprung).
func _batch(parent: Node, mesh: Mesh, capacity: int, node_name: String, transparent := true, top := true) -> MultiMeshInstance3D:
	var batch := FX_BATCH.create(mesh, capacity, transparent, true, node_name)
	parent.add_child(batch)
	if top:
		batch.top_level = true
		batch.transform = Transform3D.IDENTITY
	return batch


func _build() -> void:
	if _built:
		return
	_built = true
	_torus = TorusMesh.new()
	_torus.inner_radius = 0.9
	_torus.outer_radius = 1.0
	_torus.rings = 48
	_torus.ring_segments = 6
	_thick_torus = TorusMesh.new()
	_thick_torus.inner_radius = 0.78
	_thick_torus.outer_radius = 1.0
	_thick_torus.rings = 48
	_thick_torus.ring_segments = 6
	_dot_mesh = SphereMesh.new()
	_dot_mesh.radius = 0.26
	_dot_mesh.height = 0.52
	_dot_mesh.radial_segments = 10
	_dot_mesh.rings = 5
	_mote_mesh = SphereMesh.new()
	_mote_mesh.radius = 0.2
	_mote_mesh.height = 0.4
	_mote_mesh.radial_segments = 8
	_mote_mesh.rings = 4
	_bolt_mesh = SphereMesh.new()
	_bolt_mesh.radius = 0.24
	_bolt_mesh.height = 0.48
	_bolt_mesh.radial_segments = 10
	_bolt_mesh.rings = 5
	_bolt_halo_mesh = SphereMesh.new()
	_bolt_halo_mesh.radius = 0.36
	_bolt_halo_mesh.height = 0.72
	_bolt_halo_mesh.radial_segments = 10
	_bolt_halo_mesh.rings = 5
	_puddle_mesh = CylinderMesh.new()
	_puddle_mesh.top_radius = 1.0
	_puddle_mesh.bottom_radius = 1.0
	_puddle_mesh.height = 0.02
	_puddle_mesh.radial_segments = 28
	_puddle_mesh.rings = 1
	_bolt_material = _glow_material(Color(0.7, 1.0, 0.45), false)
	_bolt_halo_material = _glow_material(Color(ACID_COLOR.r, ACID_COLOR.g, ACID_COLOR.b, 0.35), true)
	_bolt_trail_material = _glow_material(Color(ACID_COLOR.r, ACID_COLOR.g, ACID_COLOR.b, 0.3), true)
	# Qualitaet: effect_density duennt nur Zierteile aus (Sporen, Bogenpunkte, Spuckspur).
	var density := clampf(float(QUALITY.value("effect_density", 1.0)), 0.0, 1.0)
	_mote_count = maxi(3, QUALITY.scaled_count(SPORE_MOTES, density))
	_arc_count = maxi(3, QUALITY.scaled_count(ARC_DOTS, density))
	_trail_count = QUALITY.scaled_count(2, density)
	_ring_batch = _batch(self, _torus, MAX_RINGS, "Ring batch")
	_thick_ring_batch = _batch(self, _thick_torus, MAX_RINGS, "Thick ring batch")
	_puddle_batch = _batch(self, _puddle_mesh, MAX_PUDDLES, "Puddle batch")
	# Pfuetzen liegen unter anderen Transparenzen (frueher render_priority -1).
	var puddle_material: StandardMaterial3D = _puddle_batch.material_override.duplicate()
	puddle_material.render_priority = -1
	_puddle_batch.material_override = puddle_material
	_puddle_rim_batch = _batch(self, _torus, MAX_PUDDLES, "Puddle rim batch")

	_arc_root = Node3D.new()
	_arc_root.name = "Leap arc"
	add_child(_arc_root)
	_arc_root.top_level = true
	_arc_root.visible = false
	_arc_batch = _batch(_arc_root, _dot_mesh, ARC_DOTS, "Leap arc dots")
	_leap_marker_material = _glow_material(BITE_COLOR, true)
	_leap_marker = _mesh(self, _thick_torus, _leap_marker_material)
	_leap_marker.top_level = true
	_leap_marker.visible = false

	_spore_root = Node3D.new()
	_spore_root.name = "Spore cloud"
	add_child(_spore_root)
	_spore_root.top_level = true
	_spore_root.visible = false
	_spore_edge_material = _glow_material(SPORE_COLOR, true)
	_spore_pulse_material = _glow_material(SPORE_COLOR, true)
	_spore_edge = _mesh(_spore_root, _torus, _spore_edge_material)
	_spore_edge.position.y = 0.12
	_spore_pulse = _mesh(_spore_root, _torus, _spore_pulse_material)
	_spore_pulse.position.y = 0.1
	_mote_batch = _batch(_spore_root, _mote_mesh, SPORE_MOTES, "Spore motes", true, false)

	_spine_root = Node3D.new()
	_spine_root.name = "Spine burst"
	add_child(_spine_root)
	_spine_root.top_level = true
	_spine_root.visible = false
	var spine_mesh := CylinderMesh.new()
	spine_mesh.top_radius = 0.0
	spine_mesh.bottom_radius = 0.11
	spine_mesh.height = 0.75
	spine_mesh.radial_segments = 6
	spine_mesh.rings = 1
	_spine_batch = _batch(_spine_root, spine_mesh, SPINE_COUNT, "Spines", true, false)
	_spine_batch.visible = true


func _glow_material(tint: Color, transparent: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = tint
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.no_depth_test = false
	return material


func _mesh(parent: Node, mesh: Mesh, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node
