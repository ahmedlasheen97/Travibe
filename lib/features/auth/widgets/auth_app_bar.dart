import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';

/// Auth-only surface: scrolling must not tint or elevate this dark header.
class AuthAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AuthAppBar({super.key, required this.title});

  final String title;

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
    leading: const BackButtonWidget(),
    centerTitle: true,
    title: Text(title, style: const TextStyle(color: Colors.white)),
  );
}
