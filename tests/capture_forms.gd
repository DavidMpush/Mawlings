extends SceneTree

# Bilder der Angriffsformen aus der echten Spielkamera (ohne --headless ausführen).
# Ergebnis: preview_forms_*.png im Projektordner.

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
	# Einige Frames laufen lassen, damit sich der Schwarm natürlich verteilt.
	for i in 20:
		await process_frame
	scene.set_process(false)
	world.set_process(false)
	forms = FORMS_SCRIPT.new()
	forms.name = "AttackForms"
	world.add_child(forms)
	forms.setup(world, swarm)
	var origin: Vector3 = swarm.position

	# 1) Rudelbiss: Sprungbogen im Flug und Aufprall auf zwei Jäger.
	var targets := _place([Vector3(3.2, 0, -1.2), Vector3(4.2, 0, 0.2)], origin)
	forms.set_ranks({"rudelbiss": 2})
	_step(0.13, targets, true)
	await _save("res://preview_forms_rudelbiss.png")
	_step(0.16, targets, true)
	await _save("res://preview_forms_rudelbiss_impact.png")

	# 2) Sporenwolke R3 mit Jägern innerhalb und außerhalb.
	forms.clear()
	targets = _place([Vector3(-2.6, 0, -2.0), Vector3(3.0, 0, 1.8), Vector3(6.5, 0, -3.5)], origin)
	forms.set_ranks({"sporenwolke": 3})
	_step(1.4, targets, false)
	await _save("res://preview_forms_sporenwolke.png")

	# 3) Säurespucker R3: zwei Projektile im Flug.
	forms.clear()
	targets = _place([Vector3(-5.5, 0, -5.0), Vector3(6.0, 0, -4.0)], origin)
	forms.set_ranks({"saeurespucker": 3})
	_step(0.75, targets, false)
	await _save("res://preview_forms_saeurespucker.png")

	# 4) Ätzflut: Pfützen nach Treffern.
	forms.clear()
	forms.set_ranks({"saeurespucker": 3, "aetzflut": 1})
	_step(1.55, targets, false)
	await _save("res://preview_forms_aetzflut.png")

	# 5) Stachelrücken: Burst direkt nach einem Treffer.
	forms.clear()
	targets = _place([Vector3(2.2, 0, -1.4)], origin)
	forms.set_ranks({"stachelruecken": 3})
	forms.on_swarm_hit(targets[0], 2)
	_step(0.14, targets, false)
	await _save("res://preview_forms_stachelruecken.png")

	# 6) Meute + Sporenwolke kombiniert (spätere Runde).
	forms.clear()
	targets = _place([Vector3(-3.0, 0, 1.5), Vector3(3.2, 0, -2.2), Vector3(-1.0, 0, -3.4)], origin)
	forms.set_ranks({"rudelbiss": 3, "meute": 1, "sporenwolke": 2})
	_step(1.34, targets, false)
	await _save("res://preview_forms_kombi.png")
	print("Saved attack form review frames")
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
