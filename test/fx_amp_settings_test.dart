import 'package:flutter_test/flutter_test.dart';
import 'package:layerstudio/models/fx_settings.dart';
import 'package:layerstudio/models/track.dart';
import 'package:layerstudio/utils/dsp_simple.dart';
import 'package:layerstudio/utils/music_theory.dart';

void main() {
  test('FxSettings round-trips mini amp fields', () {
    final fx = FxSettings(
      gain: 0.8,
      tone: 0.2,
      cabSim: false,
      ampPreset: AmpPreset.bassDrive,
    );
    final json = fx.toJson();
    final back = FxSettings.fromJson(json);
    expect(back.gain, 0.8);
    expect(back.tone, 0.2);
    expect(back.cabSim, isFalse);
    expect(back.ampPreset, AmpPreset.bassDrive);
  });

  test('FxSettings accepts legacy numeric cabSim', () {
    final back = FxSettings.fromJson({'cabSim': 0.9, 'gain': 0.5});
    expect(back.cabSim, isTrue);
    final off = FxSettings.fromJson({'cabSim': 0.1});
    expect(off.cabSim, isFalse);
  });

  test('bass defaults to fretboard mode', () {
    final t = Track(
      id: '1',
      name: 'Bass',
      category: TrackCategory.bass,
      presetId: 'bass_clean',
      sampleRoot: 'assets/samples/bass/bass_clean_c2.wav',
      rootMidi: 36,
    );
    expect(t.effectiveMode, TrackInstrumentMode.fretboard);
  });

  test('scale lock pitch classes for C major', () {
    expect(MusicTheory.inScale(60, 'C', 'major'), isTrue); // C
    expect(MusicTheory.inScale(61, 'C', 'major'), isFalse); // C#
    expect(MusicTheory.inScale(64, 'C', 'major'), isTrue); // E
  });

  test('SimpleDsp drive audibly reshapes buffer', () {
    final buf = List<double>.filled(8, 0.5);
    SimpleDsp.applyDrive(buf, amount: 0.8);
    expect(buf.any((s) => (s - 0.5).abs() > 0.01), isTrue);
  });

  test('bass open-string MIDI layout (E A D G)', () {
    const open = [28, 33, 38, 43];
    expect(MusicTheory.noteName(open[0]), 'E1');
    expect(MusicTheory.noteName(open[3] + 12), 'G3'); // 12th fret G
  });
}
