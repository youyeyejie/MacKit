#!/usr/bin/env python3
"""Original soft, dry two-tap snip; rounded transients, no harsh metallic hiss."""
from pathlib import Path
import math
import random
import struct
import wave

rate, duration = 44100, 0.18
rng = random.Random(20261028)
samples = []
filtered_noise = 0.0
for i in range(round(rate * duration)):
    t = i / rate
    filtered_noise += 0.18 * (rng.uniform(-1, 1) - filtered_noise)
    value = 0.0
    for onset, length, gain, frequency in [(0.008, 0.065, 0.45, 1050), (0.082, 0.085, 0.60, 780)]:
        age = t - onset
        if 0 <= age < length:
            attack = 1 - math.exp(-age / 0.0018)
            release = (1 - age / length) ** 2
            envelope = attack * math.exp(-age / 0.013) * release
            # A slightly falling wooden tap, with a quiet rounded brushing texture.
            phase = 2 * math.pi * frequency * (age - 1.4 * age * age)
            tone = math.sin(phase) + 0.18 * math.sin(1.57 * phase)
            value += gain * envelope * (0.82 * tone + 0.18 * filtered_noise)
    samples.append(max(-32767, min(32767, round(value * 32767))))
path = Path(__file__).resolve().parents[1] / 'MacKit/Resources/Cut.wav'
path.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(path), 'wb') as out:
    out.setparams((1, 2, rate, 0, 'NONE', 'not compressed'))
    out.writeframes(struct.pack('<' + 'h' * len(samples), *samples))
print(f'{path.name}: {len(samples) / rate:.2f}s, {path.stat().st_size} bytes')
