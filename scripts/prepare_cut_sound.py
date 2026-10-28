#!/usr/bin/env python3
"""Synthesize an original, quiet two-part scissors snip. No external samples."""
from pathlib import Path
import math
import random
import struct
import wave

rate, duration = 22050, 0.19
rng = random.Random(20261028)
samples = []
previous = 0.0
for i in range(round(rate * duration)):
    t = i / rate
    noise = rng.uniform(-1, 1)
    # High-pass texture with a tiny metallic component; attacks/tails are smooth.
    texture = (noise - previous) * 0.5
    previous = noise
    value = 0.0
    for onset, length, gain in [(0.008, 0.055, 0.52), (0.090, 0.075, 0.72)]:
        age = t - onset
        if 0 <= age < length:
            envelope = math.sin(math.pi * age / length) ** 2 * math.exp(-3 * age / length)
            value += gain * envelope * (texture + 0.12 * math.sin(2 * math.pi * 3300 * age))
    samples.append(max(-32767, min(32767, round(value * 32767))))
path = Path(__file__).resolve().parents[1] / 'MacKit/Resources/Cut.wav'
path.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(path), 'wb') as out:
    out.setparams((1, 2, rate, 0, 'NONE', 'not compressed'))
    out.writeframes(struct.pack('<' + 'h' * len(samples), *samples))
print(f'{path.name}: {len(samples) / rate:.2f}s, {path.stat().st_size} bytes')
