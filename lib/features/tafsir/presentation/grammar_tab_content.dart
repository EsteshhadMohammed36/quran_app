import 'package:flutter/material.dart';

import '../../../shared/theme/mushaf_theme.dart';
import '../domain/tafsir_entry.dart';
import '../domain/tafsir_repository.dart';
import '../domain/tafsir_source.dart';
import 'tafsir_html_text.dart';

/// The "الإعراب" (Grammar/I'rab, spec §13) study tab's real content:
/// Iraab Al-Muyassar's entry for the selected ayah, read straight from the
/// tafsir module's own repository/table (see [iraabMuyassarSourceId]) — spec
/// §13 requires this to stay a distinct data source from both Tafsir's own
/// screen and from Morphology, and to name that source explicitly, which
/// this widget does via its header line.
///
/// Lives under `tafsir/presentation`, not a dedicated `grammar` feature:
/// there is no separate grammar domain/data layer (CLAUDE.md rule #4 — this
/// is the same already-ingested i'rab data spec §13 wants, not a second
/// dataset), so the widget's only real dependency is [TafsirRepository].
class GrammarTabContent extends StatefulWidget {
  const GrammarTabContent({
    super.key,
    required this.ayahKey,
    required this.tafsirRepository,
  });

  final String ayahKey;
  final TafsirRepository tafsirRepository;

  @override
  State<GrammarTabContent> createState() => _GrammarTabContentState();
}

class _GrammarTabContentState extends State<GrammarTabContent> {
  // Computed once per widget lifetime, not inline in `build()` — spec §21
  // performance pass (2026-09-19): this used to call
  // `tafsirRepository.getEntry(...)` directly as `FutureBuilder`'s `future`
  // argument, which re-issues the query on *every* rebuild, not just when
  // the ayah changes. Since the Ayah Context Sheet rebuilds this tab's
  // ancestor tree on unrelated provider notifications too (found via audio
  // playback ticking `AudioProvider` several times a second — see
  // `_HighlightedAyahText` in `ayah_context_sheet.dart`), that meant this
  // tab re-hit SQLite and flickered its loading spinner over real content
  // multiple times a second whenever it was the open tab during playback.
  late final Future<TafsirEntry> _entryFuture = widget.tafsirRepository
      .getEntry(iraabMuyassarSourceId, widget.ayahKey);

  @override
  Widget build(BuildContext context) {
    // This Column's `crossAxisAlignment: .start`/each Text's default
    // TextAlign both resolve relative to *ambient* Directionality, not the
    // Arabic script itself — and the app never sets one globally (no
    // `locale`/`supportedLocales` on MaterialApp, so it defaults to LTR),
    // unlike every other Arabic text block in the app (QuranAyahText,
    // MushafReaderScreen, MorphologyTabContent), which each wrap
    // themselves in an explicit `Directionality.rtl` for this exact
    // reason. This one was missing it, so "start" meant the *left* edge —
    // the i'rab paragraph rendered left-aligned (user-reported, 2026-09-13:
    // "الكتابة ف تاب الاعراب مكتوبة من الشمال ... خليها من اليمين").
    return Directionality(
      textDirection: TextDirection.rtl,
      child: FutureBuilder<TafsirEntry>(
        future: _entryFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('خطأ: ${snapshot.error}')),
            );
          }
          final entry = snapshot.data;
          if (entry == null) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final content = entry.content;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.isMultiAyahGroup
                      ? 'الإعراب الميسر • الآيات ${entry.groupAyahStart} - '
                          '${entry.groupAyahEnd}'
                      : ' ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: mushafInkColor.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  content == null
                      ? 'لا يوجد إعراب مستقل لهذه الآية في هذا المصدر.'
                      : stripTafsirHtml(content),
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.6,
                    color: mushafInkColor,
                    fontStyle:
                        content == null ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
