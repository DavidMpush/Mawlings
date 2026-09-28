"""Icon standard V4 (Supercell style), see ART_UI_PLAN.md "Icon-Standard".

Builds assets/ui/v4/icons/<id>.png (256 px) from the project copies only:
  * painted icons (UI kit V2 PNGs, V3 expansion PNGs, painted SVGs) get one
    common crop, centring, a uniform dark contour and a small bottom shadow;
    a few near-identical "red teeth" icons get their category colour;
  * control glyphs (pause, play, clock, lock, reroll, restart, banish, skip) are
    redrawn as white Supercell glyphs with a thick dark contour, so callers can
    tint them.
The user's originals (Swarm/Design) are never touched; the SVG sources are
rasterised through Godot (assets/ui/v4/rasterize_svg.gd).

Run from the project root:  python assets/ui/v4/build_icons_v4.py
Needs numpy, scipy and Pillow, and the Godot console exe (GODOT env var or the
default path below). Afterwards run the Godot import once.
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent / "icons"
GODOT = os.environ.get("GODOT", r"C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe")

SIZE = 256          # final texture size
WORK = 512          # processing size for painted icons (2x)
BOX = 0.89          # content (incl. contour) fills 89 % of the canvas side
CONTOUR = (24, 14, 12)          # near-black warm brown, like the V2 outlines
CONTOUR_PX = 5.0    # uniform contour at 256 px (~0.8 px at 40 px, on top of the painted line)
SHADOW_PX = 5.0     # bottom shadow offset at 256 px

# game id -> source (relative to project root). "svg:<id>" = painted SVG.
PAINTED = {
    # V2 base traits
    "jaws": "assets/ui/v2/icons/jaws.png",
    "brood": "assets/ui/v2/icons/brood.png",
    "glutton": "assets/ui/v2/icons/glutton.png",
    "pack": "assets/ui/v2/icons/pack.png",
    "scatter": "assets/ui/v2/icons/scatter.png",
    "armor": "assets/ui/v2/icons/armor.png",
    # V3 expansion art
    "rudelbiss": "assets/ui/v3/icons/leap.png",
    "sporenwolke": "assets/ui/v3/icons/spore_burst.png",
    "saeurespucker": "assets/ui/v3/icons/acid_spit.png",
    "blitzbiss": "assets/ui/v3/icons/sickle_slash.png",
    "graeber": "assets/ui/v3/icons/slam.png",
    "meute": "assets/ui/v3/icons/swarm_wave.png",
    "stachelruecken": "assets/ui/v3/icons/spikeback.png",
    "brutsack": "assets/ui/v3/icons/brood_sac.png",
    "nest": "assets/ui/v3/icons/brood_nest.png",
    "totem": "assets/ui/v3/icons/curse_totem.png",
    "dna": "assets/ui/v3/icons/dna.png",
    "biomass": "assets/ui/v3/icons/biomass.png",
    "currency_dna": "assets/ui/v3/icons/dna.png",
    "currency_biomass": "assets/ui/v3/icons/biomass.png",
    "branch_growth": "assets/ui/v3/icons/hunger_mass.png",
    "branch_attack": "assets/ui/v3/icons/razor_offense.png",
    "branch_protect": "assets/ui/v3/icons/carapace_survival.png",
    "branch_special": "assets/ui/v3/icons/mutation_special.png",
    # Stage 17 weapons without own art yet: closest painted motif (ICON_REQUESTS / UI_ASSET_REQUESTS).
    "klauenwirbel": "assets/ui/v3/icons/razor_offense.png",   # three curved bone claw blades
    "giftbiss": "assets/ui/v3/icons/bite.png",                 # snapping jaw, recoloured toxic green
    # Swarm head: bust crops of the painted tribe portraits (assets/ui/v3/heads,
    # built by assets/ui/v3/build_v3.py). mawling_head_color = Glutmaw (player colour),
    # mawling_head = the same head in bone white for tinting (see HEAD_TINTABLE).
    "mawling_head_color": "assets/ui/v3/heads/glutmaw.png",
    "mawling_head": "assets/ui/v3/heads/glutmaw.png",
}
STRAINS = ["glutmaw", "sporling", "knochenkiefer", "flinkzahn", "aetzmaul", "nachtmaul"]
for _strain in STRAINS:
    PAINTED["mawling_head_" + _strain] = f"assets/ui/v3/heads/{_strain}.png"
# Ids turned into a light bone-white monochrome (painted shading kept) so a tint colours them.
HEAD_TINTABLE = ["mawling_head"]
SVG_PAINTED = [
    "aetzflut", "erdbeben", "sturmrudel", "regeneration", "dornenhaut",
    "essence", "crown_tooth", "skull", "crown", "alpha_core",
    "trophy", "biome_verdant", "biome_glutsumpf", "diff_wild", "diff_brutal", "diff_apex",
    "hunter", "skitter", "leaper", "nibbler", "bog_king", "instinct", "hub",
]
for _id in SVG_PAINTED:
    PAINTED[_id] = "svg:" + _id

# V5 originals from the UI asset request: each motif keeps its own meaning.
# This deliberately overrides the earlier SVG and reused V3/V2 sources.
V5_PAINTED = [
    "schallbrueller", "glutdruese", "pilzreich", "dornenwall", "sturmrudel",
    "crit", "haste", "reach", "vigor", "gene", "speed", "luck", "magnet",
    "pack", "scatter", "pu_rausch", "pu_blutrausch", "pu_magnetsturm",
    "pu_chitinschild", "pu_raserei", "pu_brutwelle", "cocoon", "shrine",
    "essence", "crown_tooth", "flood", "pressure", "tab_brutkammer",
    "trophy", "tab_instinct", "tab_chronicle", "hub", "alpha_core",
    "crown", "evo_badge",
]
for _id in V5_PAINTED:
    PAINTED[_id] = f"assets/ui/v5/icons/{_id}.png"

# Category recolours for the look-alike teeth icons: (hue_lo, hue_hi, target_hue, sat_mul, val_mul).
# Hue in degrees; only saturated pixels in the range change (teeth, tongue, swirl stay).
RECOLOUR = {
    "glutton": [(6, 38, 40, 1.05, 1.12)],    # Vielfraß -> Beute-Gold (tongue and orb stay)
    "pack": [(6, 38, 352, 1.0, 0.92)],        # Rudelinstinkt -> Karmesin, darker than Reißzähne
    "meute": [(6, 38, 278, 0.85, 1.0)],       # Meute (Evolution) -> Violett, cyan wave stays
    "armor": [(285, 355, 128, 0.8, 0.95)],    # Knochenpanzer: violet base -> Schutz-Grün
    "giftbiss": [(0, 45, 100, 1.0, 1.0)],     # Giftbiss: ember jaw -> toxic green, ivory fangs stay
}

GLYPHS = ["pause", "play", "clock", "lock", "reroll", "restart", "banish", "skip"]


# ---------------------------------------------------------------- helpers

def recolour(img, specs):
    arr = np.array(img).astype(np.float32)
    alpha = arr[..., 3].copy()
    hsv = np.array(Image.fromarray(arr[..., :3].astype(np.uint8), "RGB").convert("HSV")).astype(np.float32)
    hue = hsv[..., 0] * 360.0 / 255.0
    for lo, hi, target, sat_mul, val_mul in specs:
        mask = ((hue >= lo) | (hue <= hi)) if lo > hi else ((hue >= lo) & (hue <= hi))
        mask &= hsv[..., 1] > 36
        hsv[..., 0] = np.where(mask, target * 255.0 / 360.0, hsv[..., 0])
        hsv[..., 1] = np.where(mask, np.clip(hsv[..., 1] * sat_mul, 0, 255), hsv[..., 1])
        hsv[..., 2] = np.where(mask, np.clip(hsv[..., 2] * val_mul, 0, 255), hsv[..., 2])
    rgb = np.array(Image.fromarray(hsv.astype(np.uint8), "HSV").convert("RGB"))
    return Image.fromarray(np.dstack([rgb, alpha.astype(np.uint8)]), "RGBA")


def bone_white(img):
    """Light warm monochrome of a painted image (shading kept, alpha kept), so
    a tint colours it like the white glyphs while the painted form stays."""
    arr = np.array(img).astype(np.float32) / 255.0
    lum = arr[..., 0] * 0.3 + arr[..., 1] * 0.55 + arr[..., 2] * 0.15
    lo, hi = np.percentile(lum[arr[..., 3] > 0.5], [3, 97])
    v = np.clip((lum - lo) / max(hi - lo, 1e-3), 0.0, 1.0)
    v = 0.42 + 0.58 * v ** 0.7     # dark lines and mouth stay readable, faces go light
    tone = np.array([1.0, 0.97, 0.92], np.float32)
    out = np.dstack([v[..., None] * tone, arr[..., 3:4]])
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), "RGBA")


def dilate(alpha, radius):
    """Soft round dilation of an alpha mask (0..1) by `radius` pixels."""
    dist = ndimage.distance_transform_edt(alpha < 0.5)
    return np.clip(radius + 0.5 - dist, 0.0, 1.0)


def contour_layer(alpha, radius, shadow):
    """Contour mask (round dilation) plus a copy shifted down as bottom shadow."""
    ring = dilate(alpha, radius)
    shift = int(round(shadow))
    if shift > 0:
        below = np.zeros_like(ring)
        below[shift:] = ring[:-shift]
        ring = np.maximum(ring, below)
    return ring


def over(top, bottom):
    """Straight-alpha 'over' of two float RGBA arrays (0..1)."""
    ta = top[..., 3:4]
    ba = bottom[..., 3:4]
    oa = ta + ba * (1.0 - ta)
    rgb = (top[..., :3] * ta + bottom[..., :3] * ba * (1.0 - ta)) / np.maximum(oa, 1e-6)
    return np.concatenate([rgb, oa], axis=-1)


def solid(mask, colour):
    out = np.zeros(mask.shape + (4,), np.float32)
    out[..., :3] = np.array(colour, np.float32) / 255.0
    out[..., 3] = mask
    return out


def fit_canvas(img, canvas, box):
    """Trim to the visible alpha, scale the longer side to box*canvas, centre."""
    bb = img.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    img = img.crop(bb)
    target = box * canvas
    k = target / max(img.size)
    img = img.resize((max(1, round(img.size[0] * k)), max(1, round(img.size[1] * k))), Image.LANCZOS)
    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    out.alpha_composite(img, ((canvas - img.size[0]) // 2, (canvas - img.size[1]) // 2))
    return out


def standardise(img, contour_px=CONTOUR_PX, shadow_px=SHADOW_PX):
    """Common crop + contour + bottom shadow, at WORK size, returns SIZE image."""
    scale = WORK / SIZE
    img = fit_canvas(img, WORK, BOX - 2.0 * (contour_px + shadow_px * 0.5) / SIZE)
    arr = np.array(img).astype(np.float32) / 255.0
    ring = contour_layer(arr[..., 3], contour_px * scale, shadow_px * scale)
    arr = over(arr, solid(ring, CONTOUR))
    img = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGBA")
    img = fit_canvas(img, WORK, BOX)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


# ---------------------------------------------------------------- glyphs
# Drawn at 4x (1024) as masks: `body` (white), `detail` (dark cut-outs on
# the body). Contour + bottom shadow like the painted icons, thicker.

G = 1024
GLYPH_CONTOUR = 11.0   # at 256 px
GLYPH_SHADOW = 7.0


def _mask():
    return Image.new("L", (G, G), 0)


def _arrow_head(draw, c, r, ang, t, direction):
    """Triangle arrow head at angle `ang` (deg, PIL convention) pointing along the arc."""
    a = np.radians(ang)
    w = t * 1.3
    d = direction * t * 1.5 / r
    p1 = (c[0] + (r - w) * np.cos(a), c[1] + (r - w) * np.sin(a))
    p2 = (c[0] + (r + w) * np.cos(a), c[1] + (r + w) * np.sin(a))
    tip = (c[0] + r * np.cos(a + d), c[1] + r * np.sin(a + d))
    draw.polygon([p1, p2, tip], fill=255)


def _arc(draw, c, r, t, start, end):
    draw.arc([c[0] - r - t / 2, c[1] - r - t / 2, c[0] + r + t / 2, c[1] + r + t / 2], start, end, fill=255, width=int(t))
    for ang in (start, end):  # round caps
        a = np.radians(ang)
        x, y = c[0] + r * np.cos(a), c[1] + r * np.sin(a)
        draw.ellipse([x - t / 2, y - t / 2, x + t / 2, y + t / 2], fill=255)


def glyph_pause():
    body, detail = _mask(), _mask()
    d = ImageDraw.Draw(body)
    d.rounded_rectangle([282, 212, 452, 812], 60, fill=255)
    d.rounded_rectangle([572, 212, 742, 812], 60, fill=255)
    return body, detail


def glyph_play():
    body, detail = _mask(), _mask()
    d = ImageDraw.Draw(body)
    pts = [(330, 250), (770, 512), (330, 774)]
    d.polygon(pts, fill=255)
    # rounded corners: a 100 px stroke around the inner triangle
    d.line(pts + [pts[0]], fill=255, width=100, joint="curve")
    for x, y in pts:
        d.ellipse([x - 50, y - 50, x + 50, y + 50], fill=255)
    return body, detail


def glyph_skip():
    body, detail = _mask(), _mask()
    d = ImageDraw.Draw(body)
    for dx in (0, 270):
        x = 150 + dx
        d.polygon([(x, 250), (x + 190, 250), (x + 452, 512), (x + 190, 774), (x, 774), (x + 262, 512)], fill=255)
    return body, detail


def glyph_banish():
    body, detail = _mask(), _mask()
    d = ImageDraw.Draw(body)
    d.ellipse([132, 132, 892, 892], fill=255)
    d.ellipse([252, 252, 772, 772], fill=0)
    # diagonal bar from top-left to bottom-right
    c, h, w = 512, 330, 58
    k = 1 / np.sqrt(2)
    pts = [(c - h * k - w * k, c - h * k + w * k), (c - h * k + w * k, c - h * k - w * k),
           (c + h * k + w * k, c + h * k - w * k), (c + h * k - w * k, c + h * k + w * k)]
    d.polygon(pts, fill=255)
    return body, detail


def glyph_lock():
    body, detail = _mask(), _mask()
    d = ImageDraw.Draw(body)
    _arc(d, (512, 430), 185, 96, 180, 360)
    d.rectangle([327 - 48, 430, 327 + 48, 540], fill=255)
    d.rectangle([697 - 48, 430, 697 + 48, 540], fill=255)
    d.rounded_rectangle([226, 486, 798, 898], 84, fill=255)
    dd = ImageDraw.Draw(detail)
    dd.ellipse([452, 590, 572, 710], fill=255)
    dd.polygon([(482, 660), (542, 660), (566, 800), (458, 800)], fill=255)
    return body, detail


def glyph_clock():
    body, detail = _mask(), _mask()
    d = ImageDraw.Draw(body)
    c = (512, 566)
    d.ellipse([c[0] - 340, c[1] - 340, c[0] + 340, c[1] + 340], fill=255)
    d.rounded_rectangle([432, 112, 592, 196], 30, fill=255)
    d.rectangle([472, 170, 552, 250], fill=255)
    # side button at 45 degrees (top right)
    a = np.radians(-45)
    bx, by = c[0] + 330 * np.cos(a), c[1] + 330 * np.sin(a)
    ux, uy = np.cos(a), np.sin(a)
    px, py = -uy, ux
    pts = [(bx + px * 48 - ux * 20, by + py * 48 - uy * 20), (bx - px * 48 - ux * 20, by - py * 48 - uy * 20),
           (bx - px * 48 + ux * 80, by - py * 48 + uy * 80), (bx + px * 48 + ux * 80, by + py * 48 + uy * 80)]
    d.polygon(pts, fill=255)
    dd = ImageDraw.Draw(detail)
    dd.line([c, (c[0], c[1] - 210)], fill=255, width=70)
    dd.line([c, (c[0] + 160, c[1] + 40)], fill=255, width=70)
    for p in [(c[0], c[1] - 210), (c[0] + 160, c[1] + 40), c]:
        dd.ellipse([p[0] - 35, p[1] - 35, p[0] + 35, p[1] + 35], fill=255)
    dd.ellipse([c[0] - 58, c[1] - 58, c[0] + 58, c[1] + 58], fill=255)
    for ang in (0, 90, 180):
        a = np.radians(ang)
        x, y = c[0] + 268 * np.cos(a), c[1] + 268 * np.sin(a)
        dd.ellipse([x - 26, y - 26, x + 26, y + 26], fill=255)
    return body, detail


def glyph_restart():
    """Single replay arrow: open at the top, head on the left end pointing right."""
    body, detail = _mask(), _mask()
    d = ImageDraw.Draw(body)
    c, r, t = (512, 548), 300, 118
    _arc(d, c, r, t, 300, 588)
    _arrow_head(d, c, r, 228, t, 1)
    return body, detail


def glyph_reroll():
    """Two chasing arrows (refresh/cycle)."""
    body, detail = _mask(), _mask()
    d = ImageDraw.Draw(body)
    c, r, t = (512, 512), 300, 104
    _arc(d, c, r, t, 200, 318)
    _arrow_head(d, c, r, 318, t, 1)
    _arc(d, c, r, t, 20, 138)
    _arrow_head(d, c, r, 138, t, 1)
    return body, detail


def render_glyph(fn):
    body, detail = fn()
    b = np.array(body).astype(np.float32) / 255.0
    det = np.array(detail).astype(np.float32) / 255.0 * b
    scale = G / SIZE
    ring = contour_layer(b, GLYPH_CONTOUR * scale, GLYPH_SHADOW * scale)
    # white body with a soft cool shade on the lower third (light from above)
    y = np.linspace(0.0, 1.0, G, dtype=np.float32)[:, None]
    shade = np.clip((y - 0.55) / 0.35, 0.0, 1.0)
    fill = np.zeros((G, G, 4), np.float32)
    top, low = np.array([1.0, 1.0, 1.0]), np.array([0.80, 0.84, 0.86])
    fill[..., :3] = top * (1 - shade[..., None]) + low * shade[..., None]
    fill[..., 3] = b
    # dark cut-outs keep the contour colour so tinting never loses them
    out = over(solid(det, CONTOUR), over(fill, solid(ring, CONTOUR)))
    img = Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), "RGBA")
    img = fit_canvas(img, G, BOX)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


# ---------------------------------------------------------------- main

def rasterise_svgs(ids, tmp):
    cmd = [GODOT, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT),
           "--script", "res://assets/ui/v4/rasterize_svg.gd", "--", str(tmp), str(WORK / SIZE)] + ids
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)


def main():
    """Optional arguments: only build these ids (e.g. mawling_head giftbiss)."""
    only = set(sys.argv[1:])
    OUT.mkdir(parents=True, exist_ok=True)
    painted = {i: s for i, s in PAINTED.items() if not only or i in only}
    svg_ids = [i for i, src in painted.items() if src.startswith("svg:")]
    with tempfile.TemporaryDirectory() as tmp:
        if svg_ids:
            rasterise_svgs(svg_ids, tmp)
        for gid, src in painted.items():
            if src.startswith("svg:"):
                img = Image.open(Path(tmp) / (src[4:] + ".png")).convert("RGBA")
            else:
                img = Image.open(ROOT / src).convert("RGBA")
                if max(img.size) < WORK:
                    img = img.resize((img.size[0] * 2, img.size[1] * 2), Image.LANCZOS)
            if gid in RECOLOUR:
                img = recolour(img, RECOLOUR[gid])
            if gid in HEAD_TINTABLE:
                img = bone_white(img)
            standardise(img).save(OUT / f"{gid}.png", optimize=True)
    glyphs = [g for g in GLYPHS if not only or g in only]
    for gid in glyphs:
        render_glyph(globals()["glyph_" + gid]).save(OUT / f"{gid}.png", optimize=True)
    print(f"built {len(painted)} painted icons and {len(glyphs)} glyphs into {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    sys.exit(main())
