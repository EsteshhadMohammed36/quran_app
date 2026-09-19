enum SearchResultKind { ayahText, tafsir }

/// One search hit (`lib/features/search`, spec §17's architecture tree) —
/// either a Quran ayah whose own canonical text contains the query, or a
/// tafsir entry whose commentary contains it. [snippet] is always plain,
/// readable text — this is a results list, not the Mushaf page renderer,
/// so rule #2 (fixed line grid) doesn't apply here; showing plain Uthmani
/// text (or tafsir prose) unstyled is the normal, expected shape for
/// search results, distinct from the styled Mushaf page itself.
class SearchResult {
  final SearchResultKind kind;
  final String ayahKey;
  final int surahId;
  final int ayahNumber;
  final String snippet;

  /// Only set for [SearchResultKind.tafsir] — which source the match came
  /// from (e.g. "تفسير ابن كثير"), so a hit from "الإعراب الميسر" isn't
  /// mistaken for general commentary.
  final String? tafsirSourceName;

  const SearchResult({
    required this.kind,
    required this.ayahKey,
    required this.surahId,
    required this.ayahNumber,
    required this.snippet,
    this.tafsirSourceName,
  });
}
