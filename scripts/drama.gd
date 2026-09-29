extends Node
## Etappe 25 (Dramaturgie, S10/S12 aus stages/REFERENCE_SWARM.md).
##
## Beobachtet HuntWorld pro Frame nur über öffentliche Felder (wie das
## Onboarding) und erzeugt daraus
##   * Sprüche: kurze Sprechblasen mit Porträt am linken Bildrand
##     (scripts/ui/hud_speech.gd zeichnet sie). Sprecher sind der eigene
##     Anführer (Stammeskopf) und die Bosse vor ihrem Auftritt.
##   * Boss-Auftritt: Rand-Vignette (0,6 s) und ein kurzer Kamera-Zoom heraus
##     (Main.drama_zoom).
##   * Boss-Sieg: nach dem vorhandenen Sieg-Band (Flash) 1,6 s Ruhe, die Musik
##     wird leiser (Music.hush); dann ein Ruf des Anführers.
## Nichts davon pausiert das Spiel.
##
## Regeln der Sprüche: höchstens einer sichtbar, SHOW_SECONDS lang, danach
## mindestens GAP_SECONDS Pause; die Warteschlange hält höchstens QUEUE_MAX
## Zeilen (Boss-Zeilen verdrängen Anführer-Zeilen). Der Anführer ruft höchstens
## alle LEADER_COOLDOWN Sekunden; jeder Anlass hat eigene Texte, eine Zeile
## wiederholt sich im Run nicht, solange es Alternativen gibt. Abschaltbar über
## `enabled` (Einstellung „Sprüche“); Boss-Vignette, Zoom und Ruhe bleiben.

const SHOW_SECONDS := 2.6
const GAP_SECONDS := 3.0
const QUEUE_MAX := 2
const LEADER_COOLDOWN := 22.0
## Zeilen, die nicht rechtzeitig drankommen, verfallen (sonst passen sie nicht mehr).
const STALE_SECONDS := 6.0
const VIGNETTE_SECONDS := 0.6
const ZOOM_SECONDS := 1.6
const HUSH_DELAY := 0.8
const HUSH_SECONDS := 1.6

## Anlass -> Texte (Ton: „Fressen, wachsen, überleben“).
const LINES := {
	"milestone": ["Mehr Mäuler, mehr Futter!", "Wir werden immer mehr!", "Der Hunger wächst mit!"],
	"level": ["Ich spür's in den Zähnen!", "Stärker. Hungriger.", "Das schmeckt nach mehr!"],
	"evolution": ["Wir verwandeln uns!", "Neue Zähne, neues Glück!"],
	"low_hp": ["Autsch! Noch ein Biss, dann bin ich Futter!", "Nur noch ein Leben – deckt mich!"],
	"swap": ["Der Alte ist hin. Ich führe jetzt!", "Ich übernehme. Weiterfressen!"],
	"flood": ["Die Flut! Zusammenbleiben!", "Da kommt Nachschub – zum Fressen!"],
	"victory": ["Mahlzeit!", "Der war zäh. Nächster!", "Satt? Noch lange nicht!"],
	"bog_king": ["Wer knabbert da in meinem Sumpf?", "Ich zertrete euch wie Kaulquappen!", "Frischfleisch? Nur her damit!"],
	"apex": ["Ihr fresst meinen Wald? Ich fresse euch.", "Das Moos vergisst keinen Biss.", "Kommt näher, kleine Mäuler …"],
	"apex_sandworm": ["Unter euch. Immer unter euch.", "Der Sand hat Hunger – ich auch.", "Hört ihr das Graben? Das bin ich."],
	"apex_toad": ["Quaak! Ihr riecht nach Asche!", "Ein Sprung, und ihr seid Glut.", "Mein Sumpf, meine Beute!"],
}
## Boss-Sprecher: Name (fürs Band) und Porträt-Icon (scripts/ui/ui_icons.gd).
const BOSSES := {
	"bog_king": ["BOG KING", "portrait_bog_king"],
	"apex": ["MOOSSCHLUND", "portrait_apex"],
	"apex_sandworm": ["SANDWURM", "portrait_apex_sandworm"],
	"apex_toad": ["ASCHENKRÖTE", "portrait_apex_toad"],
}

var world: Node = null
var hud: Object = null
var main: Node = null
var enabled := true

## Sichtbare Zeile ({} = keine): {speaker, name, icon, text, tone, boss, age}.
var current: Dictionary = {}
var queue: Array[Dictionary] = []
var gap := 0.0
## Alle gezeigten Zeilen dieses Knotens (Tests): [speaker, text].
var said: Array = []

var _model: Object = null
var _used := {}
var _leader_ready_at := -INF
var _clock := 0.0
var _rng := RandomNumberGenerator.new()
# Beobachtete Werte vom letzten Frame.
var _seen := {}
var _hush_at := -1.0
var _vignette_serial := 0


func setup(world_node: Node, hud_node: Object, main_node: Node = null, speech_enabled: bool = true) -> void:
	world = world_node
	hud = hud_node
	main = main_node
	enabled = speech_enabled
	_rng.seed = 2510
	_reset_run()


func _process(delta: float) -> void:
	tick(delta)


## Ein Beobachtungsschritt (Tests rufen ihn mit fester Schrittweite auf).
func tick(delta: float) -> void:
	if world == null or not is_instance_valid(world):
		return
	if world.get("model") != _model:
		_reset_run()
	if bool(world.get("paused")) or bool(_model.get("extinct")):
		if bool(_model.get("extinct")) and not current.is_empty():
			_hide()
		return
	var choosing: bool = world.has_method("choosing") and world.choosing()
	_clock += delta
	_observe()
	if _hush_at >= 0.0 and _clock >= _hush_at:
		_hush_at = -1.0
		var music := _music()
		if music != null and music.has_method("hush"):
			music.hush(HUSH_SECONDS)
	if choosing:
		return
	if not current.is_empty():
		current.age = float(current.age) + delta
		if float(current.age) >= SHOW_SECONDS:
			_hide()
		else:
			_publish()
		return
	gap -= delta
	if gap > 0.0:
		return
	while not queue.is_empty():
		var line: Dictionary = queue.pop_front()
		if _clock - float(line.at) <= STALE_SECONDS:
			_show(line)
			break


## Öffentlich (Tests, Captures): legt eine Zeile in die Warteschlange.
## speaker "leader" oder ein BOSSES-Schlüssel; text "" = zufällige LINES[event].
func say(speaker: String, event: String, text: String = "") -> bool:
	if not enabled:
		return false
	var boss := BOSSES.has(speaker)
	if not boss:
		if _clock < _leader_ready_at:
			return false
		_leader_ready_at = _clock + LEADER_COOLDOWN
	var line := text if text != "" else _pick(event)
	if line == "":
		return false
	var entry := {"speaker": speaker, "text": line, "boss": boss, "at": _clock}
	if boss:
		# Boss-Zeilen stehen vor den Anführer-Zeilen.
		var index := 0
		while index < queue.size() and bool(queue[index].boss):
			index += 1
		queue.insert(index, entry)
	else:
		queue.append(entry)
	while queue.size() > QUEUE_MAX:
		# Zuerst die jüngste Anführer-Zeile opfern, sonst die jüngste überhaupt.
		var drop := queue.size() - 1
		for i in range(queue.size() - 1, -1, -1):
			if not bool(queue[i].boss):
				drop = i
				break
		queue.remove_at(drop)
	return true


## Boss-Auftritt: Rand-Vignette und kurzer Zoom heraus (öffentlich für Captures).
func boss_entrance() -> void:
	_vignette_serial += 1
	if hud != null and is_instance_valid(hud):
		hud.set_meta("drama_vignette", {"serial": _vignette_serial, "seconds": VIGNETTE_SECONDS})
	if main != null and is_instance_valid(main) and main.has_method("drama_zoom"):
		main.drama_zoom(ZOOM_SECONDS)


## Boss besiegt: das Sieg-Band blitzt schon (hud_overlays); hier die Ruhe danach.
func boss_victory() -> void:
	_hush_at = _clock + HUSH_DELAY
	_leader_ready_at = minf(_leader_ready_at, _clock)
	say("leader", "victory")


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		queue.clear()
		if not current.is_empty():
			_hide()


# ---------------------------------------------------------------- internals

func _reset_run() -> void:
	_model = world.get("model") if world != null else null
	current = {}
	queue.clear()
	gap = 0.0
	_used.clear()
	_leader_ready_at = -INF
	_hush_at = -1.0
	_seen = _snapshot()
	_publish()


func _snapshot() -> Dictionary:
	if world == null or _model == null:
		return {}
	var evo: Variant = world.get("evolution")
	return {
		"milestone": int(world.get("milestone_value")),
		"level": int(evo.get("level")) if evo != null else 0,
		"evolutions": (evo.get("evolutions") as Array).size() if evo != null else 0,
		"leader_hp": int(_model.get("leader_hp")),
		"swaps": int(_model.get("leader_swaps")),
		"flood": int(world.get("flood_state")),
		"boss": _id(world.get("boss")),
		"apex_state": int(world.get("apex_state")),
		"apex": _id(world.get("apex")),
		"kings": int(world.get("king_moments")),
		"victories": int(world.get("apex_victories")),
	}


func _observe() -> void:
	var now := _snapshot()
	var before := _seen
	_seen = now
	if before.is_empty():
		return
	var apex_kind := String(world.get("apex_kind"))
	var apex_key := apex_kind if BOSSES.has(apex_kind) else "apex"
	# Bosse vor ihrem Auftritt.
	# (Instance ids, so a boss that replaces another in one frame still counts.)
	if int(now.boss) != 0 and int(now.boss) != int(before.boss):
		say("bog_king", "bog_king")
		boss_entrance()
	if int(now.apex_state) == 1 and int(before.apex_state) != 1:
		say(apex_key, apex_key)
	if int(now.apex) != 0 and int(now.apex) != int(before.apex):
		if int(before.apex_state) != 1:
			say(apex_key, apex_key)
		boss_entrance()
	# Siege.
	if int(now.kings) > int(before.kings) or int(now.victories) > int(before.victories):
		boss_victory()
	# Anführer.
	if int(now.swaps) > int(before.swaps):
		say("leader", "swap")
	elif int(now.leader_hp) == 1 and int(before.leader_hp) > 1:
		say("leader", "low_hp")
	if int(now.evolutions) > 0 and int(before.evolutions) == 0:
		say("leader", "evolution")
	elif int(now.level) > int(before.level):
		say("leader", "level")
	if int(now.milestone) > int(before.milestone):
		say("leader", "milestone")
	if int(now.flood) == 2 and int(before.flood) != 2:
		say("leader", "flood")


func _id(node: Variant) -> int:
	return (node as Object).get_instance_id() if node is Object and is_instance_valid(node) else 0


func _pick(event: String) -> String:
	var options: Array = LINES.get(event, [])
	if options.is_empty():
		return ""
	var fresh: Array = []
	for line in options:
		if not _used.has(line):
			fresh.append(line)
	if fresh.is_empty():
		fresh = options.duplicate()
	var line: String = fresh[_rng.randi() % fresh.size()]
	_used[line] = true
	return line


func _show(line: Dictionary) -> void:
	var speaker := String(line.speaker)
	var boss := BOSSES.has(speaker)
	current = {
		"speaker": speaker,
		"name": String(BOSSES[speaker][0]) if boss else "ANFÜHRER",
		"icon": String(BOSSES[speaker][1]) if boss else "",
		"text": String(line.text),
		"tone": "danger" if boss else "ember",
		"boss": boss,
		"age": 0.0,
	}
	said.append([speaker, String(line.text)])
	_publish()


func _hide() -> void:
	current = {}
	gap = GAP_SECONDS
	_publish()


func _publish() -> void:
	if hud == null or not is_instance_valid(hud):
		return
	hud.set_meta("speech", current.duplicate())


func _music() -> Node:
	var parent := world.get_parent() if world != null else null
	return parent.get_node_or_null("Music") if parent != null else null
