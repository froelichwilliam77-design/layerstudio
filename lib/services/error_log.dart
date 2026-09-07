import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Lightweight in-app error ring buffer (no Firebase / no accounts).
/// Also persists the last entries to app documents for crash forensics.
class ErrorLog {
  ErrorLog._();
  static final ErrorLog instance = ErrorLog._();

  static const _max = 40;
  final List<String> _lines = [];

  String? get lastError => _lines.isEmpty ? null : _lines.last;

  List<String> get lines => List.unmodifiable(_lines);

  void record(Object error, [StackTrace? stack]) {
    final line =
        '${DateTime.now().toIso8601String()} $error${stack != null ? '\n$stack' : ''}';
    _lines.add(line);
    if (_lines.length > _max) _lines.removeAt(0);
    debugPrint('ErrorLog: $error');
    unawaitedPersist();
  }

  void unawaitedPersist() {
    persist().then((_) {}, onError: (Object e) {
      debugPrint('ErrorLog persist failed: $e');
    });
  }

  Future<File?> persist() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'layerstudio', 'error_log.txt'));
      await file.parent.create(recursive: true);
      await file.writeAsString(_lines.join('\n---\n'), flush: true);
      return file;
    } catch (e) {
      debugPrint('ErrorLog persist failed: $e');
      return null;
    }
  }

  Future<void> copyLastToClipboard() async {
    final text = lastError ?? 'No errors recorded.';
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> copyAllToClipboard() async {
    await Clipboard.setData(ClipboardData(text: _lines.join('\n---\n')));
  }

  void clear() => _lines.clear();
}
