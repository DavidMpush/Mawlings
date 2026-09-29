extends Control

signal restart_requested
signal pause_requested
signal mutation_chosen(slot: int)
signal hub_requested
signal reroll_requested
signal skip_requested
signal banish_requested(slot: int)
## Stage 17d: the tribe ability (button above Rally, Q / Shift).
signal ability_requested

var evolution: RefCounted

var movement_vector := Vector2.ZERO
var rally_pressed := false
var movement_pointer := -1
var rally_pointer := -1
# Etappe 27 (S25 feedback): floating joystick. A touch in the right movement
# zone puts the joystick origin under the thumb; steering is the displacement
# from there. Released, the origin goes back to the rest position.
const MOVE_RADIUS := 66.0        # displacement for full speed (as before)
const MOVE_REST_TOUCH_R := 125.0 # old fixed touch area around the rest centre
const MOVE_FRAME_R := 125.0      # drawn joystick frame; the origin keeps it on screen
const MOVE_ZONE_TOP := 0.30      # zone starts below the top HUD (share of the height)
var _movement_origin := Vector2.INF
## Stage 17d: button state from abilities.gd hud_state() ({} = no button);
## ability_requests counts presses (HuntWorld may poll it instead of the signal).
var ability_state: Dictionary = {}
var ability_requests := 0
var ability_pressed_at := -100000
# Etappe 17d-Politur: 58 -> 68 px, so it holds its own next to Rally (100 px);
# the offset grows with it (gap to the Rally disc ~17 px, cooldown ring included).
const ABILITY_R := 68.0          # drawn button radius (brawl skin)
const ABILITY_TOUCH_R := 80.0    # touch radius (160 px across)
const ABILITY_OFFSET := Vector2(190.0, -68.0)  # from the Rally centre: up-right
var population := 25
var biomass_bank := 0.0
var corpse_count := 0
var kills := 0
var hunters := 0
var skitters := 0
var leapers := 0
var boss_health := 0.0
var boss_max_health := 0.0
var hint := ""
var elapsed := 0.0
var pressure := 1.0
var extinct := false
var paused := false
# Etappe 26: volume sliders in the pause panel (brawl). main.gd sets `volumes`
# from the RunConfig, applies each change to the buses (volume_changed) and
# saves them to the profile when the pause closes.
signal volume_changed(key: String, value: float)
const VOLUME_KEYS := ["volume_master", "volume_music", "volume_sfx"]
const VOLUME_NAMES := ["GESAMT", "MUSIK", "EFFEKTE"]
var volumes := {"volume_master": 1.0, "volume_music": 1.0, "volume_sfx": 1.0}
var _volume_drag := -1
var peak_population := 25
var consumed_biomass := 0.0
var hit_feedback := 0.0
var boss_pointer := Vector2.INF
var boss_vulnerable := false
var last_loss := 0
var alpha_cores := 0
var evolve_flash := 0.0
var evolve_name := ""
var run_stats: Dictionary = {}
# Minimap stage: the round minimap under the swarm panel (hud_minimap.gd) and
# the big map overlay it opens. Tapping the minimap opens the big map; tapping
# the minimap spot or the X again closes it. Steering and Rally stay active.
const MINIMAP_SIZE := 184.0
const MAP_TOGGLE_GAP_MS := 250
var minimap_enabled := false
var map_open := false
var _map_toggled_at := -100000


# Stage 15: the result/pause hit areas follow the skin.
const UiStyle := preload("res://scripts/ui/ui_style.gd")


# Stage 04 components; order matters: overlays and the mutation dimmer sit on top.
const COMPONENTS := [
	# Etappe 37: damage numbers under every other HUD element.
	["res://scripts/ui/hud_damage.gd", []],
	["res://scripts/ui/hud_top.gd", ["top", "badges"]],
	["res://scripts/ui/hud_minimap.gd", ["minimap"]],
	["res://scripts/ui/hud_controls.gd", ["controls"]],
	# Etappe 25: speech bubbles (left edge) and the boss-entrance vignette.
	["res://scripts/ui/hud_speech.gd", ["speech"]],
	["res://scripts/ui/mutation_screen.gd", ["mutations"]],
	["res://scripts/ui/hud_overlays.gd", ["result", "banner", "feedback", "pointer"]],
]


func _ready() -> void:
	set_process_input(true)
	for entry in COMPONENTS:
		if not ResourceLoader.exists(entry[0]):
			continue
		var component: Control = load(entry[0]).new()
		component.name = String(entry[0]).get_file().get_basename()
		add_child(component)
		for key in entry[1]:
			legacy[key] = false
		if component.name == "hud_minimap":
			minimap_enabled = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		clear_pointers()
		if not paused and not extinct and is_inside_tree():
			pause_requested.emit()


func clear_pointers() -> void:
	movement_vector = Vector2.ZERO
	rally_pressed = false
	movement_pointer = -1
	_movement_origin = Vector2.INF
	rally_pointer = -1
	map_open = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ESCAPE, KEY_P]:
			pause_requested.emit()
		elif not extinct and not paused and event.keycode in [KEY_1, KEY_2, KEY_3]:
			mutation_chosen.emit(event.keycode - KEY_1)
		elif not extinct and not paused and _choosing() and event.keycode == KEY_R:
			reroll_requested.emit()
		elif not extinct and not paused and _choosing() and event.keycode == KEY_X:
			skip_requested.emit()
		elif extinct and event.keycode in [KEY_R, KEY_ENTER]:
			restart_requested.emit()
		elif extinct and event.keycode in [KEY_H, KEY_M]:
			hub_requested.emit()
		elif extinct and event.keycode in [KEY_B, KEY_TAB]:
			_toggle_result_page()
		elif not extinct and not paused and not _choosing() and event.keycode in [KEY_M, KEY_TAB]:
			set_map_open(not map_open)
		elif not extinct and not paused and not _choosing() and event.keycode in [KEY_Q, KEY_SHIFT]:
			request_ability()
	if event is InputEventScreenTouch:
		if event.pressed:
			_press(event.index, event.position)
		else:
			_release(event.index)
	elif _volume_drag >= 0 and (event is InputEventScreenDrag or event is InputEventMouseMotion):
		set_volume_at(_volume_drag, event.position.x)
	elif event is InputEventScreenDrag and event.index == movement_pointer:
		_update_movement(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press(-2, event.position)
		else:
			_release(-2)
	elif event is InputEventMouseMotion and movement_pointer == -2:
		_update_movement(event.position)


func _press(pointer: int, location: Vector2) -> void:
	if extinct or paused:
		for k in VOLUME_KEYS.size():
			if _volume_rect(k).has_point(location):
				_volume_drag = k
				set_volume_at(k, location.x)
				return
		if _action_rect().has_point(location):
			_tap_sound()
			if extinct:
				restart_requested.emit()
			else:
				pause_requested.emit()
		elif (extinct or paused) and _hub_rect().has_point(location):
			_tap_sound()
			hub_requested.emit()
		elif extinct and _share_rect().has_point(location):
			_tap_sound()
			var overlays := get_node_or_null("hud_overlays")
			if overlays != null and overlays.has_method("share_result"):
				overlays.share_result()
		elif extinct and (_build_rect().has_point(location) or _build_panel_rect().has_point(location)):
			_tap_sound()
			_toggle_result_page()
		elif paused and _restart_rect().has_point(location):
			_tap_sound()
			restart_requested.emit()
		return
	if _pause_rect().has_point(location):
		_tap_sound()
		pause_requested.emit()
		return
	if _choosing():
		# Stage 15: the brawl cards live in mutation_screen.gd; ask it for the
		# hit areas it draws. The legacy rects below stay as they are (in the
		# organic/calm skins mutation_screen calls them itself).
		var ms := get_node_or_null("mutation_screen")
		# Stage 33: a Mutationskern choice (evolution.core_offers) wins like the
		# cocoon choice: pick only; HuntWorld.choose_mutation dispatches it.
		if _core_choosing() or _chest_choosing():
			var picks: Array = evolution.core_offers if _core_choosing() else evolution.chest_offers
			for slot in picks.size():
				var chest_area: Rect2 = ms.card_rect(slot) if ms != null else _mutation_rect(slot)
				if chest_area.has_point(location):
					_tap_sound()
					mutation_chosen.emit(slot)
					return
			return
		for slot in evolution.offers.size():
			var banish_area: Rect2 = ms.banish_rect(slot) if ms != null else _banish_rect(slot)
			# Etappe 31: overdrive cards cannot be banished (the button is hidden).
			if _count("banishes") > 0 and not bool(evolution.get("offer_overdrive")) and banish_area.has_point(location):
				_tap_sound()
				banish_requested.emit(slot)
				return
			var card_area: Rect2 = ms.card_rect(slot) if ms != null else _mutation_rect(slot)
			if card_area.has_point(location):
				_tap_sound()
				mutation_chosen.emit(slot)
				return
		var reroll_area: Rect2 = ms.reroll_rect() if ms != null else _reroll_rect()
		var skip_area: Rect2 = ms.skip_rect() if ms != null else _skip_rect()
		if _count("rerolls") > 0 and reroll_area.has_point(location):
			_tap_sound()
			reroll_requested.emit()
		elif _count("skips") > 0 and skip_area.has_point(location):
			_tap_sound()
			skip_requested.emit()
		return
	if _map_tap(location):
		_tap_sound()
		return
	if not ability_state.is_empty() and location.distance_to(_ability_center()) < ABILITY_TOUCH_R:
		request_ability()
		return
	if movement_pointer == -1 and _in_movement_zone(location):
		movement_pointer = pointer
		_movement_origin = _clamp_movement_origin(location)
		_update_movement(location)
	elif rally_pointer == -1 and location.distance_to(_rally_center()) < 125.0:
		rally_pointer = pointer
		rally_pressed = true
	

# Audio pack V1 "ui" for button taps (pause, cards, map); never for the joystick
# or the Rally pad. Sfx lives under Main (HUD/Controls -> Main/Sfx).
func _tap_sound() -> void:
	var node: Node = get_parent()
	while node != null:
		var sfx := node.get_node_or_null("Sfx")
		if sfx != null and sfx.has_method("play"):
			sfx.play("ui")
			return
		node = node.get_parent()


func _release(pointer: int) -> void:
	_volume_drag = -1
	if pointer == movement_pointer:
		movement_pointer = -1
		movement_vector = Vector2.ZERO
		_movement_origin = Vector2.INF
	if pointer == rally_pointer:
		rally_pointer = -1
		rally_pressed = false


func _update_movement(location: Vector2) -> void:
	movement_vector = ((location - _movement_center()) / MOVE_RADIUS).limit_length(1.0)


## Joystick origin: under the thumb while a movement pointer is held, else the
## rest position (hud_controls draws the joystick here).
func _movement_center() -> Vector2:
	if movement_active():
		return _movement_origin
	return movement_rest_center()


## Idle joystick position (bottom right), also the old fixed touch centre.
func movement_rest_center() -> Vector2:
	return Vector2(size.x - 125.0, size.y - 145.0)


func movement_active() -> bool:
	return movement_pointer != -1 and _movement_origin != Vector2.INF


## Right movement zone: right half below the top HUD (pause, pills, chips and
## boss bar end well above 30 % of the height). Pause, minimap, ability and
## cards are handled in _press() before this; the open big map keeps its
## panel. The old circle around the rest centre always counts.
func _in_movement_zone(location: Vector2) -> bool:
	if location.distance_to(movement_rest_center()) < MOVE_REST_TOUCH_R:
		return true
	if location.x < size.x * 0.5 or location.y < size.y * MOVE_ZONE_TOP:
		return false
	if map_open and _bigmap_rect().has_point(location):
		return false
	return Rect2(Vector2.ZERO, size).has_point(location)


## Keeps the drawn joystick frame fully on screen.
func _clamp_movement_origin(location: Vector2) -> Vector2:
	var r := minf(MOVE_FRAME_R, minf(size.x, size.y) * 0.5)
	return Vector2(clampf(location.x, r, size.x - r), clampf(location.y, r, size.y - r))


func _rally_center() -> Vector2:
	return Vector2(125.0, size.y - 145.0)


## Stage 17d: the ability button sits up-right of Rally (left thumb reaches both).
func _ability_center() -> Vector2:
	return _rally_center() + ABILITY_OFFSET


func ability_rect() -> Rect2:
	return Rect2(_ability_center() - Vector2.ONE * ABILITY_TOUCH_R, Vector2.ONE * ABILITY_TOUCH_R * 2.0)


## Counts a press; emits ability_requested (a cooling button still answers with
## a short shake in hud_controls, the ability itself refuses).
func request_ability() -> void:
	if ability_state.is_empty():
		return
	ability_requests += 1
	ability_pressed_at = Time.get_ticks_msec()
	ability_requested.emit()


# Minimap (round, top left below the swarm panel) and big map overlay.
func _minimap_rect() -> Rect2:
	return Rect2(Vector2(16, 130), Vector2(MINIMAP_SIZE, MINIMAP_SIZE))

func _bigmap_rect() -> Rect2:
	return Rect2(Vector2(20, 130), Vector2(size.x - 40, maxf(400.0, size.y - 130 - 370)))

func _map_close_rect() -> Rect2:
	var panel := _bigmap_rect()
	return Rect2(Vector2(panel.end.x - 96, panel.position.y + 12), Vector2(84, 84))

## Opens or closes the big map (touch debounce: an emulated mouse click of the
## same tap must not toggle it straight back).
func set_map_open(value: bool) -> void:
	if not minimap_enabled or value == map_open:
		return
	var now := Time.get_ticks_msec()
	if now - _map_toggled_at < MAP_TOGGLE_GAP_MS:
		return
	_map_toggled_at = now
	map_open = value

# Taps on the minimap / big map; true when the tap was used.
func _map_tap(location: Vector2) -> bool:
	if not minimap_enabled:
		return false
	if map_open:
		if _map_close_rect().has_point(location) or _minimap_rect().has_point(location):
			set_map_open(false)
			return true
		return false
	if _minimap_rect().grow(6).has_point(location):
		set_map_open(true)
		return true
	return false

# 96 x 96 touch target (TOUCH_MIN) around the same centre as before, so the
# round pause button and the DNA pill beside it keep their places.
func _pause_rect() -> Rect2:
	return Rect2(Vector2(size.x - 105, 20), Vector2(96, 96))

# Stage 15 (brawl skin): result and pause buttons of hud_overlays.gd. The
# layout is the 900 x 1600 base, centred vertically on taller screens.
#   result: NOCHMAL (action, full width), below BRUTSTÄTTE + BUILD + TEILEN
#   pause:  WEITER (action, full width), below NEUSTART + BRUTSTÄTTE
func _overlay_top() -> float:
	return (size.y - 1600.0) * 0.5

func _action_rect() -> Rect2:
	if (extinct or paused) and UiStyle.is_brawl():
		if extinct:
			return Rect2(Vector2(size.x * 0.5 - 390, _overlay_top() + 1252), Vector2(780, 132))
		return Rect2(Vector2(size.x * 0.5 - 340, _overlay_top() + 770), Vector2(680, 130))
	if extinct or paused:
		return Rect2(Vector2(size.x * 0.5 - 340, size.y * 0.5 + 235), Vector2(330, 88))
	return Rect2(Vector2(size.x * 0.5 - 220, size.y * 0.5 + 235), Vector2(440, 88))

func _hub_rect() -> Rect2:
	if (extinct or paused) and UiStyle.is_brawl():
		if extinct:
			return Rect2(Vector2(size.x * 0.5 - 390, _overlay_top() + 1404), Vector2(340, 104))
		return Rect2(Vector2(size.x * 0.5 + 10, _overlay_top() + 930), Vector2(330, 104))
	return Rect2(Vector2(size.x * 0.5 + 10, size.y * 0.5 + 235), Vector2(330, 88))

# Stage 31 C (brawl result): toggles the page "DEIN BUILD" (damage per source,
# pick timeline) and back; between BRUTSTÄTTE and TEILEN.
func _build_rect() -> Rect2:
	if extinct and UiStyle.is_brawl():
		return Rect2(Vector2(size.x * 0.5 - 30, _overlay_top() + 1404), Vector2(200, 104))
	return Rect2()

# Stage 31 C: on the overview page the BUILD panel itself opens the build page.
func _build_panel_rect() -> Rect2:
	var overlays := get_node_or_null("hud_overlays")
	if extinct and UiStyle.is_brawl() and overlays != null and overlays.has_method("toggle_result_page") and int(overlays.result_page) == 0:
		return Rect2(Vector2(size.x * 0.5 - 390, _overlay_top() + 578), Vector2(780, 140))
	return Rect2()

func _toggle_result_page() -> void:
	var overlays := get_node_or_null("hud_overlays")
	if overlays != null and overlays.has_method("toggle_result_page"):
		overlays.toggle_result_page()

# Result only (brawl): renders the share card (hud_overlays.share_result()).
func _share_rect() -> Rect2:
	if extinct and UiStyle.is_brawl():
		return Rect2(Vector2(size.x * 0.5 + 190, _overlay_top() + 1404), Vector2(200, 104))
	return Rect2()

# Etappe 26: three compact volume sliders under the pause buttons (brawl only).
func _volume_rect(k: int) -> Rect2:
	if not paused or extinct or not UiStyle.is_brawl():
		return Rect2()
	var w := (680.0 - 2.0 * 16.0) / 3.0
	return Rect2(Vector2(size.x * 0.5 - 340 + k * (w + 16.0), _overlay_top() + 1062), Vector2(w, 110))


func _volume_track(k: int) -> Rect2:
	var r := _volume_rect(k)
	return Rect2(r.position.x + 20.0, r.position.y + 70.0, r.size.x - 40.0, 20.0)


## Sets slider k from a finger x (5 % steps) and reports a change.
func set_volume_at(k: int, x: float) -> void:
	var track := _volume_track(k)
	if track.size.x <= 0.0:
		return
	var value := clampf(roundf(clampf((x - track.position.x) / track.size.x, 0.0, 1.0) * 20.0) / 20.0, 0.0, 1.0)
	var key: String = VOLUME_KEYS[k]
	if is_equal_approx(float(volumes.get(key, 1.0)), value):
		return
	volumes[key] = value
	volume_changed.emit(key, value)


# Pause only (brawl): restart the run (a paused run is given up, like BRUTSTÄTTE).
func _restart_rect() -> Rect2:
	if paused and not extinct and UiStyle.is_brawl():
		return Rect2(Vector2(size.x * 0.5 - 340, _overlay_top() + 930), Vector2(330, 104))
	return Rect2()

func _banish_rect(slot: int) -> Rect2:
	var card := _mutation_rect(slot)
	return Rect2(Vector2(card.end.x - 262, card.position.y + 46), Vector2(182, 46))

# Reroll and skip share one row below the cards; a lone button is centred.
func _reroll_rect() -> Rect2:
	var both := _count("skips") > 0
	return Rect2(Vector2(size.x * 0.5 - (322 if both else 160), size.y * 0.5 + 440), Vector2(300 if both else 320, 72))

func _skip_rect() -> Rect2:
	var both := _count("rerolls") > 0
	return Rect2(Vector2(size.x * 0.5 + (22 if both else -160), size.y * 0.5 + 440), Vector2(300 if both else 320, 72))

func _choosing() -> bool:
	return evolution != null and (not evolution.offers.is_empty() or _chest_choosing() or _core_choosing())

# Stage 33: an open Mutationskern choice (evolution.core_offers); pick only.
func _core_choosing() -> bool:
	return evolution != null and "core_offers" in evolution and not evolution.core_offers.is_empty()

# Etappe 17: an open boss-cocoon choice (evolution.chest_offers) uses the same
# cards; only picking is allowed there (no banish/reroll/skip).
func _chest_choosing() -> bool:
	return evolution != null and "chest_offers" in evolution and not evolution.chest_offers.is_empty()

# Reroll/banish/skip counters; 0 when the evolution has none.
func _count(counter: String) -> int:
	if evolution == null:
		return 0
	var value: Variant = evolution.get(counter)
	return int(value) if value != null else 0

func _mutation_rect(slot: int) -> Rect2:
	# One or two offers stay vertically centred instead of hanging at the top.
	var count := 3 if evolution == null or evolution.offers.is_empty() else mini(3, evolution.offers.size())
	var top := size.y * 0.5 - 322 + float(3 - count) * 123.0
	return Rect2(Vector2(36, top + slot * 246), Vector2(size.x - 72, 226))

# ---------------------------------------------------------------- drawing

# Stage 04-15: every block is drawn by a component under scripts/ui/ (see
# COMPONENTS); this node only handles input. `legacy` stays as the switch list
# the components turn off (tests read it); the old fallback drawing is gone
# (Etappe 16 polish), so a missing component simply draws nothing.
var legacy := {"top": true, "badges": true, "pointer": true, "feedback": true, "result": true, "mutations": true, "controls": true, "banner": true}


# Attack-form accent colour (hud_top medallions and build rows use it).
func _mutation_color(id: String) -> Color:
	match id:
		"rudelbiss":
			return Color("ff9a4a")
		"sporenwolke":
			return Color("c4dc5a")
		"saeurespucker":
			return Color("7eec5c")
		"stachelruecken":
			return Color("f0d28c")
		"aetzflut":
			return Color("a6ff4f")
		"meute":
			return Color("ff6f5a")
	if id in ["jaws", "pack"]:
		return Color("f58a4d")
	if id in ["brood", "glutton"]:
		return Color("68d8c7")
	if id == "scatter":
		return Color("b798ec")
	return Color("b8d879")

# ---------------------------------------------------------------- progression

func _slot_text() -> String:
	if evolution == null or not evolution.has_method("slots_used"):
		return "WELT PAUSIERT"
	# Build slots (user decision 28.09.2026): 4 weapons · 6 stats · 6 relics.
	return "Waffen %d/%d · Werte %d/%d · Relikte %d/%d" % [evolution.slots_used("attack"), evolution.slot_limit("attack"), evolution.slots_used("trait"), evolution.slot_limit("trait"), evolution.slots_used("relic"), evolution.slot_limit("relic")]
