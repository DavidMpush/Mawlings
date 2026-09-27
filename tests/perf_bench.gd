extends SceneTree

# LEISTUNG (Etappe 06, Kriterium 7): Mess-Szene für Frame-Zeit, Draw Calls,
# Objekte und Speicher. Braucht ein echtes Fenster – NIE mit --headless starten,
# sonst rendert nichts und alle Render-Zähler bleiben 0.
#
# Aufruf (einzeln):
#   Godot_console.exe --path <projekt> --script res://tests/perf_bench.gd -- scene=worst secs=20
#   Weitere Schalter: off=units,shadows,decor,arena,enemies,corpses,fx,forms,popups,hud,swarmcpu
#                     (off=units blendet das Schwarm-MultiMesh "Mawlings" samt Geistern aus)
#                     cap=60 (nur die ersten N Mawling-Instanzen sichtbar), scale3d=0.7
#                     (3D-Renderskalierung), msaa=0|2|4, trace=1 (Speicher alle 5 s), res=540x1170 (Fenstergröße), warm=3
#                     corpses=30 (liegende Kadaver im Worst Case), quality=low|medium|high (Stufe erzwingen;
#                     sonst wählt main.gd sie wie im Spiel per Heuristik – Desktop = HOCH)
# Szenen: worst (Worst Case), calm (ruhiger Spielstart), menu (Brutstätte mit
#         SubViewport-Rudel), menu2d (Brutstätte ohne 3D-Rudel), flood (Etappe 08:
#         Worst Case plus volle Flut – 160 Moorbrut ab Stufe 3, Bisse, Tode, Kadaver).
# Kennzahlen: avg/p95 = reale Frame-Zeit (Vsync aus); process_max_ms = Performance.TIME_PROCESS
# (Godot meldet das Maximum der letzten Sekunde); world_ms/swarm_ms = selbst gemessene
# Skriptzeit von HuntWorld.step / Swarm._process (der Bench ruft beide selbst auf);
# horde_ms = horde.step() inkl. Zeichnen, horde_other_ms = melee()/damage_circle() (Etappe 08);
# render_cpu_ms/gpu_ms = RenderingServer-Messung des Haupt-Viewports.
# Ausgabe: eine Zeile "PERF scene=… avg_ms=… p95_ms=… …" plus "PERF_NODES …".
# Sammeln aller Varianten: tools/perf.ps1.

const MAIN_SCENE := "res://scenes/main.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"
const BENCH_PROFILE := "user://perf_bench_profile.json"
const MAP_SEED := 424242
const GROUND_PARTS := ["Open ground", "Trail edge", "Broad trail"]
const ENEMY_NAMES := ["Hunter", "Skitter", "Mire Leaper", "Bog King", "Nibbler"]
const TOUGH := 1.0e9
const QUALITY = preload("res://scripts/quality.gd")
const TUNING = preload("res://scripts/tuning.gd")

var args := {}
var off: PackedStringArray = []
var scene_name := "worst"
var seconds := 20.0
var warm := 3.0

var scene: Node
var world: Node3D
var swarm: Node3D
var arena: Node3D
var controls: Control
var menu: Control

var clock := 0.0
var popup_clock := 0.0
var last_world_us := 0
var last_swarm_us := 0
var last_horde_us := 0
var last_horde_other_us := 0


func _initialize() -> void:
	for raw in OS.get_cmdline_user_args():
		var parts := String(raw).split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else "1"
	scene_name = String(args.get("scene", "worst"))
	seconds = float(args.get("secs", "20"))
	warm = float(args.get("warm", "3"))
	if args.has("off"):
		off = String(args.off).split(",", false)
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("perf_bench: needs a window (run without --headless)")
		quit(2)
		return
	var res := String(args.get("res", "540x1170")).split("x")
	root.size = Vector2i(int(res[0]), int(res[1]))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	if args.has("quality"):
		QUALITY.set_override(QUALITY.parse(String(args.quality)))
	match scene_name:
		"menu", "menu2d":
			_build_menu(scene_name == "menu")
		"calm":
			_build_game()
		"flood":
			_build_game()
			await process_frame
			_build_worst_case()
			_build_flood()
		_:
			_build_game()
			await process_frame
			_build_worst_case()
	# main.gd applies the quality tier (MSAA, 3D scale, 60 fps cap) like in the
	# game; the bench measures uncapped and may override the viewport switches.
	Engine.max_fps = 0
	if args.has("scale3d"):
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		root.scaling_3d_scale = float(args.scale3d)
	if args.has("msaa"):
		root.msaa_3d = {"2": Viewport.MSAA_2X, "4": Viewport.MSAA_4X}.get(String(args.msaa), Viewport.MSAA_DISABLED)
	node_added.connect(_on_node_added)
	_apply_switches_to_tree(root)
	await _measure()
	quit()


# ---------------------------------------------------------------- scenes

func _build_game() -> void:
	scene = load(MAIN_SCENE).instantiate()
	root.add_child(scene)
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	arena = scene.get_node("Arena")
	controls = scene.get_node("HUD/Controls")
	# Background bench windows lose focus; the auto-pause must not stop the run.
	if controls.pause_requested.is_connected(world.toggle_pause):
		controls.pause_requested.disconnect(world.toggle_pause)
	# Menu runs are always seeded; the seeded map has its own decor pass.
	arena.set_seed(MAP_SEED)
	_hold_spawn_clocks()
	world.set_process(false)
	swarm.set_process(false)


func _build_worst_case() -> void:
	world.model.population = 250
	world.model.peak_population = 250
	swarm.set_population(250, false)
	# All four attack forms at their top: both evolutions replace their base form.
	var evo = world.evolution
	evo.slots = {"attack": 4, "trait": 3}
	evo.ranks = {"meute": 1, "aetzflut": 1, "sporenwolke": 3, "stachelruecken": 3, "jaws": 3, "pack": 3, "glutton": 3}
	evo.evolutions.assign(["meute", "aetzflut"])
	evo.offers.clear()
	world._sync_attack_forms()
	var origin: Vector3 = swarm.position
	world._spawn_boss(origin + Vector3(6.0, 0.0, -5.0))
	for index in 3:
		var angle := float(index) * TAU / 3.0
		world._spawn_hunter(origin + Vector3(cos(angle), 0.0, sin(angle)) * 6.5)
		world._spawn_skitter(origin + Vector3(cos(angle + 1.0), 0.0, sin(angle + 1.0)) * 8.0)
		world._spawn_leaper(origin + Vector3(cos(angle + 2.0), 0.0, sin(angle + 2.0)) * 9.0)
	for enemy in _enemies():
		_toughen(enemy)
	# A late run leaves persistent corpses along the way (a full swarm cannot eat).
	for index in int(args.get("corpses", "30")):
		var angle := float(index) * 2.39996
		world._create_corpse(origin + Vector3(cos(angle), 0.0, sin(angle)) * (4.0 + float(index % 6) * 2.5 + float(index / 30) * 1.2), 12.0)


# Full flood at stage ~3 (k = 120 s / 40 s): the horde is kept at its cap of 160
# with real stats, so bites, deaths, bundled corpses and popups all happen.
func _build_flood() -> void:
	world.model.elapsed = world.flood_start + 120.0
	world.flood_state = 2
	world.flood_reached = true
	_top_up_flood()


func _top_up_flood() -> void:
	var horde: Variant = world.get("horde")
	if horde == null or not horde.has_method("spawn_ring"):
		return
	var missing: int = TUNING.FLOOD_MAX_ACTIVE - int(horde.count())
	if missing > 0:
		horde.spawn_ring(swarm.position, missing, 11.0, world.flood_stats())


func _build_menu(with_3d: bool) -> void:
	if FileAccess.file_exists(BENCH_PROFILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BENCH_PROFILE))
	var profile: Variant = load("res://scripts/meta/profile.gd").load_or_create(BENCH_PROFILE)
	profile.essence = 800
	profile.records.best_seconds = 240.0
	profile.save()
	var session: Variant = load("res://scripts/meta/session.gd")
	session.last_result = {}
	menu = load(MENU_SCENE).instantiate()
	menu.profile_path = BENCH_PROFILE
	menu.change_scene_on_play = false
	if not with_3d:
		menu.child_entered_tree.connect(func(child: Node) -> void:
			if "use_3d" in child:
				child.set("use_3d", false))
	root.add_child(menu)
	scene = menu


# ---------------------------------------------------------------- per frame

func _drive(delta: float) -> void:
	clock += delta
	if world == null:
		return
	# Slow circle; Rally on for 1.5 s of every 3 s.
	var angle := clock * 0.9
	controls.movement_vector = Vector2(cos(angle), sin(angle)) * (0.35 if scene_name == "calm" else 0.8)
	if scene_name != "calm":
		_drive_worst_case(delta)
	if scene_name == "flood":
		world.flood_state = 2
		_top_up_flood()
	_step_systems(delta)


# The bench steps HuntWorld and Swarm itself to time their script cost per frame.
func _step_systems(delta: float) -> void:
	var horde: Variant = world.get("horde")
	var has_horde: bool = horde != null and is_instance_valid(horde) and "usec_step" in horde
	if has_horde:
		horde.usec_step = 0
		horde.usec_other = 0
	var t0 := Time.get_ticks_usec()
	world.step(minf(delta, 0.05))
	var t1 := Time.get_ticks_usec()
	if has_horde:
		last_horde_us = int(horde.usec_step)
		last_horde_other_us = int(horde.usec_other)
	if not _is_off("swarmcpu"):
		swarm._process(delta)
	var t2 := Time.get_ticks_usec()
	last_world_us = t1 - t0
	last_swarm_us = t2 - t1
	# Etappe 07: the swarm is one MultiMesh ("Mawlings"); cap trims its instances.
	if args.has("cap"):
		var cap := mini(int(args.cap), swarm.units.size())
		for batch in [swarm.get("bodies"), swarm.get("shadows")]:
			if batch is MultiMeshInstance3D:
				(batch as MultiMeshInstance3D).multimesh.visible_instance_count = mini(cap, (batch as MultiMeshInstance3D).multimesh.visible_instance_count)


func _drive_worst_case(delta: float) -> void:
	controls.rally_pressed = fmod(clock, 3.0) < 1.5
	world.paused = false
	world.evolution.offers.clear()
	_hold_spawn_clocks()
	if world.model.population < 250 or world.model.extinct:
		world.model.extinct = false
		world.model.population = 250
		swarm.set_population(250)
	# Keep the enemy set complete and close to the swarm.
	var origin: Vector3 = swarm.position
	if world.boss == null:
		_toughen(world._spawn_boss(origin + Vector3(7.0, 0.0, -5.0)))
	for pair in [["hunters", "_spawn_hunter"], ["skitters", "_spawn_skitter"], ["leapers", "_spawn_leaper"]]:
		var group: Array = world.get(pair[0])
		while group.size() < 3:
			_toughen(world.call(pair[1], origin + Vector3(randf_range(-8.0, 8.0), 0.0, randf_range(-8.0, 8.0))))
	for enemy in _enemies():
		if enemy.position.distance_to(origin) > 14.0:
			enemy.position = origin + (enemy.position - origin).normalized() * 9.0
	popup_clock -= delta
	if popup_clock <= 0.0 and not _is_off("popups"):
		popup_clock = 0.35
		var spot := origin + Vector3(randf_range(-6.0, 6.0), 0.0, randf_range(-6.0, 6.0))
		world._add_popup(spot, 10 + randi() % 30, randf_range(4.0, 20.0))


func _hold_spawn_clocks() -> void:
	world.hunter_clock = 1.0e6
	world.skitter_clock = 1.0e6
	world.leaper_clock = 1.0e6
	world.boss_clock = 1.0e6


func _enemies() -> Array:
	var result: Array = []
	result.append_array(world.hunters)
	result.append_array(world.skitters)
	result.append_array(world.leapers)
	if world.boss != null:
		result.append(world.boss)
	return result


func _toughen(enemy: Node) -> void:
	if enemy == null:
		return
	enemy.set("health", TOUGH)
	enemy.set("max_health", TOUGH)


# ---------------------------------------------------------------- switches

func _is_off(key: String) -> bool:
	return off.has(key)


func _apply_switches_to_tree(node: Node) -> void:
	if world == null:
		return
	if _is_off("hud"):
		scene.get_node("HUD").visible = false
	if _is_off("arena"):
		arena.visible = false
	if _is_off("shadows"):
		swarm.shadows.visible = false
	if _is_off("fx") and world.attack_forms != null:
		world.attack_forms.visible = false
	if _is_off("corpses") and world.get("corpse_view") != null:
		world.corpse_view.visible = false
	if _is_off("forms") and world.attack_forms != null:
		world.evolution.ranks = {"jaws": 3, "pack": 3, "glutton": 3}
		world._sync_attack_forms()
	if _is_off("units"):
		for key in ["bodies", "ghost_bodies"]:
			var batch: Variant = swarm.get(key)
			if batch is Node3D:
				(batch as Node3D).visible = false
	for child in node.find_children("*", "Node3D", true, false):
		_on_node_added(child)


func _on_node_added(node: Node) -> void:
	if world == null or not (node is Node3D):
		return
	var parent := node.get_parent()
	if _is_off("decor") and parent != null and parent.get_parent() == arena and not GROUND_PARTS.has(String(node.name)):
		node.visible = false
	elif _is_off("enemies") and parent == world and _named(node, ENEMY_NAMES):
		node.visible = false
	elif _is_off("corpses") and parent == world and String(node.name).begins_with("Persistent corpse"):
		node.visible = false
	elif _is_off("fx") and (String(node.name).contains("Ground ring") or String(node.name) == "FX rings"):
		node.visible = false


func _named(node: Node, names: Array) -> bool:
	var own := String(node.name)
	for entry in names:
		if own.contains(entry):
			return true
	return false


# ---------------------------------------------------------------- measuring

func _measure() -> void:
	var last := Time.get_ticks_usec()
	var warm_left := warm
	while warm_left > 0.0:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := float(now - last) / 1.0e6
		last = now
		warm_left -= dt
		_drive(dt)
	var frames := PackedFloat32Array()
	var mem_start := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var vram_start := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var process_ms := 0.0
	var gpu_ms := 0.0
	var render_cpu_ms := 0.0
	var draws := 0.0
	var objects := 0.0
	var prims := 0.0
	var elapsed := 0.0
	var samples := 0
	var world_ms := 0.0
	var swarm_ms := 0.0
	var horde_ms := 0.0
	var horde_other_ms := 0.0
	while elapsed < seconds:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := float(now - last) / 1.0e6
		last = now
		elapsed += dt
		_drive(dt)
		frames.append(dt * 1000.0)
		if args.has("trace") and int(elapsed / 5.0) != int((elapsed - dt) / 5.0):
			print("PERF_TRACE t=%.0f mem_mb=%.1f vram_mb=%.1f objs=%d nodes=%d draw_calls=%d" % [elapsed,
				Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
				int(Performance.get_monitor(Performance.OBJECT_COUNT)), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
		process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
		render_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
		world_ms += float(last_world_us) / 1000.0
		swarm_ms += float(last_swarm_us) / 1000.0
		horde_ms += float(last_horde_us) / 1000.0
		horde_other_ms += float(last_horde_other_us) / 1000.0
		samples += 1
	var n := float(maxi(1, samples))
	var sorted := frames.duplicate()
	sorted.sort()
	var total := 0.0
	for value in frames:
		total += value
	var p95: float = sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))] if not sorted.is_empty() else 0.0
	var label := scene_name
	if args.has("corpses"):
		label += "-corpses_%s" % String(args.corpses)
	if args.has("quality"):
		label += "-q_%s" % String(args.quality)
	if not off.is_empty():
		label += "-off_" + "+".join(off)
	for key in ["res", "cap", "scale3d", "msaa"]:
		if args.has(key):
			label += "-%s_%s" % [key, String(args[key])]
	print("PERF scene=%s tier=%s avg_ms=%.2f p95_ms=%.2f fps=%.0f process_max_ms=%.2f world_ms=%.2f swarm_ms=%.2f horde_ms=%.2f horde_other_ms=%.2f render_cpu_ms=%.2f gpu_ms=%.2f draw_calls=%.0f objects=%.0f prims=%.0f objs=%d nodes=%d mem_mb=%.1f vram_mb=%.1f mem_start_mb=%.1f vram_start_mb=%.1f frames=%d res=%dx%d" % [
		label, QUALITY.tier_id(QUALITY.current_tier()), total / n, p95, 1000.0 / maxf(0.001, total / n), process_ms / n, world_ms / n, swarm_ms / n, horde_ms / n, horde_other_ms / n, render_cpu_ms / n, gpu_ms / n,
		draws / n, objects / n, prims / n,
		int(Performance.get_monitor(Performance.OBJECT_COUNT)), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		mem_start, vram_start, samples, root.size.x, root.size.y])
	_print_node_breakdown(label)


# Visible geometry per subsystem at the end of the run (where the draw calls come from).
func _print_node_breakdown(label: String) -> void:
	if world == null:
		var geo := _geometry(scene)
		print("PERF_NODES scene=%s menu_geometry=%d menu_nodes=%d" % [label, geo, scene.get_child_count()])
		return
	var chunk_props := 0
	for chunk in arena.get_children():
		chunk_props += _geometry(chunk)
	var enemies := 0
	for enemy in _enemies():
		enemies += _geometry(enemy)
	for prey in world.prey:
		enemies += _geometry(prey)
	# Corpses: one MultiMesh per design + pool + halo (Etappe 09 corpse_visuals.gd).
	var corpses := 0
	var view: Variant = world.get("corpse_view")
	var corpse_count := 0
	if view is Node3D and is_instance_valid(view):
		corpse_count = view.count()
		if (view as Node3D).is_visible_in_tree():
			corpses = view.active_batches()
	var forms := _geometry(world.attack_forms) if world.attack_forms != null else 0
	var swarm_geo := _geometry(swarm)
	print("PERF_NODES scene=%s swarm_geo=%d mawling_units=%d ghosts=%d arena_chunks=%d arena_geo=%d enemy_geo=%d corpse_geo=%d corpses=%d attack_fx_geo=%d world_geo_total=%d unique_materials_hint=corpses:%d" % [
		label, swarm_geo, swarm.units.size(), swarm.ghosts.size(), arena.get_child_count(), chunk_props, enemies, corpses,
		corpse_count, forms, _geometry(world), corpses])


# Visible GeometryInstance3D nodes below `node` (MultiMesh counts once).
func _geometry(node: Variant) -> int:
	if not (node is Node) or not is_instance_valid(node):
		return 0
	var count := 0
	for child in node.find_children("*", "GeometryInstance3D", true, false):
		if (child as GeometryInstance3D).is_visible_in_tree():
			count += 1
	return count
