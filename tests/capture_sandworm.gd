extends SceneTree

# Review frames for the Sandwurm (scripts/apex_sandworm.gd), the Sandmaden
# (scripts/sandgrub.gd) and the desert props of stage 19 phase 1. Run WITHOUT
# --headless, e.g.:
#   Godot_console.exe --screen 1 --audio-driver Dummy --path . --script res://tests/capture_sandworm.gd
# The desert map does not exist yet (phase 2), so the real game scene is used
# with its arena hidden and a test floor in the "duerrschlund" palette of
# biomes.gd (sand with ripples and cool shadows, a packed-sand path, an oasis)
# plus a few desert props. Camera = the pulled-back apex framing of the toad.

const WORM = preload("res://scripts/apex_sandworm.gd")
const GRUBS = preload("res://scripts/sandgrub.gd")
const CORPSES = preload("res://scripts/corpse_visuals.gd")
const BIOMES = preload("res://scripts/biomes.gd")
const UI_STYLE = preload("res://scripts/ui/ui_style.gd")
const PROP_SHADER = preload("res://shaders/prop_fade.gdshader")
const CAMERA_OFFSET := Vector3(0, 23, 15)
const ZOOM := 1.42
const DT := 1.0 / 60.0
const PROPS := {
	"RibBones": preload("res://assets/gameplay/props/RibBones_game.glb"),
	"SandstoneCliff": preload("res://assets/gameplay/props/SandstoneCliff_game.glb"),
	"RockArch": preload("res://assets/gameplay/props/RockArch_game.glb"),
	"Cactus": preload("res://assets/gameplay/props/Cactus_game.glb"),
	"GiantSkull": preload("res://assets/gameplay/props/GiantSkull_game.glb"),
	"SandPortal": preload("res://assets/gameplay/props/SandPortal_game.glb"),
}
const GROUND_CODE := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform vec4 dune_light : source_color;
uniform vec4 dune_shadow : source_color;
uniform vec4 shadow_cool : source_color;
uniform vec4 ripple : source_color;
uniform float ripple_amount = 0.4;
varying vec3 world;
void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec2 p = world.xz;
	// Broad dunes: light crests, cool blue-grey troughs (never orange).
	float dune = noise(p * 0.035) * 0.65 + noise(p * 0.09 + 3.1) * 0.35;
	vec3 color = mix(dune_shadow.rgb, dune_light.rgb, smoothstep(0.25, 0.75, dune));
	color = mix(color, shadow_cool.rgb, (1.0 - smoothstep(0.1, 0.4, dune)) * 0.35);
	// Wind ripples: thin bent stripes.
	float bend = noise(p * 0.05) * 6.0;
	float stripe = sin(p.x * 2.4 + p.y * 0.8 + bend);
	color = mix(color, ripple.rgb, smoothstep(0.85, 0.99, stripe) * ripple_amount * 0.6);
	ALBEDO = color;
	ROUGHNESS = 0.95;
}
"""

var scene: Node
var world: Variant
var swarm: Variant
var arena: Variant
var camera: Camera3D
var sun: DirectionalLight3D
var desert: Dictionary
var stage: Node3D
var grubs: Variant


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	desert = BIOMES.get_data("duerrschlund")
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
	arena.visible = false
	sun.light_color = desert.light.color
	sun.light_energy = desert.light.energy
	_build_stage()
	world.model.population = 90
	swarm.set_population(90)
	swarm.position = Vector3.ZERO

	_frame(Vector3.ZERO, ZOOM)
	await _settle(1.0)

	var worm: Variant = WORM.new()
	worm.name = "Sandwurm"
	worm.arena = stage
	worm.position = Vector3(-6, 0, -10)
	world.add_child(worm)
	# 2) Arrival: bursts out vertically.
	await _advance(worm, WORM.ARRIVE_SECONDS * 0.62, swarm.position)
	await _save("preview_sandworm_arrival.png", worm.hud_message())
	await _advance(worm, WORM.ARRIVE_SECONDS * 0.4 + WORM.DIVE_SECONDS + 1.6, swarm.position)
	# 3) Burrowing: sand trail circling the swarm.
	await _save("preview_sandworm_trail.png", "DER SANDWURM GRÄBT · SPUR IM SAND")
	# 4) Breach warning ring under the swarm.
	worm.state = WORM.State.CHASE
	worm.dive = 0.0
	worm.begin_attack(WORM.Pattern.BREACH, swarm.position, 1.0)
	await _advance_windup(worm, 0.6)
	await _save("preview_sandworm_breach_warning.png", worm.hud_message())
	# 5) The breach itself (swarm dodged sideways).
	var dodge := Vector3(6.5, 0, 1.5)
	swarm.position = dodge
	while worm.state == WORM.State.WINDUP:
		worm.step(DT, dodge, 1.0)
		await process_frame
	await _advance(worm, 0.25, dodge)
	await _save("preview_sandworm_breach.png", "DURCHBRUCH!")
	# 6) Exhausted beside the hole: the attack window.
	await _advance(worm, 0.9, dodge)
	await _save("preview_sandworm_exhausted.png", worm.hud_message())
	await _advance(worm, WORM.EXHAUSTED_SECONDS[0] + WORM.DIVE_SECONDS, dodge)
	# 7) Tail sweep: half surfaced beside the swarm, cone through it.
	swarm.position = Vector3.ZERO
	worm.position = Vector3(-5, 0, -3)
	worm.state = WORM.State.CHASE
	worm.dive = 0.0
	worm.begin_attack(WORM.Pattern.SWEEP, swarm.position, 1.0)
	await _advance_windup(worm, 0.7)
	await _save("preview_sandworm_sweep.png", worm.hud_message())
	UI_STYLE.colorblind = true
	worm.restyle(true)
	await _settle(0.1)
	await _save("preview_sandworm_sweep_cb.png", "FARBENBLIND · " + worm.hud_message())
	UI_STYLE.colorblind = false
	worm.restyle(false)
	var aside := Vector3(0, 0, 5.5)
	swarm.position = aside
	while worm.state == WORM.State.WINDUP:
		worm.step(DT, aside, 1.0)
		await process_frame
	await _advance(worm, 0.2, aside)
	await _save("preview_sandworm_sweep_strike.png", "SCHWANZFEGER!")
	await _advance(worm, 1.2, aside)
	# 8) Phase 2: rage + Sandmaden breaking out and running at the swarm.
	swarm.position = Vector3.ZERO
	grubs = GRUBS.new()
	grubs.name = "Sandmaden"
	world.add_child(grubs)
	grubs.setup(world, swarm, null)
	worm.position = Vector3(-4, 0, -9)
	worm.health = worm.max_health * 0.45
	await _advance(worm, WORM.PHASE_SHIFT_SECONDS * 0.45, swarm.position)
	await _save("preview_sandworm_phase2.png", worm.hud_message())
	await _advance(worm, 0.2, swarm.position)
	await _save("preview_sandworm_phase2_grubs.png", "SANDMADEN! · %d" % grubs.count())
	# Close-up of the grubs running in (camera closer, swarm aside).
	grubs.clear()
	swarm.position = Vector3(3, 0, 3)
	grubs.spawn_burst(Vector3(-2, 0, -2), 6)
	_frame(Vector3(0, 0, 0), 0.75)
	for i in 50:
		_step_grubs(DT)
		await process_frame
	await _save("preview_sandworm_grubs_close.png", "SANDMADEN · NAHANSICHT")
	_frame(Vector3.ZERO, ZOOM)
	swarm.position = Vector3.ZERO
	await _advance(worm, WORM.DIVE_SECONDS + 0.2, swarm.position)
	# Phase-2 breach with a second batch of grubs.
	worm.state = WORM.State.CHASE
	worm.dive = 0.0
	worm.position = Vector3(3, 0, -6)
	worm.begin_attack(WORM.Pattern.BREACH, Vector3(4, 0, -5), 1.0)
	while worm.state == WORM.State.WINDUP:
		worm.step(DT, swarm.position, 1.0)
		_step_grubs(DT)
		await process_frame
	await _advance(worm, 0.3, swarm.position)
	await _save("preview_sandworm_phase2_breach.png", "PHASE 2 · DURCHBRUCH + SANDMADEN")
	# 9) Corpses: the worm (empty, ash look like in a run) and a few grubs.
	grubs.clear()
	worm.visible = false
	var visuals: Variant = CORPSES.new()
	visuals.name = "Corpses"
	visuals.empty = true
	world.add_child(visuals)
	visuals.add(1, "apex_sandworm", Vector3(-3, 0, -8), 60.0)
	for index in 4:
		visuals.add(10 + index, "sandgrub", Vector3(3.5 + index * 1.3, 0, -3.0 + (index % 2) * 1.2), 0.6)
	var full: Variant = CORPSES.new()
	full.name = "Corpses full"
	world.add_child(full)
	full.add(2, "apex_sandworm", Vector3(8, 0, 9), 60.0)
	full.add(20, "sandgrub", Vector3(-4, 0, 7), 0.6)
	_frame(Vector3(1, 0, 0), 1.9)
	await _settle(0.8)
	await _save("preview_sandworm_corpse.png", "KADAVER · LEER (VORN) UND MIT KRISTALL (HINTEN)")
	# 10) Prop overview (pulled back, no boss, no corpses).
	visuals.visible = false
	full.visible = false
	_frame(Vector3(0, 0, -6), 2.1)
	await _settle(0.4)
	await _save("preview_sandworm_props.png", "DÜRRSCHLUND · RIPPEN · KLIPPE · BOGEN · KAKTUS · SCHÄDEL · PORTAL")
	print("Saved Sandwurm review frames")
	quit()


func _build_stage() -> void:
	stage = Node3D.new()
	stage.name = "Desert test stage"
	scene.add_child(stage)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	ground.mesh = plane
	var shader := Shader.new()
	shader.code = GROUND_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	var look: Dictionary = desert.desert
	material.set_shader_parameter("dune_light", look.dune_light)
	material.set_shader_parameter("dune_shadow", look.dune_shadow)
	material.set_shader_parameter("shadow_cool", look.shadow_cool)
	material.set_shader_parameter("ripple", look.ripple)
	material.set_shader_parameter("ripple_amount", look.ripple_amount)
	ground.material_override = material
	stage.add_child(ground)
	# Packed-sand path and an oasis clearing.
	var path := MeshInstance3D.new()
	var strip := PlaneMesh.new()
	strip.size = Vector2(5.0, 60.0)
	path.mesh = strip
	path.material_override = _flat(desert.path)
	path.position = Vector3(-15, 0.02, 0)
	path.rotation.y = 0.35
	stage.add_child(path)
	var rim := MeshInstance3D.new()
	var rim_mesh := CylinderMesh.new()
	rim_mesh.top_radius = 6.2
	rim_mesh.bottom_radius = 6.2
	rim_mesh.height = 0.04
	rim.mesh = rim_mesh
	rim.material_override = _flat(desert.shore)
	rim.position = Vector3(-14, 0.02, 16)
	stage.add_child(rim)
	var water := MeshInstance3D.new()
	var water_mesh := CylinderMesh.new()
	water_mesh.top_radius = 4.8
	water_mesh.bottom_radius = 4.8
	water_mesh.height = 0.05
	water.mesh = water_mesh
	var pool := StandardMaterial3D.new()
	pool.albedo_color = desert.pool
	pool.roughness = 0.3
	water.material_override = pool
	water.position = Vector3(-14, 0.04, 16)
	stage.add_child(water)
	# Props: walls (rib row, cliff), landmarks (arch, skull), deco (cacti), portal.
	_prop("RibBones", Vector3(-11, 0, -24), 1.2, 13.0, 1.0, desert.bone_tint)
	_prop("RockArch", Vector3(8, 0, -27), 0.0, 12.0, 1.0, desert.wall_tint)
	_prop("SandstoneCliff", Vector3(19, 0, -10), 1.5, 14.0, 2.2, desert.wall_tint)
	_prop("SandstoneCliff", Vector3(-22, 0, -8), 1.3, 12.0, 2.2, desert.wall_tint)
	_prop("GiantSkull", Vector3(-12, 0, 4), 0.5, 8.0, 1.0, desert.bone_tint)
	_prop("SandPortal", Vector3(11, 0, 5), 0.0, 7.5)
	_prop("Cactus", Vector3(-3, 0, 9), 0.3, 4.6)
	_prop("Cactus", Vector3(5, 0, -12), 2.0, 4.2)
	_prop("Cactus", Vector3(-17, 0, -16), 4.0, 4.4)


# One prop, `length` = longest horizontal side in metres; `height_scale` > 0
# stretches flat models upwards (the cliff slab is only 0.17 high raw).
func _prop(kind: String, at: Vector3, yaw: float, length: float, height_scale := 1.0, tint := Color(1, 1, 1, 0)) -> void:
	var node: Node3D = PROPS[kind].instantiate()
	node.name = kind
	var box := WORM._bounds(node, node)
	var size := maxf(box.size.x, box.size.z)
	var scale := length / maxf(size, 0.01)
	node.scale = Vector3(scale, scale * height_scale, scale)
	node.rotation.y = yaw
	node.position = at
	var material := ShaderMaterial.new()
	material.shader = PROP_SHADER
	material.set_shader_parameter("brightness", 1.0)
	material.set_shader_parameter("saturation", 1.05)
	material.set_shader_parameter("shape_light", 0.5)
	material.set_shader_parameter("rim_color", desert.prop_rim)
	material.set_shader_parameter("rim_strength", 0.35)
	material.set_shader_parameter("body_tint", tint)
	material.set_shader_parameter("outline_strength", 0.8)
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_override = material
		(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(node)


func _flat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	return material


func _step_grubs(delta: float) -> void:
	if grubs == null:
		return
	for release in grubs_queue():
		grubs.spawn_burst(release.center, int(release.count))
	grubs.step(delta, world._unit_points())


func grubs_queue() -> Array:
	var worm: Variant = world.get_node_or_null("Sandwurm")
	return worm.take_grubs() if worm != null else []


func _advance_windup(worm: Variant, share: float) -> void:
	while worm.state == WORM.State.WINDUP and worm.windup_progress() < share:
		worm.step(DT, swarm.position, 1.0)
		_step_grubs(DT)
		await process_frame


func _advance(worm: Variant, seconds: float, target: Vector3) -> void:
	for i in int(seconds * 60.0):
		worm.cooldown = 999.0
		worm.step(DT, target, 1.0)
		_step_grubs(DT)
		await process_frame


func _frame(target: Vector3, zoom: float) -> void:
	camera.position = target + CAMERA_OFFSET * zoom
	camera.look_at(target, Vector3.UP)


func _settle(seconds: float) -> void:
	await create_timer(seconds).timeout


func _save(file_name: String, message: String) -> void:
	world._update_hud(message)
	await process_frame
	world._update_hud(message)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/" + file_name)
