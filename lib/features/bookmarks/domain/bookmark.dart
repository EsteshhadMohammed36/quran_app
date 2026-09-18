/// A row of `bookmarks` (spec §15). Key: `(user_id, ayah_key)` — bookmarks
/// attach to ayah identity, not page pixels (spec §19).
class Bookmark {
  final int id;
  final String ayahKey;
  final DateTime createdAt;

  const Bookmark({
    required this.id,
    required this.ayahKey,
    required this.createdAt,
  });

  factory Bookmark.fromMap(Map<String, Object?> map) {
    return Bookmark(
      id: map['id'] as int,
      ayahKey: map['ayah_key'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
