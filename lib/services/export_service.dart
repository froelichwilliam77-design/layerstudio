import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/sound_library.dart';
import '../models/project.dart';
import '../models/fx_settings.dart';
import '../models/track.dart';
import '../utils/dsp_simple.dart';
import '../utils/music_theory.dart';

/// Offline mixdown to WAV (PCM 16-bit mono @ 44.1kHz).
/// MP3: share WAV + note that device OS share sheet / external converter
/// can be used; true MP3 needs a native encoder (out of MVP scope).
class ExportService {
  static const sampleRate = 44100;

  Future<File> exportWav(StudioProject project, {void Function(double)? onProgress}) async {
    final secondsPerStep = project.secondsPerStep;
    final totalSteps = math.max(project.loopEndStep, project.totalSteps);
    final durationSec = totalSteps * secondsPerStep + 1.5;
    final totalSamples = (durationSec * sampleRate).ceil();
    final mix = Float64List(totalSamples);

    final anySolo = project.tracks.any((t) => t.solo);

    // Cache decoded WAVs
    final cache = <String, Float64List>{};

    Future<Float64List?> loadPcm(String asset) async {
      if (asset.isEmpty) return null;
      if (cache.containsKey(asset)) return cache[asset];
      try {
        final Uint8List bytes;
        if (asset.startsWith('/') || asset.startsWith('file:')) {
          final path = asset.replaceFirst('file:', '');
          bytes = await File(path).readAsBytes();
        } else {
          final data = await rootBundle.load(asset);
          bytes = data.buffer.asUint8List();
        }
        final pcm = _decodeWav(bytes);
        if (pcm != null) cache[asset] = pcm;
        return pcm;
      } catch (_) {
        return null;
      }
    }

    var trackIdx = 0;
    for (final track in project.tracks) {
      if (track.muted) continue;
      if (anySolo && !track.solo) continue;

      final preset = SoundLibrary.byId(track.presetId);
      final kit = preset?.drumKit;

      for (final note in track.notes) {
        String asset = track.sampleRoot;
        var rootMidi = track.rootMidi;
        var playPitch = note.pitch;
        if (track.category == TrackCategory.drums && kit != null) {
          final pad = DrumPadMap.padIndexForPitch(note.pitch);
          final names = kit.keys.toList();
          if (pad < names.length) {
            asset = kit[names[pad]]!;
            rootMidi = note.pitch; // 1:1, no pitch shift for drums
          }
        } else if (track.category != TrackCategory.mic && preset != null) {
          playPitch = preset.clampMidi(note.pitch);
          final resolved = preset.resolveRoot(playPitch);
          asset = resolved.path;
          rootMidi = resolved.rootMidi;
        }

        final pcm = await loadPcm(asset);
        if (pcm == null) continue;

        final startSample =
            (note.startStep * secondsPerStep * sampleRate).round();
        final vel = (note.velocity / 127.0) * track.volume;
        final ratio = track.category == TrackCategory.drums
            ? 1.0
            : MusicTheory.pitchRatio(rootMidi, playPitch).clamp(0.25, 4.0);

        // Simple resample by rate into a note buffer, then FX, then mix
        final outLen = (pcm.length / ratio).floor();
        final noteBuf = List<double>.filled(outLen, 0);
        for (var i = 0; i < outLen; i++) {
          final srcPos = i * ratio;
          final idx = srcPos.floor();
          if (idx + 1 >= pcm.length) break;
          final frac = srcPos - idx;
          final s = pcm[idx] * (1 - frac) + pcm[idx + 1] * frac;
          noteBuf[i] = _softClip(s * vel, track.fx.ampPreset.name);
        }
        // Mini Amp Sim (offline): tone → EQ shelves, gain → drive, cab → LP.
        final tone = track.fx.tone.clamp(0.0, 1.0);
        SimpleDsp.applyEq(
          noteBuf,
          low: (track.fx.eqLow + (1 - tone) * 0.25).clamp(-1.0, 1.0),
          mid: track.fx.eqMid,
          high: (track.fx.eqHigh + (tone * 2 - 1) * 0.55).clamp(-1.0, 1.0),
        );
        final driveAmt = switch (track.fx.ampPreset) {
          AmpPreset.none => track.fx.gain * 0.35,
          AmpPreset.clean => 0.1 + track.fx.gain * 0.45,
          AmpPreset.crunch => 0.35 + track.fx.gain * 0.45,
          AmpPreset.highGain => 0.55 + track.fx.gain * 0.4,
          AmpPreset.bassDrive => 0.3 + track.fx.gain * 0.5,
        };
        SimpleDsp.applyDrive(noteBuf, amount: driveAmt.clamp(0.0, 1.0));
        if (track.fx.cabSim) {
          SimpleDsp.applyCabLowpass(noteBuf, brightness: tone);
        }
        SimpleDsp.applyCompressor(noteBuf, amount: track.fx.comp);
        for (var i = 0; i < noteBuf.length; i++) {
          final dest = startSample + i;
          if (dest < 0 || dest >= mix.length) continue;
          final sample = noteBuf[i];
          mix[dest] += sample;
          if (track.fx.reverb > 0.05) {
            final d = dest + (sampleRate * 0.04).round();
            if (d < mix.length) mix[d] += sample * track.fx.reverb * 0.35;
          }
          if (track.fx.delay > 0.05) {
            final d = dest + (sampleRate * 0.25).round();
            if (d < mix.length) mix[d] += sample * track.fx.delay * 0.4;
          }
        }
      }
      trackIdx++;
      onProgress?.call(trackIdx / math.max(1, project.tracks.length));
    }

    // Normalize lightly
    var peak = 0.0;
    for (final s in mix) {
      final a = s.abs();
      if (a > peak) peak = a;
    }
    final norm = peak > 0.95 ? 0.95 / peak : 1.0;

    final pcm16 = Int16List(mix.length);
    for (var i = 0; i < mix.length; i++) {
      pcm16[i] = (mix[i] * norm * 32767).round().clamp(-32767, 32767);
    }

    final bytes = _encodeWav(pcm16, sampleRate);
    final dir = await getTemporaryDirectory();
    final safe = project.name.replaceAll(RegExp(r'[^\w\-]+'), '_');
    final file = File('${dir.path}/${safe}_mix.wav');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> shareFile(File file) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'audio/wav')],
        text: 'Made with LayerStudio',
      ),
    );
  }

  double _softClip(double s, String amp) {
    final drive = switch (amp) {
      'crunch' => 2.5,
      'highGain' => 5.0,
      'bassDrive' => 2.0,
      _ => 1.0,
    };
    if (drive <= 1.0) return s;
    // Soft clip without relying on math.tanh (analyzer quirks on some SDKs).
    final x = s * drive;
    final e = math.exp(2.0 * x.clamp(-20.0, 20.0));
    return (e - 1.0) / (e + 1.0);
  }

  Float64List? _decodeWav(Uint8List data) {
    if (data.length < 44) return null;
    // Minimal PCM WAV parser
    final bd = ByteData.sublistView(data);
    if (String.fromCharCodes(data.sublist(0, 4)) != 'RIFF') return null;
    if (String.fromCharCodes(data.sublist(8, 12)) != 'WAVE') return null;

    var offset = 12;
    int? channels;
    int? bits;
    int? dataOffset;
    int? dataSize;
    while (offset + 8 <= data.length) {
      final id = String.fromCharCodes(data.sublist(offset, offset + 4));
      final size = bd.getUint32(offset + 4, Endian.little);
      if (id == 'fmt ') {
        channels = bd.getUint16(offset + 10, Endian.little);
        bits = bd.getUint16(offset + 22, Endian.little);
      } else if (id == 'data') {
        dataOffset = offset + 8;
        dataSize = size;
        break;
      }
      offset += 8 + size;
      if (size.isOdd) offset++;
    }
    if (dataOffset == null || channels == null || bits == null) return null;

    final bytesPerSample = bits ~/ 8;
    final frameCount = dataSize! ~/ (bytesPerSample * channels);
    final out = Float64List(frameCount);
    for (var i = 0; i < frameCount; i++) {
      final pos = dataOffset + i * bytesPerSample * channels;
      double sample = 0;
      if (bits == 16) {
        sample = bd.getInt16(pos, Endian.little) / 32768.0;
      } else if (bits == 8) {
        sample = (data[pos] - 128) / 128.0;
      }
      out[i] = sample;
    }
    return out;
  }

  Uint8List _encodeWav(Int16List pcm, int sr) {
    final dataSize = pcm.length * 2;
    final buffer = ByteData(44 + dataSize);
    void writeStr(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        buffer.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    writeStr(0, 'RIFF');
    buffer.setUint32(4, 36 + dataSize, Endian.little);
    writeStr(8, 'WAVE');
    writeStr(12, 'fmt ');
    buffer.setUint32(16, 16, Endian.little);
    buffer.setUint16(20, 1, Endian.little); // PCM
    buffer.setUint16(22, 1, Endian.little); // mono
    buffer.setUint32(24, sr, Endian.little);
    buffer.setUint32(28, sr * 2, Endian.little);
    buffer.setUint16(32, 2, Endian.little);
    buffer.setUint16(34, 16, Endian.little);
    writeStr(36, 'data');
    buffer.setUint32(40, dataSize, Endian.little);
    var o = 44;
    for (final s in pcm) {
      buffer.setInt16(o, s, Endian.little);
      o += 2;
    }
    return buffer.buffer.asUint8List();
  }
}
