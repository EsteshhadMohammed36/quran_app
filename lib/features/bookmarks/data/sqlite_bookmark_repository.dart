import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/local_user.dart';
import '../domain/bookmark.dart';
import '../domain/bookmark_repository.dart';

/// SQLite-backed [BookmarkRepository]. Every query is scoped to
/// [localUserId] — see that constant's doc comment for why there is no
/// real multi-user id yet.
class SqliteBookmarkRepository implements BookmarkRepository {
  final AppDatabase _appDatabase;

  SqliteBookmarkRepository({AppDatabase? appDatabase})
      : _appDatabase = appDatabase ?? AppDatabase.instance;

  @override
  Future<List<Bookmark>> getBookmarks() async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'bookmarks',
      where: 'user_id = ?',
      whereArgs: [localUserId],
      orderBy: 'created_at DESC',
    );
    return rows.map(Bookmark.fromMap).toList();
  }

  @override
  Future<bool> isBookmarked(String ayahKey) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'bookmarks',
      where: 'user_id = ? AND ayah_key = ?',
      whereArgs: [localUserId, ayahKey],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<void> addBookmark(String ayahKey) async {
    final db = await _appDatabase.database;
    // ConflictAlgorithm.ignore: the `(user_id, ayah_key)` unique constraint
    // (schema.dart) means re-bookmarking an already-bookmarked ayah would
    // otherwise throw — this repository's contract is "no-op", not "error".
    await db.insert(
      'bookmarks',
      {
        'user_id': localUserId,
        'ayah_key': ayahKey,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<void> removeBookmark(String ayahKey) async {
    final db = await _appDatabase.database;
    await db.delete(
      'bookmarks',
      where: 'user_id = ? AND ayah_key = ?',
      whereArgs: [localUserId, ayahKey],
    );
  }
}
