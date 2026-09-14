import '../../../core/database/app_database.dart';
import '../domain/morphology_entry.dart';
import '../domain/morphology_repository.dart';

/// SQLite-backed [MorphologyRepository]. `morphology` (schema.dart) already
/// has exactly one row per `words` row, so this is a plain keyed lookup —
/// no group/self-join indirection like the Tafsir module needs.
class SqliteMorphologyRepository implements MorphologyRepository {
  final AppDatabase _appDatabase;

  SqliteMorphologyRepository({AppDatabase? appDatabase})
      : _appDatabase = appDatabase ?? AppDatabase.instance;

  @override
  Future<List<MorphologyEntry>> getEntriesForAyah(String ayahKey) async {
    final parts = ayahKey.split(':');
    final surahId = int.parse(parts[0]);
    final ayahNumber = int.parse(parts[1]);

    final db = await _appDatabase.database;
    final rows = await db.query(
      'morphology',
      where: 'surah_id = ? AND ayah_number = ?',
      whereArgs: [surahId, ayahNumber],
      orderBy: 'word_position ASC',
    );
    return rows.map(MorphologyEntry.fromMap).toList();
  }
}
