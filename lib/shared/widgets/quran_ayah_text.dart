import 'package:flutter/material.dart';

import '../../features/quran_reader/domain/word.dart';
import '../../features/quran_reader/presentation/qpc_v2_fonts.dart';
import '../theme/mushaf_theme.dart';

/// Renders a list of ayah words outside the Mushaf page itself (e.g. the
/// Ayah Context Sheet, the Tafsir screen's "Selected Ayah" header) — a
/// normal wrapping paragraph, not the Mushaf's own fixed line structure
/// (rule #2 only governs the Mushaf page renderer itself, not other UI
/// surfaces showing the same ayah as a contextual excerpt).
///
/// Each word is rendered with *its own page's* QCF font (spec §7) — a
/// page-boundary ayah's words can come from two different page fonts,
/// never assumed to share one. [words] and [pageByWordIndex] are exactly
/// what [QuranRepository.getWords]/[QuranRepository.getPageNumbersForWordIndexes]
/// return; this widget does no data fetching itself.
///
/// Extracted from `AyahContextSheet` (Prompt 10) into `shared/widgets` when
/// the Tafsir screen (Prompt 11) needed the identical rendering — sharing
/// one implementation avoids two copies of this Quran-text-rendering logic
/// silently diverging.
class QuranAyahText extends StatelessWidget {
  const QuranAyahText({
    super.key,
    required this.words,
    required this.pageByWordIndex,
    this.fontSize = 26,
    this.height = 1.8,
    this.highlightedWordKey,
  });

  final List<Word> words;
  final Map<int, int> pageByWordIndex;
  final double fontSize;
  final double height;

  /// When set, the word whose [Word.wordKey] matches gets a highlighted
  /// background — driven by [AudioProvider.currentWordKey] during
  /// recitation playback (spec §10/§14's "Optional synchronized
  /// highlight"). Purely a presentation-layer background color; the
  /// glyph text itself is never touched (rule #1).
  final String? highlightedWordKey;

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      final pageNumber = pageByWordIndex[word.wordIndex];
      final bool isHighlighted =
          highlightedWordKey != null && word.wordKey == highlightedWordKey;
      spans.add(
        TextSpan(
          text: word.text,
          style: TextStyle(
            fontFamily: pageNumber == null
                ? null
                : fontFamilyForPage(pageNumber),
            fontSize: fontSize,
            height: height,
            color: mushafInkColor,
            backgroundColor: isHighlighted
                ? mushafInkColor.withValues(alpha: 0.15)
                : null,
          ),
        ),
      );
      if (i != words.length - 1) spans.add(const TextSpan(text: ' '));
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Text.rich(TextSpan(children: spans), textAlign: TextAlign.center),
    );
  }
}
