extends SceneTree

# Preview for stage 15 package H (run WITHOUT --headless, with
# --screen 1 --audio-driver Dummy): the unified boss stack in hud_top.gd, the
# flood pill of hud_flood.gd and the edge pointers / ribbons of
# hud_objectives.gd over the real game view. The world is frozen and the HUD
# values / metas are set by hand, so every state is exact:
#   king, king_vulnerable, king_intro (mid slide-in), moosschlund,
#   apex_rising, toad_phase2, two_bosses, flood, flood_warning, flood_boss,
#   flood_two_bosses, pointers, totem_hold, victory, arrival
# Each is saved as preview_ui_boss_<name>.png (900 x 1600) and _540.png.

const TUNING = preload("res://scripts/tuning.gd")

var scene: Node
var world: Variant
var swarm: Variant
var controls: Control
var top: Control
var objectives := {}
var flood := {}


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(900, 1600)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	controls = scene.get_node("HUD/Controls")
	if controls.pause_requested.is_connected(world.toggle_pause):
		controls.pause_requested.disconnect(world.toggle_pause)
	top = controls.get_node("hud_top")
	await create_timer(0.8).timeout
	world.set_process(false)
	for target in world.prey:
		target.visible = false
	world.model.population = 120
	swarm.set_population(120, false)
	world.evolution.offers = []
	world.evolution.level = 6
	world.evolution.dna = 420
	_base()
	var king := TUNING.BOSS_HEALTH
	var apex := TUNING.APEX_HEALTH
	var toad := TUNING.APEX_TOAD_HEALTH * 1.6

	# --- Bog King
	_hud({"boss_health": king * 0.74, "boss_max_health": king, "boss_vulnerable": false})
	await _settle(2.4)
	await _save_both("king")
	_hud({"boss_vulnerable": true})
	await _settle(0.4)
	await _save_both("king_vulnerable")
	_hud({"boss_health": 0.0})
	await _settle(0.2)
	_hud({"boss_health": king, "boss_vulnerable": false})
	await _settle(0.15)
	await _save("preview_ui_boss_king_intro.png")

	# --- Moosschlund (apex): rising, phase 1
	_hud({"boss_health": 0.0})
	_apex({"apex_state": 1, "apex_warning": 0.35, "apex_kind": "apex", "apex_name": "MOOSSCHLUND"})
	await _settle(2.4)
	await _save_both("apex_rising")
	_apex({"apex_state": 2, "apex_warning": 0.0, "apex_health": apex * 0.83, "apex_max_health": apex, "apex_phase": 1})
	await _settle(0.3)
	await _save_both("moosschlund")

	# --- Aschenkröte phase 2 (second loop: bigger numbers)
	_apex({"apex_state": 0})
	await _settle(0.2)
	_apex({"apex_state": 2, "apex_kind": "apex_toad", "apex_name": "ASCHENKRÖTE", "apex_health": toad * 0.37, "apex_max_health": toad, "apex_phase": 2})
	await _settle(2.4)
	await _save_both("toad_phase2")

	# --- two bosses: the toad lives, a Bog King (vulnerable) joins
	_hud({"boss_health": king * 0.4, "boss_max_health": king, "boss_vulnerable": true})
	await _settle(2.4)
	await _save_both("two_bosses")

	# --- flood: running, announced, with one and two bosses
	_hud({"boss_health": 0.0, "boss_vulnerable": false})
	_apex({"apex_state": 0})
	_flood({"state": 2, "stage": 3, "seconds": 95.0, "countdown": 0.0})
	await _settle(1.6)
	await _save_both("flood")
	_flood({"state": 1, "stage": 1, "seconds": 0.0, "countdown": 6.4})
	await _settle(0.3)
	await _save_both("flood_warning")
	_flood({"state": 2, "stage": 4, "seconds": 211.0, "countdown": 0.0})
	_hud({"boss_health": king * 0.9, "boss_max_health": king})
	_hunters(3)
	await _settle(2.4)
	await _save_both("flood_boss")
	_apex({"apex_state": 2, "apex_kind": "apex", "apex_name": "MOOSSCHLUND", "apex_health": apex * 0.55, "apex_max_health": apex, "apex_phase": 1})
	await _settle(2.4)
	await _save_both("flood_two_bosses")

	# --- pointers: nest (filling), totem, migration maw, apex (exhausted) + curse chip
	_flood({"state": 0})
	_hud({"boss_health": 0.0})
	_apex({"apex_state": 2, "apex_vulnerable": true, "apex_health": apex * 0.3, "apex_phase": 2,
		"apex_pointer": Vector2(860, 760), "apex_distance": 31.0,
		"nest_active": true, "nest_progress": 0.4, "nest_pointer": Vector2(60, 900), "nest_distance": 24.0,
		"totem_active": true, "totem_pointer": Vector2(560, 330), "totem_distance": 38.0, "totem_screen": Vector2.INF,
		"portal_active": true, "portal_target": "GLUTSUMPF", "portal_pointer": Vector2(420, 1230), "portal_distance": 57.0, "portal_hold": 0.0,
		"curse": 1})
	await _settle(2.4)
	await _save_both("pointers")

	# --- totem hold near the swarm
	_apex({"apex_state": 0, "nest_active": false, "portal_active": false, "totem_pointer": Vector2.INF,
		"totem_screen": Vector2(450, 800), "totem_hold": 0.62, "curse": 0})
	await _settle(0.4)
	await _save_both("totem_hold")

	# --- victory ribbon (apex beaten) and the arrival ribbon of the new biome
	_apex({"totem_active": false, "apex_state": 3, "apex_kind": "apex_toad", "apex_name": "ASCHENKRÖTE", "apex_victories": 1})
	await _settle(0.7)
	await _save_both("victory")
	await _settle(2.6)
	_apex({"arrivals": 1, "biome_id": "glutsumpf"})
	await _settle(0.9)
	await _save_both("arrival")
	print("Saved boss HUD previews")
	quit()


func _base() -> void:
	objectives = {
		"nest_active": false, "nest_progress": 0.0, "nest_pointer": Vector2.INF,
		"totem_active": false, "totem_hold": 0.0, "totem_pointer": Vector2.INF, "totem_screen": Vector2.INF,
		"curse": 0, "apex_state": 0, "apex_warning": 0.0, "apex_health": 0.0, "apex_max_health": 0.0,
		"apex_phase": 1, "apex_vulnerable": false, "apex_pointer": Vector2.INF, "apex_victories": 0,
		"apex_kind": "apex", "apex_name": "MOOSSCHLUND", "portal_active": false, "portal_hold": 0.0,
		"portal_target": "", "portal_pointer": Vector2.INF, "migration": -1.0, "arrivals": 0,
		"biome_id": "verdant_maw",
	}
	flood = {"state": 0, "countdown": 0.0, "stage": 1, "level": 0.0, "seconds": 0.0, "count": 0}
	_apex({})
	_flood({})
	_hud({"elapsed": 332.0, "pressure": 6.0, "hunters": 0, "boss_health": 0.0, "alpha_cores": 0, "population": 120})


func _hud(values: Dictionary) -> void:
	for key in values:
		controls.set(key, values[key])


func _hunters(count: int) -> void:
	controls.set("hunters", count)


func _apex(values: Dictionary) -> void:
	objectives.merge(values, true)
	controls.set_meta("objectives", objectives.duplicate())


func _flood(values: Dictionary) -> void:
	flood.merge(values, true)
	controls.set_meta("flood", flood.duplicate())


func _settle(seconds: float) -> void:
	await create_timer(seconds).timeout


func _save_both(name: String) -> void:
	root.size = Vector2i(900, 1600)
	await _frames(3)
	await _save("preview_ui_boss_%s.png" % name)
	root.size = Vector2i(540, 960)
	await _frames(3)
	await _save("preview_ui_boss_%s_540.png" % name)
	root.size = Vector2i(900, 1600)
	await _frames(2)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + file_name)
