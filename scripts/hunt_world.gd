extends Node3D

const RUN_MODEL = preload("res://scripts/run_model.gd")
const PREY = preload("res://scripts/prey.gd")
const CORPSE_BIOMASS := 12.0
const HARVEST_RATE := 4.0
const HARVEST_RADIUS := 1.55

@onready var swarm = get_parent().get_node("Swarm")
@onready var hud = get_parent().get_node("HUD/Controls")

var model = RUN_MODEL.new()
var prey: Array[Node3D] = []
var corpse_visuals: Dictionary = {}
var spawn_clock := 0.0
var spawn_number := 0


func _ready() -> void:
	_spawn_prey(Vector3(-3.0, 0.0, -4.0))
	_spawn_prey(Vector3(4.0, 0.0, -2.0))
	_spawn_prey(Vector3(-2.0, 0.0, 5.0))
	_update_hud("")


func _process(delta: float) -> void:
	var message := "Jage die tuerkisfarbene Beute"
	for target in prey.duplicate():
		target.call("step", delta, swarm.position)
		var distance: float = target.position.distance_to(swarm.position)
		if distance < (1.15 if swarm.rally_pressed else 1.5):
			var damage := minf(12.0, 1.0 + float(model.population) * 0.12)
			if swarm.rally_pressed:
				damage *= 1.55
			var health: float = target.get("health") - damage * delta
			target.set("health", health)
			message = "Mawlings greifen automatisch an"
			if health <= 0.0:
				_kill_prey(target)
	for corpse in model.corpses.duplicate():
		var id: int = corpse.id
		if corpse.position.distance_to(swarm.position) > HARVEST_RADIUS:
			continue
		var rate := HARVEST_RATE * (1.35 if swarm.rally_pressed else 1.0)
		var consumed: float = model.harvest(id, rate * delta)
		if consumed > 0.0:
			swarm.set_population(model.population)
			message = "Kadaver wird geerntet"
			_update_corpse(id)
		elif model.population >= RUN_MODEL.MAX_POPULATION:
			message = "Schwarm voll — Biomasse bleibt liegen"
	spawn_clock += delta
	if spawn_clock >= 14.0 and prey.size() < 3:
		spawn_clock = 0.0
		spawn_number += 1
		var angle := float(spawn_number) * 2.39996323
		_spawn_prey(swarm.position + Vector3(cos(angle) * 6.5, 0.0, sin(angle) * 6.5))
	_update_hud(message)


func _spawn_prey(location: Vector3) -> void:
	var target: Node3D = PREY.new()
	target.name = "Nibbler"
	target.position = location
	add_child(target)
	prey.append(target)


func _kill_prey(target: Node3D) -> void:
	prey.erase(target)
	var location := target.position
	target.queue_free()
	var id: int = model.add_corpse(location, CORPSE_BIOMASS)
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


func _update_corpse(id: int) -> void:
	var visual: Node3D = corpse_visuals.get(id)
	if visual == null:
		return
	var remaining: float = model.remaining_biomass(id)
	if remaining <= 0.0:
		corpse_visuals.erase(id)
		visual.queue_free()
	else:
		var ratio := 0.45 + 0.55 * remaining / CORPSE_BIOMASS
		visual.scale = Vector3.ONE * ratio


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
	hud.hint = message
	hud.queue_redraw()
