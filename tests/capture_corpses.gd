extends SceneTree

# Review frames for the corpse designs (scripts/corpse_visuals.gd) in the game's
# "empty" mode (Etappe 16: remains are decoration, the loot lies in crystals).
# Run WITHOUT --headless, e.g.
#   Godot_console.exe --screen 1 --audio-driver Dummy --path . --script res://tests/capture_corpses.gd
# preview_corpses_kinds.png    every kind side by side as it lies in the game
# preview_corpses_compare.png  living hunter / elite / skitter / leaper (top row)
#                              next to their remains (bottom row): dead must read dead
# preview_corpses_sink.png     remains at decay 0 / 0.5 / 0.85 (rows far -> near)
# preview_corpses_boss.png     Bog King, Moosschlund and Aschenkröte remains
# plus the draw-call cost of 60 mixed corpses (printed)

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
	for target in world.prey:
		target.queue_free()
	world.prey.clear()
	world.hunter_clock = 1.0e9
	world.skitter_clock = 1.0e9
	world.leaper_clock = 1.0e9
	world.boss_clock = 1.0e9
	world.elite_clock = 1.0e9
	world.nest_clock = 1.0e9
	world.spawn_clock = -1.0e9
	world.flood_start = 1.0e9
	world.apex_state = 4
	visuals = CORPSE_VISUALS.new()
	visuals.name = "Corpse visuals"
	visuals.empty = true
	world.add_child(visuals)
	var center: Vector3 = swarm.position
	swarm.visible = false
	world.set_process(false)

	# 1: every kind as it lies in the game.
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

	# 2: living enemies (top) next to their remains (bottom).
	visuals.clear()
	var living: Array = []
	living.append(world._spawn_hunter(center + Vector3(-4.2, 0, -4.5)))
	living.append(world.spawn_elite(center + Vector3(-1.2, 0, -4.5)))
	living.append(world._spawn_skitter(center + Vector3(1.6, 0, -4.5)))
	living.append(world._spawn_leaper(center + Vector3(4.4, 0, -4.5)))
	_put("hunter", center + Vector3(-4.2, 0, 1.5))
	_put("elite", center + Vector3(-1.2, 0, 1.5))
	_put("skitter", center + Vector3(1.6, 0, 1.5))
	_put("leaper", center + Vector3(4.4, 0, 1.5))
	_put("horde", center + Vector3(-3.0, 0, 5.0))
	_put("prey", center + Vector3(0.0, 0, 5.0))
	_put("horde", center + Vector3(3.0, 0, 5.0))
	await _settle(center)
	await _save("preview_corpses_compare.png")
	for enemy in living:
		if enemy != null and is_instance_valid(enemy):
			enemy.queue_free()
	world.hunters.clear()
	world.skitters.clear()
	world.leapers.clear()

	# 3: sinking (rows far -> near: decay 0 / 0.5 / 0.85).
	visuals.clear()
	var decays := [0.0, 0.5, 0.85]
	var columns := ["prey", "hunter", "skitter", "horde", "elite", "leaper", "nest"]
	for row in decays.size():
		for column in columns.size():
			var x := -5.4 + 1.8 * float(column)
			var id := _put(columns[column], center + Vector3(x, 0, -6.0 + 5.2 * float(row)), 0.0)
			visuals.set_decay(id, decays[row])
	await _settle(center)
	await _save("preview_corpses_sink.png")

	# 4: the three boss carcasses.
	visuals.clear()
	_put("boss", center + Vector3(-2.5, 0, -7.0), 0.5)
	_put("apex", center + Vector3(2.0, 0, 0.0), -0.4)
	_put("apex_toad", center + Vector3(-2.0, 0, 7.0), 0.2)
	await _settle(center)
	await _save("preview_corpses_boss.png")

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
