import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
import '../../tafsir/data/sqlite_tafsir_repository.dart';
import '../../tafsir/domain/tafsir_repository.dart';
import '../../user_library/presentation/saved_items_screen.dart';
import '../../user_library/presentation/user_library_provider.dart';
import '../data/sqlite_quran_repository.dart';
import '../domain/mushaf_page.dart';
import '../domain/quran_repository.dart';
import 'mushaf_page_view.dart';
import 'quran_reader_provider.dart';

/// The real Mushaf reader (Prompt 9: full 604-page navigation + ayah
/// selection/hit testing; Prompt 10: the Ayah Context Sheet — spec §9,
/// §10, §17.1, §21). Supersedes [MushafPrototypeScreen] now that the
/// renderer is validated on all 4 required pages (spec §25, CLAUDE.md
/// rule #5 — "any other feature" can now be built on top of it).
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
  Future<void> _jumpToAyah(String ayahKey) async {
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
    _provider?.openAyah(ayahKey);
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
                // saveable but never viewable again.
                Positioned(
                  top: 8,
                  left: 8,
                  child: Material(
                    color: Colors.transparent,
                    child: IconButton(
                      tooltip: 'المحفوظات',
                      onPressed: _openSavedItems,
                      icon: const Icon(Icons.bookmarks_outlined),
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
        final provider = context.watch<QuranReaderProvider>();
        return MushafPageView(
          page: page,
          selectedAyahKey: provider.selectedAyahKey,
          onWordTap: provider.selectWord,
          onBackgroundTap: provider.clearSelection,
        );
      },
    );
  }
}
