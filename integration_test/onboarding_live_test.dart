import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/main.dart' as app;
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/routing/router_generator.dart';
import 'package:travibe/features/onboarding/data/onboarding_repo.dart';
import 'package:travibe/features/onboarding/data/models/onboarding_model.dart';
import 'package:travibe/features/onboarding/screens/onboarding_screen.dart';
import 'package:travibe/features/auth/screens/sign_up_screen.dart';
import 'support/test_reporting.dart';

/// Public endpoint diagnostics: never log request headers, credentials, slide
/// copy, raw server bodies or arbitrary exception messages.
class OnboardingProbe {
  final requests = <Map<String, Object?>>[];
  List<OnboardingModel>? serverSlides;
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://travibeapp.com/api/v1/',
      connectTimeout: OnboardingRepo.connectionTimeout,
      receiveTimeout: OnboardingRepo.responseTimeout,
    ),
  );
  OnboardingProbe() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.extra['probeClock'] = Stopwatch()..start();
          handler.next(options);
        },
        onResponse: (response, handler) {
          final body = response.data;
          String? parsing;
          if (response.requestOptions.path == 'onboarding' &&
              response.statusCode == 200) {
            try {
              serverSlides = OnboardingModel.parse(body);
              parsing = 'ok';
            } on FormatException catch (e) {
              parsing = e.message;
            }
          }
          final record = <String, Object?>{
            'path': response.requestOptions.path,
            'elapsedMs':
                (response.requestOptions.extra['probeClock'] as Stopwatch?)
                    ?.elapsedMilliseconds,
            'status': response.statusCode,
            'responseType': body.runtimeType.toString(),
            'parser': parsing,
            'dataType': body is Map
                ? body['data'].runtimeType.toString()
                : null,
          };
          requests.add(record);
          debugPrint('ONBOARDING_PROBE ${jsonEncode(record)}');
          handler.next(response);
        },
        onError: (error, handler) {
          final record = <String, Object?>{
            'path': error.requestOptions.path,
            'elapsedMs':
                (error.requestOptions.extra['probeClock'] as Stopwatch?)
                    ?.elapsedMilliseconds,
            'status': error.response?.statusCode,
            'dioType': error.type.name,
            'causeType': error.error.runtimeType.toString(),
          };
          requests.add(record);
          debugPrint('ONBOARDING_PROBE ${jsonEncode(record)}');
          handler.next(error);
        },
      ),
    );
  }
}

class ObservedOnboardingRepo extends OnboardingRepo {
  ObservedOnboardingRepo(Dio http) : super(transport: http);
  @override
  Future<List<OnboardingModel>> slides(String locale) async {
    try {
      return await super.slides(locale);
    } catch (e, s) {
      final category = e.toString().contains('header has more than one value')
          ? 'multiple_header_values'
          : e.runtimeType.toString();
      debugPrint('ONBOARDING_PROBE repo_failure=$category');
      for (final line
          in s
              .toString()
              .split('\n')
              .where(
                (l) =>
                    l.contains('onboarding_repo.dart') ||
                    l.contains('dio/src/headers.dart'),
              )) {
        debugPrint('ONBOARDING_PROBE frame=$line');
      }
      rethrow;
    }
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerTestReporting(binding);
  testWidgets('real onboarding HTTP, retry and skip diagnostics on Simulator', (
    tester,
  ) async {
    final preferences = PreferencesManager();
    await preferences.init();
    final language = preferences.getLanguage();
    // Test-only in-process preferences; no native session/flag is cleared or saved.
    SharedPreferences.setMockInitialValues({'selected_language': language});
    await preferences.init();
    debugPrint(
      'ONBOARDING_PROBE locale=${{'en', 'ar'}.contains(language) ? language : 'unsupported'}',
    );
    final probe = OnboardingProbe();
    final repo = ObservedOnboardingRepo(probe.dio);
    final router = RouterGenerator.createRouter(onboardingRepo: repo);
    await tester.pumpWidget(app.MyApp(router: router));
    Future<void> waitForContent() async {
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 250)),
        );
        await tester.pump(const Duration(milliseconds: 250));
        if (find.text('Unable to load onboarding.').evaluate().isNotEmpty ||
            find.text('تعذر تحميل المقدمة.').evaluate().isNotEmpty ||
            find.text('Next').evaluate().isNotEmpty ||
            find.text('التالي').evaluate().isNotEmpty) {
          break;
        }
      }
    }

    await waitForContent();
    expect(find.byType(OnboardingScreen), findsOneWidget);
    final error =
        find.text('Unable to load onboarding.').evaluate().isNotEmpty ||
        find.text('تعذر تحميل المقدمة.').evaluate().isNotEmpty;
    debugPrint(
      'ONBOARDING_PROBE first_ui=${error ? 'error' : 'content'} requests=${probe.requests.length}',
    );
    if (error) {
      final before = probe.requests
          .where((r) => r['path'] == 'onboarding')
          .length;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await waitForContent();
      final after = probe.requests
          .where((r) => r['path'] == 'onboarding')
          .length;
      debugPrint('ONBOARDING_PROBE retry_new_request=${after > before}');
      debugPrint(
        'ONBOARDING_PROBE retry_ui=${find.text('Next').evaluate().isNotEmpty || find.text('التالي').evaluate().isNotEmpty ? 'content' : 'error'}',
      );
      expect(after, greaterThan(before));
    }
    // This assertion requires real backend copy in the actual screen, not just
    // a passing HTTP/model check or a successful native build.
    expect(probe.serverSlides, isNotNull);
    expect(find.text(probe.serverSlides!.first.title), findsOneWidget);
    expect(find.text('Unable to load onboarding.'), findsNothing);
    debugPrint('ONBOARDING_PROBE real_backend_slide_visible=true');
    final skip = find.text(language == 'ar' ? 'تخطي' : 'Skip');
    await tester.ensureVisible(skip);
    await tester.tap(skip);
    await tester.pumpAndSettle();
    expect(find.byType(SignUpScreen), findsOneWidget);
    expect(preferences.onboardingCompleted, true);
    expect(preferences.hasSession, false);
    debugPrint(
      'ONBOARDING_PROBE skip=signup completion=true credentials_unchanged=true',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
    probe.dio.close(force: true);
  });
}
