extends Node3D

# Angriffsformen (Etappe 03): vier aktive Mutationen plus zwei Evolutionen;
# Etappe 10: Gräber, Blitzbiss, Brutsack plus Erdbeben und Sturmrudel.
# Etappe 17: Waffen mit Rang 1–5 (sichtbare Sprünge auf Rang 3 und 5), neue
# Waffen Klauenwirbel, Giftbiss, Schallbrüller, neue Evolutionen Pilzreich und
# Dornenwall, Relikt-Wirkungen über set_modifiers() (Angriffstempo, Reichweite,
# Ätzdrüse, Grabkralle, Gewitterfell, Glutdrüse) und on_kill()/spore_burst().
# Vertrag: stages/03_progression.md, stages/17_dual_progression.md. Dieses Modul
# reduziert die Gesundheit der übergebenen Ziele (take_damage() oder 'health'),
# gibt nie Knoten frei und bewegt keine Mawlings. Einzige Ausnahme (Etappe 17):
# der Schallbrüller schiebt leichte Gegner (mit slow_factor) kurz zurück. Alle
# Animationen laufen nur in step(), damit die Pause alles einfriert. Effekte und
# Projektile sind gepoolt, gezeichnet über fx_batch.gd-MultiMeshes.

const FORMS := {
	"rudelbiss": {
		"name": "Rudelbiss",
		"icon_hint": "jaws_leap",
		"ranks": [
			"Rally: alle 2,2 s Sprungangriff auf den nächsten Gegner (4 m), 8 Flächenschaden.",
			"Rally: alle 1,8 s Sprungangriff, 12 Flächenschaden.",
			"Rally: alle 1,4 s Sprungangriff, 16 Schaden – springt weiter zu einem zweiten Ziel.",
			"Rally: alle 1,2 s Doppelsprung, 20 Schaden.",
			"Rally: alle 1,0 s Doppelsprung, 24 Schaden – Sprünge betäuben kurz.",
		],
	},
	"sporenwolke": {
		"name": "Sporenwolke",
		"icon_hint": "spore_cloud",
		"ranks": [
			"Sporen-Aura (3 m): 5 Schaden/s, Gegner werden verlangsamt.",
			"Sporen-Aura (3,4 m): 8 Schaden/s, Gegner werden verlangsamt.",
			"Große Sporen-Aura (4,4 m): 11,5 Schaden/s, Gegner werden verlangsamt.",
			"Sporen-Aura (4,8 m): 14 Schaden/s.",
			"Sporen-Aura (5,2 m): 17 Schaden/s – lähmt Gegner stark.",
		],
	},
	"saeurespucker": {
		"name": "Säurespucker",
		"icon_hint": "acid_drop",
		"ranks": [
			"Alle 1,3 s ein Säureschuss auf den nächsten Gegner (9 m), 5 Schaden.",
			"Alle 1,1 s ein Säureschuss, 7,5 Schaden.",
			"Alle 0,9 s zwei Säuresalven, je 10 Schaden.",
			"Alle 0,8 s zwei Salven, je 12 Schaden.",
			"Alle 0,7 s zwei Salven, je 14 Schaden – Säure durchschlägt ein weiteres Ziel.",
		],
	},
	"stachelruecken": {
		"name": "Stachelrücken",
		"icon_hint": "spikes",
		"ranks": [
			"Wer den Schwarm trifft, erleidet 26 Schaden + 5 je verlorenem Mawling.",
			"Rückstoß-Stacheln: 44 Schaden + 5 je verlorenem Mawling.",
			"Rückstoß-Stacheln: 70 Schaden (+50 %) + 5 je verlorenem Mawling.",
			"Rückstoß-Stacheln: 84 Schaden + 5 je verlorenem Mawling.",
			"Rückstoß-Stacheln: 100 Schaden – eine Stachelsalve trifft 5 nahe Gegner.",
		],
	},
	"meute": {
		"name": "Meute",
		"icon_hint": "pack_leap",
		"evolved": true,
		"base": "rudelbiss",
		"requires": "rudelhorn",
		"ranks": [
			"Evolution von Rudelbiss: springt auch ohne Rally alle 1,2 s über drei Ziele, Radius 2,4 m, 24 Schaden – doppelt bei Rally.",
		],
	},
	"aetzflut": {
		"name": "Ätzflut",
		"icon_hint": "acid_pool",
		"evolved": true,
		"base": "saeurespucker",
		"requires": "aetzdruese",
		"ranks": [
			"Evolution von Säurespucker: durchschlagende Doppelsalven, jeder Treffer hinterlässt 2 s eine Säurepfütze (1,2 m, 4 Schaden/s).",
		],
	},
	# --- Etappe 10: drei neue Formen, zwei Evolutionen ---------------------
	"graeber": {
		"name": "Gräber",
		"icon_hint": "burrow",
		"ranks": [
			"Alle 2,6 s wühlt sich ein Tunnelstoß zum entferntesten Gegner (10 m) und bricht mit 10 Flächenschaden aus.",
			"Alle 2,2 s ein Tunnelstoß (11 m), 14 Flächenschaden.",
			"Alle 2,0 s zwei Tunnelstöße (12 m), je 17 Flächenschaden.",
			"Alle 1,8 s zwei Tunnelstöße, je 21 Flächenschaden.",
			"Alle 1,6 s zwei Tunnelstöße, je 25 Schaden – jeder mit Nachbeben.",
		],
	},
	"blitzbiss": {
		"name": "Blitzbiss",
		"icon_hint": "chain_bite",
		"ranks": [
			"Alle 1,6 s ein Kettenbiss: springt zwischen bis zu 3 nahen Gegnern oder Brut, 5,5 Schaden (−15 % je Sprung).",
			"Alle 1,4 s ein Kettenbiss über bis zu 4 Ziele, 7,5 Schaden.",
			"Alle 1,3 s ein Kettenbiss über bis zu 6 Ziele, 9 Schaden.",
			"Alle 1,2 s über bis zu 7 Ziele, 10,5 Schaden.",
			"Alle 1,1 s über bis zu 8 Ziele, 12 Schaden – ohne Abschwächung.",
		],
	},
	"brutsack": {
		"name": "Brutsack",
		"icon_hint": "brood_sac",
		"ranks": [
			"Alle 3,2 s platzt eine Brutblase am Schwarm und setzt 2 Hilfs-Beißer frei (je 4 Schaden).",
			"Alle 2,8 s eine Brutblase mit 3 Hilfs-Beißern (je 5 Schaden).",
			"Alle 2,6 s zwei Brutblasen mit je 3 Hilfs-Beißern (je 6 Schaden).",
			"Alle 2,4 s zwei Brutblasen mit je 4 Hilfs-Beißern (je 7 Schaden).",
			"Alle 2,2 s zwei Brutblasen, je 4 Beißer (8 Schaden) – Beißer leben länger und jagen weiter.",
		],
	},
	"erdbeben": {
		"name": "Erdbeben",
		"icon_hint": "quake",
		"evolved": true,
		"base": "graeber",
		"requires": "grabkralle",
		"ranks": [
			"Evolution von Gräber: alle 1,6 s drei Tunnelstöße zugleich (13 m, 2,8 m, 25 Schaden), jeder mit Nachbeben (50 %).",
		],
	},
	"sturmrudel": {
		"name": "Sturmrudel",
		"icon_hint": "storm_pack",
		"evolved": true,
		"base": "blitzbiss",
		"requires": "gewitterfell",
		"ranks": [
			"Evolution von Blitzbiss: alle 1,0 s (Rally 0,7 s) ein Kettenbiss über bis zu 10 Ziele, 13 Schaden ohne Abschwächung.",
		],
	},
	# --- Etappe 17: drei neue Waffen, zwei Evolutionen -----------------------
	"klauenwirbel": {
		"name": "Klauenwirbel",
		"icon_hint": "claw_orbit",
		"ranks": [
			"Zwei Knochenklingen kreisen um den Schwarm, je 6 Schaden pro Treffer.",
			"Zwei Klingen, schneller, je 8 Schaden.",
			"Drei Klingen kreisen um den Schwarm, je 9 Schaden.",
			"Drei Klingen, je 11 Schaden.",
			"Vier große Klingen, je 13 Schaden, weiter Kreis.",
		],
	},
	"giftbiss": {
		"name": "Giftbiss",
		"icon_hint": "venom_fang",
		"ranks": [
			"Alle 1,5 s schnappen Giftfänge nach 2 nahen Gegnern: 3 Schaden + Gift (4 Schaden/s, 3 s).",
			"Alle 1,4 s nach 2 Gegnern: 4 Schaden + Gift (5 Schaden/s).",
			"Alle 1,3 s nach 3 Gegnern: 5 Schaden + starkes Gift (7 Schaden/s, 4 s).",
			"Alle 1,2 s nach 3 Gegnern: 6 Schaden + Gift (8 Schaden/s, 4 s).",
			"Alle 1,1 s nach 4 Gegnern: 7 Schaden + Gift (10 Schaden/s) – Gift springt beim Tod über.",
		],
	},
	"schallbrueller": {
		"name": "Schallbrüller",
		"icon_hint": "roar_cone",
		"ranks": [
			"Alle 2,4 s ein Schallkegel nach vorn (6 m): 8 Schaden, wirft Gegner zurück.",
			"Alle 2,2 s ein Schallkegel (6,5 m): 10 Schaden.",
			"Alle 2,0 s ein breiter Schallkegel (7 m): 13 Schaden, stößt weit zurück.",
			"Alle 1,8 s ein breiter Schallkegel (7,5 m): 15 Schaden.",
			"Alle 1,6 s ein doppelter Schallkegel nach vorn und hinten: 18 Schaden.",
		],
	},
	"pilzreich": {
		"name": "Pilzreich",
		"icon_hint": "spore_kingdom",
		"evolved": true,
		"base": "sporenwolke",
		"requires": "sporenherz",
		"ranks": [
			"Evolution von Sporenwolke: riesige Aura (6 m, 22 Schaden/s, lähmt), Kills darin platzen als Pilzwolke.",
		],
	},
	"dornenwall": {
		"name": "Dornenwall",
		"icon_hint": "thorn_wall",
		"evolved": true,
		"base": "stachelruecken",
		"requires": "dornenhaut",
		"ranks": [
			"Evolution von Stachelrücken: ein Dornenring um den Schwarm (16 Schaden/s), Treffer lösen eine Stachelsalve aus (100 Schaden).",
		],
	},
}
const MAX_RANK := 5

const RUDELBISS_INTERVAL := [2.2, 1.8, 1.4, 1.2, 1.0]
const RUDELBISS_DAMAGE := [8.0, 12.0, 16.0, 20.0, 24.0]
# Rang 3: +1 Sprungziel (der Sprung setzt vom ersten Ziel zum nächsten fort).
const RUDELBISS_HOPS := [0, 0, 1, 1, 1]
const RUDELBISS_RADIUS := 1.6
const RUDELBISS_REACH := 4.0
const RUDELBISS_HOP_REACH := 4.5
# Rang 5: Sprünge betäuben kurz.
const RUDELBISS_STUN := 0.6
const LEAP_SECONDS := 0.24
const HOP_SECONDS := 0.2
const MEUTE_INTERVAL := 1.2
const MEUTE_RADIUS := 2.4
const MEUTE_DAMAGE := 24.0
const MEUTE_HOPS := 2
const MEUTE_RALLY_MULTIPLIER := 2.0

# Etappe 17: Rang 3 +30 % Fläche, Rang 5 starke Verlangsamung.
const SPORE_RADIUS := [3.0, 3.4, 4.4, 4.8, 5.2]
const SPORE_DPS := [5.0, 8.0, 11.5, 14.0, 17.0]
const SPORE_SLOW := [0.6, 0.6, 0.6, 0.6, 0.35]
const PILZ_RADIUS := 6.0
const PILZ_DPS := 22.0
const PILZ_SLOW := 0.35

const SPIT_INTERVAL := [1.3, 1.1, 0.9, 0.8, 0.7]
const SPIT_REACH := 9.0
const SPIT_SPEED := 14.0
const SPIT_DAMAGE := [5.0, 7.5, 10.0, 12.0, 14.0]
# Rang 3: zwei Salven kurz nacheinander; Rang 5: durchschlägt ein weiteres Ziel.
const SPIT_SALVOS := [1, 1, 2, 2, 2]
const SPIT_SALVO_GAP := 0.16
const SPIT_PIERCE := [0, 0, 0, 0, 1]
const SPIT_PIERCE_REACH := 3.5
const SPIT_MAX_FLIGHT := 1.2
const SPIT_HEIGHT := 0.75

const PUDDLE_SECONDS := 2.0
const PUDDLE_RADIUS := 1.2
const PUDDLE_DPS := 4.0

# Rang 3: Rückschaden +50 %; Rang 5: Stachelsalve auf nahe Gegner.
const SPINE_DAMAGE := [26.0, 44.0, 70.0, 84.0, 100.0]
const SPINE_PER_LOSS := 5.0
const SPINE_SECONDS := 0.42
const SPINE_COUNT := 12
const SPINE_VOLLEY := 5
const SPINE_VOLLEY_SHARE := 0.5
const SPINE_VOLLEY_REACH := 7.0
const DART_SECONDS := 0.22
# Dornenwall (Evolution): Dornenring um den Schwarm.
const WALL_DPS := 16.0
const WALL_WIDTH := 0.9
const WALL_SPINES := 20

# --- Etappe 10 ------------------------------------------------------------
# Gräber: Tunnelstoß wandert unter der Erde zum entferntesten Ziel in Reichweite.
const GRAEBER_INTERVAL := [2.6, 2.2, 2.0, 1.8, 1.6]
const GRAEBER_REACH := [10.0, 11.0, 12.0, 12.5, 13.0]
const GRAEBER_DAMAGE := [10.0, 14.0, 17.0, 21.0, 25.0]
const GRAEBER_RADIUS := [1.6, 1.9, 2.1, 2.3, 2.5]
# Rang 3: zwei Stöße; Rang 5: Nachbeben.
const GRAEBER_TUNNELS := [1, 1, 2, 2, 2]
const GRAEBER_SPEED := 14.0
const ERUPTION_SECONDS := 0.45
const QUAKE_INTERVAL := 1.6
const QUAKE_TUNNELS := 3
const QUAKE_RADIUS := 2.8
const QUAKE_AFTERSHOCK := 0.5
const QUAKE_AFTERSHOCK_DELAY := 0.45
# Blitzbiss: Kette vom Schwarm zum nächsten Ziel, dann von Ziel zu Ziel.
const BLITZ_INTERVAL := [1.6, 1.4, 1.3, 1.2, 1.1]
const BLITZ_REACH := 5.0
const BLITZ_JUMP := 3.5
# Rang 3: +2 Kettenziele; Rang 5: keine Abschwächung.
const BLITZ_TARGETS := [3, 4, 6, 7, 8]
const BLITZ_DAMAGE := [5.5, 7.5, 9.0, 10.5, 12.0]
const BLITZ_FALLOFF := 0.85
const BOLT_SECONDS := 0.3
const STORM_INTERVAL := 1.0
const STORM_RALLY_INTERVAL := 0.7
const STORM_REACH := 6.0
const STORM_JUMP := 4.5
const STORM_TARGETS := 10
const STORM_DAMAGE := 13.0
# Brutsack: Blase schwillt am Schwarmrand an, platzt, Hilfs-Beißer springen los.
# Rein Effekt und Schaden: die Population ändert sich nie.
const SAC_INTERVAL := [3.2, 2.8, 2.6, 2.4, 2.2]
const SAC_SENSE := 7.0
const SAC_OFFSET := 2.2
const SAC_GROW := 0.55
const SAC_BURST_RADIUS := 1.4
const SAC_BURST_DAMAGE := [4.0, 5.0, 6.0, 7.0, 8.0]
# Rang 3: +1 Blase; Rang 5: Beißer leben länger (und jagen weiter).
const SAC_COUNT := [1, 1, 2, 2, 2]
const SAC_BITERS := [2, 3, 3, 4, 4]
const SAC_BITE := [4.0, 5.0, 6.0, 7.0, 8.0]
const BITER_REACH := 4.5
const BITER_REACH_LONG := 6.5
const BITER_SPEED := 8.0
const BITER_LIFE := 1.0
const BITER_LIFE_LONG := 1.8
# Dornenhaut (Relikt; der Schaden kommt aus Evolution.thorn_damage()).
const THORN_RADIUS := 1.6
const THORN_HORDE_COOLDOWN := 0.5

# --- Etappe 17: neue Waffen ------------------------------------------------
# Klauenwirbel: Klingen kreisen außen um den Schwarm.
const CLAW_BLADES := [2, 2, 3, 3, 4]
const CLAW_DAMAGE := [6.0, 8.0, 9.0, 11.0, 13.0]
const CLAW_SPIN := [2.4, 2.8, 3.0, 3.3, 3.6]
const CLAW_ORBIT := [1.2, 1.2, 1.3, 1.3, 1.7]
const CLAW_SIZE := [1.0, 1.0, 1.1, 1.1, 1.35]
const CLAW_HIT := 1.0
const CLAW_REHIT := 0.45
const CLAW_HORDE_REHIT := 0.3
const CLAW_TRAIL := 3
# Giftbiss: Giftfänge schnappen nach nahen Zielen, Gift als Schaden über Zeit.
const GIFT_INTERVAL := [1.5, 1.4, 1.3, 1.2, 1.1]
const GIFT_TARGETS := [2, 2, 3, 3, 4]
const GIFT_BITE := [3.0, 4.0, 5.0, 6.0, 7.0]
const GIFT_DPS := [4.0, 5.0, 7.0, 8.0, 10.0]
const GIFT_SECONDS := [3.0, 3.0, 4.0, 4.0, 4.0]
const GIFT_REACH := 2.4
const GIFT_SPREAD := 3.5
const SNAP_SECONDS := 0.3
# Schallbrüller: Kegel zum nächsten Ziel, schiebt leichte Gegner zurück.
const ROAR_INTERVAL := [2.4, 2.2, 2.0, 1.8, 1.6]
const ROAR_DAMAGE := [8.0, 10.0, 13.0, 15.0, 18.0]
const ROAR_REACH := [6.0, 6.5, 7.0, 7.5, 8.0]
const ROAR_ANGLE := [0.61, 0.61, 0.87, 0.87, 0.87]
const ROAR_PUSH := [1.2, 1.4, 1.8, 2.0, 2.2]
const ROAR_CONES := [1, 1, 1, 1, 2]
const ROAR_STAGGER := 0.5
const ROAR_SECONDS := 0.42
const ROAR_ARCS := 3
const ROAR_SEGMENTS := 9
const PUSH_SECONDS := 0.18
# Relikte: Glutdrüse (Brand je Stapel), Gewitterfell (Kettenblitz), Sporenherz.
const BURN_DPS := 3.0
const BURN_SECONDS := 2.0
const BURN_REACH := 0.9
const SPARK_DAMAGE := 6.0
const SPARK_HOPS := 2
const SPARK_JUMP := 3.5
const SPARK_COOLDOWN := 0.15
const PUFF_SECONDS := 2.0
const PUFF_RADIUS := 1.8
const PUFF_DPS := 8.0
const PUFF_SLOW := 0.6

const MAX_TUNNELS := 10
const MAX_ERUPTIONS := 10
const ERUPTION_SHARDS := 7
const TUNNEL_TRAIL := 5
const MAX_BOLTS := 8
const BOLT_SUBDIV := 3
const MAX_SACS := 6
const MAX_BITERS := 24
const MAX_SNAPS := 8
const MAX_ROARS := 4
const MAX_DARTS := 12
const MAX_PUFFS := 8
const PUFF_MOTES := 7
const MAX_MARKS := 40

const EARTH_COLOR := Color(0.55, 0.36, 0.2)
const EARTH_LIGHT := Color(0.98, 0.8, 0.46)
const BOLT_COLOR := Color(0.5, 0.86, 1.0)
const BOLT_CORE := Color(0.94, 0.99, 1.0)
const SAC_COLOR := Color(0.93, 0.36, 0.78)
const SAC_CORE := Color(1.0, 0.8, 0.95)
const THORN_COLOR := Color(0.62, 0.12, 0.3)
const CLAW_COLOR := Color(1.0, 0.94, 0.82)
const CLAW_EDGE := Color(1.0, 0.5, 0.2)
const VENOM_COLOR := Color(0.55, 1.0, 0.25)
const VENOM_DARK := Color(0.2, 0.62, 0.12)
const ROAR_COLOR := Color(0.72, 0.84, 1.0)
const ROAR_CORE := Color(0.96, 0.98, 1.0)
const BURN_COLOR := Color(1.0, 0.55, 0.15)

const MAX_RINGS := 32
const MAX_PROJECTILES := 20
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
# Etappe 17: Waffen-Modifikatoren aus Werten und Relikten (Evolution.form_modifiers()).
var modifiers := {"cooldown": 1.0, "area": 1.0, "acid_damage": 1.0, "dig_radius": 0.0, "chain_chance": 0.0, "burn": 0}

var _enemy_scale := 1.0
var _clock := 0.0
var _bite_timer := 0.0
var _spit_timer := 0.0
var _salvo_timer := -1.0
var _slowed := {}
# Etappe 17: gewünschte Verlangsamung dieses Schritts (id -> [Ziel, Faktor]) und
# zeitlich begrenzte (Betäubung, Schallstoß): id -> {target, factor, until}.
var _slow_wanted := {}
var _timed_slow := {}
var _built := false
var _current: Array = []
var _rng := RandomNumberGenerator.new()
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
var _leap_seconds := LEAP_SECONDS
var _leap_from := Vector3.ZERO
var _leap_to := Vector3.ZERO
var _leap_target: Node3D
var _leap_damage := 0.0
var _leap_radius := RUDELBISS_RADIUS
var _leap_hops := 0
var _leap_stun := false
var _leap_hit: Array = []
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
var _spike_mesh: CylinderMesh

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

# Etappe 17: Pools und MultiMeshes der neuen Waffen und Relikte.
var _claw_angle := 0.0
var _claw_hits := {}
var _claw_horde_cd: Array = [0.0, 0.0, 0.0, 0.0]
var _gift_timer := 0.0
var _roar_timer := 0.0
var _spark_cd := 0.0
var _wall_horde_cd := 0.0
var _snaps: Array = []
var _roars: Array = []
var _darts: Array = []
var _puffs: Array = []
var _pushes: Array = []
# Schaden über Zeit: "iid:kind" -> {target, dps, until, kind, source, spread}.
var _dots := {}
var _blade_batch: MultiMeshInstance3D
var _fang_batch: MultiMeshInstance3D
var _wave_batch: MultiMeshInstance3D
var _dart_batch: MultiMeshInstance3D
var _puff_batch: MultiMeshInstance3D
var _mark_batch: MultiMeshInstance3D
var _wall_batch: MultiMeshInstance3D
var _dot_ring_batch: MultiMeshInstance3D


func setup(world_node: Node3D, swarm_node: Node3D) -> void:
	world = world_node
	swarm = swarm_node
	_rng.seed = 1723
	_build()


# id -> Rang (0..5); evolvierte IDs zählen als Rang 1.
func set_ranks(new_ranks: Dictionary) -> void:
	ranks = {}
	for id in new_ranks:
		var limit := 1 if FORMS.has(id) and FORMS[id].get("evolved", false) else MAX_RANK
		ranks[id] = clampi(int(new_ranks[id]), 0, limit)


## Etappe 17: Werte und Relikte (Evolution.form_modifiers()). Fehlende Schlüssel = neutral.
func set_modifiers(values: Dictionary) -> void:
	modifiers = {
		"cooldown": maxf(0.2, float(values.get("cooldown", 1.0))),
		"area": maxf(0.5, float(values.get("area", 1.0))),
		"acid_damage": float(values.get("acid_damage", 1.0)),
		"dig_radius": float(values.get("dig_radius", 0.0)),
		"chain_chance": clampf(float(values.get("chain_chance", 0.0)), 0.0, 1.0),
		"burn": int(values.get("burn", 0)),
	}


func set_horde(h: Node3D) -> void:
	horde = h


func rank(id: String) -> int:
	return int(ranks.get(id, 0))


func _cd(seconds: float) -> float:
	return seconds * float(modifiers.cooldown)


func _area(radius: float) -> float:
	return radius * float(modifiers.area)


func step(delta: float, targets: Array, rally: bool, enemy_scale: float) -> void:
	_build()
	_enemy_scale = maxf(0.0, enemy_scale)
	_clock += delta
	var origin := _swarm_position()
	var living := _living(targets)
	_current = living
	_slow_wanted = {}
	_spine_horde_cd = maxf(0.0, _spine_horde_cd - delta)
	_spark_cd = maxf(0.0, _spark_cd - delta)
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
	_step_claws(delta, origin, living)
	_step_gift(delta, origin, living)
	_step_roar(delta, origin, living)
	_step_wall(delta, origin, living)
	_step_darts(delta)
	_step_puffs(delta)
	_step_burn(delta, origin, living)
	_step_dots(delta)
	_step_pushes(delta)
	_commit_slows()
	_draw_extra()
	_draw_new()
	_step_rings(delta)


# Rückstoß für stachelruecken: sofortiger Schaden am Angreifer, Effekt läuft in step().
func on_swarm_hit(attacker: Node3D, loss: int) -> void:
	var level := rank("stachelruecken")
	if rank("dornenwall") > 0:
		level = MAX_RANK
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
	# Rang 5 / Dornenwall: eine Stachelsalve fliegt zu den nächsten Gegnern.
	if level >= MAX_RANK:
		_spine_volley(_spine_origin, amount * SPINE_VOLLEY_SHARE, attacker)
	if not _valid_target(attacker):
		return
	_hurt(attacker, amount, "stachelruecken")


func clear() -> void:
	_release_slow({})
	_timed_slow.clear()
	_leap_active = false
	_leap_target = null
	_leap_hit.clear()
	_current = []
	_bite_timer = 0.0
	_spit_timer = 0.0
	_salvo_timer = -1.0
	_spine_age = SPINE_SECONDS
	_leap_brood = false
	_spine_horde_cd = 0.0
	_dig_timer = 0.0
	_chain_timer = 0.0
	_sac_timer = 0.0
	_thorn_horde_cd = 0.0
	_gift_timer = 0.0
	_roar_timer = 0.0
	_claw_hits.clear()
	_dots.clear()
	_pushes.clear()
	for pool in [_tunnels, _eruptions, _bolts, _sacs, _biters, _snaps, _roars, _darts, _puffs]:
		for entry in pool:
			entry.active = false
			if entry.has("target"):
				entry.target = null
	if not _built:
		return
	_draw_extra()
	_draw_new(true)
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
	for pool in [_tunnels, _eruptions, _bolts, _sacs, _biters, _snaps, _roars, _darts, _puffs]:
		for entry in pool:
			if entry.active:
				count += 1
	return count + _dots.size()


# Aktive Einträge eines Pools ("tunnels", "eruptions", "bolts", "sacs", "biters",
# Etappe 17: "snaps", "roars", "darts", "puffs", "dots").
func active_count(kind: String) -> int:
	if kind == "dots":
		return _dots.size()
	var pool: Array = {"tunnels": _tunnels, "eruptions": _eruptions, "bolts": _bolts, "sacs": _sacs, "biters": _biters,
		"snaps": _snaps, "roars": _roars, "darts": _darts, "puffs": _puffs}.get(kind, [])
	var count := 0
	for entry in pool:
		if entry.active:
			count += 1
	return count


## Etappe 17: Anzahl vergifteter/brennender Ziele ("poison" | "burn").
func dot_count(kind: String) -> int:
	var count := 0
	for key in _dots:
		if String(_dots[key].kind) == kind:
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


## Etappe 17 – Kill-Hook (HuntWorld): `burst` = Sporenherz hat gewürfelt; in der
## Pilzreich-Aura platzt jeder Kill als Pilzwolke.
func on_kill(at: Vector3, burst: bool = false) -> void:
	if at == Vector3.INF:
		return
	var in_realm := rank("pilzreich") > 0 and _flat_distance(at, _swarm_position()) <= _area(PILZ_RADIUS) + 0.5
	if burst or in_realm:
		spore_burst(at)


## Sporenwolke an `at` (Sporenherz, Pilzreich): kurzer Schaden über Zeit + Verlangsamung.
func spore_burst(at: Vector3) -> void:
	_build()
	var entry: Dictionary = _take(_puffs, MAX_PUFFS, _make_puff)
	entry.active = true
	entry.age = 0.0
	entry.at = _flat(at)
	entry.radius = _area(PUFF_RADIUS)
	entry.dps = PUFF_DPS
	_ring(entry.at, Color(SPORE_COLOR.r, SPORE_COLOR.g, SPORE_COLOR.b, 0.9), 0.3, entry.radius * 1.1, 0.35, true)


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
		_advance_leap(delta, rally)
	if _leap_active or _bite_timer > 0.0 or (not rally and not pack):
		return
	var target := _nearest(living, origin, _area(RUDELBISS_REACH))
	var brood := Vector3.INF
	if target == null:
		brood = _brood_near(origin, _area(RUDELBISS_REACH))
		if brood == Vector3.INF:
			return
	if pack:
		_bite_timer = _cd(MEUTE_INTERVAL)
		_leap_radius = _area(MEUTE_RADIUS)
		_leap_damage = MEUTE_DAMAGE * (MEUTE_RALLY_MULTIPLIER if rally else 1.0)
		_leap_hops = MEUTE_HOPS
		_leap_stun = true
	else:
		_bite_timer = _cd(RUDELBISS_INTERVAL[level - 1])
		_leap_radius = _area(RUDELBISS_RADIUS)
		_leap_damage = RUDELBISS_DAMAGE[level - 1]
		_leap_hops = RUDELBISS_HOPS[level - 1]
		_leap_stun = level >= MAX_RANK
	_leap_damage *= _enemy_scale
	_leap_hit.clear()
	_start_leap(origin, target, brood, LEAP_SECONDS)


func _start_leap(from: Vector3, target: Node3D, brood: Vector3, seconds: float) -> void:
	_leap_active = true
	_leap_age = 0.0
	_leap_seconds = seconds
	_leap_from = from
	_leap_target = target
	_leap_brood = target == null
	_leap_to = _flat(target.global_position) if target != null else brood
	_arc_root.visible = true
	_leap_marker.visible = true
	_pose_arc()


func _advance_leap(delta: float, _rally: bool) -> void:
	_leap_age += delta
	if _valid_target(_leap_target):
		_leap_to = _flat(_leap_target.global_position)
	elif _leap_brood:
		_leap_to = _track_brood(_leap_to)
	if _leap_age < _leap_seconds:
		_pose_arc()
		return
	_leap_active = false
	var landed := _leap_target
	_leap_target = null
	_arc_root.visible = false
	_leap_marker.visible = false
	var tint := BITE_COLOR if rank("meute") <= 0 else Color(1.0, 0.42, 0.16)
	_ring(_leap_to, Color(tint.r, tint.g, tint.b, 0.95), _leap_radius * 0.6, _leap_radius * 1.1, 0.4, true)
	_ring(_leap_to, Color(LEAP_CORE.r, LEAP_CORE.g, LEAP_CORE.b, 0.9), 0.2, _leap_radius * 0.55, 0.26, true)
	if _leap_stun:
		# Betäubung: ein weißer Doppelring zeigt den Stillstand.
		_ring(_leap_to, Color(1.0, 1.0, 0.9, 0.9), _leap_radius * 0.3, _leap_radius * 0.8, 0.5)
	var source := "meute" if rank("meute") > 0 else "rudelbiss"
	for target in _targets_near(_leap_to, _leap_radius):
		_hurt(target, _leap_damage, source)
		_ignite(target)
		if _leap_stun:
			_slow_for(target, 0.0, RUDELBISS_STUN)
	if _has_horde():
		horde.damage_circle(_leap_to, _leap_radius, _leap_damage)
		_note_horde(source, _leap_damage)
	_leap_brood = false
	if landed != null:
		_leap_hit.append(landed.get_instance_id())
	# Rang 3+: der Sprung setzt zum nächsten, noch nicht getroffenen Ziel fort.
	if _leap_hops > 0:
		_leap_hops -= 1
		var used := {}
		for id in _leap_hit:
			used[id] = true
		var next := _nearest_unused(_current, _leap_to, _area(RUDELBISS_HOP_REACH), used)
		if next != null:
			_start_leap(_leap_to, next, Vector3.INF, HOP_SECONDS)


func _pose_arc() -> void:
	var progress := clampf(_leap_age / _leap_seconds, 0.0, 1.0)
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


# --- Sporenwolke / Pilzreich ---------------------------------------------

func _step_spores(delta: float, origin: Vector3, living: Array) -> void:
	var level := rank("sporenwolke")
	var realm := rank("pilzreich") > 0
	if level <= 0 and not realm:
		_spore_root.visible = false
		return
	var radius: float = _area(PILZ_RADIUS if realm else SPORE_RADIUS[level - 1])
	var dps: float = (PILZ_DPS if realm else SPORE_DPS[level - 1]) * _enemy_scale
	var slow: float = PILZ_SLOW if realm else SPORE_SLOW[level - 1]
	var source := "pilzreich" if realm else "sporenwolke"
	for target in living:
		if _target_distance(target, origin) > radius:
			continue
		_hurt(target, dps * delta, source, true)
		_want_slow(target, slow)
	if _has_horde():
		horde.damage_circle(origin, radius, dps * delta)
		_note_horde(source, dps * delta)
	_pose_spores(origin, radius, realm)


func _pose_spores(origin: Vector3, radius: float, realm: bool = false) -> void:
	_spore_root.visible = true
	_spore_root.global_position = Vector3(origin.x, 0.0, origin.z)
	_spore_visual_radius = lerpf(_spore_visual_radius, radius, 0.2) if _spore_visual_radius > 0.0 else radius
	var r := _spore_visual_radius
	var tone := SPORE_COLOR if not realm else Color(0.95, 0.62, 0.95)
	_spore_edge.scale = Vector3(r, 0.3, r)
	_spore_edge_material.albedo_color = Color(tone.r, tone.g, tone.b, 0.32 + 0.08 * sin(_clock * 3.0))
	# Ein Innenring läuft langsam nach außen und verblasst – zeigt die Aura-Wirkung.
	var wave := fmod(_clock * 0.55, 1.0)
	var inner := lerpf(r * 0.35, r, wave)
	_spore_pulse.scale = Vector3(inner, 0.3, inner)
	_spore_pulse_material.albedo_color = Color(tone.r, tone.g, tone.b, 0.3 * (1.0 - wave))
	var mote_tint := Color(tone.r, tone.g, tone.b, 0.42)
	_mote_batch.begin()
	for index in _mote_count:
		var phase := float(index) / float(_mote_count)
		var angle := phase * TAU + _clock * (0.35 + 0.1 * float(index % 3))
		var reach := r * (0.45 + 0.5 * fmod(phase * 3.7 + _clock * 0.08, 1.0))
		var lift := 0.35 + 0.35 * (0.5 + 0.5 * sin(_clock * 1.7 + phase * 11.0))
		var size := (0.8 + 0.35 * sin(_clock * 2.3 + phase * 7.0)) * (1.4 if realm else 1.0)
		_mote_batch.add(Transform3D(Basis.from_scale(Vector3.ONE * size), Vector3(cos(angle) * reach, lift, sin(angle) * reach)), mote_tint)
	_mote_batch.finish()


# --- Verlangsamung (Sporen, Betäubung, Schallstoß) -------------------------

func _want_slow(target: Node3D, factor: float) -> void:
	if not ("slow_factor" in target):
		return
	var id := target.get_instance_id()
	if _slow_wanted.has(id):
		_slow_wanted[id][1] = minf(float(_slow_wanted[id][1]), factor)
	else:
		_slow_wanted[id] = [target, factor]


func _slow_for(target: Node3D, factor: float, seconds: float) -> void:
	if not ("slow_factor" in target):
		return
	var id := target.get_instance_id()
	var until := _clock + seconds
	if _timed_slow.has(id):
		var entry: Dictionary = _timed_slow[id]
		entry.factor = minf(float(entry.factor), factor)
		entry.until = maxf(float(entry.until), until)
	else:
		_timed_slow[id] = {"target": target, "factor": factor, "until": until}


# Setzt je Ziel den kleinsten gewünschten Faktor; wer nicht mehr gebremst wird, läuft wieder normal.
func _commit_slows() -> void:
	for id in _timed_slow.keys():
		var entry: Dictionary = _timed_slow[id]
		if _clock >= float(entry.until) or not is_instance_valid(entry.target):
			_timed_slow.erase(id)
			continue
		if _slow_wanted.has(id):
			_slow_wanted[id][1] = minf(float(_slow_wanted[id][1]), float(entry.factor))
		else:
			_slow_wanted[id] = [entry.target, float(entry.factor)]
	var keep := {}
	for id in _slow_wanted:
		var target = _slow_wanted[id][0]
		if is_instance_valid(target):
			target.set("slow_factor", float(_slow_wanted[id][1]))
			keep[id] = target
	_release_slow(keep)


func _release_slow(keep: Dictionary) -> void:
	for id in _slowed:
		if keep.has(id):
			continue
		var target = _slowed[id]
		if is_instance_valid(target) and "slow_factor" in target:
			target.set("slow_factor", 1.0)
	_slowed = keep.duplicate()


# --- Säurespucker / Ätzflut ----------------------------------------------

func _spit_level() -> int:
	return MAX_RANK if rank("aetzflut") > 0 else rank("saeurespucker")


func _step_spit(delta: float, origin: Vector3, living: Array) -> void:
	var level := _spit_level()
	if level <= 0:
		return
	# Rang 3+: die zweite Salve folgt kurz nach der ersten.
	if _salvo_timer >= 0.0:
		_salvo_timer -= delta
		if _salvo_timer < 0.0:
			_fire_spit(origin, living, level)
	_spit_timer = maxf(0.0, _spit_timer - delta)
	if _spit_timer > 0.0:
		return
	if not _fire_spit(origin, living, level):
		return
	_spit_timer = _cd(SPIT_INTERVAL[level - 1])
	if SPIT_SALVOS[level - 1] > 1:
		_salvo_timer = SPIT_SALVO_GAP


func _fire_spit(origin: Vector3, living: Array, level: int) -> bool:
	var target := _nearest(living, origin, _area(SPIT_REACH))
	var brood := Vector3.INF
	if target == null:
		brood = _brood_near(origin, _area(SPIT_REACH))
		if brood == Vector3.INF:
			return false
	var entry: Dictionary = _take(_projectiles, MAX_PROJECTILES, _make_projectile)
	entry.active = true
	entry.age = 0.0
	entry.target = target
	entry.brood = target == null
	entry.aim = _flat(target.global_position) if target != null else brood
	entry.damage = SPIT_DAMAGE[level - 1] * _enemy_scale * float(modifiers.acid_damage)
	entry.pierce = SPIT_PIERCE[level - 1] + (1 if rank("aetzflut") > 0 else 0)
	entry.hit = []
	entry.node.visible = true
	entry.node.global_position = Vector3(origin.x, SPIT_HEIGHT, origin.z)
	for index in entry.trail.size():
		entry.trail[index].position = Vector3.ZERO
		entry.trail[index].visible = index < _trail_count
	return true


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
		var hit_point: Vector3 = entry.aim
		var source := "aetzflut" if rank("aetzflut") > 0 else "saeurespucker"
		if tracking:
			_hurt(entry.target, entry.damage, source)
			entry.hit.append(entry.target.get_instance_id())
			_ring(hit_point, Color(ACID_COLOR.r, ACID_COLOR.g, ACID_COLOR.b, 0.85), 0.15, 0.9, 0.25)
			if rank("aetzflut") > 0:
				_spawn_puddle(hit_point)
			# Rang 5 / Ätzflut: die Säure schlägt durch und fliegt zum nächsten Ziel weiter.
			if int(entry.pierce) > 0:
				var used := {}
				for id in entry.hit:
					used[id] = true
				var next := _nearest_unused(living, hit_point, _area(SPIT_PIERCE_REACH), used)
				if next != null:
					entry.pierce -= 1
					entry.target = next
					entry.age = 0.0
					_ring(hit_point, Color(1.0, 1.0, 0.7, 0.9), 0.1, 0.6, 0.2)
					continue
		elif entry.brood and _has_horde():
			var struck: Vector3 = horde.damage_nearest(hit_point, 1.0, entry.damage)
			if struck != Vector3.INF:
				_note_horde(source, entry.damage)
				_ring(struck, Color(ACID_COLOR.r, ACID_COLOR.g, ACID_COLOR.b, 0.85), 0.15, 0.9, 0.25)
				if rank("aetzflut") > 0:
					_spawn_puddle(struck)
		entry.active = false
		node.visible = false
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
			if _target_distance(target, entry.center) <= PUDDLE_RADIUS:
				_hurt(target, PUDDLE_DPS * _enemy_scale * delta, "aetzflut", true)
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


# --- Stachelrücken / Dornenwall ------------------------------------------

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


# Rang 5: Stacheln fliegen als Salve zu den nächsten Gegnern (nicht zum Angreifer).
func _spine_volley(origin: Vector3, damage: float, attacker: Node3D) -> void:
	var ranked: Array = []
	for target in _current:
		if target == attacker or not _valid_target(target):
			continue
		var distance := _target_distance(target, origin)
		if distance <= _area(SPINE_VOLLEY_REACH):
			ranked.append([distance, target])
	ranked.sort_custom(func(a, b): return a[0] < b[0])
	for index in mini(SPINE_VOLLEY, ranked.size()):
		var dart: Dictionary = _take(_darts, MAX_DARTS, _make_dart)
		dart.active = true
		dart.age = 0.0
		dart.from = _flat(origin)
		dart.target = ranked[index][1]
		dart.to = _flat(ranked[index][1].global_position)
		dart.damage = damage


func _step_darts(delta: float) -> void:
	for dart in _darts:
		if not dart.active:
			continue
		dart.age += delta
		if _valid_target(dart.target):
			dart.to = _flat(dart.target.global_position)
		if dart.age < DART_SECONDS:
			continue
		dart.active = false
		if _valid_target(dart.target):
			_hurt(dart.target, dart.damage, "stachelruecken")
			_ring(dart.to, Color(SPINE_COLOR.r, SPINE_COLOR.g, SPINE_COLOR.b, 0.85), 0.1, 0.7, 0.2)
		dart.target = null


func _step_wall(delta: float, origin: Vector3, living: Array) -> void:
	if rank("dornenwall") <= 0:
		return
	_wall_horde_cd = maxf(0.0, _wall_horde_cd - delta)
	var radius := _swarm_radius() + 0.6
	var dps := WALL_DPS * _enemy_scale
	for target in living:
		if _target_distance(target, origin) <= radius + _area(WALL_WIDTH):
			_hurt(target, dps * delta, "dornenwall", true)
	if _has_horde():
		horde.damage_circle(origin, radius + _area(WALL_WIDTH), dps * delta)
		_note_horde("dornenwall", dps * delta)


# --- Gräber / Erdbeben (Etappe 10) ---------------------------------------

func _step_dig(delta: float, origin: Vector3, living: Array) -> void:
	var level := rank("graeber")
	var quake := rank("erdbeben") > 0
	if level <= 0 and not quake:
		return
	_dig_timer = maxf(0.0, _dig_timer - delta)
	if _dig_timer > 0.0:
		return
	var index := MAX_RANK - 1 if quake else level - 1
	var count: int = QUAKE_TUNNELS if quake else GRAEBER_TUNNELS[index]
	var aims := _farthest_aims(living, origin, _area(GRAEBER_REACH[index]), count)
	if aims.is_empty():
		_dig_timer = 0.2
		return
	_dig_timer = _cd(QUAKE_INTERVAL if quake else GRAEBER_INTERVAL[index])
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
		entry.radius = _area(QUAKE_RADIUS if quake else GRAEBER_RADIUS[index]) + float(modifiers.dig_radius)
		entry.source = "erdbeben" if quake else "graeber"
		entry.aftershock = quake or level >= MAX_RANK
		entry.hidden = false


# Bis zu `count` Ziele, entfernteste zuerst: echte Gegner, sonst Brut (mit
# Mindestabstand, damit Erdbeben nicht dreimal denselben Klumpen trifft).
func _farthest_aims(living: Array, origin: Vector3, reach: float, count: int) -> Array:
	var ranked: Array = []
	for target in living:
		var distance := _target_distance(target, origin)
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
	var reach := _area(STORM_REACH if storm else BLITZ_REACH)
	var jump := _area(STORM_JUMP if storm else BLITZ_JUMP)
	var hops: int = STORM_TARGETS if storm else BLITZ_TARGETS[level - 1]
	var damage: float = (STORM_DAMAGE if storm else BLITZ_DAMAGE[level - 1]) * _enemy_scale
	var falloff := 1.0 if storm or level >= MAX_RANK else BLITZ_FALLOFF
	var source := "sturmrudel" if storm else "blitzbiss"
	var points := _chain(_flat(origin), living, reach, jump, hops, damage, falloff, source, {})
	if points.size() <= 1:
		_chain_timer = 0.15
		return
	_chain_timer = _cd((STORM_RALLY_INTERVAL if rally else STORM_INTERVAL) if storm else BLITZ_INTERVAL[level - 1])
	_bolt(points, storm, BOLT_COLOR)


# Kette ab `at`: echte Gegner und Brut, je Sprung höchstens `jump` m. Liefert die Punkte.
func _chain(at: Vector3, living: Array, reach: float, jump: float, hops: int, damage: float, falloff: float, source: String, used: Dictionary) -> PackedVector3Array:
	var brood := PackedVector3Array()
	var brood_loaded := false
	var used_brood := {}
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
		if brood_index >= 0 and node != null and _target_distance(node, at) <= _flat_distance(brood[brood_index], at):
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
			# Gewitterfell-Funken lösen keine neuen Funken aus.
			_hurt(node, damage, source, source == "gewitterfell")
		else:
			break
		points.append(at)
		damage *= falloff
	return points


func _bolt(points: PackedVector3Array, storm: bool, tint: Color) -> void:
	var entry: Dictionary = _take(_bolts, MAX_BOLTS, _make_bolt)
	entry.active = true
	entry.age = 0.0
	entry.points = points
	entry.seed = _clock * 13.7
	entry.storm = storm
	entry.tint = tint


func _nearest_unused(living: Array, at: Vector3, reach: float, used: Dictionary) -> Node3D:
	var best: Node3D = null
	var best_distance := reach
	for target in living:
		if used.has(target.get_instance_id()) or not _valid_target(target):
			continue
		var distance := _target_distance(target, at)
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
	var target := _nearest(living, origin, _area(SAC_SENSE))
	var toward := _flat(target.global_position) if target != null else _brood_near(origin, _area(SAC_SENSE))
	if toward == Vector3.INF:
		_sac_timer = 0.2
		return
	_sac_timer = _cd(SAC_INTERVAL[level - 1])
	var base := _flat(origin)
	var direction := toward - base
	var distance := direction.length()
	direction = direction / distance if distance > 0.01 else Vector3.RIGHT
	for index in SAC_COUNT[level - 1]:
		# Rang 3+: die zweite Blase sitzt auf der anderen Seite der Blickrichtung.
		var swing := sin(_clock * 7.3) * 0.8 if index == 0 else -1.4
		var side := Vector3(-direction.z, 0.0, direction.x) * swing
		var entry: Dictionary = _take(_sacs, MAX_SACS, _make_sac)
		entry.active = true
		entry.age = -0.12 * float(index)
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
	var long_life := level >= MAX_RANK
	var reach := _area(BITER_REACH_LONG if long_life else BITER_REACH)
	var aims: Array = []
	var ranked: Array = []
	for target in _targets_near(at, reach):
		ranked.append([_target_distance(target, at), target])
	ranked.sort_custom(func(a, b): return a[0] < b[0])
	for entry in ranked:
		aims.append({"target": entry[1], "at": _flat(entry[1].global_position)})
	var count: int = SAC_BITERS[level - 1]
	if aims.is_empty() and _has_horde():
		var brood: Array = []
		for point in horde.call("positions"):
			var distance := _flat_distance(point, at)
			if distance <= reach:
				brood.append([distance, _flat(point)])
		brood.sort_custom(func(a, b): return a[0] < b[0])
		for index in mini(count, brood.size()):
			aims.append({"target": null, "at": brood[index][1]})
	for index in count:
		var biter: Dictionary = _take(_biters, MAX_BITERS, _make_biter)
		var angle := TAU * float(index) / float(count) + _clock
		biter.active = true
		biter.age = 0.0
		biter.life = BITER_LIFE_LONG if long_life else BITER_LIFE
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
		if biter.age >= biter.life:
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
		if tracking:
			_hurt(biter.target, biter.damage, "brutsack")
			_ignite(biter.target)
			_ring(biter.aim, Color(SAC_COLOR.r, SAC_COLOR.g, SAC_COLOR.b, 0.85), 0.1, 0.6, 0.2)
		elif biter.brood and _has_horde():
			var struck: Vector3 = horde.damage_nearest(biter.aim, 1.0, biter.damage)
			if struck != Vector3.INF:
				_note_horde("brutsack", biter.damage)
				_ring(struck, Color(SAC_COLOR.r, SAC_COLOR.g, SAC_COLOR.b, 0.85), 0.1, 0.6, 0.2)
		# Langlebige Beißer (Rang 5) jagen nach einem Biss das nächste Ziel.
		var next: Node3D = null
		if biter.life > BITER_LIFE and biter.age < biter.life - 0.3:
			var used := {}
			if tracking:
				used[biter.target.get_instance_id()] = true
			next = _nearest_unused(_current, biter.pos, _area(BITER_REACH), used)
		if next != null:
			biter.target = next
			biter.brood = false
			biter.aim = _flat(next.global_position)
			continue
		biter.active = false
		biter.target = null


# --- Klauenwirbel (Etappe 17) --------------------------------------------

func _claw_level() -> int:
	return rank("klauenwirbel")


func _claw_orbit(level: int) -> float:
	return _swarm_radius() + _area(CLAW_ORBIT[level - 1])


func _step_claws(delta: float, origin: Vector3, living: Array) -> void:
	var level := _claw_level()
	if level <= 0:
		return
	# Angriffstempo dreht die Klingen schneller.
	_claw_angle = fmod(_claw_angle + CLAW_SPIN[level - 1] * delta / float(modifiers.cooldown), TAU)
	var blades: int = CLAW_BLADES[level - 1]
	var orbit := _claw_orbit(level)
	var hit_radius: float = _area(CLAW_HIT) * CLAW_SIZE[level - 1]
	var damage: float = CLAW_DAMAGE[level - 1] * _enemy_scale
	for id in _claw_hits.keys():
		_claw_hits[id] = float(_claw_hits[id]) - delta
		if float(_claw_hits[id]) <= 0.0:
			_claw_hits.erase(id)
	for index in blades:
		var at := _blade_point(origin, index, blades, orbit)
		for target in living:
			var id: int = target.get_instance_id()
			if _claw_hits.has(id) or _target_distance(target, at) > hit_radius:
				continue
			_claw_hits[id] = CLAW_REHIT * float(modifiers.cooldown)
			_hurt(target, damage, "klauenwirbel")
			_ignite(target)
			_ring(_flat(target.global_position), Color(CLAW_EDGE.r, CLAW_EDGE.g, CLAW_EDGE.b, 0.8), 0.1, 0.8, 0.18)
		if _has_horde():
			_claw_horde_cd[index] = float(_claw_horde_cd[index]) - delta
			if float(_claw_horde_cd[index]) <= 0.0:
				_claw_horde_cd[index] = CLAW_HORDE_REHIT
				horde.damage_circle(at, hit_radius, damage)
				_note_horde("klauenwirbel", damage)


func _blade_point(origin: Vector3, index: int, blades: int, orbit: float) -> Vector3:
	var angle := _claw_angle + TAU * float(index) / float(blades)
	return Vector3(origin.x + cos(angle) * orbit, 0.0, origin.z + sin(angle) * orbit)


# --- Giftbiss (Etappe 17) ------------------------------------------------

func _step_gift(delta: float, origin: Vector3, living: Array) -> void:
	for entry in _snaps:
		if entry.active:
			entry.age += delta
			if entry.age >= SNAP_SECONDS:
				entry.active = false
	var level := rank("giftbiss")
	if level <= 0:
		return
	_gift_timer = maxf(0.0, _gift_timer - delta)
	if _gift_timer > 0.0:
		return
	var reach := _swarm_radius() + _area(GIFT_REACH)
	var ranked: Array = []
	for target in living:
		var distance := _target_distance(target, origin)
		if distance <= reach:
			ranked.append([distance, target])
	ranked.sort_custom(func(a, b): return a[0] < b[0])
	var count: int = GIFT_TARGETS[level - 1]
	var bite: float = GIFT_BITE[level - 1] * _enemy_scale
	var snapped := 0
	for index in mini(count, ranked.size()):
		var target: Node3D = ranked[index][1]
		_hurt(target, bite, "giftbiss")
		_poison(target, GIFT_DPS[level - 1] * _enemy_scale, GIFT_SECONDS[level - 1], level >= MAX_RANK)
		_ignite(target)
		_snap(_flat(target.global_position), origin)
		snapped += 1
	# Brut bekommt Biss und die Hälfte des Gifts sofort (keine Einzel-DoTs in der Horde).
	if snapped < count and _has_horde():
		var brood: Array = []
		for point in horde.call("positions"):
			var distance := _flat_distance(point, origin)
			if distance <= reach:
				brood.append([distance, point])
		brood.sort_custom(func(a, b): return a[0] < b[0])
		var instant: float = bite + 0.5 * GIFT_DPS[level - 1] * GIFT_SECONDS[level - 1] * _enemy_scale
		for index in mini(count - snapped, brood.size()):
			var struck: Vector3 = horde.damage_nearest(brood[index][1], 0.6, instant)
			if struck != Vector3.INF:
				_note_horde("giftbiss", instant)
				_snap(_flat(struck), origin)
				snapped += 1
	_gift_timer = _cd(GIFT_INTERVAL[level - 1]) if snapped > 0 else 0.2


func _snap(at: Vector3, origin: Vector3) -> void:
	var entry: Dictionary = _take(_snaps, MAX_SNAPS, _make_snap)
	entry.active = true
	entry.age = 0.0
	entry.at = at
	var facing := at - _flat(origin)
	entry.dir = facing.normalized() if facing.length() > 0.05 else Vector3.FORWARD
	_ring(at, Color(VENOM_COLOR.r, VENOM_COLOR.g, VENOM_COLOR.b, 0.85), 0.15, 1.0, 0.28)


func _poison(target: Node3D, dps: float, seconds: float, spread: bool) -> void:
	_add_dot(target, "poison", dps, seconds, "giftbiss", spread)


# --- Schallbrüller (Etappe 17) -------------------------------------------

func _step_roar(delta: float, origin: Vector3, living: Array) -> void:
	for entry in _roars:
		if entry.active:
			entry.age += delta
			entry.origin = _flat(origin)
			if entry.age >= ROAR_SECONDS:
				entry.active = false
	var level := rank("schallbrueller")
	if level <= 0:
		return
	_roar_timer = maxf(0.0, _roar_timer - delta)
	if _roar_timer > 0.0:
		return
	var reach := _area(ROAR_REACH[level - 1])
	var target := _nearest(living, origin, reach)
	var aim := _flat(target.global_position) if target != null else _brood_near(origin, reach)
	if aim == Vector3.INF:
		_roar_timer = 0.2
		return
	_roar_timer = _cd(ROAR_INTERVAL[level - 1])
	var forward := aim - _flat(origin)
	forward = forward.normalized() if forward.length() > 0.05 else Vector3.FORWARD
	var directions: Array = [forward]
	if ROAR_CONES[level - 1] > 1:
		directions.append(-forward)
	var damage: float = ROAR_DAMAGE[level - 1] * _enemy_scale
	var angle: float = ROAR_ANGLE[level - 1]
	for dir in directions:
		_cone(_flat(origin), dir, reach, angle, damage, ROAR_PUSH[level - 1], living)
		var entry: Dictionary = _take(_roars, MAX_ROARS, _make_roar)
		entry.active = true
		entry.age = 0.0
		entry.origin = _flat(origin)
		entry.dir = dir
		entry.reach = reach
		entry.angle = angle
		entry.heavy = level >= 3


func _cone(origin: Vector3, dir: Vector3, reach: float, angle: float, damage: float, push: float, living: Array) -> void:
	var cos_limit := cos(angle)
	for target in living:
		var offset := _flat(target.global_position) - origin
		var distance := _target_distance(target, origin)
		if distance > reach:
			continue
		var along := offset.normalized() if offset.length() > 0.05 else dir
		if along.dot(dir) < cos_limit and offset.length() > 1.0:
			continue
		_hurt(target, damage, "schallbrueller")
		_slow_for(target, 0.5, ROAR_STAGGER)
		_push(target, along * push * (1.0 - 0.4 * clampf(distance / reach, 0.0, 1.0)))
	if _has_horde():
		# Drei Kreise entlang der Achse decken den Kegel ab.
		for k in 3:
			var d := reach * (0.3 + 0.28 * float(k))
			var r := minf(d * tan(angle), reach * 0.16 + 0.6)
			horde.damage_circle(origin + dir * d, r, damage)
			_note_horde("schallbrueller", damage)


# Leichte Gegner (mit slow_factor) rutschen kurz zurück; Bosse nie.
func _push(target: Node3D, offset: Vector3) -> void:
	if not ("slow_factor" in target) or target.has_method("body_distance"):
		return
	_pushes.append({"target": target, "vel": offset / PUSH_SECONDS, "left": PUSH_SECONDS})


func _step_pushes(delta: float) -> void:
	if _pushes.is_empty():
		return
	var arena: Node = world.get_parent().get_node_or_null("Arena") if world != null and world.get_parent() != null else null
	var still: Array = []
	for push in _pushes:
		var target = push.target
		if not is_instance_valid(target) or not _valid_target(target):
			continue
		var step_time := minf(delta, float(push.left))
		var motion: Vector3 = push.vel * step_time
		if arena != null and arena.has_method("resolve_motion"):
			target.position = arena.resolve_motion(target.position, motion, 0.6)
		else:
			target.position += motion
		push.left = float(push.left) - step_time
		if float(push.left) > 0.0:
			still.append(push)
	_pushes = still


# --- Relikte: Brand, Gewitterfell, Sporenwolken (Etappe 17) ---------------

# Glutdrüse: alles im Beißabstand des Schwarms brennt; Bisswaffen zünden ebenfalls.
func _step_burn(_delta: float, origin: Vector3, living: Array) -> void:
	if int(modifiers.burn) <= 0:
		return
	var reach := _swarm_radius() + BURN_REACH
	for target in living:
		if _target_distance(target, origin) <= reach:
			_ignite(target)
	if _has_horde():
		horde.damage_circle(origin, reach, BURN_DPS * float(modifiers.burn) * _enemy_scale * _delta)
		_note_horde("glutdruese", BURN_DPS * float(modifiers.burn) * _enemy_scale * _delta)


func _ignite(target: Node3D) -> void:
	if int(modifiers.burn) <= 0 or not _valid_target(target):
		return
	_add_dot(target, "burn", BURN_DPS * float(modifiers.burn) * _enemy_scale, BURN_SECONDS, "glutdruese", false)


func _add_dot(target: Node3D, kind: String, dps: float, seconds: float, source: String, spread: bool) -> void:
	if not _valid_target(target) or dps <= 0.0:
		return
	var key := "%d:%s" % [target.get_instance_id(), kind]
	if _dots.has(key):
		var entry: Dictionary = _dots[key]
		entry.dps = maxf(float(entry.dps), dps)
		entry.until = maxf(float(entry.until), _clock + seconds)
		entry.spread = bool(entry.spread) or spread
		return
	if _dots.size() >= MAX_MARKS * 2:
		return
	_dots[key] = {"target": target, "dps": dps, "until": _clock + seconds, "kind": kind, "source": source, "spread": spread, "seconds": seconds}


func _step_dots(delta: float) -> void:
	if _dots.is_empty():
		return
	for key in _dots.keys():
		var entry: Dictionary = _dots[key]
		var target = entry.target
		if not is_instance_valid(target):
			_dots.erase(key)
			continue
		if not _valid_target(target):
			_dots.erase(key)
			continue
		_hurt(target, float(entry.dps) * delta, String(entry.source), true)
		if "health" in target and float(target.get("health")) <= 0.0:
			_dots.erase(key)
			# Giftbiss Rang 5: das Gift springt auf den nächsten Gegner über.
			if bool(entry.spread):
				var used := {target.get_instance_id(): true}
				var next := _nearest_unused(_current, _flat(target.global_position), _area(GIFT_SPREAD), used)
				if next != null:
					_add_dot(next, String(entry.kind), float(entry.dps), float(entry.seconds), String(entry.source), true)
					_bolt(PackedVector3Array([_flat(target.global_position), _flat(next.global_position)]), false, VENOM_COLOR)
			continue
		if _clock >= float(entry.until):
			_dots.erase(key)


# Gewitterfell: Treffer lösen mit Chance einen kleinen Kettenblitz aus.
func _on_hit(target: Node3D, source: String) -> void:
	var chance := float(modifiers.chain_chance)
	if chance <= 0.0 or _spark_cd > 0.0 or source == "gewitterfell" or not is_instance_valid(target):
		return
	if _rng.randf() >= chance:
		return
	_spark_cd = SPARK_COOLDOWN
	var used := {target.get_instance_id(): true}
	var points := _chain(_flat(target.global_position), _current, _area(SPARK_JUMP), _area(SPARK_JUMP), SPARK_HOPS, SPARK_DAMAGE * _enemy_scale, 1.0, "gewitterfell", used)
	if points.size() > 1:
		_bolt(points, false, Color(0.62, 0.9, 1.0))


func _step_puffs(delta: float) -> void:
	for entry in _puffs:
		if not entry.active:
			continue
		entry.age += delta
		if entry.age >= PUFF_SECONDS:
			entry.active = false
			continue
		var dps: float = float(entry.dps) * _enemy_scale
		for target in _current:
			if _valid_target(target) and _target_distance(target, entry.at) <= entry.radius:
				_hurt(target, dps * delta, "sporenherz", true)
				_want_slow(target, PUFF_SLOW)
		if _has_horde():
			horde.damage_circle(entry.at, entry.radius, dps * delta)
			_note_horde("sporenherz", dps * delta)


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
		var tint: Color = entry.get("tint", BOLT_COLOR)
		var core := BOLT_CORE if tint == BOLT_COLOR else tint.lerp(Color.WHITE, 0.6)
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
				_bolt_segment(previous, next, width, Color(tint.r, tint.g, tint.b, 0.7 * fade))
				_bolt_segment(previous, next, width * 0.42, Color(core.r, core.g, core.b, fade))
				previous = next
			var spark := lerpf(2.4, 0.8, t)
			_spark_batch.add(Transform3D(Basis.from_scale(Vector3.ONE * spark), b), Color(core.r, core.g, core.b, 0.9 * fade))
	_bolt_batch.finish()
	_spark_batch.finish()

	_sac_batch.begin()
	for entry in _sacs:
		if not entry.active or entry.age < 0.0:
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
		var fade: float = 1.0 - smoothstep(0.75, 1.0, biter.age / float(biter.life))
		var body := Basis.looking_at(heading if heading.length() > 0.01 else Vector3.FORWARD, Vector3.UP)
		var at: Vector3 = biter.pos + Vector3(0, 0.3 + 0.5 * hop, 0)
		_biter_batch.add(Transform3D(body.scaled_local(Vector3(1.7, 1.4, 2.4) * fade), at), SAC_COLOR)
		_biter_batch.add(Transform3D(body.scaled_local(Vector3.ONE * 0.8 * fade), at + heading * 0.42 + Vector3(0, 0.1, 0)), SAC_CORE)
	_biter_batch.finish()


# Etappe 17: Klingen, Giftfänge, Schallwellen, Stachelsalve, Sporenwolken,
# Brand-/Giftmarken und Dornenwall. `hide_all` leert alle Batches (clear()).
func _draw_new(hide_all := false) -> void:
	if not _built:
		return
	var origin := _swarm_position()
	_blade_batch.begin()
	var level := _claw_level()
	if level > 0 and not hide_all:
		var blades: int = CLAW_BLADES[level - 1]
		var orbit := _claw_orbit(level)
		var size: float = CLAW_SIZE[level - 1] * float(modifiers.area)
		for index in blades:
			for ghost in CLAW_TRAIL:
				# Die Klinge zieht zwei blassere Nachbilder hinter sich her.
				var angle := _claw_angle + TAU * float(index) / float(blades) - float(ghost) * 0.17
				var at := Vector3(origin.x + cos(angle) * orbit, 0.55, origin.z + sin(angle) * orbit)
				var tangent := Vector3(-sin(angle), 0.0, cos(angle))
				var outward := Vector3(cos(angle), 0.0, sin(angle))
				# Gebogene Kralle: Spitze voraus in Drehrichtung, leicht nach außen gekippt.
				var basis := Basis.looking_at(tangent + outward * 0.35, Vector3.UP)
				basis = basis * Basis(Vector3.RIGHT, -PI * 0.5)
				var k := 1.0 - 0.28 * float(ghost)
				var tint := CLAW_COLOR if ghost == 0 else Color(CLAW_EDGE.r, CLAW_EDGE.g, CLAW_EDGE.b, 0.55 - 0.2 * float(ghost))
				_blade_batch.add(Transform3D(basis.scaled_local(Vector3(2.1 * k, 3.4 * k, 0.8) * size), at), tint)
	_blade_batch.finish()

	_fang_batch.begin()
	_wave_batch.begin()
	_dot_ring_batch.begin()
	# Klauenwirbel: glühender Wirbelschweif hinter jeder Klinge (liest sich als Kreisen).
	if level > 0 and not hide_all:
		var blades_n: int = CLAW_BLADES[level - 1]
		var orbit_r := _claw_orbit(level)
		for index in blades_n:
			for seg in 6:
				var a0 := _claw_angle + TAU * float(index) / float(blades_n) - 0.08 - float(seg) * 0.1
				var at := Vector3(origin.x + cos(a0) * orbit_r, 0.35, origin.z + sin(a0) * orbit_r)
				var tangent := Vector3(-sin(a0), 0.0, cos(a0))
				var fade := 1.0 - float(seg) / 6.0
				var streak := Basis.looking_at(tangent, Vector3.UP).scaled_local(Vector3(0.34 * fade + 0.06, 0.05, orbit_r * 0.1 * 1.1))
				_wave_batch.add(Transform3D(streak, at), Color(CLAW_EDGE.r, CLAW_EDGE.g, CLAW_EDGE.b, 0.6 * fade))
	_dart_batch.begin()
	_puff_batch.begin()
	_mark_batch.begin()
	_wall_batch.begin()
	if not hide_all:
		for entry in _snaps:
			if not entry.active:
				continue
			var t: float = clampf(entry.age / SNAP_SECONDS, 0.0, 1.0)
			# Zwei Fänge schlagen von oben zu und schließen sich über dem Ziel.
			var close := 1.0 - pow(1.0 - minf(1.0, t * 2.4), 3.0)
			var fade := 1.0 - smoothstep(0.6, 1.0, t)
			var dir: Vector3 = entry.dir
			var side := Vector3(-dir.z, 0.0, dir.x)
			for s in [-1.0, 1.0]:
				var open := lerpf(0.9, 0.18, close)
				var at: Vector3 = entry.at + side * s * open + Vector3(0, lerpf(1.6, 0.6, close), 0)
				var tilt := Basis.looking_at(-side * s + Vector3(0, -0.6, 0), Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5)
				var fang := CLAW_COLOR.lerp(VENOM_COLOR, 0.25)
				_fang_batch.add(Transform3D(tilt.scaled_local(Vector3(1.8, 3.8, 1.8) * maxf(0.05, fade)), at), Color(fang.r, fang.g, fang.b, fade))
			# Tropfen spritzen nach dem Zuschnappen.
			if t > 0.35:
				for d in 3:
					var ang := float(d) * 2.1 + float(entry.at.x)
					var u := (t - 0.35) / 0.65
					var drop: Vector3 = entry.at + Vector3(cos(ang), 0.0, sin(ang)) * u * 0.9 + Vector3(0, 0.6 + sin(u * PI) * 0.5, 0)
					_mark_batch.add(Transform3D(Basis.from_scale(Vector3.ONE * 0.9 * (1.0 - u)), drop), Color(VENOM_COLOR.r, VENOM_COLOR.g, VENOM_COLOR.b, 0.9))
		for entry in _roars:
			if not entry.active:
				continue
			_draw_roar(entry)
		for dart in _darts:
			if not dart.active:
				continue
			var u: float = clampf(dart.age / DART_SECONDS, 0.0, 1.0)
			var at: Vector3 = dart.from.lerp(dart.to, u) + Vector3(0, 0.5 + sin(u * PI) * 0.4, 0)
			var dir: Vector3 = dart.to - dart.from
			if dir.length() > 0.05:
				var tilt := Basis.looking_at(dir.normalized(), Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5)
				_dart_batch.add(Transform3D(tilt.scaled_local(Vector3(1.0, 1.2, 1.0)), at), SPINE_COLOR)
		for entry in _puffs:
			if not entry.active:
				continue
			var t: float = clampf(entry.age / PUFF_SECONDS, 0.0, 1.0)
			var grow := minf(1.0, t * 5.0)
			var fade := 1.0 - smoothstep(0.65, 1.0, t)
			for m in PUFF_MOTES:
				var ang := TAU * float(m) / float(PUFF_MOTES) + t * 1.4 + float(entry.at.x)
				var r: float = float(entry.radius) * (0.25 + 0.6 * grow) * (0.7 + 0.3 * float(m % 3) / 2.0)
				var lift := 0.4 + 0.5 * t + 0.2 * float(m % 2)
				var size := (2.4 + 0.8 * float(m % 3)) * (0.5 + 0.5 * grow)
				_puff_batch.add(Transform3D(Basis.from_scale(Vector3.ONE * size), entry.at + Vector3(cos(ang) * r, lift, sin(ang) * r)), Color(SPORE_COLOR.r, SPORE_COLOR.g, SPORE_COLOR.b, 0.4 * fade))
		var drawn := 0
		for key in _dots:
			if drawn >= MAX_MARKS:
				break
			var entry: Dictionary = _dots[key]
			var target = entry.target
			if not is_instance_valid(target):
				continue
			drawn += 1
			var poison: bool = String(entry.kind) == "poison"
			var base := _flat(target.global_position)
			var tint := VENOM_COLOR if poison else BURN_COLOR
			# Farbiger Bodenring unter dem Ziel (Gift grün, Brand orange), pulsiert leicht.
			var pulse := 1.0 + 0.08 * sin(_clock * 8.0 + float(target.get_instance_id() % 11))
			var ring_r := (1.05 if poison else 0.9) * pulse
			_dot_ring_batch.add(Transform3D(Basis.from_scale(Vector3(ring_r, 0.4, ring_r)), base + Vector3(0, 0.12 + (0.02 if poison else 0.0), 0)), Color(tint.r, tint.g, tint.b, 0.75))
			for b in 3:
				# Blasen (Gift) bzw. Glutfunken (Brand) steigen über dem Ziel auf.
				var phase := fmod(_clock * (1.3 if poison else 1.9) + float(b) * 0.33 + float(target.get_instance_id() % 7) * 0.13, 1.0)
				var at := base + Vector3(cos(float(b) * 2.1) * 0.35, 0.9 + phase * 1.3, sin(float(b) * 2.1) * 0.35)
				_mark_batch.add(Transform3D(Basis.from_scale(Vector3.ONE * (1.7 - 0.9 * phase)), at), Color(tint.r, tint.g, tint.b, 0.95 * (1.0 - phase * 0.8)))
		if rank("dornenwall") > 0:
			var radius := _swarm_radius() + 0.6
			for s in WALL_SPINES:
				var ang := TAU * float(s) / float(WALL_SPINES) + _clock * 0.4
				var outward := Vector3(cos(ang), 0.0, sin(ang))
				var pulse := 1.0 + 0.12 * sin(_clock * 6.0 + float(s))
				var tilt := Basis.looking_at(outward + Vector3(0, 0.9, 0), Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5)
				_wall_batch.add(Transform3D(tilt.scaled_local(Vector3(2.2, 2.3 * pulse, 2.2)), Vector3(origin.x, 0.3, origin.z) + outward * radius), Color(THORN_COLOR.r * 1.4, THORN_COLOR.g * 1.6, THORN_COLOR.b * 1.4) if s % 2 == 0 else SPINE_COLOR)
	_fang_batch.finish()
	_wave_batch.finish()
	_dot_ring_batch.finish()
	_dart_batch.finish()
	_puff_batch.finish()
	_mark_batch.finish()
	_wall_batch.finish()


# Drei Schallbögen laufen im Kegel nach außen und verblassen.
func _draw_roar(entry: Dictionary) -> void:
	var t: float = clampf(entry.age / ROAR_SECONDS, 0.0, 1.0)
	var dir: Vector3 = entry.dir
	var base_angle := atan2(dir.z, dir.x)
	var angle: float = entry.angle
	var thick := 0.42 if entry.heavy else 0.3
	for arc in ROAR_ARCS:
		var u := clampf(t * 1.25 - float(arc) * 0.14, 0.0, 1.0)
		if u <= 0.0:
			continue
		var distance: float = lerpf(0.9, float(entry.reach), 1.0 - pow(1.0 - u, 2.0))
		var fade := 1.0 - smoothstep(0.55, 1.0, u)
		var span := angle * 2.0 / float(ROAR_SEGMENTS)
		var length := distance * span * 1.08
		for s in ROAR_SEGMENTS:
			var a := base_angle - angle + span * (float(s) + 0.5)
			var at: Vector3 = entry.origin + Vector3(cos(a), 0.0, sin(a)) * distance + Vector3(0, 0.45, 0)
			var tangent := Vector3(-sin(a), 0.0, cos(a))
			var basis := Basis.looking_at(tangent, Vector3.UP).scaled_local(Vector3(thick * (1.0 + 0.6 * (1.0 - u)), 0.12, length))
			# Mitte heller: der Stoß liest sich als gebündelte Welle.
			var edge := absf(float(s) - float(ROAR_SEGMENTS - 1) * 0.5) / (float(ROAR_SEGMENTS) * 0.5)
			var tint := ROAR_CORE.lerp(ROAR_COLOR, edge)
			_wave_batch.add(Transform3D(basis, at), Color(tint.r, tint.g, tint.b, 0.9 * fade * (1.0 - 0.35 * edge)))


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
	return {"active": false, "age": 0.0, "points": PackedVector3Array(), "seed": 0.0, "storm": false, "tint": BOLT_COLOR}


func _make_sac() -> Dictionary:
	return {"active": false, "age": 0.0, "at": Vector3.ZERO, "level": 1}


func _make_biter() -> Dictionary:
	return {"active": false, "age": 0.0, "pos": Vector3.ZERO, "aim": Vector3.ZERO, "heading": Vector3.FORWARD,
		"target": null, "brood": false, "damage": 0.0, "life": BITER_LIFE}


func _make_snap() -> Dictionary:
	return {"active": false, "age": 0.0, "at": Vector3.ZERO, "dir": Vector3.FORWARD}


func _make_roar() -> Dictionary:
	return {"active": false, "age": 0.0, "origin": Vector3.ZERO, "dir": Vector3.FORWARD, "reach": 6.0, "angle": 0.6, "heavy": false}


func _make_dart() -> Dictionary:
	return {"active": false, "age": 0.0, "from": Vector3.ZERO, "to": Vector3.ZERO, "target": null, "damage": 0.0}


func _make_puff() -> Dictionary:
	return {"active": false, "age": 0.0, "at": Vector3.ZERO, "radius": PUFF_RADIUS, "dps": PUFF_DPS}


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
	# Etappe 17: Klingen und Fänge als gebogene Kegel, Schallwellen als Kästen.
	var blade_mesh := CylinderMesh.new()
	blade_mesh.top_radius = 0.0
	blade_mesh.bottom_radius = 0.16
	blade_mesh.height = 0.5
	blade_mesh.radial_segments = 6
	blade_mesh.rings = 2
	_blade_batch = _batch(self, blade_mesh, 4 * CLAW_TRAIL, "Claw blades")
	_fang_batch = _batch(self, blade_mesh, MAX_SNAPS * 2, "Venom fangs")
	_wave_batch = _batch(self, bolt_mesh, MAX_ROARS * ROAR_ARCS * ROAR_SEGMENTS + 4 * 6, "Roar waves")
	_dart_batch = _batch(self, _spike_mesh, MAX_DARTS, "Spine darts")
	_puff_batch = _batch(self, _mote_mesh, MAX_PUFFS * PUFF_MOTES, "Spore puffs")
	_mark_batch = _batch(self, _mote_mesh, MAX_MARKS * 3 + MAX_SNAPS * 3, "Dot marks")
	_dot_ring_batch = _batch(self, _thick_torus, MAX_MARKS, "Dot rings")
	_wall_batch = _lit_batch(_spike_mesh, WALL_SPINES, "Thorn wall")


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

# `tick` = Schaden über Zeit (Aura, Pfütze, Gift, Brand): löst keine Treffer-Relikte aus.
func _hurt(target, amount: float, source: String, tick: bool = false) -> void:
	if amount <= 0.0 or not is_instance_valid(target):
		return
	if target.has_method("take_damage"):
		target.call("take_damage", amount)
	elif "health" in target:
		target.set("health", float(target.get("health")) - amount)
	else:
		return
	damage_dealt[source] = float(damage_dealt.get(source, 0.0)) + amount
	if not tick:
		_on_hit(target, source)


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
		var distance := _target_distance(target, origin)
		if distance <= best_distance:
			best = target
			best_distance = distance
	return best


func _targets_near(center: Vector3, radius: float) -> Array:
	# _current wurde in diesem step() gefiltert; Schaden davor kann Ziele töten.
	var result: Array = []
	for target in _current:
		if _valid_target(target) and _target_distance(target, center) <= radius:
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


func _population() -> int:
	if swarm != null and is_instance_valid(swarm) and "population" in swarm:
		return int(swarm.get("population"))
	return 25


func _spine_reach() -> float:
	var population := _population()
	# Schwarmradius wie swarm.gd (_flow_radius) plus Stachelreichweite.
	return 2.65 + maxf(0.0, sqrt(float(population) / 25.0) - 1.0) * 0.55 + 1.2


# Etappe 17: Radius des Schwarms (klein beim Einzelstart, wie swarm.gd ab 25 Tieren).
func _swarm_radius() -> float:
	var share := sqrt(float(maxi(1, _population())) / 25.0)
	return lerpf(1.0, 2.65, clampf(share, 0.0, 1.0)) + maxf(0.0, share - 1.0) * 0.55


func _swarm_position() -> Vector3:
	if swarm != null and is_instance_valid(swarm) and swarm.is_inside_tree():
		return swarm.global_position
	return Vector3.ZERO


func _flat(location: Vector3) -> Vector3:
	return Vector3(location.x, 0.0, location.z)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# Abstand eines Ziels zu `point`: große Bosse (Moosschlund, Aschenkröte) melden
# über body_distance() den Abstand zum Körperrand, sonst zählt die Mitte.
func _target_distance(target: Node3D, point: Vector3) -> float:
	if target.has_method("body_distance"):
		return float(target.body_distance(point))
	return _flat_distance(target.global_position, point)


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
	return {"trail": trail, "node": node, "active": false, "age": 0.0, "target": null, "aim": Vector3.ZERO, "damage": 0.0, "brood": false, "pierce": 0, "hit": []}


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
	_spike_mesh = CylinderMesh.new()
	_spike_mesh.top_radius = 0.0
	_spike_mesh.bottom_radius = 0.11
	_spike_mesh.height = 0.75
	_spike_mesh.radial_segments = 6
	_spike_mesh.rings = 1
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
	_spine_batch = _batch(_spine_root, _spike_mesh, SPINE_COUNT, "Spines", true, false)
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
