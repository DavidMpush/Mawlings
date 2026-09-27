extends SceneTree

# Preview for scripts/ui/hud_top.gd (+ minimap frame) in the real game view
# (run WITHOUT --headless, with --screen 1 --audio-driver Dummy):
#   early  - run start, one leader, minimap, nothing else
#   mid    - 5-digit DNA, Alpha-Kern, attack forms, context line "DRUCK"
#   late   - flood pressure, 188 mawlings right after losing 12 (damage pulse),
#            boss active, time over 60:00
#   max    - worst case widths: 250 mawlings, DNA 99.999, 100:00+, boss vulnerable
# Each scenario is saved at 900 x 1600 and 540 x 960:
#   preview_ui_hud_top_<name>.png / preview_ui_hud_top_<name>_540.png
# plus a 2x crop of the top band of the 540 shot (…_540_detail.png).

var scene: Node
var world: Variant
var controls: Variant
var top: Control


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(900, 1600)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	world = scene.get_node("HuntWorld")
	controls = scene.get_node("HUD/Controls")
	# Background capture windows lose focus; the auto-pause must not end up in the frames.
	if controls.pause_requested.is_connected(world.toggle_pause):
		controls.pause_requested.disconnect(world.toggle_pause)
	top = controls.get_node("hud_top")
	await create_timer(0.8).timeout
	# Freeze the simulation so the HUD values below are not overwritten.
	world.set_process(false)
	var evo: Variant = world.evolution
	evo.offers = []

	# --- early
	_apply({"population": 1, "elapsed": 9.0, "pressure": 1.0, "hunters": 0, "skitters": 0, "leapers": 0, "boss_health": 0.0, "biomass_bank": 0.0, "alpha_cores": 0})
	evo.level = 0
	evo.dna = 6
	await create_timer(1.2).timeout
	await _save_both("early")
	# Region change: the minimap shows the region name only in this short banner.
	var minimap: Variant = controls.get_node_or_null("hud_minimap")
	if minimap != null:
		minimap._banner_name = "Moosgrund der Zähne"
		minimap._banner_phrase = "Hier jagt der Bog King"
		minimap._banner_t = 0.0
		minimap._banner.queue_redraw()
		await create_timer(0.5).timeout
		await _save("preview_ui_hud_top_region.png", false)

	# --- mid: pressure step triggers the context line, Alpha-Kern stored
	evo.level = 4
	evo.dna = 12345
	evo.ranks["saeurespucker"] = 2
	evo.ranks["meute"] = 1
	_apply({"population": 96, "elapsed": 214.0, "pressure": 3.4, "hunters": 2, "alpha_cores": 1})
	await create_timer(1.0).timeout
	await _save_both("mid")

	# --- late: flood, boss, loss pulse
	evo.level = 9
	evo.dna = 38
	evo.evolutions.append("meute")
	_apply({"population": 200, "elapsed": 3790.0, "pressure": 180.0, "hunters": 7, "skitters": 3, "leapers": 3, "boss_health": 8450.0, "boss_max_health": 12000.0, "boss_vulnerable": false, "alpha_cores": 0})
	await create_timer(3.2).timeout
	_apply({"population": 188})
	await create_timer(0.12).timeout
	await _save_both("late")

	# --- max widths
	evo.level = 12
	evo.dna = 99999
	_apply({"population": 250, "elapsed": 6123.0, "pressure": 4096.0, "boss_health": 11999.0, "boss_max_health": 12000.0, "boss_vulnerable": true, "alpha_cores": 3})
	await create_timer(3.2).timeout
	await _save_both("max")
	print("Saved HUD top previews")
	quit()


func _apply(values: Dictionary) -> void:
	for key in values:
		controls.set(key, values[key])


func _save_both(name: String) -> void:
	root.size = Vector2i(900, 1600)
	await _frames(3)
	await _save("preview_ui_hud_top_%s.png" % name, false)
	root.size = Vector2i(540, 960)
	await _frames(3)
	await _save("preview_ui_hud_top_%s_540.png" % name, true)
	root.size = Vector2i(900, 1600)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _save(file_name: String, detail: bool) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://" + file_name)
	if detail:
		var crop := image.get_region(Rect2i(0, 0, image.get_width(), int(image.get_height() * 0.36)))
		crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_LANCZOS)
		crop.save_png("res://" + file_name.replace(".png", "_detail.png"))
