import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ayah_study/presentation/ayah_context_sheet.dart';
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
      if (!mounted) return;
      setState(() {
        _provider = QuranReaderProvider(
          repository: _repository,
          totalPages: totalPages,
          initialPage: widget.initialPage,
        );
        _pageController = PageController(
          initialPage: widget.initialPage - 1,
        );
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
    super.dispose();
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

    return ChangeNotifierProvider<QuranReaderProvider>.value(
      value: provider,
      child: Consumer<QuranReaderProvider>(
        builder: (context, readerProvider, _) => Scaffold(
          body: SafeArea(
            child: _ReaderPageView(
              pageController: pageController,
              totalPages: provider.totalPages,
            ),
          ),
          // A persistent (non-modal) sheet, not showModalBottomSheet: spec
          // §10 wants the Mushaf page to stay visible and tappable around
          // it (e.g. tapping a different ayah while the sheet is open),
          // which a modal barrier would block.
          bottomSheet: readerProvider.isAyahSheetOpen
              ? AyahContextSheet(repository: _repository)
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
        onPageChanged: (index) =>
            context.read<QuranReaderProvider>().onPageSettled(index + 1),
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
