extends SceneTree

# Sandmade (scripts/sandgrub.gd, stage 19): standalone checks of the small desert
# horde – burst spawn from the sand (no bite while emerging), runs at the nearest
# Mawling faster than the Moorbrut but slower than the swarm, bites with a
# cooldown, the swarm bites back (melee), area damage, bundled kills, the cap,
# pause freeze, clear(), and the MultiMesh drawing.

const GRUBS = preload("res://scripts/sandgrub.gd")
const HORDE = preload("res://scripts/horde.gd")
const DT := 1.0 / 60.0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var grubs: Variant = GRUBS.new()
	root.add_child(grubs)
	grubs.setup(null, null, null)
	_check(float(GRUBS.DEFAULT_STATS.speed) > float(HORDE.DEFAULT_STATS.speed) and float(GRUBS.DEFAULT_STATS.speed) < 7.0, "Faster than the Moorbrut, slower than the swarm")
	var spawned: int = grubs.spawn_burst(Vector3(10, 0, 0), 4)
	_check(spawned == 4 and grubs.count() == 4, "Burst spawns 4 grubs")
	var spread := 0.0
	for point in grubs.positions():
		spread = maxf(spread, Vector2(point.x - 10.0, point.z).length())
	_check(spread <= GRUBS.BURST_RADIUS + 0.01 and spread > 0.5, "Burst cluster around the hole (%.1f m)" % spread)
	# Emerging: no movement and no bite.
	var swarm := PackedVector3Array([Vector3(10.3, 0, 0), Vector3(10, 0, 0.3), Vector3(0, 0, 0)])
	var start: PackedVector3Array = grubs.positions()
	var early: Dictionary = grubs.step(GRUBS.EMERGE_SECONDS * 0.5, swarm)
	_check((early.bitten_indices as PackedInt32Array).is_empty() and grubs.positions() == start, "No move / bite while breaking out of the sand")
	# Run at the nearest Mawling (the far point at the origin is ignored).
	grubs.clear()
	grubs.spawn_burst(Vector3(12, 0, 0), 1)
	for i in int(GRUBS.EMERGE_SECONDS / DT) + 2:
		grubs.step(DT, PackedVector3Array([Vector3(4, 0, 0), Vector3(-20, 0, 0)]))
	var before: Vector3 = grubs.positions()[0]
	for i in 30:
		grubs.step(DT, PackedVector3Array([Vector3(4, 0, 0), Vector3(-20, 0, 0)]))
	var after: Vector3 = grubs.positions()[0]
	var ran := before.x - after.x
	_check(ran > float(GRUBS.DEFAULT_STATS.speed) * 0.5 * 0.85 and ran < float(GRUBS.DEFAULT_STATS.speed) * 0.5 * GRUBS.LUNGE_BOOST * 1.15, "Runs at the nearest Mawling (%.2f m in 0.5 s)" % ran)
	# Bites with a cooldown.
	var bites := 0
	var losses := 0.0
	var elapsed := 0.0
	while elapsed < 3.0:
		var result: Dictionary = grubs.step(DT, PackedVector3Array([Vector3(4, 0, 0), Vector3(-20, 0, 0)]))
		elapsed += DT
		for index in result.bitten_indices:
			_check(index == 0, "Bite hits the nearest point")
			bites += 1
		losses += float(result.losses)
	var expected := 3.0 / float(GRUBS.DEFAULT_STATS.bite_cooldown)
	_check(bites >= int(expected) - 2 and bites <= int(expected) + 1 and is_equal_approx(losses, float(bites) * float(GRUBS.DEFAULT_STATS.bite)), "Bites every %.1f s (%d bites in 3 s)" % [GRUBS.DEFAULT_STATS.bite_cooldown, bites])
	# The swarm bites back; kills come out bundled with biomass + DNA.
	var killed: int = grubs.melee(PackedVector3Array([Vector3(4, 0, 0)]), 1.0, 100.0, 0.2)
	_check(killed == 1 and grubs.count() == 0 and grubs.total_kills == 1, "Melee kills the grub")
	var kills: Array = grubs.take_kills()
	_check(kills.size() == 1 and is_equal_approx(float(kills[0].biomass), float(GRUBS.DEFAULT_STATS.biomass)) and int(kills[0].dna) == 1 and grubs.take_kills().is_empty(), "take_kills hands the loot over once")
	# Area damage and bundling.
	grubs.spawn_burst(Vector3(0, 0, 20), 6, {"hp": 3.0})
	var area_killed: int = grubs.damage_circle(Vector3(0, 0, 20), GRUBS.BURST_RADIUS + 0.5, 5.0)
	_check(area_killed == 6 and grubs.last_hit_count == 6, "damage_circle hits every grub inside")
	var bundles: Array = grubs.take_kills()
	var total := 0
	for bundle in bundles:
		total += int(bundle.count)
	_check(total == 6 and bundles.size() < 6, "Close kills are bundled (%d bundles)" % bundles.size())
	grubs.spawn_burst(Vector3(0, 0, -10), 1)
	var hit: Vector3 = grubs.damage_nearest(Vector3(0, 0, -9), 5.0, 1.0)
	_check(hit.is_finite() and grubs.count() == 1, "damage_nearest wounds without killing")
	_check(not grubs.damage_nearest(Vector3(40, 0, 40), 2.0, 1.0).is_finite(), "damage_nearest respects the range")
	# Cap.
	grubs.clear()
	var added := 0
	for burst in 12:
		added += int(grubs.spawn_burst(Vector3(burst * 6.0, 0, 0), 4))
	_check(added == GRUBS.MAX_GRUBS and grubs.count() == GRUBS.MAX_GRUBS, "Capped at %d grubs" % GRUBS.MAX_GRUBS)
	# Pause: zero delta changes nothing.
	var frozen: PackedVector3Array = grubs.positions()
	var paused: Dictionary = grubs.step(0.0, PackedVector3Array([Vector3(0, 0, 0)]))
	_check(grubs.positions() == frozen and float(paused.losses) == 0.0 and not grubs.is_processing(), "Zero-delta step freezes the grubs")
	# Drawing: one MultiMesh with the Sandgrub model, instance count follows the grubs.
	var bodies: MultiMeshInstance3D = grubs.get_node("Sandmaden")
	_check(bodies.multimesh.visible_instance_count == GRUBS.MAX_GRUBS and bodies.multimesh.mesh != null and GRUBS.MODEL_SCENE.resource_path.ends_with("Sandgrub_game.glb"), "One MultiMesh draws every grub")
	var box: AABB = bodies.multimesh.mesh.get_aabb()
	_check(box.size.length() > 0.5, "Model mesh present")
	grubs.clear()
	_check(grubs.count() == 0 and not bodies.visible, "clear() empties and hides")
	# Without visible points the grub runs at the swarm node and bites at the centre.
	var swarm_node := Node3D.new()
	root.add_child(swarm_node)
	swarm_node.position = Vector3(0, 0, 0)
	grubs.swarm = swarm_node
	grubs.spawn_burst(Vector3(1.5, 0, 0), 1)
	var blind_losses := 0.0
	for i in 120:
		blind_losses += float(grubs.step(DT, PackedVector3Array()).losses)
	_check(blind_losses > 0.0, "Bites the swarm centre without visible points")
	grubs.free()
	swarm_node.free()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS sandgrub: burst from the sand, no bite while emerging, runs at the nearest Mawling (%.1f m/s), bites every %.1f s, melee/area/nearest damage, bundled kills, cap %d, pause, MultiMesh" % [float(GRUBS.DEFAULT_STATS.speed), float(GRUBS.DEFAULT_STATS.bite_cooldown), GRUBS.MAX_GRUBS])
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
