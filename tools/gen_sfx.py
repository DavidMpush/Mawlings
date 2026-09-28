"""Procedural SFX generator for MAWLINGS.

Synthesises every sound from oscillators, filtered noise, envelopes and pitch
sweeps (no samples, no downloads). Output: 16-bit mono 44.1 kHz WAV files in
assets/audio/<id>_<n>.wav, peak-normalised to -3 dBFS, DC-free, with fade-in
(>= 2 ms) and fade-out so no file starts or ends with a click.

Run from the project root:
    PYTHONPATH=.tools python tools/gen_sfx.py          (Bash)
    $env:PYTHONPATH='.tools'; python tools/gen_sfx.py  (PowerShell)
Deterministic: fixed seeds, re-running produces identical files.

Ids with a recorded user sound (tools/import_user_sfx.py RECIPES, source file
present) are skipped so the imported files are never overwritten; the synths
below stay as fallback. `--force` regenerates them anyway (then re-run the
importer to restore the user sounds).
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


# --------------------------------------------------------------------------- Etappe 09

def s_split(rng, v):
    # soft organic cell division: a wet stretch (rising, wobbling squelch) that
    # snaps into a round "plopp", then a tiny bubble as the new cell settles
    dur = 0.34
    out = silence(dur)
    base = [170, 195, 150, 215][v]
    t = t_axis(0.15)
    wob = 1 + 0.08 * np.sin(2 * np.pi * (26 + 4 * v) * t)
    freq = base * (1 + 0.9 * (t / 0.15) ** 1.6) * wob
    stretch = 2 / np.pi * np.arcsin(np.sin(2 * np.pi * np.cumsum(freq) / SR))
    stretch *= np.minimum(1.0, t / 0.1) ** 1.5 * (1 - np.clip((t - 0.13) / 0.02, 0, 1))
    place(out, stretch, 0.0, 0.35)
    squelch = band_noise(rng, 0.15, 350, 1400) * np.minimum(1.0, t_axis(0.15) / 0.12) ** 2
    squelch *= 1 - np.clip((t_axis(0.15) - 0.13) / 0.02, 0, 1)
    place(out, squelch, 0.0, 0.22)
    p0 = [260, 300, 240, 330][v]
    plop = sweep(p0, p0 * 3.0, 0.06, 0.55) * env_ad(int(0.06 * SR), 0.003, 1.8)
    place(out, plop, 0.14, 1.0)
    body = sweep(p0 * 0.5, p0 * 0.8, 0.09, 1.0) * env_exp(int(0.09 * SR), 0.002, 0.03)
    place(out, body, 0.14, 0.45)
    bub = sweep(p0 * 2.1, p0 * 4.2, 0.035, 0.7) * env_ad(int(0.035 * SR), 0.002, 2.0)
    place(out, bub, 0.22 + 0.01 * v, 0.35)
    return finish(out, 0.004, 0.03)


def s_milestone(rng, v):
    # short triumphant rise: quick major arpeggio in a warm horn-ish voice,
    # topped by a bell chord and a little sparkle
    dur = 1.0
    out = silence(dur)
    root = [392.0, 440.0][v]
    steps = [0, 4, 7, 12]
    for i, st in enumerate(steps):
        f = root * 2 ** (st / 12)
        ln = 0.16 if i < 3 else 0.6
        t = t_axis(ln)
        ph = 2 * np.pi * f * t
        horn = np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.28 * np.sin(3 * ph) + 0.12 * np.sin(4 * ph)
        horn *= env_ad(len(t), 0.012, 1.3 if i < 3 else 1.8)
        place(out, horn, 0.075 * i, 0.55 + 0.1 * i)
    for st in (12, 16, 19):
        place(out, bell(root * 2 ** (st / 12), 0.55, 0.18), 0.23, 0.22)
    sparkle = band_noise(rng, 0.4, 6000, 12000) * env_ad(int(0.4 * SR), 0.05, 2.5)
    place(out, sparkle, 0.22, 0.08)
    return finish(out, 0.003, 0.15)


def s_death(rng, v):
    # small squeaky scream: pitch jumps up, wobbles, then collapses downwards
    dur = 0.3
    out = silence(dur)
    f0 = [1250, 1080, 1420][v]
    ln = 0.24
    t = t_axis(ln)
    x = t / ln
    contour = f0 * (1 + 0.45 * np.sin(np.pi * np.minimum(1, x * 1.8)) - 0.55 * x ** 2)
    vib = 1 + 0.05 * np.sin(2 * np.pi * (31 + 5 * v) * t)
    ph = 2 * np.pi * np.cumsum(contour * vib) / SR
    voice = np.sin(ph) + 0.45 * np.sin(2 * ph + 0.4) + 0.2 * np.sin(3 * ph)
    voice *= env_ad(len(t), 0.01, 1.4)
    place(out, voice, 0.0, 0.8)
    breath = band_noise(rng, ln, 1800, 5000) * env_ad(int(ln * SR), 0.01, 2.0)
    place(out, breath, 0.0, 0.12)
    return finish(out, 0.003, 0.03)


def s_heartbeat(rng, v):
    # loopable dull "lub-dub": two low thumps per beat, silence in between;
    # both edges are silent, so the loop is seamless
    period = [0.92, 0.78][v]
    out = silence(period)
    for at, f, gain in ((0.015, 58.0, 1.0), (0.29, 50.0, 0.7)):
        ln = 0.26
        thump = sweep(f * 1.6, f, ln, 0.4) * env_exp(int(ln * SR), 0.012, 0.06)
        place(out, thump, at, gain)
        muff = band_noise(rng, 0.08, 40, 260) * env_exp(int(0.08 * SR), 0.006, 0.02)
        place(out, muff, at, 0.35 * gain)
    return finish(out, 0.004, 0.02)


def s_leader_hit(rng, v):
    # bone crack (sharp splintering grains) over a heavy thud, then a short cry
    dur = 0.5
    out = silence(dur)
    crack = band_noise(rng, 0.008, 2000, 9000) * env_ad(int(0.008 * SR), 0.0003, 3)
    place(out, crack, 0.0, 1.0)
    for g in range(5 + v):
        gl = rng.uniform(0.004, 0.01)
        grain = band_noise(rng, gl, 1500, 7000) * env_ad(int(gl * SR), 0.0004, 2.5)
        place(out, grain, 0.006 + g * rng.uniform(0.005, 0.012), rng.uniform(0.35, 0.8))
    f0 = [95, 82][v]
    thud = sweep(f0 * 1.5, f0 * 0.5, 0.2, 0.6) * env_exp(int(0.2 * SR), 0.002, 0.06)
    place(out, thud, 0.0, 0.9)
    c0 = [760, 680][v]
    ln = 0.26
    t = t_axis(ln)
    x = t / ln
    contour = c0 * (1 + 0.5 * np.sin(np.pi * np.minimum(1, x * 1.5)) - 0.4 * x)
    ph = 2 * np.pi * np.cumsum(contour * (1 + 0.04 * np.sin(2 * np.pi * 24 * t))) / SR
    cry = (np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.25 * np.sin(3 * ph)) * env_ad(len(t), 0.015, 1.5)
    place(out, cry, 0.07, 0.5)
    return finish(out, 0.002, 0.05)


def s_leader_swap(rng, v):
    # small fanfare: two short pick-ups into a held note, horn plus bell
    dur = 0.85
    out = silence(dur)
    root = [523.25, 466.16][v]
    notes = [(-5, 0.0, 0.09), (-5, 0.1, 0.09), (0, 0.2, 0.5)]
    for st, at, ln in notes:
        f = root * 2 ** (st / 12)
        t = t_axis(ln)
        ph = 2 * np.pi * f * t
        horn = np.sin(ph) + 0.6 * np.sin(2 * ph) + 0.3 * np.sin(3 * ph) + 0.15 * np.sin(5 * ph)
        horn *= env_ad(len(t), 0.01, 1.2 if ln < 0.2 else 1.7)
        place(out, horn, at, 0.7)
    place(out, bell(root * 2, 0.5, 0.15), 0.2, 0.3)
    place(out, bell(root * 2 ** (19 / 12), 0.45, 0.12), 0.24, 0.18)
    return finish(out, 0.003, 0.12)


# --------------------------------------------------------------------------- Etappe 23 (audio pass)

def tone(freq: float, dur: float, partials=((1.0, 1.0),), tau: float = 0.2, attack: float = 0.004) -> np.ndarray:
    t = t_axis(dur)
    out = np.zeros_like(t)
    for ratio, amp in partials:
        out += amp * np.sin(2 * np.pi * freq * ratio * t)
    return out * env_exp(len(t), attack, tau)


def noise_burst(rng, dur: float, lo: float, hi: float, attack: float = 0.002, tau: float = 0.05) -> np.ndarray:
    n = int(dur * SR)
    return band_noise(rng, dur, lo, hi) * env_exp(n, attack, tau)


def s_collect_coin(rng, v):
    # Bernstein coin: short bright clink (two inharmonic metal partials) plus a
    # tiny tick; the HUD chain raises its pitch step by step (play(..., pitch)).
    dur = 0.28
    out = silence(dur)
    f = [2350.0, 2640.0, 2090.0][v]
    clink = tone(f, 0.26, ((1.0, 1.0), (2.41, 0.45), (3.93, 0.18)), 0.055, 0.001)
    place(out, clink, 0.0, 0.8)
    place(out, tone(f * 1.5, 0.2, ((1.0, 1.0), (2.7, 0.3)), 0.04, 0.001), 0.035, 0.45)
    place(out, noise_burst(rng, 0.012, 3000, 9000, 0.0005, 0.003), 0.0, 0.35)
    return finish(out, 0.002, 0.04)


def s_cocoon_open(rng, v):
    # silk tearing: crackly rising noise band, then a soft wet pop
    dur = 0.45
    out = silence(dur)
    n = int(0.32 * SR)
    t = np.arange(n) / SR
    crackle = band_noise(rng, 0.32, 900, 5200) * (0.35 + 0.65 * (rng.random(n) > 0.82))
    crackle *= np.linspace(0.3, 1.0, n) ** 1.5 * np.hanning(n) ** 0.4
    place(out, crackle, 0.0, 0.55)
    pop = sweep(420 + 60 * v, 150, 0.12, 0.5) * env_exp(int(0.12 * SR), 0.002, 0.035)
    place(out, pop, 0.3, 0.8)
    return finish(out, 0.004, 0.05)


def _pop(rng, at: float, out: np.ndarray, gain: float = 0.7) -> None:
    pop = sweep(520, 180, 0.1, 0.5) * env_exp(int(0.1 * SR), 0.001, 0.03)
    place(out, pop, at, gain)
    place(out, noise_burst(rng, 0.04, 600, 3000, 0.001, 0.012), at, 0.25 * gain)


def s_cocoon_common(rng, v):
    # common loot: pop + one soft bell
    out = silence(0.7)
    _pop(rng, 0.0, out)
    place(out, bell([880.0, 987.8][v], 0.6, 0.16), 0.05, 0.6)
    return finish(out, 0.002, 0.1)


def s_cocoon_rare(rng, v):
    # rare: pop + two bells a major third up
    out = silence(0.9)
    _pop(rng, 0.0, out)
    root = [880.0, 932.3][v]
    place(out, bell(root, 0.6, 0.16), 0.05, 0.55)
    place(out, bell(root * 2 ** (4 / 12), 0.7, 0.2), 0.16, 0.65)
    return finish(out, 0.002, 0.14)


def s_cocoon_epic(rng, v):
    # epic: pop + quick major arpeggio + airy shimmer
    out = silence(1.3)
    _pop(rng, 0.0, out, 0.8)
    root = [659.3, 698.5][v]
    for i, st in enumerate((0, 4, 7, 12)):
        place(out, bell(root * 2 ** (st / 12), 0.8, 0.22), 0.05 + i * 0.08, 0.45 + 0.08 * i)
    n = int(1.0 * SR)
    shimmer = band_noise(rng, 1.0, 5000, 10000) * env_ad(n, 0.25, 2.0)
    place(out, shimmer, 0.2, 0.12)
    return finish(out, 0.002, 0.2)


def s_cocoon_legendary(rng, v):
    # legendary: low boom, rising five-note arpeggio, bright chord bloom, sparkle tail
    out = silence(2.0)
    boom = sweep(90, 42, 0.6, 0.5) * env_exp(int(0.6 * SR), 0.003, 0.16)
    place(out, boom, 0.0, 0.9)
    _pop(rng, 0.0, out, 0.7)
    root = [523.25, 587.3][v]
    for i, st in enumerate((0, 4, 7, 11, 12)):
        place(out, bell(root * 2 ** (st / 12), 1.0, 0.3), 0.08 + i * 0.07, 0.4 + 0.06 * i)
    for st in (12, 16, 19):
        f = root * 2 ** (st / 12)
        place(out, tone(f, 1.4, ((1.0, 1.0), (2.0, 0.3), (3.0, 0.12)), 0.45, 0.05), 0.45, 0.22)
    for k in range(9):
        place(out, bell(rng.uniform(2600, 4200), 0.25, 0.06), 0.55 + k * 0.1, 0.12)
    return finish(out, 0.002, 0.35)


def s_cocoon_denied(rng, v):
    # too expensive: dull double knock, second one a semitone lower, muffled
    out = silence(0.42)
    f = [210.0, 190.0][v]
    for i, at in enumerate((0.0, 0.14)):
        ff = f * (2 ** (-1 / 12)) ** i
        knock = tone(ff, 0.2, ((1.0, 1.0), (2.0, 0.25), (3.0, 0.12)), 0.05, 0.002)
        place(out, knock, at, 0.8)
        place(out, noise_burst(rng, 0.05, 150, 900, 0.001, 0.015), at, 0.3)
    return finish(out, 0.002, 0.05)


def s_powerup_take(rng, v):
    # booster picked up: quick upward sweep into a bright chord
    out = silence(0.8)
    rise = sweep(330, 1320, 0.22, 1.6) * env_ad(int(0.22 * SR), 0.01, 0.8)
    place(out, rise, 0.0, 0.35)
    root = [784.0, 880.0, 698.5][v]
    for i, st in enumerate((0, 4, 7)):
        place(out, bell(root * 2 ** (st / 12), 0.55, 0.18), 0.18 + i * 0.03, 0.4)
    return finish(out, 0.003, 0.12)


def s_powerup_end(rng, v):
    # booster runs out: two soft notes falling, a little breath
    out = silence(0.5)
    root = [659.3, 587.3][v]
    place(out, tone(root, 0.22, ((1.0, 1.0), (2.0, 0.2)), 0.07, 0.006), 0.0, 0.55)
    place(out, tone(root * 2 ** (-5 / 12), 0.3, ((1.0, 1.0), (2.0, 0.2)), 0.1, 0.006), 0.12, 0.5)
    return finish(out, 0.003, 0.08)


def s_shrine_tick(rng, v):
    # shrine charging: small glass tick; the shrine raises the pitch with the charge
    out = silence(0.22)
    upper = [(2.9, 0.25), (3.4, 0.2)][v]
    place(out, bell(1480.0, 0.2, 0.05, ((1.0, 1.0), upper)), 0.0, 0.8)
    return finish(out, 0.002, 0.04)


def s_shrine_done(rng, v):
    # shrine full: soft chord swell (choir-ish) under a clear bell
    out = silence(1.6)
    root = [440.0, 466.2][v]
    for st in (0, 7, 12, 16):
        f = root * 2 ** (st / 12)
        t = t_axis(1.4)
        vib = 1 + 0.004 * np.sin(2 * np.pi * 5.2 * t)
        ph = 2 * np.pi * np.cumsum(f * vib) / SR
        voice = (np.sin(ph) + 0.3 * np.sin(2 * ph) + 0.12 * np.sin(3 * ph)) * env_ad(len(t), 0.35, 1.8)
        place(out, voice, 0.0, 0.18)
    place(out, bell(root * 4, 1.0, 0.3), 0.3, 0.5)
    place(out, bell(root * 4 * 2 ** (7 / 12), 0.9, 0.25), 0.42, 0.35)
    return finish(out, 0.01, 0.3)


def s_ability_glutsprung(rng, v):
    # ember leap: rising whoosh with crackling sparks
    out = silence(0.55)
    n = int(0.45 * SR)
    whoosh = band_noise(rng, 0.45, 300, 3500) * env_ad(n, 0.18, 1.5)
    place(out, whoosh, 0.0, 0.6)
    place(out, sweep(160, 520 + 60 * v, 0.35, 1.3) * env_ad(int(0.35 * SR), 0.05, 1.2), 0.0, 0.3)
    for k in range(10):
        place(out, noise_burst(rng, 0.01, 2000, 8000, 0.0005, 0.002), 0.05 + k * rng.uniform(0.025, 0.045), rng.uniform(0.2, 0.45))
    return finish(out, 0.004, 0.06)


def s_ability_land(rng, v):
    # landing: warm thump plus ember crackle
    out = silence(0.5)
    thump = sweep(140, 48, 0.3, 0.5) * env_exp(int(0.3 * SR), 0.002, 0.08)
    place(out, thump, 0.0, 1.0)
    place(out, noise_burst(rng, 0.2, 200, 1800, 0.002, 0.05), 0.0, 0.35)
    for k in range(7):
        place(out, noise_burst(rng, 0.008, 2500, 8000, 0.0005, 0.002), 0.04 + k * rng.uniform(0.02, 0.05), rng.uniform(0.15, 0.3))
    return finish(out, 0.002, 0.08)


def s_ability_sporenbombe(rng, v):
    # spore bomb: deep soft puff plus bubbly pops rising out of it
    out = silence(0.8)
    n = int(0.5 * SR)
    puff = band_noise(rng, 0.5, 120, 1400) * env_ad(n, 0.02, 2.2)
    place(out, puff, 0.0, 0.8)
    place(out, sweep(95, 55, 0.35, 0.5) * env_exp(int(0.35 * SR), 0.004, 0.1), 0.0, 0.6)
    for k in range(8):
        f = rng.uniform(500, 1100)
        bub = sweep(f, f * 1.6, 0.05, 0.7) * env_ad(int(0.05 * SR), 0.004, 1.5)
        place(out, bub, 0.12 + k * rng.uniform(0.04, 0.07), rng.uniform(0.15, 0.3))
    return finish(out, 0.004, 0.1)


def s_ability_panzerstoss(rng, v):
    # armour shove: heavy low impact with a short plated ring
    out = silence(0.7)
    boom = sweep(110, 38, 0.45, 0.5) * env_exp(int(0.45 * SR), 0.002, 0.12)
    place(out, boom, 0.0, 1.0)
    place(out, noise_burst(rng, 0.15, 150, 2500, 0.001, 0.03), 0.0, 0.5)
    ring_f = [410.0, 370.0][v]
    place(out, tone(ring_f, 0.6, ((1.0, 1.0), (2.33, 0.5), (3.71, 0.25)), 0.14, 0.001), 0.005, 0.35)
    return finish(out, 0.002, 0.1)


def s_ability_hetzjagd(rng, v):
    # hunting call: short rising horn with a fast trill of footfalls under it
    out = silence(0.7)
    f0 = [392.0, 440.0][v]
    t = t_axis(0.45)
    contour = f0 * (1 + 0.5 * np.minimum(1.0, t / 0.2))
    ph = 2 * np.pi * np.cumsum(contour) / SR
    horn = (np.sin(ph) + 0.55 * np.sin(2 * ph) + 0.3 * np.sin(3 * ph) + 0.12 * np.sin(4 * ph)) * env_ad(len(t), 0.03, 1.6)
    place(out, horn, 0.0, 0.5)
    for k in range(8):
        place(out, noise_burst(rng, 0.03, 200, 1500, 0.001, 0.008), k * 0.06, 0.35)
    return finish(out, 0.004, 0.08)


def s_ability_saeureschwall(rng, v):
    # acid surge: wet spray (hiss) with fizzing bubbles
    out = silence(0.8)
    n = int(0.6 * SR)
    spray = band_noise(rng, 0.6, 1800, 9000) * env_ad(n, 0.03, 2.0)
    place(out, spray, 0.0, 0.55)
    place(out, band_noise(rng, 0.3, 200, 900) * env_exp(int(0.3 * SR), 0.004, 0.06), 0.0, 0.5)
    for k in range(14):
        f = rng.uniform(1400, 3200)
        fizz = tone(f, 0.03, ((1.0, 1.0),), 0.008, 0.001)
        place(out, fizz, 0.08 + k * rng.uniform(0.025, 0.045), rng.uniform(0.1, 0.25))
    return finish(out, 0.004, 0.1)


def s_ability_schattenschleier(rng, v):
    # shadow veil: reversed dark whoosh into a low hushed shimmer
    out = silence(0.9)
    n = int(0.5 * SR)
    rev = band_noise(rng, 0.5, 200, 2200) * (np.linspace(0.0, 1.0, n) ** 2.5)
    place(out, rev, 0.0, 0.6)
    t = t_axis(0.5)
    f = [196.0, 174.6][v]
    hush = (np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * f * 1.5 * t)) * env_ad(len(t), 0.08, 1.8)
    place(out, hush, 0.42, 0.3)
    place(out, band_noise(rng, 0.4, 3000, 7000) * env_ad(int(0.4 * SR), 0.05, 2.0), 0.45, 0.1)
    return finish(out, 0.004, 0.12)


def s_ability_ready(rng, v):
    # ability ready again: tiny warm two-note chime (ember, not the loot bell)
    out = silence(0.45)
    root = [698.5, 784.0][v]
    place(out, tone(root, 0.3, ((1.0, 1.0), (2.0, 0.25), (3.0, 0.08)), 0.09, 0.003), 0.0, 0.5)
    place(out, tone(root * 2 ** (7 / 12), 0.35, ((1.0, 1.0), (2.0, 0.25), (3.0, 0.08)), 0.12, 0.003), 0.08, 0.55)
    return finish(out, 0.002, 0.08)


def s_leader_hit_heavy(rng, v):
    # heavy leader hit (boss, lost several LP): deeper thud, bigger crack, lower cry
    dur = 0.7
    out = silence(dur)
    place(out, band_noise(rng, 0.012, 1500, 8000) * env_ad(int(0.012 * SR), 0.0004, 3), 0.0, 1.0)
    for g in range(8):
        gl = rng.uniform(0.005, 0.012)
        place(out, band_noise(rng, gl, 1200, 6000) * env_ad(int(gl * SR), 0.0004, 2.5), 0.008 + g * rng.uniform(0.006, 0.014), rng.uniform(0.35, 0.8))
    f0 = [72, 64][v]
    place(out, sweep(f0 * 1.6, f0 * 0.5, 0.35, 0.6) * env_exp(int(0.35 * SR), 0.002, 0.1), 0.0, 1.0)
    ln = 0.34
    t = t_axis(ln)
    x = t / ln
    contour = [560, 500][v] * (1 + 0.45 * np.sin(np.pi * np.minimum(1, x * 1.4)) - 0.45 * x)
    ph = 2 * np.pi * np.cumsum(contour * (1 + 0.05 * np.sin(2 * np.pi * 20 * t))) / SR
    cry = (np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.25 * np.sin(3 * ph)) * env_ad(len(t), 0.02, 1.5)
    place(out, cry, 0.09, 0.45)
    return finish(out, 0.002, 0.08)


def _loop_mod(t: np.ndarray, dur: float, cycles: int, phase: float = 0.0) -> np.ndarray:
    return np.sin(2 * np.pi * cycles / dur * t + phase)


def s_sandworm_dig(rng, v):
    # loop 4 s: the worm burrowing - low grinding rumble, sand hiss, gritty grains
    dur = 4.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    rumble = pink_noise(rng, n, 30, 240) * (0.7 + 0.3 * _loop_mod(t, dur, 3))
    hiss = band_noise(rng, dur, 1500, 6000, n) * (0.5 + 0.5 * _loop_mod(t, dur, 5, 0.7)) ** 2
    out = 0.9 * rumble + 0.18 * hiss
    for _ in range(40):
        at = rng.uniform(0.05, dur - 0.1)
        gl = rng.uniform(0.004, 0.012)
        place(out, band_noise(rng, gl, 800, 5000) * env_ad(int(gl * SR), 0.0005, 2), at, rng.uniform(0.08, 0.2))
    out -= np.mean(out)
    return out * (PEAK / np.max(np.abs(out)))


def s_sandworm_breach(rng, v):
    # breakthrough: deep boom, a wall of spraying sand, falling debris
    out = silence(1.3)
    place(out, sweep(80, 30, 0.9, 0.5) * env_exp(int(0.9 * SR), 0.004, 0.25), 0.0, 1.0)
    n = int(0.8 * SR)
    spray = band_noise(rng, 0.8, 400, 7000) * env_exp(n, 0.01, 0.2)
    place(out, spray, 0.0, 0.7)
    for k in range(26):
        gl = rng.uniform(0.005, 0.015)
        place(out, band_noise(rng, gl, 700, 5000) * env_ad(int(gl * SR), 0.0005, 2), 0.2 + rng.uniform(0.0, 0.9), rng.uniform(0.08, 0.25))
    return finish(out, 0.003, 0.2)


def s_sandworm_sweep(rng, v):
    # tail sweep: heavy air-and-sand whoosh passing through, band moving up and down
    dur = 0.9
    out = silence(dur)
    n = int(0.75 * SR)
    x = np.linspace(0, 1, n)
    low = band_noise(rng, 0.75, 120, 900)
    high = band_noise(rng, 0.75, 900, 5000)
    body = (low * (1 - x) + high * np.sin(np.pi * x)) * np.sin(np.pi * x) ** 1.5
    place(out, body, 0.0, 0.8)
    place(out, sweep(70, 45, 0.5, 0.7) * env_ad(int(0.5 * SR), 0.12, 1.5), 0.1, 0.5)
    return finish(out, 0.01, 0.1)


def s_sandgrub_burst(rng, v):
    # sand grubs breaking out: small sand puff plus clicky chitter
    out = silence(0.5)
    place(out, noise_burst(rng, 0.25, 400, 4000, 0.004, 0.06), 0.0, 0.6)
    for k in range(6 + v):
        f = rng.uniform(2500, 4200)
        click = tone(f, 0.015, ((1.0, 1.0), (1.5, 0.4)), 0.004, 0.0005)
        place(out, click, 0.06 + k * rng.uniform(0.025, 0.05), rng.uniform(0.25, 0.5))
    return finish(out, 0.003, 0.06)


def s_sandstorm(rng, v):
    # loop 8 s: howling wind - moving band noise, sand hiss, two whistling tones
    dur = 8.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    wind = pink_noise(rng, n, 80, 2500) * (0.6 + 0.4 * _loop_mod(t, dur, 2) * _loop_mod(t, dur, 3, 1.0))
    sand = band_noise(rng, dur, 2500, 9000, n) * (0.55 + 0.45 * _loop_mod(t, dur, 4, 0.4)) ** 2
    out = 0.8 * wind + 0.22 * sand
    for f, cyc, g in ((640.0, 2, 0.05), (910.0, 3, 0.035)):
        ph = 2 * np.pi * f * t + 3.0 * np.sin(2 * np.pi * 1 / dur * t)
        out += g * np.sin(ph) * np.clip(_loop_mod(t, dur, cyc, 0.5), 0, 1) ** 2
    out -= np.mean(out)
    return out * (PEAK / np.max(np.abs(out)))


def s_quicksand(rng, v):
    # loop 3 s: sifting, sucking sand under the swarm - soft low churn with slow gulps
    dur = 3.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    churn = band_noise(rng, dur, 150, 1400, n) * (0.6 + 0.4 * _loop_mod(t, dur, 2))
    grains = band_noise(rng, dur, 2000, 6000, n) * 0.15
    out = churn * 0.8 + grains
    for at in (0.6, 1.7, 2.4):
        gulp = sweep(180, 90, 0.18, 0.6) * env_ad(int(0.18 * SR), 0.03, 1.5)
        place(out, gulp, at, 0.35)
    out -= np.mean(out)
    return out * (PEAK / np.max(np.abs(out)))


def s_ambience_desert(rng, v):
    # loop 10 s: dry desert air - soft low wind, fine sand sifting, sparse crickets
    # and a far bird call; all modulations complete whole cycles (seamless)
    dur = 10.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    wind = pink_noise(rng, n, 50, 900) * (0.55 + 0.25 * _loop_mod(t, dur, 2) + 0.2 * _loop_mod(t, dur, 5, 1.3))
    sift = band_noise(rng, dur, 3000, 8000, n) * (np.clip(_loop_mod(t, dur, 3, 0.2), 0, 1) ** 3 + 0.1)
    out = 0.6 * wind + 0.1 * sift
    for _ in range(4):
        start = rng.uniform(0.4, dur - 1.4)
        f = rng.uniform(4200, 5200)
        for p in range(int(rng.integers(4, 8))):
            pl = 0.03
            chirp = np.sin(2 * np.pi * f * t_axis(pl)) * np.hanning(int(pl * SR))
            place(out, chirp, start + p * 0.11, rng.uniform(0.025, 0.045))
    start = rng.uniform(3.0, 6.0)
    for k, (f0, f1) in enumerate(((1900, 2500), (2500, 1700))):
        call = sweep(f0, f1, 0.18, 1.0) * np.hanning(int(0.18 * SR))
        place(out, call, start + k * 0.22, 0.03)
    out -= np.mean(out)
    return out * (PEAK / np.max(np.abs(out)))


SOUNDS_23 = {
    "collect_coin": (s_collect_coin, 3),
    "cocoon_open": (s_cocoon_open, 2),
    "cocoon_common": (s_cocoon_common, 2),
    "cocoon_rare": (s_cocoon_rare, 2),
    "cocoon_epic": (s_cocoon_epic, 2),
    "cocoon_legendary": (s_cocoon_legendary, 2),
    "cocoon_denied": (s_cocoon_denied, 2),
    "powerup_take": (s_powerup_take, 3),
    "powerup_end": (s_powerup_end, 2),
    "shrine_tick": (s_shrine_tick, 2),
    "shrine_done": (s_shrine_done, 2),
    "ability_glutsprung": (s_ability_glutsprung, 2),
    "ability_land": (s_ability_land, 2),
    "ability_sporenbombe": (s_ability_sporenbombe, 2),
    "ability_panzerstoss": (s_ability_panzerstoss, 2),
    "ability_hetzjagd": (s_ability_hetzjagd, 2),
    "ability_saeureschwall": (s_ability_saeureschwall, 2),
    "ability_schattenschleier": (s_ability_schattenschleier, 2),
    "ability_ready": (s_ability_ready, 2),
    "leader_hit_heavy": (s_leader_hit_heavy, 2),
    "sandworm_dig": (s_sandworm_dig, 1),
    "sandworm_breach": (s_sandworm_breach, 2),
    "sandworm_sweep": (s_sandworm_sweep, 2),
    "sandgrub_burst": (s_sandgrub_burst, 3),
    "sandstorm": (s_sandstorm, 1),
    "quicksand": (s_quicksand, 1),
    "ambience_desert": (s_ambience_desert, 1),
}


# --------------------------------------------------------------------------- Etappe 24 (Glutsumpf)

def _blub(rng, f: float, dur: float = 0.09) -> np.ndarray:
    # one lava bubble: short upward pitch pop with a soft wet tail
    return sweep(f, f * 1.9, dur, 0.6) * env_ad(int(dur * SR), 0.006, 1.8)


def s_ambience_glutsumpf(rng, v):
    # loop 10 s: glowing swamp - deep lava rumble, slow bubbling, steam hiss,
    # a little crackle; all modulations complete whole cycles (seamless)
    dur = 10.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    rumble = pink_noise(rng, n, 25, 180) * (0.7 + 0.3 * np.sin(2 * np.pi * 2 / dur * t))
    steam = band_noise(rng, dur, 2500, 8000, n) * np.clip(np.sin(2 * np.pi * 3 / dur * t + 0.8), 0, 1) ** 4
    out = 0.8 * rumble + 0.1 * steam
    for _ in range(26):
        place(out, _blub(rng, rng.uniform(140, 320), rng.uniform(0.06, 0.12)), rng.uniform(0.2, dur - 0.3), rng.uniform(0.05, 0.12))
    for _ in range(30):
        gl = rng.uniform(0.003, 0.008)
        place(out, band_noise(rng, gl, 2000, 7000) * env_ad(int(gl * SR), 0.0004, 2), rng.uniform(0.1, dur - 0.1), rng.uniform(0.03, 0.07))
    out -= np.mean(out)
    return out * (PEAK / np.max(np.abs(out)))


def s_lava_warn(rng, v):
    # eruption announced (1.6 s like the ground ring): rising rumble and faster bubbling
    dur = 1.6
    out = silence(dur)
    n = int(dur * SR)
    x = np.linspace(0, 1, n)
    rumble = band_noise(rng, dur, 40, 320) * (0.15 + 0.85 * x ** 1.6)
    place(out, rumble, 0.0, 0.8)
    place(out, sweep(55, 95 + 10 * v, dur, 1.4) * (x ** 1.2), 0.0, 0.35)
    at = 0.1
    while at < dur - 0.12:
        k = at / dur
        place(out, _blub(rng, rng.uniform(160, 260) * (1 + 0.6 * k)), at, 0.12 + 0.3 * k)
        at += 0.22 - 0.16 * k + rng.uniform(0.0, 0.03)
    return finish(out, 0.01, 0.04)


def s_lava_burst(rng, v):
    # eruption: deep boom, a hot whoosh upwards, splattering lava and hiss
    out = silence(1.2)
    place(out, sweep(95, 34, 0.7, 0.5) * env_exp(int(0.7 * SR), 0.003, 0.18), 0.0, 1.0)
    n = int(0.6 * SR)
    whoosh = band_noise(rng, 0.6, 250, 4000) * env_ad(n, 0.03, 1.8)
    place(out, whoosh, 0.0, 0.6)
    for k in range(14):
        place(out, _blub(rng, rng.uniform(220, 480), rng.uniform(0.04, 0.08)), 0.12 + rng.uniform(0.0, 0.8), rng.uniform(0.12, 0.3))
    place(out, band_noise(rng, 0.8, 3000, 9000) * env_exp(int(0.8 * SR), 0.05, 0.3), 0.15, 0.18)
    return finish(out, 0.003, 0.15)


SOUNDS_24 = {
    "ambience_glutsumpf": (s_ambience_glutsumpf, 1),
    "lava_warn": (s_lava_warn, 2),
    "lava_burst": (s_lava_burst, 2),
}


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
    "split": (s_split, 4),
    "milestone": (s_milestone, 2),
    "death": (s_death, 3),
    "heartbeat": (s_heartbeat, 2),
    "leader_hit": (s_leader_hit, 2),
    "leader_swap": (s_leader_swap, 2),
}
SOUNDS.update(SOUNDS_23)
SOUNDS.update(SOUNDS_24)
LOOPS = ("ambience", "heartbeat", "sandworm_dig", "sandstorm", "quicksand")


def analyse(name: str, x: np.ndarray, loop: bool) -> str:
    peak_db = 20 * np.log10(np.max(np.abs(x)) + 1e-12)
    dc = float(np.mean(x))
    first = abs(x[0]) if not loop else abs(x[-1] - x[0])
    last = abs(x[-1])
    # Loops of noise (Etappe 23): the seam only has to look like any other
    # neighbouring-sample step (as in tools/gen_music.py).
    limit = max(0.01, float(np.percentile(np.abs(np.diff(x)), 99.5))) if loop else 0.01
    ok = peak_db <= -2.9 and abs(dc) < 1e-3 and first < limit and (loop or last < 0.01)
    return f"{name:22s} {len(x) / SR:5.2f}s peak {peak_db:6.2f} dBFS dc {dc:+.5f} edge {first:.4f}/{last:.4f} {'OK' if ok else 'CHECK'}"


def user_ids() -> set:
    """Ids whose recorded user sound is available (tools/import_user_sfx.py)."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    try:
        import import_user_sfx
    except ImportError:
        return set()
    return {sid for sid in import_user_sfx.RECIPES if import_user_sfx.source_available(sid)}


def main() -> int:
    os.makedirs(OUT_DIR, exist_ok=True)
    total = 0
    bad = 0
    skip = set() if "--force" in sys.argv else user_ids()
    # --only a,b,c: just these ids (Etappe 23: new sounds without touching the rest)
    only = set()
    for arg in sys.argv[1:]:
        if arg.startswith("--only="):
            only = set(arg.split("=", 1)[1].split(","))
    for sid, (fn, count) in SOUNDS.items():
        if only and sid not in only:
            continue
        if sid in skip:
            print(f"{sid:22s} user sound (tools/import_user_sfx.py) - skipped")
            continue
        for v in range(count):
            rng = np.random.default_rng(1000 + 97 * v + sum(map(ord, sid)))
            x = fn(rng, v)
            name = f"{sid}_{v + 1}"
            total += write_wav(name, x)
            line = analyse(name, x, sid.startswith(LOOPS))
            bad += line.endswith("CHECK")
            print(line)
    print(f"total bytes: {total} ({total / 1024:.1f} KiB)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
