import 'package:flutter_test/flutter_test.dart';
import 'package:layerstudio/models/track.dart';
import 'package:layerstudio/theme/studio_theme.dart';

void main() {
  test('signature category colors are distinct roles', () {
    expect(StudioColors.forCategory(TrackCategory.drums), StudioColors.drumsCopper);
    expect(StudioColors.forCategory(TrackCategory.bass), StudioColors.bassCyan);
    expect(StudioColors.forCategory(TrackCategory.guitar), StudioColors.guitarViolet);
    expect(StudioColors.forCategory(TrackCategory.keys), StudioColors.keysGreen);
    expect(StudioColors.forCategory(TrackCategory.mic), StudioColors.micGreen);

    final colors = {
      StudioColors.drumsCopper,
      StudioColors.bassCyan,
      StudioColors.guitarViolet,
      StudioColors.keysGreen,
      StudioColors.micGreen,
    };
    expect(colors.length, 5);
  });
}
