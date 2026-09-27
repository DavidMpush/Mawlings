extends Node
## Adaptive music. Menu theme, four synchronised run stems cross-faded by
## intensity, and one-shot stingers. Files come from tools/gen_music.py
## (res://assets/music/, 22.05 kHz mono WAV, loops carry a 'smpl' loop chunk).
##
## Run stems all have the same length and tempo and are started in the same
## frame, so they stay sample-aligned; only their volumes change.
## With the Dummy audio driver (headless tests) nothing is ever started: all
## state (targets, fades, stingers) is only bookkept, so no playback can leak.
##
## Style "v1" (set_style) replaces the run stems by the user's audio pack V1:
## an arena loop (96 BPM, 40 s) and a boss loop (128 BPM, 30 s) from
## tools/import_user_sfx.py. The tempos differ, so the two are cross-faded, never
## layered; the boss loop restarts at its first bar each time it fades in.
## Menu theme and stingers are shared by both styles. Default stays "classic".

const MUSIC_DIR := "res://assets/music/"
const MENU_ID := "menu_theme"
const STEMS: Array[String] = ["run_base", "run_tension", "run_flood", "run_boss"]
const STINGERS := {
	"flood": "sting_flood",
	"boss": "sting_boss",
	"king": "sting_king",
	"extinct": "sting_extinct",
}
## Mix level (dB) of each layer at full intensity; files are all peak-normalised to -3 dBFS.
const STEM_DB := {"run_base": -9.0, "run_tension": -11.0, "run_flood": -9.0, "run_boss": -8.0}
const STYLES: Array[String] = ["classic", "v1"]
const V1_LOOPS: Array[String] = ["v1_arena", "v1_boss"]
## Mix level of the V1 loops (both are bass-heavy: phone loudness about -22 / -24).
const V1_DB := {"v1_arena": -7.0, "v1_boss": -6.0}
const MENU_DB := -8.0
const STINGER_DB := -5.0
const SILENT_DB := -60.0
## Seconds for a full 0 -> 1 fade of a layer (linear amplitude).
const FADE_SECONDS := 2.0
const START_FADE_SECONDS := 1.5
const STOP_FADE_SECONDS := 0.6
## Stingers duck the loops by this much for their length.
const DUCK_DB := -7.0
const DUCK_RELEASE_SECONDS := 0.8

enum Mode { NONE, MENU, RUN }

## Global offset in dB for all music.
var master_volume_db := 0.0:
	set(value):
		master_volume_db = clampf(value, -80.0, 12.0)
		_apply_volumes()
var enabled := true
var mode := Mode.NONE

var _streams := {}
var _menu_player: AudioStreamPlayer
var _stem_players: Array[AudioStreamPlayer] = []
var _v1_players: Array[AudioStreamPlayer] = []
## Linear gains 0..1 of the V1 loops (index = V1_LOOPS order).
var _v1_gain: Array[float] = [0.0, 0.0]
var _v1_target: Array[float] = [0.0, 0.0]
var _style := "classic"
## Last set_intensity() arguments, so a style switch can rebuild the targets.
var _pressure := 1.0
var _flood := false
var _boss := false
var _stinger_player: AudioStreamPlayer
## Linear gains 0..1 per layer: current and target (index = STEMS order), plus menu.
var _stem_gain: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _stem_target: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _menu_gain := 0.0
var _menu_target := 0.0
var _fade_rate := 1.0 / FADE_SECONDS
## 0 = no duck, 1 = fully ducked; bookkept per stinger.
var _duck := 0.0
var _duck_hold := 0.0
var _last_stinger := ""
var _stopping := false
var _silent := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_silent = AudioServer.get_driver_name() == "Dummy"
	_load(MENU_ID, true)
	for id in STEMS:
		_load(id, true)
	for key: String in STINGERS:
		_load(STINGERS[key], false)
	for id in V1_LOOPS:
		_load(id, true)
	_menu_player = _make_player("Menu")
	_menu_player.stream = _streams.get(MENU_ID)
	for id in STEMS:
		var player := _make_player(id)
		player.stream = _streams.get(id)
		_stem_players.append(player)
	for id in V1_LOOPS:
		var player := _make_player(id)
		player.stream = _streams.get(id)
		_v1_players.append(player)
	_stinger_player = _make_player("Stinger")
	_apply_volumes()


func _process(delta: float) -> void:
	var real_delta := delta / maxf(0.01, Engine.time_scale)
	var step := _fade_rate * real_delta
	for i in STEMS.size():
		_stem_gain[i] = move_toward(_stem_gain[i], _stem_target[i], step)
	_menu_gain = move_toward(_menu_gain, _menu_target, step)
	for i in V1_LOOPS.size():
		_v1_gain[i] = move_toward(_v1_gain[i], _v1_target[i], step)
		# A faded-out V1 loop stops; it restarts at bar 1 when it is needed again.
		if _v1_gain[i] <= 0.0 and _v1_target[i] <= 0.0 and _v1_players[i].playing:
			_v1_players[i].stop()
	# Classic stems stop together once silent in style v1 (restart in sync later).
	if _style != "classic" and _max_stem_gain() <= 0.0 and not _stem_players.is_empty() and _stem_players[0].playing:
		for player in _stem_players:
			player.stop()
	if _duck_hold > 0.0:
		_duck_hold -= real_delta
	else:
		_duck = move_toward(_duck, 0.0, real_delta / DUCK_RELEASE_SECONDS)
	_apply_volumes()
	if _stopping and _menu_gain <= 0.0 and _max_stem_gain() <= 0.0 and _max_v1_gain() <= 0.0:
		_stopping = false
		_halt_players()
		mode = Mode.NONE


# ---------------------------------------------------------------- public API

func play_menu() -> void:
	if mode == Mode.MENU and not _stopping:
		return
	_stopping = false
	for i in STEMS.size():
		_stem_target[i] = 0.0
	_v1_target = [0.0, 0.0]
	_menu_target = 1.0
	_fade_rate = 1.0 / START_FADE_SECONDS
	mode = Mode.MENU
	if enabled:
		_start_menu()


## Starts all run stems in sync; base layer fades in, the rest wait for set_intensity().
func play_run() -> void:
	if mode == Mode.RUN and not _stopping:
		return
	_stopping = false
	_menu_target = 0.0
	_pressure = 1.0
	_flood = false
	_boss = false
	_update_run_targets()
	_fade_rate = 1.0 / START_FADE_SECONDS
	mode = Mode.RUN
	if enabled:
		_start_run_layers()


## pressure_level: hunt_world's model.pressure() (1.0 at start, doubles every
## PRESSURE_DOUBLING_SECONDS). The tension layer blends in from pressure 1.5 to 4.
## flood / boss switch their layers on; the flood also holds tension at full.
## Style v1: the arena loop plays, a boss cross-fades to the boss loop and back.
func set_intensity(pressure_level: float, flood: bool, boss: bool) -> void:
	if mode != Mode.RUN or _stopping:
		return
	_pressure = pressure_level
	_flood = flood
	_boss = boss
	_update_run_targets()
	_fade_rate = 1.0 / FADE_SECONDS
	if enabled:
		_start_v1_needed()


## "classic" (adaptive stems, default) or "v1" (audio pack V1 loops). Unknown
## names are ignored. During a run the layers cross-fade over FADE_SECONDS.
func set_style(style_name: String) -> void:
	if not STYLES.has(style_name) or style_name == _style:
		return
	_style = style_name
	if mode != Mode.RUN or _stopping:
		return
	_update_run_targets()
	_fade_rate = 1.0 / FADE_SECONDS
	if enabled:
		_start_run_layers()


func style() -> String:
	return _style


func styles() -> Array[String]:
	return STYLES.duplicate()


## id: "flood", "boss", "king" or "extinct". Unknown ids are ignored.
func stinger(id: String) -> void:
	if not STINGERS.has(id) or not enabled:
		return
	var stream: AudioStream = _streams.get(STINGERS[id])
	if stream == null:
		return
	_last_stinger = id
	_duck = 1.0
	_duck_hold = maxf(0.0, stream.get_length() - DUCK_RELEASE_SECONDS)
	_apply_volumes()
	_stinger_player.stream = stream
	_stinger_player.volume_db = STINGER_DB + master_volume_db
	if not _silent:
		_stinger_player.play()


## Fades everything out, then stops the players.
func stop(immediate := false) -> void:
	_menu_target = 0.0
	_stem_target = [0.0, 0.0, 0.0, 0.0]
	_v1_target = [0.0, 0.0]
	_fade_rate = 1.0 / STOP_FADE_SECONDS
	if immediate or mode == Mode.NONE:
		_menu_gain = 0.0
		_stem_gain = [0.0, 0.0, 0.0, 0.0]
		_v1_gain = [0.0, 0.0]
		_halt_players()
		_stinger_player.stop()
		_stopping = false
		mode = Mode.NONE
		_apply_volumes()
	else:
		_stopping = true


## Off: silence and stop immediately (mode is remembered). On: resume that mode.
func set_enabled(value: bool) -> void:
	if value == enabled:
		return
	enabled = value
	if not enabled:
		_halt_players()
		_stinger_player.stop()
		_menu_gain = 0.0
		_stem_gain = [0.0, 0.0, 0.0, 0.0]
		_v1_gain = [0.0, 0.0]
		_apply_volumes()
	elif mode == Mode.MENU:
		_start_menu()
	elif mode == Mode.RUN:
		_start_run_layers()


func set_master_volume_db(value: float) -> void:
	master_volume_db = value


# ---------------------------------------------------------------- inspection (tests, HUD)

func stem_ids() -> Array[String]:
	return STEMS.duplicate()


func stem_target(id: String) -> float:
	var i := STEMS.find(id)
	return _stem_target[i] if i >= 0 else 0.0


func stem_gain(id: String) -> float:
	var i := STEMS.find(id)
	return _stem_gain[i] if i >= 0 else 0.0


func v1_ids() -> Array[String]:
	return V1_LOOPS.duplicate()


func v1_target(id: String) -> float:
	var i := V1_LOOPS.find(id)
	return _v1_target[i] if i >= 0 else 0.0


func v1_gain(id: String) -> float:
	var i := V1_LOOPS.find(id)
	return _v1_gain[i] if i >= 0 else 0.0


func v1_volume_db(id: String) -> float:
	var i := V1_LOOPS.find(id)
	return _v1_players[i].volume_db if i >= 0 else SILENT_DB


func menu_gain() -> float:
	return _menu_gain


func menu_target() -> float:
	return _menu_target


func stem_volume_db(id: String) -> float:
	var i := STEMS.find(id)
	return _stem_players[i].volume_db if i >= 0 else SILENT_DB


func last_stinger() -> String:
	return _last_stinger


func ducking() -> float:
	return _duck


func stream(id: String) -> AudioStream:
	return _streams.get(id)


func is_silent_driver() -> bool:
	return _silent


# ---------------------------------------------------------------- internals

func _exit_tree() -> void:
	# Release streams so no playback outlives the node (matters for the Dummy driver).
	_halt_players()
	for player in _all_players():
		player.stop()
		player.stream = null


func _load(id: String, loop: bool) -> void:
	var path := "%s%s.wav" % [MUSIC_DIR, id]
	if not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	# Loops normally come from the 'smpl' chunk; enforce them anyway.
	if loop and stream is AudioStreamWAV and (stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
		var wav := (stream as AudioStreamWAV).duplicate() as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(round(wav.get_length() * float(wav.mix_rate)))
		stream = wav
	_streams[id] = stream


func _make_player(player_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.volume_db = SILENT_DB
	add_child(player)
	return player


func _start_menu() -> void:
	for player in _stem_players:
		player.stop()
	for player in _v1_players:
		player.stop()
	if _silent or _menu_player.stream == null or _menu_player.playing:
		return
	_menu_player.play()


func _start_stems() -> void:
	_menu_player.stop()
	if _silent:
		return
	# Restart every stem at position 0 in the same frame so they stay aligned.
	for player in _stem_players:
		if player.stream != null:
			player.play(0.0)


## Starts whatever the current style needs; layers of the other style fade out.
func _start_run_layers() -> void:
	_menu_player.stop()
	if _style == "classic":
		if not _stem_players.is_empty() and not _stem_players[0].playing:
			_start_stems()
	else:
		_start_v1_needed()


## Starts each V1 loop whose target is above zero and that is not running (bar 1).
func _start_v1_needed() -> void:
	if _silent:
		return
	for i in V1_LOOPS.size():
		if _v1_target[i] > 0.0 and not _v1_players[i].playing and _v1_players[i].stream != null:
			_v1_players[i].play(0.0)


func _update_run_targets() -> void:
	if _style == "classic":
		var octaves := log(maxf(_pressure, 1.0)) / log(2.0)
		var tension := clampf((octaves - 0.585) / 1.415, 0.0, 1.0)
		_stem_target = [1.0, 1.0 if _flood else tension, 1.0 if _flood else 0.0, 1.0 if _boss else 0.0]
		_v1_target = [0.0, 0.0]
	else:
		_stem_target = [0.0, 0.0, 0.0, 0.0]
		_v1_target[0] = 0.0 if _boss else 1.0
		_v1_target[1] = 1.0 if _boss else 0.0


func _halt_players() -> void:
	if _menu_player != null:
		_menu_player.stop()
	for player in _stem_players:
		player.stop()
	for player in _v1_players:
		player.stop()


func _all_players() -> Array[AudioStreamPlayer]:
	var list: Array[AudioStreamPlayer] = []
	list.append_array(_stem_players)
	list.append_array(_v1_players)
	for player in [_menu_player, _stinger_player]:
		if player != null:
			list.append(player)
	return list


func _max_stem_gain() -> float:
	var best := 0.0
	for g in _stem_gain:
		best = maxf(best, g)
	return best


func _max_v1_gain() -> float:
	return maxf(_v1_gain[0], _v1_gain[1])


func _apply_volumes() -> void:
	if _menu_player == null:
		return
	var duck_db := DUCK_DB * _duck
	_menu_player.volume_db = _gain_db(_menu_gain, MENU_DB + duck_db)
	for i in _stem_players.size():
		_stem_players[i].volume_db = _gain_db(_stem_gain[i], float(STEM_DB[STEMS[i]]) + duck_db)
	for i in _v1_players.size():
		_v1_players[i].volume_db = _gain_db(_v1_gain[i], float(V1_DB[V1_LOOPS[i]]) + duck_db)


func _gain_db(gain: float, base_db: float) -> float:
	if gain <= 0.001:
		return SILENT_DB
	return maxf(SILENT_DB, base_db + master_volume_db + linear_to_db(gain))
