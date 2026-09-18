import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/theme/mushaf_theme.dart';
import '../../bookmarks/presentation/bookmark_list_tile.dart';
import '../../notes/presentation/note_list_tile.dart';
import '../../quran_reader/domain/quran_repository.dart';
import 'user_library_provider.dart';

/// "المحفوظات" (Saved) — the entry point for viewing bookmarks and notes
/// (Prompt 14). Not in spec §10's Ayah Context Sheet structure, and the
/// Mushaf reader deliberately has "no permanent chrome" (CLAUDE.md's Phase
/// 0 entry) — but a bookmark/note a user can never see again afterward
/// isn't a usable feature, so [MushafReaderScreen] adds one small always-
/// visible entry point (a corner button) to reach this screen, matching
/// that same minimal-chrome spirit rather than a full app bar/drawer.
class SavedItemsScreen extends StatelessWidget {
  const SavedItemsScreen({
    super.key,
    required this.quranRepository,
    required this.onJumpToAyah,
  });

  final QuranRepository quranRepository;

  /// Jumps the Mushaf reader to this ayah and closes this screen — supplied
  /// by [MushafReaderScreen] since only it holds the `PageController`/
  /// `QuranReaderProvider` needed to actually move the reader.
  final void Function(String ayahKey) onJumpToAyah;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: mushafPageColor,
          appBar: AppBar(
            backgroundColor: mushafPageColor,
            foregroundColor: mushafInkColor,
            title: const Text('المحفوظات'),
            bottom: const TabBar(
              labelColor: mushafInkColor,
              unselectedLabelColor: Color(0x991A1005),
              indicatorColor: mushafInkColor,
              tabs: [
                Tab(text: 'الإشارات المرجعية'),
                Tab(text: 'الملاحظات'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _BookmarksTab(
                quranRepository: quranRepository,
                onJumpToAyah: onJumpToAyah,
              ),
              _NotesTab(
                quranRepository: quranRepository,
                onJumpToAyah: onJumpToAyah,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookmarksTab extends StatelessWidget {
  const _BookmarksTab({
    required this.quranRepository,
    required this.onJumpToAyah,
  });

  final QuranRepository quranRepository;
  final void Function(String ayahKey) onJumpToAyah;

  @override
  Widget build(BuildContext context) {
    final bookmarks = context.watch<UserLibraryProvider>().bookmarks;
    if (bookmarks.isEmpty) {
      return const _EmptyState(message: 'لا توجد إشارات مرجعية بعد.');
    }
    return ListView.separated(
      itemCount: bookmarks.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) => BookmarkListTile(
        bookmark: bookmarks[index],
        quranRepository: quranRepository,
        onTap: () => onJumpToAyah(bookmarks[index].ayahKey),
      ),
    );
  }
}

class _NotesTab extends StatelessWidget {
  const _NotesTab({required this.quranRepository, required this.onJumpToAyah});

  final QuranRepository quranRepository;
  final void Function(String ayahKey) onJumpToAyah;

  @override
  Widget build(BuildContext context) {
    final notes = context.watch<UserLibraryProvider>().notes;
    if (notes.isEmpty) {
      return const _EmptyState(message: 'لا توجد ملاحظات بعد.');
    }
    return ListView.separated(
      itemCount: notes.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) => NoteListTile(
        note: notes[index],
        quranRepository: quranRepository,
        onTap: () => onJumpToAyah(notes[index].ayahKey),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: const TextStyle(color: Color(0x991A1005)),
      ),
    );
  }
}
