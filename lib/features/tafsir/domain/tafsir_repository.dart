import 'tafsir_entry.dart';
import 'tafsir_group.dart';
import 'tafsir_source.dart';

/// Domain interface for the Tafsir module (spec §11.2, exact method set).
///
/// UI widgets depend on this, never on raw SQLite rows directly (spec §17).
abstract class TafsirRepository {
  Future<List<TafsirSource>> getSources();

  /// The resolved tafsir text for [ayahKey] in [sourceId] — already
  /// following the group reference if [ayahKey] is a group member, not a
  /// group owner (spec §11).
  Future<TafsirEntry> getEntry(String sourceId, String ayahKey);

  /// The full group [ayahKey]'s tafsir entry belongs to, including every
  /// member ayah (spec §11: "Preserve group references where present").
  Future<TafsirGroup> getGroup(String sourceId, String ayahKey);

  /// Ayahs in [sourceId] whose tafsir text contains [query] (a plain
  /// substring match — MVP scope, not full-text search/ranking).
  Future<List<TafsirEntry>> search(String sourceId, String query);
}
