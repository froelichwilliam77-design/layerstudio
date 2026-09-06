#!/usr/bin/env python3
"""Regenerate LayerStudio synthetic WAV sample pack (CC0)."""
import math, struct, wave, os, random, sys

SR = 44100
ROOT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'samples')

def write_wav(path, samples, sr=SR):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, 'w') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        frames = b''.join(
            struct.pack('<h', max(-32767, min(32767, int(s * 32767))))
            for s in samples
        )
        w.writeframes(frames)

def env_exp(i, n, attack=0.01, decay=0.3):
    t = i / max(n, 1)
    a = min(1.0, t / max(attack, 1e-6))
    d = math.exp(-t / max(decay, 1e-6))
    return a * d

def tone(freq, dur, wave='sine', attack=0.01, decay=0.4, amp=0.6):
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        phase = 2 * math.pi * freq * t
        if wave == 'sine':
            s = math.sin(phase)
        elif wave == 'square':
            s = 1.0 if math.sin(phase) >= 0 else -1.0
        elif wave == 'saw':
            s = 2 * ((freq * t) % 1.0) - 1.0
        else:
            s = math.sin(phase)
        out.append(s * env_exp(i, n, attack, decay) * amp)
    return out

def noise_burst(dur, decay=0.08, amp=0.5, band=None):
    n = int(SR * dur)
    out, prev = [], 0.0
    for i in range(n):
        r = random.uniform(-1, 1)
        if band == 'low':
            prev = 0.9 * prev + 0.1 * r
            s = prev
        elif band == 'high':
            s = r - prev
            prev = 0.5 * prev + 0.5 * r
        else:
            s = r
        out.append(s * math.exp(-i / (SR * decay)) * amp)
    return out

def kick(dur=0.45):
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        f = 150 * math.exp(-t * 12) + 40
        s = math.sin(2 * math.pi * f * t) * math.exp(-t * 6) * 0.9
        if t < 0.01:
            s += random.uniform(-1, 1) * (1 - t / 0.01) * 0.4
        out.append(s)
    return out

def kick808():
    n = int(SR * 0.7)
    out = []
    for i in range(n):
        t = i / SR
        f = 80 * math.exp(-t * 4) + 35
        out.append(math.sin(2 * math.pi * f * t) * math.exp(-t * 3) * 0.95)
    return out

def snare(dur=0.35):
    body = tone(180, dur, 'sine', 0.001, 0.12, 0.4)
    noise = noise_burst(dur, 0.12, 0.55, 'high')
    n = max(len(body), len(noise))
    return [
        ((body[i] if i < len(body) else 0) + (noise[i] if i < len(noise) else 0)) * 0.8
        for i in range(n)
    ]

def hihat(dur=0.12, open_=False):
    return noise_burst(dur, 0.25 if open_ else 0.04, 0.35 if open_ else 0.28, 'high')

def clap(dur=0.3):
    base = noise_burst(dur, 0.1, 0.5, 'high')
    out = list(base)
    delay = int(0.02 * SR)
    for i, s in enumerate(base):
        if i + delay < len(out):
            out[i + delay] += s * 0.6
        else:
            out.append(s * 0.6)
    return [x * 0.7 for x in out]

def pluck(freq, dur, brightness=0.3):
    n = int(SR * dur)
    buf = [random.uniform(-1, 1) for _ in range(max(2, int(SR / freq)))]
    out, idx = [], 0
    for i in range(n):
        s = buf[idx]
        nxt = buf[(idx + 1) % len(buf)]
        avg = 0.5 * (s + nxt) * 0.996
        val = s * (1 - brightness) + avg * brightness
        buf[idx] = avg
        idx = (idx + 1) % len(buf)
        out.append(val * math.exp(-i / (SR * 0.8)) * 0.6)
    return out

def pianoish(freq, dur=1.5):
    n = int(SR * dur)
    out = []
    partials = [(1, 1.0), (2, 0.45), (3, 0.22), (4, 0.12), (5, 0.06)]
    for i in range(n):
        t = i / SR
        s = 0.0
        for m, a in partials:
            s += a * math.sin(2 * math.pi * freq * m * t) * math.exp(-t * (1.2 + m * 0.4))
        if t < 0.01:
            s += random.uniform(-1, 1) * (1 - t / 0.01) * 0.15
        out.append(s * 0.35)
    return out

def softpad(freq, dur=2.0):
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        s = (
            math.sin(2 * math.pi * freq * t)
            + 0.5 * math.sin(2 * math.pi * freq * 1.01 * t)
            + 0.3 * math.sin(2 * math.pi * freq * 0.5 * t)
        )
        env = min(1.0, t / 0.3) * math.exp(-t / 1.5)
        out.append(s * env * 0.25)
    return out

def main():
    base = os.path.abspath(ROOT)
    write_wav(f'{base}/drums/rock_kick.wav', kick())
    write_wav(f'{base}/drums/rock_snare.wav', snare())
    write_wav(f'{base}/drums/rock_hat_closed.wav', hihat(0.1, False))
    write_wav(f'{base}/drums/rock_hat_open.wav', hihat(0.35, True))
    write_wav(f'{base}/drums/rock_tom.wav', tone(120, 0.4, 'sine', 0.005, 0.2, 0.7))
    write_wav(f'{base}/drums/elec_kick.wav', kick808())
    write_wav(f'{base}/drums/elec_snare.wav', snare(0.28))
    write_wav(f'{base}/drums/elec_hat.wav', hihat(0.08, False))
    write_wav(f'{base}/drums/elec_clap.wav', clap())
    write_wav(f'{base}/drums/elec_perc.wav', tone(440, 0.15, 'square', 0.001, 0.05, 0.25))

    clean = tone(65.41, 0.8, 'sine', 0.02, 0.6, 0.55)
    clean2 = tone(130.82, 0.8, 'sine', 0.02, 0.4, 0.15)
    write_wav(f'{base}/bass/bass_clean_c2.wav', [a + b for a, b in zip(clean, clean2)])
    driven = [math.tanh(s * 3) * 0.7 for s in tone(65.41, 0.55, 'saw', 0.01, 0.5, 0.45)]
    write_wav(f'{base}/bass/bass_driven_c2.wav', driven)
    n = int(SR * 1.2)
    b808 = []
    for i in range(n):
        t = i / SR
        f = 55.0 * (1 + 0.5 * math.exp(-t * 8))
        b808.append(math.sin(2 * math.pi * f * t) * math.exp(-t * 1.2) * 0.9)
    write_wav(f'{base}/bass/bass_808_c2.wav', b808)

    write_wav(f'{base}/guitar/clean_e2.wav', pluck(82.41, 1.2, 0.5))
    write_wav(f'{base}/guitar/crunch_e2.wav', [math.tanh(s * 4) * 0.55 for s in pluck(82.41, 1.0, 0.35)])
    write_wav(f'{base}/guitar/highgain_e2.wav', [math.tanh(s * 8) * 0.5 for s in pluck(82.41, 0.9, 0.25)])
    write_wav(f'{base}/keys/piano_c4.wav', pianoish(261.63))
    write_wav(f'{base}/keys/pad_c4.wav', softpad(261.63))
    print('Wrote samples under', base)

if __name__ == '__main__':
    main()
