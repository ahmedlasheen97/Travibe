import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/sheet_handle.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:travibe/features/follow/widgets/follow_pill.dart';
import 'package:travibe/features/home/widgets/home_user_avatar.dart';
import 'package:travibe/features/home/widgets/suggested_user_card.dart';
import 'package:travibe/features/stories/cubit/story_viewers_cubit.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/widgets/story_viewers_sheet.dart';
import 'story_owner_controls_test.dart' show OwnerRepo, viewerJson, viewersPage;
import 'story_publishing_test.dart' show pageJson;

PublicUserModel user(bool following) => PublicUserModel(
  id: '8',
  name: 'Viewer 8',
  isFollowing: following,
  isBlocked: false,
  followersCount: 0,
  followingCount: 0,
);

class Follows extends FollowRepo {
  final calls =
      <({String id, bool following, Completer<PublicUserModel> result})>[];
  @override
  Future<PublicUserModel> setFollowing(String id, bool following) {
    final result = Completer<PublicUserModel>();
    calls.add((id: id, following: following, result: result));
    return result.future;
  }
}

void main() {
  final session = PreferencesManager();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await session.init();
    await session.saveToken('alignment-test-session');
  });
  tearDown(() async => session.clear());
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Finder getSheet() => find.byType(StoryViewersSheet);
  Finder button(String label) => find.descendant(
    of: getSheet(),
    matching: find.widgetWithText(TextButton, label),
  );
  Future<StoryViewersCubit> mount(
    WidgetTester tester,
    OwnerRepo repo, {
    FollowCubit? follow,
    bool home = false,
  }) async {
    phone(tester);
    final cubit = StoryViewersCubit(
      storyId: 1,
      repo: repo,
      isOwner: () => true,
    );
    await cubit.refresh();
    addTearDown(cubit.close);
    final sheet = StoryViewersSheet(cubit: cubit, count: 932, follow: follow);
    final body = home
        ? BlocProvider.value(
            value: follow!,
            child: Column(
              children: [
                SizedBox(
                  height: 244,
                  child: SuggestedUserCard(user: user(false)),
                ),
                Expanded(child: sheet),
              ],
            ),
          )
        : sheet;
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: Scaffold(body: body),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return cubit;
  }

  testWidgets(
    'header starts at 24px with native untinted eye and centered handle',
    (tester) async {
      await mount(tester, OwnerRepo());
      final svg = find.descendant(
        of: getSheet(),
        matching: find.byType(SvgPicture),
      );
      final eye = tester.widget<SvgPicture>(svg);
      expect(
        (eye.bytesLoader as SvgAssetLoader).assetName,
        'assets/images/interactions/eye.svg',
      );
      expect(eye.colorFilter, isNull);
      expect(eye.width, 24);
      expect(eye.height, 24);
      final subtitle = find.text('Only you can see who viewed your story.');
      expect(tester.getTopLeft(svg).dx, 24);
      expect(tester.getTopLeft(subtitle).dx, 24);
      expect(tester.getTopLeft(find.text('932 Views')).dx, 24 + 24 + 8);
      expect(tester.widget<Text>(subtitle).textAlign, TextAlign.start);
      expect(
        tester.widget<Text>(find.text('932 Views')).textAlign,
        TextAlign.start,
      );
      expect(tester.getCenter(find.byType(SheetHandle)).dx, 195);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('Follow and Following share compact neutral white-label pills', (
    tester,
  ) async {
    final follow = FollowCubit();
    addTearDown(follow.close);
    final repo = OwnerRepo()
      ..viewersHandler = (_) async => StoryViewersPage.fromJson(
        pageJson([viewerJson(8)..['is_following'] = false, viewerJson(9)]),
      );
    await mount(tester, repo, follow: follow);
    for (final label in ['Follow', 'Following']) {
      final found = button(label);
      expect(found, findsOneWidget);
      final control = tester.widget<TextButton>(found);
      final style = control.style!;
      for (final states in [
        <WidgetState>{},
        {WidgetState.disabled},
        {WidgetState.pressed},
      ]) {
        expect(style.backgroundColor!.resolve(states), const Color(0xFF2F2E2D));
        expect(style.foregroundColor!.resolve(states), Colors.white);
      }
      expect(
        style.overlayColor!.resolve({WidgetState.pressed}),
        Colors.white10,
      );
      expect(style.shape!.resolve({}), isA<StadiumBorder>());
      expect(style.minimumSize!.resolve({}), const Size(0, 36));
      expect(
        tester
            .widget<Text>(
              find.descendant(of: found, matching: find.text(label)),
            )
            .style!
            .color,
        Colors.white,
      );
      final material = tester.widget<Material>(
        find.descendant(of: found, matching: find.byType(Material)).first,
      );
      expect(material.color, FollowPill.backgroundColor);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'shared Home/sheet follow actions sync, disable while loading and reject duplicates',
    (tester) async {
      final repo = Follows();
      final follow = FollowCubit(repo: repo);
      addTearDown(follow.close);
      final viewers = OwnerRepo()
        ..viewersHandler = (_) async => StoryViewersPage.fromJson(
          pageJson([viewerJson(8)..['is_following'] = false]),
        );
      await mount(tester, viewers, follow: follow, home: true);
      expect(find.byType(FollowPill), findsNWidgets(2));
      expect(find.text('Follow'), findsNWidgets(2));
      final homeButton = tester.widget<TextButton>(
        find.descendant(
          of: find.byType(SuggestedUserCard),
          matching: find.byType(TextButton),
        ),
      );
      expect(
        homeButton.style!.backgroundColor!.resolve({}),
        const Color(0xFF2F2E2D),
      );
      expect(
        homeButton.style!.padding!.resolve({}),
        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      );
      expect(homeButton.style!.tapTargetSize, MaterialTapTargetSize.shrinkWrap);
      await tester.tap(button('Follow'));
      await tester.tap(button('Follow'));
      await tester.pump();
      expect(repo.calls, hasLength(1));
      expect(repo.calls.single.following, true);
      expect(
        tester
            .widget<TextButton>(
              find.descendant(
                of: getSheet(),
                matching: find.byType(TextButton),
              ),
            )
            .onPressed,
        isNull,
      );
      expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
      final pending = tester.widget<TextButton>(
        find.descendant(of: getSheet(), matching: find.byType(TextButton)),
      );
      expect(
        pending.style!.backgroundColor!.resolve({WidgetState.disabled}),
        FollowPill.backgroundColor,
      );
      repo.calls.single.result.complete(user(true));
      await tester.pumpAndSettle();
      expect(find.text('Following'), findsNWidgets(2));
      expect(follow.state.following['8'], true);
      await tester.tap(button('Following'));
      await tester.pump();
      expect(repo.calls, hasLength(2));
      expect(repo.calls.last.following, false);
      repo.calls.last.result.complete(user(false));
      await tester.pumpAndSettle();
      expect(find.text('Follow'), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'failed request preserves confirmed labels and rows with error feedback',
    (tester) async {
      final repo = Follows();
      final follow = FollowCubit(repo: repo);
      addTearDown(follow.close);
      final viewers = OwnerRepo()
        ..viewersHandler = (_) async => StoryViewersPage.fromJson(
          pageJson([viewerJson(8)..['is_following'] = false]),
        );
      await mount(tester, viewers, follow: follow);
      await tester.tap(button('Follow'));
      await tester.pump();
      repo.calls.single.result.completeError(
        ApiError(message: 'Follow request failed'),
      );
      await tester.pumpAndSettle();
      expect(button('Follow'), findsOneWidget);
      expect(find.text('Follow request failed'), findsOneWidget);
      expect(find.text('Viewer 8'), findsOneWidget);
      expect(follow.state.pending, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'blocking disables follow and account changes clear viewer rows',
    (tester) async {
      final repo = Follows();
      final follow = FollowCubit(repo: repo);
      addTearDown(follow.close);
      await mount(tester, OwnerRepo(), follow: follow);
      follow.applyBlockStatus('8', true);
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(button('Following')).onPressed, isNull);
      await tester.tap(button('Following'));
      expect(repo.calls, isEmpty);
      await session.saveToken('another-alignment-account');
      await tester.pumpAndSettle();
      expect(find.text('Viewer 8'), findsNothing);
      expect(find.byType(HomeUserAvatar), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'viewer list still scrolls with header aligned and API-supported hearts',
    (tester) async {
      final follow = FollowCubit();
      addTearDown(follow.close);
      final repo = OwnerRepo()
        ..viewersHandler = (_) async => StoryViewersPage.fromJson(
          viewersPage(List.generate(15, (i) => 100 + i)),
        );
      await mount(tester, repo, follow: follow);
      await tester.scrollUntilVisible(
        find.text('Viewer 114'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Viewer 114'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('story-viewer-liked-114')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
