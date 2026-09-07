import 'dart:math' as math;

import '../models/fx_settings.dart';

/// Offline FX that mirror the live SoLoud Echo / WaveShaper / Freeverb / biquad
/// inserts used in [AudioEngine._applyVoiceFx].
class OfflineFx {
  static void applyVoiceChain(
    List<double> left,
    List<double> right, {
    required FxSettings fx,
    int sampleRate = 44100,
  }) {
    _waveShaper(left, fx);
    _waveShaper(right, fx);
    _toneLowpass(left, fx, sampleRate);
    _toneLowpass(right, fx, sampleRate);
    _echo(left, right, fx, sampleRate);
    _freeverb(left, right, fx, sampleRate);
  }

  /// SoLoud wave-shaper: amount = amp base + gain*0.85, wet mix.
  static void _waveShaper(List<double> buf, FxSettings fx) {
    final gain = fx.gain.clamp(0.0, 1.0);
    final base = switch (fx.ampPreset) {
      AmpPreset.none => 0.0,
      AmpPreset.clean => 0.08,
      AmpPreset.crunch => 0.35,
      AmpPreset.highGain => 0.7,
      AmpPreset.bassDrive => 0.42,
    };
    final amount = (base + gain * 0.85).clamp(0.0, 0.95);
    if (amount <= 0.03) return;
    final wet = (0.45 + gain * 0.5).clamp(0.0, 0.95);
    final drive = 1.0 + amount * 8.0;
    for (var i = 0; i < buf.length; i++) {
      final x = (buf[i] * drive).clamp(-20.0, 20.0);
      final e = math.exp(2.0 * x);
      final shaped = (e - 1.0) / (e + 1.0);
      buf[i] = buf[i] * (1 - wet) + shaped * wet;
    }
  }

  /// Biquad-ish one-pole low-pass matching live tone/cab cutoff.
  static void _toneLowpass(List<double> buf, FxSettings fx, int sampleRate) {
    final tone = fx.tone.clamp(0.0, 1.0);
    var hz = 500.0 + tone * 7500.0;
    if (fx.cabSim) hz *= 0.55;
    hz = hz.clamp(120.0, 12000.0);
    final wet = (tone < 0.92 || fx.cabSim) ? 0.85 : 0.35;
    final x = math.exp(-2 * math.pi * hz / sampleRate);
    var lp = 0.0;
    for (var i = 0; i < buf.length; i++) {
      lp = x * lp + (1 - x) * buf[i];
      buf[i] = buf[i] * (1 - wet) + lp * wet;
    }
  }

  /// Stereo echo matching live delay/decay/wet.
  static void _echo(
    List<double> left,
    List<double> right,
    FxSettings fx,
    int sampleRate,
  ) {
    final delay = fx.delay.clamp(0.0, 1.0);
    final delaySec = 0.18 + delay * 0.45;
    final decay = 0.25 + delay * 0.5;
    final wet = (delay * 0.75).clamp(0.0, 0.85);
    if (wet < 0.02) return;
    final tap = (delaySec * sampleRate).round().clamp(1, sampleRate * 2);
    final n = left.length;
    for (var i = tap; i < n; i++) {
      left[i] += left[i - tap] * decay * wet;
      right[i] += right[i - tap] * decay * wet;
    }
  }

  /// Comb + allpass Freeverb approximation (stereo).
  static void _freeverb(
    List<double> left,
    List<double> right,
    FxSettings fx,
    int sampleRate,
  ) {
    var wet = fx.reverb.clamp(0.0, 1.0);
    var damp = 0.35 + (1 - wet) * 0.3;
    var room = 0.45 + wet * 0.45;
    if (fx.cabSim) {
      wet = (wet + 0.22).clamp(0.0, 0.85);
      damp = (0.72 + (1 - fx.tone.clamp(0.0, 1.0)) * 0.2).clamp(0.4, 0.95);
      room = (room * 0.7 + 0.25).clamp(0.2, 0.85);
    }
    if (wet < 0.03) return;

    const combMsL = [29.7, 37.1, 41.1, 43.7];
    const combMsR = [30.3, 37.9, 41.9, 44.3];
    _combs(left, combMsL, sampleRate, room, damp, wet);
    _combs(right, combMsR, sampleRate, room, damp, wet);
  }

  static void _combs(
    List<double> buf,
    List<double> delaysMs,
    int sampleRate,
    double room,
    double damp,
    double wet,
  ) {
    final n = buf.length;
    final dry = List<double>.from(buf);
    for (final ms in delaysMs) {
      final tap = (ms * 0.001 * sampleRate).round().clamp(1, n - 1);
      var lp = 0.0;
      final fb = (0.7 * room).clamp(0.05, 0.92);
      for (var i = tap; i < n; i++) {
        lp = (1 - damp) * buf[i - tap] + damp * lp;
        buf[i] += lp * fb * 0.25;
      }
    }
    for (var i = 0; i < n; i++) {
      buf[i] = dry[i] * (1 - wet) + buf[i] * wet;
    }
  }

  /// Cubic interpolate [src] at fractional [pos].
  static double cubicAt(List<double> src, double pos) {
    final i = pos.floor();
    final f = pos - i;
    final p0 = src[(i - 1).clamp(0, src.length - 1)];
    final p1 = src[i.clamp(0, src.length - 1)];
    final p2 = src[(i + 1).clamp(0, src.length - 1)];
    final p3 = src[(i + 2).clamp(0, src.length - 1)];
    final a = -0.5 * p0 + 1.5 * p1 - 1.5 * p2 + 0.5 * p3;
    final b = p0 - 2.5 * p1 + 2 * p2 - 0.5 * p3;
    final c = -0.5 * p0 + 0.5 * p2;
    return ((a * f + b) * f + c) * f + p1;
  }
}
