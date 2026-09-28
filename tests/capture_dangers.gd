extends SceneTree

# Stage 20 review frames: every danger form and every boss attack from the
# real game camera (540 x 960). Run WITHOUT --headless:
#   Godot --screen 1 --audio-driver Dummy --path . --script res://tests/capture_dangers.gd
#   preview_danger_enemies.png    Kontur "kommt gleich": Jäger, Skitter, Leaper, Nibbler
#   preview_danger_bog_king.png   Bog-King-Stampf (SVG-Kreis)
#   preview_danger_moss_{roots,spores,quake}.png  (+ _quake_cb)
#   preview_danger_toad_{leap,spit,tongue,puddles}.png
#   preview_danger_worm_{breach,sweep}.png
#   preview_danger_eruption.png   Lava-Ausbruch (Glutsumpf)
#   preview_danger_flood.png      Großer Ring "Ereignis läuft" (Flutwelle)
#   preview_danger_friendly.png   freundliche Ringe: Kokon, Schrein, Nest
#   preview_danger_exact.png      Referenzlinien (cyan) genau auf der Trefferkante
#   preview_danger_sheet.png      Übersicht aller Bilder (halbe Größe)

const TUNING = preload("res://scripts/tuning.gd")
const TG = preload("res://scripts/telegraph_style.gd")
const APEX = preload("res://scripts/apex_boss.gd")
const TOAD = preload("res://scripts/apex_toad.gd")
const WORM = preload("res://scripts/apex_sandworm.gd")
const UI_STYLE = preload("res://scripts/ui/ui_style.gd")
const CAMERA_OFFSET := Vector3(0.0, 23.0, 15.0)
const DT := 1.0 / 60.0

var scene: Node
var world: Variant
var swarm: Variant
var arena: Variant
var camera: Camera3D
var shots: Array[Image] = []
var extras: Array[Node] = []


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	arena = scene.get_node("Arena")
	camera = scene.get_node("Camera3D")
	var controls: Node = scene.get_node("HUD/Controls")
	for connection in controls.pause_requested.get_connections():
		connection.signal.disconnect(connection.callable)
	scene.set_process(false)
	world.set_process(false)
	_quiet()
	world.model.population = 50
	swarm.set_population(50, false)
	swarm.position = Vector3(0, 0, 30)
	_frame()
	await _settle(60)
	await _enemies()
	await _bog_king()
	await _moss()
	await _toad()
	await _worm()
	await _eruption()
	await _flood()
	await _friendly()
	_sheet()
	print("Saved danger review frames (%d)" % shots.size())
	quit()


func _quiet() -> void:
	for target in world.prey:
		target.queue_free()
	world.prey.clear()
	for clock in ["spawn_clock"]:
		world.set(clock, -1000000.0)
	for clock in ["hunter_clock", "skitter_clock", "leaper_clock", "boss_clock", "elite_clock", "nest_clock"]:
		world.set(clock, 1000000.0)
	world.flood_start = 1000000.0


func _frame() -> void:
	arena.sync(swarm.position)
	camera.position = swarm.position + CAMERA_OFFSET
	camera.look_at(swarm.position, Vector3.UP)


func _settle(frames: int) -> void:
	for frame in frames:
		_frame()
		await process_frame


func _clear() -> void:
	for node in extras:
		if is_instance_valid(node):
			node.queue_free()
	extras.clear()


func _add(part: Node3D, at: Vector3, yaw := 0.0) -> Node3D:
	world.add_child(part)
	part.global_position = Vector3(at.x, 0.12, at.z)
	part.rotation.y = yaw
	extras.append(part)
	return part


func _save(file_name: String, hint: String) -> void:
	world._update_hud(hint)
	for frame in 4:
		_frame()
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://previews/" + file_name)
	shots.append(image)


# Kontur = kommt gleich: the four normal enemy warnings at mid wind-up.
func _enemies() -> void:
	var s: Vector3 = swarm.position
	var hunter := _add(TG.build("hunter", TUNING.HUNTER_ATTACK_RADIUS), s + Vector3(-5.5, 0, -6.5))
	TG.set_armed(hunter, true)
	TG.set_progress(hunter, 0.55)
	var lane := _add(TG.build("skitter", TUNING.SKITTER_WIDTH * 2.0), s + Vector3(5.5, 0, -2.0), 0.3)
	lane.scale.z = 14.0
	TG.set_progress(lane, 0.5)
	var leaper := _add(TG.build("leaper", TUNING.LEAPER_ZONE_RADIUS), s + Vector3(-5.0, 0, 6.0))
	TG.set_progress(leaper, 0.5)
	var nibbler := _add(TG.build("hunter", TUNING.NIBBLER_SNAP_RADIUS), s + Vector3(4.0, 0, 7.0))
	TG.set_armed(nibbler, true)
	TG.set_progress(nibbler, 0.6)
	await _save("preview_danger_enemies.png", "KONTUR = KOMMT GLEICH · Jäger, Skitter, Leaper, Nibbler")
	_clear()


func _bog_king() -> void:
	var zone := _add(TG.build("boss", TUNING.BOSS_ATTACK_RADIUS), swarm.position + Vector3(1.5, 0, -1.0))
	TG.set_progress(zone, 0.6)
	await _save("preview_danger_bog_king.png", "BOG KING STAMPFT · RAUS AUS DEM KREIS!")
	_clear()


# A real apex, frozen at ~55 % of its wind-up (its own step, no resolution).
func _windup(boss: Variant, share: float) -> void:
	var total: float = boss.remaining
	while boss.remaining > total * (1.0 - share):
		boss.step(DT, swarm.position, 1.0)
		_frame()
		await process_frame


func _apex(kind: String, offset: Vector3) -> Variant:
	var boss: Variant = world.spawn_apex(swarm.position + offset, kind)
	boss.position = swarm.position + offset
	boss.state = boss.State.CHASE
	boss.remaining = 0.0
	boss.cooldown = 999.0
	if boss.has_method("refresh_pose"):
		boss.refresh_pose()
	return boss


func _drop_apex() -> void:
	if world.apex != null:
		world.apex._clear_telegraphs()
		world.apex.queue_free()
		world.apex = null
		world.apex_state = 0
	await _settle(2)


func _moss() -> void:
	var boss: Variant = _apex("apex", Vector3(0, 0, -9))
	for entry in [[APEX.Pattern.ROOTS, "roots", 1], [APEX.Pattern.SPORES, "spores", 1], [APEX.Pattern.QUAKE, "quake", 2]]:
		boss.phase = int(entry[2])
		boss.begin_attack(int(entry[0]), swarm.position, 1.0)
		await _windup(boss, 0.55)
		await _save("preview_danger_moss_%s.png" % entry[1], boss.hud_message())
		if entry[1] == "quake":
			boss.restyle(true)
			await _save("preview_danger_moss_quake_cb.png", "FARBENBLIND · " + boss.hud_message())
			boss.restyle(false)
		boss._clear_telegraphs()
		boss.state = APEX.State.CHASE
	await _drop_apex()


func _toad() -> void:
	var toad: Variant = _apex("apex_toad", Vector3(0, 0, -10))
	for entry in [[TOAD.Pattern.LEAP, "leap"], [TOAD.Pattern.SPIT, "spit"], [TOAD.Pattern.TONGUE, "tongue"]]:
		toad.begin_attack(int(entry[0]), swarm.position, 1.0)
		await _windup(toad, 0.55)
		await _save("preview_danger_toad_%s.png" % entry[1], toad.hud_message())
		toad._clear_telegraphs()
		toad.state = TOAD.State.CHASE
	# Fläche = liegt da: Glutpfützen beside the swarm.
	for spot in [Vector3(-4, 0, -2), Vector3(3.5, 0, -4), Vector3(1.0, 0, 4.5)]:
		toad.puddles.add(swarm.position + spot, 2.2, 30.0, TOAD.telegraph_material(TOAD.SHAPE_PUDDLE, false))
	await _save("preview_danger_toad_puddles.png", "FLÄCHE = LIEGT DA · Glutpfützen meiden")
	toad.puddles.clear()
	await _drop_apex()


func _worm() -> void:
	var worm: Variant = _apex("apex_sandworm", Vector3(0, 0, -8))
	worm.begin_attack(WORM.Pattern.BREACH, swarm.position, 1.0)
	await _windup(worm, 0.55)
	await _save("preview_danger_worm_breach.png", worm.hud_message())
	var ring := _reference_ring(worm.zones[0].center, float(worm.zones[0].radius))
	await _save("preview_danger_exact.png", "REFERENZ (CYAN) = TREFFERKANTE")
	ring.queue_free()
	worm._clear_telegraphs()
	worm.state = WORM.State.CHASE
	worm.begin_attack(WORM.Pattern.SWEEP, swarm.position, 1.0)
	await _windup(worm, 0.55)
	await _save("preview_danger_worm_sweep.png", worm.hud_message())
	worm._clear_telegraphs()
	await _drop_apex()


func _eruption() -> void:
	world._set_world_biome("glutsumpf", false)
	var home: Vector3 = swarm.position
	swarm.position = Vector3(45, 0, 45)
	arena.finish_rebuild()
	await _settle(10)
	if world.eruptions == null:
		return
	world.eruptions.erupt_soon()
	for frame in 900:
		world.eruptions.step(DT, swarm.position, 1.0)
		_frame()
		await process_frame
		if not world.eruptions.pending.is_empty() and float(world.eruptions.pending[0].get("remaining", 0.0)) < 0.9:
			break
	await _save("preview_danger_eruption.png", "LAVA BRICHT AUS!")
	world.eruptions.clear()
	swarm.position = home
	world._set_world_biome("verdant_maw", false)
	arena.finish_rebuild()
	await _settle(10)


# Großer Ring = Ereignis läuft: a flood wave.
func _flood() -> void:
	if world.horde == null:
		return
	world.horde.spawn_ring(swarm.position + Vector3(0, 0, -TUNING.FLOOD_RING_SHIFT), 24, TUNING.FLOOD_RING_RADIUS, world.flood_stats())
	for frame in 50:
		_frame()
		await process_frame
	await _save("preview_danger_flood.png", "RING = EREIGNIS · DIE FLUT")
	world.horde.clear()


# Freundliche Ringe: Kokon (Bernstein), Schrein, Brutnest - never danger colours.
func _friendly() -> void:
	var s: Vector3 = swarm.position
	if world.chests != null:
		world.chests.spawn("map", s + Vector3(-5, 0, -5))
		world.chests.spawn("gold", s + Vector3(5, 0, -6))
	if world.shrines != null:
		world.shrines.spawn(s + Vector3(0, 0, 7))
	for frame in 30:
		if world.chests != null:
			world.chests.step(DT, s)
		_frame()
		await process_frame
	await _save("preview_danger_friendly.png", "FREUNDLICH · Kokon, Schrein")


func _reference_ring(center: Vector3, radius: float) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.04
	torus.outer_radius = radius + 0.04
	torus.rings = 96
	var node := MeshInstance3D.new()
	node.mesh = torus
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.2, 1.0, 1.0)
	material.no_depth_test = true
	material.render_priority = 10
	node.material_override = material
	world.add_child(node)
	node.global_position = Vector3(center.x, 0.2, center.z)
	node.scale = Vector3(1.0, 0.2, 1.0)
	return node


func _reference_arc(origin: Vector3, dir: Vector3, reach: float, half: float) -> MeshInstance3D:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_LINE_STRIP)
	var base := atan2(dir.z, dir.x)
	tool.add_vertex(Vector3.ZERO)
	for step in 25:
		var a := base - half + 2.0 * half * float(step) / 24.0
		tool.add_vertex(Vector3(cos(a), 0.0, sin(a)) * reach)
	tool.add_vertex(Vector3.ZERO)
	var node := MeshInstance3D.new()
	node.mesh = tool.commit()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.2, 1.0, 1.0)
	material.no_depth_test = true
	material.render_priority = 10
	node.material_override = material
	world.add_child(node)
	node.global_position = Vector3(origin.x, 0.2, origin.z)
	return node


func _sheet() -> void:
	var columns := 4
	var w := 270
	var h := 480
	var rows := ceili(float(shots.size()) / columns)
	var sheet := Image.create(w * columns, h * rows, false, Image.FORMAT_RGBA8)
	for index in shots.size():
		var small := shots[index].duplicate() as Image
		small.convert(Image.FORMAT_RGBA8)
		small.resize(w, h)
		sheet.blit_rect(small, Rect2i(0, 0, w, h), Vector2i((index % columns) * w, (index / columns) * h))
	sheet.save_png("res://previews/preview_danger_sheet.png")
