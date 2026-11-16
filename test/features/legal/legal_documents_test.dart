import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/routing/app_routes.dart';
import 'package:travibe/core/routing/router_generator.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/custom_button.dart';
import 'package:travibe/core/widgets/custom_text_field.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'package:travibe/features/auth/data/auth_response_model.dart';
import 'package:travibe/features/auth/screens/sign_up_screen.dart';
import 'package:travibe/features/auth/widgets/terms_privacy_checkbox.dart';
import 'package:travibe/features/legal/data/legal_documents.dart';
import 'package:travibe/features/profile/screens/terms_of_service_screen.dart';
import 'package:travibe/features/profile/screens/privacy_policy_screen.dart';
import 'package:travibe/features/profile/screens/settings_screen.dart';
import 'package:travibe/features/profile/widgets/legal_text_screen.dart';
import '../profile/settings_privacy_test.dart' as settings;

class ConsentRepo extends AuthRepo {
  int calls = 0;
  bool? accepted;
  @override
  Future<AuthResponseModel> register({
    required String email,
    required String password,
    required String passwordConfirmation,
    required bool termsAccepted,
    String? locale,
  }) async {
    calls++;
    accepted = termsAccepted;
    throw ApiError(message: 'Fixture registration response', statusCode: 503);
  }
}

Widget harness(
  Widget home, {
  String language = 'en',
  double scale = 1,
  bool previewFonts = false,
}) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder: (_, _) => MaterialApp(
    theme: previewFonts
        ? darkTheme.copyWith(
            textTheme: darkTheme.textTheme.apply(
              fontFamilyFallback: const ['Legal Arabic Preview'],
            ),
          )
        : darkTheme,
    locale: Locale(language),
    supportedLocales: const [Locale('en'), Locale('ar')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: home,
  ),
);
Widget page(LegalDocumentType type) => type == LegalDocumentType.terms
    ? const TermsOfServiceScreen()
    : const PrivacyPolicyScreen();
Finder input(String title) => find.descendant(
  of: find.byWidgetPredicate((w) => w is CustomTextField && w.title == title),
  matching: find.byType(TextFormField),
);
Future<void> visibleTap(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 400, maxScrolls: 100);
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> tapConsentLink(
  WidgetTester tester,
  LegalDocumentType type, {
  String language = 'en',
}) async {
  final paragraph = find.byKey(const ValueKey('signup-legal-sentence'));
  await tester.ensureVisible(paragraph);
  await tester.pumpAndSettle();
  final label = language == 'ar'
      ? (type == LegalDocumentType.terms ? 'شروط الخدمة' : 'سياسة الخصوصية')
      : (type == LegalDocumentType.terms
            ? 'Terms of Service'
            : 'Privacy Policy');
  await tester.tapOnText(
    find.textRange.ofSubstring(label, descendentOf: paragraph),
  );
  await tester.pumpAndSettle();
}

SemanticsNode? consentLinkNode(WidgetTester tester, String identifier) {
  final root = tester.getSemantics(
    find.byKey(const ValueKey('signup-legal-sentence')),
  );
  SemanticsNode? found;
  void visit(SemanticsNode node) {
    if (node.identifier == identifier) found = node;
    node.visitChildren((child) {
      visit(child);
      return found == null;
    });
  }

  visit(root);
  return found;
}

void main() {
  final prefs = PreferencesManager();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await prefs.init();
  });

  test(
    'bilingual drafts have matching section coverage, metadata and unresolved facts',
    () {
      for (final type in LegalDocumentType.values) {
        final en = LegalDocuments.get(type, 'en'),
            ar = LegalDocuments.get(type, 'ar');
        expect(en.sections.map((s) => s.id), ar.sections.map((s) => s.id));
        expect(en.sections.length, type == LegalDocumentType.terms ? 15 : 17);
        expect(en.sections.map((s) => s.id).toSet().length, en.sections.length);
        for (final doc in [en, ar]) {
          expect(doc.reviewNotice, isNotEmpty);
          expect(
            doc.sections.every(
              (s) => s.heading.isNotEmpty && s.body.isNotEmpty,
            ),
            true,
          );
          expect(doc.sections.last.id, 'contact');
          expect(
            doc.sections.last.body,
            contains(doc.languageCode == 'ar' ? 'يلزم التأكيد' : 'To confirm'),
          );
          expect(
            doc.sections.map((s) => s.body).join(),
            isNot(contains('Lasheen Technologies')),
          );
        }
      }
      expect(LegalDocument.requiresLegalReview, true);
      expect(LegalDocument.effectiveDateIso, isNull);
      expect(DateTime.tryParse(LegalDocument.lastUpdatedIso), isNotNull);
      expect(LegalDocument.contentVersion, startsWith('draft-'));
      expect(
        LegalDocuments.get(LegalDocumentType.terms, 'unsupported').languageCode,
        'en',
      );
    },
  );

  test(
    'preferred public URLs are metadata, not unverified network navigation',
    () {
      expect(
        LegalDocuments.get(
          LegalDocumentType.terms,
          'en',
        ).preferredPublicUrl.toString(),
        'https://travibeapp.com/terms',
      );
      expect(
        LegalDocuments.get(
          LegalDocumentType.privacy,
          'ar',
        ).preferredPublicUrl.toString(),
        'https://travibeapp.com/privacy',
      );
    },
  );

  for (final language in ['en', 'ar']) {
    for (final type in LegalDocumentType.values) {
      for (final width in [320.0, 375.0, 393.0, 430.0]) {
        testWidgets(
          '${type.name} $language at $width supports 2x text and scrolling to contact',
          (tester) async {
            tester.view.physicalSize = Size(width, 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pumpWidget(
              harness(page(type), language: language, scale: 2),
            );
            await tester.pumpAndSettle();
            final doc = LegalDocuments.get(type, language);
            expect(find.text(doc.title), findsOneWidget);
            expect(find.text(doc.lastUpdatedText), findsOneWidget);
            expect(find.text(doc.effectiveDateText), findsOneWidget);
            expect(
              Directionality.of(tester.element(find.byType(LegalTextScreen))),
              language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
            );
            expect(prefs.hasSession, false);
            await tester.scrollUntilVisible(
              find.byKey(const ValueKey('legal-section-contact')),
              800,
              maxScrolls: 150,
            );
            expect(find.text(doc.sections.last.heading), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }

  for (final type in LegalDocumentType.values) {
    testWidgets(
      'existing Settings row opens ${type.name} and returns without changing settings',
      (tester) async {
        await prefs.saveToken('fixture-session');
        final api = settings.SettingsApi();
        final current = settings.settingsCubit(api);
        await current.load();
        await tester.pumpWidget(harness(SettingsScreen(currentUser: current)));
        await tester.pumpAndSettle();
        final title = LegalDocuments.get(type, 'en').title;
        await tester.scrollUntilVisible(find.text(title), 300);
        expect(find.text('Help & Legal'), findsOneWidget);
        expect(find.text(title), findsOneWidget);
        await visibleTap(tester, find.text(title));
        expect(find.byType(LegalTextScreen), findsOneWidget);
        expect(
          find.text(LegalDocuments.get(type, 'en').lastUpdatedText),
          findsOneWidget,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(api.patches, isEmpty);
        expect(prefs.hasSession, true);
        await tester.pumpWidget(const SizedBox());
        await current.close();
      },
    );
  }

  for (final type in LegalDocumentType.values) {
    testWidgets(
      'Sign Up ${type.name} link is public, accessible and does not change consent',
      (tester) async {
        final changes = <bool>[];
        await tester.pumpWidget(
          harness(
            Scaffold(body: TermsAndPrivacyCheckbox(onChanged: changes.add)),
          ),
        );
        await tester.pumpAndSettle();
        final semantics = tester.ensureSemantics();
        await tester.pump();
        final link = consentLinkNode(
          tester,
          type == LegalDocumentType.terms
              ? 'signup-terms-link'
              : 'signup-privacy-link',
        );
        expect(link, isNotNull);
        expect(link!.flagsCollection.isLink, true);
        expect(link.getSemanticsData().hasAction(SemanticsAction.tap), true);
        await tapConsentLink(tester, type);
        expect(find.byType(LegalTextScreen), findsOneWidget);
        expect(prefs.hasSession, false);
        expect(changes, isEmpty);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, false);
        await tester.tap(find.byType(Checkbox));
        await tester.pump();
        expect(changes, [true]);
        await tapConsentLink(tester, type);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, true);
        expect(changes, [true]);
        await tester.pumpWidget(const SizedBox());
        semantics.dispose();
      },
    );
  }

  testWidgets(
    'actual signup retains form values and still requires explicit acceptance before register',
    (tester) async {
      final repo = ConsentRepo();
      await tester.pumpWidget(harness(SignUpScreen(authRepo: repo)));
      await tester.pumpAndSettle();
      for (final entry in {
        'Email': 'legal@example.invalid',
        'Password': 'ValidPass123!',
        'Confirm Password': 'ValidPass123!',
      }.entries) {
        await tester.ensureVisible(input(entry.key));
        await tester.enterText(input(entry.key), entry.value);
      }
      await tapConsentLink(tester, LegalDocumentType.terms);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(input('Email')).controller!.text,
        'legal@example.invalid',
      );
      expect(
        tester.widget<TextFormField>(input('Password')).controller!.text,
        'ValidPass123!',
      );
      await visibleTap(tester, find.byType(CustomButton));
      expect(repo.calls, 0);
      expect(
        find.text('Please accept the Terms & Privacy Policy'),
        findsOneWidget,
      );
      await visibleTap(tester, find.byType(Checkbox));
      await tapConsentLink(tester, LegalDocumentType.privacy);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await visibleTap(tester, find.byType(CustomButton));
      expect(repo.calls, 1);
      expect(repo.accepted, true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final route in [AppRoutes.termsOfService, AppRoutes.privacyPolicy]) {
    testWidgets('public GoRouter route $route works without a session', (
      tester,
    ) async {
      final source = RouterGenerator.createRouter();
      final router = GoRouter(
        initialLocation: route,
        routes: source.configuration.routes,
      );
      source.dispose();
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) =>
              MaterialApp.router(theme: darkTheme, routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LegalTextScreen), findsOneWidget);
      expect(prefs.hasSession, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    });
  }

  testWidgets(
    'related document opens locally and Back restores the original document',
    (tester) async {
      await tester.pumpWidget(harness(const TermsOfServiceScreen()));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('legal-related-document')),
        800,
        maxScrolls: 150,
      );
      await visibleTap(
        tester,
        find.byKey(const ValueKey('legal-related-document')),
      );
      expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(TermsOfServiceScreen), findsOneWidget);
      expect(prefs.hasSession, false);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final language in ['en', 'ar']) {
    testWidgets(
      'legal header semantics and $language landscape layout render accessibly',
      (tester) async {
        tester.view.physicalSize = const Size(844, 390);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          harness(const PrivacyPolicyScreen(), language: language, scale: 2.5),
        );
        await tester.pumpAndSettle();
        final title = LegalDocuments.get(
          LegalDocumentType.privacy,
          language,
        ).title;
        expect(
          tester.getSemantics(find.text(title)).flagsCollection.isHeader,
          true,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        semantics.dispose();
      },
    );
  }

  testWidgets(
    'Arabic signup legal links follow RTL and do not accept on open',
    (tester) async {
      await tester.pumpWidget(
        harness(
          const Scaffold(body: TermsAndPrivacyCheckbox()),
          language: 'ar',
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('شروط الخدمة', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('سياسة الخصوصية', findRichText: true),
        findsOneWidget,
      );
      await tapConsentLink(tester, LegalDocumentType.privacy, language: 'ar');
      expect(find.text('سياسة الخصوصية'), findsOneWidget);
      await tester.tap(
        find.byTooltip(
          MaterialLocalizations.of(
            tester.element(find.byType(LegalTextScreen)),
          ).backButtonTooltip,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('legal reader captures English and Arabic review frames', (
    tester,
  ) async {
    if (const bool.fromEnvironment('LEGAL_SCREENSHOTS')) {
      await tester.runAsync(() async {
        final font = FontLoader('Plus Jakarta Sans');
        for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
          font.addFont(
            rootBundle.load('assets/fonts/PlusJakartaSans-$weight.ttf'),
          );
        }
        await font.load();
        final arabicFile = File('/System/Library/Fonts/SFArabic.ttf');
        if (await arabicFile.exists()) {
          final bytes = await arabicFile.readAsBytes();
          final arabic = FontLoader('Legal Arabic Preview')
            ..addFont(Future.value(ByteData.sublistView(bytes)));
          await arabic.load();
        }
      });
    }
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final language in ['en', 'ar']) {
      await tester.pumpWidget(
        harness(
          RepaintBoundary(
            key: const ValueKey('legal-capture'),
            child: page(
              language == 'en'
                  ? LegalDocumentType.terms
                  : LegalDocumentType.privacy,
            ),
          ),
          language: language,
          previewFonts: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('LEGAL_SCREENSHOTS')) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('legal-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '/private/tmp/travibe-legal-$language.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    await tester.pumpWidget(const SizedBox());
  });
}
