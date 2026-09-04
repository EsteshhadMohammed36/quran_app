import 'package:flutter/material.dart';

import 'features/quran_reader/presentation/mushaf_reader_screen.dart';
import 'shared/theme/mushaf_theme.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Quran App',
      // Plain Mushaf-paper white + near-black ink (see mushaf_theme.dart) —
      // not the default Material 3 seeded scheme, which tinted the page
      // lavender and didn't match a real printed Mushaf.
      theme: buildMushafTheme(),
      // Spec §25's 4-page prototype is validated (CLAUDE.md "Current
      // phase"); the real reader (Prompt 9: full 604-page navigation +
      // ayah selection, spec §9/§21) is now the app's home.
      home: const MushafReaderScreen(),
    );
  }
}
