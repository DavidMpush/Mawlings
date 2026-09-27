extends SceneTree

# Etappe 17: die neuen Waffen und Rangsprünge aus der echten Spielkamera.
# Ohne --headless ausführen (frame_post_draw), mit --screen 1 --audio-driver Dummy.
# Ergebnis: preview_weapons17_*.png im Projektordner (540 × 960).
#   klauenwirbel      Rang 1 (zwei Klingen) und Rang 5 (vier große Klingen)
#   giftbiss          Giftfänge schnappen zu, vergiftete Ziele mit Blasen
#   schallbrueller    Rang 3 (breiter Kegel) und Rang 5 (doppelter Kegel)
#   rudelbiss_r5      Doppelsprung mit Betäubung
#   graeber_r3        zwei Tunnelstöße
#   pilzreich         Evolution: große Aura mit Pilzwolken
#   dornenwall        Evolution: Dornenring
#   glut              Relikt Glutdrüse: brennende Gegner am Schwarm

const FORMS_SCRIPT = preload("res://scripts/attack_forms.gd")
const DT := 1.0 / 60.0

var scene: Node
var world: Node3D
var swarm: Node3D
var forms: Node3D


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	# Background capture windows lose focus; the auto-pause must not end up in the frames.
	var controls: Node = scene.get_node("HUD/Controls")
	if controls.pause_requested.is_connected(world.toggle_pause):
		controls.pause_requested.disconnect(world.toggle_pause)
	world.model.population = 40
	swarm.set_population(40, false)
	for i in 40:
		await process_frame
	if world.paused:
		world.toggle_pause()
	world._update_hud("")
	scene.set_process(false)
	world.set_process(false)
	if world.attack_forms != null:
		world.attack_forms.clear()
		world.attack_forms.set_ranks({})
	forms = FORMS_SCRIPT.new()
	forms.name = "AttackForms17"
	world.add_child(forms)
	forms.setup(world, swarm)
	var origin: Vector3 = swarm.position

	# Klauenwirbel Rang 1 und 5.
	var targets := _place([Vector3(3.6, 0, -1.8), Vector3(-3.4, 0, 2.2), Vector3(0.8, 0, -4.2)], origin)
	forms.set_ranks({"klauenwirbel": 1})
	_step(0.5, targets, false)
	await _save("res://preview_weapons17_klauenwirbel.png")
	forms.clear()
	forms.set_ranks({"klauenwirbel": 5})
	_step(0.6, targets, false)
	await _save("res://preview_weapons17_klauenwirbel_r5.png")

	# Giftbiss Rang 3: Fänge schnappen, vergiftete Ziele blubbern.
	forms.clear()
	targets = _place([Vector3(3.3, 0, -1.0), Vector3(-2.8, 0, -2.4), Vector3(1.0, 0, 3.4), Vector3(6.5, 0, -5.0)], origin)
	forms.set_ranks({"giftbiss": 3})
	_step(0.12, targets, false)
	await _save("res://preview_weapons17_giftbiss.png")
	_step(0.9, targets, false)
	await _save("res://preview_weapons17_giftbiss_poison.png")

	# Schallbrüller Rang 3 und Rang 5 (doppelter Kegel).
	forms.clear()
	targets = _place([Vector3(0.6, 0, -4.6), Vector3(-1.4, 0, -6.0), Vector3(1.6, 0, 5.2)], origin)
	forms.set_ranks({"schallbrueller": 3})
	_step(0.16, targets, false)
	await _save("res://preview_weapons17_schallbrueller.png")
	forms.clear()
	targets = _place([Vector3(0.6, 0, -4.6), Vector3(-1.4, 0, -6.0), Vector3(1.6, 0, 5.2)], origin)
	forms.set_ranks({"schallbrueller": 5})
	_step(0.18, targets, false)
	await _save("res://preview_weapons17_schallbrueller_r5.png")

	# Rudelbiss Rang 5: zweiter Sprung mit Betäubung.
	forms.clear()
	targets = _place([Vector3(3.0, 0, -1.2), Vector3(5.8, 0, -3.6)], origin)
	forms.set_ranks({"rudelbiss": 5})
	_step(0.36, targets, true)
	await _save("res://preview_weapons17_rudelbiss_r5.png")

	# Gräber Rang 3: zwei Tunnel.
	forms.clear()
	targets = _place([Vector3(-5.0, 0, -7.0), Vector3(5.5, 0, -6.0), Vector3(1.8, 0, 1.2)], origin)
	forms.set_ranks({"graeber": 3})
	_step(0.3, targets, false)
	await _save("res://preview_weapons17_graeber_r3.png")

	# Pilzreich: große Aura, Kills platzen als Pilzwolke.
	forms.clear()
	targets = _place([Vector3(4.5, 0, -2.0), Vector3(-4.0, 0, 3.0), Vector3(1.0, 0, -5.4)], origin)
	forms.set_ranks({"pilzreich": 1})
	_step(0.8, targets, false)
	forms.on_kill(origin + Vector3(3.5, 0, 2.5), false)
	forms.on_kill(origin + Vector3(-3.0, 0, -3.0), false)
	_step(0.3, targets, false)
	await _save("res://preview_weapons17_pilzreich.png")

	# Dornenwall: Dornenring um den Schwarm.
	forms.clear()
	targets = _place([Vector3(3.6, 0, -1.2), Vector3(-2.0, 0, 3.2)], origin)
	forms.set_ranks({"dornenwall": 1})
	_step(0.6, targets, false)
	await _save("res://preview_weapons17_dornenwall.png")

	# Glutdrüse: brennende Ziele am Schwarmrand, dazu Giftbiss.
	forms.clear()
	targets = _place([Vector3(2.8, 0, -1.5), Vector3(-2.6, 0, 1.8), Vector3(0.5, 0, 3.0)], origin)
	forms.set_ranks({"giftbiss": 1})
	forms.set_modifiers({"burn": 1})
	_step(1.0, targets, false)
	await _save("res://preview_weapons17_glut.png")
	print("Saved stage 17 weapon frames")
	quit()


func _place(offsets: Array, origin: Vector3) -> Array:
	for hunter in world.hunters.duplicate():
		world.hunters.erase(hunter)
		hunter.free()
	var result: Array = []
	for offset in offsets:
		var hunter: Node3D = world._spawn_hunter(origin + offset)
		hunter.state = hunter.State.CHASE
		hunter.warning.visible = false
		hunter.health = 1000.0
		hunter.max_health = 1000.0
		result.append(hunter)
	return result


func _step(seconds: float, targets: Array, rally: bool) -> void:
	for i in int(round(seconds / DT)):
		forms.step(DT, targets, rally, 1.0)


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
