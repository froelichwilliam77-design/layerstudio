import 'package:flutter_test/flutter_test.dart';
import 'package:layerstudio/models/project.dart';
import 'package:layerstudio/models/note_event.dart';

void main() {
  test('StudioProject JSON roundtrip', () {
    final p = StudioProject(id: '1', name: 'Demo', bpm: 100);
    p.tracks.clear();
    final json = p.toJson();
    final back = StudioProject.fromJson(json);
    expect(back.name, 'Demo');
    expect(back.bpm, 100);
  });

  test('NoteEvent JSON', () {
    final n = NoteEvent(id: 'a', pitch: 60, startStep: 4, velocity: 90);
    final back = NoteEvent.fromJson(n.toJson());
    expect(back.pitch, 60);
    expect(back.startStep, 4);
  });
}
