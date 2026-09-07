import 'note_event.dart';

/// One groove pattern (A/B/C/D bank entry). Notes keyed by track id.
class Pattern {
  Pattern({
    required this.id,
    required this.name,
    Map<String, List<NoteEvent>>? notesByTrackId,
  }) : notesByTrackId = notesByTrackId ?? <String, List<NoteEvent>>{};

  final String id;
  String name;
  Map<String, List<NoteEvent>> notesByTrackId;

  List<NoteEvent> notesFor(String trackId) =>
      notesByTrackId.putIfAbsent(trackId, () => <NoteEvent>[]);

  void setNotesFor(String trackId, List<NoteEvent> notes) {
    notesByTrackId[trackId] = notes;
  }

  void clearTrack(String trackId) {
    notesByTrackId[trackId] = <NoteEvent>[];
  }

  void clearAll() {
    for (final k in notesByTrackId.keys.toList()) {
      notesByTrackId[k] = <NoteEvent>[];
    }
  }

  Pattern deepCopy({String? id, String? name}) {
    final copy = Pattern(id: id ?? this.id, name: name ?? this.name);
    notesByTrackId.forEach((trackId, notes) {
      copy.notesByTrackId[trackId] =
          notes.map((n) => n.copyWith(id: n.id)).toList();
    });
    return copy;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'notesByTrackId': notesByTrackId.map(
          (k, v) => MapEntry(k, v.map((n) => n.toJson()).toList()),
        ),
      };

  factory Pattern.fromJson(Map<String, dynamic> json) {
    final raw = (json['notesByTrackId'] as Map?) ?? {};
    final map = <String, List<NoteEvent>>{};
    raw.forEach((k, v) {
      map[k as String] = ((v as List?) ?? [])
          .map((e) => NoteEvent.fromJson(e as Map<String, dynamic>))
          .toList();
    });
    return Pattern(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? 'Pattern',
      notesByTrackId: map,
    );
  }
}

/// Places a pattern on the song timeline (bars are 1-based length in bars).
class ArrangementClip {
  ArrangementClip({
    required this.id,
    required this.patternId,
    required this.startBar,
    this.lengthBars = 1,
  });

  final String id;
  String patternId;
  int startBar; // 0-based bar index
  int lengthBars;

  int get endBar => startBar + lengthBars;

  ArrangementClip copyWith({
    String? patternId,
    int? startBar,
    int? lengthBars,
  }) {
    return ArrangementClip(
      id: id,
      patternId: patternId ?? this.patternId,
      startBar: startBar ?? this.startBar,
      lengthBars: lengthBars ?? this.lengthBars,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'patternId': patternId,
        'startBar': startBar,
        'lengthBars': lengthBars,
      };

  factory ArrangementClip.fromJson(Map<String, dynamic> json) =>
      ArrangementClip(
        id: json['id'] as String,
        patternId: json['patternId'] as String,
        startBar: (json['startBar'] as int?) ?? 0,
        lengthBars: (json['lengthBars'] as int?) ?? 1,
      );
}
