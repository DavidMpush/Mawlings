extends SceneTree

# Review frames for Etappe 16 "Beute-Kristalle und Magnet" (run WITHOUT --headless:
#   Godot_console.exe --screen 1 --audio-driver Dummy --path . --script res://tests/capture_loot_magnet.gd):
#   preview_loot_burst.png    kills burst into crystals (mid-hop), outside the magnet
#   preview_loot_magnet.png   the swarm steps closer: the crystals fly in as a chain
#   preview_loot_counter.png  arrivals add up into one growing "+N" at the swarm
#   preview_loot_lure.png     a Lockruf beside the swarm, crystals lying all over the map
#   preview_loot_vacuum.png   Lockruf taken: every crystal of the map streams in
#   preview_loot_midgame.png  ~60 Mawlings mid-run: live hunters, kill bursts, counter, loss number
#   preview_loot_flood.png    late flood: many kills, crystals and the magnet at work

const LOOT = preload("res://scripts/loot.gd")
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
	controls.pause_requested.disconnect(world.toggle_pause)
	await create_timer(1.2).timeout
	_quiet()
	world.model.population = 45
	swarm.set_population(45, false)
	await _wait(0.6, 45)
	# 1: three hunters and an elite die ~7 m away (outside the ~5 m magnet).
	var here: Vector3 = swarm.position
	var spots := [Vector3(-5.5, 0, -5.0), Vector3(5.8, 0, -4.2), Vector3(-1.0, 0, -8.0), Vector3(4.0, 0, 3.0)]
	for index in spots.size():
		var hunter: Variant = world._spawn_hunter(here + spots[index])
		if index == 2:
			hunter.make_elite(4.0)
		hunter.health = 0.0
		world._resolve_death(hunter, "hunter")
	# The elite's Lockruf would end this scene early; picture 3 has its own.
	for lure in world.loot.lures:
		lure.node.queue_free()
	world.loot.lures.clear()
	await _wait(0.18, 45)
	await _save("preview_loot_burst.png")
	await _wait(0.6, 45)
	# 2: step towards them - the magnet pulls the chain in.
	swarm.position = here + Vector3(0.0, 0, -3.5)
	await _wait(0.16, 45)
	await _save("preview_loot_magnet.png")
	await _wait(0.34, 45)
	await _save("preview_loot_counter.png")
	# 3: crystals all over the map (a long hunt), a Lockruf beside the swarm.
	world.loot.clear()
	world.kill_popups.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 16
	here = swarm.position
	for index in 70:
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(7.0, 60.0)
		var at: Vector3 = here + Vector3(cos(angle), 0, sin(angle)) * distance
		world.drop_loot(at, rng.randf_range(3.0, 8.0), 10 if index % 3 == 0 else 0, "normal")
	await _wait(0.8, 45)
	world.drop_lure(here + Vector3(2.5, 0, -6.5))
	await _wait(0.5, 45)
	await _save("preview_loot_lure.png")
	# 4: walk into it: the whole map streams in.
	swarm.position = here + Vector3(1.5, 0, -3.5)
	var waited := 0
	while world.lures_collected == 0 and waited < 90:
		await process_frame
		_keep_alive(45)
		waited += 1
	await _wait(0.45, 45)
	await _save("preview_loot_vacuum.png")
	await _wait(3.0, 45)
	# 5: a normal mid-run moment: ~60 Mawlings, living hunters around, fresh kills
	# bursting, crystals flying in, the growing counter and a loss number.
	world.loot.clear()
	world.kill_popups.clear()
	world.model.population = 60
	swarm.set_population(60, false)
	await _wait(0.5, 60)
	here = swarm.position
	var living: Array = []
	for spot in [Vector3(-6.5, 0, -3.0), Vector3(6.0, 0, 2.5), Vector3(-2.0, 0, 7.5)]:
		living.append(world._spawn_hunter(here + spot))
	for spot in [Vector3(3.2, 0, -4.0), Vector3(-3.8, 0, -5.5), Vector3(4.5, 0, 5.0)]:
		var victim: Variant = world._spawn_hunter(here + spot)
		victim.health = 0.0
		world._resolve_death(victim, "hunter")
	for lure in world.loot.lures:
		lure.node.queue_free()
	world.loot.lures.clear()
	for index in 10:
		var angle := TAU * float(index) / 10.0
		world.drop_loot(here + Vector3(cos(angle), 0, sin(angle)) * rng.randf_range(9.0, 14.0), 3.0, 5 if index % 4 == 0 else 0, "normal")
	await _wait(0.9, 60)
	world.hit_feedback = 1.0
	world.last_loss = 4
	await _wait(0.2, 60)
	await _save("preview_loot_midgame.png")
	for enemy in living:
		if is_instance_valid(enemy) and world.hunters.has(enemy):
			world.hunters.erase(enemy)
			enemy.queue_free()
	# 6: late flood - a horde ring right at the swarm, kills burst into crystals.
	world.loot.clear()
	world.kill_popups.clear()
	world.model.population = 160
	swarm.set_population(160, false)
	world.flood_start = world.model.elapsed - 60.0
	world.flood_state = 2
	world.flood_lure_stage = 99
	world.evolution.ranks["sporenwolke"] = 3
	world._sync_attack_forms()
	var horde: Variant = world.horde
	if horde != null:
		var stats: Dictionary = world.flood_stats()
		stats.hp = 1.5
		horde.spawn_ring(swarm.position, 70, 7.5, stats)
		horde.spawn_ring(swarm.position, 50, 11.0, stats)
	await _wait(1.6, 160)
	# A few older kills further out wait for the magnet.
	for index in 14:
		var angle := TAU * float(index) / 14.0
		world.drop_loot(swarm.position + Vector3(cos(angle), 0, sin(angle)) * rng.randf_range(8.0, 12.0), 1.2, 1, "normal")
	await _wait(0.6, 160)
	await _save("preview_loot_flood.png")
	print("Saved loot review frames (%d crystals collected, %d Lockrufe)" % [world.crystals_collected, world.lures_collected])
	quit()


func _wait(seconds: float, population: int) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame
		_keep_alive(population)


func _keep_alive(population: int) -> void:
	world.evolution.offers.clear()
	world.model.leader_hp = maxi(world.model.leader_hp, 2)
	if world.model.extinct or world.model.population < population / 2:
		world.model.extinct = false
		world.model.population = population
		swarm.set_population(population, false)


func _quiet() -> void:
	for target in world.prey:
		target.queue_free()
	world.prey.clear()
	world.spawn_clock = -1000000.0
	world.hunter_clock = 1000000.0
	world.skitter_clock = 1000000.0
	world.leaper_clock = 1000000.0
	world.boss_clock = 1000000.0
	world.elite_clock = 1000000.0
	world.nest_clock = 1000000.0
	world.flood_start = 1.0e9
	world.apex_state = 4
	world.hunters_unlocked = true


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/" + file_name)
