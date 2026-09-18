import 'package:flutter/foundation.dart';

import '../../bookmarks/domain/bookmark.dart';
import '../../bookmarks/domain/bookmark_repository.dart';
import '../../last_read/domain/reading_state.dart';
import '../../last_read/domain/reading_state_repository.dart';
import '../../notes/domain/note.dart';
import '../../notes/domain/note_repository.dart';

/// spec §17.1's `UserLibraryProvider` (`bookmarks`, `notes`, `lastRead`):
/// one combined provider over the three User Layer repositories
/// ([BookmarkRepository], [NoteRepository], [ReadingStateRepository]),
/// living in its own `user_library` feature rather than nested inside any
/// one of those three siblings — see [ReadingStateRepository]'s doc comment
/// for the same reasoning applied to its own folder.
///
/// Loads its full state once up front (a handful of rows at most — nowhere
/// near CLAUDE.md rule #6's "don't hold everything in memory" territory,
/// which is about the 604 Mushaf pages, not user data) and keeps it in
/// memory as plain in-memory indexes (`Set`/`Map`) so
/// [isBookmarked]/[noteForAyah] are synchronous — the Ayah Context Sheet
/// needs to check these on every build, not re-query SQLite each time.
class UserLibraryProvider extends ChangeNotifier {
  UserLibraryProvider({
    required BookmarkRepository bookmarkRepository,
    required NoteRepository noteRepository,
    required ReadingStateRepository readingStateRepository,
  })  : _bookmarkRepository = bookmarkRepository,
        _noteRepository = noteRepository,
        _readingStateRepository = readingStateRepository {
    _loadInitial();
  }

  final BookmarkRepository _bookmarkRepository;
  final NoteRepository _noteRepository;
  final ReadingStateRepository _readingStateRepository;

  bool _isLoaded = false;
  List<Bookmark> _bookmarks = [];
  Map<String, Note> _notesByAyahKey = {};
  ReadingState? _lastRead;

  bool get isLoaded => _isLoaded;
  ReadingState? get lastRead => _lastRead;

  /// Most recently bookmarked first — see [SqliteBookmarkRepository
  /// .getBookmarks]'s `ORDER BY created_at DESC`.
  List<Bookmark> get bookmarks => List.unmodifiable(_bookmarks);

  /// Most recently updated first.
  List<Note> get notes => List.unmodifiable(_notesByAyahKey.values);

  bool isBookmarked(String ayahKey) =>
      _bookmarks.any((b) => b.ayahKey == ayahKey);
  Note? noteForAyah(String ayahKey) => _notesByAyahKey[ayahKey];

  Future<void> _loadInitial() async {
    final bookmarksFuture = _bookmarkRepository.getBookmarks();
    final notesFuture = _noteRepository.getAllNotes();
    final readingStateFuture = _readingStateRepository.getReadingState();

    final bookmarks = await bookmarksFuture;
    final notes = await notesFuture;
    final readingState = await readingStateFuture;

    _bookmarks = bookmarks;
    _notesByAyahKey = {for (final n in notes) n.ayahKey: n};
    _lastRead = readingState;
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> toggleBookmark(String ayahKey) async {
    if (isBookmarked(ayahKey)) {
      await _bookmarkRepository.removeBookmark(ayahKey);
      _bookmarks = [..._bookmarks]..removeWhere((b) => b.ayahKey == ayahKey);
    } else {
      await _bookmarkRepository.addBookmark(ayahKey);
      // Re-read from the repository rather than fabricating an id/timestamp
      // here — [Bookmark.id] is a real AUTOINCREMENT primary key only the
      // database can assign.
      _bookmarks = await _bookmarkRepository.getBookmarks();
    }
    notifyListeners();
  }

  /// Saves/updates [ayahKey]'s single note, or deletes it when [content] is
  /// blank (the note editor's own "empty save = delete" convention — see
  /// `NoteEditorSheet`).
  Future<void> saveNote(String ayahKey, String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      await deleteNote(ayahKey);
      return;
    }
    final note = await _noteRepository.upsertNote(ayahKey, trimmed);
    _notesByAyahKey = {..._notesByAyahKey, ayahKey: note};
    notifyListeners();
  }

  Future<void> deleteNote(String ayahKey) async {
    final existing = _notesByAyahKey[ayahKey];
    if (existing == null) return;
    await _noteRepository.deleteNote(existing.noteId);
    _notesByAyahKey = {..._notesByAyahKey}..remove(ayahKey);
    notifyListeners();
  }

  /// Coarse, fully automatic last-read save — called on every page turn
  /// with just the page number (spec §19/§26: never fall back to page 1 on
  /// restart). Doesn't touch a previously recorded ayah-level position from
  /// [markAyahAsLastRead] unless this page turn moved away from it, since a
  /// plain swipe carries no ayah-level information of its own.
  Future<void> updateLastReadPage(int pageNumber) async {
    final current = _lastRead;
    final bool sameAyahStillOnThisPage =
        current != null && current.pageNumber == pageNumber;
    await _readingStateRepository.saveReadingState(
      pageNumber: pageNumber,
      surahId: sameAyahStillOnThisPage ? current.surahId : null,
      ayahNumber: sameAyahStillOnThisPage ? current.ayahNumber : null,
      ayahKey: sameAyahStillOnThisPage ? current.ayahKey : null,
    );
    _lastRead = ReadingState(
      pageNumber: pageNumber,
      surahId: sameAyahStillOnThisPage ? current.surahId : null,
      ayahNumber: sameAyahStillOnThisPage ? current.ayahNumber : null,
      ayahKey: sameAyahStillOnThisPage ? current.ayahKey : null,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  /// Precise, user-initiated last-read save — the Ayah Context Sheet's
  /// "متابعة" (Continue) action: "resume reading from exactly this ayah."
  Future<void> markAyahAsLastRead({
    required int pageNumber,
    required int surahId,
    required int ayahNumber,
    required String ayahKey,
  }) async {
    await _readingStateRepository.saveReadingState(
      pageNumber: pageNumber,
      surahId: surahId,
      ayahNumber: ayahNumber,
      ayahKey: ayahKey,
    );
    _lastRead = ReadingState(
      pageNumber: pageNumber,
      surahId: surahId,
      ayahNumber: ayahNumber,
      ayahKey: ayahKey,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }
}
