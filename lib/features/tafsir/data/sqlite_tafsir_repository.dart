import '../../../core/database/app_database.dart';
import '../domain/tafsir_entry.dart';
import '../domain/tafsir_group.dart';
import '../domain/tafsir_repository.dart';
import '../domain/tafsir_source.dart';

/// SQLite-backed [TafsirRepository].
///
/// `tafsir_entries` (schema.dart) stores the real text only on a group's
/// owning row (`ayah_key == group_id`) — every other member row has
/// `content` left NULL. [getEntry] resolves this with a self-join so
/// callers never see the raw NULL-on-members storage shape (spec §11:
/// "Do not assume every surah:ayah has an independent text blob").
class SqliteTafsirRepository implements TafsirRepository {
  final AppDatabase _appDatabase;

  SqliteTafsirRepository({AppDatabase? appDatabase})
      : _appDatabase = appDatabase ?? AppDatabase.instance;

  @override
  Future<List<TafsirSource>> getSources() async {
    final db = await _appDatabase.database;
    final rows = await db.query('tafsir_sources');
    return rows.map(TafsirSource.fromMap).toList();
  }

  @override
  Future<TafsirEntry> getEntry(String sourceId, String ayahKey) async {
    final db = await _appDatabase.database;
    // Self-join: `te` is this ayah's own row (for group_id/start/end),
    // `owner` is the row that actually holds the text (itself, when `te`
    // is already the owner).
    final rows = await db.rawQuery(
      '''
      SELECT te.ayah_key AS ayah_key, te.group_id AS group_id,
             te.group_ayah_start AS group_ayah_start,
             te.group_ayah_end AS group_ayah_end,
             owner.content AS content
      FROM tafsir_entries te
      JOIN tafsir_entries owner
        ON owner.source_id = te.source_id AND owner.ayah_key = te.group_id
      WHERE te.source_id = ? AND te.ayah_key = ?
      LIMIT 1;
      ''',
      [sourceId, ayahKey],
    );
    if (rows.isEmpty) {
      throw StateError(
        'No tafsir_entries row for source_id="$sourceId", ayah_key="$ayahKey".',
      );
    }
    return TafsirEntry.fromMap({'source_id': sourceId, ...rows.first});
  }

  @override
  Future<TafsirGroup> getGroup(String sourceId, String ayahKey) async {
    final entry = await getEntry(sourceId, ayahKey);
    final db = await _appDatabase.database;
    final memberRows = await db.query(
      'tafsir_entries',
      columns: ['ayah_key'],
      where: 'source_id = ? AND group_id = ?',
      whereArgs: [sourceId, entry.groupId],
      orderBy: 'surah_id ASC, ayah_number ASC',
    );
    return TafsirGroup(
      sourceId: sourceId,
      groupId: entry.groupId,
      groupAyahStart: entry.groupAyahStart,
      groupAyahEnd: entry.groupAyahEnd,
      content: entry.content,
      memberAyahKeys: [
        for (final row in memberRows) row['ayah_key'] as String,
      ],
    );
  }

  @override
  Future<List<TafsirEntry>> search(String sourceId, String query) async {
    if (query.trim().isEmpty) return [];
    final db = await _appDatabase.database;
    // Content only lives on group-owning rows (member rows are NULL), so a
    // plain LIKE over `content` naturally searches each group's text once
    // regardless of how many ayahs it spans — no self-join needed here,
    // unlike [getEntry]/[getGroup].
    final rows = await db.query(
      'tafsir_entries',
      where: 'source_id = ? AND content IS NOT NULL AND content LIKE ?',
      whereArgs: [sourceId, '%$query%'],
      orderBy: 'surah_id ASC, ayah_number ASC',
    );
    return rows
        .map(
          (row) => TafsirEntry.fromMap({
            'source_id': row['source_id'],
            'ayah_key': row['ayah_key'],
            'group_id': row['group_id'],
            'group_ayah_start': row['group_ayah_start'],
            'group_ayah_end': row['group_ayah_end'],
            'content': row['content'],
          }),
        )
        .toList();
  }
}
