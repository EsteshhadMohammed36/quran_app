import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/ayah_action_button.dart';
import '../../user_library/presentation/user_library_provider.dart';

/// The Ayah Context Sheet's "إشارة مرجعية" action (spec §10's Actions row):
/// toggles whether [ayahKey] is bookmarked, via the shared
/// [UserLibraryProvider] (spec §17.1 — bookmarks/notes/lastRead combined).
class BookmarkActionButton extends StatelessWidget {
  const BookmarkActionButton({super.key, required this.ayahKey});

  final String ayahKey;

  @override
  Widget build(BuildContext context) {
    final userLibrary = context.watch<UserLibraryProvider>();
    final bool isBookmarked = userLibrary.isBookmarked(ayahKey);
    return AyahActionButton(
      icon: isBookmarked ? Icons.bookmark : Icons.bookmark_border,
      label: 'إشارة مرجعية',
      onPressed: () => userLibrary.toggleBookmark(ayahKey),
    );
  }
}
