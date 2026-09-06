import 'package:flutter_test/flutter_test.dart';
import 'package:layerstudio/utils/audio_clock_math.dart';

void main() {
  group('AudioClockMath', () {
    test('secondsPerStep at 120 BPM is 0.125s', () {
      expect(AudioClockMath.secondsPerStep(120), closeTo(0.125, 1e-9));
    });

    test('step/seconds roundtrip', () {
      const bpm = 100;
      for (final step in [0, 1, 4, 16, 63]) {
        final sec = AudioClockMath.stepToSeconds(step, bpm);
        expect(AudioClockMath.secondsToStep(sec + 1e-9, bpm), step);
      }
    });

    test('mapLoop wraps and re-anchors', () {
      final r = AudioClockMath.mapLoop(
        musicalSeconds: AudioClockMath.stepToSeconds(64, 120),
        bpm: 120,
        loopEnabled: true,
        loopStartStep: 0,
        loopEndStep: 64,
      );
      expect(r.didWrap, isTrue);
      expect(r.step, 0);
    });

    test('stepsInLookahead schedules upcoming steps', () {
      final steps = AudioClockMath.stepsInLookahead(
        fromStepExclusive: 3,
        toStepInclusive: 6,
        loopEnabled: false,
        loopStartStep: 0,
        loopEndStep: 64,
      );
      expect(steps, [4, 5, 6]);
    });

    test('swing delays even 16ths only', () {
      expect(AudioClockMath.isSwungStep(0), isFalse);
      expect(AudioClockMath.isSwungStep(1), isTrue);
      expect(AudioClockMath.swingDelaySeconds(0, 100, 120), 0);
      // 100% swing = half of one 16th = 0.0625s at 120 BPM
      expect(
        AudioClockMath.swingDelaySeconds(1, 100, 120),
        closeTo(0.0625, 1e-9),
      );
      expect(
        AudioClockMath.stepOnsetSeconds(1, 120, 50),
        closeTo(0.125 + 0.03125, 1e-9),
      );
    });

    test('swungStepsInWindow includes delayed even step', () {
      final items = AudioClockMath.swungStepsInWindow(
        nowSec: 0.12,
        lookaheadSec: 0.05,
        bpm: 120,
        swingPercent: 50,
        scheduledThroughOnset: -1,
        loopEnabled: false,
        loopStartStep: 0,
        loopEndStep: 64,
      );
      expect(items.any((e) => e.step == 1), isTrue);
    });
  });
}
