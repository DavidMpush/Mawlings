extends SceneTree

# Review frames for the Aschenkröte (scripts/apex_toad.gd) in the Glutsumpf
# (run WITHOUT --headless, e.g. --screen 1 --audio-driver Dummy). The toad is
# not wired into HuntWorld yet, so it is placed by hand; the camera uses the
# pulled-back apex framing of tests/capture_apex.gd.

const TOAD = preload("res://scripts/apex_toad.gd")
const BIOMES = preload("res://scripts/biomes.gd")
const UI_STYLE = preload("res://scripts/ui/ui_style.gd")
const CAMERA_OFFSET := Vector3(0, 23, 15)
const ZOOM := 1.42

var scene: Node
var world: Variant
var swarm: Variant
var arena: Variant
var camera: Camera3D
var sun: DirectionalLight3D


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	arena = scene.get_node("Arena")
	camera = scene.get_node("Camera3D")
	sun = scene.get_node("Sun")
	var controls: Variant = scene.get_node("HUD/Controls")
	if controls.pause_requested.is_connected(world.toggle_pause):
		controls.pause_requested.disconnect(world.toggle_pause)
	scene.set_process(false)
	world.set_process(false)
	for prey in world.prey:
		prey.visible = false
	arena.set_biome("glutsumpf")
	var light: Dictionary = BIOMES.get_data("glutsumpf").light
	sun.light_color = light.color
	sun.light_energy = light.energy
	world.model.population = 90
	swarm.set_population(90)
	_frame(Vector3.ZERO, ZOOM)
	await _settle(1.0)
	var toad: Variant = await _spawn(Vector3(0, 0, -9.0))
	await _save("preview_apex_toad_arrival.png", "DIE ASCHENKRÖTE ERWACHT")
	# Aschensprung: crouch (zone marked), then mid-air.
	await _windup(toad, TOAD.Pattern.LEAP, 0.3)
	await _save("preview_apex_toad_leap.png", toad.hud_message())
	await _advance_windup(toad, 0.7)
	await _save("preview_apex_toad_leap_air.png", toad.hud_message())
	await _finish(toad, Vector3(6.5, 0, 0))
	await _save("preview_apex_toad_exhausted.png", "ASCHENKRÖTE ERSCHÖPFT · JETZT ANGREIFEN!")
	_reset(toad, Vector3(0, 0, -8.5))
	await _settle(0.4)
	# Glutspucke: circles, then the puddles.
	await _windup(toad, TOAD.Pattern.SPIT, 0.75)
	await _save("preview_apex_toad_spit.png", toad.hud_message())
	await _finish(toad, Vector3(0, 0, 3.5), 0.35)
	await _save("preview_apex_toad_puddles.png", "GLUTPFÜTZEN MEIDEN")
	await _advance(toad, 3.8, Vector3(0, 0, 3.5))
	_reset(toad, Vector3(-2.0, 0, -9.0))
	await _settle(0.4)
	# Zungenpeitsche.
	await _windup(toad, TOAD.Pattern.TONGUE, 0.65)
	await _save("preview_apex_toad_tongue.png", toad.hud_message())
	await _finish(toad, Vector3(2.5, 0, 0), 0.12)
	await _save("preview_apex_toad_tongue_strike.png", "ZUNGENPEITSCHE")
	await _settle(0.8)
	# Phase 2: combo, then the colour-blind palette of the same combo.
	toad.health = toad.max_health * 0.45
	await _advance(toad, TOAD.PHASE_SHIFT_SECONDS * 0.5, swarm.position)
	await _save("preview_apex_toad_phase2_roar.png", toad.hud_message())
	await _advance(toad, TOAD.PHASE_SHIFT_SECONDS * 0.5 + 0.1, swarm.position)
	_reset(toad, Vector3(1.5, 0, -8.5))
	await _settle(0.3)
	await _windup(toad, TOAD.Pattern.COMBO, 0.7)
	await _save("preview_apex_toad_phase2_combo.png", "PHASE 2 · " + toad.hud_message())
	UI_STYLE.colorblind = true
	toad.restyle(true)
	await _settle(0.15)
	await _save("preview_apex_toad_phase2_combo_cb.png", "FARBENBLIND · " + toad.hud_message())
	UI_STYLE.colorblind = false
	toad.restyle(false)
	await _finish(toad, Vector3(-2.5, 0, 2.5), 0.3)
	await _save("preview_apex_toad_phase2_puddles.png", "PHASE 2 · GLUTPFÜTZEN")
	print("Saved Aschenkröte review frames")
	quit()


func _spawn(location: Vector3) -> Variant:
	var toad: Variant = TOAD.new()
	toad.name = "Aschenkröte"
	toad.arena = arena
	toad.position = location
	world.add_child(toad)
	await _advance(toad, TOAD.ARRIVE_SECONDS * 0.8, swarm.position)
	return toad


func _reset(toad: Variant, location: Vector3) -> void:
	toad.state = TOAD.State.CHASE
	toad.cooldown = 999.0
	toad.position = location
	var facing: Vector3 = swarm.position - toad.position
	toad.rotation.y = atan2(facing.x, facing.z) + PI * 0.5
	toad.refresh_pose()


func _windup(toad: Variant, pattern: int, share: float) -> void:
	toad.state = TOAD.State.CHASE
	toad.begin_attack(pattern, swarm.position, 1.0)
	await _advance_windup(toad, share)


func _advance_windup(toad: Variant, share: float) -> void:
	while toad.state == TOAD.State.WINDUP and toad.windup_progress() < share:
		toad.step(1.0 / 60.0, swarm.position, 1.0)
		await process_frame


# Resolves the wind-up with the swarm moved aside (visual only), then waits `after` s.
func _finish(toad: Variant, dodge: Vector3, after: float = 0.9) -> void:
	swarm.position = dodge
	while toad.state == TOAD.State.WINDUP:
		toad.step(1.0 / 60.0, dodge, 1.0)
		await process_frame
	await _advance(toad, after, dodge)
	toad.cooldown = 999.0


func _advance(toad: Variant, seconds: float, target: Vector3) -> void:
	var steps := int(seconds * 60.0)
	for i in steps:
		toad.cooldown = 999.0
		toad.step(1.0 / 60.0, target, 1.0)
		await process_frame


func _frame(target: Vector3, zoom: float) -> void:
	camera.position = target + CAMERA_OFFSET * zoom
	camera.look_at(target, Vector3.UP)


func _settle(seconds: float) -> void:
	await create_timer(seconds).timeout


func _save(file_name: String, message: String) -> void:
	world._update_hud(message)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + file_name)
