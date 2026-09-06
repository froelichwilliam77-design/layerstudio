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
    List<Track>? tracks,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : tracks = tracks ?? <Track>[],
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
  List<Track> tracks;
  DateTime createdAt;
  DateTime updatedAt;

  int get stepsPerBar => timeSignatureNum * 4; // 16ths assuming 4/4 quarter=4
  int get totalSteps => bars * stepsPerBar;

  double get secondsPerStep => (60.0 / bpm) / 4.0;

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
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory StudioProject.fromJson(Map<String, dynamic> json) => StudioProject(
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
        tracks: ((json['tracks'] as List?) ?? [])
            .map((e) => Track.fromJson(e as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}
