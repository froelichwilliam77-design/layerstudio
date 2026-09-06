import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Lightweight in-app error ring buffer (no Firebase / no accounts).
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
