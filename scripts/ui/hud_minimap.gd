extends Control

# Minimap stage · HUD_MINIMAP, stage 18 (bounded map). The minimap shows the
# WHOLE map (solo 4 x 4 regions, 336 m) in a square plaque under the swarm
# panel: baked terrain, thin region lines, the natural edge as a coloured band
# (thicket / cliff / water, Glutsumpf char / basalt / lava), fog over every
# unexplored cell, the swarm arrow at its place and the markers. The big map
# overlay it opens shows the same map larger with the names of the explored
# regions and a legend. Also the region label and the "new region" banner.
#
# Data: HuntWorld publishes the HUD meta "map" (12 Hz: arena, enemies, horde,
# crystals, POIs, region; later "chests" (Kokons) and "powerups" (Pilzknollen)
# as PackedVector3Array) plus "map_center"/"map_heading" every frame. Map size,
# regions, names and the edge come from arena.map_overview(), the fog from
# arena.explored_cells() (FOG_CELL grid). Input stays in touch_controls.gd
# (_minimap_rect, _bigmap_rect, _map_close_rect, map_open).
#
# Terrain: every map chunk is baked ONCE per map and biome into a small CPU
# image (CHUNK_PX x CHUNK_PX) from arena.map_features() - ground tint,
# trails/glow channels, pools/lava, stones, landmarks - by stamping cached
# anti-aliased disc brushes with Image.blend_rect (native), then blitted into
# one whole-map image (12 x 48 = 576 px for solo). Baking runs within a small
# per-frame budget, nearest chunks first; the texture is uploaded at most every
# UPLOAD_GAP seconds while chunks arrive. Minimap and big map draw the same
# texture; dynamic markers are collected at DOT_HZ / BIG_HZ.

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const UiLayer := preload("res://scripts/ui/ui_layer.gd")
const UiFrames := preload("res://scripts/ui/ui_frames.gd")
const UiIcons := preload("res://scripts/ui/ui_icons.gd")
const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")
const Biomes := preload("res://scripts/biomes.gd")

const CELL := 28.0                 # arena.gd CELL
const CHUNK_PX := 48
const TEXEL := 48.0 / 28.0         # texels per metre
const MAP_FILL := 0.83             # (classic skins) map square inside the disc
# Skin brawl (stage 15): the plaque is drawn smaller inside the tap rect of
# touch_controls (same centre, so taps and tests keep working).
const BRAWL_SCALE := 0.8
const DOT_HZ := 12.0
const BIG_HZ := 10.0
const BAKE_BUDGET_USEC := 600      # bake work per frame (one step may overrun it)
# Etappe 22: the quality tier may lower it ("minimap_bake_us").
var _bake_budget := int(preload("res://scripts/quality.gd").value("minimap_bake_us", BAKE_BUDGET_USEC))
const UPLOAD_GAP := 0.4            # seconds between texture uploads while baking
const BANNER_SECONDS := 2.0
const ARRIVAL_HOLD := 3.2
# Etappe 27 (S25 feedback): the region-name banner on entering a region is off;
# region names stay on the big map.
const REGION_BANNER := false
const HORDE_BIN := 6.0
const EDGE_BAND_MINI := 4.0        # px of the edge band on the minimap
const EDGE_BAND_BIG := 9.0         # px of the edge band on the big map
# Wall distance samples per chunk side (arena.gd WALL_SAMPLES, stage 18b).
const WALL_SAMPLES := 12
# Stage 18c: unexplored ground is hidden completely (minimap and big map).
const FOG_ALPHA := 1.0
# Colours of the edge band per segment kind (arena_border.gd KIND_NAMES).
const EDGE_COLORS := {
	"thicket": Color("2e5a24"), "cliff": Color("8a8a80"), "water": Color("2b8a86"),
	"char": Color("3b2a26"), "basalt": Color("4c4549"), "lava": Color("e0782c"),
}

# Marker kinds (tests read them through markers()).
# CORPSE* = loot crystal clusters (Etappe 16: small / medium / big heap), LURE = Lockruf,
# CHEST = Kokon, POWERUP = Pilzknolle (second wave; HUD meta "chests"/"powerups").
enum Mark { PREY, HUNTER, ELITE, SKITTER, LEAPER, CORPSE, CORPSE_BIG, CORPSE_BOSS, ALPHA, NEST, TOTEM, PORTAL, BOSS, APEX, HORDE, LURE, CHEST, POWERUP }
# Lockruf plate colour (scripts/loot.gd LURE_COLOR).
const LURE_COLOR := Color("ff7ad9")

# Marker colours repeat the in-world creature/objective colours (as hud_top's chips).
const PREY_COLOR := Color("8ff7ea")
const HUNTER_COLOR := UiStyle.VIOLET
const SKITTER_COLOR := Color("e46ad0")
const LEAPER_COLOR := Color("3fa89e")
const HORDE_COLOR := Color("d8283a")
const TOTEM_COLOR := Color("ff4a8a")
const PORTAL_COLOR := Color("ff9ccf")
const APEX_COLOR := Color("b8e86a")
const CHEST_COLOR := Color("ffc53a")
const POWERUP_COLOR := Color("7be35a")
const FRAME_ACCENT := Color("d8c890")
const POI_KEYS := [["nest", Mark.NEST], ["totem", Mark.TOTEM], ["portal", Mark.PORTAL], ["boss", Mark.BOSS], ["boss_site", Mark.APEX], ["apex", Mark.APEX]]
const LIST_KEYS := [["alpha", Mark.ALPHA], ["chests", Mark.CHEST], ["powerups", Mark.POWERUP]]
# Clearing types (arena.poi_slots) -> marker drawn as a quiet site symbol (18b).
# Etappe 30: no "maw" site any more - the gate stands at the boss arena and shows as "portal" once found.
const SITE_MARKS := {"boss": Mark.BOSS, "nest": Mark.NEST, "totem": Mark.TOTEM, "cocoon": Mark.CHEST, "cocoon_gold": Mark.CHEST, "grove": Mark.POWERUP, "elite": Mark.ELITE, "shrine": Mark.ALPHA}

var _time := 0.0
var _state: Dictionary = {}
var _arena: Node
var _seed := 0
var _center := Vector3.ZERO
var _heading := Vector2(0.0, -1.0)
var _biome := 0

# Map data (arena.map_overview()) and geometry.
var _overview: Dictionary = {}
var _map_key := ""
var _bounds := Rect2(-168, -168, 336, 336)
var _chunk_lo := Vector2i(-6, -6)
var _chunks := Vector2i(12, 12)

# Minimap geometry (base pixels), from touch_controls' rects.
var _frame := Rect2()
var _disc_c := Vector2.ZERO
var _map_rect := Rect2()
var _scale := 0.3

# Chunk images: Vector3i(x, z, biome) -> Image; bake queue.
var _images: Dictionary = {}
var _queue: Array[Vector3i] = []
var _queued: Dictionary = {}
var _brushes: Dictionary = {}
var _palettes: Dictionary = {}
var bakes := 0                     # chunks baked so far (tests, perf notes)
var _stage := 0                    # bake step of the queue head (0-24 landmarks, 25-33 trails, 34-42 stones, 43 paint)
var _sync_fill := false            # first chunks after a new map: bake the start area at once
## CPU microseconds spent in _process and the painters (perf probes read it).
var cost_usec := 0

# Whole-map terrain and fog.
var _map_img: Image
var _map_tex: ImageTexture
var _map_dirty := false
var _uploaded_at := -100.0
var _fog_img: Image
var _fog_tex: ImageTexture
var _fog_version := -1
# Etappe 30: the fog has its own layers with shaders/map_fog.gdshader (smooth
# B-spline mask + drifting cloud noise) instead of the stretched 28 x 28 texture.
const FOG_SHADER := preload("res://shaders/map_fog.gdshader")
var _fog_material: ShaderMaterial
var _fog_layer: Control
var _big_fog: Control
var _terrain_key := 0

# Markers (absolute minimap px).
var _mk_kind := PackedInt32Array()
var _mk_pos := PackedVector2Array()
var _mk_edge := PackedByteArray()
var _horde_bins: Dictionary = {}
var _dots_clock := 0.0

# Big map.
var _big_rect_px := Rect2()
var _big_scale := 1.0
var _big_clock := 0.0
var _was_open := false
var _big_labels: Array = []
var _big_labels_key := ""
var _big_tex: ImageTexture         # = the map texture once the big map drew it (tests)

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
var _big_terrain: Control
var _big_dots: Control
var _big_self: Control
var _dot_tex: ImageTexture
var _self_key := 0
var _label_key := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back = UiLayer.make(self, "MapBack", _paint_back, true)
	_terrain = _live("MapTerrain", _paint_terrain)
	_terrain.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_fog_layer = _fog_live("MapFog", _paint_fog)
	_dots = _live("MapDots", _paint_dots)
	_top = UiLayer.make(self, "MapFrame", _paint_top, true)
	_self_layer = _live("MapSelf", _paint_self)
	_label = UiLayer.make(self, "MapLabel", _paint_label, true)
	_banner = _live("MapBanner", _paint_banner)
	_make_big()
	_banner.visible = false
	_dot_tex = _make_dot()


# A live layer drawing the fog mask through the shared fog shader.
func _fog_live(layer_name: String, painter: Callable, parent: Node = null) -> Control:
	if _fog_material == null:
		_fog_material = ShaderMaterial.new()
		_fog_material.shader = FOG_SHADER
	var layer := _live(layer_name, painter, parent)
	layer.material = _fog_material
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	return layer


func _paint_fog(cv: CanvasItem) -> void:
	if _fog_tex != null:
		cv.draw_texture_rect(_fog_tex, _map_rect.grow(-EDGE_BAND_MINI), false)


func _paint_big_fog(cv: CanvasItem) -> void:
	if _fog_tex != null and _big_rect_px.size.x > 0.0:
		cv.draw_texture_rect(_fog_tex, _big_rect_px, false)


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
	_biome = maxi(0, Biomes.ORDER.find(String(_state.get("biome_id", Biomes.DEFAULT))))
	_bind_arena(_state.get("arena"))
	_layout(hud)
	var extinct := bool(hud.get("extinct"))
	visible = not extinct
	if extinct:
		return
	var hidden: bool = bool(hud.get("paused")) or (hud.has_method("_choosing") and bool(hud._choosing()))
	var open: bool = bool(hud.get("map_open")) and not hidden
	_step_bakes()
	_sync_fill = false
	_upload(false)
	_update_fog()
	_step_banner(real_delta)
	for layer in [_back, _terrain, _fog_layer, _dots, _top, _self_layer, _label]:
		layer.visible = not open
	_big.visible = open
	if open:
		_step_big(real_delta, not _was_open)
	_was_open = open
	if open:
		return
	_back.refresh([_frame, UiStyle.skin])
	_top.refresh([_frame, UiStyle.skin])
	var key := hash([_map_rect, _fog_version, _uploaded_at, _map_key])
	if key != _terrain_key:
		_terrain_key = key
		_terrain.queue_redraw()
		_fog_layer.queue_redraw()
	_dots_clock -= real_delta
	if _dots_clock <= 0.0:
		_dots_clock = 1.0 / DOT_HZ
		_collect_markers()
		_dots.queue_redraw()
	var tip := _tip_active(hud)
	var at := world_to_minimap(_center)
	var self_key := hash([roundi(at.x * 2.0), roundi(at.y * 2.0), int(round(atan2(_heading.y, _heading.x) * 36.0 / PI)), int(_time * 30.0) if tip else 0])
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
	if rect == _frame and _map_rect.size.x > 0.0:
		return
	_frame = rect
	_disc_c = rect.get_center()
	if UiStyle.is_brawl():
		var face := _plaque_rect().grow(-UiStyle.STROKE_M - 2.0)
		_map_rect = face
	else:
		# Classic round skins: the square map is inscribed in the disc.
		var half := _frame_radius() * MAP_FILL / sqrt(2.0) - EDGE_BAND_MINI
		_map_rect = Rect2(_disc_c - Vector2(half, half), Vector2(half, half) * 2.0)
	_scale = _map_rect.size.x / maxf(1.0, _bounds.size.x)
	_terrain_key = 0


# Radius of the drawn minimap plaque (brawl: smaller than the tap rect).
func _frame_radius() -> float:
	return _frame.size.x * 0.5 * (BRAWL_SCALE if UiStyle.is_brawl() else 1.0)


# Brawl: square plaque around the same centre as the tap rect.
func _plaque_rect() -> Rect2:
	var half := _frame_radius()
	return Rect2(_disc_c - Vector2(half, half), Vector2(half, half) * 2.0)


# A new map (seed, biome, size) or another arena: rebind everything.
func _bind_arena(value: Variant) -> void:
	var arena: Node = value if value is Node and is_instance_valid(value) else null
	var seed_value := int(arena.get("world_seed")) if arena != null else 0
	var bounds: Rect2 = arena.bounds() if arena != null and arena.has_method("bounds") else Rect2()
	var key := "%d|%d|%s|%d" % [arena.get_instance_id() if arena != null else 0, seed_value, bounds, _biome]
	if key == _map_key:
		return
	_map_key = key
	_arena = arena
	_seed = seed_value
	_images.clear()
	_queue.clear()
	_queued.clear()
	_stage = 0
	_fog_version = -1
	_big_labels_key = ""
	_overview = {}
	if _arena == null or not _arena.has_method("map_overview"):
		return
	_overview = _arena.map_overview()
	_bounds = _overview.bounds
	var chunk_range: Rect2i = _overview.chunk_range
	_chunk_lo = chunk_range.position
	_chunks = chunk_range.size
	_scale = _map_rect.size.x / maxf(1.0, _bounds.size.x)
	var pal := _palette(_biome)
	_map_img = Image.create(_chunks.x * CHUNK_PX, _chunks.y * CHUNK_PX, false, Image.FORMAT_RGBA8)
	_map_img.fill(pal.ground)
	_map_tex = ImageTexture.create_from_image(_map_img)
	_map_dirty = false
	# Every map chunk, nearest to the swarm first; the start area bakes at once.
	var here := Vector2i(floori(_center.x / CELL), floori(_center.z / CELL))
	var keys: Array[Vector2i] = []
	for x in range(_chunk_lo.x, _chunk_lo.x + _chunks.x):
		for z in range(_chunk_lo.y, _chunk_lo.y + _chunks.y):
			keys.append(Vector2i(x, z))
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - here).length_squared() < (b - here).length_squared())
	for chunk in keys:
		var id := Vector3i(chunk.x, chunk.y, _biome)
		_queued[id] = true
		_queue.append(id)
	_sync_fill = true


func _tip_active(hud: Node) -> bool:
	var icon: Variant = hud.get("tutorial_icon") if "tutorial_icon" in hud else hud.get_meta("tutorial_icon", "")
	return String(icon) == "map"


# ------------------------------------------------------------------ geometry

## Minimap position (base px) of a world point (the whole map is shown).
func world_to_minimap(world: Vector3) -> Vector2:
	return _map_rect.position + (Vector2(world.x, world.z) - _bounds.position) * _scale


## Half the side of the drawn map square (px).
func minimap_radius() -> float:
	return _map_rect.size.x * 0.5


## Drawn map square on the minimap (px) and metres per px.
func minimap_rect() -> Rect2:
	return _map_rect


func minimap_scale() -> float:
	return _scale


## Big map position (base px) of a world point (valid while the big map is open).
func world_to_bigmap(world: Vector3) -> Vector2:
	return _big_rect_px.position + (Vector2(world.x, world.z) - _bounds.position) * _big_scale


## Markers of the last collection: [[kind, minimap px, on_edge], ...].
func markers() -> Array:
	var result := []
	for index in _mk_kind.size():
		result.append([_mk_kind[index], _mk_pos[index], _mk_edge[index] == 1])
	return result


## Chunks of the current map still waiting for their bake.
func pending_bakes() -> int:
	return _queue.size()


# ------------------------------------------------------------------ baking

func _palette(biome: int) -> Dictionary:
	if _palettes.has(biome):
		return _palettes[biome]
	var id: String = Biomes.ORDER[biome] if biome >= 0 and biome < Biomes.ORDER.size() else Biomes.DEFAULT
	var data: Dictionary = Biomes.get_data(id)
	var p := {}
	if data.has("ember"):
		var look: Dictionary = data.ember
		p.ground = (look.ground_dark as Color).lerp(look.ground_light, 0.5)
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
		p.wall = Color("140d10")
		p.site = Color("8a7478")
		p.ember = true
	elif data.has("desert"):
		# Stage 19: pale sand, rust-brown walls (darker than the sand), turquoise
		# oases, darker quicksand discs.
		var sand: Dictionary = data.desert
		p.ground = (sand.dune_light as Color).lerp(sand.dune_shadow, 0.35)
		p.edge = data.path_edge
		p.path = (data.path as Color).lightened(0.05)
		p.core = Color(0, 0, 0, 0)
		p.shore = data.shore
		p.pool = data.pool
		p.pool_core = (data.pool as Color).lightened(0.3)
		p.rock_line = Color("3a281c")
		p.rock = Color("8a6a52")
		p.rock_light = Color("c9a57e")
		p.wood = Color("8a6a52")
		p.wood_light = Color("c9a57e")
		p.plinth = data.plinth
		p.meadow = (sand.dune_light as Color).lightened(0.1)
		p.flower = data.flower_light
		p.fog = Color("17120c")
		p.wall = Color("5b3f2c")
		p.site = Color("f2dca0")
		p.quicksand = sand.quicksand_swirl
		p.ember = false
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
		p.wall = Color("1c361d")
		p.site = Color("c9e39a")
		p.ember = false
	_palettes[biome] = p
	return p


func _step_bakes() -> void:
	if _arena == null or not _arena.has_method("map_features") or _map_img == null:
		return
	var started := Time.get_ticks_usec()
	# The start area (3 x 3 chunks) bakes at once on a new map, the rest in budget.
	var sync_left := 9 if _sync_fill else 0
	while not _queue.is_empty() and (sync_left > 0 or Time.get_ticks_usec() - started < _bake_budget):
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
		var image := bake_chunk(key, id.z)
		_images[id] = image
		bakes += 1
		sync_left -= 1
		if id.z == _biome:
			_map_img.blit_rect(image, Rect2i(0, 0, CHUNK_PX, CHUNK_PX), (key - _chunk_lo) * CHUNK_PX)
			_map_dirty = true


# Uploads the whole-map image (throttled while chunks keep arriving).
func _upload(force: bool) -> void:
	if not _map_dirty or _map_tex == null:
		return
	if not force and not _queue.is_empty() and _time - _uploaded_at < UPLOAD_GAP and _uploaded_at >= 0.0:
		return
	_map_tex.update(_map_img)
	_map_dirty = false
	_uploaded_at = _time


# Fog texture from the arena exploration grid (1 texel per FOG_CELL).
func _update_fog() -> void:
	if _arena == null or not _arena.has_method("explored_cells"):
		return
	var version := int(_arena.get("explore_version"))
	if version == _fog_version and _fog_tex != null:
		return
	_fog_version = version
	var size_cells: Vector2i = _arena.fog_size()
	var cells: PackedByteArray = _arena.explored_cells()
	if size_cells.x <= 0 or cells.size() != size_cells.x * size_cells.y:
		return
	if _fog_img == null or _fog_img.get_size() != size_cells:
		_fog_img = Image.create(size_cells.x, size_cells.y, false, Image.FORMAT_RGBA8)
		_fog_tex = null
	var fog: Color = _palette(_biome).fog
	var mist := fog.lerp(Color("5d6f66"), 0.22)
	_fog_material.set_shader_parameter("fog_color", fog)
	_fog_material.set_shader_parameter("mist_color", mist)
	_fog_material.set_shader_parameter("rim_color", mist.lerp(Color("e8f0d8"), 0.55))
	for z in size_cells.y:
		for x in size_cells.x:
			_fog_img.set_pixel(x, z, Color(1.0, 1.0, 1.0, 0.0 if cells[z * size_cells.x + x] != 0 else FOG_ALPHA))
	if _fog_tex == null:
		_fog_tex = ImageTexture.create_from_image(_fog_img)
	else:
		_fog_tex.update(_fog_img)


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
	# Stage 18b: walls of the path map dark (wall distance samples, bilinear up).
	var walls: PackedFloat32Array = features.get("walls", PackedFloat32Array())
	if walls.size() == WALL_SAMPLES * WALL_SAMPLES:
		var mask := Image.create(WALL_SAMPLES, WALL_SAMPLES, false, Image.FORMAT_RGBA8)
		var wall: Color = pal.wall
		for index in walls.size():
			mask.set_pixel(index % WALL_SAMPLES, index / WALL_SAMPLES, Color(wall, clampf((0.6 - walls[index]) / 2.0, 0.0, 1.0)))
		mask.resize(CHUNK_PX, CHUNK_PX, Image.INTERPOLATE_BILINEAR)
		image.blend_rect(mask, Rect2i(0, 0, CHUNK_PX, CHUNK_PX), Vector2i.ZERO)
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
	# Stage 19: quicksand patches (darker discs) reaching into this chunk.
	if pal.has("quicksand") and _arena.has_method("quicksand_patches"):
		var area := Rect2(origin, Vector2(CELL, CELL))
		for patch: Vector4 in _arena.quicksand_patches():
			if area.grow(patch.w).has_point(Vector2(patch.x, patch.z)):
				_stamp(image, Color(pal.quicksand, 0.85), (Vector2(patch.x, patch.z) - origin) * TEXEL, patch.w * TEXEL)
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


# ------------------------------------------------------------------ shared map drawing

# Terrain, region lines, edge band and fog of the whole map into `rect`.
func _draw_map(cv: CanvasItem, rect: Rect2, band: float, fog: float) -> void:
	var pal := _palette(_biome)
	cv.draw_rect(rect.grow(band * 0.5), pal.fog)
	if _map_tex != null:
		cv.draw_texture_rect(_map_tex, rect, false)
	# Thin region lines (4 x 4 for solo).
	var regions := int(_overview.get("regions_per_side", 0))
	if regions > 1:
		var line := Color(0.0, 0.0, 0.0, 0.2)
		var step := rect.size.x / float(regions)
		for index in range(1, regions):
			var offset := step * float(index)
			cv.draw_line(rect.position + Vector2(offset, 0.0), rect.position + Vector2(offset, rect.size.y), line, 1.0)
			cv.draw_line(rect.position + Vector2(0.0, offset), rect.position + Vector2(rect.size.x, offset), line, 1.0)
	_draw_sites(cv, rect)
	_draw_edge(cv, rect, band)


# Stage 18c: a place counts as seen once the arena discovered it (fog cell on
# the classic map).
func _hidden_ok(point: Vector3) -> bool:
	if _arena == null:
		return false
	if _arena.has_method("is_discovered"):
		return _arena.is_discovered(point)
	return _arena.has_method("is_explored") and _arena.is_explored(point)


# Stage 18c: nest and totem show only once found; boss, apex and the Schlund
# (announced) always.
func _poi_visible(key: String, point: Vector3) -> bool:
	if key == "nest" or key == "totem":
		return _hidden_ok(point)
	return true


# Stage 18b/18c: every discovered place as a quiet site symbol (pale disc plus
# the marker of its POI type); undiscovered places stay hidden in the fog.
func _draw_sites(cv: CanvasItem, rect: Rect2) -> void:
	var sites: Array = _overview.get("clearings", [])
	if sites.is_empty():
		return
	var scale := rect.size.x / maxf(1.0, _bounds.size.x)
	var k := clampf(rect.size.x / 260.0, 0.45, 1.3)
	for site: Dictionary in sites:
		var center: Vector2 = site.center
		var p := rect.position + (center - _bounds.position) * scale
		var seen: bool = _hidden_ok(Vector3(center.x, 0.0, center.y))
		# Stage 18c: a place shows up only once it was discovered.
		if not seen:
			continue
		# Etappe 30 (S25 feedback): a clearing is only a possible place - most
		# stay empty. No type symbol here any more (it showed POIs where nothing
		# was); the real objects come as markers from their live positions.
		var types: Array = site.get("types", [])
		if types.has("start") or types.has("arrival"):
			cv.draw_circle(p, 1.6 * k, Color(1, 1, 1, 0.9))


# The natural edge as a band along the map border, coloured per segment kind.
func _draw_edge(cv: CanvasItem, rect: Rect2, band: float) -> void:
	var border: Dictionary = _overview.get("border", {})
	var segments: Array = border.get("segments", [])
	var scale := rect.size.x / maxf(1.0, _bounds.size.x)
	var inset := band * 0.5
	for segment: Dictionary in segments:
		var a: Vector2 = rect.position + ((segment.from as Vector2) - _bounds.position) * scale
		var b: Vector2 = rect.position + ((segment.to as Vector2) - _bounds.position) * scale
		var side := int(segment.side)
		var push: Vector2 = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)][side] * inset
		var along := (b - a).normalized() * inset
		var color: Color = EDGE_COLORS.get(String(segment.kind), Color("2e5a24"))
		cv.draw_line(a + push - along, b + push + along, color, band, false)
	cv.draw_rect(rect.grow(band), UiStyle.BRAWL_INK if UiStyle.is_brawl() else UiStyle.color("outline"), false, 2.0)


# ------------------------------------------------------------------ markers

func _collect_markers() -> void:
	_mk_kind.resize(0)
	_mk_pos.resize(0)
	_mk_edge.resize(0)
	# Horde: density bins instead of single points.
	_horde_bins.clear()
	var horde: PackedVector3Array = _state.get("horde", PackedVector3Array())
	for point in horde:
		var p := world_to_minimap(point)
		var bin := Vector2i(floori(p.x / HORDE_BIN), floori(p.y / HORDE_BIN))
		_horde_bins[bin] = int(_horde_bins.get(bin, 0)) + 1
	var corpses: PackedFloat32Array = _state.get("corpses", PackedFloat32Array())
	for index in range(0, corpses.size() - 2, 3):
		_add(_loot_mark(corpses[index + 2]), world_to_minimap(Vector3(corpses[index], 0.0, corpses[index + 1])), false)
	var enemies: PackedFloat32Array = _state.get("enemies", PackedFloat32Array())
	for index in range(0, enemies.size() - 2, 3):
		_add(int(enemies[index + 2]), world_to_minimap(Vector3(enemies[index], 0.0, enemies[index + 1])), false)
	for pair in LIST_KEYS:
		var points: PackedVector3Array = _state.get(pair[0], PackedVector3Array())
		for point in points:
			_add(pair[1], world_to_minimap(point), false)
	for pair in POI_KEYS:
		var point: Vector3 = _state.get(pair[0], Vector3.INF)
		if point.is_finite() and _poi_visible(pair[0], point):
			_add(pair[1], world_to_minimap(point), false)


# Loot layer size code -> marker (0..2 crystal heaps, 3 = Lockruf).
static func _loot_mark(code: float) -> int:
	return Mark.LURE if int(code) >= 3 else Mark.CORPSE + clampi(int(code), 0, 2)


func _add(kind: int, p: Vector2, edge: bool) -> void:
	_mk_kind.append(kind)
	_mk_pos.append(p)
	_mk_edge.append(1 if edge else 0)


# Draw order: quiet things first, objectives on top.
static func _layer_of(kind: int) -> int:
	if kind == Mark.CORPSE or kind == Mark.CORPSE_BIG or kind == Mark.CORPSE_BOSS:
		return 0
	if kind <= Mark.LEAPER:
		return 1
	return 2


# ------------------------------------------------------------------ minimap painters

func _paint_back(cv: CanvasItem) -> void:
	if UiStyle.is_brawl():
		# Kit plaque: hard shadow, ink body, dark face with a lit upper half.
		var plaque := _plaque_rect()
		Kit.rrect(cv, plaque.grow(0.0).grow_individual(0, -UiStyle.SHADOW_Y, 0, UiStyle.SHADOW_Y), UiStyle.R_M, UiStyle.BRAWL_INK_SOFT)
		Kit.rrect(cv, plaque, UiStyle.R_M, UiStyle.BRAWL_INK)
		Kit.rrect(cv, plaque.grow(-UiStyle.STROKE_M + 0.5), UiStyle.R_M - 3.0, UiStyle.BRAWL_PANEL_BOTTOM)
		Kit.fade_rrect(cv, plaque.grow(-UiStyle.STROKE_M), UiStyle.R_M - 3.0, UiStyle.BRAWL_PANEL_RIM, 0.0, 0.6)
		return
	var radius := _frame_radius()
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
	cv.draw_circle(_disc_c, radius * MAP_FILL + 1.0, _palette(_biome).fog)


func _paint_terrain(cv: CanvasItem) -> void:
	# Stage 18c: only what the swarm has seen shows on the small map too.
	_draw_map(cv, _map_rect.grow(-EDGE_BAND_MINI), EDGE_BAND_MINI, 1.0)


func _paint_dots(cv: CanvasItem) -> void:
	for bin: Vector2i in _horde_bins:
		var count := int(_horde_bins[bin])
		var strength := clampf(float(count) / 5.0, 0.25, 1.0)
		_dot(cv, (Vector2(bin) + Vector2(0.5, 0.5)) * HORDE_BIN, 2.5 + 2.0 * strength, Color(HORDE_COLOR, 0.45 + 0.5 * strength))
	for layer in 3:
		for index in _mk_kind.size():
			var kind := _mk_kind[index]
			if _layer_of(kind) == layer:
				_marker(cv, kind, _mk_pos[index], _mini_k(kind))


# Marker size on the small map: creatures and crystals tiny, objectives readable.
static func _mini_k(kind: int) -> float:
	if kind <= Mark.CORPSE_BOSS:
		return 0.55
	if kind == Mark.NEST or kind == Mark.TOTEM or kind == Mark.BOSS or kind == Mark.APEX:
		return 0.62
	return 0.7


func _paint_top(cv: CanvasItem) -> void:
	if UiStyle.is_brawl():
		# Ink contour and "N" as a small badge on the top edge.
		var plaque := _plaque_rect()
		Kit.ring(cv, plaque, UiStyle.R_M, UiStyle.STROKE_M, UiStyle.BRAWL_INK)
		Kit.badge(cv, Vector2(_disc_c.x, plaque.position.y + 2.0), "N", "neutral", UiStyle.T_LABEL)
		return
	var radius := _frame_radius()
	var accent := FRAME_ACCENT
	if UiStyle.is_calm():
		accent = UiFrames.calm_color(UiStyle.CYAN)
		cv.draw_arc(_disc_c, radius * MAP_FILL + 2.0, 0.0, TAU, 64, accent, 3.0, true)
	else:
		cv.draw_arc(_disc_c, radius * MAP_FILL + 2.5, 0.0, TAU, 64, UiStyle.color("outline"), 6.0, true)
		cv.draw_arc(_disc_c, radius * MAP_FILL + 2.5, 0.0, TAU, 64, accent, 3.0, true)
		var claws := UiStyle.tex(UiFrames.DIR + "round_claws.svg")
		if claws != null:
			var area := Vector2.ONE * UiFrames.ROUND_TEX * radius / UiFrames.ROUND_RADIUS
			cv.draw_texture_rect(claws, Rect2(_disc_c - area * 0.5, area), false)
	# North marker: a bone notch with an "N" on the rim (calm: small chamfered plate).
	var north := _disc_c + Vector2(0, -radius * MAP_FILL - 4.0)
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
		if UiStyle.is_brawl():
			var ring := _plaque_rect().grow(6.0 + 6.0 * beat)
			Kit.ring(cv, ring, UiStyle.R_M + 6.0, 6.0, Color(UiStyle.color("outline"), 0.5))
			Kit.ring(cv, ring, UiStyle.R_M + 6.0, 3.0, Color(UiStyle.color("gold"), 0.55 + 0.4 * beat))
		else:
			var radius := _frame_radius() + 8.0 + 8.0 * beat
			cv.draw_arc(_disc_c, radius, 0.0, TAU, 64, Color(UiStyle.color("outline"), 0.5), 8.0, true)
			cv.draw_arc(_disc_c, radius, 0.0, TAU, 64, Color(UiStyle.color("gold"), 0.55 + 0.4 * beat), 4.0, true)
	_swarm_arrow(cv, world_to_minimap(_center), _heading, 0.85)


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
		Mark.CORPSE, Mark.CORPSE_BIG, Mark.CORPSE_BOSS:
			# Crystal heaps stay quiet: muted amber, below the creatures.
			return Color(UiStyle.color("amber"), 0.8)
		Mark.LURE:
			return LURE_COLOR
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
		Mark.CHEST:
			return CHEST_COLOR
		Mark.POWERUP:
			return POWERUP_COLOR
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
			_dot(cv, p, 2.4 * k, color)
		Mark.CORPSE_BIG:
			_dot(cv, p, 3.2 * k, color)
		Mark.CORPSE_BOSS:
			_dot(cv, p, 4.0 * k, color)
		Mark.LURE:
			# Pulsing plate: soft halo, ink disc, pink face, white spark.
			var beat := 0.5 + 0.5 * sin(_time * 6.0)
			var r := 7.0 * k
			Kit.glow(cv, p, r * (1.9 + 0.5 * beat), LURE_COLOR, 0.55 + 0.25 * beat)
			Kit.disc(cv, p, r + 2.0 * k, UiStyle.BRAWL_INK)
			Kit.disc(cv, p, r, LURE_COLOR)
			Kit.disc(cv, p - Vector2(0, r * 0.18), r * 0.62, LURE_COLOR.lightened(0.35))
			var spark := PackedVector2Array()
			for i in 8:
				var a := TAU * float(i) / 8.0 - PI * 0.5
				spark.append(p + Vector2(cos(a), sin(a)) * r * (0.62 if i % 2 == 0 else 0.24))
			cv.draw_colored_polygon(spark, Color.WHITE)
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
		Mark.CHEST:
			# Kokon (chest): gold rounded box with an ink rim and a lid seam.
			var box := Rect2(p - Vector2(7.0, 6.0) * k, Vector2(14.0, 12.0) * k)
			Kit.rrect(cv, box.grow(2.0 * k), 4.0 * k, UiStyle.BRAWL_INK)
			Kit.rrect(cv, box, 3.0 * k, color)
			cv.draw_line(Vector2(box.position.x, box.position.y + box.size.y * 0.42), Vector2(box.end.x, box.position.y + box.size.y * 0.42), color.darkened(0.45), 1.6 * k)
			cv.draw_circle(box.get_center() + Vector2(0, 1.0 * k), 1.6 * k, Color.WHITE)
		Mark.POWERUP:
			# Pilzknolle (power-up): green mushroom cap on a pale stem.
			var stem := Rect2(p + Vector2(-2.2, -0.5) * k, Vector2(4.4, 6.5) * k)
			Kit.disc(cv, p + Vector2(0, -1.5) * k, 7.5 * k, UiStyle.BRAWL_INK)
			Kit.rrect(cv, stem.grow(1.5 * k), 2.0 * k, UiStyle.BRAWL_INK)
			Kit.rrect(cv, stem, 1.5 * k, Color("f2ead0"))
			Kit.disc(cv, p + Vector2(0, -1.5) * k, 6.0 * k, color)
			cv.draw_circle(p + Vector2(-2.2, -3.2) * k, 1.4 * k, Color(1, 1, 1, 0.85))


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
		_banner_pending = REGION_BANNER
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
# header, close button, legend, map frame), BigTerrain (whole map + fog +
# edge + region names, redrawn when something changes), BigDots (markers at
# BIG_HZ) and BigSelf (swarm arrow).

func _make_big() -> void:
	_big = Control.new()
	_big.name = "BigMap"
	_big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_big)
	_big.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_live("BigDim", _paint_big_dim, _big)
	_big_static = UiLayer.make(_big, "BigStatic", _paint_big_static, true)
	_big_terrain = _live("BigTerrain", _paint_big_terrain, _big)
	_big_terrain.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_big_fog = _fog_live("BigFog", _paint_big_fog, _big)
	_big_dots = _live("BigDots", _paint_big_dots, _big)
	_big_self = _live("BigSelf", _paint_big_self, _big)
	_big.visible = false


func _big_rect() -> Rect2:
	var hud := get_parent()
	return hud._bigmap_rect() if hud != null and hud.has_method("_bigmap_rect") else Rect2(20, 130, size.x - 40, size.y - 500)


func _big_map_area() -> Rect2:
	var panel := _big_rect()
	return Rect2(panel.position + Vector2(26, 112), panel.size - Vector2(52, 112 + 130))


func _step_big(real_delta: float, opened: bool) -> void:
	var area := _big_map_area()
	var side := minf(area.size.x, area.size.y) - EDGE_BAND_BIG * 2.0
	var square := Rect2(area.get_center() - Vector2(side, side) * 0.5, Vector2(side, side))
	var cache_area := _big_rect().grow(30.0)
	if _big_static.region != cache_area:
		_big_static.region = cache_area
		_big_static.invalidate()
	var region := String(_state.get("region", ""))
	var phrase := String(_state.get("region_phrase", ""))
	_big_static.refresh([region, phrase, int(_state.get("regions", 0)), square, UiStyle.skin, _state.has("chests"), _state.has("powerups")])
	if opened:
		_upload(true)
	var labels_key := "%d|%s|%s|%s" % [_fog_version, _map_key, square, _state.get("region_key", Vector2i.ZERO)]
	if square != _big_rect_px or labels_key != _big_labels_key or opened:
		_big_rect_px = square
		_big_scale = square.size.x / maxf(1.0, _bounds.size.x)
		_big_labels_key = labels_key
		_collect_big_labels()
		_big_tex = _map_tex
		_big_terrain.queue_redraw()
		_big_fog.queue_redraw()
	elif _map_tex != null and _uploaded_at != float(_big_terrain.get_meta("uploaded", -1.0)):
		_big_terrain.set_meta("uploaded", _uploaded_at)
		_big_terrain.queue_redraw()
	_big_clock -= real_delta
	if opened or _big_clock <= 0.0:
		_big_clock = 1.0 / BIG_HZ
		_big_dots.queue_redraw()
		_big_self.queue_redraw()


# Names of the explored regions (current one highlighted); unexplored regions
# stay nameless under the fog.
func _collect_big_labels() -> void:
	_big_labels.clear()
	if _arena == null or not _arena.has_method("explored_regions"):
		return
	var seen := {}
	for region in _arena.explored_regions():
		seen[region] = true
	var current: Vector2i = _state.get("region_key", Vector2i(1 << 30, 0))
	for entry: Dictionary in _overview.get("regions", []):
		var key: Vector2i = entry.key
		if not seen.has(key):
			continue
		_big_labels.append([String(_arena.region_name(key)), entry.center, key == current])


func _paint_big_dim(cv: CanvasItem) -> void:
	cv.draw_rect(Rect2(Vector2.ZERO, size), Color(UiStyle.color("dim"), 0.35))


func _paint_big_static(cv: CanvasItem) -> void:
	var panel := _big_rect()
	var area := _big_map_area()
	var square := _big_rect_px if _big_rect_px.size.x > 0.0 else area
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
	if UiStyle.is_brawl() and UiIcons.has("g_close"):
		UiIcons.draw(cv, "g_close", Rect2(cc - Vector2(23, 23), Vector2(46, 46)))
	else:
		for pass_index in 2:
			for sign_x in [-1.0, 1.0]:
				cv.draw_line(cc + Vector2(-12.0 * sign_x, -12.0), cc + Vector2(12.0 * sign_x, 12.0), UiStyle.color("outline") if pass_index == 0 else UiStyle.color("bone"), 9.0 if pass_index == 0 else 5.0, true)
	cv.draw_rect(square.grow(EDGE_BAND_BIG + 3.0), UiStyle.color("outline"), false, 4.0)
	_paint_legend(cv, Rect2(area.position.x, area.end.y + 14.0, area.size.x, panel.end.y - area.end.y - 30.0))


func _paint_big_terrain(cv: CanvasItem) -> void:
	if _big_rect_px.size.x <= 0.0:
		return
	_draw_map(cv, _big_rect_px, EDGE_BAND_BIG, 1.0)
	var body := UiStyle.body_font()
	for label: Array in _big_labels:
		var p := _big_rect_px.position + ((label[1] as Vector2) - _bounds.position) * _big_scale
		var here: bool = label[2]
		UiStyle.text(cv, String(label[0]), p + Vector2(0, 8), UiStyle.SIZE_LABEL, UiStyle.color("gold").lightened(0.3) if here else Color(UiStyle.color("text"), 0.9), true, 6, body)


func _paint_big_dots(cv: CanvasItem) -> void:
	var horde: PackedVector3Array = _state.get("horde", PackedVector3Array())
	for index in range(0, horde.size(), 3):   # every third point is dense enough at this scale
		_dot(cv, world_to_bigmap(horde[index]), 3.5, Color(HORDE_COLOR, 0.7))
	var corpses: PackedFloat32Array = _state.get("corpses", PackedFloat32Array())
	for index in range(0, corpses.size() - 2, 3):
		_marker(cv, _loot_mark(corpses[index + 2]), world_to_bigmap(Vector3(corpses[index], 0.0, corpses[index + 1])), 1.0 if int(corpses[index + 2]) >= 3 else 0.8)
	var enemies: PackedFloat32Array = _state.get("enemies", PackedFloat32Array())
	for index in range(0, enemies.size() - 2, 3):
		_marker(cv, int(enemies[index + 2]), world_to_bigmap(Vector3(enemies[index], 0.0, enemies[index + 1])), 0.8)
	for pair in LIST_KEYS:
		var points: PackedVector3Array = _state.get(pair[0], PackedVector3Array())
		for point in points:
			_marker(cv, pair[1], world_to_bigmap(point), 1.1)
	for pair in POI_KEYS:
		var point: Vector3 = _state.get(pair[0], Vector3.INF)
		if point.is_finite() and _poi_visible(pair[0], point):
			_marker(cv, pair[1], world_to_bigmap(point), 1.1)


func _paint_big_self(cv: CanvasItem) -> void:
	_swarm_arrow(cv, world_to_bigmap(_center), _heading, 1.2)


const LEGEND := [
	["Schwarm", -1], ["Beute", Mark.PREY], ["Jäger", Mark.HUNTER], ["Horde", Mark.HORDE], ["Kristalle", Mark.CORPSE_BIG], ["Lockruf", Mark.LURE],
	["Alpha-Kern", Mark.ALPHA], ["Brutnest", Mark.NEST], ["Totem", Mark.TOTEM], ["Boss", Mark.BOSS], ["Schlund", Mark.PORTAL],
]


# Kokon and Pilzknolle join the legend once HuntWorld publishes them.
func _legend() -> Array:
	var result := LEGEND.duplicate()
	if _state.has("chests"):
		result.append(["Kokon", Mark.CHEST])
	if _state.has("powerups"):
		result.append(["Power-up", Mark.POWERUP])
	return result


func _paint_legend(cv: CanvasItem, rect: Rect2) -> void:
	var entries := _legend()
	var columns := ceili(entries.size() / 2.0)
	var cell := Vector2(rect.size.x / columns, minf(46.0, rect.size.y * 0.5))
	var body := UiStyle.body_font()
	for index in entries.size():
		var entry: Array = entries[index]
		var at := rect.position + Vector2(float(index % columns) * cell.x, float(index / columns) * cell.y)
		var icon_c := at + Vector2(16.0, cell.y * 0.5)
		if int(entry[1]) < 0:
			_swarm_arrow(cv, icon_c, Vector2(0, -1), 1.0)
		else:
			_marker(cv, int(entry[1]), icon_c, 1.7 if int(entry[1]) < Mark.NEST else 1.0)
		UiStyle.text(cv, String(entry[0]), at + Vector2(34.0, cell.y * 0.5 + 8.0), UiStyle.SIZE_LABEL, UiStyle.color("text_dim"), false, 4, body)


static func _noise(x: int, y: int) -> float:
	var n := x * 374761393 + y * 668265263
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 1023) / 1023.0
