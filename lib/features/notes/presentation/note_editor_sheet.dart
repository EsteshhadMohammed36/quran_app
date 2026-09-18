import 'package:flutter/material.dart';

import '../../../shared/theme/mushaf_theme.dart';

/// A modal editor for the selected ayah's single note (Prompt 14's "ملاحظة"
/// action — spec's Actions row: "Note"). Deliberately a small
/// `showModalBottomSheet`, not another persistent sheet stacked on top of
/// the already-open [AyahContextSheet] — this one *should* block
/// interaction with the page underneath while typing, unlike the ayah
/// sheet itself (see that class's own doc comment on why it's non-modal).
///
/// Returns the saved content via `Navigator.pop`, or `null` if the user
/// cancelled — the caller ([_ActionsRow] in ayah_context_sheet.dart) is the
/// one that actually calls [UserLibraryProvider.saveNote]/`deleteNote`, so
/// this widget has no repository dependency of its own.
class NoteEditorSheet extends StatefulWidget {
  const NoteEditorSheet({super.key, this.initialContent});

  final String? initialContent;

  /// Shows the editor and returns the trimmed note text the user saved
  /// (may be empty, meaning "delete the note"), or `null` if they
  /// cancelled without saving.
  static Future<String?> show(BuildContext context, {String? initialContent}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NoteEditorSheet(initialContent: initialContent),
    );
  }

  @override
  State<NoteEditorSheet> createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends State<NoteEditorSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialContent ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool hasExistingNote = (widget.initialContent ?? '').isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: mushafPageColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'ملاحظة',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: mushafInkColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    maxLines: 5,
                    minLines: 3,
                    style: const TextStyle(color: mushafInkColor),
                    decoration: const InputDecoration(
                      hintText: 'اكتب ملاحظتك هنا...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (hasExistingNote)
                        TextButton.icon(
                          onPressed: () => Navigator.of(context).pop(''),
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                          ),
                          label: const Text(
                            'حذف',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('إلغاء'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () =>
                            Navigator.of(context).pop(_controller.text),
                        child: const Text('حفظ'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
