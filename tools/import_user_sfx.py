"""Imports the user's recorded sound effects into MAWLINGS.

Sources (read only, never modified):
    C:\\Users\\vrxby\\Documents\\Codex\\Swarm\\Design\\Sounds\\*.wav
    (stock sounds; override with the environment variable MAWLINGS_SFX_SOURCE)
    C:\\Users\\vrxby\\Documents\\Codex\\Swarm\\Design\\Audio\\{SFX,Music}\\*.wav
    (audio pack V1, synthesised by the user, licence free; recipes with
    "dir": "v1"; override with MAWLINGS_V1_SOURCE)

Pack V1 music loops (MUSIC_RECIPES) become assets/music/v1_*.wav: stereo ->
mono, 32 -> 22.05 kHz, DC removal, -3 dBFS peak, cut to whole bars and a RIFF
'smpl' loop chunk over the whole file (the V1 loops already start and end on
zero samples, so no fades are added). scripts/music.gd plays them as style "v1".

Every recipe below cuts one segment out of a source file and processes it
reproducibly: stereo -> mono, optional filters / soft saturation (makes bass
audible on phone speakers), band-limited resampling to 44.1 or 22.05 kHz, pitch
variants (FFT resampling, duration changes with the pitch), click-free
fade-in/out (or a crossfaded seamless loop), DC removal and peak normalisation
to -3 dBFS. Output: assets/audio/<id>_<n>.wav, 16-bit mono. Surplus variants of
an id (e.g. an older procedural <id>_4.wav) are removed so Sfx loads exactly
the imported set. Relative loudness is set in scripts/sfx.gd RULES (db); the
`--report` table prints a phone-weighted loudness to align those values.

tools/gen_sfx.py skips every id listed in RECIPES while its source file exists,
so the procedural sounds stay available as a fallback without overwriting these.

Run from the project root:
    PYTHONPATH=.tools python tools/import_user_sfx.py [--report]      (Bash)
    $env:PYTHONPATH='.tools'; python tools/import_user_sfx.py          (PowerShell)
Licences of the sources: assets/audio/LICENSES.md.
"""

from __future__ import annotations

import os
import struct
import sys
import wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "audio")
SOURCE_DIR = os.environ.get("MAWLINGS_SFX_SOURCE", r"C:\Users\vrxby\Documents\Codex\Swarm\Design\Sounds")
V1_DIR = os.environ.get("MAWLINGS_V1_SOURCE", r"C:\Users\vrxby\Documents\Codex\Swarm\Design\Audio")
MUSIC_OUT_DIR = os.path.join(ROOT, "assets", "music")
PEAK = 10 ** (-3.0 / 20.0)  # -3 dBFS
MAX_VARIANTS = 8  # scripts/sfx.gd MAX_VARIANTS

ROAR = "mixkit-aggressive-beast-roar-13.wav"
ALIEN_HUM = "mixkit-alien-technology-hum-2134.wav"
LEVEL = "mixkit-completion-of-a-level-2063.wav"
ORCHESTRA = "mixkit-epic-orchestra-transition-2290.wav"
BLOOD_POP = "mixkit-game-blood-pop-slide-2363.wav"
CRATE = "mixkit-mechanical-crate-pick-up-3154.wav"
BASS_PULSE = "mixkit-mystwrious-bass-pulse-2298.wav"
DRUMS = "mixkit-ominous-drums-227.wav"
NOTIFY = "mixkit-sci-fi-positive-notification-266.wav"
SWORD = "mixkit-sword-magic-drag-3009.wav"
TECH_HUM = "mixkit-technological-futuristic-hum-2133.wav"
FANFARE = "mixkit-trumpet-fanfare-2293.wav"
RECHARGE = "mixkit-video-game-health-recharge-2837.wav"
MERGE = "merge-3-mobile-game-short-7ir6tzte.wav"
SLING = "sling-streching-sfx-for-m-vpiblugt.wav"
SLIME = "soft-quick-sound-of-slime-sk5tldnt.wav"
# Audio pack V1 (relative to V1_DIR).
V1_BITE = ["SFX/bite_01.wav", "SFX/bite_02.wav", "SFX/bite_03.wav"]
V1_RUSTLE = ["SFX/swarm_rustle_01.wav", "SFX/swarm_rustle_02.wav"]
V1_FEED = "SFX/swarm_feeding_cluster.wav"
V1_LOSS = "SFX/population_loss.wav"
V1_HARVEST = "SFX/corpse_harvest.wav"
V1_DNA = "SFX/dna_gain.wav"
V1_THREAT = "SFX/threat_rise.wav"
V1_TELEGRAPH = "SFX/enemy_telegraph.wav"
V1_RUN_END = "SFX/run_end.wav"
V1_RALLY = "SFX/rally.wav"
V1_UI_TAP = "SFX/ui_tap.wav"

# id -> recipe. start/end in seconds of the source; variants = list of
# (pitch, start_offset, end_offset); sr = output rate; fi/fo = fades (s);
# hp/lp = high/low pass (Hz); shelf = (Hz, dB) high-shelf; sat = tanh drive;
# loop = crossfade length (s) for a seamless loop instead of fades.
# dir = "v1" reads from V1_DIR; src may be a list (files crossfaded one after the
# other); a variant may carry a 4th element with its own src.
RECIPES: dict[str, dict] = {
    # --- replacements of procedural ids (same id, call sites unchanged)
    "kill": {"src": BLOOD_POP, "start": 0.0, "end": 0.36, "sr": 44100, "hp": 90, "fo": 0.05,
             "variants": [(1.0, 0, 0), (1.08, 0, 0), (0.93, 0, 0), (1.15, 0, -0.06)]},
    "death": {"src": BLOOD_POP, "start": 0.0, "end": 0.36, "sr": 22050, "hp": 70, "lp": 2600, "fo": 0.07,
              "variants": [(0.74, 0, 0), (0.8, 0, 0), (0.69, 0, -0.04)]},
    "split": {"src": SLIME, "start": 0.025, "end": 0.2, "sr": 44100, "hp": 120, "fo": 0.03,
              "variants": [(1.0, 0, 0), (1.08, 0, 0), (0.93, 0, 0), (1.17, 0, 0)]},
    "grow": {"src": MERGE, "start": 0.0, "end": 0.55, "sr": 44100, "hp": 100, "fo": 0.2,
             "variants": [(1.0, 0, 0), (1.0595, 0, 0), (0.944, 0, 0)]},
    "milestone": {"src": LEVEL, "start": 0.0, "end": 2.05, "sr": 22050, "hp": 110, "fo": 0.35,
                  "variants": [(1.0, 0, 0), (1.1225, 0, 0)]},
    "mutate": {"src": NOTIFY, "start": 0.2, "end": 0.58, "sr": 44100, "hp": 200, "shelf": (7000, -5.0), "fo": 0.06,
               "variants": [(1.0, 0, 0), (0.95, 0, 0), (1.05, 0, 0)]},
    "evolve": {"src": SWORD, "start": 0.08, "end": 1.45, "sr": 44100, "hp": 50, "fo": 0.3,
               "variants": [(1.0, 0, 0), (0.94, 0, 0)]},
    # --- new ids (need call sites, see the stage report)
    "boss_roar": {"src": ROAR, "start": 0.07, "end": 1.25, "sr": 22050, "hp": 35, "fo": 0.2,
                  "variants": [(1.0, 0, 0), (0.86, 0, 0)]},
    "flood_warn": {"src": DRUMS, "start": 0.08, "end": 3.25, "sr": 22050, "hp": 40, "sat": 1.6, "fo": 0.9,
                   "variants": [(1.0, 0, 0), (0.94, 0, 0)]},
    "quake": {"src": BASS_PULSE, "start": 0.0, "end": 2.3, "sr": 22050, "hp": 30, "sat": 3.0, "fi": 0.08, "fo": 0.45,
              "variants": [(1.0, 0, 0), (1.0, 4.0, 4.0)]},
    "regen": {"src": RECHARGE, "start": 0.0, "end": 0.9, "sr": 44100, "hp": 250, "shelf": (8000, -3.0), "fo": 0.2,
              "variants": [(1.0, 0, 0), (1.06, 0, 0)]},
    "alpha_core": {"src": CRATE, "start": 0.05, "end": 0.38, "sr": 44100, "hp": 70, "fo": 0.06,
                   "variants": [(1.0, 0, 0), (1.07, 0, 0)]},
    "fanfare": {"src": FANFARE, "start": 0.0, "end": 2.45, "sr": 22050, "hp": 80, "fo": 0.55,
                "variants": [(1.0, 0, 0)]},
    "migration_whoosh": {"src": ORCHESTRA, "start": 0.03, "end": 2.5, "sr": 22050, "hp": 35, "fo": 1.0,
                         "variants": [(1.0, 0, 0)]},
    "leaper_windup": {"src": SLING, "start": 0.55, "end": 1.65, "sr": 22050, "hp": 60, "fi": 0.02, "fo": 0.12,
                      "variants": [(1.0, 0, 0), (1.1, 0, -0.08)]},
    "portal_open": {"src": ALIEN_HUM, "start": 0.45, "end": 2.1, "sr": 44100, "hp": 150, "shelf": (9000, -4.0), "fo": 0.4,
                    "variants": [(1.0, 0, 0), (0.9, 0, 0)]},
    # seamless loop (sfx.gd LOOP_RULES)
    "portal_hum": {"src": TECH_HUM, "start": 0.4, "end": 3.0, "sr": 22050, "hp": 30, "sat": 2.5, "loop": 0.35,
                   "variants": [(1.0, 0, 0)]},
    # --- audio pack V1: replacements of procedural ids (call sites unchanged)
    "bite": {"dir": "v1", "src": V1_BITE[0], "start": 0.0, "end": 0.2, "sr": 32000, "hp": 90, "fo": 0.05,
             "variants": [(1.0, 0, 0, V1_BITE[0]), (1.0, 0, 0, V1_BITE[1]), (1.0, 0, 0, V1_BITE[2]), (1.1, 0, 0, V1_BITE[1])]},
    "warn": {"dir": "v1", "src": V1_TELEGRAPH, "start": 0.0, "end": 0.9, "sr": 22050, "hp": 45, "sat": 1.5, "fo": 0.12,
             "variants": [(1.0, 0, 0), (0.94, 0, 0), (1.06, 0, 0)]},
    "ui": {"dir": "v1", "src": V1_UI_TAP, "start": 0.0, "end": 0.12, "sr": 32000, "hp": 150, "fo": 0.03,
           "variants": [(1.0, 0, 0), (1.04, 0, 0), (0.96, 0, 0)]},
    "extinct": {"dir": "v1", "src": V1_RUN_END, "start": 0.0, "end": 1.65, "sr": 22050, "hp": 45, "fo": 0.3,
                "variants": [(1.0, 0, 0), (0.95, 0, 0)]},
    # --- audio pack V1: new ids (need call sites, see the stage report)
    "rally": {"dir": "v1", "src": V1_RALLY, "start": 0.0, "end": 0.6, "sr": 22050, "hp": 60, "fo": 0.1,
              "variants": [(1.0, 0, 0), (1.05, 0, 0)]},
    "harvest": {"dir": "v1", "src": V1_HARVEST, "start": 0.0, "end": 0.8, "sr": 22050, "hp": 60, "sat": 1.2, "fo": 0.12,
                "variants": [(1.0, 0, 0), (0.93, 0, 0), (1.07, 0, 0)]},
    "dna": {"dir": "v1", "src": V1_DNA, "start": 0.0, "end": 0.84, "sr": 22050, "hp": 200, "fo": 0.15,
            "variants": [(1.0, 0, 0), (1.0595, 0, 0)]},
    "threat": {"dir": "v1", "src": V1_THREAT, "start": 0.0, "end": 1.5, "sr": 22050, "hp": 35, "sat": 2.2, "fo": 0.3,
               "variants": [(1.0, 0, 0), (1.0595, 0, 0)]},
    "loss": {"dir": "v1", "src": V1_LOSS, "start": 0.0, "end": 0.75, "sr": 22050, "hp": 40, "sat": 2.2, "fo": 0.15,
             "variants": [(1.0, 0, 0), (0.92, 0, 0)]},
    # seamless loops (sfx.gd LOOP_RULES)
    "feed": {"dir": "v1", "src": V1_FEED, "start": 0.0, "end": 2.1, "sr": 22050, "hp": 90, "loop": 0.4,
             "variants": [(1.0, 0, 0)]},
    "rustle": {"dir": "v1", "src": V1_RUSTLE, "start": 0.0, "end": 1.9, "sr": 22050, "hp": 120, "loop": 0.25,
               "variants": [(1.0, 0, 0)]},
}

# Pack V1 music loops -> assets/music/<id>.wav (scripts/music.gd style "v1").
MUSIC_RECIPES: dict[str, dict] = {
    "v1_arena": {"src": "Music/mawlings_arena_loop_96bpm.wav", "sr": 22050, "bpm": 96, "bars": 16},
    "v1_boss": {"src": "Music/mawlings_boss_loop_128bpm.wav", "sr": 22050, "bpm": 128, "bars": 16},
}
V1_JOIN_XFADE = 0.12  # s, crossfade between the files of a list src


# --------------------------------------------------------------------------- io

def read_wav(path: str) -> tuple[np.ndarray, int]:
    with wave.open(path, "rb") as w:
        ch, sw, sr, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    if sw == 1:
        x = (np.frombuffer(raw, np.uint8).astype(np.float64) - 128.0) / 128.0
    elif sw == 2:
        x = np.frombuffer(raw, "<i2").astype(np.float64) / 32768.0
    elif sw == 3:
        b = np.frombuffer(raw, np.uint8).reshape(-1, 3).astype(np.int32)
        x = (((b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16)) << 8) >> 8) / 8388608.0
    elif sw == 4:
        x = np.frombuffer(raw, "<i4").astype(np.float64) / 2147483648.0
    else:
        raise ValueError(f"unsupported sample width {sw} in {path}")
    return x.reshape(-1, ch).mean(axis=1), sr


def write_wav(path: str, x: np.ndarray, sr: int, loop_chunk: bool = False) -> int:
    pcm = np.clip(np.round(x * 32767), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())
    if loop_chunk:
        # RIFF 'smpl' chunk: one forward loop over the whole file (as tools/gen_music.py).
        smpl = struct.pack("<9I", 0, 0, int(round(1e9 / sr)), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, len(pcm) - 1, 0, 0)
        with open(path, "r+b") as f:
            f.seek(0, 2)
            f.write(b"smpl" + struct.pack("<I", len(smpl)) + smpl)
            size = f.tell()
            f.seek(4)
            f.write(struct.pack("<I", size - 8))
    return os.path.getsize(path)


# --------------------------------------------------------------------------- dsp

def fft_filter(x: np.ndarray, sr: int, hp: float = 0.0, lp: float = 0.0, shelf: tuple | None = None) -> np.ndarray:
    """Zero-phase filtering in the frequency domain (clip is padded, so no wrap-around)."""
    pad = min(len(x), sr // 4)
    y = np.concatenate([x, np.zeros(pad)])
    spec = np.fft.rfft(y)
    f = np.fft.rfftfreq(len(y), 1.0 / sr)
    gain = np.ones_like(f)
    if hp > 0:
        gain *= 1.0 / np.sqrt(1.0 + (hp / np.maximum(f, 1e-3)) ** 4)  # 2nd-order-like
    if lp > 0:
        gain *= 1.0 / np.sqrt(1.0 + (f / lp) ** 4)
    if shelf is not None:
        fc, db = shelf
        g = 10 ** (db / 20.0)
        gain *= 1.0 + (g - 1.0) / (1.0 + (fc / np.maximum(f, 1e-3)) ** 2)
    return np.fft.irfft(spec * gain, len(y))[: len(x)]


def fft_resample(x: np.ndarray, new_len: int) -> np.ndarray:
    """Band-limited resampling to new_len samples (truncates/zero-pads the spectrum)."""
    if new_len == len(x):
        return x.copy()
    spec = np.fft.rfft(x)
    bins = new_len // 2 + 1
    out = np.zeros(bins, dtype=complex)
    k = min(bins, len(spec))
    out[:k] = spec[:k]
    return np.fft.irfft(out, new_len) * (new_len / len(x))


def fade(x: np.ndarray, sr: int, fi: float, fo: float) -> np.ndarray:
    n = len(x)
    a = min(n // 2, max(int(fi * sr), int(0.002 * sr) + 1))
    b = min(n // 2, max(int(fo * sr), int(0.004 * sr)))
    x = x.copy()
    x[:a] *= np.sin(np.linspace(0.0, np.pi / 2, a)) ** 2
    x[n - b:] *= np.cos(np.linspace(0.0, np.pi / 2, b)) ** 2
    return x


def make_loop(seg: np.ndarray, sr: int, xfade: float) -> np.ndarray:
    """seg covers loop length + xfade; the tail is crossfaded into the head."""
    xn = int(xfade * sr)
    body = seg[: len(seg) - xn].copy()
    t = np.linspace(0.0, np.pi / 2, xn)
    body[:xn] = seg[:xn] * np.sin(t) + seg[len(seg) - xn:] * np.cos(t)
    return body


def source_path(recipe: dict, src: str) -> str:
    return os.path.join(V1_DIR if recipe.get("dir") == "v1" else SOURCE_DIR, src)


def load_source(recipe: dict, src, cache: dict) -> tuple[np.ndarray, int]:
    """One file, or a list of files joined with a short equal-power crossfade."""
    key = (recipe.get("dir", ""), tuple(src) if isinstance(src, list) else src)
    if key not in cache:
        if isinstance(src, list):
            parts = [read_wav(source_path(recipe, name)) for name in src]
            sr = parts[0][1]
            xn = int(V1_JOIN_XFADE * sr)
            t = np.linspace(0.0, np.pi / 2, xn)
            x = parts[0][0].copy()
            for part, part_sr in parts[1:]:
                assert part_sr == sr, "joined sources need one sample rate"
                seam = x[len(x) - xn:] * np.cos(t) + part[:xn] * np.sin(t)
                x = np.concatenate([x[: len(x) - xn], seam, part[xn:]])
            cache[key] = (x, sr)
        else:
            cache[key] = read_wav(source_path(recipe, src))
    return cache[key]


def process(sid: str, recipe: dict, cache: dict) -> list[tuple[np.ndarray, int]]:
    out = []
    for variant in recipe["variants"]:
        pitch, d_start, d_end = variant[:3]
        x, sr_in = load_source(recipe, variant[3] if len(variant) > 3 else recipe["src"], cache)
        a = int((recipe["start"] + d_start) * sr_in)
        b = int((recipe["end"] + d_end) * sr_in)
        loop = recipe.get("loop", 0.0)
        if loop:
            b += int(loop * sr_in)
        seg = x[a:b].astype(np.float64)
        seg = seg - np.mean(seg)
        seg = fft_filter(seg, sr_in, recipe.get("hp", 0.0), recipe.get("lp", 0.0), recipe.get("shelf"))
        drive = recipe.get("sat", 0.0)
        if drive:
            seg = seg / (np.max(np.abs(seg)) + 1e-12)
            seg = np.tanh(drive * seg) / np.tanh(drive)
        sr = recipe["sr"]
        # Pitch p at output rate sr: play the source faster by p -> fewer samples.
        new_len = int(round(len(seg) * sr / sr_in / pitch))
        y = fft_resample(seg, new_len)
        if loop:
            y = make_loop(y, sr, loop)
            y = y - np.mean(y)
        else:
            y = fade(y - np.mean(y), sr, recipe.get("fi", 0.003), recipe.get("fo", 0.02))
            y = y - np.mean(y) * np.hanning(len(y))
        y = y * (PEAK / (np.max(np.abs(y)) + 1e-12))
        out.append((y, sr))
    return out


# --------------------------------------------------------------------------- analysis

def phone_loudness(x: np.ndarray, sr: int) -> float:
    """Loudest 400 ms window, weighted like a phone speaker (little below 250 Hz)."""
    y = fft_filter(x, sr, hp=250.0, shelf=(2000, 3.0))
    win = min(len(y), int(0.4 * sr))
    acc = np.concatenate([[0.0], np.cumsum(y * y)])
    power = (acc[win:] - acc[:-win]) / win  # moving average in O(n), also for music
    return 10 * np.log10(np.max(power) + 1e-12)


def check(name: str, x: np.ndarray, sr: int, loop: bool) -> tuple[bool, str]:
    peak_db = 20 * np.log10(np.max(np.abs(x)) + 1e-12)
    dc = float(np.mean(x))
    first = abs(x[-1] - x[0]) if loop else abs(x[0])
    last = abs(x[-1]) if not loop else 0.0
    # A loop seam is fine when its jump is no bigger than a typical step of the
    # material itself (noisy loops like "feed" have large sample-to-sample steps).
    seam_limit = max(0.02, float(np.percentile(np.abs(np.diff(x)), 99.5))) if loop else 0.02
    ok = peak_db <= -2.9 and abs(dc) < 2e-3 and first < seam_limit and last < 0.01
    return ok, (f"{name:20s} {len(x) / sr:5.2f}s {sr // 1000:2d}k peak {peak_db:6.2f} dBFS "
                f"loud {phone_loudness(x, sr):6.1f} edge {first:.4f}/{last:.4f} {'OK' if ok else 'CHECK'}")


def remove_surplus(sid: str, keep: int) -> None:
    for n in range(keep + 1, MAX_VARIANTS + 1):
        for suffix in (".wav", ".wav.import"):
            path = os.path.join(OUT_DIR, f"{sid}_{n}{suffix}")
            if os.path.exists(path):
                os.remove(path)
                print(f"  removed surplus {os.path.basename(path)}")


def recipe_sources(recipe: dict) -> list[str]:
    names = list(recipe["src"]) if isinstance(recipe["src"], list) else [recipe["src"]]
    names += [variant[3] for variant in recipe["variants"] if len(variant) > 3]
    return [source_path(recipe, name) for name in names]


def source_available(sid: str) -> bool:
    recipe = RECIPES.get(sid)
    return recipe is not None and all(os.path.isfile(path) for path in recipe_sources(recipe))


def import_music() -> tuple[int, int]:
    """Pack V1 music loops -> assets/music/<id>.wav with a loop chunk. Returns (bytes, bad)."""
    total = 0
    bad = 0
    for mid, recipe in MUSIC_RECIPES.items():
        path = os.path.join(V1_DIR, recipe["src"])
        if not os.path.isfile(path):
            print(f"{mid:20s} source {recipe['src']} missing - kept existing file")
            continue
        x, sr_in = read_wav(path)  # channels averaged -> mono
        sr = recipe["sr"]
        frames = int(round(recipe["bars"] * 4 * 60.0 / recipe["bpm"] * sr))  # whole bars
        y = fft_resample(x - np.mean(x), int(round(len(x) * sr / sr_in)))[:frames]
        y = y - np.mean(y)
        y = y * (PEAK / (np.max(np.abs(y)) + 1e-12))
        total += write_wav(os.path.join(MUSIC_OUT_DIR, mid + ".wav"), y, sr, loop_chunk=True)
        ok, line = check(mid, y, sr, True)
        bad += not ok
        print(f"{line} ({recipe['bpm']} BPM, {recipe['bars']} bars)")
    return total, bad


def main() -> int:
    if not os.path.isdir(SOURCE_DIR):
        print(f"source folder missing: {SOURCE_DIR} (existing files are kept)")
        return 1
    os.makedirs(OUT_DIR, exist_ok=True)
    cache: dict = {}
    total = 0
    bad = 0
    for sid, recipe in RECIPES.items():
        if not source_available(sid):
            print(f"{sid:20s} source {recipe['src']} missing - kept existing files")
            continue
        variants = process(sid, recipe, cache)
        for i, (y, sr) in enumerate(variants):
            name = f"{sid}_{i + 1}"
            total += write_wav(os.path.join(OUT_DIR, name + ".wav"), y, sr)
            ok, line = check(name, y, sr, bool(recipe.get("loop")))
            bad += not ok
            print(line)
        remove_surplus(sid, len(variants))
    music_bytes, music_bad = import_music()
    bad += music_bad
    print(f"total bytes: sfx {total} ({total / 1024:.1f} KiB), music {music_bytes} ({music_bytes / 1024:.1f} KiB)")
    if "--report" in sys.argv:
        # Phone-weighted loudness of every file in assets/audio (procedural ones too).
        print("\nloudness report (loudest 400 ms, phone weighting):")
        for fname in sorted(os.listdir(OUT_DIR)):
            if fname.endswith(".wav"):
                x, sr = read_wav(os.path.join(OUT_DIR, fname))
                print(f"  {fname:26s} {phone_loudness(x, sr):6.1f}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
