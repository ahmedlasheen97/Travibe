import 'package:travibe/core/constants/app_sizes.dart';
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
    padding: EdgeInsets.symmetric(
      horizontal: AppSizes.pw16,
      vertical: AppSizes.ph28,
    ),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: SvgPicture.asset(
              asset,
              height: AppSizes.h121,
              fit: BoxFit.contain,
            ),
          ),
          SizedBox(height: AppSizes.h24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: DarkColors.whiteColor,
              fontSize: AppSizes.sp18,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: AppSizes.h10),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: AppSizes.w300),
            child: Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: DarkColors.greyColor,
                fontSize: AppSizes.sp14,
                height: 1.5,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            SizedBox(height: AppSizes.h24),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: DarkColors.primaryColor,
                foregroundColor: DarkColors.whiteColor,
                minimumSize: Size(AppSizes.w170, AppSizes.h44),
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
