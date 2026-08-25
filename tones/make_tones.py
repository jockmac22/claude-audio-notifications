#!/usr/bin/env python3
"""
Robot-buddy notification tones.

A small FM-bell voice (soft sine carrier + fast-decaying modulator for the
attack sparkle, gentle vibrato, short plate reverb). Melodic, non-abrasive,
reads as "a friendly machine saying something you understand".

Positive tones: major intervals, rising contours.
Negative tones: minor intervals, falling contours.
Punctuation is carried by the final gesture:
  !  -> firm landing on a held, resolved note
  ?  -> final note glides upward, unresolved
  .  -> flat, steady, quiet
"""

import numpy as np
import wave
import os

SR = 48000
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "wav")

# Global transpose in octaves; fractions allowed. -1.5 = an octave and a tritone down.
TRANSPOSE = -1.5

# Global time scale applied to note starts, lengths and decays. 0.5 = half as long.
TIME = 0.25


def hz(name):
    """Note name -> frequency (A4 = 440), shifted by TRANSPOSE octaves."""
    steps = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    letter, rest = name[0], name[1:]
    semis = steps[letter]
    while rest and rest[0] in "#b":
        semis += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    octave = int(rest)
    return 440.0 * 2 ** ((semis + 12 * (octave - 4 + TRANSPOSE)) / 12)


def voice(freq, dur, amp=1.0, decay=0.35, bright=1.0, glide_cents=0.0,
          glide_start=0.45, vib=0.004, wobble=0.0, tail=0.9):
    """One FM-bell note. Returns a buffer of length dur+tail seconds."""
    n = int((dur + tail) * SR)
    t = np.arange(n) / SR

    # --- pitch contour: vibrato, optional upward glide, optional instability
    g = np.clip((t - dur * glide_start) / max(dur * (1 - glide_start), 1e-6), 0, 1)
    g = g ** 1.6                                     # ease-in bend
    cents = glide_cents * g
    vibrato = vib * np.sin(2 * np.pi * (5.2 / TIME) * t) * np.clip(t / (0.12 * TIME), 0, 1)
    if wobble:
        vibrato = vibrato + wobble * np.sin(2 * np.pi * (3.1 / TIME) * t) * \
            np.clip((t - 0.05 * TIME) / (0.2 * TIME), 0, 1)
    f = freq * (2 ** (cents / 1200)) * (1 + vibrato)
    phase = 2 * np.pi * np.cumsum(f) / SR

    # --- FM: modulator at 2f, index decays fast -> bell-like strike, then pure
    idx = 1.9 * bright * np.exp(-t / (0.055 * TIME))
    mod = np.sin(2 * phase)
    sig = np.sin(phase + idx * mod)

    # a whisper of the octave and twelfth for air
    sig += 0.18 * np.sin(2 * phase) * np.exp(-t / (decay * 0.45))
    sig += 0.06 * np.sin(3 * phase) * np.exp(-t / (decay * 0.25))

    # --- amplitude envelope: soft attack, exponential body, clean fade
    atk = max(int(0.010 * TIME * SR), int(0.004 * SR))   # floor keeps it click-free
    env = np.exp(-t / decay)
    env[:atk] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(atk) / atk)
    fade = max(int(0.030 * TIME * SR), int(0.008 * SR))
    env[-fade:] *= np.linspace(1, 0, fade)

    return sig * env * amp


def sequence(notes, total=None):
    """notes: list of (start_seconds, kwargs for voice). Scaled by TIME."""
    scaled = []
    for start, kw in notes:
        kw = dict(kw)
        kw["dur"] = kw["dur"] * TIME
        kw["decay"] = kw["decay"] * TIME
        kw["tail"] = kw.get("tail", 0.9) * TIME
        scaled.append((start * TIME, kw))
    notes = scaled
    length = int(((total * TIME if total else (max(s for s, _ in notes) + 1.6)) * SR))
    buf = np.zeros(length)
    for start, kw in notes:
        v = voice(**kw)
        i = int(start * SR)
        end = min(i + len(v), length)
        buf[i:end] += v[: end - i]
    return buf


def reverb(x, wet=0.16, rt=0.55):
    """Tiny exponentially-decaying-noise plate. Keeps things soothing."""
    n = int(rt * TIME * SR)
    rng = np.random.default_rng(7)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / (0.16 * TIME * SR))
    ir[: int(0.008 * SR)] = 0
    # dull the tail so it stays soft
    b = 0.0
    for i in range(n):
        b += 0.22 * (ir[i] - b)
        ir[i] = b
    ir /= np.abs(ir).sum() or 1
    y = np.convolve(x, ir)[: len(x)]
    return (1 - wet) * x + wet * y * 6.0


def lowpass(x, cutoff=6500):
    a = 1 - np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a * (x[i] - acc)
        y[i] = acc
    return y


def finish(x, peak_db=-3.0, trim_db=-48):
    x = reverb(x)
    x = lowpass(x)
    # trim silent tail
    env = np.abs(x)
    thr = 10 ** (trim_db / 20) * env.max()
    last = np.nonzero(env > thr)[0]
    if len(last):
        x = x[: last[-1] + int(0.04 * TIME * SR)]
    f = max(int(0.025 * TIME * SR), int(0.008 * SR))
    if len(x) > f:
        x[-f:] *= np.linspace(1, 0, f)
    x = x - np.mean(x)                       # kill DC
    x *= (10 ** (peak_db / 20)) / max(np.abs(x).max(), 1e-9)
    return x


def save(name, x):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".wav")
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"{name:22s} {len(x)/SR:5.2f}s  peak {20*np.log10(np.abs(x).max()):.1f} dBFS")


# ---------------------------------------------------------------- the tones

# 1. Action complete (!) — C major, ascending, lands resolved on the octave.
save("positive_action-complete", finish(sequence([
    (0.00, dict(freq=hz("C5"), dur=0.10, amp=0.55, decay=0.16, bright=0.9)),
    (0.09, dict(freq=hz("E5"), dur=0.10, amp=0.62, decay=0.16, bright=0.95)),
    (0.18, dict(freq=hz("G5"), dur=0.10, amp=0.70, decay=0.18, bright=1.0)),
    (0.27, dict(freq=hz("C6"), dur=0.55, amp=1.00, decay=0.40, bright=1.15)),
    (0.27, dict(freq=hz("G5"), dur=0.55, amp=0.30, decay=0.40, bright=0.7)),
], total=1.8)))

# 2. Input required (?) — major, rises, ends on an unresolved 9th bending up.
save("positive_input-required", finish(sequence([
    (0.00, dict(freq=hz("C5"), dur=0.11, amp=0.60, decay=0.16, bright=0.9)),
    (0.11, dict(freq=hz("G5"), dur=0.11, amp=0.70, decay=0.18, bright=1.0)),
    (0.23, dict(freq=hz("D6"), dur=0.42, amp=0.95, decay=0.34, bright=1.1,
                glide_cents=170, glide_start=0.35)),
    (0.23, dict(freq=hz("A5"), dur=0.42, amp=0.22, decay=0.30, bright=0.7,
                glide_cents=170, glide_start=0.35)),
], total=1.6)))

# 3. In process (.) — flat, quiet, steady: two soft pulses, no contour.
save("positive_in-process", finish(sequence([
    (0.00, dict(freq=hz("G5"), dur=0.14, amp=0.75, decay=0.13, bright=0.55)),
    (0.17, dict(freq=hz("G5"), dur=0.32, amp=0.62, decay=0.22, bright=0.5)),
    (0.17, dict(freq=hz("C6"), dur=0.32, amp=0.12, decay=0.18, bright=0.4)),
], total=1.3), peak_db=-9.0))

# 4. Action failed (!) — A minor, descending, firm landing on an A-minor dyad.
save("negative_action-failed", finish(sequence([
    (0.00, dict(freq=hz("A5"), dur=0.10, amp=0.62, decay=0.16, bright=0.85)),
    (0.10, dict(freq=hz("E5"), dur=0.10, amp=0.66, decay=0.17, bright=0.8)),
    (0.20, dict(freq=hz("C5"), dur=0.10, amp=0.70, decay=0.18, bright=0.75)),
    (0.30, dict(freq=hz("A4"), dur=0.62, amp=1.00, decay=0.46, bright=0.8)),
    (0.30, dict(freq=hz("C5"), dur=0.62, amp=0.42, decay=0.42, bright=0.6)),
], total=2.0)))

# 5. System failed (?) — minor, falls then bends up, slight wobble: uncertain.
save("negative_system-failed", finish(sequence([
    (0.00, dict(freq=hz("E5"), dur=0.12, amp=0.60, decay=0.17, bright=0.8)),
    (0.13, dict(freq=hz("C5"), dur=0.12, amp=0.58, decay=0.18, bright=0.7)),
    (0.27, dict(freq=hz("B4"), dur=0.50, amp=0.88, decay=0.40, bright=0.75,
                glide_cents=150, glide_start=0.40, wobble=0.006)),
    (0.27, dict(freq=hz("E5"), dur=0.50, amp=0.20, decay=0.34, bright=0.55,
                glide_cents=150, glide_start=0.40, wobble=0.006)),
], total=1.8), peak_db=-4.5))
