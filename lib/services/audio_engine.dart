import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../models/fx_settings.dart';
import '../utils/audio_clock_math.dart';
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

  /// Pending Timer-based clocked oneshots (flutter_soloud 3.5.4 has no
  /// Dart playClocked / playScheduled — those land in ≥4.1 needing Flutter ≥3.41).
  final List<Timer> _scheduledTimers = [];
  int _scheduleEpoch = 0;

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
    cancelScheduledPlays();
    _transportOriginSeconds = originSeconds;
    _transportWatch = Stopwatch()..start();
  }

  void pauseTransportClock() {
    cancelScheduledPlays();
    final w = _transportWatch;
    if (w != null && w.isRunning) {
      _transportOriginSeconds += w.elapsedMicroseconds / 1e6;
      w.stop();
    }
  }

  void stopTransportClock({double originSeconds = 0}) {
    cancelScheduledPlays();
    _transportWatch?.stop();
    _transportWatch = null;
    _transportOriginSeconds = originSeconds;
  }

  void seekTransportClock(double originSeconds) {
    cancelScheduledPlays();
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
        src.filters.biquadFilter.activate();
      } catch (e) {
        debugPrint('Biquad insert skipped for $key: $e');
      }
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
      final gain = fx.gain.clamp(0.0, 1.0);
      final tone = fx.tone.clamp(0.0, 1.0);
      final cab = fx.cabSim;

      src.filters.echoFilter.delay(soundHandle: handle).value =
          0.18 + delay * 0.45;
      src.filters.echoFilter.decay(soundHandle: handle).value =
          0.25 + delay * 0.5;
      src.filters.echoFilter.wet(soundHandle: handle).value =
          (delay * 0.75).clamp(0.0, 0.85);

      // Mini Amp: Gain/Drive → SoLoud wave-shaper (audible saturation).
      final base = switch (fx.ampPreset) {
        AmpPreset.none => 0.0,
        AmpPreset.clean => 0.08,
        AmpPreset.crunch => 0.35,
        AmpPreset.highGain => 0.7,
        AmpPreset.bassDrive => 0.42,
      };
      final amount = (base + gain * 0.85).clamp(0.0, 0.95);
      src.filters.waveShaperFilter.amount(soundHandle: handle).value =
          amount.clamp(-1.0, 1.0);
      src.filters.waveShaperFilter.wet(soundHandle: handle).value =
          amount > 0.03 ? (0.45 + gain * 0.5).clamp(0.0, 0.95) : 0.0;

      // Mini Amp: Tone/Brightness → biquad low-pass cutoff.
      // Cab sim darkens further (speaker cabinet approximation).
      if (src.filters.biquadFilter.isActive) {
        final toneHz = 500.0 + tone * 7500.0;
        final cabHz = cab ? toneHz * 0.55 : toneHz;
        src.filters.biquadFilter.type(soundHandle: handle).value = 0; // LOWPASS
        src.filters.biquadFilter.frequency(soundHandle: handle).value =
            cabHz.clamp(120.0, 12000.0);
        src.filters.biquadFilter.resonance(soundHandle: handle).value =
            cab ? 1.4 : 0.7;
        src.filters.biquadFilter.wet(soundHandle: handle).value =
            (tone < 0.92 || cab) ? 0.85 : 0.35;
      }

      // Reverb + optional cab-room (does not overwrite user reverb field).
      var wetReverb = reverb;
      var damp = 0.35 + (1 - reverb) * 0.3;
      var room = 0.45 + reverb * 0.45;
      if (cab) {
        wetReverb = (reverb + 0.22).clamp(0.0, 0.85);
        damp = (0.72 + (1 - tone) * 0.2).clamp(0.4, 0.95);
        room = (room * 0.7 + 0.25).clamp(0.2, 0.85);
      }
      if (src.filters.freeverbFilter.isActive) {
        src.filters.freeverbFilter.wet(soundHandle: handle).value = wetReverb;
        src.filters.freeverbFilter.roomSize(soundHandle: handle).value = room;
        try {
          src.filters.freeverbFilter.damp(soundHandle: handle).value = damp;
        } catch (_) {}
      } else if (wetReverb > 0.05) {
        final wet = src.filters.echoFilter.wet(soundHandle: handle).value;
        src.filters.echoFilter.wet(soundHandle: handle).value =
            (wet + wetReverb * 0.35).clamp(0.0, 0.9);
        src.filters.echoFilter.decay(soundHandle: handle).value =
            (0.3 + wetReverb * 0.45).clamp(0.0, 0.95);
      }
    } catch (e) {
      debugPrint('applyVoiceFx skipped: $e');
    }
  }


  /// Cancel all pending clocked oneshots (pause / stop / seek / re-anchor).
  void cancelScheduledPlays() {
    _scheduleEpoch++;
    for (final t in _scheduledTimers) {
      t.cancel();
    }
    _scheduledTimers.clear();
  }

  /// Resolve an asset/file path to a loaded [AudioSource], or null.
  Future<AudioSource?> _resolveSource(String assetPath) async {
    final isFile = assetPath.startsWith('/') || assetPath.startsWith('file:');
    if (isFile) {
      return loadFile(assetPath.replaceFirst('file:', ''));
    }
    return loadAsset(assetPath);
  }

  Future<SoundHandle?> _playResolved(
    AudioSource src, {
    required double volume,
    required double pan,
    int? pitchMidi,
    int rootMidi = 60,
    FxSettings? fx,
  }) async {
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
      debugPrint('playResolved error: $e');
      return null;
    }
  }

  /// Clocked / tighter-scheduled oneshot.
  ///
  /// Uses musical [onsetSeconds] on the app transport clock: preloads the
  /// source, then delays until the onset before calling SoLoud [play].
  /// When flutter_soloud gains Dart [playClocked] (package ≥4.1), swap the
  /// Timer path for the native sample-accurate API.
  Future<SoundHandle?> playSampleClocked(
    String assetPath, {
    required double onsetSeconds,
    double volume = 1.0,
    double pan = 0.0,
    int? pitchMidi,
    int rootMidi = 60,
    FxSettings? fx,
  }) async {
    if (!_ready) return null;
    final src = await _resolveSource(assetPath);
    if (src == null) return null;

    final now = transportSeconds;
    if (AudioClockMath.isOnsetDue(now, onsetSeconds)) {
      return _playResolved(
        src,
        volume: volume,
        pan: pan,
        pitchMidi: pitchMidi,
        rootMidi: rootMidi,
        fx: fx,
      );
    }

    final delay = AudioClockMath.scheduleDelay(
      nowSec: now,
      onsetSec: onsetSeconds,
    );
    final epoch = _scheduleEpoch;
    final completer = Completer<SoundHandle?>();
    late final Timer timer;
    timer = Timer(delay, () async {
      _scheduledTimers.remove(timer);
      if (epoch != _scheduleEpoch) {
        if (!completer.isCompleted) completer.complete(null);
        return;
      }
      final handle = await _playResolved(
        src,
        volume: volume,
        pan: pan,
        pitchMidi: pitchMidi,
        rootMidi: rootMidi,
        fx: fx,
      );
      if (!completer.isCompleted) completer.complete(handle);
    });
    _scheduledTimers.add(timer);
    return completer.future;
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
    final src = await _resolveSource(assetPath);
    if (src == null) return null;
    return _playResolved(
      src,
      volume: volume,
      pan: pan,
      pitchMidi: pitchMidi,
      rootMidi: rootMidi,
      fx: fx,
    );
  }

  Future<void> playMetronomeClick({required bool accent}) async {
    await playSample(
      accent ? metronomeAccent : metronomeClick,
      volume: accent ? 0.85 : 0.55,
    );
  }

  Future<void> playMetronomeClickClocked({
    required bool accent,
    required double onsetSeconds,
  }) async {
    await playSampleClocked(
      accent ? metronomeAccent : metronomeClick,
      onsetSeconds: onsetSeconds,
      volume: accent ? 0.85 : 0.55,
    );
  }

  Future<void> stopAll() async {
    cancelScheduledPlays();
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
