extends Control

# Draw layer (stage 07, PERF_HUD). HUD and menu components split their picture
# into a few of these child layers so a frame only repaints what changed:
#
#   var layer := UiLayer.make(self, "Top", _paint_top)      # painter(canvas: CanvasItem)
#   layer.refresh([pop, pulse > 0.0])   # every frame: repaints only when the key changes
#
# The painter draws on the canvas it gets (never on `self`), so the same code
# serves the live drawing and the cache.
#
# cached = true: while the key keeps changing (animations, dragging) the layer
# draws live; once the key has been stable for SETTLE seconds it renders one
# more time into a SubViewport - at the physical pixel size of its region, with
# the same font oversampling - copies the result into an ImageTexture (the
# render target shrinks back to 2 x 2 px, so only the texture stays in VRAM)
# and from then on shows it as ONE pixel-aligned texture (premultiplied
# alpha). A static panel full of polygons, outlines and text then costs one
# draw call per frame instead of dozens, and looks the same (probe: max. 2/255
# difference per channel).

const UiLayerScript := preload("res://scripts/ui/ui_layer.gd")
const SETTLE := 0.15

var painter: Callable
var cached := false
## Area (layer-local, base pixels) the cache needs, including glow and claws.
## Empty = the whole layer.
var region := Rect2()

var _key: Variant = null
var _has_key := false
var _changed_at := 0.0
var _state := 0            # 0 live, 1 cache rendering this frame, 2 showing cache
var _viewport: SubViewport
var _baked: ImageTexture
var _inner: Control
var _shown := Rect2()
var _place := Transform2D()

static var _premult: CanvasItemMaterial
static var _no_pixels := -1


## Adds a layer as the last child of `owner` (children draw in order).
static func make(owner: Node, layer_name: String, paint: Callable, cache: bool = false, area: Rect2 = Rect2()) -> Control:
	var layer: Control = UiLayerScript.new()
	layer.name = layer_name
	layer.painter = paint
	layer.cached = cache
	layer.region = area
	owner.add_child(layer)
	return layer


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Call once per frame. Repaints when `key` differs from the last one or when
## forced; a cached layer bakes itself after the key settled.
func refresh(key: Variant, force: bool = false) -> void:
	var now := Time.get_ticks_msec() * 0.001
	if force or not _has_key or not _same(key, _key) or (cached and _state != 0 and _placement_changed()):
		_key = key
		_has_key = true
		_changed_at = now
		_go_live()
		return
	if not cached or not is_visible_in_tree() or _headless():
		return
	if _state == 0 and now - _changed_at >= SETTLE:
		_bake()
	elif _state == 1:
		_keep_bake()


## Forgets the key so the next refresh() repaints for sure.
func invalidate() -> void:
	_has_key = false


# The dummy renderer of --headless runs has no pixels to bake: stay live.
static func _headless() -> bool:
	if _no_pixels < 0:
		_no_pixels = 1 if DisplayServer.get_name() == "headless" else 0
	return _no_pixels == 1


func is_baked() -> bool:
	return _state == 2


func _same(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b


func _go_live() -> void:
	if _state != 0:
		_state = 0
		material = null
	queue_redraw()


func _draw() -> void:
	if _state == 2 and _baked != null:
		draw_texture_rect(_baked, _shown, false)
	elif painter.is_valid():
		painter.call(self)


# ------------------------------------------------------------------ cache

func _physical() -> Transform2D:
	var vp := get_viewport()
	if vp == null:
		return get_global_transform_with_canvas()
	return vp.get_final_transform() * get_global_transform_with_canvas()


func _placement_changed() -> bool:
	return not _physical().is_equal_approx(_place)


func _ensure_cache() -> void:
	if _viewport != null:
		return
	if _premult == null:
		_premult = CanvasItemMaterial.new()
		_premult.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_viewport = SubViewport.new()
	_viewport.name = "Cache"
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.gui_disable_input = true
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_inner = Control.new()
	_inner.name = "Paint"
	_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.add_child(_inner)
	_inner.draw.connect(_paint_inner)


func _paint_inner() -> void:
	if painter.is_valid():
		painter.call(_inner)


# Renders the painter once into the SubViewport; the texture is shown from the
# next frame on (this frame still draws live, so nothing can flicker).
func _bake() -> void:
	if not is_inside_tree() or size.x <= 0.0 or size.y <= 0.0:
		return
	_ensure_cache()
	var xf := _physical()
	var scale := xf.get_scale()
	if scale.x <= 0.0 or scale.y <= 0.0:
		return
	_place = xf
	var area := region if region.size.x > 0.0 else Rect2(Vector2.ZERO, size)
	# Snap the region to physical pixels: every texel lands on one screen pixel.
	var corner := (xf * area.position).floor()
	var far := (xf * area.end).ceil()
	var px := Vector2i(maxi(1, int(far.x - corner.x)), maxi(1, int(far.y - corner.y)))
	var origin := xf.affine_inverse() * corner
	_shown = Rect2(origin, Vector2(px) / scale)
	if _viewport.size != px:
		_viewport.size = px
	# Same mapping as on screen: local -> physical, shifted to the cache corner.
	_viewport.canvas_transform = Transform2D(0.0, scale, 0.0, -origin * scale)
	_viewport.oversampling_override = scale.x
	_inner.position = Vector2.ZERO
	_inner.size = size
	_inner.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_state = 1


# The SubViewport rendered last frame: keep its picture, free the render target.
func _keep_bake() -> void:
	var image := _viewport.get_texture().get_image()
	if image == null or image.is_empty():
		_state = 0
		return
	if _baked == null or Vector2i(_baked.get_size()) != image.get_size():
		_baked = ImageTexture.create_from_image(image)
	else:
		_baked.update(image)
	# Free the render target completely; the next bake builds a new one.
	_viewport.queue_free()
	_viewport = null
	_inner = null
	_state = 2
	material = _premult
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_has_key = false
