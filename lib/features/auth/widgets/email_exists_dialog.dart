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
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: GlassSurface(
        radius: 30,
        opacity: .82,
        surfaceKey: const ValueKey('email-exists-glass'),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  warningAsset,
                  width: 80,
                  height: 80,
                  excludeFromSemantics: true,
                ),
                const SizedBox(height: 18),
                Semantics(
                  header: true,
                  child: const Text(
                    'Email already exists',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'An account with this email exists. Please log in or use another email.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: DarkColors.greyColor,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
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
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    child: const Text(
                      'Log In Instead',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () =>
                        Navigator.pop(context, EmailExistsAction.anotherEmail),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      shape: ActionButtonStyle.shape,
                      textStyle: ActionButtonStyle.label,
                      minimumSize: const Size(0, 48),
                    ),
                    child: const Text(
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
