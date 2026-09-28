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
	_test_rank_jumps()
	_test_klauenwirbel()
	_test_giftbiss()
	_test_schallbrueller()
	_test_modifiers_and_relics()
	_test_new_evolutions()
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
	# Etappe 17: 10 Waffen mit je 5 Rängen, 6 Evolutionen.
	for id in ["rudelbiss", "sporenwolke", "saeurespucker", "stachelruecken", "graeber", "blitzbiss", "brutsack", "klauenwirbel", "giftbiss", "schallbrueller"]:
		_check(FORMS_SCRIPT.FORMS.has(id), "FORMS fehlt " + id)
		_check(FORMS_SCRIPT.FORMS[id].ranks.size() == 5, id + " braucht 5 Rangtexte")
		_check(FORMS_SCRIPT.FORMS[id].name != "", id + " ohne Namen")
	for id in ["meute", "aetzflut", "erdbeben", "sturmrudel", "pilzreich", "dornenwall"]:
		_check(FORMS_SCRIPT.FORMS.has(id) and FORMS_SCRIPT.FORMS[id].get("evolved", false), "Evolution fehlt " + id)
	for table in ["RUDELBISS_DAMAGE", "SPORE_RADIUS", "SPIT_DAMAGE", "SPINE_DAMAGE", "GRAEBER_DAMAGE", "BLITZ_TARGETS", "SAC_BITE", "CLAW_BLADES", "GIFT_DPS", "ROAR_DAMAGE"]:
		_check(((FORMS_SCRIPT as Script).get_script_constant_map()[table] as Array).size() == 5, table + " braucht 5 Ränge")


func _test_rudelbiss() -> void:
	var forms := _forms({"rudelbiss": 1})
	var near := _dummy(Vector3(3, 0, 0))
	var splash := _dummy(Vector3(3, 0, 1.2))
	var far := _dummy(Vector3(12, 0, 0))
	var targets := [near, splash, far]
	_run_for(forms, 3.0, targets, false)
	_check(_lost(near) == 0.0, "Rudelbiss darf ohne Rally nicht angreifen")
	_run_for(forms, 0.5, targets, true)
	var bite: float = FORMS_SCRIPT.RUDELBISS_DAMAGE[0]
	_check(is_equal_approx(_lost(near), bite), "Rudelbiss R1 sollte %s Schaden machen, war %s" % [bite, _lost(near)])
	_check(is_equal_approx(_lost(splash), bite), "Rudelbiss-Flächenschaden fehlt (Radius 1,6)")
	_check(_lost(far) == 0.0, "Rudelbiss traf Ziel außerhalb von 4 m")
	# Intervall R1 = RUDELBISS_INTERVAL[0] (1,8 s): bis 1,5 s kein zweiter Biss, danach ja.
	_run_for(forms, 1.0, targets, true)
	_check(is_equal_approx(_lost(near), bite), "Rudelbiss-Intervall zu kurz")
	_run_for(forms, 1.0, targets, true)
	_check(is_equal_approx(_lost(near), 2.0 * bite), "Zweiter Rudelbiss nach %s s fehlt" % FORMS_SCRIPT.RUDELBISS_INTERVAL[0])
	forms.free()
	var strong := _forms({"rudelbiss": 3})
	var victim := _dummy(Vector3(-2, 0, 2))
	_run_for(strong, 0.5, [victim], true, 2.0)
	var r3: float = FORMS_SCRIPT.RUDELBISS_DAMAGE[2] * 2.0
	_check(is_equal_approx(_lost(victim), r3), "Rudelbiss R3 × enemy_scale 2 sollte %s sein, war %s" % [r3, _lost(victim)])
	strong.free()
	_dispose([near, splash, far, victim])


func _test_meute() -> void:
	var forms := _forms({"rudelbiss": 3, "meute": 1})
	var near := _dummy(Vector3(0, 0, 3))
	var wide := _dummy(Vector3(2.0, 0, 3))
	var outside := _dummy(Vector3(3.0, 0, 3))
	var targets := [near, wide, outside]
	# Nur die erste Landung (Sprung 0,24 s); danach springt die Meute weiter.
	_run_for(forms, 0.26, targets, false)
	_check(is_equal_approx(_lost(near), FORMS_SCRIPT.MEUTE_DAMAGE), "Meute sollte ohne Rally %s Schaden machen, war %s" % [FORMS_SCRIPT.MEUTE_DAMAGE, _lost(near)])
	_check(is_equal_approx(_lost(wide), FORMS_SCRIPT.MEUTE_DAMAGE), "Meute-Radius 2,4 greift nicht")
	_check(_lost(outside) == 0.0, "Meute traf außerhalb von 2,4 m")
	_run_for(forms, 0.6, targets, false)
	_check(_lost(outside) > 0.0, "Meute springt nicht zum nächsten Ziel weiter")
	forms.free()
	var raging := _forms({"meute": 1})
	var lone := _dummy(Vector3(0, 0, -3))
	_run_for(raging, 0.26, [lone], true)
	_check(is_equal_approx(_lost(lone), FORMS_SCRIPT.MEUTE_DAMAGE * 2.0), "Meute mit Rally sollte doppelt treffen, war %s" % _lost(lone))
	raging.free()
	_dispose(targets + [lone])


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
	# Etappe 17: Rang 3 schießt je Intervall zwei Salven (0,16 s Abstand) -> 6 Treffer bis 2,9 s.
	var hits := _lost(victim) / FORMS_SCRIPT.SPIT_DAMAGE[2]
	_check(hits >= 5.0 and hits <= 6.0 and is_equal_approx(hits, roundf(hits)), "Säurespucker R3 (zwei Salven) skaliert nicht, war %s" % _lost(victim))
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
	# Ätzflut schlägt durch: der Nachbar bekommt Pfütze und höchstens einen Durchschlag.
	_check(_lost(bystander) > 0.0 and _lost(bystander) < 2.0 * FORMS_SCRIPT.SPIT_DAMAGE[4] + 4.0, "Pfütze/Durchschlag trifft den Nachbarn falsch (%s)" % _lost(bystander))
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


# --- Etappe 17 -------------------------------------------------------------

func _test_rank_jumps() -> void:
	# Rudelbiss Rang 3: der Sprung setzt zu einem zweiten Ziel fort.
	var forms := _forms({"rudelbiss": 3})
	var first := _dummy(Vector3(3, 0, 0), true)
	var second := _dummy(Vector3(6.5, 0, 0), true)
	_run_for(forms, 0.6, [first, second], true)
	_check(_lost(first) > 0.0 and _lost(second) > 0.0, "Rudelbiss R3 springt nicht zum zweiten Ziel")
	forms.free()
	# Rang 5: betäubt (slow_factor 0) kurz.
	var stunning := _forms({"rudelbiss": 5})
	var dazed := _dummy(Vector3(3, 0, 0), true)
	_run_for(stunning, 0.3, [dazed], true)
	_check(is_equal_approx(dazed.slow_factor, 0.0), "Rudelbiss R5 betäubt nicht")
	_run_for(stunning, 0.8, [], false)
	_check(is_equal_approx(dazed.slow_factor, 1.0), "Betäubung endet nicht")
	stunning.free()
	# Sporenwolke Rang 5: starke Verlangsamung.
	var spores := _forms({"sporenwolke": 5})
	_run_for(spores, 0.1, [dazed], false)
	_check(is_equal_approx(dazed.slow_factor, FORMS_SCRIPT.SPORE_SLOW[4]), "Sporenwolke R5 bremst nicht stärker")
	spores.free()
	# Säurespucker Rang 5: durchschlägt ein weiteres Ziel.
	var acid := _forms({"saeurespucker": 5})
	var front := _dummy(Vector3(4, 0, 0), true)
	var behind := _dummy(Vector3(6, 0, 0), true)
	_run_for(acid, 0.45, [front, behind], false)
	_check(_lost(front) > 0.0 and _lost(behind) > 0.0, "Säurespucker R5 durchschlägt nicht")
	acid.free()
	# Stachelrücken Rang 5: Stachelsalve auf nahe Gegner.
	var spines := _forms({"stachelruecken": 5})
	var attacker := _dummy(Vector3(1, 0, 0), true)
	var nearby := _dummy(Vector3(-3, 0, 0), true)
	spines.step(DT, [attacker, nearby], false, 1.0)
	spines.on_swarm_hit(attacker, 0)
	_run_for(spines, 0.4, [attacker, nearby], false)
	_check(is_equal_approx(_lost(nearby), FORMS_SCRIPT.SPINE_DAMAGE[4] * FORMS_SCRIPT.SPINE_VOLLEY_SHARE), "Stachelsalve R5 trifft den Nachbarn nicht (%s)" % _lost(nearby))
	spines.free()
	_dispose([first, second, dazed, front, behind, attacker, nearby])


func _test_klauenwirbel() -> void:
	var forms := _forms({"klauenwirbel": 1})
	# Kreis = Schwarmradius (25 Tiere ohne FakeSwarm: 2,65 m) + 1,2 m.
	var ring := _dummy(Vector3(3.85, 0, 0), true)
	var inside := _dummy(Vector3(0.5, 0, 0), true)
	var far := _dummy(Vector3(8, 0, 0), true)
	var targets := [ring, inside, far]
	_run_for(forms, 3.0, targets, false)
	_check(_lost(ring) >= FORMS_SCRIPT.CLAW_DAMAGE[0] * 2.0, "Klauenwirbel trifft auf dem Kreis nicht (%s)" % _lost(ring))
	_check(_lost(inside) == 0.0 and _lost(far) == 0.0, "Klauenwirbel trifft außerhalb des Kreises")
	_check(forms.get_node("Claw blades").visible, "Klingen sind nicht sichtbar")
	forms.set_ranks({"klauenwirbel": 5})
	_run_for(forms, 0.05, targets, false)
	_check(forms.get_node("Claw blades").multimesh.visible_instance_count == FORMS_SCRIPT.CLAW_BLADES[4] * FORMS_SCRIPT.CLAW_TRAIL, "Rang 5 zeigt nicht 4 Klingen")
	forms.free()
	_dispose(targets)


func _test_giftbiss() -> void:
	var forms := _forms({"giftbiss": 1})
	var a := _dummy(Vector3(3, 0, 0), true)
	var b := _dummy(Vector3(0, 0, 3.5), true)
	var c := _dummy(Vector3(-3.2, 0, 0), true)
	var far := _dummy(Vector3(9, 0, 0), true)
	var targets := [a, b, c, far]
	forms.step(DT, targets, false, 1.0)
	_check(forms.dot_count("poison") == 2 and forms.active_count("snaps") == 2, "Giftbiss R1 schnappt nicht nach 2 Zielen")
	_run_for(forms, 1.0, targets, false)
	var expected: float = FORMS_SCRIPT.GIFT_BITE[0] + FORMS_SCRIPT.GIFT_DPS[0] * 1.0
	_check(absf(_lost(a) - expected) < 0.3, "Giftbiss: Biss + 1 s Gift sollte ~%s sein, war %s" % [expected, _lost(a)])
	_check(_lost(far) == 0.0, "Giftbiss trifft zu weit")
	forms.free()
	# Rang 5: Gift springt beim Tod über.
	var spread := _forms({"giftbiss": 5})
	var weak := _dummy(Vector3(3, 0, 0), true)
	weak.health = 12.0
	var next := _dummy(Vector3(5.5, 0, 0), true)
	_run_for(spread, 0.05, [weak], false)
	_run_for(spread, 1.5, [weak, next], false)
	_check(weak.health <= 0.0 and _lost(next) > 0.0, "Gift springt bei Rang 5 nicht über")
	spread.free()
	_dispose(targets + [weak, next])


func _test_schallbrueller() -> void:
	var forms := _forms({"schallbrueller": 1})
	var front := _dummy(Vector3(4, 0, 0), true)
	var side := _dummy(Vector3(3, 0, 3.5), true)
	var back := _dummy(Vector3(-4.5, 0, 0), true)
	var targets := [front, side, back]
	forms.step(DT, targets, false, 1.0)
	_check(is_equal_approx(_lost(front), FORMS_SCRIPT.ROAR_DAMAGE[0]), "Schallbrüller trifft vorn nicht (%s / %s / %s)" % [_lost(front), _lost(side), _lost(back)])
	_check(_lost(back) == 0.0 and _lost(side) == 0.0, "Schallbrüller R1 trifft außerhalb des Kegels")
	_check(forms.active_count("roars") == 1, "Schallwelle wird nicht gezeichnet")
	_run_for(forms, 0.3, targets, false)
	_check(front.global_position.x > 4.5, "Schallbrüller wirft nicht zurück (%s)" % front.global_position.x)
	forms.free()
	var twin := _forms({"schallbrueller": 5})
	back.global_position = Vector3(-4.5, 0, 0)
	front.global_position = Vector3(4, 0, 0)
	var before_back := _lost(back)
	twin.step(DT, targets, false, 1.0)
	_check(_lost(back) > before_back and twin.active_count("roars") == 2, "Rang 5: doppelter Kegel fehlt")
	twin.free()
	_dispose(targets)


func _test_modifiers_and_relics() -> void:
	# Angriffstempo: Abklingzeit × cooldown.
	var forms := _forms({"rudelbiss": 1})
	forms.set_modifiers({"cooldown": 0.5})
	var near := _dummy(Vector3(3, 0, 0), true)
	_run_for(forms, 1.5, [near], true)
	_check(is_equal_approx(_lost(near), 2.0 * FORMS_SCRIPT.RUDELBISS_DAMAGE[0]), "Angriffstempo halbiert das Intervall nicht (%s)" % _lost(near))
	forms.free()
	# Reichweite: Aura × area.
	var aura := _forms({"sporenwolke": 1})
	aura.set_modifiers({"area": 1.5})
	var edge := _dummy(Vector3(4.2, 0, 0), true)
	_run_for(aura, 0.5, [edge], false)
	_check(_lost(edge) > 0.0, "Reichweite vergrößert die Aura nicht")
	aura.free()
	# Glutdrüse: Nahkampf-Ziele brennen.
	var burn := _forms({})
	burn.set_modifiers({"burn": 1})
	var bitten := _dummy(Vector3(2.0, 0, 0), true)
	_run_for(burn, 1.0, [bitten], false)
	_check(burn.dot_count("burn") == 1 and absf(_lost(bitten) - FORMS_SCRIPT.BURN_DPS) < 0.2, "Glutdrüse setzt keinen Brand (%s)" % _lost(bitten))
	burn.free()
	# Gewitterfell: Treffer lösen (Chance 1) einen Kettenblitz aus.
	var storm := _forms({"saeurespucker": 1})
	storm.set_modifiers({"chain_chance": 1.0})
	var hit := _dummy(Vector3(4, 0, 0), true)
	var neighbour := _dummy(Vector3(5.5, 0, 0), true)
	_run_for(storm, 0.5, [hit, neighbour], false)
	_check(float(storm.damage_dealt.get("gewitterfell", 0.0)) > 0.0 and _lost(neighbour) > 0.0, "Gewitterfell löst keinen Kettenblitz aus")
	storm.free()
	# Sporenherz: Sporenwolke am Kill-Ort.
	var puff := _forms({})
	var cloud := _dummy(Vector3(10, 0, 0), true)
	puff.step(DT, [cloud], false, 1.0)
	puff.on_kill(Vector3(10, 0, 0), true)
	_run_for(puff, 1.0, [cloud], false)
	_check(_lost(cloud) > 0.0 and cloud.slow_factor < 1.0, "Sporenwolke am Kill-Ort wirkt nicht")
	puff.free()
	_dispose([near, edge, bitten, hit, neighbour, cloud])


func _test_new_evolutions() -> void:
	var realm := _forms({"pilzreich": 1})
	var wide := _dummy(Vector3(5.5, 0, 0), true)
	_run_for(realm, 1.0, [wide], false)
	_check(absf(_lost(wide) - FORMS_SCRIPT.PILZ_DPS) < 0.5 and is_equal_approx(wide.slow_factor, FORMS_SCRIPT.PILZ_SLOW), "Pilzreich-Aura (6 m) wirkt nicht")
	realm.on_kill(Vector3(3, 0, 0), false)
	_check(realm.active_count("puffs") == 1, "Kills im Pilzreich platzen nicht als Pilzwolke")
	realm.free()
	var wall := _forms({"dornenwall": 1})
	var close := _dummy(Vector3(3.2, 0, 0), true)
	_run_for(wall, 1.0, [close], false)
	_check(absf(_lost(close) - FORMS_SCRIPT.WALL_DPS) < 0.5, "Dornenwall schadet am Ring nicht (%s)" % _lost(close))
	wall.free()
	_dispose([wide, close])


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
