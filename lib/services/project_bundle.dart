import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../data/sound_library.dart';
import '../models/project.dart';
import '../utils/share_sheet.dart';
import 'project_store.dart';

/// Portable `.layerstudio` zip: project.json + samples/ for referenced WAVs.
class ProjectBundleService {
  ProjectBundleService({ProjectStore? store})
    : _store = store ?? ProjectStore();

  final ProjectStore _store;
  final _uuid = const Uuid();

  static const manifestName = 'project.json';
  static const samplesDir = 'samples';

  /// Build a zip archive bytes for [project], embedding used sample WAVs.
  Future<Uint8List> buildArchiveBytes(StudioProject project) async {
    final archive = Archive();
    final sampleMap = <String, String>{}; // original path -> zip relative

    Future<void> embed(String path) async {
      if (sampleMap.containsKey(path)) return;
      final bytes = await _readSampleBytes(path);
      if (bytes == null) return;
      final safe = _safeName(path);
      var name = safe;
      var i = 0;
      while (sampleMap.values.contains('$samplesDir/$name')) {
        i++;
        name = '${p.basenameWithoutExtension(safe)}_$i${p.extension(safe)}';
      }
      final rel = '$samplesDir/$name';
      sampleMap[path] = rel;
      archive.addFile(ArchiveFile(rel, bytes.length, bytes));
    }

    for (final track in project.tracks) {
      await embed(track.sampleRoot);
      final rec = track.recordedFilePath;
      if (rec != null && rec.isNotEmpty) await embed(rec);
      final preset = SoundLibrary.byId(track.presetId);
      final kit = preset?.drumKit;
      if (kit != null) {
        for (final path in kit.values) {
          await embed(path);
        }
      }
    }

    final json = Map<String, dynamic>.from(project.toJson());
    json['bundleVersion'] = 1;
    json['embeddedSamples'] = sampleMap;
    final jsonBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(json),
    );
    archive.addFile(ArchiveFile(manifestName, jsonBytes.length, jsonBytes));

    final encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded);
  }

  Future<File> exportToTempFile(StudioProject project) async {
    final bytes = await buildArchiveBytes(project);
    final dir = await getTemporaryDirectory();
    final safe = project.name.replaceAll(RegExp(r'[^\w\-]+'), '_');
    final file = File('${dir.path}/$safe.layerstudio');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> shareProject(StudioProject project, {Rect? shareOrigin}) async {
    final file = await exportToTempFile(project);
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(
            file.path,
            mimeType: 'application/zip',
            name: p.basename(file.path),
          ),
        ],
        text: 'LayerStudio project: ${project.name}',
        sharePositionOrigin: shareOrigin ?? shareSheetOriginFallback,
      ),
    );
  }

  /// Import a `.layerstudio` / zip file into the local store; returns project.
  Future<StudioProject> importFromFile(File file) async {
    final bytes = await file.readAsBytes();
    return importFromBytes(bytes);
  }

  Future<StudioProject> importFromBytes(Uint8List bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    final manifestFile = archive.findFile(manifestName);
    if (manifestFile == null) {
      throw StateError('Invalid project bundle: missing $manifestName');
    }
    final json =
        jsonDecode(utf8.decode(manifestFile.content)) as Map<String, dynamic>;

    final embedded =
        (json['embeddedSamples'] as Map?)?.cast<String, String>() ?? {};
    final samplesRoot = await _importedSamplesDir();

    final rewritten = <String, String>{};
    for (final entry in embedded.entries) {
      final original = entry.key;
      final rel = entry.value;
      final af = archive.findFile(rel);
      if (af == null) continue;
      final outName = '${_uuid.v4()}_${p.basename(rel)}';
      final out = File(p.join(samplesRoot.path, outName));
      await out.writeAsBytes(af.content, flush: true);
      rewritten[original] = out.path;
    }

    // Fresh id so import never clobbers an existing project silently.
    json['id'] = _uuid.v4();
    json['updatedAt'] = DateTime.now().toIso8601String();

    final project = StudioProject.fromJson(json);
    for (final track in project.tracks) {
      if (rewritten.containsKey(track.sampleRoot)) {
        track.sampleRoot = rewritten[track.sampleRoot]!;
      } else if (track.sampleRoot.startsWith('assets/')) {
        // Keep asset path — available in this install.
      }
      // Drum kits stay as asset paths via presetId; custom kit files would
      // need path rewrite in a future schema. Bundled kits use assets.
    }

    // Prefer built-in assets when the preset still exists (smaller on disk).
    for (final track in project.tracks) {
      final preset = SoundLibrary.byId(track.presetId);
      if (preset != null && track.sampleRoot.startsWith('/')) {
        // Imported copy exists; keep it for portability across machines.
      } else if (preset != null && !File(track.sampleRoot).existsSync()) {
        track.sampleRoot = preset.samplePath;
      }
    }

    await _store.save(project);
    return project;
  }

  Future<Uint8List?> _readSampleBytes(String path) async {
    try {
      if (path.startsWith('assets/')) {
        final data = await rootBundle.load(path);
        return data.buffer.asUint8List();
      }
      final f = File(path.startsWith('file:') ? path.substring(5) : path);
      if (await f.exists()) return await f.readAsBytes();
    } catch (e) {
      // ignore missing
    }
    return null;
  }

  Future<Directory> _importedSamplesDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/layerstudio/imported_samples');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _safeName(String path) {
    final base = p.basename(path);
    return base.replaceAll(RegExp(r'[^\w.\-]+'), '_');
  }
}
