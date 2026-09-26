extends SceneTree

const HUNTER = preload("res://scripts/hunter.gd")


func _initialize() -> void:
	call_deferred("_run")


# Automated playtest through the same movement controls as the player.
# Run with --fixed-fps 60 so 7200 rendered frames are two game minutes.
func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var world: Variant = scene.get_node("HuntWorld")
	var swarm: Variant = scene.get_node("Swarm")
	var hud: Variant = scene.get_node("HUD/Controls")
	world.evolution.rng.seed = 19
	var frame_budget := 43200 if OS.get_cmdline_user_args().has("--very-long") else (21600 if OS.get_cmdline_user_args().has("--long") else 7200)
	for frame in frame_budget:
		if world.model.extinct:
			break
		if world.choosing():
			world.choose_mutation(0)
		var target: Vector3 = swarm.position
		var best := INF
		var harvesting := false
		for corpse in world.model.corpses:
			var distance: float = corpse.position.distance_to(swarm.position)
			if distance < best:
				best = distance
				target = corpse.position
				harvesting = true
		if not harvesting:
			for prey in world.prey:
				var distance: float = prey.position.distance_to(swarm.position)
				if distance < best:
					best = distance
					target = prey.position
		# Brutnest: go there when no corpse is close and no hunter warns.
		var calm := true
		for hunter in world.hunters:
			if hunter.get("state") == HUNTER.State.WARNING:
				calm = false
		if world.nest != null and calm and (not harvesting or best > 6.0):
			target = world.nest.position if world.nest.position.distance_to(swarm.position) > 1.2 else swarm.position
			harvesting = false
		var direction: Vector3 = target - swarm.position
		if harvesting and direction.length() < 1.0:
			direction = Vector3.ZERO
		var avoiding := false
		for hunter in world.hunters:
			if hunter.get("state") == HUNTER.State.WARNING:
				var away: Vector3 = swarm.position - hunter.get("attack_center")
				if away.length() < 3.1:
					direction = away.normalized() if away.length() > 0.01 else Vector3.RIGHT
					avoiding = true
					break
		if not avoiding:
			for leaper in world.leapers:
				if leaper.state in [leaper.State.WARNING, leaper.State.LEAP] and leaper.zone_margin(swarm.position) < 0.6:
					direction = leaper.dodge_direction(swarm.position)
					avoiding = true
					break
		if not avoiding:
			for skitter in world.skitters:
				if skitter.state in [skitter.State.WARNING, skitter.State.DASH] and skitter.warning_distance(swarm.position) < 1.8:
					direction = skitter.dodge_direction(swarm.position)
					avoiding = true
					break
		hud.movement_vector = Vector2(direction.x, direction.z).limit_length(1.0)
		hud.rally_pressed = best < 1.05 and not avoiding
		await process_frame
	print("PLAYTEST seconds=%.1f population=%d peak=%d kills=%d lost=%d corpses=%d hunters=%d skitters=%d nests=%d extinct=%s" % [world.model.elapsed, world.model.population, world.model.peak_population, world.model.kills, world.model.lost_population, world.model.corpses.size(), world.hunters.size(), world.skitters.size(), world.nests_completed, world.model.extinct])
	print("EVOLUTION level=%d build=%s" % [world.evolution.level, world.evolution.summary()])
	if world.evolution.level < 1 or world.model.kills < 3 or world.model.peak_population <= 25 or world.model.elapsed < 60.0:
		push_error("Automated food-and-dodge playtest could not establish the survival loop")
		quit(1)
		return
	quit(0)
