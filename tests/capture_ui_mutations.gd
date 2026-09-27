extends SceneTree

# Preview of scripts/ui/mutation_screen.gd (skin "brawl", stage 15 package C) in
# the real game. Run WITHOUT --headless (frame_post_draw), with --screen 1 and
# --audio-driver Dummy. Every scene is rendered at 900 x 1600 and 540 x 960:
#   normal       mixed cards (form, form rank-up, new trait "Lockduft"), all buttons
#   long         longest card text (Rudelbiss rank I), banish on every card
#   evolution    evolution hints: one pick completes "Meute" (gold), two feed "Sturmrudel"
#   levelup      level-up moment mid-animation (~0.28 s after opening)
#   flash        pick flash on the middle card
#   columns_*    the rejected side-by-side layout, for comparison
# Output: res://preview_ui_mutations_<scene>[_540].png

var scene: Node
var world: Variant
var controls: Variant
var screen: Variant
var evo: Variant


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(900, 1600)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	world = scene.get_node("HuntWorld")
	controls = scene.get_node("HUD/Controls")
	# Background capture windows lose focus; the auto-pause must not end up in the frames.
	controls.pause_requested.disconnect(world.toggle_pause)
	screen = controls.get_node("mutation_screen")
	evo = world.evolution
	await create_timer(1.0).timeout
	world._award_dna(200)
	for size in [Vector2i(900, 1600), Vector2i(540, 960)]:
		root.size = size
		var suffix := "" if size.x == 900 else "_540"
		screen.layout = "stack"
		await _scenes(suffix)
		screen.layout = "columns"
		await _show({"jaws": 1, "rudelbiss": 1}, ["rudelbiss", "sporenwolke", "lockduft"], 2, 1, 1)
		await _save("preview_ui_mutations_columns_normal%s.png" % suffix)
		await _show({"glutton": 1}, ["rudelbiss", "stachelruecken", "scatter"], 0, 2, 0)
		await _save("preview_ui_mutations_columns_long%s.png" % suffix)
		screen.layout = "stack"
	print("Saved mutation UI previews")
	quit()


func _scenes(suffix: String) -> void:
	# Mixed: new form, form rank-up, the new trait "Lockduft"; reroll + skip + banish.
	await _show({"jaws": 1, "sporenwolke": 1}, ["sporenwolke", "saeurespucker", "lockduft"], 2, 1, 1)
	await _save("preview_ui_mutations_normal%s.png" % suffix)
	# Longest text: Rudelbiss rank I, plus the longest trait label.
	await _show({"glutton": 1}, ["rudelbiss", "stachelruecken", "glutton"], 0, 2, 0)
	await _save("preview_ui_mutations_long%s.png" % suffix)
	# Evolution hints: Rudelinstinkt completes Meute (gold), Blitzbiss/Reißzähne feed Sturmrudel.
	await _show({"rudelbiss": 3, "blitzbiss": 2}, ["pack", "blitzbiss", "jaws"], 1, 0, 0)
	await _save("preview_ui_mutations_evolution%s.png" % suffix)
	# Level-up moment mid-animation (ribbon landed, light column, cards arriving).
	await _show({"jaws": 1}, ["pack", "sporenwolke", "armor"], 1, 0, 1, 0.28)
	await _save("preview_ui_mutations_levelup%s.png" % suffix)
	await create_timer(0.8).timeout
	# Pick flash (selected state) on the middle card.
	controls.mutation_chosen.emit(1)
	await create_timer(0.08).timeout
	await _save("preview_ui_mutations_flash%s.png" % suffix)


func _show(ranks: Dictionary, ids: Array, rerolls: int, banishes: int, skips: int, wait: float = 0.9) -> void:
	evo.offers = []
	world._update_hud("")
	await create_timer(0.5).timeout
	evo.ranks = ranks.duplicate()
	evo.evolutions.clear()
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
