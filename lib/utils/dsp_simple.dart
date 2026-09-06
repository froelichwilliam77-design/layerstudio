import 'dart:math' as math;

/// Lightweight offline DSP helpers for mixdown (not a full DAW insert rack).
class SimpleDsp {
  /// Very rough 3-band shelf using one-pole filters on a buffer copy.
  static void applyEq(
    List<double> buf, {
    required double low, // -1..1
    required double mid,
    required double high,
    int sampleRate = 44100,
  }) {
    if (low.abs() < 0.01 && mid.abs() < 0.01 && high.abs() < 0.01) return;
    var lp = 0.0;
    var hpPrev = 0.0;
    final lowGain = 1.0 + low * 0.8;
    final midGain = 1.0 + mid * 0.6;
    final highGain = 1.0 + high * 0.8;
    final a = math.exp(-2 * math.pi * 250 / sampleRate);
    for (var i = 0; i < buf.length; i++) {
      final x = buf[i];
      lp = a * lp + (1 - a) * x;
      final hp = x - hpPrev;
      hpPrev = x * 0.95;
      final midBand = x - lp;
      buf[i] = lp * lowGain + midBand * midGain + hp * highGain * 0.35;
    }
  }

  /// Soft knee compressor (peak follower).
  static void applyCompressor(
    List<double> buf, {
    required double amount, // 0..1
  }) {
    if (amount < 0.05) return;
    final threshold = 0.45 - amount * 0.25;
    final ratio = 1.5 + amount * 4.0;
    var env = 0.0;
    for (var i = 0; i < buf.length; i++) {
      final x = buf[i].abs();
      env = x > env ? x : env * 0.995;
      if (env > threshold) {
        final over = env - threshold;
        final compressed = threshold + over / ratio;
        final g = compressed / (env + 1e-9);
        buf[i] *= g;
      }
    }
  }
}
