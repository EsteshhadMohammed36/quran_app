import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/ayah_action_button.dart';
import '../../quran_reader/presentation/quran_reader_provider.dart';
import '../../user_library/presentation/user_library_provider.dart';

/// The Ayah Context Sheet's "متابعة" action (spec §10's Actions row): pins
/// the precise surah:ayah as the last-read position via the shared
/// [UserLibraryProvider]. Automatic, coarser page-level last-read tracking
/// already happens on every swipe ([UserLibraryProvider.updateLastReadPage])
/// — this is the precise, user-initiated counterpart pinned to one ayah.
class MarkAsLastReadButton extends StatelessWidget {
  const MarkAsLastReadButton({
    super.key,
    required this.ayahKey,
    required this.surahId,
    required this.ayahNumber,
  });

  final String ayahKey;
  final int surahId;
  final int ayahNumber;

  @override
  Widget build(BuildContext context) {
    return AyahActionButton(
      icon: Icons.subdirectory_arrow_left_outlined,
      label: 'متابعة',
      onPressed: () async {
        final int currentPage = context
            .read<QuranReaderProvider>()
            .currentPage;
        await context.read<UserLibraryProvider>().markAyahAsLastRead(
          pageNumber: currentPage,
          surahId: surahId,
          ayahNumber: ayahNumber,
          ayahKey: ayahKey,
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ موضع المتابعة')),
        );
      },
    );
  }
}
