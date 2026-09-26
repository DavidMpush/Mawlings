"""Generates the MAWLINGS painted icon set as hand-authored SVG (viewBox 256).

Every icon is built from layers: a dark outline pass (thick stroke under the
whole silhouette), gradient fills (light top-left, dark bottom-right), soft
inner shading and a glossy highlight. Output: assets/ui/icons/<id>.svg
"""
import math
import os
import sys

OUT = sys.argv[1] if len(sys.argv) > 1 else "assets/ui/icons"

# name: (light, mid, dark, outline)
PAL = {
    "ember": ("#ffc36b", "#ff7a2e", "#b83418", "#2b0d05"),
    "cyan": ("#c4fff7", "#3fe6d8", "#0f7d7e", "#04201f"),
    "amber": ("#ffe79a", "#efb642", "#98560e", "#2a1603"),
    "violet": ("#ead2ff", "#b07ae8", "#5a2c90", "#1a0a2b"),
    "bone": ("#fffbea", "#efe2c0", "#a38a62", "#241b0e"),
    "toxic": ("#e2ffa8", "#9be15d", "#3a7420", "#0d1f07"),
    "acid": ("#f6ff9a", "#c9e637", "#5e7d0e", "#161f03"),
    "danger": ("#ffa08a", "#ff4a3a", "#8c1812", "#2a0604"),
    "gold": ("#fff3b8", "#f5c86a", "#a36d1a", "#2a1a05"),
    "grey": ("#ffffff", "#dcdcdc", "#8e8e8e", "#161616"),
    "leaf": ("#d4f79a", "#5fbf4a", "#1f6a2c", "#081c0c"),
    "flesh": ("#ff8a7a", "#a8243a", "#4a0a18", "#1c0308"),
    "moss": ("#5c7a44", "#2e4a2a", "#14261a", "#07110d"),
    "blue": ("#c2d8ff", "#5a86ff", "#2a2c9a", "#0a0b2a"),
    "magenta": ("#ffb8f2", "#e04ad0", "#7a1470", "#22041f"),
    "teal": ("#b8fff0", "#2fb8a8", "#0f5a5a", "#041a1a"),
    "plum": ("#e6a8e6", "#8e3a92", "#3a0e3e", "#16041a"),
}

OUT_W = 22  # outline stroke width (half of it shows outside the fill)


class Icon:
    def __init__(self, name):
        self.name = name
        self.defs = []
        self.back = []    # glows behind everything
        self.layers = []  # ordered (outline, fill, extras) groups
        self._grads = set()
        self.tf = ""  # optional transform around all layers (fit tweaks)

    # --- gradients -------------------------------------------------------
    def lin(self, pal, angle=0):
        gid = f"l_{pal}_{angle}"
        if gid not in self._grads:
            self._grads.add(gid)
            lo, mi, da, _ = PAL[pal]
            a = math.radians(angle)
            x1, y1 = 0.5 - 0.5 * math.sin(a), 0.0 + 0.5 - 0.5 * math.cos(a)
            x2, y2 = 0.5 + 0.5 * math.sin(a), 0.5 + 0.5 * math.cos(a)
            self.defs.append(
                f'<linearGradient id="{gid}" x1="{x1:.2f}" y1="{y1:.2f}" x2="{x2:.2f}" y2="{y2:.2f}">'
                f'<stop offset="0" stop-color="{lo}"/><stop offset="0.45" stop-color="{mi}"/>'
                f'<stop offset="1" stop-color="{da}"/></linearGradient>')
        return f"url(#{gid})"

    def rad(self, pal, cx=0.36, cy=0.3, r=0.85):
        gid = f"r_{pal}_{int(cx*100)}_{int(cy*100)}_{int(r*100)}"
        if gid not in self._grads:
            self._grads.add(gid)
            lo, mi, da, _ = PAL[pal]
            self.defs.append(
                f'<radialGradient id="{gid}" cx="{cx}" cy="{cy}" r="{r}" fx="{cx}" fy="{cy}">'
                f'<stop offset="0" stop-color="{lo}"/><stop offset="0.5" stop-color="{mi}"/>'
                f'<stop offset="1" stop-color="{da}"/></radialGradient>')
        return f"url(#{gid})"

    def glow(self, color, cx=128, cy=128, r=124, strength=0.75):
        gid = f"g_{len(self.defs)}"
        self.defs.append(
            f'<radialGradient id="{gid}" cx="0.5" cy="0.5" r="0.5">'
            f'<stop offset="0" stop-color="{color}" stop-opacity="{strength}"/>'
            f'<stop offset="0.55" stop-color="{color}" stop-opacity="{strength*0.35:.2f}"/>'
            f'<stop offset="1" stop-color="{color}" stop-opacity="0"/></radialGradient>')
        self.back.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#{gid})"/>')

    # --- shapes ----------------------------------------------------------
    def part(self, d, fill, outline_pal, extras="", tf="", ow=OUT_W):
        """One silhouette part: outline pass + fill + extras, all in one group."""
        oc = PAL[outline_pal][3]
        t = f' transform="{tf}"' if tf else ""
        self.layers.append(
            f'<g{t}><path d="{d}" fill="{oc}" stroke="{oc}" stroke-width="{ow}" stroke-linejoin="round" stroke-linecap="round"/>'
            f'<path d="{d}" fill="{fill}"/>{extras}</g>')

    def raw(self, s, tf=""):
        self.layers.append(f'<g transform="{tf}">{s}</g>' if tf else s)

    def svg(self):
        return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">'
                f'<defs>{"".join(self.defs)}</defs>{"".join(self.back)}'
                + (f'<g transform="{self.tf}">' if self.tf else "") + "".join(self.layers)
                + ("</g>" if self.tf else "") + "</svg>\n")


# --- helpers --------------------------------------------------------------
def hl(d, op=0.55, color="#ffffff"):
    return f'<path d="{d}" fill="{color}" fill-opacity="{op}"/>'


def shade(d, op=0.3, color="#000000"):
    return f'<path d="{d}" fill="{color}" fill-opacity="{op}"/>'


def circ(cx, cy, r, fill, op=1.0):
    return f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{fill}" fill-opacity="{op}"/>'


def ell(cx, cy, rx, ry, fill, op=1.0, rot=0):
    t = f' transform="rotate({rot} {cx} {cy})"' if rot else ""
    return f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{fill}" fill-opacity="{op}"{t}/>'


def ell_path(cx, cy, rx, ry, rot=0):
    """Ellipse as path (so it can carry the outline pass)."""
    pts = []
    n = 4
    a = math.radians(rot)
    k = 0.5523
    def p(x, y):
        return (cx + x * math.cos(a) - y * math.sin(a), cy + x * math.sin(a) + y * math.cos(a))
    P = [p(rx, 0), p(0, ry), p(-rx, 0), p(0, -ry)]
    C = [
        (p(rx, k * ry), p(k * rx, ry)), (p(-k * rx, ry), p(-rx, k * ry)),
        (p(-rx, -k * ry), p(-k * rx, -ry)), (p(k * rx, -ry), p(rx, -k * ry)),
    ]
    d = f"M{P[0][0]:.1f} {P[0][1]:.1f}"
    for i in range(4):
        c1, c2 = C[i]
        e = P[(i + 1) % 4]
        d += f" C{c1[0]:.1f} {c1[1]:.1f} {c2[0]:.1f} {c2[1]:.1f} {e[0]:.1f} {e[1]:.1f}"
    return d + " Z"


def circle_path(cx, cy, r):
    return ell_path(cx, cy, r, r)


def poly(pts):
    return "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts) + " Z"


def tooth(x1, y1, x2, y2, depth, bend=0.0):
    """Triangle tooth on base (x1,y1)-(x2,y2) pointing along the left normal."""
    mx, my = (x1 + x2) / 2, (y1 + y2) / 2
    dx, dy = x2 - x1, y2 - y1
    ln = math.hypot(dx, dy)
    nx, ny = -dy / ln, dx / ln
    tx, ty = mx + nx * depth + dx / ln * bend, my + ny * depth + dy / ln * bend
    cx1, cy1 = x1 + nx * depth * 0.55, y1 + ny * depth * 0.55
    return f"M{x1:.1f} {y1:.1f} Q{cx1:.1f} {cy1:.1f} {tx:.1f} {ty:.1f} Q{mx + nx*depth*0.3 + dx/ln*ln*0.35:.1f} {my + ny*depth*0.3 + dy/ln*ln*0.35:.1f} {x2:.1f} {y2:.1f} Z"


BONE_T = "#fff6dc"


def teeth_row(pts, depth, bend=0.0):
    return [tooth(pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], depth, bend) for i in range(len(pts) - 1)]


def teeth_group(ic, paths, outline_pal):
    oc = PAL[outline_pal][3]
    d = " ".join(paths)
    ic.raw(f'<path d="{d}" fill="{oc}" stroke="{oc}" stroke-width="10" stroke-linejoin="round"/>'
           f'<path d="{d}" fill="{ic.lin("bone", 20)}"/>')


# --- the Mawling head (profile, huge jaw, facing right) ---------------------
HEAD = ("M22 222 C14 170 26 112 64 74 C96 44 150 34 192 54 C216 66 234 82 242 98 "
        "C246 108 238 116 226 114 L148 118 C128 120 114 128 108 140 L116 150 L206 156 "
        "C220 158 222 172 210 178 C178 196 142 204 116 198 C104 218 72 234 22 222 Z")
MOUTH = "M100 146 L236 104 L214 168 L110 156 Z"


def head(ic, pal, tf="", eye=True):
    lo, mi, da, oc = PAL[pal]
    t = f' transform="{tf}"' if tf else ""
    up = teeth_row([(230, 114), (208, 115.5), (186, 117), (164, 118), (144, 120)], 22)
    lw = teeth_row([(122, 151), (146, 153), (170, 154.5), (196, 156)], 20)
    spikes = poly([(60, 80), (44, 50), (84, 64)]) + " " + poly([(96, 54), (92, 22), (126, 44)]) + " " + poly([(136, 42), (146, 14), (166, 44)])
    teeth = " ".join(up + lw)
    bone = f'url(#l_bone_20)'
    ic.lin("bone", 20)
    fill = ic.lin(pal, 30)
    parts = [
        f'<path d="{spikes}" fill="{oc}" stroke="{oc}" stroke-width="{OUT_W}" stroke-linejoin="round"/>',
        f'<path d="{MOUTH}" fill="{oc}" stroke="{oc}" stroke-width="{OUT_W}" stroke-linejoin="round"/>',
        f'<path d="{HEAD}" fill="{oc}" stroke="{oc}" stroke-width="{OUT_W}" stroke-linejoin="round"/>',
        f'<path d="{spikes}" fill="{da}"/>',
        f'<path d="{MOUTH}" fill="#3a0a0c"/>',
        f'<path d="M112 150 L214 162 L208 168 L118 156 Z" fill="#8a1c22"/>',
        f'<path d="{HEAD}" fill="{fill}"/>',
        # belly shading + back light
        shade("M22 222 C40 200 70 190 116 198 C104 218 72 234 22 222 Z", 0.28),
        shade("M116 150 L206 156 C220 158 222 172 210 178 C200 184 190 186 180 188 C190 176 196 168 196 164 Z", 0.25),
        hl("M52 110 C70 76 104 56 150 52 C120 64 90 84 70 122 Z", 0.45),
        f'<path d="{teeth}" fill="{oc}" stroke="{oc}" stroke-width="9" stroke-linejoin="round"/>',
        f'<path d="{teeth}" fill="{bone}"/>',
    ]
    if eye:
        parts += [circ(160, 84, 15, oc), circ(160, 84, 11, "#fff3c0"), ell(162, 84, 3.5, 9, "#140605"),
                  circ(156, 79, 3, "#ffffff")]
    ic.raw(f'<g{t}>{"".join(parts)}</g>')


# --- icons -----------------------------------------------------------------
ICONS = {}


def icon(fn):
    ICONS[fn.__name__.rstrip("_")] = fn
    return fn


@icon
def jaws(ic):
    # Wedge jaw seen from the side, opened wide, teeth and claw slashes.
    oc = PAL["ember"][3]
    ic.raw(f'<path d="M168 196 L236 150 M178 220 L244 186 M186 170 L230 128" stroke="{oc}" stroke-width="20" stroke-linecap="round"/>'
           f'<path d="M168 196 L236 150 M178 220 L244 186 M186 170 L230 128" stroke="{PAL["ember"][0]}" stroke-width="8" stroke-linecap="round"/>')
    upper = "M20 150 C16 90 56 34 124 26 C170 22 206 42 224 74 C228 84 222 92 212 90 L140 104 C104 112 70 128 44 156 Z"
    lower = "M52 168 C80 150 110 142 140 144 L202 150 C212 152 214 162 206 168 C176 204 130 226 90 222 C64 218 46 196 52 168 Z"
    ic.part("M36 160 L220 84 L208 160 L60 176 Z", "#3a0a0c", "ember")
    ic.part(lower, ic.lin("ember", 20), "ember", shade("M60 200 C90 214 150 212 196 172 C176 204 130 226 90 222 C70 219 58 210 60 200 Z", 0.3))
    ic.part(upper, ic.lin("ember", 20), "ember",
            hl("M34 120 C40 76 80 40 130 36 C92 52 62 80 50 128 Z", 0.5) +
            shade("M44 156 C70 128 104 112 140 104 L212 90 C200 98 150 110 120 122 C90 132 64 146 44 156 Z", 0.25) +
            # dorsal fins / ridges
            circ(118, 64, 11, "#2b0d05") + circ(118, 64, 7.5, "#fff0b0") + circ(119, 64, 3.5, "#2b0d05"))
    up = teeth_row([(212, 92), (190, 96), (166, 101), (142, 106), (116, 114), (92, 126)], 30)
    lw = teeth_row([(84, 162), (110, 152), (136, 147), (162, 149), (188, 152)], 26)
    teeth_group(ic, up + lw, "ember")


@icon
def brood(ic):
    ic.glow("#3fe6d8", 128, 140, 118, 0.35)
    nest = "M18 168 C26 236 230 236 238 168 C220 150 196 176 170 168 C150 184 110 184 88 168 C62 178 36 150 18 168 Z"
    ic.part(nest, ic.lin("moss", 0), "moss",
            f'<path d="M34 190 C80 214 170 216 222 188 M44 208 C96 226 160 226 212 204" stroke="#5c7a44" stroke-width="6" fill="none" stroke-linecap="round"/>')
    for (cx, cy, rx, ry, rot) in [(128, 90, 46, 60, 0), (78, 138, 46, 58, -18), (178, 138, 46, 58, 18)]:
        d = ell_path(cx, cy + 4, rx, ry, rot)
        # egg shape: narrower top via slight vertical offset is handled by ry
        spots = "".join([
            ell(cx - 14, cy - 24, 8, 10, PAL["cyan"][2], 0.85, rot),
            ell(cx + 16, cy - 4, 11, 9, PAL["cyan"][2], 0.85, rot),
            ell(cx - 10, cy + 20, 9, 7, PAL["cyan"][2], 0.85, rot),
            ell(cx + 20, cy + 32, 6, 6, PAL["cyan"][2], 0.85, rot),
            ell(cx - 24, cy + 2, 5, 5, PAL["cyan"][2], 0.85, rot),
        ])
        extras = spots + shade(ell_path(cx + 10, cy + 20, rx * 0.8, ry * 0.75, rot), 0.18) + \
            ell(cx - 18, cy - 28, 10, 18, "#ffffff", 0.7, rot - 20)
        ic.part(d, ic.rad("cyan", 0.35, 0.28, 0.9), "cyan", extras)
    # front nest rim covering egg bases
    rim = "M26 184 C60 170 90 190 128 180 C166 190 200 170 230 184 C220 226 36 226 26 184 Z"
    ic.part(rim, ic.lin("moss", 0), "moss",
            f'<path d="M40 196 C80 208 170 210 216 196" stroke="#6f9150" stroke-width="7" fill="none" stroke-linecap="round"/>'
            f'<path d="M60 184 L96 200 M150 200 L196 182 M110 186 L140 204" stroke="#0f2014" stroke-width="5" stroke-linecap="round"/>')


@icon
def glutton(ic):
    # Droplet-shaped stomach with a bite taken out of its right flank.
    d = ("M128 20 C150 60 172 84 188 108 C164 106 148 128 158 148 C136 154 132 184 156 192 "
         "C150 208 164 222 180 220 C166 232 148 238 128 238 C82 238 46 206 46 162 C46 116 96 76 128 20 Z")
    ic.part(d, ic.rad("amber", 0.38, 0.4, 0.8), "amber",
            shade("M60 190 C80 226 140 240 184 212 C150 226 96 222 60 190 Z", 0.3) +
            ell(112, 168, 34, 30, PAL["amber"][2], 0.35) + ell(104, 160, 16, 12, "#fff3c0", 0.35) +
            hl("M80 128 C88 96 108 66 124 44 C118 76 104 102 92 132 Z", 0.65) +
            circ(152, 196, 9, "#fff3c0", 0.8) + circ(132, 214, 5, "#fff3c0", 0.7) + circ(96, 188, 6, "#fff3c0", 0.6))
    # bite marks: small tooth notches along the bite edge
    oc = PAL["amber"][3]
    ic.raw(f'<path d="M188 108 C164 106 148 128 158 148 C136 154 132 184 156 192 C150 208 164 222 180 220" stroke="{PAL["amber"][2]}" stroke-width="6" fill="none"/>')
    # crumbs flying off
    for (x, y, r) in [(210, 128, 11), (222, 172, 9), (212, 206, 6)]:
        ic.part(circle_path(x, y, r), ic.rad("amber"), "amber", ow=10)


@icon
def pack(ic):
    head(ic, "ember", "translate(98 6) scale(0.56)")
    head(ic, "ember", "translate(4 34) scale(0.56)")
    head(ic, "ember", "translate(58 86) scale(0.66)")


@icon
def scatter(ic):
    ic.glow("#b07ae8", 128, 170, 70, 0.4)
    arrow = "M112 206 L112 110 L86 110 L128 44 L170 110 L144 110 L144 206 Z"
    for ang, sc in [(-52, 0.82), (52, 0.82), (0, 1.0)]:
        tf = f"rotate({ang} 128 214) translate(128 214) scale({sc}) translate(-128 -214)"
        ic.part(arrow, ic.lin("violet", 20), "violet",
                hl("M116 200 L116 106 L96 106 L128 54 L122 104 L122 200 Z", 0.45) +
                shade("M136 200 L136 106 L160 106 L170 110 L144 110 L144 206 Z", 0.3), tf)
    ic.part(circle_path(128, 216, 22), ic.rad("violet"), "violet", circ(121, 209, 6, "#ffffff", 0.7))


@icon
def armor(ic):
    ic.glow("#9be15d", 128, 150, 110, 0.4)
    back = "M34 196 C22 140 70 96 132 96 C196 96 238 142 222 200 C196 232 64 234 34 196 Z"
    ic.part(back, ic.lin("toxic", 0), "toxic",
            shade("M40 206 C80 230 180 230 220 204 C200 226 70 230 40 206 Z", 0.35) +
            f'<path d="M50 180 C70 160 90 170 104 150 M150 150 C170 170 190 160 208 180" stroke="{PAL["toxic"][2]}" stroke-width="6" fill="none" stroke-linecap="round"/>')
    shard = "M0 -92 C16 -60 26 -16 22 26 C16 40 8 48 0 52 C-8 48 -16 40 -22 26 C-26 -16 -16 -60 0 -92 Z"
    for (x, y, a, s) in [(62, 160, -38, 0.78), (196, 160, 38, 0.78), (98, 138, -16, 0.95), (160, 138, 16, 0.95), (128, 132, 0, 1.12)]:
        tf = f"translate({x} {y}) rotate({a}) scale({s})"
        ic.part(shard, ic.lin("bone", 12), "bone",
                hl("M-2 -80 C-12 -50 -18 -14 -16 22 C-12 34 -8 38 -4 40 C-8 0 -8 -40 -2 -80 Z", 0.75) +
                shade("M4 -74 C16 -40 22 -8 20 24 C16 38 8 46 2 50 C10 20 10 -30 4 -74 Z", 0.3) +
                f'<path d="M-10 -10 L6 4 L-4 18" stroke="{PAL["bone"][2]}" stroke-width="3.5" fill="none" stroke-linecap="round"/>',
                tf)


def bite_ring(ic, pal, cx=128, cy=128, r_out=104, r_in=66, gap=22):
    """Two jaw arcs (top/bottom) with teeth pointing inward."""
    oc = PAL[pal][3]
    for top in (True, False):
        a0, a1 = (180 + gap, 360 - gap) if top else (gap, 180 - gap)
        pts_o = [(cx + r_out * math.cos(math.radians(a)), cy + r_out * math.sin(math.radians(a))) for a in range(int(a0), int(a1) + 1, 4)]
        pts_i = [(cx + r_in * math.cos(math.radians(a)), cy + r_in * math.sin(math.radians(a))) for a in range(int(a1), int(a0) - 1, -4)]
        d = poly(pts_o + pts_i)
        ic.part(d, ic.lin(pal, 0 if top else 180), pal)
        # teeth on the inner edge
        n = 6
        tp = []
        for i in range(n):
            aa = a0 + 6 + (a1 - a0 - 12) * (i / (n - 1))
            w = 7.5
            b1 = (cx + (r_in + 2) * math.cos(math.radians(aa - w)), cy + (r_in + 2) * math.sin(math.radians(aa - w)))
            b2 = (cx + (r_in + 2) * math.cos(math.radians(aa + w)), cy + (r_in + 2) * math.sin(math.radians(aa + w)))
            ln = 30 if i in (0, n - 1) else 24
            tip = (cx + (r_in - ln) * math.cos(math.radians(aa)), cy + (r_in - ln) * math.sin(math.radians(aa)))
            tp.append(poly([b1, tip, b2]))
        teeth_group(ic, tp, pal)
        # rim highlight
        mid = (a0 + a1) / 2
        hp = [(cx + (r_out - 8) * math.cos(math.radians(a)), cy + (r_out - 8) * math.sin(math.radians(a))) for a in range(int(a0) + 8, int(a1) - 7, 4)]
        ic.raw(f'<path d="M{" L".join(f"{x:.1f} {y:.1f}" for x, y in hp)}" stroke="#ffffff" stroke-opacity="{0.55 if top else 0.25}" stroke-width="7" fill="none" stroke-linecap="round"/>')


@icon
def rudelbiss(ic):
    bite_ring(ic, "ember")
    # three small heads' worth of ferocity: impact sparks in the middle
    ic.part("M128 104 L136 122 L156 128 L136 134 L128 152 L120 134 L100 128 L120 122 Z", ic.rad("gold"), "ember", ow=10)


def cloud_path(circles):
    """Approximate union of circles by outlining each (outline pass merges them)."""
    return " ".join(circle_path(x, y, r) for x, y, r in circles)


@icon
def sporenwolke(ic):
    ic.glow("#9be15d", 128, 140, 120, 0.35)
    cs = [(70, 156, 46), (122, 118, 58), (180, 148, 50), (126, 176, 50), (190, 106, 34)]
    oc = PAL["toxic"][3]
    ic.raw("".join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{oc}" stroke="{oc}" stroke-width="{OUT_W}"/>' for x, y, r in cs))
    ic.raw("".join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{ic.rad("toxic", 0.4, 0.35, 0.8)}"/>' for x, y, r in cs))
    ic.raw(shade("M34 172 C60 214 180 222 224 170 C200 200 80 212 34 172 Z", 0.3) +
           hl(ell_path(104, 92, 26, 14, -25), 0.5) + hl(ell_path(186, 92, 12, 7, -20), 0.5))
    # spores: darker dots inside + floating specks
    for x, y, r in [(92, 150, 9), (140, 138, 11), (176, 168, 8), (116, 186, 7), (60, 170, 6), (196, 128, 6)]:
        ic.raw(circ(x, y, r, PAL["toxic"][2], 0.9) + circ(x - r * 0.3, y - r * 0.3, r * 0.35, "#e2ffa8", 0.8))
    for x, y, r in [(46, 88, 9), (220, 60, 8), (160, 40, 7), (230, 206, 7), (30, 220, 6)]:
        ic.part(circle_path(x, y, r), ic.rad("toxic"), "toxic", ow=10)


DROP = "M0 -60 C14 -34 36 -10 36 16 C36 38 20 54 0 54 C-20 54 -36 38 -36 16 C-36 -10 -14 -34 0 -60 Z"


def drop(ic, pal, x, y, s, rot=0, ow=OUT_W):
    ic.part(DROP, ic.rad(pal, 0.38, 0.45, 0.75), pal,
            hl("M-18 4 C-18 -12 -8 -28 0 -40 C-4 -20 -8 -6 -8 10 Z", 0.7) +
            shade("M-30 30 C-16 52 20 54 32 28 C20 44 -14 46 -30 30 Z", 0.3),
            f"translate({x} {y}) rotate({rot}) scale({s})", ow=ow)


@icon
def saeurespucker(ic):
    # Spitting maw (upper-left) launching a stream of acid globs to the lower right.
    ic.glow("#c9e637", 150, 150, 110, 0.45)
    # small spitting maw at the upper left
    head(ic, "toxic", "translate(-6 -4) scale(0.46)")
    # acid stream: globs grow toward the lower right, tails point back at the maw
    drop(ic, "acid", 118, 94, 0.36, -45, ow=30)
    drop(ic, "acid", 170, 170, 1.12, -45)
    # splash droplets around the main glob
    for x, y, r in [(232, 132, 10), (122, 232, 9), (236, 210, 8), (96, 150, 7)]:
        ic.part(circle_path(x, y, r), ic.rad("acid"), "acid", ow=10)
    # sizzling bubbles on the glob
    ic.raw(circ(184, 186, 9, "#fbffd0", 0.8) + circ(160, 204, 6, "#fbffd0", 0.7) + circ(196, 160, 5, "#fbffd0", 0.7))


@icon
def stachelruecken(ic):
    ic.tf = "translate(128 140) scale(0.84) translate(-128 -140)"
    body = "M18 214 C26 128 80 86 128 86 C176 86 230 128 238 214 Z"
    # spikes along the arc
    sp = []
    for a in (-58, -29, 0, 29, 58):
        rad_ = math.radians(a - 90)
        bx, by = 128 + 96 * math.cos(rad_) * 1.08, 214 + 118 * math.sin(rad_)
        # base points along tangent
        tx, ty = -math.sin(rad_), math.cos(rad_)
        nx, ny = math.cos(rad_), math.sin(rad_)
        w = 20
        ln = 84 if a == 0 else 70
        b1 = (bx - tx * w + nx * 10, by - ty * w + ny * 10)
        b2 = (bx + tx * w + nx * 10, by + ty * w + ny * 10)
        tip = (bx + nx * ln, by + ny * ln)
        sp.append((b1, tip, b2))
    for b1, tip, b2 in sp:
        d = f"M{b1[0]:.1f} {b1[1]:.1f} Q{(b1[0]+tip[0])/2 - 4:.1f} {(b1[1]+tip[1])/2:.1f} {tip[0]:.1f} {tip[1]:.1f} Q{(b2[0]+tip[0])/2 + 4:.1f} {(b2[1]+tip[1])/2:.1f} {b2[0]:.1f} {b2[1]:.1f} Z"
        hd = f"M{b1[0]:.1f} {b1[1]:.1f} L{tip[0]:.1f} {tip[1]:.1f} L{(b1[0]+b2[0])/2:.1f} {(b1[1]+b2[1])/2:.1f} Z"
        ic.part(d, ic.lin("bone", 0), "bone", hl(hd, 0.45))
    ic.part(body, ic.lin("violet", 0), "violet",
            hl("M44 180 C54 134 90 104 128 100 C96 116 70 144 60 186 Z", 0.4) +
            shade("M18 214 C60 196 196 196 238 214 Z", 0.35) +
            "".join(circ(x, y, r, PAL["violet"][2], 0.8) for x, y, r in [(100, 150, 12), (152, 140, 10), (180, 176, 13), (74, 188, 9), (130, 186, 8)]))


@icon
def aetzflut(ic):
    ic.glow("#c9e637", 128, 128, 128, 0.7)
    ic.glow("#fff3b8", 128, 150, 70, 0.35)
    wave = ("M14 226 C18 170 44 118 96 94 C140 74 196 82 222 118 C236 140 228 170 204 176 "
            "C186 180 170 168 176 150 C182 136 200 138 200 148 C196 128 168 120 146 132 "
            "C118 148 110 190 132 226 Z")
    ic.part(wave, ic.lin("acid", 10), "acid",
            hl("M30 190 C40 150 64 120 100 104 C140 88 184 92 206 116 C176 100 130 104 100 124 C70 144 50 170 42 206 Z", 0.5) +
            shade("M14 226 C30 212 60 210 90 226 Z", 0.35) +
            "".join(circ(x, y, r, "#fbffd0", 0.75) for x, y, r in [(80, 180, 9), (104, 150, 6), (60, 210, 7), (120, 204, 5)]))
    drop(ic, "acid", 212, 64, 0.5, 20, ow=26)
    drop(ic, "acid", 170, 36, 0.34, -10, ow=28)
    # regal sparkles
    for x, y, s in [(48, 60, 1.0), (236, 214, 0.8), (174, 224, 0.6)]:
        ic.part(poly([(x, y - 16 * s), (x + 5 * s, y - 5 * s), (x + 16 * s, y), (x + 5 * s, y + 5 * s), (x, y + 16 * s), (x - 5 * s, y + 5 * s), (x - 16 * s, y), (x - 5 * s, y - 5 * s)]),
                ic.rad("gold"), "gold", ow=8)


@icon
def meute(ic):
    # evolution mark: violet glow ring behind the crowned pack
    ic.glow("#b07ae8", 128, 128, 128, 0.8)
    ic.back.append('<circle cx="128" cy="128" r="110" fill="none" stroke="#1a0a2b" stroke-width="26"/>'
                   '<circle cx="128" cy="128" r="110" fill="none" stroke="#b07ae8" stroke-width="14"/>'
                   '<circle cx="128" cy="128" r="110" fill="none" stroke="#ead2ff" stroke-width="4" stroke-opacity="0.8"/>')
    ic.glow("#ffb347", 128, 128, 90, 0.45)
    # pack leader wearing a crown, flanked by its pack
    head(ic, "ember", "translate(-6 60) scale(0.48)")
    head(ic, "ember", "translate(128 52) scale(0.48)")
    head(ic, "ember", "translate(40 84) scale(0.68)")
    crown_shape(ic, "translate(124 60) scale(0.46) translate(-128 -130) rotate(-8 128 128)")
    for x, y, s in [(30, 70, 1.0), (226, 58, 0.9), (222, 238, 0.6)]:
        ic.part(poly([(x, y - 16 * s), (x + 5 * s, y - 5 * s), (x + 16 * s, y), (x + 5 * s, y + 5 * s), (x, y + 16 * s), (x - 5 * s, y + 5 * s), (x - 16 * s, y), (x - 5 * s, y - 5 * s)]),
                ic.rad("gold"), "gold", ow=8)


@icon
def essence(ic):
    ic.glow("#b07ae8", 128, 150, 100, 0.55)
    ic.part("M128 14 C152 60 204 104 204 156 C204 204 170 238 128 238 C86 238 52 204 52 156 C52 104 104 60 128 14 Z",
            ic.rad("violet", 0.4, 0.55, 0.7), "violet",
            hl("M82 150 C82 118 104 82 122 54 C114 96 100 120 98 156 Z", 0.7) +
            shade("M62 190 C84 236 176 236 196 186 C172 220 92 222 62 190 Z", 0.3) +
            ell(128, 162, 34, 36, "#ead2ff", 0.35) +
            poly([(128, 128), (136, 152), (160, 160), (136, 168), (128, 192), (120, 168), (96, 160), (120, 152)]).join(['<path d="', '" fill="#ffffff" fill-opacity="0.9"/>']))


@icon
def crown_tooth(ic):
    ic.glow("#f5c86a", 128, 110, 110, 0.35)
    tooth_ = "M78 70 C110 60 150 60 180 70 C184 130 164 190 132 240 C126 246 118 244 116 236 C98 186 76 130 78 70 Z"
    ic.part(tooth_, ic.lin("bone", 15), "bone",
            hl("M92 84 C94 130 104 176 118 214 C104 170 96 128 100 84 Z", 0.7) +
            shade("M160 78 C160 130 146 186 128 228 C150 186 170 130 172 80 Z", 0.28))
    crown_ = "M66 84 L60 30 L90 52 L108 14 L128 44 L148 14 L166 52 L196 30 L190 84 C150 94 106 94 66 84 Z"
    ic.part(crown_, ic.lin("gold", 0), "gold",
            hl("M70 76 L66 42 L88 60 L108 26 L110 40 L92 70 Z", 0.5) +
            shade("M66 84 C106 94 150 94 190 84 L188 72 C150 82 106 82 68 72 Z", 0.3) +
            circ(128, 68, 9, PAL["danger"][3]) + circ(128, 68, 6.5, PAL["danger"][1]) + circ(126, 66, 2.2, "#ffffff") +
            circ(94, 70, 6, PAL["cyan"][3]) + circ(94, 70, 4, PAL["cyan"][1]) +
            circ(162, 70, 6, PAL["cyan"][3]) + circ(162, 70, 4, PAL["cyan"][1]))


@icon
def dna(ic):
    ic.glow("#3fe6d8", 128, 128, 110, 0.3)
    dna_draw(ic, "rotate(-18 128 128)")


def dna_draw(ic, rotate):
    n = 60
    def strand(phase):
        pts = []
        for i in range(n + 1):
            t = i / n
            y = 26 + 204 * t
            x = 128 + 52 * math.sin(t * math.pi * 3.0 + phase)
            pts.append((x, y))
        return pts
    a = strand(0.0)
    b = strand(math.pi)
    oc = PAL["cyan"][3]
    rungs = []
    for i in range(3, n - 1, 5):
        rungs.append(f"M{a[i][0]:.1f} {a[i][1]:.1f} L{b[i][0]:.1f} {b[i][1]:.1f}")
    rd = " ".join(rungs)
    da = "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in a)
    db = "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in b)
    ic.raw(f'<path d="{rd}" stroke="{oc}" stroke-width="20" stroke-linecap="round"/>'
           f'<path d="{db}" stroke="{oc}" stroke-width="36" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'
           f'<path d="{rd}" stroke="#7fd8d0" stroke-width="9" stroke-linecap="round"/>'
           f'<path d="{db}" stroke="#1faaa6" stroke-width="20" fill="none" stroke-linecap="round"/>'
           f'<path d="{da}" stroke="{oc}" stroke-width="36" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'
           f'<path d="{da}" stroke="{PAL["cyan"][1]}" stroke-width="20" fill="none" stroke-linecap="round"/>'
           f'<path d="{da}" stroke="{PAL["cyan"][0]}" stroke-width="7" fill="none" stroke-linecap="round" transform="translate(-4 -2)"/>', rotate)


def skull_shape(ic, pal, tf="", crack=False):
    cran = ("M128 22 C184 22 222 62 222 114 C222 146 206 164 190 172 L190 204 C190 214 182 220 172 220 "
            "L84 220 C74 220 66 214 66 204 L66 172 C50 164 34 146 34 114 C34 62 72 22 128 22 Z")
    oc = PAL[pal][3]
    extras = (hl("M52 104 C54 70 84 40 124 36 C92 50 70 74 64 110 Z", 0.5) +
              ell(92, 118, 26, 28, oc) + ell(164, 118, 26, 28, oc) +
              ell(92, 122, 10, 11, "#ffdf7a" if pal != "grey" else "#ffffff", 0.9) + ell(164, 122, 10, 11, "#ffdf7a" if pal != "grey" else "#ffffff", 0.9) +
              poly([(128, 146), (116, 170), (140, 170)]).join(['<path d="', f'" fill="{oc}"/>']) +
              f'<path d="M96 190 L96 218 M116 192 L116 220 M140 192 L140 220 M160 190 L160 218" stroke="{oc}" stroke-width="8" stroke-linecap="round"/>' +
              shade("M66 180 L190 180 L190 204 C190 214 182 220 172 220 L84 220 C74 220 66 214 66 204 Z", 0.25))
    if crack:
        extras += f'<path d="M150 26 L140 54 L154 70 L144 90" stroke="{oc}" stroke-width="6" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'
    ic.part(cran, ic.lin(pal, 15), pal, extras, tf)


@icon
def skull(ic):
    skull_shape(ic, "danger")


@icon
def mawling_head(ic):
    head(ic, "grey", "translate(0 8)")


@icon
def mawling_head_color(ic):
    head(ic, "ember", "translate(0 8)")


def crown_shape(ic, tf=""):
    d = "M26 196 L16 70 L76 122 L128 36 L180 122 L240 70 L230 196 C166 214 90 214 26 196 Z"
    ic.part(d, ic.lin("gold", 0), "gold",
            hl("M34 180 L28 94 L70 130 L128 54 L120 76 L76 146 L42 116 L46 180 Z", 0.5) +
            shade("M26 196 C90 214 166 214 230 196 L228 170 C166 188 90 188 28 170 Z", 0.3) +
            circ(128, 158, 16, PAL["danger"][3]) + circ(128, 158, 12, PAL["danger"][1]) + circ(124, 153, 4, "#ffffff") +
            circ(72, 164, 10, PAL["cyan"][3]) + circ(72, 164, 7, PAL["cyan"][1]) +
            circ(184, 164, 10, PAL["cyan"][3]) + circ(184, 164, 7, PAL["cyan"][1]), tf)
    for x, y in [(16, 70), (128, 36), (240, 70)]:
        ic.part(circle_path(x, y, 12), ic.rad("gold"), "gold", tf=tf, ow=12)


@icon
def crown(ic):
    crown_shape(ic, "translate(128 128) scale(0.9) translate(-128 -118)")


@icon
def alpha_core(ic):
    ic.glow("#efb642", 128, 128, 110, 0.6)
    petal = "M0 -112 C30 -96 44 -60 36 -26 C26 -40 12 -48 0 -48 C-12 -48 -26 -40 -36 -26 C-44 -60 -30 -96 0 -112 Z"
    for a in (45, 135, 225, 315):
        ic.part(petal, ic.lin("violet", 0), "violet",
                hl("M-4 -100 C-24 -86 -34 -60 -32 -36 C-24 -44 -16 -48 -8 -50 C-14 -70 -12 -86 -4 -100 Z", 0.4),
                f"translate(128 128) rotate({a})")
    ic.part(circle_path(128, 128, 58), ic.lin("violet", 0), "violet",
            shade(circle_path(132, 134, 50), 0.35))
    ic.part(circle_path(128, 128, 40), ic.rad("amber", 0.4, 0.38, 0.75), "amber",
            circ(128, 128, 22, "#fff3b8", 0.55) + ell(114, 112, 12, 8, "#ffffff", 0.8, -30), ow=10)


@icon
def pause(ic):
    for x in (62, 146):
        ic.part(f"M{x} 44 C{x} 36 {x+8} 30 {x+16} 30 L{x+32} 30 C{x+40} 30 {x+48} 36 {x+48} 44 L{x+48} 212 C{x+48} 220 {x+40} 226 {x+32} 226 L{x+16} 226 C{x+8} 226 {x} 220 {x} 212 Z",
                ic.lin("bone", 10), "bone", hl(f"M{x+8} 48 C{x+8} 40 {x+12} 38 {x+18} 38 L{x+18} 214 C{x+12} 214 {x+8} 212 {x+8} 206 Z", 0.6))


@icon
def lock(ic):
    oc = PAL["bone"][3]
    shackle = "M72 118 L72 82 C72 44 98 22 128 22 C158 22 184 44 184 82 L184 118"
    ic.raw(f'<path d="{shackle}" stroke="{oc}" stroke-width="48" fill="none" stroke-linecap="round"/>'
           f'<path d="{shackle}" stroke="{PAL["bone"][2]}" stroke-width="26" fill="none" stroke-linecap="round"/>'
           f'<path d="M80 110 L80 82 C80 50 102 32 128 32" stroke="{PAL["bone"][0]}" stroke-width="7" fill="none" stroke-linecap="round"/>')
    body = "M40 118 C40 108 48 102 58 102 L198 102 C208 102 216 108 216 118 L216 214 C216 226 206 234 194 234 L62 234 C50 234 40 226 40 214 Z"
    ic.part(body, ic.lin("bone", 10), "bone",
            hl("M52 124 C52 116 56 112 64 112 L190 112 C170 118 90 118 60 132 Z", 0.6) +
            shade("M40 200 L216 200 L216 214 C216 226 206 234 194 234 L62 234 C50 234 40 226 40 214 Z", 0.3) +
            circ(128, 154, 20, oc) + poly([(118, 160), (138, 160), (144, 204), (112, 204)]).join(['<path d="', f'" fill="{oc}"/>']))


@icon
def trophy(ic):
    oc = PAL["gold"][3]
    ic.raw(f'<path d="M70 62 C20 60 22 128 84 132 M186 62 C236 60 234 128 172 132" stroke="{oc}" stroke-width="34" fill="none" stroke-linecap="round"/>'
           f'<path d="M70 62 C20 60 22 128 84 132 M186 62 C236 60 234 128 172 132" stroke="{PAL["gold"][2]}" stroke-width="14" fill="none" stroke-linecap="round"/>')
    cup = "M56 30 L200 30 C204 100 180 150 140 162 L140 188 L170 200 L178 226 L78 226 L86 200 L116 188 L116 162 C76 150 52 100 56 30 Z"
    ic.part(cup, ic.lin("gold", 20), "gold",
            hl("M70 42 L104 42 C100 90 108 130 124 150 C92 136 70 100 70 42 Z", 0.55) +
            shade("M176 42 C174 110 156 146 132 158 C164 146 188 110 190 42 Z", 0.3) +
            shade("M78 214 L178 214 L178 226 L78 226 Z", 0.35) +
            poly([(128, 60), (138, 84), (162, 86), (144, 102), (150, 126), (128, 112), (106, 126), (112, 102), (94, 86), (118, 84)]).join(['<path d="', '" fill="#fff8d6" fill-opacity="0.9"/>']))


@icon
def biome_verdant(ic):
    ic.glow("#5fbf4a", 128, 140, 110, 0.3)
    leaf = "M0 0 C-40 -30 -44 -110 0 -150 C44 -110 40 -30 0 0 Z"
    for a, s, x in [(-46, 0.8, 118), (46, 0.8, 138), (0, 1.0, 128)]:
        ic.part(leaf, ic.lin("leaf", 0), "leaf",
                f'<path d="M0 -6 L0 -136" stroke="{PAL["leaf"][2]}" stroke-width="6" stroke-linecap="round"/>'
                f'<path d="M0 -40 L-18 -62 M0 -70 L-18 -92 M0 -40 L18 -62 M0 -70 L18 -92" stroke="{PAL["leaf"][2]}" stroke-width="4" stroke-linecap="round"/>' +
                hl("M-8 -20 C-30 -50 -28 -104 -4 -136 C-16 -100 -16 -60 -8 -20 Z", 0.4),
                f"translate({x} 214) rotate({a}) scale({s})")
    # glowing mushrooms at the base
    for x, y, s in [(58, 212, 0.9), (198, 216, 0.75)]:
        ic.part("M-8 0 L-6 -20 L6 -20 L8 0 Z", "#e8f0d0", "leaf", tf=f"translate({x} {y}) scale({s})", ow=12)
        ic.part("M-30 -16 C-30 -50 30 -50 30 -16 Z", ic.rad("cyan", 0.4, 0.2, 0.9), "cyan", circ(-10, -32, 5, "#ffffff", 0.9) + circ(10, -26, 4, "#c4fff7", 0.8), f"translate({x} {y}) scale({s})", ow=12)
    ic.part("M36 226 C60 206 196 206 220 226 Z", ic.lin("moss", 0), "moss", ow=14)


@icon
def biome_glutsumpf(ic):
    ic.glow("#ff7a2e", 128, 176, 110, 0.5)
    pool = ell_path(128, 184, 108, 48)
    ic.part(pool, ic.rad("ember", 0.5, 0.45, 0.6), "ember",
            ell(128, 184, 76, 28, "#ffe08a", 0.35) + ell(104, 176, 30, 10, "#fff3c0", 0.55))
    # dead tree stump / reeds
    ic.part("M40 186 L46 90 L30 60 L50 76 L58 44 L66 88 L64 186 Z", ic.lin("moss", 20), "moss", ow=16)
    ic.part("M196 190 L200 110 L186 96 L204 100 L214 72 L214 190 Z", ic.lin("moss", 20), "moss", ow=16)
    for x, y, r in [(150, 150, 18), (108, 132, 12), (178, 118, 9), (132, 98, 7)]:
        ic.part(circle_path(x, y, r), ic.rad("ember", 0.35, 0.3, 0.8), "ember",
                ell(x - r * 0.35, y - r * 0.4, r * 0.35, r * 0.22, "#ffffff", 0.8), ow=12)


def slashes(ic, pal, n=3):
    oc = PAL[pal][3]
    for i in range(n):
        off = (i - (n - 1) / 2) * 50
        d = f"M{70 + off} {210} C{100 + off} {150} {140 + off} {90} {196 + off} {40} C{158 + off} {100} {126 + off} {160} {84 + off} {222} Z"
        ic.part(d, ic.lin(pal, 30), pal, hl(f"M{84 + off} {204} C{110 + off} {152} {140 + off} {104} {180 + off} {60} C{144 + off} {104} {116 + off} {150} {90 + off} {206} Z", 0.45))


@icon
def diff_wild(ic):
    # paw print (toxic): three toes and a pad
    ic.part("M64 186 C60 146 96 124 128 124 C160 124 196 146 192 186 C188 220 160 226 128 214 C96 226 68 220 64 186 Z",
            ic.rad("toxic", 0.4, 0.35, 0.85), "toxic", hl("M82 170 C88 150 104 140 122 138 C104 150 94 162 90 180 Z", 0.5))
    for x, y, rot in [(62, 96, -22), (128, 66, 0), (194, 96, 22)]:
        ic.part(ell_path(x, y, 26, 36, rot), ic.rad("toxic", 0.4, 0.35, 0.85), "toxic",
                ell(x - 8, y - 12, 8, 12, "#ffffff", 0.5, rot))
        # claw
        cx, cy = x + 44 * math.sin(math.radians(rot)), y - 44 * math.cos(math.radians(rot))
        ic.part("M-8 0 L0 -26 L8 0 Z", ic.lin("bone", 0), "bone", tf=f"translate({cx:.1f} {cy:.1f}) rotate({rot})", ow=10)


@icon
def diff_brutal(ic):
    ic.glow("#ff4a3a", 128, 128, 110, 0.3)
    slashes(ic, "danger", 3)


@icon
def diff_apex(ic):
    ic.glow("#b07ae8", 128, 140, 124, 0.55)
    # horned skull with crown: highest tier
    oc = PAL["violet"][3]
    for s in (-1, 1):
        d = f"M{128 + s*60} 96 C{128 + s*100} 80 {128 + s*118} 50 {128 + s*112} 14 C{128 + s*96} 44 {128 + s*76} 58 {128 + s*50} 64 Z"
        ic.part(d, ic.lin("bone", 0), "bone")
    skull_shape(ic, "violet", "translate(128 150) scale(0.72) translate(-128 -120)")
    crown_shape(ic, "translate(128 36) scale(0.34) translate(-128 -130)")


@icon
def clock(ic):
    ic.part(circle_path(128, 136, 100), ic.lin("bone", 15), "bone",
            f'<circle cx="128" cy="136" r="78" fill="{PAL["moss"][2]}"/>' +
            shade(circle_path(134, 142, 74), 0.3) +
            "".join(f'<path d="M{128 + 64*math.cos(math.radians(a)):.1f} {136 + 64*math.sin(math.radians(a)):.1f} L{128 + 74*math.cos(math.radians(a)):.1f} {136 + 74*math.sin(math.radians(a)):.1f}" stroke="{PAL["bone"][1]}" stroke-width="8" stroke-linecap="round"/>' for a in range(0, 360, 90)) +
            f'<path d="M128 136 L128 82 M128 136 L166 156" stroke="{PAL["cyan"][1]}" stroke-width="12" stroke-linecap="round"/>' +
            circ(128, 136, 10, PAL["cyan"][0]) +
            hl("M48 118 C54 76 88 46 128 42 C94 58 70 84 62 124 Z", 0.55))
    for x in (78, 178):
        ic.part(f"M{x-18} 40 L{x+18} 40 L{x+14} 22 L{x-14} 22 Z", ic.lin("bone", 0), "bone", tf=f"rotate({-30 if x < 128 else 30} {x} 40)", ow=14)


@icon
def reroll(ic):
    oc = PAL["cyan"][3]
    for rot in (0, 180):
        arc = "M58 132 C58 90 90 58 132 58 C156 58 176 68 190 84"
        head_ = "M170 56 L222 70 L206 122 Z"
        ic.raw(f'<path d="{arc}" stroke="{oc}" stroke-width="54" fill="none" stroke-linecap="round"/>'
               f'<path d="{head_}" fill="{oc}" stroke="{oc}" stroke-width="{OUT_W}" stroke-linejoin="round"/>'
               f'<path d="{arc}" stroke="{PAL["cyan"][2] if rot else PAL["cyan"][1]}" stroke-width="30" fill="none" stroke-linecap="round"/>'
               f'<path d="{head_}" fill="{PAL["cyan"][2] if rot else PAL["cyan"][1]}"/>'
               f'<path d="M66 124 C68 96 90 72 120 68" stroke="#ffffff" stroke-opacity="0.55" stroke-width="8" fill="none" stroke-linecap="round"/>',
               f"rotate({rot} 128 128)")


@icon
def banish(ic):
    oc = PAL["danger"][3]
    ring = "M128 22 A106 106 0 1 1 127.9 22 Z M128 58 A70 70 0 1 0 128.1 58 Z"
    ic.raw(f'<circle cx="128" cy="128" r="106" fill="none" stroke="{oc}" stroke-width="{36 + OUT_W}"/>'
           f'<path d="M62 62 L194 194" stroke="{oc}" stroke-width="{36 + OUT_W}" stroke-linecap="round"/>'
           f'<circle cx="128" cy="128" r="106" fill="none" stroke="{ic.lin("danger", 20)}" stroke-width="34"/>'
           f'<path d="M62 62 L194 194" stroke="{PAL["danger"][1]}" stroke-width="34" stroke-linecap="round"/>'
           f'<path d="M50 104 C60 68 90 42 128 36" stroke="#ffffff" stroke-opacity="0.5" stroke-width="8" fill="none" stroke-linecap="round"/>'
           f'<path d="M70 62 L110 102" stroke="#ffffff" stroke-opacity="0.45" stroke-width="8" stroke-linecap="round"/>')


@icon
def skip(ic):
    chev = "M0 -80 L80 0 L0 80 L-24 56 L32 0 L-24 -56 Z"
    for x in (86, 162):
        ic.part(chev, ic.lin("bone", 20), "bone", hl("M-4 -64 L56 -4 L44 -4 L-12 -56 Z", 0.5), f"translate({x - 20} 128)")



# --- second batch: biomass, creatures, Brutkammer upgrades, instinct --------
def plus_badge(ic, x=196, y=196, r=38, pal="toxic"):
    ic.part(circle_path(x, y, r), ic.rad(pal, 0.4, 0.35, 0.8), pal, hl(ell_path(x - r * 0.3, y - r * 0.4, r * 0.45, r * 0.25), 0.5), ow=14)
    w, l = r * 0.24, r * 0.62
    d = poly([(x - w, y - l), (x + w, y - l), (x + w, y - w), (x + l, y - w), (x + l, y + w), (x + w, y + w),
              (x + w, y + l), (x - w, y + l), (x - w, y + w), (x - l, y + w), (x - l, y - w), (x - w, y - w)])
    ic.part(d, "#ffffff", pal, ow=8)


def star(x, y, s):
    return poly([(x, y - 16 * s), (x + 5 * s, y - 5 * s), (x + 16 * s, y), (x + 5 * s, y + 5 * s),
                 (x, y + 16 * s), (x - 5 * s, y + 5 * s), (x - 16 * s, y), (x - 5 * s, y - 5 * s)])


@icon
def biomass(ic):
    # a fleshy amber lump (not a drop), veined, with a small drip
    ic.glow("#efb642", 128, 150, 110, 0.3)
    lump = ("M44 190 C30 150 52 110 88 106 C96 70 140 58 164 84 C196 80 222 110 212 146 "
            "C232 170 220 212 184 220 C150 236 90 234 60 220 C46 214 40 202 44 190 Z")
    ic.part(lump, ic.rad("amber", 0.4, 0.3, 0.85), "amber",
            f'<path d="M70 190 C90 170 110 180 128 160 C140 146 160 150 176 136 M128 160 C130 184 150 196 170 196 M96 132 C104 146 100 160 90 170" '
            f'stroke="{PAL["amber"][2]}" stroke-width="6" fill="none" stroke-linecap="round"/>' +
            shade("M48 200 C80 226 170 234 214 190 C200 222 150 236 90 230 C66 226 50 214 48 200 Z", 0.3) +
            ell(84, 128, 16, 10, "#fff3c0", 0.7, -30) + ell(140, 86, 14, 8, "#fff3c0", 0.7, -20) +
            ell(190, 116, 10, 6, "#fff3c0", 0.6, 10) +
            circ(112, 200, 7, PAL["amber"][2], 0.6) + circ(186, 180, 6, PAL["amber"][2], 0.6))
    drop(ic, "amber", 150, 238, 0.28, 0, ow=34)


@icon
def hunter(ic):
    oc = PAL["bone"][3]
    for tf in ("translate(0 18) scale(0.92)",):
        horn1 = "M58 92 C30 60 22 30 34 4 C52 34 74 54 100 64 Z"
        horn2 = "M104 60 C92 30 100 6 120 -10 C124 20 132 38 146 50 Z"
        ic.part(horn1, ic.lin("bone", 20), "bone", hl("M40 20 C44 44 56 62 72 78 C54 66 44 46 40 20 Z", 0.5), tf)
        ic.part(horn2, ic.lin("bone", 20), "bone", tf=tf)
        head(ic, "violet", tf)
    ic.raw(circ(147, 95, 7, "#ff4a3a", 0.85))


@icon
def skitter(ic):
    # fast insect head, front view: huge magenta compound eyes, mandibles, speed streaks
    oc = PAL["blue"][3]
    ic.raw(f'<path d="M8 110 L44 110 M2 146 L36 146 M12 182 L44 182" stroke="{oc}" stroke-width="18" stroke-linecap="round"/>'
           f'<path d="M8 110 L44 110 M2 146 L36 146 M12 182 L44 182" stroke="{PAL["blue"][0]}" stroke-width="7" stroke-linecap="round"/>')
    ant = "M112 72 C100 40 80 24 62 18 M160 72 C172 40 196 24 214 18"
    ic.raw(f'<path d="{ant}" stroke="{oc}" stroke-width="22" fill="none" stroke-linecap="round"/>'
           f'<path d="{ant}" stroke="{PAL["magenta"][1]}" stroke-width="9" fill="none" stroke-linecap="round"/>')
    for s in (-1, 1):
        d = f"M{136 + s*26} 176 C{136 + s*52} 196 {136 + s*52} 226 {136 + s*28} 242 C{136 + s*32} 222 {136 + s*22} 206 {136 + s*6} 196 Z"
        ic.part(d, ic.lin("bone", 0), "bone")
    ic.part(ell_path(136, 136, 78, 66), ic.lin("blue", 20), "blue",
            hl("M72 116 C80 90 110 74 140 72 C110 84 90 100 84 124 Z", 0.4) +
            shade("M64 150 C80 196 190 200 210 150 C200 190 80 196 64 150 Z", 0.3) +
            f'<path d="M136 80 L136 112" stroke="{PAL["blue"][2]}" stroke-width="6" stroke-linecap="round"/>')
    for s in (-1, 1):
        cx = 136 + s * 42
        ic.part(ell_path(cx, 136, 30, 36, s * 20), ic.rad("magenta", 0.35, 0.3, 0.8), "magenta",
                "".join(circ(cx + dx, 136 + dy, 4.5, PAL["magenta"][2], 0.55) for dx, dy in [(-8, 8), (6, 14), (10, -4), (-4, -10), (-12, 20)]) +
                ell(cx - 10, 122, 8, 11, "#ffffff", 0.8, s * 20), ow=14)


@icon
def leaper(ic):
    # crouched frog-lizard with a huge folded hind leg and a leap arc
    ic.raw('<path d="M24 118 C40 48 120 18 196 34" stroke="#ead2ff" stroke-opacity="0.85" stroke-width="10" fill="none" stroke-linecap="round" stroke-dasharray="18 16"/>')
    ic.part("M168 170 L196 232 L232 234 L214 218 L200 170 Z", ic.lin("violet", 0), "violet")
    ic.part(ell_path(148, 148, 72, 46, -18), ic.lin("teal", 20), "teal",
            hl("M92 140 C100 118 130 100 170 98 C140 110 116 124 104 146 Z", 0.45) +
            "".join(circ(x, y, r, PAL["teal"][2], 0.7) for x, y, r in [(130, 150, 8), (160, 136, 6), (112, 170, 6)]))
    ic.part("M204 84 C236 84 248 112 240 132 C232 146 214 150 196 146 C176 142 168 120 176 100 C182 90 192 84 204 84 Z",
            ic.lin("teal", 20), "teal",
            f'<path d="M198 134 C212 138 230 136 240 128" stroke="{PAL["teal"][3]}" stroke-width="4" fill="none"/>' +
            circ(208, 104, 10, PAL["teal"][3]) + circ(208, 104, 7, "#fff3c0") + ell(209, 104, 2.5, 6, "#140605"))
    thigh = "M118 128 C70 102 30 132 38 180 C44 214 92 226 124 204 C138 188 138 150 118 128 Z"
    ic.part(thigh, ic.lin("violet", 20), "violet",
            hl("M50 160 C54 134 76 118 100 118 C80 128 64 144 60 168 Z", 0.45) +
            shade("M44 196 C66 222 110 222 128 200 C110 214 70 214 44 196 Z", 0.3))
    ic.part("M44 196 L20 236 L96 238 L84 222 L60 222 L70 204 Z", ic.lin("violet", 0), "violet")


@icon
def nibbler(ic):
    leaf = "M0 0 C-20 -24 -24 -70 0 -100 C24 -70 20 -24 0 0 Z"
    for tf in ("translate(60 150) rotate(-70) scale(0.62)", "translate(196 150) rotate(70) scale(0.62)", "translate(128 74) rotate(0) scale(0.6)"):
        ic.part(leaf, ic.lin("leaf", 0), "leaf",
                f'<path d="M0 -6 L0 -90" stroke="{PAL["leaf"][2]}" stroke-width="5" stroke-linecap="round"/>', tf)
    ic.part(circle_path(128, 148, 80), ic.rad("teal", 0.38, 0.3, 0.85), "teal",
            shade("M52 170 C70 236 186 236 204 170 C190 214 70 214 52 170 Z", 0.3) +
            hl("M66 120 C74 92 100 74 130 72 C100 86 84 102 78 128 Z", 0.4) +
            ell(84, 180, 14, 9, "#ff8a7a", 0.45) + ell(172, 180, 14, 9, "#ff8a7a", 0.45))
    for x in (100, 156):
        ic.raw(circ(x, 138, 27, PAL["teal"][3]) + f'<circle cx="{x}" cy="138" r="22" fill="{ic.rad("gold", 0.4, 0.35, 0.8)}"/>' +
               circ(x + 3, 142, 10, "#140c02") + circ(x - 6, 131, 5.5, "#ffffff"))
    ic.raw(f'<path d="M110 184 C120 194 136 194 146 184" stroke="{PAL["teal"][3]}" stroke-width="6" fill="none" stroke-linecap="round"/>'
           f'<path d="M120 188 L120 200 L128 200 L128 190 Z M128 190 L128 200 L136 200 L136 188 Z" fill="{BONE_T}" stroke="{PAL["teal"][3]}" stroke-width="3"/>')


@icon
def bog_king(ic):
    ic.glow("#8e3a92", 128, 128, 128, 0.6)
    ic.tf = "translate(128 140) scale(0.9) translate(-128 -140)"
    for x, h, w in [(62, 58, 20), (94, 76, 22), (128, 86, 24), (162, 76, 22), (194, 58, 20)]:
        ic.part(poly([(x - w, 84), (x, 84 - h), (x + w, 84)]), ic.lin("bone", 0), "bone",
                hl(poly([(x - w + 6, 82), (x - 2, 90 - h), (x, 82)]), 0.5))
    face = ("M36 124 C36 76 78 58 128 58 C178 58 220 76 220 124 C236 152 228 192 204 212 "
            "C172 238 84 238 52 212 C28 192 20 152 36 124 Z")
    ic.part(face, ic.lin("plum", 15), "plum",
            hl("M50 120 C54 90 84 72 124 70 C92 82 70 98 64 128 Z", 0.35) +
            "".join(circ(x, y, r, PAL["plum"][2], 0.6) for x, y, r in [(70, 150, 9), (190, 146, 8), (128, 92, 7), (56, 186, 6), (204, 184, 6)]))
    # glowing slanted eyes
    for s in (-1, 1):
        d = f"M{128 + s*20} 124 L{128 + s*74} 104 C{128 + s*72} 128 {128 + s*56} 140 {128 + s*28} 136 Z"
        ic.raw(f'<path d="{d}" fill="{PAL["plum"][3]}" stroke="{PAL["plum"][3]}" stroke-width="10" stroke-linejoin="round"/>'
               f'<path d="{d}" fill="{ic.lin("acid", 0)}"/>')
    mouth = "M62 164 C100 180 156 180 194 164 C190 214 66 214 62 164 Z"
    ic.part(mouth, "#2a0612", "plum")
    up = teeth_row([(70, 168), (94, 174), (116, 177), (140, 177), (162, 174), (186, 168)], -22)
    lw = teeth_row([(92, 205), (116, 208), (140, 208), (164, 205)], 18)
    teeth_group(ic, up + lw, "plum")


@icon
def up_brood_size(ic):
    ic.glow("#3fe6d8", 118, 130, 110, 0.3)
    for (cx, cy, rot) in [(118, 78, 0), (74, 136, -18), (160, 138, 18)]:
        ic.part(ell_path(cx, cy, 40, 52, rot), ic.rad("cyan", 0.35, 0.28, 0.9), "cyan",
                ell(cx - 12, cy - 20, 7, 9, PAL["cyan"][2], 0.85, rot) + ell(cx + 14, cy + 4, 9, 8, PAL["cyan"][2], 0.85, rot) +
                ell(cx - 6, cy + 24, 7, 6, PAL["cyan"][2], 0.85, rot) + ell(cx - 16, cy - 26, 8, 15, "#ffffff", 0.7, rot - 20))
    plus_badge(ic, 196, 196, 42, "toxic")


@icon
def up_bite(ic):
    tooth_ = "M60 50 C100 34 150 36 186 52 C190 120 166 186 128 240 C120 248 110 246 108 236 C86 180 58 120 60 50 Z"
    ic.part(tooth_, ic.lin("bone", 15), "bone",
            hl("M76 64 C80 120 92 170 110 214 C90 164 80 116 86 64 Z", 0.7) +
            shade("M170 60 C168 120 150 180 128 228 C154 180 176 120 180 62 Z", 0.28) +
            f'<path d="M96 110 L120 132 L106 150 L128 172" stroke="{PAL["bone"][2]}" stroke-width="5" fill="none" stroke-linecap="round"/>', "rotate(-14 128 140)")
    ic.glow("#ffb347", 196, 64, 60, 0.7)
    ic.part(star(196, 62, 3.0), ic.rad("gold"), "gold", ow=12)
    ic.part(star(226, 128, 1.2), ic.rad("gold"), "gold", ow=8)


@icon
def up_chitin(ic):
    shield = "M128 20 C166 38 200 44 228 44 C228 132 198 200 128 238 C58 200 28 132 28 44 C56 44 90 38 128 20 Z"
    ic.part(shield, ic.lin("toxic", 10), "toxic",
            f'<path d="M44 92 C90 108 166 108 212 92 M52 146 C96 162 160 162 204 146 M76 196 C104 208 152 208 180 196" stroke="{PAL["toxic"][3]}" stroke-width="9" fill="none" stroke-linecap="round"/>'
            f'<path d="M44 84 C90 100 166 100 212 84 M54 138 C96 154 160 154 202 138" stroke="{PAL["toxic"][0]}" stroke-width="4" fill="none" stroke-linecap="round" stroke-opacity="0.7"/>'
            f'<path d="M128 30 L128 226" stroke="{PAL["toxic"][3]}" stroke-width="7" stroke-linecap="round"/>' +
            hl("M44 56 C70 54 100 46 122 36 L122 90 C94 92 66 86 46 80 Z", 0.35) +
            shade("M134 150 L200 150 C190 184 166 210 134 226 Z", 0.25))
    # bone rim studs
    for x, y in [(52, 60), (204, 60), (128, 34), (84, 190), (172, 190)]:
        ic.part(circle_path(x, y, 9), ic.rad("bone"), "bone", ow=8)


def claw_print(ic, x, y, rot, s):
    tf = f"translate({x} {y}) rotate({rot}) scale({s})"
    ic.part(ell_path(0, 20, 30, 26), ic.rad("teal", 0.4, 0.35, 0.85), "teal", hl(ell_path(-8, 12, 10, 6), 0.5), tf)
    for a in (-34, 0, 34):
        ic.part("M-9 0 L0 -42 L9 0 Z", ic.lin("bone", 0), "bone", tf=f"{tf} rotate({a}) translate(0 -12)", ow=12)


@icon
def up_sprint(ic):
    oc = PAL["cyan"][3]
    lines = "M20 150 L80 150 M34 190 L98 190 M14 110 L60 110"
    ic.raw(f'<path d="{lines}" stroke="{oc}" stroke-width="20" stroke-linecap="round"/>'
           f'<path d="{lines}" stroke="{PAL["cyan"][1]}" stroke-width="8" stroke-linecap="round"/>')
    claw_print(ic, 128, 186, 70, 1.35)
    claw_print(ic, 184, 84, 70, 1.35)


@icon
def up_digest(ic):
    ic.glow("#efb642", 128, 150, 100, 0.3)
    d = ("M98 22 C84 22 78 40 86 56 C98 80 70 102 58 132 C40 182 78 232 134 228 C192 224 226 182 216 134 "
         "C208 94 170 86 148 102 C128 116 112 98 114 64 C116 40 110 22 98 22 Z")
    ic.part(d, ic.rad("amber", 0.4, 0.45, 0.8), "amber",
            f'<path d="M76 160 C96 150 104 170 124 162 C144 154 150 176 172 168 M84 196 C104 188 118 204 140 196 C156 190 170 200 186 194" stroke="{PAL["amber"][2]}" stroke-width="6" fill="none" stroke-linecap="round"/>' +
            hl("M70 136 C78 114 96 98 104 84 C100 106 92 124 82 144 Z", 0.55) +
            shade("M64 190 C84 230 176 234 208 180 C190 214 110 226 64 190 Z", 0.3) +
            circ(170, 130, 10, "#fff3c0", 0.7) + circ(150, 118, 6, "#fff3c0", 0.6) + circ(186, 150, 5, "#fff3c0", 0.6))


@icon
def up_gene(ic):
    ic.glow("#3fe6d8", 110, 118, 100, 0.3)
    dna_draw(ic, "translate(-18 -10) scale(0.92) rotate(-18 128 128)")
    plus_badge(ic, 196, 196, 42, "toxic")


@icon
def up_attack_slot(ic):
    ic.glow("#ff7a2e", 128, 128, 90, 0.5)
    ic.part(circle_path(128, 128, 80), ic.lin("moss", 0), "moss",
            f'<circle cx="128" cy="128" r="72" fill="none" stroke="{PAL["ember"][1]}" stroke-width="6"/>' +
            f'<circle cx="128" cy="128" r="56" fill="#08120d"/>' +
            f'<circle cx="128" cy="128" r="56" fill="none" stroke="{PAL["ember"][2]}" stroke-width="5"/>' +
            ell(128, 138, 34, 26, "#ff7a2e", 0.25))
    claw = "M-18 0 C-20 -40 -6 -80 26 -104 C18 -70 16 -36 18 0 Z"
    for a in (-60, 60, 180):
        ic.part(claw, ic.lin("ember", 20), "ember",
                hl("M-12 -4 C-12 -40 0 -74 20 -96 C8 -64 -2 -36 -4 -4 Z", 0.5),
                f"translate(128 128) rotate({a}) translate(0 -58) scale(0.62)")


@icon
def up_trait_slot(ic):
    ic.glow("#b07ae8", 128, 128, 70, 0.6)
    for a in range(0, 360, 90):
        x, y = 128 + 96 * math.cos(math.radians(a + 45)), 128 + 96 * math.sin(math.radians(a + 45))
        ic.part(circle_path(x, y, 22), ic.rad("bone"), "bone", tf="", ow=16)
    ic.part(circle_path(128, 128, 92), ic.lin("bone", 15), "bone",
            hl("M48 110 C56 70 90 42 128 38 C94 54 70 80 62 116 Z", 0.55) +
            f'<circle cx="128" cy="128" r="58" fill="{PAL["bone"][3]}"/>' +
            f'<circle cx="128" cy="128" r="50" fill="{ic.rad("violet", 0.5, 0.5, 0.6)}" fill-opacity="0.55"/>' +
            f'<circle cx="128" cy="128" r="50" fill="none" stroke="{PAL["bone"][2]}" stroke-width="4"/>' +
            f'<path d="M72 60 L84 76 M184 60 L172 76 M72 196 L84 180 M184 196 L172 180" stroke="{PAL["bone"][2]}" stroke-width="5" stroke-linecap="round"/>')


@icon
def instinct(ic):
    ic.glow("#b07ae8", 128, 128, 128, 0.55)
    oc = PAL["violet"][3]
    ic.raw(f'<circle cx="128" cy="128" r="104" fill="none" stroke="{oc}" stroke-width="{18 + OUT_W}"/>'
           f'<circle cx="128" cy="128" r="104" fill="none" stroke="{ic.lin("violet", 0)}" stroke-width="18"/>'
           f'<circle cx="128" cy="128" r="104" fill="none" stroke="#ead2ff" stroke-width="3" stroke-opacity="0.7" stroke-dasharray="14 12"/>')
    for a in range(0, 360, 45):
        ic.part("M-10 0 L0 -22 L10 0 Z", ic.lin("bone", 0), "bone", tf=f"translate(128 128) rotate({a}) translate(0 -112)", ow=10)
    eye = "M34 128 C78 66 178 66 222 128 C178 190 78 190 34 128 Z"
    ic.part(eye, ic.lin("bone", 0), "bone",
            f'<circle cx="128" cy="128" r="46" fill="{ic.rad("amber", 0.45, 0.4, 0.7)}"/>' +
            f'<circle cx="128" cy="128" r="46" fill="none" stroke="{PAL["amber"][2]}" stroke-width="4"/>' +
            ell(128, 128, 10, 38, "#140a02") + ell(116, 110, 10, 7, "#ffffff", 0.85, -30) +
            shade("M40 134 C84 186 172 186 216 134 C172 172 84 172 40 134 Z", 0.25))


@icon
def restart(ic):
    oc = PAL["ember"][3]
    arc = "M200 92 C178 52 132 38 92 52 C50 68 30 112 40 154 C52 202 104 228 150 216 C182 208 204 186 214 158"
    head_ = "M172 52 L232 58 L214 116 Z"
    ic.raw(f'<path d="{arc}" stroke="{oc}" stroke-width="50" fill="none" stroke-linecap="round"/>'
           f'<path d="{head_}" fill="{oc}" stroke="{oc}" stroke-width="{OUT_W}" stroke-linejoin="round"/>'
           f'<path d="{arc}" stroke="{ic.lin("ember", 30)}" stroke-width="28" fill="none" stroke-linecap="round"/>'
           f'<path d="{head_}" fill="{PAL["ember"][1]}"/>'
           f'<path d="M58 128 C58 92 80 66 112 58" stroke="#ffffff" stroke-opacity="0.5" stroke-width="7" fill="none" stroke-linecap="round"/>')
    for i in range(3):
        off = (i - 1) * 26
        d = f"M{96 + off} 176 C{106 + off} 146 {122 + off} 118 {148 + off} 90 C{134 + off} 124 {122 + off} 152 {110 + off} 182 Z"
        ic.part(d, ic.lin("bone", 20), "bone", ow=12)


@icon
def hub(ic):
    ic.glow("#efb642", 128, 170, 70, 0.5)
    mound = "M14 226 C20 150 64 88 128 88 C192 88 236 150 242 226 Z"
    ic.part(mound, ic.lin("moss", 0), "moss",
            hl("M34 200 C44 150 80 110 128 104 C90 120 62 150 52 206 Z", 0.2) +
            f'<path d="M40 180 L62 170 M196 176 L220 186 M84 118 L96 128 M166 120 L176 108" stroke="#6f9150" stroke-width="7" stroke-linecap="round"/>' +
            ell(128, 226, 70, 20, "#000000", 0.25))
    ic.part("M66 226 C66 170 92 136 128 136 C164 136 190 170 190 226 Z", "#0a120c", "moss", ow=12)
    ic.part(ell_path(128, 190, 32, 40), ic.rad("amber", 0.35, 0.28, 0.9), "amber",
            ell(116, 172, 7, 12, "#ffffff", 0.7, -20) + circ(138, 196, 6, PAL["amber"][2], 0.7) + circ(122, 212, 5, PAL["amber"][2], 0.7), ow=14)
    # bone ribs arching over the burrow
    for s in (-1, 1):
        ic.part(f"M{128 + s*96} 226 C{128 + s*100} 150 {128 + s*60} 96 {128 + s*14} 70 C{128 + s*50} 108 {128 + s*80} 160 {128 + s*80} 226 Z",
                ic.lin("bone", 0), "bone", ow=14)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in ICONS.items():
        ic = Icon(name)
        fn(ic)
        with open(os.path.join(OUT, name + ".svg"), "w", encoding="utf-8") as f:
            f.write(ic.svg())
    print(len(ICONS), "icons:", " ".join(ICONS))


if __name__ == "__main__":
    main()
