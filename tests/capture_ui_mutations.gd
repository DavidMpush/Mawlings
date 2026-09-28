extends SceneTree

# Preview of scripts/ui/mutation_screen.gd (skin "brawl") in the real game.
# Run WITHOUT --headless (frame_post_draw), with --screen 1 and --audio-driver
# Dummy. Every scene is rendered at 900 x 1600 and 540 x 960:
#   rarity       stage 17: three stat cards common / rare / epic, all buttons
#   legendary    a legendary card (gold rim + glint) next to rare and common
#   long         longest stat texts (Regeneration, Reichweite), banish on every card
#   levelup      level-up moment mid-animation (~0.28 s after opening)
#   flash        pick flash on the middle card
#   chest        Boss-Kokon (mode "chest"): new weapon, legendary relic, evolution
#   chest_ranks  weapon rank-up that completes an evolution (gold), relic stack, weapon new
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
	var only := OS.get_environment("MAWLINGS_ONLY")
	for size in [Vector2i(900, 1600), Vector2i(540, 960)]:
		root.size = size
		var suffix := "" if size.x == 900 else "_540"
		screen.layout = "stack"
		await _scenes(suffix, only)
		if only == "":
			screen.layout = "columns"
			await _show({"bite": 1, "rudelbiss": 1}, [["bite", "rare"], ["armor", "common"], ["magnet", "epic"]], 2, 1, 1)
			await _save("preview_ui_mutations_columns_normal%s.png" % suffix)
			screen.layout = "stack"
	print("Saved mutation UI previews")
	quit()


func _scenes(suffix: String, only: String) -> void:
	if only == "" or only == "rarity":
		# Common / rare / epic: rarity rim + chip, value before -> after; reroll + skip + banish.
		await _show({"armor": 2, "rudelbiss": 1}, [["bite", "common"], ["armor", "rare"], ["magnet", "epic"]], 2, 1, 1)
		await _save("preview_ui_mutations_rarity%s.png" % suffix)
	if only == "" or only == "legendary":
		await _show({"crit": 1, "rudelbiss": 1}, [["crit", "legendary"], ["vigor", "rare"], ["luck", "common"]], 1, 0, 0, 1.6)
		await _save("preview_ui_mutations_legendary%s.png" % suffix)
	if only == "" or only == "long":
		# Longest texts: Regeneration and Reichweite, banish on every card.
		await _show({"rudelbiss": 1}, [["regen", "epic"], ["reach", "common"], ["evade", "rare"]], 0, 2, 0)
		await _save("preview_ui_mutations_long%s.png" % suffix)
	if only == "" or only == "levelup":
		# Level-up moment mid-animation (ribbon landed, light column, cards arriving).
		await _show({"bite": 1}, [["rally", "rare"], ["haste", "common"], ["gene", "common"]], 1, 0, 1, 0.28)
		await _save("preview_ui_mutations_levelup%s.png" % suffix)
		await create_timer(0.8).timeout
		# Pick flash (selected state) on the middle card.
		controls.mutation_chosen.emit(1)
		await create_timer(0.08).timeout
		await _save("preview_ui_mutations_flash%s.png" % suffix)
	if only == "" or only == "chest":
		# Boss-Kokon: 1 aus 3 (new weapon, legendary relic, ready evolution).
		await _chest({"rudelbiss": 5}, {"rudelhorn": 1}, [
			evo.arsenal.evolution_item("meute"),
			evo.arsenal.weapon_item("giftbiss", "epic"),
			evo.arsenal.relic_item("urmutter")])
		await _save("preview_ui_mutations_chest%s.png" % suffix)
		# Weapon rank-up that makes Ätzflut ready (gold), relic stack, new weapon.
		await _chest({"saeurespucker": 3, "klauenwirbel": 1}, {"aetzdruese": 1, "hungerstein": 1}, [
			evo.arsenal.weapon_item("saeurespucker", "epic"),
			evo.arsenal.relic_item("hungerstein"),
			evo.arsenal.weapon_item("schallbrueller", "legendary")])
		await _save("preview_ui_mutations_chest_ranks%s.png" % suffix)
		evo.chest_offers = []


func _show(ranks: Dictionary, cards: Array, rerolls: int, banishes: int, skips: int, wait: float = 0.9) -> void:
	evo.offers = []
	evo.chest_offers = []
	world._update_hud("")
	await create_timer(0.5).timeout
	evo.ranks = ranks.duplicate()
	evo.relics = {}
	evo.stats.units.clear()
	evo.evolutions.clear()
	evo.rerolls = rerolls
	evo.banishes = banishes
	evo.skips = skips
	evo.dna = maxi(evo.dna, evo.threshold() * 3)
	var offers: Array = []
	for card in cards:
		var entry: Array = evo.info(card[0])
		entry.append(card[1])
		offers.append(entry)
	evo.offers = offers
	world._update_hud("")
	await create_timer(wait).timeout


func _chest(ranks: Dictionary, relics: Dictionary, items: Array, wait: float = 1.6) -> void:
	evo.offers = []
	evo.chest_offers = []
	world._update_hud("")
	await create_timer(0.5).timeout
	evo.ranks = ranks.duplicate()
	evo.relics = relics.duplicate()
	evo.evolutions.clear()
	var offers: Array = []
	for item in items:
		# Items were built before the ranks changed: refresh from/to.
		var fresh: Dictionary = item
		match String(item.type):
			"weapon":
				fresh = evo.arsenal.weapon_item(item.id, item.rarity)
			"relic":
				fresh = evo.arsenal.relic_item(item.id)
		offers.append(evo.chest_entry(fresh))
	evo.chest_offers = offers
	world._update_hud("")
	await create_timer(wait).timeout


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/" + file_name)
