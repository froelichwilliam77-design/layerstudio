import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/sound_library.dart';
import '../models/fx_settings.dart';
import '../models/note_event.dart';
import '../models/pattern.dart';
import '../models/project.dart';
import '../models/track.dart';
import '../utils/audio_clock_math.dart';
import '../utils/music_theory.dart';
import 'audio_engine.dart';
import 'command_stack.dart';
import 'error_log.dart';
import 'export_service.dart';
import 'mic_recorder.dart';
import 'project_bundle.dart';
import 'project_store.dart';

enum StudioTab { arrange, drums, piano, keys, guitar, mixer, library }

class StudioController extends ChangeNotifier {
  StudioController({
    ProjectStore? store,
    ExportService? exporter,
    ProjectBundleService? bundle,
    MicRecorder? micRecorder,
  })  : _store = store ?? ProjectStore(),
        _exporter = exporter ?? ExportService(),
        _bundle = bundle ?? ProjectBundleService(),
        _mic = micRecorder ?? MicRecorder() {
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
  final MicRecorder _mic;
  final _uuid = const Uuid();
  final CommandStack commands = CommandStack();
  final math.Random _rng = math.Random();

  List<StudioProject> recent = [];
  StudioProject? project;
  String? selectedTrackId;
  StudioTab tab = StudioTab.arrange;

  bool isPlaying = false;
  int playheadStep = 0;
  bool scaleLock = true;
  int drawVelocity = 100;
  bool eraseMode = false;
  int snapSteps = 1;
  int drawProbability = 100;

  /// Soft pitch warning for UI banner.
  String? pitchWarning;

  bool exportBannerDismissed = false;
  bool isRecordingMic = false;
  bool isCountingIn = false;
  int countInStepsRemaining = 0;

  Timer? _poller;
  Timer? _autosaveTimer;
  bool _resumeAfterInterruption = false;
  bool _resumeAfterLifecycle = false;

  int _scheduledThroughStep = -1;
  double _scheduledThroughOnset = -1;
  final Set<String> _firedKeys = {};

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
    try {
      final prefs = await SharedPreferences.getInstance();
      exportBannerDismissed =
          prefs.getBool('export_banner_dismissed') ?? false;
    } catch (_) {}
    notifyListeners();
  }

  Future<void> dismissExportBanner() async {
    exportBannerDismissed = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('export_banner_dismissed', true);
    } catch (_) {}
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
    commands.clear();
    await refreshRecent();
    _scheduleAutosave();
    notifyListeners();
    return p;
  }

  Future<void> openProject(StudioProject p) async {
    stop();
    project = p;
    _hydrateActivePatternNotes();
    selectedTrackId = p.tracks.isNotEmpty ? p.tracks.first.id : null;
    tab = StudioTab.arrange;
    playheadStep = 0;
    commands.clear();
    _scheduleAutosave();
    notifyListeners();
  }

  /// Copy active pattern notes into track.notes for editing/playback.
  void _hydrateActivePatternNotes() {
    final p = project;
    if (p == null) return;
    final pat = p.activePattern;
    for (final t in p.tracks) {
      t.notes = pat
          .notesFor(t.id)
          .map((n) => n.copyWith())
          .toList();
    }
  }

  /// Persist track.notes back into the active pattern.
  void _flushNotesToActivePattern() {
    final p = project;
    if (p == null) return;
    final pat = p.activePattern;
    for (final t in p.tracks) {
      pat.setNotesFor(
        t.id,
        t.notes.map((n) => n.copyWith()).toList(),
      );
    }
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
    _flushNotesToActivePattern();
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
        TrackCategory.mic => StudioTab.arrange,
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
    int? swingPercent,
    bool? metronomeEnabled,
    int? countInBars,
    bool? songMode,
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
    if (swingPercent != null) p.swingPercent = swingPercent.clamp(0, 100);
    if (metronomeEnabled != null) p.metronomeEnabled = metronomeEnabled;
    if (countInBars != null) p.countInBars = countInBars.clamp(0, 2);
    if (songMode != null) p.songMode = songMode;
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
          TrackCategory.guitar => preset.id.contains('high')
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
    for (final pat in p.patterns) {
      pat.notesFor(track.id);
    }
    selectedTrackId = track.id;
    selectTrack(track.id);
    await saveNow();
    notifyListeners();
    return track;
  }

  Future<Track> addMicTrack() async {
    final p = project;
    if (p == null) throw StateError('No project');
    final track = Track(
      id: _uuid.v4(),
      name: 'Mic',
      category: TrackCategory.mic,
      presetId: 'mic',
      sampleRoot: '',
      rootMidi: 60,
      colorValue: 0xFF81C784,
      instrumentMode: TrackInstrumentMode.micRecord,
    );
    p.tracks.add(track);
    selectedTrackId = track.id;
    await saveNow();
    notifyListeners();
    return track;
  }

  void removeTrack(String id) {
    final p = project;
    if (p == null) return;
    p.tracks.removeWhere((t) => t.id == id);
    for (final pat in p.patterns) {
      pat.notesByTrackId.remove(id);
    }
    if (selectedTrackId == id) {
      selectedTrackId = p.tracks.isNotEmpty ? p.tracks.first.id : null;
    }
    notifyListeners();
  }

  void updateTrack(Track track) {
    notifyListeners();
  }

  void setDrawProbability(int v) {
    drawProbability = v.clamp(0, 100);
    notifyListeners();
  }

  // --- Patterns ---

  void selectPattern(int index) {
    final p = project;
    if (p == null) return;
    _flushNotesToActivePattern();
    p.activePatternIndex = index.clamp(0, p.patterns.length - 1);
    _hydrateActivePatternNotes();
    // In pattern mode, loop length stays pattern bars.
    if (!p.songMode) {
      p.loopStartStep = 0;
      p.loopEndStep = p.bars * p.stepsPerBar;
    }
    notifyListeners();
  }

  void copyPattern({required int fromIndex, required int toIndex}) {
    final p = project;
    if (p == null) return;
    _flushNotesToActivePattern();
    final from = p.patterns[fromIndex.clamp(0, p.patterns.length - 1)];
    final to = p.patterns[toIndex.clamp(0, p.patterns.length - 1)];
    final snap = from.deepCopy(id: to.id, name: to.name);
    to.notesByTrackId
      ..clear()
      ..addAll(snap.notesByTrackId);
    if (p.activePatternIndex == toIndex) {
      _hydrateActivePatternNotes();
    }
    notifyListeners();
  }

  void clearPattern(int index) {
    final p = project;
    if (p == null) return;
    _flushNotesToActivePattern();
    final before = _snapshotAllPatternNotes(index);
    p.patterns[index].clearAll();
    if (p.activePatternIndex == index) {
      for (final t in p.tracks) {
        t.notes.clear();
      }
    }
    final after = _snapshotAllPatternNotes(index);
    commands.push(
      NotesSnapshotCommand(
        label: 'Clear pattern',
        apply: (snap) => _applyPatternSnapshot(index, snap),
        before: before,
        after: after,
      ),
      executeNow: false,
    );
    notifyListeners();
  }

  Map<String, List<dynamic>> _snapshotAllPatternNotes(int patternIndex) {
    final p = project!;
    final pat = p.patterns[patternIndex];
    return pat.notesByTrackId.map(
      (k, v) => MapEntry(k, v.map((n) => n.toJson()).toList()),
    );
  }

  void _applyPatternSnapshot(int patternIndex, Map<String, List<dynamic>> snap) {
    final p = project;
    if (p == null) return;
    final pat = p.patterns[patternIndex];
    pat.notesByTrackId.clear();
    snap.forEach((k, v) {
      pat.notesByTrackId[k] = v
          .map((e) => NoteEvent.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    });
    if (p.activePatternIndex == patternIndex) {
      _hydrateActivePatternNotes();
    }
    notifyListeners();
  }

  // --- Arrangement ---

  void addArrangementClip({String? patternId, int? startBar, int lengthBars = 1}) {
    final p = project;
    if (p == null) return;
    final pid = patternId ?? p.activePattern.id;
    final start = startBar ??
        (p.arrangement.isEmpty
            ? 0
            : p.arrangement.map((c) => c.endBar).reduce(math.max));
    p.arrangement.add(ArrangementClip(
      id: _uuid.v4(),
      patternId: pid,
      startBar: start,
      lengthBars: lengthBars.clamp(1, 32),
    ));
    p.arrangement.sort((a, b) => a.startBar.compareTo(b.startBar));
    notifyListeners();
  }

  void removeArrangementClip(String id) {
    project?.arrangement.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  void moveArrangementClip(String id, int newStartBar) {
    final p = project;
    if (p == null) return;
    final clip = p.arrangement.cast<ArrangementClip?>().firstWhere(
          (c) => c?.id == id,
          orElse: () => null,
        );
    if (clip == null) return;
    clip.startBar = newStartBar.clamp(0, 256);
    p.arrangement.sort((a, b) => a.startBar.compareTo(b.startBar));
    notifyListeners();
  }

  Pattern? patternById(String id) {
    final p = project;
    if (p == null) return null;
    try {
      return p.patterns.firstWhere((x) => x.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Pattern that owns the playhead in song mode.
  Pattern? patternAtPlayhead() {
    final p = project;
    if (p == null) return null;
    if (!p.songMode || p.arrangement.isEmpty) return p.activePattern;
    final bar = playheadStep ~/ p.stepsPerBar;
    for (final clip in p.arrangement) {
      if (bar >= clip.startBar && bar < clip.endBar) {
        return patternById(clip.patternId) ?? p.activePattern;
      }
    }
    return p.activePattern;
  }

  // --- Notes (undoable) ---

  Map<String, List<dynamic>> _snapshotTrackNotes(String trackId) {
    final track = project!.tracks.firstWhere((t) => t.id == trackId);
    return {
      trackId: track.notes.map((n) => n.toJson()).toList(),
    };
  }

  void _applyTrackNotesSnapshot(Map<String, List<dynamic>> snap) {
    final p = project;
    if (p == null) return;
    snap.forEach((trackId, list) {
      final track = p.tracks.firstWhere((t) => t.id == trackId);
      track.notes = list
          .map((e) => NoteEvent.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    });
    _flushNotesToActivePattern();
    notifyListeners();
  }

  void _pushNotesEdit(String label, String trackId, VoidCallback mutate) {
    final before = _snapshotTrackNotes(trackId);
    mutate();
    final after = _snapshotTrackNotes(trackId);
    commands.push(
      NotesSnapshotCommand(
        label: label,
        apply: _applyTrackNotesSnapshot,
        before: before,
        after: after,
      ),
      executeNow: false,
    );
    _flushNotesToActivePattern();
    notifyListeners();
  }

  void undo() {
    if (!commands.canUndo) return;
    commands.undo();
    notifyListeners();
  }

  void redo() {
    if (!commands.canRedo) return;
    commands.redo();
    notifyListeners();
  }

  void addOrToggleNote({
    required String trackId,
    required int pitch,
    required int startStep,
    int lengthSteps = 1,
    int? velocity,
    int? probability,
  }) {
    final p = project;
    if (p == null) return;
    final track = p.tracks.firstWhere((t) => t.id == trackId);
    var finalPitch = pitch;
    if (scaleLock &&
        track.category != TrackCategory.drums &&
        track.category != TrackCategory.mic &&
        tab != StudioTab.drums) {
      finalPitch = MusicTheory.snapToScale(pitch, p.key, p.scale);
    }
    if (track.category != TrackCategory.drums &&
        track.category != TrackCategory.mic) {
      final clamped = MusicTheory.clampPitch(finalPitch, track.rootMidi);
      if (MusicTheory.exceedsSoftRange(finalPitch, track.rootMidi) ||
          clamped != finalPitch) {
        pitchWarning =
            'Pitch clamped to ±${MusicTheory.hardPitchRangeSemis} semitones of sample root (SoLoud rate-pitch).';
      } else {
        pitchWarning = null;
      }
      finalPitch = clamped;
    }
    final snapped = (startStep ~/ snapSteps) * snapSteps;

    _pushNotesEdit(eraseMode ? 'Erase note' : 'Edit note', trackId, () {
      if (eraseMode) {
        track.notes.removeWhere(
          (n) => n.pitch == finalPitch && n.startStep == snapped,
        );
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
          probability: probability ?? drawProbability,
        ));
      }
    });
  }

  void setStepCell({
    required String trackId,
    required int padIndex,
    required int step,
    required bool on,
    int? probability,
  }) {
    final p = project;
    if (p == null) return;
    final track = p.tracks.firstWhere((t) => t.id == trackId);
    final pitch = DrumPadMap.pitchForPad(padIndex);
    _pushNotesEdit(on ? 'Add step' : 'Clear step', trackId, () {
      track.notes.removeWhere((n) => n.pitch == pitch && n.startStep == step);
      if (on) {
        track.notes.add(NoteEvent(
          id: _uuid.v4(),
          pitch: pitch,
          startStep: step,
          lengthSteps: 1,
          velocity: drawVelocity,
          probability: probability ?? drawProbability,
        ));
      }
    });
  }

  void setStepProbability({
    required String trackId,
    required int padIndex,
    required int step,
    required int probability,
  }) {
    final p = project;
    if (p == null) return;
    final track = p.tracks.firstWhere((t) => t.id == trackId);
    final pitch = DrumPadMap.pitchForPad(padIndex);
    _pushNotesEdit('Step probability', trackId, () {
      for (final n in track.notes) {
        if (n.pitch == pitch && n.startStep == step) {
          n.probability = probability.clamp(0, 100);
        }
      }
    });
  }

  bool isStepOn(Track track, int padIndex, int step) {
    final pitch = DrumPadMap.pitchForPad(padIndex);
    return track.notes.any((n) => n.pitch == pitch && n.startStep == step);
  }

  int stepProbability(Track track, int padIndex, int step) {
    final pitch = DrumPadMap.pitchForPad(padIndex);
    try {
      return track.notes
          .firstWhere((n) => n.pitch == pitch && n.startStep == step)
          .probability;
    } catch (_) {
      return 100;
    }
  }

  void clearTrackNotes(String trackId) {
    final p = project;
    if (p == null) return;
    _pushNotesEdit('Clear track', trackId, () {
      p.tracks.firstWhere((t) => t.id == trackId).notes.clear();
    });
  }

  /// Clear notes for the track across ALL patterns (with undo of active only + others).
  void clearTrackAllPatterns(String trackId) {
    final p = project;
    if (p == null) return;
    _flushNotesToActivePattern();
    final beforeActive = _snapshotTrackNotes(trackId);
    for (final pat in p.patterns) {
      pat.clearTrack(trackId);
    }
    p.tracks.firstWhere((t) => t.id == trackId).notes.clear();
    final afterActive = _snapshotTrackNotes(trackId);
    commands.push(
      NotesSnapshotCommand(
        label: 'Clear track (all patterns)',
        apply: _applyTrackNotesSnapshot,
        before: beforeActive,
        after: afterActive,
      ),
      executeNow: false,
    );
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
    if (!_trackAudible(track)) return;
    await AudioEngine.instance.playSample(
      path,
      volume: track.volume,
      pan: track.pan,
      fx: track.fx,
    );
  }

  Future<void> triggerNote(Track track, int midi, {double? velocity}) async {
    if (!_trackAudible(track)) return;
    if (track.category == TrackCategory.mic) {
      final path = track.recordedFilePath;
      if (path == null || path.isEmpty) return;
      await AudioEngine.instance.playSample(
        path,
        volume: track.volume * (velocity ?? 1.0),
        pan: track.pan,
        fx: track.fx,
      );
      return;
    }
    final clamped = MusicTheory.clampPitch(midi, track.rootMidi);
    await AudioEngine.instance.playSample(
      track.sampleRoot,
      volume: track.volume * (velocity ?? 1.0),
      pan: track.pan,
      pitchMidi: clamped,
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

  // --- Mic ---

  void armMicTrack(String trackId, bool armed) {
    final p = project;
    if (p == null) return;
    for (final t in p.tracks) {
      if (t.category == TrackCategory.mic) {
        t.recordArmed = t.id == trackId ? armed : false;
      }
    }
    notifyListeners();
  }

  Future<void> _startMicIfArmed() async {
    final p = project;
    if (p == null) return;
    Track? armed;
    for (final t in p.tracks) {
      if (t.category == TrackCategory.mic && t.recordArmed) {
        armed = t;
        break;
      }
    }
    if (armed == null) return;
    try {
      await AudioEngine.instance.configureForRecording();
      final path = await _mic.start();
      isRecordingMic = path != null;
      notifyListeners();
    } catch (e, st) {
      ErrorLog.instance.record(e, st);
      isRecordingMic = false;
      notifyListeners();
    }
  }

  Future<void> _stopMicIfRecording() async {
    if (!_mic.isRecording && !isRecordingMic) return;
    try {
      final path = await _mic.stop();
      final p = project;
      if (p != null && path != null) {
        for (final t in p.tracks) {
          if (t.category == TrackCategory.mic && t.recordArmed) {
            t.recordedFilePath = path;
            t.sampleRoot = path;
            t.recordArmed = false;
            // Place a clip note at record start (approx playhead at arm time = 0 for MVP).
            if (t.notes.isEmpty) {
              t.notes.add(NoteEvent(
                id: _uuid.v4(),
                pitch: 60,
                startStep: 0,
                lengthSteps: p.loopEndStep.clamp(1, p.totalSteps),
                velocity: 100,
              ));
            }
          }
        }
        _flushNotesToActivePattern();
      }
    } catch (e, st) {
      ErrorLog.instance.record(e, st);
    } finally {
      isRecordingMic = false;
      await AudioEngine.instance.configureForMusic();
      notifyListeners();
    }
  }

  // --- Transport ---

  void play() {
    final p = project;
    if (p == null) return;
    if (isPlaying) return;
    isPlaying = true;
    _firedKeys.clear();
    final engine = AudioEngine.instance;
    unawaited(engine.activateSession());

    final countIn = p.countInBars.clamp(0, 2);
    if (countIn > 0) {
      isCountingIn = true;
      countInStepsRemaining = countIn * p.stepsPerBar;
      engine.startTransportClock(originSeconds: 0);
      _scheduledThroughStep = -1;
      _scheduledThroughOnset = -1;
    } else {
      isCountingIn = false;
      countInStepsRemaining = 0;
      final origin = AudioClockMath.stepToSeconds(playheadStep, p.bpm);
      engine.startTransportClock(originSeconds: origin);
      _scheduledThroughStep = playheadStep - 1;
      _scheduledThroughOnset =
          AudioClockMath.stepOnsetSeconds(playheadStep - 1, p.bpm, p.swingPercent);
      unawaited(_startMicIfArmed());
    }

    WakelockPlus.enable();
    _poller?.cancel();
    _poller = Timer.periodic(const Duration(milliseconds: 8), (_) {
      _onTransportPoll();
    });
    _onTransportPoll();
    notifyListeners();
  }

  void pause() {
    isPlaying = false;
    isCountingIn = false;
    _poller?.cancel();
    AudioEngine.instance.pauseTransportClock();
    unawaited(_stopMicIfRecording());
    WakelockPlus.disable();
    notifyListeners();
  }

  void stop() {
    isPlaying = false;
    isCountingIn = false;
    countInStepsRemaining = 0;
    _poller?.cancel();
    playheadStep = project?.loopStartStep ?? 0;
    _scheduledThroughStep = playheadStep - 1;
    _scheduledThroughOnset = -1;
    _firedKeys.clear();
    AudioEngine.instance.stopTransportClock(
      originSeconds: AudioClockMath.stepToSeconds(
        playheadStep,
        project?.bpm ?? 120,
      ),
    );
    unawaited(_stopMicIfRecording());
    unawaited(AudioEngine.instance.stopAll());
    unawaited(AudioEngine.instance.deactivateSession());
    unawaited(WakelockPlus.disable());
    notifyListeners();
  }

  void togglePlay() => isPlaying ? pause() : play();

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
    _scheduledThroughOnset = -1;
    _firedKeys.clear();
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

    if (isCountingIn) {
      final steps = AudioClockMath.secondsToStep(musical, p.bpm);
      final total = p.countInBars * p.stepsPerBar;
      countInStepsRemaining = (total - steps).clamp(0, total);
      // Metronome during count-in (always on for count-in).
      _scheduleMetronome(musical, p, force: true, stepOffset: 0);
      if (steps >= total) {
        isCountingIn = false;
        countInStepsRemaining = 0;
        final origin = AudioClockMath.stepToSeconds(playheadStep, p.bpm);
        engine.seekTransportClock(origin);
        _scheduledThroughStep = playheadStep - 1;
        _scheduledThroughOnset = -1;
        _firedKeys.clear();
        unawaited(_startMicIfArmed());
        notifyListeners();
      } else {
        notifyListeners();
      }
      return;
    }

    // Song mode: expand loop to arrangement length.
    var loopEnabled = p.loopEnabled;
    var loopStart = p.loopStartStep;
    var loopEnd = p.loopEndStep;
    if (p.songMode && p.arrangement.isNotEmpty) {
      loopStart = 0;
      loopEnd = p.arrangementEndBar * p.stepsPerBar;
      loopEnabled = true;
    }

    final mapped = AudioClockMath.mapLoop(
      musicalSeconds: musical,
      bpm: p.bpm,
      loopEnabled: loopEnabled,
      loopStartStep: loopStart,
      loopEndStep: loopEnd,
    );
    if (mapped.didWrap) {
      engine.seekTransportClock(mapped.wrappedSeconds);
      musical = mapped.wrappedSeconds;
      _scheduledThroughStep = mapped.step - 1;
      _scheduledThroughOnset = -1;
      _firedKeys.clear();
    }

    final step = mapped.step;
    if (step != playheadStep) {
      playheadStep = step;
      // In song mode, hydrate pattern for current clip when bar changes.
      if (p.songMode) {
        final pat = patternAtPlayhead();
        if (pat != null && pat.id != p.activePattern.id) {
          final idx = p.patterns.indexWhere((x) => x.id == pat.id);
          if (idx >= 0 && idx != p.activePatternIndex) {
            // Don't flush — song mode reads from pattern bank directly.
            p.activePatternIndex = idx;
            _hydrateActivePatternNotes();
          }
        }
      }
      notifyListeners();
    }

    if (p.metronomeEnabled) {
      _scheduleMetronome(musical, p, force: false, stepOffset: 0);
    }

    final swung = AudioClockMath.swungStepsInWindow(
      nowSec: musical,
      lookaheadSec: _lookaheadSec,
      bpm: p.bpm,
      swingPercent: p.swingPercent,
      scheduledThroughOnset: _scheduledThroughOnset,
      loopEnabled: loopEnabled,
      loopStartStep: loopStart,
      loopEndStep: loopEnd,
    );
    for (final item in swung) {
      final key = '${item.step}@${item.onset.toStringAsFixed(4)}';
      if (_firedKeys.contains(key)) continue;
      _firedKeys.add(key);
      _fireStep(item.step);
      if (item.onset > _scheduledThroughOnset) {
        _scheduledThroughOnset = item.onset;
      }
      if (item.step > _scheduledThroughStep) {
        _scheduledThroughStep = item.step;
      }
    }
  }

  void _scheduleMetronome(
    double musical,
    StudioProject p, {
    required bool force,
    required int stepOffset,
  }) {
    final swung = AudioClockMath.swungStepsInWindow(
      nowSec: musical,
      lookaheadSec: _lookaheadSec,
      bpm: p.bpm,
      swingPercent: p.swingPercent,
      scheduledThroughOnset: _scheduledThroughOnset - 0.0001,
      loopEnabled: false,
      loopStartStep: 0,
      loopEndStep: 1 << 20,
    );
    for (final item in swung) {
      // Click on quarter notes (every 4 16ths).
      if (item.step % 4 != 0) continue;
      final key = 'metro:${item.step}@${item.onset.toStringAsFixed(4)}';
      if (_firedKeys.contains(key)) continue;
      _firedKeys.add(key);
      final accent = item.step % p.stepsPerBar == 0;
      unawaited(AudioEngine.instance.playMetronomeClick(accent: accent));
    }
  }

  void _fireStep(int step) {
    final p = project;
    if (p == null) return;

    // Song mode: notes from pattern at this bar; map step into pattern-local.
    List<Track> tracks = p.tracks;
    var localStep = step;
    if (p.songMode && p.arrangement.isNotEmpty) {
      final bar = step ~/ p.stepsPerBar;
      ArrangementClip? clip;
      for (final c in p.arrangement) {
        if (bar >= c.startBar && bar < c.endBar) {
          clip = c;
          break;
        }
      }
      if (clip == null) return;
      final pat = patternById(clip.patternId);
      if (pat == null) return;
      localStep = step % (p.bars * p.stepsPerBar);
      for (final track in tracks) {
        if (!_trackAudible(track)) continue;
        for (final note in pat.notesFor(track.id)) {
          if (note.startStep != localStep) continue;
          _maybePlayNote(track, note);
        }
      }
      return;
    }

    for (final track in tracks) {
      if (!_trackAudible(track)) continue;
      for (final note in track.notes) {
        if (note.startStep != step) continue;
        _maybePlayNote(track, note);
      }
    }
  }

  void _maybePlayNote(Track track, NoteEvent note) {
    final prob = note.probability.clamp(0, 100);
    if (prob < 100) {
      if (_rng.nextInt(100) >= prob) return;
    }
    final vel = note.velocity / 127.0;
    if (track.category == TrackCategory.drums) {
      final pad = DrumPadMap.padIndexForPitch(note.pitch);
      unawaited(triggerPad(track, pad));
    } else {
      unawaited(triggerNote(track, note.pitch, velocity: vel));
    }
  }

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
    } catch (e, st) {
      ErrorLog.instance.record(e, st);
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
    } catch (e, st) {
      ErrorLog.instance.record(e, st);
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
    } catch (e, st) {
      ErrorLog.instance.record(e, st);
      return e.toString();
    }
  }

  @override
  void dispose() {
    _poller?.cancel();
    _autosaveTimer?.cancel();
    AudioEngine.instance.onInterruption = null;
    AudioEngine.instance.onBecomingNoisy = null;
    unawaited(_mic.dispose());
    WakelockPlus.disable();
    super.dispose();
  }
}
