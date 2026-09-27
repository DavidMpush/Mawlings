extends SceneTree

# Etappe 09 GEFÜHL review frames (real window, real time; never --headless):
# lone leader with pips, a cell division in three steps, the 5 milestone,
# a leader hit, the crown jumping to a successor, the last animal with the red
# vignette and a larger swarm with the leader in its centre.
#   Godot --path . --screen 1 --audio-driver Dummy --script res://tests/capture_lone.gd

var scene: Node
var world: Variant
var swarm: Variant
var controls: Variant


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	controls = scene.get_node("HUD/Controls")
	# Background capture windows lose focus; the auto-pause must not end up in the frames.
	controls.pause_requested.disconnect(world.toggle_pause)
	await process_frame
	# The world itself stands still (no spawns); the HUD is fed by hand.
	world.set_process(false)
	_clear_threats()
	_set_population(1)
	await _hold(0.9)
	await _save("preview_lone_start.png")

	# One division, three moments: swell, pinch, slide out.
	_grow(1)
	await _hold(0.14)
	await _save("preview_lone_split_1.png")
	await _hold(0.13)
	await _save("preview_lone_split_2.png")
	await _hold(0.14)
	await _save("preview_lone_split_3.png")
	await _hold(0.6)

	# Three at once reach the 5 milestone (banner, glow, staggered divisions).
	_grow(3)
	await _hold(0.38)
	await _save("preview_lone_milestone.png")
	await _hold(1.8)

	# Leader hit: a pip breaks, red flash, blinking afterwards.
	_invulnerable(false)
	world._apply_hit(0, swarm.position + Vector3(1.2, 0.0, 0.6), 0.25, null, true)
	await _hold(0.13)
	await _save("preview_lone_leader_hit.png")
	await _hold(0.5)
	await _save("preview_lone_leader_blink.png")
	await _hold(0.6)

	# Leader with 1 LP falls: the crown jumps to the successor.
	_invulnerable(false)
	world.model.leader_hp = 1
	world._apply_hit(0, swarm.position + Vector3(-1.0, 0.0, 0.8), 0.25, null, true)
	await _hold(0.24)
	await _save("preview_lone_swap.png")
	await _hold(1.2)

	# Down to the last animal: heartbeat and red vignette.
	var loss: int = world.model.population - 1
	_invulnerable(true)
	world._apply_hit(loss, swarm.position + Vector3(0.8, 0.0, -0.8), 0.3)
	await _hold(0.75)
	await _save("preview_lone_last.png")

	# A bigger swarm: leader in the centre, animals already smaller.
	_invulnerable(false)
	_grow(59)
	await _hold(1.6)
	await _save("preview_lone_mass.png")
	print("Saved lone start review frames (heartbeat loop %s)" % ("on" if swarm.heartbeat_on else "off"))
	quit()


func _clear_threats() -> void:
	for group in ["hunters", "skitters", "leapers"]:
		var list: Variant = world.get(group)
		if list is Array:
			for enemy in list:
				if is_instance_valid(enemy):
					enemy.queue_free()
			(list as Array).clear()


func _set_population(value: int) -> void:
	world.model.population = value
	world.model.peak_population = value
	swarm.set_population(value, false)
	if world.has_method("_sync_leader"):
		world.leader_state_key = Vector3i(-1, -1, -1)
		world._sync_leader()
	world._update_hud("")


# Growth through the game's own path (model, swarm division, milestone, HUD).
func _grow(count: int) -> void:
	var before: int = world.model.population
	world.model.population = before + count
	world.model.peak_population = maxi(world.model.peak_population, world.model.population)
	if world.model.has_method("_note_growth"):
		world.model._note_growth()
	swarm.set_population(world.model.population)
	if world.has_method("_on_growth"):
		world._on_growth(count)
	world._update_hud("")


func _invulnerable(on: bool) -> void:
	if "leader_invulnerable" in world.model:
		world.model.leader_invulnerable = 5.0 if on else 0.0
	if world.has_method("_sync_leader"):
		world._sync_leader()


# Waits real time while the HUD keeps getting fresh values.
func _hold(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		world._update_hud("")
		await process_frame


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + file_name)
