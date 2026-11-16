import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/action_button_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/glass_surface.dart';

enum EmailExistsAction { login, anotherEmail }

Future<EmailExistsAction?> showEmailExistsDialog(BuildContext context) =>
    showDialog<EmailExistsAction>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => const EmailExistsDialog(),
    );

class EmailExistsDialog extends StatelessWidget {
  const EmailExistsDialog({super.key});
  static const warningAsset = 'assets/images/onboarding/Group 736.svg';

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    insetPadding: EdgeInsets.symmetric(
      horizontal: AppSizes.adaptiveWidth(24),
      vertical: AppSizes.adaptiveHeight(20),
    ),
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: AppSizes.adaptiveWidth(340)),
      child: GlassSurface(
        radius: AppSizes.adaptiveRadius(30),
        opacity: .82,
        surfaceKey: const ValueKey('email-exists-glass'),
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSizes.adaptiveWidth(24),
              AppSizes.adaptiveHeight(24),
              AppSizes.adaptiveWidth(24),
              AppSizes.adaptiveHeight(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  warningAsset,
                  width: AppSizes.adaptiveRadius(80),
                  height: AppSizes.adaptiveRadius(80),
                  excludeFromSemantics: true,
                ),
                SizedBox(height: AppSizes.adaptiveHeight(18)),
                Semantics(
                  header: true,
                  child: Text(
                    'Email already exists',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: AppSizes.adaptiveFont(20),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(height: AppSizes.adaptiveHeight(12)),
                Text(
                  'An account with this email exists. Please log in or use another email.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: DarkColors.greyColor,
                    fontSize: AppSizes.adaptiveFont(14),
                    height: 1.5,
                  ),
                ),
                SizedBox(height: AppSizes.adaptiveHeight(24)),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, EmailExistsAction.login),
                    style: FilledButton.styleFrom(
                      backgroundColor: DarkColors.primaryColor,
                      foregroundColor: Colors.white,
                      shape: ActionButtonStyle.shape,
                      textStyle: ActionButtonStyle.label,
                      minimumSize: Size(0, 48),
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    child: Text('Log In Instead', textAlign: TextAlign.center),
                  ),
                ),
                SizedBox(height: AppSizes.adaptiveHeight(8)),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () =>
                        Navigator.pop(context, EmailExistsAction.anotherEmail),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      shape: ActionButtonStyle.shape,
                      textStyle: ActionButtonStyle.label,
                      minimumSize: Size(0, 48),
                    ),
                    child: Text(
                      'Try Another Email',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
