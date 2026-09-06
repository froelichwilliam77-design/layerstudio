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
}
