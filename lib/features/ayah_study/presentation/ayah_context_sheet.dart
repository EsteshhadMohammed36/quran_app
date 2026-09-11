import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/theme/mushaf_theme.dart';
import '../../../shared/widgets/quran_ayah_text.dart';
import '../../quran_reader/domain/quran_repository.dart';
import '../../quran_reader/domain/surah.dart';
import '../../quran_reader/domain/word.dart';
import '../../quran_reader/presentation/quran_reader_provider.dart';
import '../../tafsir/domain/tafsir_entry.dart';
import '../../tafsir/domain/tafsir_repository.dart';
import '../../tafsir/domain/tafsir_source.dart';
import '../../tafsir/presentation/tafsir_html_text.dart';
import '../../tafsir/presentation/tafsir_screen.dart';

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
  const AyahContextSheet({
    super.key,
    required this.repository,
    required this.tafsirRepository,
  });

  final QuranRepository repository;
  final TafsirRepository tafsirRepository;

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
      tafsirRepository: tafsirRepository,
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
    required this.tafsirRepository,
  });

  final String ayahKey;
  final QuranRepository repository;
  final TafsirRepository tafsirRepository;

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
          return _AyahSheetBody(
            data: data,
            ayahKey: widget.ayahKey,
            repository: widget.repository,
            tafsirRepository: widget.tafsirRepository,
          );
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
  const _AyahSheetBody({
    required this.data,
    required this.ayahKey,
    required this.repository,
    required this.tafsirRepository,
  });

  final _AyahData data;
  final String ayahKey;
  final QuranRepository repository;
  final TafsirRepository tafsirRepository;

  @override
  Widget build(BuildContext context) {
    final activeTab = context.watch<QuranReaderProvider>().activeStudyTab;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Header(surah: data.surah, ayahNumber: data.ayahNumber),
        const SizedBox(height: 12),
        QuranAyahText(
          words: data.words,
          pageByWordIndex: data.pageNumberByWordIndex,
        ),
        const SizedBox(height: 12),
        const Divider(height: 1),
        _StudyTabsRow(activeTab: activeTab),
        switch (activeTab) {
          // Grammar (spec §13 i'rab) reads the already-ingested Iraab
          // Al-Muyassar tafsir source directly (see [iraabMuyassarSourceId]'s
          // doc comment) rather than a placeholder — Meaning/Morphology stay
          // placeholders (Meaning is a later prompt; Morphology's root/lemma/
          // stem ingestion is still blocked on two corrupted raw_resources
          // downloads, 2026-09-12).
          StudyTab.grammar => _GrammarTabContent(
              ayahKey: ayahKey,
              tafsirRepository: tafsirRepository,
            ),
          _ => _StudyTabPlaceholder(tab: activeTab),
        },
        const Divider(height: 1),
        _ActionsRow(
          ayahKey: ayahKey,
          repository: repository,
          tafsirRepository: tafsirRepository,
        ),
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
          // Renamed 2026-09-12 (was "الإعراب"/"النحو", swapped from spec
          // §12/§13's actual meaning): StudyTab.morphology is root/lemma/
          // stem/POS (spec §12) — "الصرف" in Arabic, not "الإعراب". "الإعراب"
          // is specifically syntactic/grammatical parsing (spec §13),
          // matching the already-ingested Iraab Al-Muyassar source, so it
          // belongs on StudyTab.grammar instead.
          tabButton('الصرف', StudyTab.morphology),
          tabButton('الإعراب', StudyTab.grammar),
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
    // arrives in later prompts. Grammar (§13/i'rab) is no longer a
    // placeholder — see [_GrammarTabContent] — so it's not listed here.
    final String message = switch (tab) {
      StudyTab.meaning => 'معنى الآية غير متاح بعد.',
      StudyTab.morphology => 'تحليل الصرف غير متاح بعد.',
      StudyTab.grammar =>
        throw StateError('Grammar tab has real content — see _GrammarTabContent.'),
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

/// The "الإعراب" (Grammar/I'rab, spec §13) study tab's real content:
/// Iraab Al-Muyassar's entry for the selected ayah, read straight from the
/// tafsir module's own repository/table (see [iraabMuyassarSourceId]) — spec
/// §13 requires this to stay a distinct data source from both Tafsir's own
/// screen and from Morphology, and to name that source explicitly, which
/// this widget does via its header line.
class _GrammarTabContent extends StatelessWidget {
  const _GrammarTabContent({
    required this.ayahKey,
    required this.tafsirRepository,
  });

  final String ayahKey;
  final TafsirRepository tafsirRepository;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TafsirEntry>(
      future: tafsirRepository.getEntry(iraabMuyassarSourceId, ayahKey),
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
                    : 'الإعراب الميسر',
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
    );
  }
}

class _ActionsRow extends StatelessWidget {
  const _ActionsRow({
    required this.ayahKey,
    required this.repository,
    required this.tafsirRepository,
  });

  final String ayahKey;
  final QuranRepository repository;
  final TafsirRepository tafsirRepository;

  @override
  Widget build(BuildContext context) {
    Widget action(IconData icon, String label, {VoidCallback? onPressed}) {
      final bool enabled = onPressed != null;
      return Expanded(
        child: Tooltip(
          message: enabled ? label : 'قريبًا',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: onPressed,
                icon: Icon(
                  icon,
                  color: mushafInkColor.withValues(alpha: enabled ? 1.0 : 0.4),
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: mushafInkColor.withValues(alpha: enabled ? 1.0 : 0.4),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        action(
          Icons.menu_book_outlined,
          'تفسير',
          // spec §11: "Tafsir open: Tafsir reader replaces/extends the
          // context layer without losing ayah identity" — a normal
          // Navigator.push (a full screen, not another sheet, per
          // TafsirScreen's own doc comment), with the same
          // QuranReaderProvider instance handed in explicitly so
          // TafsirScreen's Previous/Next navigation can keep the Mushaf's
          // own selection in sync (a route pushed this way isn't a
          // descendant of the ChangeNotifierProvider wrapping the reader,
          // so `Provider.of`/`context.read` wouldn't find it there).
          onPressed: () {
            final quranReaderProvider = context.read<QuranReaderProvider>();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => TafsirScreen(
                  initialAyahKey: ayahKey,
                  quranRepository: repository,
                  tafsirRepository: tafsirRepository,
                  quranReaderProvider: quranReaderProvider,
                ),
              ),
            );
          },
        ),
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
