"""Procedural music generator for MAWLINGS.

A tiny deterministic sequencer + additive synths (no samples, no downloads).
Output: 16-bit mono 22.05 kHz WAV files in assets/music/:

    menu_theme.wav    80 BPM, 20 bars (60 s) loop, D Dorian, calm and curious
    run_base.wav      96 BPM, 8 bars (20 s) loop, D Phrygian: soft percussion + bass + dark pad
    run_tension.wav   same grid: extra percussion + marimba arpeggio
    run_flood.wav     same grid: four-on-the-floor, distorted bass, warning motif
    run_boss.wav      same grid: heavy taiko drums, low brass swells
    sting_flood.wav, sting_boss.wav, sting_king.wav, sting_extinct.wav  one-shots

All run stems share tempo, length and chord grid, so they can be layered and
cross-faded while playing in sync. Loops are rendered circularly (note tails
and reverb wrap around the loop end), so the seam is click-free. Every file is
DC-free and peak-normalised to -3 dBFS; loops carry a RIFF 'smpl' chunk so
Godot's importer detects the forward loop.

Run from the project root:
    PYTHONPATH=.tools python tools/gen_music.py          (Bash)
    $env:PYTHONPATH='.tools'; python tools/gen_music.py  (PowerShell)
"""

from __future__ import annotations

import os
import struct
import sys
import wave

import numpy as np

SR = 22050
PEAK = 10 ** (-3.0 / 20.0)
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "music")
NYQ_SAFE = 9500.0

RUN_BPM = 96.0
RUN_BARS = 8
MENU_BPM = 80.0
MENU_BARS = 20


def mtof(m: float) -> float:
    return 440.0 * 2 ** ((m - 69) / 12)


# --------------------------------------------------------------------------- canvas

class Canvas:
    """Sample buffer. loop=True wraps everything past the end back to the start."""

    def __init__(self, seconds: float, loop: bool, bpm: float = 120.0):
        self.n = int(round(seconds * SR))
        self.loop = loop
        self.bpm = bpm
        self.buf = np.zeros(self.n)

    def beat(self, b: float) -> float:
        return b * 60.0 / self.bpm

    def add(self, sig: np.ndarray, at_sec: float, gain: float = 1.0) -> None:
        i = int(round(at_sec * SR))
        if self.loop:
            i %= self.n
            pos = 0
            while pos < len(sig):
                j = (i + pos) % self.n
                k = min(len(sig) - pos, self.n - j)
                self.buf[j:j + k] += sig[pos:pos + k] * gain
                pos += k
        else:
            if i >= self.n:
                return
            k = min(len(sig), self.n - i)
            self.buf[i:i + k] += sig[:k] * gain

    def at(self, sig: np.ndarray, beat: float, gain: float = 1.0) -> None:
        self.add(sig, self.beat(beat), gain)


# --------------------------------------------------------------------------- dsp helpers

def t_axis(dur: float) -> np.ndarray:
    return np.arange(int(dur * SR)) / SR


def env_exp(n: int, attack: float, tau: float) -> np.ndarray:
    a = min(max(2, int(attack * SR)), max(2, n - 1))
    e = np.exp(-np.arange(n) / max(1e-4, tau * SR))
    e[:a] *= np.sin(np.linspace(0, np.pi / 2, a)) ** 2
    return e


def env_asr(n: int, attack: float, release: float) -> np.ndarray:
    a = min(max(2, int(attack * SR)), n // 2)
    r = min(max(2, int(release * SR)), n - a)
    e = np.ones(n)
    e[:a] = np.sin(np.linspace(0, np.pi / 2, a)) ** 2
    e[n - r:] *= np.cos(np.linspace(0, np.pi / 2, r)) ** 2
    return e


def tail_fade(x: np.ndarray, sec: float = 0.01) -> np.ndarray:
    k = min(len(x), max(2, int(sec * SR)))
    x[-k:] *= np.cos(np.linspace(0, np.pi / 2, k)) ** 2
    return x


def spectral(x: np.ndarray, lo: float, hi: float, circular: bool = True) -> np.ndarray:
    """Band filter in the frequency domain (circular -> keeps loops seamless)."""
    n = len(x)
    pad = 0 if circular else int(0.2 * SR)
    spec = np.fft.rfft(np.concatenate([x, np.zeros(pad)]))
    f = np.fft.rfftfreq(n + pad, 1.0 / SR)
    mask = np.ones_like(f)
    if lo > 0:
        mask *= 1.0 / (1.0 + (lo / np.maximum(f, 1e-3)) ** 4)
    if hi > 0:
        mask *= 1.0 / (1.0 + (f / hi) ** 4)
    return np.fft.irfft(spec * mask, n + pad)[:n]


def noise(rng: np.random.Generator, dur: float, lo: float, hi: float) -> np.ndarray:
    n = max(8, int(dur * SR))
    x = spectral(rng.standard_normal(n), lo, hi)
    return x / (np.max(np.abs(x)) + 1e-12)


def additive(freq: float, dur: float, bright: float, odd_only: bool = False, detune: float = 0.0,
             vib: float = 0.0, phase0: float = 0.0) -> np.ndarray:
    """Band-limited saw/square-ish tone; harmonics roll off above 'bright' Hz."""
    t = t_axis(dur)
    f_t = freq * (1.0 + detune)
    ph = 2 * np.pi * f_t * t + phase0
    if vib > 0:
        ph += vib * np.sin(2 * np.pi * 5.1 * t)
    out = np.zeros_like(t)
    k = 1
    while k * f_t < NYQ_SAFE and k < 60:
        if not (odd_only and k % 2 == 0):
            amp = (1.0 / k) * np.exp(-(k * f_t) / bright)
            out += amp * np.sin(k * ph)
        k += 1
    return out


def reverb(x: np.ndarray, rng: np.random.Generator, seconds: float, wet: float, circular: bool,
           hi: float = 3500.0) -> np.ndarray:
    ir_n = int(seconds * SR)
    ir = rng.standard_normal(ir_n) * np.exp(-np.arange(ir_n) / (seconds * SR / 5.0))
    ir = spectral(ir, 150, hi)
    ir[: int(0.012 * SR)] = 0.0  # pre-delay
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-12
    if circular:
        n = len(x)
        h = np.zeros(n)
        h[: min(n, ir_n)] = ir[: min(n, ir_n)]
        y = np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(h), n)
    else:
        n = len(x) + ir_n
        y = np.fft.irfft(np.fft.rfft(x, n) * np.fft.rfft(ir, n), n)[: len(x)]
    return x + wet * y


def soft_clip(x: np.ndarray, drive: float) -> np.ndarray:
    peak = np.max(np.abs(x)) + 1e-12
    return np.tanh(drive * x / peak) / np.tanh(drive)


# --------------------------------------------------------------------------- instruments

def marimba(m: float, dur: float = 0.9, vel: float = 1.0) -> np.ndarray:
    f = mtof(m)
    t = t_axis(dur)
    x = np.sin(2 * np.pi * f * t) * np.exp(-t / 0.32)
    x += 0.35 * np.sin(2 * np.pi * f * 3.93 * t) * np.exp(-t / 0.06)
    x += 0.10 * np.sin(2 * np.pi * f * 9.2 * t) * np.exp(-t / 0.02) if f * 9.2 < NYQ_SAFE else 0
    return tail_fade(x * env_exp(len(t), 0.002, 10.0) * vel)


def kalimba(m: float, dur: float = 1.4, vel: float = 1.0) -> np.ndarray:
    f = mtof(m)
    t = t_axis(dur)
    x = np.sin(2 * np.pi * f * t) * np.exp(-t / 0.55)
    x += 0.22 * np.sin(2 * np.pi * f * 2.0 * t) * np.exp(-t / 0.25)
    if f * 5.4 < NYQ_SAFE:
        x += 0.16 * np.sin(2 * np.pi * f * 5.4 * t) * np.exp(-t / 0.05)
    return tail_fade(x * env_exp(len(t), 0.0015, 10.0) * vel)


def pluck_bass(m: float, dur: float, vel: float = 1.0, bright: float = 380.0) -> np.ndarray:
    x = additive(mtof(m), dur, bright) + 0.6 * np.sin(2 * np.pi * mtof(m) * t_axis(dur))
    e = env_exp(len(x), 0.006, dur * 0.7) * env_asr(len(x), 0.004, min(0.06, dur * 0.3))
    return x * e * vel


def dist_bass(m: float, dur: float, vel: float = 1.0) -> np.ndarray:
    f = mtof(m)
    x = additive(f, dur, 900.0) + 0.5 * additive(f, dur, 600.0, detune=0.006)
    x = np.tanh(2.8 * x / (np.max(np.abs(x)) + 1e-9))
    x = spectral(x, 30, 2200)
    e = env_exp(len(x), 0.004, dur * 0.9) * env_asr(len(x), 0.003, min(0.05, dur * 0.3))
    return x * e * vel


def pad(chord: list[float], dur: float, vel: float = 1.0, bright: float = 700.0) -> np.ndarray:
    out = np.zeros(int(dur * SR))
    for i, m in enumerate(chord):
        for d in (-0.004, 0.0, 0.0045):
            out += additive(mtof(m), dur, bright, detune=d, phase0=1.3 * i + 7 * d)
    return out * env_asr(len(out), min(0.9, dur * 0.35), min(1.2, dur * 0.4)) * vel / (len(chord) * 3)


def brass(m: float, dur: float, vel: float = 1.0, bright: float = 1400.0) -> np.ndarray:
    f = mtof(m)
    x = additive(f, dur, bright, vib=0.004 * f / 5.1) + additive(f, dur, bright * 0.7, detune=0.005)
    # brightness swell: blend a darker copy at the start
    dark = additive(f, dur, bright * 0.35)
    t = np.linspace(0, 1, len(x))
    x = dark * (1 - np.minimum(1, t * 4)) + x * np.minimum(1, t * 4)
    return x * env_asr(len(x), 0.04, min(0.25, dur * 0.4)) * vel


def kick(vel: float = 1.0, f0: float = 110.0, f1: float = 44.0, dur: float = 0.42) -> np.ndarray:
    t = t_axis(dur)
    freq = f1 + (f0 - f1) * np.exp(-t / 0.035)
    x = np.sin(2 * np.pi * np.cumsum(freq) / SR)
    # 2nd harmonic helps phone speakers hear it
    x += 0.35 * np.sin(4 * np.pi * np.cumsum(freq) / SR) * np.exp(-t / 0.05)
    return tail_fade(x * env_exp(len(t), 0.002, dur * 0.35) * vel)


def taiko(rng, vel: float = 1.0, f0: float = 150.0, dur: float = 0.9) -> np.ndarray:
    t = t_axis(dur)
    freq = f0 * 0.55 + f0 * 0.45 * np.exp(-t / 0.05)
    x = np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-t / 0.28)
    x += 0.5 * np.sin(2 * np.pi * np.cumsum(freq * 1.58) / SR) * np.exp(-t / 0.12)
    skin = noise(rng, dur, 80, 900) * np.exp(-t / 0.06)
    x += 0.6 * skin
    return tail_fade(x * env_exp(len(t), 0.002, 10.0) * vel)


def log_drum(m: float, vel: float = 1.0) -> np.ndarray:
    f = mtof(m)
    t = t_axis(0.35)
    ph = 2 * np.pi * np.cumsum(f * (1 + 0.25 * np.exp(-t / 0.01))) / SR
    x = np.sin(ph) * np.exp(-t / 0.09) + 0.3 * np.sin(2.7 * ph) * np.exp(-t / 0.03)
    return tail_fade(x * env_exp(len(t), 0.0015, 10.0) * vel)


def woodblock(rng, pitch: float = 900.0, vel: float = 1.0) -> np.ndarray:
    t = t_axis(0.09)
    x = np.sin(2 * np.pi * pitch * t) * np.exp(-t / 0.018)
    x += 0.4 * np.sin(2 * np.pi * pitch * 2.4 * t) * np.exp(-t / 0.008)
    x += 0.25 * noise(rng, 0.09, 1500, 5000) * np.exp(-t / 0.004)
    return tail_fade(x * vel)


def shaker(rng, vel: float = 1.0, dur: float = 0.08) -> np.ndarray:
    x = noise(rng, dur, 3500, 9000)
    return tail_fade(x * env_exp(len(x), 0.008, dur * 0.35) * vel)


def snare(rng, vel: float = 1.0) -> np.ndarray:
    t = t_axis(0.22)
    x = 0.8 * noise(rng, 0.22, 900, 7000) * np.exp(-t / 0.05)
    x += 0.6 * np.sin(2 * np.pi * 190 * t) * np.exp(-t / 0.04)
    return tail_fade(x * env_exp(len(t), 0.001, 10.0) * vel)


def gong(rng, m: float, dur: float, vel: float = 1.0) -> np.ndarray:
    f = mtof(m)
    t = t_axis(dur)
    x = np.zeros_like(t)
    for r, a, tau in ((1.0, 1.0, 1.6), (1.52, 0.5, 1.1), (2.31, 0.35, 0.8), (2.94, 0.25, 0.6), (4.17, 0.12, 0.35)):
        if f * r < NYQ_SAFE:
            x += a * np.sin(2 * np.pi * f * r * t * (1 + 0.002 * np.exp(-t))) * np.exp(-t / tau)
    x += 0.2 * noise(rng, dur, 300, 3000) * np.exp(-t / 0.05)
    return tail_fade(x * env_exp(len(t), 0.003, 10.0) * vel, 0.2)


def swell(rng, dur: float, lo: float, hi: float) -> np.ndarray:
    x = noise(rng, dur, lo, hi)
    t = np.linspace(0, 1, len(x))
    return x * t ** 2.2 * env_asr(len(x), 0.01, 0.02)


# --------------------------------------------------------------------------- mastering & analysis

def master_loop(x: np.ndarray, drive: float = 0.0) -> np.ndarray:
    x = spectral(x, 28, NYQ_SAFE)
    if drive > 0:
        x = soft_clip(x, drive)
    x = x - np.mean(x)
    return x * (PEAK / (np.max(np.abs(x)) + 1e-12))


def master_oneshot(x: np.ndarray, drive: float = 0.0) -> np.ndarray:
    x = spectral(x, 28, NYQ_SAFE, circular=False)
    if drive > 0:
        x = soft_clip(x, drive)
    x = x - np.mean(x) * np.hanning(len(x))
    fi, fo = int(0.004 * SR), int(0.25 * SR)
    x[:fi] *= np.sin(np.linspace(0, np.pi / 2, fi)) ** 2
    x[-fo:] *= np.cos(np.linspace(0, np.pi / 2, fo)) ** 2
    return x * (PEAK / (np.max(np.abs(x)) + 1e-12))


def write_wav(name: str, x: np.ndarray, loop: bool) -> int:
    path = os.path.join(OUT_DIR, name + ".wav")
    pcm = np.clip(np.round(x * 32767), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    if loop:
        # RIFF 'smpl' chunk: one forward loop over the whole file (end is inclusive).
        period = int(round(1e9 / SR))
        smpl = struct.pack("<9I", 0, 0, period, 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, len(pcm) - 1, 0, 0)
        with open(path, "r+b") as f:
            f.seek(0, 2)
            f.write(b"smpl" + struct.pack("<I", len(smpl)) + smpl)
            size = f.tell()
            f.seek(4)
            f.write(struct.pack("<I", size - 8))
    return os.path.getsize(path)


def analyse(name: str, x: np.ndarray, loop: bool) -> tuple[bool, str]:
    peak_db = 20 * np.log10(np.max(np.abs(x)) + 1e-12)
    rms_db = 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-12)
    dc = float(np.mean(x))
    step = np.abs(np.diff(x))
    typical = float(np.percentile(step, 99.5))
    if loop:
        seam = abs(float(x[-1] - x[0]))
        # the seam jump must look like any other neighbouring-sample step
        ok_seam = seam <= max(typical, 0.02)
        edge = f"seam={seam:.4f} (p99.5 step {typical:.4f})"
    else:
        seam = max(abs(float(x[0])), abs(float(x[-1])))
        ok_seam = seam < 0.01
        edge = f"edges={seam:.4f}"
    ok = peak_db <= -2.9 and abs(dc) < 1e-3 and ok_seam
    return ok, f"{name:15s} {len(x) / SR:6.2f}s peak {peak_db:6.2f} dBFS rms {rms_db:6.1f} dB dc {dc:+.5f} {edge} {'OK' if ok else 'FAIL'}"


# --------------------------------------------------------------------------- run material (D Phrygian)

# One chord per bar. Triads as MIDI; bass roots in octave 2.
RUN_CHORDS = [
    ([50, 53, 57], 38),  # Dm
    ([50, 53, 57], 38),  # Dm
    ([51, 55, 58], 39),  # Eb
    ([50, 53, 57], 38),  # Dm
    ([46, 50, 53], 34),  # Bb
    ([48, 51, 55], 36),  # Cm
    ([43, 46, 50], 43),  # Gm
    ([51, 55, 58], 39),  # Eb -> Dm (Phrygian cadence across the loop seam)
]


def run_canvas() -> Canvas:
    return Canvas(RUN_BARS * 4 * 60.0 / RUN_BPM, True, RUN_BPM)


def gen_run_base() -> np.ndarray:
    rng = np.random.default_rng(101)
    c = run_canvas()
    beat = 60.0 / RUN_BPM
    for bar, (chord, root) in enumerate(RUN_CHORDS):
        b0 = bar * 4
        # bass: root on 1, a nudge on the "and" of 2, octave pickup at the end of odd bars
        c.at(pluck_bass(root, beat * 1.4, 0.8, 900.0), b0)
        c.at(pluck_bass(root + 12, beat * 0.45, 0.5, 900.0), b0 + 1.5)
        c.at(pluck_bass(root, beat * 0.9, 0.6, 900.0), b0 + 2.5)
        if bar % 2 == 1:
            c.at(pluck_bass(root + 12, beat * 0.4, 0.45, 900.0), b0 + 3.5)
        # low, dark pad: one chord per two bars would blur; follow bars
        c.at(pad(chord + [chord[0] - 12], beat * 4.6, 0.8, bright=650.0), b0 - 0.3)
        # soft percussion: shaker 8ths, log drum on 1 and 3-and, soft kick on 1
        for e in range(8):
            c.at(shaker(rng, 0.22 if e % 2 else 0.12), b0 + e * 0.5)
        c.at(log_drum(57, 0.45), b0)
        c.at(log_drum(52, 0.35), b0 + 2.5)
        c.at(kick(0.35, 90, 45, 0.35), b0)
        if bar % 4 == 3:
            c.at(log_drum(60, 0.3), b0 + 3.25)
            c.at(log_drum(57, 0.3), b0 + 3.5)
    x = reverb(c.buf, rng, 1.2, 0.18, True)
    return master_loop(x, 1.2)


def gen_run_tension() -> np.ndarray:
    rng = np.random.default_rng(202)
    c = run_canvas()
    arp_up = [0, 1, 2, 3, 2, 1, 2, 3]
    for bar, (chord, _root) in enumerate(RUN_CHORDS):
        b0 = bar * 4
        tones = [m + 12 for m in chord] + [chord[0] + 24]
        # marimba arpeggio: 8ths in the first half, 16ths in the second
        if bar < 4:
            for i, idx in enumerate(arp_up):
                c.at(marimba(tones[idx], 0.7, 0.75 if i % 2 == 0 else 0.5), b0 + i * 0.5)
        else:
            for i in range(16):
                idx = arp_up[i % 8] if i < 8 else arp_up[(7 - i) % 8]
                c.at(marimba(tones[idx] + (12 if i in (6, 14) else 0), 0.5, 0.65 if i % 4 == 0 else 0.4), b0 + i * 0.25)
        # woodblock syncopation + low tom answer
        for pos, p, v in ((0.75, 1100, 0.5), (1.5, 850, 0.45), (2.25, 1100, 0.4), (3.5, 850, 0.5), (3.75, 1100, 0.35)):
            c.at(woodblock(rng, p, v), b0 + pos)
        c.at(log_drum(45, 0.55), b0 + 3.0)
        for s in range(16):
            if s % 4 == 2:
                c.at(shaker(rng, 0.3, 0.05), b0 + s * 0.25)
    x = reverb(c.buf, rng, 1.0, 0.2, True)
    return master_loop(x, 1.0)


WARN_MOTIF = [(0.0, 74, 0.45), (0.5, 75, 0.45), (1.0, 74, 0.45), (1.5, 69, 1.2)]  # D5 Eb5 D5 A4


def gen_run_flood() -> np.ndarray:
    rng = np.random.default_rng(303)
    c = run_canvas()
    beat = 60.0 / RUN_BPM
    for bar, (chord, root) in enumerate(RUN_CHORDS):
        b0 = bar * 4
        for q in range(4):
            c.at(kick(1.0, 120, 46, 0.38), b0 + q)
        c.at(snare(rng, 0.6), b0 + 1)
        c.at(snare(rng, 0.7), b0 + 3)
        if bar % 2 == 1:
            c.at(snare(rng, 0.35), b0 + 3.75)
        for s in range(16):
            c.at(shaker(rng, 0.35 if s % 2 else 0.2, 0.05), b0 + s * 0.25)
        # driving distorted bass in 8ths, octave jump on the off-beat before each bar line
        for e in range(8):
            m = root + (12 if e == 7 else 0)
            c.at(dist_bass(m, beat * 0.46, 0.9 if e % 2 == 0 else 0.7), b0 + e * 0.5)
        # warning motif on odd bars, lower echo on even bars
        if bar % 2 == 0:
            for off, m, d in WARN_MOTIF:
                c.at(brass(m, beat * d, 0.55), b0 + off)
        else:
            c.at(brass(chord[0] + 12, beat * 1.5, 0.35, 900.0), b0 + 2)
    x = reverb(c.buf, rng, 0.9, 0.12, True)
    return master_loop(x, 2.0)


def gen_run_boss() -> np.ndarray:
    rng = np.random.default_rng(404)
    c = run_canvas()
    beat = 60.0 / RUN_BPM
    for bar, (chord, root) in enumerate(RUN_CHORDS):
        b0 = bar * 4
        # heavy half-time taiko pattern
        c.at(taiko(rng, 1.0, 120, 1.0), b0)
        c.at(taiko(rng, 0.5, 170, 0.6), b0 + 1.5)
        c.at(taiko(rng, 0.85, 135, 0.9), b0 + 2)
        c.at(taiko(rng, 0.45, 190, 0.5), b0 + 2.75)
        c.at(taiko(rng, 0.4, 190, 0.5), b0 + 3.25)
        if bar % 4 == 3:
            for i, p in enumerate((210, 190, 170, 150)):
                c.at(taiko(rng, 0.5 + 0.1 * i, p, 0.4), b0 + 3 + i * 0.25)
        if bar % 4 == 0:
            c.at(kick(1.0, 70, 32, 1.6), b0)  # sub boom
        # low brass swell on the root + fifth, following the chord grid
        fifth = root + 7
        c.at(brass(root + 12, beat * 3.6, 0.5, 700.0), b0 + 0.25)
        c.at(brass(fifth + 12, beat * 3.6, 0.35, 700.0), b0 + 0.25)
    # tritone stab before the loop turns over
    c.at(brass(38 + 12 + 6, beat * 1.0, 0.45, 1100.0), 7 * 4 + 3)
    x = reverb(c.buf, rng, 1.4, 0.22, True, 2500.0)
    return master_loop(x, 1.8)


# --------------------------------------------------------------------------- menu (D Dorian)

MENU_CHORDS = [
    [50, 53, 57, 60], [43, 50, 55, 59], [41, 48, 52, 57], [48, 52, 55, 60],   # Dm7 G/D Fmaj7 C
    [50, 53, 57, 60], [45, 52, 55, 60], [43, 50, 55, 59], [43, 47, 50, 55],   # Dm7 Am7 G G
    [41, 48, 52, 57], [43, 50, 55, 59], [45, 52, 55, 60], [50, 53, 57, 60],   # Fmaj7 G Am7 Dm7
    [41, 48, 52, 57], [43, 50, 55, 59], [40, 50, 55, 59], [45, 52, 55, 60],   # Fmaj7 G Em7 Am7
    [50, 53, 57, 60], [43, 50, 55, 59], [48, 52, 55, 60], [45, 52, 55, 57],   # Dm7 G C Am(sus) -> Dm7
]
DORIAN = [0, 2, 3, 5, 7, 9, 11]  # relative to D


def dorian_near(m: int, direction: int) -> int:
    m += direction
    while (m - 62) % 12 not in DORIAN:
        m += direction
    return m


def gen_menu() -> np.ndarray:
    rng = np.random.default_rng(505)
    c = Canvas(MENU_BARS * 4 * 60.0 / MENU_BPM, True, MENU_BPM)
    beat = 60.0 / MENU_BPM
    rhythms = [
        [(0.0, 1.0), (1.5, 0.5), (2.0, 1.5)],
        [(0.0, 0.5), (0.5, 0.5), (1.0, 2.0)],
        [(0.5, 0.5), (1.0, 1.0), (2.5, 0.5), (3.0, 1.0)],
        [(0.0, 2.5)],
    ]
    melody_m = 69
    for bar, chord in enumerate(MENU_CHORDS):
        b0 = bar * 4
        section_b = 8 <= bar < 16
        c.at(pad([m for m in chord], beat * 4.8, 0.7, bright=600.0), b0 - 0.4)
        c.at(pluck_bass(chord[0] - 12 if chord[0] >= 45 else chord[0], beat * 2.2, 0.7, 300.0), b0)
        if bar % 2 == 1:
            c.at(pluck_bass(chord[0] - 5 if chord[0] >= 45 else chord[0] + 7, beat * 1.2, 0.45, 300.0), b0 + 2.5)
        # soft marimba chord broken in quarters (B section: 8ths)
        tones = sorted(m + 12 for m in chord[1:])
        if section_b:
            for i in range(8):
                c.at(marimba(tones[[0, 1, 2, 1, 0, 2, 1, 2][i]], 0.6, 0.32), b0 + i * 0.5)
        else:
            for i in range(4):
                c.at(marimba(tones[i % 3], 0.8, 0.3), b0 + i)
        # curious kalimba melody: strong beats land on chord tones, weak ones step
        if bar % 4 != 3 or section_b:
            pattern = rhythms[(bar + (1 if section_b else 0)) % 4]
            chord_pcs = {(m % 12) for m in chord}
            for k, (pos, dur) in enumerate(pattern):
                if pos % 1.0 == 0.0:
                    cands = [m for m in range(62, 82) if m % 12 in chord_pcs]
                    melody_m = min(cands, key=lambda m: (abs(m - melody_m) + rng.uniform(0, 3)))
                else:
                    melody_m = dorian_near(melody_m, 1 if rng.random() < 0.5 else -1)
                melody_m = int(np.clip(melody_m, 62, 81))
                c.at(kalimba(melody_m + (12 if section_b and k == 0 else 0), max(1.0, beat * dur * 1.6), 0.6), b0 + pos)
        # light percussion: off-beat shaker, a wood tick on 4
        for e in range(8):
            if e % 2 == 1:
                c.at(shaker(rng, 0.12), b0 + e * 0.5)
        c.at(woodblock(rng, 700, 0.18), b0 + 3)
        if bar % 4 == 2:
            c.at(log_drum(57, 0.22), b0 + 2.5)
    x = reverb(c.buf, rng, 2.0, 0.35, True, 3000.0)
    return master_loop(x, 0.8)


# --------------------------------------------------------------------------- stingers

def gen_sting_flood() -> np.ndarray:
    rng = np.random.default_rng(606)
    c = Canvas(3.0, False, RUN_BPM)
    beat = 60.0 / RUN_BPM
    c.add(swell(rng, 0.6, 300, 5000), 0.0, 0.35)
    for i in range(4):
        c.add(taiko(rng, 0.6 + 0.1 * i, 150 - 8 * i, 0.6), i * beat * 0.25)
    for off, m, d in WARN_MOTIF:
        c.add(brass(m, beat * d, 0.7, 1800.0), 0.6 + c.beat(off))
        c.add(brass(m - 12, beat * d, 0.5, 1000.0), 0.6 + c.beat(off))
    c.add(kick(1.0, 90, 36, 1.4), 0.6)
    c.add(dist_bass(38, 1.2, 0.8), 0.6)
    x = reverb(c.buf, rng, 1.4, 0.3, False)
    return master_oneshot(x, 1.6)


def gen_sting_boss() -> np.ndarray:
    rng = np.random.default_rng(707)
    c = Canvas(3.8, False)
    c.add(kick(1.0, 60, 28, 2.5), 0.0)
    c.add(taiko(rng, 1.0, 110, 1.4), 0.0)
    c.add(gong(rng, 38, 3.2, 0.5), 0.02)
    c.add(brass(38 + 12, 2.2, 0.7, 800.0), 0.05)
    c.add(brass(44 + 12, 2.2, 0.55, 800.0), 0.05)   # tritone above D: dread
    c.add(brass(38, 2.2, 0.5, 500.0), 0.05)
    c.add(taiko(rng, 0.7, 120, 1.0), 1.1)
    c.add(taiko(rng, 0.9, 105, 1.2), 1.5)
    x = reverb(c.buf, rng, 2.0, 0.4, False, 2500.0)
    return master_oneshot(x, 1.4)


def gen_sting_king() -> np.ndarray:
    rng = np.random.default_rng(808)
    c = Canvas(3.2, False)
    # bright D-major/Lydian flourish (the one major moment in the score)
    run = [62, 66, 69, 74, 76, 78, 81, 86]
    for i, m in enumerate(run):
        c.add(marimba(m, 0.7, 0.55 + 0.04 * i), 0.06 * i)
        c.add(kalimba(m + 12 if i >= 5 else m, 1.2, 0.3), 0.06 * i + 0.01)
    for m in (62, 66, 69, 74):
        c.add(brass(m, 1.6, 0.35, 1600.0), 0.5)
    c.add(gong(rng, 50, 2.6, 0.45), 0.5)
    c.add(taiko(rng, 0.8, 160, 0.8), 0.5)
    c.add(kick(0.9, 100, 40, 0.8), 0.5)
    x = reverb(c.buf, rng, 1.8, 0.35, False)
    return master_oneshot(x, 1.2)


def gen_sting_extinct() -> np.ndarray:
    rng = np.random.default_rng(909)
    c = Canvas(4.6, False)
    # slow descending Phrygian kalimba phrase over a fading dark pad
    phrase = [(0.0, 74), (0.45, 70), (0.9, 69), (1.5, 65), (2.1, 63), (2.9, 62)]
    for at, m in phrase:
        c.add(kalimba(m, 1.6, 0.7), at)
        c.add(kalimba(m - 12, 1.6, 0.3), at + 0.02)
    c.add(pad([38, 50, 53, 57], 4.4, 0.8, 450.0), 0.0)
    c.add(pad([39, 51, 55], 1.6, 0.5, 450.0), 1.4)
    c.add(gong(rng, 38, 3.0, 0.35), 2.9)
    x = reverb(c.buf, rng, 2.2, 0.45, False, 2500.0)
    return master_oneshot(x, 0.6)


PIECES = [
    ("menu_theme", gen_menu, True),
    ("run_base", gen_run_base, True),
    ("run_tension", gen_run_tension, True),
    ("run_flood", gen_run_flood, True),
    ("run_boss", gen_run_boss, True),
    ("sting_flood", gen_sting_flood, False),
    ("sting_boss", gen_sting_boss, False),
    ("sting_king", gen_sting_king, False),
    ("sting_extinct", gen_sting_extinct, False),
]


def main() -> int:
    os.makedirs(OUT_DIR, exist_ok=True)
    total = 0
    ok_all = True
    stem_len = set()
    for name, fn, loop in PIECES:
        x = fn()
        ok, line = analyse(name, x, loop)
        ok_all &= ok
        size = write_wav(name, x, loop)
        total += size
        if name.startswith("run_"):
            stem_len.add(len(x))
        print(f"{line}  {size / 1024:7.0f} KiB")
    print(f"stems equal length: {len(stem_len) == 1} ({sorted(stem_len)} samples)")
    print(f"total {total / 1024 / 1024:.2f} MiB")
    return 0 if ok_all and len(stem_len) == 1 else 1


if __name__ == "__main__":
    sys.exit(main())
