import '../../../core/database/app_database.dart';
import '../../../core/database/local_user.dart';
import '../domain/note.dart';
import '../domain/note_repository.dart';

/// SQLite-backed [NoteRepository]. Every query is scoped to [localUserId] —
/// see that constant's doc comment for why there is no real multi-user id
/// yet.
class SqliteNoteRepository implements NoteRepository {
  final AppDatabase _appDatabase;

  SqliteNoteRepository({AppDatabase? appDatabase})
      : _appDatabase = appDatabase ?? AppDatabase.instance;

  @override
  Future<List<Note>> getAllNotes() async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'notes',
      where: 'user_id = ?',
      whereArgs: [localUserId],
      orderBy: 'COALESCE(updated_at, created_at) DESC',
    );
    return rows.map(Note.fromMap).toList();
  }

  @override
  Future<Note?> getNoteForAyah(String ayahKey) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'notes',
      where: 'user_id = ? AND ayah_key = ?',
      whereArgs: [localUserId, ayahKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Note.fromMap(rows.first);
  }

  @override
  Future<Note> upsertNote(String ayahKey, String content) async {
    final db = await _appDatabase.database;
    final existing = await getNoteForAyah(ayahKey);
    final nowIso = DateTime.now().toIso8601String();

    if (existing == null) {
      final noteId = '$ayahKey:$nowIso';
      await db.insert('notes', {
        'note_id': noteId,
        'user_id': localUserId,
        'ayah_key': ayahKey,
        'content': content,
        'created_at': nowIso,
        'updated_at': null,
      });
      return Note(
        noteId: noteId,
        ayahKey: ayahKey,
        content: content,
        createdAt: DateTime.parse(nowIso),
      );
    }

    await db.update(
      'notes',
      {'content': content, 'updated_at': nowIso},
      where: 'note_id = ?',
      whereArgs: [existing.noteId],
    );
    return Note(
      noteId: existing.noteId,
      ayahKey: ayahKey,
      content: content,
      createdAt: existing.createdAt,
      updatedAt: DateTime.parse(nowIso),
    );
  }

  @override
  Future<void> deleteNote(String noteId) async {
    final db = await _appDatabase.database;
    await db.delete('notes', where: 'note_id = ?', whereArgs: [noteId]);
  }
}
