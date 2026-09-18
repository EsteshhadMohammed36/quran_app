import 'bookmark.dart';

/// Domain interface for the Bookmarks module (Prompt 14, spec §15/§19).
///
/// UI widgets depend on this, never on raw SQLite rows directly (spec §17).
abstract class BookmarkRepository {
  /// Every bookmark for the local user, most recent first.
  Future<List<Bookmark>> getBookmarks();

  Future<bool> isBookmarked(String ayahKey);

  /// Adding a bookmark that already exists for [ayahKey] is a no-op — the
  /// `(user_id, ayah_key)` unique constraint (schema.dart) means there is
  /// only ever one bookmark per ayah, so there is nothing to toggle beyond
  /// present/absent.
  Future<void> addBookmark(String ayahKey);

  Future<void> removeBookmark(String ayahKey);
}
