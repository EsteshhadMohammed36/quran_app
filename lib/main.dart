import 'package:flutter/material.dart';

import 'features/quran_reader/presentation/mushaf_prototype_screen.dart';
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
      // Spec §25: home is the Mushaf renderer prototype until it's
      // validated on all 4 required pages. Nothing else is built on top of
      // the renderer before that (CLAUDE.md rule #5).
      home: const MushafPrototypeScreen(),
    );
  }
}
