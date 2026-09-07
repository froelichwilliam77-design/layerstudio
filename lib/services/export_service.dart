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
import '../utils/share_sheet.dart';
import '../utils/wav_codec.dart';

/// Offline mixdown to WAV (PCM **16-bit stereo** @ 44.1 kHz with TPDF dither).
/// Optional 24-bit path is available via [bitDepth] for cleaner masters.
/// MP3: share WAV + note that device OS share sheet / external converter
/// can be used; true MP3 needs a native encoder (out of MVP scope).
class ExportService {
  static const sampleRate = 44100;

  /// [bitDepth] 16 (default, TPDF dithered) or 24 (no dither).
  Future<File> exportWav(
    StudioProject project, {
    void Function(double)? onProgress,
    int bitDepth = 16,
  }) async {
    assert(bitDepth == 16 || bitDepth == 24);
    final secondsPerStep = project.secondsPerStep;
    final totalSteps = math.max(project.loopEndStep, project.totalSteps);
    final durationSec = totalSteps * secondsPerStep + 1.5;
    final totalSamples = (durationSec * sampleRate).ceil();
    final mixL = Float64List(totalSamples);
    final mixR = Float64List(totalSamples);

    final anySolo = project.tracks.any((t) => t.solo);

    // Cache decoded stereo WAVs
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

    var trackIdx = 0;
    for (final track in project.tracks) {
      if (track.muted) continue;
      if (anySolo && !track.solo) continue;

      final preset = SoundLibrary.byId(track.presetId);
      final kit = preset?.drumKit;
      final gains = panGains(track.pan);

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

        final startSample = (note.startStep * secondsPerStep * sampleRate)
            .round();
        final vel = (note.velocity / 127.0) * track.volume;
        final ratio = track.category == TrackCategory.drums
            ? 1.0
            : MusicTheory.pitchRatio(rootMidi, playPitch).clamp(0.25, 4.0);

        // Resample L/R by rate into note buffers, then FX, then stereo mix
        final outLen = (pcm.frames / ratio).floor();
        final noteL = List<double>.filled(outLen, 0);
        final noteR = List<double>.filled(outLen, 0);
        for (var i = 0; i < outLen; i++) {
          final srcPos = i * ratio;
          final idx = srcPos.floor();
          if (idx + 1 >= pcm.frames) break;
          final frac = srcPos - idx;
          final sL = pcm.left[idx] * (1 - frac) + pcm.left[idx + 1] * frac;
          final sR = pcm.right[idx] * (1 - frac) + pcm.right[idx + 1] * frac;
          noteL[i] = _softClip(sL * vel, track.fx.ampPreset.name);
          noteR[i] = _softClip(sR * vel, track.fx.ampPreset.name);
        }

        // Mini Amp Sim (offline): tone → EQ shelves, gain → drive, cab → LP.
        final tone = track.fx.tone.clamp(0.0, 1.0);
        void applyFx(List<double> buf) {
          SimpleDsp.applyEq(
            buf,
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
          SimpleDsp.applyDrive(buf, amount: driveAmt.clamp(0.0, 1.0));
          if (track.fx.cabSim) {
            SimpleDsp.applyCabLowpass(buf, brightness: tone);
          }
          SimpleDsp.applyCompressor(buf, amount: track.fx.comp);
        }

        applyFx(noteL);
        applyFx(noteR);

        for (var i = 0; i < noteL.length; i++) {
          final dest = startSample + i;
          if (dest < 0 || dest >= mixL.length) continue;
          final sL = noteL[i] * gains.l;
          final sR = noteR[i] * gains.r;
          mixL[dest] += sL;
          mixR[dest] += sR;

          // Crude stereo space (not full Freeverb / Echo parity):
          // short cross-fed reverb taps + delay on both channels.
          if (track.fx.reverb > 0.05) {
            final d1 = dest + (sampleRate * 0.04).round();
            if (d1 < mixL.length) {
              mixL[d1] += sL * track.fx.reverb * 0.32;
              mixR[d1] += sR * track.fx.reverb * 0.32;
            }
            final d2 = dest + (sampleRate * 0.053).round();
            if (d2 < mixL.length) {
              mixL[d2] += sR * track.fx.reverb * 0.18;
              mixR[d2] += sL * track.fx.reverb * 0.18;
            }
          }
          if (track.fx.delay > 0.05) {
            final d = dest + (sampleRate * 0.25).round();
            if (d < mixL.length) {
              mixL[d] += sL * track.fx.delay * 0.4;
              mixR[d] += sR * track.fx.delay * 0.38;
            }
            final dR = dest + (sampleRate * 0.255).round();
            if (dR < mixR.length) {
              mixR[dR] += sL * track.fx.delay * 0.12;
            }
          }
        }
      }
      trackIdx++;
      onProgress?.call(trackIdx / math.max(1, project.tracks.length));
    }

    peakNormalizeStereo(mixL, mixR, targetPeak: 0.95);

    final Uint8List bytes;
    if (bitDepth == 24) {
      final pcm24 = quantizePcm24Stereo(mixL, mixR);
      bytes = encodeWavPcm24Stereo(pcm24, sampleRate);
    } else {
      final pcm16 = quantizePcm16Stereo(
        mixL,
        mixR,
        dither: true,
        random: math.Random(),
      );
      bytes = encodeWavPcm16Stereo(pcm16, sampleRate);
    }

    final dir = await getTemporaryDirectory();
    final safe = project.name.replaceAll(RegExp(r'[^\w\-]+'), '_');
    final file = File('${dir.path}/${safe}_mix.wav');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> shareFile(File file, {Rect? shareOrigin}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'audio/wav')],
        text: 'Made with LayerStudio',
        sharePositionOrigin: shareOrigin ?? shareSheetOriginFallback,
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
}
