import 'package:flutter_test/flutter_test.dart';
import 'package:layerstudio/data/sound_library.dart';
import 'package:layerstudio/models/track.dart';

void main() {
  test('SoundLibrary exposes ~12 drum kits with 5 pads each', () {
    final kits = SoundLibrary.drumKits;
    expect(kits.length, greaterThanOrEqualTo(10));
    expect(kits.length, lessThanOrEqualTo(14));
    for (final kit in kits) {
      expect(kit.category, TrackCategory.drums);
      expect(kit.drumKit, isNotNull);
      expect(kit.drumKit!.length, 5);
      expect(kit.drumKit!.keys.first.toLowerCase(), contains('kick'));
      expect(SoundLibrary.byId(kit.id), isNotNull);
    }
    // Legacy ids remain for saved projects
    expect(SoundLibrary.byId('drums_rock'), isNotNull);
    expect(SoundLibrary.byId('drums_elec'), isNotNull);
  });

  test('DrumPadMap pitch mapping is stable', () {
    expect(DrumPadMap.pitchForPad(0), 36);
    expect(DrumPadMap.padIndexForPitch(36), 0);
    expect(DrumPadMap.padIndexForPitch(40), 4);
  });

  test('resolveRoot picks nearest multi-root sample', () {
    final bass = SoundLibrary.byId('bass_clean')!;
    expect(bass.roots, isNotNull);
    expect(bass.roots!.length, 3);

    expect(bass.resolveRoot(36).rootMidi, 36);
    expect(bass.resolveRoot(36).path, endsWith('bass_clean_c2.wav'));

    expect(bass.resolveRoot(24).rootMidi, 24);
    expect(bass.resolveRoot(24).path, endsWith('bass_clean_c1.wav'));

    expect(bass.resolveRoot(48).rootMidi, 48);
    expect(bass.resolveRoot(48).path, endsWith('bass_clean_c3.wav'));

    // Midway: C2+6 → nearer C2 or C3? abs(42-36)=6, abs(42-48)=6 → first best stays C2
    expect(bass.resolveRoot(42).rootMidi, 36);
    // Closer to C3
    expect(bass.resolveRoot(45).rootMidi, 48);
    // Closer to C1
    expect(bass.resolveRoot(28).rootMidi, 24);
  });

  test('resolveRoot falls back to samplePath when no roots', () {
    final drums = SoundLibrary.byId('drums_rock')!;
    expect(drums.roots, isNull);
    final r = drums.resolveRoot(40);
    expect(r.path, drums.samplePath);
    expect(r.rootMidi, drums.rootMidi);
  });

  test('melodic presets expose allSamplePaths for preload', () {
    final gtr = SoundLibrary.byId('gtr_clean')!;
    final paths = gtr.allSamplePaths.toList();
    expect(paths.length, 3);
    expect(paths, contains('assets/samples/guitar/clean_e1.wav'));
    expect(paths, contains('assets/samples/guitar/clean_e2.wav'));
    expect(paths, contains('assets/samples/guitar/clean_e3.wav'));
  });

  test('keys / guitar root banks use expected midis', () {
    final piano = SoundLibrary.byId('keys_piano')!;
    // abs(55-48)=7, abs(55-60)=5 → nearer C4
    expect(piano.resolveRoot(55).rootMidi, 60);
    expect(piano.resolveRoot(66).rootMidi, 60); // nearer C4 (tie prefers lower)
    expect(piano.resolveRoot(70).rootMidi, 72); // nearer C5

    final gtr = SoundLibrary.byId('gtr_crunch')!;
    expect(gtr.category, TrackCategory.guitar);
    expect(gtr.resolveRoot(34).rootMidi, 28);
    expect(gtr.resolveRoot(46).rootMidi, 40);
  });

  test('clampMidi keeps in-bank notes; soft range uses nearest root', () {
    final bass = SoundLibrary.byId('bass_clean')!;
    // Across C1–C3 bank + soft margin: no soft warning, no hard clamp.
    for (final m in [24, 28, 36, 40, 48, 55, 60]) {
      expect(bass.clampMidi(m), m, reason: 'midi $m');
      expect(bass.exceedsSoftRange(m), isFalse, reason: 'soft $m');
    }
    // Outside bank hard envelope (C1-24 .. C3+24 = 0..72)
    expect(bass.clampMidi(73), 72);
    expect(bass.clampMidi(-1), 0);
    // Far from nearest root but still inside hard bank → soft only
    expect(bass.exceedsSoftRange(72), isTrue);
    expect(bass.clampMidi(72), 72);

    final piano = SoundLibrary.byId('keys_piano')!;
    // C2 on piano: nearest C3 — within soft (±12) → no red clamp banner
    expect(piano.resolveRoot(36).rootMidi, 48);
    expect(piano.exceedsSoftRange(36), isFalse);
    expect(piano.clampMidi(36), 36);
    // Hard range for piano C3–C5: 24..96
    expect(piano.pitchHardRange.lo, 24);
    expect(piano.pitchHardRange.hi, 96);
  });
}
