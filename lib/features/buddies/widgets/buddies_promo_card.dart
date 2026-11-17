import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';

/// Rounded Buddies home banner: title, text, action and an optional footer on
/// the left, artwork anchored to the bottom-right corner.
class BuddiesPromoCard extends StatelessWidget {
  const BuddiesPromoCard({
    super.key,
    required this.color,
    required this.image,
    required this.imageWidth,
    required this.imageHeight,
    required this.title,
    required this.message,
    required this.action,
    this.footer,
  });
  final Color color;
  final String image;
  final double imageWidth, imageHeight;
  final String title, message;
  final Widget action;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    constraints: BoxConstraints(minHeight: AppSizes.adaptiveHeight(144)),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(AppSizes.adaptiveRadius(24)),
    ),
    child: Stack(
      children: [
        PositionedDirectional(
          end: 0,
          bottom: 0,
          child: ExcludeSemantics(
            child: Image.asset(
              image,
              width: AppSizes.adaptiveWidth(imageWidth),
              height: AppSizes.adaptiveWidth(imageHeight),
              fit: BoxFit.contain,
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(AppSizes.adaptiveRadius(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  letterSpacing: 0,
                  color: Colors.white,
                  fontSize: AppSizes.adaptiveFont(16),
                  height: 24 / 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: AppSizes.adaptiveHeight(4)),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: AppSizes.adaptiveWidth(210),
                ),
                child: Text(
                  message,
                  style: TextStyle(
                    letterSpacing: 0,
                    color: Colors.white,
                    fontSize: AppSizes.adaptiveFont(12),
                    height: 16 / 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              SizedBox(height: AppSizes.adaptiveHeight(16)),
              action,
              if (footer != null) ...[
                SizedBox(height: AppSizes.adaptiveHeight(12)),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: AppSizes.adaptiveWidth(210),
                  ),
                  child: footer,
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}
