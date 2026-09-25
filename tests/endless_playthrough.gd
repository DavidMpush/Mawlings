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
	var frame_budget := 21600 if OS.get_cmdline_user_args().has("--long") else 7200
	for frame in frame_budget:
		if world.model.extinct:
			break
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
		hud.movement_vector = Vector2(direction.x, direction.z).limit_length(1.0)
		hud.rally_pressed = best < 1.05 and not avoiding
		await process_frame
	print("PLAYTEST seconds=%.1f population=%d peak=%d kills=%d lost=%d corpses=%d hunters=%d extinct=%s" % [world.model.elapsed, world.model.population, world.model.peak_population, world.model.kills, world.model.lost_population, world.model.corpses.size(), world.hunters.size(), world.model.extinct])
	if world.model.kills < 3 or world.model.peak_population <= 25 or world.model.elapsed < 60.0:
		push_error("Automated food-and-dodge playtest could not establish the survival loop")
		quit(1)
		return
	quit(0)
