import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/home/widgets/post_options_sheet.dart';

void main() {
  testWidgets('feed options expose only the implemented hide action', (
    tester,
  ) async {
    PostOptionAction? selected;
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  selected = await PostOptionsSheet.show(
                    context,
                    actions: const {PostOptionAction.hidePost},
                  );
                },
                child: const Text('Options'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();
    expect(find.text('Hide post'), findsOneWidget);
    expect(find.text('Block user'), findsNothing);
    expect(find.text('Report'), findsNothing);
    expect(find.text('Not interested'), findsNothing);
    await tester.tap(find.text('Hide post'));
    await tester.pumpAndSettle();
    expect(selected, PostOptionAction.hidePost);
  });

  for (final (disabled, label, asset) in [
    (false, 'Turn off commenting', 'assets/images/icons/comments_off.svg'),
    (true, 'Turn on commenting', 'assets/images/icons/message.svg'),
  ]) {
    testWidgets('"$label" uses $asset, sized and tinted like the other rows', (
      tester,
    ) async {
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            home: Scaffold(
              body: PostOptionsSheet(
                // Own-post rows plus a grey-tinted reference row.
                actions: {...ownPostActions, PostOptionAction.notInterested},
                commentsDisabled: disabled,
              ),
            ),
          ),
        ),
      );
      SvgPicture icon(String key) => tester.widget<SvgPicture>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(SvgPicture),
        ),
      );
      final toggle = icon('post-option-toggle-comments');
      final reference = icon('post-option-not-interested');
      final link = icon('post-option-copy-link');
      expect(find.text(label), findsOneWidget);
      expect((toggle.bytesLoader as SvgAssetLoader).assetName, asset);
      expect(find.byType(Icon), findsNothing);
      expect(
        toggle.colorFilter,
        const ColorFilter.mode(DarkColors.greyColor, BlendMode.srcIn),
      );
      expect(toggle.colorFilter, reference.colorFilter);
      for (final other in [reference, link]) {
        expect(toggle.width, other.width);
        expect(toggle.height, other.height);
      }
      final size = tester.getSize(
        find.descendant(
          of: find.byKey(const ValueKey('post-option-toggle-comments')),
          matching: find.byType(SvgPicture),
        ),
      );
      expect(
        size,
        tester.getSize(
          find.descendant(
            of: find.byKey(const ValueKey('post-option-copy-link')),
            matching: find.byType(SvgPicture),
          ),
        ),
      );
    });
  }
}
