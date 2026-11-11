import 'package:travibe/core/widgets/action_icon_button.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/home_post_caption.dart';
import 'package:travibe/core/widgets/post_card.dart';

const _style = TextStyle(
  fontFamily: 'Plus Jakarta Sans',
  fontSize: 14,
  height: 1.4,
  color: Colors.white,
);
final _long =
    'Bali was everything I needed. 🌴✨\nAlready planning my next trip. 👩🏽‍💻 ' *
    10;

void main() {
  setUpAll(() async {
    for (final name in ['Regular', 'SemiBold', 'Bold']) {
      await (FontLoader(
            'Plus Jakarta Sans',
          )..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-$name.ttf')))
          .load();
    }
  });
  late PageStorageBucket bucket;
  setUp(() => bucket = PageStorageBucket());

  HomePostCaption caption({String? text, String id = '1'}) => HomePostCaption(
    key: ValueKey(id),
    postId: id,
    text: text ?? _long,
    style: _style,
  );
  Future<void> show(
    WidgetTester tester,
    Widget child, {
    double width = 390,
    double scale = 1,
    TextDirection direction = TextDirection.ltr,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: Directionality(
                  textDirection: direction,
                  child: SingleChildScrollView(
                    child: PageStorage(
                      bucket: bucket,
                      child: SizedBox(width: width, child: child),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder textIn(Finder scope) => find.descendant(
    of: scope,
    matching: find.byKey(const ValueKey('home-caption-text')),
  );
  Finder paragraphIn(Finder scope) =>
      find.descendant(of: textIn(scope), matching: find.byType(RichText));
  RenderParagraph paragraph(WidgetTester tester, Finder scope) =>
      tester.renderObject<RenderParagraph>(paragraphIn(scope));
  TextSpan span(WidgetTester tester, Finder scope) {
    var value = paragraph(tester, scope).text as TextSpan;
    while (value.text == null &&
        value.children?.length == 1 &&
        value.children!.first is TextSpan) {
      value = value.children!.first as TextSpan;
    }
    return value;
  }

  String displayed(WidgetTester tester, Finder scope) =>
      span(tester, scope).toPlainText(includeSemanticsLabels: false);
  Future<void> tapLink(WidgetTester tester, Finder scope, String label) async {
    await Scrollable.ensureVisible(tester.element(textIn(scope)), alignment: 1);
    await tester.pumpAndSettle();
    final render = paragraph(tester, scope);
    final plain = render.text.toPlainText(includeSemanticsLabels: false);
    final start = plain.lastIndexOf(label);
    expect(start, greaterThanOrEqualTo(0));
    final boxes = render.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: start + label.length),
    );
    await tester.tapAt(render.localToGlobal(boxes.first.toRect().center));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'fit measurement uses four lines, not a character-count heuristic',
    (tester) async {
      await show(tester, caption(text: 'i' * 100), width: 720);
      expect(displayed(tester, find.byType(HomePostCaption)), 'i' * 100);
      expect(
        displayed(tester, find.byType(HomePostCaption)),
        isNot(contains('read more...')),
      );
      await show(tester, caption(text: 'A\nB\nC\nD\nE'));
      expect(
        displayed(tester, find.byType(HomePostCaption)),
        contains('read more...'),
      );
      final render = paragraph(tester, find.byType(HomePostCaption));
      expect(render.maxLines, 4);
      expect(render.didExceedMaxLines, false);
      expect(render.overflow, TextOverflow.clip);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'white caption reserves an orange inline link without a redundant ellipsis',
    (tester) async {
      await show(
        tester,
        Padding(padding: const EdgeInsets.all(16), child: caption()),
      );
      final scope = find.byType(HomePostCaption);
      final value = span(tester, scope);
      expect(value.style!.color, Colors.white);
      expect(value.style!.fontFamily, 'Plus Jakarta Sans');
      final link = value.children!.last as TextSpan;
      expect(link.text, 'read more...');
      expect(link.style!.color, DarkColors.primaryColor);
      expect(link.recognizer, isA<TapGestureRecognizer>());
      expect(displayed(tester, scope), isNot(contains('…')));
      expect(paragraph(tester, scope).didExceedMaxLines, false);
      final prefix = (value.children!.first as TextSpan).text!.trimRight();
      final originalGraphemes = _long.characters.toList();
      expect(_long.startsWith(prefix), true);
      expect(originalGraphemes.take(prefix.characters.length).join(), prefix);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Read More expands original newlines and emoji; Show Less restores four lines',
    (tester) async {
      await show(tester, caption());
      final scope = find.byType(HomePostCaption);
      final collapsedHeight = tester.getSize(textIn(scope)).height;
      await tapLink(tester, scope, 'read more...');
      expect(displayed(tester, scope), '$_long show less');
      expect(paragraph(tester, scope).maxLines, isNull);
      expect(
        tester.getSize(textIn(scope)).height,
        greaterThan(collapsedHeight),
      );
      expect(
        (span(tester, scope).children!.last as TextSpan).style!.color,
        DarkColors.primaryColor,
      );
      await tapLink(tester, scope, 'show less');
      expect(paragraph(tester, scope).maxLines, 4);
      expect(tester.getSize(textIn(scope)).height, collapsedHeight);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'expansion is independent by ID, survives unrelated rebuild and restores after remount',
    (tester) async {
      Widget cards() => Column(
        children: [
          caption(id: 'a'),
          caption(id: 'b'),
        ],
      );
      await show(tester, cards());
      final first = find.byKey(const ValueKey('a'));
      final second = find.byKey(const ValueKey('b'));
      await tapLink(tester, first, 'read more...');
      expect(displayed(tester, first), endsWith('show less'));
      expect(displayed(tester, second), endsWith('read more...'));
      await show(tester, cards());
      expect(displayed(tester, first), endsWith('show less'));
      await show(tester, const SizedBox());
      await show(tester, cards());
      expect(displayed(tester, first), endsWith('show less'));
      expect(displayed(tester, second), endsWith('read more...'));
      await show(tester, caption(id: 'a', text: 'A replacement caption'));
      expect(displayed(tester, first), 'A replacement caption');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a Like update on another PostCard preserves independent caption expansion',
    (tester) async {
      Widget cards(bool liked) => Column(
        children: [
          for (final id in ['a', 'b'])
            PostCard(
              key: ValueKey('card-$id'),
              homePresentation: true,
              postId: id,
              name: 'Author $id',
              avatar: null,
              time: 'now',
              text: _long,
              isLiked: id == 'b' && liked,
              likes: id == 'b' && liked ? '1' : '0',
              comments: '0',
            ),
        ],
      );
      await show(tester, cards(false));
      final first = find.descendant(
        of: find.byKey(const ValueKey('card-a')),
        matching: find.byType(HomePostCaption),
      );
      final second = find.descendant(
        of: find.byKey(const ValueKey('card-b')),
        matching: find.byType(HomePostCaption),
      );
      await tapLink(tester, first, 'read more...');
      await show(tester, cards(true));
      expect(displayed(tester, first), endsWith('show less'));
      expect(displayed(tester, second), endsWith('read more...'));
      expect(
        tester.widget<PostCard>(find.byKey(const ValueKey('card-b'))).isLiked,
        true,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('full original caption and expand action remain accessible', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await show(tester, caption());
    final node = find.semantics.byLabel('read more...').evaluate().single;
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), true);
    expect(find.semantics.byLabel(_long).evaluate(), hasLength(1));
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  for (final width in [320.0, 375.0, 393.0, 430.0, 844.0, 1024.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'measured Arabic/mixed RTL caption fits $width with text scale $scale',
        (tester) async {
          final text =
              'رحلة رائعة إلى Bali 🌴👨‍👩‍👧‍👦!\nموعد الرحلة القادمة؟ ' * 12;
          await show(
            tester,
            Padding(
              padding: const EdgeInsets.all(16),
              child: caption(text: text),
            ),
            width: width,
            scale: scale,
          );
          final scope = find.byType(HomePostCaption);
          expect(paragraph(tester, scope).textDirection, TextDirection.rtl);
          expect(paragraph(tester, scope).didExceedMaxLines, false);
          expect(paragraph(tester, scope).maxLines, 4);
          await tapLink(tester, scope, 'read more...');
          expect(displayed(tester, scope), '$text show less');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets('English caption in RTL app uses LTR paragraph direction', (
    tester,
  ) async {
    await show(
      tester,
      caption(text: 'Hello Bali 🌴'),
      direction: TextDirection.rtl,
    );
    expect(
      paragraph(tester, find.byType(HomePostCaption)).textDirection,
      TextDirection.ltr,
    );
    await tester.pumpWidget(const SizedBox());
  });

  for (final content in [
    'caption',
    'location',
    'image',
    'carousel',
    'header',
  ]) {
    testWidgets('Home $content content ends exactly 20px before actions', (
      tester,
    ) async {
      await show(
        tester,
        PostCard(
          homePresentation: true,
          responsive: true,
          postId: '1',
          name: 'Author',
          avatar: null,
          time: 'now',
          text: content == 'header' ? '' : 'White caption',
          location: content == 'location' ? 'Bali' : null,
          image: content == 'image' ? 'assets/images/onboarding/on1.png' : null,
          images: content == 'carousel'
              ? [
                  'assets/images/onboarding/on1.png',
                  'assets/images/onboarding/on1.png',
                ]
              : null,
          likes: '0',
          comments: '0',
        ),
      );
      final gap = tester.getRect(
        find.byKey(const ValueKey('post-content-actions-gap')),
      );
      final actions = tester.getRect(
        find.byKey(const ValueKey('post-actions')),
      );
      expect(gap.height, 20);
      expect(actions.top, gap.bottom);
      final lastContent = switch (content) {
        'header' => find.byKey(const ValueKey('post-header')),
        'location' =>
          find
              .ancestor(of: find.text('Bali'), matching: find.byType(Container))
              .first,
        'image' || 'carousel' => find.byType(ClipRRect).last,
        _ => find.byType(HomePostCaption),
      };
      expect(
        actions.top - tester.getRect(lastContent).bottom,
        closeTo(20, .01),
      );
      if (content != 'header') {
        expect(
          tester.getRect(find.byType(HomePostCaption)).top -
              tester.getRect(find.byKey(const ValueKey('post-header'))).bottom,
          closeTo(20, .01),
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'caption expansion keeps all PostCard action callbacks functional',
    (tester) async {
      final actions = [0, 0, 0, 0];
      await show(
        tester,
        PostCard(
          homePresentation: true,
          postId: '7',
          name: 'Author',
          avatar: null,
          time: 'now',
          text: 'One\nTwo\nThree\nFour\nFive\nSix',
          likes: '0',
          comments: '0',
          onLikeTap: () => actions[0]++,
          onCommentsTap: () => actions[1]++,
          onShareTap: () => actions[2]++,
          onSaveTap: () => actions[3]++,
        ),
      );
      await tapLink(tester, find.byType(HomePostCaption), 'read more...');
      for (final key in [
        'post-like',
        'post-comments',
        'post-share',
        'post-save',
      ]) {
        final action = key == 'post-comments'
            ? find.byWidgetPredicate(
                (widget) =>
                    widget is ActionIconButton &&
                    widget.iconPath.endsWith('message.svg'),
              )
            : find.byKey(ValueKey(key));
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
      }
      expect(actions, [1, 1, 1, 1]);
      expect(
        displayed(tester, find.byType(HomePostCaption)),
        endsWith('show less'),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'default PostCard keeps its existing caption and spacing outside Home',
    (tester) async {
      await show(
        tester,
        const PostCard(
          name: 'Author',
          avatar: null,
          time: 'now',
          text: 'Short caption',
          likes: '0',
          comments: '0',
        ),
      );
      expect(find.byType(HomePostCaption), findsNothing);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('post-content-actions-gap')))
            .height,
        12,
      );
      expect(find.text('Short caption'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
