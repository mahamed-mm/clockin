"""Synthesises Clockin's kitchen-timer sounds as WAV files.

Four short mechanical sounds, made from scratch so there's nothing to
license: a ratchet click for each detent of the dial, a wind-up and click
for Start, a soft clunk for Pause and a lighter click for Resume. They're
played as system sounds, at the ringer's volume, so they're kept quiet
(about -18 dBFS). Standard library only; see make-sounds.sh for the
conversion to CAF.
"""
import math
import random
import struct
import sys
import wave

RATE = 44_100
PEAK = 0.126  # -18 dBFS


def tick(samples, at, amp, ring, decay=0.006, noise=0.6, seed=0):
    """A metal-on-metal tick at `at` seconds: a filtered noise burst and a short ring at `ring` Hz."""
    rand = random.Random(seed)
    start = int(at * RATE)
    length = int(decay * 8 * RATE)
    previous = 0.0
    for i in range(length):
        t = i / RATE
        if start + i >= len(samples):
            break
        # High-passed noise: the scrape of the pawl.
        n = rand.uniform(-1, 1)
        high = n - previous
        previous = n
        burst = noise * high * math.exp(-t / (decay * 0.5))
        ping = math.sin(2 * math.pi * ring * t) * math.exp(-t / decay)
        samples[start + i] += amp * (burst + ping)


def thud(samples, at, amp, frequency, drop, decay):
    """A low knock: a sine sliding down from `frequency` by `drop`, dying in `decay` seconds."""
    start = int(at * RATE)
    phase = 0.0
    for i in range(int(decay * 6 * RATE)):
        t = i / RATE
        if start + i >= len(samples):
            break
        f = frequency - drop * min(1.0, t / decay)
        phase += 2 * math.pi * f / RATE
        attack = min(1.0, t / 0.002)
        samples[start + i] += amp * attack * math.sin(phase) * math.exp(-t / decay)


def ratchet():
    s = [0.0] * int(0.045 * RATE)
    tick(s, 0.0, 1.0, 3200, seed=1)
    tick(s, 0.009, 0.5, 4300, decay=0.004, seed=2)
    return s


def wind_up():
    s = [0.0] * int(0.46 * RATE)
    at = 0.0
    gaps = [0.062, 0.054, 0.047, 0.041, 0.036, 0.032, 0.029]
    for k, gap in enumerate(gaps):
        tick(s, at, 0.45 + 0.07 * k, 3000 + 120 * k, decay=0.005, seed=10 + k)
        tick(s, at + 0.008, 0.25, 4200, decay=0.003, seed=30 + k)
        at += gap
    # The spring catches: a firmer click with a little body.
    tick(s, at + 0.02, 1.0, 1900, decay=0.009, noise=0.8, seed=50)
    thud(s, at + 0.02, 0.5, 210, 60, 0.03)
    return s


def clunk():
    s = [0.0] * int(0.16 * RATE)
    tick(s, 0.0, 0.35, 1500, decay=0.006, noise=0.9, seed=60)
    thud(s, 0.002, 1.0, 150, 55, 0.045)
    return s


def click():
    s = [0.0] * int(0.06 * RATE)
    tick(s, 0.0, 0.8, 3600, decay=0.005, seed=70)
    thud(s, 0.001, 0.3, 260, 40, 0.012)
    return s


def write(path, samples):
    peak = max(abs(v) for v in samples) or 1
    scale = PEAK * 32_767 / peak
    # A 2 ms fade at the end, so nothing clicks off.
    fade = int(0.002 * RATE)
    for i in range(fade):
        samples[-1 - i] *= i / fade
    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", round(v * scale)) for v in samples))


SOUNDS = {"ratchet": ratchet, "wind-up": wind_up, "clunk": clunk, "click": click}

if __name__ == "__main__":
    folder = sys.argv[1]
    for name, make in SOUNDS.items():
        write(f"{folder}/timer-{name}.wav", make())
