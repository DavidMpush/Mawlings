extends SceneTree

# Stage 15 package D preview (brawl skin): every in-run banner, the pause panel
# and the extinction result (normal, mid count-up, and with a new record).
# Run WITHOUT --headless (frame_post_draw needs a render loop):
#   Godot_console.exe --path . --screen 1 --audio-driver Dummy --script res://tests/capture_ui_result.gd
#   ... -- --small      (same frames at a real 540 x 960 window, suffix _540)
# The result reads a throw-away profile (never saved) for records and tasks.

const PROFILE := preload("res://scripts/meta/profile.gd")

var scene: Node
var world: Variant
var swarm: Variant
var controls: Variant
var overlays: Variant
var suffix := ""


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var small := OS.get_cmdline_user_args().has("--small")
	suffix = "_540" if small else ""
	root.size = Vector2i(540, 960) if small else Vector2i(900, 1600)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	controls = scene.get_node("HUD/Controls")
	# Background capture windows lose focus; the auto-pause must not end up in the frames.
	controls.pause_requested.disconnect(world.toggle_pause)
	overlays = controls.get_node("hud_overlays")
	overlays.force_banners = true
	await create_timer(0.6).timeout
	var evo: Variant = world.evolution
	evo.ranks = {"rudelbiss": 3, "saeurespucker": 2, "jaws": 3, "brood": 2, "armor": 1, "glutton": 1, "aetzflut": 1}
	evo.evolutions.append("aetzflut")
	evo.level = 12
	# Banners, one at a time (settled after the pop).
	var banners := [
		["flood", func(): overlays.push_flood()],
		["boss", func(): overlays.push_boss()],
		["king", func(): overlays._push_king()],
		["victory", func(): overlays.push_victory("MOOSSCHLUND")],
		["migration", func(): overlays.push_arrival("glutsumpf", "Glutsumpf")],
		["milestone", func(): overlays._push_milestone(50)],
		["milestone250", func(): overlays._push_milestone(250)],
		["leader", func(): overlays.push_leader(2)],
		["evolution", func(): overlays.push_evolution("Ätzflut", "aetzflut")],
	]
	for entry in banners:
		overlays._queue.clear()
		overlays._banner = {}
		entry[1].call()
		await create_timer(0.55).timeout
		await _save("preview_ui_banner_%s%s.png" % [entry[0], suffix])
	overlays._queue.clear()
	overlays._banner = {}
	# Pause with the build.
	world.toggle_pause()
	await create_timer(0.6).timeout
	await _save("preview_ui_pause%s.png" % suffix)
	world.toggle_pause()
	await create_timer(0.2).timeout
	# Result, no record: long-time player with a 10-minute best.
	overlays.result_profile = _profile(600.0, 240, 22)
	_extinct()
	await create_timer(1.0).timeout
	await _save("preview_ui_result_count%s.png" % suffix)
	await create_timer(2.8).timeout
	await _save("preview_ui_result%s.png" % suffix)
	# Result with a new record (time and peak) and a task completed by the run.
	world.reset_run()
	await create_timer(0.3).timeout
	evo = world.evolution
	evo.ranks = {"rudelbiss": 2, "sporenwolke": 3, "brood": 3, "scatter": 1, "armor": 2}
	evo.level = 9
	overlays.result_profile = _profile(300.0, 120, 6)
	# Everything done but three goals: two stay open, one is finished by this run.
	var open_ids := ["survive_10", "peak_200", "kills_2000"]
	overlays.result_profile.completed_quests.clear()
	for q in load("res://scripts/meta/meta_data.gd").QUESTS:
		if not open_ids.has(q.id):
			overlays.result_profile.completed_quests.append(q.id)
	_extinct()
	await create_timer(3.8).timeout
	await _save("preview_ui_result_record%s.png" % suffix)
	print("Saved result/pause/banner previews", suffix)
	quit()


# A profile with some history (runs, bests, a few finished trophies).
func _profile(best_seconds: float, best_peak: int, runs: int) -> RefCounted:
	var p: RefCounted = PROFILE.new()
	p.records.runs = runs
	p.records.best_seconds = best_seconds
	p.records.best_peak = best_peak
	p.records.total_kills = 1820
	p.records.total_bosses = 3
	p.records.total_biomass = 7400.0
	p.records.total_hunters = 88
	p.records.total_skitters = 34
	p.completed_quests = ["survive_1", "survive_3", "peak_50", "peak_100", "kills_100", "kills_500", "boss_1", "survive_5", "runs_10", "biomass_1000"]
	return p


# Simulated extinction with a full stat sheet.
func _extinct() -> void:
	var model: Variant = world.model
	world.config = {"strain_id": "glutmaw", "biome_id": "verdant_maw", "difficulty": 1, "seed": 734512}
	model.elapsed = 437.0
	model.peak_population = 186
	model.consumed_biomass = 1296.4
	model.kills_by_type = {"prey": 142, "hunter": 23, "skitter": 31, "leaper": 7, "boss": 1}
	model.kills = 204
	model.bosses = 1
	model.lost_population = 211
	model.leader_hp = 1
	model.leader_invulnerable = 0.0
	world._apply_hit(100000, swarm.position, 0.0, null, true)


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + file_name)
