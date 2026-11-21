import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';

/// Auth-only surface: scrolling must not tint or elevate this dark header.
class AuthAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AuthAppBar({super.key, this.title, this.showBack = true, this.onBack});

  /// Null shows only the back button (forgot-password / verification flow).
  final String? title;

  /// Login is the bottom of the auth stack and shows no back button.
  final bool showBack;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(
    backgroundColor: DarkColors.backgroundColor,
    foregroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    shadowColor: Colors.transparent,
    systemOverlayStyle: SystemUiOverlayStyle.light,
    automaticallyImplyLeading: false,
    leading: showBack ? BackButtonWidget(onTap: onBack) : null,
    centerTitle: true,
    title: title == null
        ? null
        : Text(title!, style: const TextStyle(color: Colors.white)),
  );
}
