import 'package:flutter/material.dart';

import '../theme/mushaf_theme.dart';

/// One icon+label action in the Ayah Context Sheet's actions row (spec §10's
/// Tafsir/Note/Bookmark/Continue row). Shared by each owning feature's own
/// action-button widget (tafsir/notes/bookmarks/last_read) so the visual
/// shape — icon, label, disabled/enabled tint, tooltip — can't silently
/// drift between them; only the icon/label/color/callback vary per action.
class AyahActionButton extends StatelessWidget {
  const AyahActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
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
                color: enabled
                    ? (iconColor ?? mushafInkColor)
                    : mushafInkColor.withValues(alpha: 0.4),
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
}
