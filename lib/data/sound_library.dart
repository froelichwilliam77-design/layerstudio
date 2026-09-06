import '../models/track.dart';

/// One pitched root sample in a multi-root bank.
class SoundRoot {
  const SoundRoot({required this.midi, required this.samplePath});

  final int midi;
  final String samplePath;
}

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
    this.roots,
  });

  final String id;
  final String name;
  final TrackCategory category;
  final String description;

  /// Primary / default sample (backward compatible).
  final String samplePath;

  /// MIDI note of [samplePath].
  final int rootMidi;
  final int colorValue;

  /// For drum kits: pad name → asset path.
  final Map<String, String>? drumKit;

  /// Optional multi-root bank for melodic presets.
  final List<SoundRoot>? roots;

  /// Nearest root sample for [midi] by absolute semitone distance.
  /// Falls back to [samplePath] / [rootMidi] when [roots] is empty/null.
  ({String path, int rootMidi}) resolveRoot(int midi) {
    final bank = roots;
    if (bank == null || bank.isEmpty) {
      return (path: samplePath, rootMidi: rootMidi);
    }
    SoundRoot best = bank.first;
    var bestDist = (midi - best.midi).abs();
    for (var i = 1; i < bank.length; i++) {
      final r = bank[i];
      final d = (midi - r.midi).abs();
      if (d < bestDist) {
        best = r;
        bestDist = d;
      }
    }
    return (path: best.samplePath, rootMidi: best.midi);
  }

  /// Hard playable MIDI span: bank [min,max] ± 24, or primary root ± 24.
  ({int lo, int hi}) get pitchHardRange {
    final bank = roots;
    if (bank == null || bank.isEmpty) {
      return (lo: rootMidi - 24, hi: rootMidi + 24);
    }
    var minM = bank.first.midi;
    var maxM = bank.first.midi;
    for (final r in bank) {
      if (r.midi < minM) minM = r.midi;
      if (r.midi > maxM) maxM = r.midi;
    }
    return (lo: minM - 24, hi: maxM + 24);
  }

  /// Clamp [midi] into the multi-root bank hard range (or primary ±24).
  int clampMidi(int midi) {
    final r = pitchHardRange;
    if (midi < r.lo) return r.lo;
    if (midi > r.hi) return r.hi;
    return midi;
  }

  /// True when [midi] is farther than ±12 semis from the nearest root.
  /// Inside a multi-root bank (octave spacing) this is rare — residual ≤ 6.
  bool exceedsSoftRange(int midi) {
    final resolved = resolveRoot(midi);
    return (midi - resolved.rootMidi).abs() > 12;
  }

  /// All asset paths that should be preloaded for this preset.
  Iterable<String> get allSamplePaths {
    if (drumKit != null) return drumKit!.values;
    if (roots != null && roots!.isNotEmpty) {
      return roots!.map((r) => r.samplePath);
    }
    return [samplePath];
  }
}

/// Built-in library (synthetic samples — see assets/samples/LICENSE).
class SoundLibrary {
  static const List<SoundPreset> all = [
    // —— Drums (hip-hop / trap / electronic first) ——
    SoundPreset(
      id: 'drums_trap',
      name: 'Trap Heat',
      category: TrackCategory.drums,
      description: 'Deep 808 kick, crisp snare & clap, ticking hats for trap.',
      samplePath: 'assets/samples/drums/trap_kick.wav',
      rootMidi: 36,
      colorValue: 0xFFE040FB,
      drumKit: {
        'Kick': 'assets/samples/drums/trap_kick.wav',
        'Snare': 'assets/samples/drums/trap_snare.wav',
        'Hat': 'assets/samples/drums/trap_hat.wav',
        'Open Hat': 'assets/samples/drums/trap_open.wav',
        'Clap': 'assets/samples/drums/trap_clap.wav',
      },
    ),
    SoundPreset(
      id: 'drums_boombap',
      name: 'Boom Bap Classic',
      category: TrackCategory.drums,
      description: 'Dusty hip-hop kick/snare with rim and vintage hats.',
      samplePath: 'assets/samples/drums/boombap_kick.wav',
      rootMidi: 36,
      colorValue: 0xFFFF8A65,
      drumKit: {
        'Kick': 'assets/samples/drums/boombap_kick.wav',
        'Snare': 'assets/samples/drums/boombap_snare.wav',
        'Hat': 'assets/samples/drums/boombap_hat.wav',
        'Open Hat': 'assets/samples/drums/boombap_open.wav',
        'Rim': 'assets/samples/drums/boombap_rim.wav',
      },
    ),
    SoundPreset(
      id: 'drums_drill',
      name: 'Drill Dark',
      category: TrackCategory.drums,
      description: 'Low 808, snappy snare, dark ticking hats for drill.',
      samplePath: 'assets/samples/drums/drill_kick.wav',
      rootMidi: 36,
      colorValue: 0xFF7E57C2,
      drumKit: {
        'Kick': 'assets/samples/drums/drill_kick.wav',
        'Snare': 'assets/samples/drums/drill_snare.wav',
        'Hat': 'assets/samples/drums/drill_hat.wav',
        'Open Hat': 'assets/samples/drums/drill_open.wav',
        'Perc': 'assets/samples/drums/drill_perc.wav',
      },
    ),
    SoundPreset(
      id: 'drums_lofi',
      name: 'Lo-Fi Chill',
      category: TrackCategory.drums,
      description: 'Warm dusty drums and shaker for chill beats.',
      samplePath: 'assets/samples/drums/lofi_kick.wav',
      rootMidi: 36,
      colorValue: 0xFFA1887F,
      drumKit: {
        'Kick': 'assets/samples/drums/lofi_kick.wav',
        'Snare': 'assets/samples/drums/lofi_snare.wav',
        'Hat': 'assets/samples/drums/lofi_hat.wav',
        'Open Hat': 'assets/samples/drums/lofi_open.wav',
        'Shaker': 'assets/samples/drums/lofi_perc.wav',
      },
    ),
    SoundPreset(
      id: 'drums_house',
      name: 'House Pulse',
      category: TrackCategory.drums,
      description: 'Four-on-the-floor kick, clap, and bright house hats.',
      samplePath: 'assets/samples/drums/house_kick.wav',
      rootMidi: 36,
      colorValue: 0xFF42A5F5,
      drumKit: {
        'Kick': 'assets/samples/drums/house_kick.wav',
        'Clap': 'assets/samples/drums/house_clap.wav',
        'Hat': 'assets/samples/drums/house_hat.wav',
        'Open Hat': 'assets/samples/drums/house_open.wav',
        'Perc': 'assets/samples/drums/house_perc.wav',
      },
    ),
    SoundPreset(
      id: 'drums_techno',
      name: 'Techno Drive',
      category: TrackCategory.drums,
      description: 'Hard techno kick, industrial snare & metallic hats.',
      samplePath: 'assets/samples/drums/techno_kick.wav',
      rootMidi: 36,
      colorValue: 0xFF26C6DA,
      drumKit: {
        'Kick': 'assets/samples/drums/techno_kick.wav',
        'Snare': 'assets/samples/drums/techno_snare.wav',
        'Hat': 'assets/samples/drums/techno_hat.wav',
        'Open Hat': 'assets/samples/drums/techno_open.wav',
        'Perc': 'assets/samples/drums/techno_perc.wav',
      },
    ),
    SoundPreset(
      id: 'drums_synthwave',
      name: 'Synthwave Neon',
      category: TrackCategory.drums,
      description: 'Retro 80s kick/snare with clap and soft tom.',
      samplePath: 'assets/samples/drums/synthwave_kick.wav',
      rootMidi: 36,
      colorValue: 0xFFEC407A,
      drumKit: {
        'Kick': 'assets/samples/drums/synthwave_kick.wav',
        'Snare': 'assets/samples/drums/synthwave_snare.wav',
        'Hat': 'assets/samples/drums/synthwave_hat.wav',
        'Clap': 'assets/samples/drums/synthwave_clap.wav',
        'Tom': 'assets/samples/drums/synthwave_tom.wav',
      },
    ),
    SoundPreset(
      id: 'drums_elec',
      name: 'Club Electro',
      category: TrackCategory.drums,
      description: '808 kick, tight snare, clap & perc for electronic/hip-hop.',
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
    // —— Rock / indie ——
    SoundPreset(
      id: 'drums_rock',
      name: 'Acoustic Rock Kit',
      category: TrackCategory.drums,
      description: 'Punchier kick, clearer snare, hats & tom for rock grooves.',
      samplePath: 'assets/samples/drums/rock_kick.wav',
      rootMidi: 36,
      colorValue: 0xFFE07A3D,
      drumKit: {
        'Kick': 'assets/samples/drums/rock_kick.wav',
        'Snare': 'assets/samples/drums/rock_snare.wav',
        'Hat Closed': 'assets/samples/drums/rock_hat_closed.wav',
        'Hat Open': 'assets/samples/drums/rock_hat_open.wav',
        'Tom': 'assets/samples/drums/rock_tom.wav',
      },
    ),
    SoundPreset(
      id: 'drums_indie',
      name: 'Indie Garage',
      category: TrackCategory.drums,
      description: 'Roomy indie kick/snare with open hats and tom fills.',
      samplePath: 'assets/samples/drums/indie_kick.wav',
      rootMidi: 36,
      colorValue: 0xFFFFB74D,
      drumKit: {
        'Kick': 'assets/samples/drums/indie_kick.wav',
        'Snare': 'assets/samples/drums/indie_snare.wav',
        'Hat Closed': 'assets/samples/drums/indie_hat_closed.wav',
        'Hat Open': 'assets/samples/drums/indie_hat_open.wav',
        'Tom': 'assets/samples/drums/indie_tom.wav',
      },
    ),
    SoundPreset(
      id: 'drums_brush',
      name: 'Soft Brush',
      category: TrackCategory.drums,
      description: 'Soft acoustic/brush feel for indie ballads & jazz-ish grooves.',
      samplePath: 'assets/samples/drums/brush_kick.wav',
      rootMidi: 36,
      colorValue: 0xFF90A4AE,
      drumKit: {
        'Kick': 'assets/samples/drums/brush_kick.wav',
        'Snare': 'assets/samples/drums/brush_snare.wav',
        'Hat Closed': 'assets/samples/drums/brush_hat.wav',
        'Hat Open': 'assets/samples/drums/brush_open.wav',
        'Tom': 'assets/samples/drums/brush_tom.wav',
      },
    ),
    SoundPreset(
      id: 'drums_punk',
      name: 'Punk Punch',
      category: TrackCategory.drums,
      description: 'Tight aggressive kick/snare for punk and power-pop.',
      samplePath: 'assets/samples/drums/punk_kick.wav',
      rootMidi: 36,
      colorValue: 0xFFEF5350,
      drumKit: {
        'Kick': 'assets/samples/drums/punk_kick.wav',
        'Snare': 'assets/samples/drums/punk_snare.wav',
        'Hat Closed': 'assets/samples/drums/punk_hat_closed.wav',
        'Hat Open': 'assets/samples/drums/punk_hat_open.wav',
        'Tom': 'assets/samples/drums/punk_tom.wav',
      },
    ),
    // Bass — roots C1 / C2 / C3
    SoundPreset(
      id: 'bass_clean',
      name: 'Clean Finger Bass',
      category: TrackCategory.bass,
      description: 'Warm fingered electric bass.',
      samplePath: 'assets/samples/bass/bass_clean_c2.wav',
      rootMidi: 36, // C2
      colorValue: 0xFF00D4FF,
      roots: [
        SoundRoot(midi: 24, samplePath: 'assets/samples/bass/bass_clean_c1.wav'),
        SoundRoot(midi: 36, samplePath: 'assets/samples/bass/bass_clean_c2.wav'),
        SoundRoot(midi: 48, samplePath: 'assets/samples/bass/bass_clean_c3.wav'),
      ],
    ),
    SoundPreset(
      id: 'bass_driven',
      name: 'Driven Bass',
      category: TrackCategory.bass,
      description: 'Slightly overdriven bass for rock/indie.',
      samplePath: 'assets/samples/bass/bass_driven_c2.wav',
      rootMidi: 36,
      colorValue: 0xFF00B8D4,
      roots: [
        SoundRoot(midi: 24, samplePath: 'assets/samples/bass/bass_driven_c1.wav'),
        SoundRoot(midi: 36, samplePath: 'assets/samples/bass/bass_driven_c2.wav'),
        SoundRoot(midi: 48, samplePath: 'assets/samples/bass/bass_driven_c3.wav'),
      ],
    ),
    SoundPreset(
      id: 'bass_808',
      name: 'Synth / 808 Bass',
      category: TrackCategory.bass,
      description: 'Deep subby 808-style sine bass.',
      samplePath: 'assets/samples/bass/bass_808_c2.wav',
      rootMidi: 36,
      colorValue: 0xFF0097A7,
      roots: [
        SoundRoot(midi: 24, samplePath: 'assets/samples/bass/bass_808_c1.wav'),
        SoundRoot(midi: 36, samplePath: 'assets/samples/bass/bass_808_c2.wav'),
        SoundRoot(midi: 48, samplePath: 'assets/samples/bass/bass_808_c3.wav'),
      ],
    ),
    // Guitar — roots E1 / E2 / E3
    SoundPreset(
      id: 'gtr_clean',
      name: 'Clean Guitar',
      category: TrackCategory.guitar,
      description: 'Plucked clean electric tone.',
      samplePath: 'assets/samples/guitar/clean_e2.wav',
      rootMidi: 40, // E2
      colorValue: 0xFF9B6BFF,
      roots: [
        SoundRoot(midi: 28, samplePath: 'assets/samples/guitar/clean_e1.wav'),
        SoundRoot(midi: 40, samplePath: 'assets/samples/guitar/clean_e2.wav'),
        SoundRoot(midi: 52, samplePath: 'assets/samples/guitar/clean_e3.wav'),
      ],
    ),
    SoundPreset(
      id: 'gtr_crunch',
      name: 'Crunch Guitar',
      category: TrackCategory.guitar,
      description: 'Medium-gain crunch rhythm tone.',
      samplePath: 'assets/samples/guitar/crunch_e2.wav',
      rootMidi: 40,
      colorValue: 0xFFB388FF,
      roots: [
        SoundRoot(midi: 28, samplePath: 'assets/samples/guitar/crunch_e1.wav'),
        SoundRoot(midi: 40, samplePath: 'assets/samples/guitar/crunch_e2.wav'),
        SoundRoot(midi: 52, samplePath: 'assets/samples/guitar/crunch_e3.wav'),
      ],
    ),
    SoundPreset(
      id: 'gtr_high',
      name: 'High-Gain Guitar',
      category: TrackCategory.guitar,
      description: 'Saturated lead/rhythm high gain.',
      samplePath: 'assets/samples/guitar/highgain_e2.wav',
      rootMidi: 40,
      colorValue: 0xFF7C4DFF,
      roots: [
        SoundRoot(midi: 28, samplePath: 'assets/samples/guitar/highgain_e1.wav'),
        SoundRoot(midi: 40, samplePath: 'assets/samples/guitar/highgain_e2.wav'),
        SoundRoot(midi: 52, samplePath: 'assets/samples/guitar/highgain_e3.wav'),
      ],
    ),
    // Keys — roots C3 / C4 / C5
    SoundPreset(
      id: 'keys_piano',
      name: 'Studio Piano',
      category: TrackCategory.keys,
      description: 'Simple additive piano for melodies & chords.',
      samplePath: 'assets/samples/keys/piano_c4.wav',
      rootMidi: 60, // C4
      colorValue: 0xFF2EE6A6,
      roots: [
        SoundRoot(midi: 48, samplePath: 'assets/samples/keys/piano_c3.wav'),
        SoundRoot(midi: 60, samplePath: 'assets/samples/keys/piano_c4.wav'),
        SoundRoot(midi: 72, samplePath: 'assets/samples/keys/piano_c5.wav'),
      ],
    ),
    SoundPreset(
      id: 'keys_pad',
      name: 'Soft Pad',
      category: TrackCategory.keys,
      description: 'Slow-attack ambient pad.',
      samplePath: 'assets/samples/keys/pad_c4.wav',
      rootMidi: 60,
      colorValue: 0xFF66D9A8,
      roots: [
        SoundRoot(midi: 48, samplePath: 'assets/samples/keys/pad_c3.wav'),
        SoundRoot(midi: 60, samplePath: 'assets/samples/keys/pad_c4.wav'),
        SoundRoot(midi: 72, samplePath: 'assets/samples/keys/pad_c5.wav'),
      ],
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

  /// Drum kits only (for pickers / counts).
  static List<SoundPreset> get drumKits => byCategory(TrackCategory.drums);
}

/// Standard GM-ish drum pad MIDI mapping used in step seq / pads.
class DrumPadMap {
  /// Pitch used in NoteEvent for each pad index.
  static int pitchForPad(int padIndex) => 36 + padIndex;

  static int padIndexForPitch(int pitch) => (pitch - 36).clamp(0, 15);
}
