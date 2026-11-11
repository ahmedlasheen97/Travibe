import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';

class ActionIconButton extends StatelessWidget {
  final bool responsive;
  final String iconPath;

  /// Hidden when null.
  final String? count;
  final VoidCallback? onTap;
  final bool preserveAssetColors;

  const ActionIconButton({
    super.key,
    required this.iconPath,
    this.count,
    this.onTap,
    this.preserveAssetColors = false,
    this.responsive = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(
        (responsive ? AppSizes.adaptiveRadius(24) : AppSizes.r24),
      ),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: responsive ? AppSizes.adaptiveWidth(8) : AppSizes.pw8,
          vertical: responsive ? AppSizes.adaptiveHeight(6) : AppSizes.ph6,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF2E2E2E)),
          borderRadius: BorderRadius.circular(
            (responsive ? AppSizes.adaptiveRadius(24) : AppSizes.r24),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              iconPath,
              width: responsive ? AppSizes.adaptiveRadius(18) : 18,
              height: responsive ? AppSizes.adaptiveRadius(18) : 18,
              colorFilter: preserveAssetColors
                  ? null
                  : const ColorFilter.mode(
                      DarkColors.whiteColor,
                      BlendMode.srcIn,
                    ),
            ),
            if (count != null) ...[
              SizedBox(width: responsive ? AppSizes.adaptiveWidth(6) : 6),
              Text(
                count!,
                style: TextStyle(
                  color: DarkColors.whiteColor,
                  fontSize: responsive ? AppSizes.adaptiveFont(13) : 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
