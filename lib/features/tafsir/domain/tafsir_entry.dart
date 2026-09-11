/// The resolved tafsir content for one specific ayah in one specific
/// source (spec §11.2 `TafsirRepository.getEntry(sourceId, ayahKey)`).
///
/// [content] is always the *resolved* text — if [ayahKey] is a member of a
/// group rather than the group's own owning ayah, this is the group's
/// shared text (spec §11: "Do not assume every surah:ayah has an
/// independent text blob. Preserve group references where present."), not
/// null. [content] can still legitimately be null: some sources omit
/// commentary for a handful of standalone ayahs entirely (verified
/// directly against the downloaded As-Saadi resource — see
/// tool/ingest_quran_data.dart) rather than exporting a placeholder.
///
/// [isGroupMember] is true when [ayahKey] itself isn't the group's owning
/// ayah (i.e. its tafsir text is defined by a range of ayahs, not by
/// [ayahKey] alone) — the UI uses this to show e.g. "tafsir for ayahs
/// 2:8-2:9" instead of implying an ayah-specific commentary that doesn't
/// exist.
class TafsirEntry {
  final String sourceId;
  final String ayahKey;
  final String groupId;
  final String groupAyahStart;
  final String groupAyahEnd;
  final String? content;

  const TafsirEntry({
    required this.sourceId,
    required this.ayahKey,
    required this.groupId,
    required this.groupAyahStart,
    required this.groupAyahEnd,
    this.content,
  });

  bool get isGroupMember => ayahKey != groupId;

  bool get isMultiAyahGroup => groupAyahStart != groupAyahEnd;

  factory TafsirEntry.fromMap(Map<String, Object?> map) {
    return TafsirEntry(
      sourceId: map['source_id'] as String,
      ayahKey: map['ayah_key'] as String,
      groupId: map['group_id'] as String,
      groupAyahStart: map['group_ayah_start'] as String,
      groupAyahEnd: map['group_ayah_end'] as String,
      content: map['content'] as String?,
    );
  }
}
