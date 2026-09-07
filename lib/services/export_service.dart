import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/sound_library.dart';
import '../models/note_event.dart';
import '../models/project.dart';
import '../models/track.dart';
import '../utils/dsp_simple.dart';
import '../utils/mixer_routing.dart';
import '../utils/music_theory.dart';
import '../utils/offline_fx.dart';
import '../utils/share_sheet.dart';
import '../utils/wav_codec.dart';
import 'mp3_exporter.dart';

enum MixExportFormat { wav16, wav24, mp3 }

/// Offline mixdown to WAV (PCM **16-bit stereo** @ 44.1 kHz with TPDF dither)
/// or MP3 via bundled LAME (LGPL). FX chain mirrors live SoLoud inserts.
class ExportService {
  static const sampleRate = 44100;

  Future<File> exportMix(
    StudioProject project, {
    MixExportFormat format = MixExportFormat.wav16,
    void Function(double)? onProgress,
  }) async {
    final mix = await renderStereo(project, onProgress: onProgress);
    final dir = await getTemporaryDirectory();
    final safe = project.name.replaceAll(RegExp(r'[^\w\-]+'), '_');
    if (format == MixExportFormat.mp3) {
      return Mp3Exporter().encodeStereo(
        left: mix.left,
        right: mix.right,
        basename: safe,
      );
    }
    final bitDepth = format == MixExportFormat.wav24 ? 24 : 16;
    final Uint8List bytes;
    if (bitDepth == 24) {
      final pcm24 = quantizePcm24Stereo(mix.left, mix.right);
      bytes = encodeWavPcm24Stereo(pcm24, sampleRate);
    } else {
      final pcm16 = quantizePcm16Stereo(
        mix.left,
        mix.right,
        dither: true,
        random: math.Random(),
      );
      bytes = encodeWavPcm16Stereo(pcm16, sampleRate);
    }
    final ext = bitDepth == 24 ? 'wav' : 'wav';
    final file = File('${dir.path}/${safe}_mix.$ext');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// [bitDepth] 16 (default, TPDF dithered) or 24 (no dither).
  Future<File> exportWav(
    StudioProject project, {
    void Function(double)? onProgress,
    int bitDepth = 16,
  }) {
    return exportMix(
      project,
      format: bitDepth == 24 ? MixExportFormat.wav24 : MixExportFormat.wav16,
      onProgress: onProgress,
    );
  }

  Future<StereoPcm> renderStereo(
    StudioProject project, {
    void Function(double)? onProgress,
  }) async {
    final secondsPerStep = project.secondsPerStep;
    final totalSteps = _mixLengthSteps(project);
    final durationSec = totalSteps * secondsPerStep + 1.5;
    final totalSamples = (durationSec * sampleRate).ceil();
    final mixL = Float64List(totalSamples);
    final mixR = Float64List(totalSamples);

    final cache = <String, StereoPcm>{};

    Future<StereoPcm?> loadPcm(String asset) async {
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
        final pcm = decodeWavStereo(bytes);
        if (pcm != null) cache[asset] = pcm;
        return pcm;
      } catch (_) {
        return null;
      }
    }

    final events = flattenMixEvents(project);
    var idx = 0;
    for (final event in events) {
      final track = event.track;
      if (!isTrackAudible(track, project: project, honorCue: false)) {
        continue;
      }
      final note = event.note;
      String asset = track.sampleRoot;
      var rootMidi = track.rootMidi;
      var playPitch = note.pitch;
      final preset = SoundLibrary.byId(track.presetId);
      final kit = preset?.drumKit;
      if (track.category == TrackCategory.drums && kit != null) {
        final pad = DrumPadMap.padIndexForPitch(note.pitch);
        final names = kit.keys.toList();
        if (pad < names.length) {
          asset = kit[names[pad]]!;
          rootMidi = note.pitch;
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

      final outLen = math.max(1, (pcm.frames / ratio).floor());
      final noteL = List<double>.filled(outLen, 0);
      final noteR = List<double>.filled(outLen, 0);
      for (var i = 0; i < outLen; i++) {
        final srcPos = i * ratio;
        noteL[i] = OfflineFx.cubicAt(pcm.left, srcPos) * vel;
        noteR[i] = OfflineFx.cubicAt(pcm.right, srcPos) * vel;
      }

      OfflineFx.applyVoiceChain(noteL, noteR, fx: track.fx, sampleRate: sampleRate);
      SimpleDsp.applyEq(noteL, low: track.fx.eqLow, mid: track.fx.eqMid, high: track.fx.eqHigh);
      SimpleDsp.applyEq(noteR, low: track.fx.eqLow, mid: track.fx.eqMid, high: track.fx.eqHigh);
      SimpleDsp.applyCompressor(noteL, amount: track.fx.comp);
      SimpleDsp.applyCompressor(noteR, amount: track.fx.comp);

      final gains = panGains(track.pan);
      for (var i = 0; i < noteL.length; i++) {
        final dest = startSample + i;
        if (dest < 0 || dest >= mixL.length) continue;
        mixL[dest] += noteL[i] * gains.l;
        mixR[dest] += noteR[i] * gains.r;
      }
      idx++;
      onProgress?.call(idx / math.max(1, events.length));
    }

    peakNormalizeStereo(mixL, mixR, targetPeak: 0.95);
    return StereoPcm(mixL, mixR);
  }

  static int _mixLengthSteps(StudioProject project) {
    if (project.songMode && project.arrangement.isNotEmpty) {
      return math.max(project.arrangementEndBar * project.stepsPerBar, 16);
    }
    return math.max(project.loopEndStep, project.totalSteps);
  }

  /// Pattern-mode uses live track notes; song mode expands arrangement clips.
  static List<({Track track, NoteEvent note})> flattenMixEvents(
    StudioProject project,
  ) {
    final out = <({Track track, NoteEvent note})>[];
    if (project.songMode && project.arrangement.isNotEmpty) {
      for (final clip in project.arrangement) {
        final matches = project.patterns.where((x) => x.id == clip.patternId);
        if (matches.isEmpty) continue;
        final pat = matches.first;
        final offset = clip.startBar * project.stepsPerBar;
        final clipSteps = clip.lengthBars * project.stepsPerBar;
        for (final track in project.tracks) {
          for (final note in pat.notesFor(track.id)) {
            if (note.startStep < 0 || note.startStep >= clipSteps) continue;
            out.add((
              track: track,
              note: note.copyWith(startStep: note.startStep + offset),
            ));
          }
        }
      }
      return out;
    }
    for (final track in project.tracks) {
      for (final note in track.notes) {
        out.add((track: track, note: note));
      }
    }
    return out;
  }

  Future<void> shareFile(File file, {Rect? shareOrigin}) async {
    final name = p.basename(file.path);
    final mime = name.toLowerCase().endsWith('.mp3') ? 'audio/mpeg' : 'audio/wav';
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mime, name: name)],
        text: 'Made with LayerStudio',
        sharePositionOrigin: shareOrigin ?? shareSheetOriginFallback,
      ),
    );
  }
}
