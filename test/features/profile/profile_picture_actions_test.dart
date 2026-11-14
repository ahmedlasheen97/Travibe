import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/profile_picture_viewer.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/features/profile/screens/profile_screen.dart';
import 'package:travibe/features/stories/cubit/stories_cubit.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/screens/story_viewer_screen.dart';
import 'package:travibe/features/stories/widgets/post_story_sheet.dart';
import 'package:travibe/root.dart';

import '../../helpers/fake_network_images.dart';
import '../home/home_experience_fixtures.dart';
import '../stories/story_owner_controls_test.dart' show OwnerRepo;
import '../stories/story_publishing_test.dart' show groupJson, pageJson;
import 'fixtures.dart' as fx;

const _url = 'https://img.travibe.test/avatar.png';

ProfileModel _withPicture({int id = 7}) =>
    ProfileModel.fromJson({...fx.profileJson(id: id), 'avatar_url': _url});

class _Feed extends OwnerRepo {
  _Feed(List<Map<String, dynamic>> groups) {
    groupsHandler = (_) async => StoriesPage.fromJson(pageJson(groups));
  }
}

/// The viewer's white loader spins while the (fake) image decodes, so
/// pumpAndSettle would never settle; pump past route transitions instead.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

final _avatar = find.byKey(const ValueKey('profile-open-stories'));
final _viewStory = find.byKey(const ValueKey('profile-view-story'));
final _viewPicture = find.byKey(const ValueKey('profile-view-picture'));

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('profile-picture-actions');
  });
  tearDown(() => PreferencesManager().clear());

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('my profile', () {
    Future<int Function()> showMine(
      WidgetTester tester, {
      required bool story,
    }) async {
      phone(tester);
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
              profileRepo: fx.MemoryProfileRepo()..result = _withPicture(),
              storiesRepo: _Feed([if (story) groupJson(7)]),
            ),
          ),
        ),
      );
      await _settle(tester);
      BottomNavigationBar bar() =>
          tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      bar().onTap!(4);
      await _settle(tester);
      return () => bar().currentIndex;
    }

    testWidgets('with a story → sheet; "View story" opens my story', (
      tester,
    ) async {
      await withFakeNetworkImages(() async {
        await showMine(tester, story: true);
        await tester.tap(_avatar);
        await _settle(tester);
        expect(_viewStory, findsOneWidget);
        expect(_viewPicture, findsOneWidget);
        expect(find.text('View profile picture'), findsOneWidget);
        await tester.tap(_viewStory);
        await _settle(tester);
        expect(_viewStory, findsNothing);
        expect(
          tester
              .widget<StoryViewerScreen>(find.byType(StoryViewerScreen))
              .initialAuthorId,
          7,
        );
      });
    });

    testWidgets('with a story → "View profile picture" opens the viewer', (
      tester,
    ) async {
      await withFakeNetworkImages(() async {
        await showMine(tester, story: true);
        await tester.tap(_avatar);
        await _settle(tester);
        await tester.tap(_viewPicture);
        await _settle(tester);
        expect(_viewPicture, findsNothing);
        expect(
          tester
              .widget<ProfilePictureViewer>(find.byType(ProfilePictureViewer))
              .imageUrl,
          _url,
        );
        expect(find.byType(StoryViewerScreen), findsNothing);
      });
    });

    testWidgets('without a story → the viewer opens directly', (tester) async {
      await withFakeNetworkImages(() async {
        await showMine(tester, story: false);
        await tester.tap(_avatar);
        await _settle(tester);
        expect(_viewStory, findsNothing);
        expect(find.byType(ProfilePictureViewer), findsOneWidget);
      });
    });

    testWidgets('"+" opens the add-story sheet on Profile (no tab switch)', (
      tester,
    ) async {
      await withFakeNetworkImages(() async {
        final tab = await showMine(tester, story: true);
        await tester.tap(find.byKey(const ValueKey('profile-add-story')));
        await _settle(tester);
        expect(find.byType(PostStorySheet), findsOneWidget);
        expect(tab(), 4);
        expect(find.byType(ProfileScreen), findsOneWidget);
      });
    });
  });

  group('another user', () {
    late FollowCubit follow;
    late BlockCubit block;

    setUp(() {
      follow = FollowCubit();
      block = BlockCubit(follow: follow);
    });
    tearDown(() async {
      await block.close();
      await follow.close();
    });

    Future<StoriesCubit> showOther(
      WidgetTester tester, {
      required bool story,
    }) async {
      phone(tester);
      final stories = StoriesCubit(
        repo: _Feed([if (story) groupJson(8)]),
        blocks: block,
      );
      await stories.load();
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: darkTheme,
            home: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: follow),
                BlocProvider.value(value: block),
                BlocProvider.value(value: stories),
              ],
              child: ProfileScreen(
                userId: 8,
                profileRepo: fx.MemoryProfileRepo()
                  ..result = _withPicture(id: 8),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
      return stories;
    }

    testWidgets('with a story → their story, no sheet', (tester) async {
      await withFakeNetworkImages(() async {
        final stories = await showOther(tester, story: true);
        await tester.tap(_avatar);
        await _settle(tester);
        expect(_viewStory, findsNothing);
        expect(
          tester
              .widget<StoryViewerScreen>(find.byType(StoryViewerScreen))
              .initialAuthorId,
          8,
        );
        unawaited(stories.close());
      });
    });

    testWidgets('without a story → the picture viewer', (tester) async {
      await withFakeNetworkImages(() async {
        final stories = await showOther(tester, story: false);
        await tester.tap(_avatar);
        await _settle(tester);
        expect(find.byType(ProfilePictureViewer), findsOneWidget);
        unawaited(stories.close());
      });
    });
  });

  group('ProfilePictureViewer', () {
    Future<void> showViewer(WidgetTester tester) async {
      phone(tester);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: darkTheme,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => openProfilePictureViewer(context, _url),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await _settle(tester);
      expect(find.byType(ProfilePictureViewer), findsOneWidget);
    }

    final drag = find.byKey(const ValueKey('profile-picture-drag'));

    testWidgets('swipe down closes it; a short drag springs back', (
      tester,
    ) async {
      await withFakeNetworkImages(() async {
        await showViewer(tester);
        await tester.timedDrag(
          drag,
          const Offset(0, 60),
          const Duration(seconds: 1),
        );
        await _settle(tester);
        expect(find.byType(ProfilePictureViewer), findsOneWidget);
        // Slow (no fling) but past the dismiss distance.
        await tester.timedDrag(
          drag,
          const Offset(0, 200),
          const Duration(seconds: 2),
        );
        await _settle(tester);
        expect(find.byType(ProfilePictureViewer), findsNothing);
      });
    });

    testWidgets('a zoomed picture pans instead of closing', (tester) async {
      await withFakeNetworkImages(() async {
        await showViewer(tester);
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .transformationController!
            .value = Matrix4.identity()
          ..scaleByDouble(3, 3, 1, 1);
        await tester.pump();
        await tester.timedDrag(
          drag,
          const Offset(0, 300),
          const Duration(milliseconds: 300),
        );
        await _settle(tester);
        expect(find.byType(ProfilePictureViewer), findsOneWidget);
      });
    });

    testWidgets('back button closes it', (tester) async {
      await withFakeNetworkImages(() async {
        await showViewer(tester);
        await tester.tap(find.byTooltip('Back'));
        await _settle(tester);
        expect(find.byType(ProfilePictureViewer), findsNothing);
      });
    });
  });
}
