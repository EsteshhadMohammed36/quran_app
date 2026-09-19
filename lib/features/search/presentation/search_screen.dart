import 'package:flutter/material.dart';

import '../../../shared/theme/mushaf_theme.dart';
import '../../../shared/widgets/ayah_label.dart';
import '../../quran_reader/domain/quran_repository.dart';
import '../domain/search_repository.dart';
import '../domain/search_result.dart';

/// App-wide search across Quran ayah text and tafsir commentary together
/// (`lib/features/search`, spec §17's architecture tree — no numbered spec
/// section of its own; built per the user's explicit request: "البحث في
/// نص الآيات والتفسير مع بعض"). Search-on-submit rather than live/
/// debounced-as-you-type, matching [TafsirScreen]'s own existing
/// per-source search control convention.
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.searchRepository,
    required this.quranRepository,
    required this.onResultTap,
  });

  final SearchRepository searchRepository;
  final QuranRepository quranRepository;

  /// Jumps the Mushaf reader to this ayah and closes this screen.
  final void Function(String ayahKey) onResultTap;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchResults {
  final List<SearchResult> ayahResults;
  final List<SearchResult> tafsirResults;

  const _SearchResults({required this.ayahResults, required this.tafsirResults});

  bool get isEmpty => ayahResults.isEmpty && tafsirResults.isEmpty;
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Future<_SearchResults>? _resultsFuture;

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

  Future<_SearchResults> _search(String query) async {
    final results = await Future.wait([
      widget.searchRepository.searchAyahText(query),
      widget.searchRepository.searchTafsir(query),
    ]);
    return _SearchResults(ayahResults: results[0], tafsirResults: results[1]);
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
            decoration: const InputDecoration(
              hintText: 'ابحث في القرآن والتفسير...',
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
      return const _MessageState(message: 'اكتبي كلمة أو عبارة للبحث فيها.');
    }
    return FutureBuilder<_SearchResults>(
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
            if (results.ayahResults.isNotEmpty) ...[
              _SectionHeader('القرآن (${results.ayahResults.length})'),
              for (final result in results.ayahResults)
                _SearchResultTile(
                  result: result,
                  quranRepository: widget.quranRepository,
                  onTap: () => widget.onResultTap(result.ayahKey),
                ),
            ],
            if (results.tafsirResults.isNotEmpty) ...[
              _SectionHeader('التفسير (${results.tafsirResults.length})'),
              for (final result in results.tafsirResults)
                _SearchResultTile(
                  result: result,
                  quranRepository: widget.quranRepository,
                  onTap: () => widget.onResultTap(result.ayahKey),
                ),
            ],
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold, color: mushafInkColor),
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
