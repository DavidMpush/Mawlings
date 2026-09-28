extends SceneTree

# VFX-Paket V1 aus der echten Spielkamera. Ohne --headless ausführen, mit
#   Godot_console.exe --screen 1 --audio-driver Dummy --path . --script res://tests/capture_vfx.gd
# Ergebnis im Projektordner (540 × 960, ignoriert):
#   preview_vfx_<art>.png        jeder Effekt einzeln (bite, acid, spore, shock, harvest, dna)
#   preview_vfx_sheet.png        die sechs Einzelbilder als Übersicht (3 × 2, halbe Größe)
#   preview_vfx_flood.png        späte Flut, 200 Mawlings, Waffen auf Maximum, echte Effekte
#   preview_vfx_flood_b.png      dieselbe Szene 0,5 s später
#   preview_vfx_boss_circle.png  Bog-King-Stampf bei ~55 % Vorwarnzeit
#   preview_vfx_boss_circle_late.png / _cb.png   ~85 % (normal / Farbenblind)
#   preview_vfx_boss_exact.png   Kreis und Kegel mit dünnem Referenzring genau auf Radius/Reichweite
#   preview_vfx_boss_cone.png    Kegel-Telegraph am Boss, zum Schwarm gerichtet

const TUNING = preload("res://scripts/tuning.gd")
const TG = preload("res://scripts/telegraph_style.gd")
const UI_STYLE = preload("res://scripts/ui/ui_style.gd")
const DT := 1.0 / 60.0

var scene: Node
var world: Variant
var swarm: Variant
var shots: Array[Image] = []


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	var controls: Node = scene.get_node("HUD/Controls")
	if controls.pause_requested.is_connected(world.toggle_pause):
		controls.pause_requested.disconnect(world.toggle_pause)
	_quiet()
	world.model.population = 60
	swarm.set_population(60, false)
	for i in 50:
		await process_frame
	if world.paused:
		world.toggle_pause()
	await _singles()
	await _flood()
	await _boss()
	print("Saved VFX review frames")
	quit()


# --- 1: jeder Effekt einzeln ----------------------------------------------

func _singles() -> void:
	world.set_process(false)
	scene.set_process(false)
	var vfx: Node3D = world.attack_forms.vfx
	var origin: Vector3 = swarm.position
	var hunter: Node3D = world._spawn_hunter(origin + Vector3(2.6, 0, -1.4))
	hunter.state = hunter.State.CHASE
	hunter.warning.visible = false
	# kind -> [offset, size, share of the life to show]
	var plan := {
		"bite": [Vector3(2.2, 0, -1.2), 1.0, 0.3],
		"acid": [Vector3(2.6, 0, -1.4), 1.0, 0.3],
		"spore": [Vector3(2.6, 0, -1.4), 1.1, 0.35],
		"shock": [Vector3(2.6, 0, -1.4), 3.6 * 2.2, 0.3],
		"harvest": [Vector3(2.8, 0, 0.6), 1.0, 0.25],
		"dna": [Vector3(0.3, 0, -2.3), 1.0, 0.25],
	}
	for kind in plan:
		vfx.clear()
		vfx.spawn(kind, origin + plan[kind][0], plan[kind][1])
		var spec: Dictionary = vfx.KINDS[kind]
		var show: float = float(spec.duration[1]) * float(plan[kind][2])
		vfx.step(show, origin)
		await _save("preview_vfx_%s.png" % kind, true)
	vfx.clear()
	world.hunters.erase(hunter)
	hunter.queue_free()
	# Übersicht 3 × 2 in halber Größe.
	var sheet := Image.create(810, 960, false, Image.FORMAT_RGBA8)
	for index in shots.size():
		var small := shots[index].duplicate() as Image
		small.resize(270, 480, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(small, Rect2i(Vector2i.ZERO, small.get_size()), Vector2i((index % 3) * 270, (index / 3) * 480))
	sheet.save_png("res://previews/preview_vfx_sheet.png")


# --- 2: späte Flut mit vielen Effekten ------------------------------------

func _flood() -> void:
	scene.set_process(true)
	world.set_process(true)
	world.model.population = 200
	swarm.set_population(200, false)
	var evo = world.evolution
	evo.ranks = {"rudelbiss": 5, "saeurespucker": 5, "sporenwolke": 3, "graeber": 5, "giftbiss": 3, "bite": 5, "rally": 5, "brood": 5}
	world._sync_attack_forms()
	world.model.elapsed = world.flood_start + 150.0
	world.flood_state = 2
	world.flood_reached = true
	var horde: Variant = world.horde
	if horde != null:
		horde.spawn_ring(swarm.position, 160 - horde.count(), 7.5, world.flood_stats())
	for index in 3:
		var angle := float(index) * TAU / 3.0 + 0.4
		var hunter: Node3D = world._spawn_hunter(swarm.position + Vector3(cos(angle), 0, sin(angle)) * 5.0)
		hunter.health = 1.0e6
		hunter.max_health = 1.0e6
	await _wait(2.2, 200, true)
	await _save("preview_vfx_flood.png")
	await _wait(0.5, 200, true)
	await _save("preview_vfx_flood_b.png")
	if horde != null:
		horde.clear()
	world.flood_start = 1.0e9
	world.flood_state = 0
	for hunter in world.hunters:
		hunter.queue_free()
	world.hunters.clear()
	world.attack_forms.clear()
	evo.ranks = {"bite": 5, "rally": 5, "brood": 5}
	world._sync_attack_forms()


# --- 3: Boss-Telegraphen ---------------------------------------------------

func _boss() -> void:
	world.model.population = 60
	swarm.set_population(60, false)
	await _wait(0.4, 60, false)
	world.set_process(false)
	var boss: Variant = world._spawn_boss(swarm.position + Vector3(0, 0, -6.0))
	boss.state = boss.State.CHASE
	boss.emerge = 1.0
	boss.refresh_pose()
	boss.position = swarm.position + Vector3(0.6, 0, -4.4)
	boss.step(0.01, swarm.position, 1.0)
	while boss.state == boss.State.WARNING and boss.remaining > TUNING.BOSS_WARNING_SECONDS * 0.45:
		boss.step(DT, swarm.position, 1.0)
	world._update_hud("BOG KING STAMPFT · RAUS AUS DEM KREIS!")
	await _save("preview_vfx_boss_circle.png")
	while boss.state == boss.State.WARNING and boss.remaining > TUNING.BOSS_WARNING_SECONDS * 0.15:
		boss.step(DT, swarm.position, 1.0)
	await _save("preview_vfx_boss_circle_late.png")
	TG.restyle(boss.zone.material_override, "boss", true)
	await _save("preview_vfx_boss_circle_cb.png")
	TG.restyle(boss.zone.material_override, "boss", false)
	# Genauigkeit: dünner weißer Referenzring exakt auf dem Trefferradius.
	var center: Vector3 = boss.attack_center
	var probe := _reference_ring(center, TUNING.BOSS_ATTACK_RADIUS)
	# Kegel daneben: Spitze am Boss, 8 m Reichweite, 29° halbe Öffnung, zum Schwarm.
	var cone := TG.build_boss_cone(8.0, TG.CONE_DEFAULT_ANGLE)
	world.add_child(cone)
	var from: Vector3 = boss.position + Vector3(-1.5, 0, 0)
	var aim := Vector3(swarm.position.x - 5.0, 0, swarm.position.z + 4.0) - Vector3(from.x, 0, from.z)
	cone.global_position = Vector3(from.x, 0.12, from.z)
	cone.rotation.y = atan2(aim.x, aim.z)
	TG.set_progress(cone, 0.6)
	var cone_probe := _reference_arc(cone.global_position, aim.normalized(), 8.0, TG.CONE_DEFAULT_ANGLE)
	await _save("preview_vfx_boss_exact.png")
	probe.queue_free()
	cone_probe.queue_free()
	# Kegel allein, Bog King in Ruhe: frühe und späte Vorwarnzeit.
	boss.warning.visible = false
	boss.state = boss.State.CHASE
	var aim2: Vector3 = Vector3(swarm.position.x, 0, swarm.position.z) - Vector3(boss.position.x, 0, boss.position.z)
	cone.global_position = Vector3(boss.position.x, 0.12, boss.position.z)
	cone.rotation.y = atan2(aim2.x, aim2.z)
	TG.set_progress(cone, 0.75)
	world._update_hud("BOSS-KEGEL · SEITLICH AUSWEICHEN")
	await _save("preview_vfx_boss_cone.png")
	cone.queue_free()


func _reference_ring(center: Vector3, radius: float) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.03
	torus.outer_radius = radius + 0.03
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


# Umriss eines Kreissektors (Radius `reach`, halbe Öffnung `half`) als Linienzug.
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


# --- Hilfen -----------------------------------------------------------------

func _wait(seconds: float, population: int, keep_flood: bool) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame
		world.evolution.offers.clear()
		if world.model.extinct or world.model.population < population / 2:
			world.model.extinct = false
			world.model.population = population
			swarm.set_population(population, false)
		if keep_flood:
			world.flood_state = 2


func _quiet() -> void:
	for target in world.prey:
		target.queue_free()
	world.prey.clear()
	world.spawn_clock = -1000000.0
	world.hunter_clock = 1000000.0
	world.skitter_clock = 1000000.0
	world.leaper_clock = 1000000.0
	world.boss_clock = 1000000.0
	world.elite_clock = 1000000.0
	world.nest_clock = 1000000.0


func _save(file_name: String, keep := false) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://previews/" + file_name)
	if keep:
		shots.append(image)
