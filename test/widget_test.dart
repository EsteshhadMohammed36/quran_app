import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quran_app/features/quran_reader/presentation/mushaf_reader_screen.dart';
import 'package:quran_app/main.dart';

void main() {
  testWidgets('MyApp boots into the Mushaf reader screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    // The page content itself depends on sqflite/path_provider platform
    // channels that aren't available in a plain widget test (no real
    // device) - getPageCount() (used to size the 604-page PageView) never
    // resolves here, so this only confirms the app boots straight into the
    // real reader (Prompt 9) without throwing, showing its loading state.
    expect(find.byType(MushafReaderScreen), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
