extends SceneTree

# Preview of scripts/ui/mutation_screen.gd in the real game (run WITHOUT --headless):
# mixed cards, intro mid-animation, single card, reroll/banish/skip with an
# evolution-ready card, long German texts and the pick flash.

var scene: Node
var world: Variant
var controls: Variant
var evo: Variant


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
	controls.legacy["mutations"] = false
	var screen: Control = load("res://scripts/ui/mutation_screen.gd").new()
	screen.name = "MutationScreen"
	controls.add_child(screen)
	evo = world.evolution
	await create_timer(0.8).timeout
	world._award_dna(200)

	await _show({"jaws": 1}, ["jaws", "rudelbiss", "brood"], 0, 0, 0)
	await _save("preview_ui_mutations_mixed.png")
	screen.use_frame_kit = false
	await create_timer(0.1).timeout
	await _save("preview_ui_mutations_mixed_ownframe.png")
	screen.use_frame_kit = true

	await _show({"jaws": 1}, ["pack", "sporenwolke", "glutton"], 0, 0, 0, 0.16)
	await _save("preview_ui_mutations_intro.png")

	await _show({"brood": 2}, ["armor"], 0, 0, 0)
	await _save("preview_ui_mutations_single.png")

	await _show({"saeurespucker": 3, "rudelbiss": 1, "pack": 1}, ["glutton", "rudelbiss", "pack"], 2, 1, 1)
	await _save("preview_ui_mutations_buttons.png")

	await _show({"saeurespucker": 2, "glutton": 1, "stachelruecken": 1}, ["scatter", "stachelruecken", "saeurespucker"], 1, 0, 1)
	await _save("preview_ui_mutations_long.png")

	controls.mutation_chosen.emit(1)
	await create_timer(0.07).timeout
	await _save("preview_ui_mutations_flash.png")
	print("Saved mutation UI previews")
	quit()


func _show(ranks: Dictionary, ids: Array, rerolls: int, banishes: int, skips: int, wait: float = 0.9) -> void:
	evo.offers = []
	world._update_hud("")
	await create_timer(0.45).timeout
	evo.ranks = ranks.duplicate()
	evo.rerolls = rerolls
	evo.banishes = banishes
	evo.skips = skips
	evo.dna = maxi(evo.dna, evo.threshold() * 3)
	var offers: Array = []
	for id in ids:
		offers.append(evo.info(id))
	evo.offers = offers
	world._update_hud("")
	await create_timer(wait).timeout


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + file_name)
