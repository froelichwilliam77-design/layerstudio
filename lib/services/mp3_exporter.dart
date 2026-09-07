import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_lame_update/flutter_lame.dart';
import 'package:path_provider/path_provider.dart';

/// Encodes stereo float PCM to MP3 via bundled LAME (LGPL).
class Mp3Exporter {
  static const sampleRate = 44100;

  Future<File> encodeStereo({
    required Float64List left,
    required Float64List right,
    required String basename,
    int bitRate = 192,
  }) async {
    if (left.length != right.length) {
      throw ArgumentError('L/R lengths must match');
    }
    final encoder = LameMp3Encoder(
      sampleRate: sampleRate,
      numChannels: 2,
      bitRate: bitRate,
    );
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${basename}_mix.mp3');
    final sink = file.openWrite();
    try {
      const hop = 44100;
      for (var i = 0; i < left.length; i += hop) {
        final end = (i + hop).clamp(0, left.length);
        final frame = await encoder.encodeDouble(
          leftChannel: Float64List.fromList(left.sublist(i, end)),
          rightChannel: Float64List.fromList(right.sublist(i, end)),
        );
        if (frame.isNotEmpty) sink.add(frame);
      }
      final tail = await encoder.flush();
      if (tail.isNotEmpty) sink.add(tail);
    } finally {
      await encoder.close();
      await sink.close();
    }
    return file;
  }
}
