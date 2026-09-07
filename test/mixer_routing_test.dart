import 'package:flutter_test/flutter_test.dart';
import 'package:layerstudio/models/project.dart';
import 'package:layerstudio/models/track.dart';
import 'package:layerstudio/utils/mixer_routing.dart';

void main() {
  test('mute silences a track', () {
    final muted = Track(
      id: 't',
      name: 'T',
      category: TrackCategory.drums,
      presetId: 'drums_rock',
      sampleRoot: 'x.wav',
      muted: true,
    );
    final p = StudioProject(id: 'p', name: 'n', tracks: [muted]);
    expect(isTrackAudible(muted, project: p), isFalse);
  });

  test('solo silences non-solo tracks', () {
    final drums = Track(
      id: 'a',
      name: 'A',
      category: TrackCategory.drums,
      presetId: 'drums_rock',
      sampleRoot: 'x.wav',
      solo: true,
    );
    final bass = Track(
      id: 'b',
      name: 'B',
      category: TrackCategory.bass,
      presetId: 'bass_clean',
      sampleRoot: 'y.wav',
    );
    final p = StudioProject(id: 'p', name: 'n', tracks: [drums, bass]);
    expect(isTrackAudible(drums, project: p), isTrue);
    expect(isTrackAudible(bass, project: p), isFalse);
  });

  test('cue mode only plays cued tracks when any cue is set', () {
    final cued = Track(
      id: 'a',
      name: 'A',
      category: TrackCategory.drums,
      presetId: 'drums_rock',
      sampleRoot: 'x.wav',
      cue: true,
    );
    final other = Track(
      id: 'b',
      name: 'B',
      category: TrackCategory.bass,
      presetId: 'bass_clean',
      sampleRoot: 'y.wav',
    );
    final p = StudioProject(
      id: 'p',
      name: 'n',
      cueMode: true,
      tracks: [cued, other],
    );
    expect(isTrackAudible(cued, project: p), isTrue);
    expect(isTrackAudible(other, project: p), isFalse);
    expect(isTrackAudible(other, project: p, honorCue: false), isTrue);
  });
}
