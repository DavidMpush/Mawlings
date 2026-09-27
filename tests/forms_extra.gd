extends SceneTree

# Etappe 10 (INHALT): neue Angriffsformen Gräber, Blitzbiss, Brutsack, die
# Evolutionen Erdbeben und Sturmrudel sowie die Anlagen Regeneration und
# Dornenhaut. Eigene Minimalszene mit Attrappen für Schwarm und Moorbrut.

const FORMS_SCRIPT = preload("res://scripts/attack_forms.gd")
const EVOLUTION = preload("res://scripts/evolution.gd")
const DATA = preload("res://scripts/meta/meta_data.gd")
const ICONS = preload("res://scripts/ui/ui_icons.gd")
const DT := 1.0 / 60.0
const NEW_FORMS := ["graeber", "blitzbiss", "brutsack"]
const NEW_EVOLVED := ["erdbeben", "sturmrudel"]
const NEW_TRAITS := ["regeneration", "dornenhaut"]

var failures := 0
var world: Node3D
var swarm: Node3D


class Brute extends Node3D:
	var health := 1000.0
	var slow_factor := 1.0

	func take_damage(amount: float) -> void:
		health -= amount


class FakeSwarm extends Node3D:
	var population := 25


# Minimal-Moorbrut mit derselben Treffer-API wie scripts/horde.gd.
class FakeHorde extends Node3D:
	var pos: Array[Vector3] = []
	var hp: Array[float] = []
	var last_hit_count := 0

	func add(at: Vector3, health := 1000.0) -> int:
		pos.append(at)
		hp.append(health)
		return pos.size() - 1

	func lost(index: int) -> float:
		return 1000.0 - hp[index]

	func count() -> int:
		var alive := 0
		for value in hp:
			if value > 0.0:
				alive += 1
		return alive

	func positions() -> PackedVector3Array:
		var result := PackedVector3Array()
		for i in pos.size():
			if hp[i] > 0.0:
				result.append(pos[i])
		return result

	func _d(a: Vector3, b: Vector3) -> float:
		return Vector2(a.x - b.x, a.z - b.z).length()

	func nearest(point: Vector3) -> Vector3:
		var best := Vector3.INF
		var best_d := INF
		for i in pos.size():
			if hp[i] > 0.0 and _d(pos[i], point) < best_d:
				best_d = _d(pos[i], point)
				best = pos[i]
		return best

	func damage_circle(center: Vector3, radius: float, amount: float) -> int:
		last_hit_count = 0
		for i in pos.size():
			if hp[i] > 0.0 and _d(pos[i], center) <= radius:
				hp[i] -= amount
				last_hit_count += 1
		return 0

	func damage_nearest(point: Vector3, max_range: float, amount: float) -> Vector3:
		last_hit_count = 0
		var best := -1
		var best_d := max_range
		for i in pos.size():
			if hp[i] > 0.0 and _d(pos[i], point) <= best_d:
				best_d = _d(pos[i], point)
				best = i
		if best < 0:
			return Vector3.INF
		hp[best] -= amount
		last_hit_count = 1
		return pos[best]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	world = Node3D.new()
	world.name = "world"
	root.add_child(world)
	swarm = FakeSwarm.new()
	swarm.name = "swarm"
	world.add_child(swarm)
	await process_frame
	_test_catalog()
	_test_graeber()
	_test_graeber_horde()
	_test_erdbeben()
	_test_blitzbiss()
	_test_blitzbiss_horde()
	_test_sturmrudel()
	_test_brutsack()
	_test_brutsack_horde_and_population()
	_test_evolution_rules()
	_test_regeneration()
	_test_dornenhaut()
	await _test_clear()
	if failures > 0:
		push_error("forms_extra: %d Prüfung(en) fehlgeschlagen" % failures)
		quit(1)
		return
	print("forms_extra: alle Prüfungen bestanden")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FEHLER: " + message)


func _near(a: float, b: float, tolerance := 0.01) -> bool:
	return absf(a - b) <= tolerance


func _forms(ranks: Dictionary, horde: Node3D = null) -> Node3D:
	var forms: Node3D = FORMS_SCRIPT.new()
	world.add_child(forms)
	forms.setup(world, swarm)
	forms.set_ranks(ranks)
	if horde != null:
		forms.set_horde(horde)
	return forms


func _horde() -> FakeHorde:
	var horde := FakeHorde.new()
	world.add_child(horde)
	return horde


func _brute(location: Vector3) -> Node3D:
	var target := Brute.new()
	world.add_child(target)
	target.global_position = location
	return target


func _run_for(forms: Node3D, seconds: float, targets: Array, rally := false, scale := 1.0) -> void:
	for i in int(round(seconds / DT)):
		forms.step(DT, targets, rally, scale)


func _lost(target: Node3D) -> float:
	return 1000.0 - float(target.get("health"))


func _dispose(nodes: Array) -> void:
	for node in nodes:
		if is_instance_valid(node):
			node.free()


func _test_catalog() -> void:
	for id in NEW_FORMS:
		_check(FORMS_SCRIPT.FORMS.has(id), "FORMS fehlt " + id)
		_check(FORMS_SCRIPT.FORMS[id].ranks.size() == 3, id + " braucht 3 Rangtexte")
		_check(EVOLUTION.new().kind_of(id) == "attack", id + " ist keine Angriffsform in evolution.gd")
		_check(DATA.MUTATION_NAMES.has(id), id + " fehlt in MUTATION_NAMES")
	for id in NEW_EVOLVED:
		_check(FORMS_SCRIPT.FORMS.has(id) and FORMS_SCRIPT.FORMS[id].get("evolved", false), "Evolution fehlt " + id)
		_check(EVOLUTION.new().kind_of(id) == "evolved", id + " ist keine Evolution in evolution.gd")
	for id in NEW_TRAITS:
		_check(EVOLUTION.new().kind_of(id) == "trait", id + " ist keine Anlage")
		_check(DATA.MUTATION_NAMES.has(id), id + " fehlt in MUTATION_NAMES")
	for id in NEW_FORMS + NEW_EVOLVED + NEW_TRAITS:
		_check(ICONS.IDS.has(id), "Icon-ID fehlt: " + id)
		_check(ResourceLoader.exists(ICONS.path(id)), "Icon-Datei fehlt: " + id)
	# Freischaltung nur über Trophäen, Start-Pool unverändert.
	var unlocks := {}
	for quest in DATA.QUESTS:
		for token in quest.reward.get("unlock", []):
			unlocks[token] = quest.id
	for id in NEW_FORMS + NEW_TRAITS:
		_check(unlocks.has("mutation:" + id), "Keine Trophäe schaltet %s frei" % id)
		_check(not DATA.START_ATTACKS.has(id) and not DATA.TRAIT_IDS.has(id), "%s darf nicht im Start-Pool sein" % id)
		_check(not EVOLUTION.new().pool.has(id), "%s darf nicht im Standard-Pool sein" % id)
	for id in NEW_EVOLVED:
		_check(not DATA.quest("evo_" + id).is_empty(), "Evolutions-Trophäe fehlt: " + id)


func _test_graeber() -> void:
	var forms := _forms({"graeber": 1})
	var near := _brute(Vector3(3, 0, 0))
	var far := _brute(Vector3(-9, 0, 0))
	var outside := _brute(Vector3(0, 0, 10.5))
	var targets := [near, far, outside]
	forms.step(DT, targets, false, 1.0)
	_check(forms.active_count("tunnels") == 1, "Gräber gräbt keinen Tunnel")
	_run_for(forms, 3.0, targets)
	_check(_near(_lost(far), FORMS_SCRIPT.GRAEBER_DAMAGE[0]), "Gräber R1 sollte den entferntesten Gegner mit %s treffen, war %s" % [FORMS_SCRIPT.GRAEBER_DAMAGE[0], _lost(far)])
	_check(_lost(near) == 0.0, "Gräber traf den nahen Gegner statt des entferntesten")
	_check(_lost(outside) == 0.0, "Gräber traf außerhalb von 10 m")
	_check(float(forms.damage_dealt.get("graeber", 0.0)) > 0.0, "Gräber-Schaden wird nicht verbucht")
	forms.free()
	# Rang 3: 12 m Reichweite, 19 Schaden, Fläche 2,2 m.
	var strong := _forms({"graeber": 3})
	var distant := _brute(Vector3(11.5, 0, 0))
	var splash := _brute(Vector3(11.5, 0, 2.0))
	_run_for(strong, 1.5, [distant, splash])
	_check(_near(_lost(distant), FORMS_SCRIPT.GRAEBER_DAMAGE[2]), "Gräber R3 (12 m, 19) greift nicht, war %s" % _lost(distant))
	_check(_near(_lost(splash), FORMS_SCRIPT.GRAEBER_DAMAGE[2]), "Gräber R3-Flächenschaden (2,2 m) fehlt")
	strong.free()
	_dispose(targets + [distant, splash])


func _test_graeber_horde() -> void:
	var horde := _horde()
	var inside := horde.add(Vector3(0, 0, 8))
	var beyond := horde.add(Vector3(0, 0, -13))
	var forms := _forms({"graeber": 1}, horde)
	_run_for(forms, 2.0, [])
	_check(_near(horde.lost(inside), FORMS_SCRIPT.GRAEBER_DAMAGE[0]), "Gräber trifft Brut in Reichweite nicht, war %s" % horde.lost(inside))
	_check(horde.lost(beyond) == 0.0, "Gräber traf Brut außerhalb von 10 m")
	_check(float(forms.damage_dealt.get("graeber", 0.0)) > 0.0, "Gräber-Brutschaden wird nicht verbucht")
	forms.free()
	horde.free()


func _test_erdbeben() -> void:
	var forms := _forms({"graeber": 3, "erdbeben": 1})
	var a := _brute(Vector3(5, 0, 0))
	var b := _brute(Vector3(-7, 0, 0))
	var c := _brute(Vector3(0, 0, 9))
	var d := _brute(Vector3(0, 0, -3))
	var targets := [a, b, c, d]
	_run_for(forms, 1.3, targets)
	var full: float = FORMS_SCRIPT.GRAEBER_DAMAGE[2] * (1.0 + FORMS_SCRIPT.QUAKE_AFTERSHOCK)
	for target in [a, b, c]:
		_check(_near(_lost(target), full), "Erdbeben: drei Stöße mit Nachbeben sollten %s machen, war %s" % [full, _lost(target)])
	_check(_lost(d) == 0.0, "Erdbeben sollte nur die drei entferntesten Ziele wählen")
	forms.free()
	_dispose(targets)


func _test_blitzbiss() -> void:
	var forms := _forms({"blitzbiss": 1})
	var a := _brute(Vector3(2, 0, 0))
	var b := _brute(Vector3(5, 0, 0))
	var c := _brute(Vector3(8, 0, 0))
	var d := _brute(Vector3(11, 0, 0))
	var lone := _brute(Vector3(0, 0, -6))
	var targets := [a, b, c, d, lone]
	forms.step(DT, targets, false, 1.0)
	var base: float = FORMS_SCRIPT.BLITZ_DAMAGE[0]
	var fall: float = FORMS_SCRIPT.BLITZ_FALLOFF
	_check(_near(_lost(a), base) and _near(_lost(b), base * fall) and _near(_lost(c), base * fall * fall), "Blitzbiss R1 sollte 3 Ziele mit Abschwächung treffen (%s/%s/%s)" % [_lost(a), _lost(b), _lost(c)])
	_check(_lost(d) == 0.0, "Blitzbiss R1 sprang auf ein viertes Ziel")
	_check(_lost(lone) == 0.0, "Blitzbiss traf außerhalb von 5 m")
	_check(forms.active_count("bolts") == 1, "Blitzbiss zeigt keinen Blitz")
	# Intervall 1,6 s: bis 1,5 s kein zweiter Biss.
	_run_for(forms, 1.5, targets)
	_check(_near(_lost(a), base), "Blitzbiss-Intervall zu kurz")
	forms.free()
	var strong := _forms({"blitzbiss": 3})
	var fresh := [_brute(Vector3(2, 0, 0)), _brute(Vector3(5, 0, 0)), _brute(Vector3(8, 0, 0)), _brute(Vector3(11, 0, 0)), _brute(Vector3(14, 0, 0)), _brute(Vector3(17, 0, 0))]
	strong.step(DT, fresh, false, 2.0)
	var top: float = FORMS_SCRIPT.BLITZ_DAMAGE[2] * 2.0
	_check(_near(_lost(fresh[0]), top), "Blitzbiss R3 × enemy_scale 2 sollte %s sein, war %s" % [top, _lost(fresh[0])])
	_check(_lost(fresh[4]) > 0.0 and _lost(fresh[5]) == 0.0, "Blitzbiss R3 sollte genau 5 Ziele treffen")
	strong.free()
	_dispose(targets + fresh)


func _test_blitzbiss_horde() -> void:
	var horde := _horde()
	var first := horde.add(Vector3(3, 0, 0))
	var second := horde.add(Vector3(6, 0, 0))
	var far := horde.add(Vector3(20, 0, 0))
	var forms := _forms({"blitzbiss": 1}, horde)
	forms.step(DT, [], false, 1.0)
	_check(_near(horde.lost(first), FORMS_SCRIPT.BLITZ_DAMAGE[0]), "Blitzbiss trifft die erste Brut nicht")
	_check(horde.lost(second) > 0.0, "Blitzbiss springt nicht zur nächsten Brut")
	_check(horde.lost(far) == 0.0, "Blitzbiss sprang zu Brut außerhalb der Reichweite")
	forms.free()
	# Gemischt: Gegner zuerst, dann Brut in Sprungweite.
	var enemy := _brute(Vector3(0, 0, 2))
	var mixed := horde.add(Vector3(0, 0, 4.5))
	var chain := _forms({"blitzbiss": 1}, horde)
	chain.step(DT, [enemy], false, 1.0)
	_check(_near(_lost(enemy), FORMS_SCRIPT.BLITZ_DAMAGE[0]), "Blitzbiss beginnt nicht beim Gegner")
	_check(horde.lost(mixed) > 0.0, "Blitzbiss springt nicht vom Gegner auf Brut")
	chain.free()
	horde.free()
	enemy.free()


func _test_sturmrudel() -> void:
	var forms := _forms({"blitzbiss": 3, "sturmrudel": 1})
	var line: Array = []
	for i in 8:
		line.append(_brute(Vector3(4.0 * float(i + 1), 0, 0)))
	_check(FORMS_SCRIPT.STORM_TARGETS < line.size(), "Testaufbau: mehr Ziele als Sturmrudel-Sprünge nötig")
	forms.step(DT, line, true, 1.0)
	var hit := 0
	for target in line:
		if _near(_lost(target), FORMS_SCRIPT.STORM_DAMAGE):
			hit += 1
	_check(hit == FORMS_SCRIPT.STORM_TARGETS, "Sturmrudel sollte %d Ziele ohne Abschwächung treffen, waren %d" % [FORMS_SCRIPT.STORM_TARGETS, hit])
	_check(_lost(line[FORMS_SCRIPT.STORM_TARGETS]) == 0.0, "Sturmrudel sprang über die Zielgrenze hinaus")
	# Rally: kürzeres Intervall (STORM_RALLY_INTERVAL statt STORM_INTERVAL).
	_run_for(forms, FORMS_SCRIPT.STORM_RALLY_INTERVAL + 0.05, line, true)
	_check(_near(_lost(line[0]), FORMS_SCRIPT.STORM_DAMAGE * 2.0), "Sturmrudel mit Rally sollte erneut beißen, war %s" % _lost(line[0]))
	forms.free()
	var calm := _forms({"sturmrudel": 1})
	var solo := _brute(Vector3(0, 0, 3))
	_run_for(calm, FORMS_SCRIPT.STORM_INTERVAL - 0.05, [solo])
	_check(_near(_lost(solo), FORMS_SCRIPT.STORM_DAMAGE), "Sturmrudel ohne Rally beißt zu oft, war %s" % _lost(solo))
	calm.free()
	solo.free()
	_dispose(line)


func _test_brutsack() -> void:
	var forms := _forms({"brutsack": 1})
	var target := _brute(Vector3(4, 0, 0))
	var far := _brute(Vector3(-12, 0, 0))
	var targets := [target, far]
	forms.step(DT, targets, false, 1.0)
	_check(forms.active_count("sacs") == 1, "Brutsack bildet keine Blase")
	_run_for(forms, 0.6, targets)
	_check(forms.active_count("biters") == FORMS_SCRIPT.SAC_BITERS[0], "Brutsack R1 sollte 2 Hilfs-Beißer freisetzen, waren %d" % forms.active_count("biters"))
	_run_for(forms, 2.0, targets)
	var expected: float = FORMS_SCRIPT.SAC_BITE[0] * FORMS_SCRIPT.SAC_BITERS[0]
	_check(_near(_lost(target), expected), "Brutsack R1 sollte %s Schaden machen, war %s" % [expected, _lost(target)])
	_check(_lost(far) == 0.0, "Brutsack traf außerhalb der Reichweite")
	_check(forms.active_count("biters") == 0, "Hilfs-Beißer verschwinden nicht")
	forms.free()
	var strong := _forms({"brutsack": 3})
	var victim := _brute(Vector3(0, 0, -4))
	_run_for(strong, 2.3, [victim])
	var top: float = FORMS_SCRIPT.SAC_BITE[2] * FORMS_SCRIPT.SAC_BITERS[2]
	_check(_near(_lost(victim), top), "Brutsack R3 sollte %s Schaden machen, war %s" % [top, _lost(victim)])
	strong.free()
	_dispose(targets + [victim])


func _test_brutsack_horde_and_population() -> void:
	var horde := _horde()
	var brood := horde.add(Vector3(3, 0, 0))
	var beyond := horde.add(Vector3(-15, 0, 0))
	var children := world.get_child_count()
	var forms := _forms({"brutsack": 3}, horde)
	var enemy := _brute(Vector3(0, 0, 5))
	_run_for(forms, 8.0, [], false)
	_check(horde.lost(brood) > 0.0, "Brutsack trifft Brut in Reichweite nicht")
	_check(horde.lost(beyond) == 0.0, "Brutsack traf Brut außerhalb der Reichweite")
	_run_for(forms, 8.0, [enemy], true)
	_check(_lost(enemy) > 0.0, "Brutsack trifft Gegner neben Brut nicht")
	_check(int(swarm.get("population")) == 25, "Brutsack hat die Population verändert")
	_check(swarm.get_child_count() == 0, "Brutsack hat dem Schwarm Knoten hinzugefügt")
	_check(world.get_child_count() == children + 2, "Brutsack erzeugt Knoten außerhalb seiner Pools")
	forms.free()
	horde.free()
	enemy.free()


func _test_evolution_rules() -> void:
	var evo := EVOLUTION.new()
	for id in EVOLUTION.UNLOCK_ONLY:
		_check(not evo.pool.has(id), "%s im Standard-Pool" % id)
	evo.configure({"pool": ["jaws", "armor", "graeber", "blitzbiss", "brutsack", "regeneration", "dornenhaut"]})
	for id in ["graeber", "blitzbiss", "brutsack", "regeneration", "dornenhaut"]:
		_check(evo.pool.has(id), "%s kommt über RunConfig nicht in den Pool" % id)
	evo.ranks = {"graeber": 3, "blitzbiss": 3}
	evo.add_alpha_core()
	_check(evo.try_evolve() == "", "Evolution ohne Partner-Anlage darf nicht greifen")
	evo.ranks["armor"] = 1
	_check(evo.try_evolve() == "erdbeben", "Gräber R3 + Knochenpanzer + Alpha-Kern sollte Erdbeben ergeben")
	_check(evo.rank("graeber") == 0 and evo.rank("erdbeben") == 1 and evo.alpha_cores == 0, "Erdbeben ersetzt Gräber nicht")
	_check(evo.attack_ranks().has("erdbeben") and evo.slots_used("attack") == 2, "Erdbeben belegt keinen Angriffsslot")
	evo.ranks["jaws"] = 1
	_check(evo.try_evolve() == "", "Evolution ohne Alpha-Kern darf nicht greifen")
	evo.add_alpha_core()
	_check(evo.try_evolve() == "sturmrudel", "Blitzbiss R3 + Reißzähne + Alpha-Kern sollte Sturmrudel ergeben")
	_check(evo.rank("blitzbiss") == 0 and evo.evolutions.has("sturmrudel"), "Sturmrudel ersetzt Blitzbiss nicht")
	var hint := EVOLUTION.new()
	hint.ranks = {"graeber": 2}
	_check(hint.evolution_hint().begins_with("Erdbeben braucht"), "Evolutions-Hinweis für Erdbeben fehlt: " + hint.evolution_hint())


var _regen_signal := 0


func _on_regen(amount: int) -> void:
	_regen_signal += amount


func _test_regeneration() -> void:
	var evo := EVOLUTION.new()
	_check(evo.regeneration_interval() == 0 and evo.note_kills(50) == 0, "Ohne Regeneration kein LP")
	evo.leader_regenerated.connect(_on_regen)
	evo.ranks["regeneration"] = 1
	_check(evo.regeneration_interval() == EVOLUTION.REGEN_KILLS[0], "Regeneration R1: LP je %d Kills" % EVOLUTION.REGEN_KILLS[0])
	_check(evo.note_kills(EVOLUTION.REGEN_KILLS[0] - 1) == 0, "Regeneration heilt zu früh")
	_check(evo.note_kills(1) == 1 and _regen_signal == 1 and evo.regen_kills == 0, "Regeneration heilt nach N Kills nicht (Signal/Rückgabe)")
	evo.ranks["regeneration"] = 3
	_check(evo.note_kills(EVOLUTION.REGEN_KILLS[2] * 2 + 1) == 2 and evo.regen_kills == 1, "Regeneration R3 zählt Mehrfach-Kills falsch")
	_check(EVOLUTION.REGEN_KILLS[0] > EVOLUTION.REGEN_KILLS[1] and EVOLUTION.REGEN_KILLS[1] > EVOLUTION.REGEN_KILLS[2], "N muss mit dem Rang sinken")


func _test_dornenhaut() -> void:
	var evo := EVOLUTION.new()
	_check(evo.thorn_factor() == 0.0 and evo.thorn_damage(5, true) == 0.0, "Ohne Dornenhaut kein Rückschaden")
	evo.ranks["dornenhaut"] = 1
	var r1 := evo.thorn_factor()
	evo.ranks["dornenhaut"] = 3
	_check(r1 > 0.0 and evo.thorn_factor() > r1, "Dornenhaut skaliert nicht mit dem Rang")
	evo.ranks["dornenhaut"] = 2
	var expected := 0.8 * (EVOLUTION.THORN_BASE + 2.0 * EVOLUTION.THORN_PER_LOSS + EVOLUTION.THORN_LEADER)
	_check(_near(evo.thorn_damage(2, true), expected), "thorn_damage(2, true) R2 sollte %s sein, war %s" % [expected, evo.thorn_damage(2, true)])
	var horde := _horde()
	var close := horde.add(Vector3(1, 0, 0))
	var away := horde.add(Vector3(5, 0, 0))
	var forms := _forms({}, horde)
	var attacker := _brute(Vector3(1, 0, 1))
	forms.step(DT, [], false, 1.5)
	forms.reflect_thorns(attacker, expected, Vector3(0.5, 0, 0))
	_check(_near(_lost(attacker), expected * 1.5), "reflect_thorns nutzt enemy_scale nicht, war %s" % _lost(attacker))
	_check(_near(horde.lost(close), expected * 1.5) and horde.lost(away) == 0.0, "Dornenhaut trifft Brut am Treffpunkt nicht (oder zu weit)")
	forms.reflect_thorns(null, expected, Vector3.ZERO)
	_check(float(forms.damage_dealt.get("dornenhaut", 0.0)) > 0.0, "Dornenhaut-Schaden wird nicht verbucht")
	forms.free()
	horde.free()
	attacker.free()


func _test_clear() -> void:
	var horde := _horde()
	horde.add(Vector3(2, 0, 2))
	var forms := _forms({"graeber": 2, "blitzbiss": 2, "brutsack": 2}, horde)
	var targets := [_brute(Vector3(3, 0, 0)), _brute(Vector3(-8, 0, 1)), _brute(Vector3(0, 0, 4))]
	_run_for(forms, 0.4, targets)
	_check(forms.active_effects() > 0, "Keine aktiven Effekte der neuen Formen")
	var health: Array = targets.map(func(t): return t.health)
	for i in 5:
		await process_frame
	_check(health == targets.map(func(t): return t.health), "Ohne step() hat sich Gesundheit verändert (Pause)")
	forms.clear()
	_check(forms.active_effects() == 0, "clear() entfernt die neuen Effekte nicht")
	var visible := 0
	for node in forms.find_children("*", "GeometryInstance3D", true, false):
		if node.is_visible_in_tree():
			visible += 1
	_check(visible == 0, "Nach clear() sind noch %d Effekt-Knoten sichtbar" % visible)
	forms.free()
	horde.free()
	_dispose(targets)
