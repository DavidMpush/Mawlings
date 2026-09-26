extends SceneTree
## Einstieg (Etappe 06): Tipps erscheinen einmal pro Profil, nie zwei zugleich,
## mit Mindestabstand; Speicherung in seen_tips; inaktiv ohne Profil; Main legt
## das Onboarding nur für Menü-Configs an; Erststart-Weiche im Menü.

const TEST_PROFILE := "user://test_onboarding_profile.json"
const MENU_PROFILE := "user://test_onboarding_menu_profile.json"
const PROFILE := preload("res://scripts/meta/profile.gd")
const ONBOARDING := preload("res://scripts/onboarding.gd")
const SESSION := preload("res://scripts/meta/session.gd")
const STEP := 0.1

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(60.0).timeout.connect(func() -> void: _fail("Onboarding test timed out"))
	_delete(TEST_PROFILE)
	_delete(MENU_PROFILE)
	SESSION.pending_config = {}
	SESSION.last_result = {}

	# --- Profil: seen_tips, Erststart --------------------------------------
	var profile: RefCounted = PROFILE.load_or_create(TEST_PROFILE)
	check(profile.is_first_start(), "Fresh profile is a first start")
	check(profile.seen_tips.is_empty(), "Fresh profile has no seen tips")

	# --- Main ohne Menü-Config: kein Onboarding ------------------------------
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	check(not scene.has_node("Onboarding"), "No onboarding without a menu config (tests, F5)")
	var world: Node = scene.get_node("HuntWorld")
	var hud: Control = scene.get_node("HUD/Controls")
	var swarm: Node3D = scene.get_node("Swarm")
	# Freeze the simulation: the test drives world state and time itself.
	world.set_process(false)
	scene.set_process(false)
	for enemy in world.hunters + world.skitters + world.leapers:
		enemy.position = Vector3(90, 0, 90)

	# --- Inaktiv ohne Profil ----------------------------------------------
	var idle: Node = ONBOARDING.new()
	idle.set_process(false)
	scene.add_child(idle)
	idle.setup(world, hud, swarm, null)
	_advance(idle, 8.0)
	check(not idle.active and idle.shown.is_empty(), "Onboarding stays inactive without a profile")
	idle.queue_free()

	# --- Aktiv mit Testprofil ------------------------------------------------
	var tips: Node = ONBOARDING.new()
	tips.set_process(false)
	scene.add_child(tips)
	tips.setup(world, hud, swarm, profile)
	check(tips.active, "Onboarding active with a profile")
	_advance(tips, 0.5)
	check(tips.current == "", "No tip before the first delay")
	_advance(tips, 1.0)
	check(tips.current == "move", "Movement tip first (got '%s')" % tips.current)
	check(_tip(hud).begins_with("Ziehe rechts"), "HUD carries the movement tip text")
	check(_icon(hud) == "move", "HUD carries the movement tip icon")
	var saved: RefCounted = PROFILE.load_or_create(TEST_PROFILE)
	check(saved.has_seen_tip("move"), "Shown tip is saved immediately")
	check(not saved.is_first_start(), "Profile with a seen tip is no longer a first start")
	# Fulfilment: moving hides it (after the minimum show time).
	swarm.position += Vector3(3.2, 0, 0)
	_advance(tips, 0.5)
	check(tips.current == "move", "Tip stays for its minimum time")
	_advance(tips, 1.4)
	check(tips.current == "" and _tip(hud) == "", "Fulfilled movement tip disappears")
	# Gap: nothing for GAP_SECONDS even though prey is close.
	_place_prey(world, swarm, 3.0)
	_advance(tips, 3.0)
	check(tips.current == "", "No new tip inside the minimum gap")
	_advance(tips, 1.2)
	check(tips.current == "prey", "Prey tip after the gap (got '%s')" % tips.current)
	check(_tip(hud).contains("Beute"), "Prey tip text")
	# Unfulfilled tips time out on their own.
	_advance(tips, ONBOARDING.SHOW_SECONDS + 0.2)
	check(tips.current == "", "Unfulfilled tip times out")
	# Warning zone: urgent tip, disappears once the warning is over.
	hud.hint = "RAUS AUS DEM ROTEN RING!"
	_advance(tips, ONBOARDING.GAP_SECONDS + 0.2)
	check(tips.current == "warning", "Warning tip on the first warning zone (got '%s')" % tips.current)
	hud.hint = "Jage die türkisfarbene Beute"
	_advance(tips, ONBOARDING.MIN_SHOW_SECONDS + 0.2)
	check(tips.current == "", "Warning tip disappears after the warning")
	# Rally: a hunter close by, fulfilled by holding Rally.
	var hunter: Node3D = world._spawn_hunter(swarm.position + Vector3(4.0, 0, 0))
	_advance(tips, ONBOARDING.GAP_SECONDS + 0.2)
	check(tips.current == "rally", "Rally tip with a threat nearby (got '%s')" % tips.current)
	check(_icon(hud) == "rally", "Rally tip icon")
	swarm.rally_pressed = true
	_advance(tips, ONBOARDING.MIN_SHOW_SECONDS + 0.2)
	check(tips.current == "", "Rally tip fulfilled by holding Rally")
	swarm.rally_pressed = false
	hunter.position = Vector3(90, 0, 90)
	# Never two tips at once: every frame shows at most one entry.
	check(_unique(tips.shown), "Every tip was shown at most once: %s" % [tips.shown])

	# --- Neuer Knoten, gleiches Profil: gesehene Tipps kommen nicht wieder ---
	tips.queue_free()
	var reloaded: RefCounted = PROFILE.load_or_create(TEST_PROFILE)
	for id in ["move", "prey", "warning", "rally"]:
		check(reloaded.has_seen_tip(id), "Profile remembers tip '%s'" % id)
	var again: Node = ONBOARDING.new()
	again.set_process(false)
	scene.add_child(again)
	again.setup(world, hud, swarm, reloaded)
	hud.hint = "RAUS AUS DEM ROTEN RING!"
	hunter.position = swarm.position + Vector3(3.0, 0, 0)
	_advance(again, 12.0)
	for id in ["move", "prey", "warning", "rally"]:
		check(not again.shown.has(id), "Seen tip '%s' does not repeat" % id)
	# Mutation: after the first choice closes.
	hud.hint = ""
	hunter.position = Vector3(90, 0, 90)
	world.evolution.offers = ["x"]
	_advance(again, 1.0)
	world.evolution.offers = []
	_advance(again, ONBOARDING.GAP_SECONDS + ONBOARDING.SHOW_SECONDS + 0.5)
	check(again.shown.has("mutation"), "Mutation tip after the first choice (shown %s)" % [again.shown])
	again.queue_free()
	scene.queue_free()
	await process_frame

	# --- Main mit Menü-Config legt das Onboarding an --------------------------
	SESSION.pending_config = PROFILE.load_or_create(TEST_PROFILE).build_run_config("glutmaw", "verdant_maw", 0)
	SESSION.pending_config["profile_path"] = TEST_PROFILE
	var configured: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(configured)
	await process_frame
	var created: Node = configured.get_node_or_null("Onboarding")
	check(created != null and created.active, "Main creates an active onboarding for menu configs")
	configured.queue_free()
	await process_frame

	# --- Erststart-Weiche im Menü --------------------------------------------
	SESSION.pending_config = {}
	var menu: Control = load("res://scripts/menu/menu.gd").new()
	menu.profile_path = MENU_PROFILE
	menu.change_scene_on_play = false
	root.add_child(menu)
	await process_frame
	check(SESSION.pending_config.is_empty(), "Menu test mode does not auto-start")
	var first: Dictionary = menu.try_first_start()
	check(not first.is_empty(), "First start builds a run config")
	check(SESSION.pending_config.get("strain_id", "") == "glutmaw", "First start plays Glutmaw")
	check(int(SESSION.pending_config.get("difficulty", -1)) == 0, "First start plays Wild")
	check(int(SESSION.pending_config.get("seed", 0)) == int(menu.profile.next_seed), "First start uses the profile seed")
	check(String(SESSION.pending_config.get("profile_path", "")) == MENU_PROFILE, "Config carries the profile path for the onboarding")
	check(bool(SESSION.pending_config.get("first_start", false)), "Config is marked as first start")
	menu.queue_free()
	await process_frame
	# After the first run the menu stays.
	SESSION.pending_config = {}
	var veteran: RefCounted = PROFILE.load_or_create(MENU_PROFILE)
	veteran.record_run({"seconds": 40.0, "kills": 3})
	var menu2: Control = load("res://scripts/menu/menu.gd").new()
	menu2.profile_path = MENU_PROFILE
	menu2.change_scene_on_play = false
	root.add_child(menu2)
	await process_frame
	check(menu2.try_first_start().is_empty() and SESSION.pending_config.is_empty(), "Menu shows normally after the first run")
	menu2.queue_free()
	SESSION.pending_config = {}

	_delete(TEST_PROFILE)
	_delete(MENU_PROFILE)
	if failures > 0:
		print("ONBOARDING FAILED: %d" % failures)
		quit(1)
		return
	print("Onboarding test passed")
	quit(0)


func _advance(node: Node, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		node.tick(STEP)
		t += STEP


func _place_prey(world: Node, swarm: Node3D, distance: float) -> void:
	for target in world.prey:
		target.position = Vector3(90, 0, 90)
	world.prey[0].position = swarm.position + Vector3(0, 0, distance)


func _tip(hud: Object) -> String:
	return String(hud.get("tutorial_tip")) if "tutorial_tip" in hud else String(hud.get_meta("tutorial_tip", ""))


func _icon(hud: Object) -> String:
	return String(hud.get("tutorial_icon")) if "tutorial_icon" in hud else String(hud.get_meta("tutorial_icon", ""))


func _unique(list: Array) -> bool:
	var seen := {}
	for item in list:
		if seen.has(item):
			return false
		seen[item] = true
	return true


func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)


func _delete(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
