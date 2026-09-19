import '../../../core/database/app_database.dart';
import '../../tafsir/presentation/tafsir_html_text.dart';
import '../domain/search_repository.dart';
import '../domain/search_result.dart';

/// SQLite-backed [SearchRepository]. Both queries are plain `LIKE`
/// substring matches (MVP scope, same as `TafsirRepository.search`) —
/// no normalization/diacritic-folding of the query or the stored text,
/// so a search only matches text written the same way (deliberate: rule
/// #1 forbids any transformation of canonical Quran text, and doing it
/// only for the search index while leaving display untouched would be an
/// inconsistent, confusing halfway measure).
class SqliteSearchRepository implements SearchRepository {
  final AppDatabase _appDatabase;

  SqliteSearchRepository({AppDatabase? appDatabase})
    : _appDatabase = appDatabase ?? AppDatabase.instance;

  @override
  Future<List<SearchResult>> searchAyahText(String query) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final db = await _appDatabase.database;
    final rows = await db.query(
      'ayahs',
      where: 'text_uthmani LIKE ?',
      whereArgs: ['%$trimmed%'],
      orderBy: 'surah_id ASC, ayah_number ASC',
    );
    return [
      for (final row in rows)
        SearchResult(
          kind: SearchResultKind.ayahText,
          ayahKey: row['ayah_key'] as String,
          surahId: row['surah_id'] as int,
          ayahNumber: row['ayah_number'] as int,
          // The full ayah, not a truncated snippet — ayahs are short
          // enough (even the longest, 2:282, is a normal paragraph) that
          // truncating would hide the very match the user searched for.
          snippet: row['text_uthmani'] as String,
        ),
    ];
  }

  @override
  Future<List<SearchResult>> searchTafsir(String query) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final db = await _appDatabase.database;
    // Spans every source (unlike TafsirRepository.search's single-source
    // scope) — a general search has no one source in context, and the
    // result tile's tafsirSourceName tells them apart.
    final rows = await db.rawQuery(
      '''
      SELECT te.ayah_key, te.surah_id, te.ayah_number, te.content,
             ts.name AS source_name
      FROM tafsir_entries te
      JOIN tafsir_sources ts ON ts.source_id = te.source_id
      WHERE te.content IS NOT NULL AND te.content LIKE ?
      ORDER BY te.surah_id ASC, te.ayah_number ASC;
      ''',
      ['%$trimmed%'],
    );
    return [
      for (final row in rows)
        SearchResult(
          kind: SearchResultKind.tafsir,
          ayahKey: row['ayah_key'] as String,
          surahId: row['surah_id'] as int,
          ayahNumber: row['ayah_number'] as int,
          snippet: _snippetAround(
            stripTafsirHtml(row['content'] as String),
            trimmed,
          ),
          tafsirSourceName: row['source_name'] as String,
        ),
    ];
  }

  /// Tafsir passages can run to several paragraphs — showing all of it in
  /// a results list would bury the match. Extracts a short window of
  /// plain text around the first occurrence of [query] instead, matching
  /// the same plain-substring-match assumption the `LIKE` query itself
  /// makes (an HTML tag landing inside the window is the one known MVP
  /// limitation, same territory `TafsirRepository.search`'s own doc
  /// comment already accepts).
  static String _snippetAround(String text, String query, {int context = 60}) {
    final int idx = text.indexOf(query);
    if (idx == -1) {
      return text.length <= 160 ? text : '${text.substring(0, 160)}...';
    }
    final int start = (idx - context).clamp(0, text.length);
    final int end = (idx + query.length + context).clamp(0, text.length);
    final String prefix = start > 0 ? '...' : '';
    final String suffix = end < text.length ? '...' : '';
    return '$prefix${text.substring(start, end)}$suffix';
  }
}
