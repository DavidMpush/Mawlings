"""Builds the two UI fonts of the "brawl" skin (stage 15) from the OFL candidates.

    PYTHONPATH=.tools python tools/subset_fonts.py

- assets/ui/fonts/display.ttf  <- candidates/baloo2/Baloo2.ttf  (variable wght 400-800)
- assets/ui/fonts/body.ttf     <- candidates/figtree/Figtree.ttf (variable wght 300-900)

Both stay variable fonts; the weight is chosen in Godot through a FontVariation
(scripts/ui/ui_style.gd: Baloo 800, Figtree 500/700). The subset keeps Latin
with German umlauts, the Latin-1 supplement, typographic punctuation, the euro
sign, arrows and the maths signs the game texts use. Layout features kept:
kerning, tnum/pnum/lnum (tabular digits for timers and counters), case, frac,
locl, ccmp, liga. fontTools lives in .tools/ (pip install --target .tools fonttools).
"""
from pathlib import Path
import shutil

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent
FONTS = ROOT / "assets" / "ui" / "fonts"
JOBS = [
    ("candidates/baloo2/Baloo2.ttf", "display.ttf", "OFL_display.txt"),
    ("candidates/figtree/Figtree.ttf", "body.ttf", "OFL_body.txt"),
]
UNICODES = (
    list(range(0x20, 0x7F))            # Basic Latin
    + list(range(0xA0, 0x100))         # Latin-1 (umlauts, ß, ×, ·, ±, «»)
    + [0x152, 0x153, 0x178, 0x1E9E]    # Œ œ Ÿ ẞ
    + [0x2013, 0x2014, 0x2018, 0x2019, 0x201A, 0x201C, 0x201D, 0x201E,
       0x2022, 0x2026, 0x2030, 0x2039, 0x203A, 0x2212, 0x20AC, 0x2122]
    + [0x2190, 0x2191, 0x2192, 0x2193]  # arrows
    + [0x2248, 0x2260, 0x2264, 0x2265, 0x221E, 0x25B2, 0x25BC]
)
METRICS = {"display.ttf": (900, 300)}   # (ascent, descent) in font units, 1000 upm
FEATURES = ["kern", "tnum", "pnum", "lnum", "case", "frac", "numr", "dnom",
            "locl", "ccmp", "liga", "calt", "mark", "mkmk", "rvrn"]


def build(src: str, dst: str, licence: str) -> None:
    options = subset.Options()
    options.layout_features = FEATURES
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    options.notdef_outline = True
    options.glyph_names = False
    options.hinting = False            # Godot rasterises unhinted with light AA
    font = TTFont(str(FONTS / src))
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=UNICODES)
    subsetter.subset(font)
    if dst in METRICS:
        # Baloo 2 reserves Devanagari headroom (ascent 1078, descent 524 =
        # 1.6 em line box). The Latin subset gets a tight box (Ä top 786,
        # g bottom -202) so Labels and vertical centring line up.
        ascent, descent = METRICS[dst]
        font["hhea"].ascent, font["hhea"].descent, font["hhea"].lineGap = ascent, -descent, 0
        os2 = font["OS/2"]
        os2.sTypoAscender, os2.sTypoDescender, os2.sTypoLineGap = ascent, -descent, 0
        os2.usWinAscent, os2.usWinDescent = ascent, descent
    font.save(str(FONTS / dst))
    shutil.copyfile(FONTS / Path(src).parent / "OFL.txt", FONTS / licence)
    cmap = font.getBestCmap()
    missing = [hex(u) for u in UNICODES if u not in cmap]
    size = (FONTS / dst).stat().st_size // 1024
    print(f"{dst}: {size} KB, {len(font.getGlyphOrder())} glyphs, missing {missing}")


if __name__ == "__main__":
    for job in JOBS:
        build(*job)
