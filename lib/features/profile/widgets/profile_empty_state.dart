import 'dart:math' as math;

import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/action_button_style.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// Only used for Profile and its connection lists. No fabricated model data.
class ProfileEmptyState extends StatelessWidget {
  const ProfileEmptyState({
    super.key,
    required this.asset,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
    this.padding,
  });
  final String asset, title;

  /// Optional line under [title].
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Defaults to 16 horizontal × 28 vertical.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding:
        padding ??
        EdgeInsets.symmetric(
          horizontal: AppSizes.pw16,
          vertical: AppSizes.ph28,
        ),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            // Raster art (1x/2x/3x): Figma exports these as PNGs wrapped in
            // SVG pattern fills, which flutter_svg draws as nothing.
            child: Image.asset(
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
          if (description case final description?) ...[
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
          ],
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

/// A Profile tab's empty state: fills only the space left below the header
/// and centers [ProfileEmptyState] in it, so an empty profile that fits the
/// screen does not scroll. [bottomInset] keeps it centered above Root's
/// bottom nav bar; the owning tab then skips Profile's own inset sliver.
class ProfileEmptyStateSliver extends StatelessWidget {
  const ProfileEmptyStateSliver({
    super.key,
    required this.asset,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
    this.bottomInset = 0,
  });
  final String asset, title;
  final String? description, actionLabel;
  final VoidCallback? onAction;
  final double bottomInset;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) => SliverToBoxAdapter(
      // At least the space left below the header (stable while scrolling);
      // grows with its content instead of squeezing it on short screens.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: math.max(
            0,
            constraints.viewportMainAxisExtent -
                constraints.precedingScrollExtent,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Center(
            child: ProfileEmptyState(
              asset: asset,
              title: title,
              description: description,
              actionLabel: actionLabel,
              onAction: onAction,
              padding: EdgeInsets.symmetric(
                horizontal: AppSizes.pw16,
                vertical: AppSizes.ph12,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
