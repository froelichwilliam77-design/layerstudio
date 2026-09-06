import 'dart:math' as math;

class MusicTheory {
  static const pitchNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
  ];

  static const majorIntervals = [0, 2, 4, 5, 7, 9, 11];
  static const minorIntervals = [0, 2, 3, 5, 7, 8, 10];

  /// Soft clamp window for rate-based pitching (±12). Beyond this, UI warns.
  static const int softPitchRangeSemis = 12;

  /// Hard clamp for playback rate (±24) to avoid extreme SoLoud artifacts.
  static const int hardPitchRangeSemis = 24;

  static String noteName(int midi) {
    final name = pitchNames[midi % 12];
    final octave = (midi ~/ 12) - 1;
    return '$name$octave';
  }

  static int keyRootMidi(String key, {int octave = 4}) {
    final i = pitchNames.indexOf(key);
    final idx = i >= 0 ? i : 0;
    return (octave + 1) * 12 + idx;
  }

  static Set<int> scalePitchClasses(String key, String scale) {
    final root = pitchNames.indexOf(key);
    final r = root >= 0 ? root : 0;
    final intervals = scale == 'minor' ? minorIntervals : majorIntervals;
    return intervals.map((i) => (r + i) % 12).toSet();
  }

  static bool inScale(int midi, String key, String scale) =>
      scalePitchClasses(key, scale).contains(midi % 12);

  static int snapToScale(int midi, String key, String scale) {
    if (inScale(midi, key, scale)) return midi;
    for (var d = 1; d <= 6; d++) {
      if (inScale(midi + d, key, scale)) return midi + d;
      if (inScale(midi - d, key, scale)) return midi - d;
    }
    return midi;
  }

  static List<int> triad(int rootMidi, {bool minor = false}) {
    return [
      rootMidi,
      rootMidi + (minor ? 3 : 4),
      rootMidi + 7,
    ];
  }

  /// Build a chord voicing for expressive strum / songwriting.
  ///
  /// - [sus4] replaces the third with a perfect fourth.
  /// - [seventh] adds a dominant 7th (+10) for major, minor 7th (+10) for minor.
  /// - [inversion] rotates the voicing upward (0 = root position).
  static List<int> chordVoicing(
    int rootMidi, {
    bool minor = false,
    bool seventh = false,
    bool sus4 = false,
    int inversion = 0,
  }) {
    final thirdOrSus = sus4 ? 5 : (minor ? 3 : 4);
    final notes = <int>[
      rootMidi,
      rootMidi + thirdOrSus,
      rootMidi + 7,
    ];
    if (seventh) {
      notes.add(rootMidi + 10);
    }
    var inv = inversion;
    if (inv < 0) inv = 0;
    final maxInv = notes.length - 1;
    if (inv > maxInv) inv = maxInv;
    for (var i = 0; i < inv; i++) {
      final n = notes.removeAt(0);
      notes.add(n + 12);
    }
    return notes;
  }

  /// Short chord-quality suffix for labels (e.g. `m7`, `sus4`, `7`).
  static String chordSuffix({
    bool minor = false,
    bool seventh = false,
    bool sus4 = false,
  }) {
    if (sus4 && seventh) return minor ? 'm7sus4' : '7sus4';
    if (sus4) return 'sus4';
    if (minor && seventh) return 'm7';
    if (minor) return 'm';
    if (seventh) return '7';
    return '';
  }

  static double pitchRatio(int fromMidi, int toMidi) =>
      math.pow(2, (toMidi - fromMidi) / 12.0).toDouble();

  /// Clamp [midi] to [rootMidi] ± [hardPitchRangeSemis].
  static int clampPitch(int midi, int rootMidi) {
    final lo = rootMidi - hardPitchRangeSemis;
    final hi = rootMidi + hardPitchRangeSemis;
    return midi.clamp(lo, hi);
  }

  static bool exceedsSoftRange(int midi, int rootMidi) {
    final d = (midi - rootMidi).abs();
    return d > softPitchRangeSemis;
  }

  static bool wasHardClamped(int requested, int rootMidi) {
    return clampPitch(requested, rootMidi) != requested;
  }
}
