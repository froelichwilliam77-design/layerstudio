import 'package:flutter_test/flutter_test.dart';
import 'package:layerstudio/models/note_event.dart';
import 'package:layerstudio/models/pattern.dart';
import 'package:layerstudio/models/project.dart';
import 'package:layerstudio/models/track.dart';

void main() {
  test('pattern + arrangement serialize roundtrip', () {
    final patA = Pattern(id: 'pat_a', name: 'A');
    patA.setNotesFor('t1', [
      NoteEvent(id: 'n1', pitch: 36, startStep: 0, probability: 80),
    ]);
    final project = StudioProject(
      id: 'p1',
      name: 'Groove',
      patterns: [
        patA,
        Pattern(id: 'pat_b', name: 'B'),
        Pattern(id: 'pat_c', name: 'C'),
        Pattern(id: 'pat_d', name: 'D'),
      ],
      arrangement: [
        ArrangementClip(id: 'c1', patternId: 'pat_a', startBar: 0, lengthBars: 2),
        ArrangementClip(id: 'c2', patternId: 'pat_b', startBar: 2, lengthBars: 1),
      ],
      songMode: true,
      swingPercent: 35,
      countInBars: 1,
      tracks: [
        Track(
          id: 't1',
          name: 'Drums',
          category: TrackCategory.drums,
          presetId: 'drums_rock',
          sampleRoot: 'assets/samples/drums/rock_kick.wav',
        ),
      ],
    );

    final json = project.toJson();
    final back = StudioProject.fromJson(json);
    expect(back.swingPercent, 35);
    expect(back.countInBars, 1);
    expect(back.songMode, isTrue);
    expect(back.patterns.length, 4);
    expect(back.patterns.first.notesFor('t1').first.probability, 80);
    expect(back.arrangement.length, 2);
    expect(back.arrangementEndBar, 3);
  });

  test('legacy project migrates notes into pattern A', () {
    final legacy = {
      'id': 'old',
      'name': 'Old',
      'tracks': [
        {
          'id': 't1',
          'name': 'Kit',
          'category': 'drums',
          'presetId': 'drums_rock',
          'sampleRoot': 'assets/samples/drums/rock_kick.wav',
          'notes': [
            {'id': 'n1', 'pitch': 36, 'startStep': 4, 'lengthSteps': 1, 'velocity': 100},
          ],
        }
      ],
    };
    final p = StudioProject.fromJson(legacy);
    expect(p.patterns.length, 4);
    expect(p.patterns.first.notesFor('t1').single.startStep, 4);
  });
}
