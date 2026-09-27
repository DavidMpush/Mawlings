extends SceneTree

const SfxScript := preload("res://scripts/sfx.gd")
const IDS := ["bite", "kill", "grow", "hit", "warn", "stomp", "mutate", "evolve", "extinct", "pickup", "ui"]
## Recorded user sounds (tools/import_user_sfx.py) for single big moments.
const USER_IDS := ["boss_roar", "flood_warn", "quake", "regen", "alpha_core", "fanfare", "migration_whoosh", "leaper_windup", "portal_open"]
## Rare one-shots may ship a single variant; every other id needs at least two.
const SINGLE_OK := ["fanfare", "migration_whoosh"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Every rule id and loop id has files that load as audio (variants 1..n, no gaps).
	for id: String in SfxScript.RULES.keys() + SfxScript.LOOP_RULES.keys():
		var count := _count_files(id)
		if count < 0:
			return
		var needed := 1 if (id in SINGLE_OK or SfxScript.LOOP_RULES.has(id)) else 2
		if count < needed:
			_fail("Sound '%s' needs at least %d variant(s), found %d" % [id, needed, count])
			return
	for id: String in USER_IDS:
		if not SfxScript.RULES.has(id):
			_fail("New sound id '%s' missing in Sfx.RULES" % id)
			return
	if not SfxScript.LOOP_RULES.has("portal_hum"):
		_fail("Loop 'portal_hum' missing in Sfx.LOOP_RULES")
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
	sfx.stop_all()
	for id: String in USER_IDS:
		var wanted := 1 if id in SINGLE_OK else 2
		if sfx.variant_count(id) < wanted:
			_fail("Sfx loaded %d variant(s) for %s, expected >= %d" % [sfx.variant_count(id), id, wanted])
			return
		sfx.play(id)
		if sfx.active_voices(id) != 1:
			_fail("play('%s') did not start a voice" % id)
			return
	sfx.start_loop("portal_hum")
	if not sfx.is_looping("portal_hum"):
		_fail("portal_hum loop did not start")
		return
	sfx.stop_loop("portal_hum")
	if sfx.is_looping("portal_hum"):
		_fail("portal_hum loop did not stop")
		return
	sfx.stop_all()

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
	print("SFX test passed: %d ids (%d recorded), bite burst=%d, spaced=%d/%d" % [SfxScript.RULES.size(), USER_IDS.size(), burst, spaced, limit])
	quit(0)


## Number of consecutive <id>_<n>.wav files; -1 (after _fail) when one is not audio.
func _count_files(id: String) -> int:
	var found := 0
	for n in range(1, SfxScript.MAX_VARIANTS + 1):
		var path := "res://assets/audio/%s_%d.wav" % [id, n]
		if not ResourceLoader.exists(path):
			break
		var stream := load(path) as AudioStream
		if stream == null or stream.get_length() <= 0.0:
			_fail("Not a playable AudioStream: %s" % path)
			return -1
		found += 1
	return found


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
