extends RefCounted

# Shared look for every UI component (stage 04). Colours come from the concept
# sheets in Swarm/Design (active HUD, mutation choice). Components use these
# tokens instead of literals so the whole UI stays one family.

# Surfaces
const PANEL := Color("0c1d17e8")        # deep green-black card body
const PANEL_SOFT := Color("12281fcc")   # secondary panels, chips
const PANEL_EDGE := Color("2f4b3a")     # quiet inner stroke
const SHADOW := Color("03090680")
const DIM := Color("050b08b8")           # world dimmer behind overlays

# Text
const TEXT := Color("f4ecd8")
const TEXT_DIM := Color("a9b8a2")
const BONE := Color("efe2c0")            # claws, teeth, ornaments
const OUTLINE := Color("07110d")         # text outline

# Accents (the frame colour carries meaning; text repeats it)
const EMBER := Color("ff7a2e")           # player, attack, Rally
const EMBER_GLOW := Color("ffb347")
const CYAN := Color("3fe6d8")            # growth, brood, DNA
const VIOLET := Color("b07ae8")          # mutation, special, evolution
const TOXIC := Color("9be15d")           # protection, spores
const DANGER := Color("ff4a3a")          # threat, pressure, loss
const GOLD := Color("f5c86a")            # rewards, boss, crowns
const AMBER := Color("efb642")           # biomass, Alpha-Kern core

const CATEGORY := {"attack": EMBER, "growth": CYAN, "special": VIOLET, "protect": TOXIC, "reflex": VIOLET}

# Colour-blind palette (stage 05), after Okabe & Ito: stays apart under
# deuteranopia and protanopia because it pairs blue with orange/yellow and adds
# white/black instead of relying on red against green. Meaning must never rest
# on colour alone: telegraphs also carry patterns (scripts/telegraph_style.gd).
const CB_ORANGE := Color("e69f00")
const CB_SKY := Color("56b4e9")
const CB_GREEN := Color("009e73")        # bluish green, not grass green
const CB_YELLOW := Color("f0e442")
const CB_BLUE := Color("0072b2")
const CB_VERMILLION := Color("d55e00")
const CB_PURPLE := Color("cc79a7")
const CB_WHITE := Color("f7f7f2")
const CB_BLACK := Color("111014")
# Colour-blind equivalents of the accent tokens above (same keys as `accent()`).
const CB_ACCENT := {
	"ember": CB_ORANGE, "cyan": CB_SKY, "violet": CB_PURPLE, "toxic": CB_YELLOW,
	"danger": CB_VERMILLION, "gold": CB_YELLOW, "amber": CB_ORANGE,
}
const ACCENT := {
	"ember": EMBER, "cyan": CYAN, "violet": VIOLET, "toxic": TOXIC,
	"danger": DANGER, "gold": GOLD, "amber": AMBER,
}

# UI skin switch. "calm" (default since the V2 decision) = quiet petrol
# cards, panels and bars from Swarm/Design/UI_Assets_V2 (copied to
# res://assets/ui/v2/); "organic" = the glowing organic frames of stage 04,
# kept as a fully working alternative.
#
# The UPPER_CASE tokens above are the organic palette and stay constant (other
# scripts use them in `const` expressions). Skin-aware colours come from:
#   UiStyle.color("text")   token by name for the current skin (see TOKENS)
#   UiStyle.tone(c)         an organic token (or a colour close to one) mapped
#                           onto the current skin; unchanged in organic and in
#                           colour-blind mode. text()/text_px() and UiFrames
#                           apply it, so labels and frames follow the skin.
const SKINS := ["organic", "calm"]
static var skin := "calm"
const CALM_BG := Color("09191c")
const CALM_TEXT := Color("eaf0d9")
const CALM_TEXT_DIM := Color("a2c4b8")
const CALM_TEAL := Color("4cdacb")      # DNA, growth
const CALM_AMBER := Color("d9aa5b")     # biomass, rewards
const CALM_GOLD := Color("e6c27a")      # crowns, boss, trophies (light amber)
const CALM_ORANGE := Color("e9905d")    # attack
const CALM_ORANGE_LIGHT := Color("f2b36e")  # Rally, highlights
const CALM_DANGER := Color("e57b53")    # threat fill of the kit
const CALM_LEAF := Color("b4d778")      # protection
const CALM_VIOLET := Color("b993e8")    # special
const CALM_EDGE := Color("37645e")      # quiet panel stroke
const CALM_CREAM := Color("f4e7bd")     # focus frame, ornaments

const TOKENS := {
	"organic": {
		"text": TEXT, "text_dim": TEXT_DIM, "bone": BONE, "outline": OUTLINE,
		"panel": PANEL, "panel_soft": PANEL_SOFT, "panel_edge": PANEL_EDGE,
		"shadow": SHADOW, "dim": DIM,
		"ember": EMBER, "ember_glow": EMBER_GLOW, "cyan": CYAN, "violet": VIOLET,
		"toxic": TOXIC, "danger": DANGER, "gold": GOLD, "amber": AMBER,
	},
	"calm": {
		"text": CALM_TEXT, "text_dim": CALM_TEXT_DIM, "bone": CALM_CREAM, "outline": Color("041012"),
		"panel": Color("09191cf0"), "panel_soft": Color("0f2428dc"), "panel_edge": CALM_EDGE,
		"shadow": Color("02080a80"), "dim": Color("071310b8"),
		"ember": CALM_ORANGE, "ember_glow": CALM_ORANGE_LIGHT, "cyan": CALM_TEAL, "violet": CALM_VIOLET,
		"toxic": CALM_LEAF, "danger": CALM_DANGER, "gold": CALM_GOLD, "amber": CALM_AMBER,
	},
}

static var _tone_cache: Dictionary = {}


static func is_calm() -> bool:
	return skin == "calm"


## Colour token of the current skin (the colour-blind swap stays with
## accent(), so this is a drop-in for the UPPER_CASE constants) ("text", "text_dim", "bone", "outline",
## "panel", "panel_soft", "panel_edge", "shadow", "dim", "ember", "ember_glow",
## "cyan", "violet", "toxic", "danger", "gold", "amber").
static func color(token: String) -> Color:
	return TOKENS[skin].get(token, TOKENS["organic"].get(token, TEXT))


## Maps an organic palette colour onto the current skin (alpha kept). Colours
## far from every token (white, custom greys, painted tints) stay unchanged.
## Identity in the organic skin and in colour-blind mode.
static func tone(value: Color) -> Color:
	if skin == "organic" or colorblind:
		return value
	var key := Color(value.r, value.g, value.b, 1.0)
	if not _tone_cache.has(key):
		_tone_cache[key] = _nearest(key, skin)
	var mapped: Color = _tone_cache[key]
	return Color(mapped, value.a)


static func _nearest(value: Color, target: String) -> Color:
	var organic: Dictionary = TOKENS["organic"]
	var table: Dictionary = TOKENS[target]
	# Idempotent: a colour already nearer to the target palette than to the
	# organic one (e.g. a calm token lightened by a component) stays as it is.
	if _distance(value, table) < _distance(value, organic):
		return value
	var best := 0.012
	var mapped := value
	for token in organic:
		var ref: Color = organic[token]
		var d := Vector3(value.r - ref.r, value.g - ref.g, value.b - ref.b).length_squared()
		if d < best:
			best = d
			mapped = table[token]
	if mapped == value:
		# Mixed shades (e.g. EMBER.lerp(WHITE, 0.3)): shift by the offset of the
		# nearest accent so tints keep their family in the new palette.
		best = 0.09
		for token in ["ember", "ember_glow", "cyan", "violet", "toxic", "danger", "gold", "amber", "text", "text_dim", "bone"]:
			var ref: Color = organic[token]
			var d := Vector3(value.r - ref.r, value.g - ref.g, value.b - ref.b).length_squared()
			if d < best:
				best = d
				var to: Color = table[token]
				mapped = Color(clampf(value.r + to.r - ref.r, 0.0, 1.0), clampf(value.g + to.g - ref.g, 0.0, 1.0), clampf(value.b + to.b - ref.b, 0.0, 1.0))
	if mapped == value and target == "calm" and value.v < 0.45 and value.h > 0.18 and value.h < 0.5:
		# Dark moss greens of the organic look (card bodies, wells, tracks)
		# become the kit's petrol with the same saturation and brightness.
		mapped = Color.from_hsv(0.525, minf(value.s, 0.72), value.v)
	return mapped


static func _distance(value: Color, table: Dictionary) -> float:
	var best := 9.0
	for token in table:
		var ref: Color = table[token]
		best = minf(best, Vector3(value.r - ref.r, value.g - ref.g, value.b - ref.b).length_squared())
	return best


## Switches the skin at runtime and repaints every Control (cached UiLayers
## are invalidated so they bake again with the new frames).
static func set_skin(value: String) -> void:
	if not SKINS.has(value) or value == skin:
		return
	skin = value
	_tone_cache.clear()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	for node in tree.root.find_children("*", "Control", true, false):
		if node.has_method("invalidate"):
			node.invalidate()
		(node as Control).queue_redraw()


# Colour-blind mode switch. Persisting it in the settings is the menu's job;
# readers call `accent()` or check the flag when they build their visuals.
static var colorblind := false


# Accent colour by token name, honouring the colour-blind switch.
static func accent(token: String) -> Color:
	if colorblind:
		return CB_ACCENT.get(token, TEXT)
	return TOKENS[skin].get(token, TEXT)

# Type scale in base-viewport pixels (900 x 1600). Nothing readable below 20.
const SIZE_HERO := 72
const SIZE_TITLE := 48
const SIZE_HEAD := 34
const SIZE_BODY := 26
const SIZE_LABEL := 22

const DISPLAY_FONT_PATH := "res://assets/ui/fonts/display.ttf"
const BODY_FONT_PATH := "res://assets/ui/fonts/body.ttf"

static var _fonts: Dictionary = {}
static var _textures: Dictionary = {}
static var _boxes: Dictionary = {}


# Condensed heavy display face for numbers and titles. Until a real font file is
# added the fallback font is emboldened and tightened so layouts stay stable.
static func display_font() -> Font:
	if not _fonts.has("display"):
		_fonts["display"] = _load_font(DISPLAY_FONT_PATH, 0.9, -1)
	return _fonts["display"]


static func body_font() -> Font:
	if not _fonts.has("body"):
		_fonts["body"] = _load_font(BODY_FONT_PATH, 0.35, 0)
	return _fonts["body"]


static func _load_font(path: String, embolden: float, spacing: int) -> Font:
	if ResourceLoader.exists(path):
		return load(path)
	var variation := FontVariation.new()
	variation.base_font = ThemeDB.fallback_font
	variation.variation_embolden = embolden
	variation.spacing_glyph = spacing
	return variation


# Cached texture (SVG/PNG) or null when the file does not exist yet.
static func tex(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _textures[path]


# Nine-slice box from a texture; margins in texture pixels (left, top, right, bottom).
static func nine(path: String, margins: Vector4, tint: Color = Color.WHITE) -> StyleBoxTexture:
	var key := "%s|%s|%s" % [path, margins, tint]
	if not _boxes.has(key):
		var box := StyleBoxTexture.new()
		box.texture = tex(path)
		box.texture_margin_left = margins.x
		box.texture_margin_top = margins.y
		box.texture_margin_right = margins.z
		box.texture_margin_bottom = margins.w
		box.modulate_color = tint
		_boxes[key] = box
	return _boxes[key]


# Outlined text; align center when centered. Returns the drawn width.
static func text(canvas: CanvasItem, value: String, at: Vector2, size: int, tint: Color = TEXT, centered: bool = false, outline: int = 6, font: Font = null) -> float:
	var face: Font = font if font != null else display_font()
	var width := face.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var origin := at - Vector2(width * 0.5, 0.0) if centered else at
	if outline > 0:
		canvas.draw_string_outline(face, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, outline_color())
	canvas.draw_string(face, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, tone(tint))
	return width


# Text outline of the current skin.
static func outline_color() -> Color:
	return color("outline")


# Stage 07: every rasterised font size costs a glyph cache (~0.8 MB RAM and
# ~0.3 MB VRAM per size with outline). Animated or fitted sizes (pop, zoom,
# shrink-to-fit) therefore never rasterise their own size: they pick the next
# larger size of this palette and scale it down with draw_set_transform.
const SIZE_STEPS := [22, 26, 30, 34, 38, 44, 48, 54, 64, 72, 84, 96, 110]


# Palette size a fractional size is drawn from (the next larger one).
static func size_step(px: float) -> int:
	for step in SIZE_STEPS:
		if step >= px - 0.01:
			return step
	return int(ceil(px))


# Width of `value` at a fractional size (same measure text_px() draws with).
static func width_px(value: String, px: float, font: Font = null) -> float:
	var face: Font = font if font != null else display_font()
	var step := size_step(px)
	return face.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, step).x * px / step


# Outlined text at a fractional size: drawn at a palette size and scaled, so a
# pulsing or fitted label adds no new glyph cache. Palette sizes draw exactly
# like text(). Returns the drawn width.
static func text_px(canvas: CanvasItem, value: String, at: Vector2, px: float, tint: Color = TEXT, centered: bool = false, outline: int = 6, font: Font = null) -> float:
	var step := size_step(px)
	if absf(px - step) < 0.01:
		return text(canvas, value, at, step, tint, centered, outline, font)
	var face: Font = font if font != null else display_font()
	var k := px / step
	var width := face.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, step).x * k
	var origin := at - Vector2(width * 0.5, 0.0) if centered else at
	canvas.draw_set_transform(origin, 0.0, Vector2(k, k))
	if outline > 0:
		canvas.draw_string_outline(face, Vector2.ZERO, value, HORIZONTAL_ALIGNMENT_LEFT, -1, step, outline, outline_color())
	canvas.draw_string(face, Vector2.ZERO, value, HORIZONTAL_ALIGNMENT_LEFT, -1, step, tone(tint))
	canvas.draw_set_transform(Vector2.ZERO)
	return width
