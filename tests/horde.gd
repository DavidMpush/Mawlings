extends SceneTree

# Headless-Test der Moorbrut-Horde (scripts/horde.gd) mit eigener Minimalszene:
# echte Arena (Felsen), ein einfacher Schwarm-Knoten und Mawling-Punkte als Array.
#
# Leistungsmessung (ohne --headless, rendert main.tscn mit 120 Mawlings + 160 Brut):
#   Godot --path . --script res://tests/horde.gd -- --bench

const HORDE_SCRIPT = preload("res://scripts/horde.gd")
const ARENA_SCRIPT = preload("res://scripts/arena.gd")
const FORMS_SCRIPT = preload("res://scripts/attack_forms.gd")
const DT := 1.0 / 60.0
const STATS := {"hp": 6.0, "speed": 5.0, "bite": 1.0, "bite_cooldown": 1.0, "biomass": 0.4, "dna": 1}

var failures := 0
var world: Node3D
var swarm: Node3D
var arena: Node3D
var horde: Node3D


class Brute extends Node3D:
	var health := 1000.0
	var slow_factor := 1.0

	func take_damage(amount: float) -> void:
		health -= amount


func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--bench"):
		call_deferred("_bench")
	else:
		call_deferred("_run")


func _run() -> void:
	world = Node3D.new()
	world.name = "World"
	root.add_child(world)
	arena = ARENA_SCRIPT.new()
	arena.name = "Arena"
	world.add_child(arena)
	swarm = Node3D.new()
	swarm.name = "Swarm"
	world.add_child(swarm)
	horde = HORDE_SCRIPT.new()
	horde.name = "Horde"
	world.add_child(horde)
	horde.setup(world, swarm, arena)
	await process_frame
	_test_spawn_cap()
	_test_pursuit()
	_test_bite_contact_and_cooldown()
	_test_bite_fraction()
	_test_damage_circle_and_kills()
	_test_damage_nearest()
	_test_melee()
	_test_separation()
	_test_rocks()
	await _test_pause_and_clear()
	_test_forms()
	if failures > 0:
		push_error("horde: %d Prüfung(en) fehlgeschlagen" % failures)
		quit(1)
		return
	print("horde: alle Prüfungen bestanden")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FEHLER: " + message)


func _disc(center: Vector3, amount: int, radius: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	for index in amount:
		var angle := float(index) * 2.39996323
		var r := sqrt((float(index) + 0.5) / float(amount)) * radius
		points.append(center + Vector3(cos(angle) * r, 0.0, sin(angle) * r))
	return points


func _run_steps(seconds: float, points: PackedVector3Array) -> Dictionary:
	var bites := 0
	var losses := 0
	for frame in int(round(seconds / DT)):
		var result: Dictionary = horde.step(DT, points)
		bites += (result.bitten_indices as PackedInt32Array).size()
		losses += int(result.losses)
	return {"bites": bites, "losses": losses}


func _mean_distance(center: Vector3) -> float:
	var positions: PackedVector3Array = horde.positions()
	if positions.is_empty():
		return 0.0
	var total := 0.0
	for p in positions:
		total += Vector2(p.x - center.x, p.z - center.z).length()
	return total / float(positions.size())


# ------------------------------------------------------------------ Tests

func _test_spawn_cap() -> void:
	horde.clear()
	var first: int = horde.spawn_ring(Vector3.ZERO, 100, 12.0, STATS)
	_check(first == 100, "Ring-Spawn setzt 100 Brut (%d)" % first)
	var second: int = horde.spawn_ring(Vector3.ZERO, 100, 14.0, STATS)
	_check(second == 60 and horde.count() == 160, "Deckel 160 (zweiter Spawn %d, gesamt %d)" % [second, horde.count()])
	_check(horde.spawn_ring(Vector3.ZERO, 5, 10.0, STATS) == 0, "Voller Deckel: kein weiterer Spawn")
	var inside := 0
	for p in horde.positions():
		var d := Vector2(p.x, p.z).length()
		if d > 10.5 and d < 18.5:
			inside += 1
	_check(inside == 160, "Spawn liegt auf dem Ring (%d/160)" % inside)
	_check(arena.is_open(horde.positions()[0], 0.3), "Spawn nicht im Fels")


func _test_pursuit() -> void:
	horde.clear()
	horde.spawn_ring(Vector3.ZERO, 40, 12.0, STATS)
	var points := _disc(Vector3.ZERO, 60, 2.8)
	var before := _mean_distance(Vector3.ZERO)
	_run_steps(1.5, points)
	var after := _mean_distance(Vector3.ZERO)
	_check(after < before - 5.0, "Verfolgung: mittlerer Abstand %.1f -> %.1f m" % [before, after])
	# Schwarm zieht weg: die Brut folgt.
	var moved := _disc(Vector3(8.0, 0.0, 6.0), 60, 2.8)
	var far := _mean_distance(Vector3(8.0, 0.0, 6.0))
	_run_steps(2.0, moved)
	_check(_mean_distance(Vector3(8.0, 0.0, 6.0)) < far - 4.0, "Verfolgung folgt dem bewegten Schwarm")


func _test_bite_contact_and_cooldown() -> void:
	horde.clear()
	var target := Vector3(0.0, 0.0, 0.0)
	var points := PackedVector3Array([target])
	horde.spawn_ring(target, 1, 4.0, STATS)
	var first_bite_distance := -1.0
	var bite_times: Array[float] = []
	var clock := 0.0
	for frame in 300:
		var result: Dictionary = horde.step(DT, points)
		clock += DT
		var bitten: PackedInt32Array = result.bitten_indices
		if bitten.size() > 0:
			var now: Vector3 = horde.positions()[0]
			if first_bite_distance < 0.0:
				first_bite_distance = Vector2(now.x - target.x, now.z - target.z).length()
			bite_times.append(clock)
			_check(bitten[0] == 0 and int(result.losses) == 1, "Biss meldet Index 0 und 1 Verlust")
	_check(first_bite_distance >= 0.0 and first_bite_distance < horde.BITE_RANGE + 0.001, "Erster Biss erst bei Kontakt (%.2f m)" % first_bite_distance)
	_check(bite_times.size() >= 3 and bite_times.size() <= 5, "Abklingzeit 1 s: %d Bisse in 5 s" % bite_times.size())
	for k in range(1, bite_times.size()):
		_check(bite_times[k] - bite_times[k - 1] >= 1.0 - DT * 0.5, "Abstand zwischen Bissen >= Abklingzeit")
	# Weit weg: niemals Biss.
	horde.clear()
	horde.spawn_ring(Vector3(0, 0, 0), 6, 9.0, STATS)
	var far_points := PackedVector3Array([Vector3(0, 0, 0)])
	var total := 0
	for frame in 30:
		total += int(horde.step(DT, far_points).losses)
	_check(total == 0, "Kein Biss ohne Kontakt")
	# Keine Punkte: kein Biss, kein Fehler.
	_check(int(horde.step(DT, PackedVector3Array()).losses) == 0, "Leere Punktliste ohne Biss")


func _test_bite_fraction() -> void:
	horde.clear()
	var stats := STATS.duplicate()
	stats.bite = 0.5
	stats.bite_cooldown = 0.5
	horde.spawn_ring(Vector3.ZERO, 4, 1.5, stats)
	var result := _run_steps(4.0, _disc(Vector3.ZERO, 30, 1.2))
	var snaps: int = horde.total_bites
	_check(snaps > 4 and absi(int(result.losses) - snaps / 2) <= 1, "Halber Biss: %d Bisse -> %d Verluste" % [snaps, result.losses])
	_check(int(result.bites) == int(result.losses), "Gemeldete Indizes = ganze Verluste (%d/%d)" % [result.bites, result.losses])


func _test_damage_circle_and_kills() -> void:
	horde.clear()
	horde.take_kills()
	horde.spawn_ring(Vector3(3, 0, 3), 20, 3.0, STATS)
	horde.spawn_ring(Vector3(3, 0, 3), 5, 9.0, STATS)
	var kills: int = horde.damage_circle(Vector3(3, 0, 3), 4.0, 3.0)
	_check(kills == 0 and horde.last_hit_count == 20, "Fläche: 20 getroffen, keiner tot (%d/%d)" % [horde.last_hit_count, kills])
	kills = horde.damage_circle(Vector3(3, 0, 3), 4.0, 3.0)
	_check(kills == 20 and horde.count() == 5, "Fläche: 20 Kills, 5 außerhalb übrig (%d, %d)" % [kills, horde.count()])
	var bundles: Array = horde.take_kills()
	var sum_count := 0
	var sum_biomass := 0.0
	var sum_dna := 0
	for bundle in bundles:
		sum_count += int(bundle.count)
		sum_biomass += float(bundle.biomass)
		sum_dna += int(bundle.dna)
		_check(bundle.position is Vector3, "Kill mit Position")
	_check(sum_count == 20 and is_equal_approx(sum_biomass, 8.0) and sum_dna == 20, "Kills: 20, Biomasse 8, DNA 20 (%d, %.1f, %d)" % [sum_count, sum_biomass, sum_dna])
	_check(bundles.size() < 20 and bundles.size() >= 1, "Kills räumlich gebündelt (%d Bündel)" % bundles.size())
	_check(horde.take_kills().is_empty(), "take_kills liefert nur einmal")


func _test_damage_nearest() -> void:
	horde.clear()
	_check(horde.damage_nearest(Vector3.ZERO, 5.0, 10.0) == Vector3.INF, "damage_nearest ohne Brut = INF")
	_check(horde.nearest(Vector3.ZERO) == Vector3.INF, "nearest ohne Brut = INF")
	horde.spawn_ring(Vector3(20, 0, 0), 1, 0.5, STATS)
	_check(horde.damage_nearest(Vector3.ZERO, 5.0, 10.0) == Vector3.INF, "damage_nearest außer Reichweite = INF")
	var hit: Vector3 = horde.damage_nearest(Vector3(20, 0, 0), 3.0, 10.0)
	_check(hit != Vector3.INF and hit.distance_to(Vector3(20, 0, 0)) < 1.5, "damage_nearest trifft")
	_check(horde.count() == 0 and horde.take_kills().size() == 1, "damage_nearest tötet und meldet Kill")


func _test_melee() -> void:
	horde.clear()
	horde.take_kills()
	var stats := STATS.duplicate()
	stats.hp = 4.0
	horde.spawn_ring(Vector3.ZERO, 6, 3.0, stats)
	horde.spawn_ring(Vector3.ZERO, 4, 9.0, stats)
	var points := _disc(Vector3.ZERO, 40, 2.6)
	var killed: int = horde.melee(points, 1.3, 10.0, 0.25)
	_check(killed == 0, "Nahkampf: erster Treffer noch nicht tödlich")
	killed = horde.melee(points, 1.3, 10.0, 0.25)
	_check(killed == 6 and horde.count() == 4, "Nahkampf tötet nur Brut in Reichweite (%d, übrig %d)" % [killed, horde.count()])
	_check(horde.melee(PackedVector3Array(), 1.0, 10.0, 1.0) == 0, "Nahkampf ohne Punkte")


func _test_separation() -> void:
	horde.clear()
	var stats := STATS.duplicate()
	stats.bite_cooldown = 99.0
	horde.spawn_ring(Vector3.ZERO, 40, 8.0, stats)
	var points := PackedVector3Array([Vector3.ZERO])
	_run_steps(4.0, points)
	var positions: PackedVector3Array = horde.positions()
	var stacked := 0
	var near_target := 0
	for a in positions.size():
		if Vector2(positions[a].x, positions[a].z).length() < 3.5:
			near_target += 1
		for b in range(a + 1, positions.size()):
			if Vector2(positions[a].x - positions[b].x, positions[a].z - positions[b].z).length() < 0.2:
				stacked += 1
	_check(stacked <= 2, "Separation: %d gestapelte Paare" % stacked)
	_check(near_target >= 30, "Brut drängt sich trotzdem um den Punkt (%d/40)" % near_target)


func _test_rocks() -> void:
	horde.clear()
	# Ein Fels der festen Karte (Seed 0) mit Mawling-Punkt dahinter, Brut davor.
	var rock := Vector4.ZERO
	for x in range(-2, 3):
		for z in range(-2, 3):
			var list: Array = arena.obstacles(Vector2i(x, z))
			for circle in list:
				if rock == Vector4.ZERO and circle.w < 2.5:
					rock = circle
	_check(rock != Vector4.ZERO, "Testfels gefunden")
	var center := Vector3(rock.x, 0.0, rock.z)
	var points := PackedVector3Array([center + Vector3(rock.w + 1.5, 0.0, 0.0)])
	horde.spawn_ring(center - Vector3(rock.w + 1.6, 0.0, 0.0), 6, 0.6, STATS)
	var worst := INF
	for frame in 240:
		horde.step(DT, points)
		for p in horde.positions():
			worst = minf(worst, Vector2(p.x - rock.x, p.z - rock.z).length())
	_check(worst >= rock.w + horde.BODY_RADIUS - 0.08, "Felsen nicht durchlaufen (min %.2f, Radius %.2f)" % [worst, rock.w + horde.BODY_RADIUS])
	# Umgehen: nach einigen Sekunden erreicht die Brut den Punkt hinter dem Fels.
	var reached := 0
	for p in horde.positions():
		if p.distance_to(points[0]) < 1.6:
			reached += 1
	_check(reached >= 3, "Brut umläuft den Fels (%d/6 am Ziel)" % reached)


func _test_pause_and_clear() -> void:
	horde.clear()
	horde.spawn_ring(Vector3.ZERO, 10, 6.0, STATS)
	var before: PackedVector3Array = horde.positions()
	for frame in 5:
		await process_frame
	_check(horde.positions() == before, "Ohne step() bewegt sich nichts (Pause)")
	horde.damage_circle(Vector3.ZERO, 20.0, 100.0)
	horde.spawn_ring(Vector3.ZERO, 10, 6.0, STATS)
	horde.clear()
	_check(horde.count() == 0 and horde.take_kills().is_empty(), "clear leert Brut und Kills")
	var bodies: MultiMeshInstance3D = horde.get_node("Moorbrut")
	_check(bodies.multimesh.visible_instance_count == 0, "clear leert die MultiMesh")


func _forms(ranks: Dictionary) -> Node3D:
	var forms: Node3D = FORMS_SCRIPT.new()
	world.add_child(forms)
	forms.setup(world, swarm)
	forms.set_horde(horde)
	forms.set_ranks(ranks)
	return forms


func _forms_run(forms: Node3D, seconds: float, targets: Array, rally: bool) -> void:
	for frame in int(round(seconds / DT)):
		forms.step(DT, targets, rally, 1.0)


func _test_forms() -> void:
	swarm.position = Vector3.ZERO
	# Sporenwolke R1 (3 m, 3,5/s): Brut innerhalb stirbt, außerhalb bleibt.
	horde.clear()
	horde.spawn_ring(Vector3.ZERO, 8, 2.0, STATS)
	horde.spawn_ring(Vector3.ZERO, 4, 8.0, STATS)
	var forms := _forms({"sporenwolke": 1})
	_forms_run(forms, 2.0, [], false)
	_check(horde.count() == 4, "Sporenwolke räumt Brut in der Aura (%d übrig)" % horde.count())
	_check(float(forms.damage_dealt.get("sporenwolke", 0.0)) > 40.0, "Sporen-Schaden an Brut gezählt")
	forms.queue_free()
	# Säurespucker ohne echte Ziele: zielt auf Brut, Einschlag tötet sie.
	horde.clear()
	horde.spawn_ring(Vector3.ZERO, 1, 5.0, STATS)
	forms = _forms({"saeurespucker": 3})
	_forms_run(forms, 1.0, [], false)
	_check(horde.count() == 0, "Säure trifft Brut ohne andere Ziele")
	# Echtes Ziel hat Vorrang vor Brut.
	horde.clear()
	horde.spawn_ring(Vector3.ZERO, 1, 3.0, STATS)
	var brute := Brute.new()
	world.add_child(brute)
	brute.global_position = Vector3(6, 0, 0)
	forms.clear()
	_forms_run(forms, 0.8, [brute], false)
	_check(brute.health < 1000.0 and horde.count() == 1, "Säure: echtes Ziel vor Brut")
	brute.queue_free()
	forms.queue_free()
	# Ätzflut: Pfütze beim Brut-Treffer schadet weiterer Brut.
	horde.clear()
	var tough := STATS.duplicate()
	tough.hp = 14.0
	horde.spawn_ring(Vector3.ZERO, 3, 5.0, tough)
	forms = _forms({"aetzflut": 1})
	_forms_run(forms, 0.6, [], false)
	_check(forms.active_puddles() >= 1 and float(forms.damage_dealt.get("aetzflut", 0.0)) > 0.0, "Ätzflut-Pfütze trifft Brut")
	forms.queue_free()
	# Rudelbiss mit Rally: Sprung auf Brut, Landung trifft die Gruppe.
	horde.clear()
	horde.spawn_ring(Vector3(3, 0, 0), 5, 0.8, STATS)
	forms = _forms({"rudelbiss": 1})
	_forms_run(forms, 0.4, [], true)
	_check(horde.count() == 5 - horde.total_kills and horde.total_kills >= 3, "Rudelbiss-Landung tötet Brut (%d)" % horde.total_kills)
	forms.queue_free()
	# Stachelrücken: Treffer am Schwarm (ohne Angreifer) trifft Brut am Rand, gedrosselt.
	horde.clear()
	var soft := STATS.duplicate()
	# Etappe 17 Welle 2: Stachelrücken Rang 1 trifft mit 44 (+5 je Verlust); ein
	# Treffer darf die Brut nicht töten, zwei zugleich würden es.
	soft.hp = 80.0
	horde.spawn_ring(Vector3.ZERO, 6, 3.0, soft)
	horde.spawn_ring(Vector3.ZERO, 3, 12.0, soft)
	forms = _forms({"stachelruecken": 1})
	forms.on_swarm_hit(null, 2)
	_check(horde.count() == 9 and horde.last_hit_count == 6, "Stacheln treffen Brut am Rand (%d)" % horde.last_hit_count)
	forms.on_swarm_hit(null, 2)
	_check(horde.total_kills == 0, "Stacheln gedrosselt (kein Doppeltreffer im selben Moment)")
	_forms_run(forms, 0.6, [], false)
	forms.on_swarm_hit(null, 2)
	_check(horde.total_kills == 6, "Stacheln nach Abklingzeit erneut (%d Kills)" % horde.total_kills)
	forms.queue_free()
	horde.clear()


# ------------------------------------------------------------------ Bench

func _bench() -> void:
	root.size = Vector2i(540, 960)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var hunt: Node3D = scene.get_node("HuntWorld")
	var main_swarm: Node3D = scene.get_node("Swarm")
	var controls: Node = scene.get_node("HUD/Controls")
	if controls.has_signal("pause_requested") and controls.pause_requested.is_connected(hunt.toggle_pause):
		controls.pause_requested.disconnect(hunt.toggle_pause)
	for frame in 30:
		await process_frame
	hunt.set_process(false)
	hunt.model.population = 120
	main_swarm.set_population(120, false)
	for frame in 30:
		await process_frame
	var calls_without := _draw_calls()
	var h: Node3D = HORDE_SCRIPT.new()
	h.name = "Horde bench"
	hunt.add_child(h)
	h.setup(hunt, main_swarm, scene.get_node("Arena"))
	var stats := {"hp": 1.0e9, "speed": 5.0, "bite": 1.0, "bite_cooldown": 1.0}
	h.spawn_ring(main_swarm.position, 80, 5.5, stats)
	h.spawn_ring(main_swarm.position, 80, 8.0, stats)
	var total := 0
	var part_step := 0
	var part_melee := 0
	var worst := 0
	var samples: Array[int] = []
	var frames := 600
	var calls_with := 0
	for frame in frames:
		var points: PackedVector3Array = main_swarm.unit_world_points()
		var started := Time.get_ticks_usec()
		h.step(DT, points)
		var stepped := Time.get_ticks_usec()
		h.melee(points, 1.6, 0.001, DT)
		var meleed := Time.get_ticks_usec()
		h.damage_circle(main_swarm.position, 4.2, 0.001)
		h.take_kills()
		var spent := Time.get_ticks_usec() - started
		part_step += stepped - started
		part_melee += meleed - stepped
		total += spent
		samples.append(spent)
		worst = maxi(worst, spent)
		await process_frame
		if frame == frames / 2:
			calls_with = _draw_calls()
	var avg_ms := float(total) / float(frames) / 1000.0
	samples.sort()
	var median_ms := float(samples[samples.size() / 2]) / 1000.0
	print("horde bench: %d Brut, %d Mawlings: step+melee+aura Median %.3f ms, Ø %.3f ms, max %.3f ms; (step %.3f, melee %.3f); Draw Calls %d -> %d, FPS %d" % [h.count(), main_swarm.units.size(), median_ms, avg_ms, float(worst) / 1000.0, float(part_step) / float(frames) / 1000.0, float(part_melee) / float(frames) / 1000.0, calls_without, calls_with, Engine.get_frames_per_second()])
	quit(0)


func _draw_calls() -> int:
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
