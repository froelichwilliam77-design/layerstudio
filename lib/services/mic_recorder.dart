import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

/// Armed-track mic capture to a WAV file (not sample-accurate punch-in).
class MicRecorder {
  MicRecorder();

  final AudioRecorder _recorder = AudioRecorder();
  final _uuid = const Uuid();
  String? _activePath;
  bool get isRecording => _activePath != null;

  Future<bool> hasPermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (e) {
      debugPrint('mic permission check failed: $e');
      return false;
    }
  }

  Future<String?> start() async {
    if (!await hasPermission()) {
      throw StateError('Microphone permission denied');
    }
    final dir = await getApplicationDocumentsDirectory();
    final recDir = Directory(p.join(dir.path, 'recordings'));
    if (!await recDir.exists()) await recDir.create(recursive: true);
    final path = p.join(recDir.path, 'take_${_uuid.v4()}.wav');
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 44100,
        numChannels: 1,
        bitRate: 256000,
      ),
      path: path,
    );
    _activePath = path;
    return path;
  }

  Future<String?> stop() async {
    final path = _activePath;
    _activePath = null;
    try {
      final out = await _recorder.stop();
      return out ?? path;
    } catch (e) {
      debugPrint('mic stop failed: $e');
      return path;
    }
  }

  Future<void> cancel() async {
    try {
      await _recorder.cancel();
    } catch (_) {}
    _activePath = null;
  }

  Future<void> dispose() async {
    await cancel();
    await _recorder.dispose();
  }
}
