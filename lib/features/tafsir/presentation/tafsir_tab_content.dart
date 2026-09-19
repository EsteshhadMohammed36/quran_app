import 'package:flutter/material.dart';

import '../../../shared/theme/mushaf_theme.dart';
import '../domain/tafsir_entry.dart';
import '../domain/tafsir_repository.dart';
import '../domain/tafsir_source.dart';
import 'tafsir_html_text.dart';

/// The "التفسير" study tab's real content (added 2026-09-13, replacing the
/// never-built "المعنى" tab — see `StudyTab`'s doc comment): every
/// [TafsirRepository] source *except* Iraab Al-Muyassar, as a single-open
/// accordion (same convention as `TafsirScreen`'s own source list) —
/// Iraab Al-Muyassar is deliberately excluded here since it's shown
/// exclusively on the "الإعراب" tab instead ([GrammarTabContent]), per the
/// user's explicit ask ("من غير الحاجة التالتة اللي هي الاعراب الميسر").
/// Reuses the same already-ingested `TafsirRepository` the full-screen
/// `TafsirScreen`/"تفسير" action already use (CLAUDE.md rule #4 — one
/// canonical source, not a second copy of the data or the query logic).
///
/// Lives under `tafsir/presentation` (moved here 2026-09-19, was inline in
/// `ayah_study/presentation/ayah_context_sheet.dart`) for the same reason
/// [GrammarTabContent] and `MorphologyTabContent` already do: this tab
/// replaced the full-screen `TafsirScreen`'s entry point (moved from the
/// sheet's Actions Row into the study-tabs row next to الإعراب/الصرف), it
/// didn't retire the Tafsir feature — so the widget that renders it belongs
/// to the `tafsir` feature's own presentation layer, not `ayah_study`'s.
class TafsirTabContent extends StatefulWidget {
  const TafsirTabContent({
    super.key,
    required this.ayahKey,
    required this.tafsirRepository,
  });

  final String ayahKey;
  final TafsirRepository tafsirRepository;

  @override
  State<TafsirTabContent> createState() => _TafsirTabContentState();
}

class _TafsirTabContentState extends State<TafsirTabContent> {
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

/// One accordion section within [TafsirTabContent]: a tappable source
/// name header and, when [expanded], that source's content for the
/// current ayah. Deliberately no search box here (unlike `TafsirScreen`'s
/// own accordion) — this is the compact sheet, not the full-screen reader;
/// searching within a source still works via the "تفسير" action's full
/// `TafsirScreen`.
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
/// `TafsirScreen`'s own `_SourceContent`, kept as a separate small copy
/// here (rather than shared) since this one is styled for the compact
/// sheet (smaller, fixed font size, no font-size control) while
/// `TafsirScreen`'s is styled for a full-screen reader with a user-
/// adjustable size.
class _TafsirSourceContent extends StatefulWidget {
  const _TafsirSourceContent({
    required this.sourceId,
    required this.ayahKey,
    required this.tafsirRepository,
  });

  final String sourceId;
  final String ayahKey;
  final TafsirRepository tafsirRepository;

  @override
  State<_TafsirSourceContent> createState() => _TafsirSourceContentState();
}

class _TafsirSourceContentState extends State<_TafsirSourceContent> {
  // Computed once per widget lifetime — see GrammarTabContent's identical
  // fix (spec §21 performance pass, 2026-09-19) for why calling the
  // repository directly as `FutureBuilder`'s `future` argument is a bug:
  // this section only rebuilds when its accordion is toggled or a
  // different ayah is selected (each gets a fresh `ValueKey`/ancestor
  // rebuild), but before this fix it *also* silently re-queried on every
  // unrelated ancestor rebuild (e.g. audio playback ticking `AudioProvider`
  // several times a second while this tab was open).
  late final Future<TafsirEntry> _entryFuture = widget.tafsirRepository
      .getEntry(widget.sourceId, widget.ayahKey);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TafsirEntry>(
      future: _entryFuture,
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
