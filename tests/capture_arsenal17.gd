extends SceneTree

# Etappe 17 Welle 2: Kokons, Power-ups, Schreine und das Arsenal-HUD aus der
# echten Spielkamera. Ohne --headless ausführen (frame_post_draw), mit
# --screen 1 --audio-driver Dummy. Ergebnis: preview_arsenal17_*.png (900 × 1600).
#   cocoon_price         Karten-Kokon mit Preis (bezahlbar), goldener Kokon (GRATIS)
#   cocoon_red           Karten-Kokon zu teuer (rote Pille, ZU TEUER)
#   cocoon_hold          Schwarm hält den Kokon (Haltebalken)
#   open_<rarity>        Öffnungsmoment je Seltenheit (Strahl + Beute-Karte)
#   boss_choice          Boss-Kokon: 1 aus 3
#   powerups_world       alle sechs Power-ups in der Welt
#   powerup_<id>         aktiv am Schwarm (mit Band beim ersten)
#   shrine               Schrein beim Laden
#   hud_full             HUD mit 4 Waffen (eine Evolution), Relikten und Power-ups,
#                        Bernstein-Pill und violettem XP-Balken
#   loot                 Bernstein-Münzen (gold), Biomasse (grün), DNA (blau)

const DT := 1.0 / 60.0

var scene: Node
var world: Node3D
var swarm: Node3D
var origin := Vector3.ZERO
var only := ""


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	for raw in OS.get_cmdline_user_args():
		only = String(raw).trim_prefix("--")
	root.size = Vector2i(900, 1600)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	world = scene.get_node("HuntWorld")
	swarm = scene.get_node("Swarm")
	var controls: Node = scene.get_node("HUD/Controls")
	if controls.pause_requested.is_connected(world.toggle_pause):
		controls.pause_requested.disconnect(world.toggle_pause)
	_population(40)
	for i in 40:
		await process_frame
	if world.paused:
		world.toggle_pause()
	scene.set_process(false)
	world.set_process(false)
	_quiet()
	origin = swarm.position
	# Park the fallback objects out of view.
	for entry in world.chests.cocoons:
		entry.node.position = Vector3(900, 0, 900)
		entry.at = Vector3(900, 0, 900)
	for entry in world.shrines.shrines:
		entry.node.position = Vector3(-900, 0, 900)
		entry.at = Vector3(-900, 0, 900)
	for knoll in world.powerups.knolls:
		knoll.node.position = Vector3(900, 0, -900)
		knoll.at = Vector3(900, 0, -900)
	var chests: Variant = world.chests

	if _want("cocoon"):
		# Affordable map cocoon ahead, a golden one to the side.
		world.model.amber = 1240
		var map: Dictionary = chests.spawn("map", origin + Vector3(-1.5, 0, -6.5))
		var gold: Dictionary = chests.spawn("gold", origin + Vector3(4.2, 0, -3.0))
		await _run(0.4)
		await _save("cocoon_price")
		# Too expensive: not enough Bernstein.
		world.model.amber = 12
		map.denied = true
		await _run(0.1)
		await _save("cocoon_red")
		world.model.amber = 1240
		map.denied = false
		_remove(gold)
		# The swarm holds the cocoon.
		map.at = origin + Vector3(0, 0, -1.0)
		map.node.position = map.at
		await _run(0.55)
		await _save("cocoon_hold")
		_remove(map)

	if _want("loot"):
		# Bernstein coins (gold), biomass crystals (green) and DNA (blue) after kills.
		world.model.amber = 87
		for i in 5:
			var angle := TAU * float(i) / 5.0 + 0.4
			world.drop_loot(origin + Vector3(cos(angle), 0, sin(angle)) * 7.5, 7.0, 25, "mini", 9)
		await _run(0.9)
		await _save("loot")
		world.collect_loot_now()

	if _want("open"):
		var items := {
			"common": world.evolution.arsenal.relic_item("zaehe_haut"),
			"rare": world.evolution.arsenal.weapon_item("sporenwolke", "rare"),
			"epic": world.evolution.arsenal.relic_item("koenigszahnkette"),
			"legendary": world.evolution.arsenal.relic_item("urmutter"),
		}
		for rarity in ["common", "rare", "epic", "legendary"]:
			var entry: Dictionary = chests.spawn("map", origin + Vector3(0.5, 0, -5.5))
			await _run(0.1)
			var granted: Dictionary = world.evolution.grant(items[rarity])
			chests.play_moment(entry, rarity, granted)
			await _run(0.28)
			await _save("open_" + rarity)
			await _run(2.4)

	if _want("boss"):
		world.evolution.ranks["rudelbiss"] = 5
		world.evolution.relics["rudelhorn"] = 1
		var boss: Dictionary = chests.spawn("boss", origin + Vector3(0, 0, -0.5))
		for i in 120:
			swarm.position = origin
			world.step(DT)
			await process_frame
			if world.choosing():
				break
		for i in 70:
			await process_frame
		await _save("boss_choice")
		if world.choosing():
			world.choose_mutation(0)
		await _run(0.3)
		await _save("boss_card")
		await _run(2.5)

	if _want("powerups"):
		var ids: Array = ["rausch", "blutrausch", "magnetsturm", "chitinschild", "raserei", "brutwelle"]
		var drops: Array = []
		for i in ids.size():
			var angle := -PI * 0.5 + (float(i) - 2.5) * 0.42
			drops.append(world.powerups.drop(origin + Vector3(cos(angle), 0, sin(angle)) * 7.0 + Vector3(0, 0, -1.0), ids[i]))
		await _run(0.6)
		await _save("powerups_world")
		for entry in drops:
			entry.node.queue_free()
		world.powerups.pickups.clear()
		for id in ["rausch", "chitinschild", "raserei", "magnetsturm", "blutrausch"]:
			world.powerups.clear_active()
			world.powerups.collect(id)
			swarm.movement_vector = Vector2(0.0, -1.0) if id == "rausch" else Vector2.ZERO
			await _run(0.35)
			await _save("powerup_" + id)
			world.powerups.band = {}
		swarm.movement_vector = Vector2.ZERO
		world.powerups.clear_active()

	if _want("shrine"):
		var shrine: Dictionary = world.shrines.spawn(origin + Vector3(0, 0, -1.5))
		shrine.charge = 0.55
		await _run(0.4)
		await _save("shrine")
		shrine.done = true
		shrine.node.visible = false

	if _want("hud"):
		var evo: Variant = world.evolution
		evo.ranks.erase("rudelbiss")
		evo.relics.clear()
		evo.evolutions.clear()
		evo.ranks["sporenwolke"] = 3
		evo.ranks["klauenwirbel"] = 5
		evo.ranks["giftbiss"] = 1
		evo.debug_grant("rudelbiss", "legendary")
		evo.ranks["rudelbiss"] = 5
		evo.relics["rudelhorn"] = 1
		evo.debug_grant("meute")
		for pair in [["scharfe_zaehne", 3], ["zaehe_haut", 1], ["gluecksknochen", 2], ["koenigszahnkette", 1], ["urmutter", 1], ["witterungsnase", 2]]:
			evo.relics[pair[0]] = pair[1]
		evo.revision += 1
		world.powerups.collect("rausch")
		world.powerups.collect("raserei")
		world.powerups.collect("chitinschild")
		world.powerups.band = {}
		world.model.amber = 1240
		evo.dna = int(evo.threshold() * 0.6)
		await _run(2.2)
		await _save("hud_full")
	print("Saved stage 17 wave 2 frames")
	quit()


func _want(key: String) -> bool:
	return only == "" or key.begins_with(only) or only.begins_with(key)


func _population(count: int) -> void:
	world.model.population = count
	swarm.set_population(count, false)
	world.unit_points_valid = false


func _remove(entry: Dictionary) -> void:
	entry.node.queue_free()
	world.chests.cocoons.erase(entry)


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
	world.flood_start = 1000000.0
	world.apex_state = 4
	world.totem_offered = true


# Advances the world (and draws) for `seconds`, keeping the swarm in place.
func _run(seconds: float) -> void:
	for i in int(round(seconds / DT)):
		swarm.position = origin
		world.unit_points_valid = false
		world.step(DT)
		while not world.evolution.offers.is_empty():
			world.choose_mutation(0)
		await process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/preview_arsenal17_%s.png" % name)
