import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/permissions/app_permission.dart';
import 'package:travibe/core/permissions/device_settings.dart';
import 'package:travibe/core/permissions/permission_flow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('fromError', () {
    final cases = <Object, AppPermission?>{
      PlatformException(code: 'camera_access_denied'): AppPermission.camera,
      PlatformException(code: 'camera_access_restricted'): AppPermission.camera,
      PlatformException(code: 'photo_access_denied'): AppPermission.photos,
      PlatformException(code: 'photo_access_restricted'): AppPermission.photos,
      PlatformException(code: 'permission_denied'): AppPermission.photosAdd,
      PlatformException(code: 'no_available_camera'): null,
      MissingPluginException(): null,
      const FormatException('Invalid image.'): null,
    };
    for (final entry in cases.entries) {
      test('${entry.key} → ${entry.value}', () {
        expect(PermissionFlow.fromError(entry.key), entry.value);
      });
    }
  });

  group('settings sheet', () {
    late List<String> calls;
    late bool settingsFail;

    setUp(() {
      calls = [];
      settingsFail = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DeviceSettings.channel, (call) async {
            calls.add(call.method);
            if (settingsFail) throw PlatformException(code: 'unavailable');
            return null;
          });
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DeviceSettings.channel, null),
    );

    Future<BuildContext> pump(WidgetTester tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (c) {
                  context = c;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      return context;
    }

    for (final permission in AppPermission.values) {
      testWidgets('${permission.name} explains why and offers Settings', (
        tester,
      ) async {
        final context = await pump(tester);
        final done = PermissionFlow.showSettings(context, permission);
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('permission-settings-${permission.name}')),
          findsOneWidget,
        );
        expect(find.text(permission.title), findsOneWidget);
        expect(find.text(permission.message), findsOneWidget);
        expect(find.text('Open Settings'), findsOneWidget);
        expect(find.text('Not Now'), findsOneWidget);
        await tester.tap(find.text('Open Settings'));
        await tester.pumpAndSettle();
        await done;
        expect(calls, ['openSettings']);
      });
    }

    testWidgets('Not Now closes without opening Settings', (tester) async {
      final context = await pump(tester);
      final done = PermissionFlow.showSettings(context, AppPermission.camera);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not Now'));
      await tester.pumpAndSettle();
      await done;
      expect(calls, isEmpty);
      expect(find.text(AppPermission.camera.title), findsNothing);
    });

    testWidgets('swiping the sheet away is the same as Not Now', (
      tester,
    ) async {
      final context = await pump(tester);
      final done = PermissionFlow.showSettings(context, AppPermission.photos);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await done;
      expect(calls, isEmpty);
    });

    testWidgets('if Settings cannot open, the user is told where to go', (
      tester,
    ) async {
      settingsFail = true;
      final context = await pump(tester);
      final done = PermissionFlow.showSettings(
        context,
        AppPermission.microphone,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();
      await done;
      expect(calls, ['openSettings']);
      expect(find.textContaining('Open Settings › Travibe'), findsOneWidget);
    });

    testWidgets('handleError shows the sheet only for permission denials', (
      tester,
    ) async {
      final context = await pump(tester);
      expect(
        await PermissionFlow.handleError(context, MissingPluginException()),
        isFalse,
      );
      await tester.pumpAndSettle();
      expect(find.text('Open Settings'), findsNothing);
      final handled = PermissionFlow.handleError(
        context,
        PlatformException(code: 'permission_denied'),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('permission-settings-photosAdd')),
        findsOneWidget,
      );
      await tester.tap(find.text('Not Now'));
      await tester.pumpAndSettle();
      expect(await handled, isTrue);
    });
  });
}
