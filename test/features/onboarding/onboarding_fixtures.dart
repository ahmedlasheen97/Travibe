import 'dart:async';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/features/onboarding/data/onboarding_repo.dart';
import 'package:travibe/features/onboarding/data/models/onboarding_model.dart';
import 'package:travibe/features/onboarding/data/models/app_locale.dart';

Map<String, dynamic> slideJson() => {
  'data': [
    {
      'key': 'discover',
      'title': 'Discover places from the server',
      'body': 'Server discovery copy.',
      'asset_url': null,
    },
    {
      'key': 'plan',
      'title': 'Plan journeys from the server',
      'body': 'Server planning copy.',
      'asset_url': null,
    },
    {
      'key': 'together',
      'title': 'Travel together from the server',
      'body': 'Server social copy.',
      'asset_url': null,
    },
  ],
};
Map<String, dynamic> localesJson() => {
  'data': {
    'locales': [
      {'code': 'en', 'name': 'English', 'rtl': false},
      {'code': 'ar', 'name': 'العربية', 'rtl': true},
    ],
    'default': 'en',
  },
};

class FakeOnboardingRepo extends OnboardingRepo {
  Object? failure;
  Completer<List<OnboardingModel>>? gate;
  int slideCalls = 0;
  final requestedLocales = <String>[];
  @override
  Future<List<OnboardingModel>> slides(String locale) async {
    slideCalls++;
    requestedLocales.add(locale);
    if (failure != null) throw failure!;
    return gate == null ? OnboardingModel.parse(slideJson()) : gate!.future;
  }

  @override
  Future<LocaleCatalog> locales(String locale) async =>
      LocaleCatalog.parse(localesJson());
}

ProfileModel startupUser({
  bool verified = true,
  bool complete = true,
  String locale = 'en',
}) => ProfileModel(
  id: '7',
  email: 'traveler@example.invalid',
  locale: locale,
  emailVerifiedAt: verified ? '2026-10-01T00:00:00Z' : null,
  profileCompleted: complete,
);

class StartupAuth extends AuthRepo {
  int calls = 0;
  Future<ProfileModel> Function() handler = () async => startupUser();
  @override
  Future<ProfileModel> currentUser() {
    calls++;
    return handler();
  }
}

class InvalidStartupAuth extends StartupAuth {
  InvalidStartupAuth() {
    handler = () async =>
        throw ApiError(message: 'Unauthenticated', statusCode: 401);
  }
}
