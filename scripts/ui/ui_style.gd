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

# Type scale in base-viewport pixels (900 x 1600). Nothing readable below 20.
const SIZE_HERO := 72
const SIZE_TITLE := 48
const SIZE_HEAD := 34
const SIZE_BODY := 26
const SIZE_LABEL := 21

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
static func text(canvas: CanvasItem, value: String, at: Vector2, size: int, color: Color = TEXT, centered: bool = false, outline: int = 6, font: Font = null) -> float:
	var face: Font = font if font != null else display_font()
	var width := face.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var origin := at - Vector2(width * 0.5, 0.0) if centered else at
	if outline > 0:
		canvas.draw_string_outline(face, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, OUTLINE)
	canvas.draw_string(face, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	return width
