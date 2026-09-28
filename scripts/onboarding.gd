extends Node
## Einstieg (Etappe 06): kontextuelle Tipps beim ersten Auftreten eines Themas.
##
## Beobachtet HuntWorld, Swarm und HUD pro Frame, ohne sie zu verändern; das
## Einzige, was geschrieben wird, sind `tutorial_tip` / `tutorial_icon` am HUD
## (als Variable, falls vorhanden, sonst als Metadaten) und `seen_tips` im Profil.
## Regeln: höchstens ein Tipp gleichzeitig, mindestens GAP_SECONDS zwischen zwei
## Tipps, jeder Tipp einmal pro Profil (beim Zeigen sofort gespeichert). Ein Tipp
## verschwindet, sobald er erfüllt ist (frühestens nach MIN_SHOW_SECONDS), sonst
## nach SHOW_SECONDS. Ohne Profil bleibt der Knoten inaktiv.

const PROFILE_PATH := "res://scripts/meta/profile.gd"
const FIRST_DELAY := 1.2
const GAP_SECONDS := 4.0
const SHOW_SECONDS := 6.0
const MIN_SHOW_SECONDS := 1.6

## id -> Text; die Reihenfolge von ORDER ist die Priorität, wenn mehrere Themen gleichzeitig anstehen.
const TIPS := {
	"move": "Ziehe rechts, um den Schwarm zu führen",
	"warning": "Raus aus der markierten Fläche – nur Tiere darin sterben",
	"leader": "Dein Anführer hat nur wenige Leben – fällt er, führt das nächste Tier",
	"boss": "Der Bog King! Weiche dem Stampfen aus und beiß zu, wenn er erschöpft ist",
	"rally": "Halte links RALLY: dichter Schwarm, stärkerer Biss",
	"prey": "Umzingle die Beute – der Schwarm beißt automatisch",
	"corpse": "Sammle die Kristalle ein: Biomasse wird zu neuen Mawlings",
	"alpha": "Alpha-Kern! Einsammeln – er lässt deinen Schwarm aufsteigen",
	"mutation": "Mutation aktiv – mehr DNA aus Beute bringt die nächste Wahl",
	"nest": "Brutnest! Bleib im Kreis, bis der Balken voll ist",
	"map": "Tippe auf die Karte für die Übersicht",
	"ability": "Stammesfähigkeit bereit! Tippe den Knopf über Rally (Q / Shift)",
	# Etappe 24: the systems of stages 17-20.
	"leader_low": "Anführer auf 1 LP! Lebensraub heilt beim Beißen – weich Treffern aus",
	"boss_cocoon": "Boss-Kokon! Gratis öffnen – du wählst 1 aus 3 Beuten",
	"cocoon": "Kokon! Bleib im Kreis, bis er aufgeht – der Preis in Bernstein steht darüber",
	"amber": "Bernstein! Mit den Münzen kaufst du Kokons",
	"powerup": "Power-up! Lauf hinein – es wirkt ein paar Sekunden",
	"shrine": "Schrein! Bleib darin, bis er voll ist – er schenkt einen seltenen Wert",
	"xp": "Der Balken oben füllt sich mit DNA – voll heißt neue Mutation",
	"explore": "Erkunde! Der Nebel verbirgt Kokons, Schreine und Bosse",
	"quicksand": "Treibsand bremst – raus auf festen Sand",
	"sandstorm": "Sandsturm zieht auf – Gegner werden schneller, bleib in Bewegung",
}
const ORDER := ["move", "warning", "leader", "leader_low", "boss", "rally", "ability", "sandstorm", "quicksand",
	"prey", "corpse", "amber", "boss_cocoon", "cocoon", "powerup", "shrine", "alpha", "xp", "mutation", "nest",
	"explore", "map"]
## Etappe 17d: the ability tip comes once the run is under way and a threat is near.
const ABILITY_SECONDS := 20.0

const PREY_RANGE := 7.0
const CORPSE_RANGE := 8.0
const THREAT_RANGE := 8.0
const ALPHA_RANGE := 14.0
const NEST_RANGE := 16.0
## Kartentipp (Minimap-Etappe): erst nach etwas Erkundung - eine zweite Region
## oder MAP_DISTANCE vom Start, frühestens nach MAP_SECONDS Laufzeit.
const MAP_SECONDS := 40.0
const MAP_DISTANCE := 30.0
## Etappe 24: ranges for the new systems ("in sight" on the phone camera).
const COCOON_RANGE := 16.0
const POWERUP_RANGE := 12.0
const SHRINE_RANGE := 16.0
const LANDMARK_RANGE := 20.0
## Explore tip: after the start phase, with the first landmark in sight.
const EXPLORE_SECONDS := 25.0

var world: Node = null
var hud: Object = null
var swarm: Node3D = null
var profile: Object = null
var active := false

## Aktuell sichtbarer Tipp ("" = keiner) und alle in diesem Knoten gezeigten IDs.
var current := ""
var shown: Array[String] = []
var shown_time := 0.0
var gap := FIRST_DELAY

var _model: Object = null
var _run_start := Vector3.ZERO
var _anchor := Vector3.ZERO
var _kills_at := 0
var _biomass_at := 0.0
var _was_choosing := false
var _mutation_ready := false
var _collected_at := 0
var _regions_at := 0
var _cocoon: Dictionary = {}


## `profile_ref` ist ein Profil-Objekt oder ein Profilpfad; null/"" = inaktiv.
func setup(world_node: Node, hud_node: Object, swarm_node: Node3D, profile_ref: Variant) -> void:
	world = world_node
	hud = hud_node
	swarm = swarm_node
	profile = null
	if profile_ref is Object:
		profile = profile_ref
	elif profile_ref is String and String(profile_ref) != "" and ResourceLoader.exists(PROFILE_PATH):
		profile = load(PROFILE_PATH).load_or_create(String(profile_ref))
	active = world != null and hud != null and swarm != null and profile != null and profile.has_method("mark_tip")
	_reset_run_state()
	_publish("", "")


func _process(delta: float) -> void:
	tick(delta)


## Ein Beobachtungsschritt; Tests rufen ihn mit fester Schrittweite direkt auf.
func tick(delta: float) -> void:
	if not active or not is_instance_valid(world):
		return
	if world.get("model") != _model:
		# NEUER RUN: frische Ausgangslage, gesehene Tipps bleiben gesehen.
		_reset_run_state()
		_publish("", "")
	if bool(world.get("paused")) or bool(_model.get("extinct")):
		return
	if world.has_method("choosing") and world.choosing():
		_was_choosing = true
		return
	if _was_choosing:
		_was_choosing = false
		_mutation_ready = true
	if current != "":
		shown_time += delta
		if shown_time >= SHOW_SECONDS or (shown_time >= MIN_SHOW_SECONDS and _fulfilled(current)):
			_hide()
		return
	gap -= delta
	if gap > 0.0:
		return
	for id: String in ORDER:
		if not profile.has_seen_tip(id) and _wanted(id):
			_show(id)
			break


func _reset_run_state() -> void:
	_model = world.get("model") if world != null else null
	_run_start = swarm.position if swarm != null else Vector3.ZERO
	current = ""
	shown_time = 0.0
	gap = FIRST_DELAY
	_was_choosing = false
	_mutation_ready = false


func _show(id: String) -> void:
	current = id
	shown_time = 0.0
	shown.append(id)
	_anchor = swarm.position
	_kills_at = int(_model.get("kills"))
	_biomass_at = float(_model.get("consumed_biomass"))
	var powerups: Variant = world.get("powerups")
	_collected_at = int(powerups.collected) if _valid(powerups) else 0
	var regions: Variant = world.get("regions_seen")
	_regions_at = (regions as Dictionary).size() if regions is Dictionary else 0
	_cocoon = {}
	if id == "cocoon" or id == "boss_cocoon":
		_cocoon = _near_cocoon(["boss"] if id == "boss_cocoon" else ["map", "gold", "elite", "start"])
	if id == "mutation":
		_mutation_ready = false
	profile.mark_tip(id)
	_publish(TIPS[id], id)


func _hide() -> void:
	current = ""
	gap = GAP_SECONDS
	_publish("", "")


func _publish(text: String, icon: String) -> void:
	if hud == null or not is_instance_valid(hud):
		return
	for pair in [["tutorial_tip", text], ["tutorial_icon", icon]]:
		if pair[0] in hud:
			hud.set(pair[0], pair[1])
		else:
			hud.set_meta(pair[0], pair[1])


# ---------------------------------------------------------------- conditions

func _wanted(id: String) -> bool:
	match id:
		"move":
			return swarm.position.distance_to(_run_start) < 1.5
		"warning":
			return _warning_active()
		"leader":
			# Etappe 09: after the first hit on the leader.
			var hits: Variant = _model.get("leader_hits")
			return hits != null and int(hits) > 0
		"boss":
			return _alive(world.get("boss"))
		"rally":
			return not bool(swarm.get("rally_pressed")) and _threat_near()
		"ability":
			var ability: Variant = world.get("abilities")
			return ability != null and is_instance_valid(ability) and ability.is_ready() and int(ability.uses) == 0 and float(_model.get("elapsed")) >= ABILITY_SECONDS and _threat_near()
		"prey":
			return _nearest(world.get("prey"), PREY_RANGE)
		"corpse":
			# Etappe 16: loot crystals lying close by (id "corpse" kept for saved profiles).
			var loot: Variant = world.get("loot")
			if loot == null or not is_instance_valid(loot):
				return false
			return (loot.lying_near(swarm.position, CORPSE_RANGE) as Array).size() > 0
		"alpha":
			return _nearest(world.get("alpha_pickups"), ALPHA_RANGE)
		"mutation":
			return _mutation_ready
		"nest":
			var nest := _nest()
			return nest != null and not bool(nest.get("complete")) and nest.global_position.distance_to(swarm.global_position) <= NEST_RANGE
		"leader_low":
			return int(_model.get("leader_hp")) == 1 and int(_model.get("leader_max_hp")) > 1
		"boss_cocoon":
			return not _near_cocoon(["boss"]).is_empty()
		"cocoon":
			return not _near_cocoon(["map", "gold", "elite", "start"]).is_empty()
		"amber":
			var amber: Variant = _model.get("amber_collected")
			return amber != null and int(amber) > 0
		"powerup":
			var powerups: Variant = world.get("powerups")
			if not _valid(powerups):
				return false
			for entry: Dictionary in powerups.pickups:
				if _flat((entry.at as Vector3)) <= POWERUP_RANGE:
					return true
			return false
		"shrine":
			return not _near_shrine().is_empty()
		"xp":
			var evo: Variant = world.get("evolution")
			return evo != null and int(evo.get("level")) == 0 and int(evo.get("dna")) > 0
		"explore":
			return float(_model.get("elapsed")) >= EXPLORE_SECONDS and _landmark_near()
		"quicksand":
			var arena: Variant = _arena()
			return _valid(arena) and arena.has_method("quicksand_factor") and float(arena.quicksand_factor(swarm.position)) < 0.95
		"sandstorm":
			var storm := _storm()
			return storm != null and int(storm.get("state")) in [1, 2]
		"map":
			if not bool(hud.get("minimap_enabled")) or bool(hud.get("map_open")):
				return false
			if float(_model.get("elapsed")) < MAP_SECONDS:
				return false
			var regions: Variant = world.get("regions_seen")
			return (regions is Dictionary and (regions as Dictionary).size() >= 2) or swarm.position.distance_to(_run_start) >= MAP_DISTANCE
	return false


func _fulfilled(id: String) -> bool:
	match id:
		"move":
			return swarm.position.distance_to(_anchor) > 2.5
		"warning":
			return not _warning_active()
		"boss":
			return not _alive(world.get("boss"))
		"rally":
			return bool(swarm.get("rally_pressed"))
		"ability":
			var used: Variant = world.get("abilities")
			return used == null or not is_instance_valid(used) or int(used.uses) > 0
		"prey":
			return int(_model.get("kills")) > _kills_at
		"corpse":
			return float(_model.get("consumed_biomass")) > _biomass_at + 0.5
		"alpha":
			var pickups: Variant = world.get("alpha_pickups")
			return pickups is Array and (pickups as Array).is_empty()
		"nest":
			var nest := _nest()
			return nest == null or float(nest.get("inside_share") if "inside_share" in nest else 0.0) > 0.2
		"map":
			return bool(hud.get("map_open"))
		"leader_low":
			return int(_model.get("leader_hp")) > 1
		"cocoon", "boss_cocoon":
			return _cocoon.is_empty() or int(_cocoon.get("state", 0)) != 0 or _flat(_cocoon.at as Vector3) > COCOON_RANGE * 1.5
		"powerup":
			var powerups: Variant = world.get("powerups")
			return not _valid(powerups) or int(powerups.collected) > _collected_at
		"shrine":
			var shrine := _near_shrine()
			return shrine.is_empty() or float(shrine.get("charge", 0.0)) > 0.3
		"xp":
			var evo: Variant = world.get("evolution")
			return evo == null or int(evo.get("level")) > 0
		"explore":
			var regions: Variant = world.get("regions_seen")
			return regions is Dictionary and (regions as Dictionary).size() > _regions_at
		"quicksand":
			return not _wanted("quicksand")
		"sandstorm":
			var storm := _storm()
			return storm == null or int(storm.get("state")) == 0
	return false


func _warning_active() -> bool:
	var hint := String(hud.get("hint")) if "hint" in hud else ""
	var upper := hint.to_upper()
	return upper.begins_with("RAUS") or upper.begins_with("SPRINT") or upper.contains("RAUS AUS")


func _threat_near() -> bool:
	for key in ["hunters", "skitters", "leapers"]:
		if _nearest(world.get(key), THREAT_RANGE):
			return true
	var boss: Variant = world.get("boss")
	return _alive(boss) and (boss as Node3D).position.distance_to(swarm.position) <= THREAT_RANGE + 3.0


func _nearest(list: Variant, reach: float) -> bool:
	if not (list is Array):
		return false
	for node in list:
		if _alive(node) and (node as Node3D).position.distance_to(swarm.position) <= reach:
			return true
	return false


func _alive(node: Variant) -> bool:
	return node is Node3D and is_instance_valid(node)


# The map node sits next to HuntWorld under Main ("Arena"), like HuntWorld finds it.
func _arena() -> Node:
	var parent := world.get_parent() if world != null else null
	return parent.get_node_or_null("Arena") if parent != null else null


func _valid(node: Variant) -> bool:
	return node is Object and is_instance_valid(node)


func _flat(point: Vector3) -> float:
	return Vector2(point.x - swarm.position.x, point.z - swarm.position.z).length()


# Nearest closed cocoon of the given kinds in sight ({} = none).
func _near_cocoon(kinds: Array) -> Dictionary:
	var chests: Variant = world.get("chests")
	if not _valid(chests) or not chests.has_method("nearest"):
		return {}
	return chests.nearest(swarm.position, COCOON_RANGE, kinds)


# Nearest unfinished shrine in sight ({} = none).
func _near_shrine() -> Dictionary:
	var shrines: Variant = world.get("shrines")
	if not _valid(shrines):
		return {}
	var best: Dictionary = {}
	var best_d := SHRINE_RANGE
	for entry: Dictionary in shrines.shrines:
		if bool(entry.get("done", false)):
			continue
		var d := _flat(entry.at as Vector3)
		if d <= best_d:
			best_d = d
			best = entry
	return best


# A landmark (root arch, fallen log, ...) standing in one of the 3 x 3 chunks
# around the swarm and within LANDMARK_RANGE.
func _landmark_near() -> bool:
	var arena: Variant = _arena()
	if not _valid(arena) or not arena.has_method("landmark") or not arena.has_method("chunk_at"):
		return false
	var key: Vector2i = arena.chunk_at(swarm.position)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var mark: Dictionary = arena.landmark(key + Vector2i(dx, dz))
			if not mark.is_empty() and mark.has("center") and _flat(mark.center as Vector3) <= LANDMARK_RANGE:
				return true
	return false


# Sandstorm of the Dürrschlund (desert_run.storm), null outside the desert.
func _storm() -> Node:
	var desert: Variant = world.get("desert")
	if not _valid(desert) or not desert.has_method("active") or not desert.active():
		return null
	var storm: Variant = desert.get("storm")
	return storm if _valid(storm) else null


# Brutnest (Etappe 06, ZIELE) ist optional: erkannt wird eine Welt-Variable
# `nest`/`active_nest` oder ein Objectives-Knoten mit einer solchen Variable.
func _nest() -> Node3D:
	for owner_ref: Variant in [world, world.get("objectives"), world.get_node_or_null("Objectives")]:
		if not (owner_ref is Object) or not is_instance_valid(owner_ref):
			continue
		for key in ["nest", "active_nest"]:
			if key in owner_ref:
				var value: Variant = owner_ref.get(key)
				if value is Node3D and is_instance_valid(value) and value.is_inside_tree():
					return value
	return null
