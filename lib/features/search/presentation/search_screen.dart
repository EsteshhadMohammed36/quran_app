import 'package:flutter/material.dart';

import '../../../shared/theme/mushaf_theme.dart';
import '../../../shared/widgets/ayah_label.dart';
import '../../quran_reader/domain/quran_repository.dart';
import '../domain/search_repository.dart';
import '../domain/search_result.dart';

/// Scoped search (`lib/features/search`, spec §17's architecture tree — no
/// numbered spec section of its own). Deliberately single-scope per screen
/// instance rather than one combined "search everything and group by kind"
/// screen (an earlier version of this did that; the user explicitly asked
/// for it to be split instead): [scope] is decided entirely by the caller,
/// not by this widget — `MushafReaderScreen` reads its own
/// `QuranReaderProvider` state (is the Ayah Context Sheet open, and is its
/// active tab `StudyTab.tafsir`?) to pick `SearchResultKind.tafsir` vs
/// `.ayahText` before pushing this screen. [SearchScreen] itself stays
/// ignorant of *why* a scope was chosen — that decision belongs to
/// whoever is currently showing the Mushaf, not to the search feature, so
/// `search` never has to depend on `quran_reader`'s presentation state.
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.scope,
    required this.searchRepository,
    required this.quranRepository,
    required this.onResultTap,
  });

  final SearchResultKind scope;
  final SearchRepository searchRepository;
  final QuranRepository quranRepository;

  /// Jumps the Mushaf reader to this ayah and closes this screen.
  final void Function(String ayahKey) onResultTap;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Future<List<SearchResult>>? _resultsFuture;

  bool get _isTafsirScope => widget.scope == SearchResultKind.tafsir;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _runSearch() {
    final String query = _controller.text.trim();
    setState(() {
      _resultsFuture = query.isEmpty ? null : _search(query);
    });
  }

  Future<List<SearchResult>> _search(String query) {
    return _isTafsirScope
        ? widget.searchRepository.searchTafsir(query)
        : widget.searchRepository.searchAyahText(query);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: mushafPageColor,
        appBar: AppBar(
          backgroundColor: mushafPageColor,
          foregroundColor: mushafInkColor,
          title: TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _runSearch(),
            style: const TextStyle(color: mushafInkColor),
            decoration: InputDecoration(
              hintText: _isTafsirScope
                  ? 'ابحث في التفسير...'
                  : 'ابحث في آيات المصحف...',
              border: InputBorder.none,
            ),
          ),
          actions: [
            IconButton(icon: const Icon(Icons.search), onPressed: _runSearch),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final future = _resultsFuture;
    if (future == null) {
      return _MessageState(
        message: _isTafsirScope
            ? 'اكتب كلمة أو عبارة للبحث في التفسير.'
            : 'اكتب كلمة أو عبارة للبحث في آيات المصحف.',
      );
    }
    return FutureBuilder<List<SearchResult>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _MessageState(message: 'خطأ: ${snapshot.error}');
        }
        final results = snapshot.data;
        if (results == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (results.isEmpty) {
          return const _MessageState(message: 'لا توجد نتائج.');
        }
        return ListView(
          children: [
            for (final result in results)
              _SearchResultTile(
                result: result,
                quranRepository: widget.quranRepository,
                onTap: () => widget.onResultTap(result.ayahKey),
              ),
          ],
        );
      },
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: mushafInkColor.withValues(alpha: 0.6)),
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.result,
    required this.quranRepository,
    required this.onTap,
  });

  final SearchResult result;
  final QuranRepository quranRepository;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        result.kind == SearchResultKind.ayahText
            ? Icons.menu_book_outlined
            : Icons.notes_outlined,
        color: mushafInkColor,
      ),
      title: FutureBuilder<String>(
        future: resolveAyahLabel(quranRepository, result.ayahKey),
        builder: (context, snapshot) {
          final String label = snapshot.data ?? result.ayahKey;
          final String? sourceName = result.tafsirSourceName;
          return Text(
            sourceName == null ? label : '$label  •  $sourceName',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: mushafInkColor,
            ),
          );
        },
      ),
      subtitle: Text(
        result.snippet,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: mushafInkColor.withValues(alpha: 0.75)),
      ),
      onTap: onTap,
    );
  }
}
