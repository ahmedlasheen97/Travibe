class AppRoutes {
  AppRoutes._();

  // Onboarding / Auth
  static const String splash = '/splash';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String register = '/register';
  static const String otpVerification = '/otp-verification';
  static const String profileSetup = '/profile-setup';

  static const String emailVerification = '/email-verification/:id/:hash';

  // Root shell tabs
  static const String root = '/root';
  static const String home = '/home';
  static const String explore = '/explore';
  static const String buddies = '/buddies';
  static const String profile = '/profile';

  // Settings
  static const String settings = '/settings';
  static const String changePassword = '/settings/change-password';
  static const String currency = '/settings/currency';
  static const String blockedAccounts = '/settings/blocked-accounts';
  static const String reportProblem = '/settings/report-problem';
  static const String termsOfService = '/settings/terms';
  static const String privacyPolicy = '/settings/privacy';
  static const String deleteAccount = '/settings/delete-account';

  // Edit profile
  static const String editProfile = '/profile/edit';
  static const String editLanguages = '/profile/edit/languages';
  static const String editInterests = '/profile/edit/interests';
  static const String editTravelStyle = '/profile/edit/travel-style';

  // Helper to build the deep-link path with real values
  static String emailVerificationPath(String id, String hash) =>
      '/email-verification/$id/$hash';
}
