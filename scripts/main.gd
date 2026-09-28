extends Node3D

@onready var swarm: Node3D = $Swarm
@onready var camera: Camera3D = $Camera3D
@onready var controls: Control = $HUD/Controls
@onready var world: Node3D = $HuntWorld
@onready var arena: Node3D = $Arena

const CAMERA_OFFSET := Vector3(0.0, 23.0, 15.0)
# Parallel modules are loaded at runtime so the game still starts without them.
const SESSION_PATH := "res://scripts/meta/session.gd"
const SFX_PATH := "res://scripts/sfx.gd"
const PROFILE_PATH := "res://scripts/meta/profile.gd"
const MENU_SCENE := "res://scenes/menu.tscn"
const ONBOARDING_PATH := "res://scripts/onboarding.gd"
const QUALITY = preload("res://scripts/quality.gd")
const BIOMES = preload("res://scripts/biomes.gd")
# Stage 10 migration swirl: the camera pushes towards the maw while it closes.
const MIGRATION_ZOOM := 0.82

const KING_SLOW_SCALE := 0.3
const KING_SLOW_SECONDS := 0.6      # real time, not game time
const KING_ZOOM_SECONDS := 1.3      # real time
const KING_ZOOM := 0.74
const HITSTOP_MAX := 0.12           # real seconds
const HITSTOP_SCALE := 0.04

var shake := 0.0
var zoom := 1.0
var camera_base := Vector3.ZERO
# Königsmoment: real-time countdowns for slow motion and the close zoom. Slow
# motion is skipped headless so fixed-delta tests and the bot stay deterministic;
# tests switch it on explicitly.
var slow_motion_enabled := DisplayServer.get_name() != "headless"
var king_slow_left := 0.0
var king_zoom_left := 0.0
var king_focus := Vector3.ZERO
var hitstop_left := 0.0
# Etappe 25: boss entrance - the camera pulls back a little for a moment.
const DRAMA_ZOOM := 1.12
const DRAMA_PATH := "res://scripts/drama.gd"
var drama_zoom_left := 0.0
# Etappe 07: quality tier (quality.gd Tier) and its display switches.
var quality_tier := -1
var quality: Dictionary = {}


func _ready() -> void:
	_register_keyboard_input()
	controls.restart_requested.connect(_restart)
	controls.pause_requested.connect(world.toggle_pause)
	controls.mutation_chosen.connect(world.choose_mutation)
	for pair in [["hub_requested", _open_hub], ["reroll_requested", world.reroll_mutations], ["skip_requested", world.skip_mutation], ["banish_requested", world.banish_mutation]]:
		if controls.has_signal(pair[0]):
			controls.connect(pair[0], pair[1])
	_create_sfx()
	var config := _take_pending_config()
	_apply_quality(config.get("settings", {}))
	if not config.is_empty():
		# The map is generated from the run seed before the world spawns into it.
		# Stage 18: bounded map; multiplayer configs bring "players" (bigger map).
		if config.has("players") or config.has("map_regions"):
			var players := int(config.get("players", 1))
			arena.configure_map(int(config.get("map_regions", arena.regions_for_players(players))), players)
		arena.set_seed(int(config.get("seed", 0)))
		_apply_settings(config.get("settings", {}))
		world.apply_config(config)
		_create_onboarding(config)
	_create_drama(config)
	_snap_camera()
	DisplayServer.window_set_title("MAWLINGS — Godot Prototype")


# Purely visual camera kick; stacks but saturates so big hits stay readable.
func add_shake(amount: float) -> void:
	shake = minf(1.0, shake + amount)


## Etappe 25: pulls the camera back by DRAMA_ZOOM for `seconds` (real time).
func drama_zoom(seconds: float) -> void:
	drama_zoom_left = maxf(drama_zoom_left, seconds)


# Bog King eaten: short slow motion and a close camera push towards the kill.
func king_moment(location: Vector3) -> void:
	king_focus = location
	king_zoom_left = KING_ZOOM_SECONDS
	if slow_motion_enabled:
		king_slow_left = KING_SLOW_SECONDS
		Engine.time_scale = KING_SLOW_SCALE


# Etappe 09: a loss freezes the frame for a moment, proportional to the share of
# the swarm that fell (0..1): 1 of 3 is clearly felt, 1 of 200 barely. At most
# HITSTOP_MAX real seconds; off headless (tests, bot) and never while paused.
func hitstop(strength: float) -> void:
	if not slow_motion_enabled or world.paused or world.model.extinct:
		return
	var seconds := HITSTOP_MAX * sqrt(clampf(strength, 0.0, 1.0))
	if seconds < 0.012:
		return
	hitstop_left = maxf(hitstop_left, seconds)
	Engine.time_scale = HITSTOP_SCALE


# Counts the moment down in real seconds and always restores normal time.
func update_king_moment(real_delta: float) -> void:
	king_zoom_left = maxf(0.0, king_zoom_left - real_delta)
	drama_zoom_left = maxf(0.0, drama_zoom_left - real_delta)
	if hitstop_left > 0.0:
		hitstop_left -= real_delta
		if hitstop_left <= 0.0 or world.paused or world.model.extinct:
			hitstop_left = 0.0
			Engine.time_scale = KING_SLOW_SCALE if king_slow_left > 0.0 else 1.0
	if king_slow_left <= 0.0:
		return
	king_slow_left -= real_delta
	if king_slow_left <= 0.0 or world.paused or world.model.extinct:
		end_king_moment()


func end_king_moment() -> void:
	king_slow_left = 0.0
	hitstop_left = 0.0
	if Engine.time_scale != 1.0:
		Engine.time_scale = 1.0


func _exit_tree() -> void:
	end_king_moment()


func _process(delta: float) -> void:
	var real_delta := delta / maxf(0.01, Engine.time_scale)
	update_king_moment(real_delta)
	var keyboard := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var movement: Vector2 = controls.movement_vector if controls.movement_vector.length() > 0.05 else keyboard
	var active: bool = not world.paused and not world.model.extinct and not world.choosing()
	swarm.frozen = not active
	# Stage 10: during the migration swirl the swarm is drawn into the maw.
	var steering: bool = active and not world.migrating()
	swarm.set_controls(movement if steering else Vector2.ZERO, steering and (controls.rally_pressed or Input.is_key_pressed(KEY_SPACE)))
	# Etappe 22: new chunks one per frame (no hitch when a row appears).
	arena.chunk_budget = 1
	arena.sync(swarm.position)
	# Pull back for a large swarm and a nearby boss so both fit the portrait frame.
	var wanted := 1.0 + clampf(float(swarm.population - 25) / 225.0, 0.0, 1.0) * 0.12
	# Etappe 09: a handful of animals gets a slightly closer camera.
	wanted *= lerpf(0.8, 1.0, sqrt(clampf(float(swarm.population - 1) / 24.0, 0.0, 1.0)))
	if world.boss != null and world.boss.position.distance_to(swarm.position) < 16.0:
		wanted += 0.14
	# Stage 10: the Moosschlund is bigger; pull back further while it is close.
	var apex_close: bool = world.apex != null and world.apex.position.distance_to(swarm.position) < 22.0
	if apex_close:
		wanted += 0.3
	var look_at_point: Vector3 = swarm.position
	# ... and look a little towards it so its crown stays below the top HUD.
	if apex_close:
		look_at_point = swarm.position.lerp(Vector3(world.apex.position.x, 0.0, world.apex.position.z), 0.18)
	var zoom_rate := 1.5
	if drama_zoom_left > 0.0 and king_zoom_left <= 0.0:
		wanted *= DRAMA_ZOOM
		zoom_rate = 3.0
	if king_zoom_left > 0.0:
		# Push in fast, then let the normal framing ease back out.
		wanted *= KING_ZOOM
		zoom_rate = 6.0
		look_at_point = swarm.position.lerp(king_focus, 0.35)
	if world.migrating():
		wanted *= MIGRATION_ZOOM
		zoom_rate = 4.0
	zoom = lerpf(zoom, wanted, 1.0 - exp(-zoom_rate * real_delta))
	camera_base = camera_base.lerp(look_at_point + CAMERA_OFFSET * zoom, 1.0 - exp(-5.0 * real_delta))
	shake = maxf(0.0, shake - delta * 2.4)
	var jitter := Vector3(randf_range(-1.0, 1.0), randf_range(-0.4, 0.4), randf_range(-1.0, 1.0)) * shake * shake * 0.8
	camera.position = camera_base + jitter
	camera.look_at(look_at_point + jitter * 0.5, Vector3.UP)


# Reads and clears the RunConfig handed over by the menu ({} = prototype defaults).
func _take_pending_config() -> Dictionary:
	if not ResourceLoader.exists(SESSION_PATH):
		return {}
	var session: Script = load(SESSION_PATH)
	if session == null:
		return {}
	var pending: Variant = session.get("pending_config")
	session.set("pending_config", {})
	return (pending as Dictionary).duplicate(true) if pending is Dictionary else {}


# Etappe 25: speech bubbles and boss drama for every run (tests too; they only
# write HUD metadata). The menu switch "SPRÜCHE" (settings.speech) mutes the lines.
func _create_drama(config: Dictionary) -> void:
	if has_node("Drama") or not ResourceLoader.exists(DRAMA_PATH):
		return
	var drama: Node = load(DRAMA_PATH).new()
	drama.name = "Drama"
	add_child(drama)
	var settings: Variant = config.get("settings", {})
	drama.setup(world, controls, self, not (settings is Dictionary) or bool((settings as Dictionary).get("speech", true)))


# Einstieg: contextual first-time tips, only for runs started from the menu
# (the menu adds its profile path to the RunConfig). Tests and F5 stay without.
func _create_onboarding(config: Dictionary) -> void:
	var profile_path := String(config.get("profile_path", ""))
	if profile_path == "" or has_node("Onboarding") or not ResourceLoader.exists(ONBOARDING_PATH):
		return
	var onboarding: Node = load(ONBOARDING_PATH).new()
	onboarding.name = "Onboarding"
	add_child(onboarding)
	onboarding.setup(world, controls, swarm, profile_path)


# Etappe 07: picks the quality tier (settings "quality" = low/medium/high
# overrides the device heuristic in quality.gd) and applies its display-only
# switches. Never touches combat: the visible Mawling limit stays as it is,
# because melee and area hits count the visible animals.
func _apply_quality(settings: Variant) -> void:
	if settings is Dictionary and (settings as Dictionary).has("quality"):
		QUALITY.set_override(QUALITY.parse(String(settings["quality"])))
	quality_tier = QUALITY.current_tier()
	quality = QUALITY.settings(quality_tier)
	# Headless tests keep their own frame pacing (--fixed-fps, no FPS cap).
	if DisplayServer.get_name() != "headless":
		QUALITY.apply_viewport(get_viewport(), quality)
	# Ground shadows under the Mawlings (Swarm.shadows MultiMesh), if present.
	var shadows: Variant = swarm.get("shadows")
	if shadows is Node3D:
		(shadows as Node3D).visible = bool(quality.get("unit_shadows", true))


## Stage 10: sun colour and energy of a biome (biomes.gd "light"); HuntWorld
## calls it on reset and when the migration swirl covers the screen.
func apply_biome_light(id: String) -> void:
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		return
	var light: Dictionary = BIOMES.get_data(id).get("light", {})
	sun.light_color = light.get("color", Color(1, 1, 1))
	sun.light_energy = float(light.get("energy", 1.15))


## Display switch of the active quality tier, e.g. "decor_density" (read later by
## the arena) or "effect_density" (fx.gd, attack_forms.gd read it via quality.gd).
func quality_value(key: String, fallback: Variant = null) -> Variant:
	return quality.get(key, fallback)


# Menu settings travel inside the RunConfig; the menu already mutes the bus.
func _apply_settings(settings: Variant) -> void:
	var sfx := get_node_or_null("Sfx")
	if sfx != null and settings is Dictionary:
		sfx.set("vibration_enabled", bool(settings.get("vibration", true)))
		sfx.set("sfx_enabled", bool(settings.get("sound", true)))
	var music := get_node_or_null("Music")
	if music != null and settings is Dictionary:
		music.set_enabled(bool(settings.get("sound", true)))
		# Menu switch "MUSIK: KLASSIK V1": audio pack V1 loops instead of the adaptive stems.
		if music.has_method("set_style"):
			music.set_style("v1" if bool(settings.get("music_v1", false)) else "classic")


func _create_sfx() -> void:
	if has_node("Sfx") or not ResourceLoader.exists(SFX_PATH):
		return
	var script: Script = load(SFX_PATH)
	if script == null or not script.can_instantiate():
		return
	var sfx: Node = script.new()
	sfx.name = "Sfx"
	add_child(sfx)
	if sfx.has_method("play_ambience"):
		sfx.play_ambience()
	_create_music()


const MUSIC_PATH := "res://scripts/music.gd"


# Adaptive run music; HuntWorld drives intensity and stingers.
func _create_music() -> void:
	if has_node("Music") or not ResourceLoader.exists(MUSIC_PATH):
		return
	var music: Node = load(MUSIC_PATH).new()
	music.name = "Music"
	add_child(music)
	music.play_run()


# "NEUER RUN" skips the menu, so a menu-started run books its result into the
# profile here; the menu only sees Session.last_result of the run that leads
# back to it. Unconfigured runs (tests, editor F5) never touch the profile.
func _bank_result_for_new_run() -> void:
	if world.config.is_empty() or not world.model.extinct or not ResourceLoader.exists(SESSION_PATH) or not ResourceLoader.exists(PROFILE_PATH):
		return
	var session: Script = load(SESSION_PATH)
	var result: Variant = session.get("last_result")
	if not (result is Dictionary) or (result as Dictionary).is_empty():
		return
	var profile_script: Script = load(PROFILE_PATH)
	var profile: RefCounted = profile_script.call("load_or_create")
	if profile != null:
		profile.call("record_run", result)
		profile.call("save")
	session.set("last_result", {})


# Result screen "BRUTSTÄTTE": back to the menu, or a fresh run while no menu exists.
func _open_hub() -> void:
	end_king_moment()
	# Leaving from the pause menu forfeits the run; its rewards still count.
	if not world.model.extinct and world.has_method("_store_result"):
		world._store_result()
	if ResourceLoader.exists(MENU_SCENE):
		get_tree().change_scene_to_file(MENU_SCENE)
	else:
		_restart()


func _restart() -> void:
	_bank_result_for_new_run()
	end_king_moment()
	king_zoom_left = 0.0
	drama_zoom_left = 0.0
	world.reset_run()
	var music := get_node_or_null("Music")
	if music != null:
		music.play_run()
	shake = 0.0
	_snap_camera()


func _snap_camera() -> void:
	zoom = 1.0
	camera_base = swarm.position + CAMERA_OFFSET
	camera.position = camera_base
	camera.look_at(swarm.position, Vector3.UP)


func _register_keyboard_input() -> void:
	var bindings := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN]
	}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key_code in bindings[action]:
			var key := InputEventKey.new()
			key.physical_keycode = key_code
			InputMap.action_add_event(action, key)
