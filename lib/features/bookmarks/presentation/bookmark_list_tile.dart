import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/theme/mushaf_theme.dart';
import '../../../shared/widgets/ayah_label.dart';
import '../../quran_reader/domain/quran_repository.dart';
import '../../user_library/presentation/user_library_provider.dart';
import '../domain/bookmark.dart';

/// One row in the Saved Items screen's "الإشارات المرجعية" tab: the
/// bookmarked ayah's label, a delete action (removes it via the shared
/// [UserLibraryProvider]), and a tap to jump there — owned by `bookmarks`
/// itself rather than implemented inline in `user_library`'s screen (which
/// should only compose per-feature rows, not know how one is rendered).
class BookmarkListTile extends StatelessWidget {
  const BookmarkListTile({
    super.key,
    required this.bookmark,
    required this.quranRepository,
    required this.onTap,
  });

  final Bookmark bookmark;
  final QuranRepository quranRepository;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.bookmark, color: mushafInkColor),
      title: FutureBuilder<String>(
        future: resolveAyahLabel(quranRepository, bookmark.ayahKey),
        builder: (context, snapshot) =>
            Text(snapshot.data ?? bookmark.ayahKey),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: () => context.read<UserLibraryProvider>().toggleBookmark(
          bookmark.ayahKey,
        ),
      ),
      onTap: onTap,
    );
  }
}
