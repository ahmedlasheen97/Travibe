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
    insetPadding: AppSizes.authDialogInset,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: AppSizes.authDialogMaxWidth),
      child: GlassSurface(
        radius: AppSizes.authDialogRadius,
        opacity: .82,
        surfaceKey: const ValueKey('email-exists-glass'),
        child: SingleChildScrollView(
          child: Padding(
            padding: AppSizes.authDialogPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  warningAsset,
                  width: AppSizes.authDialogArtSize,
                  height: AppSizes.authDialogArtSize,
                  excludeFromSemantics: true,
                ),
                SizedBox(height: AppSizes.authDialogArtGap),
                Semantics(
                  header: true,
                  child: Text(
                    'Email already exists',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: AppSizes.authDialogTitleFont,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(height: AppSizes.authDialogTitleGap),
                Text(
                  'An account with this email exists. Please log in or use another email.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: DarkColors.greyColor,
                    fontSize: AppSizes.authDialogBodyFont,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: AppSizes.authDialogActionsGap),
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
                      minimumSize: Size(0, AppSizes.buttonHeight),
                      padding: AppSizes.authDialogButtonPadding,
                    ),
                    child: Text('Log In Instead', textAlign: TextAlign.center),
                  ),
                ),
                SizedBox(height: AppSizes.authDialogButtonGap),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () =>
                        Navigator.pop(context, EmailExistsAction.anotherEmail),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      shape: ActionButtonStyle.shape,
                      textStyle: ActionButtonStyle.label,
                      minimumSize: Size(0, AppSizes.buttonHeight),
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
