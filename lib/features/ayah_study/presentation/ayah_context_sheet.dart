import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/theme/mushaf_theme.dart';
import '../../quran_reader/domain/quran_repository.dart';
import '../../quran_reader/domain/surah.dart';
import '../../quran_reader/domain/word.dart';
import '../../quran_reader/presentation/qpc_v2_fonts.dart';
import '../../quran_reader/presentation/quran_reader_provider.dart';

/// The Ayah Context Sheet (spec §10): opens under
/// `QuranReaderProvider.isAyahSheetOpen`, i.e. whenever an ayah is
/// selected (spec §9's tap flow ends with "... -> open Ayah Context
/// Sheet"). A persistent (non-modal) sheet, not a blocking dialog — the
/// Mushaf page stays visible and tappable around/behind it, matching
/// spec §10's "compact contextual panel ... preserve the Quran page
/// context" and §9.1's "tapping a different ayah updates the selection
/// in place, sheet remains open."
///
/// This prompt only builds the sheet's shell (header, ayah text, study
/// tabs, actions, audio row) wired to real surah/ayah/word data. The tab
/// bodies and action buttons show a non-blocking "not available yet"
/// state (spec §20) — Tafsir/Morphology/Audio/Bookmarks are later prompts
/// that will fill these in, not this one.
class AyahContextSheet extends StatelessWidget {
  const AyahContextSheet({super.key, required this.repository});

  final QuranRepository repository;

  @override
  Widget build(BuildContext context) {
    // Only re-fetch ayah data when the *ayah itself* changes, not on every
    // provider notification (e.g. switching study tabs) — see
    // _AyahSheetContent's stable `late final` future.
    final ayahKey = context.select<QuranReaderProvider, String?>(
      (p) => p.selectedAyahKey,
    );
    if (ayahKey == null) return const SizedBox.shrink();
    return _AyahSheetContent(
      key: ValueKey(ayahKey),
      ayahKey: ayahKey,
      repository: repository,
    );
  }
}

class _AyahData {
  final Surah surah;
  final int ayahNumber;
  final List<Word> words;
  final Map<int, int> pageNumberByWordIndex;

  const _AyahData({
    required this.surah,
    required this.ayahNumber,
    required this.words,
    required this.pageNumberByWordIndex,
  });
}

class _AyahSheetContent extends StatefulWidget {
  const _AyahSheetContent({
    super.key,
    required this.ayahKey,
    required this.repository,
  });

  final String ayahKey;
  final QuranRepository repository;

  @override
  State<_AyahSheetContent> createState() => _AyahSheetContentState();
}

class _AyahSheetContentState extends State<_AyahSheetContent> {
  late final Future<_AyahData> _future = _load();

  Future<_AyahData> _load() async {
    final parts = widget.ayahKey.split(':');
    final surahId = int.parse(parts[0]);
    final ayahNumber = int.parse(parts[1]);

    final surah = await widget.repository.getSurah(surahId);
    final words = await widget.repository.getWords(widget.ayahKey);
    final pageNumberByWordIndex = await widget.repository
        .getPageNumbersForWordIndexes([for (final w in words) w.wordIndex]);

    return _AyahData(
      surah: surah,
      ayahNumber: ayahNumber,
      words: words,
      pageNumberByWordIndex: pageNumberByWordIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      child: FutureBuilder<_AyahData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error: ${snapshot.error}'),
            );
          }
          final data = snapshot.data;
          if (data == null) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _AyahSheetBody(data: data);
        },
      ),
    );
  }
}

/// Shared outer chrome: rounded top corners, warm-paper background
/// matching the Mushaf page (mushaf_theme.dart), a drag-handle affordance,
/// and a safe-area pad so it doesn't sit under the system nav bar.
class _SheetShell extends StatelessWidget {
  const _SheetShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: mushafPageColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(blurRadius: 12, color: Colors.black26)],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: mushafInkColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _AyahSheetBody extends StatelessWidget {
  const _AyahSheetBody({required this.data});

  final _AyahData data;

  @override
  Widget build(BuildContext context) {
    final activeTab = context.watch<QuranReaderProvider>().activeStudyTab;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Header(surah: data.surah, ayahNumber: data.ayahNumber),
        const SizedBox(height: 12),
        _AyahText(words: data.words, pageByWordIndex: data.pageNumberByWordIndex),
        const SizedBox(height: 12),
        const Divider(height: 1),
        _StudyTabsRow(activeTab: activeTab),
        _StudyTabPlaceholder(tab: activeTab),
        const Divider(height: 1),
        const _ActionsRow(),
        const SizedBox(height: 4),
        const _AudioRow(),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.surah, required this.ayahNumber});

  final Surah surah;
  final int ayahNumber;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '${surah.nameArabic} • آية $ayahNumber',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: mushafInkColor,
            ),
          ),
        ),
        const Tooltip(
          message: 'مشاركة (قريبًا)',
          child: IconButton(
            onPressed: null,
            icon: Icon(Icons.share_outlined),
            color: mushafInkColor,
          ),
        ),
        Tooltip(
          message: 'إغلاق',
          child: IconButton(
            onPressed: () =>
                context.read<QuranReaderProvider>().clearSelection(),
            icon: const Icon(Icons.close),
            color: mushafInkColor,
          ),
        ),
      ],
    );
  }
}

/// The selected ayah's own words, each rendered with *its own page's* QCF
/// font (spec §7 — a page-boundary ayah's words can come from two
/// different page fonts, never assumed to share one). Unlike the fixed
/// single Mushaf line (rule #2), this is a normal wrapping paragraph — a
/// different UI surface (a contextual excerpt in a panel, not the Mushaf
/// page itself), so wrapping here doesn't conflict with that rule.
class _AyahText extends StatelessWidget {
  const _AyahText({required this.words, required this.pageByWordIndex});

  final List<Word> words;
  final Map<int, int> pageByWordIndex;

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      final pageNumber = pageByWordIndex[word.wordIndex];
      spans.add(
        TextSpan(
          text: word.text,
          style: TextStyle(
            fontFamily: pageNumber == null
                ? null
                : fontFamilyForPage(pageNumber),
            fontSize: 26,
            height: 1.8,
            color: mushafInkColor,
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

class _StudyTabsRow extends StatelessWidget {
  const _StudyTabsRow({required this.activeTab});

  final StudyTab activeTab;

  @override
  Widget build(BuildContext context) {
    Widget tabButton(String label, StudyTab? tab) {
      final bool isActive = tab != null && tab == activeTab;
      return Expanded(
        child: TextButton(
          onPressed: tab == null
              ? null
              : () => context.read<QuranReaderProvider>().setActiveStudyTab(
                  tab,
                ),
          style: TextButton.styleFrom(
            foregroundColor: mushafInkColor.withValues(
              alpha: tab == null ? 0.3 : (isActive ? 1.0 : 0.55),
            ),
            backgroundColor: isActive
                ? mushafAyahHighlightColor
                : Colors.transparent,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          tabButton('المعنى', StudyTab.meaning),
          tabButton('الإعراب', StudyTab.morphology),
          tabButton('النحو', StudyTab.grammar),
          // Qiraat is explicitly "(future)" in spec §10 — shown, not built.
          tabButton('القراءات', null),
        ],
      ),
    );
  }
}

class _StudyTabPlaceholder extends StatelessWidget {
  const _StudyTabPlaceholder({required this.tab});

  final StudyTab tab;

  @override
  Widget build(BuildContext context) {
    // Non-blocking "not available yet" state (spec §20) — real content
    // arrives in later prompts (Tafsir/Morphology feature modules).
    final String message = switch (tab) {
      StudyTab.meaning => 'معنى الآية غير متاح بعد.',
      StudyTab.morphology => 'تحليل الإعراب غير متاح بعد.',
      StudyTab.grammar => 'شرح النحو غير متاح بعد.',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text(
          message,
          style: TextStyle(color: mushafInkColor.withValues(alpha: 0.55)),
        ),
      ),
    );
  }
}

class _ActionsRow extends StatelessWidget {
  const _ActionsRow();

  @override
  Widget build(BuildContext context) {
    Widget action(IconData icon, String label) {
      return Expanded(
        child: Tooltip(
          message: 'قريبًا',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: null,
                icon: Icon(icon, color: mushafInkColor.withValues(alpha: 0.4)),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: mushafInkColor.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        action(Icons.menu_book_outlined, 'تفسير'),
        action(Icons.edit_note_outlined, 'ملاحظة'),
        action(Icons.bookmark_border, 'إشارة مرجعية'),
        action(Icons.subdirectory_arrow_left_outlined, 'متابعة'),
      ],
    );
  }
}

class _AudioRow extends StatelessWidget {
  const _AudioRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: null,
          icon: Icon(
            Icons.play_arrow_rounded,
            color: mushafInkColor.withValues(alpha: 0.4),
          ),
        ),
        Expanded(
          child: Text(
            'الصوت غير متاح بعد',
            style: TextStyle(
              fontSize: 12,
              color: mushafInkColor.withValues(alpha: 0.4),
            ),
          ),
        ),
      ],
    );
  }
}
