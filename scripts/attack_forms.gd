extends Node3D

# Angriffsformen (Etappe 03): vier aktive Mutationen plus zwei Evolutionen;
# Etappe 10: Gräber, Blitzbiss, Brutsack plus Erdbeben und Sturmrudel.
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
			"Sporen-Aura (3 m): 5 Schaden/s, Gegner werden verlangsamt.",
			"Sporen-Aura (3,6 m): 8 Schaden/s, Gegner werden verlangsamt.",
			"Sporen-Aura (4,2 m): 11,5 Schaden/s, Gegner werden verlangsamt.",
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
			"Wer den Schwarm trifft, erleidet 26 Schaden + 5 je verlorenem Mawling.",
			"Rückstoß-Stacheln: 44 Schaden + 5 je verlorenem Mawling.",
			"Rückstoß-Stacheln: 62 Schaden + 5 je verlorenem Mawling.",
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
	# --- Etappe 10: drei neue Formen, zwei Evolutionen ---------------------
	"graeber": {
		"name": "Gräber",
		"icon_hint": "burrow",
		"ranks": [
			"Alle 2,6 s wühlt sich ein Tunnelstoß zum entferntesten Gegner (10 m) und bricht mit 10 Flächenschaden aus.",
			"Alle 2,2 s ein Tunnelstoß (11 m), 14 Flächenschaden.",
			"Alle 1,8 s ein Tunnelstoß (12 m), 19 Flächenschaden.",
		],
	},
	"blitzbiss": {
		"name": "Blitzbiss",
		"icon_hint": "chain_bite",
		"ranks": [
			"Alle 1,6 s ein Kettenbiss: springt zwischen bis zu 3 nahen Gegnern oder Brut, 5,5 Schaden (−15 % je Sprung).",
			"Alle 1,4 s ein Kettenbiss über bis zu 4 Ziele, 7,5 Schaden.",
			"Alle 1,2 s ein Kettenbiss über bis zu 5 Ziele, 9 Schaden.",
		],
	},
	"brutsack": {
		"name": "Brutsack",
		"icon_hint": "brood_sac",
		"ranks": [
			"Alle 3,2 s platzt eine Brutblase am Schwarm und setzt 2 Hilfs-Beißer frei (je 4 Schaden).",
			"Alle 2,8 s eine Brutblase mit 3 Hilfs-Beißern (je 5 Schaden).",
			"Alle 2,4 s eine Brutblase mit 4 Hilfs-Beißern (je 6 Schaden).",
		],
	},
	"erdbeben": {
		"name": "Erdbeben",
		"icon_hint": "quake",
		"evolved": true,
		"base": "graeber",
		"requires": "armor",
		"ranks": [
			"Evolution von Gräber: alle 1,6 s drei Tunnelstöße zugleich (12 m, 2,4 m, 19 Schaden), jeder mit Nachbeben (50 %).",
		],
	},
	"sturmrudel": {
		"name": "Sturmrudel",
		"icon_hint": "storm_pack",
		"evolved": true,
		"base": "blitzbiss",
		"requires": "jaws",
		"ranks": [
			"Evolution von Blitzbiss: alle 1,1 s (Rally 0,8 s) ein Kettenbiss über bis zu 6 Ziele, 9 Schaden ohne Abschwächung.",
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
# Etappe 10 Balance: seit dem Einzelstart (Etappe 09) war die Aura wieder klar hinten.
const SPORE_DPS := [5.0, 8.0, 11.5]
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
# Etappe 10 Balance: Stachelrücken lag im Formvergleich (Brutal) hinten.
const SPINE_DAMAGE := [26.0, 44.0, 62.0]
const SPINE_PER_LOSS := 5.0
const SPINE_SECONDS := 0.42
const SPINE_COUNT := 12

# --- Etappe 10 ------------------------------------------------------------
# Gräber: Tunnelstoß wandert unter der Erde zum entferntesten Ziel in Reichweite.
const GRAEBER_INTERVAL := [2.6, 2.2, 1.8]
const GRAEBER_REACH := [10.0, 11.0, 12.0]
const GRAEBER_DAMAGE := [10.0, 14.0, 19.0]
const GRAEBER_RADIUS := [1.6, 1.9, 2.2]
const GRAEBER_SPEED := 14.0
const ERUPTION_SECONDS := 0.45
const QUAKE_INTERVAL := 1.6
const QUAKE_TUNNELS := 3
const QUAKE_RADIUS := 2.4
const QUAKE_AFTERSHOCK := 0.5
const QUAKE_AFTERSHOCK_DELAY := 0.45
# Blitzbiss: Kette vom Schwarm zum nächsten Ziel, dann von Ziel zu Ziel.
const BLITZ_INTERVAL := [1.6, 1.4, 1.2]
const BLITZ_REACH := 5.0
const BLITZ_JUMP := 3.5
const BLITZ_TARGETS := [3, 4, 5]
const BLITZ_DAMAGE := [5.5, 7.5, 9.0]
const BLITZ_FALLOFF := 0.85
const BOLT_SECONDS := 0.3
const STORM_INTERVAL := 1.1
const STORM_RALLY_INTERVAL := 0.8
const STORM_REACH := 6.0
const STORM_JUMP := 4.5
const STORM_TARGETS := 6
const STORM_DAMAGE := 9.0
# Brutsack: Blase schwillt am Schwarmrand an, platzt, Hilfs-Beißer springen los.
# Rein Effekt und Schaden: die Population ändert sich nie.
const SAC_INTERVAL := [3.2, 2.8, 2.4]
const SAC_SENSE := 7.0
const SAC_OFFSET := 2.2
const SAC_GROW := 0.55
const SAC_BURST_RADIUS := 1.4
const SAC_BURST_DAMAGE := [4.0, 5.0, 6.0]
const SAC_BITERS := [2, 3, 4]
const SAC_BITE := [4.0, 5.0, 6.0]
const BITER_REACH := 4.5
const BITER_SPEED := 8.0
const BITER_LIFE := 1.0
# Dornenhaut (Anlage; der Schaden kommt aus Evolution.thorn_damage()).
const THORN_RADIUS := 1.6
const THORN_HORDE_COOLDOWN := 0.5

const MAX_TUNNELS := 8
const MAX_ERUPTIONS := 8
const ERUPTION_SHARDS := 7
const TUNNEL_TRAIL := 5
const MAX_BOLTS := 4
const BOLT_SUBDIV := 3
const MAX_SACS := 4
const MAX_BITERS := 16

const EARTH_COLOR := Color(0.55, 0.36, 0.2)
const EARTH_LIGHT := Color(0.98, 0.8, 0.46)
const BOLT_COLOR := Color(0.5, 0.86, 1.0)
const BOLT_CORE := Color(0.94, 0.99, 1.0)
const SAC_COLOR := Color(0.93, 0.36, 0.78)
const SAC_CORE := Color(1.0, 0.8, 0.95)
const THORN_COLOR := Color(0.62, 0.12, 0.3)

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

# Etappe 10: Pools und MultiMeshes der neuen Formen.
var _dig_timer := 0.0
var _chain_timer := 0.0
var _sac_timer := 0.0
var _thorn_horde_cd := 0.0
var _tunnels: Array = []
var _eruptions: Array = []
var _bolts: Array = []
var _sacs: Array = []
var _biters: Array = []
var _clump_batch: MultiMeshInstance3D
var _shard_batch: MultiMeshInstance3D
var _bolt_batch: MultiMeshInstance3D
var _spark_batch: MultiMeshInstance3D
var _sac_batch: MultiMeshInstance3D
var _biter_batch: MultiMeshInstance3D
var _trail_clumps := TUNNEL_TRAIL


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
	_thorn_horde_cd = maxf(0.0, _thorn_horde_cd - delta)
	_step_dig(delta, origin, living)
	_step_tunnels(delta)
	_step_chain(delta, origin, living, rally)
	_step_sacs(delta, origin, living)
	_step_biters(delta)
	_draw_extra()
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
	_dig_timer = 0.0
	_chain_timer = 0.0
	_sac_timer = 0.0
	_thorn_horde_cd = 0.0
	for pool in [_tunnels, _eruptions, _bolts, _sacs, _biters]:
		for entry in pool:
			entry.active = false
			if entry.has("target"):
				entry.target = null
	if not _built:
		return
	_draw_extra()
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
	for pool in [_tunnels, _eruptions, _bolts, _sacs, _biters]:
		for entry in pool:
			if entry.active:
				count += 1
	return count


# Etappe 10: aktive Einträge eines neuen Pools ("tunnels", "eruptions", "bolts", "sacs", "biters").
func active_count(kind: String) -> int:
	var pool: Array = {"tunnels": _tunnels, "eruptions": _eruptions, "bolts": _bolts, "sacs": _sacs, "biters": _biters}.get(kind, [])
	var count := 0
	for entry in pool:
		if entry.active:
			count += 1
	return count


# Etappe 10 – Dornenhaut: HuntWorld ruft das nach einem Nahkampf-/Kontakttreffer
# mit Evolution.thorn_damage(loss, leader_struck) auf. Schaden × enemy_scale am
# Angreifer (falls gültig) und an Brut im THORN_RADIUS um `impact` (gedrosselt).
func reflect_thorns(attacker: Node3D, amount: float, impact: Vector3) -> void:
	if amount <= 0.0:
		return
	_build()
	var scaled := amount * _enemy_scale
	var at := _flat(impact)
	_ring(at, Color(THORN_COLOR.r, THORN_COLOR.g, THORN_COLOR.b, 0.9), 0.4, THORN_RADIUS + 0.6, 0.3, true)
	if _has_horde() and _thorn_horde_cd <= 0.0:
		_thorn_horde_cd = THORN_HORDE_COOLDOWN
		horde.damage_circle(at, THORN_RADIUS, scaled)
		_note_horde("dornenhaut", scaled)
	if _valid_target(attacker):
		_hurt(attacker, scaled, "dornenhaut")


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


# --- Gräber / Erdbeben (Etappe 10) ---------------------------------------

func _step_dig(delta: float, origin: Vector3, living: Array) -> void:
	var level := rank("graeber")
	var quake := rank("erdbeben") > 0
	if level <= 0 and not quake:
		return
	_dig_timer = maxf(0.0, _dig_timer - delta)
	if _dig_timer > 0.0:
		return
	var index := 2 if quake else level - 1
	var aims := _farthest_aims(living, origin, GRAEBER_REACH[index], QUAKE_TUNNELS if quake else 1)
	if aims.is_empty():
		_dig_timer = 0.2
		return
	_dig_timer = QUAKE_INTERVAL if quake else GRAEBER_INTERVAL[index]
	for aim in aims:
		var entry: Dictionary = _take(_tunnels, MAX_TUNNELS, _make_tunnel)
		entry.active = true
		entry.age = 0.0
		entry.from = _flat(origin)
		entry.pos = _flat(origin)
		entry.to = aim.at
		entry.target = aim.target
		entry.brood = aim.target == null
		entry.damage = GRAEBER_DAMAGE[index] * _enemy_scale
		entry.radius = QUAKE_RADIUS if quake else GRAEBER_RADIUS[index]
		entry.source = "erdbeben" if quake else "graeber"
		entry.aftershock = quake
		entry.hidden = false


# Bis zu `count` Ziele, entfernteste zuerst: echte Gegner, sonst Brut (mit
# Mindestabstand, damit Erdbeben nicht dreimal denselben Klumpen trifft).
func _farthest_aims(living: Array, origin: Vector3, reach: float, count: int) -> Array:
	var ranked: Array = []
	for target in living:
		var distance := _flat_distance(target.global_position, origin)
		if distance <= reach:
			ranked.append([distance, target])
	ranked.sort_custom(func(a, b): return a[0] > b[0])
	var result: Array = []
	for entry in ranked:
		if result.size() >= count:
			break
		result.append({"target": entry[1], "at": _flat(entry[1].global_position)})
	if not result.is_empty() or not _has_horde():
		return result
	var brood: Array = []
	for point in horde.call("positions"):
		var distance := _flat_distance(point, origin)
		if distance <= reach:
			brood.append([distance, _flat(point)])
	brood.sort_custom(func(a, b): return a[0] > b[0])
	for entry in brood:
		if result.size() >= count:
			break
		var apart := true
		for chosen in result:
			if _flat_distance(chosen.at, entry[1]) < 2.0:
				apart = false
				break
		if apart:
			result.append({"target": null, "at": entry[1]})
	return result


func _step_tunnels(delta: float) -> void:
	for entry in _eruptions:
		if entry.active:
			entry.age += delta
			if entry.age >= ERUPTION_SECONDS:
				entry.active = false
	for entry in _tunnels:
		if not entry.active:
			continue
		entry.age += delta
		if entry.age < 0.0:
			continue
		if _valid_target(entry.target):
			entry.to = _flat(entry.target.global_position)
		elif entry.brood:
			entry.to = _track_brood(entry.to)
		var offset: Vector3 = entry.to - entry.pos
		var travel := GRAEBER_SPEED * delta
		if offset.length() > travel and entry.age < 2.0:
			entry.pos += offset.normalized() * travel
			continue
		var at: Vector3 = entry.to if offset.length() <= travel else entry.pos
		var damage: float = entry.damage
		var radius: float = entry.radius
		var source: String = entry.source
		var aftershock: bool = entry.aftershock
		entry.active = false
		entry.target = null
		_erupt(at, damage, radius, source)
		if aftershock:
			var shock: Dictionary = _take(_tunnels, MAX_TUNNELS, _make_tunnel)
			shock.active = true
			shock.age = -QUAKE_AFTERSHOCK_DELAY
			shock.from = at
			shock.pos = at
			shock.to = at
			shock.target = null
			shock.brood = false
			shock.damage = damage * QUAKE_AFTERSHOCK
			shock.radius = radius
			shock.source = source
			shock.aftershock = false
			shock.hidden = true


func _erupt(at: Vector3, damage: float, radius: float, source: String) -> void:
	for target in _targets_near(at, radius):
		_hurt(target, damage, source)
	if _has_horde():
		horde.damage_circle(at, radius, damage)
		_note_horde(source, damage)
	_ring(at, Color(EARTH_LIGHT.r, EARTH_LIGHT.g, EARTH_LIGHT.b, 0.95), radius * 0.5, radius * 1.1, 0.42, true)
	_ring(at, Color(EARTH_COLOR.r, EARTH_COLOR.g, EARTH_COLOR.b, 0.9), 0.2, radius * 0.75, 0.3, true)
	var entry: Dictionary = _take(_eruptions, MAX_ERUPTIONS, _make_eruption)
	entry.active = true
	entry.age = 0.0
	entry.at = at
	entry.radius = radius


# --- Blitzbiss / Sturmrudel (Etappe 10) ----------------------------------

func _step_chain(delta: float, origin: Vector3, living: Array, rally: bool) -> void:
	for entry in _bolts:
		if entry.active:
			entry.age += delta
			if entry.age >= BOLT_SECONDS:
				entry.active = false
	var level := rank("blitzbiss")
	var storm := rank("sturmrudel") > 0
	if level <= 0 and not storm:
		return
	_chain_timer = maxf(0.0, _chain_timer - delta)
	if _chain_timer > 0.0:
		return
	var reach := STORM_REACH if storm else BLITZ_REACH
	var jump := STORM_JUMP if storm else BLITZ_JUMP
	var hops: int = STORM_TARGETS if storm else BLITZ_TARGETS[level - 1]
	var damage: float = (STORM_DAMAGE if storm else BLITZ_DAMAGE[level - 1]) * _enemy_scale
	var falloff := 1.0 if storm else BLITZ_FALLOFF
	var source := "sturmrudel" if storm else "blitzbiss"
	var brood := PackedVector3Array()
	var brood_loaded := false
	var used := {}
	var used_brood := {}
	var at := _flat(origin)
	var points := PackedVector3Array([at])
	while points.size() - 1 < hops:
		var limit := reach if points.size() == 1 else jump
		var node := _nearest_unused(living, at, limit, used)
		var brood_index := -1
		# Erster Sprung: echte Gegner haben Vorrang; danach das nächste Ziel.
		if node == null or points.size() > 1:
			if not brood_loaded:
				brood_loaded = true
				brood = horde.call("positions") if _has_horde() else PackedVector3Array()
			brood_index = _nearest_unused_brood(brood, at, limit, used_brood)
		if brood_index >= 0 and node != null and _flat_distance(node.global_position, at) <= _flat_distance(brood[brood_index], at):
			brood_index = -1
		if brood_index >= 0:
			used_brood[brood_index] = true
			at = _flat(brood[brood_index])
			if _has_horde():
				horde.damage_nearest(brood[brood_index], 0.5, damage)
				_note_horde(source, damage)
		elif node != null:
			used[node.get_instance_id()] = true
			at = _flat(node.global_position)
			_hurt(node, damage, source)
		else:
			break
		points.append(at)
		damage *= falloff
	if points.size() <= 1:
		_chain_timer = 0.15
		return
	_chain_timer = (STORM_RALLY_INTERVAL if rally else STORM_INTERVAL) if storm else BLITZ_INTERVAL[level - 1]
	var entry: Dictionary = _take(_bolts, MAX_BOLTS, _make_bolt)
	entry.active = true
	entry.age = 0.0
	entry.points = points
	entry.seed = _clock * 13.7
	entry.storm = storm


func _nearest_unused(living: Array, at: Vector3, reach: float, used: Dictionary) -> Node3D:
	var best: Node3D = null
	var best_distance := reach
	for target in living:
		if used.has(target.get_instance_id()) or not _valid_target(target):
			continue
		var distance := _flat_distance(target.global_position, at)
		if distance <= best_distance:
			best = target
			best_distance = distance
	return best


func _nearest_unused_brood(points: PackedVector3Array, at: Vector3, reach: float, used: Dictionary) -> int:
	var best := -1
	var best_distance := reach
	for index in points.size():
		if used.has(index):
			continue
		var distance := _flat_distance(points[index], at)
		if distance <= best_distance:
			best = index
			best_distance = distance
	return best


# --- Brutsack (Etappe 10) ------------------------------------------------
# Nur Effekt und Schaden: kein Aufruf an den Schwarm, die Population bleibt gleich.

func _step_sacs(delta: float, origin: Vector3, living: Array) -> void:
	for entry in _sacs:
		if not entry.active:
			continue
		entry.age += delta
		if entry.age >= SAC_GROW:
			entry.active = false
			_burst_sac(entry.at, entry.level)
	var level := rank("brutsack")
	if level <= 0:
		return
	_sac_timer = maxf(0.0, _sac_timer - delta)
	if _sac_timer > 0.0:
		return
	var target := _nearest(living, origin, SAC_SENSE)
	var toward := _flat(target.global_position) if target != null else _brood_near(origin, SAC_SENSE)
	if toward == Vector3.INF:
		_sac_timer = 0.2
		return
	_sac_timer = SAC_INTERVAL[level - 1]
	var base := _flat(origin)
	var direction := toward - base
	var distance := direction.length()
	direction = direction / distance if distance > 0.01 else Vector3.RIGHT
	var side := Vector3(-direction.z, 0.0, direction.x) * sin(_clock * 7.3) * 0.8
	var entry: Dictionary = _take(_sacs, MAX_SACS, _make_sac)
	entry.active = true
	entry.age = 0.0
	entry.at = base + direction * minf(SAC_OFFSET, distance) + side
	entry.level = level


func _burst_sac(at: Vector3, level: int) -> void:
	var burst: float = SAC_BURST_DAMAGE[level - 1] * _enemy_scale
	for target in _targets_near(at, SAC_BURST_RADIUS):
		_hurt(target, burst, "brutsack")
	if _has_horde():
		horde.damage_circle(at, SAC_BURST_RADIUS, burst)
		_note_horde("brutsack", burst)
	_ring(at, Color(SAC_COLOR.r, SAC_COLOR.g, SAC_COLOR.b, 0.95), 0.3, SAC_BURST_RADIUS * 1.2, 0.35, true)
	_ring(at, Color(SAC_CORE.r, SAC_CORE.g, SAC_CORE.b, 0.85), 0.1, 0.8, 0.22)
	var aims: Array = []
	var ranked: Array = []
	for target in _targets_near(at, BITER_REACH):
		ranked.append([_flat_distance(target.global_position, at), target])
	ranked.sort_custom(func(a, b): return a[0] < b[0])
	for entry in ranked:
		aims.append({"target": entry[1], "at": _flat(entry[1].global_position)})
	var count: int = SAC_BITERS[level - 1]
	if aims.is_empty() and _has_horde():
		var brood: Array = []
		for point in horde.call("positions"):
			var distance := _flat_distance(point, at)
			if distance <= BITER_REACH:
				brood.append([distance, _flat(point)])
		brood.sort_custom(func(a, b): return a[0] < b[0])
		for index in mini(count, brood.size()):
			aims.append({"target": null, "at": brood[index][1]})
	for index in count:
		var biter: Dictionary = _take(_biters, MAX_BITERS, _make_biter)
		var angle := TAU * float(index) / float(count) + _clock
		biter.active = true
		biter.age = 0.0
		biter.pos = at + Vector3(cos(angle), 0.0, sin(angle)) * 0.35
		biter.damage = SAC_BITE[level - 1] * _enemy_scale
		if aims.is_empty():
			# Kein Ziel: die Beißer schwärmen kurz aus und vergehen ohne Schaden.
			biter.target = null
			biter.brood = false
			biter.aim = at + Vector3(cos(angle), 0.0, sin(angle)) * 1.6
		else:
			var aim: Dictionary = aims[index % aims.size()]
			biter.target = aim.target
			biter.brood = aim.target == null
			biter.aim = aim.at
		biter.heading = (biter.aim - biter.pos).normalized() if biter.aim.distance_to(biter.pos) > 0.01 else Vector3.FORWARD


func _step_biters(delta: float) -> void:
	for biter in _biters:
		if not biter.active:
			continue
		biter.age += delta
		if biter.age >= BITER_LIFE:
			biter.active = false
			biter.target = null
			continue
		var tracking: bool = _valid_target(biter.target)
		if tracking:
			biter.aim = _flat(biter.target.global_position)
		elif biter.brood:
			biter.aim = _track_brood(biter.aim)
		var offset: Vector3 = biter.aim - biter.pos
		var travel := BITER_SPEED * delta
		if offset.length() > travel + 0.3:
			biter.heading = offset.normalized()
			biter.pos += biter.heading * travel
			continue
		biter.active = false
		if tracking:
			_hurt(biter.target, biter.damage, "brutsack")
			_ring(biter.aim, Color(SAC_COLOR.r, SAC_COLOR.g, SAC_COLOR.b, 0.85), 0.1, 0.6, 0.2)
		elif biter.brood and _has_horde():
			var struck: Vector3 = horde.damage_nearest(biter.aim, 1.0, biter.damage)
			if struck != Vector3.INF:
				_note_horde("brutsack", biter.damage)
				_ring(struck, Color(SAC_COLOR.r, SAC_COLOR.g, SAC_COLOR.b, 0.85), 0.1, 0.6, 0.2)
		biter.target = null


# --- Zeichnen der neuen Formen (je Batch ein Draw-Call) -------------------

func _draw_extra() -> void:
	if not _built:
		return
	_clump_batch.begin()
	for entry in _tunnels:
		if not entry.active or entry.hidden or entry.age < 0.0:
			continue
		var back: Vector3 = entry.from - entry.pos
		back = back.normalized() if back.length() > 0.01 else Vector3.ZERO
		var bob := 0.12 * sin(_clock * 22.0 + entry.pos.x)
		_clump_batch.add(Transform3D(Basis.from_scale(Vector3(3.3, 1.9 + bob, 3.3)), entry.pos + Vector3(0, 0.06, 0)), Color(EARTH_COLOR.r * 1.25, EARTH_COLOR.g * 1.2, EARTH_COLOR.b * 1.1))
		var travelled: float = entry.from.distance_to(entry.pos)
		for index in _trail_clumps:
			var gap := 0.5 * float(index + 1)
			if gap > travelled:
				break
			var size := 2.7 - 0.32 * float(index)
			var jitter := Vector3(back.z, 0.0, -back.x) * 0.2 * sin(float(index) * 2.3 + float(entry.from.x))
			_clump_batch.add(Transform3D(Basis.from_scale(Vector3(size, 0.55 * size, size)), entry.pos + back * gap + jitter + Vector3(0, 0.03, 0)), EARTH_COLOR)
	# Ausbruch: Erdbrocken fliegen im Bogen nach außen (von oben gut lesbar).
	for entry in _eruptions:
		if not entry.active:
			continue
		var t: float = clampf(entry.age / ERUPTION_SECONDS, 0.0, 1.0)
		for index in ERUPTION_SHARDS:
			var angle := TAU * (float(index) + 0.5) / float(ERUPTION_SHARDS) + float(entry.at.z)
			var reach: float = entry.radius * (0.2 + 0.85 * t) * (0.8 + 0.2 * float(index % 3))
			var lift := sin(t * PI) * (0.9 + 0.3 * float(index % 2))
			var size := (1.5 + 0.5 * float(index % 3)) * (1.0 - smoothstep(0.75, 1.0, t))
			_clump_batch.add(Transform3D(Basis.from_scale(Vector3.ONE * maxf(0.05, size)), entry.at + Vector3(cos(angle) * reach, 0.1 + lift, sin(angle) * reach)), EARTH_COLOR.lerp(EARTH_LIGHT, 0.2 * float(index % 2)))
	_clump_batch.finish()

	_shard_batch.begin()
	for entry in _eruptions:
		if not entry.active:
			continue
		var t: float = clampf(entry.age / ERUPTION_SECONDS, 0.0, 1.0)
		var rise := sin(minf(1.0, t * 3.0) * PI * 0.5) * (1.0 - smoothstep(0.65, 1.0, t))
		var tint := EARTH_COLOR.lerp(EARTH_LIGHT, 0.45)
		for index in ERUPTION_SHARDS:
			var angle := TAU * float(index) / float(ERUPTION_SHARDS) + float(entry.at.x)
			var reach: float = entry.radius * (0.25 + 0.3 * float(index % 2))
			var tilt := Basis.from_euler(Vector3(0.0, -angle, -0.8 - 0.2 * float(index % 3)))
			var size := maxf(0.02, rise) * (1.4 + 0.4 * float(index % 3))
			_shard_batch.add(Transform3D(tilt.scaled_local(Vector3(1.0, size, 1.0)), entry.at + Vector3(cos(angle) * reach, 0.1, sin(angle) * reach)), tint)
	_shard_batch.finish()

	_bolt_batch.begin()
	_spark_batch.begin()
	for entry in _bolts:
		if not entry.active:
			continue
		var t: float = clampf(entry.age / BOLT_SECONDS, 0.0, 1.0)
		var fade := 1.0 - t * t
		var points: PackedVector3Array = entry.points
		var width := 0.34 if entry.storm else 0.28
		for hop in points.size() - 1:
			var a := points[hop] + Vector3(0, 0.55, 0)
			var b := points[hop + 1] + Vector3(0, 0.55, 0)
			var across := Vector3(-(b - a).z, 0.0, (b - a).x).normalized()
			var previous := a
			for step in BOLT_SUBDIV:
				var u := float(step + 1) / float(BOLT_SUBDIV)
				var next := a.lerp(b, u)
				if step < BOLT_SUBDIV - 1:
					# Zickzack, flackert mit der Uhr.
					next += across * 0.35 * sin(entry.seed + float(hop * 5 + step) * 2.7 + _clock * 40.0)
					next.y += 0.18 * cos(entry.seed + float(step) * 1.9 + _clock * 31.0)
				_bolt_segment(previous, next, width, Color(BOLT_COLOR.r, BOLT_COLOR.g, BOLT_COLOR.b, 0.7 * fade))
				_bolt_segment(previous, next, width * 0.42, Color(BOLT_CORE.r, BOLT_CORE.g, BOLT_CORE.b, fade))
				previous = next
			var spark := lerpf(2.4, 0.8, t)
			_spark_batch.add(Transform3D(Basis.from_scale(Vector3.ONE * spark), b), Color(BOLT_CORE.r, BOLT_CORE.g, BOLT_CORE.b, 0.9 * fade))
	_bolt_batch.finish()
	_spark_batch.finish()

	_sac_batch.begin()
	for entry in _sacs:
		if not entry.active:
			continue
		var t: float = clampf(entry.age / SAC_GROW, 0.0, 1.0)
		var grow := lerpf(0.55, 1.6, 1.0 - pow(1.0 - t, 2.0)) * (1.0 + 0.08 * sin(_clock * 30.0))
		var at: Vector3 = entry.at + Vector3(0, 0.42 * grow, 0)
		_sac_batch.add(Transform3D(Basis.from_scale(Vector3(grow, grow * 0.9, grow)), at), Color(SAC_COLOR.r, SAC_COLOR.g, SAC_COLOR.b, 0.8))
		_sac_batch.add(Transform3D(Basis.from_scale(Vector3.ONE * grow * 0.55), at + Vector3(-0.08, 0.1, -0.08) * grow), Color(SAC_CORE.r, SAC_CORE.g, SAC_CORE.b, 0.95))
	_sac_batch.finish()

	_biter_batch.begin()
	for biter in _biters:
		if not biter.active:
			continue
		var heading: Vector3 = biter.heading
		var hop := absf(sin(biter.age * 18.0))
		var fade: float = 1.0 - smoothstep(0.75, 1.0, biter.age / BITER_LIFE)
		var body := Basis.looking_at(heading if heading.length() > 0.01 else Vector3.FORWARD, Vector3.UP)
		var at: Vector3 = biter.pos + Vector3(0, 0.3 + 0.5 * hop, 0)
		_biter_batch.add(Transform3D(body.scaled_local(Vector3(1.7, 1.4, 2.4) * fade), at), SAC_COLOR)
		_biter_batch.add(Transform3D(body.scaled_local(Vector3.ONE * 0.8 * fade), at + heading * 0.42 + Vector3(0, 0.1, 0)), SAC_CORE)
	_biter_batch.finish()


func _bolt_segment(from: Vector3, to: Vector3, width: float, tint: Color) -> void:
	var span := to - from
	var length := span.length()
	if length < 0.01:
		return
	var up := Vector3.UP if absf(span.normalized().y) < 0.95 else Vector3.RIGHT
	var basis := Basis.looking_at(span / length, up).scaled_local(Vector3(width, width, length))
	_bolt_batch.add(Transform3D(basis, (from + to) * 0.5), tint)


func _make_tunnel() -> Dictionary:
	return {"active": false, "age": 0.0, "from": Vector3.ZERO, "pos": Vector3.ZERO, "to": Vector3.ZERO, "target": null,
		"brood": false, "damage": 0.0, "radius": 1.0, "source": "graeber", "aftershock": false, "hidden": false}


func _make_eruption() -> Dictionary:
	return {"active": false, "age": 0.0, "at": Vector3.ZERO, "radius": 1.0}


func _make_bolt() -> Dictionary:
	return {"active": false, "age": 0.0, "points": PackedVector3Array(), "seed": 0.0, "storm": false}


func _make_sac() -> Dictionary:
	return {"active": false, "age": 0.0, "at": Vector3.ZERO, "level": 1}


func _make_biter() -> Dictionary:
	return {"active": false, "age": 0.0, "pos": Vector3.ZERO, "aim": Vector3.ZERO, "heading": Vector3.FORWARD,
		"target": null, "brood": false, "damage": 0.0}


func _build_extra(density: float) -> void:
	_trail_clumps = maxi(2, QUALITY.scaled_count(TUNNEL_TRAIL, density))
	var shard_mesh := CylinderMesh.new()
	shard_mesh.top_radius = 0.0
	shard_mesh.bottom_radius = 0.24
	shard_mesh.height = 1.0
	shard_mesh.radial_segments = 5
	shard_mesh.rings = 1
	var bolt_mesh := BoxMesh.new()
	bolt_mesh.size = Vector3.ONE
	var sac_mesh := SphereMesh.new()
	sac_mesh.radius = 0.5
	sac_mesh.height = 1.0
	sac_mesh.radial_segments = 14
	sac_mesh.rings = 7
	# Erde und Felsen schattiert (plastisch), Blitz und Blasen leuchtend.
	_clump_batch = _lit_batch(_mote_mesh, MAX_TUNNELS * (1 + TUNNEL_TRAIL) + MAX_ERUPTIONS * ERUPTION_SHARDS, "Tunnel clumps")
	_shard_batch = _lit_batch(shard_mesh, MAX_ERUPTIONS * ERUPTION_SHARDS, "Eruption shards")
	_bolt_batch = _batch(self, bolt_mesh, MAX_BOLTS * STORM_TARGETS * BOLT_SUBDIV * 2, "Chain bolts")
	_spark_batch = _batch(self, _dot_mesh, MAX_BOLTS * STORM_TARGETS, "Chain sparks")
	_sac_batch = _batch(self, sac_mesh, MAX_SACS * 2, "Brood sacs")
	_biter_batch = _lit_batch(_mote_mesh, MAX_BITERS * 2, "Brood biters")


func _lit_batch(mesh: Mesh, capacity: int, node_name: String) -> MultiMeshInstance3D:
	var batch := FX_BATCH.create(mesh, capacity, false, false, node_name)
	add_child(batch)
	batch.top_level = true
	batch.transform = Transform3D.IDENTITY
	return batch


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
	_build_extra(density)


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
