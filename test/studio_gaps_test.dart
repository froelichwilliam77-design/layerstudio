import 'package:flutter_test/flutter_test.dart';
import 'package:layerstudio/models/note_event.dart';
import 'package:layerstudio/models/pattern.dart';
import 'package:layerstudio/models/project.dart';
import 'package:layerstudio/models/track.dart';
import 'package:layerstudio/services/command_stack.dart';
import 'package:layerstudio/services/export_service.dart';

void main() {
  test('JsonSnapshotCommand undoes string state', () {
    var json = '{"v":1}';
    final stack = CommandStack();
    stack.push(
      JsonSnapshotCommand(
        label: 'edit',
        apply: (s) => json = s,
        before: '{"v":1}',
        after: '{"v":2}',
      ),
      executeNow: false,
    );
    json = '{"v":2}';
    stack.undo();
    expect(json, '{"v":1}');
    stack.redo();
    expect(json, '{"v":2}');
  });

  test('song-mode mix events offset clip notes by start bar', () {
    final drums = Track(
      id: 't1',
      name: 'Drums',
      category: TrackCategory.drums,
      presetId: 'drums_rock',
      sampleRoot: 'kick.wav',
    );
    drums.notes.add(NoteEvent(id: 'live', pitch: 36, startStep: 0));
    final patB = Pattern(id: 'pat_b', name: 'B');
    patB.setNotesFor('t1', [
      NoteEvent(id: 'n1', pitch: 36, startStep: 0),
    ]);
    final project = StudioProject(
      id: 'p',
      name: 'Song',
      bars: 4,
      songMode: true,
      tracks: [drums],
      patterns: [
        Pattern(id: 'pat_a', name: 'A'),
        patB,
        Pattern(id: 'pat_c', name: 'C'),
        Pattern(id: 'pat_d', name: 'D'),
      ],
      arrangement: [
        ArrangementClip(
          id: 'c1',
          patternId: 'pat_b',
          startBar: 2,
          lengthBars: 1,
        ),
      ],
    );
    final events = ExportService.flattenMixEvents(project);
    expect(events, hasLength(1));
    expect(events.first.note.startStep, 2 * project.stepsPerBar);
  });

  test('cue and latency fields survive JSON roundtrip', () {
    final t = Track(
      id: 'm',
      name: 'Mic',
      category: TrackCategory.mic,
      presetId: 'mic',
      sampleRoot: '',
      cue: true,
      overdub: true,
      latencyMs: 40,
    );
    final p = StudioProject(
      id: 'p',
      name: 'n',
      cueMode: true,
      latencyCompensationMs: 12,
      tracks: [t],
    );
    final back = StudioProject.fromJson(p.toJson());
    expect(back.cueMode, isTrue);
    expect(back.latencyCompensationMs, 12);
    expect(back.tracks.first.cue, isTrue);
    expect(back.tracks.first.overdub, isTrue);
    expect(back.tracks.first.latencyMs, 40);
  });
}
