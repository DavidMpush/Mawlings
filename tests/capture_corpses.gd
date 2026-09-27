extends SceneTree

# Review frames for the corpse designs (scripts/corpse_visuals.gd). Run WITHOUT
# --headless, e.g.
#   Godot_console.exe --screen 1 --audio-driver Dummy --path . --script res://tests/capture_corpses.gd
# preview_corpses_kinds.png   all kinds side by side, full biomass
# preview_corpses_fill.png    normal + mini-boss kinds at 100 / 50 / 10 %
# preview_corpses_boss.png    Bog King carcass at 100 / 50 / 10 %
# preview_corpses_apex.png    Moosschlund carcass at 100 / 50 / 10 %
# (every corpse carries its biomass crystal: small shards, medium, big)
# plus the draw-call cost of 60 mixed corpses (printed)
# preview_corpses_swarm.png   the swarm feeding on a Bog King carcass

const CORPSE_VISUALS = preload("res://scripts/corpse_visuals.gd")

var scene: Node
var world: Variant
var swarm: Variant
var visuals: Node3D
var next_id := 1


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	var controls: Variant = scene.get_node("HUD/Controls")
	# Background capture windows lose focus; the auto-pause must not end up in the frames.
	controls.pause_requested.disconnect(world.toggle_pause)
	await create_timer(1.0).timeout
	# Freeze the hunt (no spawns, no harvest); camera and swarm animation keep running.
	for target in world.prey:
		target.queue_free()
	world.prey.clear()
	world.set_process(false)
	visuals = CORPSE_VISUALS.new()
	visuals.name = "Corpse visuals"
	world.add_child(visuals)
	var center: Vector3 = swarm.position
	swarm.visible = false

	# 1: every kind at full biomass, by rank (bosses far, normal ones near).
	_put("boss", center + Vector3(-3.4, 0, -9.5), 0.35)
	_put("apex", center + Vector3(3.6, 0, -9.0), -0.35)
	_put("elite", center + Vector3(-4.3, 0, -2.2))
	_put("leaper", center + Vector3(0.0, 0, -2.0))
	_put("nest", center + Vector3(4.3, 0, -2.2))
	_put("prey", center + Vector3(-5.2, 0, 3.6))
	_put("hunter", center + Vector3(-2.6, 0, 3.6))
	_put("skitter", center + Vector3(0.0, 0, 3.6))
	_put("horde", center + Vector3(2.4, 0, 3.6))
	_put("mawling", center + Vector3(4.6, 0, 3.6))
	await _settle(center)
	await _save("preview_corpses_kinds.png")

	# 2: fill levels 100 / 50 / 10 % (rows far -> near).
	visuals.clear()
	var fills := [1.0, 0.5, 0.1]
	var columns := ["prey", "hunter", "skitter", "horde", "elite", "leaper", "nest"]
	for row in fills.size():
		for column in columns.size():
			var x := -5.4 + 1.8 * float(column)
			var id := _put(columns[column], center + Vector3(x, 0, -6.0 + 5.2 * float(row)), 0.0)
			visuals.set_fill(id, fills[row])
	await _settle(center)
	await _save("preview_corpses_fill.png")

	# 3/4: boss carcasses at 100 / 50 / 10 % (rows far -> near), one image each.
	for kind in ["boss", "apex"]:
		visuals.clear()
		for row in fills.size():
			var boss_id := _put(kind, center + Vector3(-0.6 + 0.8 * float(row), 0, -6.5 + 6.0 * float(row)), PI * 0.5 + 0.15)
			visuals.set_fill(boss_id, fills[row])
		await _settle(center)
		await _save("preview_corpses_%s.png" % kind)

	# Draw-call cost of 60 mixed corpses (visible vs hidden), all in view.
	visuals.clear()
	var kinds: Array = CORPSE_VISUALS.KIND_DESIGN.keys()
	for index in 60:
		_put(kinds[index % kinds.size()], center + Vector3(-6.0 + 1.35 * float(index % 10), 0, -7.0 + 2.4 * float(index / 10)), null)
	await _settle(center)
	var with_corpses := await _draw_calls()
	visuals.visible = false
	var without := await _draw_calls()
	visuals.visible = true
	print("60 mixed corpses: %d draw calls (%d with, %d without), %d batches" % [with_corpses - without, with_corpses, without, visuals.active_batches()])

	# 4: the swarm feeding on a Bog King carcass, a few small corpses around.
	visuals.clear()
	swarm.visible = true
	world.model.population = 60
	swarm.set_population(60, false)
	var carcass: Vector3 = center + Vector3(0, 0, -1.0)
	var carcass_id := _put("boss", carcass, 0.6)
	visuals.set_fill(carcass_id, 0.7)
	_put("hunter", center + Vector3(-4.5, 0, 3.5), 0.4)
	_put("prey", center + Vector3(4.2, 0, 4.2), 1.0)
	_put("mawling", center + Vector3(2.8, 0, -6.5))
	_put("horde", center + Vector3(-3.6, 0, -6.0))
	swarm.set_focus(carcass, 1)
	await _settle(center)
	await create_timer(0.8).timeout
	await _save("preview_corpses_swarm.png")
	print("Saved corpse review frames")
	quit()


# Adds one corpse; yaw overrides the random facing (null = keep).
func _put(kind: String, location: Vector3, yaw: Variant = null) -> int:
	var id := next_id
	next_id += 1
	visuals.add(id, kind, location, float(CORPSE_VISUALS.DESIGNS[kind].ref))
	if yaw != null:
		visuals.corpses[id].yaw = yaw
		visuals._apply(id)
	return id


func _settle(center: Vector3) -> void:
	swarm.position = center
	scene._snap_camera()
	for frame in 20:
		await process_frame


func _draw_calls() -> int:
	var total := 0
	for frame in 6:
		await RenderingServer.frame_post_draw
		total = maxi(total, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	return total


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + file_name)
