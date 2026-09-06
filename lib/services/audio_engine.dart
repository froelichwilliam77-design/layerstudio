import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../utils/music_theory.dart';

/// Low-latency sample playback via flutter_soloud (SoLoud).
/// Architecture leaves room for native Oboe / AudioUnit backends later.
class AudioEngine {
  AudioEngine._();
  static final AudioEngine instance = AudioEngine._();

  final SoLoud _soloud = SoLoud.instance;
  final Map<String, AudioSource> _sources = {};
  bool _ready = false;
  bool get isReady => _ready;

  /// Initialize the audio device. Call once at app start.
  Future<void> init() async {
    if (_ready) return;
    try {
      // Smaller buffer = lower latency for pads/sequencer (see SoLoud metronome docs).
      await _soloud.init(
        bufferSize: 1024,
        channels: Channels.stereo,
        sampleRate: 44100,
      );
      _ready = true;
    } catch (e, st) {
      debugPrint('AudioEngine init failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> dispose() async {
    try {
      for (final s in _sources.values) {
        await _soloud.disposeSource(s);
      }
      _sources.clear();
      if (_soloud.isInitialized) {
        _soloud.deinit();
      }
    } catch (_) {}
    _ready = false;
  }

  Future<AudioSource?> loadAsset(String assetPath) async {
    if (!_ready) await init();
    if (_sources.containsKey(assetPath)) return _sources[assetPath];
    try {
      final src = await _soloud.loadAsset(assetPath);
      _sources[assetPath] = src;
      return src;
    } catch (e) {
      debugPrint('Failed to load $assetPath: $e');
      return null;
    }
  }

  Future<void> preload(Iterable<String> paths) async {
    for (final p in paths) {
      await loadAsset(p);
    }
  }

  /// Play a one-shot sample. [pitchMidi]/[rootMidi] set playback rate for pitch.
  Future<SoundHandle?> playSample(
    String assetPath, {
    double volume = 1.0,
    double pan = 0.0,
    int? pitchMidi,
    int rootMidi = 60,
  }) async {
    if (!_ready) return null;
    final src = await loadAsset(assetPath);
    if (src == null) return null;
    try {
      final handle = await _soloud.play(
        src,
        volume: volume.clamp(0.0, 1.5),
        pan: pan.clamp(-1.0, 1.0),
      );
      if (pitchMidi != null && pitchMidi != rootMidi) {
        final ratio = MusicTheory.pitchRatio(rootMidi, pitchMidi);
        // Clamp extreme pitches to keep sample usable.
        _soloud.setRelativePlaySpeed(handle, ratio.clamp(0.25, 4.0));
      }
      return handle;
    } catch (e) {
      debugPrint('playSample error: $e');
      return null;
    }
  }

  Future<void> stopAll() async {
    if (!_ready) return;
    try {
      for (final src in _soloud.activeSounds) {
        for (final handle in src.handles.toList()) {
          await _soloud.stop(handle);
        }
      }
    } catch (_) {}
  }

  /// Apply simple global FX (reverb/echo) — demo-level, not per-track bus.
  void applyGlobalFx({required double reverb, required double delay}) {
    if (!_ready) return;
    try {
      if (reverb > 0.01) {
        _soloud.filters.freeverbFilter.activate();
        _soloud.filters.freeverbFilter.wet.value = reverb.clamp(0.0, 1.0);
        _soloud.filters.freeverbFilter.roomSize.value = 0.5 + reverb * 0.4;
      } else {
        try {
          _soloud.filters.freeverbFilter.deactivate();
        } catch (_) {}
      }
      if (delay > 0.01) {
        _soloud.filters.echoFilter.activate();
        _soloud.filters.echoFilter.delay.value = 0.2 + delay * 0.4;
        _soloud.filters.echoFilter.decay.value = 0.3 + delay * 0.4;
        _soloud.filters.echoFilter.wet.value = delay.clamp(0.0, 0.8);
      } else {
        try {
          _soloud.filters.echoFilter.deactivate();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('FX apply skipped: $e');
    }
  }
}
