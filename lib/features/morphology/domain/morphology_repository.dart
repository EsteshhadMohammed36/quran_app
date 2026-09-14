import 'morphology_entry.dart';

/// Domain interface for the Morphology module (spec §12/§12.2).
///
/// UI widgets depend on this, never on raw SQLite rows directly (spec §17).
abstract class MorphologyRepository {
  /// One [MorphologyEntry] per word in [ayahKey], ordered by
  /// `word_position` — exactly the "word list / analysis" spec §12.2 wants
  /// the Morphology tab to show.
  Future<List<MorphologyEntry>> getEntriesForAyah(String ayahKey);
}
