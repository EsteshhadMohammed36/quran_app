import '../../../core/database/app_database.dart';
import '../domain/ayah.dart';
import '../domain/mushaf_line.dart';
import '../domain/mushaf_page.dart';
import '../domain/quran_repository.dart';
import '../domain/surah.dart';
import '../domain/word.dart';

/// SQLite-backed [QuranRepository].
///
/// [getPage] implements the renderer pipeline from spec §6.2 exactly:
/// query `mushaf_lines` ordered by line_number, then for each line resolve
/// surah_name -> [Surah] or ayah -> `words` between `first_word_id` and
/// `last_word_id` (inclusive, ordered by word_index).
class SqliteQuranRepository implements QuranRepository {
  final AppDatabase _appDatabase;

  SqliteQuranRepository({AppDatabase? appDatabase})
      : _appDatabase = appDatabase ?? AppDatabase.instance;

  @override
  Future<Surah> getSurah(int surahId) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'surahs',
      where: 'surah_id = ?',
      whereArgs: [surahId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('No surah row for surah_id=$surahId.');
    }
    return Surah.fromMap(rows.first);
  }

  @override
  Future<Ayah> getAyah(String ayahKey) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'ayahs',
      where: 'ayah_key = ?',
      whereArgs: [ayahKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('No ayah row for ayah_key="$ayahKey".');
    }
    return Ayah.fromMap(rows.first);
  }

  @override
  Future<List<Word>> getWords(String ayahKey) async {
    final parts = ayahKey.split(':');
    if (parts.length != 2) {
      throw ArgumentError('Malformed ayah_key: "$ayahKey" (expected surah:ayah).');
    }
    final db = await _appDatabase.database;
    final rows = await db.query(
      'words',
      where: 'surah_id = ? AND ayah_number = ?',
      whereArgs: [int.parse(parts[0]), int.parse(parts[1])],
      orderBy: 'word_position ASC',
    );
    return rows.map(Word.fromMap).toList();
  }

  @override
  Future<List<Word>> getWordsForPage(int pageNumber) async {
    final page = await getPage(pageNumber);
    return [for (final line in page.lines) ...line.words];
  }

  @override
  Future<int> getPageCount() async {
    final db = await _appDatabase.database;
    final rows = await db.rawQuery(
      'SELECT MAX(page_number) AS max_page FROM mushaf_lines',
    );
    final maxPage = rows.first['max_page'] as int?;
    if (maxPage == null) {
      throw StateError('mushaf_lines is empty; cannot determine page count.');
    }
    return maxPage;
  }

  @override
  Future<MushafPage> getPage(int pageNumber) async {
    final db = await _appDatabase.database;

    final lineRows = await db.query(
      'mushaf_lines',
      where: 'page_number = ?',
      whereArgs: [pageNumber],
      orderBy: 'line_number ASC',
    );
    if (lineRows.isEmpty) {
      throw StateError('No mushaf_lines rows for page_number=$pageNumber.');
    }

    // basmallah lines carry no first_word_id/last_word_id (no per-page word
    // data), and no page font has a working composed Bismillah glyph
    // (checked directly - see qpc_v2_fonts.dart). Surah 1 ayah 1 *is* the
    // Bismillah, so every basmallah line reuses those same real words,
    // fetched once per page if needed.
    //
    // A line_type=='basmallah' row only ever occurs for surahs *other than*
    // Al-Fatiha — Al-Fatiha's own Bismillah is stored as an ordinary
    // line_type=='ayah' row instead (page 1, line 2, first_word_id/
    // last_word_id 1-5), since it genuinely is that surah's ayah 1 and goes
    // through the normal per-page word path. That means the last of the 5
    // reused words here (word_position 5, e.g. word_key '1:1:5') — the
    // ayah-end number glyph — is only ever correct for Al-Fatiha's ayah 1
    // and must never be shown on a basmallah line, since the Bismillah
    // opening every other surah isn't itself a numbered ayah (user's
    // request, 2026-08-31 pt.3: no ayah-number marker on the basmallah
    // except in Al-Fatiha — which this trim doesn't even touch, since that
    // one never goes through this basmallah path at all).
    List<Word>? basmallahWords;
    if (lineRows.any((row) => row['line_type'] == 'basmallah')) {
      final allFatihaAyah1Words = await getWords('1:1');
      basmallahWords = allFatihaAyah1Words.sublist(
        0,
        allFatihaAyah1Words.length - 1,
      );
    }

    final Set<int> neededSurahNumbers = {
      for (final row in lineRows)
        if (row['line_type'] == 'surah_name') row['surah_number'] as int,
    };
    final Map<int, Surah> surahsByNumber = {};
    if (neededSurahNumbers.isNotEmpty) {
      final placeholders = List.filled(neededSurahNumbers.length, '?').join(', ');
      final surahRows = await db.query(
        'surahs',
        where: 'surah_id IN ($placeholders)',
        whereArgs: neededSurahNumbers.toList(),
      );
      for (final row in surahRows) {
        final surah = Surah.fromMap(row);
        surahsByNumber[surah.surahId] = surah;
      }
    }

    final List<MushafLine> lines = [];
    for (final row in lineRows) {
      final lineType = MushafLineType.fromValue(row['line_type'] as String);
      final isCentered = (row['is_centered'] as int) != 0;

      switch (lineType) {
        case MushafLineType.ayah:
          final int firstWordId = row['first_word_id'] as int;
          final int lastWordId = row['last_word_id'] as int;
          final wordRows = await db.query(
            'words',
            where: 'word_index BETWEEN ? AND ?',
            whereArgs: [firstWordId, lastWordId],
            orderBy: 'word_index ASC',
          );
          lines.add(
            MushafLine(
              pageNumber: pageNumber,
              lineNumber: row['line_number'] as int,
              lineType: lineType,
              isCentered: isCentered,
              words: wordRows.map(Word.fromMap).toList(),
            ),
          );
        case MushafLineType.surahName:
          final int surahNumber = row['surah_number'] as int;
          final surah = surahsByNumber[surahNumber];
          if (surah == null) {
            throw StateError(
              'surah_name line on page $pageNumber references '
              'surah_number=$surahNumber with no matching surahs row.',
            );
          }
          lines.add(
            MushafLine(
              pageNumber: pageNumber,
              lineNumber: row['line_number'] as int,
              lineType: lineType,
              isCentered: isCentered,
              surah: surah,
            ),
          );
        case MushafLineType.basmallah:
          lines.add(
            MushafLine(
              pageNumber: pageNumber,
              lineNumber: row['line_number'] as int,
              lineType: lineType,
              isCentered: isCentered,
              words: basmallahWords!,
            ),
          );
      }
    }

    return MushafPage(pageNumber: pageNumber, lines: lines);
  }
}
