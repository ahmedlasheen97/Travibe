import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/stories/cubit/story_likes_cubit.dart';
import 'package:travibe/features/stories/cubit/story_viewer_cubit.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/screens/story_viewer_screen.dart';
import 'package:travibe/features/stories/widgets/story_like_button.dart';
import 'package:travibe/features/stories/widgets/story_glass.dart';
import 'package:travibe/features/stories/widgets/story_viewer_canvas.dart';
import 'fixtures.dart';
import 'story_owner_controls_test.dart' show OwnerRepo;
import 'story_publishing_test.dart' show StoryAdapter, repository, response;
import 'story_viewer_test.dart' show viewerGroup, viewerDetail;

StoryDetail reaction(
  int id, {
  bool liked = false,
  int count = 4,
  bool mine = false,
}) => StoryDetail.fromJson(
  viewerDetail(id)
    ..['is_mine'] = mine
    ..['is_liked'] = liked
    ..['likes_count'] = count,
);

class ReactionRepo extends StoriesRepo {
  int posts = 0, deletes = 0, reads = 0;
  CancelToken? token;
  Future<void> Function()? write;
  Future<StoryDetail> Function(int)? read;
  bool liked = false;
  @override
  Future<void> likeStory(int id, {CancelToken? cancelToken}) async {
    posts++;
    token = cancelToken;
    await write?.call();
    liked = true;
  }

  @override
  Future<void> unlikeStory(int id, {CancelToken? cancelToken}) async {
    deletes++;
    token = cancelToken;
    await write?.call();
    liked = false;
  }

  @override
  Future<StoryDetail> getStory(int id) async {
    reads++;
    return read == null
        ? reaction(id, liked: liked, count: liked ? 9 : 4)
        : read!(id);
  }
}

void main() {
  final session = PreferencesManager();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await session.init();
    await session.saveToken('story-like-test-session');
  });
  tearDown(() async => session.clear());

  for (final liked in [true, false]) {
    test(
      '${liked ? 'POST' : 'DELETE'} accepts empty success without JSON inference, uses bearer and no body',
      () async {
        final adapter = StoryAdapter()
          ..handler = (_) async => ResponseBody.fromString('', 204);
        final repo = repository(adapter);
        if (liked) {
          await repo.likeStory(12);
        } else {
          await repo.unlikeStory(12);
        }
        final request = adapter.requests.single;
        expect(request.path, 'stories/12/like');
        expect(request.method, liked ? 'POST' : 'DELETE');
        expect(request.data, isNull);
        expect(
          request.headers['Authorization'],
          'Bearer story-like-test-session',
        );
        expect(request.responseType, ResponseType.plain);
      },
    );
  }
  test(
    'mutation ignores unverified response body, then reads verified Story Detail',
    () async {
      final adapter = StoryAdapter()
        ..handler = (request) async => request.method == 'POST'
            ? response({'unverified_example': true})
            : response({
                'data': viewerDetail(1)
                  ..['is_mine'] = false
                  ..['is_liked'] = true
                  ..['likes_count'] = 17,
              });
      final cubit = StoryLikesCubit(repo: repository(adapter));
      expect(await cubit.toggle(reaction(1)), isNull);
      expect(cubit.state.values[1]!.isLiked, true);
      expect(cubit.state.values[1]!.count, 17);
      expect(adapter.requests.map((r) => r.path), [
        'stories/1/like',
        'stories/1',
      ]);
      await cubit.close();
    },
  );
  for (final code in [401, 403, 404, 422, 429]) {
    for (final liked in [false, true]) {
      test(
        '${liked ? 'unlike' : 'like'} HTTP $code preserves verified state',
        () async {
          final adapter = StoryAdapter()
            ..handler = (_) async =>
                response({'message': 'Denied'}, status: code);
          final cubit = StoryLikesCubit(repo: repository(adapter));
          cubit.accept(
            reaction(1, liked: liked),
            requestRevision: cubit.revision,
          );
          final error = await cubit.toggle(reaction(1));
          expect(error!.statusCode, code);
          expect(cubit.state.values[1]!.isLiked, liked);
          expect(cubit.state.values[1]!.count, 4);
          expect(cubit.state.values[1]!.pending, false);
          expect(adapter.requests, hasLength(1));
          await cubit.close();
        },
      );
    }
  }
  test('confirmed unlike uses returned detail count including zero', () async {
    final repo = ReactionRepo()..read = (id) async => reaction(id, count: 0);
    final cubit = StoryLikesCubit(repo: repo);
    cubit.accept(reaction(1, liked: true), requestRevision: cubit.revision);
    await cubit.toggle(reaction(1));
    expect(repo.deletes, 1);
    expect(cubit.state.values[1]!.isLiked, false);
    expect(cubit.state.values[1]!.count, 0);
    await cubit.close();
  });
  test(
    'duplicate taps wait for confirmation and never increment locally',
    () async {
      final pending = Completer<void>();
      final repo = ReactionRepo()..write = () => pending.future;
      final cubit = StoryLikesCubit(repo: repo);
      final first = cubit.toggle(reaction(1));
      await cubit.toggle(reaction(1));
      expect(repo.posts, 1);
      expect(cubit.state.values[1]!.isLiked, false);
      expect(cubit.state.values[1]!.count, 4);
      expect(cubit.state.values[1]!.pending, true);
      pending.complete();
      await first;
      expect(cubit.state.values[1]!.isLiked, true);
      expect(cubit.state.values[1]!.count, 9);
      await cubit.close();
    },
  );
  test(
    'late pre-mutation detail cannot overwrite confirmation or rollback',
    () async {
      final repo = ReactionRepo();
      final cubit = StoryLikesCubit(repo: repo);
      final oldRevision = cubit.revision;
      await cubit.toggle(reaction(1));
      cubit.accept(reaction(1), requestRevision: oldRevision);
      expect(cubit.state.values[1]!.isLiked, true);
      cubit.accept(
        reaction(1, liked: true, count: 12),
        requestRevision: cubit.revision,
      );
      expect(cubit.state.values[1]!.count, 12);
      await cubit.close();
    },
  );
  for (final transport in [false, true]) {
    test(
      '${transport ? 'transport uncertainty' : 'confirmation GET failure'} recovers with GET and no duplicate mutation',
      () async {
        final repo = ReactionRepo();
        if (transport) {
          repo.write = () async => throw ApiError(message: 'Timeout');
        } else {
          repo.read = (_) async => throw ApiError(message: 'Offline');
        }
        final cubit = StoryLikesCubit(repo: repo);
        expect(await cubit.toggle(reaction(1)), isA<ApiError>());
        expect(cubit.state.refreshRequired, contains(1));
        expect(cubit.state.values[1]!.count, 4);
        repo.write = null;
        repo.read = (id) async => reaction(id, liked: true, count: 15);
        await cubit.toggle(reaction(1));
        expect(repo.posts, 1);
        expect(repo.deletes, 0);
        expect(cubit.state.refreshRequired, isEmpty);
        expect(cubit.state.values[1]!.count, 15);
        await cubit.close();
      },
    );
  }
  for (final dispose in [false, true]) {
    test(
      '${dispose ? 'disposal' : 'logout/account change'} cancels mutation and discards late completion',
      () async {
        final pending = Completer<void>();
        final repo = ReactionRepo()..write = () => pending.future;
        final cubit = StoryLikesCubit(repo: repo);
        final operation = cubit.toggle(reaction(1));
        if (dispose) {
          await cubit.close();
        } else {
          await session.clear();
          await session.saveToken('next-account');
        }
        expect(repo.token!.isCancelled, true);
        pending.complete();
        await operation;
        expect(repo.reads, 0);
        if (!dispose) {
          expect(cubit.state.values, isEmpty);
          await cubit.close();
        }
      },
    );
  }
  test(
    'story switching does not lose or cross-apply in-flight likes',
    () async {
      final pending = Completer<void>();
      final repo = ReactionRepo()..write = () => pending.future;
      final likes = StoryLikesCubit(repo: repo);
      final viewer = StoryViewerCubit(
        groups: [
          viewerGroup(7, [1, 2]),
        ],
        initialAuthorId: 7,
        repo: repo,
        likes: likes,
      );
      await viewer.start();
      final operation = likes.toggle(viewer.state.detail!);
      await viewer.next();
      expect(viewer.state.detail!.id, 2);
      pending.complete();
      await operation;
      expect(likes.state.values[1]!.isLiked, true);
      expect(likes.state.values[2]!.isLiked, false);
      await viewer.previous();
      expect(likes.state.values[1]!.isLiked, true);
      await viewer.close();
      await likes.close();
    },
  );
  test(
    'owner cannot mutate and malformed negative counts are rejected',
    () async {
      final repo = ReactionRepo();
      final cubit = StoryLikesCubit(repo: repo);
      await cubit.toggle(reaction(1, mine: true));
      expect(repo.posts, 0);
      expect(() => reaction(1, count: -1), throwsFormatException);
      await cubit.close();
    },
  );
  test('known expired story is rejected before dispatch', () async {
    final repo = ReactionRepo();
    final likes = StoryLikesCubit(repo: repo);
    final expired = StoryDetail.fromJson(
      viewerDetail(1)
        ..['is_mine'] = false
        ..['expires_at'] = DateTime.now()
            .subtract(const Duration(seconds: 1))
            .toIso8601String(),
    );
    expect((await likes.toggle(expired))!.statusCode, 404);
    expect(repo.posts, 0);
    await likes.close();
  });
  test(
    'fresh detail after uncertainty reconciles without repeating the write',
    () async {
      final repo = ReactionRepo()
        ..write = () async => throw ApiError(message: 'Timeout');
      final likes = StoryLikesCubit(repo: repo);
      await likes.toggle(reaction(1));
      expect(likes.state.refreshRequired, contains(1));
      likes.accept(
        reaction(1, liked: true, count: 13),
        requestRevision: likes.revision,
      );
      expect(likes.state.refreshRequired, isEmpty);
      expect(likes.state.values[1]!.count, 13);
      expect(repo.posts, 1);
      await likes.close();
    },
  );
  test('repository honors caller cancellation before dispatch', () async {
    final adapter = StoryAdapter();
    final token = CancelToken()..cancel();
    await expectLater(
      repository(adapter).likeStory(1, cancelToken: token),
      throwsA(isA<ApiError>()),
    );
    expect(adapter.requests, isEmpty);
  });
  testWidgets(
    'glass heart is untinted, accessible and follows authoritative state',
    (tester) async {
      final repo = ReactionRepo();
      final cubit = StoryLikesCubit(repo: repo);
      final detail = reaction(1);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StoryLikeButton(detail: detail, likes: cubit),
          ),
        ),
      );
      final button = find.byKey(const ValueKey('story-like'));
      expect(tester.getSize(button), const Size(48, 48));
      expect(find.byType(StoryGlass), findsOneWidget);
      expect(find.byTooltip('Like Story'), findsOneWidget);
      expect(
        (tester.widget<SvgPicture>(find.byType(SvgPicture)).bytesLoader
                as SvgAssetLoader)
            .assetName,
        endsWith('heart2.svg'),
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Unlike Story'), findsOneWidget);
      final icon = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(icon.colorFilter, isNull);
      expect(
        (icon.bytesLoader as SvgAssetLoader).assetName,
        endsWith('heart.svg'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await cubit.close();
    },
  );
  for (final mine in [false, true]) {
    testWidgets(
      '${mine ? 'owner hides' : 'other author shows'} like control; tapping it does not navigate',
      (tester) async {
        final repo = OwnerRepo()
          ..detailHandler = (id) async => reaction(id, mine: mine);
        final likes = StoryLikesCubit(repo: ReactionRepo());
        final photo = MemoryImage(photoBytes());
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StoryViewerScreen(
                        groups: [
                          viewerGroup(7, [1, 2]),
                        ],
                        initialAuthorId: 7,
                        currentUserId: mine ? 7 : 8,
                        repo: repo,
                        likes: likes,
                        imageProvider: (_) => photo,
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => precacheImage(photo, tester.element(find.text('Open'))),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final button = find.byKey(const ValueKey('story-like'));
        expect(button, mine ? findsNothing : findsOneWidget);
        if (!mine) {
          final canvasKey = tester
              .widget<StoryViewerCanvas>(find.byType(StoryViewerCanvas))
              .key;
          await tester.tap(button);
          await tester.pump();
          expect(find.byKey(const ValueKey('story-like')), findsOneWidget);
          expect(find.byType(StoryViewerScreen), findsOneWidget);
          expect(
            tester
                .widget<StoryViewerCanvas>(find.byType(StoryViewerCanvas))
                .key,
            canvasKey,
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await likes.close();
      },
    );
  }
}
