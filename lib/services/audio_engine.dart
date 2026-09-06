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

  Stopwatch? _transportWatch;
  double _transportOriginSeconds = 0;

  static const metronomeClick = 'assets/samples/drums/metronome_click.wav';
  static const metronomeAccent = 'assets/samples/drums/metronome_accent.wav';

  double get transportSeconds {
    final w = _transportWatch;
    if (w == null || !w.isRunning) {
      return _transportOriginSeconds;
    }
    return _transportOriginSeconds + w.elapsedMicroseconds / 1e6;
  }

  bool get isTransportRunning =>
      _transportWatch != null && _transportWatch!.isRunning;

  Future<void> init() async {
    if (_ready) return;
    try {
      await _configureSession();
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

  /// Switch to a play-and-record friendly session while mic arm is active.
  Future<void> configureForRecording() async {
    try {
      final session = _session ?? await AudioSession.instance;
      await session.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.defaultToSpeaker |
                  AVAudioSessionCategoryOptions.allowBluetooth,
          avAudioSessionMode: AVAudioSessionMode.defaultMode,
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.music,
            usage: AndroidAudioUsage.media,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          androidWillPauseWhenDucked: true,
        ),
      );
      await session.setActive(true);
    } catch (e) {
      debugPrint('configureForRecording failed: $e');
    }
  }

  Future<void> configureForMusic() async {
    try {
      final session = _session ?? await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      await session.setActive(true);
    } catch (e) {
      debugPrint('configureForMusic failed: $e');
    }
  }

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

  void startTransportClock({double originSeconds = 0}) {
    _transportOriginSeconds = originSeconds;
    _transportWatch = Stopwatch()..start();
  }

  void pauseTransportClock() {
    final w = _transportWatch;
    if (w != null && w.isRunning) {
      _transportOriginSeconds += w.elapsedMicroseconds / 1e6;
      w.stop();
    }
  }

  void stopTransportClock({double originSeconds = 0}) {
    _transportWatch?.stop();
    _transportWatch = null;
    _transportOriginSeconds = originSeconds;
  }

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
    await loadAsset(metronomeClick);
    await loadAsset(metronomeAccent);
  }

  void _prepareSourceFx(AudioSource src, String key) {
    if (_fxPrepared.contains(key)) return;
    try {
      try {
        _soloud.filters.freeverbFilter.deactivate();
      } catch (_) {}
      try {
        _soloud.filters.echoFilter.deactivate();
      } catch (_) {}

      src.filters.echoFilter.activate();
      src.filters.waveShaperFilter.activate();
      try {
        src.filters.freeverbFilter.activate();
      } catch (e) {
        debugPrint('Freeverb insert skipped for $key: $e');
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

      src.filters.echoFilter.delay(soundHandle: handle).value =
          0.18 + delay * 0.45;
      src.filters.echoFilter.decay(soundHandle: handle).value =
          0.25 + delay * 0.5;
      src.filters.echoFilter.wet(soundHandle: handle).value =
          (delay * 0.75).clamp(0.0, 0.85);

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

      if (src.filters.freeverbFilter.isActive) {
        src.filters.freeverbFilter.wet(soundHandle: handle).value = reverb;
        src.filters.freeverbFilter.roomSize(soundHandle: handle).value =
            0.45 + reverb * 0.45;
        try {
          src.filters.freeverbFilter.damp(soundHandle: handle).value =
              0.35 + (1 - reverb) * 0.3;
        } catch (_) {}
      } else if (reverb > 0.05) {
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
        final clamped = MusicTheory.clampPitch(pitchMidi, rootMidi);
        final ratio = MusicTheory.pitchRatio(rootMidi, clamped);
        _soloud.setRelativePlaySpeed(handle, ratio.clamp(0.25, 4.0));
      }
      _applyVoiceFx(src, handle, fx);
      return handle;
    } catch (e) {
      debugPrint('playSample error: $e');
      return null;
    }
  }

  Future<void> playMetronomeClick({required bool accent}) async {
    await playSample(
      accent ? metronomeAccent : metronomeClick,
      volume: accent ? 0.85 : 0.55,
    );
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
}
