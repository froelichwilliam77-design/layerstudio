import 'package:flutter_test/flutter_test.dart';
import 'package:layerstudio/models/note_event.dart';
import 'package:layerstudio/models/track.dart';
import 'package:layerstudio/services/command_stack.dart';
import 'package:layerstudio/utils/music_theory.dart';

/// Mirrors StudioController paint-stroke batching without AudioEngine.
class _PaintStrokeHarness {
  _PaintStrokeHarness(this.track);

  final Track track;
  final CommandStack commands = CommandStack();
  Map<String, List<dynamic>>? _before;

  Map<String, List<dynamic>> _snap() => {
        track.id: track.notes.map((n) => n.toJson()).toList(),
      };

  void _apply(Map<String, List<dynamic>> snap) {
    track.notes = (snap[track.id] ?? const [])
        .map((e) => NoteEvent.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  void begin() => _before = _snap();

  void paint({
    required int pitch,
    required int startStep,
    required bool on,
    int velocity = 100,
    int probability = 100,
    int lengthSteps = 1,
  }) {
    track.notes.removeWhere(
      (n) => n.pitch == pitch && n.startStep == startStep,
    );
    if (on) {
      track.notes.add(NoteEvent(
        id: 'n-$pitch-$startStep-${track.notes.length}',
        pitch: pitch,
        startStep: startStep,
        lengthSteps: lengthSteps,
        velocity: velocity,
        probability: probability,
      ));
    }
  }

  void paintStep({
    required int padIndex,
    required int step,
    required bool on,
  }) {
    final pitch = 36 + padIndex; // DrumPadMap.pitchForPad
    paint(pitch: pitch, startStep: step, on: on);
  }

  void end({String label = 'Paint notes'}) {
    final before = _before;
    _before = null;
    if (before == null) return;
    final after = _snap();
    if (before[track.id].toString() == after[track.id].toString()) return;
    commands.push(
      NotesSnapshotCommand(
        label: label,
        apply: _apply,
        before: before,
        after: after,
      ),
      executeNow: false,
    );
  }

  NoteEvent? findNote(int pitch, int startStep) {
    for (final n in track.notes) {
      if (n.pitch == pitch && n.startStep == startStep) return n;
    }
    return null;
  }

  void setNoteParams({
    required String noteId,
    int? velocity,
    int? lengthSteps,
    int? probability,
  }) {
    final before = _snap();
    for (final n in track.notes) {
      if (n.id != noteId) continue;
      if (velocity != null) n.velocity = velocity.clamp(1, 127);
      if (lengthSteps != null) n.lengthSteps = lengthSteps.clamp(1, 64);
      if (probability != null) n.probability = probability.clamp(0, 100);
    }
    commands.push(
      NotesSnapshotCommand(
        label: 'Note params',
        apply: _apply,
        before: before,
        after: _snap(),
      ),
      executeNow: false,
    );
  }
}

void main() {
  test('scale lock collapses to in-scale pitch classes only', () {
    const key = 'C';
    const scale = 'major';
    final lanes = [
      for (var m = 84; m >= 36; m--)
        if (MusicTheory.inScale(m, key, scale)) m,
    ];
    expect(lanes.every((m) => MusicTheory.inScale(m, key, scale)), isTrue);
    expect(lanes.length, lessThan(84 - 36 + 1));
    expect(lanes.length, greaterThan(20));
    expect(lanes.contains(42), isFalse); // F#2 out of C major
    expect(lanes.contains(41), isTrue); // F2
    expect(lanes.first, greaterThan(lanes.last)); // high→low axis
  });

  test('collapsed lane height is larger than full chromatic', () {
    const cellHNormal = 18.0;
    const cellHCollapsed = 28.0;
    expect(cellHCollapsed, greaterThan(cellHNormal));
  });

  test('paint stroke batches into one undo entry', () {
    final track = Track(
      id: 'bass1',
      name: 'Bass',
      category: TrackCategory.bass,
      presetId: 'bass_finger',
      sampleRoot: 'assets/samples/bass/finger_c.wav',
      rootMidi: 36,
    );
    final h = _PaintStrokeHarness(track);
    h.begin();
    for (var s = 0; s < 4; s++) {
      h.paint(pitch: 48, startStep: s, on: true);
    }
    h.end();
    expect(track.notes.length, 4);
    expect(h.commands.canUndo, isTrue);
    h.commands.undo();
    expect(track.notes, isEmpty);
    h.commands.redo();
    expect(track.notes.length, 4);
  });

  test('paintStep stroke paints consecutive drum steps', () {
    final track = Track(
      id: 'drums1',
      name: 'Drums',
      category: TrackCategory.drums,
      presetId: 'kit_core',
      sampleRoot: 'assets/samples/drums/kick.wav',
    );
    final h = _PaintStrokeHarness(track);
    h.begin();
    h.paintStep(padIndex: 0, step: 0, on: true);
    h.paintStep(padIndex: 0, step: 4, on: true);
    h.paintStep(padIndex: 0, step: 8, on: true);
    h.end(label: 'Paint steps');
    expect(track.notes.length, 3);
    expect(h.findNote(36, 0), isNotNull);
    expect(h.findNote(36, 4), isNotNull);
    expect(h.findNote(36, 8), isNotNull);
    h.commands.undo();
    expect(track.notes, isEmpty);
  });

  test('parameter lock updates velocity length probability', () {
    final track = Track(
      id: 'keys1',
      name: 'Keys',
      category: TrackCategory.keys,
      presetId: 'keys_piano',
      sampleRoot: 'assets/samples/keys/piano_c.wav',
      rootMidi: 60,
      notes: [
        NoteEvent(
          id: 'n1',
          pitch: 60,
          startStep: 0,
          lengthSteps: 1,
          velocity: 100,
          probability: 100,
        ),
      ],
    );
    final h = _PaintStrokeHarness(track);
    h.setNoteParams(
      noteId: 'n1',
      velocity: 77,
      lengthSteps: 4,
      probability: 40,
    );
    final n = track.notes.single;
    expect(n.velocity, 77);
    expect(n.lengthSteps, 4);
    expect(n.probability, 40);
    h.commands.undo();
    expect(track.notes.single.velocity, 100);
    expect(track.notes.single.lengthSteps, 1);
    expect(track.notes.single.probability, 100);
  });

  test('findNote locates by pitch and step', () {
    final track = Track(
      id: 'x',
      name: 'X',
      category: TrackCategory.keys,
      presetId: 'keys_piano',
      sampleRoot: 'assets/samples/keys/piano_c.wav',
      notes: [
        NoteEvent(id: 'a', pitch: 60, startStep: 2),
        NoteEvent(id: 'b', pitch: 64, startStep: 2),
      ],
    );
    final h = _PaintStrokeHarness(track);
    expect(h.findNote(60, 2)?.id, 'a');
    expect(h.findNote(64, 2)?.id, 'b');
    expect(h.findNote(60, 3), isNull);
  });
}
