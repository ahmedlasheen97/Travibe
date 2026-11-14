import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/action_button_style.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// Share Profile is only shown when the profile has a backend share link
/// (the caller passes [onShare]); Edit Profile then fills the row.
class ProfileActionButtons extends StatelessWidget {
  const ProfileActionButtons({super.key, this.onEdit, this.onShare});
  final VoidCallback? onEdit;

  /// Receives the button's global rect (iPad share popover anchor).
  final ValueChanged<Rect>? onShare;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      backgroundColor: DarkColors.darkgreyColor,
      disabledBackgroundColor: DarkColors.darkgreyColor,
      foregroundColor: DarkColors.whiteColor,
      disabledForegroundColor: DarkColors.whiteColor,
      padding: EdgeInsets.symmetric(horizontal: AppSizes.pw8),
      minimumSize: Size(0, AppSizes.h44),
      fixedSize: Size.fromHeight(AppSizes.h44),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: ActionButtonStyle.shape,
      textStyle: ActionButtonStyle.label.copyWith(fontSize: AppSizes.sp18),
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSizes.pw20),
      child: Row(
        children: [
          if (onShare case final share?) ...[
            Expanded(
              child: Builder(
                builder: (context) => FilledButton(
                  key: const ValueKey('profile-share-button'),
                  style: style,
                  onPressed: () {
                    final box = context.findRenderObject() as RenderBox?;
                    share(
                      box == null || !box.hasSize
                          ? const Rect.fromLTWH(0, 0, 1, 1)
                          : box.localToGlobal(Offset.zero) & box.size,
                    );
                  },
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Share Profile',
                      maxLines: 1,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: AppSizes.w12),
          ],
          Expanded(
            child: FilledButton(
              style: style,
              onPressed: onEdit,
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Edit Profile',
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
