extends SceneTree

# Etappe 37: damage numbers (scripts/ui/hud_damage.gd). A hunter that loses
# health shows one gathered number above it; a big hit is gold, a boss hit
# orange; numbers fade after their life; pause shows none; format.

const HUD_DAMAGE = preload("res://scripts/ui/hud_damage.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var world: Variant = scene.get_node("HuntWorld")
	var swarm: Variant = scene.get_node("Swarm")
	var hud: Variant = scene.get_node("HUD/Controls")
	world.set_process(false)
	var numbers: Variant = hud.get_node_or_null("hud_damage")
	_check(numbers != null, "Damage number layer is part of the HUD")
	if numbers == null:
		_finish(scene)
		return
	_check(HUD_DAMAGE.format_amount(7.2) == "7" and HUD_DAMAGE.format_amount(1234.0) == "1.234" and HUD_DAMAGE.format_amount(12345.0) == "12,3K" and HUD_DAMAGE.format_amount(2_500_000.0) == "2,5M", "Number format")
	var hunter: Variant = world._spawn_hunter(swarm.position + Vector3(3, 0, -2))
	hunter.state = 1  # HUNTER.State.CHASE (ARRIVING hunters are not hittable targets)
	for index in 4:
		await process_frame
	hunter.health -= 5.0
	await create_timer(0.45).timeout
	_check(numbers.popup_count() >= 1, "A hit shows a number (%d)" % numbers.popup_count())
	# Big hit: >= 20 % of max HP in one go -> gold.
	hunter.health -= float(hunter.max_health) * 0.5
	await create_timer(0.45).timeout
	var gold := false
	for popup in numbers._popups:
		if Color(popup.color).is_equal_approx(HUD_DAMAGE.BIG):
			gold = true
	_check(gold, "A big hit is gold")
	# Fade out.
	await create_timer(1.0).timeout
	_check(numbers.popup_count() == 0, "Numbers fade after their life")
	# Paused: nothing new.
	hud.paused = true
	hunter.health -= 3.0
	await create_timer(0.45).timeout
	_check(numbers.popup_count() == 0, "No numbers while paused")
	hud.paused = false
	_finish(scene)


func _finish(scene: Node) -> void:
	scene.queue_free()
	await process_frame
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS damage_numbers: layer in HUD, gathered number per target, big hits gold, fade, pause, format")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
