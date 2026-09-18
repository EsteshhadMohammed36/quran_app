import 'reading_state.dart';

/// Domain interface for Last Read (Prompt 14, spec §15/§19/§26). Not its
/// own top-level box in spec §17's literal `lib/` tree (only `bookmarks/`,
/// `notes/`, `search/` are listed there), but the spec's own architecture
/// diagram and §17.1's `UserLibraryProvider` both treat Last Read as a
/// third peer of Bookmarks/Notes under the User Layer — hence its own
/// `last_read` feature folder, matching how the other two are structured,
/// rather than nesting it awkwardly inside one of them.
abstract class ReadingStateRepository {
  /// The local user's saved reading position, or `null` if nothing has
  /// been recorded yet (first launch).
  Future<ReadingState?> getReadingState();

  /// Overwrites the local user's single reading-state row (spec: "Key:
  /// user_id" — always one row, not a history). Called two ways:
  ///  - on every page turn, with just [pageNumber] (surah/ayah/ayahKey left
  ///    `null`) — a coarse, fully automatic "where was I" fallback;
  ///  - from the Ayah Context Sheet's "متابعة" (Continue) action, with the
  ///    full ayah identity — a precise, user-initiated bookmark of exactly
  ///    which ayah to resume from.
  Future<void> saveReadingState({
    required int pageNumber,
    int? surahId,
    int? ayahNumber,
    String? ayahKey,
  });
}
