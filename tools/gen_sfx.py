"""Procedural SFX generator for MAWLINGS.

Synthesises every sound from oscillators, filtered noise, envelopes and pitch
sweeps (no samples, no downloads). Output: 16-bit mono 44.1 kHz WAV files in
assets/audio/<id>_<n>.wav, peak-normalised to -3 dBFS, DC-free, with fade-in
(>= 2 ms) and fade-out so no file starts or ends with a click.

Run from the project root:
    PYTHONPATH=.tools python tools/gen_sfx.py          (Bash)
    $env:PYTHONPATH='.tools'; python tools/gen_sfx.py  (PowerShell)
Deterministic: fixed seeds, re-running produces identical files.
"""

from __future__ import annotations

import os
import sys
import wave

import numpy as np

SR = 44100
PEAK = 10 ** (-3.0 / 20.0)  # -3 dBFS
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "audio")


# --------------------------------------------------------------------------- building blocks

def t_axis(dur: float) -> np.ndarray:
    return np.arange(int(dur * SR)) / SR


def silence(dur: float) -> np.ndarray:
    return np.zeros(int(dur * SR))


def sweep(f0: float, f1: float, dur: float, curve: float = 1.0, wave_: str = "sine") -> np.ndarray:
    """Oscillator with a pitch glide f0 -> f1 (exponential-ish when curve != 1)."""
    n = int(dur * SR)
    x = np.linspace(0.0, 1.0, n, endpoint=False) ** curve
    freq = f0 * (f1 / f0) ** x
    phase = 2 * np.pi * np.cumsum(freq) / SR
    if wave_ == "tri":
        return 2 / np.pi * np.arcsin(np.sin(phase))
    return np.sin(phase)


def env_ad(n: int, attack: float, decay_pow: float = 2.0) -> np.ndarray:
    """Linear attack (seconds), then (1 - x)^pow decay to zero."""
    a = max(1, int(attack * SR))
    a = min(a, n - 1)
    e = np.empty(n)
    e[:a] = np.linspace(0.0, 1.0, a, endpoint=False)
    e[a:] = np.linspace(1.0, 0.0, n - a) ** decay_pow
    return e


def env_exp(n: int, attack: float, tau: float) -> np.ndarray:
    a = min(max(1, int(attack * SR)), n - 1)
    e = np.exp(-np.arange(n) / (tau * SR))
    e[:a] *= np.linspace(0.0, 1.0, a, endpoint=False)
    return e


def band_noise(rng: np.random.Generator, dur: float, lo: float, hi: float, n: int | None = None) -> np.ndarray:
    """White noise band-limited in the frequency domain (circular -> loopable)."""
    n = n if n is not None else int(dur * SR)
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / SR)
    # soft band edges (raised-cosine skirts of 30 %)
    mask = np.ones_like(f)
    lo_skirt = lo * 0.3
    hi_skirt = hi * 0.3
    mask[f < lo - lo_skirt] = 0
    m = (f >= lo - lo_skirt) & (f < lo)
    mask[m] = 0.5 - 0.5 * np.cos(np.pi * (f[m] - (lo - lo_skirt)) / max(lo_skirt, 1e-6))
    mask[f > hi + hi_skirt] = 0
    m = (f > hi) & (f <= hi + hi_skirt)
    mask[m] = 0.5 + 0.5 * np.cos(np.pi * (f[m] - hi) / hi_skirt)
    out = np.fft.irfft(spec * mask, n)
    return out / (np.max(np.abs(out)) + 1e-12)


def pink_noise(rng: np.random.Generator, n: int, lo: float, hi: float) -> np.ndarray:
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / SR)
    f[0] = 1.0
    mask = 1.0 / np.sqrt(f)
    mask[(f < lo) | (f > hi)] *= 0.02
    out = np.fft.irfft(spec * mask, n)
    return out / (np.max(np.abs(out)) + 1e-12)


def place(dst: np.ndarray, src: np.ndarray, at: float, gain: float = 1.0) -> None:
    i = int(at * SR)
    if i >= len(dst):
        return
    j = min(len(dst), i + len(src))
    dst[i:j] += src[: j - i] * gain


def bell(freq: float, dur: float, tau: float, partials=((1.0, 1.0), (2.76, 0.35), (5.4, 0.12), (8.93, 0.05))) -> np.ndarray:
    t = t_axis(dur)
    out = np.zeros_like(t)
    for ratio, amp in partials:
        out += amp * np.sin(2 * np.pi * freq * ratio * t) * np.exp(-t * ratio ** 0.6 / tau)
    return out * env_exp(len(t), 0.002, 10.0)


def finish(x: np.ndarray, fade_in: float = 0.003, fade_out: float = 0.012) -> np.ndarray:
    x = x - np.mean(x)
    n = len(x)
    fi = max(int(fade_in * SR), int(0.002 * SR) + 1)
    fo = max(int(fade_out * SR), int(0.004 * SR))
    x[:fi] *= np.sin(np.linspace(0, np.pi / 2, fi)) ** 2
    x[n - fo:] *= np.cos(np.linspace(0, np.pi / 2, fo)) ** 2
    x = x - np.mean(x) * np.hanning(n)  # remove residual DC without touching edges
    return x * (PEAK / (np.max(np.abs(x)) + 1e-12))


def write_wav(name: str, x: np.ndarray) -> int:
    path = os.path.join(OUT_DIR, name + ".wav")
    pcm = np.clip(np.round(x * 32767), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    return os.path.getsize(path)


# --------------------------------------------------------------------------- sounds

def s_bite(rng, v):
    # tiny wet snap: bright tooth-click + short downward "tchp" + wet smack noise
    dur = 0.13
    out = silence(dur)
    click = band_noise(rng, 0.012, 2500, 6500) * env_ad(int(0.012 * SR), 0.0005, 3)
    place(out, click, 0.0, 0.7)
    f0 = [1100, 950, 1250, 1020][v]
    snap = sweep(f0, f0 * 0.32, 0.06, 0.6) * env_ad(int(0.06 * SR), 0.002, 2.5)
    place(out, snap, 0.004, 0.8)
    wet = band_noise(rng, 0.07, 500, 1800) * env_exp(int(0.07 * SR), 0.004, 0.018)
    place(out, wet, 0.01, 0.45)
    return finish(out, 0.002, 0.01)


def s_kill(rng, v):
    # crunchy crackle (granular noise bursts) + round plop
    dur = 0.30
    out = silence(dur)
    grains = 6 + v
    for g in range(grains):
        gl = rng.uniform(0.006, 0.014)
        grain = band_noise(rng, gl, 900, 5000) * env_ad(int(gl * SR), 0.0006, 2.5)
        place(out, grain, 0.004 + g * rng.uniform(0.006, 0.011), rng.uniform(0.5, 1.0))
    body = band_noise(rng, 0.09, 200, 900) * env_exp(int(0.09 * SR), 0.002, 0.025)
    place(out, body, 0.0, 0.6)
    p0 = [210, 240, 190, 260][v]
    plop = sweep(p0, p0 * 2.6, 0.075, 0.5) * env_ad(int(0.075 * SR), 0.004, 1.8)
    place(out, plop, 0.075 + 0.01 * v, 0.9)
    return finish(out, 0.002, 0.03)


def s_grow(rng, v):
    # bright bubble blubb, rising, plus a smaller second bubble
    dur = 0.24
    out = silence(dur)
    f0 = [340, 380, 310, 420][v]
    b1 = sweep(f0, f0 * 2.4, 0.09, 0.7) * env_ad(int(0.09 * SR), 0.004, 1.6)
    place(out, b1, 0.0, 1.0)
    b2 = sweep(f0 * 1.7, f0 * 3.6, 0.06, 0.7) * env_ad(int(0.06 * SR), 0.003, 1.8)
    place(out, b2, 0.075, 0.55)
    sparkle = bell(f0 * 4.0, 0.12, 0.04, ((1.0, 1.0), (2.0, 0.2)))
    place(out, sparkle, 0.1, 0.12)
    return finish(out, 0.003, 0.03)


def s_hit(rng, v):
    # dull thud (low sine drop + muffled noise) + short swarm squeak
    dur = 0.32
    out = silence(dur)
    f0 = [120, 105, 135][v]
    thud = sweep(f0, f0 * 0.42, 0.16, 0.6) * env_exp(int(0.16 * SR), 0.003, 0.05)
    place(out, thud, 0.0, 1.0)
    muff = band_noise(rng, 0.08, 80, 700) * env_exp(int(0.08 * SR), 0.002, 0.02)
    place(out, muff, 0.0, 0.55)
    sq0 = [1500, 1700, 1350][v]
    t = t_axis(0.09)
    vib = 1 + 0.04 * np.sin(2 * np.pi * 38 * t)
    sq = np.sin(2 * np.pi * np.cumsum(sq0 * vib * (1 + 0.35 * t / 0.09)) / SR)
    sq = (sq + 0.25 * np.sin(2 * np.pi * np.cumsum(2 * sq0 * vib) / SR)) * env_ad(len(t), 0.008, 1.5)
    place(out, sq, 0.03, 0.28)
    return finish(out, 0.002, 0.04)


def s_warn(rng, v):
    # short low hum with gentle tremolo and soft attack (not shrill)
    dur = 0.38
    f = [98, 110, 104][v]
    t = t_axis(dur)
    trem = 0.8 + 0.2 * np.sin(2 * np.pi * 11 * t)
    tone = (np.sin(2 * np.pi * f * t) + 0.45 * np.sin(2 * np.pi * 2 * f * t + 0.3)
            + 0.18 * np.sin(2 * np.pi * 3 * f * t) + 0.3 * np.sin(2 * np.pi * f * 1.006 * t))
    e = np.minimum(1.0, t / 0.03) * np.minimum(1.0, (dur - t) / 0.12)
    return finish(tone * trem * e, 0.02, 0.05)


def s_stomp(rng, v):
    # deep boom: sub sine drop, mid body, rumble tail, soft attack thump
    dur = 0.75
    out = silence(dur)
    f0 = [72, 64, 80][v]
    sub = sweep(f0, f0 * 0.45, 0.6, 0.5) * env_exp(int(0.6 * SR), 0.004, 0.18)
    place(out, sub, 0.0, 1.0)
    body = sweep(f0 * 2.2, f0 * 0.9, 0.18, 0.5) * env_exp(int(0.18 * SR), 0.002, 0.05)
    place(out, body, 0.0, 0.5)
    rumble = band_noise(rng, 0.7, 30, 260) * env_exp(int(0.7 * SR), 0.01, 0.2)
    place(out, rumble, 0.005, 0.55)
    thump = band_noise(rng, 0.03, 200, 1400) * env_ad(int(0.03 * SR), 0.001, 3)
    place(out, thump, 0.0, 0.3)
    return finish(out, 0.002, 0.08)


PENTA = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24]


def s_mutate(rng, v):
    # magical rising glitter: fast pentatonic bell arpeggio + airy shimmer
    dur = 0.7
    out = silence(dur)
    root = [660, 740, 587][v]
    steps = [0, 2, 4, 5, 7] if v != 1 else [0, 1, 3, 5, 7]
    for i, s in enumerate(steps):
        f = root * 2 ** (PENTA[s] / 12)
        place(out, bell(f, 0.4, 0.12), 0.055 * i, 0.55 + 0.08 * i)
    shimmer = band_noise(rng, 0.55, 5000, 11000)
    shimmer *= env_ad(len(shimmer), 0.2, 2.0) * (0.6 + 0.4 * np.sin(2 * np.pi * 23 * t_axis(0.55)))
    place(out, shimmer, 0.02, 0.12)
    return finish(out, 0.003, 0.1)


def s_evolve(rng, v):
    # larger: rising sweep swell + major chord arpeggio + sustained chord shimmer
    dur = 1.3
    out = silence(dur)
    root = [392, 440][v]
    swell = sweep(root * 0.5, root * 2, 0.45, 1.3, "tri") * env_ad(int(0.45 * SR), 0.35, 1.2)
    place(out, swell, 0.0, 0.35)
    chord = [0, 4, 7, 12, 16, 19, 24]
    for i, s in enumerate(chord):
        f = root * 2 ** (s / 12)
        place(out, bell(f, 0.9, 0.3), 0.25 + 0.05 * i, 0.4 + 0.05 * i)
    t = t_axis(0.9)
    pad = sum(np.sin(2 * np.pi * root * 2 ** (s / 12) * t) for s in (12, 16, 19)) / 3
    pad *= env_ad(len(t), 0.15, 1.5)
    place(out, pad, 0.35, 0.35)
    shimmer = band_noise(rng, 1.0, 5500, 12000) * env_ad(int(1.0 * SR), 0.3, 2.0)
    place(out, shimmer, 0.2, 0.1)
    return finish(out, 0.004, 0.2)


def s_extinct(rng, v):
    # sad descending minor phrase, soft triangle voice with slight vibrato, fading
    dur = 1.5
    out = silence(dur)
    root = [440, 415][v]
    notes = [0, -2, -5, -9] if v == 0 else [0, -3, -5, -8]
    for i, s in enumerate(notes):
        f = root * 2 ** (s / 12)
        ln = 0.55 if i < 3 else 0.8
        t = t_axis(ln)
        vib = 1 + 0.006 * np.sin(2 * np.pi * 5 * t) * np.minimum(1, t / 0.2)
        ph = 2 * np.pi * np.cumsum(f * vib * (1 - 0.03 * (t / ln))) / SR
        tone = 2 / np.pi * np.arcsin(np.sin(ph)) + 0.25 * np.sin(ph * 0.5)
        tone *= env_ad(len(t), 0.03, 1.6)
        place(out, tone, 0.26 * i, 0.9 - 0.12 * i)
    return finish(out, 0.01, 0.25)


def s_pickup(rng, v):
    # little bell / ding-ding
    dur = 0.45
    out = silence(dur)
    a, b = [(1318.5, 1760.0), (1568.0, 2093.0), (1174.7, 1568.0)][v]
    place(out, bell(a, 0.3, 0.09), 0.0, 0.6)
    place(out, bell(b, 0.4, 0.12), 0.06, 0.8)
    return finish(out, 0.002, 0.06)


def s_ui(rng, v):
    # soft click: short rounded tick + tiny tone body
    dur = 0.05
    out = silence(dur)
    f = [1250, 1100, 1400][v]
    tone = np.sin(2 * np.pi * f * t_axis(0.03)) * env_exp(int(0.03 * SR), 0.002, 0.007)
    place(out, tone, 0.0, 1.0)
    tick = band_noise(rng, 0.01, 1500, 4000) * env_ad(int(0.01 * SR), 0.001, 3)
    place(out, tick, 0.0, 0.35)
    return finish(out, 0.002, 0.012)


def s_ambience(rng, v):
    # 10 s seamless loop: wind + leaf rustle + sparse insects.
    # Noise is FFT-filtered (circular) and every modulation completes whole cycles,
    # so sample N-1 flows into sample 0 without a jump.
    dur = 10.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    wind = pink_noise(rng, n, 60, 1200)
    wind_mod = 0.55 + 0.25 * np.sin(2 * np.pi * 0.2 * t) + 0.2 * np.sin(2 * np.pi * 0.5 * t + 1.1)
    leaves = band_noise(rng, dur, 2500, 8000, n)
    gust = np.clip(np.sin(2 * np.pi * 0.3 * t + 0.4), 0, 1) ** 3 + 0.15
    out = 0.6 * wind * wind_mod + 0.14 * leaves * gust
    # insects: sparse chirp trains, kept away from the loop seam
    for _ in range(7):
        start = rng.uniform(0.3, dur - 1.3)
        f = rng.uniform(3800, 6200)
        pulses = int(rng.integers(3, 9))
        rate = rng.uniform(0.045, 0.08)
        for p in range(pulses):
            pl = 0.022
            chirp = np.sin(2 * np.pi * f * t_axis(pl) * (1 + 0.05 * t_axis(pl) / pl)) * np.hanning(int(pl * SR))
            place(out, chirp, start + p * rate, rng.uniform(0.04, 0.08))
    # frog-ish low croaks, very rare
    for _ in range(2):
        start = rng.uniform(0.5, dur - 1.0)
        croak = sweep(210, 160, 0.14) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 30 * t_axis(0.14)))) * np.hanning(int(0.14 * SR))
        place(out, croak, start, 0.05)
    out -= np.mean(out)
    return out * (PEAK / np.max(np.abs(out)))  # no fades: must loop seamlessly


SOUNDS = {
    "bite": (s_bite, 4),
    "kill": (s_kill, 4),
    "grow": (s_grow, 4),
    "hit": (s_hit, 3),
    "warn": (s_warn, 3),
    "stomp": (s_stomp, 3),
    "mutate": (s_mutate, 3),
    "evolve": (s_evolve, 2),
    "extinct": (s_extinct, 2),
    "pickup": (s_pickup, 3),
    "ui": (s_ui, 3),
    "ambience_jungle": (s_ambience, 1),
}


def analyse(name: str, x: np.ndarray, loop: bool) -> str:
    peak_db = 20 * np.log10(np.max(np.abs(x)) + 1e-12)
    dc = float(np.mean(x))
    first = abs(x[0]) if not loop else abs(x[-1] - x[0])
    last = abs(x[-1])
    ok = peak_db <= -2.9 and abs(dc) < 1e-3 and first < 0.01 and (loop or last < 0.01)
    return f"{name:22s} {len(x) / SR:5.2f}s peak {peak_db:6.2f} dBFS dc {dc:+.5f} edge {first:.4f}/{last:.4f} {'OK' if ok else 'CHECK'}"


def main() -> int:
    os.makedirs(OUT_DIR, exist_ok=True)
    total = 0
    bad = 0
    for sid, (fn, count) in SOUNDS.items():
        for v in range(count):
            rng = np.random.default_rng(1000 + 97 * v + sum(map(ord, sid)))
            x = fn(rng, v)
            name = f"{sid}_{v + 1}"
            total += write_wav(name, x)
            line = analyse(name, x, sid.startswith("ambience"))
            bad += line.endswith("CHECK")
            print(line)
    print(f"total bytes: {total} ({total / 1024:.1f} KiB)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
