import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/navigation/bottom_nav_visibility.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';

void main() {
  late TravibeToastController toasts;
  late BottomNavVisibility nav;

  setUp(() {
    toasts = TravibeToastController();
    nav = BottomNavVisibility();
  });
  tearDown(() {
    toasts.dispose();
    nav.dispose();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                TravibeToastHost(
                  controller: toasts,
                  visibility: nav,
                  navHeight: 100,
                  safeBottom: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color surface(WidgetTester tester) {
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(TravibeToastView),
            matching: find.byType(Container),
          )
          .first,
    );
    return (container.decoration! as BoxDecoration).color!;
  }

  testWidgets('variants use the Figma colors and icons', (tester) async {
    await pump(tester);
    for (final (data, color, icon) in [
      (
        const TravibeToastData.success('Post published successfully'),
        DarkColors.toastSuccess,
        Icons.check_circle,
      ),
      (
        TravibeToastData.info(
          'Post hidden',
          actionLabel: 'Undo',
          onAction: () {},
        ),
        DarkColors.toastInfo,
        Icons.check_circle,
      ),
      (
        TravibeToastData.error(
          'No internet connection',
          actionLabel: 'Refresh',
          onAction: () {},
        ),
        DarkColors.toastError,
        Icons.error,
      ),
    ]) {
      toasts.show(data);
      await tester.pumpAndSettle();
      expect(find.text(data.message), findsOneWidget);
      expect(surface(tester), color);
      expect(
        tester
            .widget<Icon>(
              find.byKey(ValueKey('toast-icon-${data.variant.name}')),
            )
            .icon,
        icon,
      );
    }
    toasts.dismiss();
    await tester.pumpAndSettle();
  });

  testWidgets('success hides after about 3 seconds', (tester) async {
    await pump(tester);
    toasts.show(const TravibeToastData.success('Story published successfully'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2900));
    expect(find.text('Story published successfully'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('Story published successfully'), findsNothing);
  });

  testWidgets('pill runs its action and closes a transient toast', (
    tester,
  ) async {
    var undone = 0;
    await pump(tester);
    toasts.show(
      TravibeToastData.info(
        'Post hidden',
        actionLabel: 'Undo',
        onAction: () => undone++,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(undone, 1);
    expect(find.text('Post hidden'), findsNothing);
  });

  testWidgets('X runs onClose; sticky toasts stay until their owner clears', (
    tester,
  ) async {
    var closed = 0;
    var retried = 0;
    await pump(tester);
    toasts.setSticky(
      'upload',
      TravibeToastData.error(
        'Couldn’t publish your post',
        actionLabel: 'Retry',
        onAction: () => retried++,
        onClose: () => closed++,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect((retried, closed), (1, 1));
    expect(find.text('Couldn’t publish your post'), findsOneWidget);
    toasts.setSticky('upload', null);
    await tester.pumpAndSettle();
    expect(find.byType(TravibeToastView), findsNothing);
  });

  testWidgets('only one toast at a time; the newest replaces the old', (
    tester,
  ) async {
    await pump(tester);
    toasts.show(const TravibeToastData.success('Post published successfully'));
    await tester.pumpAndSettle();
    toasts.show(TravibeToastData.info('Post hidden'));
    await tester.pumpAndSettle();
    expect(find.byType(TravibeToastView), findsOneWidget);
    expect(find.text('Post published successfully'), findsNothing);
    expect(find.text('Post hidden'), findsOneWidget);

    // A new sticky toast also replaces the transient one.
    toasts.setSticky(
      'offline',
      TravibeToastData.error(
        'No internet connection',
        actionLabel: 'Refresh',
        onAction: () {},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TravibeToastView), findsOneWidget);
    expect(find.text('No internet connection'), findsOneWidget);
    toasts.setSticky('offline', null);
    await tester.pumpAndSettle();
  });

  testWidgets('an unresolved sticky toast returns after a transient one', (
    tester,
  ) async {
    await pump(tester);
    toasts.setSticky(
      'upload',
      TravibeToastData.error(
        'Couldn’t publish your post',
        actionLabel: 'Retry',
        onAction: () {},
      ),
    );
    await tester.pumpAndSettle();
    toasts.show(const TravibeToastData.success('Story published successfully'));
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t publish your post'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t publish your post'), findsOneWidget);
    toasts.setSticky('upload', null);
    await tester.pumpAndSettle();
  });

  testWidgets('is announced and exposes labelled buttons', (tester) async {
    final semantics = tester.ensureSemantics();
    final announcements = <String>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      (message) async {
        final data = (message as Map)['data'] as Map;
        if (message['type'] == 'announce') {
          announcements.add(data['message'] as String);
        }
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility,
            null,
          ),
    );
    await pump(tester);
    toasts.show(
      TravibeToastData.error(
        'Couldn’t publish your post',
        actionLabel: 'Retry',
        onAction: () {},
        onClose: () {},
      ),
    );
    await tester.pumpAndSettle();
    expect(announcements, ['Couldn’t publish your post']);
    expect(
      tester.getSemantics(find.text('Retry')),
      matchesSemantics(label: 'Retry', isButton: true, hasTapAction: true),
    );
    expect(find.byTooltip('Dismiss'), findsOneWidget);
    toasts.dismiss();
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets('floats above the nav bar and follows it when it hides', (
    tester,
  ) async {
    await pump(tester);
    toasts.show(TravibeToastData.info('Post hidden'));
    await tester.pumpAndSettle();
    final toast = find.byType(TravibeToastView);
    final shown = tester.getRect(toast).bottom;
    expect(shown, closeTo(844 - 100 - 16, 1));
    nav.hide();
    await tester.pumpAndSettle();
    expect(tester.getRect(toast).bottom, closeTo(844 - 20 - 16, 1));
    nav.show();
    await tester.pumpAndSettle();
    expect(tester.getRect(toast).bottom, closeTo(shown, 0.01));
    toasts.dismiss();
    await tester.pumpAndSettle();
  });

  testWidgets('falls back to a SnackBar outside a toast scope', (tester) async {
    var undone = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => TravibeToast.show(
                context,
                TravibeToastData.info(
                  'Post hidden',
                  actionLabel: 'Undo',
                  onAction: () => undone = true,
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    await tester.tap(find.text('Undo'));
    expect(undone, isTrue);
  });
}
