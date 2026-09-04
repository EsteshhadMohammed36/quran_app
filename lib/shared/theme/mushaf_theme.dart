import 'package:flutter/material.dart';

/// Colors matched against the real printed Madinah Mushaf (screenshots on
/// the Pixel 6 API 34 emulator, page 1/300/601/604), not guessed: a plain
/// warm-white page — not the pale lavender tint Material 3 derives from a
/// `ColorScheme.fromSeed` seed color — with near-black ink. This is pure
/// app chrome (page background + ink color), not Quran content, so it
/// carries no resource_manifest entry (CLAUDE.md rule #4 only applies to
/// imported *data*).
const Color mushafPageColor = Color(0xFFFFFEF8);
const Color mushafInkColor = Color(0xFF1A1005);

ThemeData buildMushafTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: mushafPageColor,
    colorScheme: const ColorScheme.light(
      surface: mushafPageColor,
      onSurface: mushafInkColor,
      primary: mushafInkColor,
      onPrimary: mushafPageColor,
      surfaceContainerHighest: mushafPageColor,
    ),
  );
}
