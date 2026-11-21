import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/app_styles.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// Auth screen title with an optional subtitle.
///
/// The default is the Login/Sign Up heading: 32 title, left-aligned.
/// [AuthHeading.small] is the forgot-password/verification heading: 20 title,
/// 14 grey subtitle, both centered.
class AuthHeading extends StatelessWidget {
  const AuthHeading(this.title, {super.key, this.subtitle}) : small = false;

  const AuthHeading.small(this.title, {super.key, this.subtitle})
    : small = true;

  final String title;
  final String? subtitle;
  final bool small;

  static TextStyle get titleStyle => AppStyles.authTitleStyle;

  static TextStyle get subtitleStyle =>
      AppStyles.grey16MediumStyle.copyWith(fontSize: AppSizes.authBodyFont);

  static TextStyle get smallTitleStyle =>
      AppStyles.authTitleStyle.copyWith(fontSize: AppSizes.authSmallTitleFont);

  static TextStyle get smallSubtitleStyle =>
      AppStyles.grey16MediumStyle.copyWith(
        fontSize: AppSizes.authSmallSubtitleFont,
        color: DarkColors.greyColor,
      );

  @override
  Widget build(BuildContext context) {
    final align = small ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: small
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.start,
      children: [
        Text(
          title,
          textAlign: align,
          style: small ? smallTitleStyle : titleStyle,
        ),
        if (subtitle != null) ...[
          SizedBox(height: AppSizes.authSubtitleGap),
          Text(
            subtitle!,
            textAlign: align,
            style: small ? smallSubtitleStyle : subtitleStyle,
          ),
        ],
      ],
    );
  }
}
