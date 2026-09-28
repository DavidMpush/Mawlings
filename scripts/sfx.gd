extends Node
## Pooled, rate-limited sound effects and handheld vibration.
## Main adds this as child "Sfx". Files live in res://assets/audio/<id>_<n>.wav
## (n = 1..): recorded user sounds and the user's audio pack V1, both processed by
## tools/import_user_sfx.py (see assets/audio/LICENSES.md), everything else
## procedural from tools/gen_sfx.py.

const AUDIO_DIR := "res://assets/audio/"
const MAX_VARIANTS := 8
const POOL_SIZE := 12
const AMBIENCE_ID := "ambience_jungle"
const VIBRATE_MIN_GAP_MS := 60

## Per id: gap = minimum ms between two starts, voices = max simultaneous voices,
## db = base loudness (files are all peak-normalised to -3 dBFS; db values of the
## imported ids are matched by tools/import_user_sfx.py --report loudness).
const RULES := {
	"bite": {"gap": 45, "voices": 3, "db": -9.5},       # pack V1: organic bites
	"kill": {"gap": 50, "voices": 3, "db": -7.5},       # user: blood pop
	"grow": {"gap": 60, "voices": 2, "db": -6.0},       # user: merge pop
	"hit": {"gap": 90, "voices": 2, "db": -5.0},
	"warn": {"gap": 250, "voices": 1, "db": -9.0},      # pack V1: enemy telegraph
	"stomp": {"gap": 200, "voices": 2, "db": -1.0},
	"mutate": {"gap": 150, "voices": 1, "db": -3.5},    # user: positive notification
	"evolve": {"gap": 400, "voices": 1, "db": -0.5},    # user: magic drag
	"extinct": {"gap": 1000, "voices": 1, "db": -4.5},  # pack V1: run end
	"pickup": {"gap": 70, "voices": 2, "db": -8.0},
	"ui": {"gap": 40, "voices": 2, "db": -12.5},        # pack V1: ui tap
	# Etappe 09: division, growth moments and losses.
	"split": {"gap": 70, "voices": 3, "db": -11.0},     # user: slime blob
	"milestone": {"gap": 600, "voices": 1, "db": 0.0},  # user: level completion
	"death": {"gap": 110, "voices": 2, "db": -5.0},     # user: blood pop, pitched down
	"leader_hit": {"gap": 250, "voices": 1, "db": -3.0},
	"leader_swap": {"gap": 500, "voices": 1, "db": -4.0},
	# Recorded user sounds for single big moments (tools/import_user_sfx.py).
	"boss_roar": {"gap": 1500, "voices": 1, "db": -1.5},
	"flood_warn": {"gap": 3000, "voices": 1, "db": -3.0},
	"quake": {"gap": 1500, "voices": 1, "db": -5.0},
	# Etappe 23: lifesteal/regeneration heals often - kept discreet (was -9.5 / 400).
	"regen": {"gap": 900, "voices": 1, "db": -12.5},
	"alpha_core": {"gap": 150, "voices": 2, "db": 0.0},
	"fanfare": {"gap": 3000, "voices": 1, "db": -4.0},
	"migration_whoosh": {"gap": 1500, "voices": 1, "db": -2.5},
	"leaper_windup": {"gap": 300, "voices": 2, "db": -5.0},
	"portal_open": {"gap": 1500, "voices": 1, "db": -6.0},
	# Audio pack V1 (tools/import_user_sfx.py). Gaps bundle bursts: many kills,
	# harvest ticks or DNA gains within the gap become one sound.
	"rally": {"gap": 250, "voices": 1, "db": -11.0},
	"harvest": {"gap": 450, "voices": 1, "db": -12.0},
	"dna": {"gap": 350, "voices": 1, "db": -11.5},
	"threat": {"gap": 2000, "voices": 1, "db": -2.0},
	"loss": {"gap": 700, "voices": 1, "db": 0.0},
	# Etappe 16: collected loot crystals, a chain with rising pitch (play(..., pitch)).
	# Short gap, few voices: a fast chain stays a pleasant ripple, not a wall.
	"collect_bio": {"gap": 65, "voices": 3, "db": -13.0},
	"collect_dna": {"gap": 80, "voices": 2, "db": -12.5},
	"lure": {"gap": 1500, "voices": 1, "db": -2.0},
	# Etappe 23 (audio pass): own sounds for the systems of stages 17-20, all
	# procedural (tools/gen_sfx.py SOUNDS_23). db values match the measured
	# loudness (loudest 300 ms) to their peers: chains ~ -27, loot moments
	# -22 .. -17 (rising with rarity), abilities ~ -19, desert hits -15 .. -17.
	"collect_coin": {"gap": 60, "voices": 3, "db": -9.0},       # Bernstein chain (pitch)
	"cocoon_open": {"gap": 300, "voices": 1, "db": -6.0},       # silk tears
	"cocoon_common": {"gap": 300, "voices": 1, "db": -7.5},
	"cocoon_rare": {"gap": 300, "voices": 1, "db": -7.0},
	"cocoon_epic": {"gap": 300, "voices": 1, "db": -5.0},
	"cocoon_legendary": {"gap": 600, "voices": 1, "db": -3.0},  # plus "fanfare"
	"cocoon_denied": {"gap": 700, "voices": 1, "db": -7.0},     # too expensive
	"powerup_take": {"gap": 300, "voices": 1, "db": -5.5},
	"powerup_end": {"gap": 500, "voices": 1, "db": -11.5},
	"shrine_tick": {"gap": 180, "voices": 1, "db": -10.0},      # pitch rises with the charge
	"shrine_done": {"gap": 1000, "voices": 1, "db": -5.5},
	"ability_glutsprung": {"gap": 250, "voices": 1, "db": -6.0},
	"ability_land": {"gap": 250, "voices": 1, "db": -3.0},
	"ability_sporenbombe": {"gap": 250, "voices": 1, "db": -3.5},
	"ability_panzerstoss": {"gap": 250, "voices": 1, "db": -3.0},
	"ability_hetzjagd": {"gap": 250, "voices": 1, "db": -6.5},
	"ability_saeureschwall": {"gap": 250, "voices": 1, "db": -3.0},
	"ability_schattenschleier": {"gap": 250, "voices": 1, "db": -5.0},
	"ability_ready": {"gap": 800, "voices": 1, "db": -10.5},
	"leader_hit_heavy": {"gap": 250, "voices": 1, "db": -2.0},
	"sandworm_breach": {"gap": 800, "voices": 1, "db": -2.5},
	"sandworm_sweep": {"gap": 800, "voices": 1, "db": -4.0},
	"sandgrub_burst": {"gap": 400, "voices": 1, "db": -3.5},
	# Etappe 24: Glutsumpf eruptions (scripts/eruptions.gd): the rising bubbling
	# under the ground ring (1.6 s, like the ring) and the burst itself.
	"lava_warn": {"gap": 400, "voices": 1, "db": -9.0},
	"lava_burst": {"gap": 300, "voices": 1, "db": -3.0},
}
## Ids that reuse the files of another id (no own recordings yet).
const SOURCES := {"collect_bio": "pickup", "collect_dna": "dna", "lure": "evolve", "leader_critical": "heartbeat"}
## Loops (start_loop/stop_loop), one voice each outside the pool.
const LOOP_RULES := {
	"heartbeat": {"db": -4.0},
	"portal_hum": {"db": -15.0},
	# Pack V1: group feeding while the swarm harvests, soft rustle while it moves.
	# Callers scale them with set_loop_volume() (swarm size, speed).
	"feed": {"db": -12.0},
	"rustle": {"db": -16.0},
	# Etappe 23: desert loops (scripts/desert_run.gd scales them per frame) and
	# the leader's own heartbeat at 1 LP (the "heartbeat" loop stays the last animal's).
	"sandworm_dig": {"db": -10.0},
	"sandstorm": {"db": -6.0},
	"quicksand": {"db": -12.0},
	"leader_critical": {"db": -9.0},
}
## Ambience per biome (set_ambience cross-fades); db offsets on ambience_volume_db.
const AMBIENCES := {"ambience_jungle": 0.0, "ambience_desert": 0.0, "ambience_glutsumpf": 0.0}
const AMBIENCE_FADE_SECONDS := 1.5

## Global offset in dB applied to every effect and the ambience.
var master_volume_db := 0.0:
	set(value):
		master_volume_db = clampf(value, -80.0, 12.0)
		_apply_ambience()
		for id: String in _loops:
			(_loops[id] as AudioStreamPlayer).volume_db = loop_volume_db(id)
const AUDIO_SETTINGS = preload("res://scripts/audio_settings.gd")
var sfx_enabled := true
var vibration_enabled := true
var ambience_volume_db := -17.0

var _streams := {}
var _last_variant := {}
var _last_start_ms := {}
var _players: Array[AudioStreamPlayer] = []
var _player_ids: Array[String] = []
var _player_started: Array[int] = []
## Bookkept end time per voice; independent of the audio driver (works headless).
var _player_end: Array[int] = []
var _ambience: AudioStreamPlayer   # the current biome's ambience player
var _ambience_id := AMBIENCE_ID
var _ambience_on := false
var _ambience_players := {}       # id -> AudioStreamPlayer
var _ambience_gain := {}          # id -> linear 0..1 (bookkept, also with the Dummy driver)
var _loops := {}          # id -> AudioStreamPlayer
var _loop_on := {}        # id -> bool (bookkept, also with the Dummy driver)
var _loop_db := {}        # id -> caller offset in dB (start_loop / set_loop_volume)
var _last_vibrate_ms := -100000
## True with the Dummy audio driver (headless tests): voices are only bookkept, never
## started, because the dummy mixer never releases playbacks and Godot reports leaks.
var _silent := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_silent = AudioServer.get_driver_name() == "Dummy"
	# Lautstärke-Regler: alle Geräusche laufen über den SFX-Bus (audio_settings.gd).
	AUDIO_SETTINGS.ensure_buses()
	for id: String in RULES:
		_load_variants(id)
	for id: String in AMBIENCES:
		_load_variants(id)
	for id: String in LOOP_RULES:
		_load_variants(id)
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "Voice%d" % i
		player.bus = AUDIO_SETTINGS.SFX
		add_child(player)
		_players.append(player)
		_player_ids.append("")
		_player_started.append(0)
		_player_end.append(0)


## `pitch` (Etappe 16) scales the playback rate on top of the jitter (collect chains).
func play(id: String, volume_db := 0.0, pitch_jitter := 0.08, pitch := 1.0) -> void:
	if not sfx_enabled or not RULES.has(id) or _players.is_empty():
		return
	var variants: Array = _streams.get(id, [])
	if variants.is_empty():
		return
	var rule: Dictionary = RULES[id]
	var now := Time.get_ticks_msec()
	if _last_start_ms.has(id) and now - int(_last_start_ms[id]) < int(rule["gap"]):
		return
	var active := active_voices(id)
	if active >= int(rule["voices"]):
		return
	var slot := _free_slot()
	_last_start_ms[id] = now
	var player := _players[slot]
	player.stop()
	var stream: AudioStream = variants[_pick_variant(id, variants.size())]
	player.stream = stream
	player.pitch_scale = clampf(pitch * (1.0 + randf_range(-pitch_jitter, pitch_jitter)), 0.5, 4.0)
	# Stacked voices of the same id get quieter so bursts stay pleasant.
	player.volume_db = float(rule["db"]) + volume_db + master_volume_db - 2.5 * active
	_player_ids[slot] = id
	_player_started[slot] = now
	_player_end[slot] = now + int(ceilf(stream.get_length() * 1000.0 / player.pitch_scale))
	if not _silent:
		player.play()


func vibrate(ms: int) -> void:
	if not vibration_enabled or ms <= 0 or not OS.has_feature("mobile"):
		return
	var now := Time.get_ticks_msec()
	if now - _last_vibrate_ms < VIBRATE_MIN_GAP_MS:
		return
	_last_vibrate_ms = now
	Input.vibrate_handheld(ms)


func play_ambience() -> void:
	var first := not _ambience_on
	_ambience_on = true
	var player := _ambience_player(_ambience_id)
	if player == null:
		return
	_ambience = player
	# The very first start is immediate; later switches cross-fade in _process.
	if first and _max_ambience_gain() <= 0.0:
		_ambience_gain[_ambience_id] = 1.0
	_apply_ambience()
	if not player.playing and not _silent:
		player.play()


func stop_ambience() -> void:
	_ambience_on = false
	for id: String in _ambience_players:
		(_ambience_players[id] as AudioStreamPlayer).stop()
		_ambience_gain[id] = 0.0


## Etappe 23: switches the ambience bed (e.g. "ambience_desert" in the
## Dürrschlund); the old one fades out over AMBIENCE_FADE_SECONDS.
func set_ambience(id: String) -> void:
	if not AMBIENCES.has(id) or id == _ambience_id or (_streams.get(id, []) as Array).is_empty():
		return
	_ambience_id = id
	if not _ambience_on:
		return
	var player := _ambience_player(id)
	_ambience = player
	_apply_ambience()
	if player != null and not player.playing and not _silent:
		player.play()


func ambience_id() -> String:
	return _ambience_id


## Linear gain 0..1 of an ambience bed (tests).
func ambience_gain(id: String) -> float:
	return float(_ambience_gain.get(id, 0.0))


func _process(delta: float) -> void:
	if _ambience_players.is_empty():
		return
	var step := delta / AMBIENCE_FADE_SECONDS
	for id: String in _ambience_players:
		var target := 1.0 if _ambience_on and id == _ambience_id else 0.0
		var gain := move_toward(float(_ambience_gain.get(id, 0.0)), target, step)
		_ambience_gain[id] = gain
		var player: AudioStreamPlayer = _ambience_players[id]
		if gain <= 0.0 and target <= 0.0 and player.playing:
			player.stop()
	_apply_ambience()


func _ambience_player(id: String) -> AudioStreamPlayer:
	var variants: Array = _streams.get(id, [])
	if variants.is_empty():
		return null
	var player: AudioStreamPlayer = _ambience_players.get(id)
	if player == null:
		player = AudioStreamPlayer.new()
		player.name = "Ambience" if id == AMBIENCE_ID else "Ambience_" + id.trim_prefix("ambience_")
		player.bus = AUDIO_SETTINGS.SFX
		add_child(player)
		player.stream = _looped(variants[0])
		_ambience_players[id] = player
		_ambience_gain[id] = float(_ambience_gain.get(id, 0.0))
	return player


func _max_ambience_gain() -> float:
	var best := 0.0
	for id: String in _ambience_gain:
		best = maxf(best, float(_ambience_gain[id]))
	return best


func _apply_ambience() -> void:
	for id: String in _ambience_players:
		var gain := float(_ambience_gain.get(id, 0.0))
		var db := _ambience_db() + float(AMBIENCES.get(id, 0.0))
		(_ambience_players[id] as AudioStreamPlayer).volume_db = db + linear_to_db(gain) if gain > 0.001 else -80.0


## Starts a seamless loop (e.g. "heartbeat"); calling it again keeps it running
## and only updates the volume offset.
func start_loop(id: String, volume_db := 0.0) -> void:
	if not LOOP_RULES.has(id) or not sfx_enabled:
		return
	var variants: Array = _streams.get(id, [])
	if variants.is_empty():
		return
	_loop_on[id] = true
	_loop_db[id] = volume_db
	var player: AudioStreamPlayer = _loops.get(id)
	if player == null:
		player = AudioStreamPlayer.new()
		player.name = "Loop_" + id
		player.bus = AUDIO_SETTINGS.SFX
		add_child(player)
		player.stream = _looped(variants[0])
		_loops[id] = player
	player.volume_db = loop_volume_db(id)
	if not player.playing and not _silent:
		player.play()


## Changes the offset of a loop without restarting it (e.g. rustle by swarm size).
func set_loop_volume(id: String, volume_db: float) -> void:
	if not LOOP_RULES.has(id):
		return
	_loop_db[id] = volume_db
	var player: AudioStreamPlayer = _loops.get(id)
	if player != null:
		player.volume_db = loop_volume_db(id)


## Effective volume of a loop: rule + caller offset + master.
func loop_volume_db(id: String) -> float:
	if not LOOP_RULES.has(id):
		return -80.0
	return float(LOOP_RULES[id]["db"]) + float(_loop_db.get(id, 0.0)) + master_volume_db


func stop_loop(id: String) -> void:
	_loop_on[id] = false
	var player: AudioStreamPlayer = _loops.get(id)
	if player != null:
		player.stop()


## True when `id` started less than `ms` milliseconds ago (callers avoid doubles).
func recently_played(id: String, ms: int) -> bool:
	return _last_start_ms.has(id) and Time.get_ticks_msec() - int(_last_start_ms[id]) < ms


func is_looping(id: String) -> bool:
	return bool(_loop_on.get(id, false))


## Number of pool voices currently playing the given id.
func active_voices(id: String) -> int:
	var count := 0
	var now := Time.get_ticks_msec()
	for i in _players.size():
		if _player_ids[i] == id and _player_end[i] > now:
			count += 1
	return count


func variant_count(id: String) -> int:
	return (_streams.get(id, []) as Array).size()


func sound_ids() -> Array:
	return RULES.keys()


func stop_all() -> void:
	for i in _players.size():
		_players[i].stop()
		_player_end[i] = 0
	stop_ambience()
	for id: String in _loops:
		stop_loop(id)


func _exit_tree() -> void:
	# Release streams so no playback outlives the node (matters for headless/dummy audio).
	stop_all()
	for player in _players:
		player.stream = null
	for id: String in _ambience_players:
		(_ambience_players[id] as AudioStreamPlayer).stream = null
	for id: String in _loops:
		(_loops[id] as AudioStreamPlayer).stream = null


func _looped(stream: AudioStream) -> AudioStream:
	if stream is AudioStreamWAV:
		var wav := (stream as AudioStreamWAV).duplicate() as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * float(wav.mix_rate))
		return wav
	return stream


func _load_variants(id: String) -> void:
	# Probe fixed names instead of DirAccess: exported builds only list .import files.
	var list: Array = []
	for n in range(1, MAX_VARIANTS + 1):
		var path := "%s%s_%d.wav" % [AUDIO_DIR, String(SOURCES.get(id, id)), n]
		if not ResourceLoader.exists(path):
			break
		var stream := load(path) as AudioStream
		if stream != null:
			list.append(stream)
	_streams[id] = list


func _pick_variant(id: String, count: int) -> int:
	var last := int(_last_variant.get(id, -1))
	var index := randi() % count
	if count > 1 and index == last:
		index = (index + 1 + randi() % (count - 1)) % count
	_last_variant[id] = index
	return index


func _free_slot() -> int:
	var oldest := 0
	var now := Time.get_ticks_msec()
	for i in _players.size():
		if _player_end[i] <= now:
			return i
		if _player_started[i] < _player_started[oldest]:
			oldest = i
	return oldest


func _ambience_db() -> float:
	return ambience_volume_db + master_volume_db
