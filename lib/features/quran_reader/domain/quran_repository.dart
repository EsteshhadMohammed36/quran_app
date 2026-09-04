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
}
