"""Calm UI skin (UiStyle.skin = "calm"): copies the V2 vector kit and derives
nine-slice frames from it.

Source (read only): C:/Users/vrxby/Documents/Codex/Swarm/Design/UI_Assets_V2/
  Vector/*.svg  -> assets/ui/v2/vector/ (unchanged copies, for reference/icons)
  derived      -> assets/ui/v2/frames/  (same shapes, strokes and colours as
                  the kit, but split into a fixed-colour body and a white
                  accent layer so scripts/ui/ui_frames.gd can tint them, and
                  sized as nine-slices without the card's layout lines)

Run from the project root: python assets/ui/v2/build_calm_frames.py
Import settings: svg/scale = 2.0 (like assets/ui/frames), set in the .import files.
"""
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent
KIT = Path(r"C:\Users\vrxby\Documents\Codex\Swarm\Design\UI_Assets_V2\Vector")
BG = "#09191C"


def svg(width, height, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
            f'viewBox="0 0 {width} {height}">\n{body}\n</svg>\n')


def chamfer(x0, y0, x1, y1, c):
    return f"M{x0 + c} {y0}H{x1 - c}L{x1} {y0 + c}V{y1 - c}L{x1 - c} {y1}H{x0 + c}L{x0} {y1 - c}V{y0 + c}Z"


FRAMES = {
    # Mutation card (mutation_card_*.svg, 240 x 200 instead of 660 x 170).
    # Nine-slice margins (svg units): 24, 46, 24, 44.
    "card_body": svg(240, 200, f'<path d="{chamfer(4, 4, 236, 196, 16)}" fill="{BG}" fill-opacity=".97" stroke="#3D665F" stroke-width="3"/>'),
    "card_accent": svg(240, 200, "\n".join([
        '<path d="M20 4H220L236 20V43H4V20Z" fill="#FFFFFF" fill-opacity=".13"/>',
        '<path d="M4 42V20L20 4H220L236 20V42" fill="none" stroke="#FFFFFF" stroke-width="5"/>',
        '<path d="M4 156V180L20 196H220L236 180V156" fill="none" stroke="#FFFFFF" stroke-opacity=".7" stroke-width="4"/>',
        '<path d="M4 37L19 20M236 37L221 20M4 163L19 180M236 163L221 180" stroke="#FFFFFF" stroke-width="4"/>',
    ])),
    "card_focus": svg(240, 200, "\n".join([
        f'<path d="{chamfer(3, 3, 237, 197, 17)}" fill="none" stroke="#F4E7BD" stroke-width="5"/>',
        '<path d="M25 12H215M25 188H215" stroke="#F4E7BD" stroke-opacity=".46" stroke-width="2"/>',
    ])),
    # HUD panel (hud_panel.svg, 120 x 96). Margins 22, 22, 22, 36.
    "panel_body": svg(120, 96, "\n".join([
        f'<path d="M18 4H102L116 19V77L102 92H18L4 77V19Z" fill="{BG}" fill-opacity=".94" stroke="#37645E" stroke-width="3"/>',
        '<path d="M20 17H100" stroke="#76CFC0" stroke-opacity=".4" stroke-width="2"/>',
        '<path d="M5 61L17 77V91M115 61L103 77V91" fill="none" stroke="#A8C4AC" stroke-opacity=".35" stroke-width="3"/>',
        '<path d="M28 78H92" stroke="#204443" stroke-width="2"/>',
    ])),
    "panel_edge": svg(120, 96, '<path d="M18 4H102L116 19V77L102 92H18L4 77V19Z" fill="none" stroke="#FFFFFF" stroke-width="3"/>'),
    # Chip (hud_panel_compact.svg, 100 x 48). Margins 16 all round.
    "pill_body": svg(100, 48, "\n".join([
        f'<path d="{chamfer(3, 3, 97, 45, 10)}" fill="{BG}" fill-opacity=".94" stroke="#37645E" stroke-width="3"/>',
        '<path d="M16 12H84" stroke="#76CFC0" stroke-opacity=".3" stroke-width="2"/>',
    ])),
    "pill_edge": svg(100, 48, f'<path d="{chamfer(3, 3, 97, 45, 10)}" fill="none" stroke="#FFFFFF" stroke-width="3"/>'),
    # Buttons (round_button_base.svg, 120 x 72). Margins 24 all round.
    "button_secondary": svg(120, 72, "\n".join([
        f'<path d="{chamfer(4, 4, 116, 68, 11)}" fill="#0A1B1E" fill-opacity=".96" stroke="#6E9F93" stroke-width="3"/>',
        '<path d="M15 13H105" stroke="#C3DCC5" stroke-opacity=".36" stroke-width="2"/>',
    ])),
    "button_primary": svg(120, 72, "\n".join([
        f'<path d="{chamfer(4, 4, 116, 68, 11)}" fill="#B9653B" stroke="#F2B36E" stroke-width="3"/>',
        '<path d="M15 13H105" stroke="#FFE3B8" stroke-opacity=".5" stroke-width="2"/>',
        '<path d="M15 59H105" stroke="#6E321C" stroke-opacity=".45" stroke-width="2"/>',
    ])),
    # Round button (rally_button_base / joystick style, 128 x 128, r 60).
    "round_body": svg(128, 128, "\n".join([
        f'<circle cx="64" cy="64" r="60" fill="#081719" fill-opacity=".9" stroke="#6A7C62" stroke-width="4"/>',
        '<path d="M64 4V13M64 115V124M4 64H13M115 64H124" stroke="#A8C4AC" stroke-opacity=".5" stroke-width="3"/>',
    ])),
    "round_ring": svg(128, 128, '<circle cx="64" cy="64" r="51" fill="none" stroke="#FFFFFF" stroke-width="4"/>'),
    # Progress bar (progress_track.svg / progress_fill_*.svg, 300 x 24).
    # Margins 14, 12, 14, 12. The fill is light grey with a white highlight so
    # one tint keeps the kit's two-tone look.
    "bar_track": svg(300, 24, "\n".join([
        '<path d="M12 2H288L298 12L288 22H12L2 12Z" fill="#071215" stroke="#46736D" stroke-width="2"/>',
        '<path d="M15 7H285" stroke="#B6D7CB" stroke-opacity=".15" stroke-width="2"/>',
    ])),
    "bar_fill": svg(300, 24, "\n".join([
        '<path d="M12 3H286L296 12L286 21H12L4 12Z" fill="#D2D2D2"/>',
        '<path d="M16 7H283" stroke="#FFFFFF" stroke-opacity=".75" stroke-width="3"/>',
    ])),
}


def main():
    vector = ROOT / "vector"
    frames = ROOT / "frames"
    vector.mkdir(exist_ok=True)
    frames.mkdir(exist_ok=True)
    for source in sorted(KIT.glob("*.svg")):
        shutil.copyfile(source, vector / source.name)
    for name, text in FRAMES.items():
        (frames / f"{name}.svg").write_text(text, encoding="utf-8")
    print(f"{len(list(KIT.glob('*.svg')))} kit SVGs copied, {len(FRAMES)} calm frames written")


if __name__ == "__main__":
    main()
