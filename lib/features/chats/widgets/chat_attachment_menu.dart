import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';

/// Compact reference menu anchored to the actual composer control, including
/// keyboard/SafeArea offsets. Outside-tap and Back dismiss without changing drafts.
class ChatAttachmentMenu extends StatelessWidget {
  const ChatAttachmentMenu({super.key, this.onCamera, this.onGallery});
  final VoidCallback? onCamera, onGallery;

  static Future<ImageSource?> show(
    BuildContext context, {
    required Rect anchor,
    required bool enabled,
  }) => showGeneralDialog<ImageSource>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: .65),
    transitionDuration: const Duration(milliseconds: 120),
    requestFocus: false,
    pageBuilder: (dialog, _, _) => CustomSingleChildLayout(
      delegate: _AttachmentPosition(
        anchor,
        MediaQuery.paddingOf(dialog),
        Directionality.of(dialog),
        MediaQuery.textScalerOf(dialog).scale(1),
      ),
      child: ChatAttachmentMenu(
        onCamera: enabled
            ? () => Navigator.pop(dialog, ImageSource.camera)
            : null,
        onGallery: enabled
            ? () => Navigator.pop(dialog, ImageSource.gallery)
            : null,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF171717),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(28),
      side: const BorderSide(color: Color(0xFF333333)),
    ),
    clipBehavior: Clip.antiAlias,
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _item('Camera', 'camera.svg', onCamera),
            _item('Gallery', 'gallery.svg', onGallery),
          ],
        ),
      ),
    ),
  );
  Widget _item(String title, String asset, VoidCallback? action) => ListTile(
    enabled: action != null,
    onTap: action,
    minTileHeight: 48,
    dense: true,
    minLeadingWidth: 20,
    horizontalTitleGap: 10,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18),
    leading: SvgPicture.asset(
      'assets/images/interactions/$asset',
      width: 20,
      height: 20,
      colorFilter: ColorFilter.mode(
        action == null ? Colors.white38 : Colors.white70,
        BlendMode.srcIn,
      ),
    ),
    title: Text(
      title,
      style: TextStyle(
        color: action == null ? Colors.white38 : Colors.white,
        fontSize: 14,
      ),
    ),
  );
}

class _AttachmentPosition extends SingleChildLayoutDelegate {
  _AttachmentPosition(this.anchor, this.insets, this.direction, this.scale);
  final Rect anchor;
  final EdgeInsets insets;
  final TextDirection direction;
  final double scale;
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final width = math
        .min(
          math.max(184.0, 184 * scale.clamp(1, 1.5)),
          constraints.maxWidth - 32,
        )
        .clamp(0.0, constraints.maxWidth)
        .toDouble();
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: (anchor.top - insets.top - 20)
          .clamp(0.0, constraints.maxHeight)
          .toDouble(),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final start = direction == TextDirection.rtl
        ? anchor.right - childSize.width
        : anchor.left;
    return Offset(
      start.clamp(16.0, math.max(16.0, size.width - childSize.width - 16)),
      (anchor.top - childSize.height - 12).clamp(
        insets.top + 8,
        math.max(
          insets.top + 8,
          size.height - insets.bottom - childSize.height,
        ),
      ),
    );
  }

  @override
  bool shouldRelayout(covariant _AttachmentPosition old) =>
      anchor != old.anchor ||
      insets != old.insets ||
      direction != old.direction ||
      scale != old.scale;
}
