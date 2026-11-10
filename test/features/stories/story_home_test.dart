import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/home/widgets/home_stories.dart';
import 'package:travibe/features/stories/widgets/post_story_sheet.dart';
import 'package:travibe/root.dart';

import '../home/home_experience_fixtures.dart';

void main() {
  testWidgets(
    'actual Home story plus opens Story sheet and retains navigation',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SharedPreferences.getInstance();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final account = AccountRepo();
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: darkTheme,
            home: Root(
              postsRepo: EmptyPostsRepo(),
              homeAccountRepo: account,
              followRepo: PeopleRepo(account),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HomeStories), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('add-story-photo')));
      await tester.pumpAndSettle();
      expect(find.byType(PostStorySheet), findsOneWidget);
      await tester.tapAt(const Offset(10, 200));
      await tester.pumpAndSettle();
      expect(find.byType(PostStorySheet), findsNothing);
      expect(find.byType(HomeStories), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
