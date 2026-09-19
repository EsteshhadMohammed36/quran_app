import 'package:flutter/material.dart';

import '../../../shared/theme/mushaf_theme.dart';
import '../../quran_reader/domain/word.dart';
import '../../quran_reader/presentation/qpc_v2_fonts.dart';
import '../domain/morphology_entry.dart';
import '../domain/morphology_repository.dart';

/// The "الصرف" (Morphology, spec §12) study tab's real content: every word
/// in the ayah alongside its root/lemma/stem (spec §12.2: "Word list /
/// analysis -> show Word, Root, Lemma, Stem, Part of Speech, Grammar tags
/// (when available)"). A horizontally-scrolling strip of per-word cards
/// rather than a vertical list — keeps the sheet's height bounded
/// regardless of ayah length, since the outer sheet Column sizes to its
/// content (spec §10's compact-panel shape) and an unbounded vertical list
/// here would risk overflowing the screen on a long ayah.
///
/// [words]/[pageByWordIndex] are the same ayah data the sheet's header
/// already loaded (see `_AyahData` in `ayah_context_sheet.dart`) — reused
/// here so each word's glyph renders with its own page's QCF font (spec
/// §7), exactly like `QuranAyahText` does, rather than fetching/deriving it
/// twice. [words] may include the ayah-end ornament row (`Word
/// .isAyahEndMarker`) — this widget filters it out before building cards,
/// since it isn't a real Quran word and has no morphology of its own.
class MorphologyTabContent extends StatefulWidget {
  const MorphologyTabContent({
    super.key,
    required this.ayahKey,
    required this.words,
    required this.pageByWordIndex,
    required this.morphologyRepository,
  });

  final String ayahKey;
  final List<Word> words;
  final Map<int, int> pageByWordIndex;
  final MorphologyRepository morphologyRepository;

  @override
  State<MorphologyTabContent> createState() => _MorphologyTabContentState();
}

class _MorphologyTabContentState extends State<MorphologyTabContent> {
  // Computed once per widget lifetime — see GrammarTabContent's identical
  // fix (spec §21 performance pass, 2026-09-19) for why calling the
  // repository directly as `FutureBuilder`'s `future` argument is a bug,
  // not just a style nit: it re-queries SQLite on every ancestor rebuild,
  // not just when the ayah changes.
  late final Future<List<MorphologyEntry>> _entriesFuture =
      widget.morphologyRepository.getEntriesForAyah(widget.ayahKey);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MorphologyEntry>>(
      future: _entriesFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text('خطأ: ${snapshot.error}')),
          );
        }
        final entries = snapshot.data;
        if (entries == null) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final Map<int, MorphologyEntry> entryByPosition = {
          for (final e in entries) e.wordPosition: e,
        };
        // Exclude the ayah-end ornament ("end_marker" — see `Word
        // .isAyahEndMarker`'s doc comment): it's a real row in `words`
        // because the Mushaf line must render it, but it isn't a Quran
        // word, so it must never get its own morphology card here. Fixed
        // at the source (Word.wordType, computed once during ingestion),
        // not by guessing from position/content in this widget.
        final List<Word> realWords =
            widget.words.where((w) => !w.isAyahEndMarker).toList();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Height picked to fit each card's tallest real content (word
            // glyph + divider + 5 label/value field rows) without its own
            // internal overflow — 260 clipped ~20px off the last field row
            // (found via test/morphology_tab_scroll_test.dart, which
            // exercises this with populated root/lemma/stem/POS/grammar-tag
            // values, not just a couple of short fields).
            SizedBox(
              height: 300,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                // RTL reading order: first word starts at the right edge.
                reverse: true,
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                itemCount: realWords.length,
                itemBuilder: (context, index) {
                  final word = realWords[index];
                  final pageNumber = widget.pageByWordIndex[word.wordIndex];
                  return MorphologyWordCard(
                    word: word,
                    fontFamily: pageNumber == null
                        ? null
                        : fontFamilyForPage(pageNumber),
                    entry: entryByPosition[word.wordPosition],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class MorphologyWordCard extends StatelessWidget {
  const MorphologyWordCard({
    super.key,
    required this.word,
    required this.fontFamily,
    required this.entry,
  });

  final Word word;
  final String? fontFamily;
  final MorphologyEntry? entry;

  @override
  Widget build(BuildContext context) {
    Widget field(String label, String? value) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: mushafInkColor.withValues(alpha: 0.5),
              ),
            ),
            Text(
              value ?? '—',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: value == null ? FontWeight.normal : FontWeight.bold,
                color:
                    mushafInkColor.withValues(alpha: value == null ? 0.4 : 1.0),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: 116,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: mushafInkColor.withValues(alpha: 0.15)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Directionality(
            textDirection: TextDirection.rtl,
            child: Text(
              word.text,
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: 22,
                color: mushafInkColor,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Divider(height: 1),
          field('الجذر', entry?.root),
          field('الأصل', entry?.lemma),
          field('الجذع', entry?.stem),
          field('نوع الكلمة', entry?.partOfSpeech),
          field('الوسوم النحوية', entry?.grammarTags),
        ],
      ),
    );
  }
}
