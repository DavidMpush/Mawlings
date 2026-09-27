extends RefCounted

# Painted expansion art of the V2 UI kit (EXPANSION_ASSETS.md): menu
# background, logo, biome cards, strain and boss portraits, launcher icons.
# Small copies live in res://assets/ui/v3/ (built by assets/ui/v3/build_v3.py).
# Usage: const UiArt := preload("res://scripts/ui/ui_art.gd")
#        UiArt.draw_cover(canvas, UiArt.biome("glutsumpf"), shape_points, rect)
# Every getter returns null when the file is missing, so callers keep their
# drawn fallback.

const DIR := "res://assets/ui/v3/"
## Boss portraits that match a game boss (spine_mother/crownfang have no match).
const BOSSES := ["bog_king"]

static var _cache: Dictionary = {}


static func texture(file: String) -> Texture2D:
	if not _cache.has(file):
		var p := DIR + file
		_cache[file] = load(p) if ResourceLoader.exists(p) else null
	return _cache[file]


static func logo() -> Texture2D:
	return texture("logo.png")


static func menu_background() -> Texture2D:
	return texture("menu_background.png")


static func biome(id: String) -> Texture2D:
	return texture("biomes/%s.png" % id)


static func tribe(strain: String) -> Texture2D:
	return texture("tribes/%s.png" % strain)


## Portrait for a boss id ("bog_king", "boss" = Bog King); null for bosses
## without matching art (Moosschlund, Aschenkröte).
static func boss(id: String) -> Texture2D:
	if id == "boss" or id == "bog_king_portrait":
		id = "bog_king"
	return texture("bosses/%s.png" % id) if BOSSES.has(id) else null


## Draws `tex` filling `rect` like CSS object-fit: cover, clipped to the convex
## polygon `points` (inside rect). `focus` (0..1) picks the visible part.
static func draw_cover(canvas: CanvasItem, tex: Texture2D, points: PackedVector2Array, rect: Rect2, modulate := Color.WHITE, focus := Vector2(0.5, 0.5)) -> void:
	var tex_size := Vector2(tex.get_size())
	var scale := maxf(rect.size.x / tex_size.x, rect.size.y / tex_size.y)
	var shown := rect.size / (tex_size * scale)   # visible share of the texture (<= 1)
	var origin := (Vector2.ONE - shown) * focus
	var uvs := PackedVector2Array()
	for p in points:
		uvs.append(origin + (p - rect.position) / rect.size * shown)
	canvas.draw_colored_polygon(points, modulate, uvs, tex)


## Draws `tex` with its aspect kept, bottom-centred on `foot`, `height` tall.
static func draw_standing(canvas: CanvasItem, tex: Texture2D, foot: Vector2, height: float, modulate := Color.WHITE) -> Rect2:
	var s := Vector2(tex.get_size()) * (height / float(tex.get_height()))
	var r := Rect2(foot - Vector2(s.x * 0.5, s.y), s)
	canvas.draw_texture_rect(tex, r, false, modulate)
	return r
