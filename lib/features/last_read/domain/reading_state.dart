/// A row of `reading_state` (spec §15). Key: `user_id` — one row per user,
/// overwritten on every update. Restoring this must not fall back to page 1
/// (spec §19) and must survive an app restart (spec §26 "Last read: Last
/// page/ayah is restored after app restart").
///
/// [surahId]/[ayahNumber]/[ayahKey] are `null` when only a page (not a
/// specific ayah) has been recorded — see
/// [ReadingStateRepository.saveReadingState]'s doc comment.
class ReadingState {
  final int pageNumber;
  final int? surahId;
  final int? ayahNumber;
  final String? ayahKey;
  final DateTime updatedAt;

  const ReadingState({
    required this.pageNumber,
    this.surahId,
    this.ayahNumber,
    this.ayahKey,
    required this.updatedAt,
  });

  factory ReadingState.fromMap(Map<String, Object?> map) {
    return ReadingState(
      pageNumber: map['page_number'] as int,
      surahId: map['surah_id'] as int?,
      ayahNumber: map['ayah_number'] as int?,
      ayahKey: map['ayah_key'] as String?,
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
