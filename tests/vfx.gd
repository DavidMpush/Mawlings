extends SceneTree

# VFX-Paket V1 (scripts/vfx_sprites.gd): Pool-Grenzen, Drosselung, Ablauf,
# Einbau in die Angriffsformen und Pause/Reset in der echten Spielszene.

const VFX_SPRITES = preload("res://scripts/vfx_sprites.gd")
const FORMS_SCRIPT = preload("res://scripts/attack_forms.gd")
const TG = preload("res://scripts/telegraph_style.gd")
const DT := 1.0 / 60.0

var failures := 0


class Dummy extends Node3D:
	var health := 1000.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_pool_limits()
	_test_ember_pool()
	_test_expiry_and_clear()
	await _test_forms_hooks()
	_test_telegraphs()
	await _test_pause_and_reset()
	if failures > 0:
		push_error("vfx: %d Prüfung(en) fehlgeschlagen" % failures)
		quit(1)
		return
	print("vfx: alle Prüfungen bestanden")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("vfx: " + message)


func _test_pool_limits() -> void:
	var vfx: Node3D = VFX_SPRITES.create()
	root.add_child(vfx)
	for kind in VFX_SPRITES.KINDS:
		_check(vfx.capacity(kind) >= 2 and vfx.capacity(kind) <= int(VFX_SPRITES.KINDS[kind].cap), "%s: Kapazität %d" % [kind, vfx.capacity(kind)])
	# Drosselung: zwei Bisse im selben Moment -> der zweite wird verworfen.
	_check(vfx.spawn("bite", Vector3.ZERO), "erster Biss muss erscheinen")
	_check(not vfx.spawn("bite", Vector3(1, 0, 0)), "zweiter Biss im selben Moment muss gedrosselt werden")
	# Viele Bisse in kurzer Folge: nie mehr als die Kapazität gleichzeitig.
	for index in 400:
		vfx.step(0.031, Vector3.ZERO)
		vfx.spawn("bite", Vector3(index % 20, 0, 0))
		vfx.spawn("acid", Vector3(0, 0, index % 20))
	var bite_batch: MultiMeshInstance3D = vfx.get_node("VFX bite")
	_check(vfx.active_count("bite") <= vfx.capacity("bite"), "mehr Bisse als Kapazität: %d" % vfx.active_count("bite"))
	_check(bite_batch.multimesh.visible_instance_count <= vfx.capacity("bite"), "sichtbare Instanzen über der Kapazität")
	_check(vfx.active_count("acid") <= vfx.capacity("acid"), "mehr Säure als Kapazität")
	# Bisse leben 0,12-0,20 s: bei 31 ms Abstand also höchstens ~7 gleichzeitig.
	_check(vfx.active_count("bite") <= 8, "Bisse laufen zu lange: %d aktiv" % vfx.active_count("bite"))
	# Voll: Säure (ohne Drosselung) ersetzt die älteste statt zu wachsen.
	for index in 60:
		vfx.spawn("acid", Vector3(index, 0, 0))
	_check(vfx.active_count("acid") == vfx.capacity("acid"), "volle Säure sollte genau die Kapazität zeigen, war %d" % vfx.active_count("acid"))
	_check(not vfx.spawn("nope", Vector3.ZERO), "unbekannte Art darf nichts erzeugen")
	# Schalter für die A/B-Messung (perf_bench off=vfx) wie dort über load() gesetzt.
	var script: Variant = load("res://scripts/vfx_sprites.gd")
	script.enabled = false
	vfx.step(1.0, Vector3.ZERO)
	_check(not vfx.spawn("shock", Vector3.ZERO), "abgeschaltete VFX erzeugen trotzdem Effekte")
	script.enabled = true
	_check(vfx.spawn("shock", Vector3.ZERO), "VFX nach Wiedereinschalten stumm")
	vfx.free()


# 17d-Politur: the strain abilities' pool tints its poison sprites in ember,
# the weapons' pool keeps the painted colours.
func _test_ember_pool() -> void:
	var own: Node3D = VFX_SPRITES.create(VFX_SPRITES.ABILITY_POOL)
	var weapons: Node3D = VFX_SPRITES.create()
	for kind in ["acid", "spore"]:
		_check(is_equal_approx(own.ember_amount(kind), 1.0), "Fähigkeits-%s ohne Glut-Tönung" % kind)
		_check(is_zero_approx(weapons.ember_amount(kind)), "Waffen-%s ist getönt" % kind)
	_check(is_zero_approx(own.ember_amount("shock")), "Schockwelle der Fähigkeiten darf nicht getönt sein")
	own.free()
	weapons.free()


func _test_expiry_and_clear() -> void:
	var vfx: Node3D = VFX_SPRITES.create()
	root.add_child(vfx)
	for kind in VFX_SPRITES.KINDS:
		_check(vfx.spawn(kind, Vector3(2, 0, 3), 1.2), "%s erscheint nicht" % kind)
	_check(vfx.active_count() == VFX_SPRITES.KINDS.size(), "je Art ein Effekt erwartet")
	_check(vfx.visible_batches() == VFX_SPRITES.KINDS.size(), "je Art ein sichtbarer Batch erwartet")
	# Kürzeste Art (Biss, max 0,2 s) ist nach 0,25 s weg, die längste (DNA, 0,8 s) nicht.
	for index in 15:
		vfx.step(DT, Vector3.ZERO)
	_check(vfx.active_count("bite") == 0, "Biss nach 0,25 s nicht abgelaufen")
	_check(vfx.active_count("dna") == 1, "DNA-Leuchten zu früh abgelaufen")
	for index in 60:
		vfx.step(DT, Vector3.ZERO)
	_check(vfx.active_count() == 0, "nach 1,25 s sind noch %d Effekte aktiv" % vfx.active_count())
	_check(vfx.visible_batches() == 0, "abgelaufene Batches bleiben sichtbar (Draw Calls)")
	# Ohne step (Pause) läuft nichts ab.
	vfx.spawn("spore", Vector3.ZERO)
	var clock_before: float = vfx.clock()
	_check(vfx.active_count("spore") == 1 and vfx.clock() == clock_before, "Sporen ohne Schritt verändert")
	vfx.clear()
	_check(vfx.active_count() == 0 and vfx.visible_batches() == 0, "clear() lässt Effekte stehen")
	_check(vfx.spawn("spore", Vector3.ZERO), "nach clear() muss sofort wieder ein Effekt gehen")
	vfx.free()


func _test_forms_hooks() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var swarm := Node3D.new()
	world.add_child(swarm)
	await process_frame
	var forms: Node3D = FORMS_SCRIPT.new()
	world.add_child(forms)
	forms.setup(world, swarm)
	forms.set_ranks({"saeurespucker": 1, "graeber": 1, "giftbiss": 1})
	var vfx: Node3D = forms.vfx
	_check(vfx != null, "Angriffsformen ohne VFX-Manager")
	var target := Dummy.new()
	world.add_child(target)
	target.global_position = Vector3(3, 0, 0)
	var acid := 0
	var shock := 0
	var bite := 0
	for index in 150:
		forms.step(DT, [target], false, 1.0)
		acid = maxi(acid, vfx.active_count("acid"))
		shock = maxi(shock, vfx.active_count("shock"))
		bite = maxi(bite, vfx.active_count("bite"))
	_check(acid > 0, "Säuretreffer ohne Säure-Sprite")
	_check(shock > 0, "Gräber-Ausbruch ohne Schockwelle")
	_check(bite > 0, "Giftbiss ohne Biss-Sprite")
	forms.contact_fx(true)
	_check(vfx.active_count("bite") >= 1, "Kontaktbiss ohne Sprite")
	forms.pickup_fx(3, 1)
	_check(vfx.active_count("harvest") == 1 and vfx.active_count("dna") == 1, "Kristall-Aufnahme: ein Biomasse- und ein DNA-Sprite erwartet")
	forms.pickup_fx(3, 1)
	_check(vfx.active_count("harvest") == 1, "Biomasse-Sprite nicht zusammengefasst")
	forms.impact_fx(Vector3(1, 0, 1), 3.6)
	forms.spore_burst(Vector3(-2, 0, 0))
	_check(vfx.active_count("spore") >= 1, "Sporenherz-Wolke ohne Sporen-Sprite")
	forms.clear()
	_check(vfx.active_count() == 0 and vfx.visible_batches() == 0, "forms.clear() räumt die Effekte nicht ab")
	world.free()


func _test_telegraphs() -> void:
	var circle := TG.build("boss", 3.6)
	var mesh := circle.mesh as PlaneMesh
	# Trefferkreis der SVG (210 von 256 px) liegt genau auf dem Radius.
	_check(is_equal_approx(mesh.size.x * 0.5 * 210.0 / 256.0, 3.6), "Boss-Kreis passt nicht zum Trefferradius: %s" % mesh.size)
	var material := circle.material_override as ShaderMaterial
	_check(material != null and material.shader == TG.BOSS_SHADER, "Boss-Kreis ohne VFX-Shader")
	TG.set_progress(circle, 0.5)
	_check(is_equal_approx(float(material.get_shader_parameter("progress")), 0.5), "Fortschritt wird nicht gesetzt")
	TG.restyle(material, "boss", true)
	_check(material.get_shader_parameter("edge_color") == TG.PALETTE_COLORBLIND["boss"].edge, "Farbenblind-Palette fehlt")
	var cone := TG.build_boss_cone(8.0, 0.5094)
	var box := cone.mesh.get_aabb()
	# Spitze am Knoten, Reichweite 8 m entlang +Z (Rand der Textur liegt etwas dahinter).
	var reach_px: float = TG.CONE_REACH_PX
	_check(is_equal_approx(box.position.z, -75.0 * 8.0 / reach_px) and box.end.z > 8.0, "Boss-Kegel falsch ausgerichtet: %s" % box)
	circle.free()
	cone.free()


func _test_pause_and_reset() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var world: Node = scene.get_node("HuntWorld")
	world.set_process(false)
	var forms: Node3D = world.attack_forms
	_check(forms != null and forms.vfx != null, "HuntWorld ohne VFX-Manager")
	var vfx: Node3D = forms.vfx
	forms.pickup_fx(2, 1)
	forms.impact_fx(world.swarm.position, 3.6)
	var clock_before: float = vfx.clock()
	world.paused = true
	for index in 20:
		world.step(DT)
	_check(vfx.clock() == clock_before and vfx.active_count() >= 3, "Pause lässt Effekte weiterlaufen")
	world.paused = false
	for index in 10:
		world.step(DT)
	_check(vfx.clock() > clock_before, "Effekt-Uhr läuft nach der Pause nicht weiter")
	world.reset_run()
	await process_frame
	_check(world.attack_forms != null and world.attack_forms.vfx != null, "Reset ohne neuen VFX-Manager")
	_check(world.attack_forms.vfx.active_count() == 0, "Reset lässt Effekte stehen")
	for index in 30:
		world.step(DT)
	scene.queue_free()
	await process_frame
