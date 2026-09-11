import 'package:flutter/material.dart';

import '../../../shared/theme/mushaf_theme.dart';
import '../../../shared/widgets/quran_ayah_text.dart';
import '../../quran_reader/domain/quran_repository.dart';
import '../../quran_reader/domain/surah.dart';
import '../../quran_reader/domain/word.dart';
import '../../quran_reader/presentation/quran_reader_provider.dart';
import '../domain/tafsir_entry.dart';
import '../domain/tafsir_repository.dart';
import '../domain/tafsir_source.dart';
import 'tafsir_html_text.dart';

/// TafsirScreen (spec §11.1): Selected Ayah header -> list of Tafsir
/// Sources as an accordion (source header + source content) -> Previous/
/// Current/Next ayah navigation -> font size control -> search control ->
/// Return to Mushaf.
///
/// Opened from [AyahContextSheet]'s "تفسير" (Tafsir) action (spec §11:
/// "Tafsir open: Tafsir reader replaces/extends the context layer without
/// losing ayah identity") via a normal full-screen [Navigator.push] — not
/// another sheet, since this needs room for multiple accordion sources
/// plus ayah navigation/search/font controls at once, unlike the compact
/// Ayah Context Sheet.
///
/// [quranReaderProvider] is the *same* [QuranReaderProvider] instance the
/// Mushaf reader uses, passed in directly rather than looked up via
/// `Provider.of`/`context.read` — a route pushed by [Navigator.push] isn't
/// a descendant of the `ChangeNotifierProvider` that wraps the reader's
/// own widget tree (that provider only wraps the *first* route's content,
/// not the whole `Navigator`), so ambient lookup would throw here. Every
/// ayah-navigation step calls [QuranReaderProvider.selectAyahKey] on it
/// directly, so "Return to Mushaf" always shows the last-viewed ayah
/// selected/highlighted (preserving ayah identity per spec §11).
class TafsirScreen extends StatefulWidget {
  const TafsirScreen({
    super.key,
    required this.initialAyahKey,
    required this.quranRepository,
    required this.tafsirRepository,
    required this.quranReaderProvider,
  });

  final String initialAyahKey;
  final QuranRepository quranRepository;
  final TafsirRepository tafsirRepository;
  final QuranReaderProvider quranReaderProvider;

  @override
  State<TafsirScreen> createState() => _TafsirScreenState();
}

class _TafsirScreenState extends State<TafsirScreen> {
  late String _ayahKey = widget.initialAyahKey;
  double _fontSize = 18;

  // Classic single-open accordion: at most one source's content is shown
  // at a time (spec §11.1's single global "Search control" only makes
  // sense scoped to one source at a time, since TafsirRepository.search
  // takes a sourceId — see spec §11.2).
  String? _expandedSourceId;

  late final Future<List<TafsirSource>> _sourcesFuture =
      widget.tafsirRepository.getSources();

  final TextEditingController _searchController = TextEditingController();
  Future<List<TafsirEntry>>? _searchFuture;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _stepAyah(int direction) async {
    final parts = _ayahKey.split(':');
    int surahId = int.parse(parts[0]);
    int ayahNumber = int.parse(parts[1]);
    if (direction > 0) {
      final Surah surah = await widget.quranRepository.getSurah(surahId);
      if (ayahNumber < surah.ayahCount) {
        ayahNumber += 1;
      } else if (surahId < 114) {
        surahId += 1;
        ayahNumber = 1;
      } else {
        return; // Already at 114:6 — no next ayah.
      }
    } else {
      if (ayahNumber > 1) {
        ayahNumber -= 1;
      } else if (surahId > 1) {
        surahId -= 1;
        final Surah previousSurah = await widget.quranRepository.getSurah(
          surahId,
        );
        ayahNumber = previousSurah.ayahCount;
      } else {
        return; // Already at 1:1 — no previous ayah.
      }
    }
    _goToAyah('$surahId:$ayahNumber');
  }

  void _goToAyah(String ayahKey) {
    if (!mounted) return;
    setState(() {
      _ayahKey = ayahKey;
      _searchFuture = null;
      _searchController.clear();
    });
    widget.quranReaderProvider.selectAyahKey(ayahKey);
  }

  void _runSearch(String sourceId) {
    final String query = _searchController.text.trim();
    setState(() {
      _searchFuture = query.isEmpty
          ? null
          : widget.tafsirRepository.search(sourceId, query);
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<String> parts = _ayahKey.split(':');
    final int surahId = int.parse(parts[0]);
    final int ayahNumber = int.parse(parts[1]);
    final bool canGoPrevious = !(surahId == 1 && ayahNumber == 1);
    final bool canGoNext = !(surahId == 114 && ayahNumber == 6);

    return Scaffold(
      backgroundColor: mushafPageColor,
      appBar: AppBar(
        backgroundColor: mushafPageColor,
        foregroundColor: mushafInkColor,
        elevation: 0,
        title: const Text('التفسير'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.menu_book_outlined, color: mushafInkColor),
            label: const Text(
              'العودة إلى المصحف',
              style: TextStyle(color: mushafInkColor),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _SelectedAyahHeader(
              key: ValueKey(_ayahKey),
              ayahKey: _ayahKey,
              repository: widget.quranRepository,
            ),
            _AyahNavigationRow(
              onPrevious: canGoPrevious ? () => _stepAyah(-1) : null,
              onNext: canGoNext ? () => _stepAyah(1) : null,
            ),
            _FontSizeControl(
              fontSize: _fontSize,
              onChanged: (value) => setState(() => _fontSize = value),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<TafsirSource>>(
                future: _sourcesFuture,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('خطأ: ${snapshot.error}'));
                  }
                  final sources = snapshot.data;
                  if (sources == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return ListView(
                    children: [
                      for (final source in sources)
                        _SourceAccordionSection(
                          key: ValueKey('${source.sourceId}:$_ayahKey'),
                          source: source,
                          ayahKey: _ayahKey,
                          fontSize: _fontSize,
                          tafsirRepository: widget.tafsirRepository,
                          expanded: _expandedSourceId == source.sourceId,
                          onToggle: () => setState(() {
                            final bool wasExpanded =
                                _expandedSourceId == source.sourceId;
                            _expandedSourceId = wasExpanded
                                ? null
                                : source.sourceId;
                            _searchFuture = null;
                            _searchController.clear();
                          }),
                          searchController: _searchController,
                          searchFuture: _expandedSourceId == source.sourceId
                              ? _searchFuture
                              : null,
                          onSearchSubmitted: () => _runSearch(source.sourceId),
                          onSearchResultTap: (entry) =>
                              _goToAyah(entry.ayahKey),
                        ),
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('العودة إلى المصحف'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Selected Ayah header" (spec §11.1): surah name + ayah number, plus the
/// ayah's own text for context (this screen replaces the Mushaf page
/// entirely rather than floating over it, unlike the Ayah Context Sheet,
/// so the ayah text isn't visible behind it otherwise).
class _SelectedAyahHeader extends StatefulWidget {
  const _SelectedAyahHeader({super.key, required this.ayahKey, required this.repository});

  final String ayahKey;
  final QuranRepository repository;

  @override
  State<_SelectedAyahHeader> createState() => _SelectedAyahHeaderState();
}

class _SelectedAyahHeaderState extends State<_SelectedAyahHeader> {
  late final Future<
      (Surah surah, int ayahNumber, List<Word> words, Map<int, int> pageByWordIndex)
  > _future = _load();

  Future<(Surah, int, List<Word>, Map<int, int>)> _load() async {
    final parts = widget.ayahKey.split(':');
    final surahId = int.parse(parts[0]);
    final ayahNumber = int.parse(parts[1]);
    final surah = await widget.repository.getSurah(surahId);
    final words = await widget.repository.getWords(widget.ayahKey);
    final pageByWordIndex = await widget.repository
        .getPageNumbersForWordIndexes([for (final w in words) w.wordIndex]);
    return (surah, ayahNumber, words, pageByWordIndex);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(Surah, int, List<Word>, Map<int, int>)>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final (surah, ayahNumber, words, pageByWordIndex) = data;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              Text(
                '${surah.nameArabic} • آية $ayahNumber',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: mushafInkColor,
                ),
              ),
              const SizedBox(height: 8),
              QuranAyahText(words: words, pageByWordIndex: pageByWordIndex),
            ],
          ),
        );
      },
    );
  }
}

class _AyahNavigationRow extends StatelessWidget {
  const _AyahNavigationRow({required this.onPrevious, required this.onNext});

  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // RTL content: "previous" (toward ayah 1) reads as the right-facing
        // arrow, "next" as the left-facing one — matching how the Mushaf
        // reader's own RTL page navigation already reads (mushaf_reader_
        // screen.dart's _ReaderPageView doc comment).
        IconButton(
          tooltip: 'الآية السابقة',
          onPressed: onPrevious,
          icon: const Icon(Icons.arrow_forward),
        ),
        const Text('الآية', style: TextStyle(color: mushafInkColor)),
        IconButton(
          tooltip: 'الآية التالية',
          onPressed: onNext,
          icon: const Icon(Icons.arrow_back),
        ),
      ],
    );
  }
}

class _FontSizeControl extends StatelessWidget {
  const _FontSizeControl({required this.fontSize, required this.onChanged});

  final double fontSize;
  final ValueChanged<double> onChanged;

  static const double _min = 14;
  static const double _max = 28;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.text_decrease, color: mushafInkColor, size: 18),
          Expanded(
            child: Slider(
              value: fontSize.clamp(_min, _max),
              min: _min,
              max: _max,
              divisions: 7,
              label: fontSize.toStringAsFixed(0),
              onChanged: onChanged,
            ),
          ),
          const Icon(Icons.text_increase, color: mushafInkColor, size: 18),
        ],
      ),
    );
  }
}

/// One accordion section: a tappable source header (name + author) and,
/// when [expanded], that source's content for the current ayah plus a
/// search box scoped to this source (spec §11.1's "Search control").
class _SourceAccordionSection extends StatelessWidget {
  const _SourceAccordionSection({
    super.key,
    required this.source,
    required this.ayahKey,
    required this.fontSize,
    required this.tafsirRepository,
    required this.expanded,
    required this.onToggle,
    required this.searchController,
    required this.searchFuture,
    required this.onSearchSubmitted,
    required this.onSearchResultTap,
  });

  final TafsirSource source;
  final String ayahKey;
  final double fontSize;
  final TafsirRepository tafsirRepository;
  final bool expanded;
  final VoidCallback onToggle;
  final TextEditingController searchController;
  final Future<List<TafsirEntry>>? searchFuture;
  final VoidCallback onSearchSubmitted;
  final ValueChanged<TafsirEntry> onSearchResultTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: mushafInkColor,
                        ),
                      ),
                      if (source.author != null)
                        Text(
                          source.author!,
                          style: TextStyle(
                            fontSize: 12,
                            color: mushafInkColor.withValues(alpha: 0.6),
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  color: mushafInkColor,
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => onSearchSubmitted(),
                  decoration: InputDecoration(
                    hintText: 'ابحث في ${source.name}...',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                if (searchFuture != null)
                  _SearchResultsList(
                    future: searchFuture!,
                    onResultTap: onSearchResultTap,
                  )
                else
                  _SourceContent(
                    sourceId: source.sourceId,
                    ayahKey: ayahKey,
                    fontSize: fontSize,
                    tafsirRepository: tafsirRepository,
                  ),
              ],
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }
}

class _SearchResultsList extends StatelessWidget {
  const _SearchResultsList({required this.future, required this.onResultTap});

  final Future<List<TafsirEntry>> future;
  final ValueChanged<TafsirEntry> onResultTap;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TafsirEntry>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text('خطأ: ${snapshot.error}');
        }
        final results = snapshot.data;
        if (results == null) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (results.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'لا توجد نتائج.',
              style: TextStyle(color: mushafInkColor),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in results)
              ListTile(
                dense: true,
                title: Text(
                  entry.isMultiAyahGroup
                      ? 'الآيات ${entry.groupAyahStart} - ${entry.groupAyahEnd}'
                      : 'الآية ${entry.ayahKey}',
                  style: const TextStyle(color: mushafInkColor),
                ),
                subtitle: Text(
                  stripTafsirHtml(entry.content ?? ''),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => onResultTap(entry),
              ),
          ],
        );
      },
    );
  }
}

/// One source's tafsir text for [ayahKey] (spec §11.1's "Source Content"),
/// resolved through the group reference already (spec §11) — the caller
/// never has to know whether [ayahKey] is a group's owning ayah or a
/// member.
class _SourceContent extends StatelessWidget {
  const _SourceContent({
    required this.sourceId,
    required this.ayahKey,
    required this.fontSize,
    required this.tafsirRepository,
  });

  final String sourceId;
  final String ayahKey;
  final double fontSize;
  final TafsirRepository tafsirRepository;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TafsirEntry>(
      future: tafsirRepository.getEntry(sourceId, ayahKey),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text('خطأ: ${snapshot.error}');
        }
        final entry = snapshot.data;
        if (entry == null) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final content = entry.content;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry.isMultiAyahGroup)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'تفسير الآيات ${entry.groupAyahStart} - ${entry.groupAyahEnd}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: mushafInkColor.withValues(alpha: 0.7),
                  ),
                ),
              ),
            Text(
              content == null
                  ? 'لا يوجد تفسير مستقل لهذه الآية في هذا المصدر.'
                  : stripTafsirHtml(content),
              style: TextStyle(
                fontSize: fontSize,
                height: 1.6,
                color: mushafInkColor,
                fontStyle: content == null ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ],
        );
      },
    );
  }
}
