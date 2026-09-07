import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../data/sound_library.dart';
import '../models/track.dart';

/// Copies user WAVs into app documents and builds [SoundPreset]s.
class UserSampleStore {
  UserSampleStore();

  final _uuid = const Uuid();

  Future<Directory> _dir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'layerstudio', 'user_samples'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  File _indexFile(Directory dir) => File(p.join(dir.path, 'index.json'));

  Future<SoundPreset> importWav({
    required Uint8List bytes,
    required String originalName,
    required TrackCategory category,
  }) async {
    final dir = await _dir();
    final id = 'user_${_uuid.v4()}';
    final safe = originalName.replaceAll(RegExp(r'[^\w.\-]+'), '_');
    final ext = p.extension(safe).toLowerCase().isEmpty
        ? '.wav'
        : p.extension(safe).toLowerCase();
    final file = File(p.join(dir.path, '$id$ext'));
    await file.writeAsBytes(bytes, flush: true);

    final preset = presetFromFile(
      id: id,
      label: p.basenameWithoutExtension(originalName),
      originalName: originalName,
      path: file.path,
      category: category,
    );
    final existing = await loadAll();
    existing.add(preset);
    await _writeIndex(dir, existing);
    return preset;
  }

  static SoundPreset presetFromFile({
    required String id,
    required String label,
    required String path,
    required TrackCategory category,
    String? originalName,
  }) {
    final rootMidi = switch (category) {
      TrackCategory.drums => 36,
      TrackCategory.bass => 36,
      TrackCategory.guitar => 40,
      TrackCategory.keys => 60,
      TrackCategory.mic => 60,
    };

    final color = switch (category) {
      TrackCategory.drums => 0xFFE07A3D,
      TrackCategory.bass => 0xFF00D4FF,
      TrackCategory.guitar => 0xFF9B6BFF,
      TrackCategory.keys => 0xFF2EE6A6,
      TrackCategory.mic => 0xFF66BB6A,
    };

    return SoundPreset(
      id: id,
      name: label.isEmpty ? 'User sample' : label,
      category: category,
      description: originalName == null
          ? 'Imported WAV'
          : 'Imported from $originalName',
      samplePath: path,
      rootMidi: rootMidi,
      colorValue: color,
      drumKit: category == TrackCategory.drums
          ? {
              'Kick': path,
              'Snare': path,
              'Hat': path,
              'Open Hat': path,
              'Clap': path,
            }
          : null,
    );
  }

  Future<List<SoundPreset>> loadAll() async {
    final dir = await _dir();
    final index = _indexFile(dir);
    if (!await index.exists()) return [];
    try {
      final raw = jsonDecode(await index.readAsString()) as List;
      return raw.map((e) {
        final m = e as Map<String, dynamic>;
        final cat = TrackCategory.values.firstWhere(
          (c) => c.name == m['category'],
          orElse: () => TrackCategory.keys,
        );
        return presetFromFile(
          id: m['id'] as String,
          label: m['name'] as String? ?? 'User sample',
          path: m['samplePath'] as String,
          category: cat,
          originalName: m['originalName'] as String?,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeIndex(Directory dir, List<SoundPreset> presets) async {
    final data = presets
        .map(
          (s) => {
            'id': s.id,
            'name': s.name,
            'category': s.category.name,
            'samplePath': s.samplePath,
            'originalName': s.description,
          },
        )
        .toList();
    await _indexFile(dir).writeAsString(jsonEncode(data), flush: true);
  }
}
