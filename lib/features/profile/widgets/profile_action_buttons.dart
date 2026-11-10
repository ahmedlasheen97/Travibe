import 'package:flutter/material.dart';
import 'package:travibe/core/theme/action_button_style.dart';
import 'package:travibe/core/theme/dark_colors.dart';

class ProfileActionButtons extends StatelessWidget {
  const ProfileActionButtons({super.key, this.onEdit});
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      backgroundColor: DarkColors.darkgreyColor,
      disabledBackgroundColor: DarkColors.darkgreyColor,
      foregroundColor: DarkColors.whiteColor,
      disabledForegroundColor: DarkColors.whiteColor,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(0, 44),
      fixedSize: const Size.fromHeight(44),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: ActionButtonStyle.shape,
      textStyle: ActionButtonStyle.label,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: FilledButton(
              style: style,
              // Profile sharing is not yet implemented. Do not claim success.
              onPressed: null,
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
          const SizedBox(width: 12),
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
