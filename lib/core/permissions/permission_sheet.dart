import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/permissions/app_permission.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/custom_button.dart';
import 'package:travibe/core/widgets/glass_surface.dart';
import 'package:travibe/core/widgets/sheet_handle.dart';

/// Shared glass permission sheet (soft ask and "Open Settings"). Resolves to
/// true only when [confirmLabel] is tapped; swiping down or "Not Now" is false.
Future<bool> showPermissionSheet(
  BuildContext context, {
  required Widget art,
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Not Now',
  Key? sheetKey,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => PermissionSheet(
        key: sheetKey,
        art: art,
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
      ),
    ) ??
    false;

/// Explains why [permission] is needed and offers Settings. Returns true when
/// the user chose "Open Settings".
Future<bool> showPermissionSettingsSheet(
  BuildContext context,
  AppPermission permission,
) => showPermissionSheet(
  context,
  sheetKey: ValueKey('permission-settings-${permission.name}'),
  art: PermissionSheetIcon(permission.icon),
  title: permission.title,
  message: permission.message,
  confirmLabel: 'Open Settings',
);

class PermissionSheet extends StatelessWidget {
  const PermissionSheet({
    super.key,
    required this.art,
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.cancelLabel = 'Not Now',
  });
  final Widget art;
  final String title, message, confirmLabel, cancelLabel;

  static const _font = 'Plus Jakarta Sans';

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: EdgeInsets.all(AppSizes.adaptiveWidth(12)),
    child: GlassSurface(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSizes.adaptiveWidth(24),
          AppSizes.adaptiveHeight(12),
          AppSizes.adaptiveWidth(24),
          AppSizes.adaptiveHeight(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            SizedBox(height: AppSizes.adaptiveHeight(24)),
            art,
            SizedBox(height: AppSizes.adaptiveHeight(16)),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: _font,
                color: DarkColors.whiteColor,
                fontSize: AppSizes.adaptiveFont(20),
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: AppSizes.adaptiveHeight(8)),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: _font,
                color: Colors.white70,
                fontSize: AppSizes.adaptiveFont(14),
                height: 1.45,
              ),
            ),
            SizedBox(height: AppSizes.adaptiveHeight(24)),
            CustomButton(
              key: const ValueKey('permission-sheet-confirm'),
              title: confirmLabel,
              onPressed: () => Navigator.pop(context, true),
            ),
            SizedBox(height: AppSizes.adaptiveHeight(12)),
            CustomButton(
              key: const ValueKey('permission-sheet-cancel'),
              title: cancelLabel,
              isOutlined: true,
              onPressed: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Round orange-tinted badge used as the sheet art for a Material icon.
class PermissionSheetIcon extends StatelessWidget {
  const PermissionSheetIcon(this.icon, {super.key});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final size = AppSizes.adaptiveRadius(72);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: DarkColors.primaryColor.withValues(alpha: .16),
      ),
      child: Icon(icon, color: DarkColors.primaryColor, size: size * .5),
    );
  }
}
