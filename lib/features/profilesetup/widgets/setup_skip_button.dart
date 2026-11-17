import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// Grey "Skip for now" text button shown under the main action of Profile
/// Setup steps 2 and 3 (same treatment as the sheets' "Not Now"). Plain sizes like the
/// other setup step widgets.
class SetupSkipButton extends StatelessWidget {
  const SetupSkipButton({super.key, required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: DarkColors.greyColor,
        minimumSize: const Size(0, 44),
      ),
      child: const Text(
        'Skip for now',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
    ),
  );
}
