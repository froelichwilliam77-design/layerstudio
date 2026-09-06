/// Pure transport/clock helpers (unit-testable without SoLoud).
class AudioClockMath {
  AudioClockMath._();

  /// Seconds per 16th-note step at [bpm] (quarter note = 4 steps).
  static double secondsPerStep(int bpm) => (60.0 / bpm.clamp(1, 999)) / 4.0;

  /// Musical time in seconds for a step index (no swing).
  static double stepToSeconds(int step, int bpm) =>
      step * secondsPerStep(bpm);

  /// Floor step from continuous musical time (seconds), ignoring swing.
  static int secondsToStep(double seconds, int bpm) {
    final sps = secondsPerStep(bpm);
    if (sps <= 0) return 0;
    return (seconds / sps).floor();
  }

  /// True for even 16ths that receive swing delay (odd 0-based indices:
  /// steps 1,3,5… = the 2nd/4th 16th of each beat).
  static bool isSwungStep(int step) => step % 2 == 1;

  /// Delay in seconds applied to a swung (even) 16th.
  /// [swingPercent] 0 = straight; 100 = delay by a full half-step (triplet-ish).
  static double swingDelaySeconds(int step, int swingPercent, int bpm) {
    if (!isSwungStep(step)) return 0;
    final amount = swingPercent.clamp(0, 100) / 100.0;
    return amount * secondsPerStep(bpm) * 0.5;
  }

  /// Absolute musical onset time for [step] including swing.
  static double stepOnsetSeconds(int step, int bpm, int swingPercent) =>
      stepToSeconds(step, bpm) + swingDelaySeconds(step, swingPercent, bpm);

  /// Map continuous time into a looped step range.
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

  /// Given transport time [nowSec] and lookahead, return steps whose swung
  /// onset falls in (scheduledThroughOnset, nowSec+lookahead].
  static List<({int step, double onset})> swungStepsInWindow({
    required double nowSec,
    required double lookaheadSec,
    required int bpm,
    required int swingPercent,
    required double scheduledThroughOnset,
    required bool loopEnabled,
    required int loopStartStep,
    required int loopEndStep,
  }) {
    final horizon = nowSec + lookaheadSec;
    // Scan a generous step range covering the window.
    final fromStep = secondsToStep(nowSec, bpm) - 2;
    final toStep = secondsToStep(horizon, bpm) + 4;
    final candidates = stepsInLookahead(
      fromStepExclusive: fromStep - 1,
      toStepInclusive: toStep,
      loopEnabled: loopEnabled,
      loopStartStep: loopStartStep,
      loopEndStep: loopEndStep,
    );
    final out = <({int step, double onset})>[];
    for (final step in candidates) {
      // Reconstruct absolute onset in unwrapped time near [nowSec].
      final base = stepToSeconds(step, bpm);
      // Align to nearest loop cycle around now.
      var onset = base + swingDelaySeconds(step, swingPercent, bpm);
      if (loopEnabled) {
        final loopStart = loopStartStep;
        final loopEnd = loopEndStep <= loopStart ? loopStart + 1 : loopEndStep;
        final loopLen = loopEnd - loopStart;
        final loopDur = loopLen * secondsPerStep(bpm);
        if (loopDur > 0) {
          final loopOrigin = stepToSeconds(loopStart, bpm);
          // Place onset in the same cycle window as now.
          while (onset < nowSec - loopDur) {
            onset += loopDur;
          }
          while (onset > nowSec + loopDur) {
            onset -= loopDur;
          }
          // Prefer onset inside [loopOrigin + k*loopDur ...] near now
          final k = ((nowSec - loopOrigin) / loopDur).floor();
          final local = (step - loopStart) % loopLen;
          onset = loopOrigin +
              k * loopDur +
              local * secondsPerStep(bpm) +
              swingDelaySeconds(step, swingPercent, bpm);
          if (onset < nowSec - 0.001) {
            onset += loopDur;
          }
        }
      }
      if (onset > scheduledThroughOnset && onset <= horizon) {
        out.add((step: step, onset: onset));
      }
    }
    out.sort((a, b) => a.onset.compareTo(b.onset));
    return out;
  }

  /// Delay in seconds from [nowSec] until [onsetSec] (negative if overdue).
  static double delayUntilOnset(double nowSec, double onsetSec) =>
      onsetSec - nowSec;

  /// Whether [onsetSec] is due now (already passed or within [epsilonSec]).
  static bool isOnsetDue(
    double nowSec,
    double onsetSec, {
    double epsilonSec = 0.0005,
  }) =>
      delayUntilOnset(nowSec, onsetSec) <= epsilonSec;

  /// Timer delay from [nowSec] to [onsetSec], clamped to [0, maxDelaySec].
  /// Used when flutter_soloud lacks playClocked (need ≥4.1 / Flutter ≥3.41).
  static Duration scheduleDelay({
    required double nowSec,
    required double onsetSec,
    double maxDelaySec = 2.0,
  }) {
    final d = delayUntilOnset(nowSec, onsetSec).clamp(0.0, maxDelaySec);
    return Duration(microseconds: (d * 1e6).round());
  }

}
