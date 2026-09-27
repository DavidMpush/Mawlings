extends SceneTree

# Review frames for the delivered 3D objectives (run WITHOUT --headless):
# Fluch-Totem model, Alpha-Kern model (swapped in here the way
# HuntWorld._drop_alpha_core should call alpha_core_visual.gd) and the
# Migrationsschlund pit model, each beside a small swarm in the game camera.

const ALPHA_CORE_VISUAL = preload("res://scripts/objectives/alpha_core_visual.gd")
const MIGRATION_MAW = preload("res://scripts/migration_maw.gd")

var scene: Node
var world: Variant
var swarm: Variant


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	var controls: Variant = scene.get_node("HUD/Controls")
	controls.pause_requested.disconnect(world.toggle_pause)
	await create_timer(0.3).timeout
	_quiet()
	world.model.population = 30
	swarm.set_population(30, false)
	# 1: totem and alpha core side by side above the swarm.
	world.spawn_totem(swarm.position + Vector3(-3.2, 0, -5.5))
	var core: Node3D = world._drop_alpha_core(swarm.position + Vector3(3.0, 0, -5.0))
	var float_root: Node3D = core.get_node("Float")
	for child in float_root.get_children():
		child.queue_free()
	ALPHA_CORE_VISUAL.attach(float_root)
	await create_timer(1.0).timeout
	await _save("preview_assets_v3_objectives.png")
	# 2: migration pit opened in front of the swarm.
	world.totem.queue_free()
	var maw: Node3D = MIGRATION_MAW.new()
	maw.setup("glutsumpf")
	maw.position = swarm.position + Vector3(0, 0, -7.0)
	world.add_child(maw)
	for i in 90:
		maw.step(1.0 / 60.0, 0.0)
	await create_timer(0.3).timeout
	await _save("preview_assets_v3_pit.png")
	# 3: swarm inside, hold arc half full.
	swarm.position = maw.position
	maw.hold = 0.5
	maw.step(0.016, 1.0)
	await create_timer(0.6).timeout
	await _save("preview_assets_v3_pit_hold.png")
	print("Saved assets v3 review frames")
	quit()


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


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + file_name)
