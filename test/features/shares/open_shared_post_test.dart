import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/notifications/data/notification_targets.dart';
import 'package:travibe/features/home/screens/post_screen.dart';
import 'package:travibe/features/shares/screens/open_shared_post.dart';
import 'send_post_fixtures.dart';

void main() {
  final preferences = PreferencesManager();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.saveToken('fixture-session');
  });
  tearDown(preferences.clearSession);

  Future<void> open(WidgetTester tester, SharedPostLoader load) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => openSharedPost(context, 10, load: load),
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

  testWidgets('opens the post screen for a visible post', (tester) async {
    final requested = <int>[];
    await open(tester, (id) async {
      requested.add(id);
      return NotificationContent(
        const NotificationTarget(NotificationTargetKind.post, 10),
        post: sharedPost(),
      );
    });
    expect(requested, [10]);
    expect(find.byType(PostScreen), findsOneWidget);
    expect(find.text('Sunset over Petra'), findsOneWidget);
  });

  testWidgets('deleted or forbidden posts show a friendly message', (
    tester,
  ) async {
    await open(
      tester,
      (_) async => throw ApiError(message: 'Not found', statusCode: 404),
    );
    expect(find.byType(PostScreen), findsNothing);
    expect(find.text(sharedPostUnavailable), findsOneWidget);
  });
}
