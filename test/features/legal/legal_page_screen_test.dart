import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:travibe/features/legal/data/legal_page.dart';
import 'package:travibe/features/legal/screens/legal_page_screen.dart';
import 'package:travibe/features/profile/screens/privacy_policy_screen.dart';
import 'package:travibe/features/profile/screens/terms_of_service_screen.dart';

import 'legal_fakes.dart';

final privacyUri = Uri.parse('https://travibeapp.com/privacy');
final deleteUri = Uri.parse('https://travibeapp.com/delete-account');

LegalPage termsWithLinks() => samplePage(
  LegalPageSlug.terms,
  blocks: [
    const LegalBlock([LegalSpan('7. Privacy', bold: true)], isHeading: true),
    LegalBlock([
      const LegalSpan('Read our '),
      LegalSpan('Privacy Policy', link: privacyUri),
      const LegalSpan(' or delete at '),
      LegalSpan('the website', link: deleteUri),
      const LegalSpan('.'),
    ]),
    const LegalBlock([
      LegalSpan('Email: '),
      LegalSpan('support@travibeapp.com', email: 'support@travibeapp.com'),
    ]),
  ],
);

void main() {
  late FakeLegalPagesRepo repo;
  late FakeLinkOpener opener;
  late List<String> clipboard;

  setUp(() {
    repo = FakeLegalPagesRepo(
      pages: {
        LegalPageSlug.terms: termsWithLinks(),
        LegalPageSlug.privacy: samplePage(LegalPageSlug.privacy),
      },
    );
    opener = FakeLinkOpener();
    clipboard = [];
  });

  Future<void> show(
    WidgetTester tester, {
    Widget? home,
    String language = 'en',
  }) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          locale: Locale(language),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: home ?? TermsOfServiceScreen(repo: repo, linkOpener: opener),
        ),
      ),
    );
  }

  testWidgets('white loader first, then the page in our style', (tester) async {
    repo.pending = Completer<void>();
    await show(tester);
    await tester.pump();
    expect(find.byKey(const ValueKey('legal-loading')), findsOneWidget);
    final spinner = tester.widget<CupertinoActivityIndicator>(
      find.byType(CupertinoActivityIndicator),
    );
    expect(spinner.color, DarkColors.whiteColor);
    expect(find.byType(BackButtonWidget), findsOneWidget);
    expect(find.text('Terms of Service'), findsOneWidget);

    repo.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('legal-loading')), findsNothing);
    expect(find.text('Last updated: 25 November 2026'), findsOneWidget);
    expect(find.text('7. Privacy'), findsOneWidget);
    expect(find.byKey(const ValueKey('legal-view-on-website')), findsOneWidget);
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      DarkColors.backgroundColor,
    );
  });

  testWidgets('external links open in the in-app browser, styled orange', (
    tester,
  ) async {
    await show(tester);
    await tester.pumpAndSettle();
    final rich = tester.widget<RichText>(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains('the website'),
      ),
    );
    TextSpan? linkSpan;
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.text == 'the website') linkSpan = span;
      return linkSpan == null;
    });
    expect(linkSpan?.style?.color, DarkColors.primaryColor);

    await tester.tapOnText(find.textRange.ofSubstring('the website'));
    await tester.pumpAndSettle();
    expect(opener.opened, [deleteUri]);
  });

  testWidgets('a link to our Privacy Policy opens the native screen', (
    tester,
  ) async {
    await show(tester);
    await tester.pumpAndSettle();
    await tester.tapOnText(find.textRange.ofSubstring('Privacy Policy'));
    await tester.pumpAndSettle();
    expect(opener.opened, isEmpty);
    final screens = tester.widgetList<LegalPageScreen>(
      find.byType(LegalPageScreen),
    );
    expect(screens.last.slug, LegalPageSlug.privacy);
    expect(find.text('Privacy Policy'), findsWidgets);
    expect(repo.fetches, [LegalPageSlug.terms, LegalPageSlug.privacy]);

    await tester.tap(find.byType(BackButtonWidget).last);
    await tester.pumpAndSettle();
    expect(find.text('7. Privacy'), findsOneWidget);
  });

  testWidgets('tapping an email copies it and shows Copied', (tester) async {
    await show(tester);
    await tester.pumpAndSettle();
    await tester.tapOnText(
      find.textRange.ofSubstring('support@travibeapp.com'),
    );
    await tester.pump();
    expect(clipboard, ['support@travibeapp.com']);
    expect(find.text('Copied'), findsOneWidget);
    expect(opener.opened, isEmpty);
    await tester.pumpAndSettle(const Duration(seconds: 4));
  });

  testWidgets('a link that cannot open shows the red toast', (tester) async {
    opener.succeeds = false;
    await show(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('legal-view-on-website')));
    await tester.pump();
    expect(opener.opened, [LegalPageSlug.terms.webUri]);
    expect(find.text(LegalPageScreen.openFailedMessage), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('offline without a cache: fallback, Open in browser, Refresh', (
    tester,
  ) async {
    repo.pages[LegalPageSlug.terms] = null;
    await show(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('legal-unavailable')), findsOneWidget);
    // The fallback text plus the toast.
    expect(find.text(LegalPageScreen.loadFailedMessage), findsNWidgets(2));
    expect(find.text('Refresh'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('legal-open-in-browser')));
    await tester.pump();
    expect(opener.opened, [Uri.parse('https://travibeapp.com/terms')]);

    repo.pages[LegalPageSlug.terms] = termsWithLinks();
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(repo.fetches.length, 2);
    expect(find.text('7. Privacy'), findsOneWidget);
    expect(find.byKey(const ValueKey('legal-unavailable')), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('offline with a cache shows the cached copy and the toast', (
    tester,
  ) async {
    repo = FakeLegalPagesRepo(
      pages: {LegalPageSlug.terms: null},
      cache: {LegalPageSlug.terms: termsWithLinks()},
    );
    await show(tester);
    await tester.pumpAndSettle();
    expect(find.text('7. Privacy'), findsOneWidget);
    expect(find.text(LegalPageScreen.loadFailedMessage), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('the English page stays LTR when the app is in Arabic', (
    tester,
  ) async {
    await show(tester, language: 'ar');
    await tester.pumpAndSettle();
    final text = find.text('7. Privacy');
    expect(Directionality.of(tester.element(text)), TextDirection.ltr);
  });

  testWidgets('Privacy screen loads the privacy page', (tester) async {
    await show(
      tester,
      home: PrivacyPolicyScreen(repo: repo, linkOpener: opener),
    );
    await tester.pumpAndSettle();
    expect(repo.fetches, [LegalPageSlug.privacy]);
    expect(find.text('1. Who can use Travibe'), findsOneWidget);
  });

  test('dates format like the website', () {
    expect(formatLegalDate(DateTime(2026, 11, 25)), '25 November 2026');
    expect(formatLegalDate(DateTime(2027, 1, 3)), '3 January 2027');
  });
}
