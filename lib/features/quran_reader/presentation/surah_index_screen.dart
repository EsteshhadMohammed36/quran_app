import 'package:flutter/material.dart';

import '../../../shared/theme/mushaf_theme.dart';
import '../domain/quran_repository.dart';
import '../domain/surah.dart';

/// "فهرس السور" — a full list of the 114 surahs by Arabic name, tap-to-jump
/// straight to a surah's opening page (spec §3: "Surah, Juz, Hizb and page
/// navigation"). Reuses [QuranRepository]/[Surah] from `quran_reader`
/// itself rather than a new feature module — this screen needs nothing
/// beyond the existing `surahs`/`mushaf_lines` tables already exposed there
/// (CLAUDE.md rule #4: one canonical source, no new table for this).
///
/// [MushafReaderScreen] owns the `PageController` needed to actually move
/// the reader, so — same pattern as [SavedItemsScreen]/[SearchScreen] —
/// this screen only reports which page was tapped via [onSurahTap] and lets
/// the caller pop it and jump.
class SurahIndexScreen extends StatefulWidget {
  const SurahIndexScreen({
    super.key,
    required this.quranRepository,
    required this.onSurahTap,
  });

  final QuranRepository quranRepository;

  /// Called with the surah's first Mushaf page number.
  final void Function(int pageNumber) onSurahTap;

  @override
  State<SurahIndexScreen> createState() => _SurahIndexScreenState();
}

class _SurahIndexScreenState extends State<SurahIndexScreen> {
  late final Future<
    (List<Surah> surahs, Map<int, int> firstPageBySurahId)
  >
  _future = _load();

  Future<(List<Surah>, Map<int, int>)> _load() async {
    final surahs = await widget.quranRepository.getAllSurahs();
    final firstPageBySurahId = await widget.quranRepository
        .getFirstPageNumbersForSurahs();
    return (surahs, firstPageBySurahId);
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
          title: const Text('فهرس السور'),
        ),
        body: FutureBuilder<(List<Surah>, Map<int, int>)>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('تعذر تحميل الفهرس: ${snapshot.error}'),
                ),
              );
            }
            final data = snapshot.data;
            if (data == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final (surahs, firstPageBySurahId) = data;
            return ListView.separated(
              itemCount: surahs.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final surah = surahs[index];
                final int? pageNumber = firstPageBySurahId[surah.surahId];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: mushafPageColor,
                    foregroundColor: mushafInkColor,
                    child: Text('${surah.surahId}'),
                  ),
                  title: Text(
                    surah.nameArabic,
                    style: const TextStyle(
                      color: mushafInkColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    '${surah.ayahCount} آية'
                    '${surah.revelationPlace != null ? ' · ${surah.revelationPlace}' : ''}',
                    style: const TextStyle(color: Color(0x991A1005)),
                  ),
                  trailing: pageNumber != null
                      ? Text(
                          'ص $pageNumber',
                          style: const TextStyle(color: Color(0x991A1005)),
                        )
                      : null,
                  onTap: pageNumber != null
                      ? () => widget.onSurahTap(pageNumber)
                      : null,
                );
              },
            );
          },
        ),
      ),
    );
  }
}
