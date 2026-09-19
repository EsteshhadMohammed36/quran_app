import 'package:flutter_test/flutter_test.dart';

import 'package:quran_app/features/quran_reader/domain/ayah.dart';
import 'package:quran_app/features/quran_reader/domain/mushaf_page.dart';
import 'package:quran_app/features/quran_reader/domain/quran_repository.dart';
import 'package:quran_app/features/quran_reader/domain/surah.dart';
import 'package:quran_app/features/quran_reader/domain/word.dart';
import 'package:quran_app/features/quran_reader/presentation/quran_reader_provider.dart';

/// [QuranReaderProvider]'s constructor always prefetches its neighbor
/// pages (see its own doc comment) — [getPage] must not throw or every
/// test here would fail on an unrelated, unawaited background fetch.

/// spec §26 "Selection" / "Selection switch" acceptance tests. Unlike the
/// data-resolution rows covered by tool/run_acceptance_tests.dart, these
/// two rows are pure app-state claims ("tapping any word selects the
/// parent ayah", "tapping another ayah changes selection without
/// corrupting state") with no SQL truth to check — [QuranReaderProvider]
/// is the whole implementation, so it's exercised directly here.
class _UnusedRepository implements QuranRepository {
  @override
  Future<Surah> getSurah(int surahId) => throw UnimplementedError();
  @override
  Future<List<Surah>> getAllSurahs() => throw UnimplementedError();
  @override
  Future<Map<int, int>> getFirstPageNumbersForSurahs() =>
      throw UnimplementedError();
  @override
  Future<Ayah> getAyah(String ayahKey) => throw UnimplementedError();
  @override
  Future<MushafPage> getPage(int pageNumber) async =>
      MushafPage(pageNumber: pageNumber, lines: const []);
  @override
  Future<List<Word>> getWords(String ayahKey) => throw UnimplementedError();
  @override
  Future<List<Word>> getWordsForPage(int pageNumber) =>
      throw UnimplementedError();
  @override
  Future<int> getPageCount() async => 604;
  @override
  Future<Map<int, int>> getPageNumbersForWordIndexes(
    List<int> wordIndexes,
  ) => throw UnimplementedError();
}

Word _word(int surah, int ayah, int position, int wordIndex) => Word(
  surahId: surah,
  ayahNumber: ayah,
  wordPosition: position,
  wordKey: '$surah:$ayah:$position',
  wordIndex: wordIndex,
  text: 'GLYPH',
);

void main() {
  late QuranReaderProvider provider;

  setUp(() {
    provider = QuranReaderProvider(
      repository: _UnusedRepository(),
      totalPages: 604,
    );
  });

  test('Selection: tapping any word selects the whole parent ayah', () {
    // Tap the *third* word of ayah 2:255 (Ayat al-Kursi), not the first —
    // proves resolution goes through Word.ayahKey (surah:ayah), not
    // "whichever word happened to be first".
    provider.selectWord(_word(2, 255, 3, 500));

    expect(provider.selectedAyahKey, '2:255');
    expect(provider.isAyahSheetOpen, isTrue);
  });

  test(
    'Selection: tapping a different word in the SAME ayah keeps it selected',
    () {
      provider.selectWord(_word(2, 255, 1, 498));
      provider.selectWord(_word(2, 255, 7, 504));

      expect(provider.selectedAyahKey, '2:255');
      expect(provider.isAyahSheetOpen, isTrue);
    },
  );

  test(
    'Selection switch: tapping another ayah changes selection without '
    'corrupting other state',
    () {
      provider.selectWord(_word(2, 255, 1, 498));
      provider.setActiveStudyTab(StudyTab.morphology);

      provider.selectWord(_word(18, 10, 1, 9000));

      expect(provider.selectedAyahKey, '18:10');
      expect(provider.isAyahSheetOpen, isTrue);
      // spec §9.1 "Selected ayah changes in place; sheet remains open when
      // practical" — the active study tab is unrelated ambient state, not
      // reset by a plain ayah switch.
      expect(provider.activeStudyTab, StudyTab.morphology);
    },
  );

  test(
    'Selection switch: repeated taps across many ayahs never leave a '
    'stale selection',
    () {
      final targets = [
        _word(1, 1, 1, 1),
        _word(2, 1, 1, 10),
        _word(2, 255, 1, 498),
        _word(114, 6, 1, 77700),
      ];
      for (final w in targets) {
        provider.selectWord(w);
        expect(provider.selectedAyahKey, w.ayahKey);
      }
      expect(provider.selectedAyahKey, '114:6');
    },
  );

  test('Outside tap clears selection entirely (spec §9.1 "Idle")', () {
    provider.selectWord(_word(2, 255, 1, 498));
    provider.clearSelection();

    expect(provider.selectedAyahKey, isNull);
    expect(provider.isAyahSheetOpen, isFalse);
  });
}
