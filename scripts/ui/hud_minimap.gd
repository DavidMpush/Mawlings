extends Control

# Minimap stage · HUD_MINIMAP. Round minimap under the swarm panel, the big map
# overlay it opens, the region label and the "new region" banner.
#
# Data: HuntWorld publishes the HUD meta "map" (12 Hz: arena, enemies, horde,
# corpses, POIs, explored chunks, region) plus "map_center"/"map_heading" every
# frame. Input stays in touch_controls.gd (_minimap_rect, _bigmap_rect,
# _map_close_rect, map_open).
#
# Terrain: every chunk is baked ONCE per biome into a small CPU image
# (CHUNK_PX x CHUNK_PX) from arena.map_features() - ground tint, trails/glow
# channels, pools/lava, stones, landmarks - by stamping cached anti-aliased disc
# brushes with Image.blend_rect (native). The minimap shows a 5 x 5 chunk window
# texture (recomposed only when the swarm enters another chunk or a chunk
# finishes baking) through one textured circle polygon; the big map composes
# the explored chunks of its view into one texture plus a soft fog texture.
# At most BAKES_PER_FRAME chunks are baked per frame.
#
# Dynamic markers are collected at DOT_HZ into preallocated arrays; between two
# collections the dot layer only shifts by the swarm's movement (no repaint).

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const UiLayer := preload("res://scripts/ui/ui_layer.gd")
const UiFrames := preload("res://scripts/ui/ui_frames.gd")
const UiIcons := preload("res://scripts/ui/ui_icons.gd")
const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")
const Biomes := preload("res://scripts/biomes.gd")
const RegionNames := preload("res://scripts/region_names.gd")

const CELL := 28.0                 # arena.gd CELL
const REGION_CHUNKS := 3           # arena.gd REGION
const CHUNK_PX := 48
const TEXEL := 48.0 / 28.0         # texels per metre
const WINDOW := 2                  # minimap window: centre chunk +- 2
const WINDOW_CHUNKS := 5
const RADIUS_M := 50.0             # world radius shown by the minimap
const MAP_FILL := 0.83             # map disc radius / frame radius
# Skin brawl (stage 15): the plaque is drawn smaller inside the tap rect of
# touch_controls (same centre, so taps and tests keep working).
const BRAWL_SCALE := 0.8
const DOT_HZ := 12.0
const BIG_HZ := 10.0
const BIG_SCALE := 2.1             # big map px per metre (fixed zoom)
const BIG_REBUILD_GAP := 1.0
const BIG_MARGIN := 2              # composite margin (chunks) around the view
const BAKE_BUDGET_USEC := 600      # bake work per frame (one step may overrun it)
const IMAGE_LIMIT := 1500          # ~9 KB each; far chunks are dropped first
const KEEP_CHUNKS := 14            # eviction keeps images within this chunk distance
const BANNER_SECONDS := 2.0
const ARRIVAL_HOLD := 3.2
const CIRCLE_POINTS := 48
const HORDE_BIN := 8.0
const FOG_PX := 6                  # fog texels per chunk (soft edges when filtered)

# Marker kinds (tests read them through markers()).
enum Mark { PREY, HUNTER, ELITE, SKITTER, LEAPER, CORPSE, CORPSE_BIG, CORPSE_BOSS, ALPHA, NEST, TOTEM, PORTAL, BOSS, APEX, HORDE }

# Marker colours repeat the in-world creature/objective colours (as hud_top's chips).
const PREY_COLOR := Color("8ff7ea")
const HUNTER_COLOR := UiStyle.VIOLET
const SKITTER_COLOR := Color("e46ad0")
const LEAPER_COLOR := Color("3fa89e")
const HORDE_COLOR := Color("d8283a")
const TOTEM_COLOR := Color("ff4a8a")
const PORTAL_COLOR := Color("ff9ccf")
const APEX_COLOR := Color("b8e86a")
const FRAME_ACCENT := Color("d8c890")
const POI_KEYS := [["nest", Mark.NEST], ["totem", Mark.TOTEM], ["portal", Mark.PORTAL], ["boss", Mark.BOSS], ["apex", Mark.APEX]]

var _time := 0.0
var _state: Dictionary = {}
var _arena: Node
var _seed := 0
var _center := Vector3.ZERO
var _heading := Vector2(0.0, -1.0)
var _biome := 0

# Geometry (base pixels), from touch_controls' rects.
var _frame := Rect2()
var _disc_c := Vector2.ZERO
var _disc_r := 70.0
var _scale := 1.4

# Chunk images: Vector3i(x, z, biome) -> Image; bake queue (front = urgent).
var _images: Dictionary = {}
var _queue: Array[Vector3i] = []
var _queued: Dictionary = {}
var _brushes: Dictionary = {}
var _palettes: Dictionary = {}
var bakes := 0                     # chunks baked so far (tests, perf notes)
var _stage := 0                    # bake step of the queue head (0-24 landmarks, 25-33 trails, 34-42 stones, 43 paint)
var _sync_fill := false            # first window after a new world: bake it at once
## CPU microseconds spent in _process and the painters (perf probes read it).
var cost_usec := 0

# Minimap window.
var _win_img: Image
var _win_tex: ImageTexture
var _win_center := Vector2i(1 << 30, 0)
var _win_biome := -1
var _poly := PackedVector2Array()
var _uvs := PackedVector2Array()
var _unit := PackedVector2Array()
var _white := PackedColorArray([Color.WHITE])
var _terrain_key := 0

# Markers (minimap px relative to the disc centre at the snapshot _dots_center).
var _mk_kind := PackedInt32Array()
var _mk_pos := PackedVector2Array()
var _mk_edge := PackedByteArray()
var _horde_bins := PackedInt32Array()
var _dots_center := Vector3.ZERO
var _dots_clock := 0.0

# Big map.
var _big_img: Image
var _big_tex: ImageTexture
var _fog_img: Image
var _fog_tex: ImageTexture
var _big_lo := Vector2i(1 << 30, 0)
var _big_hi := Vector2i(-(1 << 30), 0)
var _big_snap := Vector3.ZERO
var _big_dots_snap := Vector3.ZERO
var _big_origin := Vector2.ZERO
var _big_dirty := true
var _big_rebuilt_at := -100.0
var _big_version := -1
var _big_labels: Array = []
var _big_clock := 0.0
var _was_open := false
var _mist: Dictionary = {}

# Banner.
var _entries_seen := -1
var _arrivals_seen := -1
var _hold := 0.0
var _banner_pending := false
var _banner_t := -1.0
var _banner_name := ""
var _banner_phrase := ""

# Layers (draw order).
var _back: Control
var _terrain: Control
var _dots: Control
var _top: Control
var _self_layer: Control
var _label: Control
var _banner: Control
var _big: Control
var _big_static: Control
var _big_clip: Control
var _big_terrain: Control
var _big_labels_layer: Control
var _big_dots: Control
var _big_self: Control
var _dot_tex: ImageTexture
var _self_key := 0
var _label_key := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index in CIRCLE_POINTS:
		var angle := TAU * float(index) / float(CIRCLE_POINTS)
		_unit.append(Vector2(cos(angle), sin(angle)))
	_poly.resize(CIRCLE_POINTS)
	_uvs.resize(CIRCLE_POINTS)
	_back = UiLayer.make(self, "MapBack", _paint_back, true)
	_terrain = _live("MapTerrain", _paint_terrain)
	_terrain.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_dots = _live("MapDots", _paint_dots)
	_top = UiLayer.make(self, "MapFrame", _paint_top, true)
	_self_layer = _live("MapSelf", _paint_self)
	_label = UiLayer.make(self, "MapLabel", _paint_label, true)
	_banner = _live("MapBanner", _paint_banner)
	_make_big()
	_banner.visible = false
	_dot_tex = _make_dot()


func _live(layer_name: String, painter: Callable, parent: Node = null) -> Control:
	var layer := Control.new()
	layer.name = layer_name
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else self).add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.draw.connect(func() -> void:
		var started := Time.get_ticks_usec()
		painter.call(layer)
		cost_usec += Time.get_ticks_usec() - started)
	return layer


# ------------------------------------------------------------------ frame step

func _process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	_step(delta)
	cost_usec += Time.get_ticks_usec() - started


func _step(delta: float) -> void:
	var hud := get_parent()
	if hud == null or not hud.has_meta("map"):
		return
	var real_delta := delta / maxf(0.01, Engine.time_scale)
	_time += real_delta
	_state = hud.get_meta("map")
	_center = hud.get_meta("map_center", _state.get("center", Vector3.ZERO))
	_heading = hud.get_meta("map_heading", _heading)
	_bind_arena(_state.get("arena"))
	_biome = maxi(0, Biomes.ORDER.find(String(_state.get("biome_id", Biomes.DEFAULT))))
	_layout(hud)
	var extinct := bool(hud.get("extinct"))
	visible = not extinct
	if extinct:
		return
	var hidden: bool = bool(hud.get("paused")) or (hud.has_method("_choosing") and bool(hud._choosing()))
	var open: bool = bool(hud.get("map_open")) and not hidden
	if open:
		_sync_fill = false
	_step_bakes()
	_step_banner(real_delta)
	for layer in [_back, _terrain, _dots, _top, _self_layer, _label]:
		layer.visible = not open
	_big.visible = open
	if open:
		_step_big(real_delta, not _was_open)
	_was_open = open
	if open:
		return
	# Minimap: terrain follows the swarm every frame (one polygon), markers at DOT_HZ.
	_ensure_window()
	if _sync_fill:
		# New world (run start, other seed): the first window is baked at once,
		# like the arena builds its first chunks; later chunks bake in the budget.
		_step_bakes()
		_sync_fill = false
	_back.refresh(_frame)
	_top.refresh([_frame, UiStyle.skin])
	var key := hash(Vector3i(roundi(_center.x * 8.0), roundi(_center.z * 8.0), _win_center.x * 7919 + _win_center.y)) ^ bakes
	if key != _terrain_key:
		_terrain_key = key
		_terrain.queue_redraw()
	_dots_clock -= real_delta
	if _dots_clock <= 0.0:
		_dots_clock = 1.0 / DOT_HZ
		_collect_markers()
		_dots.position = Vector2.ZERO
		_dots.queue_redraw()
	else:
		_dots.position = -Vector2(_center.x - _dots_center.x, _center.z - _dots_center.z) * _scale
	var tip := _tip_active(hud)
	var self_key := int(round(atan2(_heading.y, _heading.x) * 36.0 / PI)) + (int(_time * 30.0) * 1000 if tip else 0)
	if self_key != _self_key:
		_self_key = self_key
		_self_layer.queue_redraw()
	var label := String(_state.get("region", ""))
	if label != _label_key:
		_label_key = label
		_label.invalidate()
	_label.refresh([label, _frame, UiStyle.skin])


func _layout(hud: Node) -> void:
	var rect: Rect2 = hud._minimap_rect() if hud.has_method("_minimap_rect") else Rect2(16, 130, 184, 184)
	if rect == _frame:
		return
	_frame = rect
	_disc_c = rect.get_center()
	_disc_r = _frame_radius() * MAP_FILL
	_scale = _disc_r / RADIUS_M
	_horde_bins.resize(int(ceil(_disc_r * 2.0 / HORDE_BIN)) * int(ceil(_disc_r * 2.0 / HORDE_BIN)))
	_terrain_key = 0


# Radius of the drawn minimap plaque (brawl: smaller than the tap rect).
func _frame_radius() -> float:
	return _frame.size.x * 0.5 * (BRAWL_SCALE if UiStyle.is_brawl() else 1.0)


func _bind_arena(value: Variant) -> void:
	var arena: Node = value if value is Node and is_instance_valid(value) else null
	var seed_value := int(arena.get("world_seed")) if arena != null else 0
	if arena == _arena and seed_value == _seed:
		return
	_arena = arena
	_seed = seed_value
	# A new seed is a new world: every baked chunk is stale.
	_images.clear()
	_queue.clear()
	_queued.clear()
	_win_center = Vector2i(1 << 30, 0)
	_big_dirty = true
	_stage = 0
	_sync_fill = _arena != null


func _tip_active(hud: Node) -> bool:
	var icon: Variant = hud.get("tutorial_icon") if "tutorial_icon" in hud else hud.get_meta("tutorial_icon", "")
	return String(icon) == "map"


# ------------------------------------------------------------------ geometry

## Minimap position (base px) of a world point, using the current centre.
func world_to_minimap(world: Vector3) -> Vector2:
	return _disc_c + Vector2(world.x - _center.x, world.z - _center.z) * _scale


func minimap_radius() -> float:
	return _disc_r


## Markers of the last collection: [[kind, minimap px, on_edge], ...].
func markers() -> Array:
	var result := []
	for index in _mk_kind.size():
		result.append([_mk_kind[index], _disc_c + _mk_pos[index], _mk_edge[index] == 1])
	return result


# ------------------------------------------------------------------ baking

func _palette(biome: int) -> Dictionary:
	if _palettes.has(biome):
		return _palettes[biome]
	var id: String = Biomes.ORDER[biome] if biome >= 0 and biome < Biomes.ORDER.size() else Biomes.DEFAULT
	var data: Dictionary = Biomes.get_data(id)
	var p := {}
	if data.has("ember"):
		var look: Dictionary = data.ember
		p.ground = (look.ground_dark as Color).lerp(look.ground_light, 0.2)
		p.edge = (look.crust_rim as Color).lightened(0.22)
		p.path = look.crust
		p.core = look.core
		p.shore = look.lava_crust
		p.pool = look.lava_mid
		p.pool_core = look.lava_core
		p.rock_line = Color("120d0f")
		p.rock = Color("2e262a")
		p.rock_light = Color("5d4c50")
		p.wood = Color("2a201f")
		p.wood_light = look.char_rim
		p.plinth = data.plinth
		p.meadow = (data.moss[2] as Color)
		p.flower = look.mushroom_light
		p.fog = Color("100b0e")
		p.ember = true
	else:
		p.ground = (data.ground as Color).darkened(0.1)
		p.edge = data.path_edge
		p.path = (data.path as Color).lightened(0.05)
		p.core = Color(0, 0, 0, 0)
		p.shore = data.shore
		p.pool = data.pool
		p.pool_core = (data.pool as Color).lightened(0.3)
		p.rock_line = Color("27302a")
		p.rock = Color("707b6c")
		p.rock_light = Color("adb7a0")
		p.wood = Color("684630")
		p.wood_light = Color("a27a50")
		p.plinth = data.plinth
		p.meadow = (data.moss[0] as Color).lightened(0.14)
		p.flower = data.flower_light
		p.fog = Color("0a1511")
		p.ember = false
	_palettes[biome] = p
	return p


# Cached image of a chunk in a biome, or null (then queued for baking).
func _chunk_image(key: Vector2i, biome: int, urgent: bool) -> Image:
	var id := Vector3i(key.x, key.y, biome)
	var image: Variant = _images.get(id)
	if image != null:
		return image
	if not _queued.has(id):
		_queued[id] = true
		if urgent:
			_queue.push_front(id)
		else:
			_queue.append(id)
	elif urgent:
		_queue.erase(id)
		_queue.push_front(id)
	return null


func _step_bakes() -> void:
	if _arena == null or not _arena.has_method("map_features"):
		return
	var started := Time.get_ticks_usec()
	while not _queue.is_empty() and (_sync_fill or Time.get_ticks_usec() - started < BAKE_BUDGET_USEC):
		var id: Vector3i = _queue[0]
		if _images.has(id):
			_queue.pop_front()
			_queued.erase(id)
			continue
		# The first look at a far chunk makes the arena compute its layout
		# (landmarks of the 5 x 5 area, trail edges and stones of the 3 x 3
		# neighbourhood: several ms in total). Those arena caches are warmed in
		# small steps inside the frame budget (a cached step costs nothing),
		# then the chunk is painted (~0.4 ms).
		var key := Vector2i(id.x, id.y)
		if _stage < 25:
			_arena.landmark(key + Vector2i(_stage % 5 - 2, _stage / 5 - 2))
			_stage += 1
			continue
		if _stage < 34:
			var near := key + Vector2i((_stage - 25) % 3 - 1, (_stage - 25) / 3 - 1)
			_arena.trail_clearance(Vector3((near.x + 0.5) * CELL, 0.0, (near.y + 0.5) * CELL))
			_stage += 1
			continue
		if _stage < 43:
			_arena.obstacles(key + Vector2i((_stage - 34) % 3 - 1, (_stage - 34) / 3 - 1))
			_stage += 1
			continue
		_stage = 0
		_queue.pop_front()
		_queued.erase(id)
		if _images.size() >= IMAGE_LIMIT:
			_evict_far()
		var image := bake_chunk(Vector2i(id.x, id.y), id.z)
		_images[id] = image
		bakes += 1
		# Drop the fresh chunk straight into the open windows.
		if id.z == _win_biome and _win_img != null:
			var offset := Vector2i(id.x, id.y) - (_win_center - Vector2i(WINDOW, WINDOW))
			if offset.x >= 0 and offset.y >= 0 and offset.x < WINDOW_CHUNKS and offset.y < WINDOW_CHUNKS:
				_win_img.blit_rect(image, Rect2i(0, 0, CHUNK_PX, CHUNK_PX), offset * CHUNK_PX)
				_win_tex.update(_win_img)
		if id.x >= _big_lo.x and id.y >= _big_lo.y and id.x <= _big_hi.x and id.y <= _big_hi.y:
			_big_dirty = true


# Drops cached chunk images far from the swarm (they re-bake if seen again).
func _evict_far() -> void:
	var here := Vector2i(floori(_center.x / CELL), floori(_center.z / CELL))
	for id: Vector3i in _images.keys():
		if maxi(absi(id.x - here.x), absi(id.y - here.y)) > KEEP_CHUNKS:
			_images.erase(id)
	if _images.size() >= IMAGE_LIMIT:
		_images.clear()
		_win_center = Vector2i(1 << 30, 0)


## Paints one chunk (world data of the arena, colours of `biome`) into a new image.
func bake_chunk(key: Vector2i, biome: int) -> Image:
	var pal := _palette(biome)
	var ground: Color = pal.ground
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	for cx in 2:
		for cz in 2:
			var shift: Vector2 = _arena.map_tint((key.x + cx) * CELL, (key.y + cz) * CELL)
			image.set_pixel(cx, cz, Color.from_hsv(ground.h + shift.x, ground.s, clampf(ground.v * (1.0 + shift.y), 0.0, 1.0)))
	image.resize(CHUNK_PX, CHUNK_PX, Image.INTERPOLATE_BILINEAR)
	var features: Dictionary = _arena.map_features(key)
	var origin := Vector2(key.x * CELL, key.y * CELL)
	# Every second centreline sample is enough: discs of >= 3 m spaced <= 2.4 m.
	var trails: Array = features.trails
	for index in range(0, trails.size(), 2):
		var sample: Vector4 = trails[index]
		_stamp(image, pal.edge, (Vector2(sample.x, sample.z) - origin) * TEXEL, (sample.w + 0.9) * TEXEL)
	for index in range(0, trails.size(), 2):
		var sample: Vector4 = trails[index]
		_stamp(image, pal.path, (Vector2(sample.x, sample.z) - origin) * TEXEL, sample.w * TEXEL)
	if bool(pal.ember):
		for sample: Vector4 in trails:
			_stamp(image, pal.core, (Vector2(sample.x, sample.z) - origin) * TEXEL, 0.75 * TEXEL)
	for pool: Vector4 in features.pools:
		var at := (Vector2(pool.x, pool.y) - origin) * TEXEL
		_stamp(image, pal.shore, at, pool.z * 1.35 * TEXEL, pool.w * 1.35 * TEXEL)
		_stamp(image, pal.pool, at, pool.z * TEXEL, pool.w * TEXEL)
		_stamp(image, pal.pool_core, at + Vector2(-0.25, -0.25) * pool.w * TEXEL, pool.z * 0.45 * TEXEL, pool.w * 0.4 * TEXEL)
	for mark: Dictionary in features.marks:
		_bake_mark(image, pal, mark, origin)
	for stone: Vector4 in features.stones:
		var at := (Vector2(stone.x, stone.z) - origin) * TEXEL
		_stamp(image, pal.rock_line, at + Vector2(0.3, 0.4), (stone.w + 0.35) * TEXEL)
		_stamp(image, pal.rock, at, stone.w * TEXEL)
		_stamp(image, pal.rock_light, at - Vector2(0.3, 0.35) * stone.w * TEXEL, stone.w * 0.45 * TEXEL)
	return image


func _bake_mark(image: Image, pal: Dictionary, mark: Dictionary, origin: Vector2) -> void:
	var center_3d: Vector3 = mark.center
	var center := (Vector2(center_3d.x, center_3d.z) - origin) * TEXEL
	var circles: Array = mark.get("circles", [])
	var ember := bool(pal.ember)
	match int(mark.type):
		0:   # root arch: two feet joined by the arch body (charred in the Glutsumpf)
			if circles.size() >= 2:
				var a := (Vector2(circles[0].x, circles[0].z) - origin) * TEXEL
				var b := (Vector2(circles[1].x, circles[1].z) - origin) * TEXEL
				_stamp(image, pal.plinth, a, 2.3 * TEXEL)
				_stamp(image, pal.plinth, b, 2.3 * TEXEL)
				_line(image, pal.rock_line, a, b, 1.25 * TEXEL)
				_line(image, pal.wood, a, b, 0.95 * TEXEL)
				_line(image, pal.wood_light, a, b, 0.35 * TEXEL)
				_stamp(image, pal.wood, a, 1.5 * TEXEL)
				_stamp(image, pal.wood, b, 1.5 * TEXEL)
		1:   # fallen log (Glutsumpf: three extinct stumps on the same knots)
			if circles.size() >= 3:
				var first := (Vector2(circles[0].x, circles[0].z) - origin) * TEXEL
				var last := (Vector2(circles[circles.size() - 1].x, circles[circles.size() - 1].z) - origin) * TEXEL
				var along := (last - first).normalized() * 0.9 * TEXEL
				_line(image, pal.plinth, first - along * 1.6, last + along * 1.6, 1.9 * TEXEL)
				if ember:
					for index in circles.size():
						var knot := (Vector2(circles[index].x, circles[index].z) - origin) * TEXEL
						var radius := (1.9 if index == 1 else 1.6) * TEXEL
						_stamp(image, pal.rock_line, knot, radius + 0.6)
						_stamp(image, pal.wood, knot, radius)
						_stamp(image, pal.wood_light, knot, 0.45 * TEXEL)
				else:
					_line(image, pal.rock_line, first - along, last + along, 1.25 * TEXEL)
					_line(image, pal.wood, first - along, last + along, 0.95 * TEXEL)
					_line(image, pal.wood_light, first - along, last + along, 0.35 * TEXEL)
		3:   # meadow: a light clearing with flowers (Glutsumpf: cold Glutpilze)
			_stamp(image, pal.meadow, center, 4.4 * TEXEL, 3.8 * TEXEL)
			var yaw := float(mark.get("yaw", 0.0))
			for index in 7:
				var angle := float(index) * 2.39996 + yaw
				var distance := 1.0 + 3.4 * sqrt((float(index) + 0.5) / 7.0)
				_stamp(image, pal.flower, center + Vector2(cos(angle) * distance, sin(angle) * distance * 0.85) * TEXEL, 0.6 * TEXEL)
		_:
			pass   # pond: already in the pool list


func _line(image: Image, color: Color, a: Vector2, b: Vector2, radius: float) -> void:
	var steps := maxi(1, ceili(a.distance_to(b) / maxf(0.6, radius * 0.7)))
	for step in steps + 1:
		_stamp(image, color, a.lerp(b, float(step) / float(steps)), radius)


# Blends a cached anti-aliased disc/ellipse brush centred at `at` (texels).
func _stamp(image: Image, color: Color, at: Vector2, rx: float, rz: float = -1.0) -> void:
	if rz < 0.0:
		rz = rx
	var brush := _brush(color, rx, rz)
	var extent := brush.get_size()
	image.blend_rect(brush, Rect2i(Vector2i.ZERO, extent), Vector2i(roundi(at.x - extent.x * 0.5), roundi(at.y - extent.y * 0.5)))


func _brush(color: Color, rx: float, rz: float) -> Image:
	var qx := maxi(1, roundi(rx * 4.0))
	var qz := maxi(1, roundi(rz * 4.0))
	var id := Vector4i(color.to_rgba32(), qx, qz, 0)
	var cached: Variant = _brushes.get(id)
	if cached != null:
		return cached
	var radius := Vector2(qx, qz) / 4.0
	var w := int(ceil(radius.x * 2.0)) + 2
	var h := int(ceil(radius.y * 2.0)) + 2
	w += w % 2
	h += h % 2
	var brush := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var small := minf(radius.x, radius.y)
	for y in h:
		for x in w:
			var d := Vector2((x + 0.5 - w * 0.5) / radius.x, (y + 0.5 - h * 0.5) / radius.y)
			var alpha := clampf(0.5 - (d.length() - 1.0) * small, 0.0, 1.0)
			brush.set_pixel(x, y, Color(color.r, color.g, color.b, color.a * alpha))
	_brushes[id] = brush
	return brush


# ------------------------------------------------------------------ minimap window

func _ensure_window() -> void:
	if _arena == null:
		return
	var center: Vector2i = Vector2i(floori(_center.x / CELL), floori(_center.z / CELL))
	if center == _win_center and _biome == _win_biome and _win_img != null:
		return
	_win_center = center
	_win_biome = _biome
	var px := WINDOW_CHUNKS * CHUNK_PX
	if _win_img == null:
		_win_img = Image.create(px, px, false, Image.FORMAT_RGBA8)
	_win_img.fill(_palette(_biome).ground)
	# Missing chunks go to the front of the bake queue, centre first, then the
	# rings outwards.
	var missing: Array[Vector3i] = []
	for ring in WINDOW + 1:
		for dx in range(-ring, ring + 1):
			for dz in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var id := Vector3i(center.x + dx, center.y + dz, _biome)
				var image: Variant = _images.get(id)
				if image != null:
					_win_img.blit_rect(image, Rect2i(0, 0, CHUNK_PX, CHUNK_PX), Vector2i(dx + WINDOW, dz + WINDOW) * CHUNK_PX)
				else:
					missing.append(id)
	for index in range(missing.size() - 1, -1, -1):
		var id: Vector3i = missing[index]
		if _queued.has(id):
			_queue.erase(id)
		_queued[id] = true
		_queue.push_front(id)
	if _win_tex == null:
		_win_tex = ImageTexture.create_from_image(_win_img)
	else:
		_win_tex.update(_win_img)
	_terrain_key = 0


# ------------------------------------------------------------------ markers

func _collect_markers() -> void:
	_dots_center = _center
	_mk_kind.resize(0)
	_mk_pos.resize(0)
	_mk_edge.resize(0)
	var inner := _disc_r - 3.0
	# Horde: density bins instead of single points.
	_horde_bins.fill(0)
	var side := int(ceil(_disc_r * 2.0 / HORDE_BIN))
	var horde: PackedVector3Array = _state.get("horde", PackedVector3Array())
	for point in horde:
		var p := Vector2(point.x - _center.x, point.z - _center.z) * _scale
		if p.length_squared() > inner * inner:
			continue
		var bx := clampi(int((p.x + _disc_r) / HORDE_BIN), 0, side - 1)
		var by := clampi(int((p.y + _disc_r) / HORDE_BIN), 0, side - 1)
		_horde_bins[by * side + bx] += 1
	var corpses: PackedFloat32Array = _state.get("corpses", PackedFloat32Array())
	var nearest_corpse := Vector2.INF
	for index in range(0, corpses.size() - 2, 3):
		var p := Vector2(corpses[index] - _center.x, corpses[index + 1] - _center.z) * _scale
		var kind := Mark.CORPSE + int(corpses[index + 2])
		if p.length_squared() <= inner * inner:
			_add(kind, p, false)
		elif not nearest_corpse.is_finite() or p.length_squared() < nearest_corpse.length_squared():
			nearest_corpse = p
	# The nearest corpse outside the disc gets a rim arrow when none is inside.
	if nearest_corpse.is_finite() and not _mk_kind.has(Mark.CORPSE) and not _mk_kind.has(Mark.CORPSE_BIG) and not _mk_kind.has(Mark.CORPSE_BOSS):
		_add(Mark.CORPSE, nearest_corpse.normalized() * (_disc_r - 7.0), true)
	var enemies: PackedFloat32Array = _state.get("enemies", PackedFloat32Array())
	for index in range(0, enemies.size() - 2, 3):
		var p := Vector2(enemies[index] - _center.x, enemies[index + 1] - _center.z) * _scale
		if p.length_squared() <= inner * inner:
			_add(int(enemies[index + 2]), p, false)
	var cores: PackedVector3Array = _state.get("alpha", PackedVector3Array())
	for point in cores:
		_add_poi(Mark.ALPHA, point)
	for pair in POI_KEYS:
		var point: Vector3 = _state.get(pair[0], Vector3.INF)
		if point.is_finite():
			_add_poi(pair[1], point)


func _add(kind: int, p: Vector2, edge: bool) -> void:
	_mk_kind.append(kind)
	_mk_pos.append(p)
	_mk_edge.append(1 if edge else 0)


# Objectives: inside the disc as icon, outside as a rim arrow.
func _add_poi(kind: int, world: Vector3) -> void:
	var p := Vector2(world.x - _center.x, world.z - _center.z) * _scale
	var inner := _disc_r - 8.0
	if p.length_squared() <= inner * inner:
		_add(kind, p, false)
	else:
		_add(kind, p.normalized() * (_disc_r - 7.0), true)


# ------------------------------------------------------------------ minimap painters

func _paint_back(cv: CanvasItem) -> void:
	var radius := _frame_radius()
	if UiStyle.is_brawl():
		# Kit plaque: hard shadow, ink disc, dark face with a lit upper half.
		Kit.disc(cv, _disc_c + Vector2(0, UiStyle.SHADOW_Y), radius, UiStyle.BRAWL_INK_SOFT)
		Kit.disc(cv, _disc_c, radius, UiStyle.BRAWL_INK)
		Kit.disc(cv, _disc_c, radius - UiStyle.STROKE_M + 0.5, UiStyle.BRAWL_PANEL_BOTTOM)
		Kit.fade_disc(cv, _disc_c, radius - UiStyle.STROKE_M, UiStyle.BRAWL_PANEL_RIM, 0.0, 0.6)
		Kit.disc(cv, _disc_c, _disc_r + 1.0, _palette(_biome).fog)
		return
	cv.draw_circle(_disc_c + Vector2(0, 5), radius, UiStyle.color("shadow"))
	if UiStyle.is_calm():
		var tex := UiStyle.tex(UiFrames.CALM_DIR + "round_body.svg")
		if tex != null:
			var calm := Vector2.ONE * UiFrames.CALM_ROUND_TEX * radius / UiFrames.CALM_ROUND_RADIUS
			cv.draw_texture_rect(tex, Rect2(_disc_c - calm * 0.5, calm), false)
	else:
		var tex := UiStyle.tex(UiFrames.DIR + "round_body.svg")
		if tex != null:
			var area := Vector2.ONE * UiFrames.ROUND_TEX * radius / UiFrames.ROUND_RADIUS
			cv.draw_texture_rect(tex, Rect2(_disc_c - area * 0.5, area), false)
		else:
			cv.draw_circle(_disc_c, radius, UiStyle.color("panel"))
	cv.draw_circle(_disc_c, _disc_r + 1.0, _palette(_biome).fog)


func _paint_terrain(cv: CanvasItem) -> void:
	if _win_tex == null:
		return
	var origin := Vector2((_win_center.x - WINDOW) * CELL, (_win_center.y - WINDOW) * CELL)
	var inv := 1.0 / (WINDOW_CHUNKS * CELL)
	var here := Vector2(_center.x, _center.z)
	var reach := _disc_r / _scale
	for index in CIRCLE_POINTS:
		var d: Vector2 = _unit[index]
		_poly[index] = _disc_c + d * _disc_r
		_uvs[index] = (here + d * reach - origin) * inv
	cv.draw_polygon(_poly, _white, _uvs, _win_tex)
	# Soft inner vignette so the rim reads as depth, not as a hard cut.
	cv.draw_arc(_disc_c, _disc_r - 3.0, 0.0, TAU, CIRCLE_POINTS, Color(UiStyle.color("outline"), 0.35), 6.0, true)


func _paint_dots(cv: CanvasItem) -> void:
	var side := int(ceil(_disc_r * 2.0 / HORDE_BIN))
	for index in _horde_bins.size():
		var count := _horde_bins[index]
		if count <= 0:
			continue
		var p := _disc_c + Vector2((index % side + 0.5) * HORDE_BIN - _disc_r, (index / side + 0.5) * HORDE_BIN - _disc_r)
		var strength := clampf(float(count) / 5.0, 0.25, 1.0)
		_dot(cv, p, 4.0 + 3.0 * strength, Color(HORDE_COLOR, 0.45 + 0.5 * strength))
	for index in _mk_kind.size():
		var p := _disc_c + _mk_pos[index]
		if _mk_edge[index] == 1:
			_rim_arrow(cv, p, _mk_pos[index].normalized(), _mark_color(_mk_kind[index]), _mk_kind[index] >= Mark.PORTAL)
		else:
			_marker(cv, _mk_kind[index], p, 1.0)


func _paint_top(cv: CanvasItem) -> void:
	var radius := _frame_radius()
	if UiStyle.is_brawl():
		# Ink seam between map and rim, outer ink contour, "N" as a small badge.
		Kit.circle_ring(cv, _disc_c, _disc_r + 2.0, UiStyle.STROKE_S, UiStyle.BRAWL_INK)
		Kit.circle_ring(cv, _disc_c, radius, UiStyle.STROKE_M, UiStyle.BRAWL_INK)
		Kit.badge(cv, _disc_c + Vector2(0, -radius + 2.0), "N", "neutral", UiStyle.T_LABEL)
		return
	var accent := FRAME_ACCENT
	if UiStyle.is_calm():
		accent = UiFrames.calm_color(UiStyle.CYAN)
		cv.draw_arc(_disc_c, _disc_r + 2.0, 0.0, TAU, 64, accent, 3.0, true)
	else:
		cv.draw_arc(_disc_c, _disc_r + 2.5, 0.0, TAU, 64, UiStyle.color("outline"), 6.0, true)
		cv.draw_arc(_disc_c, _disc_r + 2.5, 0.0, TAU, 64, accent, 3.0, true)
		var claws := UiStyle.tex(UiFrames.DIR + "round_claws.svg")
		if claws != null:
			var area := Vector2.ONE * UiFrames.ROUND_TEX * radius / UiFrames.ROUND_RADIUS
			cv.draw_texture_rect(claws, Rect2(_disc_c - area * 0.5, area), false)
	# North marker: a bone notch with an "N" on the rim (calm: small chamfered plate).
	var north := _disc_c + Vector2(0, -_disc_r - 4.0)
	if UiStyle.is_calm():
		var plate := UiFrames.chamfer_points(Rect2(north - Vector2(15, 15), Vector2(30, 30)), 7.0)
		cv.draw_colored_polygon(plate, Color(UiStyle.CALM_BG, 0.97))
		plate.append(plate[0])
		cv.draw_polyline(plate, accent, 2.0, true)
		UiStyle.text(cv, "N", north + Vector2(0, 8), UiStyle.SIZE_LABEL, UiStyle.CALM_TEXT, true, 3, UiStyle.body_font())
		return
	cv.draw_circle(north, 15.0, UiStyle.color("outline"))
	cv.draw_circle(north, 13.0, UiStyle.color("panel").darkened(0.2))
	cv.draw_arc(north, 13.0, 0.0, TAU, 24, accent, 2.0, true)
	UiStyle.text(cv, "N", north + Vector2(0, 8), UiStyle.SIZE_LABEL, UiStyle.color("bone"), true, 4, UiStyle.body_font())


func _paint_self(cv: CanvasItem) -> void:
	if _tip_active(get_parent()):
		var beat := 0.5 + 0.5 * sin(_time * 5.0)
		var ring := _frame_radius() + 8.0 + 8.0 * beat
		cv.draw_arc(_disc_c, ring, 0.0, TAU, 64, Color(UiStyle.color("outline"), 0.5), 8.0, true)
		cv.draw_arc(_disc_c, ring, 0.0, TAU, 64, Color(UiStyle.color("gold"), 0.55 + 0.4 * beat), 4.0, true)
	_swarm_arrow(cv, _disc_c, _heading, 1.0)


func _paint_label(cv: CanvasItem) -> void:
	var text := String(_state.get("region", ""))
	# Brawl: no permanent name plate; the region name appears only in the
	# short banner on a region change (and on the big map).
	if text == "" or UiStyle.is_brawl():
		return
	var font := UiStyle.body_font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.SIZE_LABEL).x
	var w := maxf(width + 30.0, 90.0)
	var rect := Rect2(_disc_c.x - w * 0.5, _frame.end.y + 2.0, w, 36.0)
	if UiStyle.is_calm():
		# V2 name plate: quiet petrol chip, stroke in the frame teal, light text.
		UiFrames.pill(cv, rect, Color(UiStyle.CALM_EDGE.lightened(0.25), 1.0))
		UiStyle.text(cv, text, Vector2(rect.get_center().x, rect.position.y + 26.0), UiStyle.SIZE_LABEL, UiStyle.CALM_TEXT, true, 4, font)
		return
	UiFrames.pill(cv, rect, FRAME_ACCENT)
	UiStyle.text(cv, text, Vector2(rect.get_center().x, rect.position.y + 26.0), UiStyle.SIZE_LABEL, UiStyle.color("bone"), true, 5, font)


# ------------------------------------------------------------------ markers (shared)

func _mark_color(kind: int) -> Color:
	match kind:
		Mark.PREY:
			return PREY_COLOR
		Mark.HUNTER, Mark.ELITE:
			return HUNTER_COLOR
		Mark.SKITTER:
			return SKITTER_COLOR
		Mark.LEAPER:
			return LEAPER_COLOR
		Mark.CORPSE, Mark.CORPSE_BIG:
			return UiStyle.color("amber")
		Mark.CORPSE_BOSS:
			return UiStyle.color("gold")
		Mark.ALPHA:
			return UiStyle.color("violet")
		Mark.NEST:
			return UiStyle.color("cyan")
		Mark.TOTEM:
			return TOTEM_COLOR
		Mark.PORTAL:
			return PORTAL_COLOR
		Mark.BOSS:
			return UiStyle.color("gold")
		Mark.APEX:
			return APEX_COLOR
		Mark.HORDE:
			return HORDE_COLOR
	return UiStyle.color("text")


# One marker; k scales it (big map, legend).
func _marker(cv: CanvasItem, kind: int, p: Vector2, k: float) -> void:
	var color := _mark_color(kind)
	match kind:
		Mark.PREY:
			_dot(cv, p, 3.4 * k, color)
		Mark.HUNTER, Mark.SKITTER, Mark.LEAPER:
			_dot(cv, p, 4.5 * k, color)
		Mark.ELITE:
			_dot(cv, p, 6.0 * k, UiStyle.color("gold"))
			_dot(cv, p, 3.8 * k, color)
		Mark.CORPSE:
			_drop(cv, p, 3.0 * k, color)
		Mark.CORPSE_BIG:
			_drop(cv, p, 4.2 * k, color)
		Mark.CORPSE_BOSS:
			_dot(cv, p, 8.0 * k, Color(UiStyle.color("gold"), 0.45))
			_drop(cv, p, 5.2 * k, color)
		Mark.ALPHA:
			var r := 5.5 * k
			var gem := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r * 0.75, 0), p + Vector2(0, r), p + Vector2(-r * 0.75, 0)])
			cv.draw_colored_polygon(gem, UiStyle.color("violet"))
			cv.draw_polyline(_closed(gem), UiStyle.color("outline"), 1.6 * k, true)
			cv.draw_circle(p, 1.8 * k, UiStyle.color("amber"))
		Mark.PORTAL:
			var beat := 0.5 + 0.5 * sin(_time * 5.0)
			cv.draw_circle(p, 6.0 * k, Color(color, 0.25 + 0.2 * beat))
			cv.draw_arc(p, (6.0 + 3.0 * beat) * k, 0.0, TAU, 20, UiStyle.color("outline"), 3.5 * k, true)
			cv.draw_arc(p, (6.0 + 3.0 * beat) * k, 0.0, TAU, 20, color, 2.2 * k, true)
			cv.draw_circle(p, 2.5 * k, Color("3a0f2a"))
		Mark.NEST, Mark.TOTEM, Mark.BOSS, Mark.APEX:
			var size := (22.0 if kind == Mark.BOSS or kind == Mark.APEX else 18.0) * k
			cv.draw_circle(p, size * 0.62, UiStyle.color("outline"))
			cv.draw_circle(p, size * 0.54, UiStyle.color("panel").darkened(0.3))
			cv.draw_arc(p, size * 0.54, 0.0, TAU, 20, color, 2.0 * k, true)
			# V2 facility icons (painted, untinted) for nest and totem.
			var icon: String = {Mark.NEST: "nest", Mark.TOTEM: "totem", Mark.BOSS: "crown", Mark.APEX: "crown"}[kind]
			var painted := kind == Mark.NEST or kind == Mark.TOTEM
			if painted and not UiIcons.has(icon):
				icon = "brood" if kind == Mark.NEST else "skull"
			var icon_k := 0.5 if painted else 0.42
			UiIcons.draw(cv, icon, Rect2(p - Vector2.ONE * size * icon_k, Vector2.ONE * size * icon_k * 2.0), Color.WHITE if kind == Mark.NEST or (painted and icon == "totem") else color.lightened(0.2))
		Mark.HORDE:
			_dot(cv, p, 6.0 * k, Color(color, 0.85))
			_dot(cv, p + Vector2(5, 3) * k, 4.2 * k, Color(color, 0.7))


func _drop(cv: CanvasItem, p: Vector2, r: float, color: Color) -> void:
	_dot(cv, p, r + 1.2, color)


# A white disc with a dark rim (anti-aliased); tinted per marker, so every dot
# is one textured quad of the same texture (batched).
static func _make_dot() -> ImageTexture:
	var extent := 32
	var image := Image.create(extent, extent, false, Image.FORMAT_RGBA8)
	for y in extent:
		for x in extent:
			var d := Vector2(x + 0.5 - 16.0, y + 0.5 - 16.0).length()
			var alpha := clampf(15.5 - d, 0.0, 1.0)
			var rim := clampf(d - 10.5, 0.0, 1.0)
			var shade := lerpf(1.0, 0.06, rim)
			image.set_pixel(x, y, Color(shade, shade, shade, alpha))
	return ImageTexture.create_from_image(image)


func _dot(cv: CanvasItem, p: Vector2, r: float, color: Color) -> void:
	cv.draw_texture_rect(_dot_tex, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, color)


func _rim_arrow(cv: CanvasItem, p: Vector2, direction: Vector2, color: Color, big: bool) -> void:
	var size := 9.0 if big else 6.5
	var side := Vector2(-direction.y, direction.x)
	var tip := p + direction * size
	var points := PackedVector2Array([tip, p - direction * size * 0.6 + side * size, p - direction * size * 0.6 - side * size])
	cv.draw_colored_polygon(points, color)
	cv.draw_polyline(_closed(points), UiStyle.color("outline"), 2.0, true)


func _swarm_arrow(cv: CanvasItem, p: Vector2, heading: Vector2, k: float) -> void:
	var forward := heading.normalized() if heading.length_squared() > 0.0001 else Vector2(0, -1)
	var side := Vector2(-forward.y, forward.x)
	cv.draw_circle(p, 11.0 * k, Color(UiStyle.color("ember"), 0.22))
	var points := PackedVector2Array([p + forward * 10.0 * k, p - forward * 6.0 * k + side * 7.0 * k, p - forward * 2.5 * k, p - forward * 6.0 * k - side * 7.0 * k])
	cv.draw_colored_polygon(points, UiStyle.color("ember"))
	cv.draw_polyline(_closed(points), Color.WHITE, 2.0 * k, true)


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	result.append(points[0])
	return result


# ------------------------------------------------------------------ banner

func _step_banner(real_delta: float) -> void:
	var entries := int(_state.get("region_entries", 0))
	if _entries_seen < 0 or entries < _entries_seen:
		_entries_seen = entries
	elif entries != _entries_seen:
		_entries_seen = entries
		_banner_pending = true
	var arrivals := int(_state.get("arrivals", 0))
	if arrivals != _arrivals_seen:
		if _arrivals_seen >= 0 and arrivals > _arrivals_seen:
			_hold = ARRIVAL_HOLD
		_arrivals_seen = arrivals
	_hold = maxf(0.0, _hold - real_delta)
	var objectives: Dictionary = get_parent().get_meta("objectives", {})
	var migrating := float(objectives.get("migration", -1.0)) >= 0.0
	if _banner_pending and _hold <= 0.0 and not migrating:
		_banner_pending = false
		_banner_t = 0.0
		_banner_name = String(_state.get("region", ""))
		_banner_phrase = String(_state.get("region_phrase", ""))
	if _banner_t >= 0.0:
		_banner_t += real_delta
		if _banner_t > BANNER_SECONDS or _banner_name == "":
			_banner_t = -1.0
	_banner.visible = _banner_t >= 0.0 and not bool(get_parent().get("map_open"))
	if _banner.visible:
		var appear := clampf(_banner_t / 0.25, 0.0, 1.0)
		var fade := clampf((BANNER_SECONDS - _banner_t) / 0.35, 0.0, 1.0)
		_banner.modulate = Color(1, 1, 1, minf(appear, fade))
		_banner.position = Vector2(0.0, -14.0 * (1.0 - appear))
		if _banner_t - real_delta <= 0.0:
			_banner.queue_redraw()


## Seconds the region banner has been showing (-1 = hidden); tests read it.
func banner_time() -> float:
	return _banner_t


func banner_text() -> String:
	return _banner_name if _banner_phrase == "" else "%s · %s" % [_banner_name, _banner_phrase]


func _paint_banner(cv: CanvasItem) -> void:
	if _banner_t < 0.0:
		return
	var font := UiStyle.display_font()
	var body := UiStyle.body_font()
	var name_w := font.get_string_size(_banner_name, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.SIZE_HEAD).x
	var phrase_w := body.get_string_size(_banner_phrase, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.SIZE_LABEL).x if _banner_phrase != "" else 0.0
	var w := clampf(maxf(name_w, phrase_w) + (110.0 if UiStyle.is_brawl() else 80.0), 300.0, size.x - 80.0)
	var h := 92.0 if _banner_phrase != "" else 66.0
	var rect := Rect2(size.x * 0.5 - w * 0.5, _frame.end.y + 46.0, w, h)
	UiFrames.panel(cv, rect, UiStyle.color("gold"), not UiStyle.is_calm())
	var c := rect.get_center().x
	UiStyle.text(cv, _banner_name.to_upper(), Vector2(c, rect.position.y + 46.0), UiStyle.SIZE_HEAD, UiStyle.color("text"), true, 7)
	if _banner_phrase != "":
		UiStyle.text(cv, _banner_phrase, Vector2(c, rect.position.y + 78.0), UiStyle.SIZE_LABEL, UiStyle.color("bone"), true, 5, body)


# ------------------------------------------------------------------ big map
# Layers under BigMap: BigDim (one rect), BigStatic (cached UiLayer: panel,
# header, close button, legend, map frame), BigClip (clip_contents = the map
# area) with BigTerrain (explored-chunk composite + fog), BigLabels (region
# names) and BigDots (markers) - each drawn relative to the swarm position of
# its last repaint and only shifted in between - and BigSelf (swarm arrow and
# border arrows for POIs outside the view).

func _make_big() -> void:
	_big = Control.new()
	_big.name = "BigMap"
	_big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_big)
	_big.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_live("BigDim", _paint_big_dim, _big)
	_big_static = UiLayer.make(_big, "BigStatic", _paint_big_static, true)
	_big_clip = Control.new()
	_big_clip.name = "BigClip"
	_big_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_big_clip.clip_contents = true
	_big.add_child(_big_clip)
	_big_terrain = _live("BigTerrain", _paint_big_terrain, _big_clip)
	_big_terrain.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_big_labels_layer = _live("BigLabels", _paint_big_labels, _big_clip)
	_big_dots = _live("BigDots", _paint_big_dots, _big_clip)
	_big_self = _live("BigSelf", _paint_big_self, _big)
	_big.visible = false


func _big_rect() -> Rect2:
	var hud := get_parent()
	return hud._bigmap_rect() if hud != null and hud.has_method("_bigmap_rect") else Rect2(20, 130, size.x - 40, size.y - 500)


func _big_map_area() -> Rect2:
	var panel := _big_rect()
	return Rect2(panel.position + Vector2(26, 112), panel.size - Vector2(52, 112 + 130))


# Metres from the swarm to the view edge (half the map area).
func _big_half() -> Vector2:
	return _big_map_area().size * 0.5 / BIG_SCALE


func _step_big(real_delta: float, opened: bool) -> void:
	var area := _big_map_area()
	if _big_clip.position != area.position or _big_clip.size != area.size:
		_big_clip.position = area.position
		_big_clip.size = area.size
		_big_dirty = true
	var cache_area := _big_rect().grow(30.0)
	if _big_static.region != cache_area:
		_big_static.region = cache_area
		_big_static.invalidate()
	var region := String(_state.get("region", ""))
	var phrase := String(_state.get("region_phrase", ""))
	_big_static.refresh([region, phrase, int(_state.get("regions", 0)), area, UiStyle.skin])
	var version := int(_state.get("explored_version", 0))
	var half := _big_half()
	var need_lo := Vector2i(floori((_center.x - half.x) / CELL), floori((_center.z - half.y) / CELL))
	var need_hi := Vector2i(floori((_center.x + half.x) / CELL), floori((_center.z + half.y) / CELL))
	var outside := need_lo.x < _big_lo.x or need_lo.y < _big_lo.y or need_hi.x > _big_hi.x or need_hi.y > _big_hi.y
	if version != _big_version:
		_big_dirty = true
	if opened or outside or (_big_dirty and _time - _big_rebuilt_at >= BIG_REBUILD_GAP):
		# A margin of BIG_MARGIN chunks lets the view move before the next rebuild.
		_rebuild_big(need_lo - Vector2i(BIG_MARGIN, BIG_MARGIN), need_hi + Vector2i(BIG_MARGIN, BIG_MARGIN), version)
	var shift := -Vector2(_center.x - _big_snap.x, _center.z - _big_snap.z) * BIG_SCALE
	_big_terrain.position = shift
	_big_labels_layer.position = shift
	_big_clock -= real_delta
	if opened or _big_clock <= 0.0:
		_big_clock = 1.0 / BIG_HZ
		_big_dots_snap = _center
		_big_dots.position = Vector2.ZERO
		_big_dots.queue_redraw()
		_big_self.queue_redraw()
	else:
		_big_dots.position = -Vector2(_center.x - _big_dots_snap.x, _center.z - _big_dots_snap.z) * BIG_SCALE


func _rebuild_big(lo: Vector2i, hi: Vector2i, version: int) -> void:
	_big_dirty = false
	_big_rebuilt_at = _time
	_big_version = version
	_big_lo = lo
	_big_hi = hi
	_big_snap = _center
	var span := hi - lo + Vector2i.ONE
	var px := span * CHUNK_PX
	var fog_color: Color = _palette(_biome).fog
	if _big_img == null or _big_img.get_size() != px:
		_big_img = Image.create(px.x, px.y, false, Image.FORMAT_RGBA8)
		_fog_img = Image.create(span.x * FOG_PX, span.y * FOG_PX, false, Image.FORMAT_RGBA8)
		_big_tex = null
		_fog_tex = null
	_big_img.fill(fog_color)
	var mist := _mist_tiles(fog_color)
	_big_origin = Vector2(lo.x * CELL, lo.y * CELL)
	var explored: Dictionary = _state.get("explored", {})
	var regions := {}
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.y, hi.y + 1):
			var key := Vector2i(x, z)
			var cell := Vector2i(x - lo.x, z - lo.y)
			if not explored.has(key):
				var tile: Image = mist[posmod(x * 7 + z * 13, mist.size())]
				_fog_img.blit_rect(tile, Rect2i(0, 0, FOG_PX, FOG_PX), cell * FOG_PX)
				# Known ground under the fog (if already baked) keeps the fog edge soft.
				var hidden: Variant = _images.get(Vector3i(x, z, _biome))
				if hidden != null:
					_big_img.blit_rect(hidden, Rect2i(0, 0, CHUNK_PX, CHUNK_PX), cell * CHUNK_PX)
				continue
			var biome := maxi(0, Biomes.ORDER.find(String(explored[key])))
			var image := _chunk_image(key, biome, false)
			if image != null:
				_big_img.blit_rect(image, Rect2i(0, 0, CHUNK_PX, CHUNK_PX), cell * CHUNK_PX)
			else:
				_big_img.fill_rect(Rect2i(cell * CHUNK_PX, Vector2i(CHUNK_PX, CHUNK_PX)), _palette(biome).ground)
			_fog_img.fill_rect(Rect2i(cell * FOG_PX, Vector2i(FOG_PX, FOG_PX)), Color(0, 0, 0, 0))
			var region := Vector3i(floori(float(x) / REGION_CHUNKS), floori(float(z) / REGION_CHUNKS), biome)
			var entry: Array = regions.get(region, [Vector2.ZERO, 0])
			entry[0] += Vector2((x + 0.5) * CELL, (z + 0.5) * CELL)
			entry[1] += 1
			regions[region] = entry
	if _big_tex == null:
		_big_tex = ImageTexture.create_from_image(_big_img)
		_fog_tex = ImageTexture.create_from_image(_fog_img)
	else:
		_big_tex.update(_big_img)
		_fog_tex.update(_fog_img)
	# Region names: the current region first, then the most explored ones; a
	# name overlapping an earlier one is left out (no label soup).
	_big_labels.clear()
	var current: Vector2i = _state.get("region_key", Vector2i.ZERO)
	var order: Array = regions.keys()
	order.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		var a_here := a.x == current.x and a.y == current.y and a.z == _biome
		var b_here := b.x == current.x and b.y == current.y and b.z == _biome
		if a_here != b_here:
			return a_here
		return int(regions[a][1]) > int(regions[b][1]))
	var taken: Array[Rect2] = []
	var font := UiStyle.body_font()
	for region: Vector3i in order:
		var entry: Array = regions[region]
		var text := RegionNames.name_for(_seed, Vector2i(region.x, region.y), String(Biomes.ORDER[region.z]))
		var at: Vector2 = entry[0] / float(entry[1])
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.SIZE_LABEL).x
		var box := Rect2(at * BIG_SCALE - Vector2(w * 0.5 + 10.0, 24.0), Vector2(w + 20.0, 34.0))
		var free := true
		for other in taken:
			if other.intersects(box):
				free = false
				break
		if not free:
			continue
		taken.append(box)
		var here := region.x == current.x and region.y == current.y and region.z == _biome
		_big_labels.append([text, at, here])
	_big_terrain.queue_redraw()
	_big_labels_layer.queue_redraw()


# Four small mist tiles (FOG_PX square) with seeded variation; unexplored
# chunks get one each, so the filtered fog reads as soft clouds.
func _mist_tiles(fog_color: Color) -> Array:
	var key := fog_color.to_rgba32()
	if _mist.has(key):
		return _mist[key]
	var tiles := []
	var mist := fog_color.lerp(Color("5d6f66"), 0.22)
	for variant in 4:
		var tile := Image.create(FOG_PX, FOG_PX, false, Image.FORMAT_RGBA8)
		for y in FOG_PX:
			for x in FOG_PX:
				var n := _noise(variant * 97 + x, variant * 31 + y)
				tile.set_pixel(x, y, Color(fog_color.lerp(mist, n), 0.96))
		tiles.append(tile)
	_mist[key] = tiles
	return tiles


static func _noise(x: int, y: int) -> float:
	var n := x * 374761393 + y * 668265263
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 1023) / 1023.0


# Local position (map-area space) of a world point for a layer snapped at `snap`.
func _big_local(world: Vector2, snap: Vector3) -> Vector2:
	return _big_clip.size * 0.5 + (world - Vector2(snap.x, snap.z)) * BIG_SCALE


func _paint_big_dim(cv: CanvasItem) -> void:
	cv.draw_rect(Rect2(Vector2.ZERO, size), Color(UiStyle.color("dim"), 0.35))


func _paint_big_static(cv: CanvasItem) -> void:
	var panel := _big_rect()
	var area := _big_map_area()
	var hud := get_parent()
	UiFrames.panel(cv, panel, FRAME_ACCENT, true)
	var x0 := panel.position.x + 30.0
	UiStyle.text(cv, "KARTE", Vector2(x0, panel.position.y + 52.0), UiStyle.SIZE_HEAD, UiStyle.color("text"), false, 7)
	var region := String(_state.get("region", ""))
	var phrase := String(_state.get("region_phrase", ""))
	var line := region if phrase == "" else "%s %s" % [region, phrase]
	UiStyle.text(cv, line, Vector2(x0, panel.position.y + 90.0), UiStyle.SIZE_BODY, UiStyle.color("gold").lightened(0.2), false, 6, UiStyle.body_font())
	var close: Rect2 = hud._map_close_rect() if hud != null and hud.has_method("_map_close_rect") else Rect2(panel.end.x - 96, panel.position.y + 12, 84, 84)
	var counter := "REGIONEN %d" % int(_state.get("regions", 0))
	var counter_w := UiStyle.body_font().get_string_size(counter, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.SIZE_LABEL).x
	UiStyle.text(cv, counter, Vector2(close.position.x - 18.0 - counter_w, panel.position.y + 52.0), UiStyle.SIZE_LABEL, UiStyle.color("text_dim"), false, 5, UiStyle.body_font())
	UiFrames.button(cv, close.grow(-8.0), "round", false, FRAME_ACCENT)
	var cc := close.get_center()
	for pass_index in 2:
		for sign_x in [-1.0, 1.0]:
			cv.draw_line(cc + Vector2(-12.0 * sign_x, -12.0), cc + Vector2(12.0 * sign_x, 12.0), UiStyle.color("outline") if pass_index == 0 else UiStyle.color("bone"), 9.0 if pass_index == 0 else 5.0, true)
	cv.draw_rect(area.grow(3.0), UiStyle.color("outline"), false, 4.0)
	cv.draw_rect(area.grow(1.0), Color(FRAME_ACCENT, 0.6), false, 2.0)
	_paint_legend(cv, Rect2(area.position.x, area.end.y + 14.0, area.size.x, panel.end.y - area.end.y - 30.0))


func _paint_big_terrain(cv: CanvasItem) -> void:
	if _big_tex == null:
		return
	var at := _big_local(_big_origin, _big_snap)
	var extent := Vector2(_big_img.get_size()) / TEXEL * BIG_SCALE
	cv.draw_texture_rect(_big_tex, Rect2(at, extent), false)
	cv.draw_texture_rect(_fog_tex, Rect2(at, extent), false)


func _paint_big_labels(cv: CanvasItem) -> void:
	var view := Rect2(Vector2.ZERO, _big_clip.size).grow(BIG_MARGIN * CELL * BIG_SCALE)
	var body := UiStyle.body_font()
	for label: Array in _big_labels:
		var p := _big_local(label[1], _big_snap)
		if view.has_point(p):
			var here: bool = label[2]
			UiStyle.text(cv, String(label[0]), p, UiStyle.SIZE_LABEL, UiStyle.color("gold").lightened(0.3) if here else Color(UiStyle.color("text"), 0.85), true, 6, body)


func _paint_big_dots(cv: CanvasItem) -> void:
	var view := Rect2(Vector2.ZERO, _big_clip.size).grow(40.0)
	var snap := _big_dots_snap
	var horde: PackedVector3Array = _state.get("horde", PackedVector3Array())
	for index in range(0, horde.size(), 3):   # every third point is dense enough at this scale
		var p := _big_local(Vector2(horde[index].x, horde[index].z), snap)
		if view.has_point(p):
			_dot(cv, p, 5.5, Color(HORDE_COLOR, 0.7))
	var corpses: PackedFloat32Array = _state.get("corpses", PackedFloat32Array())
	for index in range(0, corpses.size() - 2, 3):
		var p := _big_local(Vector2(corpses[index], corpses[index + 1]), snap)
		if view.has_point(p):
			_marker(cv, Mark.CORPSE + int(corpses[index + 2]), p, 1.1)
	var enemies: PackedFloat32Array = _state.get("enemies", PackedFloat32Array())
	for index in range(0, enemies.size() - 2, 3):
		var p := _big_local(Vector2(enemies[index], enemies[index + 1]), snap)
		if view.has_point(p):
			_marker(cv, int(enemies[index + 2]), p, 1.1)
	var cores: PackedVector3Array = _state.get("alpha", PackedVector3Array())
	for point in cores:
		var p := _big_local(Vector2(point.x, point.z), snap)
		if view.has_point(p):
			_marker(cv, Mark.ALPHA, p, 1.3)
	for pair in POI_KEYS:
		var point: Vector3 = _state.get(pair[0], Vector3.INF)
		if point.is_finite():
			var p := _big_local(Vector2(point.x, point.z), snap)
			if view.has_point(p):
				_marker(cv, pair[1], p, 1.3)


# Swarm arrow in the middle; POIs outside the view as arrows on the map border.
func _paint_big_self(cv: CanvasItem) -> void:
	var area := _big_map_area()
	var inner := area.grow(-16.0)
	var c := area.get_center()
	var targets: Array = []
	var cores: PackedVector3Array = _state.get("alpha", PackedVector3Array())
	for point in cores:
		targets.append([Mark.ALPHA, point])
	for pair in POI_KEYS:
		var point: Vector3 = _state.get(pair[0], Vector3.INF)
		if point.is_finite():
			targets.append([pair[1], point])
	for target: Array in targets:
		var world: Vector3 = target[1]
		var p := c + Vector2(world.x - _center.x, world.z - _center.z) * BIG_SCALE
		if inner.has_point(p):
			continue
		var d := p - c
		var reach := minf((inner.size.x * 0.5) / maxf(0.001, absf(d.x)), (inner.size.y * 0.5) / maxf(0.001, absf(d.y)))
		_rim_arrow(cv, c + d * reach, d.normalized(), _mark_color(int(target[0])), true)
	_swarm_arrow(cv, c, _heading, 1.5)


const LEGEND := [
	["Schwarm", -1], ["Beute", Mark.PREY], ["Jäger", Mark.HUNTER], ["Horde", Mark.HORDE], ["Kadaver", Mark.CORPSE],
	["Alpha-Kern", Mark.ALPHA], ["Brutnest", Mark.NEST], ["Totem", Mark.TOTEM], ["Boss", Mark.BOSS], ["Schlund", Mark.PORTAL],
]


func _paint_legend(cv: CanvasItem, rect: Rect2) -> void:
	var columns := 5
	var cell := Vector2(rect.size.x / columns, minf(46.0, rect.size.y * 0.5))
	var body := UiStyle.body_font()
	for index in LEGEND.size():
		var entry: Array = LEGEND[index]
		var at := rect.position + Vector2(float(index % columns) * cell.x, float(index / columns) * cell.y)
		var icon_c := at + Vector2(16.0, cell.y * 0.5)
		if int(entry[1]) < 0:
			_swarm_arrow(cv, icon_c, Vector2(0, -1), 1.0)
		else:
			_marker(cv, int(entry[1]), icon_c, 1.7 if int(entry[1]) < Mark.NEST else 1.0)
		UiStyle.text(cv, String(entry[0]), at + Vector2(34.0, cell.y * 0.5 + 8.0), UiStyle.SIZE_LABEL, UiStyle.color("text_dim"), false, 4, body)
