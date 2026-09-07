import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/track.dart';

class StudioColors {
  static const bg = Color(0xFF0E0F12);
  static const surface = Color(0xFF171A21);
  static const surface2 = Color(0xFF1E2330);
  static const border = Color(0xFF2A3142);
  static const accent = Color(0xFF5B8CFF);
  static const accent2 = Color(0xFF00D1A0);
  static const danger = Color(0xFFFF5C7A);
  static const warning = Color(0xFFFFB020);
  static const text = Color(0xFFE8ECF5);
  static const textDim = Color(0xFF9AA3B5);
  static const play = Color(0xFF3DDC97);
  static const record = Color(0xFFFF4D6D);

  /// Signature track hues (visual-guide Foundation).
  static const drumsCopper = Color(0xFFE07A3D);
  static const drumsAmber = Color(0xFFFFB020);
  static const bassCyan = Color(0xFF00D4FF);
  static const guitarViolet = Color(0xFF9B6BFF);
  static const keysGreen = Color(0xFF2EE6A6);
  static const micGreen = Color(0xFF66BB6A);

  static Color forCategory(TrackCategory cat) => switch (cat) {
    TrackCategory.drums => drumsCopper,
    TrackCategory.bass => bassCyan,
    TrackCategory.guitar => guitarViolet,
    TrackCategory.keys => keysGreen,
    TrackCategory.mic => micGreen,
  };

  static Color forTrack(Track track) => Color(track.colorValue);

  /// Luminous fill for active sequencer / mode chrome.
  static Color luminous(Color base, {double alpha = 0.95}) =>
      Color.alphaBlend(base.withValues(alpha: alpha), surface2);
}

ThemeData buildStudioTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: const ColorScheme.dark(
      primary: StudioColors.accent,
      secondary: StudioColors.accent2,
      surface: StudioColors.surface,
      error: StudioColors.danger,
    ),
    scaffoldBackgroundColor: StudioColors.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: StudioColors.surface,
      foregroundColor: StudioColors.text,
      elevation: 0,
      centerTitle: false,
      toolbarHeight: 48,
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: StudioColors.surface,
      indicatorColor: Color(0x405B8CFF),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    ),
    cardTheme: CardThemeData(
      color: StudioColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: StudioColors.border),
      ),
    ),
    dividerColor: StudioColors.border,
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: StudioColors.surface2,
      contentTextStyle: TextStyle(color: StudioColors.text),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: StudioColors.accent,
      foregroundColor: Colors.white,
    ),
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: StudioColors.text,
      displayColor: StudioColors.text,
    ),
  );
}
