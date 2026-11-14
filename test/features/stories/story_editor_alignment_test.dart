import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/stories/screens/story_editor_screen.dart';
import 'package:travibe/features/stories/widgets/story_canvas.dart';

import 'fixtures.dart';

void main() {
  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    await tester.runAsync(() async {
      await (FontLoader('Plus Jakarta Sans')..addFont(
            rootBundle.load('assets/fonts/PlusJakartaSans-Regular.ttf'),
          ))
          .load();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          fontFamily: 'Plus Jakarta Sans',
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: StoryEditorScreen(
          draft: draft(),
          avatarUrl: 'https://unused.invalid/avatar.png',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'reference header uses compact Public pill and 44px controls below safe area',
    (tester) async {
      await show(tester);
      final back = tester.getRect(find.byKey(const ValueKey('story-back')));
      final audience = tester.getRect(
        find.byKey(const ValueKey('story-audience')),
      );
      final post = tester.getRect(find.byKey(const ValueKey('story-post')));
      expect(back, const Rect.fromLTWH(16, 64, 44, 44));
      expect(audience.size, const Size(140, 44));
      expect(audience.top, 64);
      expect(post.size, const Size(80, 44));
      expect(post.right, 370);
      expect(post.left - audience.right, 8);
      expect(find.text('Public'), findsOneWidget);
      expect(find.byIcon(Icons.language), findsOneWidget);
      expect(find.byIcon(Icons.person_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'toolbar has four white 44px circles with 16px gaps and 20px right inset',
    (tester) async {
      await show(tester);
      final buttons = tester
          .widgetList<IconButton>(find.byType(IconButton))
          .where((button) => button.tooltip != 'Back')
          .toList();
      expect(buttons, hasLength(4));
      for (var i = 0; i < buttons.length; i++) {
        final rect = tester.getRect(find.byWidget(buttons[i]));
        expect(rect.size, const Size(44, 44));
        expect(rect.right, 370);
        expect(rect.top, 134 + i * 60);
        expect(
          buttons[i].style!.foregroundColor!.resolve({WidgetState.disabled}),
          Colors.white,
        );
      }
      // Aa, @, emoji and draw are active; Location is intentionally absent.
      expect(buttons.every((button) => button.onPressed != null), isTrue);
      expect(
        buttons.map((button) => button.tooltip),
        ['Add text', 'Mention someone', 'Add emoji', 'Draw'],
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'photo retains centered cover crop and original full safe-area canvas',
    (tester) async {
      await show(tester);
      final canvas = tester.getRect(find.byType(StoryCanvas));
      expect(canvas, const Rect.fromLTWH(0, 44, 390, 800));
      final photo = tester.widget<Image>(
        find.byKey(const ValueKey('story-background')),
      );
      expect(photo.fit, BoxFit.cover);
      expect(photo.alignment, Alignment.center);
      expect((photo.image as MemoryImage).bytes, photoBytes());
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).resizeToAvoidBottomInset,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'short narrow viewport and large text do not overflow header or toolbar',
    (tester) async {
      await show(tester, size: const Size(280, 480), scale: 2);
      expect(
        tester.getRect(find.byKey(const ValueKey('story-post'))).right,
        lessThanOrEqualTo(260),
      );
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'audience dismissal and disabled orange Post leave the local draft intact',
    (tester) async {
      await show(tester);
      final before = tester.widget<StoryCanvas>(find.byType(StoryCanvas)).draft;
      final post = tester.widget<FilledButton>(
        find.byKey(const ValueKey('story-post')),
      );
      expect(post.onPressed, isNull);
      expect(
        post.style!.backgroundColor!.resolve({WidgetState.disabled}),
        DarkColors.primaryColor,
      );
      await tester.tap(find.text('Public'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('story-post')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<StoryCanvas>(find.byType(StoryCanvas)).draft,
        same(before),
      );
      expect(find.byType(StoryEditorScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
