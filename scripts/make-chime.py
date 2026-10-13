"""Synthesises Clockin's end-of-session chime as a WAV file.

A warm two-note bell (G5 then E5, "ding-dong"), struck every three seconds,
eight times: 24 seconds that loop seamlessly, since the alarm repeats the
sound until it's stopped. Notification sounds must stay under 30 seconds,
so the same file serves the notification too. Standard library only; see
make-chime.sh for the conversion to CAF.
"""
import math
import struct
import sys
import wave

RATE = 22_050
PERIOD = 3.0       # seconds between strikes
STRIKES = 8
# A struck bell: partials above the note, the higher ones dying away faster.
PARTIALS = [  # (ratio, amplitude, decay in seconds)
    (1.0, 1.0, 1.6),
    (2.0, 0.45, 1.0),
    (2.76, 0.3, 0.7),
    (4.07, 0.16, 0.45),
    (5.4, 0.1, 0.3),
]
NOTES = [(783.99, 0.0), (659.26, 0.38)]  # G5 at once, E5 just after


def bell(t: float, frequency: float) -> float:
    if t < 0:
        return 0.0
    attack = min(1.0, t / 0.004)  # a 4 ms strike, no click
    return attack * sum(a * math.exp(-t / d) * math.sin(2 * math.pi * frequency * r * t)
                        for r, a, d in PARTIALS)


def main(path: str) -> None:
    length = int(RATE * PERIOD * STRIKES)
    samples = []
    for i in range(length):
        t = i / RATE
        # Only this strike and the one before can still be heard.
        strike = math.floor(t / PERIOD)
        value = 0.0
        for k in (strike, strike - 1):
            if 0 <= k < STRIKES:
                local = t - k * PERIOD
                value += sum(bell(local - offset, f) for f, offset in NOTES)
        # The last strike rings into the loop's start, as it would on repeat.
        if strike == 0:
            value += sum(bell(t + PERIOD - offset, f) for f, offset in NOTES)
        samples.append(value)
    peak = max(abs(s) for s in samples)
    scale = 0.7 * 32_767 / peak  # about -3 dBFS
    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", round(s * scale)) for s in samples))


if __name__ == "__main__":
    main(sys.argv[1])
