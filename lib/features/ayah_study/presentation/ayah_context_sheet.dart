import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/theme/mushaf_theme.dart';
import '../../../shared/widgets/quran_ayah_text.dart';
import '../../audio/presentation/audio_playback_row.dart';
import '../../audio/presentation/audio_provider.dart';
import '../../bookmarks/presentation/bookmark_action_button.dart';
import '../../last_read/presentation/mark_as_last_read_button.dart';
import '../../morphology/domain/morphology_repository.dart';
import '../../morphology/presentation/morphology_tab_content.dart';
import '../../notes/presentation/note_action_button.dart';
import '../../quran_reader/domain/quran_repository.dart';
import '../../quran_reader/domain/surah.dart';
import '../../quran_reader/domain/word.dart';
import '../../quran_reader/presentation/quran_reader_provider.dart';
import '../../tafsir/domain/tafsir_entry.dart';
import '../../tafsir/domain/tafsir_repository.dart';
import '../../tafsir/domain/tafsir_source.dart';
import '../../tafsir/presentation/grammar_tab_content.dart';
import '../../tafsir/presentation/tafsir_action_button.dart';
import '../../tafsir/presentation/tafsir_html_text.dart';

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
/// tabs, actions, audio row) wired to real surah/ayah/word data. Tafsir
/// (Prompt 11), Grammar (Prompt 12, i'rab) and Morphology (Prompt 12,
/// root/lemma/stem) now have real content; Meaning/Audio/Bookmarks/Notes
/// are still later prompts and stay a non-blocking "not available yet"
/// state (spec §20).
class AyahContextSheet extends StatelessWidget {
  const AyahContextSheet({
    super.key,
    required this.repository,
    required this.tafsirRepository,
    required this.morphologyRepository,
  });

  final QuranRepository repository;
  final TafsirRepository tafsirRepository;
  final MorphologyRepository morphologyRepository;

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
      morphologyRepository: morphologyRepository,
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
    required this.morphologyRepository,
  });

  final String ayahKey;
  final QuranRepository repository;
  final TafsirRepository tafsirRepository;
  final MorphologyRepository morphologyRepository;

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
            morphologyRepository: widget.morphologyRepository,
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
    // `SafeArea` alone isn't enough here: this sheet is a persistent
    // `Scaffold.bottomSheet`, not part of `body`, and on at least one real
    // device (Xiaomi/HyperOS, on-screen 3-button nav rendered as an overlay
    // rather than reserved window space) `MediaQuery.padding.bottom`
    // under-reports the nav bar's real height, so `SafeArea`'s own padding
    // ends up too small and the audio row renders half-hidden behind the
    // nav bar icons (user-reported, confirmed on-device). Computing the
    // padding explicitly with a guaranteed minimum floor — rather than
    // trusting the system-reported inset alone — fixes it regardless of
    // whether that inset is accurate on a given device.
    final double bottomInset = math.max(
      MediaQuery.of(context).padding.bottom,
      24.0,
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: mushafPageColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(blurRadius: 12, color: Colors.black26)],
      ),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottomInset),
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
    required this.morphologyRepository,
  });

  final _AyahData data;
  final String ayahKey;
  final QuranRepository repository;
  final TafsirRepository tafsirRepository;
  final MorphologyRepository morphologyRepository;

  @override
  Widget build(BuildContext context) {
    final activeTab = context.watch<QuranReaderProvider>().activeStudyTab;
    final audioProvider = context.watch<AudioProvider>();
    // Only highlight while *this* ayah is the one actually playing — a
    // stale currentWordKey from a previously-played ayah must never leak
    // onto a newly selected one just because the sheet re-rendered.
    final String? highlightedWordKey = audioProvider.currentAyahKey == ayahKey
        ? audioProvider.currentWordKey
        : null;
    // Cap the whole sheet's height (spec §10's "compact contextual panel",
    // not a full-screen surface) and let only the ayah text + tab content
    // region scroll internally, instead of the outer Column overflowing
    // past the top of the screen. Header/tabs row/actions/audio stay
    // pinned and always visible; only the variable-length middle — a long
    // ayah's own text, or a long الإعراب/tafsir passage — can exceed the
    // available space, e.g. a long Iraab Al-Muyassar entry on the
    // الإعراب tab (StudyTab.grammar/GrammarTabContent), which previously
    // caused a "RenderFlex overflowed" error since a plain Column only
    // sizes to its children's total height regardless of what actually
    // fits on screen.
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.8;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Header(surah: data.surah, ayahNumber: data.ayahNumber),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  QuranAyahText(
                    words: data.words,
                    pageByWordIndex: data.pageNumberByWordIndex,
                    highlightedWordKey: highlightedWordKey,
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  _StudyTabsRow(activeTab: activeTab),
                  switch (activeTab) {
                    // Tafsir (Ibn Kathir + As-Saadi, excluding Iraab
                    // Al-Muyassar — see [_TafsirTabContent]'s doc comment)
                    // replaces the never-built Meaning tab, 2026-09-13.
                    StudyTab.tafsir => _TafsirTabContent(
                        ayahKey: ayahKey,
                        tafsirRepository: tafsirRepository,
                      ),
                    // Grammar (spec §13 i'rab) reads the already-ingested
                    // Iraab Al-Muyassar tafsir source directly (see
                    // [iraabMuyassarSourceId]'s doc comment) rather than a
                    // placeholder. Extracted to its own file
                    // (tafsir/presentation/grammar_tab_content.dart) for
                    // the same reason QuranAyahText was: one shared
                    // implementation, not a copy that can silently drift.
                    StudyTab.grammar => GrammarTabContent(
                        ayahKey: ayahKey,
                        tafsirRepository: tafsirRepository,
                      ),
                    // Morphology (spec §12: root/lemma/stem per word) —
                    // Prompt 12's ingestion (tool/ingest_quran_data.dart)
                    // now populates this for real. Extracted to its own
                    // file (morphology/presentation/morphology_tab_content
                    // .dart) — same reasoning as GrammarTabContent above.
                    StudyTab.morphology => MorphologyTabContent(
                        ayahKey: ayahKey,
                        words: data.words,
                        pageByWordIndex: data.pageNumberByWordIndex,
                        morphologyRepository: morphologyRepository,
                      ),
                    // Every StudyTab value now has real content — no
                    // placeholder case left (see the now-removed
                    // _StudyTabPlaceholder).
                  },
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          _ActionsRow(
            ayahKey: ayahKey,
            surahId: data.surah.surahId,
            ayahNumber: data.ayahNumber,
            repository: repository,
            tafsirRepository: tafsirRepository,
          ),
          const SizedBox(height: 4),
          AudioPlaybackRow(ayahKey: ayahKey),
        ],
      ),
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
            backgroundColor:
                isActive ? mushafAyahHighlightColor : Colors.transparent,
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
          // Order/labels last changed 2026-09-13, replacing the never-
          // built "المعنى" (Meaning) tab with "التفسير" (Tafsir) and
          // moving it next to "الإعراب" (Grammar) — the user's explicit
          // ask: "عاوزة التاب بتاعة المعني تستبدل بتاب التفسير ... يكون
          // كلمة الاعراب والتفسير جنب بعض" (see StudyTab's own doc comment
          // for the full rationale/spec-deviation note).
          tabButton('التفسير', StudyTab.tafsir),
          tabButton('الإعراب', StudyTab.grammar),
          // Renamed 2026-09-12 (was "الإعراب"/"النحو", swapped from spec
          // §12/§13's actual meaning): StudyTab.morphology is root/lemma/
          // stem/POS (spec §12) — "الصرف" in Arabic, not "الإعراب". "الإعراب"
          // is specifically syntactic/grammatical parsing (spec §13),
          // matching the already-ingested Iraab Al-Muyassar source, so it
          // belongs on StudyTab.grammar instead.
          tabButton('الصرف', StudyTab.morphology),
          // Qiraat is explicitly "(future)" in spec §10 — shown, not built.
          tabButton('القراءات', null),
        ],
      ),
    );
  }
}

/// The "التفسير" study tab's real content (added 2026-09-13, replacing the
/// never-built "المعنى" tab — see [StudyTab]'s doc comment): every
/// [TafsirRepository] source *except* Iraab Al-Muyassar, as a single-open
/// accordion (same convention as [TafsirScreen]'s own source list) —
/// Iraab Al-Muyassar is deliberately excluded here since it's shown
/// exclusively on the "الإعراب" tab instead ([GrammarTabContent]), per the
/// user's explicit ask ("من غير الحاجة التالتة اللي هي الاعراب الميسر").
/// Reuses the same already-ingested `TafsirRepository` the full-screen
/// [TafsirScreen]/"تفسير" action already use (CLAUDE.md rule #4 — one
/// canonical source, not a second copy of the data or the query logic).
class _TafsirTabContent extends StatefulWidget {
  const _TafsirTabContent({
    required this.ayahKey,
    required this.tafsirRepository,
  });

  final String ayahKey;
  final TafsirRepository tafsirRepository;

  @override
  State<_TafsirTabContent> createState() => _TafsirTabContentState();
}

class _TafsirTabContentState extends State<_TafsirTabContent> {
  late final Future<List<TafsirSource>> _sourcesFuture =
      widget.tafsirRepository.getSources();

  // Single-open accordion. Before the user taps anything, the first
  // visible source is shown open by default (so there's something to
  // read without an extra tap) without that default being recorded as a
  // real "selection" — _expandedSourceId only starts meaning anything
  // once _userToggled flips true, at which point null legitimately means
  // "everything collapsed".
  bool _userToggled = false;
  String? _expandedSourceId;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: FutureBuilder<List<TafsirSource>>(
        future: _sourcesFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('خطأ: ${snapshot.error}')),
            );
          }
          final sources = snapshot.data;
          if (sources == null) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final visibleSources = [
            for (final source in sources)
              if (source.sourceId != iraabMuyassarSourceId) source,
          ];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final source in visibleSources) ...[
                  _TafsirSourceSection(
                    key: ValueKey('${source.sourceId}:${widget.ayahKey}'),
                    source: source,
                    ayahKey: widget.ayahKey,
                    tafsirRepository: widget.tafsirRepository,
                    expanded: _userToggled
                        ? _expandedSourceId == source.sourceId
                        : source == visibleSources.first,
                    onToggle: () => setState(() {
                      final String? currentlyExpanded = _userToggled
                          ? _expandedSourceId
                          : visibleSources.first.sourceId;
                      _userToggled = true;
                      _expandedSourceId = currentlyExpanded == source.sourceId
                          ? null
                          : source.sourceId;
                    }),
                  ),
                  if (source != visibleSources.last)
                    Divider(
                      height: 16,
                      color: mushafInkColor.withValues(alpha: 0.15),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One accordion section within [_TafsirTabContent]: a tappable source
/// name header and, when [expanded], that source's content for the
/// current ayah. Deliberately no search box here (unlike [TafsirScreen]'s
/// own accordion) — this is the compact sheet, not the full-screen reader;
/// searching within a source still works via the "تفسير" action's full
/// [TafsirScreen].
class _TafsirSourceSection extends StatelessWidget {
  const _TafsirSourceSection({
    super.key,
    required this.source,
    required this.ayahKey,
    required this.tafsirRepository,
    required this.expanded,
    required this.onToggle,
  });

  final TafsirSource source;
  final String ayahKey;
  final TafsirRepository tafsirRepository;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: mushafInkColor.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    source.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: mushafInkColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(right: 24, bottom: 4),
            child: _TafsirSourceContent(
              sourceId: source.sourceId,
              ayahKey: ayahKey,
              tafsirRepository: tafsirRepository,
            ),
          ),
      ],
    );
  }
}

/// One source's resolved tafsir text for [ayahKey] — same shape as
/// [TafsirScreen]'s own `_SourceContent`, kept as a separate small copy
/// here (rather than shared) since this one is styled for the compact
/// sheet (smaller, fixed font size, no font-size control) while
/// [TafsirScreen]'s is styled for a full-screen reader with a user-
/// adjustable size.
class _TafsirSourceContent extends StatelessWidget {
  const _TafsirSourceContent({
    required this.sourceId,
    required this.ayahKey,
    required this.tafsirRepository,
  });

  final String sourceId;
  final String ayahKey;
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
                  'تفسير الآيات ${entry.groupAyahStart} - '
                  '${entry.groupAyahEnd}',
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
                fontSize: 15,
                height: 1.6,
                color: mushafInkColor,
                fontStyle:
                    content == null ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The sheet's Tafsir/Note/Bookmark/Continue row (spec §10's Actions row).
/// Each action is owned and implemented by its own feature — this widget
/// only composes them side by side, it holds no bookmark/note/last-read
/// logic of its own (that used to live here directly, which was a Clean
/// Architecture violation: `ayah_study` reaching into other features'
/// concerns instead of depending on their public presentation widgets).
class _ActionsRow extends StatelessWidget {
  const _ActionsRow({
    required this.ayahKey,
    required this.surahId,
    required this.ayahNumber,
    required this.repository,
    required this.tafsirRepository,
  });

  final String ayahKey;
  final int surahId;
  final int ayahNumber;
  final QuranRepository repository;
  final TafsirRepository tafsirRepository;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TafsirActionButton(
          ayahKey: ayahKey,
          quranRepository: repository,
          tafsirRepository: tafsirRepository,
        ),
        NoteActionButton(ayahKey: ayahKey),
        BookmarkActionButton(ayahKey: ayahKey),
        MarkAsLastReadButton(
          ayahKey: ayahKey,
          surahId: surahId,
          ayahNumber: ayahNumber,
        ),
      ],
    );
  }
}
