extends SceneTree

# Headless-Test der Angriffsformen mit eigener Minimalszene (ohne main.tscn).

const FORMS_SCRIPT = preload("res://scripts/attack_forms.gd")
const DT := 1.0 / 60.0

var failures := 0
var world: Node3D
var swarm: Node3D


class Dummy extends Node3D:
	var health := 1000.0


class Brute extends Node3D:
	var health := 1000.0
	var slow_factor := 1.0
	var hits := 0

	func take_damage(amount: float) -> void:
		health -= amount
		hits += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	world = Node3D.new()
	world.name = "world"
	root.add_child(world)
	swarm = Node3D.new()
	swarm.name = "swarm"
	world.add_child(swarm)
	await process_frame
	_test_catalog()
	_test_rudelbiss()
	_test_meute()
	_test_spores()
	_test_spit()
	_test_aetzflut()
	_test_spines()
	await _test_freeze_and_clear()
	await _test_invalid_targets()
	if failures > 0:
		push_error("attack_forms: %d Prüfung(en) fehlgeschlagen" % failures)
		quit(1)
		return
	print("attack_forms: alle Prüfungen bestanden")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FEHLER: " + message)


func _forms(ranks: Dictionary) -> Node3D:
	var forms: Node3D = FORMS_SCRIPT.new()
	world.add_child(forms)
	forms.setup(world, swarm)
	forms.set_ranks(ranks)
	return forms


func _dummy(location: Vector3, brute := false) -> Node3D:
	var target: Node3D = Brute.new() if brute else Dummy.new()
	world.add_child(target)
	target.global_position = location
	return target


func _run_for(forms: Node3D, seconds: float, targets: Array, rally: bool, scale := 1.0) -> void:
	for i in int(round(seconds / DT)):
		forms.step(DT, targets, rally, scale)


func _lost(target: Node3D) -> float:
	return 1000.0 - float(target.get("health"))


func _dispose(nodes: Array) -> void:
	for node in nodes:
		if is_instance_valid(node):
			node.free()


func _test_catalog() -> void:
	for id in ["rudelbiss", "sporenwolke", "saeurespucker", "stachelruecken"]:
		_check(FORMS_SCRIPT.FORMS.has(id), "FORMS fehlt " + id)
		_check(FORMS_SCRIPT.FORMS[id].ranks.size() == 3, id + " braucht 3 Rangtexte")
		_check(FORMS_SCRIPT.FORMS[id].name != "", id + " ohne Namen")
	for id in ["meute", "aetzflut"]:
		_check(FORMS_SCRIPT.FORMS.has(id) and FORMS_SCRIPT.FORMS[id].get("evolved", false), "Evolution fehlt " + id)


func _test_rudelbiss() -> void:
	var forms := _forms({"rudelbiss": 1})
	var near := _dummy(Vector3(3, 0, 0))
	var splash := _dummy(Vector3(3, 0, 1.2))
	var far := _dummy(Vector3(12, 0, 0))
	var targets := [near, splash, far]
	_run_for(forms, 3.0, targets, false)
	_check(_lost(near) == 0.0, "Rudelbiss darf ohne Rally nicht angreifen")
	_run_for(forms, 0.5, targets, true)
	_check(is_equal_approx(_lost(near), 8.0), "Rudelbiss R1 sollte 8 Schaden machen, war %s" % _lost(near))
	_check(is_equal_approx(_lost(splash), 8.0), "Rudelbiss-Flächenschaden fehlt (Radius 1,6)")
	_check(_lost(far) == 0.0, "Rudelbiss traf Ziel außerhalb von 4 m")
	# Intervall R1 = 2,2 s: bis 2,0 s kein zweiter Biss, danach ja.
	_run_for(forms, 1.5, targets, true)
	_check(is_equal_approx(_lost(near), 8.0), "Rudelbiss-Intervall zu kurz")
	_run_for(forms, 1.0, targets, true)
	_check(is_equal_approx(_lost(near), 16.0), "Zweiter Rudelbiss nach 2,2 s fehlt")
	forms.free()
	var strong := _forms({"rudelbiss": 3})
	var victim := _dummy(Vector3(-2, 0, 2))
	_run_for(strong, 0.5, [victim], true, 2.0)
	_check(is_equal_approx(_lost(victim), 32.0), "Rudelbiss R3 × enemy_scale 2 sollte 32 sein, war %s" % _lost(victim))
	strong.free()
	_dispose([near, splash, far, victim])


func _test_meute() -> void:
	var forms := _forms({"rudelbiss": 3, "meute": 1})
	var near := _dummy(Vector3(0, 0, 3))
	var wide := _dummy(Vector3(2.0, 0, 3))
	var outside := _dummy(Vector3(3.0, 0, 3))
	var targets := [near, wide, outside]
	_run_for(forms, 0.5, targets, false)
	_check(is_equal_approx(_lost(near), 16.0), "Meute sollte ohne Rally 16 Schaden machen, war %s" % _lost(near))
	_check(is_equal_approx(_lost(wide), 16.0), "Meute-Radius 2,4 greift nicht")
	_check(_lost(outside) == 0.0, "Meute traf außerhalb von 2,4 m")
	_run_for(forms, 1.2, targets, true)
	_check(is_equal_approx(_lost(near), 48.0), "Meute mit Rally sollte doppelt (32) treffen, gesamt %s" % _lost(near))
	forms.free()
	_dispose(targets)


func _test_spores() -> void:
	var forms := _forms({"sporenwolke": 1})
	var inside := _dummy(Vector3(2.5, 0, 0), true)
	var outside := _dummy(Vector3(0, 0, 3.5), true)
	var targets := [inside, outside]
	_run_for(forms, 1.0, targets, false)
	_check(absf(_lost(inside) - FORMS_SCRIPT.SPORE_DPS[0]) < 0.05, "Sporenwolke R1 sollte ~%s Schaden/s machen, war %s" % [FORMS_SCRIPT.SPORE_DPS[0], _lost(inside)])
	_check(_lost(outside) == 0.0, "Sporenwolke traf außerhalb von 3 m")
	_check(is_equal_approx(inside.slow_factor, 0.6), "Sporenwolke verlangsamt nicht")
	_check(is_equal_approx(outside.slow_factor, 1.0), "Außerhalb darf nicht verlangsamt werden")
	inside.global_position = Vector3(6, 0, 0)
	_run_for(forms, 0.1, targets, false)
	_check(is_equal_approx(inside.slow_factor, 1.0), "Verlangsamung wird beim Verlassen nicht aufgehoben")
	forms.set_ranks({"sporenwolke": 3})
	_run_for(forms, 1.0, targets, false)
	_check(absf(_lost(outside) - FORMS_SCRIPT.SPORE_DPS[2]) < 0.05, "Sporenwolke R3 (4,2 m, %s/s) greift nicht, war %s" % [FORMS_SCRIPT.SPORE_DPS[2], _lost(outside)])
	forms.clear()
	_check(is_equal_approx(outside.slow_factor, 1.0), "clear() hebt Verlangsamung nicht auf")
	forms.free()
	_dispose(targets)


func _test_spit() -> void:
	var forms := _forms({"saeurespucker": 1})
	var near := _dummy(Vector3(0, 0, -8))
	var far := _dummy(Vector3(9.5, 0, 0))
	var targets := [near, far]
	forms.step(DT, targets, false, 1.0)
	_check(forms.active_projectiles() == 1, "Säurespucker feuert kein Projektil")
	_run_for(forms, 1.0, targets, false)
	_check(is_equal_approx(_lost(near), FORMS_SCRIPT.SPIT_DAMAGE[0]), "Säurespucker R1 sollte %s Schaden machen, war %s" % [FORMS_SCRIPT.SPIT_DAMAGE[0], _lost(near)])
	_check(_lost(far) == 0.0, "Säurespucker traf außerhalb von 9 m")
	_check(forms.active_puddles() == 0, "Ohne Ätzflut darf keine Pfütze entstehen")
	forms.free()
	var fast := _forms({"saeurespucker": 3})
	var victim := _dummy(Vector3(3, 0, 0))
	_run_for(fast, 2.9, [victim], false)
	# R3: Schüsse alle SPIT_INTERVAL[2] s ab 0, Flugzeit 3 m / SPIT_SPEED -> nur Treffer bis 2,9 s zählen.
	var shots := int(floor((2.9 - 3.0 / FORMS_SCRIPT.SPIT_SPEED) / FORMS_SCRIPT.SPIT_INTERVAL[2])) + 1
	_check(is_equal_approx(_lost(victim), shots * FORMS_SCRIPT.SPIT_DAMAGE[2]), "Säurespucker R3 skaliert nicht, war %s" % _lost(victim))
	fast.free()
	_dispose([near, far, victim])


func _test_aetzflut() -> void:
	var forms := _forms({"saeurespucker": 3, "aetzflut": 1})
	var victim := _dummy(Vector3(4, 0, 0), true)
	var bystander := _dummy(Vector3(4, 0, 0.9), true)
	var outside := _dummy(Vector3(4, 0, 2.5), true)
	var targets := [victim, bystander, outside]
	_run_for(forms, 0.4, targets, false)
	_check(forms.active_puddles() >= 1, "Ätzflut hinterlässt keine Pfütze")
	_check(_lost(bystander) > 0.0 and _lost(bystander) < 12.0, "Pfütze schadet Nachbarn im Radius 1,2 nicht")
	_check(_lost(outside) == 0.0, "Pfütze traf außerhalb von 1,2 m")
	_check(float(forms.damage_dealt.get("aetzflut", 0.0)) > 0.0, "Ätzflut-Schaden wird nicht verbucht")
	_run_for(forms, 3.0, [], false)
	_check(forms.active_puddles() == 0, "Pfütze verschwindet nicht nach 2 s")
	forms.free()
	_dispose(targets)


func _test_spines() -> void:
	var idle := _forms({})
	var attacker := _dummy(Vector3(1, 0, 1), true)
	idle.on_swarm_hit(attacker, 3)
	_check(_lost(attacker) == 0.0, "Ohne Stachelrücken kein Rückstoß")
	idle.free()
	var forms := _forms({"stachelruecken": 2})
	forms.on_swarm_hit(attacker, 3)
	var spine_r2: float = FORMS_SCRIPT.SPINE_DAMAGE[1] + 3.0 * FORMS_SCRIPT.SPINE_PER_LOSS
	_check(is_equal_approx(_lost(attacker), spine_r2), "Stachelrücken R2 + 3 Verluste sollte %s sein, war %s" % [spine_r2, _lost(attacker)])
	forms.step(DT, [], false, 1.5)
	forms.on_swarm_hit(attacker, 0)
	_check(is_equal_approx(_lost(attacker), spine_r2 + FORMS_SCRIPT.SPINE_DAMAGE[1] * 1.5), "Stachelrücken nutzt enemy_scale nicht")
	forms.on_swarm_hit(null, 5)
	forms.free()
	var top := _forms({"stachelruecken": 3})
	var second := _dummy(Vector3(-1, 0, 0))
	top.on_swarm_hit(second, 1)
	_check(is_equal_approx(_lost(second), FORMS_SCRIPT.SPINE_DAMAGE[2] + FORMS_SCRIPT.SPINE_PER_LOSS), "Stachelrücken R3 sollte SPINE_DAMAGE[2] + SPINE_PER_LOSS sein")
	top.free()
	_dispose([attacker, second])


func _test_freeze_and_clear() -> void:
	var forms := _forms({"saeurespucker": 1, "sporenwolke": 1, "rudelbiss": 1, "stachelruecken": 1})
	var target := _dummy(Vector3(0, 0, -7))
	var biter := _dummy(Vector3(2, 0, 0))
	var targets := [target, biter]
	forms.step(DT, targets, true, 1.0)
	forms.on_swarm_hit(biter, 1)
	_run_for(forms, 0.1, targets, true)
	_check(forms.active_projectiles() == 1, "Projektil sollte im Flug sein")
	var snapshot := _snapshot(forms, targets)
	for i in 10:
		await process_frame
	_check(snapshot == _snapshot(forms, targets), "Ohne step() haben sich Effekte oder Gesundheit verändert")
	forms.clear()
	_check(forms.active_projectiles() == 0, "clear() entfernt Projektile nicht")
	_check(forms.active_effects() == 0, "clear() entfernt Effekte nicht")
	var visible := 0
	for node in forms.find_children("*", "MeshInstance3D", true, false):
		if node.is_visible_in_tree():
			visible += 1
	_check(visible == 0, "Nach clear() sind noch %d Effekt-Meshes sichtbar" % visible)
	forms.free()
	_dispose(targets)


func _snapshot(forms: Node3D, targets: Array) -> Array:
	var values: Array = []
	for target in targets:
		values.append(target.get("health"))
	for node in forms.find_children("*", "MeshInstance3D", true, false):
		values.append(node.global_transform)
		values.append(node.visible)
		var material := node.material_override as StandardMaterial3D
		if material != null:
			values.append(material.albedo_color)
	return values


func _test_invalid_targets() -> void:
	var forms := _forms({"saeurespucker": 2, "sporenwolke": 1, "rudelbiss": 1})
	var doomed := _dummy(Vector3(0, 0, 2))
	doomed.health = 3.0
	var gone := _dummy(Vector3(1, 0, 1))
	var targets := [doomed, gone]
	forms.step(DT, targets, true, 1.0)
	gone.free()
	_run_for(forms, 1.5, targets, true)
	_check(is_instance_valid(doomed) and not doomed.is_queued_for_deletion(), "Angriffsformen dürfen Ziele nie freigeben")
	_check(doomed.health <= 0.0, "Schwaches Ziel sollte auf 0 Gesundheit fallen")
	var dead_health: float = doomed.health
	_run_for(forms, 1.0, targets, true)
	_check(doomed.health == dead_health, "Tote Ziele (health <= 0) werden weiter beschädigt")
	forms.free()
	_dispose([doomed])
