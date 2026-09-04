import 'package:flutter/material.dart';

import '../../../shared/theme/mushaf_theme.dart';
import '../domain/mushaf_line.dart';
import '../domain/mushaf_page.dart';
import '../domain/word.dart';
import 'qpc_v2_fonts.dart';
import 'surah_header_ligatures.dart';

/// Renders a [MushafPage] exactly as its line structure dictates.
///
/// CLAUDE.md rule #2: this is a fixed stack of lines, never a reflowing
/// paragraph. Each line is forced onto a single physical line and scaled
/// down to fit the available width if needed (spec §6.3: "Responsive
/// behavior should scale the page/typography ... rather than reflowing
/// the Quran into an arbitrary paragraph layout") — it is never allowed to
/// wrap onto a second line.
class MushafPageView extends StatelessWidget {
  final MushafPage page;

  /// `surah:ayah` of the currently selected ayah, or `null` if none is
  /// selected. Every word belonging to it gets highlighted (rule #3: ayah
  /// selection is semantic, never word-level).
  final String? selectedAyahKey;

  /// Called with the tapped [Word] (spec §9: tap -> resolve word ->
  /// resolve `surah:ayah` -> select the whole ayah). `null` (the default)
  /// makes the page non-interactive, e.g. for [MushafPrototypeScreen]
  /// which only needs to validate rendering, not hit testing.
  final ValueChanged<Word>? onWordTap;

  /// Called when a tap lands somewhere on the page that isn't a word —
  /// blank margins, the surah-header banner, a basmallah line, or the gap
  /// between two words (spec §9.1 "Outside tap -> dismiss selection").
  final VoidCallback? onBackgroundTap;

  const MushafPageView({
    super.key,
    required this.page,
    this.selectedAyahKey,
    this.onWordTap,
    this.onBackgroundTap,
  });

  @override
  Widget build(BuildContext context) {
    // One GlobalKey per *ayah* line (null for basmallah/surah_name), so a
    // single page-level tap handler can measure exactly which line (if
    // any) was tapped and resolve the word within it via _wordAt below.
    //
    // Deliberately ONE GestureDetector for the whole page rather than a
    // TapGestureRecognizer per word: Flutter's gesture arena does not
    // automatically suppress a second, independent tap recognizer that
    // also contains the same point (nested GestureDetectors/TextSpan
    // recognizers sharing a point can both fire) — a real risk once this
    // widget also needs "tap elsewhere clears selection" (spec §9.1)
    // alongside per-word selection. A single detector doing its own hit
    // testing sidesteps that arena-conflict class of bug entirely.
    final List<GlobalKey?> ayahTextKeys = [
      for (final line in page.lines)
        line.lineType == MushafLineType.ayah ? GlobalKey() : null,
    ];

    void handleTapUp(TapUpDetails details) {
      for (var i = 0; i < page.lines.length; i++) {
        final key = ayahTextKeys[i];
        if (key == null) continue;
        final renderObject = key.currentContext?.findRenderObject();
        if (renderObject is! RenderBox || !renderObject.attached) continue;

        final local = renderObject.globalToLocal(details.globalPosition);
        final withinBounds =
            local.dx >= 0 &&
            local.dy >= 0 &&
            local.dx <= renderObject.size.width &&
            local.dy <= renderObject.size.height;
        if (!withinBounds) continue;

        final line = page.lines[i];
        final word = _wordAt(
          context: context,
          words: line.words,
          fontFamily: fontFamilyForPage(line.pageNumber),
          localPosition: local,
        );
        if (word != null) {
          onWordTap?.call(word);
        } else {
          onBackgroundTap?.call();
        }
        return;
      }
      // Tap didn't land inside any ayah line's text box at all (margins,
      // a surah_name banner, a basmallah line, ...).
      onBackgroundTap?.call();
    }

    // Every page fills the full page surface and spaces lines evenly
    // across it (Expanded per line), matching how an ordinary printed
    // Mushaf page always fills its physical height regardless of how many
    // of the 15 line slots it actually uses. Page 1 (Al-Fatiha) used to be
    // exempted from this — kept at its natural, compact top-aligned size
    // as a "title page" (user's explicit call, 2026-08-31) — but with only
    // ~8 lines total that left a large dead-white block at the bottom of
    // the screen and read as pushed-up rather than balanced, so the user
    // asked for it to spread and distribute like every other page instead
    // (2026-09-03, supersedes the 2026-08-31 decision). The ayah lines'
    // own FittedBox still uses BoxFit.scaleDown (never enlarges past its
    // natural fontSize), so this only changes how much empty space sits
    // *around* each line, not the glyph size itself.
    //
    // surah_name rows get a *fixed* height (`_surahNameRowHeight` below)
    // instead of a relative Expanded flex share, and only ayah/basmallah
    // rows are Expanded (Flutter's flex layout is fine mixing the two: the
    // fixed-size children are laid out first, and Expanded children split
    // whatever height is left over). A relative flex share made the
    // Al-Fatiha banner render visibly bigger than every other surah's
    // banner (user flagged this, 2026-09-03, right after the page-1-spread
    // change above): with a flex share, a banner's slot height depends on
    // *how many other lines share the page with it* — Al-Fatiha only has
    // ~8 lines total vs. the standard 15, so its banner's flex share of
    // the page came out roughly double. Pinning to a fixed height makes
    // every surah_name row the same size everywhere, regardless of how
    // many lines its own page happens to have.
    return Directionality(
      textDirection: TextDirection.rtl,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (onWordTap == null && onBackgroundTap == null)
            ? null
            : handleTapUp,
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            for (var i = 0; i < page.lines.length; i++)
              page.lines[i].lineType == MushafLineType.surahName
                  ? SizedBox(
                      height: _surahNameRowHeight(context),
                      child: _MushafLineView(line: page.lines[i]),
                    )
                  : Expanded(
                      flex: page.lines[i].lineType == MushafLineType.surahName
                          ? 13
                          : 10,
                      child: _MushafLineView(
                        line: page.lines[i],
                        selectedAyahKey: selectedAyahKey,
                        textKey: ayahTextKeys[i],
                      ),
                    ),
          ],
        ),
      ),
    );
  }

  // A standard 15-line Mushaf page (e.g. page 601/604, each with 3
  // surah_name rows) has 12 flex:1 ayah/basmallah rows + 3 surah_name rows;
  // giving surah_name flex:2 there meant each surah_name row got 2/18 of
  // the page (flex sum 12×1 + 3×2 = 18). That 2/18 fraction is the already
  // user-approved banner size (verified on-device on pages 1/601/604), so
  // it's reused here as a fixed fraction of the screen height, independent
  // of the current page's own line count — pinning Al-Fatiha's banner to
  // the exact same size as every other page's instead of a size that
  // depends on how many lines happen to share its page.
  double _surahNameRowHeight(BuildContext context) =>
      MediaQuery.of(context).size.height * (2 / 18);
}

class _MushafLineView extends StatelessWidget {
  final MushafLine line;
  final String? selectedAyahKey;

  /// Attached to the ayah-line [Text.rich] only, so [MushafPageView]'s
  /// single tap handler can locate this exact render box for hit testing.
  final GlobalKey? textKey;

  const _MushafLineView({
    required this.line,
    this.selectedAyahKey,
    this.textKey,
  });

  @override
  Widget build(BuildContext context) {
    final String? pageFontFamily = fontFamilyForPage(line.pageNumber);
    late final Widget content;

    switch (line.lineType) {
      case MushafLineType.ayah:
        // Per-word spans joined by a plain space, same unmodified word
        // glyph strings concatenation as before (rule #1: no
        // character-level transformation of the Quran text itself) — only
        // now built as separate spans so each word can carry its own
        // highlight, instead of one opaque Text blob. Splitting into
        // same-style spans doesn't change the rendered glyphs: QCF words
        // are already fully composed per-word artwork joined by a literal
        // space, with no cross-word shaping/kerning to preserve. Tap
        // resolution itself happens one level up (MushafPageView._wordAt),
        // not via a recognizer on these spans — see that class's doc
        // comment for why.
        content = Text.rich(
          key: textKey,
          _buildAyahSpan(
            words: line.words,
            baseStyle: _ayahTextStyle(pageFontFamily),
            selectedAyahKey: selectedAyahKey,
          ),
          maxLines: 1,
          softWrap: false,
        );
      case MushafLineType.basmallah:
        // Always surah 1 ayah 1's real words/font, not this page's own
        // font — see qpc_v2_fonts.dart doc comment on qcfBasmallahFontFamily.
        final text = line.words.map((w) => w.text).join(' ');
        content = Text(
          text,
          style: const TextStyle(
            fontFamily: qcfBasmallahFontFamily,
            fontSize: 28,
            height: 1.0,
            color: mushafInkColor,
          ),
          maxLines: 1,
          softWrap: false,
        );
      case MushafLineType.surahName:
        // The dedicated per-surah decorative ligature glyph (from the
        // surah-header font, surah_header_ligatures.dart) already draws
        // "سورة <name>" as one ornate banner, framed exactly like a real
        // printed Mushaf's surah header — checked visually, not assumed
        // (an earlier version of this code prepended a separate "سورة "
        // text span before noticing the glyph already includes it).
        // Neither the page-specific QCFxxx font nor plain system text can
        // give surah_name lines this real Mushaf calligraphy (user's
        // explicit request, 2026-08-31).
        final String? ligature = line.surah == null
            ? null
            : surahHeaderLigatureByNumber[line.surah!.surahId];
        content = Text(
          ligature ?? line.surah?.nameArabic ?? '',
          style: const TextStyle(
            // NOTE: this fontSize is moot for on-screen size — the
            // FittedBox below uses BoxFit.fill for surah_name lines,
            // which stretches to the target box regardless of the
            // child's intrinsic size, so changing this number alone
            // has no visible effect. See `bannerScale` below for the
            // value that actually controls the rendered size.
            fontFamily: surahHeaderFontFamily,
            fontSize: 66,
            height: 1.0,
          ),
          maxLines: 1,
          softWrap: false,
        );
      // No highlight box behind it: the ligature is a self-contained COLR
      // glyph that already draws its own ornate frame (see comment above),
      // so painting a Material "surfaceContainerHighest" band behind it
      // (an earlier version did) just adds a mismatched grey seam wider
      // than the glyph's own frame — a real Mushaf's banner sits flush on
      // the page.
    }

    // On the standard 15-line pages every line gets an equal Expanded share
    // of the page height (see MushafPageView above). Vertical padding is
    // still trimmed for surah_name lines (kept at the ayah-line default
    // otherwise) so the banner isn't squeezed any smaller than it needs to
    // be within that fixed slot.
    final bool isSurahName = line.lineType == MushafLineType.surahName;
    // No `alignment:` on this Container: Container converts a non-null
    // alignment into an inner Align, and Align always *loosens* the
    // constraints it passes to its child (min -> 0) — which meant the
    // FittedBox below was only ever given a loose max-width, so it just
    // hugged the ligature's natural (unstretched) size and BoxFit.fill had
    // nothing to stretch into (verified directly: a debug ColoredBox around
    // the FittedBox showed its box was already exactly the glyph's own
    // width, not the container's). `width: double.infinity` here keeps the
    // width tight all the way down to the FittedBox instead; alignment is
    // now done by FittedBox's own `alignment` param, which works the same
    // regardless of tight/loose constraints.
    // Same responsive box height for every line type (scales with screen
    // width via MediaQuery, never a hardcoded px value): the equal-share
    // slot every line already gets on the 15-line pages (see
    // MushafPageView above). surah_name's own font bakes a lot of white
    // space/framing into its glyph box (measured on-device: at an equal
    // nominal size its visible ink is well under half the ayah font's),
    // so instead of shrinking surah_name into some smaller measured box
    // — which only makes that gap worse — it gets the full slot height
    // like every other line, and BoxFit.fill (below) stretches its ink
    // to actually use all of it, both directions. That's the largest a
    // surah_name banner can get without overlapping the line above/below
    // it — the printed page's fixed 15-line grid (rule #2) leaves no
    // room to grow beyond one slot no matter how it's scaled.
    //final double slotHeight = MediaQuery.of(context).size.width * 0.4;

    Widget fitted = FittedBox(
      // surah_name: BoxFit.fill stretches the banner to fill its full
      // slot in both directions — full line width (user's explicit
      // choice, kept as-is) and full slot height (today's request for
      // a clearly bigger, more prominent banner). Every other line
      // type keeps BoxFit.scaleDown, unchanged.
      fit: isSurahName ? BoxFit.fill : BoxFit.scaleDown,
      alignment: Alignment.center,
      child: content,
    );

    if (isSurahName) {
      // Even after BoxFit.fill, the banner still read with visible empty
      // space above/below it inside its slot (user flagged this,
      // 2026-09-03). Root-caused with a temporary debug ColoredBox around
      // this exact FittedBox, screenshotted on-device on page 601, then
      // pixel-scanned (adb screencap + a small script): the *slot* itself
      // (the green debug tint) really was being filled edge-to-edge as
      // intended, but the ligature's own ink (the frame + "سورة <name>"
      // text — measured as the dark pixel band, consistent across two
      // different surah banners: 119px ink / 306px slot and 120px / 307px)
      // only occupies ~39% of that filled box's height. That's the same
      // "font bakes in a lot of white space" issue already noted above,
      // just quantified now: BoxFit.fill scales the *whole* glyph box
      // (ink + the font's own baked-in vertical padding) uniformly, so the
      // baked-in padding grows right along with the ink instead of
      // disappearing — confirming this is a font-metrics artifact, not a
      // padding/margin bug in this widget's own layout.
      // Fix: apply an *extra* vertical-only stretch on top of the already
      // fully-filled box (1 / 0.39 ≈ 2.56, from the on-device measurement
      // above — an intrinsic property of this one font file, effectively
      // constant across all 114 ligatures since it's the shared frame
      // artwork, not the per-surah text, that sets the ink's vertical
      // extent), then clip back down to the slot's own bounds. Horizontal
      // scale is left untouched (Matrix4 diagonal, X factor 1.0) — the
      // same pixel scan found ink already spanning ~29px to ~1049px of a
      // 1080px-wide screenshot at this line, i.e. already edge-to-edge
      // (modulo this widget's own 8dp horizontal padding), so there's no
      // matching horizontal gap to correct.
      //
      // `bannerScale` (2026-09-03 pt.5, user's request to make the banner
      // "slightly smaller"): the `fontSize: 66` above was tried as the
      // sizing lever first (dropped to 30) and had *zero* visible effect.
      // Root cause: `fontSize` only sets the surah_name Text's own
      // intrinsic/natural size, but the FittedBox above uses
      // `BoxFit.fill` (surah_name only) — and `fill`, unlike `scaleDown`/
      // `contain`, does not scale *relative to* the child's natural size
      // at all; it unconditionally stretches whatever child it's given,
      // non-uniformly per axis, to exactly match its target box (here:
      // the full line width from `width: double.infinity`, and the fixed
      // `_surahNameRowHeight` slot height). A 66pt glyph and a 30pt glyph
      // both get stretched to that identical final box, so the rendered
      // size is identical either way — fontSize is fully decoupled from
      // the on-screen size for this line type. The only thing that
      // actually controls final visible size is a scale factor applied
      // *after* the fill, which is exactly what `verticalInkFillCorrection`
      // already is. `bannerScale` used to multiply that same post-fill
      // transform on *both* axes — but the user then explicitly asked for
      // the banner to take the screen's full width again (2026-09-03
      // pt.6), which that horizontal shrink was directly undoing (it
      // scaled the already-edge-to-edge `BoxFit.fill` result back down to
      // 85%, leaving a left/right margin). `bannerScale` is now applied to
      // the vertical axis only — the horizontal factor is hardcoded to
      // `1.0` so the banner stays exactly as wide as its slot (edge-to-edge,
      // modulo this widget's own padding, which is already 0 for
      // surah_name) — while the "slightly smaller" sizing request is still
      // honored on the vertical axis, where it doesn't conflict with the
      // width request.
      const double bannerScale = 0.85;
      const double verticalInkFillCorrection = 2.56 * bannerScale;
      fitted = ClipRect(
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.diagonal3Values(
            1.0,
            verticalInkFillCorrection,
            1.0,
          ),
          child: fitted,
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: isSurahName ? 3 : 4,
        bottom: isSurahName ? 3 : 4,
        left: isSurahName ? 0 : 8,
        right: isSurahName ? 0 : 8,
      ),
      child: SizedBox(
        //height: double.infinity,
        width: double.infinity,
        child: fitted,
      ),
    );
  }
}

TextStyle _ayahTextStyle(String? fontFamily) => TextStyle(
  fontFamily: fontFamily,
  fontSize: 28,
  height: 1.0,
  color: mushafInkColor,
);

/// Builds one ayah line's words as a single [TextSpan] tree, one child span
/// per word (highlighted if it belongs to [selectedAyahKey]) joined by
/// plain-space spans. Used both to *render* the line (via [Text.rich]) and,
/// with the exact same word/style layout, to *hit-test* it in
/// [MushafPageView._wordAt] — sharing this one builder guarantees the two
/// never drift apart.
TextSpan _buildAyahSpan({
  required List<Word> words,
  required TextStyle baseStyle,
  required String? selectedAyahKey,
}) {
  final children = <InlineSpan>[];
  for (var i = 0; i < words.length; i++) {
    final word = words[i];
    final isSelected = word.ayahKey == selectedAyahKey;
    children.add(
      TextSpan(
        text: word.text,
        style: isSelected
            ? baseStyle.copyWith(backgroundColor: mushafAyahHighlightColor)
            : baseStyle,
      ),
    );
    if (i != words.length - 1) {
      children.add(TextSpan(text: ' ', style: baseStyle));
    }
  }
  return TextSpan(children: children);
}

/// One word's character range within the joined text [_buildAyahSpan]
/// produces (the exact same words + single-space joins), used to map a
/// tapped character offset back to a [Word].
class _WordSpan {
  final Word word;
  final int start;
  final int end; // exclusive
  const _WordSpan(this.word, this.start, this.end);
}

List<_WordSpan> _computeWordSpans(List<Word> words) {
  final spans = <_WordSpan>[];
  int offset = 0;
  for (var i = 0; i < words.length; i++) {
    final word = words[i];
    final start = offset;
    final end = start + word.text.length;
    spans.add(_WordSpan(word, start, end));
    offset = end + (i != words.length - 1 ? 1 : 0); // +1 for the joining space
  }
  return spans;
}

/// Resolves which [Word] (if any) sits at [localPosition] within an ayah
/// line, by laying out the exact same [TextSpan] [_MushafLineView] rendered
/// (same words/style/constraints) in a throwaway [TextPainter] and mapping
/// the tapped point to a character offset, then to a word via
/// [_computeWordSpans]. Returns `null` for a tap in the joining space
/// between two words, or past either end of the line's own text — spec
/// §9.1 treats those as an "outside tap" (dismiss), not a word selection.
Word? _wordAt({
  required BuildContext context,
  required List<Word> words,
  required String? fontFamily,
  required Offset localPosition,
}) {
  final baseStyle = _ayahTextStyle(fontFamily);
  final span = _buildAyahSpan(
    words: words,
    baseStyle: baseStyle,
    selectedAyahKey: null,
  );
  final painter = TextPainter(
    text: span,
    textDirection: TextDirection.rtl,
    maxLines: 1,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();

  final charOffset = painter.getPositionForOffset(localPosition).offset;
  final wordSpans = _computeWordSpans(words);
  for (final wordSpan in wordSpans) {
    if (charOffset >= wordSpan.start && charOffset < wordSpan.end) {
      return wordSpan.word;
    }
  }
  return null;
}
