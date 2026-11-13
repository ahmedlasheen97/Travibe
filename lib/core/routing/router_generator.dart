import 'package:go_router/go_router.dart';
import 'package:travibe/core/routing/app_routes.dart';
import 'package:travibe/features/auth/screens/login_screen.dart';
import 'package:travibe/features/auth/screens/otp_verification_screen.dart';
import 'package:travibe/features/auth/screens/sign_up_screen.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'package:travibe/features/onboarding/data/onboarding_repo.dart';
import 'package:travibe/features/onboarding/screens/onboarding_screen.dart';
import 'package:travibe/features/onboarding/screens/startup_screen.dart';
import 'package:travibe/features/onboarding/cubit/startup_cubit.dart';
import 'package:travibe/features/onboarding/cubit/session_revalidator.dart';
import 'package:travibe/features/profilesetup/screens/profile_setup_screen.dart';
import 'package:travibe/root.dart';

class RouterGenerator {
  static GoRouter router = createRouter();

  static GoRouter createRouter({
    AuthRepo? auth,
    OnboardingRepo? onboardingRepo,
  }) => GoRouter(
    initialLocation: AppRoutes.splash,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        pageBuilder: (context, state) => NoTransitionPage(
          child: StartupScreen(
            auth: auth,
            onboardingRepo: onboardingRepo,
            onReady: (decision) => context.go(switch (decision.target) {
              StartupTarget.onboarding => AppRoutes.onboarding,
              StartupTarget.home => AppRoutes.root,
              StartupTarget.login => AppRoutes.login,
              StartupTarget.profileSetup => AppRoutes.profileSetup,
              StartupTarget.verification => Uri(
                path: AppRoutes.otpVerification,
                queryParameters: {'email': decision.email!},
              ).toString(),
            }, extra: decision.offline ? const OfflineStartup() : null),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        name: AppRoutes.onboarding,
        pageBuilder: (context, state) =>
            NoTransitionPage(child: OnboardingScreen(repo: onboardingRepo)),
      ),
      GoRoute(
        path: AppRoutes.login,
        name: AppRoutes.login,
        builder: (context, state) =>
            LoginScreen(initialEmail: state.uri.queryParameters['email'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.register,
        name: AppRoutes.register,
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: AppRoutes.root,
        name: AppRoutes.root,
        builder: (context, state) =>
            Root(revalidateSession: state.extra is OfflineStartup),
      ),
      GoRoute(
        path: AppRoutes.otpVerification,
        name: AppRoutes.otpVerification,
        builder: (context, state) => OtpVerificationScreen(
          email: state.uri.queryParameters['email'] ?? '',
        ),
      ),
      GoRoute(
        path: AppRoutes.profileSetup,
        builder: (context, state) => const ProfileSetupScreen(),
      ),
    ],
  );
}
