import 'package:flutter/widgets.dart';

/// Fallback popover origin for [share_plus] on iPad.
///
/// iOS presents `UIActivityViewController` as a popover on iPad and crashes
/// unless `sharePositionOrigin` is a non-empty rect.
const Rect shareSheetOriginFallback = Rect.fromLTWH(0, 0, 1, 1);

/// Popover origin from a widget [context], or [shareSheetOriginFallback].
Rect shareSheetOrigin(BuildContext? context) {
  if (context == null || !context.mounted) return shareSheetOriginFallback;
  final box = context.findRenderObject();
  if (box is RenderBox && box.hasSize) {
    final size = box.size;
    if (size.width > 0 && size.height > 0) {
      return box.localToGlobal(Offset.zero) & size;
    }
  }
  final media = MediaQuery.maybeSizeOf(context);
  if (media != null && media.width > 0) {
    return Rect.fromLTWH(media.width / 2, media.height - 1, 1, 1);
  }
  return shareSheetOriginFallback;
}
