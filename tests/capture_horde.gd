extends SceneTree

# Bilder der Moorbrut aus der echten Spielkamera (ohne --headless ausführen):
#   preview_horde_ring.png     – Welle läuft aus dem Ring auf den Schwarm zu
#   preview_horde_contact.png  – Brut umringt den Schwarm und schnappt zu
#   preview_horde_spores.png   – Sporenwolke R3 räumt die Brut (Todes-Effekte)
#   preview_horde_after.png    – danach: Rest der Brut, Schwarm frei
# Die Horde wird hier selbst getaktet (HuntWorld pausiert), damit die Bilder
# unabhängig von Flut-Zeitpunkt und Zufall sind.

const HORDE_SCRIPT = preload("res://scripts/horde.gd")
const DT := 1.0 / 60.0
const STATS := {"hp": 24.0, "speed": 4.6, "bite": 1.0, "bite_cooldown": 1.1}

var scene: Node
var world: Node3D
var swarm: Node3D
var horde: Node3D
var forms: Node3D


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	var controls: Node = scene.get_node("HUD/Controls")
	# Hintergrundfenster verlieren den Fokus; die Auto-Pause darf nicht ins Bild.
	if controls.pause_requested.is_connected(world.toggle_pause):
		controls.pause_requested.disconnect(world.toggle_pause)
	# UI-Einblendung abwarten.
	await create_timer(1.2).timeout
	world.set_process(false)
	var integrated: Variant = world.get("horde")
	if integrated is Node and is_instance_valid(integrated):
		integrated.clear()
	for enemy in world.get("prey"):
		(enemy as Node3D).visible = false
	world.model.population = 70
	swarm.set_population(70, false)
	horde = HORDE_SCRIPT.new()
	horde.name = "Horde capture"
	world.add_child(horde)
	horde.setup(world, swarm, scene.get_node("Arena"))
	forms = world.get("attack_forms")
	await create_timer(0.6).timeout

	horde.spawn_ring(swarm.position, 60, 9.5, STATS)
	horde.spawn_ring(swarm.position, 40, 12.5, STATS)
	await _run(0.45, false)
	await _save("preview_horde_ring.png")
	await _run(1.6, false)
	await _save("preview_horde_contact.png")
	if forms != null and forms.has_method("set_horde"):
		forms.set_horde(horde)
		forms.set_ranks({"sporenwolke": 3, "saeurespucker": 3})
	await _run(1.35, true)
	await _save("preview_horde_spores.png")
	await _run(1.8, true)
	await _save("preview_horde_after.png")
	print("Saved horde review frames: %d Brut übrig, %d getötet" % [horde.count(), horde.total_kills])
	quit()


# Echte Frames, feste Schritte: Horde (Bisse nur als Effekt), optional Formen.
func _run(seconds: float, with_forms: bool) -> void:
	for frame in int(round(seconds / DT)):
		var points: PackedVector3Array = swarm.unit_world_points()
		horde.melee(points, 1.6, 6.0, DT)
		horde.step(DT, points)
		if with_forms and forms != null:
			forms.step(DT, [], false, 1.0)
		horde.take_kills()
		await process_frame


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + file_name)
