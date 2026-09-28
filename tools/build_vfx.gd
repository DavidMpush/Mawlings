extends SceneTree

# Builds assets/vfx/ from the user's VFX package V1 (read-only source folder):
#   * the six painted PNGs (1254 px) -> cropped to their visible effect, square,
#     alpha edges fixed, downscaled (Lanczos) to 256-384 px
#   * the two boss telegraph SVGs -> 512 px CHANNEL MASKS (one layer per channel,
#     so telegraph_style.gd can recolour them, e.g. for the colour-blind palette):
#       R = translucent fill, G = dark contour, B = coral ring/edge, A = pale marks
#     Geometry is copied 1:1 from the SVGs (viewBox 512); only the colours are dropped.
#
# Run (no window needed):
#   Godot_console.exe --headless --audio-driver Dummy --path <project> --script res://tools/build_vfx.gd [-- src=<folder>]
# then import once: Godot_console.exe --headless --editor --import --path <project> --quit
# Import options (mipmaps, compression) live in the committed assets/vfx/*.png.import.

const DEFAULT_SOURCE := "C:/Users/vrxby/Documents/Codex/Swarm/Design/VFX_Assets_V1"
const OUT := "res://assets/vfx"

# name -> output edge in px (big, soft effects get more pixels).
const SPRITES := {
	"bite_hit": 256,
	"acid_splash": 256,
	"spore_cloud": 320,
	"slam_shockwave": 384,
	"harvest_particles": 256,
	"dna_pickup": 256,
}
const MASK_SIZE := 512
# Pixels with alpha above this count as "visible" for the crop.
const CROP_ALPHA := 0.16
const CROP_MARGIN := 0.04

# --- boss_telegraph_circle.svg, split into layers --------------------------
const CIRCLE_FILL := '<circle cx="256" cy="256" r="209" fill="#fff"/>'
const CIRCLE_DARK := '<circle cx="256" cy="256" r="210" fill="none" stroke="#fff" stroke-width="23"/>'
const CIRCLE_CORAL := '<circle cx="256" cy="256" r="210" fill="none" stroke="#fff" stroke-width="12" stroke-dasharray="150 18 38 18"/><circle cx="256" cy="256" r="30" fill="none" stroke="#fff" stroke-width="8"/>'
const CIRCLE_TRIS := "M256 12 275 43 237 43Z M500 256 469 275 469 237Z M256 500 237 469 275 469Z M12 256 43 237 43 275Z"
const CIRCLE_PALE := '<circle cx="256" cy="256" r="178" fill="none" stroke="#fff" stroke-width="4" stroke-dasharray="25 17"/>'
# Pale inner ring is 72 % opaque in the SVG; the hub 70 %; the dark ring 88 %.
const CIRCLE_PALE_RING_ALPHA := 0.72

# --- boss_telegraph_cone.svg ------------------------------------------------
const CONE_FILL := '<path d="M75 256 437 54 A445 445 0 0 1 437 458Z" fill="#fff"/>'
const CONE_DARK := '<path d="M75 256 437 54 M75 256 437 458" fill="none" stroke="#fff" stroke-width="24" stroke-linecap="round"/><path d="M437 54 A445 445 0 0 1 437 458" fill="none" stroke="#fff" stroke-width="25" stroke-linecap="round"/>'
const CONE_CORAL := '<path d="M75 256 437 54 M75 256 437 458" fill="none" stroke="#fff" stroke-width="12" stroke-linecap="round"/><path d="M437 54 A445 445 0 0 1 437 458" fill="none" stroke="#fff" stroke-width="13" stroke-dasharray="84 22 33 22" stroke-linecap="round"/>'
const CONE_DIAMOND := "M75 235 102 256 75 277 48 256Z"
const CONE_CHEVRONS := '<path d="M282 222 315 256 282 290 M348 204 399 256 348 308" fill="none" stroke="#fff" stroke-width="8" stroke-linecap="round" stroke-linejoin="round"/>'


func _initialize() -> void:
	var source := DEFAULT_SOURCE
	for raw in OS.get_cmdline_user_args():
		if String(raw).begins_with("src="):
			source = String(raw).substr(4)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var ok := true
	for sprite_name in SPRITES:
		ok = _build_sprite(source.path_join(sprite_name + ".png"), sprite_name, int(SPRITES[sprite_name])) and ok
	ok = _build_circle() and ok
	ok = _build_cone() and ok
	print("build_vfx: %s" % ("done" if ok else "FAILED"))
	quit(0 if ok else 1)


func _build_sprite(path: String, sprite_name: String, edge: int) -> bool:
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		printerr("build_vfx: cannot read %s" % path)
		return false
	image.convert(Image.FORMAT_RGBA8)
	# Crop on a small copy (fast), then map back.
	var probe := image.duplicate() as Image
	var step := 4
	probe.resize(image.get_width() / step, image.get_height() / step, Image.INTERPOLATE_BILINEAR)
	var low := Vector2i(probe.get_width(), probe.get_height())
	var high := Vector2i(-1, -1)
	for y in probe.get_height():
		for x in probe.get_width():
			if probe.get_pixel(x, y).a > CROP_ALPHA:
				low = Vector2i(mini(low.x, x), mini(low.y, y))
				high = Vector2i(maxi(high.x, x), maxi(high.y, y))
	if high.x < 0:
		printerr("build_vfx: %s is empty" % path)
		return false
	var center := Vector2(low + high + Vector2i.ONE) * 0.5 * float(step)
	var side := float(maxi(high.x - low.x, high.y - low.y) + 1) * float(step) * (1.0 + 2.0 * CROP_MARGIN)
	var square := Image.create(int(side), int(side), false, Image.FORMAT_RGBA8)
	square.fill(Color(0, 0, 0, 0))
	var origin := Vector2i(center - Vector2(side, side) * 0.5)
	var src_rect := Rect2i(origin, Vector2i(int(side), int(side))).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	square.blit_rect(image, src_rect, src_rect.position - origin)
	# Transparent pixels take the colour of their visible neighbours, so the
	# downscale and later mipmaps do not pull dark fringes into the edges.
	square.fix_alpha_edges()
	square.resize(edge, edge, Image.INTERPOLATE_LANCZOS)
	var target := "%s/%s.png" % [OUT, sprite_name]
	var error := square.save_png(ProjectSettings.globalize_path(target))
	print("build_vfx: %s -> %s (%d px, crop %d px)" % [path.get_file(), target, edge, int(side)])
	return error == OK


func _layer(body: String) -> Image:
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">%s</svg>' % body
	var image := Image.new()
	image.load_svg_from_string(svg, float(MASK_SIZE) / 512.0)
	image.convert(Image.FORMAT_RGBA8)
	return image


# channels: [fill, dark, coral, pale] images plus per-channel alpha factors.
func _pack(target: String, fill: Image, dark: Image, coral: Image, pale: Image, pale_cut: Image) -> bool:
	var result := Image.create(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_RGBA8)
	for y in MASK_SIZE:
		for x in MASK_SIZE:
			var p := pale.get_pixel(x, y).a
			if pale_cut != null:
				# Pale shapes with a dark outline: the outline wins (SVG draws stroke over fill).
				p *= 1.0 - pale_cut.get_pixel(x, y).a
			result.set_pixel(x, y, Color(fill.get_pixel(x, y).a, dark.get_pixel(x, y).a, coral.get_pixel(x, y).a, p))
	var error := result.save_png(ProjectSettings.globalize_path(target))
	print("build_vfx: mask -> %s" % target)
	return error == OK


func _build_circle() -> bool:
	var tri_fill := '<path d="%s" fill="#fff"/>' % CIRCLE_TRIS
	var tri_stroke := '<path d="%s" fill="none" stroke="#fff" stroke-width="6" stroke-linejoin="round"/>' % CIRCLE_TRIS
	var fill := _layer(CIRCLE_FILL)
	var dark := _layer(CIRCLE_DARK + tri_stroke)
	var coral := _layer(CIRCLE_CORAL)
	# Pale = dashed inner ring (72 %) + triangle fills (full).
	var pale_ring := _layer(CIRCLE_PALE)
	var pale := _layer(tri_fill)
	for y in MASK_SIZE:
		for x in MASK_SIZE:
			var ring := pale_ring.get_pixel(x, y).a * CIRCLE_PALE_RING_ALPHA
			var c := pale.get_pixel(x, y)
			c.a = maxf(c.a, ring)
			pale.set_pixel(x, y, c)
	return _pack(OUT + "/boss_telegraph_circle_mask.png", fill, dark, coral, pale, _layer(tri_stroke))


func _build_cone() -> bool:
	var diamond_fill := '<path d="%s" fill="#fff"/>' % CONE_DIAMOND
	var diamond_stroke := '<path d="%s" fill="none" stroke="#fff" stroke-width="6"/>' % CONE_DIAMOND
	var fill := _layer(CONE_FILL)
	var dark := _layer(CONE_DARK + diamond_stroke)
	var coral := _layer(CONE_CORAL)
	var pale := _layer(diamond_fill + CONE_CHEVRONS)
	return _pack(OUT + "/boss_telegraph_cone_mask.png", fill, dark, coral, pale, _layer(diamond_stroke))
