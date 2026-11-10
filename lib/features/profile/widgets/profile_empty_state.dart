import 'package:travibe/core/theme/action_button_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// Only used for Profile and its connection lists. No fabricated model data.
class ProfileEmptyState extends StatelessWidget {
  const ProfileEmptyState({
    super.key,
    required this.asset,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });
  final String asset, title, description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: SvgPicture.asset(asset, height: 121, fit: BoxFit.contain),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: DarkColors.whiteColor,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: DarkColors.greyColor,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: DarkColors.primaryColor,
                foregroundColor: DarkColors.whiteColor,
                minimumSize: const Size(170, 44),
                shape: ActionButtonStyle.shape,
                textStyle: ActionButtonStyle.label,
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    ),
  );
}
