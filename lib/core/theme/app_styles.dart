import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';

class AppStyles {
  /// Big auth headings (Login, Sign Up): one size, weight and line height.
  static TextStyle get authTitleStyle => TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: AppSizes.adaptiveFont(32),
    fontWeight: FontWeight.w700,
    height: 1.25,
    color: DarkColors.whiteColor,
  );

  static TextStyle primaryHeadLinesStyle = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: AppSizes.sp32,
    fontWeight: FontWeight.w700,
    color: DarkColors.whiteColor,
  );

  static TextStyle subtitlesStyles = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: AppSizes.sp20,
    fontWeight: FontWeight.w600,
    color: DarkColors.whiteColor,
  );

  static TextStyle smallSubtitlesStyles = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: AppSizes.sp20,
    fontWeight: FontWeight.w600,
    color: DarkColors.whiteColor,
  );
  static TextStyle white18Style = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: AppSizes.sp18,
    fontWeight: FontWeight.w400,
    color: DarkColors.whiteColor,
  );
  static TextStyle white20Style = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: AppSizes.sp20,
    fontWeight: FontWeight.w600,
    color: DarkColors.whiteColor,
  );

  static TextStyle white16MediumStyle = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: AppSizes.sp16,
    fontWeight: FontWeight.w600,
    color: DarkColors.whiteColor,
  );

  static TextStyle grey14MediumStyle = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: AppSizes.sp14,
    fontWeight: FontWeight.w400,
    color: DarkColors.greyColor,
  );
  static TextStyle grey16MediumStyle = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: AppSizes.sp16,
    fontWeight: FontWeight.w400,
    color: DarkColors.greyColor,
  );
  static TextStyle orange16MediumStyle = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: AppSizes.sp16,
    fontWeight: FontWeight.w500,
    color: DarkColors.primaryColor,
  );
}
