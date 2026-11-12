import 'package:flutter/cupertino.dart';
import '../../helpers/cursor_fixtures.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:travibe/core/widgets/glass_surface.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/glass_confirm_dialog.dart';
import 'package:travibe/features/create_post/data/create_post_request.dart';
import 'package:travibe/features/create_post/data/post_image_picker.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/create_post/screens/create_post_screen.dart';
import 'package:travibe/features/home/cubit/posts_cubit.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/widgets/home_tabs.dart';
import 'package:travibe/root.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'fixtures.dart';
import '../home/home_experience_fixtures.dart' as home;

/// App-wide current user that is already loaded and makes no requests.
class CachedCurrentUser extends CurrentUserCubit {
  CachedCurrentUser(ProfileModel profile) {
    emit(CurrentUserState(profile: profile));
  }
  @override
  Future<void> load() async {}
}

class Feeds extends PostsRepo {
  final calls = <FeedType>[];
  @override
  Future<PostsPageModel> getPosts({
    FeedType feed = FeedType.explore,
    String? cursor,
    int perPage = 15,
  }) async {
    calls.add(feed);
    return PostsPageModel(
      pagination: fixtureMeta(current: 1, last: 1),
      posts: [],
      currentPage: 1,
      lastPage: 1,
      total: 0,
    );
  }
}

void main() {
  late MemoryCreatePostRepo repo;
  late FakePostImagePicker picker;
  CreatePostRequest? result;
  setUp(() {
    repo = MemoryCreatePostRepo();
    picker = FakePostImagePicker();
    result = null;
  });

  FilledButton postButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const ValueKey('post-submit')));

  Future<void> open(WidgetTester tester, {CurrentUserCubit? user}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) {
          final app = MaterialApp(
            theme: darkTheme,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = await CreatePostScreen.open(
                      context,
                      repo: repo,
                      picker: picker,
                    );
                  },
                  child: const Text('Compose'),
                ),
              ),
            ),
          );
          return user == null
              ? app
              : BlocProvider<CurrentUserCubit>.value(value: user, child: app);
        },
      ),
    );
    await tester.tap(find.text('Compose'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'validates input, counts Unicode text and offers only supported audiences',
    (tester) async {
      await open(tester);
      expect(postButton(tester).onPressed, isNull);
      expect(find.text('Sara'), findsOneWidget);
      expect(find.text('@sara'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '😀 Trip');
      await tester.pump();
      expect(find.text('6/2000'), findsOneWidget);
      expect(postButton(tester).onPressed, isNotNull);
      await tester.tap(find.text('Public'));
      await tester.pumpAndSettle();
      expect(find.text('Mutuals'), findsNothing);
      expect(find.byKey(const ValueKey('audience-followers')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('audience-private')));
      await tester.pumpAndSettle();
      expect(find.text('Private'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'x' * 2001);
      await tester.pump();
      expect(postButton(tester).onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Post closes immediately and returns the draft for upload', (
    tester,
  ) async {
    picker.gallery = [postImage('a')];
    await open(tester);
    await tester.enterText(find.byType(TextField), '  My draft ');
    await tester.tap(find.text('Public'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('audience-followers')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-gallery')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();
    expect(find.byType(CreatePostScreen), findsNothing);
    expect(result!.content, '  My draft ');
    expect(result!.visibility, PostVisibility.followers);
    expect(result!.images.single.localId, 'a');
    // Nothing is sent from the composer itself.
    expect(repo.requests, isEmpty);
  });

  testWidgets('photos show 3 per row, can be removed, and enable Post alone', (
    tester,
  ) async {
    picker.gallery = [for (var i = 0; i < 4; i++) postImage('$i')];
    await open(tester);
    expect(find.text('Add to your post'), findsOneWidget);
    expect(find.byKey(const ValueKey('add-video')), findsNothing);
    expect(find.byKey(const ValueKey('add-location')), findsNothing);
    final gallery = tester.getCenter(find.byKey(const ValueKey('add-gallery')));
    final camera = tester.getCenter(find.byKey(const ValueKey('add-camera')));
    final emoji = tester.getCenter(find.byKey(const ValueKey('add-emoji')));
    expect(gallery.dx, lessThan(camera.dx));
    expect(camera.dx, lessThan(emoji.dx));

    await tester.tap(find.byKey(const ValueKey('add-gallery')));
    await tester.pumpAndSettle();
    expect(picker.galleryLimits, [10]);
    expect(postButton(tester).onPressed, isNotNull);
    Rect tile(String id) =>
        tester.getRect(find.byKey(ValueKey('post-image-$id')));
    expect(tile('0').width, closeTo(tile('0').height, 0.01));
    expect(tile('1').top, tile('0').top);
    expect(tile('2').top, tile('0').top);
    expect(tile('2').left, greaterThan(tile('1').left));
    expect(tile('3').top, greaterThan(tile('0').bottom));
    expect(tile('3').left, tile('0').left);

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(ValueKey('remove-image-$i')));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey('post-image-grid')), findsNothing);
    expect(postButton(tester).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('camera adds one photo and the 10 photo limit shows a message', (
    tester,
  ) async {
    picker.gallery = [for (var i = 0; i < 12; i++) postImage('g$i')];
    picker.camera = [postImage('c')];
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('add-camera')));
    await tester.pumpAndSettle();
    expect(picker.captures, 1);
    expect(find.byKey(const ValueKey('post-image-c')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add-gallery')));
    await tester.pumpAndSettle();
    // The system picker is asked for the remaining 9 only.
    expect(picker.galleryLimits, [9]);
    expect(find.byKey(const ValueKey('post-image-g8')), findsOneWidget);
    expect(find.byKey(const ValueKey('post-image-g9')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('add-camera')));
    await tester.pump();
    expect(picker.captures, 1);
    expect(find.text('You can add up to 10 photos.'), findsOneWidget);
  });

  testWidgets('denied access explains and offers Settings', (tester) async {
    picker.error = const PostImagePermissionDenied(camera: true);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('add-camera')));
    await tester.pumpAndSettle();
    expect(find.text('Camera access is off'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Camera access is off'), findsNothing);
    picker.error = const PostImagePermissionDenied(camera: false);
    await tester.tap(find.byKey(const ValueKey('add-gallery')));
    await tester.pumpAndSettle();
    expect(find.text('Photo access is off'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('emoji panel inserts at the cursor and enables Post', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('add-emoji')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-emoji-picker')), findsOneWidget);
    await tester.tap(find.text('😀').first);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '😀',
    );
    expect(find.text('1/2000'), findsOneWidget);
    expect(postButton(tester).onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('add-emoji')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-emoji-picker')), findsNothing);
  });

  testWidgets('photos alone ask before discarding; empty closes directly', (
    tester,
  ) async {
    picker.gallery = [postImage('a')];
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('add-gallery')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close composer'));
    await tester.pumpAndSettle();
    expect(find.text('Discard Post?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('post-image-a')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('remove-image-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close composer'));
    await tester.pumpAndSettle();
    expect(find.text('Discard Post?'), findsNothing);
    expect(find.byType(CreatePostScreen), findsNothing);
    expect(result, isNull);
  });

  testWidgets(
    'back and close ask before discarding and Cancel retains the draft',
    (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), 'Unsaved');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard Post?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Unsaved',
      );
      await tester.tap(find.byTooltip('Close composer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(CreatePostScreen), findsNothing);
      expect(result, isNull);
      expect(repo.requests, isEmpty);
    },
  );

  testWidgets(
    'center Add publishes and refreshes the same feeds while retaining Home tab selection',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final feeds = Feeds();
      final uploads = FakeUploads();
      picker.gallery = [postImage('a')];
      final account = home.AccountRepo();
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: darkTheme,
            home: Root(
              createPostRepo: repo,
              postImagePicker: picker,
              mediaUploads: uploads.create,
              postsRepo: feeds,
              homeAccountRepo: account,
              followRepo: home.PeopleRepo(account),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final explore = tester
          .widget<BlocBuilder<PostsCubit, PostsState>>(
            find.byKey(const ValueKey('home-feed-content')),
          )
          .bloc;
      await tester.tap(find.text('Following'));
      await tester.pumpAndSettle();
      final following = tester
          .widget<BlocBuilder<PostsCubit, PostsState>>(
            find.byKey(const ValueKey('home-feed-content')),
          )
          .bloc;
      final nav = tester.getRect(find.byType(BottomNavigationBar));
      await tester.tapAt(nav.center);
      await tester.pumpAndSettle();
      expect(find.byType(CreatePostScreen), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'A new post');
      await tester.tap(find.byKey(const ValueKey('add-gallery')));
      await tester.pumpAndSettle();
      repo.gate = Completer<PostModel>();
      await tester.tap(find.text('Post'));
      // The upload spinner animates indefinitely while the request is gated.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // Composer closes at once; Home shows the upload toast.
      expect(find.byType(CreatePostScreen), findsNothing);
      expect(find.text('Uploading your post'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(TravibeToastView),
          matching: find.byType(CupertinoActivityIndicator),
        ),
        findsOneWidget,
      );
      expect(uploads.uploaded, ['post-a.png']);
      expect(repo.requests.single.toJson()['media_ids'], [100]);
      repo.gate!.complete(PostModel.fromJson(postJson(content: 'A new post')));
      await tester.pumpAndSettle();
      expect(find.text('Uploading your post'), findsNothing);
      expect(find.text('Post published successfully'), findsOneWidget);
      expect(
        feeds.calls.where((feed) => feed == FeedType.explore),
        hasLength(2),
      );
      expect(
        feeds.calls.where((feed) => feed == FeedType.following),
        hasLength(2),
      );
      expect(tester.widget<HomeTabs>(find.byType(HomeTabs)).selectedIndex, 1);
      expect(
        tester
            .widget<BlocBuilder<PostsCubit, PostsState>>(
              find.byKey(const ValueKey('home-feed-content')),
            )
            .bloc,
        same(following),
      );
      await tester.tap(
        find.descendant(
          of: find.byType(HomeTabs),
          matching: find.text('For You'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BlocBuilder<PostsCubit, PostsState>>(
              find.byKey(const ValueKey('home-feed-content')),
            )
            .bloc,
        same(explore),
      );
      expect((following!.state as PostsLoaded).posts, isEmpty);
      expect((explore!.state as PostsLoaded).posts, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('a failed upload offers Retry on Home and keeps the post', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final uploads = FakeUploads()..failNext = 1;
    final account = home.AccountRepo();
    picker.gallery = [postImage('a')];
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: Root(
            createPostRepo: repo,
            postImagePicker: picker,
            mediaUploads: uploads.create,
            postsRepo: Feeds(),
            homeAccountRepo: account,
            followRepo: home.PeopleRepo(account),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getRect(find.byType(BottomNavigationBar)).center);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-gallery')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t publish your post'), findsOneWidget);
    final failed = tester.widget<TravibeToastView>(
      find.byType(TravibeToastView),
    );
    expect(failed.data.variant, TravibeToastVariant.error);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byTooltip('Dismiss'), findsOneWidget);
    expect(repo.requests, isEmpty);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t publish your post'), findsNothing);
    expect(repo.requests.single.toJson()['media_ids'], [100]);
    expect(find.text('Post published successfully'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('X and system back ask under the real GoRouter + Root shell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final account = home.AccountRepo();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Root(
            createPostRepo: repo,
            postImagePicker: picker,
            postsRepo: Feeds(),
            homeAccountRepo: account,
            followRepo: home.PeopleRepo(account),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) =>
            MaterialApp.router(theme: darkTheme, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getRect(find.byType(BottomNavigationBar)).center);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Unsaved');
    await tester.pump();

    await tester.tap(find.byTooltip('Close composer'));
    await tester.pumpAndSettle();
    expect(find.text('Discard Post?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Android back button / predictive back reach the same confirmation.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard Post?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(CreatePostScreen), findsNothing);
    expect(repo.requests, isEmpty);
  });

  testWidgets('text that bypasses onChanged still counts as unsaved', (
    tester,
  ) async {
    await open(tester);
    // IME composition, autocorrect and paste can update the controller
    // without an onChanged callback.
    tester.widget<TextField>(find.byType(TextField)).controller!.text =
        'From the keyboard';
    await tester.pump();
    expect(postButton(tester).onPressed, isNotNull);
    await tester.tap(find.byTooltip('Close composer'));
    await tester.pumpAndSettle();
    expect(find.text('Discard Post?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard Post?'), findsOneWidget);
  });

  testWidgets(
    'Discard Post? uses the glass dialog: red Discard left, Cancel right',
    (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), 'x');
      await tester.tap(find.byTooltip('Close composer'));
      await tester.pumpAndSettle();
      expect(find.byType(GlassConfirmDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(GlassConfirmDialog),
          matching: find.byType(GlassSurface),
        ),
        findsOneWidget,
      );
      expect(find.text('Your post won’t be saved.'), findsOneWidget);
      expect(
        tester.getCenter(find.text('Discard')).dx,
        lessThan(tester.getCenter(find.text('Cancel')).dx),
      );
      Color? color(String label) => tester
          .widget<RichText>(
            find.descendant(
              of: find.text(label),
              matching: find.byType(RichText),
            ),
          )
          .text
          .style!
          .color;
      expect(color('Discard'), DarkColors.dangerColor);
      expect(color('Cancel'), DarkColors.whiteColor);
    },
  );

  testWidgets('cached current user fills the header with no request', (
    tester,
  ) async {
    final user = CachedCurrentUser(
      const ProfileModel(id: '7', name: 'Cached Sara', username: 'cachedsara'),
    );
    addTearDown(user.close);
    await open(tester, user: user);
    expect(repo.authorCalls, 0);
    expect(find.text('Cached Sara'), findsOneWidget);
    expect(find.text('@cachedsara'), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('post-author-identity')),
          )
          .opacity,
      1,
    );
  });

  testWidgets(
    'without a cached profile the author loads in the background, no spinner',
    (tester) async {
      repo.authorGate = Completer<void>();
      await open(tester);
      expect(repo.authorCalls, 1);
      // Field is usable at once; header shows the dimmed fallback.
      expect(find.byKey(const ValueKey('post-content')), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      double opacity() => tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('post-author-identity')),
          )
          .opacity;
      expect(opacity(), lessThan(1));
      final field = tester.getRect(find.byKey(const ValueKey('post-content')));

      repo.authorGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Sara'), findsOneWidget);
      expect(find.text('@sara'), findsOneWidget);
      expect(opacity(), 1);
      expect(tester.getRect(find.byKey(const ValueKey('post-content'))), field);
      expect(repo.authorCalls, 1);
    },
  );

  testWidgets('profile failure keeps the Retry fallback', (tester) async {
    repo.authorError = true;
    await open(tester);
    expect(find.text('Unable to load your profile.'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    repo.authorError = false;
    await tester.tap(find.text('Retry profile'));
    await tester.pumpAndSettle();
    expect(find.text('Sara'), findsOneWidget);
    expect(find.text('Unable to load your profile.'), findsNothing);
    expect(repo.authorCalls, 2);
  });

  testWidgets('short drafts stay visible above the keyboard', (tester) async {
    await open(tester);
    addTearDown(tester.view.resetViewInsets);
    await tester.enterText(find.byType(TextField), 'A trip');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(
      tester.getBottomLeft(find.byType(TextField)).dy,
      lessThanOrEqualTo(544),
    );
    expect(tester.takeException(), isNull);
  });
}
