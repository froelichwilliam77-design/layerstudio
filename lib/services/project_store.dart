import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/project.dart';

class ProjectStore {
  Future<Directory> _projectsDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/layerstudio/projects');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _fileFor(String id) async {
    final dir = await _projectsDir();
    return File('${dir.path}/$id.json');
  }

  Future<List<StudioProject>> listProjects() async {
    final dir = await _projectsDir();
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.json'))
        .cast<File>()
        .toList();
    final projects = <StudioProject>[];
    for (final f in files) {
      try {
        final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        projects.add(StudioProject.fromJson(json));
      } catch (_) {}
    }
    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return projects;
  }

  Future<void> save(StudioProject project) async {
    project.updatedAt = DateTime.now();
    final file = await _fileFor(project.id);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(project.toJson()),
    );
  }

  Future<StudioProject?> load(String id) async {
    final file = await _fileFor(id);
    if (!await file.exists()) return null;
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return StudioProject.fromJson(json);
  }

  Future<void> delete(String id) async {
    final file = await _fileFor(id);
    if (await file.exists()) await file.delete();
  }
}
