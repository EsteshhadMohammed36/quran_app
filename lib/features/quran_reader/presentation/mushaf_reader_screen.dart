import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/theme/mushaf_theme.dart';
import '../../audio/data/sqlite_audio_repository.dart';
import '../../audio/domain/audio_repository.dart';
import '../../audio/presentation/audio_provider.dart';
import '../../ayah_study/presentation/ayah_context_sheet.dart';
import '../../bookmarks/data/sqlite_bookmark_repository.dart';
import '../../bookmarks/domain/bookmark_repository.dart';
import '../../last_read/data/sqlite_reading_state_repository.dart';
import '../../last_read/domain/reading_state_repository.dart';
import '../../morphology/data/sqlite_morphology_repository.dart';
import '../../morphology/domain/morphology_repository.dart';
import '../../notes/data/sqlite_note_repository.dart';
import '../../notes/domain/note_repository.dart';
import '../../search/data/sqlite_search_repository.dart';
import '../../search/domain/search_repository.dart';
import '../../search/domain/search_result.dart';
import '../../search/presentation/search_screen.dart';
import '../../tafsir/data/sqlite_tafsir_repository.dart';
import '../../tafsir/domain/tafsir_repository.dart';
import '../../user_library/presentation/saved_items_screen.dart';
import '../../user_library/presentation/user_library_provider.dart';
import '../data/sqlite_quran_repository.dart';
import '../domain/mushaf_page.dart';
import '../domain/quran_repository.dart';
import 'mushaf_page_view.dart';
import 'quran_reader_provider.dart';
import 'surah_index_screen.dart';

/// The real Mushaf reader (Prompt 9: full 604-page navigation + ayah
/// selection/hit testing; Prompt 10: the Ayah Context Sheet — spec §9,
/// §10, §17.1, §21). Supersedes the Phase 0 rendering-only prototype now
/// that the renderer is validated on all 4 required pages (spec §25,
/// CLAUDE.md rule #5 — "any other feature" can now be built on top of it).
///
/// Swipes across every page the installed layout has (not a hardcoded 604 —
/// see [QuranRepository.getPageCount]), lazily loading + caching only a
/// small window of nearby pages (rule #6 / spec §21, see
/// [QuranReaderProvider]). Tapping any word resolves its `surah:ayah`,
/// highlights the whole ayah (rule #3), and opens [AyahContextSheet] as a
/// persistent (non-modal) `Scaffold.bottomSheet` — the Mushaf page stays
/// visible/tappable around it, matching spec §10. Tapping elsewhere on
/// the page (or the sheet's own close button) dismisses the selection and
/// closes the sheet (spec §9.1 "Outside tap").
class MushafReaderScreen extends StatefulWidget {
  const MushafReaderScreen({super.key, this.initialPage = 1});

  final int initialPage;

  @override
  State<MushafReaderScreen> createState() => _MushafReaderScreenState();
}

class _MushafReaderScreenState extends State<MushafReaderScreen> {
  final QuranRepository _repository = SqliteQuranRepository();
  final TafsirRepository _tafsirRepository = SqliteTafsirRepository();
  final MorphologyRepository _morphologyRepository =
      SqliteMorphologyRepository();
  final AudioRepository _audioRepository = SqliteAudioRepository();
  late final AudioProvider _audioProvider = AudioProvider(
    audioRepository: _audioRepository,
  );
  final BookmarkRepository _bookmarkRepository = SqliteBookmarkRepository();
  final NoteRepository _noteRepository = SqliteNoteRepository();
  final ReadingStateRepository _readingStateRepository =
      SqliteReadingStateRepository();
  final SearchRepository _searchRepository = SqliteSearchRepository();
  late final UserLibraryProvider _userLibraryProvider = UserLibraryProvider(
    bookmarkRepository: _bookmarkRepository,
    noteRepository: _noteRepository,
    readingStateRepository: _readingStateRepository,
  );
  QuranReaderProvider? _provider;
  PageController? _pageController;
  Object? _initError;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final totalPages = await _repository.getPageCount();
      // Only one reciter is ingested so far (Prompt 13, spec §14 has no
      // picker yet) — read it from the data itself instead of
      // hardcoding its id a second time in the app layer.
      final reciters = await _audioRepository.getReciters();
      // spec §19/§26: restore the last-read position instead of always
      // starting at page 1. Queried directly from the repository (not via
      // [_userLibraryProvider], which loads the same row asynchronously on
      // its own timeline) so the very first frame already opens on the
      // right page rather than starting at page 1 and jumping once loaded.
      final savedState = await _readingStateRepository.getReadingState();
      final int resolvedInitialPage =
          savedState != null &&
              savedState.pageNumber >= 1 &&
              savedState.pageNumber <= totalPages
          ? savedState.pageNumber
          : widget.initialPage;
      if (!mounted) return;
      setState(() {
        _provider = QuranReaderProvider(
          repository: _repository,
          totalPages: totalPages,
          initialPage: resolvedInitialPage,
        );
        _pageController = PageController(
          initialPage: resolvedInitialPage - 1,
        );
        if (reciters.isNotEmpty) {
          _audioProvider.reciterId = reciters.first.reciterId;
        }
        // Restore which ayah was selected too (spec §26: "Last page/ayah is
        // restored"), without popping the sheet open on launch — only an
        // explicit tap (a word, or a Saved Items entry) should do that.
        final String? savedAyahKey = savedState?.ayahKey;
        if (savedAyahKey != null) {
          _provider!.selectAyahKey(savedAyahKey);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _initError = e);
    }
  }

  @override
  void dispose() {
    _provider?.dispose();
    _pageController?.dispose();
    _audioProvider.dispose();
    _userLibraryProvider.dispose();
    super.dispose();
  }

  /// Jumps the reader to [ayahKey]'s page and opens its context sheet —
  /// what tapping an entry in [SavedItemsScreen] does. Resolves the page
  /// the same authoritative way [AyahContextSheet] resolves a word's page
  /// (via [QuranRepository.getPageNumbersForWordIndexes], since
  /// `ayahs.page_number` itself isn't populated — same ingestion gap as
  /// `words.page_number`, see that repository method's own doc comment),
  /// rather than re-deriving page lookup a third way.
  ///
  /// [openSheet] controls whether the Ayah Context Sheet pops open on
  /// arrival (via [QuranReaderProvider.openAyah]) or the ayah is only
  /// selected/highlighted in place (via [QuranReaderProvider.selectAyahKey],
  /// which never touches [QuranReaderProvider.isAyahSheetOpen]). Defaults to
  /// `true` — [SavedItemsScreen]'s jump-to-ayah wants both (a bookmark/note
  /// nobody can revisit *and see* isn't useful). [_openSearch] passes
  /// `false` for ayah-text results (user's explicit complaint, 2026-09-19:
  /// searching the Mushaf's own text and landing straight in the تفسير tab
  /// instead of the Mushaf page defeated the point of "search the Mushaf")
  /// but keeps the default `true` for تفسير-scoped results, where jumping
  /// straight into the sheet is exactly what searching tafsir implies.
  Future<void> _jumpToAyah(String ayahKey, {bool openSheet = true}) async {
    final words = await _repository.getWords(ayahKey);
    if (words.isEmpty || !mounted) return;
    final pageByWordIndex = await _repository.getPageNumbersForWordIndexes([
      words.first.wordIndex,
    ]);
    final int? page = pageByWordIndex[words.first.wordIndex];
    if (page == null || !mounted) return;
    // jumpToPage itself drives _ReaderPageView's onPageChanged, which
    // already calls QuranReaderProvider.onPageSettled/
    // UserLibraryProvider.updateLastReadPage — no need to call either a
    // second time here.
    _pageController?.jumpToPage(page - 1);
    if (openSheet) {
      _provider?.openAyah(ayahKey);
    } else {
      _provider?.selectAyahKey(ayahKey);
    }
  }

  void _openSavedItems() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ChangeNotifierProvider<UserLibraryProvider>.value(
          value: _userLibraryProvider,
          child: SavedItemsScreen(
            quranRepository: _repository,
            onJumpToAyah: (ayahKey) {
              Navigator.of(context).pop();
              _jumpToAyah(ayahKey);
            },
          ),
        ),
      ),
    );
  }

  /// Scope is decided here, not inside [SearchScreen] itself (spec §10's
  /// sheet stays visible over the Mushaf page, so "reading the Mushaf" and
  /// "التفسير tab open" are two states of the *same* screen, not two
  /// different screens): تفسير open → search only tafsir; anything else
  /// (sheet closed, or open on a different tab) → search only ayah text.
  /// User's explicit request, replacing an earlier version that searched
  /// both at once and grouped results by kind.
  void _openSearch(QuranReaderProvider readerProvider) {
    final SearchResultKind scope =
        readerProvider.isAyahSheetOpen &&
            readerProvider.activeStudyTab == StudyTab.tafsir
        ? SearchResultKind.tafsir
        : SearchResultKind.ayahText;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SearchScreen(
          scope: scope,
          searchRepository: _searchRepository,
          quranRepository: _repository,
          onResultTap: (ayahKey) {
            Navigator.of(context).pop();
            _jumpToAyah(ayahKey, openSheet: scope == SearchResultKind.tafsir);
          },
        ),
      ),
    );
  }

  /// Opens [SurahIndexScreen] (spec §3: "Surah, Juz, Hizb and page
  /// navigation") — a third deliberate exception to the reader's "no
  /// permanent chrome" rule, same reasoning as the Saved Items/Search
  /// corner buttons: without a fixed entry point, jumping straight to a
  /// named surah would only be possible by swiping through pages one at a
  /// time.
  void _openSurahIndex() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SurahIndexScreen(
          quranRepository: _repository,
          onSurahTap: (pageNumber) {
            Navigator.of(context).pop();
            _pageController?.jumpToPage(pageNumber - 1);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final initError = _initError;
    if (initError != null) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Error: $initError'),
          ),
        ),
      );
    }

    final provider = _provider;
    final pageController = _pageController;
    if (provider == null || pageController == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<QuranReaderProvider>.value(value: provider),
        ChangeNotifierProvider<AudioProvider>.value(value: _audioProvider),
        ChangeNotifierProvider<UserLibraryProvider>.value(
          value: _userLibraryProvider,
        ),
      ],
      child: Consumer<QuranReaderProvider>(
        builder: (context, readerProvider, _) => Scaffold(
          body: SafeArea(
            child: Stack(
              children: [
                _ReaderPageView(
                  pageController: pageController,
                  totalPages: provider.totalPages,
                ),
                // The reader deliberately has no permanent chrome
                // (CLAUDE.md's Phase 0 entry) — this one small always-
                // visible corner button is the sole entry point to
                // [SavedItemsScreen]; without it, bookmarks/notes would be
                // saveable but never viewable again. It used to be a plain
                // transparent IconButton, which on a surah's first page sits
                // right on top of the decorative surah-header banner's own
                // dark ink — same dark ink color as the icon itself, so the
                // icon visually disappeared into the banner's scrollwork
                // (user-reported). An opaque circular chip behind the icon
                // fixes this regardless of what's underneath (banner corner,
                // ayah text, ...) rather than needing per-page positioning.
                Positioned(
                  top: 8,
                  left: 8,
                  child: Material(
                    color: mushafPageColor,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: IconButton(
                      tooltip: 'المحفوظات',
                      onPressed: _openSavedItems,
                      icon: const Icon(
                        Icons.bookmarks_outlined,
                        color: mushafInkColor,
                      ),
                    ),
                  ),
                ),
                // Symmetric top-right entry point to [SearchScreen] — a
                // second, deliberate exception to "no permanent chrome"
                // alongside the Saved Items button above: one fixed way in,
                // scoped by whatever's currently open (see _openSearch).
                // Same opaque-chip treatment from the start (not a plain
                // transparent IconButton) so it doesn't repeat that bug on
                // a surah's first page. Tooltip reflects the resolved scope
                // so it's clear before tapping which thing will be
                // searched.
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: mushafPageColor,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: IconButton(
                      tooltip:
                          readerProvider.isAyahSheetOpen &&
                              readerProvider.activeStudyTab ==
                                  StudyTab.tafsir
                          ? 'بحث في التفسير'
                          : 'بحث في المصحف',
                      onPressed: () => _openSearch(readerProvider),
                      icon: const Icon(Icons.search, color: mushafInkColor),
                    ),
                  ),
                ),
                // Bottom-left corner, mirroring the Saved Items chip above
                // it — the reader's fourth (and last planned) deliberate
                // exception to "no permanent chrome": a fixed way to jump
                // straight to any surah by name instead of only swiping.
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Material(
                    color: mushafPageColor,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: IconButton(
                      tooltip: 'فهرس السور',
                      onPressed: _openSurahIndex,
                      icon: const Icon(
                        Icons.menu_book_outlined,
                        color: mushafInkColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // A persistent (non-modal) sheet, not showModalBottomSheet: spec
          // §10 wants the Mushaf page to stay visible and tappable around
          // it (e.g. tapping a different ayah while the sheet is open),
          // which a modal barrier would block.
          bottomSheet: readerProvider.isAyahSheetOpen
              ? AyahContextSheet(
                  repository: _repository,
                  tafsirRepository: _tafsirRepository,
                  morphologyRepository: _morphologyRepository,
                )
              : null,
        ),
      ),
    );
  }
}

class _ReaderPageView extends StatelessWidget {
  const _ReaderPageView({
    required this.pageController,
    required this.totalPages,
  });

  final PageController pageController;
  final int totalPages;

  @override
  Widget build(BuildContext context) {
    // Ambient RTL so the PageView's index order and swipe gesture match how
    // a real (right-bound) Mushaf turns pages: index 0 (page 1) starts on
    // the right, and swiping toward higher page numbers reads naturally
    // right-to-left. Each page's own text layout already sets its own RTL
    // Directionality independently (MushafPageView) — this is the outer
    // navigation direction, a separate concern.
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PageView.builder(
        controller: pageController,
        itemCount: totalPages,
        // spec §21 performance pass (2026-09-19): without this, PageView
        // only builds the current page's widget tree — the neighbor page
        // (already prefetched as *data* via QuranReaderProvider's
        // cacheWindowRadius) still has to build/lay out its Arabic text
        // from scratch the instant a swipe starts, which can visibly hitch
        // ("Ayah selection/hit testing must remain responsive while
        // scrolling"). `true` makes PageView also build+keep alive the
        // immediate previous/next page ahead of the gesture — still only
        // 3 pages' widgets ever exist at once, nowhere near rule #6's
        // "never render all 604 pages simultaneously".
        allowImplicitScrolling: true,
        onPageChanged: (index) {
          context.read<QuranReaderProvider>().onPageSettled(index + 1);
          // spec §19/§26: keep last-read current on every page turn, not
          // just via the explicit "متابعة" action — see
          // [UserLibraryProvider.updateLastReadPage]'s doc comment.
          context.read<UserLibraryProvider>().updateLastReadPage(index + 1);
        },
        itemBuilder: (context, index) {
          return _LazyPage(pageNumber: index + 1);
        },
      ),
    );
  }
}

/// Loads and renders a single page. Fetches it exactly once per widget
/// lifetime (via the stable `late final` future below) regardless of how
/// many times an ancestor rebuilds — e.g. on ayah selection changes, which
/// rebuild every currently-alive page in the PageView's window.
class _LazyPage extends StatefulWidget {
  const _LazyPage({required this.pageNumber});

  final int pageNumber;

  @override
  State<_LazyPage> createState() => _LazyPageState();
}

class _LazyPageState extends State<_LazyPage> {
  late final Future<MushafPage> _future = context
      .read<QuranReaderProvider>()
      .loadPage(widget.pageNumber);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MushafPage>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Error loading page ${widget.pageNumber}: ${snapshot.error}',
              ),
            ),
          );
        }
        final page = snapshot.data;
        if (page == null) {
          return const Center(child: CircularProgressIndicator());
        }
        // `select`, not `watch`: this page must only rebuild when the
        // selected ayah itself changes (to move the highlight), not on
        // every QuranReaderProvider notification — e.g. switching the
        // sheet's active study tab used to rebuild every visible Mushaf
        // page too, even though nothing about its rendering changed
        // (2026-09-19 performance pass, same class of fix as
        // ayah_context_sheet.dart's _HighlightedAyahText).
        final selectedAyahKey = context.select<QuranReaderProvider, String?>(
          (p) => p.selectedAyahKey,
        );
        final provider = context.read<QuranReaderProvider>();
        return MushafPageView(
          page: page,
          selectedAyahKey: selectedAyahKey,
          onWordTap: provider.selectWord,
          onBackgroundTap: provider.clearSelection,
        );
      },
    );
  }
}
