import '../../helpers/cursor_fixtures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/post_card.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/widgets/follow_action_builder.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/root.dart';
import '../follow/follow_action_builder_test.dart' show ButtonRepo;
import 'home_experience_fixtures.dart';

class CardPosts extends EmptyPostsRepo {
  @override
  Future<PostsPageModel> getPosts({
    FeedType feed = FeedType.explore,
    String? cursor,
    int perPage = 15,
  }) async => PostsPageModel(
    pagination: fixtureMeta(current: 1, last: 1),

    posts: [
      PostModel.fromJson({
        'id': 1,
        'user_id': 7,
        'user': {'id': 7, 'name': 'Card author'},
        'content': 'A real card fixture',
      }),
    ],
    currentPage: 1,
    lastPage: 1,
    total: 1,
  );
}

PostCard card({
  bool neutral = true,
  bool following = false,
  bool pending = false,
  VoidCallback? onTap,
}) => PostCard(
  name: 'Author',
  avatar: null,
  time: 'now',
  text: '',
  likes: '0',
  comments: '0',
  shares: '0',
  showFollowButton: true,
  neutralFollowButton: neutral,
  isFollowing: following,
  isFollowPending: pending,
  onFollowTap: onTap,
);

void main() {
  void viewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> show(WidgetTester tester, Widget child) async {
    viewport(tester);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Container button(WidgetTester tester, String label) {
    final ink = find
        .ancestor(of: find.text(label), matching: find.byType(InkWell))
        .first;
    return tester.widget<InkWell>(ink).child! as Container;
  }

  Size size(WidgetTester tester, String label) => tester.getSize(
    find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first,
  );

  for (final following in [false, true]) {
    testWidgets(
      '${following ? 'Following' : 'Follow'} uses neutral colors without changing dimensions or typography',
      (tester) async {
        final label = following ? 'Following' : 'Follow';
        await show(tester, card(neutral: false, following: following));
        final previous = size(tester, label);
        await show(tester, card(following: following));
        final ink = tester.widget<InkWell>(
          find
              .ancestor(of: find.text(label), matching: find.byType(InkWell))
              .first,
        );
        expect(
          ink.overlayColor!.resolve({WidgetState.pressed}),
          Colors.white10,
        );
        final container = button(tester, label);
        final decoration = container.decoration! as BoxDecoration;
        expect(
          decoration.color,
          following ? const Color(0xFF262626) : const Color(0xFF303030),
        );
        expect(decoration.borderRadius, BorderRadius.circular(30));
        final border =
            (following
                        ? decoration
                        : container.foregroundDecoration! as BoxDecoration)
                    .border!
                as Border;
        expect(border.top.color, const Color(0xFF444444));
        expect(border.top.width, 1);
        expect(
          container.padding,
          const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        );
        final text = tester.widget<Text>(find.text(label));
        expect(text.style!.color, Colors.white);
        expect(text.style!.fontSize, 12);
        expect(text.style!.fontWeight, FontWeight.w600);
        expect(size(tester, label), previous);
      },
    );
  }
  testWidgets('default shared PostCard styling stays unchanged outside Home', (
    tester,
  ) async {
    await show(
      tester,
      const PostCard(
        name: 'Author',
        avatar: null,
        time: 'now',
        text: '',
        likes: '0',
        comments: '0',
        shares: '0',
        showFollowButton: true,
      ),
    );
    final decoration = button(tester, 'Follow').decoration! as BoxDecoration;
    expect(decoration.color, DarkColors.primaryColor);
    expect(decoration.borderRadius, BorderRadius.circular(20));
  });
  testWidgets(
    'pending disables taps and confirmed shared state becomes Following',
    (tester) async {
      final repo = ButtonRepo();
      final cubit = FollowCubit(repo: repo);
      await show(
        tester,
        BlocProvider.value(
          value: cubit,
          child: FollowActionBuilder(
            userId: '7',
            initialFollowing: false,
            builder: (_, following, pending, toggle) =>
                card(following: following, pending: pending, onTap: toggle),
          ),
        ),
      );
      await tester.tap(find.text('Follow'));
      await tester.pump();
      final ink = tester.widget<InkWell>(
        find
            .ancestor(
              of: find.text('Updating…'),
              matching: find.byType(InkWell),
            )
            .first,
      );
      expect(ink.onTap, isNull);
      expect(
        (button(tester, 'Updating…').decoration! as BoxDecoration).color,
        const Color(0xFF303030),
      );
      await cubit.toggle('7', currentlyFollowing: false);
      expect(repo.calls, 1);
      repo.result.complete(
        PublicUserModel.fromJson({
          'id': 7,
          'name': 'Author',
          'is_following': true,
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Following'), findsOneWidget);
      expect(cubit.state.following['7'], true);
      await tester.pumpWidget(const SizedBox.shrink());
      await cubit.close();
    },
  );
  testWidgets('actual Home post cards opt into neutral presentation', (
    tester,
  ) async {
    viewport(tester);
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('follow-style-viewer');
    final account = AccountRepo();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: Root(
            postsRepo: CardPosts(),
            homeAccountRepo: account,
            followRepo: PeopleRepo(account),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final feed = find.byType(CustomScrollView).first;
    await tester.scrollUntilVisible(
      find.byType(PostCard),
      180,
      scrollable: find
          .descendant(of: feed, matching: find.byType(Scrollable))
          .first,
    );
    final post = tester.widget<PostCard>(find.byType(PostCard).first);
    expect(post.neutralFollowButton, true);
    final follow = find.descendant(
      of: find.byType(PostCard).first,
      matching: find.text('Follow'),
    );
    final ink = tester.widget<InkWell>(
      find.ancestor(of: follow, matching: find.byType(InkWell)).first,
    );
    expect(
      ((ink.child! as Container).decoration! as BoxDecoration).color,
      const Color(0xFF303030),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await PreferencesManager().clear();
  });
}
