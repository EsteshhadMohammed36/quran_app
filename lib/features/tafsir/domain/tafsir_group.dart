/// The full group a given ayah's tafsir entry belongs to (spec §11.2
/// `TafsirRepository.getGroup(sourceId, ayahKey)`), including every member
/// ayah — not just the resolved text [TafsirEntry] already gives you.
///
/// For a standalone (non-grouped) ayah, [memberAyahKeys] has exactly one
/// element (the ayah itself) — spec §11's "preserve group references"
/// still applies, it's just a group of size 1.
class TafsirGroup {
  final String sourceId;
  final String groupId;
  final String groupAyahStart;
  final String groupAyahEnd;
  final String? content;
  final List<String> memberAyahKeys;

  const TafsirGroup({
    required this.sourceId,
    required this.groupId,
    required this.groupAyahStart,
    required this.groupAyahEnd,
    required this.memberAyahKeys,
    this.content,
  });

  bool get isMultiAyahGroup => groupAyahStart != groupAyahEnd;
}
