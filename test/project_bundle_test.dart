import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerstudio/models/note_event.dart';
import 'package:layerstudio/models/project.dart';
import 'package:layerstudio/models/track.dart';
import 'package:layerstudio/services/project_bundle.dart';

void main() {
  test('bundle archive contains project.json and roundtrips JSON fields', () async {
    final project = StudioProject(
      id: 'proj-1',
      name: 'Bundle Test',
      bpm: 128,
      key: 'D',
      scale: 'minor',
      bars: 2,
      loopEndStep: 32,
    );
    project.tracks.add(
      Track(
        id: 't1',
        name: 'Keys',
        category: TrackCategory.keys,
        presetId: 'keys_piano',
        sampleRoot: 'assets/samples/keys/piano_c4.wav',
        rootMidi: 60,
        notes: [
          NoteEvent(id: 'n1', pitch: 62, startStep: 0, velocity: 100),
        ],
      ),
    );

    // Unit-level: encode a minimal zip the same way the service does for JSON.
    final archive = Archive();
    final json = Map<String, dynamic>.from(project.toJson());
    json['bundleVersion'] = 1;
    json['embeddedSamples'] = <String, String>{};
    final jsonBytes = utf8.encode(jsonEncode(json));
    archive.addFile(ArchiveFile(ProjectBundleService.manifestName, jsonBytes.length, jsonBytes));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));

    final decoded = ZipDecoder().decodeBytes(bytes);
    final manifest = decoded.findFile(ProjectBundleService.manifestName);
    expect(manifest, isNotNull);
    final backJson =
        jsonDecode(utf8.decode(manifest!.content)) as Map<String, dynamic>;
    final back = StudioProject.fromJson(backJson);
    expect(back.name, 'Bundle Test');
    expect(back.bpm, 128);
    expect(back.tracks.single.notes.single.pitch, 62);
    expect(backJson['bundleVersion'], 1);
  });
}
