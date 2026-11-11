import 'package:flutter/material.dart';
import 'package:travibe/features/profile/widgets/profile_shimmer.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/post_card.dart';
import 'package:travibe/features/profile/screens/profile_screen.dart';
import 'package:travibe/features/saved/cubit/saves_cubit.dart';
import 'package:travibe/features/saved/cubit/saved_posts_cubit.dart';
import '../profile/fixtures.dart';
import 'fixtures.dart';

void main() {
  late SavedRepo repo;
  late SavesCubit saves;
  late SavedPostsCubit list;
  bool created = false;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('widget-account');
    repo = SavedRepo();
    created = false;
  });
  tearDown(() async {
    if (created) {
      await list.close();
      await saves.close();
    }
  });
  Future<void> show(WidgetTester tester, {int? userId}) async {
    if (!created) {
      saves = SavesCubit(repo: repo);
      list = SavedPostsCubit(saves: saves);
      created = true;
    }
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final profileRepo = MemoryProfileRepo()..result = profile(id: userId ?? 7);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: saves),
              BlocProvider.value(value: list),
            ],
            child: ProfileScreen(
              userId: userId,
              profileRepo: profileRepo,
              postsRepo: EmptyProfilePostsRepo(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> saved(WidgetTester tester) async {
    await tester.tap(find.text('Saved'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'real Saved tab uses PostCard and bookmark waits for confirmation',
    (tester) async {
      await show(tester);
      expect(repo.reads, isEmpty);
      await saved(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('post-save')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byType(PostCard), findsOneWidget);
      expect(find.text('Saved post 1'), findsOneWidget);
      expect(tester.widget<PostCard>(find.byType(PostCard)).isSaved, true);
      final svg = tester.widget<SvgPicture>(
        find.descendant(
          of: find.byKey(const ValueKey('post-save')),
          matching: find.byType(SvgPicture),
        ),
      );
      expect(
        (svg.bytesLoader as SvgAssetLoader).assetName,
        'assets/images/interactions/archive 2.svg',
      );
      repo.holdWrites = true;
      await tester.tap(find.byKey(const ValueKey('post-save')));
      await tester.pump();
      expect(tester.widget<PostCard>(find.byType(PostCard)).isSaved, true);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('post-save')))
            .onPressed,
        isNull,
      );
      repo.writes.single.result.complete(false);
      await tester.pumpAndSettle();
      expect(list.state.posts, isEmpty);
      expect(find.byType(PostCard), findsNothing);
      expect(find.text('No saved items yet'), findsOneWidget);
    },
  );
  testWidgets('save errors preserve bookmark and show backend feedback', (
    tester,
  ) async {
    repo.writeError = ApiError(message: 'Not permitted', statusCode: 403);
    await show(tester);
    await saved(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('post-save')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('post-save')));
    await tester.pumpAndSettle();
    expect(find.text('Not permitted'), findsOneWidget);
    expect(tester.widget<PostCard>(find.byType(PostCard)).isSaved, true);
  });
  testWidgets('loading error retries to empty; pull refresh loads real posts', (
    tester,
  ) async {
    repo.holdReads = true;
    await show(tester);
    await tester.tap(find.text('Saved'));
    await tester.pump();
    expect(find.byType(ProfilePostSkeleton), findsOneWidget);
    repo.reads.last.result.completeError(ApiError(message: 'Offline'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Retry'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Offline'), findsOneWidget);
    repo.holdReads = false;
    repo.stored = [];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No saved items yet'), findsOneWidget);
    repo.stored = [2];
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 650));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 650));
    await tester.pumpAndSettle();
    expect(list.state.posts.map((p) => p.id), ['2']);
  });
  testWidgets('Saved remains private and logout clears visible post content', (
    tester,
  ) async {
    await show(tester, userId: 23);
    expect(find.text('Saved'), findsNothing);
    expect(repo.reads, isEmpty);
    await show(tester);
    await saved(tester);
    expect(list.state.posts, hasLength(1));
    await tester.runAsync(() => PreferencesManager().clear());
    await tester.pumpAndSettle();
    expect(list.state.posts, isEmpty);
    expect(find.byType(PostCard), findsNothing);
  });
  testWidgets(
    'unsaved PostCard uses outline SVG and its existing bookmark action',
    (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            home: Scaffold(
              body: PostCard(
                name: 'Person',
                avatar: null,
                time: 'Now',
                text: 'Text',
                likes: '0',
                comments: '0',
                onSaveTap: () => tapped++,
              ),
            ),
          ),
        ),
      );
      final svg = tester.widget<SvgPicture>(
        find.descendant(
          of: find.byKey(const ValueKey('post-save')),
          matching: find.byType(SvgPicture),
        ),
      );
      expect(
        (svg.bytesLoader as SvgAssetLoader).assetName,
        'assets/images/interactions/archive.svg',
      );
      await tester.tap(find.byKey(const ValueKey('post-save')));
      expect(tapped, 1);
    },
  );
}
