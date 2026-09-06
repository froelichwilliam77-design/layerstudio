#!/usr/bin/env python3
"""Regenerate LayerStudio synthetic WAV sample pack (CC0).

All drum/melodic samples are procedurally generated — no third-party packs.
Drum samples are **stereo** so SoLoud Freeverb inserts can activate.
Melodic samples remain mono (pitch-rate playback).
"""
from __future__ import annotations

import math
import os
import random
import struct
import wave

SR = 44100
ROOT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'samples')


def write_wav(path, samples, sr=SR, stereo=False):
    """samples: list of float, or list of (L,R) if stereo=True."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, 'w') as w:
        w.setnchannels(2 if stereo else 1)
        w.setsampwidth(2)
        w.setframerate(sr)
        frames = bytearray()
        if stereo:
            for pair in samples:
                if isinstance(pair, (list, tuple)):
                    l, r = pair
                else:
                    l = r = pair
                for s in (l, r):
                    frames += struct.pack(
                        '<h', max(-32767, min(32767, int(s * 32767)))
                    )
        else:
            for s in samples:
                frames += struct.pack(
                    '<h', max(-32767, min(32767, int(s * 32767)))
                )
        w.writeframes(bytes(frames))


def to_stereo(mono, pan=0.0, width=0.0):
    """pan -1..1; optional width adds tiny L/R decorrelation."""
    pan = max(-1.0, min(1.0, pan))
    angle = (pan + 1) * 0.25 * math.pi
    l_g = math.cos(angle)
    r_g = math.sin(angle)
    out = []
    delay = max(0, int(width * 4))
    for i, s in enumerate(mono):
        l = s * l_g
        r = s * r_g
        if delay and i >= delay:
            r = 0.92 * r + 0.08 * mono[i - delay] * r_g
        out.append((l, r))
    return out


def soft_clip(x, drive=1.4):
    return math.tanh(x * drive) / math.tanh(drive)


def normalize(buf, peak=0.92):
    m = max((abs(x) for x in buf), default=1.0)
    if m < 1e-9:
        return buf
    g = peak / m
    return [x * g for x in buf]


def mix_add(a, b, gain=1.0):
    n = max(len(a), len(b))
    out = [0.0] * n
    for i in range(n):
        out[i] = (a[i] if i < len(a) else 0.0) + (b[i] if i < len(b) else 0.0) * gain
    return out


def env_exp(i, n, attack=0.01, decay=0.3):
    t = i / max(n, 1)
    a = min(1.0, t / max(attack, 1e-6))
    d = math.exp(-t / max(decay, 1e-6))
    return a * d


def one_pole_lp(x, cutoff, state):
    """Simple low-pass; cutoff ~0..1 (higher = brighter)."""
    a = max(0.001, min(0.999, cutoff))
    state[0] = state[0] + a * (x - state[0])
    return state[0]


def one_pole_hp(x, cutoff, state):
    lp = one_pole_lp(x, cutoff, state)
    return x - lp


# ---------- core synthesis ----------

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
        elif wave == 'tri':
            s = 2 * abs(2 * ((freq * t) % 1.0) - 1.0) - 1.0
        else:
            s = math.sin(phase)
        out.append(s * env_exp(i, n, attack, decay) * amp)
    return out


def noise_burst(dur, decay=0.08, amp=0.5, band='white', color=0.5):
    n = int(SR * dur)
    out, prev = [], 0.0
    lp = [0.0]
    for i in range(n):
        r = random.uniform(-1, 1)
        if band == 'low':
            prev = 0.92 * prev + 0.08 * r
            s = prev
        elif band == 'high':
            s = one_pole_hp(r, 0.35 + 0.4 * color, lp)
        elif band == 'pink':
            prev = 0.97 * prev + 0.03 * r
            s = 0.5 * r + 0.5 * prev
        else:
            s = r
        out.append(s * math.exp(-i / (SR * decay)) * amp)
    return out


def kick(
    dur=0.5,
    start_f=180.0,
    end_f=42.0,
    drop=14.0,
    body_decay=5.5,
    click=0.45,
    punch=0.35,
    sub_amp=0.55,
    drive=1.3,
):
    """Punchier acoustic/electronic kick with click + sub."""
    n = int(SR * dur)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / SR
        f = end_f + (start_f - end_f) * math.exp(-t * drop)
        phase += 2 * math.pi * f / SR
        body = math.sin(phase) * math.exp(-t * body_decay)
        sub = math.sin(2 * math.pi * end_f * t) * math.exp(-t * (body_decay * 0.55)) * sub_amp
        # beater click
        clk = 0.0
        if t < 0.012:
            clk = random.uniform(-1, 1) * (1 - t / 0.012) * click
            clk += math.sin(2 * math.pi * 2200 * t) * (1 - t / 0.012) * punch * 0.5
        s = soft_clip(body + sub + clk, drive)
        out.append(s)
    return normalize(out, 0.95)


def kick808(
    dur=0.85,
    start_f=95.0,
    end_f=38.0,
    drop=5.5,
    decay=2.4,
    click=0.22,
    drive=1.15,
):
    n = int(SR * dur)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / SR
        f = end_f + (start_f - end_f) * math.exp(-t * drop)
        phase += 2 * math.pi * f / SR
        s = math.sin(phase) * math.exp(-t * decay)
        if t < 0.008:
            s += random.uniform(-1, 1) * (1 - t / 0.008) * click
        # gentle saturation for weight without harshness
        s = soft_clip(s * 1.05, drive)
        out.append(s)
    return normalize(out, 0.96)


def snare(
    dur=0.38,
    body_f=185.0,
    body_amp=0.42,
    noise_amp=0.62,
    noise_decay=0.11,
    snap=0.35,
    tone2_f=330.0,
    drive=1.25,
    dusty=0.0,
):
    n = int(SR * dur)
    body = []
    for i in range(n):
        t = i / SR
        s = math.sin(2 * math.pi * body_f * t) * math.exp(-t * 18) * body_amp
        s += math.sin(2 * math.pi * tone2_f * t) * math.exp(-t * 28) * body_amp * 0.35
        body.append(s)
    noise = noise_burst(dur, noise_decay, noise_amp, 'high', color=0.7)
    # early snap transient
    snap_n = int(0.008 * SR)
    for i in range(min(snap_n, n)):
        body[i] += random.uniform(-1, 1) * snap * (1 - i / snap_n)
    out = mix_add(body, noise)
    if dusty > 0:
        dust = noise_burst(dur, 0.2, dusty * 0.25, 'pink')
        out = mix_add(out, dust)
        # mild bit of grit
        out = [soft_clip(x * (1 + dusty * 0.3), 1.1 + dusty) for x in out]
    else:
        out = [soft_clip(x, drive) for x in out]
    return normalize(out, 0.9)


def clap(dur=0.32, layers=4, spread=0.014, amp=0.55):
    """Multi-burst clap (more realistic than single noise)."""
    n = int(SR * (dur + layers * spread))
    out = [0.0] * n
    for layer in range(layers):
        delay = int(layer * spread * SR * (0.85 + 0.3 * random.random()))
        burst = noise_burst(0.12, 0.07 + layer * 0.01, amp * (0.9 - layer * 0.12), 'high')
        for i, s in enumerate(burst):
            j = i + delay
            if j < n:
                out[j] += s
    # body thump
    for i in range(min(n, int(0.04 * SR))):
        t = i / SR
        out[i] += math.sin(2 * math.pi * 420 * t) * math.exp(-t * 60) * 0.2
    out = [soft_clip(x, 1.35) for x in out]
    return normalize(out, 0.88)


def hihat(dur=0.12, open_=False, metallic=0.45, amp=0.32, decay=None):
    """Metallic hats: HP noise + quiet ring partials."""
    if decay is None:
        decay = 0.28 if open_ else 0.038
    n = int(SR * dur)
    noise = noise_burst(dur, decay, amp, 'high', color=0.85)
    rings = [0.0] * n
    partials = [5500, 7800, 9200, 11200]
    for pf in partials:
        for i in range(n):
            t = i / SR
            rings[i] += math.sin(2 * math.pi * pf * t) * math.exp(-t / decay) * metallic * 0.08
    out = mix_add(noise, rings)
    # extra brightness trim via soft clip
    out = [soft_clip(x, 1.1) for x in out]
    return normalize(out, 0.7 if open_ else 0.62)


def rim(dur=0.12, freq=880.0, amp=0.45):
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        s = math.sin(2 * math.pi * freq * t) * math.exp(-t * 55) * amp
        s += math.sin(2 * math.pi * freq * 1.5 * t) * math.exp(-t * 70) * amp * 0.4
        s += random.uniform(-1, 1) * math.exp(-t * 90) * 0.25
        out.append(soft_clip(s, 1.2))
    return normalize(out, 0.75)


def tom(dur=0.45, freq=120.0, amp=0.75, pitch_drop=1.15):
    n = int(SR * dur)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / SR
        f = freq * (pitch_drop * math.exp(-t * 8) + (1 - (pitch_drop - 1) * 0.3))
        phase += 2 * math.pi * f / SR
        s = math.sin(phase) * math.exp(-t * 5.5) * amp
        s += math.sin(phase * 2) * math.exp(-t * 10) * amp * 0.18
        if t < 0.008:
            s += random.uniform(-1, 1) * (1 - t / 0.008) * 0.3
        out.append(soft_clip(s, 1.2))
    return normalize(out, 0.88)


def perc_blip(dur=0.14, freq=440.0, wave='square', amp=0.28):
    return normalize(tone(freq, dur, wave, 0.001, 0.04, amp), 0.7)


def shaker(dur=0.18, amp=0.28):
    return normalize(noise_burst(dur, 0.06, amp, 'high', color=0.9), 0.65)


def brush_snare(dur=0.45):
    body = snare(dur, body_f=160, body_amp=0.18, noise_amp=0.55, noise_decay=0.22, snap=0.12, dusty=0.35)
    soft = noise_burst(dur, 0.3, 0.2, 'pink')
    return normalize(mix_add(body, soft, 0.6), 0.78)


def click(freq=1000, dur=0.04):
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        out.append(math.sin(2 * math.pi * freq * t) * math.exp(-t * 80) * 0.7)
    return out


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
            s += a * math.sin(2 * math.pi * freq * m * t) * math.exp(
                -t * (1.2 + m * 0.4)
            )
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


def write_drum(path, mono, pan=0.0, width=0.15):
    write_wav(path, to_stereo(mono, pan, width), stereo=True)


# ---------- kit builders ----------

def build_kits(base: str):
    d = f'{base}/drums'

    # --- improved legacy rock ---
    write_drum(f'{d}/rock_kick.wav', kick(0.52, 170, 48, 13, 5.2, 0.5, 0.4), 0.0)
    write_drum(f'{d}/rock_snare.wav', snare(0.36, 190, 0.45, 0.58, 0.12, 0.4), 0.12)
    write_drum(f'{d}/rock_hat_closed.wav', hihat(0.09, False, 0.5, 0.3), -0.28)
    write_drum(f'{d}/rock_hat_open.wav', hihat(0.38, True, 0.55, 0.34), -0.22)
    write_drum(f'{d}/rock_tom.wav', tom(0.42, 115, 0.78), -0.08)

    # --- improved legacy elec / hip-hop ---
    write_drum(f'{d}/elec_kick.wav', kick808(0.75, 88, 36, 5.0, 2.6, 0.28), 0.0)
    write_drum(f'{d}/elec_snare.wav', snare(0.28, 210, 0.35, 0.7, 0.09, 0.45, 380), 0.1)
    write_drum(f'{d}/elec_hat.wav', hihat(0.07, False, 0.6, 0.3, 0.03), -0.32)
    write_drum(f'{d}/elec_clap.wav', clap(0.3, 4, 0.013, 0.55), 0.18)
    write_drum(f'{d}/elec_perc.wav', perc_blip(0.12, 520, 'square', 0.28), 0.35)

    # --- Trap Heat ---
    write_drum(f'{d}/trap_kick.wav', kick808(1.0, 110, 32, 4.2, 1.9, 0.18, 1.25), 0.0)
    write_drum(f'{d}/trap_snare.wav', snare(0.32, 240, 0.28, 0.75, 0.08, 0.5, 420), 0.08)
    write_drum(f'{d}/trap_hat.wav', hihat(0.055, False, 0.7, 0.28, 0.025), -0.35)
    write_drum(f'{d}/trap_open.wav', hihat(0.42, True, 0.65, 0.32, 0.32), -0.25)
    write_drum(f'{d}/trap_clap.wav', clap(0.28, 5, 0.011, 0.6), 0.2)

    # --- Boom Bap ---
    write_drum(f'{d}/boombap_kick.wav', kick(0.48, 140, 45, 11, 6.0, 0.35, 0.25, 0.5, 1.5), 0.0)
    write_drum(
        f'{d}/boombap_snare.wav',
        snare(0.4, 175, 0.4, 0.55, 0.15, 0.28, 300, dusty=0.55),
        0.1,
    )
    write_drum(f'{d}/boombap_hat.wav', hihat(0.1, False, 0.35, 0.26, 0.045), -0.25)
    write_drum(f'{d}/boombap_open.wav', hihat(0.3, True, 0.4, 0.28), -0.2)
    write_drum(f'{d}/boombap_rim.wav', rim(0.1, 760, 0.5), 0.25)

    # --- Drill Dark ---
    write_drum(f'{d}/drill_kick.wav', kick808(0.9, 100, 30, 4.8, 2.1, 0.15, 1.35), 0.0)
    write_drum(f'{d}/drill_snare.wav', snare(0.26, 260, 0.22, 0.8, 0.07, 0.55, 480), 0.05)
    write_drum(f'{d}/drill_hat.wav', hihat(0.05, False, 0.8, 0.26, 0.02), -0.38)
    write_drum(f'{d}/drill_open.wav', hihat(0.35, True, 0.75, 0.3), -0.28)
    write_drum(f'{d}/drill_perc.wav', rim(0.09, 1100, 0.4), 0.3)

    # --- Lo-Fi Chill ---
    write_drum(f'{d}/lofi_kick.wav', kick(0.55, 130, 50, 9, 4.8, 0.25, 0.2, 0.45, 1.6), 0.0)
    write_drum(
        f'{d}/lofi_snare.wav',
        snare(0.42, 165, 0.32, 0.5, 0.18, 0.2, 280, dusty=0.7),
        0.12,
    )
    write_drum(f'{d}/lofi_hat.wav', hihat(0.12, False, 0.25, 0.22, 0.055), -0.22)
    write_drum(f'{d}/lofi_open.wav', hihat(0.4, True, 0.3, 0.24, 0.35), -0.18)
    write_drum(f'{d}/lofi_perc.wav', shaker(0.2, 0.3), 0.28)

    # --- House Pulse ---
    write_drum(f'{d}/house_kick.wav', kick(0.45, 160, 50, 16, 7.5, 0.55, 0.45, 0.4, 1.2), 0.0)
    write_drum(f'{d}/house_clap.wav', clap(0.34, 4, 0.015, 0.58), 0.15)
    write_drum(f'{d}/house_hat.wav', hihat(0.08, False, 0.55, 0.3, 0.035), -0.3)
    write_drum(f'{d}/house_open.wav', hihat(0.36, True, 0.5, 0.32), -0.22)
    write_drum(f'{d}/house_perc.wav', perc_blip(0.1, 660, 'tri', 0.3), 0.32)

    # --- Techno Drive ---
    write_drum(f'{d}/techno_kick.wav', kick(0.5, 200, 48, 18, 6.8, 0.65, 0.5, 0.35, 1.45), 0.0)
    write_drum(f'{d}/techno_snare.wav', snare(0.22, 220, 0.2, 0.85, 0.06, 0.6, 500), 0.08)
    write_drum(f'{d}/techno_hat.wav', hihat(0.06, False, 0.85, 0.28, 0.022), -0.35)
    write_drum(f'{d}/techno_open.wav', hihat(0.28, True, 0.7, 0.3), -0.25)
    write_drum(f'{d}/techno_perc.wav', perc_blip(0.08, 880, 'square', 0.22), 0.4)

    # --- Synthwave Neon ---
    write_drum(f'{d}/synthwave_kick.wav', kick(0.48, 175, 46, 14, 5.8, 0.4, 0.35, 0.5, 1.25), 0.0)
    write_drum(f'{d}/synthwave_snare.wav', snare(0.35, 200, 0.38, 0.65, 0.12, 0.35, 360), 0.1)
    write_drum(f'{d}/synthwave_hat.wav', hihat(0.09, False, 0.45, 0.28), -0.28)
    write_drum(f'{d}/synthwave_clap.wav', clap(0.32, 3, 0.018, 0.5), 0.22)
    write_drum(f'{d}/synthwave_tom.wav', tom(0.38, 95, 0.7, 1.25), -0.12)

    # --- Indie Garage ---
    write_drum(f'{d}/indie_kick.wav', kick(0.5, 155, 52, 12, 5.5, 0.4, 0.3, 0.48, 1.35), 0.0)
    write_drum(
        f'{d}/indie_snare.wav',
        snare(0.38, 180, 0.42, 0.52, 0.14, 0.32, 310, dusty=0.25),
        0.14,
    )
    write_drum(f'{d}/indie_hat_closed.wav', hihat(0.1, False, 0.4, 0.27), -0.26)
    write_drum(f'{d}/indie_hat_open.wav', hihat(0.4, True, 0.45, 0.3), -0.2)
    write_drum(f'{d}/indie_tom.wav', tom(0.4, 130, 0.72), -0.05)

    # --- Soft Brush ---
    write_drum(f'{d}/brush_kick.wav', kick(0.55, 120, 55, 8, 4.2, 0.2, 0.15, 0.4, 1.15), 0.0)
    write_drum(f'{d}/brush_snare.wav', brush_snare(0.5), 0.1)
    write_drum(f'{d}/brush_hat.wav', hihat(0.14, False, 0.2, 0.2, 0.07), -0.2)
    write_drum(f'{d}/brush_open.wav', hihat(0.45, True, 0.25, 0.22, 0.4), -0.15)
    write_drum(f'{d}/brush_tom.wav', tom(0.5, 100, 0.55, 1.1), -0.08)

    # --- Punk Punch ---
    write_drum(f'{d}/punk_kick.wav', kick(0.4, 190, 50, 16, 7.0, 0.6, 0.5, 0.35, 1.5), 0.0)
    write_drum(f'{d}/punk_snare.wav', snare(0.3, 210, 0.48, 0.7, 0.09, 0.55, 350), 0.08)
    write_drum(f'{d}/punk_hat_closed.wav', hihat(0.07, False, 0.55, 0.32, 0.03), -0.3)
    write_drum(f'{d}/punk_hat_open.wav', hihat(0.28, True, 0.5, 0.34), -0.22)
    write_drum(f'{d}/punk_tom.wav', tom(0.32, 140, 0.8, 1.3), -0.05)

    # Metronome
    write_drum(f'{d}/metronome_click.wav', click(1200, 0.035), 0.0, 0.0)
    write_drum(f'{d}/metronome_accent.wav', click(1600, 0.045), 0.0, 0.0)


def build_melodic(base: str):
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
    write_wav(
        f'{base}/guitar/crunch_e2.wav',
        [math.tanh(s * 4) * 0.55 for s in pluck(82.41, 1.0, 0.35)],
    )
    write_wav(
        f'{base}/guitar/highgain_e2.wav',
        [math.tanh(s * 8) * 0.5 for s in pluck(82.41, 0.9, 0.25)],
    )
    write_wav(f'{base}/keys/piano_c4.wav', pianoish(261.63))
    write_wav(f'{base}/keys/pad_c4.wav', softpad(261.63))


def main():
    random.seed(42)
    base = os.path.abspath(ROOT)
    build_kits(base)
    build_melodic(base)
    drum_files = sorted(f for f in os.listdir(f'{base}/drums') if f.endswith('.wav'))
    total = sum(os.path.getsize(f'{base}/drums/{f}') for f in drum_files)
    print(f'Wrote {len(drum_files)} drum WAVs ({total / 1024:.0f} KiB) + melodic under {base}')


if __name__ == '__main__':
    main()
