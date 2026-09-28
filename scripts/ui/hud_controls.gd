extends Control

# Stage 04 component "CONTROLS": Rally button (left), movement joystick (right)
# and the hint banner above them. Replaces `legacy.controls` in touch_controls.gd.
# Input stays in the parent; this node only draws at the parent's centres
# (_rally_center(), _movement_center()) so the touch areas are unchanged.

#
# Stage 07 (performance): drawn through UiLayer children in the original order.
# Static parts (claws, frame ring, core, heads, labels, joystick at rest) are
# baked; the Rally breathing only animates the scale/modulate of three small
# layers, the pulling rings repaint only while Rally is held.

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const UiLayer := preload("res://scripts/ui/ui_layer.gd")
const ICONS_PATH := "res://scripts/ui/ui_icons.gd"
const FRAMES_PATH := "res://scripts/ui/ui_frames.gd"
const UiFrames := preload("res://scripts/ui/ui_frames.gd")
const UiIcons := preload("res://scripts/ui/ui_icons.gd")
const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")
const DIR := "res://assets/ui/controls/"
# Calm skin (V2 kit): rally_button_base / joystick_base have their outer ring at
# r 89 of 192 units, the Rally core at r 76, joystick_knob r 38 of 84 units.
const KIT_RALLY_K := (FRAME_R - 2.0) / 89.0
const KIT_JOY_K := (JOY_R + 16.0) / 89.0

# Visual radii in base-viewport pixels. The touch radius in the parent is 125.
const FRAME_R := 126.0
const RALLY_R := 106.0
const JOY_R := 104.0
const KNOB_R := 50.0
const KNOB_TRAVEL := 52.0
const BANNER_GAP := 52.0  # space between banner and the top claws

var _icons: Script = null
var _icons_checked := false
var _frames: Script = null
var _frames_checked := false

# Einstieg (stage 06): one friendly tip panel above the hint banner. The
# onboarding node writes `tutorial_tip` / `tutorial_icon` on the HUD (as a
# variable when it exists, else as metadata); this component only draws it on
# a child layer so the whole panel can fade through `modulate`.
const TIP_FADE_SPEED := 3.2
const TIP_GAP := 22.0       # space between tip panel and the hint banner
const TIP_ICONS := {
	"move": "mawling_head_color", "rally": "pack", "warning": "skull", "boss": "bog_king",
	"prey": "nibbler", "corpse": "biomass", "alpha": "alpha_core", "mutation": "dna", "nest": "brood",
	"ability": "mawling_head_color",
	# Etappe 24: tips for the systems of stages 17-20.
	"leader_low": "regeneration", "boss_cocoon": "cocoon", "cocoon": "cocoon", "amber": "crown_tooth",
	"powerup": "pu_rausch", "shrine": "shrine", "xp": "evo_badge", "explore": "g_map",
	"quicksand": "speed", "sandstorm": "haste",
}
var _tip_layer: Control = null
var _tip_text := ""
var _tip_icon := ""
var _tip_alpha := 0.0

var _cv: CanvasItem = self
var _paint := ""
var _layers: Dictionary = {}
const PARTS := [
	# name, cached
	# Etappe 22: the rally glow (a fan of ~90 polygons) is cached too; its
	# breathing is the layer's scale/modulate, not a repaint.
	# Etappe 22b: the warning hint's pulsing halo is its own live layer, the
	# banner itself stays baked.
	["hint_glow", false], ["hint", true], ["rally_glow", true], ["rally_base", true], ["rally_rim", false],
	["rally_core", false], ["rally_heads", true], ["rally_rings", false], ["rally_text", true],
	# Etappe 22: joystick base (static, baked) under the moving part.
	["joy_base", true], ["joy", true], ["ability", true],
]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for spec in PARTS:
		var part: String = spec[0]
		_layers[part] = UiLayer.make(self, part.capitalize().replace(" ", ""), _painter(part), spec[1])
	_tip_layer = Control.new()
	_tip_layer.name = "TutorialTip"
	_tip_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_layer.visible = false
	add_child(_tip_layer)
	_tip_layer.draw.connect(_draw_tip)


func _process(delta: float) -> void:
	var hud := _hud()
	if hud != null and size != hud.size:
		position = Vector2.ZERO
		size = hud.size
	_update_tip(hud, delta)
	_refresh_layers(hud)


func _painter(part: String) -> Callable:
	return func(canvas: CanvasItem) -> void:
		var hud := _hud()
		if not _visible_now(hud):
			return
		_cv = canvas
		_paint = part
		var rally_c: Vector2 = hud._rally_center()
		var move_c: Vector2 = hud._movement_center()
		if part == "hint" or part == "hint_glow":
			if hud.hint != "":
				_draw_hint(hud.hint, _banner_top(hud))
		elif part == "joy":
			_draw_joystick(move_c, hud.movement_vector)
		elif part == "joy_base":
			if UiStyle.is_brawl():
				_draw_joystick_brawl(move_c, hud.movement_vector)
		elif part == "ability":
			if "ability_state" in hud and not (hud.ability_state as Dictionary).is_empty():
				_draw_ability(hud._ability_center(), hud.ability_state, _ability_pressed(hud))
		else:
			_draw_rally(rally_c, hud.rally_pressed)
		_paint = ""
		_cv = self


## Perf bench (Etappe 22): layer names to keep hidden for A/B measurements.
var debug_hidden: PackedStringArray = []


func _refresh_layers(hud: Control) -> void:
	var shown := _visible_now(hud)
	for part in _layers:
		_layers[part].visible = shown and not debug_hidden.has(part)
	if not shown:
		return
	var rally_c: Vector2 = hud._rally_center()
	var move_c: Vector2 = hud._movement_center()
	var pressed: bool = hud.rally_pressed
	var hint: String = hud.hint
	var warn := hint != "" and _is_warning(hint)
	var hint_top := _banner_top(hud)
	_region("hint", Rect2(0, hint_top - 40, size.x, 150))
	_layers.hint.visible = hint != "" and not debug_hidden.has("hint")
	var brawl := UiStyle.is_brawl()
	_layers.hint.refresh([hint, int(_t() * 30.0) if warn and not brawl else 0, size, hint_top])
	_layers.hint_glow.visible = brawl and warn and not debug_hidden.has("hint_glow")
	if _layers.hint_glow.visible:
		_layers.hint_glow.refresh([hint, int(_t() * 30.0), size, hint_top])
	var rally_area := Rect2(rally_c - Vector2.ONE * (FRAME_R + 90.0), Vector2.ONE * (FRAME_R + 90.0) * 2.0)
	var charge := _rally_charge(hud)
	for part in ["rally_base", "rally_heads", "rally_text"]:
		_region(part, rally_area)
		_layers[part].refresh([pressed, rally_c, charge, _rally_count(hud)])
	_region("joy", Rect2(move_c - Vector2.ONE * (FRAME_R + 90.0), Vector2.ONE * (FRAME_R + 90.0) * 2.0))
	_layers.joy.refresh([hud.movement_vector, move_c])
	_region("joy_base", Rect2(move_c - Vector2.ONE * (FRAME_R + 90.0), Vector2.ONE * (FRAME_R + 90.0) * 2.0))
	_layers.joy_base.refresh([move_c, UiStyle.is_brawl()])
	# Stage 17d: ability button (repaints only when its state changes).
	var ability: Dictionary = hud.ability_state if "ability_state" in hud else {}
	_layers.ability.visible = not ability.is_empty() and not debug_hidden.has("ability")
	if not ability.is_empty():
		var ac: Vector2 = hud._ability_center()
		_region("ability", Rect2(ac - Vector2.ONE * 130.0, Vector2.ONE * 260.0))
		_layers.ability.refresh([ac, String(ability.get("id", "")), bool(ability.get("ready", false)), roundf(float(ability.get("share", 0.0)) * 60.0), int(ability.get("seconds", 0)), roundf(float(ability.get("active", 0.0)) * 30.0), _ability_pressed(hud)])
	# Breathing without repainting: glow radius/alpha, rim and core light.
	var breathe := _pulse(2.4)
	var glow: Control = _layers.rally_glow
	_region("rally_glow", rally_area)
	glow.refresh([pressed, rally_c])
	glow.pivot_offset = rally_c
	glow.scale = Vector2.ONE if pressed else Vector2.ONE * (FRAME_R + 26.0 + 6.0 * breathe) / (FRAME_R + 26.0)
	glow.modulate = Color.WHITE if pressed else Color(1, 1, 1, 0.5 + 0.22 * breathe)
	_layers.rally_rim.refresh([pressed, rally_c])
	_layers.rally_rim.modulate = Color(1, 1, 1, 0.35 + 0.45 * breathe)
	_layers.rally_core.refresh([pressed, rally_c])
	_layers.rally_core.modulate = Color.WHITE if pressed else Color(1, 1, 1, 0.18 + 0.14 * breathe)
	if UiStyle.is_brawl():
		# Held: the light ring beats quickly; at rest nothing moves (calm HUD).
		glow.scale = Vector2.ONE
		glow.modulate = Color(1, 1, 1, 0.72 + 0.28 * _pulse(7.0)) if pressed else Color.WHITE
	var rings: Control = _layers.rally_rings
	rings.visible = pressed
	if pressed:
		rings.refresh(null, true)


func _region(part: String, rect: Rect2) -> void:
	var layer: Control = _layers[part]
	var snapped := Rect2(rect.position.floor(), rect.size.ceil())
	if layer.region != snapped:
		layer.region = snapped
		layer.invalidate()


func _hud() -> Control:
	return get_parent() as Control


func _visible_now(hud: Control) -> bool:
	if hud == null or hud.extinct or hud.paused:
		return false
	return not (hud.has_method("_choosing") and hud._choosing())


# ---------------------------------------------------------------- helpers

func _t() -> float:
	return Time.get_ticks_msec() * 0.001


func _pulse(speed: float) -> float:
	return 0.5 + 0.5 * sin(_t() * speed)


func _tex_at(name: String, center: Vector2, tex_size: Vector2, tint: Color = Color.WHITE, angle: float = 0.0) -> bool:
	var texture := UiStyle.tex(DIR + name)
	if texture == null:
		return false
	_cv.draw_set_transform(center, angle, Vector2.ONE)
	_cv.draw_texture_rect(texture, Rect2(-tex_size * 0.5, tex_size), false, tint)
	_cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


func _glow(center: Vector2, radius: float, color: Color) -> void:
	if not _tex_at("glow.svg", center, Vector2.ONE * radius * 2.0, color):
		for i in 4:
			_cv.draw_circle(center, radius * (1.0 - i * 0.2), Color(color, color.a * 0.25))


# Bone claws gripping the frame like talons: each one sits on the rim and
# curls along it (tangential), as in the active-HUD concept. `side` mirrors
# the set for the right-hand joystick.
const CLAWS := [
	# [angle from up in degrees, length, lean in degrees, hooks inward]
	# Top cluster grips over the rim toward the button, bottom pair hangs out.
	[-64.0, 58.0, 52.0, true], [-44.0, 66.0, 50.0, true], [-24.0, 60.0, 48.0, true], [-6.0, 50.0, 46.0, true],
	[142.0, 62.0, -40.0, false], [164.0, 70.0, -34.0, false],
]


func _claws(c: Vector2, side: float, alpha: float) -> void:
	var texture := UiStyle.tex(DIR + "claw.svg")
	if texture == null:
		return
	for claw in CLAWS:
		var deg: float = float(claw[0]) * side
		var length: float = claw[1]
		var lean: float = float(claw[2]) * side
		var inward: bool = claw[3]
		var dir := Vector2.UP.rotated(deg_to_rad(deg))
		var base: Vector2
		var angle: float
		if inward:
			# Rooted outside the frame, the tip hooks back over the rim.
			base = c + dir * (FRAME_R + 16.0)
			angle = deg_to_rad(deg + 180.0 + lean)
		else:
			base = c + dir * (FRAME_R - 14.0)
			angle = deg_to_rad(deg + lean)
		# Texture: base at the bottom, tip at the top curling toward +x.
		var flip := side if inward else -side
		_cv.draw_set_transform(base, angle, Vector2(flip, 1.0))
		_cv.draw_texture_rect(texture, Rect2(Vector2(-length * 0.24, -length), Vector2(length * 0.5, length)), false, Color(UiStyle.color("bone"), alpha))
		_cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _frame_ring(c: Vector2, alpha: float, spin: float) -> void:
	if not _tex_at("frame_ring.svg", c, Vector2.ONE * FRAME_R * 2.0, Color(1, 1, 1, alpha), spin):
		_cv.draw_circle(c, FRAME_R, Color(UiStyle.color("panel"), alpha))
		_cv.draw_arc(c, FRAME_R - 2.0, 0.0, TAU, 64, Color(UiStyle.color("panel_edge"), alpha), 3.0, true)


# ---------------------------------------------------------------- rally

# Parts (in drawing order); the breathing values (glow radius and alpha, rim
# and core light) are applied by _refresh_layers() through scale/modulate, so
# the parts below draw them at rest size with full alpha.
func _draw_rally(c: Vector2, pressed: bool) -> void:
	if UiStyle.is_brawl():
		_draw_rally_brawl(c, pressed)
		return
	if UiStyle.is_calm():
		_draw_rally_calm(c, pressed)
		return
	var core_r := RALLY_R - (5.0 if pressed else 0.0)
	match _paint:
		"rally_glow":
			if pressed:
				_glow(c, FRAME_R + 40.0, Color(UiStyle.color("ember_glow"), 0.7))
			else:
				_glow(c, FRAME_R + 26.0, Color(UiStyle.color("ember"), 1.0))
		"rally_base":
			_frame_ring(c, 0.96, 0.0)
			_claws(c, 1.0, 1.0)
			# Core disc with its ember ring; the whole disc sinks a little when held.
			if not _tex_at("rally_core.svg", c, Vector2.ONE * core_r * 2.0):
				_cv.draw_circle(c, core_r, UiStyle.tone(Color("5e200c")))
				_cv.draw_arc(c, core_r - 5.0, 0.0, TAU, 64, UiStyle.color("ember"), 8.0, true)
		"rally_rim":
			# Warm rim light breathes at rest (alpha 0.35 + 0.45 * breathe).
			_cv.draw_arc(c, core_r - 5.0, 0.0, TAU, 72, Color(UiStyle.color("ember_glow"), 1.0), 4.0, true)
		"rally_core":
			# Held, the core flares up; at rest a soft glow breathes (0.18 + 0.14 * breathe).
			if pressed:
				_cv.draw_circle(c, core_r - 9.0, Color(UiStyle.color("ember"), 0.92))
				_glow(c + Vector2(0, -8), core_r * 0.95, Color(UiStyle.color("ember_glow"), 1.0))
				_glow(c + Vector2(0, -12), 52.0, Color(UiStyle.color("text"), 0.95))
			else:
				_glow(c + Vector2(0, -14), 58.0, Color(UiStyle.color("ember"), 1.0))
		"rally_heads":
			var heads_size := Vector2(180, 155)
			# Held: the heads turn into dark silhouettes against the flaring core.
			var heads_tint := Color(0.42, 0.16, 0.07) if pressed else Color.WHITE
			if not _tex_at("rally_heads.svg", c + Vector2(-6, -30), heads_size, heads_tint):
				_cv.draw_circle(c + Vector2(0, -24), 34, UiStyle.color("ember"))
		"rally_text":
			_draw_rally_text(c, pressed)
	# Held: bright rings contract from the rim toward the heads (the swarm pulls in).
	if pressed and _paint == "rally_rings":
		for i in 3:
			var phase := fposmod(_t() * 1.4 + i / 3.0, 1.0)
			var r := lerpf(core_r + 18.0, core_r - 34.0, phase)
			var fade := sin(phase * PI)
			_cv.draw_arc(c, r, 0.0, TAU, 72, Color(UiStyle.color("text"), 0.9 * fade), lerpf(9.0, 3.0, phase), true)


# Calm skin: V2 rally_button_base with the kit's Rally glyph. At rest the
# amber core is dark and only its rim breathes; held, the core fills with
# orange, glyph and label turn dark and cream rings pull inward.
func _draw_rally_calm(c: Vector2, pressed: bool) -> void:
	var k := KIT_RALLY_K * (0.96 if pressed else 1.0)
	var core_r := 76.0 * k
	var hot := UiStyle.color("ember")
	var light := UiStyle.color("ember_glow")
	match _paint:
		"rally_glow":
			if pressed:
				UiFrames.halo(_cv, c, FRAME_R + 34.0, Color(light, 0.9))
		"rally_base":
			var side := 192.0 * k
			if not UiFrames.kit_at(_cv, "rally_button_base", c, Vector2(side, side)):
				_cv.draw_circle(c, 89.0 * k, Color(UiStyle.CALM_BG, 0.88))
				_cv.draw_circle(c, core_r, UiStyle.tone(Color("2a1b16")))
				_cv.draw_arc(c, core_r, 0.0, TAU, 64, UiStyle.tone(Color("d69a55")), 5.0, true)
		"rally_rim":
			_cv.draw_arc(c, core_r - 1.0, 0.0, TAU, 72, light, 3.0, true)
		"rally_core":
			if pressed:
				_cv.draw_circle(c, core_r - 2.5, Color(hot, 0.95))
				_cv.draw_arc(c, core_r - 12.0, 0.0, TAU, 72, Color(UiStyle.CALM_CREAM, 0.55), 2.0, true)
		"rally_heads":
			var glyph := Rect2(c + Vector2(-34.0, -66.0), Vector2(68.0, 68.0))
			UiIcons.draw(_cv, "v2_rally", glyph, Color(0.14, 0.14, 0.14) if pressed else Color.WHITE)
		"rally_text":
			var ink := UiStyle.tone(Color("1b100b")) if pressed else light
			UiStyle.text(_cv, "RALLY", c + Vector2(0, 32), UiStyle.SIZE_HEAD, ink, true, 0 if pressed else 5)
			var sub := "AKTIV" if pressed else "HALTEN"
			UiStyle.text(_cv, sub, c + Vector2(0, 60), UiStyle.SIZE_LABEL, UiStyle.tone(Color("2a160c")) if pressed else UiStyle.color("text_dim"), true, 0 if pressed else 4)
	if pressed and _paint == "rally_rings":
		for i in 3:
			var phase := fposmod(_t() * 1.4 + i / 3.0, 1.0)
			var r := lerpf(89.0 * k, core_r - 30.0, phase)
			var fade := sin(phase * PI)
			_cv.draw_arc(c, r, 0.0, TAU, 72, Color(UiStyle.CALM_CREAM, 0.85 * fade), lerpf(6.0, 2.0, phase), true)


func _draw_rally_text(c: Vector2, pressed: bool) -> void:
	UiStyle.text(_cv, "RALLY", c + Vector2(0, 58), UiStyle.SIZE_HEAD, UiStyle.color("text"), true, 7)
	var sub := "AKTIV" if pressed else "HALTEN"
	var sub_color: Color = UiStyle.color("ember_glow").lerp(Color.WHITE, 0.55) if pressed else UiStyle.color("text_dim").lerp(UiStyle.color("ember_glow"), 0.35)
	UiStyle.text(_cv, sub, c + Vector2(0, 84), UiStyle.SIZE_LABEL, sub_color, true, 5)


# ---------------------------------------------------------------- joystick

func _draw_joystick(c: Vector2, move: Vector2) -> void:
	if UiStyle.is_brawl():
		_draw_joystick_brawl(c, move)
		return
	if UiStyle.is_calm():
		_draw_joystick_calm(c, move)
		return
	var strength := clampf(move.length(), 0.0, 1.0)
	# Bark crescent on the outer (screen-edge) side carries the claws.
	_cv.draw_arc(c, JOY_R + 10.0, -PI * 0.62, PI * 0.62, 48, Color(UiStyle.color("panel"), 0.92), 20.0, true)
	_cv.draw_arc(c, JOY_R + 19.0, -PI * 0.6, PI * 0.6, 48, Color(UiStyle.color("panel_edge"), 0.8), 2.5, true)
	_cv.draw_arc(c, JOY_R + 3.0, 0.0, TAU, 72, Color(UiStyle.color("outline"), 0.55), 5.0, true)
	_claws(c, -1.0, 0.95)
	if not _tex_at("joy_base.svg", c, Vector2.ONE * JOY_R * 2.0):
		_cv.draw_circle(c, JOY_R, UiStyle.tone(Color("0c1d1a88")))
		_cv.draw_arc(c, JOY_R - 3.0, 0.0, TAU, 64, Color(1, 1, 1, 0.42), 3.0, true)
	# Direction wedge glow under the knob.
	if strength > 0.05:
		_glow(c + move.normalized() * 58.0, 64.0, Color(UiStyle.color("ember_glow"), 0.3 * strength))
	for i in 4:
		var dir := Vector2.RIGHT.rotated(i * PI * 0.5)
		var lit := clampf(move.dot(dir), 0.0, 1.0)
		var tip := c + dir * 80.0
		if lit > 0.15:
			_glow(tip, 30.0 + 10.0 * lit, Color(UiStyle.color("ember_glow"), 0.55 * lit))
		var tint := Color(1, 1, 1, 0.42).lerp(Color(UiStyle.color("ember_glow"), 1.0), lit)
		if not _tex_at("arrow.svg", tip, Vector2(38, 38) * (1.0 + 0.3 * lit), tint, dir.angle()):
			var side := Vector2(-dir.y, dir.x)
			_cv.draw_colored_polygon(PackedVector2Array([tip + dir * 8, tip - dir * 8 + side * 11, tip - dir * 8 - side * 11]), tint)
	var knob := c + move.limit_length(1.0) * KNOB_TRAVEL
	if not _tex_at("joy_knob.svg", knob + Vector2(0, 4), Vector2.ONE * KNOB_R * 2.46):
		_cv.draw_circle(knob, KNOB_R, UiStyle.tone(Color("d8e6e0f0")))


# Calm skin: V2 joystick_base (translucent ring with four arrows) and knob.
# The arrow in the pushed direction lights up; no claws, no bark.
func _draw_joystick_calm(c: Vector2, move: Vector2) -> void:
	var k := KIT_JOY_K
	var side := 192.0 * k
	if not UiFrames.kit_at(_cv, "joystick_base", c, Vector2(side, side)):
		_cv.draw_circle(c, 89.0 * k, UiStyle.tone(Color("07191d73")))
		_cv.draw_arc(c, 89.0 * k, 0.0, TAU, 72, UiStyle.tone(Color("89b7ae8c")), 4.0, true)
	var light := UiStyle.color("ember_glow")
	var strength := clampf(move.length(), 0.0, 1.0)
	if strength > 0.05:
		_cv.draw_arc(c, 62.0 * k, move.angle() - 0.5, move.angle() + 0.5, 24, Color(light, 0.75 * strength), 4.0, true)
	for i in 4:
		var dir := Vector2.RIGHT.rotated(i * PI * 0.5)
		var lit := clampf(move.dot(dir), 0.0, 1.0)
		if lit < 0.15:
			continue
		# Same wedge as the kit arrow (tip at 82 units, base 67 units, 9 wide).
		var ortho := Vector2(-dir.y, dir.x)
		var tip := c + dir * 82.0 * k
		var base := c + dir * 67.0 * k
		_cv.draw_colored_polygon(PackedVector2Array([tip, base + ortho * 9.0 * k, base - ortho * 9.0 * k]), Color(light, lit))
	var knob := c + move.limit_length(1.0) * KNOB_TRAVEL
	var knob_side := 84.0 * KNOB_R / 38.0
	if not UiFrames.kit_at(_cv, "joystick_knob", knob, Vector2(knob_side, knob_side)):
		_cv.draw_circle(knob, KNOB_R, UiStyle.tone(Color("17363aeb")))
		_cv.draw_arc(knob, KNOB_R, 0.0, TAU, 48, UiStyle.tone(Color("b8d8cd")), 4.0, true)


# ---------------------------------------------------------------- tutorial tip

func tip_value(hud: Object, key: String) -> String:
	if hud == null:
		return ""
	if key in hud:
		return String(hud.get(key))
	return String(hud.get_meta(key, ""))


# Fades in a new tip; a changed tip first fades the old one out, then swaps.
func _update_tip(hud: Control, delta: float) -> void:
	if _tip_layer == null:
		return
	var wanted := tip_value(hud, "tutorial_tip")
	var target := 0.0
	if wanted != "":
		if _tip_text == "" or _tip_alpha <= 0.02:
			_tip_text = wanted
			_tip_icon = tip_value(hud, "tutorial_icon")
		target = 1.0 if wanted == _tip_text else 0.0
	_tip_alpha = move_toward(_tip_alpha, target, delta * TIP_FADE_SPEED)
	if _tip_alpha <= 0.0 and wanted == "":
		_tip_text = ""
	_tip_layer.position = Vector2.ZERO
	_tip_layer.size = size
	_tip_layer.modulate = Color(1, 1, 1, _ease(_tip_alpha))
	_tip_layer.visible = _tip_alpha > 0.0 and _tip_text != "" and _visible_now(hud)
	if _tip_layer.visible:
		_tip_layer.queue_redraw()


func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


func _chamfer(rect: Rect2, cut: float) -> PackedVector2Array:
	var p := rect.position
	var e := rect.end
	return PackedVector2Array([Vector2(p.x + cut, p.y), Vector2(e.x - cut, p.y), Vector2(e.x, p.y + cut), Vector2(e.x, e.y - cut),
		Vector2(e.x - cut, e.y), Vector2(p.x + cut, e.y), Vector2(p.x, e.y - cut), Vector2(p.x, p.y + cut)])


func _tip_accent(id: String) -> Color:
	match id:
		"rally", "ability":
			return UiStyle.color("ember")
		"warning":
			return UiStyle.color("danger")
		"boss":
			return UiStyle.color("gold")
		"corpse", "alpha":
			return UiStyle.color("amber")
		"mutation":
			return UiStyle.color("violet")
		"nest":
			return UiStyle.color("toxic")
	return UiStyle.color("cyan")


# Top of the hint banner slot: above the claws, and (brawl) above the ability
# button's cooldown ring when a strain ability is shown.
func _banner_top(hud: Control) -> float:
	var top := minf(hud._rally_center().y, hud._movement_center().y) - FRAME_R - 30.0 - BANNER_GAP
	if UiStyle.is_brawl() and "ability_state" in hud and not (hud.ability_state as Dictionary).is_empty():
		var ability_top: float = (hud._ability_center() as Vector2).y - ABILITY_R - 24.0
		top = minf(top, ability_top - 14.0 - BRAWL_HINT_H)
	return top


# Panel rect of the tip: always above the banner slot so the screen centre stays free.
func tip_rect() -> Rect2:
	var hud := _hud()
	if hud == null:
		return Rect2()
	var banner_top := _banner_top(hud)
	var height := _tip_height()
	var width := minf(size.x - 64.0, 800.0) if UiStyle.is_brawl() else minf(size.x - 96.0, 780.0)
	var slide := (1.0 - _ease(_tip_alpha)) * 22.0
	return Rect2(Vector2(size.x * 0.5 - width * 0.5, banner_top - TIP_GAP - height + slide), Vector2(width, height))


func _tip_text_width() -> float:
	return minf(size.x - 96.0, 780.0) - 160.0


func _tip_height() -> float:
	if UiStyle.is_brawl():
		return _tip_height_brawl()
	var lines := _wrap(_tip_text, UiStyle.display_font(), UiStyle.SIZE_BODY, _tip_text_width())
	return maxf(118.0, 60.0 + 34.0 * lines.size())


func _wrap(text: String, font: Font, font_size: int, max_w: float) -> PackedStringArray:
	var lines := PackedStringArray()
	var line := ""
	for word in text.split(" ", false):
		var candidate := word if line == "" else line + " " + word
		if line != "" and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_w:
			lines.append(line)
			line = word
		else:
			line = candidate
	if line != "":
		lines.append(line)
	return lines


func _draw_tip() -> void:
	var hud := _hud()
	if hud == null or _tip_text == "":
		return
	if UiStyle.is_brawl():
		_draw_tip_brawl(hud)
		return
	var layer := _tip_layer
	var rect := tip_rect()
	var accent := _tip_accent(_tip_icon)
	var calm := UiStyle.is_calm()
	var beat := 0.35 * _pulse(3.0) if calm else _pulse(3.0)
	_draw_tip_pointer(layer, hud, rect, accent, beat)
	var frames := _frames_script()
	if frames != null and ResourceLoader.exists("res://assets/ui/frames/panel_body.svg"):
		frames.panel(layer, rect, accent.lerp(Color.WHITE, 0.15 * beat), true)
		# Soft accent wash so the tip reads friendlier than the dark HUD panels.
		layer.draw_colored_polygon(_banner_points(frames.panel_inner(rect).grow(-4.0), 10.0), Color(accent, 0.1 + 0.04 * beat))
	else:
		var pts := _banner_points(rect, 18.0)
		layer.draw_colored_polygon(_offset(pts, Vector2(0, 5)), UiStyle.color("shadow"))
		layer.draw_colored_polygon(pts, UiStyle.color("panel"))
		layer.draw_polyline(_closed(pts), accent, 3.0, true)
	# Icon medallion on the left.
	var icon_c := Vector2(rect.position.x + 70.0, rect.get_center().y)
	var medal_r := 42.0
	if calm:
		# Quiet icon plate: chamfered square with a thin accent stroke, no glow.
		var plate := Rect2(icon_c - Vector2.ONE * medal_r, Vector2.ONE * medal_r * 2.0)
		layer.draw_colored_polygon(_chamfer(plate, 12.0), UiStyle.color("panel"))
		layer.draw_polyline(_closed(_chamfer(plate, 12.0)), accent, 3.0, true)
	else:
		if not _tex_at_on(layer, "glow.svg", icon_c, Vector2.ONE * (medal_r + 22.0 + 6.0 * beat) * 2.0, Color(accent, 0.45)):
			layer.draw_circle(icon_c, medal_r + 10.0, Color(accent, 0.18))
		layer.draw_circle(icon_c, medal_r, UiStyle.tone(Color("0a1712f2")))
		layer.draw_arc(icon_c, medal_r, 0.0, TAU, 48, accent, 3.5, true)
	var icons := _icons_script()
	var icon_id: String = TIP_ICONS.get(_tip_icon, "")
	if icons != null and icon_id != "" and icons.has(icon_id):
		var icon_r := medal_r * 0.78
		icons.draw(layer, icon_id, Rect2(icon_c - Vector2.ONE * icon_r, Vector2.ONE * icon_r * 2.0), Color.WHITE)
	else:
		UiStyle.text(layer, "!", icon_c + Vector2(0, 14), UiStyle.SIZE_HEAD, accent, true, 6)
	# "TIPP" tag hangs on the top edge; the message sits right of the medallion.
	var tag := Rect2(Vector2(rect.position.x + 128.0, rect.position.y - 17.0), Vector2(92.0, 34.0))
	if frames != null and ResourceLoader.exists("res://assets/ui/frames/pill_body.svg"):
		frames.pill(layer, tag, accent)
	else:
		layer.draw_rect(tag, UiStyle.tone(Color("0a1712f2")))
		layer.draw_rect(tag, accent, false, 2.0)
	UiStyle.text(layer, "TIPP", tag.get_center() + Vector2(0, 8), UiStyle.SIZE_LABEL, accent.lerp(Color.WHITE, 0.35), true, 5)
	var lines := _wrap(_tip_text, UiStyle.display_font(), UiStyle.SIZE_BODY, _tip_text_width())
	var text_x := rect.position.x + 128.0
	var first_baseline := rect.get_center().y - (lines.size() - 1) * 17.0 + UiStyle.SIZE_BODY * 0.36
	for i in lines.size():
		UiStyle.text(layer, lines[i], Vector2(text_x, first_baseline + i * 34.0), UiStyle.SIZE_BODY, UiStyle.color("text"), false, 6)


# Bewegen/Rally: animated chevrons from the panel down to the matching control,
# a pulsing ring around it and a fingertip (dragging on the joystick, pressing Rally).
func _draw_tip_pointer(layer: Control, hud: Control, rect: Rect2, accent: Color, beat: float) -> void:
	var target: Vector2
	var frame := FRAME_R
	match _tip_icon:
		"move":
			target = hud._movement_center()
		"rally":
			target = hud._rally_center()
		"ability":
			if not hud.has_method("_ability_center"):
				return
			target = hud._ability_center()
			frame = 78.0
		_:
			return
	var from := Vector2(clampf(target.x, rect.position.x + 40.0, rect.end.x - 40.0), rect.end.y + 6.0)
	var to := target + Vector2(0.0, -frame - 14.0)
	var along := to - from
	var dir := along.normalized()
	var side := Vector2(-dir.y, dir.x)
	for i in 3:
		var phase := fposmod(_t() * 0.9 + i / 3.0, 1.0)
		var p := from + along * phase
		var fade := sin(phase * PI)
		var pts := PackedVector2Array([p - dir * 10.0 + side * 16.0, p + dir * 6.0, p - dir * 10.0 - side * 16.0])
		layer.draw_polyline(pts, Color(UiStyle.color("outline"), 0.7 * fade), 9.0, true)
		layer.draw_polyline(pts, Color(accent.lerp(Color.WHITE, 0.3), fade), 5.0, true)
	var ring_r := frame + 12.0 + 10.0 * beat
	layer.draw_arc(target, ring_r, 0.0, TAU, 72, Color(UiStyle.color("outline"), 0.5), 8.0, true)
	layer.draw_arc(target, ring_r, 0.0, TAU, 72, Color(accent, 0.55 + 0.4 * beat), 4.0, true)
	var finger: Vector2
	var finger_r := 22.0
	if _tip_icon == "move":
		var swing := sin(_t() * 2.2)
		finger = target + Vector2(swing * 46.0, -26.0 + absf(swing) * 10.0)
	else:
		finger = target + Vector2(0.0, -16.0)
		finger_r = 20.0 + 6.0 * beat
		layer.draw_arc(target, 36.0 + 40.0 * (1.0 - beat), 0.0, TAU, 48, Color(UiStyle.color("text"), 0.6 * beat), 3.0, true)
	layer.draw_circle(finger + Vector2(0, 4), finger_r + 3.0, Color(UiStyle.color("outline"), 0.55))
	layer.draw_circle(finger, finger_r, Color(UiStyle.color("text"), 0.92))
	layer.draw_arc(finger, finger_r, 0.0, TAU, 32, accent, 3.0, true)


func _tex_at_on(layer: CanvasItem, name: String, center: Vector2, tex_size: Vector2, tint: Color) -> bool:
	var texture := UiStyle.tex(DIR + name)
	if texture == null:
		return false
	layer.draw_texture_rect(texture, Rect2(center - tex_size * 0.5, tex_size), false, tint)
	return true


# ---------------------------------------------------------------- hint banner

func _is_warning(text: String) -> bool:
	var upper := text.to_upper()
	return upper.begins_with("RAUS") or upper.begins_with("SPRINT")


func _draw_hint(text: String, top: float) -> void:
	if UiStyle.is_brawl():
		_draw_hint_brawl(text, top)
		return
	if _paint == "hint_glow":
		return
	var warn := _is_warning(text)
	var font := UiStyle.display_font()
	var font_size := UiStyle.SIZE_HEAD - 4 if warn else UiStyle.SIZE_BODY
	var icon_space := 46.0 if warn else 0.0
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var max_w := size.x - 72.0
	var width := clampf(text_w + icon_space + 88.0, 380.0, max_w)
	if text_w + icon_space + 88.0 > max_w:
		font_size = maxi(UiStyle.SIZE_LABEL, int(font_size * (max_w - icon_space - 88.0) / text_w))
		text_w = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var height := 66.0 if warn else 60.0
	var rect := Rect2(Vector2(size.x * 0.5 - width * 0.5, top), Vector2(width, height))
	var beat := _pulse(9.0) if warn else 0.0
	var accent: Color = UiStyle.color("danger") if warn else UiStyle.color("toxic").lerp(UiStyle.color("bone"), 0.35)
	var frames := _frames_script()
	if frames != null and ResourceLoader.exists("res://assets/ui/frames/panel_body.svg"):
		# Shared organic panel from the frame kit; warnings add a pulsing red fill and halo.
		if warn and not UiStyle.is_calm():
			for k in 2:
				var halo := _banner_points(rect.grow(4.0 + 5.0 * k + 3.0 * beat), 18.0)
				_cv.draw_polyline(_closed(halo), Color(UiStyle.color("danger"), (0.85 - 0.4 * k) * (0.45 + 0.55 * beat)), 5.0 - k, true)
		frames.panel(_cv, rect, accent.lerp(Color.WHITE, 0.25 * beat), true)
		if warn:
			var inner_rect: Rect2 = frames.panel_inner(rect)
			_cv.draw_colored_polygon(_banner_points(inner_rect, 8.0), Color(UiStyle.color("danger"), 0.42 + 0.22 * beat))
	else:
		_draw_banner_fallback(rect, warn, accent, beat)
	var content_w := text_w + icon_space
	var x := rect.get_center().x - content_w * 0.5
	var baseline := rect.position.y + height * 0.5 + font_size * 0.36
	if warn:
		_warn_icon(Vector2(x + 18.0, rect.get_center().y), 19.0 + 2.0 * beat, UiStyle.color("danger").lerp(UiStyle.color("gold"), 0.35 * beat))
	var text_color: Color = Color.WHITE.lerp(UiStyle.tone(Color("ffd9c8")), beat) if warn else UiStyle.color("text")
	UiStyle.text(_cv, text, Vector2(x + icon_space, baseline), font_size, text_color, false, 7)


func _draw_banner_fallback(rect: Rect2, warn: bool, accent: Color, beat: float) -> void:
	var height := rect.size.y
	var outer := _banner_points(rect, 16.0)
	var inner := _banner_points(rect.grow(-5.0), 12.0)
	_cv.draw_colored_polygon(_offset(outer, Vector2(0, 5)), UiStyle.color("shadow"))
	_cv.draw_colored_polygon(outer, UiStyle.tone(Color("2a0c08f0")) if warn else UiStyle.color("panel"))
	_cv.draw_colored_polygon(inner, Color(UiStyle.color("danger"), 0.16 + 0.18 * beat) if warn else Color(UiStyle.color("panel_soft"), 0.9))
	_veins(rect, Color(accent, 0.22))
	var edge := accent.lerp(Color.WHITE, 0.25 * beat)
	_cv.draw_polyline(_closed(outer), edge, 3.0 if not warn else 4.0, true)
	_cv.draw_polyline(_closed(inner), Color(edge, 0.3), 1.5, true)
	# Bone teeth on both ends of the banner.
	for s: float in [-1.0, 1.0]:
		var base_x := rect.get_center().x + s * (rect.size.x * 0.5 - 2.0)
		for k in 2:
			var y := rect.position.y + height * (0.32 + 0.36 * k)
			var tip := Vector2(base_x + s * 16.0, y)
			_cv.draw_colored_polygon(PackedVector2Array([Vector2(base_x - s * 4.0, y - 8), tip, Vector2(base_x - s * 4.0, y + 8)]), UiStyle.color("bone"))
			_cv.draw_polyline(PackedVector2Array([Vector2(base_x - s * 4.0, y - 8), tip, Vector2(base_x - s * 4.0, y + 8)]), UiStyle.color("outline"), 1.5, true)


func _frames_script() -> Script:
	if not _frames_checked:
		_frames_checked = true
		if ResourceLoader.exists(FRAMES_PATH):
			_frames = load(FRAMES_PATH)
	return _frames


func _warn_icon(center: Vector2, radius: float, color: Color) -> void:
	var icons := _icons_script()
	if icons != null and UiStyle.is_calm() and icons.has("v2_threat"):
		icons.draw(_cv, "v2_threat", Rect2(center - Vector2.ONE * radius * 1.15, Vector2.ONE * radius * 2.3), Color.WHITE)
		return
	if icons != null and icons.has("skull"):
		icons.draw(_cv, "skull", Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), color)
		return
	var pts := PackedVector2Array([center + Vector2(0, -radius), center + Vector2(radius * 1.05, radius * 0.8), center + Vector2(-radius * 1.05, radius * 0.8)])
	_cv.draw_colored_polygon(pts, color)
	_cv.draw_polyline(_closed(pts), UiStyle.color("outline"), 2.0, true)
	_cv.draw_rect(Rect2(center + Vector2(-2.5, -radius * 0.45), Vector2(5, radius * 0.7)), UiStyle.color("outline"))
	_cv.draw_circle(center + Vector2(0, radius * 0.5), 3.0, UiStyle.color("outline"))


func _icons_script() -> Script:
	if not _icons_checked:
		_icons_checked = true
		if ResourceLoader.exists(ICONS_PATH):
			_icons = load(ICONS_PATH)
	return _icons


# Chamfered banner with two small notches on the long edges.
func _banner_points(rect: Rect2, cut: float) -> PackedVector2Array:
	var p := rect.position
	var e := rect.end
	var mid := rect.get_center().x
	var notch := 6.0
	return PackedVector2Array([
		Vector2(p.x + cut, p.y), Vector2(mid - 70, p.y), Vector2(mid - 60, p.y + notch), Vector2(mid + 60, p.y + notch), Vector2(mid + 70, p.y),
		Vector2(e.x - cut, p.y), Vector2(e.x, p.y + cut), Vector2(e.x, e.y - cut), Vector2(e.x - cut, e.y),
		Vector2(mid + 40, e.y), Vector2(mid + 32, e.y - notch), Vector2(mid - 32, e.y - notch), Vector2(mid - 40, e.y),
		Vector2(p.x + cut, e.y), Vector2(p.x, e.y - cut), Vector2(p.x, p.y + cut),
	])


func _veins(rect: Rect2, color: Color) -> void:
	var seed_points := [0.12, 0.27, 0.73, 0.88]
	for f in seed_points:
		var x: float = rect.position.x + rect.size.x * f
		var pts := PackedVector2Array()
		for k in 5:
			var t := k / 4.0
			pts.append(Vector2(x + sin(t * 5.0 + f * 20.0) * 10.0, rect.position.y + 8.0 + (rect.size.y - 16.0) * t))
		_cv.draw_polyline(pts, color, 1.5, true)


func _offset(points: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in points:
		out.append(point + by)
	return out


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := points.duplicate()
	out.append(points[0])
	return out


# ================================================================ brawl skin
# Stage 15 (wave 2, package B): Supercell-style controls drawn only with the
# brawl kit. Rally = big ember round button (held: pressed face + light ring),
# joystick = translucent disc with an ink contour and a neutral knob (info while
# steering), hints and tips = pills bottom centre. The touch areas stay in the
# parent (radius 125 around _rally_center() / _movement_center()).

const ABILITY_R := 68.0         # = touch_controls.ABILITY_R (drawn radius)
const BRAWL_RALLY_R := 100.0   # round button, 200 px across (touch radius 125)
const BRAWL_JOY_R := 112.0     # base disc
const BRAWL_KNOB_R := 50.0     # knob, 100 px across
const BRAWL_HINT_H := 76.0
const BRAWL_TIP_PLATE := 76.0


## Optional Rally charge from the HUD: property/meta `rally_charge` (0..1,
## 1 = ready) draws a ring around the button, `rally_count` (int > 0) a badge.
## -1 = the run has no charge (today Rally is a plain hold).
func _rally_charge(hud: Object) -> float:
	if hud == null:
		return -1.0
	var value: Variant = hud.get("rally_charge") if "rally_charge" in hud else (hud.get_meta("rally_charge") if hud.has_meta("rally_charge") else null)
	if value == null:
		return -1.0
	return snappedf(clampf(float(value), 0.0, 1.0), 0.01)


func _rally_count(hud: Object) -> int:
	if hud == null:
		return 0
	var value: Variant = hud.get("rally_count") if "rally_count" in hud else (hud.get_meta("rally_count") if hud.has_meta("rally_count") else null)
	return int(value) if value != null else 0


func _draw_rally_brawl(c: Vector2, pressed: bool) -> void:
	var r := BRAWL_RALLY_R
	var light: Color = UiStyle.brawl_tone("ember")["light"]
	match _paint:
		"rally_glow":
			if pressed:
				# Glow ring: soft halo plus a bright band with an ink contour.
				Kit.glow(_cv, c, r + 40.0, light, 0.55)
				Kit.circle_ring(_cv, c, r + 14.0, 3.0, UiStyle.BRAWL_INK)
				Kit.circle_ring(_cv, c, r + 11.0, 7.0, light)
				Kit.circle_ring(_cv, c, r + 4.0, 3.0, UiStyle.BRAWL_INK)
		"rally_base":
			var hud := _hud()
			var charge := _rally_charge(hud)
			if charge >= 0.0:
				Kit.circle_ring(_cv, c, r + 12.0, 10.0, Color(UiStyle.BRAWL_WELL, 0.85))
				if charge > 0.0:
					_cv.draw_arc(c, r + 7.0, -PI * 0.5, -PI * 0.5 + TAU * charge, 64, light if charge >= 1.0 else Color(light, 0.8), 6.0, true)
			Kit.round_button(_cv, c, r, "ember", pressed)
			var lc := Kit.round_label_center(c, r, pressed)
			Kit.text_outlined(_cv, lc, "RALLY", UiStyle.T_HEAD, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
			var count := _rally_count(hud)
			if count > 0:
				Kit.badge(_cv, c + Vector2(r * 0.72, -r * 0.72), str(count), "info", UiStyle.T_LABEL)
	# Held: thin light rings pull in toward the button (the swarm gathers).
	if pressed and _paint == "rally_rings":
		for i in 2:
			var phase := fposmod(_t() * 1.3 + i * 0.5, 1.0)
			var rr := lerpf(r + 48.0, r + 16.0, phase)
			var fade := sin(phase * PI)
			Kit.circle_ring(_cv, c, rr, 4.0, Color(light, 0.7 * fade))


# ---------------------------------------------------------------- ability (stage 17d)

func _ability_pressed(hud: Control) -> bool:
	return "ability_pressed_at" in hud and Time.get_ticks_msec() - int(hud.ability_pressed_at) < 160


## Round tribe-ability button up-right of Rally: strain icon, cooldown ring
## (fills clockwise in ember light, seconds in the middle while cooling), a
## soft ember glow when ready, a bright ring while the effect runs. The own
## colour is ember - never the danger pink.
func _draw_ability(c: Vector2, state: Dictionary, pressed: bool) -> void:
	var r: float = ABILITY_R
	var ready := bool(state.get("ready", false))
	var share := clampf(float(state.get("share", 0.0)), 0.0, 1.0)
	var active := float(state.get("active", 0.0))
	var light: Color = UiStyle.brawl_tone("ember")["light"]
	if ready:
		# Static glow: the layer bakes into one texture (a pulsing glow cost ~130
		# draw calls a frame, Etappe 22).
		Kit.glow(_cv, c, r + 30.0, light, 0.42)
	# Cooldown track and ring.
	Kit.circle_ring(_cv, c, r + 11.0, 11.0, Color(UiStyle.BRAWL_WELL, 0.9))
	if share > 0.0:
		_cv.draw_arc(c, r + 11.0, -PI * 0.5, -PI * 0.5 + TAU * share, 64, light if ready else Color(light, 0.75), 7.0, true)
	Kit.circle_ring(_cv, c, r + 17.0, 3.0, UiStyle.BRAWL_INK)
	Kit.round_button(_cv, c, r, "ember" if ready else "neutral", pressed)
	var lc := Kit.round_label_center(c, r, pressed)
	var icon := String(state.get("icon", ""))
	var icon_rect := Rect2(lc - Vector2.ONE * r * 0.62, Vector2.ONE * r * 1.24)
	if icon != "":
		UiIcons.draw(_cv, icon, icon_rect, Color.WHITE if ready else Color(1, 1, 1, 0.45))
	if not ready:
		Kit.text_outlined(_cv, lc + Vector2(0, 4), str(int(state.get("seconds", 0))), UiStyle.T_HEAD, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
	if active > 0.0:
		Kit.circle_ring(_cv, c, r + 24.0, 5.0, Color(light, 0.5 + 0.5 * active))
	# Name under the button (short, in the kit label size).
	Kit.text_outlined(_cv, c + Vector2(0, r + 34.0), String(state.get("name", "")).to_upper(), UiStyle.T_LABEL, Color.WHITE if ready else UiStyle.BRAWL_TEXT_DIM, -1, -1, null, Kit.CENTER | Kit.MIDDLE)


func _draw_joystick_brawl(c: Vector2, move: Vector2) -> void:
	var strength := clampf(move.length(), 0.0, 1.0)
	var r := BRAWL_JOY_R
	var info: Dictionary = UiStyle.brawl_tone("info")
	# Etappe 22: the static base (disc, rings, quiet arrows) lives in the baked
	# "joy_base" layer; "joy" only draws what moves (lit rim, lit arrows, knob).
	var base_pass := _paint == "joy_base"
	if base_pass:
		Kit.disc(_cv, c, r, Color(UiStyle.BRAWL_INK, 0.34))
		Kit.circle_ring(_cv, c, r + 2.0, 4.0, Color(UiStyle.BRAWL_INK, 0.55))
		Kit.circle_ring(_cv, c, r - 1.0, 5.0, Color(1, 1, 1, 0.4))
		Kit.circle_ring(_cv, c, r * 0.56, 2.0, Color(1, 1, 1, 0.12))
		for i in 4:
			var dir := Vector2.RIGHT.rotated(i * PI * 0.5)
			var tip := c + dir * (r - 16.0)
			var base := c + dir * (r - 32.0)
			var side := Vector2(-dir.y, dir.x)
			var pts := PackedVector2Array([tip, base + side * 13.0, base - side * 13.0])
			var closed := pts.duplicate()
			closed.append(pts[0])
			_cv.draw_polyline(closed, Color(UiStyle.BRAWL_INK, 0.5), 5.0, true)
			_cv.draw_colored_polygon(pts, Color(1, 1, 1, 0.5))
		return
	# Steering direction lights the rim.
	if strength > 0.05:
		var a := move.angle()
		_cv.draw_arc(c, r - 4.0, a - 0.55, a + 0.55, 24, Color(info["light"], 0.9 * strength), 8.0, true)
	# Lit direction arrows over the quiet ones of the base layer.
	for i in 4:
		var dir := Vector2.RIGHT.rotated(i * PI * 0.5)
		var lit := clampf(move.dot(dir), 0.0, 1.0)
		if lit <= 0.02:
			continue
		var tip := c + dir * (r - 16.0)
		var base := c + dir * (r - 32.0)
		var side := Vector2(-dir.y, dir.x)
		var pts := PackedVector2Array([tip, base + side * 13.0, base - side * 13.0])
		_cv.draw_colored_polygon(pts, Color(1, 1, 1, 0.5).lerp(info["light"], lit))
	# Knob: neutral at rest, info (pushed in) while steering.
	var knob := c + move.limit_length(1.0) * KNOB_TRAVEL
	var active := strength > 0.05
	Kit.round_button(_cv, knob, BRAWL_KNOB_R, "info" if active else "neutral", active)


# ---------------------------------------------------------------- brawl hint

func _hint_tone(text: String) -> String:
	var upper := text.to_upper()
	if upper.begins_with("EVOLUTION"):
		return "special"
	if upper.begins_with("MIGRATION"):
		return "info"
	return "dark"


func _draw_hint_brawl(text: String, top: float) -> void:
	var warn := _is_warning(text)
	var font := UiStyle.display_font()
	var size_px := UiStyle.T_HEAD if warn else UiStyle.T_BODY
	var h := BRAWL_HINT_H if warn else 64.0
	var glyph_w := 64.0 if warn else 0.0
	var pad := 34.0
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var max_w := size.x - 48.0
	var width := clampf(text_w + glyph_w + pad * 2.0, 320.0, max_w)
	var text_room := width - glyph_w - pad * 2.0
	var shown_w := minf(text_w, text_room)
	var rect := Rect2(Vector2(roundf(size.x * 0.5 - width * 0.5), top + (BRAWL_HINT_H - h) * 0.5), Vector2(roundf(width), h))
	if _paint == "hint_glow":
		# Etappe 22b: only the pulsing halo repaints; the banner below is baked.
		if warn:
			var beat := _pulse(9.0)
			var glow: Color = UiStyle.brawl_tone("danger")["light"]
			for k in 3:
				Kit.ring(_cv, rect.grow(6.0 + 5.0 * k + 3.0 * beat), h * 0.5 + 6.0 + 5.0 * k, 4.0, Color(glow, (0.55 - 0.16 * k) * (0.4 + 0.6 * beat)))
		return
	if warn:
		Kit.pill(_cv, rect, "danger")
	else:
		Kit.pill(_cv, rect, _hint_tone(text))
	var x := rect.get_center().x - (shown_w + glyph_w) * 0.5
	var mid := rect.position.y + (h - 4.0) * 0.5
	if warn:
		Kit.warn_glyph(_cv, Vector2(x + 24.0, mid), 25.0)
	Kit.text_outlined(_cv, Vector2(x + glyph_w, mid), text, size_px, Color.WHITE, -1, -1, font, Kit.LEFT | Kit.MIDDLE, text_room)


# ---------------------------------------------------------------- brawl tip

func _tip_plate_tone(id: String) -> String:
	match id:
		"rally":
			return "ember"
		"warning", "boss", "leader_low", "sandstorm", "quicksand":
			return "danger"
		"corpse", "prey", "amber", "cocoon", "boss_cocoon":
			return "loot"
		"alpha", "mutation", "shrine", "xp":
			return "special"
		"nest", "powerup":
			return "action"
	return "info"


func _tip_text_width_brawl() -> float:
	return minf(size.x - 64.0, 800.0) - BRAWL_TIP_PLATE - 64.0


func _tip_height_brawl() -> float:
	var lines := Kit.wrap_lines(_tip_text, UiStyle.body_bold_font(), UiStyle.T_BODY, _tip_text_width_brawl())
	return maxf(104.0, 40.0 + 34.0 * mini(lines.size(), 3))


func _draw_tip_brawl(hud: Control) -> void:
	var layer := _tip_layer
	var rect := tip_rect()
	rect = Rect2(rect.position.round(), rect.size)
	var height := rect.size.y
	var tone := _tip_plate_tone(_tip_icon)
	_draw_tip_pointer_brawl(layer, hud, rect, tone)
	Kit.panel(layer, rect, "dark", minf(height * 0.5, UiStyle.R_XL))
	# Icon plate on the left, "TIPP" chip on the top edge.
	var plate_c := Vector2(rect.position.x + 20.0 + BRAWL_TIP_PLATE * 0.5, rect.get_center().y)
	# The painted Rally jaws are red: they need the dark plate to read.
	Kit.icon_plate(layer, plate_c, BRAWL_TIP_PLATE, "dark" if _tip_icon == "rally" else tone)
	var icon_id: String = TIP_ICONS.get(_tip_icon, "")
	var ic := Kit.plate_center(plate_c, BRAWL_TIP_PLATE)
	if icon_id != "" and UiIcons.has(icon_id):
		UiIcons.draw(layer, icon_id, Rect2(ic - Vector2.ONE * 29.0, Vector2.ONE * 58.0), Color.WHITE)
	else:
		Kit.text_outlined(layer, ic, "!", UiStyle.T_HEAD, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
	var chip := Rect2(Vector2(rect.position.x + BRAWL_TIP_PLATE + 44.0, rect.position.y - 18.0), Vector2(86.0, 34.0))
	Kit.chip(layer, chip, "info")
	Kit.text_outlined(layer, chip.get_center(), "TIPP", UiStyle.T_LABEL, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
	var text_x := rect.position.x + BRAWL_TIP_PLATE + 44.0
	var tw := _tip_text_width_brawl()
	var lines := Kit.wrap_lines(_tip_text, UiStyle.body_bold_font(), UiStyle.T_BODY, tw)
	var n := mini(lines.size(), 3)
	var first := rect.get_center().y - (n - 1) * 17.0 + UiStyle.T_BODY * Kit.CAP_BODY * 0.5 + 2.0
	Kit.paragraph(layer, Vector2(text_x, first), _tip_text, tw, UiStyle.T_BODY, Color.WHITE, true, Kit.LEFT, 3, 0)


# Bewegen/Rally tips point at their control: chevrons, a ring and a fingertip.
func _draw_tip_pointer_brawl(layer: Control, hud: Control, rect: Rect2, tone: String) -> void:
	var target: Vector2
	var target_r: float
	match _tip_icon:
		"move":
			target = hud._movement_center()
			target_r = BRAWL_JOY_R
		"rally":
			target = hud._rally_center()
			target_r = BRAWL_RALLY_R
		"ability":
			# Etappe 24: the ability tip points at its button (up-right of Rally).
			if not ("ability_state" in hud) or (hud.ability_state as Dictionary).is_empty():
				return
			target = hud._ability_center()
			target_r = ABILITY_R + 17.0
		_:
			return
	var light: Color = UiStyle.brawl_tone(tone)["light"]
	var beat := _pulse(3.0)
	var from := Vector2(clampf(target.x, rect.position.x + 48.0, rect.end.x - 48.0), rect.end.y + 8.0)
	var to := target + Vector2(0.0, -target_r - 26.0)
	var along := to - from
	var dir := along.normalized()
	var side := Vector2(-dir.y, dir.x)
	for i in 3:
		var phase := fposmod(_t() * 0.9 + i / 3.0, 1.0)
		var p := from + along * phase
		var fade := sin(phase * PI)
		var pts := PackedVector2Array([p - dir * 11.0 + side * 17.0, p + dir * 7.0, p - dir * 11.0 - side * 17.0])
		layer.draw_polyline(pts, Color(UiStyle.BRAWL_INK, 0.8 * fade), 12.0, true)
		layer.draw_polyline(pts, Color(Color.WHITE, fade), 6.0, true)
	# The ring stays on screen (the controls sit 125 px from the edges).
	var edge := minf(minf(target.x, size.x - target.x), size.y - target.y) - 8.0
	var ring_r := minf(target_r + 16.0 + 6.0 * beat, edge)
	Kit.circle_ring(layer, target, ring_r + 2.0, 9.0, Color(UiStyle.BRAWL_INK, 0.55))
	Kit.circle_ring(layer, target, ring_r, 5.0, Color(light, 0.6 + 0.4 * beat))
	var finger: Vector2
	var finger_r := 22.0
	if _tip_icon == "move":
		var swing := sin(_t() * 2.2)
		finger = target + Vector2(swing * 46.0, -26.0 + absf(swing) * 10.0)
	else:
		# Presses the lower right of the button, the label stays readable.
		finger = target + Vector2(38.0, 44.0)
		finger_r = 20.0 + 5.0 * beat
	Kit.disc(layer, finger + Vector2(0, 4), finger_r + 4.0, UiStyle.BRAWL_INK_SOFT)
	Kit.disc(layer, finger, finger_r + 3.0, UiStyle.BRAWL_INK)
	Kit.disc(layer, finger, finger_r, Color.WHITE)
