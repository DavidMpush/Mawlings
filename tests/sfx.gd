extends SceneTree

const SfxScript := preload("res://scripts/sfx.gd")
const IDS := ["bite", "kill", "grow", "hit", "warn", "stomp", "mutate", "evolve", "extinct", "pickup", "ui"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for id: String in IDS:
		var found := 0
		for n in range(1, 9):
			var path := "res://assets/audio/%s_%d.wav" % [id, n]
			if not ResourceLoader.exists(path):
				break
			if not load(path) is AudioStream:
				_fail("Not an AudioStream: %s" % path)
				return
			found += 1
		if found < 2:
			_fail("Sound '%s' needs at least 2 variants, found %d" % [id, found])
			return
	if not load("res://assets/audio/ambience_jungle_1.wav") is AudioStream:
		_fail("Ambience loop missing")
		return

	var sfx: Node = SfxScript.new()
	sfx.name = "Sfx"
	root.add_child(sfx)
	await process_frame

	for id: String in IDS:
		if sfx.variant_count(id) < 2:
			_fail("Sfx did not load variants for %s" % id)
			return
		sfx.play(id)
		if sfx.active_voices(id) != 1:
			_fail("play('%s') did not start a voice" % id)
			return

	# Unknown ids and odd arguments are ignored silently.
	sfx.play("does_not_exist")
	sfx.play("")
	sfx.vibrate(30)
	sfx.vibrate(-5)

	# Rate limiting: a burst in one frame must not exceed the voice limit.
	sfx.stop_all()
	OS.delay_msec(100)
	for i in 60:
		sfx.play("bite", 0.0, 0.1)
	var burst: int = sfx.active_voices("bite")
	if burst != 1:
		_fail("Minimum gap failed: %d bite voices after a same-frame burst" % burst)
		return
	var limit: int = int(SfxScript.RULES["bite"]["voices"])
	for i in 12:
		OS.delay_msec(55)
		sfx.play("bite")
		sfx.play("bite")
	var spaced: int = sfx.active_voices("bite")
	if spaced > limit:
		_fail("Voice limit failed: %d bite voices > %d" % [spaced, limit])
		return

	# Pool never grows beyond its size even when everything fires.
	for id: String in IDS:
		sfx.play(id)
	var total := 0
	for id: String in IDS:
		total += sfx.active_voices(id)
	if total > SfxScript.POOL_SIZE:
		_fail("Pool overflow: %d voices" % total)
		return

	sfx.master_volume_db = -6.0
	sfx.play_ambience()
	sfx.play_ambience()
	sfx.stop_ambience()
	sfx.stop_all()
	sfx.queue_free()
	await process_frame
	print("SFX test passed: %d ids, bite burst=%d, spaced=%d/%d" % [IDS.size(), burst, spaced, limit])
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
