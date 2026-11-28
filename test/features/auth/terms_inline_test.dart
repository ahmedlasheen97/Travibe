import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/auth/widgets/terms_privacy_checkbox.dart';
import 'package:travibe/features/legal/screens/legal_page_screen.dart';
import 'package:travibe/features/profile/screens/privacy_policy_screen.dart';
import 'package:travibe/features/profile/screens/terms_of_service_screen.dart';

import '../legal/legal_fakes.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
          'Plus Jakarta Sans',
        )..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-Regular.ttf')))
        .load();
  });
  Future<void> show(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
    String language = 'en',
    ValueChanged<bool>? changed,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          locale: Locale(language),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(8),
              child: TermsAndPrivacyCheckbox(
                onChanged: changed,
                legalPagesRepo: FakeLegalPagesRepo(),
                linkOpener: FakeLinkOpener(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder getSentence() => find.byKey(const ValueKey('signup-legal-sentence'));
  RichText rich(WidgetTester tester) => tester.widget<RichText>(
    find.descendant(of: getSentence(), matching: find.byType(RichText)),
  );
  List<TextSpan> links(WidgetTester tester) {
    final result = <TextSpan>[];
    void visit(InlineSpan span) {
      if (span is TextSpan) {
        if (span.recognizer != null) result.add(span);
        span.children?.forEach(visit);
      }
    }

    visit(rich(tester).text);
    return result;
  }

  for (final width in [320.0, 375.0, 393.0, 430.0]) {
    for (final language in ['en', 'ar']) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'inline agreement wraps naturally $width $language ${scale}x',
          (tester) async {
            await show(tester, width: width, language: language, scale: scale);
            final paragraphFinder = find.descendant(
              of: getSentence(),
              matching: find.byType(RichText),
            );
            final paragraph = tester.renderObject<RenderParagraph>(
              paragraphFinder,
            );
            final widget = rich(tester);
            final painter = TextPainter(
              text: paragraph.text,
              textAlign: widget.textAlign,
              textDirection: language == 'ar'
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              textScaler: TextScaler.linear(scale),
            )..layout(maxWidth: paragraph.size.width);
            addTearDown(painter.dispose);
            final metrics = painter.computeLineMetrics();
            expect(paragraph.size.height, closeTo(painter.height, .1));
            expect(
              (paragraph.text as TextSpan).children!.whereType<WidgetSpan>(),
              isEmpty,
            );
            expect(
              find.descendant(
                of: find.byType(TermsAndPrivacyCheckbox),
                matching: find.byType(Wrap),
              ),
              findsNothing,
            );
            expect(find.byType(TextButton), findsNothing);
            expect(links(tester), hasLength(2));
            expect(
              links(
                tester,
              ).every((s) => s.style!.color == DarkColors.primaryColor),
              true,
            );
            expect(
              paragraph.text.toPlainText(),
              language == 'ar'
                  ? 'أوافق على شروط الخدمة وسياسة الخصوصية'
                  : 'I agree to the Terms of Service and Privacy Policy',
            );
            expect((paragraph.text as TextSpan).style!.height, 1.4);
            if (scale == 2) expect(metrics.length, greaterThan(1));
            for (var i = 1; i < metrics.length; i++) {
              expect(
                metrics[i].baseline - metrics[i - 1].baseline,
                closeTo(metrics[i].height, 1),
              );
            }
            final firstLineCenter =
                tester.getTopLeft(paragraphFinder).dy +
                metrics.first.height / 2;
            expect(
              firstLineCenter,
              closeTo(tester.getCenter(find.byType(Checkbox)).dy, 1),
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }

  for (final language in ['en', 'ar']) {
    for (final terms in [true, false]) {
      testWidgets(
        'independent inline ${terms ? 'Terms' : 'Privacy'} link $language preserves consent',
        (tester) async {
          final changes = <bool>[];
          await show(
            tester,
            width: 320,
            scale: 2,
            language: language,
            changed: changes.add,
          );
          final originalRecognizers = links(
            tester,
          ).map((e) => e.recognizer).toList();
          final label = language == 'ar'
              ? (terms ? 'شروط الخدمة' : 'سياسة الخصوصية')
              : (terms ? 'Terms of Service' : 'Privacy Policy');
          await tester.tapOnText(
            find.textRange.ofSubstring(label, descendentOf: getSentence()),
          );
          await tester.pumpAndSettle();
          expect(
            find.byType(terms ? TermsOfServiceScreen : PrivacyPolicyScreen),
            findsOneWidget,
          );
          expect(find.byType(LegalPageScreen), findsOneWidget);
          expect(changes, isEmpty);
          await tester.tap(
            find.byTooltip(
              MaterialLocalizations.of(
                tester.element(find.byType(LegalPageScreen)),
              ).backButtonTooltip,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, false);
          await tester.tap(find.byType(Checkbox));
          await tester.pump();
          expect(changes, [true]);
          expect(links(tester).map((e) => e.recognizer), originalRecognizers);
          expect(
            originalRecognizers.every((e) => e is TapGestureRecognizer),
            true,
          );
          await tester.pumpWidget(const SizedBox());
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('rapid inline taps open only one legal route', (tester) async {
    await show(tester);
    final tap = links(tester).first.recognizer as TapGestureRecognizer;
    tap.onTap!();
    tap.onTap!();
    await tester.pumpAndSettle();
    expect(find.byType(TermsOfServiceScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(TermsAndPrivacyCheckbox), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
