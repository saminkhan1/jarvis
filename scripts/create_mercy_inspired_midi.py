#!/usr/bin/env python3
from pathlib import Path
import struct

PPQ = 480
BPM = 140
BARS = 35  # 35 bars * 4 beats at 140 BPM = 60 seconds
OUT = Path('/Users/saminkhan1/Documents/jarvis/garageband_mercy_inspired_two_instruments.mid')


def vlq(n: int) -> bytes:
    bytes_ = [n & 0x7F]
    n >>= 7
    while n:
        bytes_.insert(0, (n & 0x7F) | 0x80)
        n >>= 7
    return bytes(bytes_)


def event(delta, data):
    return vlq(delta) + bytes(data)


def meta(delta, typ, data):
    return vlq(delta) + bytes([0xFF, typ]) + vlq(len(data)) + bytes(data)


def track(events):
    body = b''.join(events) + meta(0, 0x2F, b'')
    return b'MTrk' + struct.pack('>I', len(body)) + body


def add_note(events_abs, tick, channel, note, velocity, dur):
    events_abs.append((tick, [0x90 | channel, note, velocity]))
    events_abs.append((tick + dur, [0x80 | channel, note, 0]))


def compile_abs(events_abs):
    # Sort note-offs before note-ons at same tick to avoid overlap glitches.
    events_abs.sort(key=lambda x: (x[0], 0 if x[1][0] & 0xF0 == 0x80 else 1))
    out, last = [], 0
    for tick, data in events_abs:
        out.append(event(tick - last, data))
        last = tick
    return out

# Track 0: conductor / markers
us_per_quarter = int(60_000_000 / BPM)
conductor = [
    meta(0, 0x03, b'AURA - original Mercy-inspired two-instrument beat'),
    meta(0, 0x51, list(us_per_quarter.to_bytes(3, 'big'))),
    meta(0, 0x58, [4, 2, 24, 8]),
]

# Track 1: trap drums, MIDI channel 10 (zero-index channel 9)
drum_abs = []
# GM percussion notes: kick 36, snare/clap 38/39, closed hat 42, open hat 46
for bar in range(BARS):
    base = bar * 4 * PPQ
    # Hats: rolling eighths with occasional sixteenth pickups.
    for step in range(8):
        tick = base + step * (PPQ // 2)
        vel = 62 if step % 2 else 78
        add_note(drum_abs, tick, 9, 42, vel, PPQ // 8)
    if bar % 2 == 1:
        for off in [PPQ * 3 + PPQ // 4, PPQ * 3 + PPQ // 2, PPQ * 3 + PPQ * 3 // 4]:
            add_note(drum_abs, base + off, 9, 42, 50, PPQ // 12)
    # Backbeat clap/snare on 2 and 4.
    for beat in [1, 3]:
        add_note(drum_abs, base + beat * PPQ, 9, 39, 96, PPQ // 6)
        add_note(drum_abs, base + beat * PPQ, 9, 38, 70, PPQ // 6)
    # Syncopated kick pattern, varied every fourth bar.
    kicks = [0, PPQ * 3 // 4, PPQ * 2, PPQ * 2 + PPQ // 2, PPQ * 3 + PPQ * 3 // 4]
    if bar % 4 == 3:
        kicks += [PPQ + PPQ // 2, PPQ * 3 + PPQ // 4]
    for off in kicks:
        add_note(drum_abs, base + off, 9, 36, 110, PPQ // 5)

drum_events = [meta(0, 0x03, b'Instrument 1 - Trap drum kit'), event(0, [0xC0 | 9, 0])] + compile_abs(drum_abs)

# Track 2: dark synth bass/pluck, MIDI channel 1 (zero-index channel 0)
bass_abs = []
# Program 39 = Synth Bass 1 in General MIDI; GarageBand will map it to a software instrument.
# Minor, modal, half-step movement evokes dark trap without copying the source melody.
roots = [37, 37, 34, 36]  # C#2, C#2, A#1, C2
for bar in range(BARS):
    base = bar * 4 * PPQ
    root = roots[bar % 4]
    phrase = [
        (0, root, 112, PPQ),
        (PPQ + PPQ // 2, root + 7, 92, PPQ // 2),
        (PPQ * 2, root, 108, PPQ // 2),
        (PPQ * 2 + PPQ * 3 // 4, root + 10, 82, PPQ // 4),
        (PPQ * 3, root - 2, 102, PPQ),
    ]
    if bar % 8 in (6, 7):
        phrase.append((PPQ * 3 + PPQ // 2, root + 12, 76, PPQ // 4))
    for off, note, vel, dur in phrase:
        add_note(bass_abs, base + off, 0, note, vel, dur)

bass_events = [meta(0, 0x03, b'Instrument 2 - Dark synth bass/pluck'), event(0, [0xC0 | 0, 38])] + compile_abs(bass_abs)

header = b'MThd' + struct.pack('>IHHH', 6, 1, 3, PPQ)
OUT.write_bytes(header + track(conductor) + track(drum_events) + track(bass_events))
print(f'Wrote {OUT}')
print(f'Duration: {BARS * 4 * 60 / BPM:.1f}s, tempo: {BPM} BPM, tracks: drums + synth bass')
