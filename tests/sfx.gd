extends SceneTree

const SfxScript := preload("res://scripts/sfx.gd")
const IDS := ["bite", "kill", "grow", "hit", "warn", "stomp", "mutate", "evolve", "extinct", "pickup", "ui"]
## Recorded user sounds (tools/import_user_sfx.py) for single big moments.
const USER_IDS := ["boss_roar", "flood_warn", "quake", "regen", "alpha_core", "fanfare", "migration_whoosh", "leaper_windup", "portal_open"]
## Audio pack V1 (tools/import_user_sfx.py "dir": "v1"): new one-shots and loops.
## bite, warn, ui and extinct are V1 too (replacements, checked via IDS).
const V1_IDS := ["rally", "harvest", "dna", "threat", "loss"]
const V1_LOOPS := ["feed", "rustle"]
## Rare one-shots may ship a single variant; every other id needs at least two.
const SINGLE_OK := ["fanfare", "migration_whoosh"]
## Etappe 23 (audio pass): own sounds for the systems of stages 17-20 (no borrowed ids).
const E23_IDS := ["collect_coin", "cocoon_open", "cocoon_common", "cocoon_rare", "cocoon_epic", "cocoon_legendary",
	"cocoon_denied", "powerup_take", "powerup_end", "shrine_tick", "shrine_done", "ability_glutsprung", "ability_land",
	"ability_sporenbombe", "ability_panzerstoss", "ability_hetzjagd", "ability_saeureschwall", "ability_schattenschleier",
	"ability_ready", "leader_hit_heavy", "sandworm_breach", "sandworm_sweep", "sandgrub_burst",
	"lava_warn", "lava_burst"]  # Etappe 24: Glutsumpf eruptions
const E23_LOOPS := ["sandworm_dig", "sandstorm", "quicksand", "leader_critical"]


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
	for id: String in V1_IDS:
		if not SfxScript.RULES.has(id):
			_fail("V1 sound id '%s' missing in Sfx.RULES" % id)
			return
	for id: String in V1_LOOPS:
		if not SfxScript.LOOP_RULES.has(id):
			_fail("V1 loop '%s' missing in Sfx.LOOP_RULES" % id)
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
	for id: String in V1_IDS:
		if sfx.variant_count(id) < 2:
			_fail("Sfx loaded %d variant(s) for V1 id %s, expected >= 2" % [sfx.variant_count(id), id])
			return
		sfx.play(id)
		if sfx.active_voices(id) != 1:
			_fail("play('%s') did not start a voice" % id)
			return
	# Bundling: a burst of DNA / harvest calls within the gap stays one sound.
	for i in 20:
		sfx.play("dna")
		sfx.play("harvest")
	if sfx.active_voices("dna") != 1 or sfx.active_voices("harvest") != 1:
		_fail("DNA/harvest burst not bundled: %d / %d voices" % [sfx.active_voices("dna"), sfx.active_voices("harvest")])
		return
	sfx.stop_all()
	# V1 loops: start with an offset, change it live, master volume applies, stop.
	for id: String in V1_LOOPS:
		if sfx.variant_count(id) != 1:
			_fail("Loop %s should have exactly one file" % id)
			return
		var base: float = float(SfxScript.LOOP_RULES[id]["db"])
		sfx.start_loop(id, -6.0)
		if not sfx.is_looping(id) or absf(sfx.loop_volume_db(id) - (base - 6.0)) > 0.01:
			_fail("Loop %s did not start at %.1f dB (got %.1f)" % [id, base - 6.0, sfx.loop_volume_db(id)])
			return
		sfx.set_loop_volume(id, 2.0)
		sfx.master_volume_db = -3.0
		var live: float = (sfx._loops[id] as AudioStreamPlayer).volume_db
		if absf(sfx.loop_volume_db(id) - (base - 1.0)) > 0.01 or absf(live - (base - 1.0)) > 0.01:
			_fail("Loop %s volume not updated live (%.1f dB)" % [id, live])
			return
		sfx.master_volume_db = 0.0
		sfx.start_loop(id)  # a second start keeps it running and resets the offset
		sfx.stop_loop(id)
		if sfx.is_looping(id):
			_fail("Loop %s did not stop" % id)
			return
	sfx.set_loop_volume("does_not_exist", 3.0)
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
	sfx.master_volume_db = 0.0
	if not _check_e23(sfx):
		return
	sfx.stop_all()
	sfx.queue_free()
	await process_frame
	if not await _check_game_wiring():
		return
	print("SFX test passed: %d ids (%d recorded, %d V1 + %d V1 loops, %d + %d loops Etappe 23, biome ambience), bite burst=%d, spaced=%d/%d" % [SfxScript.RULES.size(), USER_IDS.size(), V1_IDS.size(), V1_LOOPS.size(), E23_IDS.size(), E23_LOOPS.size(), burst, spaced, limit])
	quit(0)


## Etappe 23: own files for every new id, sane levels, desert loops and the
## biome ambience cross-fade (jungle -> desert -> jungle).
func _check_e23(sfx: Node) -> bool:
	for id: String in E23_IDS:
		if not SfxScript.RULES.has(id) or SfxScript.SOURCES.has(id):
			_fail("Etappe 23 id '%s' missing in RULES or borrowed via SOURCES" % id)
			return false
		var db := float(SfxScript.RULES[id]["db"])
		if db > 0.0 or db < -14.0:
			_fail("Etappe 23 id '%s' has an odd level (%.1f dB)" % [id, db])
			return false
		if sfx.variant_count(id) < 2:
			_fail("Etappe 23 id '%s' loaded %d variant(s), expected >= 2" % [id, sfx.variant_count(id)])
			return false
		sfx.play(id)
		if sfx.active_voices(id) != 1:
			_fail("play('%s') did not start a voice" % id)
			return false
	# Chains stay the quietest layer: coin like the crystal chain, below the loot moments.
	if float(SfxScript.RULES["collect_coin"]["db"]) > float(SfxScript.RULES["cocoon_common"]["db"]):
		_fail("collect_coin is louder than the cocoon moments")
		return false
	for id: String in E23_LOOPS:
		if not SfxScript.LOOP_RULES.has(id) or sfx.variant_count(id) < 1:
			_fail("Etappe 23 loop '%s' missing (no file)" % id)
			return false
		sfx.start_loop(id, -3.0)
		if not sfx.is_looping(id):
			_fail("Loop %s did not start" % id)
			return false
		sfx.stop_loop(id)
	for bed: String in ["ambience_desert", "ambience_glutsumpf"]:
		if sfx.variant_count(bed) != 1 or not SfxScript.AMBIENCES.has(bed):
			_fail("Ambience %s missing" % bed)
			return false
	sfx.play_ambience()
	if sfx.ambience_id() != "ambience_jungle" or sfx.ambience_gain("ambience_jungle") < 1.0:
		_fail("Ambience does not start on the jungle bed at full level")
		return false
	sfx.set_ambience("does_not_exist")
	sfx.set_ambience("ambience_desert")
	if sfx.ambience_id() != "ambience_desert":
		_fail("set_ambience did not switch to the desert")
		return false
	for i in 120:
		sfx._process(1.0 / 60.0)
	if sfx.ambience_gain("ambience_desert") < 0.99 or sfx.ambience_gain("ambience_jungle") > 0.01:
		_fail("Ambience cross-fade failed: desert %.2f jungle %.2f" % [sfx.ambience_gain("ambience_desert"), sfx.ambience_gain("ambience_jungle")])
		return false
	sfx.set_ambience("ambience_glutsumpf")
	for i in 120:
		sfx._process(1.0 / 60.0)
	if sfx.ambience_gain("ambience_glutsumpf") < 0.99 or sfx.ambience_gain("ambience_desert") > 0.01:
		_fail("Ambience does not fade to the Glutsumpf")
		return false
	sfx.set_ambience("ambience_jungle")
	for i in 120:
		sfx._process(1.0 / 60.0)
	if sfx.ambience_gain("ambience_jungle") < 0.99 or sfx.ambience_gain("ambience_glutsumpf") > 0.01:
		_fail("Ambience does not fade back to the jungle")
		return false
	sfx.stop_ambience()
	if sfx.ambience_gain("ambience_jungle") > 0.0:
		_fail("stop_ambience left a bed audible")
		return false
	return true


## Audio pack V1 calls inside the run scene (main.tscn): rally edge, collect
## chain (Etappe 16), painful loss, threat, rustle, ui tap, music style.
func _check_game_wiring() -> bool:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var game_sfx: Node = scene.get_node_or_null("Sfx")
	var world: Node = scene.get_node("HuntWorld")
	var swarm: Node = scene.get_node("Swarm")
	if game_sfx == null:
		_fail("Main has no Sfx node")
		return false
	swarm.set_controls(Vector2.ZERO, false)
	swarm.set_controls(Vector2.ZERO, true)
	if not game_sfx.recently_played("rally", 500):
		_fail("Rally press did not play 'rally'")
		return false
	# Etappe 16: collected crystals play a rising collect chain (no feed loop any more).
	world.drop_loot(swarm.position, 2.0, 0)
	world.collect_loot_now()
	if not game_sfx.recently_played("collect_bio", 500) or game_sfx.is_looping("feed"):
		_fail("Collected biomass did not play 'collect_bio' (or a feed loop runs)")
		return false
	var chain_before: int = world.collect_chain
	world.collect_sound_ms -= 1000
	world.drop_loot(swarm.position, 0.0, 3)
	world.collect_loot_now()
	if not game_sfx.recently_played("collect_dna", 500) and not game_sfx.recently_played("collect_bio", 100):
		_fail("Collected DNA did not play a collect sound")
		return false
	if world.collect_chain != chain_before + 1:
		_fail("Quick arrivals must climb the collect chain (%d -> %d)" % [chain_before, world.collect_chain])
		return false
	world.drop_loot(swarm.position, 2.0, 0)
	world.collect_loot_now()
	if world.collect_chain != chain_before + 1:
		_fail("Collect sounds are throttled (chain %d)" % world.collect_chain)
		return false
	world.model.elapsed = world.model.pressure_doubling * 1.01
	world._audio_threat()
	if not game_sfx.recently_played("threat", 500) or world.threat_doublings != 1:
		_fail("Pressure doubling did not play 'threat'")
		return false
	var controls: Node = scene.get_node("HUD/Controls")
	# Main steers the swarm from the controls every frame.
	controls.movement_vector = Vector2(1, 0)
	for i in 6:
		await process_frame
	if not game_sfx.is_looping("rustle"):
		_fail("Moving swarm did not start the rustle loop")
		return false
	controls.movement_vector = Vector2.ZERO
	for i in 8:
		await process_frame
	if game_sfx.is_looping("rustle"):
		_fail("Rustle loop kept running while the swarm stands still")
		return false
	controls._tap_sound()
	if not game_sfx.recently_played("ui", 500):
		_fail("Touch controls tap did not play 'ui'")
		return false
	var music: Node = scene.get_node_or_null("Music")
	if music != null:
		scene._apply_settings({"sound": true, "music_v1": true})
		if music.style() != "v1":
			_fail("Setting music_v1 did not switch the music style")
			return false
		scene._apply_settings({"sound": true, "music_v1": false})
		if music.style() != "classic":
			_fail("Setting music_v1 off did not restore the classic style")
			return false
	world.alpha_cores_enabled = true
	var core: Node3D = world._drop_alpha_core(Vector3.ZERO)
	if core.get_node("Float").get_node_or_null("CoreModel") == null:
		_fail("Alpha core pickup has no CoreModel")
		return false
	world.model.population = 20
	swarm.set_population(20, false)
	world._apply_hit(5, swarm.position, 0.1)
	if not game_sfx.recently_played("loss", 500):
		_fail("A 25 %% loss did not play 'loss'")
		return false
	scene.queue_free()
	await process_frame
	return true


## Number of consecutive <id>_<n>.wav files; -1 (after _fail) when one is not audio.
func _count_files(id: String) -> int:
	var found := 0
	for n in range(1, SfxScript.MAX_VARIANTS + 1):
		var path := "res://assets/audio/%s_%d.wav" % [String(SfxScript.SOURCES.get(id, id)), n]
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
