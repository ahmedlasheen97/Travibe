import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/features/home/widgets/report_reason_sheet.dart';

void main() {
  late ReportSubmission? result;
  late bool closed;

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    result = null;
    closed = false;
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await ReportReasonSheet.show(context);
                  closed = true;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  ElevatedButton submit(WidgetTester tester) => tester.widget<ElevatedButton>(
    find.descendant(
      of: find.byKey(const ValueKey('report-submit')),
      matching: find.byType(ElevatedButton),
    ),
  );

  testWidgets('matches Figma copy; submit disabled until a reason', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Why are you reporting this?'), findsOneWidget);
    for (final reason in ReportReason.values) {
      expect(find.text(reason.label), findsOneWidget);
    }
    expect(find.text('Submit Report'), findsOneWidget);
    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(
      sheet.shape,
      const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    );
    expect(submit(tester).onPressed, isNull);
    expect(find.byKey(const ValueKey('report-details')), findsNothing);

    await tester.tap(find.text('Harassment'));
    await tester.pump();
    expect(submit(tester).onPressed, isNotNull);
    await tester.tap(find.text('Submit Report'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result!.reason, ReportReason.harassment);
    expect(result!.description, isNull);
  });

  testWidgets('Something else reveals an optional free-text field', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Something else'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('report-details'));
    expect(field, findsOneWidget);
    expect(tester.widget<TextField>(field).maxLength, 1000);
    await tester.enterText(field, '  Selling fake tours  ');
    await tester.tap(find.text('Submit Report'));
    await tester.pumpAndSettle();
    expect(result!.reason, ReportReason.somethingElse);
    expect(result!.description, 'Selling fake tours');
  });

  testWidgets('text typed for Something else is dropped for other reasons', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Something else'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('report-details')), 'x');
    await tester.tap(find.text('Spam or scam'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('report-details')), findsNothing);
    await tester.tap(find.text('Submit Report'));
    await tester.pumpAndSettle();
    expect(result!.reason, ReportReason.spamOrScam);
    expect(result!.description, isNull);
  });

  testWidgets('dismissing returns null', (tester) async {
    await open(tester);
    await tester.tapAt(const Offset(195, 50));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
  });
}
