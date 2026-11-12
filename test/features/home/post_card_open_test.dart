import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/post_card.dart';

void main() {
  late Map<String, int> taps;
  setUp(() => taps = {});
  VoidCallback count(String name) =>
      () => taps[name] = (taps[name] ?? 0) + 1;

  Future<void> show(
    WidgetTester tester, {
    bool responsive = false,
    bool detail = false,
    List<String>? images,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: PostCard(
                postId: '10',
                responsive: responsive,
                detailPresentation: detail,
                name: 'Ahmed Adel',
                avatar: null,
                time: '20min',
                text: 'Bali was everything I needed.',
                image: images == null ? 'assets/missing.png' : null,
                images: images,
                likes: '123',
                comments: '1.2K',
                showFollowButton: true,
                onFollowTap: count('follow'),
                onLikeTap: count('like'),
                onLikesCountTap: count('likers'),
                onCommentsTap: count('comments'),
                onShareTap: count('share'),
                onSaveTap: count('save'),
                onMoreTap: count('more'),
                onOpen: count('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final responsive in [false, true]) {
    testWidgets('text, image and empty space open the post '
        '(responsive: $responsive)', (tester) async {
      await show(tester, responsive: responsive);
      await tester.tap(find.text('Bali was everything I needed.'));
      await tester.tap(find.byType(Image));
      final card = find.byKey(const ValueKey('post-open'));
      await tester.tapAt(tester.getTopRight(card) + const Offset(-4, 4));
      await tester.pump();
      expect(taps, {'open': 3});
    });

    testWidgets('buttons keep their own actions (responsive: $responsive)', (
      tester,
    ) async {
      await show(tester, responsive: responsive);
      await tester.tap(find.byKey(const ValueKey('post-like')));
      await tester.tap(find.byKey(const ValueKey('post-likes-count')));
      await tester.tap(find.text('1.2K'));
      await tester.tap(find.byKey(const ValueKey('post-share')));
      await tester.tap(find.byKey(const ValueKey('post-save')));
      await tester.tap(find.text('Follow'));
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();
      expect(taps, {
        'like': 1,
        'likers': 1,
        'comments': 1,
        'share': 1,
        'save': 1,
        'follow': 1,
        'more': 1,
      });
    });
  }

  testWidgets('like count opens likers without toggling the like', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.text('123'));
    await tester.pump();
    expect(taps, {'likers': 1});
  });

  testWidgets('heart and count are each at least 44px tap targets', (
    tester,
  ) async {
    await show(tester, responsive: true);
    for (final key in ['post-like', 'post-likes-count']) {
      final size = tester.getSize(find.byKey(ValueKey(key)));
      expect(size.width, greaterThanOrEqualTo(44), reason: key);
      expect(size.height, greaterThanOrEqualTo(44), reason: key);
    }
  });

  testWidgets('swiping the carousel does not open the post', (tester) async {
    await show(tester, images: ['assets/a.png', 'assets/b.png']);
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(taps, isEmpty);
    await tester.tap(find.byType(PageView));
    await tester.pump();
    expect(taps, {'open': 1});
  });

  testWidgets('detail presentation reads "N Likes"', (tester) async {
    await show(tester, responsive: true, detail: true);
    expect(find.text('123 Likes'), findsOneWidget);
  });
}
