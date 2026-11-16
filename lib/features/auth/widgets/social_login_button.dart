import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/action_button_style.dart';
import 'package:travibe/core/constants/feature_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SocialLoginButton extends StatelessWidget {
  const SocialLoginButton({
    super.key,
    required this.title,
    required this.iconPath,
    required this.onPressed,
  });

  final String title;
  final String iconPath;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SizedBox(
        height: AppSizes.adaptiveHeight(50).clamp(50, 58),
        child: ElevatedButton(
          onPressed: kEnableSocialAuthentication ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF303030),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: EdgeInsets.symmetric(
              horizontal: AppSizes.adaptiveWidth(12),
            ),
            shape: ActionButtonStyle.shape,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  iconPath,
                  width: AppSizes.adaptiveWidth(24),
                  height: AppSizes.adaptiveHeight(24),
                ),
                SizedBox(width: AppSizes.adaptiveWidth(12)),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: ActionButtonStyle.fontSize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
