extends Node3D

const RUN_MODEL = preload("res://scripts/run_model.gd")
const PREY = preload("res://scripts/prey.gd")
const HUNTER = preload("res://scripts/hunter.gd")
const TUNING = preload("res://scripts/tuning.gd")
const CORPSE_BIOMASS := TUNING.CORPSE_BIOMASS

@onready var swarm = get_parent().get_node("Swarm")
@onready var hud = get_parent().get_node("HUD/Controls")
var model = RUN_MODEL.new()
var prey: Array[Node3D] = []
var hunters: Array[Node3D] = []
var corpse_visuals: Dictionary = {}
var spawn_clock := 0.0
var hunter_clock := TUNING.FIRST_HUNTER_SECONDS
var spawn_number := 0
var paused := false
var hit_feedback := 0.0
var last_loss := 0


func _ready() -> void:
	_starting_prey()
	_update_hud("")


func _starting_prey() -> void:
	_spawn_prey(Vector3(-3.0, 0.0, -4.0))
	_spawn_prey(Vector3(4.0, 0.0, -2.0))
	_spawn_prey(Vector3(-2.0, 0.0, 5.0))


func reset_run() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	prey.clear()
	hunters.clear()
	corpse_visuals.clear()
	model = RUN_MODEL.new()
	spawn_clock = 0.0
	hunter_clock = TUNING.FIRST_HUNTER_SECONDS
	spawn_number = 0
	paused = false
	hit_feedback = 0.0
	last_loss = 0
	swarm.position = Vector3.ZERO
	swarm.set_population(model.population)
	swarm.set_controls(Vector2.ZERO, false)
	hud.clear_pointers()
	_starting_prey()
	_update_hud("")


func toggle_pause() -> void:
	if model.extinct:
		return
	paused = not paused
	hud.clear_pointers()
	swarm.set_controls(Vector2.ZERO, false)
	_update_hud("")


func _process(delta: float) -> void:
	# A stalled frame must not consume the whole player reaction window.
	step(minf(delta, 0.05))


func step(delta: float) -> void:
	if paused or model.extinct:
		return
	model.advance(delta)
	hit_feedback = maxf(0.0, hit_feedback - delta)
	var message := "Jage die türkisfarbene Beute"
	var pressure: float = model.pressure()
	var attack_range := 1.15 if swarm.rally_pressed else 1.5
	var damage := minf(32.0, 1.0 + float(model.population) * 0.12) * (1.55 if swarm.rally_pressed else 1.0)
	for target in prey.duplicate():
		# Living prey may be recycled at a distance; corpses never expire.
		if target.position.distance_to(swarm.position) > 40.0:
			prey.erase(target)
			target.queue_free()
			continue
		target.call("step", delta, swarm.position)
		if target.position.distance_to(swarm.position) < attack_range:
			var health: float = target.get("health") - damage * delta
			target.set("health", health)
			message = "Mawlings greifen automatisch an"
			if health <= 0.0:
				_kill_prey(target)
	for hunter in hunters.duplicate():
		if hunter.get("state") != HUNTER.State.ARRIVING and hunter.position.distance_to(swarm.position) < attack_range:
			hunter.call("take_damage", damage * delta)
			message = "Jäger angreifen · vor dem Ring ausweichen"
			if hunter.get("health") <= 0.0:
				hunters.erase(hunter)
				_create_corpse(hunter.position, TUNING.HUNTER_BIOMASS)
				hunter.queue_free()
				continue
		var velocity: Vector3 = Vector3(swarm.movement_vector.x, 0.0, swarm.movement_vector.y) * swarm.MOVE_SPEED
		var loss: int = hunter.call("step", delta, swarm.position, pressure, velocity)
		if loss > 0:
			last_loss = model.apply_loss(loss)
			swarm.set_population(model.population)
			hit_feedback = 1.2
			if model.extinct:
				swarm.set_controls(Vector2.ZERO, false)
				hud.clear_pointers()
				_update_hud("Ausgestorben")
				return
		if hunter.get("state") == HUNTER.State.WARNING:
			message = "RAUS AUS DEM ROTEN RING!"
	for corpse in model.corpses.duplicate():
		var id: int = corpse.id
		if corpse.position.distance_to(swarm.position) > TUNING.HARVEST_RADIUS:
			continue
		var rate := TUNING.HARVEST_RATE * (1.35 if swarm.rally_pressed else 1.0)
		var consumed: float = model.harvest(id, rate * delta)
		if consumed > 0.0:
			swarm.set_population(model.population)
			if not message.begins_with("RAUS"):
				message = "Biomasse ernten · Rally beschleunigt"
			_update_corpse(id, corpse.initial)
		elif model.population >= RUN_MODEL.MAX_POPULATION:
			message = "Schwarm voll — Biomasse bleibt liegen"
	spawn_clock += delta
	if spawn_clock >= TUNING.PREY_RESPAWN_SECONDS and prey.size() < TUNING.MAX_PREY:
		spawn_clock = 0.0
		_spawn_prey(_spawn_position(7.0))
	hunter_clock -= delta
	var hunter_budget := mini(TUNING.MAX_HUNTERS, 1 + int(model.elapsed / 35.0))
	if hunter_clock <= 0.0 and hunters.size() < hunter_budget:
		_spawn_hunter(_spawn_position(8.0))
		hunter_clock = maxf(2.5, 12.0 / sqrt(pressure))
	_update_hud(message)


func _spawn_position(radius: float) -> Vector3:
	spawn_number += 1
	var angle := float(spawn_number) * 2.39996323
	return swarm.position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


func _spawn_prey(location: Vector3) -> void:
	var target: Node3D = PREY.new()
	target.name = "Nibbler"
	target.position = location
	add_child(target)
	prey.append(target)


func _spawn_hunter(location: Vector3) -> Node3D:
	var target = HUNTER.new()
	target.name = "Hunter"
	target.position = location
	target.health = TUNING.HUNTER_HEALTH * sqrt(model.pressure())
	target.max_health = target.health
	add_child(target)
	hunters.append(target)
	return target


func _kill_prey(target: Node3D) -> void:
	prey.erase(target)
	_create_corpse(target.position, CORPSE_BIOMASS)
	target.queue_free()


func _create_corpse(location: Vector3, biomass: float) -> void:
	var id: int = model.add_corpse(location, biomass)
	if id < 0:
		return
	var visual := Node3D.new()
	visual.name = "Persistent corpse %d" % id
	visual.position = location
	add_child(visual)
	var amber := StandardMaterial3D.new()
	amber.albedo_color = Color("efb642")
	amber.roughness = 0.8
	var ring := CylinderMesh.new()
	ring.top_radius = 0.7
	ring.bottom_radius = 0.7
	ring.height = 0.06
	_piece(visual, ring, amber, Vector3(0.0, 0.05, 0.0))
	var core := SphereMesh.new()
	core.radius = 0.25
	core.height = 0.4
	_piece(visual, core, amber, Vector3(0.0, 0.25, 0.0))
	corpse_visuals[id] = visual


func _update_corpse(id: int, initial: float) -> void:
	var visual: Node3D = corpse_visuals.get(id)
	if visual == null:
		return
	var remaining: float = model.remaining_biomass(id)
	if remaining <= 0.0:
		corpse_visuals.erase(id)
		visual.queue_free()
	else:
		visual.scale = Vector3.ONE * (0.45 + 0.55 * remaining / initial)


func _piece(parent: Node3D, mesh: Mesh, material: Material, location: Vector3) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = location
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)


func _update_hud(message: String) -> void:
	hud.population = model.population
	hud.biomass_bank = model.biomass_bank
	hud.corpse_count = model.corpses.size()
	hud.kills = model.kills
	hud.elapsed = model.elapsed
	hud.pressure = model.pressure()
	hud.extinct = model.extinct
	hud.paused = paused
	hud.peak_population = model.peak_population
	hud.consumed_biomass = model.consumed_biomass
	hud.hit_feedback = hit_feedback
	hud.last_loss = last_loss
	hud.hint = message
	hud.nearest_corpse = ""
	var nearest := INF
	for corpse in model.corpses:
		var offset: Vector3 = corpse.position - swarm.position
		var distance := offset.length()
		if distance < nearest:
			nearest = distance
			var direction := "hier"
			if distance > TUNING.HARVEST_RADIUS:
				direction = ("oben" if offset.z < 0 else "unten") if absf(offset.z) > absf(offset.x) else ("links" if offset.x < 0 else "rechts")
			hud.nearest_corpse = "Kadaver: %dm · %s" % [int(distance), direction]
	hud.queue_redraw()
