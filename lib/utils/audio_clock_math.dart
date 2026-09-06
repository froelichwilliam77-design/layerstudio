/// Pure transport/clock helpers (unit-testable without SoLoud).
class AudioClockMath {
  AudioClockMath._();

  /// Seconds per 16th-note step at [bpm] (quarter note = 4 steps).
  static double secondsPerStep(int bpm) => (60.0 / bpm.clamp(1, 999)) / 4.0;

  /// Musical time in seconds for a step index.
  static double stepToSeconds(int step, int bpm) =>
      step * secondsPerStep(bpm);

  /// Floor step from continuous musical time (seconds).
  static int secondsToStep(double seconds, int bpm) {
    final sps = secondsPerStep(bpm);
    if (sps <= 0) return 0;
    return (seconds / sps).floor();
  }

  /// Map continuous time into a looped step range.
  /// Returns (step, loopedSecondsAnchor) where loopedSecondsAnchor is the
  /// musical-time origin after wrapping (for resetting the audio clock).
  static ({int step, double wrappedSeconds, bool didWrap}) mapLoop({
    required double musicalSeconds,
    required int bpm,
    required bool loopEnabled,
    required int loopStartStep,
    required int loopEndStep,
  }) {
    final loopStart = loopStartStep;
    final loopEnd = loopEndStep <= loopStart ? loopStart + 1 : loopEndStep;
    var step = secondsToStep(musicalSeconds, bpm);

    if (!loopEnabled || step < loopEnd) {
      return (step: step, wrappedSeconds: musicalSeconds, didWrap: false);
    }

    final loopLen = loopEnd - loopStart;
    final into = (step - loopStart) % loopLen;
    final mapped = loopStart + into;
    return (
      step: mapped,
      wrappedSeconds: stepToSeconds(mapped, bpm),
      didWrap: true,
    );
  }

  /// Steps that should be scheduled in a lookahead window.
  /// Inclusive of [fromStepExclusive]+1 through [toStepInclusive].
  static List<int> stepsInLookahead({
    required int fromStepExclusive,
    required int toStepInclusive,
    required bool loopEnabled,
    required int loopStartStep,
    required int loopEndStep,
  }) {
    if (toStepInclusive <= fromStepExclusive) return const [];
    final out = <int>[];
    final loopStart = loopStartStep;
    final loopEnd = loopEndStep <= loopStart ? loopStart + 1 : loopEndStep;
    final loopLen = loopEnd - loopStart;

    for (var s = fromStepExclusive + 1; s <= toStepInclusive; s++) {
      var step = s;
      if (loopEnabled && step >= loopEnd) {
        final into = (step - loopStart) % loopLen;
        step = loopStart + into;
      }
      if (out.isEmpty || out.last != step) {
        out.add(step);
      }
    }
    return out;
  }
}
