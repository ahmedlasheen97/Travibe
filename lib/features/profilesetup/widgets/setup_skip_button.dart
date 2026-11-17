import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// Orange "Skip For Now" text button (Figma) under the main action of
/// Profile Setup steps 2 and 3. Plain sizes like the other setup step widgets.
class SetupSkipButton extends StatelessWidget {
  const SetupSkipButton({super.key, required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: DarkColors.primaryColor,
        minimumSize: const Size(0, 44),
      ),
      child: const Text(
        'Skip For Now',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
    ),
  );
}
