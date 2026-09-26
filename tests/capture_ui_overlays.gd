extends SceneTree

# Stage 04 OVERLAYS preview: evolution banner, bundled loss feedback, off-screen
# boss pointer, pause and the extinction result (mid count-up and settled).
# Run without --headless: frame_post_draw needs a real render loop.

const BOG_KING := preload("res://scripts/bog_king.gd")

var scene: Node
var world: Variant
var swarm: Variant
var controls: Variant
var overlays: Control


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
	for key in ["result", "banner", "feedback", "pointer"]:
		controls.legacy[key] = false
	overlays = load("res://scripts/ui/hud_overlays.gd").new()
	overlays.name = "HudOverlays"
	controls.add_child(overlays)
	await create_timer(0.4).timeout
	# Evolution banner: big moment, then the settled small state.
	world.evolve_name = "Ätzflut"
	world.evolve_flash = 3.0
	await create_timer(0.7).timeout
	await _save("preview_ui_overlays_evolve.png")
	await create_timer(1.3).timeout
	await _save("preview_ui_overlays_evolve_late.png")
	world.evolve_flash = 0.0
	await create_timer(0.4).timeout
	# Two quick hits are bundled into one number.
	world._apply_hit(4, swarm.position + Vector3(1.6, 0.0, 0.4), 0.3)
	await create_timer(0.25).timeout
	world._apply_hit(3, swarm.position + Vector3(-1.2, 0.0, 0.6), 0.3)
	await create_timer(0.2).timeout
	await _save("preview_ui_overlays_hit.png")
	await create_timer(1.4).timeout
	# Boss off-screen, first normal, then vulnerable (gold).
	world._spawn_boss(swarm.position + Vector3(16.0, 0.0, -9.0))
	await create_timer(0.4).timeout
	await _save("preview_ui_overlays_pointer.png")
	if "state" in world.boss:
		world.boss.state = BOG_KING.State.RECOVERY
	await create_timer(0.2).timeout
	await _save("preview_ui_overlays_pointer_gold.png")
	world.boss.queue_free()
	world.boss = null
	# Build for pause and result.
	var evo: Variant = world.evolution
	evo.ranks = {"jaws": 3, "brood": 2, "saeurespucker": 3, "glutton": 1, "armor": 2, "rudelbiss": 1, "aetzflut": 1}
	evo.evolutions.append("aetzflut")
	evo.level = 12
	world.toggle_pause()
	await create_timer(0.6).timeout
	await _save("preview_ui_overlays_pause.png")
	world.toggle_pause()
	await create_timer(0.2).timeout
	# Simulated extinction with a full stat sheet.
	var model: Variant = world.model
	model.elapsed = 437.0
	model.peak_population = 186
	model.consumed_biomass = 96.4
	model.kills_by_type = {"prey": 142, "hunter": 23, "skitter": 31, "leaper": 7, "boss": 1}
	model.kills = 204
	model.bosses = 1
	model.lost_population = 211
	world._apply_hit(9999, swarm.position + Vector3(1.0, 0.0, 0.0), 0.2)
	await create_timer(0.75).timeout
	await _save("preview_ui_overlays_result_count.png")
	await create_timer(2.6).timeout
	await _save("preview_ui_overlays_result.png")
	print("Saved UI overlay previews")
	quit()


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + file_name)
