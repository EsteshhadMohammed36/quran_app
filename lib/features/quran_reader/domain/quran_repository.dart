import 'ayah.dart';
import 'mushaf_page.dart';
import 'surah.dart';
import 'word.dart';

/// Domain interface for Quran reading data (spec §18).
///
/// UI widgets depend on this, never on raw SQLite rows directly (spec §17).
abstract class QuranRepository {
  Future<Surah> getSurah(int surahId);

  /// Every surah (spec §15's `surahs` table), ordered by `surah_id` — the
  /// Surah Index screen's list (spec §3: "Surah, Juz, Hizb and page
  /// navigation").
  Future<List<Surah>> getAllSurahs();

  /// The first Mushaf page each surah opens on, keyed by `surah_id` —
  /// resolved from `mushaf_lines.line_type == 'surah_name'` (every surah has
  /// exactly one such line, spec §6), so the Surah Index screen can jump
  /// straight there. Not derived from `ayahs.page_number`/
  /// `getPageNumbersForWordIndexes`, since a surah's *banner* line is the
  /// actual first thing on its opening page, not its first ayah's word.
  Future<Map<int, int>> getFirstPageNumbersForSurahs();

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
