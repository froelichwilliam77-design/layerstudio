import 'package:flutter_test/flutter_test.dart';
import 'package:layerstudio/models/fx_settings.dart';
import 'package:layerstudio/utils/offline_fx.dart';

void main() {
  test('cubicAt interpolates between samples', () {
    final src = [0.0, 1.0, 0.0, -1.0];
    expect(OfflineFx.cubicAt(src, 0), 0.0);
    expect(OfflineFx.cubicAt(src, 1), 1.0);
    final mid = OfflineFx.cubicAt(src, 0.5);
    expect(mid, greaterThan(0.3));
    expect(mid, lessThan(0.8));
  });

  test('applyVoiceChain leaves dry signal when FX are off', () {
    final left = [0.2, -0.1, 0.05];
    final right = [0.2, -0.1, 0.05];
    OfflineFx.applyVoiceChain(
      left,
      right,
      fx: FxSettings(
        ampPreset: AmpPreset.none,
        reverb: 0,
        delay: 0,
        gain: 0,
        tone: 1,
        cabSim: false,
      ),
    );
    expect(left[0], closeTo(0.2, 0.0001));
    expect(right[0], closeTo(0.2, 0.0001));
  });

  test('delay wet adds energy after the tap', () {
    final left = List<double>.filled(25000, 0);
    final right = List<double>.filled(25000, 0);
    left[0] = 1;
    right[0] = 1;
    OfflineFx.applyVoiceChain(
      left,
      right,
      fx: FxSettings(
        ampPreset: AmpPreset.none,
        reverb: 0,
        delay: 0.8,
        gain: 0,
        tone: 1,
        cabSim: false,
      ),
    );
    var energy = 0.0;
    for (var i = 100; i < left.length; i++) {
      energy += left[i].abs();
    }
    expect(energy, greaterThan(0.01));
  });
}
