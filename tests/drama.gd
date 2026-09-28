extends SceneTree
## Etappe 25 (Dramaturgie): speech queue (one at a time, gap, boss lines first,
## leader cooldown, stale lines drop, no repeats), the "Sprüche" switch, the
## bubble stays at the left edge and off the screen middle, boss entrance
## (vignette + zoom), victory hush, and nothing pauses or slows the game.
## Run with --audio-driver Dummy.

const DRAMA := preload("res://scripts/drama.gd")
const STEP := 0.1

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(60.0).timeout.connect(func() -> void: _fail("Drama test timed out"))
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var world: Node = scene.get_node("HuntWorld")
	var hud: Control = scene.get_node("HUD/Controls")
	var swarm: Node3D = scene.get_node("Swarm")
	world.set_process(false)
	scene.set_process(false)
	var main_drama: Node = scene.get_node_or_null("Drama")
	check(main_drama != null and main_drama.enabled, "Main creates the drama node (speech on by default)")
	if main_drama != null:
		main_drama.set_process(false)

	var drama: Node = DRAMA.new()
	drama.set_process(false)
	scene.add_child(drama)
	drama.setup(world, hud, scene, true)

	# --- Queue: one line at a time, SHOW_SECONDS, then GAP_SECONDS ---------
	check(drama.say("leader", "milestone"), "Leader line accepted")
	check(not drama.say("leader", "level"), "Leader cooldown blocks a second shout")
	check(drama.say("bog_king", "bog_king"), "Boss line accepted despite the leader cooldown")
	check(drama.queue.size() == 2 and bool(drama.queue[0].boss), "Boss line queued before the leader line")
	_advance(drama, STEP)
	check(String(drama.current.get("speaker", "")) == "bog_king", "Boss speaks first (got '%s')" % drama.current.get("speaker", ""))
	var shown: Dictionary = hud.get_meta("speech", {})
	check(String(shown.get("name", "")) == "BOG KING" and String(shown.get("icon", "")) == "portrait_bog_king", "HUD gets name and portrait of the boss")
	_advance(drama, DRAMA.SHOW_SECONDS - 0.2)
	check(not drama.current.is_empty(), "Line stays for its show time")
	_advance(drama, 0.4)
	check(drama.current.is_empty() and (hud.get_meta("speech", {}) as Dictionary).is_empty(), "Line disappears after SHOW_SECONDS")
	_advance(drama, DRAMA.GAP_SECONDS - 0.3)
	check(drama.current.is_empty(), "Gap before the next line")
	_advance(drama, 0.5)
	check(String(drama.current.get("speaker", "")) == "leader", "Leader line after the gap")
	check(String((hud.get_meta("speech", {}) as Dictionary).get("name", "")) == "ANFÜHRER", "Leader bubble is named")
	_advance(drama, DRAMA.SHOW_SECONDS + 0.2)

	# --- Queue limit and stale lines ------------------------------------------
	for kind in ["apex", "apex_toad", "apex_sandworm"]:
		drama.say(kind, kind)
	check(drama.queue.size() <= DRAMA.QUEUE_MAX, "Queue never holds more than %d lines (%d)" % [DRAMA.QUEUE_MAX, drama.queue.size()])
	drama.queue.clear()
	drama.current = {}
	drama.queue.clear()
	drama.gap = 99.0
	drama._leader_ready_at = -INF
	drama.say("leader", "level")
	_advance(drama, DRAMA.STALE_SECONDS + 1.0)
	drama.gap = 0.0
	var before: int = drama.said.size()
	_advance(drama, STEP)
	check(drama.said.size() == before, "A line older than STALE_SECONDS is dropped")

	# --- No repeats while alternatives remain -----------------------------------
	drama._used.clear()
	var texts := {}
	for i in (DRAMA.LINES["apex_toad"] as Array).size():
		texts[drama._pick("apex_toad")] = true
	check(texts.size() == (DRAMA.LINES["apex_toad"] as Array).size(), "Lines do not repeat before all were used")

	# --- Switch "Sprüche" ----------------------------------------------------
	drama.current = {}
	drama.queue.clear()
	drama.gap = 0.0
	drama.set_enabled(false)
	check(not drama.say("bog_king", "bog_king"), "Speech off: no line accepted")
	_advance(drama, 1.0)
	check(drama.current.is_empty() and (hud.get_meta("speech", {}) as Dictionary).is_empty(), "Speech off: nothing shown")
	drama.set_enabled(true)

	# --- World events: boss entrance, victory, leader events -------------------
	var music: Node = scene.get_node_or_null("Music")
	var hushes: int = music.hushes if music != null else 0
	drama._leader_ready_at = -INF
	drama.gap = 0.0
	var serial := int((hud.get_meta("drama_vignette", {}) as Dictionary).get("serial", 0))
	world._spawn_boss(swarm.position + Vector3(0, 0, -12))
	_advance(drama, STEP)
	check(int((hud.get_meta("drama_vignette", {}) as Dictionary).get("serial", 0)) > serial, "Boss entrance darkens the edge (vignette)")
	check(float(scene.get("drama_zoom_left")) > 0.0, "Boss entrance pulls the camera back")
	check(String(drama.current.get("speaker", "")) == "bog_king", "Bog King comments his entrance")
	check(Engine.time_scale == 1.0 and not bool(world.paused), "Entrance neither pauses nor slows the game")
	world.king_moments += 1
	_advance(drama, DRAMA.HUSH_DELAY + 0.2)
	if music != null:
		check(int(music.hushes) > hushes, "Victory: music hushes after the moment")
	check(drama.queue.size() > 0 or String(drama.current.get("speaker", "")) == "leader", "Victory: the leader shouts")
	check(Engine.time_scale == 1.0 and not bool(world.paused), "Victory neither pauses nor slows the game")
	drama.current = {}
	drama.queue.clear()
	drama.gap = 0.0
	drama._leader_ready_at = -INF
	world.model.leader_hp = 1
	world.model.leader_max_hp = 3
	_advance(drama, STEP * 2)
	check(String(drama.current.get("speaker", "")) == "leader" and (DRAMA.LINES["low_hp"] as Array).has(String(drama.current.get("text", ""))), "Low LP: the leader calls for cover")

	# --- Bubble position: left edge, below the banners, off the middle ------------
	await process_frame
	await process_frame
	var speech: Control = hud.get_node_or_null("hud_speech")
	check(speech != null, "HUD has the speech component")
	if speech != null:
		for text in ["Kurz!", "Ihr fresst meinen Wald? Ich fresse euch.", "Ein sehr langer Spruch, der sicher auf zwei oder drei Zeilen umbrechen muss, damit er passt"]:
			speech._line = {"speaker": "apex", "name": "MOOSSCHLUND", "icon": "portrait_apex", "text": text, "tone": "danger", "boss": true, "age": 1.0}
			var rect: Rect2 = speech.bubble_rect()
			check(rect.position.x <= 20.0, "Bubble starts at the left edge (%s)" % rect)
			check(rect.end.x <= speech.size.x * 0.62, "Bubble stays in the left part (%s)" % rect)
			check(not rect.intersects(speech.center_zone()), "Bubble never covers the screen middle (%s vs %s)" % [rect, speech.center_zone()])
			var overlays: Node = hud.get_node_or_null("hud_overlays")
			if overlays != null:
				# Banner title ribbon (cy + 46) plus its sub line (cy + 94 +- half a line).
				var banner_bottom: float = (speech.size.y - float(overlays.BASE_H)) * 0.5 + float(overlays.BANNER_Y) + 110.0
				check(rect.position.y >= banner_bottom, "Bubble below the moment banners (%.0f >= %.0f)" % [rect.position.y, banner_bottom])

	drama.queue_free()
	scene.queue_free()
	await process_frame
	if failures > 0:
		print("DRAMA FAILED: %d" % failures)
		quit(1)
		return
	print("PASS drama: queue (one at a time, gap, boss first, cooldown, limit, stale drop, no repeats), switch, boss entrance (vignette, zoom), victory hush + shout, low LP, no pause, bubble left and off the middle")
	quit(0)


func _advance(node: Node, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		node.tick(STEP)
		t += STEP


func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
