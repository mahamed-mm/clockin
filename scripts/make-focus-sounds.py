"""Synthesises Clockin's focus sounds as seamless WAV loops.

Four sounds to keep you company through a focus session, made from scratch
so there's nothing to license: a kitchen timer's tick-tock, brown noise,
rain and a fireplace. Rain and the fireplace are two layers each, a bed and
the drops or crackles on top, with lengths that share no factor: played
together they only line up again after half an hour or so, so a session
never hears the same few seconds twice.

Each layer is rendered a little longer than its loop and the overhang is
crossfaded back over the start (equal power, as the layers are noise), so
the last sample runs straight into the first. Levels sit around -20 dBFS
RMS, played summed at full volume. Standard library only; see
make-focus-sounds.sh for the conversion to CAF.
"""
import math
import random
import struct
import sys
import wave

RATE = 32_000
FADE = 2.0  # Seconds of overhang crossfaded over the start.


# MARK: Filters

class OnePole:
    """A one-pole low-pass at `cutoff` Hz."""

    def __init__(self, cutoff):
        self.a = math.exp(-2 * math.pi * cutoff / RATE)
        self.y = 0.0

    def __call__(self, x):
        self.y = (1 - self.a) * x + self.a * self.y
        return self.y


class HighPass:
    """A one-pole high-pass at `cutoff` Hz."""

    def __init__(self, cutoff):
        self.low = OnePole(cutoff)

    def __call__(self, x):
        return x - self.low(x)


class BandPass:
    """A biquad band-pass (constant peak gain) at `centre` Hz."""

    def __init__(self, centre, q):
        w = 2 * math.pi * centre / RATE
        alpha = math.sin(w) / (2 * q)
        a0 = 1 + alpha
        self.b0, self.b2 = alpha / a0, -alpha / a0
        self.a1, self.a2 = -2 * math.cos(w) / a0, (1 - alpha) / a0
        self.x1 = self.x2 = self.y1 = self.y2 = 0.0

    def __call__(self, x):
        y = self.b0 * x + self.b2 * self.x2 - self.a1 * self.y1 - self.a2 * self.y2
        self.x2, self.x1 = self.x1, x
        self.y2, self.y1 = self.y1, y
        return y


class Drift:
    """A slow random wander between `low` and `high`, changing about every `period` seconds."""

    def __init__(self, rand, low, high, period):
        self.rand, self.low, self.high = rand, low, high
        self.step = 1 / (period * RATE)
        self.at, self.start, self.end = 0.0, rand.uniform(low, high), rand.uniform(low, high)

    def __call__(self):
        self.at += self.step
        if self.at >= 1:
            self.at, self.start, self.end = 0.0, self.end, self.rand.uniform(self.low, self.high)
        eased = 0.5 - 0.5 * math.cos(math.pi * self.at)
        return self.start + (self.end - self.start) * eased


# MARK: Layers

def brown_noise(seconds, seed):
    """Brown noise: white noise, integrated with a leak, then softened."""
    rand = random.Random(seed)
    level, soft, dc = 0.0, OnePole(900), HighPass(20)
    out = []
    for _ in range(int(seconds * RATE)):
        level = (level + 0.02 * rand.uniform(-1, 1)) / 1.02
        out.append(dc(soft(level * 3.5)))
    return out


def rain_bed(seconds, seed):
    """Steady rain: a wash of band-limited noise that swells a little."""
    rand = random.Random(seed)
    hiss, body, dc = BandPass(4200, 0.5), BandPass(900, 0.7), HighPass(80)
    swell = Drift(rand, 0.75, 1.0, 5.0)
    previous = 0.0
    out = []
    for _ in range(int(seconds * RATE)):
        white = rand.uniform(-1, 1)
        # A touch of pink: average with the last sample to tame the top.
        pinkish = 0.6 * white + 0.4 * previous
        previous = white
        out.append(dc(swell() * (0.8 * hiss(pinkish) + 0.5 * body(pinkish))))
    return out


def rain_drops(seconds, seed):
    """Drops on a window and a sill: short pitched taps at random, now and then a heavier drip."""
    rand = random.Random(seed)
    total = int(seconds * RATE)
    out = [0.0] * total
    at = 0.0
    while True:
        at += rand.expovariate(28)  # About 28 drops a second.
        start = int(at * RATE)
        if start >= total:
            break
        heavy = rand.random() < 0.06
        amp = rand.uniform(0.25, 1.0) * (1.8 if heavy else 1.0)
        pitch = rand.uniform(1800, 5200) if not heavy else rand.uniform(700, 1400)
        decay = rand.uniform(0.002, 0.006) * (2.5 if heavy else 1.0)
        noise_rand = random.Random(rand.random())
        for i in range(int(decay * 7 * RATE)):
            t = i / RATE
            ring = math.sin(2 * math.pi * pitch * t)
            tap = 0.5 * noise_rand.uniform(-1, 1) * math.exp(-t / (decay * 0.4))
            out[(start + i) % total] += amp * (0.6 * ring + tap) * math.exp(-t / decay)
    return out


def fire_bed(seconds, seed):
    """A fire's roar: low, flickering rumble with a soft breath of air above it."""
    rand = random.Random(seed)
    level, rumble, air, dc = 0.0, OnePole(260), BandPass(1600, 0.6), HighPass(30)
    flicker = Drift(rand, 0.55, 1.0, 0.8)
    out = []
    for _ in range(int(seconds * RATE)):
        white = rand.uniform(-1, 1)
        level = (level + 0.02 * white) / 1.02
        low = rumble(level * 6)
        out.append(dc(flicker() * low + 0.06 * air(white)))
    return out


def fire_crackles(seconds, seed):
    """Crackles and pops: bright little bursts, often in clusters, and the odd deep pop of sap."""
    rand = random.Random(seed)
    total = int(seconds * RATE)
    out = [0.0] * total
    at = 0.0
    while True:
        at += rand.expovariate(1.6)  # A cluster about every 0.6 s.
        cluster = int(at * RATE)
        if cluster >= total:
            break
        for k in range(1 if rand.random() < 0.5 else rand.randint(2, 6)):
            start = cluster + int(rand.uniform(0, 0.12) * RATE) * k
            amp = rand.uniform(0.2, 1.0)
            length = rand.uniform(0.001, 0.006)
            bright = HighPass(rand.uniform(1500, 4000))
            noise_rand = random.Random(rand.random())
            for i in range(int(length * 6 * RATE)):
                t = i / RATE
                burst = bright(noise_rand.uniform(-1, 1)) * math.exp(-t / length)
                out[(start + i) % total] += amp * burst
        if rand.random() < 0.08:
            # A deep pop: a short knock with a falling pitch.
            start, phase = cluster, 0.0
            for i in range(int(0.05 * RATE)):
                t = i / RATE
                phase += 2 * math.pi * (180 - 900 * t) / RATE
                out[(start + i) % total] += 0.8 * math.sin(phase) * math.exp(-t / 0.012)
    return out


def tick_tock():
    """A wind-up kitchen timer's escapement: tick on the second, a duller tock on the next, two seconds a loop."""
    total = 2 * RATE
    out = [0.0] * total

    def strike(at, ring, body, amp, seed):
        rand = random.Random(seed)
        start = int(at * RATE)
        bright = HighPass(2500)
        for i in range(int(0.06 * RATE)):
            t = i / RATE
            click = bright(rand.uniform(-1, 1)) * math.exp(-t / 0.0015)
            ping = 0.5 * math.sin(2 * math.pi * ring * t) * math.exp(-t / 0.008)
            knock = 0.4 * math.sin(2 * math.pi * body * t) * math.exp(-t / 0.02)
            out[start + i] += amp * (click + ping + knock)

    # Off the loop point, so the wrap falls in the quiet between strikes.
    strike(0.25, 3400, 520, 1.0, seed=1)
    strike(1.25, 2600, 430, 0.85, seed=2)
    return out


# MARK: Loops and levels

def looped(make, seconds, seed):
    """Renders `seconds` plus an overhang and folds the overhang over the start, equal power."""
    raw = make(seconds + FADE, seed)
    n, fade = int(seconds * RATE), int(FADE * RATE)
    out = raw[:n]
    for i in range(fade):
        x = i / fade
        out[i] = raw[i] * math.sin(0.5 * math.pi * x) + raw[n + i] * math.cos(0.5 * math.pi * x)
    return out


def from_quiet_point(samples):
    """The same loop, turned to start where it's nearest silence and moving least.

    IMA4 starts its first packet from nothing and takes a few samples to
    catch up, which would click on a slow waveform like brown noise. A loop
    has no real start, so it can start where that costs nothing.
    """
    n = len(samples)
    at = min(range(n), key=lambda i: abs(samples[i]) + abs(samples[(i + 1) % n] - samples[i]))
    return samples[at:] + samples[:at]


def rms(samples):
    return math.sqrt(sum(s * s for s in samples) / len(samples))


def scaled(samples, dbfs):
    """Scaled to `dbfs` RMS, with a soft limit on any peak past -1 dBFS."""
    gain = 10 ** (dbfs / 20) / rms(samples)
    ceiling = 10 ** (-1 / 20)
    return [ceiling * math.tanh(s * gain / ceiling) for s in samples]


def seam(samples):
    """How the step from the last sample to the first compares with the loop's typical step."""
    steps = [abs(b - a) for a, b in zip(samples, samples[1:])]
    typical = sum(steps) / len(steps)
    return abs(samples[0] - samples[-1]) / typical if typical else 0.0


def write(path, samples):
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in samples))


# Layer lengths: rain 47 + 37 s, fire 53 + 41 s. Coprime, so each pair
# repeats only after 29 and 36 minutes.
LAYERS = {
    "focus-tick-tock": (lambda: tick_tock(), -24),
    "focus-brown-noise": (lambda: looped(brown_noise, 47, 3), -20),
    "focus-rain": (lambda: looped(rain_bed, 47, 5), -22),
    "focus-rain-drops": (lambda: looped(rain_drops, 37, 7), -26),
    "focus-fireplace": (lambda: looped(fire_bed, 53, 11), -21),
    "focus-fireplace-crackle": (lambda: looped(fire_crackles, 41, 13), -27),
}

if __name__ == "__main__":
    folder = sys.argv[1] if len(sys.argv) > 1 else "."
    for name, (make, level) in LAYERS.items():
        samples = from_quiet_point(scaled(make(), level))
        write(f"{folder}/{name}.wav", samples)
        print(f"{name}: {len(samples) / RATE:.1f} s, {20 * math.log10(rms(samples)):.1f} dBFS RMS, "
              f"seam step {seam(samples):.2f}x typical")
