import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/local_user.dart';
import '../domain/reading_state.dart';
import '../domain/reading_state_repository.dart';

/// SQLite-backed [ReadingStateRepository]. `reading_state` is keyed on
/// `user_id` alone (schema.dart) — exactly one row per user — so saving is
/// always a full-row replace (`InsertOrReplace`), never an insert-then-
/// update dance.
class SqliteReadingStateRepository implements ReadingStateRepository {
  final AppDatabase _appDatabase;

  SqliteReadingStateRepository({AppDatabase? appDatabase})
      : _appDatabase = appDatabase ?? AppDatabase.instance;

  @override
  Future<ReadingState?> getReadingState() async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'reading_state',
      where: 'user_id = ?',
      whereArgs: [localUserId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ReadingState.fromMap(rows.first);
  }

  @override
  Future<void> saveReadingState({
    required int pageNumber,
    int? surahId,
    int? ayahNumber,
    String? ayahKey,
  }) async {
    final db = await _appDatabase.database;
    await db.insert('reading_state', {
      'user_id': localUserId,
      'page_number': pageNumber,
      'surah_id': surahId,
      'ayah_number': ayahNumber,
      'ayah_key': ayahKey,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
