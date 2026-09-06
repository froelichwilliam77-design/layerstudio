import '../models/track.dart';

class SoundPreset {
  const SoundPreset({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.samplePath,
    required this.rootMidi,
    required this.colorValue,
    this.drumKit,
  });

  final String id;
  final String name;
  final TrackCategory category;
  final String description;
  final String samplePath;
  final int rootMidi;
  final int colorValue;

  /// For drum kits: pad name → asset path.
  final Map<String, String>? drumKit;
}

/// Built-in MVP library (synthetic samples — see README for licenses).
class SoundLibrary {
  static const List<SoundPreset> all = [
    // Drums
    SoundPreset(
      id: 'drums_rock',
      name: 'Acoustic Rock Kit',
      category: TrackCategory.drums,
      description: 'Kick, snare, hats & tom for rock grooves.',
      samplePath: 'assets/samples/drums/rock_kick.wav',
      rootMidi: 36,
      colorValue: 0xFFE57373,
      drumKit: {
        'Kick': 'assets/samples/drums/rock_kick.wav',
        'Snare': 'assets/samples/drums/rock_snare.wav',
        'Hat Closed': 'assets/samples/drums/rock_hat_closed.wav',
        'Hat Open': 'assets/samples/drums/rock_hat_open.wav',
        'Tom': 'assets/samples/drums/rock_tom.wav',
      },
    ),
    SoundPreset(
      id: 'drums_elec',
      name: 'Electronic / Hip-Hop Kit',
      category: TrackCategory.drums,
      description: '808 kick, clap, tight hats & perc.',
      samplePath: 'assets/samples/drums/elec_kick.wav',
      rootMidi: 36,
      colorValue: 0xFFBA68C8,
      drumKit: {
        'Kick': 'assets/samples/drums/elec_kick.wav',
        'Snare': 'assets/samples/drums/elec_snare.wav',
        'Hat': 'assets/samples/drums/elec_hat.wav',
        'Clap': 'assets/samples/drums/elec_clap.wav',
        'Perc': 'assets/samples/drums/elec_perc.wav',
      },
    ),
    // Bass
    SoundPreset(
      id: 'bass_clean',
      name: 'Clean Finger Bass',
      category: TrackCategory.bass,
      description: 'Warm fingered electric bass.',
      samplePath: 'assets/samples/bass/bass_clean_c2.wav',
      rootMidi: 36, // C2
      colorValue: 0xFF4DB6AC,
    ),
    SoundPreset(
      id: 'bass_driven',
      name: 'Driven Bass',
      category: TrackCategory.bass,
      description: 'Slightly overdriven bass for rock/indie.',
      samplePath: 'assets/samples/bass/bass_driven_c2.wav',
      rootMidi: 36,
      colorValue: 0xFF26A69A,
    ),
    SoundPreset(
      id: 'bass_808',
      name: 'Synth / 808 Bass',
      category: TrackCategory.bass,
      description: 'Deep subby 808-style sine bass.',
      samplePath: 'assets/samples/bass/bass_808_c2.wav',
      rootMidi: 36,
      colorValue: 0xFF00897B,
    ),
    // Guitar
    SoundPreset(
      id: 'gtr_clean',
      name: 'Clean Guitar',
      category: TrackCategory.guitar,
      description: 'Plucked clean electric tone.',
      samplePath: 'assets/samples/guitar/clean_e2.wav',
      rootMidi: 40, // E2
      colorValue: 0xFFFFB74D,
    ),
    SoundPreset(
      id: 'gtr_crunch',
      name: 'Crunch Guitar',
      category: TrackCategory.guitar,
      description: 'Medium-gain crunch rhythm tone.',
      samplePath: 'assets/samples/guitar/crunch_e2.wav',
      rootMidi: 40,
      colorValue: 0xFFFFA726,
    ),
    SoundPreset(
      id: 'gtr_high',
      name: 'High-Gain Guitar',
      category: TrackCategory.guitar,
      description: 'Saturated lead/rhythm high gain.',
      samplePath: 'assets/samples/guitar/highgain_e2.wav',
      rootMidi: 40,
      colorValue: 0xFFEF6C00,
    ),
    // Keys
    SoundPreset(
      id: 'keys_piano',
      name: 'Studio Piano',
      category: TrackCategory.keys,
      description: 'Simple additive piano for melodies & chords.',
      samplePath: 'assets/samples/keys/piano_c4.wav',
      rootMidi: 60, // C4
      colorValue: 0xFF64B5F6,
    ),
    SoundPreset(
      id: 'keys_pad',
      name: 'Soft Pad',
      category: TrackCategory.keys,
      description: 'Slow-attack ambient pad.',
      samplePath: 'assets/samples/keys/pad_c4.wav',
      rootMidi: 60,
      colorValue: 0xFF7986CB,
    ),
  ];

  static SoundPreset? byId(String id) {
    try {
      return all.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  static List<SoundPreset> byCategory(TrackCategory c) =>
      all.where((p) => p.category == c).toList();
}

/// Standard GM-ish drum pad MIDI mapping used in step seq / pads.
class DrumPadMap {
  static const List<String> rockOrder = [
    'Kick',
    'Snare',
    'Hat Closed',
    'Hat Open',
    'Tom',
  ];
  static const List<String> elecOrder = [
    'Kick',
    'Snare',
    'Hat',
    'Clap',
    'Perc',
  ];

  /// Pitch used in NoteEvent for each pad index.
  static int pitchForPad(int padIndex) => 36 + padIndex;

  static int padIndexForPitch(int pitch) => (pitch - 36).clamp(0, 15);
}
