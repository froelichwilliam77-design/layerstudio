import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:layerstudio/utils/wav_codec.dart';

void main() {
  test('overlayStereo overdub sums at offset', () {
    final base = StereoPcm(Float64List.fromList([1, 0, 0]), Float64List.fromList([1, 0, 0]));
    final take = StereoPcm(Float64List.fromList([0.5]), Float64List.fromList([0.25]));
    final mixed = overlayStereo(base, take, offsetFrames: 1);
    expect(mixed.frames, 3);
    expect(mixed.left[0], 1);
    expect(mixed.left[1], 0.5);
    expect(mixed.right[1], 0.25);
  });

  test('overlayStereo replace punches in over the take length', () {
    final base = StereoPcm(
      Float64List.fromList([1, 1, 1]),
      Float64List.fromList([1, 1, 1]),
    );
    final take = StereoPcm(
      Float64List.fromList([0.2, 0.3]),
      Float64List.fromList([0.2, 0.3]),
    );
    final mixed = overlayStereo(base, take, offsetFrames: 0, replace: true);
    expect(mixed.left[0], 0.2);
    expect(mixed.left[1], 0.3);
    expect(mixed.left[2], 1);
  });
}
