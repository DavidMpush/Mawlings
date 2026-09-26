extends SceneTree

# Preview for scripts/ui/hud_top.gd in the real game view (run WITHOUT --headless):
# calm start, full screen of information, high pressure with population loss.
# Writes preview_ui_hud_top_{calm,full,pressure}.png into the project root.

const HUD_TOP := "res://scripts/ui/hud_top.gd"

var scene: Node
var world: Variant
var controls: Variant
var top: Control


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	world = scene.get_node("HuntWorld")
	controls = scene.get_node("HUD/Controls")
	# Background capture windows lose focus; the auto-pause must not end up in the frames.
	controls.pause_requested.disconnect(world.toggle_pause)
	controls.legacy["top"] = false
	controls.legacy["badges"] = false
	top = load(HUD_TOP).new()
	top.name = "HudTop"
	controls.add_child(top)
	await create_timer(0.6).timeout
	# Freeze the simulation so the HUD values below are not overwritten.
	world.set_process(false)
	var evo: Variant = world.evolution
	evo.offers = []

	_apply({"population": 25, "elapsed": 12.0, "pressure": 1.1, "hunters": 0, "skitters": 0, "leapers": 0, "boss_health": 0.0, "nearest_corpse": "", "biomass_bank": 0.0, "alpha_cores": 0})
	evo.level = 0
	evo.dna = 6
	await create_timer(1.6).timeout
	await _save("preview_ui_hud_top_calm.png")

	evo.level = 4
	evo.dna = 12
	evo.ranks["saeurespucker"] = 2
	evo.ranks["meute"] = 1
	evo.evolutions.append("meute")
	_apply({"population": 243, "elapsed": 157.0, "pressure": 6.2, "hunters": 3, "skitters": 2, "leapers": 1, "boss_health": 640.0, "boss_max_health": 900.0, "boss_vulnerable": true, "nearest_corpse": "Kadaver: 14m · rechts", "biomass_bank": 1.4, "alpha_cores": 1})
	await create_timer(1.5).timeout
	_apply({"population": 250})
	await create_timer(0.12).timeout
	await _save("preview_ui_hud_top_full.png")

	evo.level = 7
	evo.dna = 30
	_apply({"population": 250, "elapsed": 781.0, "pressure": 180.0, "hunters": 7, "skitters": 3, "leapers": 3, "boss_health": 210.0, "boss_max_health": 900.0, "boss_vulnerable": false, "nearest_corpse": "Kadaver: 31m · oben", "biomass_bank": 0.0, "alpha_cores": 2})
	await create_timer(1.4).timeout
	_apply({"population": 212})
	await create_timer(0.15).timeout
	await _save("preview_ui_hud_top_pressure.png")
	print("Saved HUD top previews")
	quit()


func _apply(values: Dictionary) -> void:
	for key in values:
		controls.set(key, values[key])


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://" + file_name)
	# Detail crop of the upper band at 2x for close review.
	var detail := image.get_region(Rect2i(0, 0, image.get_width(), int(image.get_height() * 0.3)))
	detail.resize(detail.get_width() * 2, detail.get_height() * 2, Image.INTERPOLATE_LANCZOS)
	detail.save_png("res://" + file_name.replace(".png", "_detail.png"))
