import 'dart:math' as math;

class MusicTheory {
  static const pitchNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
  ];

  static const majorIntervals = [0, 2, 4, 5, 7, 9, 11];
  static const minorIntervals = [0, 2, 3, 5, 7, 8, 10];

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

  static double pitchRatio(int fromMidi, int toMidi) =>
      math.pow(2, (toMidi - fromMidi) / 12.0).toDouble();
}
