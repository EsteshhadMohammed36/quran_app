import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/mushaf_page.dart';
import '../domain/quran_repository.dart';
import '../domain/word.dart';

/// The Ayah Context Sheet's study tabs (spec §10: "Meaning, Morphology,
/// Grammar, Qiraat (future)"). Qiraat has no tab content at all yet — it's
/// listed in the UI as a future placeholder, not a selectable tab.
enum StudyTab { meaning, morphology, grammar }

/// App state for the Mushaf reader (spec §17.1 `QuranReaderProvider`):
/// which page is showing, which ayah is selected, and a small lazily
/// loaded page cache.
///
/// CLAUDE.md rule #6 / spec §21: never hold all 604 pages in memory at
/// once. [loadPage] fetches from [QuranRepository] on demand and caches
/// the result; [_evictOutsideWindow] drops anything more than
/// [cacheWindowRadius] pages away from [currentPage] as the reader moves,
/// so memory stays bounded to a small constant window regardless of how
/// far the user has scrolled through the 604 pages.
///
/// The ayah context sheet (spec §17.1 `isAyahSheetOpen`/`activeStudyTab`)
/// isn't built yet (a later prompt) — this provider only covers the
/// selection/hit-testing slice needed for that.
class QuranReaderProvider extends ChangeNotifier {
  QuranReaderProvider({
    required QuranRepository repository,
    required this.totalPages,
    int initialPage = 1,
  }) : _repository = repository,
       _currentPage = initialPage {
    _prefetchNeighbors();
  }

  final QuranRepository _repository;
  final int totalPages;

  /// How many pages on each side of [currentPage] stay cached.
  static const int cacheWindowRadius = 2;

  int _currentPage;
  int get currentPage => _currentPage;

  String? _selectedAyahKey;
  String? get selectedAyahKey => _selectedAyahKey;

  /// spec §17.1 `isAyahSheetOpen` / `activeStudyTab`. The sheet's open
  /// state tracks selection 1:1 for now (opening = selecting an ayah,
  /// closing = clearing it) — the state table in spec §9.1 never
  /// describes an ayah staying selected on the page with the sheet
  /// hidden, so there's no third state to model yet.
  bool _isAyahSheetOpen = false;
  bool get isAyahSheetOpen => _isAyahSheetOpen;

  StudyTab _activeStudyTab = StudyTab.meaning;
  StudyTab get activeStudyTab => _activeStudyTab;

  void setActiveStudyTab(StudyTab tab) {
    if (_activeStudyTab == tab) return;
    _activeStudyTab = tab;
    notifyListeners();
  }

  final Map<int, MushafPage> _pageCache = {};
  final Map<int, Future<MushafPage>> _inFlight = {};

  /// Returns the cached page for [pageNumber] without triggering a fetch,
  /// or `null` if it isn't currently cached.
  MushafPage? peekPage(int pageNumber) => _pageCache[pageNumber];

  /// Returns the cached page if present, otherwise fetches it from
  /// [_repository] and caches it. Concurrent calls for the same page share
  /// the same in-flight request rather than issuing duplicate queries.
  Future<MushafPage> loadPage(int pageNumber) {
    final cached = _pageCache[pageNumber];
    if (cached != null) return SynchronousFuture(cached);

    final inFlight = _inFlight[pageNumber];
    if (inFlight != null) return inFlight;

    final future = _repository.getPage(pageNumber).then((page) {
      _pageCache[pageNumber] = page;
      _inFlight.remove(pageNumber);
      _evictOutsideWindow();
      return page;
    });
    _inFlight[pageNumber] = future;
    return future;
  }

  /// Call when the reader settles on a new page (a swipe finished). Updates
  /// [currentPage], evicts pages outside the cache window, and prefetches
  /// the immediate neighbors so the next swipe stays instant.
  void onPageSettled(int pageNumber) {
    if (pageNumber == _currentPage) return;
    _currentPage = pageNumber;
    _evictOutsideWindow();
    notifyListeners();
    _prefetchNeighbors();
  }

  void _prefetchNeighbors() {
    for (final neighbor in [_currentPage - 1, _currentPage + 1]) {
      if (neighbor >= 1 && neighbor <= totalPages) {
        unawaited(loadPage(neighbor));
      }
    }
  }

  void _evictOutsideWindow() {
    _pageCache.removeWhere(
      (pageNumber, _) => (pageNumber - _currentPage).abs() > cacheWindowRadius,
    );
  }

  /// Rule #3 / spec §9: tapping any word resolves to `surah:ayah`,
  /// selects/highlights the *whole* ayah (never just the tapped word),
  /// then opens the ayah context sheet (spec §9's flow ends with "...
  /// -> open Ayah Context Sheet"). Tapping a *different* ayah while the
  /// sheet is already open updates the selection in place and leaves the
  /// sheet open (spec §9.1 "Different ayah tapped"), keeping whichever
  /// study tab was already active rather than resetting it.
  void selectWord(Word word) {
    final ayahKey = word.ayahKey;
    if (_selectedAyahKey == ayahKey && _isAyahSheetOpen) return;
    _selectedAyahKey = ayahKey;
    _isAyahSheetOpen = true;
    notifyListeners();
  }

  /// spec §9.1 "Outside tap": dismiss the selection and close the sheet.
  void clearSelection() {
    if (_selectedAyahKey == null && !_isAyahSheetOpen) return;
    _selectedAyahKey = null;
    _isAyahSheetOpen = false;
    _activeStudyTab = StudyTab.meaning;
    notifyListeners();
  }
}
