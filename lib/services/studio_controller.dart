import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/sound_library.dart';
import '../models/fx_settings.dart';
import '../models/note_event.dart';
import '../models/project.dart';
import '../models/track.dart';
import '../utils/audio_clock_math.dart';
import '../utils/music_theory.dart';
import 'audio_engine.dart';
import 'export_service.dart';
import 'project_bundle.dart';
import 'project_store.dart';

enum StudioTab { arrange, drums, piano, keys, guitar, mixer, library }

class StudioController extends ChangeNotifier {
  StudioController({
    ProjectStore? store,
    ExportService? exporter,
    ProjectBundleService? bundle,
  })  : _store = store ?? ProjectStore(),
        _exporter = exporter ?? ExportService(),
        _bundle = bundle ?? ProjectBundleService() {
    final engine = AudioEngine.instance;
    engine.onInterruption = ({required bool began}) {
      if (began) {
        if (isPlaying) {
          _resumeAfterInterruption = true;
          pause();
        }
      } else if (_resumeAfterInterruption) {
        _resumeAfterInterruption = false;
        play();
      }
    };
    engine.onBecomingNoisy = () {
      if (isPlaying) pause();
    };
  }

  final ProjectStore _store;
  final ExportService _exporter;
  final ProjectBundleService _bundle;
  final _uuid = const Uuid();

  List<StudioProject> recent = [];
  StudioProject? project;
  String? selectedTrackId;
  StudioTab tab = StudioTab.arrange;

  bool isPlaying = false;
  int playheadStep = 0;
  bool scaleLock = true;
  int drawVelocity = 100;
  bool eraseMode = false;
  int snapSteps = 1; // 1 = 16th

  /// Poller only — source of truth is AudioEngine.transportSeconds.
  Timer? _poller;
  Timer? _autosaveTimer;
  bool _resumeAfterInterruption = false;
  bool _resumeAfterLifecycle = false;

  /// Last step index that was scheduled via lookahead (exclusive cursor).
  int _scheduledThroughStep = -1;

  /// Lookahead window for note oneshots (~40ms).
  static const double _lookaheadSec = 0.04;

  Track? get selectedTrack {
    final p = project;
    if (p == null || selectedTrackId == null) return null;
    try {
      return p.tracks.firstWhere((t) => t.id == selectedTrackId);
    } catch (_) {
      return null;
    }
  }

  Future<void> bootstrap() async {
    await AudioEngine.instance.init();
    await AudioEngine.instance.preload(
      SoundLibrary.all.expand((p) {
        if (p.drumKit != null) return p.drumKit!.values;
        return [p.samplePath];
      }),
    );
    recent = await _store.listProjects();
    notifyListeners();
  }

  Future<void> refreshRecent() async {
    recent = await _store.listProjects();
    notifyListeners();
  }

  Future<StudioProject> createProject({
    required String name,
    int bpm = 120,
    String key = 'C',
    String scale = 'major',
    int bars = 4,
  }) async {
    final p = StudioProject(
      id: _uuid.v4(),
      name: name,
      bpm: bpm,
      key: key,
      scale: scale,
      bars: bars,
      loopEndStep: bars * 16,
    );
    await _store.save(p);
    project = p;
    selectedTrackId = null;
    tab = StudioTab.library;
    await refreshRecent();
    _scheduleAutosave();
    notifyListeners();
    return p;
  }

  Future<void> openProject(StudioProject p) async {
    stop();
    project = p;
    selectedTrackId = p.tracks.isNotEmpty ? p.tracks.first.id : null;
    tab = StudioTab.arrange;
    playheadStep = 0;
    _scheduleAutosave();
    notifyListeners();
  }

  Future<void> deleteProject(String id) async {
    await _store.delete(id);
    if (project?.id == id) {
      project = null;
      selectedTrackId = null;
    }
    await refreshRecent();
    notifyListeners();
  }

  Future<void> saveNow() async {
    final p = project;
    if (p == null) return;
    await _store.save(p);
    await refreshRecent();
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      saveNow();
    });
  }

  void setTab(StudioTab t) {
    tab = t;
    notifyListeners();
  }

  void selectTrack(String? id) {
    selectedTrackId = id;
    final t = selectedTrack;
    if (t != null) {
      tab = switch (t.category) {
        TrackCategory.drums => StudioTab.drums,
        TrackCategory.bass => StudioTab.piano,
        TrackCategory.guitar => StudioTab.guitar,
        TrackCategory.keys => StudioTab.keys,
      };
    }
    notifyListeners();
  }

  void updateProjectMeta({
    String? name,
    int? bpm,
    String? key,
    String? scale,
    int? bars,
    bool? loopEnabled,
    int? loopStartStep,
    int? loopEndStep,
  }) {
    final p = project;
    if (p == null) return;
    if (name != null) p.name = name;
    if (bpm != null) p.bpm = bpm.clamp(40, 240);
    if (key != null) p.key = key;
    if (scale != null) p.scale = scale;
    if (bars != null) {
      p.bars = bars.clamp(1, 32);
      p.loopEndStep = p.bars * p.stepsPerBar;
    }
    if (loopEnabled != null) p.loopEnabled = loopEnabled;
    if (loopStartStep != null) p.loopStartStep = loopStartStep;
    if (loopEndStep != null) p.loopEndStep = loopEndStep;
    notifyListeners();
  }

  Future<Track> addTrackFromPreset(SoundPreset preset) async {
    final p = project;
    if (p == null) throw StateError('No project');
    final track = Track(
      id: _uuid.v4(),
      name: preset.name,
      category: preset.category,
      presetId: preset.id,
      sampleRoot: preset.samplePath,
      rootMidi: preset.rootMidi,
      colorValue: preset.colorValue,
      fx: FxSettings(
        ampPreset: switch (preset.category) {
          TrackCategory.guitar =>
            preset.id.contains('high')
                ? AmpPreset.highGain
                : preset.id.contains('crunch')
                    ? AmpPreset.crunch
                    : AmpPreset.clean,
          TrackCategory.bass =>
            preset.id.contains('driven') ? AmpPreset.bassDrive : AmpPreset.none,
          _ => AmpPreset.none,
        },
      ),
    );
    p.tracks.add(track);
    selectedTrackId = track.id;
    selectTrack(track.id);
    await saveNow();
    notifyListeners();
    return track;
  }

  void removeTrack(String id) {
    final p = project;
    if (p == null) return;
    p.tracks.removeWhere((t) => t.id == id);
    if (selectedTrackId == id) {
      selectedTrackId = p.tracks.isNotEmpty ? p.tracks.first.id : null;
    }
    notifyListeners();
  }

  void updateTrack(Track track) {
    notifyListeners();
  }

  // --- Notes ---

  void addOrToggleNote({
    required String trackId,
    required int pitch,
    required int startStep,
    int lengthSteps = 1,
    int? velocity,
  }) {
    final p = project;
    if (p == null) return;
    final track = p.tracks.firstWhere((t) => t.id == trackId);
    var finalPitch = pitch;
    if (scaleLock &&
        track.category != TrackCategory.drums &&
        tab != StudioTab.drums) {
      finalPitch = MusicTheory.snapToScale(pitch, p.key, p.scale);
    }
    final snapped = (startStep ~/ snapSteps) * snapSteps;

    if (eraseMode) {
      track.notes.removeWhere(
        (n) => n.pitch == finalPitch && n.startStep == snapped,
      );
      notifyListeners();
      return;
    }

    final existing = track.notes.where(
      (n) => n.pitch == finalPitch && n.startStep == snapped,
    );
    if (existing.isNotEmpty) {
      track.notes.removeWhere(
        (n) => n.pitch == finalPitch && n.startStep == snapped,
      );
    } else {
      track.notes.add(NoteEvent(
        id: _uuid.v4(),
        pitch: finalPitch,
        startStep: snapped,
        lengthSteps: lengthSteps,
        velocity: velocity ?? drawVelocity,
      ));
    }
    notifyListeners();
  }

  void setStepCell({
    required String trackId,
    required int padIndex,
    required int step,
    required bool on,
  }) {
    final p = project;
    if (p == null) return;
    final track = p.tracks.firstWhere((t) => t.id == trackId);
    final pitch = DrumPadMap.pitchForPad(padIndex);
    track.notes.removeWhere((n) => n.pitch == pitch && n.startStep == step);
    if (on) {
      track.notes.add(NoteEvent(
        id: _uuid.v4(),
        pitch: pitch,
        startStep: step,
        lengthSteps: 1,
        velocity: drawVelocity,
      ));
    }
    notifyListeners();
  }

  bool isStepOn(Track track, int padIndex, int step) {
    final pitch = DrumPadMap.pitchForPad(padIndex);
    return track.notes.any((n) => n.pitch == pitch && n.startStep == step);
  }

  void clearTrackNotes(String trackId) {
    final p = project;
    if (p == null) return;
    p.tracks.firstWhere((t) => t.id == trackId).notes.clear();
    notifyListeners();
  }

  // --- Preview / pads ---

  Future<void> previewPreset(SoundPreset preset) async {
    if (preset.drumKit != null) {
      await AudioEngine.instance.playSample(
        preset.drumKit!.values.first,
        volume: 0.9,
      );
    } else {
      await AudioEngine.instance.playSample(
        preset.samplePath,
        volume: 0.85,
        pitchMidi: preset.rootMidi,
        rootMidi: preset.rootMidi,
      );
    }
  }

  Future<void> triggerPad(Track track, int padIndex) async {
    final preset = SoundLibrary.byId(track.presetId);
    final kit = preset?.drumKit;
    if (kit == null) return;
    final names = kit.keys.toList();
    if (padIndex >= names.length) return;
    final path = kit[names[padIndex]]!;
    final audible = _trackAudible(track);
    if (!audible) return;
    await AudioEngine.instance.playSample(
      path,
      volume: track.volume,
      pan: track.pan,
      fx: track.fx,
    );
  }

  Future<void> triggerNote(Track track, int midi, {double? velocity}) async {
    if (!_trackAudible(track)) return;
    await AudioEngine.instance.playSample(
      track.sampleRoot,
      volume: track.volume * (velocity ?? 1.0),
      pan: track.pan,
      pitchMidi: midi,
      rootMidi: track.rootMidi,
      fx: track.fx,
    );
  }

  bool _trackAudible(Track track) {
    final p = project;
    if (p == null) return false;
    if (track.muted) return false;
    final anySolo = p.tracks.any((t) => t.solo);
    if (anySolo && !track.solo) return false;
    return true;
  }

  // --- Transport (audio-clock + lookahead) ---

  void play() {
    final p = project;
    if (p == null) return;
    if (isPlaying) return;
    isPlaying = true;
    final engine = AudioEngine.instance;
    unawaited(engine.activateSession());
    final origin = AudioClockMath.stepToSeconds(playheadStep, p.bpm);
    engine.startTransportClock(originSeconds: origin);
    _scheduledThroughStep = playheadStep - 1;
    WakelockPlus.enable();
    _poller?.cancel();
    // Poller updates UI + runs lookahead; clock is the source of truth.
    _poller = Timer.periodic(const Duration(milliseconds: 8), (_) {
      _onTransportPoll();
    });
    // Schedule immediately so step 0 notes fire without waiting a poll.
    _onTransportPoll();
    notifyListeners();
  }

  void pause() {
    isPlaying = false;
    _poller?.cancel();
    AudioEngine.instance.pauseTransportClock();
    WakelockPlus.disable();
    notifyListeners();
  }

  void stop() {
    isPlaying = false;
    _poller?.cancel();
    playheadStep = project?.loopStartStep ?? 0;
    _scheduledThroughStep = playheadStep - 1;
    AudioEngine.instance.stopTransportClock(
      originSeconds: AudioClockMath.stepToSeconds(
        playheadStep,
        project?.bpm ?? 120,
      ),
    );
    unawaited(AudioEngine.instance.stopAll());
    unawaited(AudioEngine.instance.deactivateSession());
    unawaited(WakelockPlus.disable());
    notifyListeners();
  }

  void togglePlay() => isPlaying ? pause() : play();

  /// App lifecycle: pause transport when backgrounded; optional resume.
  void onAppLifecycle(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        if (isPlaying) {
          _resumeAfterLifecycle = true;
          pause();
        }
        break;
      case AppLifecycleState.resumed:
        if (_resumeAfterLifecycle) {
          _resumeAfterLifecycle = false;
          // Do not auto-resume after background — keeps Play honest / OS-safe.
        }
        break;
      case AppLifecycleState.detached:
        stop();
        break;
    }
  }

  void setScaleLock(bool v) {
    scaleLock = v;
    notifyListeners();
  }

  void setEraseMode(bool v) {
    eraseMode = v;
    notifyListeners();
  }

  void setDrawVelocity(int v) {
    drawVelocity = v.clamp(1, 127);
    notifyListeners();
  }

  void setTrackInstrumentMode(Track track, TrackInstrumentMode mode) {
    track.instrumentMode = mode;
    notifyListeners();
  }

  void seek(int step) {
    final p = project;
    playheadStep = step;
    _scheduledThroughStep = step - 1;
    final origin = AudioClockMath.stepToSeconds(step, p?.bpm ?? 120);
    if (isPlaying) {
      AudioEngine.instance.seekTransportClock(origin);
    } else {
      AudioEngine.instance.stopTransportClock(originSeconds: origin);
    }
    notifyListeners();
  }

  void _onTransportPoll() {
    final p = project;
    if (p == null || !isPlaying) return;

    final engine = AudioEngine.instance;
    var musical = engine.transportSeconds;

    final mapped = AudioClockMath.mapLoop(
      musicalSeconds: musical,
      bpm: p.bpm,
      loopEnabled: p.loopEnabled,
      loopStartStep: p.loopStartStep,
      loopEndStep: p.loopEndStep,
    );
    if (mapped.didWrap) {
      engine.seekTransportClock(mapped.wrappedSeconds);
      musical = mapped.wrappedSeconds;
      _scheduledThroughStep = mapped.step - 1;
    }

    final step = mapped.step;
    if (step != playheadStep) {
      playheadStep = step;
      notifyListeners();
    }

    // Lookahead schedule: fire oneshots for steps entering [now, now+lookahead].
    final horizonSec = musical + _lookaheadSec;
    final horizonStep = AudioClockMath.secondsToStep(horizonSec, p.bpm);
    final steps = AudioClockMath.stepsInLookahead(
      fromStepExclusive: _scheduledThroughStep,
      toStepInclusive: horizonStep,
      loopEnabled: p.loopEnabled,
      loopStartStep: p.loopStartStep,
      loopEndStep: p.loopEndStep,
    );
    for (final s in steps) {
      _fireStep(s);
    }
    if (horizonStep > _scheduledThroughStep) {
      _scheduledThroughStep = horizonStep;
    }
  }

  void _fireStep(int step) {
    final p = project;
    if (p == null) return;
    for (final track in p.tracks) {
      if (!_trackAudible(track)) continue;
      for (final note in track.notes) {
        if (note.startStep != step) continue;
        final vel = note.velocity / 127.0;
        if (track.category == TrackCategory.drums) {
          final pad = DrumPadMap.padIndexForPitch(note.pitch);
          unawaited(triggerPad(track, pad));
        } else {
          unawaited(triggerNote(track, note.pitch, velocity: vel));
        }
      }
    }
  }

  /// Called when mixer FX change so live inserts stay relevant on next notes.
  void notifyFxChanged() {
    notifyListeners();
  }

  Future<String?> exportAndShare() async {
    final p = project;
    if (p == null) return 'No project open';
    try {
      pause();
      final file = await _exporter.exportWav(p);
      await _exporter.shareFile(file);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> exportProjectBundle() async {
    final p = project;
    if (p == null) return 'No project open';
    try {
      await saveNow();
      await _bundle.shareProject(p);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> importProjectFile(File file) async {
    try {
      stop();
      final imported = await _bundle.importFromFile(file);
      await openProject(imported);
      await refreshRecent();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  @override
  void dispose() {
    _poller?.cancel();
    _autosaveTimer?.cancel();
    AudioEngine.instance.onInterruption = null;
    AudioEngine.instance.onBecomingNoisy = null;
    WakelockPlus.disable();
    super.dispose();
  }
}
