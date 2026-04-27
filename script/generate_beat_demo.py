#!/usr/bin/env python3
import math
import random
import struct
import wave
from pathlib import Path

SR = 44100
DURATION = 30.0
BPM = 132
BEAT = 60.0 / BPM
SIXTEENTH = BEAT / 4.0
TOTAL_SAMPLES = int(SR * DURATION)
MASTER_GAIN = 0.72
SEED = 17

random.seed(SEED)


def clamp(x, lo=-1.0, hi=1.0):
    return lo if x < lo else hi if x > hi else x


def add_hit(buf, start_s, samples, gain=1.0):
    start = int(start_s * SR)
    if start >= len(buf):
        return
    for i, v in enumerate(samples):
        idx = start + i
        if idx >= len(buf):
            break
        buf[idx] += v * gain


def sine(freq, t):
    return math.sin(2.0 * math.pi * freq * t)


def kick(length=0.42):
    n = int(length * SR)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / SR
        env = math.exp(-8.5 * t)
        freq = 138.0 * math.exp(-10.0 * t) + 38.0
        phase += 2.0 * math.pi * freq / SR
        click = math.exp(-140.0 * t) * (random.random() * 2.0 - 1.0)
        body = math.sin(phase)
        out.append((body * 0.95 + click * 0.18) * env)
    return out


def snare(length=0.22):
    n = int(length * SR)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / SR
        noise_env = math.exp(-20.0 * t)
        tone_env = math.exp(-13.0 * t)
        noise = (random.random() * 2.0 - 1.0) * noise_env
        phase += 2.0 * math.pi * 188.0 / SR
        tone = math.sin(phase) * tone_env
        out.append(noise * 0.70 + tone * 0.45)
    return out


def hat(length=0.07):
    n = int(length * SR)
    out = []
    for i in range(n):
        t = i / SR
        env = math.exp(-55.0 * t)
        noise = (random.random() * 2.0 - 1.0)
        bright = noise - 0.55 * math.sin(2.0 * math.pi * 7200.0 * t)
        out.append(bright * env * 0.42)
    return out


def clap(length=0.18):
    n = int(length * SR)
    out = [0.0] * n
    offsets = [0.0, 0.012, 0.024]
    for off in offsets:
        shift = int(off * SR)
        for i in range(shift, n):
            t = (i - shift) / SR
            env = math.exp(-24.0 * t)
            out[i] += (random.random() * 2.0 - 1.0) * env * 0.24
    return out


def supersaw(freq, length, detune_cents=(-12, -5, 0, 6, 13)):
    n = int(length * SR)
    phases = [random.random() for _ in detune_cents]
    out = []
    for i in range(n):
        t = i / SR
        attack = min(1.0, t / 0.015)
        release = min(1.0, max(0.0, (length - t) / 0.22))
        env = (attack ** 0.8) * (release ** 1.4)
        s = 0.0
        for j, cents in enumerate(detune_cents):
            f = freq * (2.0 ** (cents / 1200.0))
            phases[j] = (phases[j] + f / SR) % 1.0
            saw = 2.0 * phases[j] - 1.0
            s += saw
        out.append((s / len(detune_cents)) * env * 0.22)
    return out


def bass_note(freq, length):
    n = int(length * SR)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / SR
        attack = min(1.0, t / 0.01)
        release = min(1.0, max(0.0, (length - t) / 0.12))
        env = attack * (release ** 1.8)
        wobble = 1.0 + 0.015 * math.sin(2.0 * math.pi * 5.2 * t)
        phase += 2.0 * math.pi * freq * wobble / SR
        tone = math.sin(phase) + 0.35 * math.sin(phase * 2.0)
        out.append(tone * env * 0.28)
    return out


def midi_to_freq(m):
    return 440.0 * (2.0 ** ((m - 69) / 12.0))


buf = [0.0] * TOTAL_SAMPLES

kick_s = kick()
snare_s = snare()
hat_s = hat()
clap_s = clap()

bars = int(DURATION / (BEAT * 4.0))
bar_len = BEAT * 4.0

for bar in range(bars):
    base = bar * bar_len
    for step in range(16):
        t = base + step * SIXTEENTH
        if step in (0, 6, 8, 11):
            add_hit(buf, t, kick_s, 1.0 if step in (0, 8) else 0.78)
        if step in (4, 12):
            add_hit(buf, t, snare_s, 0.90)
            add_hit(buf, t + 0.006, clap_s, 0.75)
        hat_gain = 0.18 if step % 2 == 0 else 0.12
        swing = 0.0 if step % 2 == 0 else 0.011
        add_hit(buf, t + swing, hat_s, hat_gain)
        if step in (3, 7, 10, 15):
            add_hit(buf, t + 0.02, hat_s, 0.08)

progression = [
    [57, 61, 64],   # A minor
    [53, 57, 60],   # F major
    [60, 64, 67],   # C major
    [55, 59, 62],   # G major
]

bass_roots = [33, 29, 36, 31]

for bar in range(bars):
    base = bar * bar_len
    chord = progression[bar % len(progression)]
    bass_root = bass_roots[bar % len(bass_roots)]

    chord_times = [0.0, BEAT * 2.0]
    chord_lengths = [BEAT * 1.7, BEAT * 1.5]
    chord_sets = [chord, [n + 12 for n in chord[:2]] + [chord[2]]]
    for ctime, clen, notes in zip(chord_times, chord_lengths, chord_sets):
        for note in notes:
            add_hit(buf, base + ctime, supersaw(midi_to_freq(note), clen), 1.0)

    bass_pattern = [0, 0, 7, 0, 12, 7, 0, -5]
    for idx, interval in enumerate(bass_pattern):
        note = bass_root + interval
        start = base + idx * (BEAT / 2.0)
        length = BEAT * (0.32 if idx % 2 == 0 else 0.22)
        add_hit(buf, start, bass_note(midi_to_freq(note), length), 1.0)

# gentle sidechain-style pumping
for i in range(TOTAL_SAMPLES):
    t = i / SR
    beat_pos = (t % BEAT) / BEAT
    pump = 0.60 + 0.40 * min(1.0, beat_pos / 0.33)
    buf[i] *= pump

# fade in/out
fade = int(SR * 0.03)
for i in range(fade):
    buf[i] *= i / fade
for i in range(fade):
    idx = TOTAL_SAMPLES - 1 - i
    buf[idx] *= i / fade

peak = max(max(buf), -min(buf), 1e-9)
scale = MASTER_GAIN / peak
pcm = bytearray()
for v in buf:
    s = int(clamp(v * scale) * 32767.0)
    pcm.extend(struct.pack('<h', s))

out_dir = Path('generated_audio')
out_dir.mkdir(exist_ok=True)
out_wav = out_dir / 'ninajirachi_inspired_beat_demo_30s.wav'
with wave.open(str(out_wav), 'wb') as wf:
    wf.setnchannels(1)
    wf.setsampwidth(2)
    wf.setframerate(SR)
    wf.writeframes(pcm)

print(out_wav)
print(f'duration_seconds={DURATION}')
print(f'bpm={BPM}')
print('format=wav_pcm_s16le_mono_44100')
