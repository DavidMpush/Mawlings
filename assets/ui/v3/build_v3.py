"""Builds the small in-game copies of the V2 expansion artwork (UI kit V2,
EXPANSION_ASSETS.md) into assets/ui/v3/. The Swarm sources are only read.

Run from the project root: python assets/ui/v3/build_v3.py
Needs numpy and Pillow. Sizes are chosen for the 900 x 1600 base canvas at
up to ~1.2x device scale; photos are JPEG/WebP-sized PNGs, icons 256 px.
Two tribe portraits are recoloured to their strain tint (see TRIBES).
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SRC = Path(r"C:\Users\vrxby\Documents\Codex\Swarm\Design\UI_Assets_V2")
OUT = Path(__file__).resolve().parent

# strain id -> (portrait, recolour: (hue_lo, hue_hi, target_hue, sat_mul, val_mul) or None)
TRIBES = {
    "glutmaw": ("base_mawling", None),
    "sporling": ("tribe_sporling", None),
    "knochenkiefer": ("tribe_knochenkiefer", None),
    "flinkzahn": ("leaper", None),
    "aetzmaul": ("spitter", None),
    "nachtmaul": ("tribe_nachtmaul", None),
}
BOSSES = {"bog_king": "bog_king", "moosschlund": "moosschlund", "ash_toad": "ash_toad", "apex_sandworm": "portrait_apex_sandworm"}
# Head crops of the tribe portraits for the swarm icon (mawling_head_<strain>,
# finished by assets/ui/v4/build_icons_v4.py). Values in 448-px portrait
# units: (centre x, centre y, radius) of a soft circular bust mask; the head's
# own painted outline stays inside, the body is cut by the circle.
HEADS = {
    "glutmaw": (165, 148, 145),
    "sporling": (215, 175, 158),
    "knochenkiefer": (210, 185, 160),
    "flinkzahn": (185, 155, 135),
    "aetzmaul": (178, 160, 142),
    "nachtmaul": (205, 180, 158),
}
HEAD_SIZE = 512
ICONS = {
    "Attacks": ["bite", "acid_spit", "spore_burst", "sickle_slash", "slam", "swarm_wave", "leap", "brood_sac", "spikeback"],
    "Evolutions": ["hunger_mass", "razor_offense", "carapace_survival", "mutation_special"],
    "Facilities": ["brood_nest", "curse_totem"],
    "Currencies": ["dna", "biomass"],
}


def fit(image, size):
    image = image.copy()
    image.thumbnail(size, Image.LANCZOS)
    return image


def recolour(image, spec):
    lo, hi, target, sat_mul, val_mul = spec
    alpha = np.array(image)[..., 3]
    hsv = np.array(image.convert("RGB").convert("HSV")).astype(float)
    hue = hsv[..., 0] * 360.0 / 255.0
    mask = ((hue >= lo) | (hue <= hi)) if lo > hi else ((hue >= lo) & (hue <= hi))
    mask &= hsv[..., 1] > 40
    hsv[..., 0] = np.where(mask, target * 255.0 / 360.0, hsv[..., 0])
    hsv[..., 1] = np.where(mask, np.clip(hsv[..., 1] * sat_mul, 0, 255), hsv[..., 1])
    hsv[..., 2] = np.where(mask, np.clip(hsv[..., 2] * val_mul, 0, 255), hsv[..., 2])
    rgb = np.array(Image.fromarray(hsv.astype(np.uint8), "HSV").convert("RGB"))
    return Image.fromarray(np.dstack([rgb, alpha]), "RGBA")


def save(image, name, colours=0):
    path = OUT / name
    path.parent.mkdir(parents=True, exist_ok=True)
    if colours:
        image = image.quantize(colours, method=Image.FASTOCTREE, dither=Image.FLOYDSTEINBERG)
    image.save(path, optimize=True)
    print(f"{name}: {image.size[0]}x{image.size[1]}, {path.stat().st_size // 1024} KB")


def head_crop(strain):
    """Square head crop of a tribe portrait from the full-size source, masked
    by a soft circle, recoloured like the portrait, HEAD_SIZE px."""
    file, spec = TRIBES[strain]
    image = Image.open(SRC / "Portraits" / "Tribes" / f"{file}.png").convert("RGBA")
    k = max(image.size) / 448.0
    cx, cy, r = (v * k for v in HEADS[strain])
    box = tuple(int(round(v)) for v in (cx - r, cy - r, cx + r, cy + r))
    image = image.crop(box)
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).ellipse([cx - r - box[0], cy - r - box[1], cx + r - box[0], cy + r - box[1]], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(2.0))
    alpha = np.minimum(np.array(image.getchannel("A")), np.array(mask))
    image.putalpha(Image.fromarray(alpha))
    image = image.resize((HEAD_SIZE, HEAD_SIZE), Image.LANCZOS)
    if spec:
        image = recolour(image, spec)
    return image


def app_icons():
    icon = Image.open(SRC / "Brand" / "app_icon_open_maw.png").convert("RGB")
    save(fit(icon, (192, 192)), "launcher/icon_192.png")
    # Adaptive icon: the maw keyed out of its teal ground (flood fill from the
    # border over teal/dark-teal pixels; the black contour stops the fill).
    small = fit(icon, (864, 864))
    rgb = np.array(small).astype(int)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    teal = (np.maximum(g, b) > r + 6) & (r < 90)
    h, w = teal.shape
    background = np.zeros_like(teal)
    stack = [(y, x) for x in range(w) for y in (0, h - 1)] + [(y, x) for y in range(h) for x in (0, w - 1)]
    while stack:
        y, x = stack.pop()
        if background[y, x] or not teal[y, x]:
            continue
        background[y, x] = True
        if y > 0: stack.append((y - 1, x))
        if y < h - 1: stack.append((y + 1, x))
        if x > 0: stack.append((y, x - 1))
        if x < w - 1: stack.append((y, x + 1))
    alpha = Image.fromarray(np.where(background, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
    maw = small.convert("RGBA")
    maw.putalpha(alpha)
    maw = maw.crop(maw.getbbox())
    maw.thumbnail((300, 300), Image.LANCZOS)   # Android safe zone: 264 of 432 px must hold the motif
    fg = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    fg.alpha_composite(maw, ((432 - maw.width) // 2, (432 - maw.height) // 2))
    save(fg, "launcher/adaptive_foreground_432.png")
    # Background: the icon's own teal glow, the maw painted out by a large blur of the ground.
    corner = np.array(small)[: h // 8, : w // 8].reshape(-1, 3).mean(0)
    centre = np.array([8, 54, 58])
    yy, xx = np.mgrid[0:432, 0:432]
    t = np.clip(np.hypot(yy - 216, xx - 216) / 300.0, 0, 1)[..., None]
    bg = (centre * (1 - t) + corner * t).astype(np.uint8)
    save(Image.fromarray(bg, "RGB"), "launcher/adaptive_background_432.png")


def main():
    save(fit(Image.open(SRC / "Backgrounds" / "menu_background_portrait.png").convert("RGB"), (720, 1280)), "menu_background.png", 0)
    logo = Image.open(SRC / "Brand" / "mawlings_logo.png").convert("RGBA")
    save(fit(logo, (1000, 1000)), "logo.png")
    for biome, file in {"verdant_maw": "verdant_maw_card", "glutsumpf": "ashen_mire_card"}.items():
        save(fit(Image.open(SRC / "Biomes" / f"{file}.png").convert("RGB"), (480, 320)), f"biomes/{biome}.png")
    for strain, (file, spec) in TRIBES.items():
        image = fit(Image.open(SRC / "Portraits" / "Tribes" / f"{file}.png").convert("RGBA"), (448, 448))
        if spec:
            image = recolour(image, spec)
        save(image, f"tribes/{strain}.png")
    for strain in HEADS:
        save(head_crop(strain), f"heads/{strain}.png")
    for boss, file in BOSSES.items():
        save(fit(Image.open(SRC / "Portraits" / "Bosses" / f"{file}.png").convert("RGBA"), (256, 256)), f"bosses/{boss}.png")
    for folder, names in ICONS.items():
        for name in names:
            save(fit(Image.open(SRC / "Icons" / folder / f"{name}.png").convert("RGBA"), (256, 256)), f"icons/{name}.png")
    app_icons()


if __name__ == "__main__":
    main()
