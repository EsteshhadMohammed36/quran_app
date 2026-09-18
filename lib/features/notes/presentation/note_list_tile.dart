import 'package:flutter/material.dart';

import '../../../shared/theme/mushaf_theme.dart';
import '../../../shared/widgets/ayah_label.dart';
import '../../quran_reader/domain/quran_repository.dart';
import '../domain/note.dart';

/// One row in the Saved Items screen's "الملاحظات" tab: the noted ayah's
/// label, a content preview, and a tap to jump there — owned by `notes`
/// itself rather than implemented inline in `user_library`'s screen (which
/// should only compose per-feature rows, not know how one is rendered).
class NoteListTile extends StatelessWidget {
  const NoteListTile({
    super.key,
    required this.note,
    required this.quranRepository,
    required this.onTap,
  });

  final Note note;
  final QuranRepository quranRepository;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.edit_note, color: mushafInkColor),
      title: FutureBuilder<String>(
        future: resolveAyahLabel(quranRepository, note.ayahKey),
        builder: (context, snapshot) => Text(snapshot.data ?? note.ayahKey),
      ),
      subtitle: Text(
        note.content,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
    );
  }
}
