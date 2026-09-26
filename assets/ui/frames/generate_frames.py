"""Generates the MAWLINGS UI frame kit (stage 04, agent FRAMES).

All SVGs are authored in base-viewport units (900 x 1600 layout pixels) and
imported with svg/scale = 2.0, so ui_frames.gd draws them at 0.5 texture scale
and they stay sharp on phones. Layers:
  *_body  fixed dark colours (never tinted)
  *_edge  white/grey rim, tinted with the accent via modulate
  *_glow  soft white halo from stacked low-alpha strokes, tinted, drawn first
Nine-slice margins are listed in ui_frames.gd (SVG units, including padding).
Keep the middle strips of every frame periodic/straight so tiling or stretching
never distorts corners, claws or notches.

Run:  python assets/ui/frames/generate_frames.py
"""
import math
import os
import re

OUT = os.path.dirname(os.path.abspath(__file__))

BAND = "#17321f"
BAND_DARK = "#0c1d14"
VEIN = "#3b6a47"
VEIN_DARK = "#07120c"
BODY_TOP = "#11261c"
BODY_BOTTOM = "#07130e"
HOLE = "#020604"
BONE = "#efe2c0"
BONE_SHADE = "#a8916a"
BONE_DARK = "#2a1f12"


def svg(w, h, body):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">\n'
        f"{body}\n</svg>\n"
    )


def save(name, w, h, body):
    with open(os.path.join(OUT, name + ".svg"), "w", encoding="utf-8") as f:
        f.write(svg(w, h, body))


def wave(x0, x1, y, amp, period, phase=0.0, step=4.0):
    pts = []
    x = x0
    while x <= x1 + 0.01:
        pts.append((x, y + amp * math.sin(2 * math.pi * (x - phase) / period)))
        x += step
    return "M " + " L ".join(f"{px:.1f},{py:.1f}" for px, py in pts)


def glow_strokes(path, widths=((22, 0.06), (14, 0.11), (8, 0.2), (4, 0.34)), extra=""):
    return "\n".join(
        f'<path d="{path}" fill="none" stroke="#fff" stroke-opacity="{o}" stroke-width="{w}" stroke-linejoin="round" {extra}/>'
        for w, o in widths
    )


# ---------------------------------------------------------------- card
# 420 x 260, visual card box 18..402 x 18..242 (pad 18). Nine-slice 150/100/150/100.
# Middle horizontal strip x 150..270 (120) is tiled: every edge detail inside it
# repeats with period 60 or 120 so tiles join seamlessly.
CARD_W, CARD_H = 420, 260
TILE_X0, TILE = 150, 120


def mirror_y(path, h=CARD_H):
    return re.sub(r"(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)", lambda m: f"{m.group(1)},{h - float(m.group(2)):g}", path)


def wavy(x0, x1, y, amp, period=60, step=5):
    """Polyline points (without M) along a periodic wave locked to the tile."""
    pts = []
    x = x0
    direction = 1 if x1 > x0 else -1
    while (x - x1) * direction <= 0.01:
        pts.append(f"{x:.1f},{y + amp * math.sin(2 * math.pi * (x - TILE_X0) / period):.2f}")
        x += step * direction
    return " L ".join(pts)


CARD_OUTER = (
    "M 72,30 L " + wavy(72, 300, 30, 1.4) + " "
    "C 306,30 308,22 316,22 L 352,22 C 378,22 394,38 394,64 "
    "L 394,70 C 394,78 383,80 383,88 C 383,96 394,98 394,104 "
    "L 394,196 C 394,218 380,230 356,230 L 334,230 L 322,218 L 310,230 L 300,230 "
    "L " + wavy(300, 72, 230, 1.4) + " "
    "C 44,230 26,214 26,188 L 26,104 C 26,98 39,94 39,84 C 39,74 26,71 26,66 "
    "C 26,44 44,30 72,30 Z"
)
CARD_INNER = "M 76,54 L 348,54 Q 364,54 364,70 L 364,190 Q 364,206 348,206 L 76,206 Q 60,206 60,190 L 60,70 Q 60,54 76,54 Z"
def mirror_x(path, w=CARD_W):
    return re.sub(r"(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)", lambda m: f"{w - float(m.group(1)):g},{m.group(2)}", path)


# Curved hook horns: wide root on the frame corner, thin tip curling inward.
_TL_HORN = "M 28,84 C 10,64 2,36 12,14 C 16,6 24,2 34,2 C 26,10 24,20 30,30 C 36,38 50,38 64,34 C 48,46 36,62 28,84 Z"
_TL_SPINE = "M 24,70 C 14,50 14,28 26,12"
_TL_THORN = "M 106,31 C 112,22 118,16 128,10 C 126,18 127,25 130,31 Z"
_BR_SPUR = "M 344,230 C 352,240 364,248 378,252 C 372,244 368,236 366,228 Z"
CARD_HORNS = [_TL_HORN, _TL_THORN, mirror_x(_TL_HORN), mirror_y(_TL_HORN), mirror_x(mirror_y(_TL_HORN))]
CARD_SPINES = [_TL_SPINE, mirror_x(_TL_SPINE), mirror_y(_TL_SPINE), mirror_x(mirror_y(_TL_SPINE))]
CARD_CELLS = [(334, 76, 8), (352, 74, 6), (343, 91, 6.5), (358, 90, 4.5), (324, 92, 5), (333, 105, 3.8)]
CARD_HOLES = [(43, 176, 7, 12), (45, 204, 5, 7), (48, 60, 4, 6), (379, 180, 5, 9), (378, 202, 3.5, 6)]
# pits in the top/bottom band, one tile worth of offsets
_PITS = [(8, 0, 4.4, 2.6), (29, -3, 2.4, 1.7), (51, 2, 3.6, 2.2), (74, -2, 2.2, 1.6), (94, 1, 4.8, 2.8), (112, -3, 2.1, 1.5)]


def card_pits(y_center, flip=1):
    out = []
    for start in range(TILE_X0 - 2 * TILE, 420, TILE):
        for dx, dy, rx, ry in _PITS:
            x = start + dx
            if 64 <= x <= 300:
                out.append((x, y_center + dy * flip, rx, ry))
    return out


def card_body():
    parts = [
        "<defs>",
        f'<linearGradient id="b" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{BODY_TOP}"/><stop offset="1" stop-color="{BODY_BOTTOM}"/></linearGradient>',
        '<linearGradient id="band" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1f4029"/><stop offset="0.5" stop-color="#14301f"/><stop offset="1" stop-color="#1b3a26"/></linearGradient>',
        '<linearGradient id="h" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2b4a32"/><stop offset="1" stop-color="#10211a"/></linearGradient>',
        f'<clipPath id="c"><path d="{CARD_OUTER}"/></clipPath>',
        "</defs>",
    ]
    for horn in CARD_HORNS:
        parts.append(f'<path d="{horn}" fill="url(#h)" stroke="{VEIN_DARK}" stroke-width="1.5"/>')
    parts.append(f'<path d="{CARD_OUTER}" fill="url(#band)"/>')
    parts.append('<g clip-path="url(#c)">')
    for y, a, ph, w, col, op in ((36, 2.0, 0, 1.3, VEIN, 0.7), (47, 2.4, 30, 1.6, VEIN_DARK, 0.8)):
        parts.append(f'<path d="{wave(20, 400, y, a, 60, TILE_X0 + ph)}" fill="none" stroke="{col}" stroke-width="{w}" stroke-opacity="{op}"/>')
        parts.append(f'<path d="{wave(20, 400, 260 - y, a, 60, TILE_X0 + ph + 20)}" fill="none" stroke="{col}" stroke-width="{w}" stroke-opacity="{op}"/>')
    for x, col, w in ((34, VEIN, 1.2), (52, VEIN_DARK, 1.6), (387, VEIN, 1.2), (371, VEIN_DARK, 1.6)):
        parts.append(f'<path d="M {x},60 L {x},200" fill="none" stroke="{col}" stroke-width="{w}" stroke-opacity="0.8"/>')
    for cx, cy, rx, ry in card_pits(42) + card_pits(218, -1):
        parts.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{rx + 1.2}" ry="{ry + 1.1}" fill="#2a5236"/>')
        parts.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{HOLE}"/>')
    for cx, cy, rx, ry in CARD_HOLES:
        parts.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{rx + 1.8}" ry="{ry + 1.8}" fill="#2a5236"/>')
        parts.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{HOLE}"/>')
    parts.append("</g>")
    parts.append(f'<path d="{CARD_INNER}" fill="url(#b)"/>')
    parts.append(f'<path d="{CARD_INNER}" fill="none" stroke="#000" stroke-opacity="0.45" stroke-width="8"/>')
    parts.append(f'<path d="{CARD_INNER}" fill="none" stroke="{VEIN_DARK}" stroke-width="2.5"/>')
    veins = [
        "M 62,82 C 74,90 78,104 92,110 C 100,113 108,111 114,118",
        "M 80,56 C 86,68 98,72 104,84",
        "M 62,184 C 74,180 82,190 96,186 C 106,183 112,188 120,184",
        "M 362,182 C 350,180 344,190 330,188",
        "M 318,204 C 322,194 332,192 336,182",
    ]
    for v in veins:
        parts.append(f'<path d="{v}" fill="none" stroke="#1f3b2a" stroke-width="1.6" stroke-linecap="round"/>')
    for x in (180, 240):
        parts.append(f'<path d="M {x},55 C {x - 3},62 {x + 3},66 {x},72" fill="none" stroke="#1a3325" stroke-width="1.4" stroke-linecap="round"/>')
    for cx, cy, r in CARD_CELLS:
        parts.append(f'<circle cx="{cx}" cy="{cy}" r="{r + 1.8}" fill="#21412d"/>')
        parts.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{HOLE}"/>')
        parts.append(f'<circle cx="{cx - r * 0.25}" cy="{cy - r * 0.3}" r="{r * 0.45}" fill="#0a1a12"/>')
    return "\n".join(parts)


def card_edge():
    parts = [
        "<defs>",
        f'<clipPath id="c"><path d="{CARD_OUTER}"/></clipPath>',
        '<linearGradient id="hn" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#fff" stop-opacity="0.6"/></linearGradient>',
        "</defs>",
        '<g clip-path="url(#c)">',
        f'<path d="{CARD_OUTER}" fill="none" stroke="#fff" stroke-opacity="0.16" stroke-width="30"/>',
        f'<path d="{CARD_OUTER}" fill="none" stroke="#fff" stroke-opacity="0.3" stroke-width="16"/>',
        f'<path d="{CARD_OUTER}" fill="none" stroke="#fff" stroke-opacity="0.5" stroke-width="7"/>',
        "</g>",
        f'<path d="{CARD_OUTER}" fill="none" stroke="#fff" stroke-width="2.6" stroke-linejoin="round"/>',
        f'<path d="{CARD_INNER}" fill="none" stroke="#fff" stroke-opacity="0.3" stroke-width="1.3"/>',
    ]
    for horn in CARD_HORNS:
        parts.append(f'<path d="{horn}" fill="url(#hn)" fill-opacity="0.62" stroke="#fff" stroke-width="1.4" stroke-linejoin="round"/>')
    for spine in CARD_SPINES:
        parts.append(f'<path d="{spine}" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round"/>')
    for cx, cy, rx, ry in CARD_HOLES:
        parts.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{rx + 1.8}" ry="{ry + 1.8}" fill="none" stroke="#fff" stroke-opacity="0.45" stroke-width="1.2"/>')
    for cx, cy, r in CARD_CELLS:
        parts.append(f'<circle cx="{cx}" cy="{cy}" r="{r + 1.6}" fill="none" stroke="#fff" stroke-opacity="0.3" stroke-width="1"/>')
    return "\n".join(parts)


def card_glow():
    parts = [glow_strokes(CARD_OUTER)]
    for horn in CARD_HORNS:
        parts.append(glow_strokes(horn, ((12, 0.1), (6, 0.2))))
    return "\n".join(parts)


# ---------------------------------------------------------------- panel
# 200 x 120, visual box 10..190 x 10..110 (pad 10). Nine-slice 44/40/44/40.
PANEL_W, PANEL_H = 200, 120
PANEL_OUTER = "M 26,12 L 174,12 L 188,26 L 188,94 L 174,108 L 26,108 L 12,94 L 12,26 Z"
PANEL_INNER = "M 29,18 L 171,18 L 182,29 L 182,91 L 171,102 L 29,102 L 18,91 L 18,29 Z"


def panel_body():
    return "\n".join([
        "<defs>",
        '<linearGradient id="b" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#132a1f" stop-opacity="0.96"/><stop offset="1" stop-color="#08140f" stop-opacity="0.94"/></linearGradient>',
        "</defs>",
        f'<path d="{PANEL_OUTER}" fill="url(#b)" stroke="#040a07" stroke-width="2.5" stroke-linejoin="round"/>',
        f'<path d="{PANEL_INNER}" fill="none" stroke="#000" stroke-opacity="0.35" stroke-width="4"/>',
        # corner veins (kept in the corner cells)
        '<path d="M 20,34 C 26,30 28,24 34,21" fill="none" stroke="#24442f" stroke-width="1.3" stroke-linecap="round"/>',
        '<path d="M 180,86 C 174,90 172,96 166,99" fill="none" stroke="#24442f" stroke-width="1.3" stroke-linecap="round"/>',
    ])


def panel_edge():
    return "\n".join([
        f'<path d="{PANEL_OUTER}" fill="none" stroke="#fff" stroke-width="2" stroke-linejoin="round"/>',
        f'<path d="{PANEL_INNER}" fill="none" stroke="#fff" stroke-opacity="0.22" stroke-width="1"/>',
        # a short brighter lip along the top edge (straight, stretch-safe)
        '<path d="M 26,13.5 L 174,13.5" stroke="#fff" stroke-opacity="0.35" stroke-width="1.5"/>',
    ])


def bone_claw_path(x, y, sx, sy, length=26, bend=9):
    """Small curved bone claw anchored at (x, y) pointing along (sx, sy) quadrant."""
    tip = (x + sx * length * 0.35, y + sy * length)
    c1 = (x + sx * bend * 1.2, y + sy * length * 0.35)
    base_w = 6
    return (
        f"M {x - sx * base_w:.1f},{y:.1f} "
        f"C {x - sx * base_w * 0.2:.1f},{y + sy * length * 0.5:.1f} {c1[0]:.1f},{c1[1] + sy * 4:.1f} {tip[0]:.1f},{tip[1]:.1f} "
        f"C {x + sx * bend * 0.4:.1f},{y + sy * length * 0.5:.1f} {x + sx * base_w:.1f},{y + sy * 6:.1f} {x + sx * base_w * 1.3:.1f},{y:.1f} Z"
    )


def claw_group(d):
    return (
        f'<path d="{d}" fill="url(#bone)" stroke="{BONE_DARK}" stroke-width="1.4" stroke-linejoin="round"/>'
    )


BONE_DEFS = (
    f'<linearGradient id="bone" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff7e2"/>'
    f'<stop offset="0.45" stop-color="{BONE}"/><stop offset="1" stop-color="{BONE_SHADE}"/></linearGradient>'
)


def panel_claws():
    # claws hook outward from the chamfered corners, pointing up / down
    parts = ["<defs>", BONE_DEFS, "</defs>"]
    claws = [
        "M 14,34 C 10,24 8,14 2,4 C 12,10 20,16 26,22 C 22,24 18,28 14,34 Z",
        "M 32,14 C 28,10 24,8 16,6 C 26,4 36,6 42,12 Z",
        "M 186,34 C 190,24 192,14 198,4 C 188,10 180,16 174,22 C 178,24 182,28 186,34 Z",
        "M 168,14 C 172,10 176,8 184,6 C 174,4 164,6 158,12 Z",
        "M 14,86 C 10,96 8,106 2,116 C 12,110 20,104 26,98 C 22,96 18,92 14,86 Z",
        "M 186,86 C 190,96 192,106 198,116 C 188,110 180,104 174,98 C 178,96 182,92 186,86 Z",
    ]
    for c in claws:
        parts.append(claw_group(c))
    return "\n".join(parts)


# ---------------------------------------------------------------- pill
# 120 x 60, capsule box 6..114 x 6..54 (h 48, pad 6). Nine-slice 32/28/32/28.
PILL = "M 30,6 L 90,6 A 24,24 0 0 1 90,54 L 30,54 A 24,24 0 0 1 30,6 Z"
PILL_IN = "M 30,10 L 90,10 A 20,20 0 0 1 90,50 L 30,50 A 20,20 0 0 1 30,10 Z"


def pill_body():
    return "\n".join([
        '<defs><linearGradient id="b" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#16301f" stop-opacity="0.95"/><stop offset="1" stop-color="#07130d" stop-opacity="0.95"/></linearGradient></defs>',
        f'<path d="{PILL}" fill="url(#b)" stroke="#030805" stroke-width="2"/>',
        f'<path d="{PILL_IN}" fill="none" stroke="#000" stroke-opacity="0.3" stroke-width="3"/>',
    ])


def pill_edge():
    return "\n".join([
        f'<path d="{PILL}" fill="none" stroke="#fff" stroke-width="2"/>',
        '<path d="M 30,9.5 L 90,9.5" stroke="#fff" stroke-opacity="0.35" stroke-width="1.4" stroke-linecap="round"/>',
    ])


# ---------------------------------------------------------------- buttons
# 240 x 96, button box 12..228 x 12..84 (h 72, pad 12). Nine-slice 48/40/48/40.
BTN = "M 34,12 L 206,12 L 228,34 L 228,62 L 206,84 L 34,84 L 12,62 L 12,34 Z"
BTN_IN = "M 36,17 L 204,17 L 223,36 L 223,60 L 204,79 L 36,79 L 17,60 L 17,36 Z"


def btn_primary():
    return "\n".join([
        "<defs>",
        '<linearGradient id="f" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#ffc56a"/><stop offset="0.42" stop-color="#ff8a33"/>'
        '<stop offset="0.75" stop-color="#e45a1c"/><stop offset="1" stop-color="#9e3310"/></linearGradient>',
        '<linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="0.7"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>',
        "</defs>",
        f'<path d="{BTN}" fill="url(#f)" stroke="#3a1406" stroke-width="3" stroke-linejoin="round"/>',
        f'<path d="{BTN_IN}" fill="none" stroke="#ffe0a8" stroke-opacity="0.75" stroke-width="1.5" stroke-linejoin="round"/>',
        # gloss band across the top half (straight in the middle strip)
        '<path d="M 38,20 L 202,20 L 214,32 L 214,40 L 26,40 L 26,32 Z" fill="url(#g)" opacity="0.55"/>',
        # dark lip at the bottom
        '<path d="M 36,79 L 204,79" stroke="#5a1d07" stroke-opacity="0.8" stroke-width="2"/>',
    ])


def btn_secondary():
    return "\n".join([
        '<defs><linearGradient id="f" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1a3325"/><stop offset="1" stop-color="#08140e"/></linearGradient></defs>',
        f'<path d="{BTN}" fill="url(#f)" stroke="#030805" stroke-width="4" stroke-linejoin="round"/>',
        f'<path d="{BTN}" fill="none" stroke="{BONE}" stroke-width="2.4" stroke-linejoin="round"/>',
        f'<path d="{BTN_IN}" fill="none" stroke="{BONE}" stroke-opacity="0.22" stroke-width="1.2" stroke-linejoin="round"/>',
        '<path d="M 38,21 L 202,21" stroke="#fff" stroke-opacity="0.08" stroke-width="3"/>',
    ])


def btn_glow():
    return glow_strokes(BTN, ((24, 0.08), (15, 0.14), (8, 0.24)))


# ---------------------------------------------------------------- round button
# 340 x 340, ring radius 100 around (170,170); organic cradle band r 104..124,
# claws reach out to r ~ 165.
RC = 170
ROUND = 340
CLAW_PATH = ("M 12,114 C 8,80 14,44 32,20 C 38,12 46,6 54,4 C 46,14 42,26 40,40 "
             "C 36,64 40,90 48,114 Z")


def _polar(r, deg):
    a = math.radians(deg)
    return RC + math.cos(a) * r, RC + math.sin(a) * r


def round_body():
    parts = [
        "<defs>",
        '<radialGradient id="b" cx="0.5" cy="0.42" r="0.6"><stop offset="0" stop-color="#1c3a2a"/><stop offset="0.7" stop-color="#0b1a12"/><stop offset="1" stop-color="#050c08"/></radialGradient>',
        "</defs>",
        # organic cradle: dark vine band with pits
        f'<circle cx="{RC}" cy="{RC}" r="115" fill="none" stroke="#040a07" stroke-width="24"/>',
        f'<circle cx="{RC}" cy="{RC}" r="115" fill="none" stroke="#17321f" stroke-width="19"/>',
        f'<circle cx="{RC}" cy="{RC}" r="111" fill="none" stroke="{VEIN_DARK}" stroke-width="1.4" stroke-dasharray="14 6 4 9"/>',
        f'<circle cx="{RC}" cy="{RC}" r="119" fill="none" stroke="{VEIN}" stroke-opacity="0.7" stroke-width="1.1" stroke-dasharray="22 8 6 12"/>',
    ]
    for i in range(22):
        x, y = _polar(115 + (i % 3 - 1) * 2.5, i / 22 * 360 + 7)
        r = 2.2 + (i % 4) * 0.7
        parts.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r + 1:.1f}" fill="#2a5236"/><circle cx="{x:.1f}" cy="{y:.1f}" r="{r:.1f}" fill="{HOLE}"/>')
    parts += [
        f'<circle cx="{RC}" cy="{RC}" r="100" fill="url(#b)"/>',
        f'<circle cx="{RC}" cy="{RC}" r="78" fill="none" stroke="#000" stroke-opacity="0.35" stroke-width="5"/>',
    ]
    return "\n".join(parts)


def round_ring():
    return "\n".join([
        f'<circle cx="{RC}" cy="{RC}" r="100" fill="none" stroke="#fff" stroke-width="8"/>',
        f'<circle cx="{RC}" cy="{RC}" r="92" fill="none" stroke="#fff" stroke-opacity="0.22" stroke-width="4"/>',
        f'<circle cx="{RC}" cy="{RC}" r="80" fill="none" stroke="#fff" stroke-opacity="0.55" stroke-width="2"/>',
    ])


def round_glow():
    return "\n".join([
        '<defs><radialGradient id="g" cx="0.5" cy="0.5" r="0.5">'
        '<stop offset="0.5" stop-color="#fff" stop-opacity="0"/><stop offset="0.59" stop-color="#fff" stop-opacity="0.5"/>'
        '<stop offset="0.68" stop-color="#fff" stop-opacity="0.1"/><stop offset="0.8" stop-color="#fff" stop-opacity="0"/></radialGradient>'
        '<radialGradient id="i" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#fff" stop-opacity="0.2"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient></defs>',
        f'<circle cx="{RC}" cy="{RC}" r="170" fill="url(#g)"/>',
        f'<circle cx="{RC}" cy="{RC}" r="94" fill="url(#i)"/>',
    ])


def round_claws():
    parts = ["<defs>", BONE_DEFS, "</defs>"]
    # hooked bone claws gripping the cradle: a fan at the lower left, a pair at the top right
    for deg, size in ((125, 0.34), (148, 0.4), (171, 0.34), (-62, 0.3), (-40, 0.36)):
        x, y = _polar(117, deg)
        rot = deg + 90 + 28
        parts.append(
            f'<g transform="translate({x:.1f},{y:.1f}) rotate({rot:.1f}) scale({size}) translate(-30,-114)">'
            f'<path d="{CLAW_PATH}" fill="url(#bone)" stroke="{BONE_DARK}" stroke-width="4" stroke-linejoin="round"/>'
            '<path d="M 22,108 C 20,80 24,52 38,30" fill="none" stroke="#fff" stroke-opacity="0.5" stroke-width="5" stroke-linecap="round"/>'
            "</g>"
        )
    return "\n".join(parts)


# ---------------------------------------------------------------- bars
# 120 x 28, capsule h 28. Nine-slice 14/12/14/12 (middle 4 px vertical).
BAR = "M 14,1 L 106,1 A 13,13 0 0 1 106,27 L 14,27 A 13,13 0 0 1 14,1 Z"


def bar_track():
    return "\n".join([
        '<defs><linearGradient id="t" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#020604"/><stop offset="1" stop-color="#0d1d15"/></linearGradient></defs>',
        f'<path d="{BAR}" fill="url(#t)" stroke="#2f4b3a" stroke-width="2"/>',
        '<path d="M 14,4 L 106,4" stroke="#000" stroke-opacity="0.5" stroke-width="3"/>',
    ])


def bar_fill():
    return "\n".join([
        '<defs><linearGradient id="f" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff"/><stop offset="0.5" stop-color="#e6e6e6"/><stop offset="1" stop-color="#a6a6a6"/></linearGradient></defs>',
        f'<path d="{BAR}" fill="url(#f)"/>',
        '<path d="M 14,6 L 106,6" stroke="#fff" stroke-opacity="0.8" stroke-width="3" stroke-linecap="round"/>',
    ])


# ---------------------------------------------------------------- ornaments
def claw():
    # 60 x 120; base centre at (30,114), tip up and hooking right.
    return "\n".join([
        "<defs>", BONE_DEFS, "</defs>",
        '<path d="M 12,114 C 8,80 14,44 32,20 C 38,12 46,6 54,4 C 46,14 42,26 40,40 C 36,64 40,90 48,114 Z" fill="url(#bone)" stroke="#2a1f12" stroke-width="2.5" stroke-linejoin="round"/>',
        '<path d="M 22,108 C 20,80 24,52 38,30" fill="none" stroke="#fff" stroke-opacity="0.55" stroke-width="2.5" stroke-linecap="round"/>',
        '<path d="M 16,100 L 44,100 M 18,88 L 42,88" stroke="#6b5636" stroke-opacity="0.45" stroke-width="1.5"/>',
    ])


def tooth():
    # 40 x 64; base centre at (20,4), pointing down.
    return "\n".join([
        "<defs>", BONE_DEFS, "</defs>",
        '<path d="M 4,4 C 6,24 12,44 20,60 C 26,44 34,24 36,4 Z" fill="url(#bone)" stroke="#2a1f12" stroke-width="2" stroke-linejoin="round"/>',
        '<path d="M 12,8 C 13,24 16,36 19,46" fill="none" stroke="#fff" stroke-opacity="0.6" stroke-width="2" stroke-linecap="round"/>',
    ])


def vine():
    # 260 x 96. Curl at the outer (left) end, stem tapering to the right tip at y 64.
    # Nine-slice 100/0/50/0: the middle x 100..210 is a straight stem of constant width.
    return "\n".join([
        '<path d="M 70,61.5 L 210,62.6 L 258,64 L 210,65.4 L 70,67 Z" fill="#fff"/>',
        '<path d="M 96,64 C 58,64 30,54 26,34 C 22,14 42,4 54,12 C 64,19 58,32 46,30" fill="none" stroke="#fff" stroke-opacity="0.14" stroke-width="12" stroke-linecap="round"/>',
        '<path d="M 100,64 C 58,64 30,54 26,34 C 23,18 34,8 46,10" fill="none" stroke="#fff" stroke-width="5" stroke-linecap="round"/>',
        '<path d="M 46,10 C 60,13 60,30 46,29 C 40,28 40,22 44,21" fill="none" stroke="#fff" stroke-width="3" stroke-linecap="round"/>',
        '<path d="M 72,63 C 62,72 50,76 40,72 C 34,69 36,62 42,63" fill="none" stroke="#fff" stroke-width="2.4" stroke-linecap="round"/>',
        '<path d="M 62,60 L 56,46 L 70,58 Z" fill="#fff"/>',
        '<path d="M 34,50 L 20,54 L 30,44 Z" fill="#fff"/>',
        '<path d="M 26,28 L 14,22 L 27,20 Z" fill="#fff"/>',
        '<path d="M 88,66 L 84,78 L 94,66 Z" fill="#fff" fill-opacity="0.9"/>',
        '<path d="M 80,62 C 82,50 94,44 104,46 C 100,56 92,62 80,62 Z" fill="#fff" fill-opacity="0.75"/>',
    ])


# ---------------------------------------------------------------- card cells
# Organic cell/vein layer for the card body (stage 06 polish). 760 x 170, drawn
# stretched over UiFrames.card_inner() and tinted; white strokes, dark cell
# wells. Dense along the edges and around the icon, faint behind the text.
CELLS_W, CELLS_H = 760, 170


def _clip(poly, a, b, c):
    """Keep the part of poly with a*x + b*y <= c (convex clipping)."""
    out = []
    n = len(poly)
    for i in range(n):
        p, q = poly[i], poly[(i + 1) % n]
        fp = a * p[0] + b * p[1] - c
        fq = a * q[0] + b * q[1] - c
        if fp <= 0:
            out.append(p)
        if fp * fq < 0:
            t = fp / (fp - fq)
            out.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
    return out


def _smooth(poly):
    """Closed quadratic path through edge midpoints (rounded blob)."""
    n = len(poly)
    mids = [((poly[i][0] + poly[(i + 1) % n][0]) / 2, (poly[i][1] + poly[(i + 1) % n][1]) / 2) for i in range(n)]
    d = f"M {mids[-1][0]:.1f},{mids[-1][1]:.1f} "
    for i in range(n):
        d += f"Q {poly[i][0]:.1f},{poly[i][1]:.1f} {mids[i][0]:.1f},{mids[i][1]:.1f} "
    return d + "Z"


def _cell_weight(x, y):
    left = 1.2 - x / 260.0
    right = (x - 600.0) / 150.0
    top = 0.8 - y / 40.0
    bottom = (y - 136.0) / 40.0
    return max(0.0, min(1.0, max(left, right, top, bottom)))


def card_cells():
    import random
    rng = random.Random(4711)
    sites = []
    step = 44.0
    y = -step * 0.5
    row = 0
    while y < CELLS_H + step:
        x = -step + (step * 0.5 if row % 2 else 0.0)
        while x < CELLS_W + step:
            sites.append((x + rng.uniform(-14, 14), y + rng.uniform(-12, 12)))
            x += step * rng.uniform(0.75, 1.35)
        y += step * 0.86
        row += 1
    parts = [f'<clipPath id="k"><rect x="0" y="0" width="{CELLS_W}" height="{CELLS_H}" rx="18"/></clipPath>', '<g clip-path="url(#k)">']
    for i, (sx, sy) in enumerate(sites):
        poly = [(sx - 60, sy - 60), (sx + 60, sy - 60), (sx + 60, sy + 60), (sx - 60, sy + 60)]
        for j, (tx, ty) in enumerate(sites):
            if i == j or abs(tx - sx) > 70 or abs(ty - sy) > 70:
                continue
            a, b = tx - sx, ty - sy
            c = (tx * tx + ty * ty - sx * sx - sy * sy) / 2.0
            poly = _clip(poly, a, b, c)
            if not poly:
                break
        if len(poly) < 3:
            continue
        w = _cell_weight(sx, sy)
        if w < 0.08:
            continue
        shrink = 0.72 + 0.14 * rng.random()
        inner = [(sx + (px - sx) * shrink, sy + (py - sy) * shrink) for px, py in poly]
        path = _smooth(inner)
        parts.append(f'<path d="{path}" fill="#000" fill-opacity="{0.42 * w:.2f}" stroke="#fff" stroke-opacity="{0.9 * w:.2f}" stroke-width="{1.6 + 1.6 * w:.2f}"/>')
        if w > 0.45 and rng.random() < 0.3:
            r = 2.0 + 3.0 * rng.random()
            parts.append(f'<circle cx="{sx:.1f}" cy="{sy:.1f}" r="{r:.1f}" fill="#000" fill-opacity="{0.55 * w:.2f}" stroke="#fff" stroke-opacity="{0.5 * w:.2f}" stroke-width="1"/>')
    # a few thicker veins running in from the edges
    veins = [
        "M 0,30 C 40,40 70,22 110,34 C 150,46 170,30 210,38",
        "M 0,140 C 36,128 70,148 116,136 C 150,128 180,146 230,132",
        "M 760,24 C 724,40 700,26 664,42 C 636,54 612,42 580,52",
        "M 760,150 C 730,136 704,152 668,138 C 640,128 618,140 590,130",
        "M 300,0 C 306,14 296,24 304,40",
        "M 470,170 C 464,156 474,148 468,132",
    ]
    for v in veins:
        parts.append(f'<path d="{v}" fill="none" stroke="#fff" stroke-opacity="0.55" stroke-width="3.2" stroke-linecap="round"/>')
        parts.append(f'<path d="{v}" fill="none" stroke="#000" stroke-opacity="0.35" stroke-width="1.2" stroke-linecap="round"/>')
    parts.append("</g>")
    return "\n".join(parts)


def halo():
    # 128 x 128 soft radial glow, white, tinted by the caller.
    return (
        '<defs><radialGradient id="g" cx="0.5" cy="0.5" r="0.5">'
        '<stop offset="0" stop-color="#fff" stop-opacity="1"/>'
        '<stop offset="0.45" stop-color="#fff" stop-opacity="0.45"/>'
        '<stop offset="0.75" stop-color="#fff" stop-opacity="0.12"/>'
        '<stop offset="1" stop-color="#fff" stop-opacity="0"/>'
        '</radialGradient></defs>'
        '<circle cx="64" cy="64" r="64" fill="url(#g)"/>'
    )


def main():
    os.makedirs(OUT, exist_ok=True)
    save("card_body", CARD_W, CARD_H, card_body())
    save("card_edge", CARD_W, CARD_H, card_edge())
    save("card_glow", CARD_W, CARD_H, card_glow())
    save("panel_body", PANEL_W, PANEL_H, panel_body())
    save("panel_edge", PANEL_W, PANEL_H, panel_edge())
    save("panel_claws", PANEL_W, PANEL_H, panel_claws())
    save("pill_body", 120, 60, pill_body())
    save("pill_edge", 120, 60, pill_edge())
    save("button_primary", 240, 96, btn_primary())
    save("button_secondary", 240, 96, btn_secondary())
    save("button_glow", 240, 96, btn_glow())
    save("round_body", ROUND, ROUND, round_body())
    save("round_ring", ROUND, ROUND, round_ring())
    save("round_glow", ROUND, ROUND, round_glow())
    save("round_claws", ROUND, ROUND, round_claws())
    save("bar_track", 120, 28, bar_track())
    save("bar_fill", 120, 28, bar_fill())
    save("claw", 60, 120, claw())
    save("tooth", 40, 64, tooth())
    save("vine_divider", 260, 96, vine())
    save("card_cells", CELLS_W, CELLS_H, card_cells())
    save("halo", 128, 128, halo())


if __name__ == "__main__":
    main()
