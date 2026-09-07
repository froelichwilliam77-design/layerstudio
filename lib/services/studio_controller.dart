import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Rect;

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
import '../utils/app_lifecycle_policy.dart';
import '../utils/audio_clock_math.dart';
import '../utils/mixer_routing.dart';
import '../utils/music_theory.dart';
import '../utils/wav_codec.dart';
import 'audio_engine.dart';
import 'command_stack.dart';
import 'error_log.dart';
import 'export_service.dart';
import 'mic_recorder.dart';
import 'midi_input.dart';
import 'project_backup.dart';
import 'project_bundle.dart';
import 'project_store.dart';
import 'studio_audio_handler.dart';
import 'user_sample_store.dart';

enum StudioTab { arrange, drums, piano, keys, guitar, mixer, library }

class StudioController extends ChangeNotifier {
  StudioController({
    ProjectStore? store,
    ExportService? exporter,
    ProjectBundleService? bundle,
    MicRecorder? micRecorder,
  }) : _store = store ?? ProjectStore(),
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
  final UserSampleStore _userSamples = UserSampleStore();
  final ProjectBackup backup = ProjectBackup();
  final MidiInputService midi = MidiInputService();
  final _uuid = const Uuid();
  final CommandStack commands = CommandStack();
  final math.Random _rng = math.Random();
  StudioAudioHandler? audioHandler;

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

  /// Active paint-stroke undo batch (piano roll / step grid drag-paint).
  String? _strokeTrackId;
  Map<String, List<dynamic>>? _strokeBefore;

  /// Soft pitch warning for UI banner.
  String? pitchWarning;

  bool exportBannerDismissed = false;
  bool onboarded = true;
  bool isRecordingMic = false;
  bool isCountingIn = false;
  int countInStepsRemaining = 0;
  int? _recordStartStep;
  String? _recordTrackId;
  String? _gestureBefore;

  Timer? _poller;
  Timer? _autosaveTimer;
  bool _resumeAfterInterruption = false;

  int _scheduledThroughStep = -1;
  double _scheduledThroughOnset = -1;
  final Set<String> _firedKeys = {};

  /// Lookahead window for clocked oneshots (~60ms Timer headroom).
  static const double _lookaheadSec = 0.06;

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
      SoundLibrary.bundled.expand((p) => p.allSamplePaths),
    );
    try {
      SoundLibrary.userPresets
        ..clear()
        ..addAll(await _userSamples.loadAll());
      for (final preset in SoundLibrary.userPresets) {
        if (preset.samplePath.startsWith('/')) {
          await AudioEngine.instance.loadFile(preset.samplePath);
        }
      }
    } catch (e, st) {
      ErrorLog.instance.record(e, st);
    }
    recent = await _store.listProjects();
    try {
      final prefs = await SharedPreferences.getInstance();
      exportBannerDismissed = prefs.getBool('export_banner_dismissed') ?? false;
      onboarded = prefs.getBool('studio_onboarded') ?? false;
    } catch (_) {}
    midi.onNoteOn = _onMidiNoteOn;
    midi.onClockBpm = (bpm) {
      updateProjectMeta(bpm: bpm, recordUndo: false);
    };
    notifyListeners();
  }

  void attachAudioHandler(StudioAudioHandler handler) {
    audioHandler = handler;
    _syncNowPlaying();
  }

  void _syncNowPlaying() {
    audioHandler?.setProject(project?.name ?? 'LayerStudio', playing: isPlaying);
  }

  Future<void> completeOnboarding() async {
    onboarded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('studio_onboarded', true);
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
      t.notes = pat.notesFor(t.id).map((n) => n.copyWith()).toList();
    }
  }

  /// Persist track.notes back into the active pattern.
  void _flushNotesToActivePattern() {
    final p = project;
    if (p == null) return;
    final pat = p.activePattern;
    for (final t in p.tracks) {
      pat.setNotesFor(t.id, t.notes.map((n) => n.copyWith()).toList());
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
    bool? cueMode,
    int? latencyCompensationMs,
    bool recordUndo = true,
  }) {
    final p = project;
    if (p == null) return;
    void apply() {
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
      if (cueMode != null) p.cueMode = cueMode;
      if (latencyCompensationMs != null) {
        p.latencyCompensationMs = latencyCompensationMs.clamp(0, 250);
      }
    }

    if (recordUndo &&
        (name != null ||
            bpm != null ||
            key != null ||
            scale != null ||
            bars != null ||
            songMode != null ||
            cueMode != null ||
            latencyCompensationMs != null)) {
      captureUndo('Project settings', apply);
    } else {
      apply();
      notifyListeners();
    }
  }

  void captureUndo(String label, VoidCallback mutate) {
    final p = project;
    if (p == null) return;
    final before = jsonEncode(p.toJson());
    mutate();
    final after = jsonEncode(p.toJson());
    if (before == after) {
      notifyListeners();
      return;
    }
    commands.push(
      JsonSnapshotCommand(
        label: label,
        apply: _restoreProjectJson,
        before: before,
        after: after,
      ),
      executeNow: false,
    );
    notifyListeners();
  }

  void beginGestureUndo() {
    _gestureBefore = project == null ? null : jsonEncode(project!.toJson());
  }

  void endGestureUndo(String label) {
    final p = project;
    final before = _gestureBefore;
    _gestureBefore = null;
    if (p == null || before == null) return;
    final after = jsonEncode(p.toJson());
    if (before == after) return;
    commands.push(
      JsonSnapshotCommand(
        label: label,
        apply: _restoreProjectJson,
        before: before,
        after: after,
      ),
      executeNow: false,
    );
    notifyListeners();
  }

  void _restoreProjectJson(String raw) {
    final decoded = StudioProject.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    project = decoded;
    if (selectedTrackId == null ||
        !decoded.tracks.any((t) => t.id == selectedTrackId)) {
      selectedTrackId = decoded.tracks.isNotEmpty ? decoded.tracks.first.id : null;
    }
    _hydrateActivePatternNotes();
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
    for (final pat in p.patterns) {
      pat.notesFor(track.id);
    }
    selectedTrackId = track.id;
    selectTrack(track.id);
    await saveNow();
    notifyListeners();
    return track;
  }

  Future<SoundPreset?> importUserSample({
    required Uint8List bytes,
    required String originalName,
    required TrackCategory category,
  }) async {
    try {
      final preset = await _userSamples.importWav(
        bytes: bytes,
        originalName: originalName,
        category: category,
      );
      SoundLibrary.userPresets.add(preset);
      if (preset.samplePath.startsWith('/')) {
        await AudioEngine.instance.loadFile(preset.samplePath);
      }
      notifyListeners();
      return preset;
    } catch (e, st) {
      ErrorLog.instance.record(e, st);
      return null;
    }
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
      colorValue: 0xFF66BB6A,
      instrumentMode: TrackInstrumentMode.micRecord,
    );
    p.tracks.add(track);
    selectedTrackId = track.id;
    await saveNow();
    notifyListeners();
    return track;
  }

  void removeTrack(String id) {
    captureUndo('Remove track', () {
      final p = project;
      if (p == null) return;
      p.tracks.removeWhere((t) => t.id == id);
      for (final pat in p.patterns) {
        pat.notesByTrackId.remove(id);
      }
      if (selectedTrackId == id) {
        selectedTrackId = p.tracks.isNotEmpty ? p.tracks.first.id : null;
      }
    });
  }

  void updateTrack(Track track) {
    notifyListeners();
  }

  void toggleMute(Track track) =>
      captureUndo('Mute', () => track.muted = !track.muted);

  void toggleSolo(Track track) =>
      captureUndo('Solo', () => track.solo = !track.solo);

  void toggleCue(Track track) {
    captureUndo('Cue', () {
      track.cue = !track.cue;
      if (track.cue) project?.cueMode = true;
    });
  }

  void toggleOverdub(Track track) =>
      captureUndo('Overdub', () => track.overdub = !track.overdub);

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

  void _applyPatternSnapshot(
    int patternIndex,
    Map<String, List<dynamic>> snap,
  ) {
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

  void addArrangementClip({
    String? patternId,
    int? startBar,
    int lengthBars = 1,
  }) {
    captureUndo('Add clip', () {
      final p = project;
      if (p == null) return;
      final pid = patternId ?? p.activePattern.id;
      final start =
          startBar ??
          (p.arrangement.isEmpty
              ? 0
              : p.arrangement.map((c) => c.endBar).reduce(math.max));
      p.arrangement.add(
        ArrangementClip(
          id: _uuid.v4(),
          patternId: pid,
          startBar: start,
          lengthBars: lengthBars.clamp(1, 32),
        ),
      );
      p.arrangement.sort((a, b) => a.startBar.compareTo(b.startBar));
    });
  }

  void removeArrangementClip(String id) {
    captureUndo('Remove clip', () {
      project?.arrangement.removeWhere((c) => c.id == id);
    });
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

  void resizeArrangementClip(String id, int lengthBars) {
    captureUndo('Resize clip', () {
      final p = project;
      if (p == null) return;
      for (final c in p.arrangement) {
        if (c.id == id) {
          c.lengthBars = lengthBars.clamp(1, 32);
          break;
        }
      }
    });
  }

  void duplicateArrangementClip(String id) {
    captureUndo('Duplicate clip', () {
      final p = project;
      if (p == null) return;
      ArrangementClip? clip;
      for (final c in p.arrangement) {
        if (c.id == id) {
          clip = c;
          break;
        }
      }
      if (clip == null) return;
      p.arrangement.add(
        ArrangementClip(
          id: _uuid.v4(),
          patternId: clip.patternId,
          startBar: clip.endBar,
          lengthBars: clip.lengthBars,
        ),
      );
      p.arrangement.sort((a, b) => a.startBar.compareTo(b.startBar));
    });
  }

  void setArrangementClipPattern(String id, String patternId) {
    captureUndo('Clip pattern', () {
      final p = project;
      if (p == null) return;
      for (final c in p.arrangement) {
        if (c.id == id) {
          c.patternId = patternId;
          break;
        }
      }
    });
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
    return {trackId: track.notes.map((n) => n.toJson()).toList()};
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
      final preset = SoundLibrary.byId(track.presetId);
      final int clamped;
      if (preset != null) {
        clamped = preset.clampMidi(finalPitch);
      } else {
        clamped = MusicTheory.clampPitch(finalPitch, track.rootMidi);
      }
      if (clamped != finalPitch) {
        // Red banner only when we actually hard-clamp outside bank coverage.
        pitchWarning =
            'Pitch clamped to multi-root bank range (±${MusicTheory.hardPitchRangeSemis} semis past outer roots; SoLoud rate-pitch).';
      } else if (preset != null && preset.exceedsSoftRange(finalPitch)) {
        pitchWarning =
            'Far from nearest sample root — tone may stretch (SoLoud rate-pitch).';
      } else if (preset == null &&
          (MusicTheory.exceedsSoftRange(finalPitch, track.rootMidi))) {
        pitchWarning = 'Pitch far from sample root (SoLoud rate-pitch).';
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
        track.notes.add(
          NoteEvent(
            id: _uuid.v4(),
            pitch: finalPitch,
            startStep: snapped,
            lengthSteps: lengthSteps,
            velocity: velocity ?? drawVelocity,
            probability: probability ?? drawProbability,
          ),
        );
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
        track.notes.add(
          NoteEvent(
            id: _uuid.v4(),
            pitch: pitch,
            startStep: step,
            lengthSteps: 1,
            velocity: drawVelocity,
            probability: probability ?? drawProbability,
          ),
        );
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

  int stepVelocity(Track track, int padIndex, int step) {
    final pitch = DrumPadMap.pitchForPad(padIndex);
    try {
      return track.notes
          .firstWhere((n) => n.pitch == pitch && n.startStep == step)
          .velocity;
    } catch (_) {
      return drawVelocity;
    }
  }

  void setStepVelocity({
    required String trackId,
    required int padIndex,
    required int step,
    required int velocity,
  }) {
    final p = project;
    if (p == null) return;
    final track = p.tracks.firstWhere((t) => t.id == trackId);
    final pitch = DrumPadMap.pitchForPad(padIndex);
    _pushNotesEdit('Step velocity', trackId, () {
      for (final n in track.notes) {
        if (n.pitch == pitch && n.startStep == step) {
          n.velocity = velocity.clamp(1, 127);
        }
      }
    });
  }

  NoteEvent? findNote(Track track, int pitch, int startStep) {
    for (final n in track.notes) {
      if (n.pitch == pitch && n.startStep == startStep) return n;
    }
    return null;
  }

  /// Begin a batched undo stroke for drag-paint on [trackId].
  void beginNoteStroke(String trackId) {
    if (_strokeTrackId != null) {
      endNoteStroke();
    }
    final p = project;
    if (p == null) return;
    _strokeTrackId = trackId;
    _strokeBefore = _snapshotTrackNotes(trackId);
  }

  /// Force a cell on/off during an active paint stroke (no per-cell undo).
  void paintNoteCell({
    required String trackId,
    required int pitch,
    required int startStep,
    required bool on,
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
      final preset = SoundLibrary.byId(track.presetId);
      finalPitch =
          preset?.clampMidi(finalPitch) ??
          MusicTheory.clampPitch(finalPitch, track.rootMidi);
    }
    final snapped = (startStep ~/ snapSteps) * snapSteps;
    track.notes.removeWhere(
      (n) => n.pitch == finalPitch && n.startStep == snapped,
    );
    if (on) {
      track.notes.add(
        NoteEvent(
          id: _uuid.v4(),
          pitch: finalPitch,
          startStep: snapped,
          lengthSteps: lengthSteps,
          velocity: velocity ?? drawVelocity,
          probability: probability ?? drawProbability,
        ),
      );
    }
    notifyListeners();
  }

  /// Force a drum step on/off during an active paint stroke.
  void paintStepCell({
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
      track.notes.add(
        NoteEvent(
          id: _uuid.v4(),
          pitch: pitch,
          startStep: step,
          lengthSteps: 1,
          velocity: drawVelocity,
          probability: drawProbability,
        ),
      );
    }
    notifyListeners();
  }

  /// Commit the active paint stroke as a single undoable command.
  void endNoteStroke({String label = 'Paint notes'}) {
    final trackId = _strokeTrackId;
    final before = _strokeBefore;
    _strokeTrackId = null;
    _strokeBefore = null;
    if (trackId == null || before == null || project == null) return;
    final after = _snapshotTrackNotes(trackId);
    final beforeJson = before[trackId] ?? const [];
    final afterJson = after[trackId] ?? const [];
    if (beforeJson.toString() == afterJson.toString()) return;
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

  /// Per-note parameter lock (velocity / length / probability).
  void setNoteParams({
    required String trackId,
    required String noteId,
    int? velocity,
    int? lengthSteps,
    int? probability,
  }) {
    final p = project;
    if (p == null) return;
    _pushNotesEdit('Note params', trackId, () {
      final track = p.tracks.firstWhere((t) => t.id == trackId);
      for (final n in track.notes) {
        if (n.id != noteId) continue;
        if (velocity != null) n.velocity = velocity.clamp(1, 127);
        if (lengthSteps != null) n.lengthSteps = lengthSteps.clamp(1, 64);
        if (probability != null) n.probability = probability.clamp(0, 100);
      }
    });
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
    final preset = SoundLibrary.byId(track.presetId);
    final clamped =
        preset?.clampMidi(midi) ?? MusicTheory.clampPitch(midi, track.rootMidi);
    final resolved =
        preset?.resolveRoot(clamped) ??
        (path: track.sampleRoot, rootMidi: track.rootMidi);
    await AudioEngine.instance.playSample(
      resolved.path,
      volume: track.volume * (velocity ?? 1.0),
      pan: track.pan,
      pitchMidi: clamped,
      rootMidi: resolved.rootMidi,
      fx: track.fx,
    );
  }

  /// Sequencer path: schedule pad hit at swung [onsetSeconds].
  Future<void> triggerPadClocked(
    Track track,
    int padIndex, {
    required double onsetSeconds,
  }) async {
    final preset = SoundLibrary.byId(track.presetId);
    final kit = preset?.drumKit;
    if (kit == null) return;
    final names = kit.keys.toList();
    if (padIndex >= names.length) return;
    final path = kit[names[padIndex]]!;
    if (!_trackAudible(track)) return;
    await AudioEngine.instance.playSampleClocked(
      path,
      onsetSeconds: onsetSeconds,
      volume: track.volume,
      pan: track.pan,
      fx: track.fx,
    );
  }

  /// Sequencer path: schedule pitched note at swung [onsetSeconds].
  Future<void> triggerNoteClocked(
    Track track,
    int midi, {
    double? velocity,
    required double onsetSeconds,
  }) async {
    if (!_trackAudible(track)) return;
    if (track.category == TrackCategory.mic) {
      final path = track.recordedFilePath;
      if (path == null || path.isEmpty) return;
      await AudioEngine.instance.playSampleClocked(
        path,
        onsetSeconds: onsetSeconds,
        volume: track.volume * (velocity ?? 1.0),
        pan: track.pan,
        fx: track.fx,
      );
      return;
    }
    final preset = SoundLibrary.byId(track.presetId);
    final clamped =
        preset?.clampMidi(midi) ?? MusicTheory.clampPitch(midi, track.rootMidi);
    final resolved =
        preset?.resolveRoot(clamped) ??
        (path: track.sampleRoot, rootMidi: track.rootMidi);
    await AudioEngine.instance.playSampleClocked(
      resolved.path,
      onsetSeconds: onsetSeconds,
      volume: track.volume * (velocity ?? 1.0),
      pan: track.pan,
      pitchMidi: clamped,
      rootMidi: resolved.rootMidi,
      fx: track.fx,
    );
  }

  bool _trackAudible(Track track) {
    final p = project;
    if (p == null) return false;
    return isTrackAudible(track, project: p);
  }

  void _onMidiNoteOn(int midiNote, int velocity) {
    final track = selectedTrack;
    if (track == null) return;
    final vel = (velocity / 127.0).clamp(0.05, 1.0);
    if (track.category == TrackCategory.drums) {
      unawaited(triggerPad(track, DrumPadMap.padIndexForPitch(midiNote)));
    } else {
      unawaited(triggerNote(track, midiNote, velocity: vel));
    }
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
      _recordTrackId = armed.id;
      _recordStartStep = playheadStep;
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
      final startStep = _recordStartStep ?? 0;
      final trackId = _recordTrackId;
      _recordStartStep = null;
      _recordTrackId = null;
      if (p != null && path != null && trackId != null) {
        for (final t in p.tracks) {
          if (t.id != trackId) continue;
          final latencyMs =
              t.latencyMs != 0 ? t.latencyMs : p.latencyCompensationMs;
          final latSteps =
              (latencyMs / 1000.0 / p.secondsPerStep).round();
          final placed = (startStep - latSteps).clamp(0, p.loopEndStep);
          var outPath = path;
          if (t.overdub &&
              t.recordedFilePath != null &&
              File(t.recordedFilePath!).existsSync()) {
            outPath = await _mixOverdubTakes(
              existingPath: t.recordedFilePath!,
              takePath: path,
              offsetSteps: placed,
              secondsPerStep: p.secondsPerStep,
            );
          }
          t.recordedFilePath = outPath;
          t.sampleRoot = outPath;
          t.recordArmed = false;
          await AudioEngine.instance.loadFile(outPath);
          var lengthSteps = p.loopEndStep.clamp(1, p.totalSteps);
          try {
            final pcm = decodeWavStereo(await File(outPath).readAsBytes());
            if (pcm != null) {
              lengthSteps = math.max(
                1,
                (pcm.frames / ExportService.sampleRate / p.secondsPerStep)
                    .round(),
              );
            }
          } catch (_) {}
          t.notes.removeWhere(
            (n) => n.startStep == placed && n.pitch == 60,
          );
          t.notes.add(
            NoteEvent(
              id: _uuid.v4(),
              pitch: 60,
              startStep: placed,
              lengthSteps: lengthSteps,
              velocity: 100,
            ),
          );
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
      _scheduledThroughOnset = AudioClockMath.stepOnsetSeconds(
        playheadStep - 1,
        p.bpm,
        p.swingPercent,
      );
      unawaited(_startMicIfArmed());
    }

    WakelockPlus.enable();
    _poller?.cancel();
    _poller = Timer.periodic(const Duration(milliseconds: 8), (_) {
      _onTransportPoll();
    });
    _onTransportPoll();
    _syncNowPlaying();
    notifyListeners();
  }

  void pause() {
    isPlaying = false;
    isCountingIn = false;
    _poller?.cancel();
    AudioEngine.instance.pauseTransportClock();
    unawaited(_stopMicIfRecording());
    WakelockPlus.disable();
    _syncNowPlaying();
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
    _syncNowPlaying();
    notifyListeners();
  }

  void togglePlay() => isPlaying ? pause() : play();

  void onAppLifecycle(AppLifecycleState state) {
    switch (transportActionForLifecycle(state)) {
      case TransportLifecycleAction.none:
        break;
      case TransportLifecycleAction.saveOnly:
        unawaited(saveNow());
      case TransportLifecycleAction.pauseAndSave:
        if (isPlaying) pause();
        unawaited(saveNow());
      case TransportLifecycleAction.reactivateSession:
        unawaited(AudioEngine.instance.activateSession());
      case TransportLifecycleAction.stopAndSave:
        stop();
        unawaited(saveNow());
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

  /// Sync Mini Amp Sim knobs into EQ shelves used by export; live path reads
  /// gain/tone/cabSim directly in AudioEngine._applyVoiceFx.
  void updateTrackFx(Track track, {FxSettings? fx}) {
    if (fx != null) track.fx = fx;
    final f = track.fx;
    final tone = f.tone.clamp(0.0, 1.0);
    f.eqHigh = (tone * 2 - 1).clamp(-1.0, 1.0);
    f.eqLow = ((1 - tone) * 0.35 - 0.15).clamp(-1.0, 1.0);
    // Nudge amp preset from gain for bass/guitar so wave-shaper has a base.
    if (track.category == TrackCategory.bass ||
        track.category == TrackCategory.guitar) {
      if (f.gain > 0.62 &&
          (f.ampPreset == AmpPreset.clean || f.ampPreset == AmpPreset.none)) {
        f.ampPreset = track.category == TrackCategory.bass
            ? AmpPreset.bassDrive
            : AmpPreset.crunch;
      } else if (f.gain < 0.22 &&
          (f.ampPreset == AmpPreset.crunch ||
              f.ampPreset == AmpPreset.bassDrive)) {
        f.ampPreset = AmpPreset.clean;
      }
    }
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
      // Schedule at exact swung onset (delay) instead of immediate fire.
      _fireStep(item.step, onsetSeconds: item.onset);
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
      unawaited(
        AudioEngine.instance.playMetronomeClickClocked(
          accent: accent,
          onsetSeconds: item.onset,
        ),
      );
    }
  }

  void _fireStep(int step, {required double onsetSeconds}) {
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
          _maybePlayNote(track, note, onsetSeconds: onsetSeconds);
        }
      }
      return;
    }

    for (final track in tracks) {
      if (!_trackAudible(track)) continue;
      for (final note in track.notes) {
        if (note.startStep != step) continue;
        _maybePlayNote(track, note, onsetSeconds: onsetSeconds);
      }
    }
  }

  void _maybePlayNote(
    Track track,
    NoteEvent note, {
    required double onsetSeconds,
  }) {
    final prob = note.probability.clamp(0, 100);
    if (prob < 100) {
      if (_rng.nextInt(100) >= prob) return;
    }
    final vel = note.velocity / 127.0;
    if (track.category == TrackCategory.drums) {
      final pad = DrumPadMap.padIndexForPitch(note.pitch);
      unawaited(triggerPadClocked(track, pad, onsetSeconds: onsetSeconds));
    } else {
      unawaited(
        triggerNoteClocked(
          track,
          note.pitch,
          velocity: vel,
          onsetSeconds: onsetSeconds,
        ),
      );
    }
  }

  void notifyFxChanged() {
    notifyListeners();
  }

  Future<String?> exportAndShare({
    Rect? shareOrigin,
    MixExportFormat format = MixExportFormat.wav16,
  }) async {
    final p = project;
    if (p == null) return 'No project open';
    try {
      pause();
      final file = await _exporter.exportMix(p, format: format);
      await _exporter.shareFile(file, shareOrigin: shareOrigin);
      return null;
    } catch (e, st) {
      ErrorLog.instance.record(e, st);
      return e.toString();
    }
  }

  Future<String?> exportProjectBundle({Rect? shareOrigin}) async {
    final p = project;
    if (p == null) return 'No project open';
    try {
      await saveNow();
      await _bundle.shareProject(p, shareOrigin: shareOrigin);
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

  Future<String?> importProjectBytes(Uint8List bytes) async {
    try {
      stop();
      final imported = await _bundle.importFromBytes(bytes);
      await openProject(imported);
      await refreshRecent();
      return null;
    } catch (e, st) {
      ErrorLog.instance.record(e, st);
      return e.toString();
    }
  }

  Future<String?> shareAllProjectsBackup({Rect? shareOrigin}) async {
    try {
      await refreshRecent();
      await backup.shareAll(recent, shareOrigin: shareOrigin);
      return null;
    } catch (e, st) {
      ErrorLog.instance.record(e, st);
      return e.toString();
    }
  }

  Future<String> _mixOverdubTakes({
    required String existingPath,
    required String takePath,
    required int offsetSteps,
    required double secondsPerStep,
  }) async {
    final existingBytes = await File(existingPath).readAsBytes();
    final takeBytes = await File(takePath).readAsBytes();
    final existing = decodeWavStereo(existingBytes);
    final take = decodeWavStereo(takeBytes);
    if (existing == null || take == null) return takePath;
    final offset = (offsetSteps * secondsPerStep * ExportService.sampleRate)
        .round();
    final mixed = overlayStereo(existing, take, offsetFrames: offset);
    final bytes = encodeFloatStereoWav16(mixed, ExportService.sampleRate);
    await File(existingPath).writeAsBytes(bytes, flush: true);
    return existingPath;
  }

  @override
  void dispose() {
    _poller?.cancel();
    _autosaveTimer?.cancel();
    AudioEngine.instance.onInterruption = null;
    AudioEngine.instance.onBecomingNoisy = null;
    unawaited(_mic.dispose());
    unawaited(midi.dispose());
    WakelockPlus.disable();
    super.dispose();
  }
}
