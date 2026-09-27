extends SceneTree

# Headless check of scripts/corpse_visuals.gd (Etappe 09 Kadaver-Designs):
# add / set_fill / remove / clear per kind, instance counts per batch, unknown
# kinds fall back to the normal design, no node per corpse, 60 mixed corpses in
# at most MAX_BATCHES batches (= draw calls). Biomass crystals: size per rank (small /
# medium / big), 1-3 shards on normal enemies, shrinking with the fill.

const CORPSE_VISUALS = preload("res://scripts/corpse_visuals.gd")
# One batch per design (11 incl. the Aschenkröte) + pool, halo, 3 crystal sizes.
const MAX_BATCHES := 16
const KINDS := ["prey", "hunter", "elite", "skitter", "leaper", "boss", "apex", "apex_toad", "horde", "mawling", "nest"]

var failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var visuals: Node3D = CORPSE_VISUALS.new()
	holder.add_child(visuals)
	await process_frame

	# Every kind: one remains instance in its own design batch.
	var id := 1
	for kind in KINDS:
		visuals.add(id, kind, Vector3(id * 3.0, 0.0, 0.0), 10.0)
		_check(visuals.design_of(id) == kind, "%s uses its own design" % kind)
		_check(visuals.instances(kind) == 1, "%s batch has one instance" % kind)
		id += 1
	_check(visuals.count() == KINDS.size(), "count() after adding every kind")
	var pools: int = 0
	var halos: int = 0
	for kind in KINDS:
		if float(CORPSE_VISUALS.DESIGNS[kind].pool) > 0.0:
			pools += 1
		if float(CORPSE_VISUALS.DESIGNS[kind].halo) > 0.0:
			halos += 1
	_check(visuals.instances("pool") == pools, "one amber pool per corpse with a pool (%d)" % pools)
	_check(visuals.instances("halo") == halos, "one halo per mini-boss/boss/mawling (%d)" % halos)
	_check(CORPSE_VISUALS.rank_of("boss") == "boss" and CORPSE_VISUALS.rank_of("apex") == "boss" and CORPSE_VISUALS.rank_of("apex_toad") == "boss", "boss rank")
	_check(CORPSE_VISUALS.rank_of("elite") == "mini" and CORPSE_VISUALS.rank_of("leaper") == "mini", "mini-boss rank")
	_check(CORPSE_VISUALS.rank_of("hunter") == "normal", "normal rank")

	# Biomass crystals by rank.
	var expected_drop := {
		"prey": "drop_small", "hunter": "drop_small", "skitter": "drop_small", "horde": "drop_small",
		"elite": "drop_medium", "leaper": "drop_medium",
		"boss": "drop_big", "apex": "drop_big", "apex_toad": "drop_big", "nest": "drop_big", "mawling": "",
	}
	for kind in KINDS:
		_check(CORPSE_VISUALS.drop_of(kind) == expected_drop[kind], "%s drop is %s" % [kind, expected_drop[kind]])
	var shard_total := {"drop_small": 0, "drop_medium": 0, "drop_big": 0}
	for index in KINDS.size():
		var drop: String = expected_drop[KINDS[index]]
		var shards: int = visuals.drops_of(index + 1)
		if drop == "":
			_check(shards == 0, "%s has no crystal" % KINDS[index])
			continue
		shard_total[drop] += shards
		if drop == "drop_small" and KINDS[index] != "horde":
			_check(shards >= 1 and shards <= 3, "%s has 1-3 shards (%d)" % [KINDS[index], shards])
		else:
			_check(shards == 1, "%s has one crystal" % KINDS[index])
	for drop in shard_total:
		_check(visuals.instances(drop) == shard_total[drop], "%s batch holds every shard (%d)" % [drop, shard_total[drop]])
	# More biomass -> more shards (normal enemies), capped at 3.
	visuals.add(300, "prey", Vector3(0, 0, 30), 1.0)
	visuals.add(301, "prey", Vector3(3, 0, 30), 100.0)
	_check(visuals.drops_of(300) == 1, "little biomass: one shard (%d)" % visuals.drops_of(300))
	_check(visuals.drops_of(301) == 3, "much biomass: three shards (%d)" % visuals.drops_of(301))
	# Crystal size by rank: big > medium > small (world height at full fill).
	var small_h := _drop_height(visuals, "drop_small", 1)
	var medium_h := _drop_height(visuals, "drop_medium", KINDS.find("elite") + 1)
	var big_h := _drop_height(visuals, "drop_big", KINDS.find("boss") + 1)
	_check(small_h < medium_h and medium_h < big_h, "crystal size grows with rank (%.2f / %.2f / %.2f)" % [small_h, medium_h, big_h])
	# Shrinks with the fill, restores at full fill, leaves with the corpse.
	visuals.set_fill(301, 0.1)
	var first_small := _drop_scale(visuals, "drop_small", 301, 0)
	var extra_small := _drop_scale(visuals, "drop_small", 301, 2)
	visuals.set_fill(301, 1.0)
	_check(first_small < _drop_scale(visuals, "drop_small", 301, 0) * 0.45, "crystal shrinks at 10 %")
	_check(extra_small / _drop_scale(visuals, "drop_small", 301, 2) < first_small / _drop_scale(visuals, "drop_small", 301, 0), "extra shards shrink faster")
	var small_before: int = visuals.instances("drop_small")
	visuals.remove(301)
	visuals.remove(300)
	_check(visuals.instances("drop_small") == small_before - 4, "removing a corpse removes all its shards")

	# Unknown kind -> normal design.
	visuals.add(100, "wurstbrot", Vector3(0, 0, 9), 5.0)
	_check(visuals.design_of(100) == CORPSE_VISUALS.FALLBACK_KIND, "unknown kind falls back to the normal design")
	_check(CORPSE_VISUALS.rank_of("wurstbrot") == "normal", "unknown kind has normal rank")
	visuals.remove(100)

	# set_fill: the pool shrinks, remains of normal enemies shrink, boss bones stay.
	var prey_id := 1
	var boss_id := KINDS.find("boss") + 1
	var pool_before := _instance_scale(visuals, "pool", prey_id)
	var prey_before := _instance_scale(visuals, "prey", prey_id)
	var boss_before := _instance_scale(visuals, "boss", boss_id)
	var boss_pool_before := _instance_scale(visuals, "pool", boss_id)
	visuals.set_fill(prey_id, 0.1)
	visuals.set_fill(boss_id, 0.1)
	_check(_instance_scale(visuals, "pool", prey_id) < pool_before * 0.5, "prey pool shrinks at 10 %")
	_check(_instance_scale(visuals, "prey", prey_id) < prey_before * 0.7, "prey remains shrink at 10 %")
	_check(_instance_scale(visuals, "boss", boss_id) > boss_before * 0.9, "boss bones stay at 10 %")
	_check(_instance_scale(visuals, "pool", boss_id) < boss_pool_before * 0.5, "boss pool shrinks at 10 %")
	var custom: Color = _layer(visuals, "pool").customs[_layer(visuals, "pool").slot[prey_id]]
	_check(is_equal_approx(custom.r, 0.1), "fill is written to INSTANCE_CUSTOM.r")
	visuals.set_fill(prey_id, 1.0)
	_check(is_equal_approx(_instance_scale(visuals, "pool", prey_id), pool_before), "fill 1 restores the pool size")
	visuals.set_fill(999, 0.5)  # unknown id: ignored

	# remove: swap-remove keeps the other instances in place.
	var hunter_id := KINDS.find("hunter") + 1
	visuals.add(200, "hunter", Vector3(50, 0, 0), 8.0)
	visuals.add(201, "hunter", Vector3(60, 0, 0), 8.0)
	visuals.remove(hunter_id)
	_check(visuals.instances("hunter") == 2, "hunter batch shrinks on remove")
	var layer = _layer(visuals, "hunter")
	var moved_origin: Vector3 = layer.xforms[layer.slot[201]].origin
	_check(moved_origin.is_equal_approx(Vector3(60, 0, 0)), "swap-remove keeps the moved corpse at its place")
	_check(not visuals.has(hunter_id), "removed id is gone")
	visuals.remove(hunter_id)  # twice: harmless

	# clear: everything gone, batch nodes stay (reused next run).
	var nodes_before := visuals.get_child_count()
	visuals.clear()
	_check(visuals.count() == 0 and visuals.active_batches() == 0, "clear empties every batch")
	_check(visuals.get_child_count() == nodes_before, "clear keeps the batch nodes")

	# 60 mixed corpses (+ growth over the batch step): no node per corpse, <= MAX_BATCHES.
	for index in 300:
		visuals.add(1000 + index, KINDS[index % KINDS.size()], Vector3(index % 20, 0, index / 20) * 3.0, 10.0)
		if index == 59:
			_check(visuals.active_batches() <= MAX_BATCHES, "60 mixed corpses use <= %d batches (%d)" % [MAX_BATCHES, visuals.active_batches()])
			_check(visuals.get_child_count() <= MAX_BATCHES, "60 mixed corpses use <= %d nodes (%d)" % [MAX_BATCHES, visuals.get_child_count()])
	_check(visuals.count() == 300, "300 corpses tracked")
	_check(visuals.get_child_count() <= MAX_BATCHES, "300 corpses still <= %d nodes" % MAX_BATCHES)
	var per_kind := {}
	for index in 300:
		per_kind[KINDS[index % KINDS.size()]] = int(per_kind.get(KINDS[index % KINDS.size()], 0)) + 1
	var big_total: int = per_kind.boss + per_kind.apex + per_kind.apex_toad + per_kind.nest
	_check(visuals.instances("drop_big") == big_total, "%d big crystals (boss, apex, apex_toad, nest) in one batch" % big_total)
	_check(visuals.instances("boss") == per_kind.boss, "%d boss corpses in one batch" % per_kind.boss)
	_check(visuals.instances("apex_toad") == per_kind.apex_toad, "%d Aschenkröten corpses in one batch" % per_kind.apex_toad)
	# After growth every instance still has its own transform.
	var boss_layer = _layer(visuals, "boss")
	var first_boss := 1000 + KINDS.find("boss")
	var origin: Vector3 = boss_layer.xforms[boss_layer.slot[first_boss]].origin
	_check(origin.is_equal_approx(Vector3(first_boss - 1000, 0, 0) * 3.0), "grown batch keeps instance transforms")
	for index in 300:
		visuals.set_fill(1000 + index, 0.5)
		visuals.remove(1000 + index)
	_check(visuals.count() == 0 and visuals.active_batches() == 0, "all removed")
	for child in visuals.get_children():
		_check(not child.visible, "empty batch %s hidden" % child.name)
	# Every design mesh is a single surface (one draw call per batch).
	for child in visuals.get_children():
		_check((child as MultiMeshInstance3D).multimesh.mesh.get_surface_count() == 1, "%s has one surface" % child.name)
	# Real models are baked from a reduced import LOD: Moorbrut corpses stay tiny
	# (hundreds possible), the others stay within their triangle budget.
	for design: String in CORPSE_VISUALS.MODEL_TRIS:
		var design_mesh: Mesh = _layer(visuals, design).node.multimesh.mesh
		var tris: int = design_mesh.surface_get_array_index_len(0) / 3
		var budget: int = int(CORPSE_VISUALS.MODEL_TRIS[design])
		# Crown, splinters and spore sacs come on top of the animal itself.
		var extra := 800 if design == "elite" else 400
		_check(tris <= budget + extra, "%s remains within %d triangles (%d)" % [design, budget + extra, tris])
	var horde_mesh: Mesh = _layer(visuals, "horde").node.multimesh.mesh
	_check(horde_mesh.surface_get_array_index_len(0) / 3 <= int(CORPSE_VISUALS.MODEL_TRIS.horde), "Moorbrut remains are a low-poly LOD")

	holder.queue_free()
	await process_frame
	if failed:
		quit(1)
		return
	print("Corpse visuals test passed")
	quit(0)


func _layer(visuals: Node3D, layer_name: String):
	return visuals.layers[layer_name]


func _instance_scale(visuals: Node3D, layer_name: String, id: int) -> float:
	var layer = _layer(visuals, layer_name)
	return layer.xforms[layer.slot[id]].basis.get_scale().x


func _drop_scale(visuals: Node3D, layer_name: String, id: int, shard: int) -> float:
	var layer = _layer(visuals, layer_name)
	return layer.xforms[layer.slot[id * CORPSE_VISUALS.DROP_SLOTS + shard]].basis.get_scale().x


func _drop_height(visuals: Node3D, layer_name: String, id: int) -> float:
	return _drop_scale(visuals, layer_name, id, 0) * float(CORPSE_VISUALS.DROP_HEIGHT[layer_name])


func _check(condition: bool, label: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL: " + label)
		print("FAIL: " + label)
