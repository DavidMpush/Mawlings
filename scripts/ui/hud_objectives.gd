extends Control

# Stage 06 · Run-Ziele HUD. HuntWorld adds this component to HUD/Controls and
# publishes its state as the HUD meta "objectives" (see HuntWorld._objective_hud):
# off-screen pointers for the Brutnest (with its fill ring) and the Fluch-Totem,
# plus a status chip while a curse is active. Input stays in touch_controls.gd.

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const UiIcons := preload("res://scripts/ui/ui_icons.gd")
const CURSE := Color("ff4a8a")
const CHIP_Y := 392.0          # left column, below corpse and biomass hints
const POINTER_GAP := 128.0     # minimum distance between two edge markers

var _time := 0.0
var _last_key: Variant = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# Stage 07: repaint only when the markers move or pulse (30 Hz) or the curse
# chip pulses (20 Hz); with nothing to show it stays empty and costs nothing.
func _process(delta: float) -> void:
	_time += delta
	var key: Array = [size]
	var state := _state()
	if not state.is_empty() and not _hidden():
		var markers := bool(state.get("nest_active", false)) or bool(state.get("totem_active", false))
		var tick := int(_time * 30.0) if markers else (int(_time * 20.0) if int(state.get("curse", 0)) > 0 else 0)
		key = [size, state.duplicate(), get_parent().get("boss_pointer"), tick]
	if typeof(_last_key) != TYPE_ARRAY or key != _last_key:
		queue_redraw()
	_last_key = key


func _state() -> Dictionary:
	var hud := get_parent()
	if hud == null or not hud.has_meta("objectives"):
		return {}
	return hud.get_meta("objectives")


func _hidden() -> bool:
	var hud := get_parent()
	if hud == null:
		return true
	if bool(hud.get("paused")) or bool(hud.get("extinct")):
		return true
	return hud.has_method("_choosing") and hud._choosing()


func _draw() -> void:
	var state := _state()
	if state.is_empty() or _hidden():
		return
	var boss_at: Vector2 = get_parent().get("boss_pointer") if get_parent().get("boss_pointer") is Vector2 else Vector2.INF
	var taken: Array[Vector2] = []
	if boss_at.is_finite():
		taken.append(boss_at)
	if bool(state.get("nest_active", false)):
		var at: Vector2 = state.get("nest_pointer", Vector2.INF)
		if at.is_finite():
			at = _separate(at, taken)
			taken.append(at)
			_draw_nest_pointer(at, float(state.get("nest_progress", 0.0)))
	if bool(state.get("totem_active", false)):
		var at: Vector2 = state.get("totem_pointer", Vector2.INF)
		if at.is_finite():
			_draw_totem_pointer(_separate(at, taken), float(state.get("totem_hold", 0.0)))
		var hold := float(state.get("totem_hold", 0.0))
		var screen: Vector2 = state.get("totem_screen", Vector2.INF)
		if hold > 0.0 and screen.is_finite():
			_draw_totem_hold(screen, hold)
	var curse := int(state.get("curse", 0))
	if curse > 0:
		_draw_curse_chip(curse)


# Pushes a marker along the screen edge until it clears the others.
func _separate(at: Vector2, taken: Array[Vector2]) -> Vector2:
	for other in taken:
		if at.distance_to(other) < POINTER_GAP:
			var along := Vector2(0, 1) if absf(at.x - size.x * 0.5) > absf(at.y - size.y * 0.5) else Vector2(1, 0)
			var push := along * POINTER_GAP * (1.0 if along.dot(at - other) >= 0.0 else -1.0)
			at += push
	return at


func _keep_on_screen(at: Vector2, reach: float) -> Vector2:
	return Vector2(clampf(at.x, reach, size.x - reach), clampf(at.y, reach, size.y - reach))


func _draw_nest_pointer(at: Vector2, progress: float) -> void:
	var direction := (at - size * 0.5).normalized()
	at = _keep_on_screen(at, 70.0)
	var pulse := 0.5 + 0.5 * sin(_time * 3.2)
	var r := 44.0
	draw_circle(at, r + 12 + 5 * pulse, Color(UiStyle.CYAN, 0.10 + 0.08 * pulse))
	_arrow(at, direction, r, UiStyle.CYAN)
	draw_circle(at + Vector2(0, 4), r, UiStyle.SHADOW)
	draw_circle(at, r, UiStyle.PANEL)
	draw_arc(at, r - 3, 0.0, TAU, 48, Color(UiStyle.CYAN, 0.35), 5.0, true)
	if progress > 0.0:
		draw_arc(at, r - 3, -PI * 0.5, -PI * 0.5 + TAU * progress, 48, UiStyle.CYAN.lightened(0.2), 7.0, true)
	UiIcons.draw(self, "brood", Rect2(at - Vector2(29, 29), Vector2(58, 58)), Color.WHITE)
	_label("BRUTNEST", at + Vector2(0, r + 28), UiStyle.CYAN.lightened(0.35))


func _draw_totem_pointer(at: Vector2, hold: float) -> void:
	var direction := (at - size * 0.5).normalized()
	at = _keep_on_screen(at, 64.0)
	var pulse := 0.5 + 0.5 * sin(_time * 4.0)
	var r := 38.0
	draw_circle(at, r + 10 + 4 * pulse, Color(CURSE, 0.10 + 0.08 * pulse))
	_arrow(at, direction, r, UiStyle.VIOLET)
	draw_circle(at + Vector2(0, 4), r, UiStyle.SHADOW)
	draw_circle(at, r, UiStyle.PANEL)
	draw_arc(at, r - 3, 0.0, TAU, 40, UiStyle.VIOLET.lerp(CURSE, hold), 4.0, true)
	UiIcons.draw(self, "skull", Rect2(at - Vector2(25, 25), Vector2(50, 50)), Color("ffd3e4"))
	_label("TOTEM", at + Vector2(0, r + 28), CURSE.lightened(0.45))


# Hold ring over the totem while the swarm stands on it (the swarm hides the ground ring).
func _draw_totem_hold(at: Vector2, hold: float) -> void:
	var r := 58.0
	var pulse := 0.5 + 0.5 * sin(_time * 9.0)
	at += Vector2(0, -150)
	draw_circle(at, r + 8 + 6 * pulse * hold, Color(CURSE, 0.14 + 0.12 * hold))
	draw_circle(at + Vector2(0, 4), r, UiStyle.SHADOW)
	draw_circle(at, r, Color(UiStyle.PANEL, 0.9))
	draw_arc(at, r - 5, 0.0, TAU, 56, Color(UiStyle.VIOLET, 0.35), 8.0, true)
	draw_arc(at, r - 5, -PI * 0.5, -PI * 0.5 + TAU * hold, 56, CURSE.lerp(Color.WHITE, 0.25 * pulse), 10.0, true)
	UiIcons.draw(self, "skull", Rect2(at - Vector2(32, 32), Vector2(64, 64)), Color("ffd3e4"))
	_label("FLUCH ANNEHMEN", at + Vector2(0, r + 30), Color("ffd3e4"))


func _draw_curse_chip(curse: int) -> void:
	var text := "FLUCH · BEUTE ×2 · BOSS +50%" if curse == 1 else "VERFLUCHTER KING · BEUTE ×2"
	var font := UiStyle.body_font()
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.SIZE_LABEL + 1).x + 66
	var rect := Rect2(16, CHIP_Y, w, 46)
	var pulse := 0.5 + 0.5 * sin(_time * 3.0)
	var points := _pill_points(rect)
	draw_colored_polygon(points, Color(UiStyle.PANEL.darkened(0.2), 0.94).lerp(CURSE, 0.10 + 0.06 * pulse))
	points.append(points[0])
	draw_polyline(points, CURSE.lerp(UiStyle.VIOLET, 0.4), 3.0, true)
	var icon_c := rect.position + Vector2(26, 23)
	draw_circle(icon_c, 18, Color(CURSE, 0.18 + 0.14 * pulse))
	UiIcons.draw(self, "skull", Rect2(icon_c - Vector2(17, 17), Vector2(34, 34)), Color("ffd3e4"))
	UiStyle.text(self, text, rect.position + Vector2(48, 31), UiStyle.SIZE_LABEL + 1, Color("ffd3e4"), false, 5, font)


func _arrow(center: Vector2, direction: Vector2, r: float, color: Color) -> void:
	if direction.length_squared() < 0.01:
		return
	var side := Vector2(-direction.y, direction.x)
	var tip := center + direction * (r + 24)
	var base := center + direction * (r - 4)
	draw_colored_polygon(PackedVector2Array([tip + direction * 2 + Vector2(0, 3), base + side * 17 + Vector2(0, 3), base - side * 17 + Vector2(0, 3)]), UiStyle.SHADOW)
	draw_colored_polygon(PackedVector2Array([tip, base + side * 16, base - side * 16]), color)


func _label(text: String, at: Vector2, color: Color) -> void:
	UiStyle.text(self, text, at, UiStyle.SIZE_LABEL + 1, color, true, 6, UiStyle.body_font())


func _pill_points(rect: Rect2) -> PackedVector2Array:
	var points := PackedVector2Array()
	var r := rect.size.y * 0.5
	for index in 13:
		var angle := PI * 0.5 + PI * float(index) / 12.0
		points.append(Vector2(rect.position.x + r, rect.position.y + r) + Vector2(cos(angle), sin(angle)) * r)
	for index in 13:
		var angle := -PI * 0.5 + PI * float(index) / 12.0
		points.append(Vector2(rect.end.x - r, rect.position.y + r) + Vector2(cos(angle), sin(angle)) * r)
	return points
