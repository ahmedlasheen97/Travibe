import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:travibe/core/routing/app_routes.dart';
import 'package:travibe/features/auth/screens/login_screen.dart';
import 'package:travibe/features/auth/screens/sign_up_screen.dart';

/// Back-navigation rules for the auth flow; see docs/AUTH_BACK_NAVIGATION.md.
///
/// Login is the bottom of the auth stack: Signup, OTP and Forgot password are
/// pushed on top so the back button, Android back and the iOS swipe all return
/// to the previous step with its input intact.
abstract final class AuthNavigation {
  /// Removes every route (router pages and pushed routes) and shows [builder].
  /// Used once an auth step completes so back never returns to auth screens.
  static void resetTo(
    BuildContext context,
    WidgetBuilder builder, {
    String? name,
  }) => Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(
      builder: builder,
      settings: RouteSettings(name: name),
    ),
    (_) => false,
  );

  /// Returns to the previous route when there is one, otherwise runs [orElse].
  static void back(BuildContext context, VoidCallback orElse) {
    final navigator = Navigator.of(context);
    navigator.canPop() ? navigator.pop() : orElse();
  }

  /// Signup's back target. Pops to the Login underneath when present;
  /// otherwise replaces the stack with Login.
  static void backToLogin(BuildContext context, {String email = ''}) =>
      back(context, () => toLogin(context, email: email));

  /// Shows Login (with [email] prefilled) as the only auth route.
  static void toLogin(BuildContext context, {String email = ''}) {
    final router = GoRouter.maybeOf(context);
    final query = email.isEmpty ? null : {'email': email};
    if (router != null &&
        router.routerDelegate.currentConfiguration.uri.path !=
            AppRoutes.login) {
      final previousRoute = ModalRoute.of(context);
      final navigator = Navigator.of(context);
      router.go(Uri(path: AppRoutes.login, queryParameters: query).toString());
      // A pushed route may sit above the router's former page. Remove that
      // old imperative route after Login is installed.
      if (previousRoute != null && previousRoute.settings is! Page) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (navigator.mounted && previousRoute.isActive) {
            navigator.removeRoute(previousRoute);
          }
        });
      }
      return;
    }
    resetTo(
      context,
      (_) => LoginScreen(initialEmail: email),
      name: AppRoutes.login,
    );
  }

  /// Shows Signup on top of Login, with [email] prefilled.
  static void toSignup(BuildContext context, {String email = ''}) {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.go(
        Uri(
          path: AppRoutes.register,
          queryParameters: email.isEmpty ? null : {'email': email},
        ).toString(),
      );
      return;
    }
    final navigator = Navigator.of(context);
    resetTo(context, (_) => const LoginScreen(), name: AppRoutes.login);
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => SignUpScreen(initialEmail: email),
      ),
    );
  }
}
