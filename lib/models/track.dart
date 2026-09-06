import 'fx_settings.dart';
import 'note_event.dart';

enum TrackCategory { drums, bass, guitar, keys }

enum TrackInstrumentMode { drumPads, stepSeq, pianoRoll, keyboard, guitarChords }

class Track {
  Track({
    required this.id,
    required this.name,
    required this.category,
    required this.presetId,
    required this.sampleRoot,
    this.colorValue = 0xFF4FC3F7,
    this.volume = 0.85,
    this.pan = 0.0,
    this.muted = false,
    this.solo = false,
    List<NoteEvent>? notes,
    FxSettings? fx,
    this.instrumentMode,
    this.rootMidi = 36,
  })  : notes = notes ?? <NoteEvent>[],
        fx = fx ?? FxSettings();

  final String id;
  String name;
  TrackCategory category;
  String presetId;

  /// Asset path for the root sample (pitch reference).
  String sampleRoot;

  /// MIDI note the [sampleRoot] was recorded at.
  int rootMidi;

  int colorValue;
  double volume; // 0–1
  double pan; // -1..1
  bool muted;
  bool solo;
  List<NoteEvent> notes;
  FxSettings fx;
  TrackInstrumentMode? instrumentMode;

  TrackInstrumentMode get effectiveMode {
    if (instrumentMode != null) return instrumentMode!;
    return switch (category) {
      TrackCategory.drums => TrackInstrumentMode.stepSeq,
      TrackCategory.bass => TrackInstrumentMode.pianoRoll,
      TrackCategory.guitar => TrackInstrumentMode.guitarChords,
      TrackCategory.keys => TrackInstrumentMode.keyboard,
    };
  }

  Track copyWith({
    String? name,
    double? volume,
    double? pan,
    bool? muted,
    bool? solo,
    List<NoteEvent>? notes,
    FxSettings? fx,
    TrackInstrumentMode? instrumentMode,
  }) {
    return Track(
      id: id,
      name: name ?? this.name,
      category: category,
      presetId: presetId,
      sampleRoot: sampleRoot,
      rootMidi: rootMidi,
      colorValue: colorValue,
      volume: volume ?? this.volume,
      pan: pan ?? this.pan,
      muted: muted ?? this.muted,
      solo: solo ?? this.solo,
      notes: notes ?? this.notes,
      fx: fx ?? this.fx,
      instrumentMode: instrumentMode ?? this.instrumentMode,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category.name,
        'presetId': presetId,
        'sampleRoot': sampleRoot,
        'rootMidi': rootMidi,
        'colorValue': colorValue,
        'volume': volume,
        'pan': pan,
        'muted': muted,
        'solo': solo,
        'notes': notes.map((n) => n.toJson()).toList(),
        'fx': fx.toJson(),
        'instrumentMode': instrumentMode?.name,
      };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        id: json['id'] as String,
        name: json['name'] as String,
        category: TrackCategory.values.firstWhere(
          (e) => e.name == json['category'],
          orElse: () => TrackCategory.keys,
        ),
        presetId: json['presetId'] as String,
        sampleRoot: json['sampleRoot'] as String,
        rootMidi: (json['rootMidi'] as int?) ?? 36,
        colorValue: (json['colorValue'] as int?) ?? 0xFF4FC3F7,
        volume: (json['volume'] as num?)?.toDouble() ?? 0.85,
        pan: (json['pan'] as num?)?.toDouble() ?? 0.0,
        muted: (json['muted'] as bool?) ?? false,
        solo: (json['solo'] as bool?) ?? false,
        notes: ((json['notes'] as List?) ?? [])
            .map((e) => NoteEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
        fx: json['fx'] != null
            ? FxSettings.fromJson(json['fx'] as Map<String, dynamic>)
            : FxSettings(),
        instrumentMode: json['instrumentMode'] != null
            ? TrackInstrumentMode.values.firstWhere(
                (e) => e.name == json['instrumentMode'],
                orElse: () => TrackInstrumentMode.pianoRoll,
              )
            : null,
      );
}
