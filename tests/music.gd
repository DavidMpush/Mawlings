extends SceneTree

const MusicScript := preload("res://scripts/music.gd")
const LOOPS := ["menu_theme", "run_base", "run_tension", "run_flood", "run_boss"]
const STINGS := ["sting_flood", "sting_boss", "sting_king", "sting_extinct"]
## Audio pack V1 loops (style "v1"): id -> expected length (16 bars at 96 / 128 BPM).
const V1_LOOPS := {"v1_arena": 40.0, "v1_boss": 30.0}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Files: loops must import as forward loops over the whole file, stems equally long.
	var stem_length := -1.0
	for id: String in LOOPS:
		var path := "res://assets/music/%s.wav" % id
		var stream := load(path) as AudioStreamWAV
		if stream == null:
			_fail("Not an AudioStreamWAV: %s" % path)
			return
		if stream.loop_mode != AudioStreamWAV.LOOP_FORWARD:
			_fail("%s is not imported as a forward loop (loop_mode %d)" % [id, stream.loop_mode])
			return
		var frames := int(round(stream.get_length() * float(stream.mix_rate)))
		if stream.loop_begin != 0 or absi(stream.loop_end - frames) > 2:
			_fail("%s loop points %d..%d do not span %d frames" % [id, stream.loop_begin, stream.loop_end, frames])
			return
		if id.begins_with("run_"):
			if stem_length < 0.0:
				stem_length = stream.get_length()
			elif absf(stream.get_length() - stem_length) > 0.0005:
				_fail("Stem %s is %.4f s, expected %.4f s" % [id, stream.get_length(), stem_length])
				return
	if absf(stem_length - 20.0) > 0.01:
		_fail("Run stems should be 8 bars at 96 BPM (20 s), got %.3f" % stem_length)
		return
	for id: String in STINGS:
		var sting := load("res://assets/music/%s.wav" % id) as AudioStream
		if sting == null or sting.get_length() < 1.0 or sting.get_length() > 6.0:
			_fail("Stinger %s missing or odd length" % id)
			return

	for id: String in V1_LOOPS:
		var v1 := load("res://assets/music/%s.wav" % id) as AudioStreamWAV
		if v1 == null or v1.loop_mode != AudioStreamWAV.LOOP_FORWARD:
			_fail("V1 loop %s missing or not a forward loop" % id)
			return
		if absf(v1.get_length() - float(V1_LOOPS[id])) > 0.01:
			_fail("V1 loop %s is %.3f s, expected %.1f s" % [id, v1.get_length(), V1_LOOPS[id]])
			return

	var music: Node = MusicScript.new()
	music.name = "Music"
	root.add_child(music)
	await process_frame

	for id: String in LOOPS:
		var loaded: AudioStream = music.stream(id)
		if loaded == null:
			_fail("Music node did not load %s" % id)
			return

	# Menu fades in, run replaces it.
	music.play_menu()
	if music.menu_target() != 1.0:
		_fail("play_menu did not target the menu theme")
		return
	music.play_run()
	if music.menu_target() != 0.0 or music.stem_target("run_base") != 1.0 or music.stem_target("run_tension") != 0.0:
		_fail("play_run targets wrong: menu %.2f base %.2f tension %.2f" % [music.menu_target(), music.stem_target("run_base"), music.stem_target("run_tension")])
		return

	# Intensity: pressure 1 = base only; pressure 4 = full tension; flood / boss add layers.
	music.set_intensity(1.0, false, false)
	if not _targets(music, [1.0, 0.0, 0.0, 0.0]):
		return
	music.set_intensity(2.0, false, false)
	var mid: float = music.stem_target("run_tension")
	if mid <= 0.0 or mid >= 1.0:
		_fail("Pressure 2 should blend tension partially, got %.2f" % mid)
		return
	music.set_intensity(4.0, false, false)
	if not _targets(music, [1.0, 1.0, 0.0, 0.0]):
		return
	music.set_intensity(1.2, true, false)
	if not _targets(music, [1.0, 1.0, 1.0, 0.0]):
		return
	music.set_intensity(1.2, false, true)
	if not _targets(music, [1.0, 0.0, 0.0, 1.0]):
		return

	# Fades move towards the targets over time and change the player volume.
	for i in 150:
		music._process(1.0 / 60.0)
	if absf(music.stem_gain("run_boss") - 1.0) > 0.001 or music.stem_gain("run_tension") > 0.001:
		_fail("Fade did not reach targets: boss %.3f tension %.3f" % [music.stem_gain("run_boss"), music.stem_gain("run_tension")])
		return
	if music.stem_volume_db("run_boss") < -20.0 or music.stem_volume_db("run_tension") > -59.0:
		_fail("Player volumes wrong: boss %.1f dB tension %.1f dB" % [music.stem_volume_db("run_boss"), music.stem_volume_db("run_tension")])
		return
	var before: float = music.stem_volume_db("run_boss")
	music.master_volume_db = -6.0
	if absf(music.stem_volume_db("run_boss") - (before - 6.0)) > 0.01:
		_fail("Master volume not applied")
		return
	music.master_volume_db = 0.0

	# Stingers: known ids duck the loops, unknown ids are ignored.
	for id: String in ["flood", "boss", "king", "extinct"]:
		music.stinger(id)
		if music.last_stinger() != id or music.ducking() < 0.99:
			_fail("Stinger %s not played/ducked" % id)
			return
	music.stinger("nope")
	if music.last_stinger() != "extinct":
		_fail("Unknown stinger changed state")
		return
	for i in 400:
		music._process(1.0 / 60.0)
	if music.ducking() > 0.001:
		_fail("Duck did not release")
		return

	# Style v1: stems fade out, the arena loop in; a boss cross-fades to the boss
	# loop (never both at full); unknown styles are ignored; back to classic.
	if music.style() != "classic":
		_fail("Default style should be classic, got %s" % music.style())
		return
	for id: String in V1_LOOPS:
		if music.stream(id) == null:
			_fail("Music node did not load %s" % id)
			return
	music.set_intensity(1.0, false, false)
	music.set_style("v1")
	if music.style() != "v1" or music.v1_target("v1_arena") != 1.0 or music.v1_target("v1_boss") != 0.0 or not _targets(music, [0.0, 0.0, 0.0, 0.0]):
		_fail("set_style('v1') targets wrong")
		return
	for i in 150:
		music._process(1.0 / 60.0)
	if music.v1_gain("v1_arena") < 0.999 or music.stem_gain("run_base") > 0.001 or music.v1_volume_db("v1_arena") < -20.0:
		_fail("v1 fade wrong: arena %.2f base %.2f" % [music.v1_gain("v1_arena"), music.stem_gain("run_base")])
		return
	music.set_intensity(4.0, true, true)
	if music.v1_target("v1_boss") != 1.0 or music.v1_target("v1_arena") != 0.0 or not _targets(music, [0.0, 0.0, 0.0, 0.0]):
		_fail("v1 boss crossfade targets wrong")
		return
	for i in 60:
		music._process(1.0 / 60.0)
	if absf(music.v1_gain("v1_arena") + music.v1_gain("v1_boss") - 1.0) > 0.02:
		_fail("v1 crossfade not complementary: %.2f + %.2f" % [music.v1_gain("v1_arena"), music.v1_gain("v1_boss")])
		return
	music.stinger("boss")
	if music.ducking() < 0.99:
		_fail("Stinger does not duck in style v1")
		return
	music.set_style("jazz")
	if music.style() != "v1":
		_fail("Unknown style changed the style")
		return
	music.set_intensity(1.2, false, false)
	music.set_style("classic")
	if music.v1_target("v1_arena") != 0.0 or music.v1_target("v1_boss") != 0.0 or not _targets(music, [1.0, 0.0, 0.0, 0.0]):
		_fail("Back to classic: targets wrong")
		return
	for i in 400:
		music._process(1.0 / 60.0)
	if music.v1_gain("v1_arena") > 0.0 or music.v1_gain("v1_boss") > 0.0 or music.stem_gain("run_base") < 0.999:
		_fail("Back to classic: fades wrong")
		return
	# The style survives the menu: a new run starts directly in v1.
	music.set_style("v1")
	music.play_menu()
	if music.v1_target("v1_arena") != 0.0:
		_fail("Menu should silence the v1 loops")
		return
	music.play_run()
	if music.v1_target("v1_arena") != 1.0 or not _targets(music, [0.0, 0.0, 0.0, 0.0]):
		_fail("play_run in style v1 targets wrong")
		return
	music.stop()
	for i in 90:
		music._process(1.0 / 60.0)
	if music.mode != MusicScript.Mode.NONE or music.v1_gain("v1_arena") > 0.0:
		_fail("stop() did not fade out the v1 loop")
		return
	music.set_style("classic")
	music.play_run()

	# Etappe 23: the desert stem set - same length as the classic stems, a
	# biome change cross-fades the sets, the boss layer is the Sandwurm fight.
	for id: String in music.desert_ids():
		var desert_stream: AudioStream = music.stream(id)
		if desert_stream == null or absf(desert_stream.get_length() - stem_length) > 0.01:
			_fail("Desert stem %s missing or not %.2f s long" % [id, stem_length])
			return
	music.set_intensity(1.0, false, false)
	for i in 150:
		music._process(1.0 / 60.0)
	music.set_biome("desert")
	if music.biome() != "desert" or music.desert_target("desert_base") != 1.0 or not _targets(music, [0.0, 0.0, 0.0, 0.0]):
		_fail("set_biome('desert') targets wrong")
		return
	for i in 150:
		music._process(1.0 / 60.0)
	if music.desert_gain("desert_base") < 0.999 or music.stem_gain("run_base") > 0.001:
		_fail("Desert fade wrong: desert %.2f base %.2f" % [music.desert_gain("desert_base"), music.stem_gain("run_base")])
		return
	music.set_intensity(4.0, false, true)
	if music.desert_target("desert_boss") != 1.0 or music.desert_target("desert_tension") < 0.99 or music.desert_target("desert_flood") != 0.0:
		_fail("Sandwurm fight: desert boss/tension targets wrong")
		return
	music.set_biome("tundra")
	if music.biome() != "desert":
		_fail("Unknown biome changed the biome")
		return
	music.set_intensity(1.0, false, false)
	music.set_biome("verdant")
	if music.desert_target("desert_base") != 0.0 or music.desert_target("desert_boss") != 0.0 or not _targets(music, [1.0, 0.0, 0.0, 0.0]):
		_fail("Back to verdant: targets wrong")
		return
	for i in 400:
		music._process(1.0 / 60.0)
	if music.desert_gain("desert_base") > 0.0 or music.desert_gain("desert_boss") > 0.0 or music.stem_gain("run_base") < 0.999:
		_fail("Back to verdant: fades wrong")
		return
	# Style v1 ignores the biome (no desert variant of the user's loops).
	music.set_style("v1")
	music.set_biome("desert")
	if music.desert_target("desert_base") != 0.0 or music.v1_target("v1_arena") != 1.0:
		_fail("Style v1 must keep its loops in the desert")
		return
	music.set_biome("verdant")
	music.set_style("classic")

	# Disable / enable keeps the mode; stop fades to silence.
	music.set_enabled(false)
	music.stinger("boss")
	music.set_enabled(true)
	if music.mode != MusicScript.Mode.RUN:
		_fail("Mode lost across set_enabled")
		return
	music.stop()
	for i in 90:
		music._process(1.0 / 60.0)
	if music.mode != MusicScript.Mode.NONE or music.stem_gain("run_base") > 0.0:
		_fail("stop() did not fade out")
		return
	music.play_menu()
	music.stop(true)

	music.queue_free()
	await process_frame
	await process_frame
	print("MUSIC TEST PASSED (stems %.2f s, styles classic+v1, biomes verdant+desert, silent driver: %s)" % [stem_length, str(AudioServer.get_driver_name() == "Dummy")])
	quit(0)


func _targets(music: Node, wanted: Array) -> bool:
	var ids: Array = music.stem_ids()
	for i in ids.size():
		var got: float = music.stem_target(ids[i])
		if absf(got - float(wanted[i])) > 0.001:
			_fail("Target for %s is %.2f, expected %.2f" % [ids[i], got, wanted[i]])
			return false
	return true


func _fail(message: String) -> void:
	push_error(message)
	print("MUSIC TEST FAILED: " + message)
	quit(1)
