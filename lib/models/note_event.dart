/// A single note or drum hit on the timeline.
class NoteEvent {
  NoteEvent({
    required this.id,
    required this.pitch,
    required this.startStep,
    this.lengthSteps = 1,
    this.velocity = 100,
    this.probability = 100,
  });

  final String id;

  /// MIDI pitch (0–127). For drums, maps to pad index via kit mapping.
  int pitch;

  /// Position in 16th-note steps from project start.
  int startStep;

  /// Length in 16th-note steps.
  int lengthSteps;

  /// 1–127
  int velocity;

  /// 0–100 chance this note fires when its step is reached (default 100).
  int probability;

  NoteEvent copyWith({
    String? id,
    int? pitch,
    int? startStep,
    int? lengthSteps,
    int? velocity,
    int? probability,
  }) {
    return NoteEvent(
      id: id ?? this.id,
      pitch: pitch ?? this.pitch,
      startStep: startStep ?? this.startStep,
      lengthSteps: lengthSteps ?? this.lengthSteps,
      velocity: velocity ?? this.velocity,
      probability: probability ?? this.probability,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'pitch': pitch,
        'startStep': startStep,
        'lengthSteps': lengthSteps,
        'velocity': velocity,
        'probability': probability,
      };

  factory NoteEvent.fromJson(Map<String, dynamic> json) => NoteEvent(
        id: json['id'] as String,
        pitch: json['pitch'] as int,
        startStep: json['startStep'] as int,
        lengthSteps: (json['lengthSteps'] as int?) ?? 1,
        velocity: (json['velocity'] as int?) ?? 100,
        probability: (json['probability'] as int?) ?? 100,
      );
}
