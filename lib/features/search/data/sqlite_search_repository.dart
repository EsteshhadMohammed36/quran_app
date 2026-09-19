import '../../../core/database/app_database.dart';
import '../../tafsir/presentation/tafsir_html_text.dart';
import '../domain/search_repository.dart';
import '../domain/search_result.dart';

/// SQLite-backed [SearchRepository]. `searchTafsir` is a plain `LIKE`
/// substring match (MVP scope, same as `TafsirRepository.search`).
/// `searchAyahText` matches with tashkeel/tatweel/alef-variants folded on
/// *both* sides of the comparison — this does not violate rule #1
/// ("never transform Quran source text"): [_normalizeForMatch] is only
/// ever applied to a transient in-memory copy used to decide
/// match/no-match. `ayahs.text_uthmani` in the database, and the
/// `snippet` returned in [SearchResult], are always the untouched
/// canonical string — nothing stored or displayed is ever normalized.
/// Without this, a query typed on a real keyboard (plain letters, no
/// diacritics, plain alef) never matched the fully-diacritized canonical
/// text — real Uthmani orthography always spells the "ال" definite
/// article and several other letters with special alef variants (e.g.
/// "الرحمن" is actually stored as alef-wasla + full tashkeel + a
/// tatweel filler character), none of which a keyboard produces.
/// `searchTafsir` didn't have this problem since tafsir prose isn't
/// written in strict Uthmani orthography.
class SqliteSearchRepository implements SearchRepository {
  final AppDatabase _appDatabase;

  SqliteSearchRepository({AppDatabase? appDatabase})
    : _appDatabase = appDatabase ?? AppDatabase.instance;

  /// Arabic combining diacritic marks (tashkeel + Quranic annotation
  /// signs) plus the tatweel filler character, by codepoint so nothing
  /// here depends on how Arabic glyphs happen to render in an editor:
  /// U+0610-061A (Quranic annotation signs), U+064B-065F (standard
  /// tashkeel: fathatan, dammatan, kasratan, fatha, damma, kasra,
  /// shadda, sukun, etc.), U+0670 (superscript alef), U+06D6-06ED
  /// (Quranic small high signs), U+08D4-08FF (Arabic Extended-A Quranic
  /// marks), U+0640 (tatweel — a zero-sound elongation/connector
  /// character Uthmani orthography uses as a base for some superscript
  /// marks; never typed on a keyboard). None of the diacritic ranges
  /// overlap a base-letter codepoint, so stripping them can't merge two
  /// distinct letters into one.
  static final RegExp _tashkeelAndTatweelPattern = RegExp(
    '[ؐ-ًؚ-ٰٟۖ-ۭࣔ-ࣿـ]',
  );

  /// Alef variants (madda U+0622, hamza-above U+0623, hamza-below
  /// U+0625, wasla U+0671) that Uthmani orthography requires in
  /// specific positions (e.g. the "ال" definite article is always
  /// spelled with alef *wasla*, not plain alef) but that a real
  /// keyboard always produces as plain alef (U+0627) — folded for
  /// comparison only, same transient-copy-only rule as
  /// [_tashkeelAndTatweelPattern].
  static final RegExp _alefVariantsPattern = RegExp(
    '[آأإٱ]',
  );

  static String _normalizeForMatch(String text) => text
      .replaceAll(_tashkeelAndTatweelPattern, '')
      .replaceAll(_alefVariantsPattern, 'ا');

  @override
  Future<List<SearchResult>> searchAyahText(String query) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final String needle = _normalizeForMatch(trimmed);
    final db = await _appDatabase.database;
    final rows = await db.query(
      'ayahs',
      orderBy: 'surah_id ASC, ayah_number ASC',
    );
    return [
      for (final row in rows)
        if (_normalizeForMatch(
          row['text_uthmani'] as String,
        ).contains(needle))
          SearchResult(
            kind: SearchResultKind.ayahText,
            ayahKey: row['ayah_key'] as String,
            surahId: row['surah_id'] as int,
            ayahNumber: row['ayah_number'] as int,
            // The full ayah, not a truncated snippet — ayahs are short
            // enough (even the longest, 2:282, is a normal paragraph) that
            // truncating would hide the very match the user searched for.
            // Always the untouched canonical text, never the normalized
            // comparison copy.
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
