import 'search_result.dart';

/// Domain interface for the Search module (`lib/features/search`, spec
/// §17's architecture tree). Searches ayah text and tafsir separately
/// rather than one merged method, since the UI groups results by kind
/// (user's explicit request: "البحث في نص الآيات والتفسير مع بعض").
///
/// UI widgets depend on this, never on raw SQLite rows directly (spec §17).
abstract class SearchRepository {
  /// Ayahs whose own canonical text (`ayahs.text_uthmani`) contains
  /// [query] — a substring match with tashkeel, tatweel, and alef
  /// variants folded on both sides, so a query typed on a real keyboard
  /// (plain letters, no diacritics, plain alef) still matches the fully
  /// diacritized canonical text written in strict Uthmani orthography.
  /// Still MVP scope otherwise (same as `TafsirRepository.search`'s own
  /// doc comment: not full-text search/ranking). The returned
  /// [SearchResult.snippet] is always the untouched canonical text.
  Future<List<SearchResult>> searchAyahText(String query);

  /// Tafsir entries across *every* source (Ibn Kathir, As-Saadi, Iraab
  /// Al-Muyassar) whose content contains [query] — unlike
  /// `TafsirRepository.search`, which is scoped to one source at a time
  /// for the Tafsir screen's own per-source accordion search, this spans
  /// all of them since a general search has no single source in context.
  Future<List<SearchResult>> searchTafsir(String query);
}
