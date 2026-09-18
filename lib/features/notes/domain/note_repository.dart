import 'note.dart';

/// Domain interface for the Notes module (Prompt 14, spec §15/§19).
///
/// The `notes` table (schema.dart) has no uniqueness constraint on
/// `ayah_key` — but this app's UI only ever shows one editable note per
/// ayah (a single Note action on the Ayah Context Sheet, not a list), so
/// [upsertNote] enforces "at most one note per ayah" itself: it updates the
/// ayah's existing note if one exists, otherwise creates a new one.
///
/// UI widgets depend on this, never on raw SQLite rows directly (spec §17).
abstract class NoteRepository {
  /// Every note for the local user, most recently updated first.
  Future<List<Note>> getAllNotes();

  Future<Note?> getNoteForAyah(String ayahKey);

  /// Creates or updates [ayahKey]'s single note with [content]. Returns the
  /// resulting [Note].
  Future<Note> upsertNote(String ayahKey, String content);

  Future<void> deleteNote(String noteId);
}
