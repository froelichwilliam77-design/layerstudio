import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/project.dart';
import '../utils/share_sheet.dart';
import 'project_bundle.dart';
import 'project_store.dart';

/// Zips every local project into one backup archive (Files-app / share sheet).
class ProjectBackup {
  ProjectBackup({
    ProjectStore? store,
    ProjectBundleService? bundle,
  })  : _store = store ?? ProjectStore(),
        _bundle = bundle ?? ProjectBundleService();

  final ProjectStore _store;
  final ProjectBundleService _bundle;

  Future<File> buildArchive(List<StudioProject> projects) async {
    final archive = Archive();
    for (final project in projects) {
      final bytes = await _bundle.buildArchiveBytes(project);
      final safe = project.name.replaceAll(RegExp(r'[^\w\-]+'), '_');
      archive.addFile(
        ArchiveFile('$safe.layerstudio', bytes.length, bytes),
      );
    }
    final encoded = ZipEncoder().encode(archive);
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File(p.join(dir.path, 'LayerStudio-backup-$stamp.zip'));
    await file.writeAsBytes(Uint8List.fromList(encoded), flush: true);
    return file;
  }

  Future<void> shareAll(
    List<StudioProject> projects, {
    Rect? shareOrigin,
  }) async {
    if (projects.isEmpty) return;
    final file = await buildArchive(projects);
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(file.path, mimeType: 'application/zip', name: p.basename(file.path)),
        ],
        text: 'LayerStudio backup (${projects.length} projects)',
        sharePositionOrigin: shareOrigin ?? shareSheetOriginFallback,
      ),
    );
  }

  Future<List<StudioProject>> list() => _store.listProjects();

  String manifestJson(List<StudioProject> projects) =>
      const JsonEncoder.withIndent('  ').convert({
        'kind': 'layerstudio-backup',
        'count': projects.length,
        'names': projects.map((p) => p.name).toList(),
      });
}
