extends Control

# Stage 06 · Run-Ziele HUD. HuntWorld adds this component to HUD/Controls and
# publishes its state as the HUD meta "objectives" (see HuntWorld._objective_hud):
# off-screen pointers for the Brutnest (with its fill ring) and the Fluch-Totem,
# plus a status chip while a curse is active. Input stays in touch_controls.gd.
# Stage 10 adds the Moosschlund (apex) bar above the hint banner, its and the
# Migrationsschlund's edge pointers, the victory and arrival banners and the
# migration swirl (see HuntWorld._objective_hud for the keys).

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const UiIcons := preload("res://scripts/ui/ui_icons.gd")
const Biomes := preload("res://scripts/biomes.gd")
const APEX_GREEN := Color("b8e86a")
const MIGRATION_PINK := Color("ff9ccf")
const APEX_BAR_BOTTOM := 470.0   # bar sits this far above the bottom edge (hint banner below)
const VICTORY_SECONDS := 3.2
const ARRIVAL_SECONDS := 2.8
const CURSE := Color("ff4a8a")
const MINIMAP_PLATE := 46.0             # region name plate below the minimap disc
const CHIP_Y := 392.0          # left column, below corpse and biomass hints
const POINTER_GAP := 128.0     # minimum distance between two edge markers

var _time := 0.0
var _last_key: Variant = null
# Banner clocks in real seconds (-1 = off), started when the counters grow.
var _victory_seen := 0
var _victory_time := -1.0
var _arrival_seen := 0
var _arrival_time := -1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# Stage 07: repaint only when the markers move or pulse (30 Hz) or the curse
# chip pulses (20 Hz); with nothing to show it stays empty and costs nothing.
func _process(delta: float) -> void:
	_time += delta
	var key: Array = [size]
	var state := _state()
	_step_banners(state, delta / maxf(0.01, Engine.time_scale))
	if not state.is_empty() and not _hidden():
		var markers := bool(state.get("nest_active", false)) or bool(state.get("totem_active", false)) or int(state.get("apex_state", 0)) in [1, 2] or bool(state.get("portal_active", false))
		var tick := int(_time * 30.0) if markers else (int(_time * 20.0) if int(state.get("curse", 0)) > 0 else 0)
		if _victory_time >= 0.0 or _arrival_time >= 0.0 or float(state.get("migration", -1.0)) >= 0.0:
			tick = int(_time * 60.0)
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
	# Stage 10 - apex (Moosschlund / Aschenkröte) and migration.
	var apex_state := int(state.get("apex_state", 0))
	if apex_state == 1 or apex_state == 2:
		_draw_apex_bar(state)
		var apex_at: Vector2 = state.get("apex_pointer", Vector2.INF)
		if apex_at.is_finite():
			apex_at = _separate(apex_at, taken)
			taken.append(apex_at)
			_draw_apex_pointer(apex_at, bool(state.get("apex_vulnerable", false)), state)
	if bool(state.get("portal_active", false)) and float(state.get("migration", -1.0)) < 0.0:
		var portal_at: Vector2 = state.get("portal_pointer", Vector2.INF)
		if portal_at.is_finite():
			_draw_portal_pointer(_separate(portal_at, taken), float(state.get("portal_hold", 0.0)), String(state.get("portal_target", "")))
	if _victory_time >= 0.0:
		_draw_victory(state)
	if _arrival_time >= 0.0:
		_draw_arrival(state)
	var migration := float(state.get("migration", -1.0))
	if migration >= 0.0:
		_draw_swirl(state, migration)


# Pushes a marker along the screen edge until it clears the others.
func _separate(at: Vector2, taken: Array[Vector2]) -> Vector2:
	for other in taken:
		if at.distance_to(other) < POINTER_GAP:
			var along := Vector2(0, 1) if absf(at.x - size.x * 0.5) > absf(at.y - size.y * 0.5) else Vector2(1, 0)
			var push := along * POINTER_GAP * (1.0 if along.dot(at - other) >= 0.0 else -1.0)
			at += push
	return at


func _keep_on_screen(at: Vector2, reach: float) -> Vector2:
	at = Vector2(clampf(at.x, reach, size.x - reach), clampf(at.y, reach, size.y - reach))
	# The minimap (top left) and its region name plate stay clear: a pointer
	# (medallion + label below it) that would overlap slides down along the edge.
	var hud := get_parent()
	if hud != null and bool(hud.get("minimap_enabled")) and hud.has_method("_minimap_rect"):
		var map: Rect2 = hud._minimap_rect()
		var keep_out := Rect2(map.position, map.size + Vector2(0, MINIMAP_PLATE)).grow(reach)
		if keep_out.has_point(at):
			at.y = keep_out.end.y + 4.0
	return at


func _draw_nest_pointer(at: Vector2, progress: float) -> void:
	var direction := (at - size * 0.5).normalized()
	at = _keep_on_screen(at, 70.0)
	var pulse := 0.5 + 0.5 * sin(_time * 3.2)
	var r := 44.0
	_glow_disc(at, r + 12 + 5 * pulse, Color(UiStyle.color("cyan"), 0.10 + 0.08 * pulse))
	_arrow(at, direction, r, UiStyle.color("cyan"))
	draw_circle(at + Vector2(0, 4), r, UiStyle.color("shadow"))
	draw_circle(at, r, UiStyle.color("panel"))
	draw_arc(at, r - 3, 0.0, TAU, 48, Color(UiStyle.color("cyan"), 0.35), 5.0, true)
	if progress > 0.0:
		draw_arc(at, r - 3, -PI * 0.5, -PI * 0.5 + TAU * progress, 48, UiStyle.color("cyan").lightened(0.2), 7.0, true)
	UiIcons.draw(self, "nest" if UiIcons.has("nest") else "brood", Rect2(at - Vector2(29, 29), Vector2(58, 58)), Color.WHITE)
	_label("BRUTNEST", at + Vector2(0, r + 28), UiStyle.color("cyan").lightened(0.35))


func _draw_totem_pointer(at: Vector2, hold: float) -> void:
	var direction := (at - size * 0.5).normalized()
	at = _keep_on_screen(at, 64.0)
	var pulse := 0.5 + 0.5 * sin(_time * 4.0)
	var r := 38.0
	_glow_disc(at, r + 10 + 4 * pulse, Color(CURSE, 0.10 + 0.08 * pulse))
	_arrow(at, direction, r, UiStyle.color("violet"))
	draw_circle(at + Vector2(0, 4), r, UiStyle.color("shadow"))
	draw_circle(at, r, UiStyle.color("panel"))
	draw_arc(at, r - 3, 0.0, TAU, 40, UiStyle.color("violet").lerp(CURSE, hold), 4.0, true)
	_totem_icon(Rect2(at - Vector2(28, 28), Vector2(56, 56)))
	_label("TOTEM", at + Vector2(0, r + 28), CURSE.lightened(0.45))


# Hold ring over the totem while the swarm stands on it (the swarm hides the ground ring).
func _draw_totem_hold(at: Vector2, hold: float) -> void:
	var r := 58.0
	var pulse := 0.5 + 0.5 * sin(_time * 9.0)
	at += Vector2(0, -150)
	draw_circle(at, r + 8 + 6 * pulse * hold, Color(CURSE, 0.14 + 0.12 * hold))
	draw_circle(at + Vector2(0, 4), r, UiStyle.color("shadow"))
	draw_circle(at, r, Color(UiStyle.color("panel"), 0.9))
	draw_arc(at, r - 5, 0.0, TAU, 56, Color(UiStyle.color("violet"), 0.35), 8.0, true)
	draw_arc(at, r - 5, -PI * 0.5, -PI * 0.5 + TAU * hold, 56, CURSE.lerp(Color.WHITE, 0.25 * pulse), 10.0, true)
	_totem_icon(Rect2(at - Vector2(36, 36), Vector2(72, 72)))
	_label("FLUCH ANNEHMEN", at + Vector2(0, r + 30), UiStyle.tone(Color("ffd3e4")))


## V2 Fluch-Totem icon (painted, untinted); the pink skull is the fallback.
func _totem_icon(rect: Rect2) -> void:
	if UiIcons.has("totem"):
		UiIcons.draw(self, "totem", rect, Color.WHITE)
	else:
		UiIcons.draw(self, "skull", rect.grow(-rect.size.x * 0.06), UiStyle.tone(Color("ffd3e4")))


func _draw_curse_chip(curse: int) -> void:
	var text := "FLUCH · BEUTE ×2 · BOSS +50%" if curse == 1 else "VERFLUCHTER KING · BEUTE ×2"
	var font := UiStyle.body_font()
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.SIZE_LABEL + 1).x + 66
	var rect := Rect2(16, CHIP_Y, w, 46)
	var pulse := 0.5 + 0.5 * sin(_time * 3.0)
	var points := _pill_points(rect)
	draw_colored_polygon(points, Color(UiStyle.color("panel").darkened(0.2), 0.94).lerp(CURSE, 0.10 + 0.06 * pulse))
	points.append(points[0])
	draw_polyline(points, CURSE.lerp(UiStyle.color("violet"), 0.4), 3.0, true)
	var icon_c := rect.position + Vector2(26, 23)
	_glow_disc(icon_c, 18, Color(CURSE, 0.18 + 0.14 * pulse))
	_totem_icon(Rect2(icon_c - Vector2(19, 19), Vector2(38, 38)))
	UiStyle.text(self, text, rect.position + Vector2(48, 31), UiStyle.SIZE_LABEL + 1, UiStyle.tone(Color("ffd3e4")), false, 5, font)


func _arrow(center: Vector2, direction: Vector2, r: float, color: Color) -> void:
	if direction.length_squared() < 0.01:
		return
	var side := Vector2(-direction.y, direction.x)
	var tip := center + direction * (r + 24)
	var base := center + direction * (r - 4)
	draw_colored_polygon(PackedVector2Array([tip + direction * 2 + Vector2(0, 3), base + side * 17 + Vector2(0, 3), base - side * 17 + Vector2(0, 3)]), UiStyle.color("shadow"))
	draw_colored_polygon(PackedVector2Array([tip, base + side * 16, base - side * 16]), color)


func _label(text: String, at: Vector2, color: Color) -> void:
	UiStyle.text(self, text, at, UiStyle.SIZE_LABEL + 1, color, true, 6, UiStyle.body_font())


# Soft pulsing disc behind a marker; the calm skin keeps markers flat.
func _glow_disc(at: Vector2, radius: float, color: Color) -> void:
	if not UiStyle.is_calm():
		draw_circle(at, radius, color)


func _apex_green() -> Color:
	return UiStyle.CALM_LEAF if UiStyle.is_calm() else APEX_GREEN


# Second apex: the Aschenkröte (Glutsumpf) uses glut orange instead of moss green.
func _is_toad(state: Dictionary) -> bool:
	return String(state.get("apex_kind", "apex")) == "apex_toad"


func _apex_name(state: Dictionary) -> String:
	return String(state.get("apex_name", "MOOSSCHLUND"))


## Base colour of the current apex (moss green or glut orange).
func _apex_color(state: Dictionary) -> Color:
	return UiStyle.color("ember") if _is_toad(state) else _apex_green()


# Capsule outline (organic) or the kit's chamfered chip (calm).
func _pill_points(rect: Rect2) -> PackedVector2Array:
	if UiStyle.is_calm():
		var cut := minf(14.0, rect.size.y * 0.3)
		var p := rect.position
		var e := rect.end
		return PackedVector2Array([Vector2(p.x + cut, p.y), Vector2(e.x - cut, p.y), Vector2(e.x, p.y + cut), Vector2(e.x, e.y - cut),
			Vector2(e.x - cut, e.y), Vector2(p.x + cut, e.y), Vector2(p.x, e.y - cut), Vector2(p.x, p.y + cut)])
	var points := PackedVector2Array()
	var r := rect.size.y * 0.5
	for index in 13:
		var angle := PI * 0.5 + PI * float(index) / 12.0
		points.append(Vector2(rect.position.x + r, rect.position.y + r) + Vector2(cos(angle), sin(angle)) * r)
	for index in 13:
		var angle := -PI * 0.5 + PI * float(index) / 12.0
		points.append(Vector2(rect.end.x - r, rect.position.y + r) + Vector2(cos(angle), sin(angle)) * r)
	return points


# ---------------------------------------------------------------- stage 10

func _step_banners(state: Dictionary, real_delta: float) -> void:
	var victories := int(state.get("apex_victories", 0))
	if victories > _victory_seen:
		_victory_time = 0.0
	_victory_seen = victories
	var arrivals := int(state.get("arrivals", 0))
	if arrivals > _arrival_seen:
		_arrival_time = 0.0
	_arrival_seen = arrivals
	if _victory_time >= 0.0:
		_victory_time += real_delta
		if _victory_time > VICTORY_SECONDS:
			_victory_time = -1.0
	# The arrival banner waits until the swirl has opened again.
	if _arrival_time >= 0.0 and float(state.get("migration", -1.0)) < 0.0:
		_arrival_time += real_delta
		if _arrival_time > ARRIVAL_SECONDS:
			_arrival_time = -1.0


# Apex (Moosschlund / Aschenkröte) health above the hint banner (the top boss bar belongs to the Bog
# King): name, phase tag, segmented health with the phase-2 mark at 50 %.
func _draw_apex_bar(state: Dictionary) -> void:
	var warning := int(state.get("apex_state", 0)) == 1
	var vulnerable := bool(state.get("apex_vulnerable", false))
	var phase := int(state.get("apex_phase", 1))
	var w := minf(640.0, size.x - 120.0)
	var rect := Rect2(size.x * 0.5 - w * 0.5, size.y - APEX_BAR_BOTTOM, w, 80)
	var pulse := 0.5 + 0.5 * sin(_time * (8.0 if vulnerable or warning else 3.0))
	var base := _apex_color(state)
	var phase_color := UiStyle.color("danger") if _is_toad(state) else UiStyle.color("ember")
	var accent := UiStyle.color("gold") if vulnerable else (phase_color if phase == 2 else base)
	if (vulnerable or warning) and not UiStyle.is_calm():
		draw_rect(rect.grow(6 + 4 * pulse), Color(accent, 0.12 + 0.12 * pulse))
	var points := _pill_points(rect)
	draw_colored_polygon(_offset(points, Vector2(0, 5)), UiStyle.color("shadow"))
	draw_colored_polygon(points, Color(UiStyle.color("panel").darkened(0.25), 0.95))
	points.append(points[0])
	draw_polyline(points, accent, 3.0, true)
	var icon_c := rect.position + Vector2(44, 40)
	_glow_disc(icon_c, 30, Color(accent, 0.2 + 0.1 * pulse))
	UiIcons.draw(self, "crown", Rect2(icon_c - Vector2(24, 24), Vector2(48, 48)), accent.lightened(0.2))
	var x := rect.position.x + 84
	UiStyle.text(self, _apex_name(state), Vector2(x, rect.position.y + 34), 30, UiStyle.color("text"), false, 6)
	var tag := "ERWACHT" if warning else ("ERSCHÖPFT" if vulnerable else ("PHASE 2" if phase == 2 else ""))
	if tag != "":
		var font := UiStyle.body_font()
		var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.SIZE_LABEL).x + 26
		var tag_rect := Rect2(rect.end.x - 26 - tw, rect.position.y + 10, tw, 30)
		var tag_points := _pill_points(tag_rect)
		draw_colored_polygon(tag_points, accent.darkened(0.55).lerp(accent.darkened(0.25), pulse))
		UiStyle.text(self, tag, Vector2(tag_rect.get_center().x, tag_rect.position.y + 22), UiStyle.SIZE_LABEL, Color.WHITE, true, 4, font)
	var bar := Rect2(x, rect.position.y + 46, rect.end.x - x - 30, 18)
	var share := 1.0 - float(state.get("apex_warning", 0.0)) if warning else clampf(float(state.get("apex_health", 0.0)) / maxf(1.0, float(state.get("apex_max_health", 1.0))), 0.0, 1.0)
	var segments := 16
	var gap := 3.0
	var seg_w := (bar.size.x - gap * float(segments - 1)) / float(segments)
	for index in segments:
		var seg := Rect2(bar.position.x + float(index) * (seg_w + gap), bar.position.y, seg_w, bar.size.y)
		draw_rect(seg, Color(UiStyle.color("outline"), 0.9))
		var fill := clampf(share * float(segments) - float(index), 0.0, 1.0)
		if fill > 0.0:
			var color := accent if not warning else base.lerp(Color.WHITE, 0.25 * pulse)
			draw_rect(Rect2(seg.position + Vector2(1, 1), Vector2((seg.size.x - 2) * fill, seg.size.y - 2)), color)
	if not warning:
		# Phase-2 mark: the boss roars at half health.
		var mark_x := bar.position.x + bar.size.x * 0.5
		draw_line(Vector2(mark_x, bar.position.y - 6), Vector2(mark_x, bar.end.y + 6), Color(UiStyle.color("bone"), 0.9), 3.0)


func _draw_apex_pointer(at: Vector2, vulnerable: bool, state: Dictionary) -> void:
	var direction := (at - size * 0.5).normalized()
	at = _keep_on_screen(at, 70.0)
	var accent := UiStyle.color("gold") if vulnerable else _apex_color(state)
	var pulse := 0.5 + 0.5 * sin(_time * (8.0 if vulnerable else 4.0))
	var r := 44.0
	_glow_disc(at, r + 12 + 5 * pulse, Color(accent, 0.12 + 0.1 * pulse))
	_arrow(at, direction, r, accent)
	draw_circle(at + Vector2(0, 4), r, UiStyle.color("shadow"))
	draw_circle(at, r, UiStyle.color("panel"))
	draw_arc(at, r - 3, 0.0, TAU, 48, accent, 4.0, true)
	UiIcons.draw(self, "crown", Rect2(at - Vector2(28, 28), Vector2(56, 56)), accent.lightened(0.15))
	_label("VERWUNDBAR!" if vulnerable else _apex_name(state), at + Vector2(0, (-r - 18) if direction.y > 0.6 else (r + 28)), accent.lightened(0.35))


func _draw_portal_pointer(at: Vector2, hold: float, target: String) -> void:
	var direction := (at - size * 0.5).normalized()
	at = _keep_on_screen(at, 70.0)
	var pulse := 0.5 + 0.5 * sin(_time * 3.4)
	var r := 44.0
	_glow_disc(at, r + 12 + 6 * pulse, Color(MIGRATION_PINK, 0.12 + 0.1 * pulse))
	_arrow(at, direction, r, MIGRATION_PINK)
	draw_circle(at + Vector2(0, 4), r, UiStyle.color("shadow"))
	draw_circle(at, r, UiStyle.color("panel"))
	draw_arc(at, r - 3, 0.0, TAU, 48, Color(MIGRATION_PINK, 0.45), 5.0, true)
	if hold > 0.0:
		draw_arc(at, r - 3, -PI * 0.5, -PI * 0.5 + TAU * hold, 48, Color.WHITE, 7.0, true)
	var icon := "biome_glutsumpf" if target == "GLUTSUMPF" else "biome_verdant"
	UiIcons.draw(self, icon, Rect2(at - Vector2(29, 29), Vector2(58, 58)), Color.WHITE)
	_label("MIGRATION", at + Vector2(0, (-r - 18) if direction.y > 0.6 else (r + 28)), MIGRATION_PINK.lightened(0.3))


# Gold ribbon in the apex colour: the apex is beaten, the maw opens (Main adds
# slow motion). apex_kind / apex_name keep the fallen apex until the next rises.
func _draw_victory(state: Dictionary) -> void:
	var t := _victory_time
	var tint := _apex_color(state)
	var burst := 1.0 - pow(1.0 - clampf(t / 0.3, 0.0, 1.0), 3.0)
	var fade := burst * (1.0 - clampf((t - (VICTORY_SECONDS - 0.5)) / 0.5, 0.0, 1.0))
	var flash := 1.0 - clampf(t / 0.35, 0.0, 1.0)
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(tint, 0.3 * flash))
	var scale := lerpf(1.5, 1.0, burst)
	var c := Vector2(size.x * 0.5, size.y * 0.5 - 380)
	var rect := Rect2(c - Vector2(390, 70) * scale, Vector2(780, 140) * scale)
	var points := _pill_points(rect)
	draw_colored_polygon(_offset(points, Vector2(0, 8)), Color(UiStyle.color("shadow"), 0.6 * fade))
	draw_colored_polygon(points, Color(UiStyle.color("panel").darkened(0.3), 0.94 * fade))
	points.append(points[0])
	draw_polyline(points, Color(UiStyle.color("gold"), fade), 4.0, true)
	var icon_c := c + Vector2(0, -92) * scale
	draw_circle(icon_c, 52 * scale, Color(UiStyle.color("panel"), 0.95 * fade))
	draw_arc(icon_c, 50 * scale, 0.0, TAU, 48, Color(tint, fade), 4.0, true)
	UiIcons.draw(self, "crown", Rect2(icon_c - Vector2(36, 36) * scale, Vector2(72, 72) * scale), Color(UiStyle.color("gold"), fade))
	UiStyle.text(self, "%s BEZWUNGEN" % _apex_name(state), c + Vector2(0, 8), 48, Color(1, 1, 1, fade), true, 8)
	UiStyle.text(self, "Der Migrationsschlund öffnet sich", c + Vector2(0, 50), 26, Color(tint.lightened(0.3), fade), true, 5, UiStyle.body_font())


# New biome title after the swirl opened again.
func _draw_arrival(state: Dictionary) -> void:
	var t := _arrival_time
	var fade := clampf(t / 0.3, 0.0, 1.0) * (1.0 - clampf((t - (ARRIVAL_SECONDS - 0.6)) / 0.6, 0.0, 1.0))
	var id := String(state.get("biome_id", "verdant_maw"))
	var data: Dictionary = Biomes.get_data(id)
	var accent: Color = _biome_colors(id)[1]
	var c := Vector2(size.x * 0.5, size.y * 0.5 - 360)
	var rect := Rect2(c - Vector2(330, 58), Vector2(660, 116))
	var points := _pill_points(rect)
	draw_colored_polygon(points, Color(UiStyle.color("panel").darkened(0.3), 0.9 * fade))
	points.append(points[0])
	draw_polyline(points, Color(accent, fade), 4.0, true)
	var icon_c := rect.position + Vector2(62, 58)
	UiIcons.draw(self, "biome_glutsumpf" if id == "glutsumpf" else "biome_verdant", Rect2(icon_c - Vector2(40, 40), Vector2(80, 80)), Color(1, 1, 1, fade))
	UiStyle.text(self, String(data.get("title", "")), Vector2(c.x + 40, c.y + 4), 54, Color(1, 1, 1, fade), true, 8)
	UiStyle.text(self, String(data.get("description", "")), Vector2(c.x + 40, c.y + 42), 22, Color(accent.lightened(0.35), fade), true, 5, UiStyle.body_font())


# Migration: a vortex closes around the maw (screen fully covered at the biome
# switch), then opens from the centre over the new biome. Real HUD drawing only.
func _draw_swirl(state: Dictionary, progress: float) -> void:
	var switch_at := clampf(float(state.get("migration_switch", 0.45)), 0.1, 0.9)
	var cover := 0.0
	var centre := size * 0.5
	var target := String(state.get("migration_to", "glutsumpf"))
	if progress < switch_at:
		var k := progress / switch_at
		cover = k * k * (3.0 - 2.0 * k)
		var maw: Vector2 = state.get("migration_screen", Vector2.INF)
		if maw.is_finite():
			centre = maw.lerp(size * 0.5, cover)
	else:
		var k := (progress - switch_at) / (1.0 - switch_at)
		cover = 1.0 - k * k * (3.0 - 2.0 * k)
	var colors := _biome_colors(target)
	var deep: Color = colors[0]
	var mid: Color = colors[1]
	var core: Color = colors[2]
	var reach := size.length()
	draw_rect(Rect2(Vector2.ZERO, size), Color(deep, 0.94 * cover))
	var spin := _time * 5.0 + progress * 9.0
	var arms := 6
	for arm in arms:
		var line := PackedVector2Array()
		var base := spin + TAU * float(arm) / float(arms)
		for step in 72:
			var r := reach * float(step) / 71.0 * (0.25 + 0.75 * cover)
			var angle := base + r / 140.0
			line.append(centre + Vector2(cos(angle), sin(angle)) * r)
		draw_polyline(line, Color(mid, 0.85 * cover), 26.0 * cover + 2.0, true)
		draw_polyline(line, Color(core, 0.6 * cover), 8.0 * cover + 1.0, true)
	draw_circle(centre, 180.0 * cover, Color(core, 0.5 * cover))
	draw_circle(centre, 90.0 * cover, Color(Color.WHITE, 0.55 * cover))
	if cover > 0.55:
		var alpha := (cover - 0.55) / 0.45
		UiStyle.text(self, "MIGRATION", size * 0.5 + Vector2(0, -250), 54, Color(1, 1, 1, alpha), true, 8)
		UiStyle.text(self, String(Biomes.get_data(target).get("title", "")), size * 0.5 + Vector2(0, -196), 30, Color(core.lightened(0.3), alpha), true, 6, UiStyle.body_font())


# [deep, mid, core] of a biome's vortex (same palette as migration_maw.gd).
func _biome_colors(id: String) -> Array:
	var data: Dictionary = Biomes.get_data(id)
	if data.has("ember"):
		return [UiStyle.tone(Color("2a0c22")), Color(data.ember.lava_mid), Color(data.ember.lava_core)]
	return [Color(data.ground).darkened(0.7), Color(data.pool), Color(data.pool).lightened(0.45)]


func _offset(points: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		result.append(point + by)
	return result
