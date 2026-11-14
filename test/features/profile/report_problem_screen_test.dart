import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/create_post/data/post_image.dart';
import 'package:travibe/features/create_post/data/post_image_picker.dart';
import 'package:travibe/features/profile/data/support_repo.dart';
import 'package:travibe/features/profile/screens/report_problem_screen.dart';

import '../../helpers/fake_network_images.dart' show transparentPng;

class _Picker extends PostImagePicker {
  final limits = <int>[];
  int rejected = 0;
  int next = 0;

  @override
  Future<PostImagePick> pickGallery({required int limit}) async {
    limits.add(limit);
    return PostImagePick([
      for (var i = 0; i < limit; i++)
        PostImage(
          localId: 'shot-${next++}',
          bytes: transparentPng,
          filename: 'shot.png',
          contentType: 'image/png',
        ),
    ], rejected: rejected);
  }
}

class _Support extends SupportRepo {
  final uploaded = <String>[];
  final reports = <Map<String, Object>>[];
  Completer<void>? pending;
  Object? failure;

  @override
  Future<int> uploadScreenshot(
    PostImage image, {
    required bool Function() isActive,
    required CancelToken cancelToken,
  }) async {
    uploaded.add(image.localId);
    return 100 + uploaded.length;
  }

  @override
  Future<void> reportProblem({
    required String category,
    required String description,
    List<int> mediaIds = const [],
  }) async {
    reports.add({
      'category': category,
      'description': description,
      'media_ids': mediaIds,
    });
    if (pending case final wait?) await wait.future;
    if (failure case final error?) throw error;
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('report-problem-test');
  });
  tearDown(() => PreferencesManager().clear());

  Future<void> show(WidgetTester tester, _Support repo, _Picker picker) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ReportProblemScreen(repo: repo, picker: picker),
                  ),
                ),
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
      of: find.byKey(const ValueKey('submit-report')),
      matching: find.byType(ElevatedButton),
    ),
  );
  final description = find.byKey(const ValueKey('problem-description'));

  Future<void> pickCategory(WidgetTester tester, String slug) async {
    await tester.tap(find.byKey(const ValueKey('problem-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('problem-category-$slug')));
    await tester.pumpAndSettle();
  }

  testWidgets('Submit waits for a category and a description', (tester) async {
    await show(tester, _Support(), _Picker());
    expect(find.text('Problem category'), findsOneWidget);
    expect(find.text('0/${SupportRepo.maxDescription}'), findsOneWidget);
    expect(submit(tester).onPressed, isNull);
    await tester.enterText(description, '   ');
    await tester.pump();
    await pickCategory(tester, 'bug');
    expect(find.text("Something isn't working"), findsOneWidget);
    expect(submit(tester).onPressed, isNull);
    await tester.enterText(description, 'Feed is empty');
    await tester.pump();
    expect(find.text('13/${SupportRepo.maxDescription}'), findsOneWidget);
    expect(submit(tester).onPressed, isNotNull);
    expect(tester.widget<TextField>(description).cursorColor, Colors.white);
  });

  testWidgets('description is capped at the max length', (tester) async {
    await show(tester, _Support(), _Picker());
    await tester.enterText(description, 'x' * (SupportRepo.maxDescription + 5));
    await tester.pump();
    expect(
      find.text('${SupportRepo.maxDescription}/${SupportRepo.maxDescription}'),
      findsOneWidget,
    );
  });

  testWidgets('screenshots: picker limit, thumbnails, remove, max count', (
    tester,
  ) async {
    final picker = _Picker();
    await show(tester, _Support(), picker);
    await tester.tap(find.byKey(const ValueKey('add-screenshot')));
    await tester.pumpAndSettle();
    expect(picker.limits, [SupportRepo.maxScreenshots]);
    expect(find.byType(Image), findsNWidgets(SupportRepo.maxScreenshots));
    // Full → the add button is gone.
    expect(find.byKey(const ValueKey('add-screenshot')), findsNothing);
    await tester.tap(find.bySemanticsLabel('Remove screenshot').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('screenshot-shot-0')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('add-screenshot')));
    await tester.pumpAndSettle();
    expect(picker.limits.last, 1);
    expect(find.byType(Image), findsNWidgets(SupportRepo.maxScreenshots));
  });

  testWidgets('rejected photos show an error toast', (tester) async {
    final picker = _Picker()..rejected = 1;
    await show(tester, _Support(), picker);
    await tester.tap(find.byKey(const ValueKey('add-screenshot')));
    await tester.pumpAndSettle();
    expect(find.textContaining('up to 20 MB'), findsOneWidget);
  });

  testWidgets('submit uploads screenshots, sends the report, toasts, pops', (
    tester,
  ) async {
    final repo = _Support()..pending = Completer<void>();
    await show(tester, repo, _Picker());
    await pickCategory(tester, 'chats');
    await tester.enterText(description, '  Messages arrive late  ');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('add-screenshot')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('submit-report')));
    await tester.pump();
    // Loader is white and the button can't be pressed twice.
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .color,
      Colors.white,
    );
    expect(submit(tester).onPressed, isNull);
    repo.pending!.complete();
    await tester.pumpAndSettle();
    expect(repo.uploaded, ['shot-0', 'shot-1', 'shot-2']);
    expect(repo.reports.single, {
      'category': 'chats',
      'description': 'Messages arrive late',
      'media_ids': [101, 102, 103],
    });
    expect(find.byType(ReportProblemScreen), findsNothing);
    expect(find.text('Thanks, we received your report'), findsOneWidget);
  });

  testWidgets('a failure shows an error toast and a retry reuses uploads', (
    tester,
  ) async {
    final repo = _Support()
      ..failure = ApiError(message: 'Not found.', statusCode: 404);
    await show(tester, repo, _Picker());
    await pickCategory(tester, 'other');
    await tester.enterText(description, 'Broken');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('add-screenshot')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('submit-report')));
    await tester.pumpAndSettle();
    expect(find.byType(ReportProblemScreen), findsOneWidget);
    expect(find.text('Not found.'), findsOneWidget);
    repo.failure = null;
    // Outside Root the toast is a SnackBar covering the button.
    submit(tester).onPressed!();
    await tester.pumpAndSettle();
    expect(repo.uploaded, hasLength(SupportRepo.maxScreenshots));
    expect(repo.reports, hasLength(2));
    expect(find.byType(ReportProblemScreen), findsNothing);
  });
}
