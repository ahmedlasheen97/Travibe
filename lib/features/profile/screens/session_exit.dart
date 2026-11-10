import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:travibe/core/routing/app_routes.dart';
import 'package:travibe/features/auth/screens/login_screen.dart';

void openSignedOutScreen(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  // Login currently opens Root through Navigator.pushReplacement. In that
  // flow GoRouter still matches /login, so go(/login) reuses the missing page
  // and cannot remove imperative authenticated routes. Reset that stack directly.
  if (router != null &&
      router.routerDelegate.currentConfiguration.uri.path != AppRoutes.login) {
    router.go(AppRoutes.login);
  } else {
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }
}
