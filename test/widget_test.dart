import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quran_app/features/quran_reader/presentation/mushaf_prototype_screen.dart';
import 'package:quran_app/main.dart';

void main() {
  testWidgets('MyApp boots into the Mushaf prototype screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    // The page content itself depends on sqflite/path_provider platform
    // channels that aren't available in a plain widget test (no real
    // device) - all 4 pages are preloaded before the PageView appears, so
    // this only confirms the app boots straight into the spec §25
    // prototype screen (no other chrome) without throwing.
    expect(find.byType(MushafPrototypeScreen), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
