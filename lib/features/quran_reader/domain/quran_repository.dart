import 'ayah.dart';
import 'mushaf_page.dart';
import 'surah.dart';
import 'word.dart';

/// Domain interface for Quran reading data (spec §18).
///
/// UI widgets depend on this, never on raw SQLite rows directly (spec §17).
abstract class QuranRepository {
  Future<Surah> getSurah(int surahId);

  Future<Ayah> getAyah(String ayahKey);

  Future<MushafPage> getPage(int pageNumber);

  Future<List<Word>> getWords(String ayahKey);

  Future<List<Word>> getWordsForPage(int pageNumber);

  /// Total number of Mushaf pages in the installed layout (spec §21: the
  /// real reader must know this to page/lazy-load across the whole Mushaf
  /// without assuming a hardcoded page count).
  Future<int> getPageCount();

  /// Which Mushaf page each of [wordIndexes] is drawn on — needed to pick
  /// the right per-page QCF font for a word outside the normal page
  /// renderer (spec §7), e.g. the Ayah Context Sheet's own ayah text.
  /// `words.page_number` itself isn't populated (spec §23 ingestion gap),
  /// so this resolves it the same authoritative way [getPage] does: via
  /// `mushaf_lines`' own `first_word_id`/`last_word_id` ranges. A single
  /// ayah's words can resolve to *two different* pages for a page-boundary
  /// ayah (spec §26 "Page boundary") — never assumed to be one page.
  Future<Map<int, int>> getPageNumbersForWordIndexes(List<int> wordIndexes);
}
