import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/constants/feature_flags.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';
import 'package:travibe/features/stories/data/story_audience.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/data/story_elements.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/screens/story_viewer_screen.dart';

import '../profile/fixtures.dart' as profile;
import 'fixtures.dart';
import 'story_publishing_test.dart' show StoryAdapter, repository, response;
import 'story_viewer_test.dart' show ViewerRepo, viewerDetail, viewerGroup;

/// [ViewerRepo] that records `reshare` calls instead of hitting the API.
class ReshareRepo extends ViewerRepo {
  final reshares = <(int, StoryAudience?)>[];
  Object? error;
  @override
  Future<void> reshare(int id, {StoryAudience? visibility}) async {
    reshares.add((id, visibility));
    if (error != null) throw error!;
  }
}

/// A signed-in user whose own profile has `is_private: [private]`.
Future<CurrentUserCubit> currentUser({required bool private}) async {
  final session = PreferencesManager();
  if (!session.hasSession) {
    await session.init();
    await session.saveToken('current-user-test');
    addTearDown(session.clear);
  }
  final cubit = CurrentUserCubit(
    profileRepo: profile.MemoryProfileRepo()
      ..result = ProfileModel.fromJson(
        profile.profileJson()..['is_private'] = private,
      ),
  );
  await cubit.load();
  expect(cubit.state.profile?.isPrivate, private);
  return cubit;
}

StoryReshareError reshareError(int status, {Map<String, dynamic>? errors}) =>
    StoryReshareError.from(
      ApiError(
        message: 'Server says no',
        statusCode: status,
        fieldErrors: {
          for (final entry in (errors ?? const {}).entries)
            entry.key: List<String>.from(entry.value as List),
        },
      ),
      Response(
        requestOptions: RequestOptions(path: ''),
        statusCode: status,
      ),
    );

void main() {
  setUp(() async {
    ScreenUtil.configure(
      data: const MediaQueryData(size: Size(390, 844)),
      designSize: const Size(390, 844),
      minTextAdapt: false,
      splitScreenMode: false,
    );
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('reshare-test');
  });
  tearDown(() => PreferencesManager().clear());

  test('reshare is on: the backend shipped it', () {
    expect(kEnableStoryReshare, isTrue);
  });

  group('StoryDetail', () {
    test('parses allow_mention_reshare, can_reshare and reshared_from', () {
      final plain = StoryDetail.fromJson(viewerDetail(1));
      expect(plain.allowMentionReshare, isFalse);
      expect(plain.canReshare, isFalse);
      expect(plain.resharedFrom, isNull);
      final reshared = StoryDetail.fromJson(
        viewerDetail(2)
          ..['allow_mention_reshare'] = true
          ..['can_reshare'] = true
          ..['reshared_from'] = {
            'story_id': 40,
            'user': {
              'id': 9,
              'name': 'Sara Adel',
              'username': 'sara',
              'avatar_url': null,
            },
          },
      );
      expect(reshared.allowMentionReshare, isTrue);
      expect(reshared.canReshare, isTrue);
      expect(reshared.resharedFrom!.storyId, 40);
      expect(reshared.resharedFrom!.user!.name, 'Sara Adel');
      expect(reshared.resharedFrom!.user!.username, 'sara');
    });

    test('reshared_from keeps the user when story_id is null (expired)', () {
      final from = StoryDetail.fromJson(
        viewerDetail(3)
          ..['reshared_from'] = {
            'story_id': null,
            'user': {'id': 9, 'name': 'Sara Adel', 'avatar_url': null},
          },
      ).resharedFrom!;
      expect(from.storyId, isNull);
      expect(from.user!.id, 9);
    });

    test('a null or malformed user still marks the story as a reshare', () {
      for (final user in [
        null,
        {'id': 'x'},
      ]) {
        final from = StoryDetail.fromJson(
          viewerDetail(4)..['reshared_from'] = {'story_id': 4, 'user': user},
        ).resharedFrom;
        expect(from, isNotNull);
        expect(from!.user, isNull);
      }
    });
  });

  group('StoriesRepo.reshare', () {
    test('POSTs stories/{id}/reshare; visibility only when given', () async {
      final adapter = StoryAdapter();
      final repo = repository(adapter);
      await repo.reshare(5);
      await repo.reshare(6, visibility: StoryAudience.followers);
      expect(adapter.requests.map((r) => (r.method, r.path)), [
        ('POST', 'stories/5/reshare'),
        ('POST', 'stories/6/reshare'),
      ]);
      expect(adapter.requests.first.data, isEmpty);
      expect(adapter.requests.last.data, {'visibility': 'followers'});
    });

    final cases = <(int, Map<String, dynamic>, String, bool)>[
      (
        422,
        {
          'story': ['Already reshared.'],
        },
        'You\'ve already reshared this story.',
        true,
      ),
      (
        422,
        {
          'stories': ['You can have at most 10 active stories.'],
        },
        'You can have at most 10 active stories.',
        false,
      ),
      (403, {}, 'You can\'t reshare this story.', true),
      (404, {}, 'This story has expired.', true),
      (500, {}, StoryReshareError.fallback, false),
    ];
    for (final (status, errors, message, gone) in cases) {
      test('HTTP $status ${errors.keys} → "$message"', () async {
        final adapter = StoryAdapter()
          ..handler = (_) async =>
              response({'message': 'x', 'errors': errors}, status: status);
        await expectLater(
          repository(adapter).reshare(5),
          throwsA(
            isA<StoryReshareError>()
                .having((e) => e.message, 'message', message)
                .having((e) => e.reshareGone, 'gone', gone)
                .having((e) => e.statusCode, 'status', status),
          ),
        );
      });
    }
  });

  Future<({ReshareRepo repo, List<int> opened, List<int> reshared})> open(
    WidgetTester tester, {
    bool enable = true,
    bool canReshare = true,
    Map<String, dynamic>? resharedFrom,
    List<dynamic> elements = const [],
    List<dynamic> mentions = const [],
    CurrentUserCubit? current,
  }) async {
    final repo = ReshareRepo()
      ..handler = (id) async {
        final json = viewerDetail(id, elements: elements)
          ..['is_mine'] = false
          ..['can_reshare'] = canReshare
          ..['mentions'] = mentions
          ..['created_at'] = DateTime.now()
              .subtract(const Duration(hours: 12))
              .toIso8601String();
        if (resharedFrom != null) json['reshared_from'] = resharedFrom;
        return StoryDetail.fromJson(json);
      };
    final opened = <int>[], reshared = <int>[];
    final photo = MemoryImage(photoBytes());
    Widget viewer = StoryViewerScreen(
      groups: [
        viewerGroup(7, [1]),
      ],
      initialAuthorId: 7,
      currentUserId: 99,
      repo: repo,
      imageProvider: (_) => photo,
      enableReshare: enable,
      onOpenProfile: (context, userId) async => opened.add(userId),
      onReshared: () => reshared.add(1),
    );
    if (current != null) {
      viewer = BlocProvider<CurrentUserCubit>.value(
        value: current,
        child: viewer,
      );
    }
    await tester.pumpWidget(MaterialApp(home: viewer));
    await tester.pump();
    await tester.pump();
    return (repo: repo, opened: opened, reshared: reshared);
  }

  final reshareButton = find.byKey(const ValueKey('story-reshare'));

  group('viewer Reshare button', () {
    testWidgets('shows above the reply bar when can_reshare', (tester) async {
      await open(tester);
      expect(reshareButton, findsOneWidget);
      expect(find.text('Reshare'), findsOneWidget);
      expect(
        tester.getBottomLeft(reshareButton).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('story-other-controls')))
              .dy,
        ),
      );
    });

    testWidgets('hidden when can_reshare is false or the flag is off', (
      tester,
    ) async {
      await open(tester, canReshare: false);
      expect(reshareButton, findsNothing);
      await open(tester, enable: false);
      expect(reshareButton, findsNothing);
    });

    testWidgets(
      'tap → POST reshare (default public) → "Story reshared", refresh, hidden',
      (tester) async {
        final calls = await open(tester);
        await tester.tap(reshareButton);
        await tester.pump();
        await tester.pump();
        expect(calls.repo.reshares, [(1, null)]);
        expect(find.text('Story reshared'), findsOneWidget);
        expect(calls.reshared, [1]);
        expect(reshareButton, findsNothing);
      },
    );

    testWidgets('a public account omits visibility', (tester) async {
      final current = await currentUser(private: false);
      addTearDown(current.close);
      final calls = await open(tester, current: current);
      await tester.tap(reshareButton);
      await tester.pump();
      expect(calls.repo.reshares, [(1, null)]);
    });

    testWidgets('a private account reshares to followers', (tester) async {
      final current = await currentUser(private: true);
      addTearDown(current.close);
      final calls = await open(tester, current: current);
      await tester.tap(reshareButton);
      await tester.pump();
      expect(calls.repo.reshares, [(1, StoryAudience.followers)]);
    });

    final errors = <(String, StoryReshareError, bool)>[
      (
        'already reshared',
        reshareError(
          422,
          errors: {
            'story': ['dup'],
          },
        ),
        true,
      ),
      ('not allowed', reshareError(403), true),
      ('original expired', reshareError(404), true),
      (
        'story limit',
        reshareError(
          422,
          errors: {
            'stories': ['You can have at most 10 active stories.'],
          },
        ),
        false,
      ),
    ];
    for (final (name, error, hides) in errors) {
      testWidgets('$name: red toast${hides ? ', button hidden' : ''}', (
        tester,
      ) async {
        final calls = await open(tester);
        calls.repo.error = error;
        await tester.tap(reshareButton);
        await tester.pump();
        await tester.pump();
        expect(find.text(error.message), findsOneWidget);
        expect(find.text('Story reshared'), findsNothing);
        expect(calls.reshared, isEmpty);
        expect(reshareButton, hides ? findsNothing : findsOneWidget);
      });
    }

    testWidgets('an unexpected error shows the generic message', (
      tester,
    ) async {
      final calls = await open(tester);
      calls.repo.error = StateError('boom');
      await tester.tap(reshareButton);
      await tester.pump();
      await tester.pump();
      expect(find.text(StoryReshareError.fallback), findsOneWidget);
      expect(reshareButton, findsOneWidget);
    });
  });

  group('reshared story', () {
    const sara = {
      'id': 9,
      'name': 'Sara Adel',
      'username': 'sara',
      'avatar_url': null,
    };
    final header = find.byKey(const ValueKey('story-reshared-from'));

    testWidgets('header "12h • reshared from @user" opens their profile', (
      tester,
    ) async {
      final calls = await open(
        tester,
        canReshare: false,
        resharedFrom: {'story_id': 40, 'user': sara},
      );
      expect(find.text('12h • reshared from @sara'), findsOneWidget);
      await tester.tap(header);
      await tester.pump();
      expect(calls.opened, [9]);
    });

    testWidgets('original expired (story_id null): still shows the user', (
      tester,
    ) async {
      final calls = await open(
        tester,
        canReshare: false,
        resharedFrom: {'story_id': null, 'user': sara},
      );
      expect(find.text('12h • reshared from @sara'), findsOneWidget);
      await tester.tap(header);
      await tester.pump();
      expect(calls.opened, [9]);
    });

    testWidgets('no user: the plain time, no link', (tester) async {
      await open(
        tester,
        canReshare: false,
        resharedFrom: {'story_id': 40, 'user': null},
      );
      expect(find.text('12h'), findsOneWidget);
      expect(header, findsNothing);
    });

    testWidgets('flag off: the plain time', (tester) async {
      await open(
        tester,
        enable: false,
        resharedFrom: {'story_id': 40, 'user': sara},
      );
      expect(find.textContaining('reshared from'), findsNothing);
      expect(header, findsNothing);
    });

    testWidgets(
      '@names are plain white and not tappable; hidden mentions stay hidden',
      (tester) async {
        const bubble = StoryTextLayer(
          id: 't',
          text: 'Coffee with @omar',
          center: Offset(.5, .4),
        );
        await open(
          tester,
          canReshare: false,
          resharedFrom: {'story_id': 40, 'user': sara},
          elements: StoryElements.encode(
            [bubble],
            mentions: const [StoryMentionedUser(id: 5, username: 'nour')],
          ),
        );
        final bubbles = find.byKey(const ValueKey('story-text-bubble'));
        expect(bubbles, findsOneWidget);
        expect(find.textContaining('nour', findRichText: true), findsNothing);
        final text = tester.widget<RichText>(
          find.descendant(of: bubbles, matching: find.byType(RichText)),
        );
        final span = text.text as TextSpan;
        expect(span.toPlainText(), 'Coffee with @omar');
        expect(span.style!.color, Colors.white);
        span.visitChildren((child) {
          expect(child.style?.color, isNot(DarkColors.primaryColor));
          return true;
        });
        await tester.tap(bubbles);
        await tester.pump();
        expect(
          find.byKey(const ValueKey('story-mention-popover')),
          findsNothing,
        );
      },
    );
  });
}
