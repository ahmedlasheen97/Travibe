import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/utils/viewer_identity.dart';
import 'package:travibe/core/widgets/glass_confirm_dialog.dart';
import 'package:travibe/core/widgets/post_card.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/root.dart';
import '../../helpers/cursor_fixtures.dart';
import 'home_experience_fixtures.dart' as home;

Map<String, dynamic> _post(int id, int authorId, {bool disabled = false}) => {
  'id': id,
  'type': 'text',
  'user_id': authorId,
  'user': {
    'id': authorId,
    'name': 'Author $authorId',
    'username': 'a$authorId',
  },
  'content': 'Post $id',
  'visibility': 'public',
  'media': [],
  'comments_disabled': disabled,
};

/// Viewer is user 1 (home AccountRepo). Post 10 is theirs, post 20 is not.
class MenuFeeds extends PostsRepo {
  final deleted = <String>[];
  final commentChanges = <(String, bool)>[];
  ApiError? deleteError;

  @override
  Future<PostsPageModel> getPosts({
    FeedType feed = FeedType.explore,
    String? cursor,
    int perPage = 15,
  }) async => PostsPageModel(
    pagination: fixtureMeta(current: 1, last: 1),
    posts: feed == FeedType.explore
        ? [PostModel.fromJson(_post(10, 1)), PostModel.fromJson(_post(20, 2))]
        : [],
    currentPage: 1,
    lastPage: 1,
    total: 2,
  );

  @override
  Future<void> deletePost(String postId) async {
    if (deleteError != null) throw deleteError!;
    deleted.add(postId);
  }

  @override
  Future<PostModel> setCommentsDisabled(String postId, bool disabled) async {
    commentChanges.add((postId, disabled));
    return PostModel.fromJson(_post(int.parse(postId), 1, disabled: disabled));
  }
}

void main() {
  final preferences = PreferencesManager();
  late MenuFeeds feeds;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
    await preferences.init();
    await preferences.saveToken('token');
    feeds = MenuFeeds();
  });
  tearDown(() => preferences.clear());

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final account = home.AccountRepo();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: Root(
            postsRepo: feeds,
            homeAccountRepo: account,
            followRepo: home.PeopleRepo(account),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester, String content) async {
    final card = find.ancestor(
      of: find.text(content),
      matching: find.byType(PostCard),
    );
    final more = find.descendant(
      of: card,
      matching: find.byIcon(Icons.more_vert),
    );
    await tester.ensureVisible(more);
    await tester.pumpAndSettle();
    await tester.tap(more);
    await tester.pumpAndSettle();
  }

  test('ownership compares normalized ids and never guesses', () {
    expect(normalizeUserId('007'), '7');
    expect(normalizeUserId(7), '7');
    expect(normalizeUserId(''), isNull);
    expect(normalizeUserId('abc'), isNull);
    expect(normalizeUserId(0), isNull);
  });

  testWidgets('own post shows the own-post menu; others keep Hide/Block', (
    tester,
  ) async {
    await pumpHome(tester);
    await openMenu(tester, 'Post 10');
    expect(find.text('Turn off commenting'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    expect(find.text('Delete post'), findsOneWidget);
    expect(find.text('Hide post'), findsNothing);
    expect(find.text('Block user'), findsNothing);
    final delete = tester.widget<Text>(find.text('Delete post'));
    expect(delete.style!.color, DarkColors.dangerColor);
    expect(DarkColors.dangerColor, const Color(0xFFDD312A));
    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(
      sheet.shape,
      const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    );
    await tester.tapAt(const Offset(195, 100));
    await tester.pumpAndSettle();

    await openMenu(tester, 'Post 20');
    expect(find.text('Hide post'), findsOneWidget);
    expect(find.text('Block user'), findsOneWidget);
    expect(find.text('Delete post'), findsNothing);
    expect(find.text('Copy link'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Delete asks in the glass dialog, then removes the post', (
    tester,
  ) async {
    await pumpHome(tester);
    await openMenu(tester, 'Post 10');
    await tester.tap(find.text('Delete post'));
    await tester.pumpAndSettle();
    expect(find.byType(GlassConfirmDialog), findsOneWidget);
    expect(find.text('Delete this post?'), findsOneWidget);
    expect(find.text('This action can’t be undone.'), findsOneWidget);
    // Cancel keeps it.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(feeds.deleted, isEmpty);
    expect(find.text('Post 10'), findsOneWidget);

    await openMenu(tester, 'Post 10');
    await tester.tap(find.text('Delete post'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(feeds.deleted, ['10']);
    expect(find.text('Post 10'), findsNothing);
    expect(find.text('Post 20'), findsOneWidget);
    expect(find.text('Post deleted'), findsOneWidget);
  });

  testWidgets('a failed delete keeps the post and explains', (tester) async {
    feeds.deleteError = ApiError(message: 'Unable to delete the post.');
    await pumpHome(tester);
    await openMenu(tester, 'Post 10');
    await tester.tap(find.text('Delete post'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Post 10'), findsOneWidget);
    expect(find.text('Unable to delete the post.'), findsOneWidget);
  });

  testWidgets('commenting toggles via the API and the label follows', (
    tester,
  ) async {
    await pumpHome(tester);
    await openMenu(tester, 'Post 10');
    await tester.tap(find.text('Turn off commenting'));
    await tester.pumpAndSettle();
    expect(feeds.commentChanges, [('10', true)]);
    expect(find.text('Commenting turned off'), findsOneWidget);
    await openMenu(tester, 'Post 10');
    expect(find.text('Turn on commenting'), findsOneWidget);
    await tester.tap(find.text('Turn on commenting'));
    await tester.pumpAndSettle();
    expect(feeds.commentChanges.last, ('10', false));
  });

  testWidgets('Copy link reuses the links-unavailable message', (tester) async {
    await pumpHome(tester);
    await openMenu(tester, 'Post 10');
    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();
    expect(find.text("Post links aren't available yet."), findsOneWidget);
  });
}
