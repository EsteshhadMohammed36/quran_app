import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/theme/mushaf_theme.dart';
import '../../../shared/widgets/ayah_action_button.dart';
import '../../user_library/presentation/user_library_provider.dart';
import 'note_editor_sheet.dart';

/// The Ayah Context Sheet's "ملاحظة" action (spec §10's Actions row): opens
/// [NoteEditorSheet] for [ayahKey] and saves the result via the shared
/// [UserLibraryProvider]; the icon fills in once a note already exists.
class NoteActionButton extends StatelessWidget {
  const NoteActionButton({super.key, required this.ayahKey});

  final String ayahKey;

  @override
  Widget build(BuildContext context) {
    final userLibrary = context.watch<UserLibraryProvider>();
    final bool hasNote = userLibrary.noteForAyah(ayahKey) != null;
    return AyahActionButton(
      icon: hasNote ? Icons.edit_note : Icons.edit_note_outlined,
      label: 'ملاحظة',
      iconColor: hasNote ? mushafAyahHighlightColor : null,
      onPressed: () async {
        final existing = userLibrary.noteForAyah(ayahKey);
        final String? result = await NoteEditorSheet.show(
          context,
          initialContent: existing?.content,
        );
        if (result != null) {
          await userLibrary.saveNote(ayahKey, result);
        }
      },
    );
  }
}
