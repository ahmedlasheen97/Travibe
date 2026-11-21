import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/auth/widgets/auth_app_bar.dart';

/// The shared auth shell: top bar, one scroll owner and the auth body inset.
/// The Scaffold resizes for the keyboard, so the main button scrolls into view.
class AuthPage extends StatelessWidget {
  const AuthPage({
    super.key,
    required String this.barTitle,
    required this.child,
    this.showBack = true,
    this.onBack,
  }) : recovery = false;

  /// Forgot-password / verification screens: the bar shows only the back
  /// button and the heading sits [AppSizes.authRecoveryHeaderGap] below it.
  const AuthPage.recovery({
    super.key,
    required this.child,
    this.showBack = true,
    this.onBack,
  }) : barTitle = null,
       recovery = true;

  final String? barTitle;
  final bool recovery;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: DarkColors.backgroundColor,
    child: SafeArea(
      child: Scaffold(
        backgroundColor: DarkColors.backgroundColor,
        appBar: AuthAppBar(title: barTitle, showBack: showBack, onBack: onBack),
        body: SingleChildScrollView(
          child: Padding(
            padding: recovery
                ? AppSizes.authRecoveryPagePadding
                : AppSizes.authPagePadding,
            child: child,
          ),
        ),
      ),
    ),
  );
}
