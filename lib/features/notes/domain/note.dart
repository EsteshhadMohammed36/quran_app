/// A row of `notes` (spec §15). Key: `note_id` — notes attach to ayah
/// identity, not page pixels (spec §19).
class Note {
  final String noteId;
  final String ayahKey;
  final String content;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const Note({
    required this.noteId,
    required this.ayahKey,
    required this.content,
    required this.createdAt,
    this.updatedAt,
  });

  factory Note.fromMap(Map<String, Object?> map) {
    final updatedAtRaw = map['updated_at'] as String?;
    return Note(
      noteId: map['note_id'] as String,
      ayahKey: map['ayah_key'] as String,
      content: map['content'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: updatedAtRaw == null ? null : DateTime.parse(updatedAtRaw),
    );
  }
}
