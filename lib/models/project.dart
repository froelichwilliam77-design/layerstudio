import 'pattern.dart';
import 'track.dart';

class StudioProject {
  StudioProject({
    required this.id,
    required this.name,
    this.bpm = 120,
    this.timeSignatureNum = 4,
    this.timeSignatureDen = 4,
    this.key = 'C',
    this.scale = 'major',
    this.bars = 4,
    this.loopEnabled = true,
    this.loopStartStep = 0,
    this.loopEndStep = 64,
    this.swingPercent = 0,
    this.metronomeEnabled = false,
    this.countInBars = 0,
    this.songMode = false,
    this.cueMode = false,
    this.latencyCompensationMs = 0,
    this.activePatternIndex = 0,
    List<Track>? tracks,
    List<Pattern>? patterns,
    List<ArrangementClip>? arrangement,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : tracks = tracks ?? <Track>[],
        patterns = patterns ??
            [
              Pattern(id: 'pat_a', name: 'A'),
              Pattern(id: 'pat_b', name: 'B'),
              Pattern(id: 'pat_c', name: 'C'),
              Pattern(id: 'pat_d', name: 'D'),
            ],
        arrangement = arrangement ?? <ArrangementClip>[],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String name;
  int bpm;
  int timeSignatureNum;
  int timeSignatureDen;
  String key;
  String scale;
  int bars;
  bool loopEnabled;
  int loopStartStep;
  int loopEndStep;

  /// 0–100 swing: delays even 16ths toward the next odd step.
  int swingPercent;

  bool metronomeEnabled;

  /// 0 = off, 1 or 2 bars of count-in before play/record.
  int countInBars;

  /// When true, transport follows [arrangement] clips; else loops active pattern.
  bool songMode;

  /// Headphone-style PFL: only tracks with [Track.cue] are audible.
  bool cueMode;

  /// Default mic latency compensation (ms) when a track has no override.
  int latencyCompensationMs;

  int activePatternIndex;
  List<Track> tracks;
  List<Pattern> patterns;
  List<ArrangementClip> arrangement;
  DateTime createdAt;
  DateTime updatedAt;

  int get stepsPerBar => timeSignatureNum * 4; // 16ths assuming 4/4 quarter=4
  int get totalSteps => bars * stepsPerBar;

  double get secondsPerStep => (60.0 / bpm) / 4.0;

  Pattern get activePattern {
    if (patterns.isEmpty) {
      patterns.add(Pattern(id: 'pat_a', name: 'A'));
    }
    final i = activePatternIndex.clamp(0, patterns.length - 1);
    return patterns[i];
  }

  /// End bar exclusive of arrangement (or bars if empty).
  int get arrangementEndBar {
    if (arrangement.isEmpty) return bars;
    var maxEnd = 0;
    for (final c in arrangement) {
      if (c.endBar > maxEnd) maxEnd = c.endBar;
    }
    return maxEnd < 1 ? bars : maxEnd;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'bpm': bpm,
        'timeSignatureNum': timeSignatureNum,
        'timeSignatureDen': timeSignatureDen,
        'key': key,
        'scale': scale,
        'bars': bars,
        'loopEnabled': loopEnabled,
        'loopStartStep': loopStartStep,
        'loopEndStep': loopEndStep,
        'swingPercent': swingPercent,
        'metronomeEnabled': metronomeEnabled,
        'countInBars': countInBars,
        'songMode': songMode,
        'cueMode': cueMode,
        'latencyCompensationMs': latencyCompensationMs,
        'activePatternIndex': activePatternIndex,
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'patterns': patterns.map((p) => p.toJson()).toList(),
        'arrangement': arrangement.map((c) => c.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory StudioProject.fromJson(Map<String, dynamic> json) {
    final patternsRaw = (json['patterns'] as List?) ?? [];
    List<Pattern> patterns;
    if (patternsRaw.isEmpty) {
      // Migrate legacy projects: put track notes into pattern A.
      patterns = [
        Pattern(id: 'pat_a', name: 'A'),
        Pattern(id: 'pat_b', name: 'B'),
        Pattern(id: 'pat_c', name: 'C'),
        Pattern(id: 'pat_d', name: 'D'),
      ];
      final tracks = ((json['tracks'] as List?) ?? [])
          .map((e) => Track.fromJson(e as Map<String, dynamic>))
          .toList();
      for (final t in tracks) {
        patterns[0].setNotesFor(
          t.id,
          t.notes.map((n) => n.copyWith()).toList(),
        );
      }
      return StudioProject(
        id: json['id'] as String,
        name: json['name'] as String,
        bpm: (json['bpm'] as int?) ?? 120,
        timeSignatureNum: (json['timeSignatureNum'] as int?) ?? 4,
        timeSignatureDen: (json['timeSignatureDen'] as int?) ?? 4,
        key: (json['key'] as String?) ?? 'C',
        scale: (json['scale'] as String?) ?? 'major',
        bars: (json['bars'] as int?) ?? 4,
        loopEnabled: (json['loopEnabled'] as bool?) ?? true,
        loopStartStep: (json['loopStartStep'] as int?) ?? 0,
        loopEndStep: (json['loopEndStep'] as int?) ?? 64,
        swingPercent: (json['swingPercent'] as int?) ?? 0,
        metronomeEnabled: (json['metronomeEnabled'] as bool?) ?? false,
        countInBars: (json['countInBars'] as int?) ?? 0,
        songMode: (json['songMode'] as bool?) ?? false,
        cueMode: (json['cueMode'] as bool?) ?? false,
        latencyCompensationMs: (json['latencyCompensationMs'] as int?) ?? 0,
        activePatternIndex: (json['activePatternIndex'] as int?) ?? 0,
        tracks: tracks,
        patterns: patterns,
        arrangement: ((json['arrangement'] as List?) ?? [])
            .map((e) => ArrangementClip.fromJson(e as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );
    }

    return StudioProject(
      id: json['id'] as String,
      name: json['name'] as String,
      bpm: (json['bpm'] as int?) ?? 120,
      timeSignatureNum: (json['timeSignatureNum'] as int?) ?? 4,
      timeSignatureDen: (json['timeSignatureDen'] as int?) ?? 4,
      key: (json['key'] as String?) ?? 'C',
      scale: (json['scale'] as String?) ?? 'major',
      bars: (json['bars'] as int?) ?? 4,
      loopEnabled: (json['loopEnabled'] as bool?) ?? true,
      loopStartStep: (json['loopStartStep'] as int?) ?? 0,
      loopEndStep: (json['loopEndStep'] as int?) ?? 64,
      swingPercent: (json['swingPercent'] as int?) ?? 0,
      metronomeEnabled: (json['metronomeEnabled'] as bool?) ?? false,
      countInBars: (json['countInBars'] as int?) ?? 0,
      songMode: (json['songMode'] as bool?) ?? false,
      cueMode: (json['cueMode'] as bool?) ?? false,
      latencyCompensationMs: (json['latencyCompensationMs'] as int?) ?? 0,
      activePatternIndex: (json['activePatternIndex'] as int?) ?? 0,
      tracks: ((json['tracks'] as List?) ?? [])
          .map((e) => Track.fromJson(e as Map<String, dynamic>))
          .toList(),
      patterns: patternsRaw
          .map((e) => Pattern.fromJson(e as Map<String, dynamic>))
          .toList(),
      arrangement: ((json['arrangement'] as List?) ?? [])
          .map((e) => ArrangementClip.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
