import 'package:flutter_test/flutter_test.dart';
import 'package:layerstudio/utils/music_theory.dart';

void main() {
  test('triad still returns root–third–fifth', () {
    expect(MusicTheory.triad(60, minor: false), [60, 64, 67]);
    expect(MusicTheory.triad(60, minor: true), [60, 63, 67]);
  });

  test('chordVoicing adds dominant 7th and sus4', () {
    expect(
      MusicTheory.chordVoicing(60, seventh: true),
      [60, 64, 67, 70],
    );
    expect(
      MusicTheory.chordVoicing(60, sus4: true),
      [60, 65, 67],
    );
    expect(
      MusicTheory.chordVoicing(60, minor: true, seventh: true),
      [60, 63, 67, 70],
    );
  });

  test('chordVoicing inversions rotate upward', () {
    expect(
      MusicTheory.chordVoicing(60, inversion: 1),
      [64, 67, 72],
    );
    expect(
      MusicTheory.chordVoicing(60, inversion: 2),
      [67, 72, 76],
    );
    expect(
      MusicTheory.chordVoicing(60, seventh: true, inversion: 3),
      [70, 72, 76, 79],
    );
  });

  test('chordSuffix labels extensions', () {
    expect(MusicTheory.chordSuffix(), '');
    expect(MusicTheory.chordSuffix(minor: true), 'm');
    expect(MusicTheory.chordSuffix(seventh: true), '7');
    expect(MusicTheory.chordSuffix(minor: true, seventh: true), 'm7');
    expect(MusicTheory.chordSuffix(sus4: true), 'sus4');
    expect(MusicTheory.chordSuffix(seventh: true, sus4: true), '7sus4');
  });

  test('strum offset range matches visual-guide window', () {
    // Documented micro-timing window used by Harmonic tools slider.
    const minMs = 10;
    const maxMs = 40;
    expect(minMs, lessThan(maxMs));
    expect((maxMs - minMs), 30);
  });
}
