import 'package:flutter/material.dart';

import '../data/sqlite_quran_repository.dart';
import '../domain/mushaf_page.dart';
import '../domain/quran_repository.dart';
import 'mushaf_page_view.dart';

/// Spec §25 "Mandatory Prototype Before Full Build": validates the Mushaf
/// renderer (layout + script + font) on page 1, a multi-surah page, a
/// mid-range page, and page 604 — nothing else. This screen only cycles
/// through those 4 pages (swipe); it is not the real reader (CLAUDE.md
/// rule #5: don't scale past the validated prototype).
///
/// No permanent chrome (title bar / page-number chips) so the page itself
/// fills the screen like a real Mushaf. Tapping the page briefly reveals
/// which of the 4 prototype pages is showing.
///
/// All 4 pages are loaded once up front, not per-swipe: this is local
/// SQLite data, not a network/backend call, so swiping between already-
/// validated pages must feel instant with no reload/spinner in between.
class MushafPrototypeScreen extends StatefulWidget {
  const MushafPrototypeScreen({super.key});

  /// (page number, prototype case label per spec §25).
  static const List<(int, String)> prototypePages = [
    (1, 'Page 1'),
    (601, 'Multi-surah page (3 surah headers)'),
    (300, 'Mid-range page'),
    (604, 'Page 604 (last page)'),
  ];

  @override
  State<MushafPrototypeScreen> createState() => _MushafPrototypeScreenState();
}

class _MushafPrototypeScreenState extends State<MushafPrototypeScreen> {
  final QuranRepository _repository = SqliteQuranRepository();
  final PageController _controller = PageController();
  int _index = 0;
  bool _showPageNumber = false;
  late final Future<List<MushafPage>> _pagesFuture;

  @override
  void initState() {
    super.initState();
    _pagesFuture = Future.wait([
      for (final (pageNumber, _) in MushafPrototypeScreen.prototypePages)
        _repository.getPage(pageNumber),
    ]);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleNumberOverlay() {
    setState(() => _showPageNumber = !_showPageNumber);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<List<MushafPage>>(
          future: _pagesFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Error: ${snapshot.error}'),
              );
            }
            final pages = snapshot.data;
            if (pages == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return Stack(
              children: [
                PageView.builder(
                  controller: _controller,
                  itemCount: pages.length,
                  onPageChanged: (i) => setState(() {
                    _index = i;
                    _showPageNumber = false;
                  }),
                  itemBuilder: (context, i) {
                    return GestureDetector(
                      onTap: _toggleNumberOverlay,
                      behavior: HitTestBehavior.opaque,
                      child: MushafPageView(page: pages[i]),
                    );
                  },
                ),
                if (_showPageNumber)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surface.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(blurRadius: 4, color: Colors.black26),
                        ],
                      ),
                      child: Text(
                        '${MushafPrototypeScreen.prototypePages[_index].$1}',
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
