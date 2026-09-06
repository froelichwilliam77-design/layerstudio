import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../models/fx_settings.dart';
import '../utils/music_theory.dart';

/// Callbacks so StudioController can keep Play state honest.
typedef AudioInterruptionCallback = void Function({required bool began});
typedef AudioBecomingNoisyCallback = void Function();

/// Low-latency sample playback via flutter_soloud (SoLoud).
///
/// Transport timing uses [AudioEngine.transportSeconds] (Stopwatch anchored at
/// play) as the sequencer source of truth; a short Timer only polls for UI +
/// lookahead scheduling — it does not define when notes fire.
class AudioEngine {
  AudioEngine._();
  static final AudioEngine instance = AudioEngine._();

  final SoLoud _soloud = SoLoud.instance;
  final Map<String, AudioSource> _sources = {};
  final Set<String> _fxPrepared = {};

  bool _ready = false;
  bool get isReady => _ready;

  AudioSession? _session;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _noisySub;

  AudioInterruptionCallback? onInterruption;
  AudioBecomingNoisyCallback? onBecomingNoisy;

  /// Monotonic transport clock (audio-side). Null when stopped/paused.
  Stopwatch? _transportWatch;
  double _transportOriginSeconds = 0;

  /// Seconds of musical transport time since play (or seek) anchor.
  double get transportSeconds {
    final w = _transportWatch;
    if (w == null || !w.isRunning) {
      return _transportOriginSeconds;
    }
    return _transportOriginSeconds + w.elapsedMicroseconds / 1e6;
  }

  bool get isTransportRunning =>
      _transportWatch != null && _transportWatch!.isRunning;

  /// Initialize audio session + SoLoud device. Call once at app start.
  Future<void> init() async {
    if (_ready) return;
    try {
      await _configureSession();
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

  Future<void> _configureSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _session = session;

      await _interruptionSub?.cancel();
      await _noisySub?.cancel();

      _interruptionSub = session.interruptionEventStream.listen((event) {
        onInterruption?.call(began: event.begin);
      });
      _noisySub = session.becomingNoisyEventStream.listen((_) {
        onBecomingNoisy?.call();
      });
    } catch (e) {
      debugPrint('audio_session configure skipped: $e');
    }
  }

  /// Request audio focus / activate session before playback.
  Future<void> activateSession() async {
    try {
      await (_session ?? await AudioSession.instance).setActive(true);
    } catch (e) {
      debugPrint('audio_session setActive(true) failed: $e');
    }
  }

  Future<void> deactivateSession() async {
    try {
      await (_session ?? await AudioSession.instance).setActive(false);
    } catch (_) {}
  }

  /// Start or resume the transport clock at [originSeconds] musical time.
  void startTransportClock({double originSeconds = 0}) {
    _transportOriginSeconds = originSeconds;
    _transportWatch = Stopwatch()..start();
  }

  /// Pause transport clock; keeps current musical time as origin.
  void pauseTransportClock() {
    final w = _transportWatch;
    if (w != null && w.isRunning) {
      _transportOriginSeconds += w.elapsedMicroseconds / 1e6;
      w.stop();
    }
  }

  /// Stop and reset transport clock to [originSeconds].
  void stopTransportClock({double originSeconds = 0}) {
    _transportWatch?.stop();
    _transportWatch = null;
    _transportOriginSeconds = originSeconds;
  }

  /// Re-anchor clock without stopping (e.g. after loop wrap or seek while playing).
  void seekTransportClock(double originSeconds) {
    _transportOriginSeconds = originSeconds;
    if (_transportWatch != null) {
      _transportWatch!
        ..reset()
        ..start();
    }
  }

  Future<void> dispose() async {
    await _interruptionSub?.cancel();
    await _noisySub?.cancel();
    _interruptionSub = null;
    _noisySub = null;
    stopTransportClock();
    try {
      for (final s in _sources.values) {
        await _soloud.disposeSource(s);
      }
      _sources.clear();
      _fxPrepared.clear();
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
      _prepareSourceFx(src, assetPath);
      return src;
    } catch (e) {
      debugPrint('Failed to load $assetPath: $e');
      return null;
    }
  }

  Future<AudioSource?> loadFile(String filePath) async {
    if (!_ready) await init();
    final key = 'file:$filePath';
    if (_sources.containsKey(key)) return _sources[key];
    try {
      final src = await _soloud.loadFile(filePath);
      _sources[key] = src;
      _prepareSourceFx(src, key);
      return src;
    } catch (e) {
      debugPrint('Failed to load file $filePath: $e');
      return null;
    }
  }

  Future<void> preload(Iterable<String> paths) async {
    for (final p in paths) {
      await loadAsset(p);
    }
  }

  /// Activate insert FX on an [AudioSource] once (Echo + WaveShaper; Freeverb if possible).
  void _prepareSourceFx(AudioSource src, String key) {
    if (_fxPrepared.contains(key)) return;
    try {
      // Clear legacy global filters so live mix is per-source.
      try {
        _soloud.filters.freeverbFilter.deactivate();
      } catch (_) {}
      try {
        _soloud.filters.echoFilter.deactivate();
      } catch (_) {}

      src.filters.echoFilter.activate();
      src.filters.waveShaperFilter.activate();
      // Freeverb needs stereo sources; bundled WAVs are mono — activate may fail.
      try {
        src.filters.freeverbFilter.activate();
      } catch (e) {
        debugPrint('Freeverb insert skipped for $key (likely mono): $e');
      }
      _fxPrepared.add(key);
    } catch (e) {
      debugPrint('prepareSourceFx failed for $key: $e');
    }
  }

  void _applyVoiceFx(AudioSource src, SoundHandle handle, FxSettings? fx) {
    if (fx == null) return;
    try {
      final delay = fx.delay.clamp(0.0, 1.0);
      final reverb = fx.reverb.clamp(0.0, 1.0);

      // Per-handle echo = delay send.
      src.filters.echoFilter.delay(soundHandle: handle).value =
          0.18 + delay * 0.45;
      src.filters.echoFilter.decay(soundHandle: handle).value =
          0.25 + delay * 0.5;
      src.filters.echoFilter.wet(soundHandle: handle).value =
          (delay * 0.75).clamp(0.0, 0.85);

      // Amp via waveshaper amount (0 = clean, higher = drive).
      final amount = switch (fx.ampPreset) {
        AmpPreset.none || AmpPreset.clean => 0.0,
        AmpPreset.crunch => 0.35,
        AmpPreset.highGain => 0.7,
        AmpPreset.bassDrive => 0.4,
      };
      src.filters.waveShaperFilter.amount(soundHandle: handle).value =
          amount.clamp(-1.0, 1.0);
      src.filters.waveShaperFilter.wet(soundHandle: handle).value =
          amount > 0.01 ? 0.85 : 0.0;

      // Freeverb per-handle when the insert is active (stereo sources).
      if (src.filters.freeverbFilter.isActive) {
        src.filters.freeverbFilter.wet(soundHandle: handle).value = reverb;
        src.filters.freeverbFilter.roomSize(soundHandle: handle).value =
            0.45 + reverb * 0.45;
      } else if (reverb > 0.05) {
        // Mono pack fallback: blend a little extra echo wet as "space".
        final wet = src.filters.echoFilter.wet(soundHandle: handle).value;
        src.filters.echoFilter.wet(soundHandle: handle).value =
            (wet + reverb * 0.35).clamp(0.0, 0.9);
        src.filters.echoFilter.decay(soundHandle: handle).value =
            (0.3 + reverb * 0.45).clamp(0.0, 0.95);
      }
    } catch (e) {
      debugPrint('applyVoiceFx skipped: $e');
    }
  }

  /// Play a one-shot sample. [pitchMidi]/[rootMidi] set playback rate for pitch.
  /// [fx] applies per-voice insert params when SoLoud allows.
  Future<SoundHandle?> playSample(
    String assetPath, {
    double volume = 1.0,
    double pan = 0.0,
    int? pitchMidi,
    int rootMidi = 60,
    FxSettings? fx,
  }) async {
    if (!_ready) return null;
    final isFile = assetPath.startsWith('/') || assetPath.startsWith('file:');
    final src = isFile
        ? await loadFile(assetPath.replaceFirst('file:', ''))
        : await loadAsset(assetPath);
    if (src == null) return null;
    try {
      final handle = await _soloud.play(
        src,
        volume: volume.clamp(0.0, 1.5),
        pan: pan.clamp(-1.0, 1.0),
      );
      if (pitchMidi != null && pitchMidi != rootMidi) {
        final ratio = MusicTheory.pitchRatio(rootMidi, pitchMidi);
        _soloud.setRelativePlaySpeed(handle, ratio.clamp(0.25, 4.0));
      }
      _applyVoiceFx(src, handle, fx);
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

  /// Legacy global FX — kept for offline-debug / fallback; live path uses inserts.
  @Deprecated('Use per-source playSample(..., fx:) instead')
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
